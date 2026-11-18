using System;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class RtmPoseTrackerTests
    {
        [Fact]
        public void Follows_the_pose_which_rtmo_found()
        {
            using var vision = new RiderVision(TestData.LoadModel(TestData.Rtmo));
            using var tracker = new RtmPoseTracker(TestData.LoadModel(TestData.RtmPose));
            var frame = TestData.LoadFrame("astronaut_640x480.png");

            var found = vision.Process(frame).Player;
            Assert.NotNull(found);
            Assert.False(tracker.Tracking);
            Assert.Null(tracker.Track(frame));

            Assert.True(tracker.Seed(found!));
            var followed = tracker.Track(TestData.LoadFrame("astronaut_640x480.png", 0.1));
            Assert.NotNull(followed);
            Assert.True(tracker.Tracking);

            // NOTE (mristin):
            // The confident key points of both agree within a few pixels.
            int compared = 0;
            for (int k = 0; k < Pose.KeypointCount; k++)
            {
                var a = found!.Keypoints[k];
                var b = followed!.Keypoints[k];
                if (a.Score < vision.KeypointThreshold || b.Score < 0.5f)
                {
                    continue;
                }

                compared++;
                float distance = MathF.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));
                Assert.True(distance < 25f, $"Key point {(BodyPart)k}: RTMO {a}, RTMPose {b}");
            }

            Assert.True(compared >= 5, $"Expected at least 5 key points to compare, but got {compared}.");
        }

        [Fact]
        public void Loses_the_player_in_an_empty_picture()
        {
            using var vision = new RiderVision(TestData.LoadModel(TestData.Rtmo));
            using var tracker = new RtmPoseTracker(TestData.LoadModel(TestData.RtmPose));
            var found = vision.Process(TestData.LoadFrame("astronaut_640x480.png")).Player;
            Assert.True(tracker.Seed(found!));

            var empty = new Frame(new byte[640 * 480 * 3], 640, 480, 0.1);
            for (int i = 0; i < 3 && tracker.Tracking; i++)
            {
                tracker.Track(empty);
            }

            Assert.False(tracker.Tracking);
        }
    }
}
