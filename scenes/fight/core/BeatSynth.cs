using System;

namespace Auslender.Fight;

/// <summary>
/// Synthesize the music of the rhythm fight and its sounds, as 16-bit mono
/// samples: no audio files, so that all of it is our own.
/// </summary>
/// <remarks>
/// <para>
/// The song is in A minor (Am, F, C, G: one chord per bar), bar by bar; the
/// level of each bar says how much plays: 0 the kick and the hi-hats over a
/// pad, then the bass, the snare, an arpeggio, four on the floor, and at the
/// top sixteenth hi-hats. The last bar of every eight has a snare fill, which
/// leads into the next section. The kick falls on the beats, so that the beat
/// can be heard where the notes of the fight arrive.
/// </para>
/// <para>
/// The voices are simple on purpose (a sine with a falling pitch for the kick,
/// noise for the snare and the hi-hats, a filtered saw for the bass and a
/// square for the arpeggio), and the mix is soft-clipped.
/// </para>
/// </remarks>
public static class BeatSynth
{
    /// <summary>The samples per second.</summary>
    public const int SampleRate = 22050;

    // NOTE (mristin):
    // MIDI notes: the roots of Am, F, C and G (in the bass), and their chords.
    private static readonly int[] Roots = { 45, 41, 48, 43 };

    private static readonly int[][] Chords =
    {
        new[] { 57, 60, 64 },
        new[] { 53, 57, 60 },
        new[] { 55, 60, 64 },
        new[] { 55, 59, 62 },
    };

    /// <summary>
    /// Render the song: one bar per level, at the tempo.
    /// </summary>
    /// <param name="bpm">The beats per minute.</param>
    /// <param name="levels">How much plays in each bar (0 to 6).</param>
    /// <param name="seed">The seed of the noise.</param>
    /// <returns>The samples.</returns>
    public static short[] RenderSong(double bpm, int[] levels, int seed)
    {
        double beat = 60.0 / bpm;
        int bar = BarSamples(bpm);
        var mix = new float[bar * levels.Length + SampleRate];
        var random = new Random(seed);
        for (int b = 0; b < levels.Length; b++)
        {
            int start = b * bar;
            int level = levels[b];
            int chord = b % 4;
            bool fill = b % 8 == 7 && level > 0;
            RenderBar(mix, start, beat, level, chord, fill, random);
        }

        return ToSamples(mix, 0.9f);
    }

    /// <summary>How many samples a bar of four beats has at the tempo.</summary>
    public static int BarSamples(double bpm) => (int)Math.Round(4.0 * 60.0 / bpm * SampleRate);

    /// <summary>
    /// Render a sound of the fight: "hit" (a punch lands), "perfect" (a ding),
    /// "miss" (a low buzz), "dodge" (a whoosh), "hurt" (a heavy thud), "bell"
    /// (the ring bell) or "count" (a tick of the count-in).
    /// </summary>
    public static short[] RenderSound(string name)
    {
        var random = new Random(name.GetHashCode() & 0xffff);
        float[] mix;
        switch (name)
        {
            case "hit":
                mix = new float[(int)(0.25 * SampleRate)];
                Kick(mix, 0, 1.0f, 140.0, 55.0);
                Noise(mix, 0, 0.08, 0.7f, 40.0, random, false);
                break;
            case "perfect":
                mix = new float[(int)(0.5 * SampleRate)];
                Tone(mix, 0, 0.5, 1318.5, 0.35f, 9.0);
                Tone(mix, 0, 0.5, 1975.5, 0.2f, 12.0);
                break;
            case "miss":
                mix = new float[(int)(0.2 * SampleRate)];
                for (int i = 0; i < mix.Length; i++)
                {
                    double t = (double)i / SampleRate;
                    double square = Math.Sin(2 * Math.PI * 90.0 * t) > 0 ? 1.0 : -1.0;
                    mix[i] += (float)(0.25 * square * Math.Exp(-t * 10.0));
                }

                break;
            case "dodge":
                mix = new float[(int)(0.35 * SampleRate)];
                float low = 0f;
                for (int i = 0; i < mix.Length; i++)
                {
                    double share = (double)i / mix.Length;
                    float noise = (float)(random.NextDouble() * 2.0 - 1.0);
                    float alpha = (float)(0.05 + 0.5 * share);
                    low += alpha * (noise - low);
                    mix[i] += (float)(0.6 * low * Math.Sin(Math.PI * share));
                }

                break;
            case "hurt":
                mix = new float[(int)(0.4 * SampleRate)];
                Kick(mix, 0, 1.0f, 90.0, 40.0);
                Noise(mix, 0, 0.2, 0.5f, 18.0, random, false);
                break;
            case "bell":
                mix = new float[(int)(1.6 * SampleRate)];
                foreach (int at in new[] { 0, (int)(0.28 * SampleRate) })
                {
                    Tone(mix, at, 1.2, 880.0, 0.3f, 3.0);
                    Tone(mix, at, 1.2, 2093.0, 0.15f, 4.0);
                    Tone(mix, at, 1.2, 2637.0, 0.1f, 5.0);
                }

                break;
            case "count":
                mix = new float[(int)(0.15 * SampleRate)];
                Tone(mix, 0, 0.15, 1760.0, 0.3f, 30.0);
                break;
            default:
                throw new ArgumentException($"Unknown sound: {name}", nameof(name));
        }

        return ToSamples(mix, 1.0f);
    }

    private static void RenderBar(
        float[] mix, int start, double beat, int level, int chord, bool fill, Random random)
    {
        int Sample(double beats) => start + (int)Math.Round(beats * beat * SampleRate);

        // Drums.
        for (int b = 0; b < 4; b++)
        {
            if (b % 2 == 0 || level >= 4)
            {
                Kick(mix, Sample(b), 0.9f, 150.0, 48.0);
            }

            if (level >= 2 && b % 2 == 1)
            {
                Snare(mix, Sample(b), 0.55f, random);
            }
        }

        int hats = level >= 6 ? 16 : 8;
        for (int h = 0; h < hats; h++)
        {
            double at = h * 4.0 / hats;
            bool offbeat = level >= 4 && Math.Abs(at % 1.0 - 0.5) < 1e-6;
            float gain = level == 0 ? 0.12f : 0.18f;
            Noise(mix, Sample(at), offbeat ? 0.25 : 0.06, gain, offbeat ? 14.0 : 60.0, random, true);
        }

        if (fill)
        {
            for (int s = 0; s < 4; s++)
            {
                Snare(mix, Sample(3.0 + s * 0.25), 0.3f + 0.1f * s, random);
            }
        }

        // The pad: the chord, softly, across the bar.
        foreach (int note in Chords[chord])
        {
            Pad(mix, start, 4.0 * beat, Frequency(note), level == 0 ? 0.05f : 0.035f);
        }

        // The bass: eighths on the root (octave jumps at the top).
        if (level >= 1)
        {
            int root = Roots[chord];
            for (int e = 0; e < 8; e++)
            {
                int note = level >= 5 && e % 2 == 1 ? root + 12 : root;
                Bass(mix, Sample(e * 0.5), 0.45 * beat, Frequency(note), 0.3f);
            }
        }

        // The arpeggio: sixteenths up and down the chord.
        if (level >= 3)
        {
            int[] notes = Chords[chord];
            int[] order = { 0, 1, 2, 1 };
            for (int s = 0; s < 16; s++)
            {
                int note = notes[order[s % 4]] + 12;
                float gain = level >= 6 ? 0.1f : 0.07f;
                Square(mix, Sample(s * 0.25), 0.22 * beat, Frequency(note), gain);
            }
        }
    }

    private static double Frequency(int midi) => 440.0 * Math.Pow(2.0, (midi - 69) / 12.0);

    private static void Kick(float[] mix, int at, float gain, double from, double to)
    {
        int length = (int)(0.3 * SampleRate);
        double phase = 0;
        for (int i = 0; i < length && at + i < mix.Length; i++)
        {
            double t = (double)i / SampleRate;
            double frequency = to + (from - to) * Math.Exp(-t * 30.0);
            phase += 2 * Math.PI * frequency / SampleRate;
            mix[at + i] += (float)(gain * Math.Sin(phase) * Math.Exp(-t * 11.0));
        }
    }

    private static void Snare(float[] mix, int at, float gain, Random random)
    {
        Noise(mix, at, 0.2, gain * 0.8f, 22.0, random, false);
        Tone(mix, at, 0.12, 185.0, gain * 0.45f, 28.0);
    }

    private static void Noise(
        float[] mix, int at, double seconds, float gain, double decay, Random random, bool high)
    {
        int length = (int)(seconds * SampleRate);
        float previous = 0f;
        for (int i = 0; i < length && at + i < mix.Length; i++)
        {
            double t = (double)i / SampleRate;
            float noise = (float)(random.NextDouble() * 2.0 - 1.0);
            float value = high ? noise - previous : noise;
            previous = noise;
            mix[at + i] += (float)(gain * value * Math.Exp(-t * decay));
        }
    }

    private static void Tone(float[] mix, int at, double seconds, double frequency, float gain, double decay)
    {
        int length = (int)(seconds * SampleRate);
        for (int i = 0; i < length && at + i < mix.Length; i++)
        {
            double t = (double)i / SampleRate;
            mix[at + i] += (float)(gain * Math.Sin(2 * Math.PI * frequency * t) * Math.Exp(-t * decay));
        }
    }

    private static void Bass(float[] mix, int at, double seconds, double frequency, float gain)
    {
        int length = (int)(seconds * SampleRate);
        float low = 0f;
        for (int i = 0; i < length && at + i < mix.Length; i++)
        {
            double t = (double)i / SampleRate;
            double saw = 2.0 * (t * frequency % 1.0) - 1.0;
            low += 0.12f * ((float)saw - low);
            double envelope = Math.Min(1.0, t / 0.005) * (0.6 + 0.4 * Math.Exp(-t * 8.0));
            double release = Math.Min(1.0, (seconds - t) / 0.02);
            mix[at + i] += (float)(gain * low * envelope * release);
        }
    }

    private static void Square(float[] mix, int at, double seconds, double frequency, float gain)
    {
        int length = (int)(seconds * SampleRate);
        for (int i = 0; i < length && at + i < mix.Length; i++)
        {
            double t = (double)i / SampleRate;
            double square = t * frequency % 1.0 < 0.5 ? 1.0 : -1.0;
            mix[at + i] += (float)(gain * square * Math.Exp(-t * 14.0));
        }
    }

    private static void Pad(float[] mix, int at, double seconds, double frequency, float gain)
    {
        int length = (int)(seconds * SampleRate);
        float low = 0f;
        for (int i = 0; i < length && at + i < mix.Length; i++)
        {
            double t = (double)i / SampleRate;
            double saw = (2.0 * (t * frequency % 1.0) - 1.0) + (2.0 * (t * frequency * 1.006 % 1.0) - 1.0);
            low += 0.04f * ((float)saw - low);
            double envelope = Math.Min(1.0, t / 0.3) * Math.Min(1.0, (seconds - t) / 0.3);
            mix[at + i] += (float)(gain * low * envelope);
        }
    }

    private static short[] ToSamples(float[] mix, float gain)
    {
        var samples = new short[mix.Length];
        for (int i = 0; i < mix.Length; i++)
        {
            samples[i] = (short)Math.Round(Math.Tanh(mix[i] * gain) * 30000.0);
        }

        return samples;
    }
}
