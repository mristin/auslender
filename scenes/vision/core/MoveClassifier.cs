using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

using Microsoft.ML.OnnxRuntime;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>A trained model which gives the probability of each move class from the features.</summary>
    public interface IMoveModel : IDisposable
    {
        int ClassCount { get; }

        void Predict(ReadOnlySpan<float> features, Span<float> probabilities);
    }

    /// <summary>An XGBoost model (see <see cref="GradientBoostedTrees"/>).</summary>
    public sealed class XgboostMoveModel : IMoveModel
    {
        private readonly GradientBoostedTrees _trees;

        public XgboostMoveModel(string json)
        {
            _trees = GradientBoostedTrees.FromJson(json);
        }

        public int ClassCount => _trees.ClassCount;

        public void Predict(ReadOnlySpan<float> features, Span<float> probabilities) =>
            _trees.Predict(features, probabilities);

        public void Dispose()
        {
        }
    }

    /// <summary>
    /// A neural network exported to ONNX with the inputs "seq" ([1, steps,
    /// 26]: the sequence of the features) and "score" ([1, 2]: the wrist
    /// confidences), and the output "probs" ([1, classes]).
    /// </summary>
    public sealed class OnnxMoveModel : IMoveModel
    {
        private readonly InferenceSession _session;
        private readonly RunOptions _runOptions = new();
        private readonly float[] _seq;
        private readonly float[] _score = new float[2];
        private readonly OrtValue _seqValue;
        private readonly OrtValue _scoreValue;
        private readonly string[] _inputNames = { "seq", "score" };
        private readonly string[] _outputNames = { "probs" };

        public int ClassCount { get; }

        public OnnxMoveModel(byte[] model, int steps, int classes)
        {
            OnnxRuntimePrivacy.DisableTelemetry();
            using var options = new SessionOptions
            {
                GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR,
                IntraOpNumThreads = 1,
                InterOpNumThreads = 1,
            };
            _session = new InferenceSession(model, options);
            ClassCount = classes;
            _seq = new float[steps * MoveFeatures.Points.Length * 2];
            _seqValue = OrtValue.CreateTensorValueFromMemory(_seq, new long[] { 1, steps, MoveFeatures.Points.Length * 2 });
            _scoreValue = OrtValue.CreateTensorValueFromMemory(_score, new long[] { 1, 2 });
        }

        public void Predict(ReadOnlySpan<float> features, Span<float> probabilities)
        {
            features.Slice(0, _seq.Length).CopyTo(_seq);
            features.Slice(_seq.Length, 2).CopyTo(_score);
            using var outputs = _session.Run(_runOptions, _inputNames, new[] { _seqValue, _scoreValue }, _outputNames);
            outputs[0].GetTensorDataAsSpan<float>().Slice(0, ClassCount).CopyTo(probabilities);
        }

        public void Dispose()
        {
            _seqValue.Dispose();
            _scoreValue.Dispose();
            _runOptions.Dispose();
            _session.Dispose();
        }
    }

    /// <summary>A move which the classifier found.</summary>
    public readonly struct ClassifiedMove
    {
        public readonly double Time;

        /// <summary>The class, e.g., "hook_left", "duck" or "slip_right".</summary>
        public readonly string Class;

        public readonly float Probability;

        public ClassifiedMove(double time, string name, float probability)
        {
            Time = time;
            Class = name;
            Probability = probability;
        }

        public override string ToString() => $"{Class} {Probability:F2} at {Time:F2}";
    }

    /// <summary>
    /// Find the moves of the player (the punches by type and side, the kicks (a
    /// knee raised high: the camera need not see the whole leg),
    /// the ducks, the jumps and the slips) and whether she covers her head,
    /// from her poses on every frame, with a model trained on labelled
    /// recordings (dev/moves/ml).
    /// </summary>
    /// <remarks>
    /// <para>
    /// The model gives the probability of each class for the last few poses
    /// (see <see cref="MoveFeatures"/>). The classes form groups: the strikes
    /// of one side (the straight, the hook, the uppercut and the kick of the
    /// left, say) are one group, and every other move is a group of its own.
    /// A group triggers when the probability of one of its classes rises over
    /// <see cref="OnThreshold"/>.
    /// </para>
    /// <para>
    /// A strike then decides within <see cref="DecisionTime"/> (or as soon as
    /// all its classes fell under <see cref="OffThreshold"/>) on the class of
    /// the most probability over the movement: a hook starts like a straight,
    /// so the straight would else fire first. A duck, a jump or a slip fires
    /// at once, since the dodges must be in time. A group triggers again only
    /// after all its classes fell under <see cref="OffThreshold"/> and
    /// <see cref="Refractory"/> passed.
    /// </para>
    /// <para>
    /// The cover is a state, not a move: the player covers while its
    /// probability stays over the thresholds (with the same hysteresis).
    /// </para>
    /// <para>
    /// The model comes with a description (JSON): its classes, the offsets of
    /// the poses, the format ("xgboost" or "onnx") and its file.
    /// </para>
    /// </remarks>
    public sealed class MoveClassifier : IDisposable
    {
        public const string None = "none";
        public const string Cover = "cover";

        private static readonly string[] _strikes = { "straight", "hook", "uppercut", "kick" };

        public float OnThreshold = 0.5f;
        public float OffThreshold = 0.3f;
        public double Refractory = 0.3;

        /// <summary>A strike decides on its class at the latest this long after it triggered, in seconds.</summary>
        public double DecisionTime = 0.2;

        public readonly string[] Classes;
        public readonly MoveFeatures Features;

        /// <summary>The probabilities of the classes of the newest pose.</summary>
        public readonly float[] Probabilities;

        /// <summary>Whether the player covers her head now.</summary>
        public bool Covering { get; private set; }

        private enum Phase
        {
            Idle,
            Deciding,
            Waiting,
        }

        private sealed class Group
        {
            public int[] Members = Array.Empty<int>();
            public bool Decides;
            public Phase Phase;
            public double TriggeredAt;
            public double FiredAt = double.NegativeInfinity;
            public float[] Sums = Array.Empty<float>();
            public float[] Peaks = Array.Empty<float>();
        }

        private readonly IMoveModel _model;
        private readonly float[] _features;
        private readonly Group[] _groups;
        private readonly int _cover;
        private bool _covering;

        public MoveClassifier(string[] classes, double[] offsets, IMoveModel model)
        {
            if (model.ClassCount != classes.Length)
            {
                throw new ArgumentException(
                    $"The model gives {model.ClassCount} classes, but the description lists {classes.Length}.");
            }

            Classes = classes;
            Features = new MoveFeatures(offsets);
            _model = model;
            _features = new float[Features.Count];
            Probabilities = new float[classes.Length];
            _cover = Array.IndexOf(classes, Cover);

            var groups = new Dictionary<string, List<int>>();
            for (int c = 0; c < classes.Length; c++)
            {
                string name = classes[c];
                if (name == None || name == Cover)
                {
                    continue;
                }

                string key = name;
                foreach (string strike in _strikes)
                {
                    foreach (string side in new[] { "left", "right" })
                    {
                        if (name == $"{strike}_{side}")
                        {
                            key = $"strike_{side}";
                        }
                    }
                }

                if (!groups.TryGetValue(key, out var members))
                {
                    members = new List<int>();
                    groups[key] = members;
                }

                members.Add(c);
            }

            _groups = groups.Values.Select(members => new Group
            {
                Members = members.ToArray(),
                Decides = members.Count > 1,
                Sums = new float[members.Count],
                Peaks = new float[members.Count],
            }).ToArray();
        }

        /// <summary>
        /// Load the classifier from its description (JSON); <paramref name="readFile"/>
        /// reads the model file which the description names, next to it.
        /// </summary>
        public static MoveClassifier FromDescription(string json, Func<string, byte[]> readFile)
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            var classes = root.GetProperty("classes").EnumerateArray().Select(c => c.GetString()!).ToArray();
            var offsets = root.GetProperty("offsets").EnumerateArray().Select(o => o.GetDouble()).ToArray();
            string format = root.GetProperty("format").GetString()!;
            byte[] model = readFile(root.GetProperty("model").GetString()!);
            IMoveModel loaded = format switch
            {
                "xgboost" => new XgboostMoveModel(System.Text.Encoding.UTF8.GetString(model)),
                "onnx" => new OnnxMoveModel(model, offsets.Length, classes.Length),
                _ => throw new InvalidOperationException($"Unknown model format: {format}"),
            };
            return new MoveClassifier(classes, offsets, loaded);
        }

        /// <summary>Forget the poses and the moves, e.g., when the player is lost.</summary>
        public void Reset()
        {
            Features.Reset();
            foreach (var group in _groups)
            {
                group.Phase = Phase.Idle;
                group.FiredAt = double.NegativeInfinity;
            }

            Array.Clear(Probabilities);
            _covering = false;
            Covering = false;
        }

        /// <summary>
        /// Observe the pose (17 COCO key points as x, y and score, in pixels) at
        /// the time <paramref name="t"/>, and add the moves which fire now.
        /// </summary>
        public void Observe(double t, float[] pose, List<ClassifiedMove> fired)
        {
            Features.Observe(t, pose);
            if (!Features.Compute(_features))
            {
                return;
            }

            _model.Predict(_features, Probabilities);
            Decide(t, Probabilities, fired);
        }

        /// <summary>Turn the probabilities at the time into moves and the cover (see the remarks).</summary>
        public void Decide(double t, float[] probabilities, List<ClassifiedMove> fired)
        {
            foreach (var group in _groups)
            {
                float highest = 0f;
                foreach (int c in group.Members)
                {
                    highest = Math.Max(highest, probabilities[c]);
                }

                bool quiet = highest < OffThreshold;
                switch (group.Phase)
                {
                    case Phase.Idle:
                        if (highest >= OnThreshold && t - group.FiredAt >= Refractory)
                        {
                            group.Phase = Phase.Deciding;
                            group.TriggeredAt = t;
                            Array.Clear(group.Sums);
                            Array.Clear(group.Peaks);
                            Accumulate(group, probabilities);
                            if (!group.Decides)
                            {
                                Fire(group, t, fired);
                            }
                        }

                        break;
                    case Phase.Deciding:
                        if (!quiet)
                        {
                            Accumulate(group, probabilities);
                        }

                        if (quiet || t - group.TriggeredAt >= DecisionTime)
                        {
                            Fire(group, t, fired);
                        }

                        break;
                    case Phase.Waiting:
                        break;
                }

                if (group.Phase == Phase.Waiting && quiet)
                {
                    group.Phase = Phase.Idle;
                }
            }

            if (_cover >= 0)
            {
                float p = probabilities[_cover];
                _covering = _covering ? p >= OffThreshold : p >= OnThreshold;
            }

            Covering = _covering;
        }

        private static void Accumulate(Group group, float[] probabilities)
        {
            for (int i = 0; i < group.Members.Length; i++)
            {
                float p = probabilities[group.Members[i]];
                group.Sums[i] += p;
                group.Peaks[i] = Math.Max(group.Peaks[i], p);
            }
        }

        private void Fire(Group group, double t, List<ClassifiedMove> fired)
        {
            int best = 0;
            for (int i = 1; i < group.Members.Length; i++)
            {
                if (group.Sums[i] > group.Sums[best])
                {
                    best = i;
                }
            }

            fired.Add(new ClassifiedMove(t, Classes[group.Members[best]], group.Peaks[best]));
            group.FiredAt = t;
            group.Phase = Phase.Waiting;
        }

        public void Dispose() => _model.Dispose();
    }
}
