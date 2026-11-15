using System;
using System.Linq;

using Auslender.Fight;

using Xunit;

namespace Auslender.Tests;

public class ChartTests
{
    [Fact]
    public void Levels_have_the_intro_the_sections_and_the_outro()
    {
        int[] levels = Chart.Levels();
        Assert.Equal(
            Chart.IntroBars + Chart.Sections.Length * Chart.SectionBars + Chart.OutroBars, levels.Length);
        Assert.All(levels.Take(Chart.IntroBars), level => Assert.Equal(0, level));
        Assert.All(levels.TakeLast(Chart.OutroBars), level => Assert.Equal(0, level));
        Assert.InRange(levels.Max(), 1, 6);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(42)]
    public void Notes_leave_time_to_recover(int seed)
    {
        var notes = Chart.Build(seed);
        Assert.NotEmpty(notes);
        for (int i = 1; i < notes.Count; i++)
        {
            Assert.True(
                Chart.Fits(notes[i - 1], notes[i]), $"{notes[i - 1]} is followed too soon by {notes[i]}");
        }
    }

    [Fact]
    public void Notes_fall_only_in_the_sections_and_not_in_their_rests()
    {
        foreach (Note note in Chart.Build(7))
        {
            int bar = (int)Math.Floor(note.Beat / 4.0);
            int section = Chart.SectionOf(bar);
            Assert.True(section >= 0, $"{note} is outside of the sections");
            bool rest = (bar - Chart.IntroBars) % Chart.SectionBars == Chart.SectionBars - 1;
            Assert.True(!rest || section == Chart.Sections.Length - 1, $"{note} is in a rest");
        }
    }

    [Fact]
    public void Notes_teach_one_move_per_section_first()
    {
        string[][] taught =
        {
            new[] { "straight" },
            new[] { "hook" },
            new[] { "uppercut" },
            new[] { "duck" },
            new[] { "jump" },
            new[] { "slip_left", "slip_right" },
            new[] { "cover" },
        };
        foreach (Note note in Chart.Build(5))
        {
            int section = Chart.SectionOf((int)Math.Floor(note.Beat / 4.0));
            if (section < taught.Length)
            {
                Assert.Contains(note.Kind, taught[section]);
            }
        }
    }

    [Fact]
    public void Notes_are_the_same_for_the_same_seed()
    {
        Assert.Equal(Chart.Build(3), Chart.Build(3));
    }

    [Fact]
    public void Song_lasts_its_bars_and_does_not_clip()
    {
        int[] levels = Chart.Levels();
        short[] song = BeatSynth.RenderSong(100.0, levels, 1);
        int bars = BeatSynth.BarSamples(100.0) * levels.Length;
        Assert.InRange(song.Length, bars, bars + BeatSynth.SampleRate);
        Assert.All(song, sample => Assert.InRange(sample, -30000, 30000));
        Assert.True(song.Max(sample => Math.Abs((int)sample)) > 5000, "The song is too quiet.");
    }

    [Theory]
    [InlineData("hit")]
    [InlineData("perfect")]
    [InlineData("miss")]
    [InlineData("dodge")]
    [InlineData("hurt")]
    [InlineData("bell")]
    [InlineData("count")]
    public void Sounds_are_short_and_not_silent(string name)
    {
        short[] sound = BeatSynth.RenderSound(name);
        Assert.InRange(sound.Length, 1, 2 * BeatSynth.SampleRate);
        Assert.True(sound.Max(sample => Math.Abs((int)sample)) > 1000, $"{name} is silent.");
    }
}
