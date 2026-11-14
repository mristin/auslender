using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Evaluate a multi-class XGBoost model (objective <c>multi:softprob</c>),
    /// as XGBoost saves it as JSON (<c>booster.save_model("model.json")</c>),
    /// without XGBoost itself.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Each tree adds its leaf to the margin of its class (the tree info); a
    /// node goes left if the feature is less than its split condition, and to
    /// its default side if the feature is missing (NaN). The probabilities are
    /// the softmax of the margins, which start at the base scores. On the
    /// trained models, this agrees with XGBoost's <c>predict_proba</c> to
    /// about 1e-7.
    /// </para>
    /// <para>
    /// The trees are flattened into arrays, so a prediction allocates nothing.
    /// </para>
    /// </remarks>
    public sealed class GradientBoostedTrees
    {
        public readonly int ClassCount;
        public readonly int FeatureCount;

        private readonly float[] _baseScores;

        // NOTE (mristin):
        // All the nodes of all the trees, one after the other; the children
        // are indices into these arrays, -1 for a leaf.
        private readonly int[] _left;
        private readonly int[] _right;
        private readonly int[] _feature;
        private readonly float[] _value;
        private readonly bool[] _defaultLeft;

        private readonly int[] _roots;
        private readonly int[] _treeClass;

        private GradientBoostedTrees(
            int classCount, int featureCount, float[] baseScores,
            List<int> left, List<int> right, List<int> feature, List<float> value, List<bool> defaultLeft,
            List<int> roots, List<int> treeClass)
        {
            ClassCount = classCount;
            FeatureCount = featureCount;
            _baseScores = baseScores;
            _left = left.ToArray();
            _right = right.ToArray();
            _feature = feature.ToArray();
            _value = value.ToArray();
            _defaultLeft = defaultLeft.ToArray();
            _roots = roots.ToArray();
            _treeClass = treeClass.ToArray();
        }

        /// <summary>Load a model from the JSON which XGBoost saves.</summary>
        public static GradientBoostedTrees FromJson(string json)
        {
            using var document = JsonDocument.Parse(json);
            var learner = document.RootElement.GetProperty("learner");
            var parameters = learner.GetProperty("learner_model_param");
            int classes = int.Parse(parameters.GetProperty("num_class").GetString()!, CultureInfo.InvariantCulture);
            int features = int.Parse(parameters.GetProperty("num_feature").GetString()!, CultureInfo.InvariantCulture);
            if (classes < 2)
            {
                throw new InvalidOperationException($"Expected a multi-class model, but got {classes} class(es).");
            }

            var baseScores = ParseBaseScores(parameters.GetProperty("base_score").GetString()!, classes);

            var model = learner.GetProperty("gradient_booster").GetProperty("model");
            var left = new List<int>();
            var right = new List<int>();
            var feature = new List<int>();
            var value = new List<float>();
            var defaultLeft = new List<bool>();
            var roots = new List<int>();
            var treeClass = new List<int>();

            foreach (var info in model.GetProperty("tree_info").EnumerateArray())
            {
                treeClass.Add(info.GetInt32());
            }

            foreach (var tree in model.GetProperty("trees").EnumerateArray())
            {
                int offset = left.Count;
                roots.Add(offset);
                var lefts = tree.GetProperty("left_children");
                var rights = tree.GetProperty("right_children");
                var indices = tree.GetProperty("split_indices");
                var conditions = tree.GetProperty("split_conditions");
                var defaults = tree.GetProperty("default_left");
                int count = lefts.GetArrayLength();
                for (int i = 0; i < count; i++)
                {
                    int l = lefts[i].GetInt32();
                    int r = rights[i].GetInt32();
                    left.Add(l < 0 ? -1 : offset + l);
                    right.Add(r < 0 ? -1 : offset + r);
                    feature.Add(indices[i].GetInt32());
                    value.Add(conditions[i].GetSingle());
                    defaultLeft.Add(defaults[i].GetInt32() != 0);
                }
            }

            if (roots.Count != treeClass.Count)
            {
                throw new InvalidOperationException(
                    $"Expected as many tree infos as trees, but got {treeClass.Count} and {roots.Count}.");
            }

            return new GradientBoostedTrees(
                classes, features, baseScores, left, right, feature, value, defaultLeft, roots, treeClass);
        }

        /// <summary>The base scores, either one for all the classes ("0.5") or one per class ("[a,b,...]").</summary>
        private static float[] ParseBaseScores(string text, int classes)
        {
            var scores = new float[classes];
            string trimmed = text.Trim();
            if (trimmed.StartsWith("[", StringComparison.Ordinal))
            {
                var parts = trimmed.Trim('[', ']').Split(',');
                if (parts.Length != classes)
                {
                    throw new InvalidOperationException(
                        $"Expected {classes} base scores, but got {parts.Length}: {text}");
                }

                for (int i = 0; i < classes; i++)
                {
                    scores[i] = float.Parse(parts[i], NumberStyles.Float, CultureInfo.InvariantCulture);
                }
            }
            else
            {
                Array.Fill(scores, float.Parse(trimmed, NumberStyles.Float, CultureInfo.InvariantCulture));
            }

            return scores;
        }

        /// <summary>Predict the probability of each class into <paramref name="probabilities"/>.</summary>
        public void Predict(ReadOnlySpan<float> features, Span<float> probabilities)
        {
            if (features.Length < FeatureCount)
            {
                throw new ArgumentException($"Expected {FeatureCount} features, but got {features.Length}.");
            }

            if (probabilities.Length < ClassCount)
            {
                throw new ArgumentException($"Expected room for {ClassCount} probabilities, but got {probabilities.Length}.");
            }

            for (int c = 0; c < ClassCount; c++)
            {
                probabilities[c] = _baseScores[c];
            }

            for (int tree = 0; tree < _roots.Length; tree++)
            {
                int node = _roots[tree];
                while (_left[node] >= 0)
                {
                    float x = features[_feature[node]];
                    bool goLeft = float.IsNaN(x) ? _defaultLeft[node] : x < _value[node];
                    node = goLeft ? _left[node] : _right[node];
                }

                probabilities[_treeClass[tree]] += _value[node];
            }

            float max = float.NegativeInfinity;
            for (int c = 0; c < ClassCount; c++)
            {
                max = Math.Max(max, probabilities[c]);
            }

            float sum = 0f;
            for (int c = 0; c < ClassCount; c++)
            {
                probabilities[c] = MathF.Exp(probabilities[c] - max);
                sum += probabilities[c];
            }

            for (int c = 0; c < ClassCount; c++)
            {
                probabilities[c] /= sum;
            }
        }
    }
}
