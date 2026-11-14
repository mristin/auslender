using System;
using System.Collections.Generic;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Turn the stream of body poses into the input of the move classifier:
    /// the last few poses, scale invariant, as dev/moves/ml trains on them.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The poses are resampled at fixed times back from now
    /// (<see cref="Offsets"/>), by linear interpolation, so the frame rate of
    /// the camera does not matter. Each is expressed relative to the middle of
    /// the shoulders now, in units of the body scale: the median length of
    /// the torso (from the middle of the shoulders to the middle of the hips)
    /// over the last <see cref="ScaleHistory"/> seconds. So a child far away
    /// and an adult close by give the same features for the same move.
    /// </para>
    /// <para>
    /// The features are the sequence (oldest first; per time, the x and y of
    /// <see cref="Points"/>), followed by the lowest confidence of each wrist
    /// over the window. This must stay exactly as in the training (the parity
    /// test checks it against the Python of the training).
    /// </para>
    /// </remarks>
    public sealed class MoveFeatures
    {
        /// <summary>
        /// The COCO key points we use: nose, shoulders, elbows, wrists, hips, knees.
        /// </summary>
        /// <remarks>
        /// Not the ankles: whether the camera sees the feet depends on the height of
        /// the player and the place of the camera (it saw a child's feet, but not an
        /// adult's), and the classifier trained with them made five times more false
        /// moves on the child.
        /// </remarks>
        public static readonly int[] Points = { 0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 };

        /// <summary>How long back the median torso length looks, in seconds.</summary>
        public const double ScaleHistory = 2.0;

        /// <summary>The times back from now at which the poses are taken, in seconds, newest first.</summary>
        public readonly double[] Offsets;

        /// <summary>The number of features: the sequence and the two wrist confidences.</summary>
        public int Count => Offsets.Length * Points.Length * 2 + 2;

        /// <summary>The number of time steps of the sequence.</summary>
        public int Steps => Offsets.Length;

        private readonly List<(double T, float[] Pose)> _history = new();
        private readonly List<float> _lengths = new();

        /// <param name="offsets">The times back from now, newest first, e.g., 0, 0.1, 0.2, 0.3.</param>
        public MoveFeatures(double[] offsets)
        {
            if (offsets.Length == 0 || offsets[0] != 0.0)
            {
                throw new ArgumentException("The offsets must start at 0 (now).", nameof(offsets));
            }

            Offsets = (double[])offsets.Clone();
        }

        /// <summary>Forget the poses, e.g., when the player is lost.</summary>
        public void Reset() => _history.Clear();

        /// <summary>
        /// Observe the pose (17 COCO key points as x, y, score in pixels) at the
        /// time <paramref name="t"/>, in seconds, after all the earlier ones.
        /// </summary>
        public void Observe(double t, float[] pose)
        {
            if (pose.Length < 51)
            {
                throw new ArgumentException($"Expected 17 key points (51 numbers), but got {pose.Length}.");
            }

            if (_history.Count > 0 && t <= _history[^1].T)
            {
                return;
            }

            _history.Add((t, (float[])pose.Clone()));
            double keep = Math.Max(ScaleHistory, Offsets[^1]) + 0.5;
            int drop = 0;
            while (drop < _history.Count - 2 && _history[drop + 1].T < t - keep)
            {
                drop++;
            }

            _history.RemoveRange(0, drop);
        }

        /// <summary>Whether there are poses to compute the features from.</summary>
        public bool Ready => _history.Count > 0;

        /// <summary>Compute the features of the newest pose into <paramref name="features"/> (at least <see cref="Count"/>).</summary>
        public bool Compute(Span<float> features)
        {
            if (_history.Count == 0)
            {
                return false;
            }

            if (features.Length < Count)
            {
                throw new ArgumentException($"Expected room for {Count} features, but got {features.Length}.");
            }

            var (now, pose) = _history[^1];
            float scale = BodyScale(now);
            if (!(scale > 0f))
            {
                return false;
            }

            float shoulderX = (pose[5 * 3] + pose[6 * 3]) / 2f;
            float shoulderY = (pose[5 * 3 + 1] + pose[6 * 3 + 1]) / 2f;

            float wristLeft = float.PositiveInfinity;
            float wristRight = float.PositiveInfinity;
            Span<float> sample = stackalloc float[51];
            int width = Points.Length * 2;
            for (int step = 0; step < Offsets.Length; step++)
            {
                Interpolate(now - Offsets[step], sample);

                // NOTE (mristin):
                // Oldest first: the newest pose (offset 0) is the last time step.
                int row = (Offsets.Length - 1 - step) * width;
                for (int i = 0; i < Points.Length; i++)
                {
                    int p = Points[i] * 3;
                    features[row + 2 * i] = (sample[p] - shoulderX) / scale;
                    features[row + 2 * i + 1] = (sample[p + 1] - shoulderY) / scale;
                }

                wristLeft = Math.Min(wristLeft, sample[9 * 3 + 2]);
                wristRight = Math.Min(wristRight, sample[10 * 3 + 2]);
            }

            features[Offsets.Length * width] = wristLeft;
            features[Offsets.Length * width + 1] = wristRight;
            return true;
        }

        /// <summary>The median torso length of the poses within <see cref="ScaleHistory"/> before <paramref name="now"/>.</summary>
        private float BodyScale(double now)
        {
            _lengths.Clear();
            foreach (var (t, pose) in _history)
            {
                if (t < now - ScaleHistory)
                {
                    continue;
                }

                float dx = (pose[5 * 3] + pose[6 * 3]) / 2f - (pose[11 * 3] + pose[12 * 3]) / 2f;
                float dy = (pose[5 * 3 + 1] + pose[6 * 3 + 1]) / 2f - (pose[11 * 3 + 1] + pose[12 * 3 + 1]) / 2f;
                _lengths.Add(MathF.Sqrt(dx * dx + dy * dy));
            }

            _lengths.Sort();
            int n = _lengths.Count;
            return n % 2 == 1 ? _lengths[n / 2] : (_lengths[n / 2 - 1] + _lengths[n / 2]) / 2f;
        }

        /// <summary>The pose at the time, linearly interpolated, clamped to the history.</summary>
        private void Interpolate(double at, Span<float> result)
        {
            int n = _history.Count;
            if (n == 1 || at <= _history[0].T)
            {
                _history[0].Pose.AsSpan(0, 51).CopyTo(result);
                return;
            }

            if (at >= _history[n - 1].T)
            {
                _history[n - 1].Pose.AsSpan(0, 51).CopyTo(result);
                return;
            }

            int j = n - 2;
            while (j > 0 && _history[j].T > at)
            {
                j--;
            }

            var (t0, a) = _history[j];
            var (t1, b) = _history[j + 1];
            float w = (float)Math.Clamp((at - t0) / Math.Max(t1 - t0, 1e-6), 0.0, 1.0);
            for (int i = 0; i < 51; i++)
            {
                result[i] = a[i] * (1f - w) + b[i] * w;
            }
        }
    }
}
