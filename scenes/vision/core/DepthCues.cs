using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>Enumerate the sizes of the player which tell how far from the camera she stands.</summary>
    public enum DepthCue
    {
        /// <summary>The distance between the eyes; shrinks as she turns her head.</summary>
        Eyes = 0,

        /// <summary>From the middle of the eyes to the middle of the mouth; shrinks as she nods.</summary>
        EyesToMouth = 1,

        /// <summary>The width of the face box of the face landmarks.</summary>
        FaceBox = 2,

        /// <summary>The width of the head box of the head detector (only when it ran on the frame).</summary>
        HeadWidth = 3,

        /// <summary>The height of the head box of the head detector.</summary>
        HeadHeight = 4,

        /// <summary>The width of the shoulders, from the pose; shrinks as she twists in a punch.</summary>
        Shoulders = 5,

        /// <summary>From the middle of the shoulders to the middle of the hips, from the pose; shrinks as she ducks.</summary>
        Torso = 6,

        /// <summary>The width of the hips, from the pose.</summary>
        Hips = 7,
    }

    /// <summary>
    /// Hold the sizes of the player in one frame, in pixels, each NaN if not
    /// measured; see <see cref="DepthCue"/>.
    /// </summary>
    /// <remarks>
    /// Each size alone is fooled by something: turning the head, nodding,
    /// twisting the shoulders in a punch, ducking. They are fooled by different
    /// things, though, so the <see cref="RoomJoystick"/> takes the median of
    /// how much each grew since home.
    /// </remarks>
    public sealed class DepthCues
    {
        public const int Count = 8;

        public readonly float[] Sizes = new float[Count];

        public DepthCues()
        {
            Clear();
        }

        public float this[DepthCue cue]
        {
            get => Sizes[(int)cue];
            set => Sizes[(int)cue] = value;
        }

        public void Clear()
        {
            Array.Fill(Sizes, float.NaN);
        }

        /// <summary>Set the cues of the face: the landmarks, and the head box if the head detector found it in this frame.</summary>
        public void SetFace(FaceLandmarks? face, BoundingBox? head, bool detected)
        {
            for (int i = (int)DepthCue.Eyes; i <= (int)DepthCue.HeadHeight; i++)
            {
                Sizes[i] = float.NaN;
            }

            if (face != null)
            {
                float eyesX = (face.LeftEyeX + face.RightEyeX) * 0.5f;
                float eyesY = (face.LeftEyeY + face.RightEyeY) * 0.5f;
                float mouthX = (face.MouthLeftX + face.MouthRightX) * 0.5f;
                float mouthY = (face.MouthLeftY + face.MouthRightY) * 0.5f;
                this[DepthCue.Eyes] = Distance(face.LeftEyeX, face.LeftEyeY, face.RightEyeX, face.RightEyeY);
                this[DepthCue.EyesToMouth] = Distance(eyesX, eyesY, mouthX, mouthY);
                this[DepthCue.FaceBox] = face.Box.IsEmpty ? float.NaN : face.Box.Width;
            }

            if (detected && head != null && !head.Value.IsEmpty)
            {
                this[DepthCue.HeadWidth] = head.Value.Width;
                this[DepthCue.HeadHeight] = head.Value.Height;
            }
        }

        /// <summary>Set the cues of the body from the pose; NaN where its key points are not confident.</summary>
        public void SetPose(Pose? pose, float threshold)
        {
            for (int i = (int)DepthCue.Shoulders; i <= (int)DepthCue.Hips; i++)
            {
                Sizes[i] = float.NaN;
            }

            if (pose == null)
            {
                return;
            }

            bool shoulders = pose.Has(BodyPart.LeftShoulder, threshold) && pose.Has(BodyPart.RightShoulder, threshold);
            bool hips = pose.Has(BodyPart.LeftHip, threshold) && pose.Has(BodyPart.RightHip, threshold);
            var ls = pose[BodyPart.LeftShoulder];
            var rs = pose[BodyPart.RightShoulder];
            var lh = pose[BodyPart.LeftHip];
            var rh = pose[BodyPart.RightHip];
            if (shoulders)
            {
                this[DepthCue.Shoulders] = Distance(ls.X, ls.Y, rs.X, rs.Y);
            }

            if (hips)
            {
                this[DepthCue.Hips] = Distance(lh.X, lh.Y, rh.X, rh.Y);
            }

            if (shoulders && hips)
            {
                this[DepthCue.Torso] = Distance(
                    (ls.X + rs.X) * 0.5f, (ls.Y + rs.Y) * 0.5f, (lh.X + rh.X) * 0.5f, (lh.Y + rh.Y) * 0.5f
                );
            }
        }

        /// <summary>Copy the cues of the body from the other.</summary>
        public void CopyPose(DepthCues other)
        {
            for (int i = (int)DepthCue.Shoulders; i <= (int)DepthCue.Hips; i++)
            {
                Sizes[i] = other.Sizes[i];
            }
        }

        private static float Distance(float x1, float y1, float x2, float y2)
        {
            float dx = x2 - x1;
            float dy = y2 - y1;
            float distance = MathF.Sqrt(dx * dx + dy * dy);
            return distance > 1f ? distance : float.NaN;
        }
    }
}  // namespace Auslender.Vision
