using System.IO;
using System.Text.Json;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class GradientBoostedTreesTests
    {
        /// <summary>
        /// The model and the cases were made with XGBoost in Python: 4 classes,
        /// 8 features, some of them missing (NaN), and the probabilities which
        /// XGBoost's <c>predict_proba</c> gave.
        /// </summary>
        [Fact]
        public void Predicts_the_same_probabilities_as_xgboost()
        {
            var model = GradientBoostedTrees.FromJson(File.ReadAllText(TestData.Path("xgboost_probe.json")));
            Assert.Equal(4, model.ClassCount);
            Assert.Equal(8, model.FeatureCount);

            using var cases = JsonDocument.Parse(File.ReadAllText(TestData.Path("xgboost_probe_cases.json")));
            var features = cases.RootElement.GetProperty("features");
            var expected = cases.RootElement.GetProperty("probabilities");
            Assert.True(features.GetArrayLength() > 0);

            var x = new float[model.FeatureCount];
            var p = new float[model.ClassCount];
            for (int i = 0; i < features.GetArrayLength(); i++)
            {
                for (int j = 0; j < x.Length; j++)
                {
                    var value = features[i][j];
                    x[j] = value.ValueKind == JsonValueKind.Null ? float.NaN : value.GetSingle();
                }

                model.Predict(x, p);
                for (int c = 0; c < p.Length; c++)
                {
                    Assert.Equal(expected[i][c].GetSingle(), p[c], 5);
                }
            }
        }
    }
}
