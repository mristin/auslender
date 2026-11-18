using System;
using System.Collections.Generic;

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
/// The chart of a rhythm level: the song's bars and their levels, and the
/// notes on its beats, section by section.
/// </summary>
/// <remarks>
/// <para>
/// A level gives its sections, each by the moves which it brings ("straight",
/// "hook", "uppercut", "duck", "jump", "slip", "cover"; in a run also "steer":
/// obstacles in two of the three lanes, to steer into the free one). After four bars to get
/// ready (no notes), each section has six bars: five with a note on their
/// first beat, and a breather; in a fight, the last bar of the last section is
/// the finisher (an uppercut) instead. Two bars end the song. The music grows
/// with the sections (see <see cref="Levels"/>).
/// </para>
/// <para>
/// A section of one move brings it in every bar (a punch with either hand, a
/// slip to either side, at random). A section of several moves brings each in
/// a block of two bars, never the same move twice in a row (the play-tests: a
/// new move in every bar, and two notes a bar, was too much). The notes are a
/// bar apart (the play-tests: a note on every beat, and on every other beat,
/// was too fast for the player and the vision). There are no kicks: the vision
/// saw them too late and too seldom.
/// </para>
/// <para>
/// <see cref="Curriculum"/> teaches all the moves one by one, then mixes them.
/// </para>
/// </remarks>
public static class Chart
{
    /// <summary>The bars to get ready, and the bars to end.</summary>
    public const int IntroBars = 4;

    public const int OutroBars = 2;

    /// <summary>The bars of a section.</summary>
    public const int SectionBars = 6;

    /// <summary>The bars of a block of the same move, in a section of several.</summary>
    public const int BlockBars = 2;

    /// <summary>The moves of a chart.</summary>
    public static readonly string[] Moves =
    {
        "straight", "hook", "uppercut", "duck", "jump", "slip", "cover", "steer",
    };

    /// <summary>
    /// The notes of a "steer" (in a run): the lane to be in, the others
    /// blocked.
    /// </summary>
    public static readonly string[] Lanes = { "lane_left", "lane_middle", "lane_right" };

    /// <summary>All the moves one by one, then mixed, twice.</summary>
    public static readonly string[] Curriculum =
    {
        "straight",
        "hook",
        "uppercut",
        "duck",
        "jump",
        "slip",
        "cover",
        "straight,hook,uppercut,duck,jump,slip,cover",
        "straight,hook,uppercut,duck,jump,slip,cover",
    };

    /// <summary>The level of the music in every bar of a song of the sections (see <see cref="BeatSynth"/>).</summary>
    public static int[] Levels(int sections)
    {
        var levels = new List<int>();
        for (int i = 0; i < IntroBars; i++)
        {
            levels.Add(0);
        }

        for (int section = 0; section < sections; section++)
        {
            // NOTE (mristin):
            // From 1 in the first section up to 6 in the last.
            int level = sections == 1 ? 3 : 1 + (int)Math.Round(5.0 * section / (sections - 1));
            for (int i = 0; i < SectionBars; i++)
            {
                levels.Add(level);
            }
        }

        for (int i = 0; i < OutroBars; i++)
        {
            levels.Add(0);
        }

        return levels.ToArray();
    }

    /// <summary>The section of a bar (-1 before the first, and after the last).</summary>
    public static int SectionOf(int bar, int sections)
    {
        int section = (bar - IntroBars) / SectionBars;
        return bar < IntroBars || section >= sections ? -1 : section;
    }

    /// <summary>Build the notes of the song, in the order of their beats.</summary>
    /// <param name="sections">The moves of each section, separated by ",".</param>
    /// <param name="seed">The seed of the picks.</param>
    /// <param name="finisher">Whether the last bar is the finisher (in a fight).</param>
    /// <param name="extra">
    /// Whether every second bar has a second note, on its third beat (a fight:
    /// a little more often than a run; two dodges in a row still keep four
    /// beats apart).
    /// </param>
    public static List<Note> Build(string[] sections, int seed, bool finisher, bool extra = false)
    {
        var random = new Random(seed);
        var notes = new List<Note>();
        string previous = "";
        string side = "left";
        for (int section = 0; section < sections.Length; section++)
        {
            string[] moves = sections[section].Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            foreach (string move in moves)
            {
                if (Array.IndexOf(Moves, move) < 0)
                {
                    throw new ArgumentException($"Unknown move {move} in section {section}", nameof(sections));
                }
            }

            for (int inSection = 0; inSection < SectionBars; inSection++)
            {
                int bar = IntroBars + section * SectionBars + inSection;
                bool last = inSection == SectionBars - 1;
                string move;
                if (last && finisher && section == sections.Length - 1)
                {
                    move = "uppercut";
                    side = "right";
                }
                else if (last)
                {
                    continue;
                }
                else if (moves.Length > 1 && inSection % BlockBars != 0)
                {
                    // NOTE (mristin):
                    // The same move again, in its block.
                    move = previous;
                }
                else
                {
                    do
                    {
                        move = moves[random.Next(moves.Length)];
                    }
                    while (moves.Length > 1 && move == previous);

                    side = random.Next(2) == 0 ? "left" : "right";
                }

                previous = move;
                // NOTE (mristin):
                // A section of one move alternates the sides at random, bar by
                // bar.
                if (moves.Length == 1 && !last)
                {
                    side = random.Next(2) == 0 ? "left" : "right";
                }

                Note note = move switch
                {
                    "slip" => new Note(bar * 4.0, side == "left" ? "slip_left" : "slip_right", ""),
                    "steer" => new Note(bar * 4.0, Lanes[random.Next(Lanes.Length)], ""),
                    "duck" or "jump" or "cover" => new Note(bar * 4.0, move, ""),
                    _ => new Note(bar * 4.0, move, side),
                };
                if (notes.Count == 0 || Fits(notes[^1], note))
                {
                    notes.Add(note);
                }

                if (extra && !last && inSection % 2 == 1)
                {
                    string again = random.Next(2) == 0 ? "left" : "right";
                    Note second = move switch
                    {
                        "slip" => new Note(bar * 4.0 + 2.0, again == "left" ? "slip_left" : "slip_right", ""),
                        "steer" => new Note(bar * 4.0 + 2.0, Lanes[random.Next(Lanes.Length)], ""),
                        "duck" or "jump" or "cover" => new Note(bar * 4.0 + 2.0, move, ""),
                        _ => new Note(bar * 4.0 + 2.0, move, again),
                    };
                    if (Fits(notes[^1], second))
                    {
                        notes.Add(second);
                    }
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
}
