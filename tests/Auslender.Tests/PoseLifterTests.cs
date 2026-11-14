using System;
using System.Numerics;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class PoseLifterTests
    {
        /// <summary>
        /// A player standing in his guard in a 640x480 picture (not mirrored: him
        /// left is on the right of the picture), without his feet in it.
        /// </summary>
        private static Pose Standing()
        {
            var points = new (float X, float Y, float Score)[]
            {
                (320, 100, 0.9f), (330, 90, 0.9f), (310, 90, 0.9f), (340, 95, 0.9f), (300, 95, 0.9f),
                (370, 150, 0.9f), (270, 150, 0.9f), (392, 222, 0.9f), (248, 222, 0.9f),
                (345, 140, 0.9f), (295, 140, 0.9f), (350, 280, 0.9f), (290, 280, 0.9f),
                (352, 372, 0.9f), (288, 372, 0.9f), (353, 470, 0.1f), (287, 470, 0.1f),
            };
            var keypoints = new Keypoint[Pose.KeypointCount];
            for (int i = 0; i < keypoints.Length; i++)
            {
                keypoints[i] = new Keypoint(points[i].X, points[i].Y, points[i].Score);
            }

            return new Pose(keypoints, new BoundingBox(240, 80, 400, 480), 0.9f);
        }

        [Fact]
        public void Guesses_the_ankles_which_the_camera_misses()
        {
            var joints = new Vector2[PoseLifter.JointCount];
            PoseLifter.ToH36m(Standing(), joints);
            // NOTE (mristin):
            // The knee plus the thigh again: (352, 372) + ((352, 372) - (350, 280)).
            Assert.Equal(new Vector2(354, 464), joints[(int)PoseLifter.Joint.LeftAnkle]);
            Assert.Equal(new Vector2(320, 280), joints[(int)PoseLifter.Joint.Pelvis]);
            Assert.Equal(new Vector2(320, 150), joints[(int)PoseLifter.Joint.Thorax]);
        }

        [Fact]
        public void Lifts_a_standing_player_upright_with_the_gloves_in_front()
        {
            using var lifter = new PoseLifter(TestData.LoadModel(TestData.Lifter));
            var joints3d = new Vector3[PoseLifter.JointCount];
            var joints2d = new Vector2[PoseLifter.JointCount];
            lifter.Lift(Standing(), 640, 480, joints3d, joints2d);

            Vector3 At(PoseLifter.Joint joint) => joints3d[(int)joint];

            // NOTE (mristin):
            // y is down: the head is above the thorax, which is above the pelvis.
            Assert.True(At(PoseLifter.Joint.Head).Y < At(PoseLifter.Joint.Thorax).Y);
            Assert.True(At(PoseLifter.Joint.Thorax).Y < -0.3f);
            Assert.True(MathF.Abs(At(PoseLifter.Joint.Pelvis).Length()) < 0.05f);
            // His left is on the right of the picture (x right).
            Assert.True(At(PoseLifter.Joint.LeftShoulder).X > At(PoseLifter.Joint.RightShoulder).X);
            // The gloves of the guard are in front of the shoulders (z away from the camera).
            Assert.True(At(PoseLifter.Joint.LeftWrist).Z < At(PoseLifter.Joint.LeftShoulder).Z);
            Assert.True(At(PoseLifter.Joint.RightWrist).Z < At(PoseLifter.Joint.RightShoulder).Z);
        }
    }
}
