class_name RoadPlan
extends RefCounted

## The plan of the road of a run (see Run and DESIGN.md), laid out as it
## starts: the opponents in the breathers between the sections, the combined
## obstacles (see RhythmNote.COMBOS), a platform or a climb or a fork in each
## section, the barriers, and the boosters. It clears the obstacles of the
## chart around them (see [member chart]).

## How long a platform is (in bars), and how long its gaps (in seconds of the
## notes).
const PLATFORM_BARS := 2.5
const PLATFORM_GAP := 0.5

## How often a jump or a duck in a section which mixes it with the steering
## becomes a combined obstacle (see RhythmNote.COMBOS).
const COMBO_SHARE := 0.6

## How far ahead a shortcut takes him, in bars.
const SHORTCUT_BARS := 3.0

## The section with a barrier in its middle (instead of a fork), how far into
## it (in bars), and how far before the end of the road the last barrier
## stands (in bars).
const BARRIER_SECTION := 3
const BARRIER_BARS := 2.0
const LAST_BARRIER_BARS := 0.5

## The section with a climb (instead of a platform), and how far into it it
## starts (in bars).
const CLIMB_SECTION := 2
const CLIMB_BARS := 1.25

## The notes of the chart (see Chart), as laid out: without the obstacles
## around what else is on the road.
var chart: Array = []

## The level (see Levels), and the times of the notes at which the opponents
## meet him.
var _level: Dictionary
var _meet: Array[float] = []

## The time of a note of the chart (a Callable of the note), how long a bar
## is, where the sections start (in bars), how long each is, which moves
## each has, and where the road ends (in the time of the notes).
var _beat_time: Callable
var _bar := 0.0
var _intro_bars := 0
var _section_bars := 0
var _sections: PackedStringArray
var _goal := 0.0

## The things on the road which the plan lays out (see Run).
var _road: Dictionary


## A plan for the [param level] from its [param notes], timed by
## [param beat_time] at [param beat_seconds] a beat, in [param sections] of
## [param section_bars] after [param intro_bars], up to [param goal]; it lays
## out the things of [param road] ("encounters", "boosters", "platforms",
## "forks", "barriers", "climbs").
func _init(
    level: Dictionary,
    notes: Array,
    beat_time: Callable,
    beat_seconds: float,
    intro_bars: int,
    section_bars: int,
    sections: PackedStringArray,
    goal: float,
    road: Dictionary
) -> void:
    _level = level
    chart = notes
    _beat_time = beat_time
    _bar = 4.0 * beat_seconds
    _intro_bars = intro_bars
    _section_bars = section_bars
    _sections = sections
    _goal = goal
    _road = road


## Lay out the whole road.
func lay() -> void:
    for key in _road:
        _road[key].clear()
    _combine()
    _lay_opponents()
    var looks: Array = _level.get("boosters", [])
    for k in range(_sections.size()):
        var section := _section_start(k)
        var clear_until := section
        if k == CLIMB_SECTION and _level.has("climb"):
            clear_until = _lay_climb(section + CLIMB_BARS * _bar, looks)
        elif k % 2 == 0:
            var start := section + 1.5 * _bar
            var end := start + PLATFORM_BARS * _bar
            if _clear_of(start - _bar, end + _bar):
                _lay_platform(start, end, looks)
        elif k != BARRIER_SECTION:
            _lay_fork(section + 0.5 * _bar)
        if not looks.is_empty():
            # NOTE (mristin):
            # After the platform or the climb, if any, and before the opponent.
            var at := maxf(section + randf_range(4.2, 4.7) * _bar, clear_until + 0.3)
            _road["boosters"].add(looks.pick_random(), at, randf_range(-1.0, 1.0) * Scenery.LANE)
    _lay_barriers()


## Where the section of the index [param k] starts, in the time of the notes.
func _section_start(k: int) -> float:
    return (_intro_bars + _section_bars * k) * _bar


## Make some of the jumps and the ducks of the sections which mix them with
## the steering into combined obstacles (see RhythmNote.COMBOS): he must go
## to the right place and jump or duck there. A jump becomes a fence low in
## one part or a plank over a hole; a duck, a wall with a hole; in a section
## of both, either may become the road split into a beam and a hurdle.
func _combine() -> void:
    for note: Dictionary in chart:
        var kind: String = note["kind"]
        if kind != "jump" and kind != "duck":
            continue
        var k := floori((float(_beat_time.call(note)) / _bar - _intro_bars) / _section_bars)
        if k < 0 or k >= _sections.size():
            continue
        var moves := _sections[k].split(",")
        if not moves.has("steer") or randf() >= COMBO_SHARE:
            continue
        var choices: Array = (
            ["fence_jump", "fence_jump", "plank"] if kind == "jump" else ["fence_duck"]
        )
        if moves.has("jump") and moves.has("duck"):
            choices.append("split")
        note["kind"] = choices.pick_random()


## Put the opponents of the level on the road, each in a breather between two
## sections (spread over the run, a little off at random), and clear the road
## of obstacles around them.
func _lay_opponents() -> void:
    var encounters: Encounters = _road["encounters"]
    _meet.clear()
    var ids: Array = _level.get("opponents", [])
    var used := {}
    for i in range(ids.size()):
        var k := clampi(roundi((i + 1) * float(_sections.size()) / (ids.size() + 1)), 1, 99)
        while used.has(k):
            k += 1
        used[k] = true
        # NOTE (mristin):
        # The middle of the breather, the last bar of the section before.
        var at := _section_start(k) - 0.5 * _bar + randf_range(-0.2, 0.2) * _bar
        _meet.append(at)
        _clear_notes(at - 1.5 * _bar, at + 0.75 * _bar)
        encounters.add(ids[i], at * RhythmLevel.SPEED + Fight.OPPONENT_DISTANCE)


## A fork at the time of the notes [param at], to a side at random, with its
## shortcut (see Forks), if none of the opponents meets him on the way.
func _lay_fork(at: float) -> void:
    var skip := SHORTCUT_BARS * _bar
    if not _clear_of(at, at + skip + _bar) or at + skip >= _goal - _bar:
        return
    var theme: String = _level["scenery"]
    var road: Color = Scenery.LOOKS.get(theme, Scenery.LOOKS["jungle"])["road"]
    var side: float = [-1.0, 1.0].pick_random()
    _road["forks"].add(at, side, skip, road, Scenery.LANE * 1.5 + 0.4)
    _clear_notes(at - 0.75, at + 0.4)


## The barriers of the level (see Levels): the first in the middle of
## BARRIER_SECTION, the last just before the end of the road; no obstacles
## around them.
func _lay_barriers() -> void:
    var looks: Array = _level.get("barriers", [])
    if looks.is_empty():
        return
    var spots: Array[float] = []
    if _sections.size() > BARRIER_SECTION + 1:
        spots.append(_section_start(BARRIER_SECTION) + BARRIER_BARS * _bar)
    spots.append(_goal - LAST_BARRIER_BARS * _bar)
    for i in range(spots.size()):
        var at := spots[i]
        if not _clear_of(at - _bar, at + _bar):
            continue
        _road["barriers"].add(looks[mini(i, looks.size() - 1)], at, _level["scenery"])
        _clear_notes(at - 1.2, at + 0.8)


## The climb of the level (see Levels) from the time of the notes
## [param start], if none of the opponents meets him around it, with a
## booster of the [param looks] on its top; no obstacles on it. The time at
## which it ends (or [param start] without a climb).
func _lay_climb(start: float, looks: Array) -> float:
    var climbs: Climbs = _road["climbs"]
    var look: String = _level["climb"]
    var end := climbs.add(look, start, RhythmLevel.SPEED)
    if not _clear_of(start - _bar, end + 0.5 * _bar):
        climbs.clear()
        return start
    if not looks.is_empty():
        _road["boosters"].add(
            looks.pick_random(),
            Climbs.top_middle(look, start, RhythmLevel.SPEED),
            randi_range(-1, 1) * Scenery.LANE,
            Climbs.HEIGHT
        )
    _clear_notes(start - 1.2, end + 0.6)
    return end


## Whether none of the opponents meets him between the times of the notes
## [param from] and [param to].
func _clear_of(from: float, to: float) -> bool:
    for at in _meet:
        if at >= from and at <= to:
            return false
    return true


## A platform from the time of the notes [param start] to about [param end],
## in a lane at random, of blocks one or two levels high with gaps (see
## Platforms.segments), a booster of the [param looks] on each block of the
## upper level; no obstacles around it.
func _lay_platform(start: float, end: float, looks: Array) -> void:
    var segments := Platforms.segments(start, end, PLATFORM_GAP)
    var x := randi_range(-1, 1) * Scenery.LANE
    _road["platforms"].add(x, segments, RhythmLevel.SPEED, _level["scenery"])
    if not looks.is_empty():
        for segment: Array in segments:
            if int(segment[2]) == 2:
                var middle := (float(segment[0]) + float(segment[1])) * 0.5
                _road["boosters"].add(looks.pick_random(), middle, x, Platforms.HEIGHT * 2.0)
    _clear_notes(start - 1.0, float(segments[segments.size() - 1][1]) + 0.6)


## Take the obstacles off the road between the times of the notes [param from]
## and [param to].
func _clear_notes(from: float, to: float) -> void:
    chart = chart.filter(
        func(n: Dictionary) -> bool:
            var t := float(_beat_time.call(n))
            return t < from or t > to
    )
