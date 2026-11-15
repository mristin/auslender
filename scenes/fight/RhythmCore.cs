using Godot;

using Auslender.Fight;

/// <summary>
/// Bring the chart and the synthesized music of the rhythm fight (see
/// <see cref="Chart"/> and <see cref="BeatSynth"/>) to GDScript.
/// </summary>
public partial class RhythmCore : RefCounted
{
    /// <summary>The samples per second of the music and the sounds.</summary>
    public int SampleRate() => BeatSynth.SampleRate;

    /// <summary>The bars to get ready before the first section.</summary>
    public int IntroBars() => Chart.IntroBars;

    /// <summary>The level of every bar of the song.</summary>
    public int[] Levels() => Chart.Levels();

    /// <summary>The titles of the sections.</summary>
    public string[] Sections() => Chart.Sections;

    /// <summary>The section of a bar (-1 outside of them).</summary>
    public int SectionOf(int bar) => Chart.SectionOf(bar);

    /// <summary>The notes: each a dictionary of "beat", "kind" and "side".</summary>
    public Godot.Collections.Array<Godot.Collections.Dictionary> Notes(int seed)
    {
        var notes = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (Note note in Chart.Build(seed))
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

    /// <summary>The song, as 16-bit little-endian mono samples.</summary>
    public byte[] Song(double bpm, int seed) => ToBytes(BeatSynth.RenderSong(bpm, Chart.Levels(), seed));

    /// <summary>A sound (see <see cref="BeatSynth.RenderSound"/>), as the song.</summary>
    public byte[] Sound(string name) => ToBytes(BeatSynth.RenderSound(name));

    private static byte[] ToBytes(short[] samples)
    {
        var bytes = new byte[samples.Length * 2];
        System.Buffer.BlockCopy(samples, 0, bytes, 0, bytes.Length);
        return bytes;
    }
}
