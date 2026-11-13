using System;
using System.Collections.Generic;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>Enumerate the punches.</summary>
    public enum PunchKind
    {
        /// <summary>A straight punch: the fist flies towards the camera, so its box grows.</summary>
        Straight,

        /// <summary>A hook: the fist swings across, towards the other side of the body.</summary>
        Hook,

        /// <summary>An uppercut: the fist rises fast.</summary>
        Uppercut,
    }

    /// <summary>A punch which a <see cref="PunchDetector"/> found.</summary>
    public readonly struct Punch
    {
        public readonly double Time;
        public readonly HandSide Side;
        public readonly PunchKind Kind;

        /// <summary>How hard the punch was, in [0, 1].</summary>
        public readonly float Power;

        public Punch(double time, HandSide side, PunchKind kind, float power)
        {
            Time = time;
            Side = side;
            Kind = kind;
            Power = power;
        }

        public override string ToString() => $"{Side} {Kind} {Power:F2} at {Time:F2}";
    }

    /// <summary>
    /// Find the punches of one hand from the hand detector, on every frame.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The camera sees the player from the front, so a straight punch hardly
    /// moves the fist in the picture: it flies towards the camera, and its box
    /// grows. We therefore look at a short window (<see cref="Window"/>) of the
    /// hand and compare how much it grew (straight), how far it swung across the
    /// body (hook) and how far it rose (uppercut), each against its own
    /// threshold, and take the strongest.
    /// </para>
    /// <para>
    /// The distances are in the unit of the player (about the width of the
    /// shoulders), and the positions in the pixels of the not mirrored frame.
    /// After a punch, the hand must come to rest or pull back before the next
    /// punch counts (<see cref="Rearm"/>), so that one punch counts once.
    /// </para>
    /// </remarks>
    public sealed class PunchDetector
    {
        public readonly HandSide Side;

        /// <summary>The window in which we measure the movement, in seconds.</summary>
        public double Window = 0.15;

        /// <summary>A straight punch grows the fist at least this much within the window (as a factor).</summary>
        public float StraightGrowth = 1.3f;

        /// <summary>A hook swings the fist at least this far across within the window, in units.</summary>
        public float HookAcross = 0.55f;

        /// <summary>An uppercut raises the fist at least this far within the window, in units.</summary>
        public float UppercutRise = 0.55f;

        /// <summary>
        /// A punch is thrown from above this far below the eyes, in units: a hand
        /// hanging down at the hip does not punch.
        /// </summary>
        public float GuardBelowEyes = 1.4f;

        /// <summary>After a punch, the next one counts once the fist shrank back by this factor, or after <see cref="Rearm"/>.</summary>
        public float PullBack = 0.9f;

        /// <summary>The next punch counts at the latest this long after the last one, in seconds.</summary>
        public double Rearm = 0.45;

        /// <summary>The next punch counts at the earliest this long after the last one, in seconds.</summary>
        public double Refractory = 0.2;

        private readonly List<(double T, float X, float Y, float Size)> _samples = new();

        private double _lastPunchAt = double.NegativeInfinity;
        private float _sizeAtPunch = float.NaN;
        private bool _armed = true;

        public PunchDetector(HandSide side)
        {
            Side = side;
        }

        /// <summary>How many punches were found so far.</summary>
        public int Count { get; private set; }

        /// <summary>Forget the hand, e.g., when the player steps out.</summary>
        public void Reset()
        {
            _samples.Clear();
            _armed = true;
            _lastPunchAt = double.NegativeInfinity;
            _sizeAtPunch = float.NaN;
        }

        /// <summary>
        /// Observe the hand at the time <paramref name="t"/>: its middle and its
        /// size (see <see cref="HandTracker.HandSize"/>) in pixels, the eyes and
        /// the unit of the player; return the punch if one was thrown.
        /// </summary>
        public Punch? Observe(double t, float x, float y, float size, float eyesY, float unit)
        {
            if (float.IsNaN(unit) || unit <= 1f || size <= 0f)
            {
                return null;
            }

            _samples.Add((t, x, y, size));
            while (_samples.Count > 0 && t - _samples[0].T > Window)
            {
                _samples.RemoveAt(0);
            }

            double since = t - _lastPunchAt;
            if (!_armed)
            {
                bool pulledBack = !float.IsNaN(_sizeAtPunch) && size <= _sizeAtPunch * PullBack;
                if ((pulledBack && since >= Refractory) || since >= Rearm)
                {
                    _armed = true;
                }
                else
                {
                    return null;
                }
            }

            if (_samples.Count < 2 || (y - eyesY) / unit > GuardBelowEyes)
            {
                return null;
            }

            // NOTE (mristin):
            // We compare the hand now with the smallest and the lowest it was in
            // the window, which holds also when the detector jitters at the start.
            float smallest = float.PositiveInfinity;
            float lowest = float.NegativeInfinity;
            float bodyX0 = float.NaN;
            foreach (var sample in _samples)
            {
                smallest = MathF.Min(smallest, sample.Size);
                lowest = MathF.Max(lowest, sample.Y);
            }

            bodyX0 = BodyX(_samples[0].X);

            float growth = size / smallest;
            float across = (BodyX(x) - bodyX0) / unit;
            if (Side == HandSide.Right)
            {
                across = -across;
            }

            float rise = (lowest - y) / unit;

            float straight = (growth - 1f) / (StraightGrowth - 1f);
            float hook = across / HookAcross;
            float uppercut = rise / UppercutRise;

            float best = MathF.Max(straight, MathF.Max(hook, uppercut));
            if (best < 1f)
            {
                return null;
            }

            PunchKind kind = straight >= hook && straight >= uppercut
                ? PunchKind.Straight
                : (hook >= uppercut ? PunchKind.Hook : PunchKind.Uppercut);

            _armed = false;
            _lastPunchAt = t;
            _sizeAtPunch = size;
            _samples.Clear();
            Count++;

            // NOTE (mristin):
            // Twice the threshold is a full-power punch.
            float power = Math.Clamp(best - 0.5f, 0.5f, 1.5f) / 1.5f;
            return new Punch(t, Side, kind, power);
        }

        /// <summary>The x in the terms of the player's body: positive to her right.</summary>
        private static float BodyX(float frameX) => -frameX;
    }
}  // namespace Auslender.Vision
