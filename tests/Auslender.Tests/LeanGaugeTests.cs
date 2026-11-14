using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class LeanGaugeTests
    {
        private const double Fps = 15.0;

        /// <summary>Hold the sideways offset for a while, and return the time after it.</summary>
        private static double Hold(LeanGauge gauge, double t, float sideways, double seconds)
        {
            double end = t + seconds;
            for (; t < end; t += 1.0 / Fps)
            {
                gauge.Observe(t, sideways);
            }

            return t;
        }

        [Fact]
        public void Standing_still_is_no_slip()
        {
            var gauge = new LeanGauge();
            Hold(gauge, 0.0, 0f, 3.0);
            Assert.Equal(0, gauge.Slip);
            Assert.Equal(0f, gauge.Lean, 3);
        }

        [Fact]
        public void A_quick_lean_to_the_left_is_a_slip_to_the_left()
        {
            var gauge = new LeanGauge();
            double t = Hold(gauge, 0.0, 0f, 3.0);
            Hold(gauge, t, -1.2f, 0.4);
            Assert.Equal(-1, gauge.Slip);
        }

        [Fact]
        public void A_quick_lean_to_the_right_is_a_slip_to_the_right()
        {
            var gauge = new LeanGauge();
            double t = Hold(gauge, 0.0, 0f, 3.0);
            Hold(gauge, t, 1.2f, 0.4);
            Assert.Equal(1, gauge.Slip);
        }

        [Fact]
        public void Drifting_off_home_slowly_is_no_slip()
        {
            // NOTE (mristin):
            // As on the recording of a fight: half a unit to the left over a
            // minute, and then a slip still counts from where he stands.
            var gauge = new LeanGauge();
            double t = 0.0;
            for (int i = 0; i <= 60 * (int)Fps; i++)
            {
                gauge.Observe(t, -0.5f * i / (60f * (float)Fps));
                Assert.Equal(0, gauge.Slip);
                t += 1.0 / Fps;
            }

            Hold(gauge, t, -0.5f + 0.8f, 0.4);
            Assert.Equal(1, gauge.Slip);
        }

        [Fact]
        public void A_held_slip_stays_a_slip_for_a_while()
        {
            var gauge = new LeanGauge();
            double t = Hold(gauge, 0.0, 0f, 3.0);
            Hold(gauge, t, 1.0f, 1.2);
            Assert.Equal(1, gauge.Slip);
        }

        [Fact]
        public void A_step_aside_becomes_the_new_baseline()
        {
            var gauge = new LeanGauge();
            double t = Hold(gauge, 0.0, 0f, 3.0);
            Hold(gauge, t, 1.0f, 8.0);
            Assert.Equal(0, gauge.Slip);
            Assert.Equal(1.0f, gauge.Baseline, 1);
        }

        [Fact]
        public void Reset_forgets_the_baseline()
        {
            var gauge = new LeanGauge();
            Hold(gauge, 0.0, 1.0f, 3.0);
            gauge.Reset();
            Assert.True(float.IsNaN(gauge.Baseline));
            Assert.Equal(0, gauge.Slip);
        }
    }
}
