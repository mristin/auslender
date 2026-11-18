using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Tell from the pose how far the player turned his body to his left or to
    /// his right, to steer the walking.
    /// </summary>
    /// <remarks>
    /// <para>
    /// On the recording of a player (dev/moves/), two measures told the turns
    /// apart, with their direction, while he walked in place:
    /// </para>
    /// <list type="bullet">
    /// <item>
    /// the nose against the middle of the shoulders, in torsos (from the middle
    /// of the shoulders to the middle of the hips): +0.02 ± 0.06 facing the
    /// camera, +0.22 turned to his left, -0.20 turned to his right (in the not
    /// mirrored frame, his left is to the right);
    /// </item>
    /// <item>
    /// the score of the left ear minus the right one: -0.03 ± 0.07 facing,
    /// -0.69 turned to his left (the camera sees his right ear), +0.78 turned
    /// to his right.
    /// </item>
    /// </list>
    /// <para>
    /// The width of the shoulders shrinks in both turns, and in a boxing stance,
    /// too, so it tells neither the direction nor the turn alone. We average the
    /// two measures, each over its value when fully turned, smooth it, and give
    /// the turn beyond a dead zone.
    /// </para>
    /// </remarks>
    public sealed class TurnGauge
    {
        /// <summary>The nose this far (in torsos) from the middle of the shoulders is fully turned.</summary>
        public float FullNose = 0.2f;

        /// <summary>The difference of the scores of the ears when fully turned.</summary>
        public float FullEars = 0.7f;

        /// <summary>Up to this share of a full turn, the player faces the camera.</summary>
        public float Dead = 0.35f;

        /// <summary>From this share of a full turn, the turn is full.</summary>
        public float Full = 0.85f;

        /// <summary>The time constant of smoothing, in seconds.</summary>
        public double Tau = 0.15;

        /// <summary>Use only the key points of at least this score.</summary>
        public float KeypointThreshold = 0.4f;

        private double _observedAt = double.NaN;

        /// <summary>The share of a full turn, smoothed: positive to his left; 0 if unknown.</summary>
        public float Raw { get; private set; }

        /// <summary>The turn in [-1, 1], beyond the dead zone: negative to his left, as the reins of The Steppe Rescue.</summary>
        public float Turn { get; private set; }

        public void Reset()
        {
            _observedAt = double.NaN;
            Raw = 0f;
            Turn = 0f;
        }

        public void Observe(double t, Pose pose)
        {
            float th = KeypointThreshold;
            float sum = 0f;
            int count = 0;
            bool shoulders = pose.Has(BodyPart.LeftShoulder, th) && pose.Has(BodyPart.RightShoulder, th);
            bool hips = pose.Has(BodyPart.LeftHip, th) && pose.Has(BodyPart.RightHip, th);
            if (shoulders && hips && pose.Has(BodyPart.Nose, th))
            {
                var ls = pose[BodyPart.LeftShoulder];
                var rs = pose[BodyPart.RightShoulder];
                var lh = pose[BodyPart.LeftHip];
                var rh = pose[BodyPart.RightHip];
                float midX = (ls.X + rs.X) * 0.5f;
                float midY = (ls.Y + rs.Y) * 0.5f;
                float dx = midX - (lh.X + rh.X) * 0.5f;
                float dy = midY - (lh.Y + rh.Y) * 0.5f;
                float torso = MathF.Sqrt(dx * dx + dy * dy);
                if (torso > 1f)
                {
                    sum += Math.Clamp((pose[BodyPart.Nose].X - midX) / torso / FullNose, -1.5f, 1.5f);
                    count++;
                }
            }

            float ears = pose[BodyPart.LeftEar].Score - pose[BodyPart.RightEar].Score;
            sum += Math.Clamp(-ears / FullEars, -1.5f, 1.5f);
            count++;

            float raw = sum / count;
            if (double.IsNaN(_observedAt) || t - _observedAt > 1.0)
            {
                Raw = raw;
            }
            else
            {
                float a = (float)(1.0 - Math.Exp(-Math.Max(0.0, t - _observedAt) / Tau));
                Raw += (raw - Raw) * a;
            }

            _observedAt = t;
            Turn = -RoomJoystick.Ramp(Raw, Dead, Full);
        }

        /// <summary>Let go of the turn when the pose is lost.</summary>
        public void Update(double t)
        {
            if (double.IsNaN(_observedAt) || t - _observedAt > 0.6)
            {
                Raw = 0f;
                Turn = 0f;
            }
        }
    }
}  // namespace Auslender.Vision
