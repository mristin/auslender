using System;
using System.Diagnostics;
using System.Linq;

using Microsoft.ML.OnnxRuntime;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Follow the player's body pose on every camera frame with RTMPose-t, a
    /// top-down pose estimator: it only looks at the box around the player.
    /// </summary>
    /// <remarks>
    /// <para>
    /// RTMO finds all the persons in the whole picture, but takes about 70 ms
    /// on a modest laptop (100 ms next to the face tracker), so it ran only a
    /// few times a second: too slow for the punches. RTMPose-t takes about
    /// 13 ms for one person, so it keeps up with the camera.
    /// </para>
    /// <para>
    /// It needs a box to look into: we take it from the pose of the previous
    /// frame (its confident key points, padded by 1.25 and widened to the
    /// aspect of the input), and from a pose of RTMO to start with or when the
    /// player was lost (<see cref="Seed"/>). This is exactly how the poses were
    /// made on which the move classifier was trained (dev/moves/ml), so keep
    /// the two the same.
    /// </para>
    /// <para>The instance is not thread-safe; use it from a single thread only.</para>
    /// </remarks>
    public sealed class RtmPoseTracker : IDisposable
    {
        public const int InputWidth = 192;
        public const int InputHeight = 256;

        /// <summary>The key points from which a pose gives the box of the next frame.</summary>
        public float TrackThreshold = 0.4f;

        /// <summary>The key points from which a pose of RTMO gives the first box.</summary>
        public float SeedThreshold = 0.3f;

        /// <summary>A box needs at least this many confident key points.</summary>
        public int MinKeypoints = 5;

        private static readonly float[] _mean = { 123.675f, 116.28f, 103.53f };
        private static readonly float[] _std = { 58.395f, 57.12f, 57.375f };

        private readonly InferenceSession _session;
        private readonly RunOptions _runOptions = new();
        private readonly string[] _inputNames;
        private readonly string[] _outputNames = { "simcc_x", "simcc_y" };
        private readonly float[] _input = new float[3 * InputWidth * InputHeight];
        private readonly OrtValue _inputValue;

        // The box: the center and the size, in frame pixels; NaN while lost.
        private float _cx = float.NaN;
        private float _cy;
        private float _w;
        private float _h;

        public RtmPoseTracker(byte[] model, int threads = 1)
        {
            OnnxRuntimePrivacy.DisableTelemetry();

            using var options = new SessionOptions
            {
                GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR,
                ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
                IntraOpNumThreads = threads,
                InterOpNumThreads = 1,
            };
            options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");

            _session = new InferenceSession(model, options);
            foreach (string name in _outputNames)
            {
                if (!_session.OutputMetadata.ContainsKey(name))
                {
                    _session.Dispose();
                    throw new InvalidOperationException(
                        $"Expected RTMPose to have the output {name}, but got: " +
                        string.Join(", ", _session.OutputMetadata.Keys));
                }
            }

            _inputNames = new[] { _session.InputMetadata.Keys.First() };
            _inputValue = OrtValue.CreateTensorValueFromMemory(_input, new long[] { 1, 3, InputHeight, InputWidth });
        }

        /// <summary>Whether we follow the player now (else we need a <see cref="Seed"/>).</summary>
        public bool Tracking => !float.IsNaN(_cx);

        /// <summary>Start following the person of the pose (e.g., found by RTMO); false if it is too vague.</summary>
        public bool Seed(Pose pose) => SetBox(pose.Keypoints, SeedThreshold);

        /// <summary>Forget the box.</summary>
        public void Lose() => _cx = float.NaN;

        /// <summary>
        /// Estimate the pose in the box of the player, and follow it to the next
        /// frame; null if we do not follow anybody, or lost them now.
        /// </summary>
        public Pose? Track(Frame frame)
        {
            if (!Tracking)
            {
                return null;
            }

            float cx = _cx;
            float cy = _cy;
            float w = _w;
            float h = _h;
            Preprocess(frame, cx, cy, w, h, _input);

            using var outputs = _session.Run(_runOptions, _inputNames, new[] { _inputValue }, _outputNames);
            var simccX = outputs[0].GetTensorDataAsSpan<float>();
            var simccY = outputs[1].GetTensorDataAsSpan<float>();
            int binsX = InputWidth * 2;
            int binsY = InputHeight * 2;

            var keypoints = new Keypoint[Pose.KeypointCount];
            float x0 = float.MaxValue, y0 = float.MaxValue, x1 = float.MinValue, y1 = float.MinValue;
            float scoreSum = 0f;
            for (int k = 0; k < Pose.KeypointCount; k++)
            {
                var rowX = simccX.Slice(k * binsX, binsX);
                var rowY = simccY.Slice(k * binsY, binsY);
                int bx = ArgMax(rowX);
                int by = ArgMax(rowY);
                float x = cx - w / 2f + bx / 2f * w / InputWidth;
                float y = cy - h / 2f + by / 2f * h / InputHeight;
                float score = Math.Min(rowX[bx], rowY[by]);
                keypoints[k] = new Keypoint(x, y, score);
                scoreSum += score;
                x0 = Math.Min(x0, x);
                y0 = Math.Min(y0, y);
                x1 = Math.Max(x1, x);
                y1 = Math.Max(y1, y);
            }

            if (!SetBox(keypoints, TrackThreshold))
            {
                return null;
            }

            return new Pose(keypoints, new BoundingBox(x0, y0, x1, y1), scoreSum / Pose.KeypointCount);
        }

        private static int ArgMax(ReadOnlySpan<float> values)
        {
            int best = 0;
            for (int i = 1; i < values.Length; i++)
            {
                if (values[i] > values[best])
                {
                    best = i;
                }
            }

            return best;
        }

        /// <summary>Set the box from the confident key points; lose it if there are too few.</summary>
        private bool SetBox(Keypoint[] keypoints, float threshold)
        {
            float x0 = float.MaxValue, y0 = float.MaxValue, x1 = float.MinValue, y1 = float.MinValue;
            int count = 0;
            foreach (var point in keypoints)
            {
                if (point.Score < threshold)
                {
                    continue;
                }

                count++;
                x0 = Math.Min(x0, point.X);
                y0 = Math.Min(y0, point.Y);
                x1 = Math.Max(x1, point.X);
                y1 = Math.Max(y1, point.Y);
            }

            if (count < MinKeypoints)
            {
                _cx = float.NaN;
                return false;
            }

            float w = (x1 - x0) * 1.25f;
            float h = (y1 - y0) * 1.25f;
            if (w * InputHeight > h * InputWidth)
            {
                h = w * InputHeight / InputWidth;
            }
            else
            {
                w = h * InputWidth / InputHeight;
            }

            _cx = (x0 + x1) / 2f;
            _cy = (y0 + y1) / 2f;
            _w = w;
            _h = h;
            return true;
        }

        /// <summary>
        /// Cut the box out of the frame into the planar RGB input, normalized;
        /// nearest pixels, black outside the frame.
        /// </summary>
        public static void Preprocess(Frame frame, float cx, float cy, float w, float h, float[] target)
        {
            int plane = InputWidth * InputHeight;
            byte[] rgb = frame.Rgb;
            for (int y = 0; y < InputHeight; y++)
            {
                int iy = (int)(cy - h / 2f + (y + 0.5f) * h / InputHeight);
                bool insideY = iy >= 0 && iy < frame.Height;
                for (int x = 0; x < InputWidth; x++)
                {
                    int ix = (int)(cx - w / 2f + (x + 0.5f) * w / InputWidth);
                    int index = y * InputWidth + x;
                    if (!insideY || ix < 0 || ix >= frame.Width)
                    {
                        for (int c = 0; c < 3; c++)
                        {
                            target[c * plane + index] = (0f - _mean[c]) / _std[c];
                        }

                        continue;
                    }

                    int pixel = (iy * frame.Width + ix) * 3;
                    for (int c = 0; c < 3; c++)
                    {
                        target[c * plane + index] = (rgb[pixel + c] - _mean[c]) / _std[c];
                    }
                }
            }
        }

        public void Dispose()
        {
            _inputValue.Dispose();
            _runOptions.Dispose();
            _session.Dispose();
        }
    }
}
