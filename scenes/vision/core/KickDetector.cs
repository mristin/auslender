using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>Enumerate the kicks.</summary>
    public enum KickKind
    {
        /// <summary>A front kick (or a knee): the foot rises in front of the body.</summary>
        Front,

        /// <summary>A side kick (or a roundhouse): the foot rises out to the side.</summary>
        Side,
    }

    /// <summary>A kick which a <see cref="KickDetector"/> found.</summary>
    public readonly struct Kick
    {
        public readonly double Time;
        public readonly HandSide Side;
        public readonly KickKind Kind;

        /// <summary>How high the foot rose, in [0, 1].</summary>
        public readonly float Power;

        public Kick(double time, HandSide side, KickKind kind, float power)
        {
            Time = time;
            Side = side;
            Kind = kind;
            Power = power;
        }

        public override string ToString() => $"{Side} {Kind} kick {Power:F2} at {Time:F2}";
    }

    /// <summary>
    /// Find the kicks of one leg from the body pose: knee strikes, as the
    /// camera often does not see the feet, but sees the knees.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The pose runs only a few times a second (see <see cref="PoseScheduler"/>),
    /// which is too slow to time a punch, but a knee strike takes half a second
    /// or so, and the knee stays up for a moment. We measure how much higher the
    /// knee is than the other knee, as a share of the thigh (from the hip to the
    /// knee, standing); so a duck (both knees bend) does not kick, and it does
    /// not matter how far from the camera the player stands. Walking in place
    /// lifts the knees, too, but less, and the recordings (dev/moves/) tell how
    /// much less.
    /// </para>
    /// <para>
    /// The thigh is learned in the unit of the player (the width of the
    /// shoulders, see <see cref="Pose.Unit"/>), as the longest it was lately. A
    /// kick counts once as the knee rises over <see cref="KickFrom"/>, and the
    /// next one once it came down below <see cref="DownBelow"/>. Only confident
    /// knees and hips count (<see cref="KeypointThreshold"/>), since unsure ones
    /// jump about.
    /// </para>
    /// </remarks>
    public sealed class KickDetector
    {
        public readonly HandSide Side;

        /// <summary>A knee raised by this share of the thigh above the other kicks.</summary>
        public float KickFrom = 0.6f;

        /// <summary>A knee below this share of the thigh is down again.</summary>
        public float DownBelow = 0.25f;

        /// <summary>A knee this far out to the side of its hip (as a share of the thigh) kicks sideways.</summary>
        public float SideFrom = 0.6f;

        /// <summary>A thigh is about this many units long, until we measured it.</summary>
        public float DefaultThigh = 1.1f;

        /// <summary>The time constant of forgetting a long thigh, in seconds.</summary>
        public double ForgetTau = 5.0;

        /// <summary>Use only the key points of at least this score.</summary>
        public float KeypointThreshold = 0.5f;

        /// <summary>
        /// A knee raised while the other one was up by this share of the thigh
        /// within <see cref="WalkWindow"/> is a step of walking in place, not a kick.
        /// </summary>
        public float OtherUp = 0.35f;

        /// <summary>The window in which the other knee must have stayed down, in seconds.</summary>
        public double WalkWindow = 1.0;

        private readonly System.Collections.Generic.List<(double T, float Lift)> _lifts = new();

        private float _thigh = float.NaN;
        private double _learnedAt = double.NaN;
        private bool _up;

        public KickDetector(HandSide side)
        {
            Side = side;
        }

        /// <summary>How much higher the knee is than the other now, as a share of the thigh; NaN if unknown.</summary>
        public float Lift { get; private set; } = float.NaN;

        /// <summary>Whether both knees were seen in the latest pose.</summary>
        public bool SeesKnees { get; private set; }

        /// <summary>The length of the thigh in units, as learned; NaN before it was seen.</summary>
        public float Thigh => _thigh;

        /// <summary>How many kicks were found so far.</summary>
        public int Count { get; private set; }

        public void Reset()
        {
            _thigh = float.NaN;
            _learnedAt = double.NaN;
            _up = false;
            Lift = float.NaN;
            SeesKnees = false;
            _lifts.Clear();
        }

        /// <summary>Observe the pose of the player at the time <paramref name="t"/>; return the kick if one was thrown.</summary>
        public Kick? Observe(double t, Pose pose)
        {
            bool left = Side == HandSide.Left;
            var hipPart = left ? BodyPart.LeftHip : BodyPart.RightHip;
            var kneePart = left ? BodyPart.LeftKnee : BodyPart.RightKnee;
            var otherKneePart = left ? BodyPart.RightKnee : BodyPart.LeftKnee;

            SeesKnees = pose.Has(kneePart, KeypointThreshold) && pose.Has(otherKneePart, KeypointThreshold);
            var unit = pose.Unit(KeypointThreshold);
            bool hasHip = pose.Has(hipPart, KeypointThreshold);
            if (unit == null || !SeesKnees || !hasHip)
            {
                Lift = float.NaN;
                return null;
            }

            var hip = pose[hipPart];
            var knee = pose[kneePart];
            Learn(t, (knee.Y - hip.Y) / unit.Value);
            float thigh = (float.IsNaN(_thigh) ? DefaultThigh : _thigh) * unit.Value;

            float lift = (pose[otherKneePart].Y - knee.Y) / thigh;
            Lift = lift;

            // NOTE (mristin):
            // Walking in place lifts the knees in turns: the other knee was up
            // (this one's lift was negative) just before.
            bool walking = false;
            foreach (var (seenAt, earlier) in _lifts)
            {
                walking |= t - seenAt <= WalkWindow && earlier <= -OtherUp;
            }

            _lifts.Add((t, lift));
            while (_lifts.Count > 0 && t - _lifts[0].T > WalkWindow)
            {
                _lifts.RemoveAt(0);
            }

            if (_up)
            {
                if (lift < DownBelow)
                {
                    _up = false;
                }

                return null;
            }

            if (lift < KickFrom)
            {
                return null;
            }

            _up = true;
            if (walking)
            {
                return null;
            }

            Count++;
            float outward = MathF.Abs(knee.X - hip.X) / thigh;
            var kind = outward >= SideFrom ? KickKind.Side : KickKind.Front;
            float power = Math.Clamp(lift / (KickFrom * 1.5f), 0.5f, 1f);
            return new Kick(t, Side, kind, power);
        }

        /// <summary>Learn the length of the thigh: the longest lately, slowly forgotten.</summary>
        private void Learn(double t, float thigh)
        {
            if (thigh <= 0f)
            {
                return;
            }

            if (float.IsNaN(_thigh) || thigh > _thigh)
            {
                _thigh = thigh;
            }
            else
            {
                double dt = Math.Max(0.0, t - _learnedAt);
                _thigh += (thigh - _thigh) * (float)(1.0 - Math.Exp(-dt / ForgetTau));
            }

            _learnedAt = t;
        }
    }
}  // namespace Auslender.Vision
