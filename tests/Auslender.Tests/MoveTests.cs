using System;
using System.Collections.Generic;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class RoomJoystickTests
    {
        private const double Fps = 30.0;

        /// <summary>The unit of the player at home, in pixels (the eyes 20 pixels apart).</summary>
        private const float Unit = 88f;

        /// <summary>Stand still at home for the calibration, and return the time after it.</summary>
        private static double Calibrate(RoomJoystick joystick)
        {
            double t = 0.0;
            for (; t < 1.5; t += 1.0 / Fps)
            {
                joystick.Observe(t, 320f, 200f, Unit);
                joystick.Update(t);
            }

            Assert.True(joystick.Calibrated);
            return t;
        }

        /// <summary>Hold the head at the position for a while, and return the time after it.</summary>
        private static double Hold(RoomJoystick joystick, double t, float x, float y, float unit, double seconds = 1.0)
        {
            double end = t + seconds;
            for (; t < end; t += 1.0 / Fps)
            {
                joystick.Observe(t, x, y, unit);
                joystick.Update(t);
            }

            return t;
        }

        [Fact]
        public void Holding_still_sets_the_home_spot()
        {
            var joystick = new RoomJoystick();
            Assert.False(joystick.Calibrated);
            Calibrate(joystick);
            Assert.Equal(320f, joystick.HomeX, 1);
            Assert.Equal((0f, 0f), joystick.Stick);
        }

        [Fact]
        public void Moving_does_not_set_the_home_spot()
        {
            var joystick = new RoomJoystick();
            for (double t = 0.0; t < 3.0; t += 1.0 / Fps)
            {
                // NOTE (mristin):
                // Swaying by a unit each second, as when walking about.
                joystick.Observe(t, 320f + Unit * (float)Math.Sin(t * Math.PI * 2.0), 200f, Unit);
                joystick.Update(t);
            }

            Assert.False(joystick.Calibrated);
        }

        [Fact]
        public void Boxing_on_the_spot_does_not_move()
        {
            var joystick = new RoomJoystick();
            double t = Calibrate(joystick);

            // NOTE (mristin):
            // Leaning a quarter of a unit to the side and bobbing a little stays
            // within the dead zone.
            t = Hold(joystick, t, 320f - Unit * 0.25f, 210f, Unit * 1.04f);
            Assert.Equal((0f, 0f), joystick.Stick);
        }

        [Fact]
        public void A_step_to_the_right_moves_right()
        {
            var joystick = new RoomJoystick();
            double t = Calibrate(joystick);

            // NOTE (mristin):
            // In the not mirrored frame, the player's right is to the left.
            Hold(joystick, t, 320f - Unit * 1.2f, 200f, Unit);
            Assert.Equal(1f, joystick.Stick.X, 2);
            Assert.Equal(0f, joystick.Stick.Y, 2);
        }

        [Fact]
        public void A_step_to_the_left_moves_left()
        {
            var joystick = new RoomJoystick();
            double t = Calibrate(joystick);
            Hold(joystick, t, 320f + Unit * 0.7f, 200f, Unit);
            Assert.InRange(joystick.Stick.X, -0.7f, -0.3f);
        }

        [Fact]
        public void A_step_towards_the_camera_moves_forward_and_one_back_moves_back()
        {
            var joystick = new RoomJoystick();
            double t = Calibrate(joystick);

            // NOTE (mristin):
            // From 2.5 m, a step of half a meter towards the camera makes the head
            // a quarter bigger; one back makes it a sixth smaller.
            t = Hold(joystick, t, 320f, 200f, Unit * 1.25f);
            Assert.Equal(1f, joystick.Stick.Y, 2);

            t = Hold(joystick, t, 320f, 200f, Unit);
            Assert.Equal(0f, joystick.Stick.Y, 2);

            Hold(joystick, t, 320f, 200f, Unit * 0.83f);
            Assert.Equal(-1f, joystick.Stick.Y, 2);
        }

        [Fact]
        public void Losing_the_head_lets_go_of_the_stick()
        {
            var joystick = new RoomJoystick();
            double t = Calibrate(joystick);
            t = Hold(joystick, t, 320f - Unit * 1.2f, 200f, Unit);
            Assert.NotEqual(0f, joystick.Stick.X);

            joystick.Update(t + 1.0);
            Assert.Equal((0f, 0f), joystick.Stick);
            Assert.True(joystick.Calibrated);
        }

        [Fact]
        public void A_duck_ducks_and_a_jump_jumps_once()
        {
            var joystick = new RoomJoystick();
            double t = Calibrate(joystick);

            t = Hold(joystick, t, 320f, 200f + Unit * 0.6f, Unit, 0.5);
            Assert.True(joystick.Ducking);
            Assert.Equal(0, joystick.Jumps);

            t = Hold(joystick, t, 320f, 200f, Unit, 0.5);
            Assert.False(joystick.Ducking);

            // NOTE (mristin):
            // The head rises 0.8 units for a third of a second, and lands.
            t = Hold(joystick, t, 320f, 200f - Unit * 0.8f, Unit, 0.33);
            Assert.True(joystick.Jumping);
            Hold(joystick, t, 320f, 200f, Unit, 0.5);
            Assert.False(joystick.Jumping);
            Assert.Equal(1, joystick.Jumps);
        }

        [Fact]
        public void Ramp_is_zero_in_the_dead_zone_and_one_beyond_full()
        {
            Assert.Equal(0f, RoomJoystick.Ramp(0.3f, 0.4f, 1f));
            Assert.Equal(0.5f, RoomJoystick.Ramp(0.7f, 0.4f, 1f), 3);
            Assert.Equal(-1f, RoomJoystick.Ramp(-2f, 0.4f, 1f));
        }
    }
}
