using System;
using System.Collections.Generic;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Tell from the knees whether the player walks in place, and how fast.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Walking in place lifts the knees in turns. We follow how much higher the
    /// left knee is than the right one, in thighs (from the hip to the knee):
    /// on the recording of a player (dev/moves/), it swung by about ±0.7 while
    /// walking and stayed within ±0.05 while standing and punching. The head
    /// hardly bobs (0.03 units), so it does not tell.
    /// </para>
    /// <para>
    /// A window of <see cref="Window"/> seconds is walking when the knees
    /// alternated in it: the left knee was up by <see cref="StepFrom"/> and the
    /// right one, too. The speed grows with the swing and with the cadence (how
    /// often a knee comes up), and fades out over <see cref="FadeOut"/> once
    /// the knees stop.
    /// </para>
    /// </remarks>
    public sealed class WalkMeter
    {
        /// <summary>The window in which the knees must alternate, in seconds.</summary>
        public double Window = 1.6;

        /// <summary>A knee up by this share of the thigh above the other is a step.</summary>
        public float StepFrom = 0.25f;

        /// <summary>The swing of the knees at which the speed is full.</summary>
        public float FullSwing = 0.8f;

        /// <summary>The steps per second at which the speed is full (each knee counts).</summary>
        public float FullCadence = 2.5f;

        /// <summary>The speed fades out over this long after the knees stop, in seconds.</summary>
        public double FadeOut = 0.5;

        /// <summary>Use only the key points of at least this score.</summary>
        public float KeypointThreshold = 0.4f;

        private readonly List<(double T, float Lift)> _lifts = new();
        private readonly List<double> _steps = new();
        private int _lastStepSide;
        private double _walkingUntil = double.NegativeInfinity;
        private float _target;
        private float _thigh = float.NaN;

        /// <summary>How fast the player walks, in [0, 1].</summary>
        public float Speed { get; private set; }

        /// <summary>Whether the knees alternated lately.</summary>
        public bool Walking { get; private set; }

        /// <summary>The steps per second lately (each knee counts), or 0.</summary>
        public float Cadence { get; private set; }

        /// <summary>How much higher the left knee is than the right one now, in thighs; NaN if unknown.</summary>
        public float Lift { get; private set; } = float.NaN;

        /// <summary>How many steps were counted so far.</summary>
        public int Steps { get; private set; }

        public void Reset()
        {
            _lifts.Clear();
            _steps.Clear();
            _lastStepSide = 0;
            _walkingUntil = double.NegativeInfinity;
            _target = 0f;
            _thigh = float.NaN;
            Speed = 0f;
            Walking = false;
            Cadence = 0f;
            Lift = float.NaN;
            Steps = 0;
        }

        /// <summary>Observe the pose of the player at the time <paramref name="t"/>.</summary>
        public void Observe(double t, Pose pose)
        {
            float th = KeypointThreshold;
            if (!pose.Has(BodyPart.LeftKnee, th) || !pose.Has(BodyPart.RightKnee, th)
                || !pose.Has(BodyPart.LeftHip, th) || !pose.Has(BodyPart.RightHip, th))
            {
                Lift = float.NaN;
                return;
            }

            float thigh = 0.5f * (
                pose[BodyPart.LeftKnee].Y - pose[BodyPart.LeftHip].Y
                + pose[BodyPart.RightKnee].Y - pose[BodyPart.RightHip].Y
            );

            // NOTE (mristin):
            // The thigh of a standing player is the longest; a lifted knee
            // shortens it, so we learn it as the longest lately.
            if (float.IsNaN(_thigh) || thigh > _thigh)
            {
                _thigh = thigh;
            }
            else
            {
                _thigh += (thigh - _thigh) * 0.01f;
            }

            if (_thigh <= 1f)
            {
                return;
            }

            float lift = (pose[BodyPart.RightKnee].Y - pose[BodyPart.LeftKnee].Y) / _thigh;
            Lift = lift;
            _lifts.Add((t, lift));
            while (_lifts.Count > 0 && t - _lifts[0].T > Window)
            {
                _lifts.RemoveAt(0);
            }

            // NOTE (mristin):
            // A step counts when a knee comes up, and only if the other knee
            // came up before it, so that one knee held up is one step.
            int side = lift >= StepFrom ? 1 : (lift <= -StepFrom ? -1 : 0);
            if (side != 0 && side != _lastStepSide)
            {
                _lastStepSide = side;
                _steps.Add(t);
                Steps++;
            }

            while (_steps.Count > 0 && t - _steps[0] > Window * 2.0)
            {
                _steps.RemoveAt(0);
            }

            float high = float.NegativeInfinity;
            float low = float.PositiveInfinity;
            foreach (var (_, value) in _lifts)
            {
                high = MathF.Max(high, value);
                low = MathF.Min(low, value);
            }

            bool alternated = high >= StepFrom && low <= -StepFrom;
            if (alternated)
            {
                _walkingUntil = t + FadeOut;
                float swing = (high - low) * 0.5f;
                Cadence = _steps.Count >= 2
                    ? (float)((_steps.Count - 1) / Math.Max(1e-3, _steps[^1] - _steps[0]))
                    : 0f;
                float bySwing = Math.Clamp(swing / FullSwing, 0f, 1f);
                float byCadence = Math.Clamp(Cadence / FullCadence, 0.3f, 1f);
                _target = Math.Clamp(0.25f + 0.75f * bySwing * byCadence, 0f, 1f);
            }
        }

        /// <summary>Let the speed follow the walking, and fade out when it stops.</summary>
        public void Update(double t, double delta)
        {
            Walking = t <= _walkingUntil;
            float target = Walking ? _target : 0f;
            float rate = (float)Math.Min(1.0, delta / (target > Speed ? 0.25 : FadeOut * 0.5));
            Speed += (target - Speed) * rate;
            if (!Walking)
            {
                Cadence = 0f;
            }
        }
    }
}  // namespace Auslender.Vision
