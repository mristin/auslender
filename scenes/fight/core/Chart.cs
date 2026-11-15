using System;
using System.Collections.Generic;
using System.Globalization;

namespace Auslender.Fight;

/// <summary>A note of the chart: what the player does on which beat.</summary>
/// <param name="Beat">The beat (from the start of the song) on which it arrives.</param>
/// <param name="Kind">
/// A punch of the player ("straight", "hook", "uppercut"),
/// or how he dodges an attack ("slip_left", "slip_right", "duck", "jump",
/// "cover").
/// </param>
/// <param name="Side">"left" or "right" for a punch, "" for a dodge.</param>
public sealed record Note(double Beat, string Kind, string Side)
{
    /// <summary>Whether the player dodges this note (else he strikes it).</summary>
    public bool IsDodge => Side == "";
}

/// <summary>
/// The chart of the rhythm fight: the song's bars and their levels, and the
/// notes on its beats, section by section.
/// </summary>
/// <remarks>
/// <para>
/// The song teaches the moves one by one: after four bars to get ready (no
/// notes), each section brings one move only (see <see cref="Sections"/>):
/// jabs, hooks, uppercuts, ducks, jumps, slips and the cover; then a section
/// mixes them, one a bar, and the final round brings two a bar; then two bars
/// to end. A section has six bars: five with a note on its first beat, and a
/// breather, but in the final round, where the last bar is the finisher. The
/// music grows with the sections (see <see cref="Levels"/>).
/// </para>
/// <para>
/// Each bar takes one pattern of its section (picked at random, sometimes
/// mirrored left for right). The notes are two beats apart at the least
/// (the play-tests: a note on every beat, and then on every other, was too
/// fast for the player and the vision), and four between two dodges, which
/// take longer to come back from. The notes which break these rules where two
/// patterns meet are dropped. There are no kicks: the vision saw them too
/// late and too seldom.
/// </para>
/// </remarks>
public static class Chart
{
    /// <summary>The bars to get ready, and the bars to end.</summary>
    public const int IntroBars = 4;

    public const int OutroBars = 2;

    /// <summary>The bars of a section.</summary>
    public const int SectionBars = 6;

    /// <summary>The sections: their titles, as the game announces them.</summary>
    public static readonly string[] Sections =
    {
        "JABS",
        "HOOKS",
        "UPPERCUTS",
        "DUCK",
        "JUMP",
        "SLIP",
        "COVER",
        "MIX IT UP",
        "FINAL ROUND",
    };

    // NOTE (mristin):
    // How much of the music plays in each section (see BeatSynth).
    private static readonly int[] MusicLevels = { 1, 2, 2, 3, 3, 4, 4, 5, 6 };

    // NOTE (mristin):
    // The patterns of a bar, by section: "<beat> <kind> [<side>]", separated
    // by ";". Left and right are the player's.
    private static readonly string[][] Patterns =
    {
        new[] { "0 straight left", "0 straight right" },
        new[] { "0 hook left", "0 hook right" },
        new[] { "0 uppercut left", "0 uppercut right" },
        new[] { "0 duck" },
        new[] { "0 jump" },
        new[] { "0 slip_left", "0 slip_right" },
        new[] { "0 cover" },
        new[]
        {
            "0 straight left", "0 hook right", "0 uppercut left", "0 duck", "0 jump", "0 slip_right",
            "0 cover",
        },
        new[]
        {
            "0 straight left; 2 hook right",
            "0 slip_right; 2 hook left",
            "0 duck; 2 uppercut right",
            "0 cover; 2 straight left",
            "0 jump; 2 straight right",
            "0 uppercut left; 2 uppercut right",
        },
    };

    /// <summary>The level of the music in every bar of the song (see <see cref="BeatSynth"/>).</summary>
    public static int[] Levels()
    {
        var levels = new List<int>();
        for (int i = 0; i < IntroBars; i++)
        {
            levels.Add(0);
        }

        for (int section = 0; section < Sections.Length; section++)
        {
            for (int i = 0; i < SectionBars; i++)
            {
                levels.Add(MusicLevels[section]);
            }
        }

        for (int i = 0; i < OutroBars; i++)
        {
            levels.Add(0);
        }

        return levels.ToArray();
    }

    /// <summary>The section of a bar (-1 before the first, and after the last).</summary>
    public static int SectionOf(int bar)
    {
        int section = (bar - IntroBars) / SectionBars;
        return bar < IntroBars || section >= Sections.Length ? -1 : section;
    }

    /// <summary>Build the notes of the song, in the order of their beats.</summary>
    /// <param name="seed">The seed of the patterns' picks.</param>
    public static List<Note> Build(int seed)
    {
        var random = new Random(seed);
        int bars = Levels().Length;
        var notes = new List<Note>();
        for (int bar = 0; bar < bars; bar++)
        {
            int section = SectionOf(bar);
            if (section < 0)
            {
                continue;
            }

            bool last = (bar - IntroBars) % SectionBars == SectionBars - 1;
            string pattern;
            if (last && section == Sections.Length - 1)
            {
                pattern = "0 uppercut right";
            }
            else if (last)
            {
                continue;
            }
            else
            {
                string[] choices = Patterns[section];
                pattern = choices[random.Next(choices.Length)];
            }

            bool mirrored = random.Next(2) == 1;
            foreach (Note note in Parse(pattern, bar * 4.0, mirrored))
            {
                if (notes.Count == 0 || Fits(notes[^1], note))
                {
                    notes.Add(note);
                }
            }
        }

        return notes;
    }

    /// <summary>Whether the note may follow the one before it.</summary>
    public static bool Fits(Note before, Note next)
    {
        double gap = next.Beat - before.Beat;
        return gap >= (next.IsDodge && before.IsDodge ? 4.0 : 2.0);
    }

    private static IEnumerable<Note> Parse(string pattern, double start, bool mirrored)
    {
        foreach (string part in pattern.Split(';'))
        {
            string[] words = part.Trim().Split(' ');
            double beat = start + double.Parse(words[0], CultureInfo.InvariantCulture);
            string kind = words[1];
            string side = words.Length > 2 ? words[2] : "";
            if (mirrored)
            {
                side = side switch { "left" => "right", "right" => "left", _ => side };
                kind = kind switch { "slip_left" => "slip_right", "slip_right" => "slip_left", _ => kind };
            }

            yield return new Note(beat, kind, side);
        }
    }
}
