using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Measure how far the player leans to the side, to slip a punch, against
    /// where she stood lately rather than against the home spot.
    /// </summary>
    /// <remarks>
    /// <para>
    /// On the recording of a fight (dev/moves/plans/fight.csv), the slips moved
    /// the head 1.2 to 2.4 units from where it was. But the player drifted
    /// half a unit off her home spot over two minutes, so against home she
    /// "slipped" all the time while she ducked, jumped or punched.
    /// </para>
    /// <para>
    /// So we follow where she stands with a slow baseline (the time constant
    /// <see cref="Tau"/>), which does not follow while she leans (beyond
    /// <see cref="Freeze"/>, so that a held slip stays a slip), unless she
    /// stays there longer than a slip lasts (<see cref="HoldMax"/>: she
    /// stepped, or the home spot was set again). The lean is the sideways
    /// offset against that baseline. On that recording, a slip from
    /// <see cref="SlipFrom"/> on found 12 of the 13 slips (the 13th hardly
    /// moved), and no false slip while she stood in her guard, covered,
    /// punched or ducked; turning the head to look around still leans a
    /// fifth of the time.
    /// </para>
    /// <para>
    /// The offsets are in units (about the width of the shoulders), positive to
    /// the player's right, as <see cref="RoomJoystick.Sideways"/>.
    /// </para>
    /// </remarks>
    public sealed class LeanGauge
    {
        /// <summary>The time constant of the baseline, in seconds.</summary>
        public double Tau = 2.0;

        /// <summary>The baseline holds still while the lean is beyond this, in units.</summary>
        public float Freeze = 0.3f;

        /// <summary>The baseline follows anyway once a lean was held this long, in seconds.</summary>
        public double HoldMax = 1.5;

        /// <summary>A lean beyond this, in units, is a slip.</summary>
        public float SlipFrom = 0.5f;

        /// <summary>Where the player stands lately, in units against home; NaN before the first observation.</summary>
        public float Baseline { get; private set; } = float.NaN;

        /// <summary>The lean against the baseline, in units, positive to the player's right.</summary>
        public float Lean { get; private set; }

        /// <summary>-1 while the player slips to her left, 1 to her right, else 0.</summary>
        public int Slip => Lean <= -SlipFrom ? -1 : (Lean >= SlipFrom ? 1 : 0);

        private double _lastTime = double.NaN;
        private double _leaningSince = double.NaN;

        /// <summary>Observe the sideways offset (in units) at the time (in seconds).</summary>
        public void Observe(double t, float sideways)
        {
            if (float.IsNaN(sideways))
            {
                return;
            }

            if (float.IsNaN(Baseline))
            {
                Baseline = sideways;
                _lastTime = t;
                Lean = 0f;
                return;
            }

            double dt = Math.Max(0.0, t - _lastTime);
            _lastTime = t;
            float lean = sideways - Baseline;
            if (Math.Abs(lean) < Freeze)
            {
                _leaningSince = double.NaN;
            }
            else if (double.IsNaN(_leaningSince))
            {
                _leaningSince = t;
            }

            if (double.IsNaN(_leaningSince) || t - _leaningSince > HoldMax)
            {
                Baseline += (float)(1.0 - Math.Exp(-dt / Tau)) * lean;
                lean = sideways - Baseline;
            }

            Lean = lean;
        }

        /// <summary>Forget the baseline, e.g., when the home spot is set again.</summary>
        public void Reset()
        {
            Baseline = float.NaN;
            Lean = 0f;
            _lastTime = double.NaN;
            _leaningSince = double.NaN;
        }
    }
}
