using System;
using System.IO;
using System.Text.Json;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class MoveFeaturesTests
    {
        /// <summary>
        /// The cases were made by the Python of the training
        /// (moves_ml.sequences) on a synthetic pose stream at an uneven frame
        /// rate: the features must be the same, frame by frame.
        /// </summary>
        [Fact]
        public void Computes_the_same_features_as_the_training()
        {
            using var cases = JsonDocument.Parse(File.ReadAllText(TestData.Path("move_features_cases.json")));
            var root = cases.RootElement;
            var offsets = new double[root.GetProperty("offsets").GetArrayLength()];
            for (int i = 0; i < offsets.Length; i++)
            {
                offsets[i] = root.GetProperty("offsets")[i].GetDouble();
            }

            var features = new MoveFeatures(offsets);
            var times = root.GetProperty("t");
            var poses = root.GetProperty("poses");
            var expected = root.GetProperty("features");
            Assert.Equal(expected[0].GetArrayLength(), features.Count);

            var pose = new float[51];
            var got = new float[features.Count];
            for (int frame = 0; frame < times.GetArrayLength(); frame++)
            {
                for (int i = 0; i < 51; i++)
                {
                    pose[i] = poses[frame][i].GetSingle();
                }

                features.Observe(times[frame].GetDouble(), pose);
                Assert.True(features.Compute(got));
                for (int i = 0; i < got.Length; i++)
                {
                    Assert.True(
                        Math.Abs(expected[frame][i].GetSingle() - got[i]) < 1e-4f,
                        $"Frame {frame}, feature {i}: expected {expected[frame][i].GetSingle()}, got {got[i]}");
                }
            }
        }

        [Fact]
        public void Scaling_the_body_does_not_change_the_features()
        {
            var small = new MoveFeatures(new[] { 0.0, 0.1, 0.2, 0.3 });
            var big = new MoveFeatures(new[] { 0.0, 0.1, 0.2, 0.3 });
            var a = new float[small.Count];
            var b = new float[big.Count];
            for (int frame = 0; frame < 40; frame++)
            {
                double t = frame / 30.0;
                var pose = new float[51];
                for (int i = 0; i < 17; i++)
                {
                    pose[i * 3] = 300f + 10f * i + 20f * MathF.Sin((float)t * 5f + i);
                    pose[i * 3 + 1] = 100f + 25f * i;
                    pose[i * 3 + 2] = 0.9f;
                }

                small.Observe(t, pose);
                var scaled = (float[])pose.Clone();
                for (int i = 0; i < 17; i++)
                {
                    // NOTE (mristin):
                    // Twice the size, somewhere else in the picture.
                    scaled[i * 3] = scaled[i * 3] * 2f - 150f;
                    scaled[i * 3 + 1] = scaled[i * 3 + 1] * 2f + 40f;
                }

                big.Observe(t, scaled);
                Assert.True(small.Compute(a));
                Assert.True(big.Compute(b));
                for (int i = 0; i < a.Length; i++)
                {
                    Assert.Equal(a[i], b[i], 4);
                }
            }
        }
    }
}
