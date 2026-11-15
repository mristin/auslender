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
        int sections = Chart.Curriculum.Length;
        int[] levels = Chart.Levels(sections);
        Assert.Equal(Chart.IntroBars + sections * Chart.SectionBars + Chart.OutroBars, levels.Length);
        Assert.All(levels.Take(Chart.IntroBars), level => Assert.Equal(0, level));
        Assert.All(levels.TakeLast(Chart.OutroBars), level => Assert.Equal(0, level));
        Assert.Equal(1, levels[Chart.IntroBars]);
        Assert.Equal(6, levels.Max());
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(42)]
    public void Notes_leave_time_to_recover(int seed)
    {
        var notes = Chart.Build(Chart.Curriculum, seed, true);
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
        int sections = Chart.Curriculum.Length;
        foreach (Note note in Chart.Build(Chart.Curriculum, 7, true))
        {
            int bar = (int)Math.Floor(note.Beat / 4.0);
            int section = Chart.SectionOf(bar, sections);
            Assert.True(section >= 0, $"{note} is outside of the sections");
            bool rest = (bar - Chart.IntroBars) % Chart.SectionBars == Chart.SectionBars - 1;
            Assert.True(!rest || section == sections - 1, $"{note} is in a rest");
        }
    }

    [Fact]
    public void Notes_of_a_section_of_one_move_are_that_move()
    {
        string[] taught = { "straight", "hook", "uppercut", "duck", "jump", "slip", "cover" };
        foreach (Note note in Chart.Build(Chart.Curriculum, 5, true))
        {
            int section = Chart.SectionOf((int)Math.Floor(note.Beat / 4.0), Chart.Curriculum.Length);
            if (section < taught.Length)
            {
                Assert.StartsWith(taught[section], note.Kind);
            }
        }
    }

    [Fact]
    public void Notes_come_in_blocks_of_the_same_move_once_mixed()
    {
        int sections = Chart.Curriculum.Length;
        var byBar = Chart.Build(Chart.Curriculum, 9, true).ToDictionary(note => (int)Math.Floor(note.Beat / 4.0));
        foreach (var (bar, note) in byBar)
        {
            int section = Chart.SectionOf(bar, sections);
            int inSection = (bar - Chart.IntroBars) % Chart.SectionBars;
            bool finisher = inSection == Chart.SectionBars - 1;
            if (Chart.Curriculum[section].Contains(',') && inSection % Chart.BlockBars == 1 && !finisher)
            {
                Assert.True(byBar.ContainsKey(bar - 1), $"bar {bar} has no block before it");
                Assert.Equal(byBar[bar - 1].Kind, note.Kind);
                Assert.Equal(byBar[bar - 1].Side, note.Side);
            }
        }
    }

    [Fact]
    public void Notes_end_with_the_finisher_only_in_a_fight()
    {
        Assert.Equal("uppercut", Chart.Build(Chart.Curriculum, 3, true)[^1].Kind);
        int sections = Chart.Curriculum.Length;
        int lastBar = Chart.IntroBars + sections * Chart.SectionBars - 1;
        Assert.DoesNotContain(Chart.Build(Chart.Curriculum, 3, false), note => note.Beat >= lastBar * 4.0);
    }

    [Fact]
    public void Unknown_moves_are_refused()
    {
        Assert.Throws<ArgumentException>(() => Chart.Build(new[] { "kick" }, 1, false));
    }

    [Fact]
    public void Steering_picks_a_lane()
    {
        var notes = Chart.Build(new[] { "steer" }, 4, false);
        Assert.NotEmpty(notes);
        Assert.All(notes, note => Assert.Contains(note.Kind, Chart.Lanes));
        Assert.All(notes, note => Assert.True(note.IsDodge));
    }

    [Fact]
    public void Notes_are_the_same_for_the_same_seed()
    {
        Assert.Equal(Chart.Build(Chart.Curriculum, 3, true), Chart.Build(Chart.Curriculum, 3, true));
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 3)]
    [InlineData(2, -2)]
    [InlineData(3, 5)]
    public void Song_lasts_its_bars_and_does_not_clip(int progression, int transpose)
    {
        int[] levels = Chart.Levels(Chart.Curriculum.Length);
        short[] song = BeatSynth.RenderSong(100.0, levels, 1, progression, transpose);
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
