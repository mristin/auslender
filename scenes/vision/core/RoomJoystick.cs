using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Turn the room into a joystick: the player stands on a home spot, and a
    /// step to the left, to the right, towards the camera or away from it moves
    /// the boxer in the ring; back on the home spot, he stands.
    /// </summary>
    /// <remarks>
    /// <para>
    /// We follow the head on every frame of the face tracker (see
    /// <see cref="HeadGauge"/>). The sideways offset is how far the head moved
    /// from home, in the unit of the player (about the width of the shoulders),
    /// so that it does not matter how far from the camera the player stands. The
    /// depth is how much bigger the head looks than at home: stepping towards the
    /// camera makes the eyes farther apart. We take its logarithm, so that a step
    /// forward and a step back weigh the same.
    /// </para>
    /// <para>
    /// The size of the head alone is easily fooled: the eyes come closer as the
    /// player turns her head. So the depth combines several sizes of the player
    /// (see <see cref="DepthCues"/>, observed with <see cref="ObserveCues"/>):
    /// each is compared with its size at home, and the depth is the median of
    /// them, which one or two fooled sizes do not move. Without any cues (e.g.,
    /// without the face tracker), the depth comes from the unit alone.
    /// </para>
    /// <para>
    /// The positions are in the pixels of the (not mirrored) frame. The stick is
    /// in the terms of the player's body: x is positive to her right, and y is
    /// positive forward, towards the camera.
    /// </para>
    /// <para>
    /// A dead zone around home lets the player box, lean and duck on the spot
    /// without moving the boxer; beyond it, the stick ramps up to full.
    /// </para>
    /// </remarks>
    public sealed class RoomJoystick
    {
        /// <summary>The sideways offset (in units) up to which the boxer stands.</summary>
        public float DeadSideways = 0.4f;

        /// <summary>The sideways offset (in units) from which the boxer moves at full speed.</summary>
        public float FullSideways = 1.0f;

        /// <summary>The depth (the logarithm of the size of the head against home) up to which the boxer stands.</summary>
        public float DeadDepth = 0.07f;

        /// <summary>
        /// The depth from which the boxer moves at full speed: from 2.5 m, half
        /// a meter forward makes the head 1.25 times bigger (0.22), and half a
        /// meter back 0.83 times (-0.18).
        /// </summary>
        public float FullDepth = 0.18f;

        /// <summary>The time constant of smoothing the head, in seconds.</summary>
        public double PositionTau = 0.06;

        /// <summary>
        /// The time constant of smoothing the size of the head, in seconds:
        /// slower than the position, since the size jitters more.
        /// </summary>
        public double SizeTau = 0.15;

        /// <summary>A cue counts this long after it was measured, in seconds (the pose comes only a few times a second).</summary>
        public double CueStale = 0.5;

        /// <summary>The player must hold still this long (in seconds) for the home spot to be set.</summary>
        public double CalibrationHold = 1.0;

        /// <summary>The head moves at most this far (in units) while the player holds still.</summary>
        public float StillTolerance = 0.2f;

        /// <summary>The head counts as lost after this many seconds without a measure.</summary>
        public double LostAfter = 0.3;

        /// <summary>A head this far (in units) below home ducks.</summary>
        public float DuckFrom = 0.45f;

        /// <summary>
        /// A head this far (in units) above home jumps; in The Steppe Rescue,
        /// children's jumps rose 0.86 units and more, and their bouncing squats
        /// at most 0.46.
        /// </summary>
        public float JumpFrom = 0.6f;

        /// <summary>After a jump, the next one counts once the head came down below this (in units above home).</summary>
        public float LandedBelow = 0.3f;

        /// <summary>Whether the home spot is set.</summary>
        public bool Calibrated { get; private set; }

        /// <summary>The home of the head in the frame (pixels), or NaN.</summary>
        public float HomeX { get; private set; } = float.NaN;

        public float HomeY { get; private set; } = float.NaN;

        /// <summary>The unit of the player at home (pixels), or NaN.</summary>
        public float HomeUnit { get; private set; } = float.NaN;

        /// <summary>The sideways offset from home in units, positive to the player's right; 0 before the calibration.</summary>
        public float Sideways { get; private set; }

        /// <summary>The depth against home, positive towards the camera; 0 before the calibration.</summary>
        public float Depth { get; private set; }

        /// <summary>How far the head is below home, in units (positive down); 0 before the calibration.</summary>
        public float Down { get; private set; }

        /// <summary>The stick: x to the player's right, y forward, each in [-1, 1].</summary>
        public (float X, float Y) Stick { get; private set; }

        /// <summary>Whether the player ducks now: her head is clearly below home.</summary>
        public bool Ducking => Calibrated && Down >= DuckFrom;

        /// <summary>Whether the player is in a jump now.</summary>
        public bool Jumping { get; private set; }

        /// <summary>How many jumps were found so far.</summary>
        public int Jumps { get; private set; }

        /// <summary>
        /// How far the calibration got, in [0, 1]: how long the player has held
        /// still, as a share of <see cref="CalibrationHold"/>.
        /// </summary>
        public float CalibrationProgress { get; private set; }

        private float _x = float.NaN;
        private float _y = float.NaN;
        private float _logUnit = float.NaN;
        private double _measuredAt = double.NaN;

        private readonly float[] _cueLog = new float[DepthCues.Count];
        private readonly double[] _cueAt = new double[DepthCues.Count];
        private readonly float[] _cueHome = new float[DepthCues.Count];

        private double _stillSince = double.NaN;
        private float _stillX;
        private float _stillY;

        public RoomJoystick()
        {
            Array.Fill(_cueLog, float.NaN);
            Array.Fill(_cueAt, double.NaN);
            Array.Fill(_cueHome, float.NaN);
        }

        /// <summary>
        /// How much the cue grew since home (the logarithm of the ratio), as of
        /// the time <paramref name="t"/>; NaN if unknown or stale.
        /// </summary>
        public float CueDepth(DepthCue cue, double t)
        {
            int i = (int)cue;
            if (float.IsNaN(_cueHome[i]) || double.IsNaN(_cueAt[i]) || t - _cueAt[i] > CueStale)
            {
                return float.NaN;
            }

            return _cueLog[i] - _cueHome[i];
        }

        /// <summary>
        /// Observe the sizes of the player measured at the time
        /// <paramref name="t"/>; the NaN ones were not measured, and keep their
        /// last value.
        /// </summary>
        public void ObserveCues(double t, DepthCues cues)
        {
            for (int i = 0; i < DepthCues.Count; i++)
            {
                float size = cues.Sizes[i];
                if (float.IsNaN(size) || size <= 1f)
                {
                    continue;
                }

                float log = MathF.Log(size);
                if (float.IsNaN(_cueLog[i]) || double.IsNaN(_cueAt[i]) || t - _cueAt[i] > 1.0)
                {
                    _cueLog[i] = log;
                }
                else
                {
                    double dt = Math.Max(0.0, t - _cueAt[i]);
                    _cueLog[i] += (log - _cueLog[i]) * (float)(1.0 - Math.Exp(-dt / SizeTau));
                }

                _cueAt[i] = Math.Max(double.IsNaN(_cueAt[i]) ? t : _cueAt[i], t);

                // NOTE (mristin):
                // A cue first seen after the calibration (e.g., the hips, once the
                // player stepped back) gets its home from the others.
                if (Calibrated && float.IsNaN(_cueHome[i]))
                {
                    float depth = FusedDepth(t, exclude: i);
                    if (!float.IsNaN(depth))
                    {
                        _cueHome[i] = _cueLog[i] - depth;
                    }
                }
            }
        }

        /// <summary>The median of the depths of the fresh cues with a home, or NaN if none.</summary>
        private float FusedDepth(double t, int exclude = -1)
        {
            Span<float> depths = stackalloc float[DepthCues.Count];
            int count = 0;
            for (int i = 0; i < DepthCues.Count; i++)
            {
                if (i == exclude)
                {
                    continue;
                }

                float depth = CueDepth((DepthCue)i, t);
                if (!float.IsNaN(depth))
                {
                    depths[count++] = depth;
                }
            }

            if (count == 0)
            {
                return float.NaN;
            }

            var used = depths.Slice(0, count);
            used.Sort();
            return count % 2 == 1 ? used[count / 2] : (used[count / 2 - 1] + used[count / 2]) * 0.5f;
        }

        /// <summary>Forget the home spot; the player sets it again by holding still.</summary>
        public void Recalibrate()
        {
            Calibrated = false;
            HomeX = HomeY = HomeUnit = float.NaN;
            Array.Fill(_cueHome, float.NaN);
            _stillSince = double.NaN;
            CalibrationProgress = 0f;
            Sideways = Depth = Down = 0f;
            Stick = (0f, 0f);
            Jumping = false;
        }

        /// <summary>Forget everything, e.g., when another player steps in.</summary>
        public void Reset()
        {
            Recalibrate();
            Jumps = 0;
            _x = _y = _logUnit = float.NaN;
            _measuredAt = double.NaN;
            Array.Fill(_cueLog, float.NaN);
            Array.Fill(_cueAt, double.NaN);
        }

        /// <summary>
        /// Observe the head at the time <paramref name="t"/>: the point between
        /// the eyes (pixels of the not mirrored frame) and the unit measured in
        /// this frame alone (see <see cref="HeadGauge.RawUnit"/>).
        /// </summary>
        public void Observe(double t, float x, float y, float rawUnit)
        {
            if (float.IsNaN(x) || float.IsNaN(y) || float.IsNaN(rawUnit) || rawUnit <= 1f)
            {
                return;
            }

            float logUnit = MathF.Log(rawUnit);
            if (double.IsNaN(_measuredAt) || t - _measuredAt > LostAfter * 2.0)
            {
                _x = x;
                _y = y;
                _logUnit = logUnit;
            }
            else
            {
                double dt = Math.Max(0.0, t - _measuredAt);
                float a = (float)(1.0 - Math.Exp(-dt / PositionTau));
                float b = (float)(1.0 - Math.Exp(-dt / SizeTau));
                _x += (x - _x) * a;
                _y += (y - _y) * a;
                _logUnit += (logUnit - _logUnit) * b;
            }

            _measuredAt = t;
            float unit = MathF.Exp(_logUnit);

            if (!Calibrated)
            {
                Settle(t, unit);
            }

            if (Calibrated)
            {
                float fused = FusedDepth(t);
                Depth = float.IsNaN(fused) ? _logUnit - MathF.Log(HomeUnit) : fused;

                // NOTE (mristin):
                // The unit follows the depth, too, so that turning the head does
                // not change how far a step to the side goes.
                unit = HomeUnit * MathF.Exp(Depth);

                // NOTE (mristin):
                // In the not mirrored frame, the player's right is to the left.
                Sideways = (HomeX - _x) / unit;
                Down = (_y - HomeY) / unit;
                Stick = (Ramp(Sideways, DeadSideways, FullSideways), Ramp(Depth, DeadDepth, FullDepth));

                // NOTE (mristin):
                // We take the raw height, not the smoothed, so that a jump counts at once.
                float up = (HomeY - y) / unit;
                if (Jumping)
                {
                    Jumping = up >= LandedBelow;
                }
                else if (up >= JumpFrom)
                {
                    Jumping = true;
                    Jumps++;
                }
            }
        }

        /// <summary>Let go of the stick if the head is lost.</summary>
        public void Update(double t)
        {
            if (double.IsNaN(_measuredAt) || t - _measuredAt > LostAfter)
            {
                Stick = (0f, 0f);
                _stillSince = double.NaN;
                if (!Calibrated)
                {
                    CalibrationProgress = 0f;
                }
            }
        }

        /// <summary>Whether the head was measured lately.</summary>
        public bool Sees(double t) => !double.IsNaN(_measuredAt) && t - _measuredAt <= LostAfter;

        /// <summary>Set the home spot once the player held still long enough.</summary>
        private void Settle(double t, float unit)
        {
            float moved = double.IsNaN(_stillSince)
                ? float.PositiveInfinity
                : MathF.Sqrt((_x - _stillX) * (_x - _stillX) + (_y - _stillY) * (_y - _stillY)) / unit;
            if (moved > StillTolerance)
            {
                _stillSince = t;
                _stillX = _x;
                _stillY = _y;
                CalibrationProgress = 0f;
                return;
            }

            CalibrationProgress = (float)Math.Clamp((t - _stillSince) / CalibrationHold, 0.0, 1.0);
            if (CalibrationProgress >= 1f)
            {
                Calibrated = true;
                HomeX = _x;
                HomeY = _y;
                HomeUnit = unit;
                for (int i = 0; i < DepthCues.Count; i++)
                {
                    bool fresh = !double.IsNaN(_cueAt[i]) && t - _cueAt[i] <= CueStale;
                    _cueHome[i] = fresh ? _cueLog[i] : float.NaN;
                }
            }
        }

        /// <summary>Map the offset to [-1, 1]: 0 within the dead zone, ramping up to 1 at full.</summary>
        public static float Ramp(float offset, float dead, float full)
        {
            float magnitude = MathF.Abs(offset);
            if (magnitude <= dead)
            {
                return 0f;
            }

            float value = Math.Clamp((magnitude - dead) / Math.Max(1e-6f, full - dead), 0f, 1f);
            return MathF.Sign(offset) * value;
        }
    }
}  // namespace Auslender.Vision
