using System;
using System.Collections.Generic;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Find the punches of one arm from the body pose: the wrist shoots up from
    /// the guard.
    /// </summary>
    /// <remarks>
    /// <para>
    /// On the recording of a player (dev/moves/), each punch thrown at the
    /// camera showed as the wrist rising against its shoulder by a third of the
    /// torso and more within a fraction of a second, from the guard at about
    /// the height of the shoulder; walking in place, ducking and twisting never
    /// did it. The growth of the box of the fist (see
    /// <see cref="PunchDetector"/>) jittered too much at 15 frames a second.
    /// </para>
    /// <para>
    /// We measure the height of the wrist against the shoulder in torsos (from
    /// the middle of the shoulders to the middle of the hips), and find a punch
    /// when it rose by <see cref="Rise"/> from its lowest within the last
    /// <see cref="Window"/> seconds; the next punch counts once the wrist came
    /// down again by <see cref="Rearm"/>.
    /// </para>
    /// </remarks>
    public sealed class PosePunchDetector
    {
        public readonly HandSide Side;

        /// <summary>A punch raises the wrist by this many torsos.</summary>
        public float Rise = 0.35f;

        /// <summary>... within this many seconds.</summary>
        public double Window = 0.3;

        /// <summary>The next punch counts once the wrist came down by this many torsos.</summary>
        public float Rearm = 0.15f;

        /// <summary>Use only the key points of at least this score.</summary>
        public float KeypointThreshold = 0.4f;

        private readonly List<(double T, float Y)> _heights = new();
        private bool _armed = true;
        private float _top = float.NaN;

        public PosePunchDetector(HandSide side)
        {
            Side = side;
        }

        /// <summary>How many punches were found so far.</summary>
        public int Count { get; private set; }

        public void Reset()
        {
            _heights.Clear();
            _armed = true;
            _top = float.NaN;
        }

        /// <summary>Observe the pose at the time <paramref name="t"/>; return the punch if one was thrown.</summary>
        public Punch? Observe(double t, Pose pose)
        {
            bool left = Side == HandSide.Left;
            var wristPart = left ? BodyPart.LeftWrist : BodyPart.RightWrist;
            var shoulderPart = left ? BodyPart.LeftShoulder : BodyPart.RightShoulder;
            float th = KeypointThreshold;
            if (!pose.Has(wristPart, th) || !pose.Has(BodyPart.LeftShoulder, th) || !pose.Has(BodyPart.RightShoulder, th)
                || !pose.Has(BodyPart.LeftHip, th) || !pose.Has(BodyPart.RightHip, th))
            {
                return null;
            }

            var ls = pose[BodyPart.LeftShoulder];
            var rs = pose[BodyPart.RightShoulder];
            var lh = pose[BodyPart.LeftHip];
            var rh = pose[BodyPart.RightHip];
            float dx = (ls.X + rs.X - lh.X - rh.X) * 0.5f;
            float dy = (ls.Y + rs.Y - lh.Y - rh.Y) * 0.5f;
            float torso = MathF.Sqrt(dx * dx + dy * dy);
            if (torso <= 1f)
            {
                return null;
            }

            // NOTE (mristin):
            // Up is positive: how far the wrist is above its shoulder.
            float height = (pose[shoulderPart].Y - pose[wristPart].Y) / torso;
            _heights.Add((t, height));
            while (_heights.Count > 0 && t - _heights[0].T > Window)
            {
                _heights.RemoveAt(0);
            }

            if (!_armed)
            {
                _top = MathF.Max(_top, height);
                if (_top - height >= Rearm)
                {
                    _armed = true;
                }

                return null;
            }

            float lowest = float.PositiveInfinity;
            foreach (var (_, value) in _heights)
            {
                lowest = MathF.Min(lowest, value);
            }

            float rise = height - lowest;
            if (rise < Rise)
            {
                return null;
            }

            _armed = false;
            _top = height;
            _heights.Clear();
            Count++;
            float power = Math.Clamp(rise / (Rise * 2f), 0.5f, 1f);
            return new Punch(t, Side, PunchKind.Straight, power);
        }
    }
}  // namespace Auslender.Vision
