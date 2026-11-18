using Godot;

using Auslender.Fight;

/// <summary>
/// Bring the chart and the synthesized music of the rhythm levels (see
/// <see cref="Chart"/> and <see cref="BeatSynth"/>) to GDScript.
/// </summary>
public partial class RhythmCore : RefCounted
{
    /// <summary>The samples per second of the music and the sounds.</summary>
    public int SampleRate() => BeatSynth.SampleRate;

    /// <summary>The bars to get ready before the first section.</summary>
    public int IntroBars() => Chart.IntroBars;

    /// <summary>The bars of a section.</summary>
    public int SectionBars() => Chart.SectionBars;

    /// <summary>The level of every bar of a song of the sections.</summary>
    public int[] Levels(int sections) => Chart.Levels(sections);

    /// <summary>The section of a bar (-1 outside of them).</summary>
    public int SectionOf(int bar, int sections) => Chart.SectionOf(bar, sections);

    /// <summary>
    /// The notes of the sections (see <see cref="Chart.Build"/>): each a
    /// dictionary of "beat", "kind" and "side".
    /// </summary>
    public Godot.Collections.Array<Godot.Collections.Dictionary> Notes(
        string[] sections, int seed, bool finisher, bool extra)
    {
        var notes = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (Note note in Chart.Build(sections, seed, finisher, extra))
        {
            notes.Add(new Godot.Collections.Dictionary
            {
                { "beat", note.Beat },
                { "kind", note.Kind },
                { "side", note.Side },
            });
        }

        return notes;
    }

    /// <summary>
    /// The song of the sections, as 16-bit little-endian mono samples, at the
    /// tempo, in the chord progression, moved by the semitones.
    /// </summary>
    public byte[] Song(double bpm, int sections, int seed, int progression, int transpose) =>
        ToBytes(BeatSynth.RenderSong(bpm, Chart.Levels(sections), seed, progression, transpose));

    /// <summary>A sound (see <see cref="BeatSynth.RenderSound"/>), as the song.</summary>
    public byte[] Sound(string name) => ToBytes(BeatSynth.RenderSound(name));

    private static byte[] ToBytes(short[] samples)
    {
        var bytes = new byte[samples.Length * 2];
        System.Buffer.BlockCopy(samples, 0, bytes, 0, bytes.Length);
        return bytes;
    }
}
