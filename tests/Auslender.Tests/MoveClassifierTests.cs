using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class MoveClassifierTests
    {
        private static readonly string[] Classes =
        {
            "none", "straight_left", "straight_right", "hook_left", "hook_right", "uppercut_left",
            "uppercut_right", "kick_left", "kick_right", "duck", "jump", "slip_left", "slip_right", "cover",
        };

        private sealed class Stub : IMoveModel
        {
            public int ClassCount => Classes.Length;

            public void Predict(ReadOnlySpan<float> features, Span<float> probabilities)
            {
            }

            public void Dispose()
            {
            }
        }

        private static MoveClassifier Make() => new(Classes, new[] { 0.0, 0.1, 0.2, 0.3 }, new Stub());

        /// <summary>The probabilities with the given classes set, the rest to "none".</summary>
        private static float[] P(params (string Class, float P)[] set)
        {
            var p = new float[Classes.Length];
            float rest = 1f;
            foreach (var (name, value) in set)
            {
                p[Array.IndexOf(Classes, name)] = value;
                rest -= value;
            }

            p[0] = Math.Max(0f, rest);
            return p;
        }

        /// <summary>Feed the probabilities at 30 frames a second, and return the moves which fired.</summary>
        private static List<ClassifiedMove> Feed(MoveClassifier classifier, IEnumerable<float[]> frames, double start = 0.0)
        {
            var fired = new List<ClassifiedMove>();
            double t = start;
            foreach (var frame in frames)
            {
                classifier.Decide(t, frame, fired);
                t += 1.0 / 30.0;
            }

            return fired;
        }

        [Fact]
        public void A_hook_which_starts_like_a_straight_fires_once_as_a_hook()
        {
            var fired = Feed(Make(), new[]
            {
                P(),
                P(("straight_left", 0.6f)),
                P(("straight_left", 0.4f), ("hook_left", 0.5f)),
                P(("hook_left", 0.8f)),
                P(("hook_left", 0.9f)),
                P(("hook_left", 0.6f)),
                P(),
                P(),
            });

            Assert.Equal(new[] { "hook_left" }, fired.Select(m => m.Class));
        }

        [Fact]
        public void Strikes_of_both_sides_fire_both()
        {
            var fired = Feed(Make(), new[]
            {
                P(("straight_left", 0.8f)),
                P(("straight_left", 0.3f), ("straight_right", 0.6f)),
                P(("straight_right", 0.8f)),
                P(),
                P(),
                P(),
                P(),
                P(),
            });

            Assert.Equal(new[] { "straight_left", "straight_right" }, fired.Select(m => m.Class).OrderBy(c => c));
        }

        [Fact]
        public void A_duck_fires_at_once()
        {
            var fired = Feed(Make(), new[] { P(), P(("duck", 0.7f)) });
            Assert.Equal(new[] { "duck" }, fired.Select(m => m.Class));
            Assert.Equal(1.0 / 30.0, fired[0].Time, 6);
        }

        [Fact]
        public void A_held_move_fires_once()
        {
            var frames = Enumerable.Repeat(P(("uppercut_right", 0.9f)), 30);
            var fired = Feed(Make(), frames);
            Assert.Single(fired);
        }

        [Fact]
        public void Two_punches_in_a_row_fire_twice()
        {
            var punch = new[] { P(("straight_right", 0.9f)), P(("straight_right", 0.9f)), P(), P() };
            var frames = punch.Concat(Enumerable.Repeat(P(), 8)).Concat(punch);
            var fired = Feed(Make(), frames);
            Assert.Equal(2, fired.Count);
        }

        [Fact]
        public void The_cover_is_a_state_with_hysteresis()
        {
            var classifier = Make();
            Feed(classifier, new[] { P(("cover", 0.6f)) });
            Assert.True(classifier.Covering);
            Feed(classifier, new[] { P(("cover", 0.4f)) });
            Assert.True(classifier.Covering);
            Feed(classifier, new[] { P(("cover", 0.2f)) });
            Assert.False(classifier.Covering);
        }

        [Fact]
        public void Loads_the_model_of_the_game()
        {
            // NOTE (mristin):
            // The trained model of the game, with its description.
            string directory = Path.GetDirectoryName(TestData.Path("moves.json"))!;
            using var classifier = MoveClassifier.FromDescription(
                File.ReadAllText(TestData.Path("moves.json")),
                file => File.ReadAllBytes(Path.Combine(directory, file)));
            Assert.Equal(Classes, classifier.Classes);
            Assert.Equal(4, classifier.Features.Steps);
        }
    }
}
