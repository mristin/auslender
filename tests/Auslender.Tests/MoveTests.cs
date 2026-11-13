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

    public class PunchDetectorTests
    {
        private const double Fps = 30.0;
        private const float Unit = 100f;
        private const float EyesY = 150f;

        /// <summary>Feed the hand along the path, and return the punches found.</summary>
        private static List<Punch> Feed(
            PunchDetector detector, Func<double, (float X, float Y, float Size)> path, double seconds, double start = 0.0
        )
        {
            var punches = new List<Punch>();
            for (double t = start; t < start + seconds; t += 1.0 / Fps)
            {
                var (x, y, size) = path(t - start);
                var punch = detector.Observe(t, x, y, size, EyesY, Unit);
                if (punch != null)
                {
                    punches.Add(punch.Value);
                }
            }

            return punches;
        }

        /// <summary>The left fist in the guard, in front of the chin, on the right of the (not mirrored) frame.</summary>
        private static (float X, float Y, float Size) Guard(double _) => (360f, 220f, 40f);

        [Fact]
        public void A_fist_in_the_guard_does_not_punch()
        {
            var detector = new PunchDetector(HandSide.Left);
            Assert.Empty(Feed(detector, Guard, 3.0));
        }

        [Fact]
        public void A_jittering_fist_does_not_punch()
        {
            var detector = new PunchDetector(HandSide.Left);
            var random = new Random(1);
            Assert.Empty(Feed(
                detector,
                _ => (360f + (float)random.NextDouble() * 8f, 220f + (float)random.NextDouble() * 8f,
                    40f * (1f + (float)random.NextDouble() * 0.1f)),
                3.0
            ));
        }

        [Fact]
        public void A_fist_flying_at_the_camera_is_a_straight_punch_once()
        {
            var detector = new PunchDetector(HandSide.Left);
            // NOTE (mristin):
            // The fist doubles its size within a fifth of a second, stays out a
            // moment, and comes back.
            var punches = Feed(
                detector,
                t =>
                {
                    float grow = (float)Math.Clamp(t / 0.2, 0.0, 1.0);
                    if (t > 0.4)
                    {
                        grow = (float)Math.Clamp(1.0 - (t - 0.4) / 0.2, 0.0, 1.0);
                    }

                    return (360f - grow * 20f, 220f - grow * 10f, 40f * (1f + grow));
                },
                1.0
            );

            Assert.Single(punches);
            Assert.Equal(PunchKind.Straight, punches[0].Kind);
            Assert.Equal(HandSide.Left, punches[0].Side);
        }

        [Fact]
        public void A_fist_swinging_across_is_a_hook()
        {
            var detector = new PunchDetector(HandSide.Left);
            // NOTE (mristin):
            // The left fist swings to the player's right, which is to the left
            // of the (not mirrored) frame, by a unit in a fifth of a second.
            var punches = Feed(
                detector,
                t => (420f - (float)Math.Clamp(t / 0.2, 0.0, 1.0) * Unit, 180f, 40f),
                0.6
            );

            Assert.Single(punches);
            Assert.Equal(PunchKind.Hook, punches[0].Kind);
        }

        [Fact]
        public void A_fist_swinging_out_is_no_hook()
        {
            var detector = new PunchDetector(HandSide.Left);
            Assert.Empty(Feed(
                detector,
                t => (360f + (float)Math.Clamp(t / 0.2, 0.0, 1.0) * Unit, 180f, 40f),
                0.6
            ));
        }

        [Fact]
        public void A_rising_fist_is_an_uppercut()
        {
            var detector = new PunchDetector(HandSide.Right);
            var punches = Feed(
                detector,
                t => (280f, 260f - (float)Math.Clamp(t / 0.2, 0.0, 1.0) * Unit, 40f),
                0.6
            );

            Assert.Single(punches);
            Assert.Equal(PunchKind.Uppercut, punches[0].Kind);
            Assert.Equal(HandSide.Right, punches[0].Side);
        }

        [Fact]
        public void Two_punches_count_twice()
        {
            var detector = new PunchDetector(HandSide.Left);
            (float X, float Y, float Size) Jab(double t)
            {
                double phase = t % 0.8;
                float grow = phase < 0.15 ? (float)(phase / 0.15) : (phase < 0.3 ? 1f : Math.Max(0f, 1f - (float)((phase - 0.3) / 0.15)));
                return (360f, 220f, 40f * (1f + grow * 0.8f));
            }

            Assert.Equal(2, Feed(detector, Jab, 1.6).Count);
        }

        [Fact]
        public void A_hand_hanging_at_the_hip_does_not_punch()
        {
            var detector = new PunchDetector(HandSide.Left);
            Assert.Empty(Feed(
                detector,
                t => (360f, EyesY + Unit * 2f, 40f * (1f + (float)Math.Clamp(t / 0.2, 0.0, 1.0))),
                0.6
            ));
        }
    }

    public class KickDetectorTests
    {
        private const float Unit = 100f;

        /// <summary>A pose of a player standing at x = 320, with the left ankle raised by the share of the leg.</summary>
        private static Pose Standing(float leftLift = 0f, float leftOut = 0f, float squat = 0f)
        {
            var pose = HandTrackerTests.PoseAt(320f, (380f, 220f), (260f, 220f));
            var points = (Keypoint[])pose.Keypoints.Clone();
            const float leg = 200f;
            void Set(BodyPart part, float x, float y) => points[(int)part] = new Keypoint(x, y, 0.9f);

            // NOTE (mristin):
            // A squat lowers the hips and the knees, but the feet stay.
            float hipY = 300f + squat * leg;
            Set(BodyPart.LeftHip, 360f, hipY);
            Set(BodyPart.RightHip, 280f, hipY);
            Set(BodyPart.LeftKnee, 360f + leftOut * leg * 0.5f, (hipY + 500f) * 0.5f - leftLift * leg * 0.5f);
            Set(BodyPart.RightKnee, 280f, (hipY + 500f) * 0.5f);
            Set(BodyPart.LeftAnkle, 360f + leftOut * leg, 500f - leftLift * leg);
            Set(BodyPart.RightAnkle, 280f, 500f);
            return new Pose(points, pose.Box, pose.Score);
        }

        private static List<Kick> Feed(KickDetector detector, IEnumerable<Pose> poses, double rate = 10.0)
        {
            var kicks = new List<Kick>();
            double t = 0.0;
            foreach (var pose in poses)
            {
                var kick = detector.Observe(t, pose);
                if (kick != null)
                {
                    kicks.Add(kick.Value);
                }

                t += 1.0 / rate;
            }

            return kicks;
        }

        private static IEnumerable<Pose> Repeat(Func<int, Pose> pose, int count)
        {
            for (int i = 0; i < count; i++)
            {
                yield return pose(i);
            }
        }

        [Fact]
        public void Standing_does_not_kick()
        {
            Assert.Empty(Feed(new KickDetector(HandSide.Left), Repeat(_ => Standing(), 30)));
        }

        [Fact]
        public void A_squat_does_not_kick()
        {
            Assert.Empty(Feed(new KickDetector(HandSide.Left), Repeat(i => Standing(squat: i % 10 < 5 ? 0.3f : 0f), 30)));
        }

        [Fact]
        public void A_raised_foot_kicks_once()
        {
            // NOTE (mristin):
            // Up for half a second, at ten poses a second.
            var kicks = Feed(
                new KickDetector(HandSide.Left),
                Repeat(i => Standing(leftLift: i >= 10 && i < 15 ? 0.5f : 0f), 30)
            );

            Assert.Single(kicks);
            Assert.Equal(KickKind.Front, kicks[0].Kind);
            Assert.Equal(HandSide.Left, kicks[0].Side);
        }

        [Fact]
        public void A_foot_raised_out_to_the_side_is_a_side_kick()
        {
            var kicks = Feed(
                new KickDetector(HandSide.Left),
                Repeat(i => Standing(leftLift: i >= 10 && i < 15 ? 0.5f : 0f, leftOut: i >= 10 && i < 15 ? 0.7f : 0f), 30)
            );

            Assert.Single(kicks);
            Assert.Equal(KickKind.Side, kicks[0].Kind);
        }

        [Fact]
        public void The_other_leg_does_not_kick()
        {
            Assert.Empty(Feed(
                new KickDetector(HandSide.Right),
                Repeat(i => Standing(leftLift: i >= 10 && i < 15 ? 0.5f : 0f), 30)
            ));
        }

        [Fact]
        public void Two_kicks_count_twice()
        {
            var kicks = Feed(
                new KickDetector(HandSide.Left),
                Repeat(i => Standing(leftLift: i % 10 >= 3 && i % 10 < 7 ? 0.5f : 0f), 20)
            );
            Assert.Equal(2, kicks.Count);
        }
    }
}  // namespace Auslender.Tests
