class_name Run
extends RhythmLevel

## A run through the land of the world (see RhythmLevel and Levels), as the
## penguin of Antarctic Adventure: he runs as fast as he lifts his knees, and
## the land rolls towards him; its obstacles stand on the road (the chart's
## notes, placed at the pace of the song), and the song is his time: he must
## arrive before it ends. He steers continuously with his
## torso across the camera picture (see BodyReader): obstacles leave a free
## gap of their own width anywhere across the road (see RhythmNote); he
## jumps over holes and fallen trees (a flight, as in Quake) and ducks under
## branches, looking straight ahead (the view does not tilt). A strip on the
## floor shows the path he is heading on (see PathStrip). The camera picture
## does not lie over the scene while he plays (only the panel in the corner
## shows it, see CameraPanel): it is for the menus.
##
## On the road, he meets the opponents of the level (see Levels), one by one,
## in the breathers between the sections (the road is free of obstacles
## around them), each in random colors of his own (see Looks.recolor). Each
## charges at him, weaving across the road from side to side, and in the last
## meters homes in on him: there is no way around him, he always meets the
## hero. Then the
## run turns into a fight (see Brawl): the clock of the run holds, the land
## stops, and they box freely until one goes down. After the knock-out, the
## opponent is dragged to the side of the road, and the run goes on (a little
## of the hero's energy comes back).
##
## The road has more on it (see DESIGN.md): boosters to pick up (see
## Boosters), platforms to jump up on, with gaps to jump over, which he may
## fall through to the road below (see Platforms), forks with a shortcut for
## him who runs all the way to their side (see Forks), barriers across the
## road which he must smash to pass (see Barriers), climbs up stairs, slopes
## and ladders, which he runs up and slides down (see Climbs), and curves
## (only the look, see Scenery.set_bend).

## The lane around which the free gap of each steering note lies (-1 left, 0
## the middle, 1 right; see RhythmNote).
const LANE_OF := {"lane_left": -1, "lane_middle": 0, "lane_right": 1}

## The color of the obstacles, by the surroundings.
const OBSTACLES := {
    "jungle": Color("8a5a2a"),
    "ice": Color("8ac4e0"),
    "cave": Color("7a6a5a"),
    "city": Color("e8701a"),
    "suburbs": Color("c8302c"),
}

## How wide the player's body is on each side (meters).
const BODY_HALF := 0.25

## The knees lifted a second (each knee counts) at which he runs at the pace
## of the notes, and how many times as fast he may run at most.
const NORMAL_CADENCE := 1.7
const FASTEST := 1.5

## How many times as long as the song he has to arrive (the music loops):
## forgiving, so that a slower runner arrives, too.
const TIME_SLACK := 1.3

## How quickly he speeds up and slows down (1/s).
const SPEED_UP := 8.0
## How much of the normal pace he loses a second at most, when he lifts his
## knees slower or not at all: very gradually, so that he keeps rolling
## through a jump or a duck (in which he can not run), and a pause of a few
## steps hardly slows him (from the normal pace to a stop: about 12 s).
const SLOW_DOWN := 0.08

## How high he flies in a jump, in meters.
const JUMP_HEIGHT := 0.8

## How much energy comes back after a knock-out.
const HEAL := 35.0

## How long a platform is (in bars), and how long its gaps (in seconds of the
## notes).
const PLATFORM_BARS := 2.5
const PLATFORM_GAP := 0.5

## How often a jump or a duck in a section which mixes it with the steering
## becomes a combined obstacle (see RhythmNote.COMBOS), and how early before
## its beat (in seconds of the notes) his jump or duck counts for it.
const COMBO_SHARE := 0.6
const COMBO_EARLY := 1.2

## How far ahead a shortcut takes him, in bars.
const SHORTCUT_BARS := 3.0

## The section with a barrier in its middle (instead of a fork), how far into
## it (in bars), and how far before the end of the road the last barrier
## stands (in bars).
const BARRIER_SECTION := 3
const BARRIER_BARS := 2.0
const LAST_BARRIER_BARS := 0.5

## The section with a climb (instead of a platform), how far into it it
## starts (in bars), and the points for its top.
const CLIMB_SECTION := 2
const CLIMB_BARS := 1.25
const TOP_BONUS := 100

## How much the road curves at most (see Scenery.set_bend), how far it goes
## before it turns another way (meters, at random), and how many meters it
## takes to turn from straight to the most.
const CURVE_MOST := 0.0028
const CURVE_EVERY := Vector2(25.0, 45.0)
const CURVE_TURN := 12.0

var _strip: PathStrip
var _rolled := 0.0
var _pace := 0.0
var _brawl := Brawl.new()
var _encounters := Encounters.new()
## The opponent fighting now (-1 if none).
var _fighting := -1
## The black sheep, who cheers the hero on from the roadside while he boxes a
## white sheep (see DESIGN.md).
var _black_sheep: Node3D
var _boosters := Boosters.new()
var _platforms := Platforms.new()
var _forks := Forks.new()
var _barriers := Barriers.new()
var _climbs := Climbs.new()
## The climb whose ladder he climbs now (-1 if none), and how high he got.
var _laddering := -1
var _climbed := 0.0
## On which level of a platform he runs now (see Platforms): 0 the road, 1
## or 2 on a platform.
var _level := 0
## Whether he flies over a gap now, which he jumped (see _on_platforms).
var _over_gap := false
## Until when (the song's time) the boosters of speed and of the shield work,
## and whether his punches are powered up for the next fight (see Boosters).
var _speed_until := -1.0
var _shield_until := -1.0
var _powered := false
## How much the road curves now, how much it turns to, and from how far (in
## meters rolled) it turns another way.
var _curve := 0.0
var _curve_goal := 0.0
var _curve_next := 0.0
## How white the screen flashes (a shortcut), in [0, 1].
var _flash := 0.0


func _is_run() -> bool:
    return true


func _build() -> void:
    _body.running = true
    boxer.jump_height = JUMP_HEIGHT
    boxer.jump_seconds = BodyReader.RUN_JUMP_HOLD
    boxer.running_steps = 0.001
    boxer.level_gaze = true
    hud.opponent_name = ""
    hud.speed_most = FASTEST
    hud.speed_needed = _goal() / (_length * TIME_SLACK)
    # NOTE (mristin):
    # His own pace, not the music's; the music loops while he runs.
    _follow_music = false
    _music.finished.connect(_loop_music)
    _strip = PathStrip.new()
    add_child(_strip)
    _strip.setup(SPOT, BODY_HALF * 2.0)
    _brawl.setup(hud, boxer, _scoring, _log, play_sound, _beat_seconds)
    add_child(_encounters)
    add_child(_boosters)
    add_child(_platforms)
    add_child(_forks)
    add_child(_barriers)
    add_child(_climbs)


## Put the opponents of the level on the road, each in a breather between two
## sections (spread over the run, a little off at random), and clear the road
## of obstacles around them.
func _on_start() -> void:
    _combine()
    _encounters.clear()
    _fighting = -1
    _end_fight_mode()
    var ids: Array = level.get("opponents", [])
    var bar := 4.0 * _beat_seconds
    var used := {}
    var meet: Array[float] = []
    for i in range(ids.size()):
        var k := clampi(roundi((i + 1) * float(_sections.size()) / (ids.size() + 1)), 1, 99)
        while used.has(k):
            k += 1
        used[k] = true
        # NOTE (mristin):
        # The middle of the breather, the last bar of the section before.
        var at: float = (_intro_bars + _core.SectionBars() * k - 0.5) * bar
        at += randf_range(-0.2, 0.2) * bar
        meet.append(at)
        _chart = _chart.filter(
            func(n: Dictionary) -> bool:
                var t := _beat_time(n)
                return t < at - 1.5 * bar or t > at + 0.75 * bar
        )
        _encounters.add(ids[i], at * SPEED + Fight.OPPONENT_DISTANCE)
    _lay_out(meet)


## Make some of the jumps and the ducks of the sections which mix them with
## the steering into combined obstacles (see RhythmNote.COMBOS): he must go
## to the right place and jump or duck there. A jump becomes a fence low in
## one part or a plank over a hole; a duck, a wall with a hole; in a section
## of both, either may become the road split into a beam and a hurdle.
func _combine() -> void:
    var bar := 4.0 * _beat_seconds
    for note: Dictionary in _chart:
        var kind: String = note["kind"]
        if kind != "jump" and kind != "duck":
            continue
        var k := floori((_beat_time(note) / bar - _intro_bars) / _core.SectionBars())
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


## Lay out the road besides the obstacles and the opponents (who meet him at
## the times of the notes in [param meet]): in every other section a platform
## (with a booster on each of its blocks), in the others a fork, a booster on
## the road late in every section, and the curves.
func _lay_out(meet: Array[float]) -> void:
    _boosters.clear()
    _platforms.clear()
    _forks.clear()
    _barriers.clear()
    _climbs.clear()
    _laddering = -1
    _climbed = 0.0
    hud.countdown = -1.0
    _level = 0
    _over_gap = false
    _speed_until = -1.0
    _shield_until = -1.0
    _powered = false
    _brawl.power = 1.0
    _curve = 0.0
    _curve_goal = 0.0
    _curve_next = 0.0
    _scenery.set_bend(0.0)
    var bar := 4.0 * _beat_seconds
    var looks: Array = level.get("boosters", [])
    var theme: String = level["scenery"]
    for k in range(_sections.size()):
        var section: float = (_intro_bars + _core.SectionBars() * k) * bar
        var clear_until := section
        if k == CLIMB_SECTION and level.has("climb"):
            var start := section + CLIMB_BARS * bar
            clear_until = _lay_climb(start, meet, looks)
        elif k % 2 == 0:
            var start := section + 1.5 * bar
            var end := start + PLATFORM_BARS * bar
            if _clear_of(meet, start - bar, end + bar):
                _lay_platform(start, end, looks, theme)
        elif k != BARRIER_SECTION:
            var at := section + 0.5 * bar
            var skip := SHORTCUT_BARS * bar
            if _clear_of(meet, at, at + skip + bar) and at + skip < _goal() - bar:
                var road: Color = Scenery.LOOKS.get(theme, Scenery.LOOKS["jungle"])["road"]
                var side: float = [-1.0, 1.0].pick_random()
                _forks.add(at, side, skip, road, Scenery.LANE * 1.5 + 0.4)
                _clear_notes(at - 0.75, at + 0.4)
        if not looks.is_empty():
            # NOTE (mristin):
            # After the platform, if any, and before the opponent.
            var at := maxf(section + randf_range(4.2, 4.7) * bar, clear_until + 0.3)
            _boosters.add(looks.pick_random(), at, randf_range(-1.0, 1.0) * Scenery.LANE)
    _lay_barriers(meet)


## The barriers of the level (see Levels): the first in the middle of
## BARRIER_SECTION, the last just before the end of the road; no obstacles
## around them.
func _lay_barriers(meet: Array[float]) -> void:
    var looks: Array = level.get("barriers", [])
    if looks.is_empty():
        return
    var bar := 4.0 * _beat_seconds
    var spots: Array[float] = []
    if _sections.size() > BARRIER_SECTION + 1:
        var section: float = (_intro_bars + _core.SectionBars() * BARRIER_SECTION) * bar
        spots.append(section + BARRIER_BARS * bar)
    spots.append(_goal() - LAST_BARRIER_BARS * bar)
    for i in range(spots.size()):
        var at := spots[i]
        if not _clear_of(meet, at - bar, at + bar):
            continue
        _barriers.add(looks[mini(i, looks.size() - 1)], at, level["scenery"])
        _clear_notes(at - 1.2, at + 0.8)


## The climb of the level (see Levels) from the time of the notes
## [param start], if none of the opponents meets him around it ([param meet]),
## with a booster of the [param looks] on its top; no obstacles on it. The
## time at which it ends (or [param start] without a climb).
func _lay_climb(start: float, meet: Array[float], looks: Array) -> float:
    var look: String = level["climb"]
    var spec: Dictionary = Climbs.LOOKS[look]
    var bar := 4.0 * _beat_seconds
    var end := _climbs.add(look, start, SPEED)
    if not _clear_of(meet, start - bar, end + 0.5 * bar):
        _climbs.clear()
        return start
    if not looks.is_empty():
        var rise := (
            0.0 if spec["up"] == "ladder" else Climbs.HEIGHT / float(Climbs.STEEP[spec["up"]])
        )
        var middle := start + (rise + Climbs.TOP * 0.5) / SPEED
        _boosters.add(looks.pick_random(), middle, randi_range(-1, 1) * Scenery.LANE, Climbs.HEIGHT)
    _clear_notes(start - 1.2, end + 0.6)
    return end


## Whether none of the opponents meets him between the times of the notes
## [param from] and [param to].
static func _clear_of(meet: Array[float], from: float, to: float) -> bool:
    for at in meet:
        if at >= from and at <= to:
            return false
    return true


## A platform from the time of the notes [param start] to about [param end],
## in a lane at random, of blocks one or two levels high with gaps (see
## Platforms.segments), a booster on each block of the upper level; no
## obstacles around it.
func _lay_platform(start: float, end: float, looks: Array, theme: String) -> void:
    var segments := Platforms.segments(start, end, PLATFORM_GAP)
    var x := randi_range(-1, 1) * Scenery.LANE
    _platforms.add(x, segments, SPEED, theme)
    if not looks.is_empty():
        for segment: Array in segments:
            if int(segment[2]) == 2:
                var middle := (float(segment[0]) + float(segment[1])) * 0.5
                _boosters.add(looks.pick_random(), middle, x, Platforms.HEIGHT * 2.0)
    _clear_notes(start - 1.0, float(segments[segments.size() - 1][1]) + 0.6)


## Take the obstacles off the road between the times of the notes [param from]
## and [param to].
func _clear_notes(from: float, to: float) -> void:
    _chart = _chart.filter(
        func(n: Dictionary) -> bool:
            var t := _beat_time(n)
            return t < from or t > to
    )


func _holds() -> bool:
    return _fighting >= 0 or _barriers.smashing() or _laddering >= 0


## While they box: the brawl plays; at its end, the run goes on. While he
## smashes a barrier: its clock runs. While he climbs a ladder: he goes up
## as fast as he runs, and on at its top.
func _hold(delta: float) -> void:
    if _laddering >= 0:
        _run_pace(delta)
        _climbed += delta * _pace * Climbs.LADDER_SPEED
        if _climbed >= Climbs.HEIGHT:
            _t = _climbs.climbed(_laddering)
            _laddering = -1
            _on_climb("top")
        return
    if _barriers.smashing():
        hud.countdown = maxf(0.0, _barriers.time_left())
        return
    _brawl.step(delta, _body.dodges())
    if boxer.health <= 0.0:
        _finish(false)
        return
    if _brawl.active():
        return
    var encounter: Dictionary = _encounters.at(_fighting)
    encounter["state"] = "down"
    _fighting = -1
    if _powered:
        _powered = false
        _brawl.power = 1.0
    boxer.health = minf(Boxer.MAX_HEALTH, boxer.health + HEAL)
    _end_fight_mode()
    hud.announce("RUN!", 1.5)
    _log.write("run_on", {"song": _now})


func _threatened() -> bool:
    return _fighting >= 0 and _brawl.threatened()


## He ran into a barrier (the [param index] of it): the run stops, and he
## smashes it (see Barriers).
func _start_smash(index: int) -> void:
    _barriers.start(index, boxer.shift)
    var look := _barriers.look()
    boxer.running_steps = 0.0
    boxer.level_gaze = false
    _level = 0
    _over_gap = false
    hud.speed = -1.0
    hud.opponent_name = str(Barriers.LOOKS[look]["title"]).trim_prefix("THE ")
    hud.countdown = Barriers.LIMIT
    hud.announce("SMASH IT!", 1.5)
    play_sound("bell", -6.0)
    if look == "poster":
        _black_sheep = Looks.black_sheep()
        add_child(_black_sheep)
        _black_sheep.position = SPOT + Vector3(boxer.shift + 1.6, 0, -1.2)
        _black_sheep.rotation.y = 0.6
    _log.write("barrier_start", {"look": look, "song": _now})


## He smashed the barrier: the bonus for the time left, and the run goes on.
func _smashed() -> void:
    var left := _barriers.time_left()
    _scoring.met("landed")
    if left > 0.0:
        var points := Barriers.BONUS * ceili(left)
        _scoring.bonus(points)
        hud.say("SMASHED! +%d" % points, Hud.GOLD)
    else:
        hud.say("SMASHED!", Hud.GOLD)
    hud.countdown = -1.0
    play_sound("perfect", -4.0)
    play_sound("hit", -2.0)
    _end_fight_mode()
    hud.announce("RUN!", 1.5)
    _log.write("barrier_smashed", {"seconds": Barriers.LIMIT - left, "song": _now})


## The hero crashed into the opponent: the run turns into a fight.
func _crash(index: int) -> void:
    var encounter: Dictionary = _encounters.at(index)
    encounter["state"] = "fight"
    _fighting = index
    var figure: Opponent = encounter["figure"]
    figure.global_position = SPOT + Vector3(boxer.shift, 0, -Fight.OPPONENT_DISTANCE)
    figure.target = SPOT + Vector3(boxer.shift, 0, 0)
    boxer.running_steps = 0.0
    boxer.level_gaze = false
    boxer.take_damage(0.0, true)
    _level = 0
    hud.speed = -1.0
    hud.announce("FIGHT!", 1.5)
    play_sound("hurt", -8.0)
    play_sound("bell", -6.0)
    _brawl.start(encounter["id"], figure)
    if figure.look == "white_sheep":
        _black_sheep = Looks.black_sheep()
        add_child(_black_sheep)
        _black_sheep.position = SPOT + Vector3(boxer.shift + 1.6, 0, -2.4)
        _black_sheep.rotation.y = 0.6


## Back to running.
func _end_fight_mode() -> void:
    boxer.level_gaze = true
    hud.opponent_name = ""
    if _black_sheep != null:
        _black_sheep.queue_free()
        _black_sheep = null


## A punch or a kick of the player counts only in a fight (running lifts the
## knees, too, which the classifier may take for kicks).
func throw(kind: String, side: String, _source := "vision") -> void:
    if _phase != Phase.PLAYING or _paused:
        return
    if _barriers.smashing():
        _show_strike(kind, side)
        _smash(kind, side)
        return
    if _fighting < 0:
        return
    _show_strike(kind, side)
    _brawl.punch(kind, side)


## A punch or a kick at the barrier: chunks fly (see Barriers.hit); the
## power booster works on it, too.
func _smash(kind: String, side: String) -> void:
    var result := _barriers.hit(kind, side, _brawl.power)
    _log.write("barrier_hit", {"kind": kind, "side": side, "result": result, "song": _now})
    match result:
        "target":
            _scoring.bonus(50)
            hud.say("CRASH!", Hud.GOLD)
            play_sound("hit", -2.0)
        "hit":
            _scoring.bonus(20)
            hud.say("BAM!", Hud.PAPER)
            play_sound("hit", -6.0)
        "smashed":
            _smashed()


func _his_health() -> float:
    if _barriers.smashing():
        return _barriers.health()
    if _fighting < 0:
        return -1.0
    return (_encounters.at(_fighting)["figure"] as Opponent).health


func _idle_command() -> String:
    if _barriers.smashing():
        return "SMASH IT!"
    if _fighting >= 0:
        return "READY"
    var going := _climbs.way(_t)
    if _laddering >= 0 or going == "stairs" or going == "slope":
        return "CLIMB: KNEES UP!"
    if _pace < 0.15:
        return "LIFT YOUR KNEES!"
    return "RUN!"


func _on_frame(delta: float) -> void:
    _boosters.place(_t, SPEED, SPOT, delta)
    _platforms.place(_t, SPEED, SPOT)
    _forks.place(_t, SPEED, SPOT)
    _barriers.place(_t, SPEED, SPOT, _scenery.bend)
    _barriers.step(delta)
    _climbs.place(_t, SPEED, SPOT, _scenery.bend)
    _scenery.keep_clear(_forks.clearings() + _climbs.clearings())
    _show_boosts()
    hud.flash = _flash
    _flash = maxf(0.0, _flash - delta * 2.0)
    var ground := _ground()
    var climb := 4.0 if ground > boxer.elevation else 3.0
    if _laddering >= 0 or _climbs.way(_t) != "":
        climb = 8.0
    boxer.elevation = move_toward(boxer.elevation, ground, delta * climb)
    # NOTE (mristin):
    # He looks up the climb ahead (up the ladder), and down it.
    var rise := _climbs.height(_t + 4.0 / SPEED) - _climbs.height(_t)
    if _laddering >= 0:
        rise = 2.5
    boxer.gaze_rise = lerpf(boxer.gaze_rise, rise, minf(1.0, delta * 4.0))
    if _laddering >= 0:
        boxer.shift = lerpf(boxer.shift, Climbs.ladder_at(boxer.shift), minf(1.0, delta * 6.0))
        boxer.face(SPOT + Vector3(boxer.shift, 0, -6.0), delta)
        boxer.running_steps = maxf(0.001, _pace * NORMAL_CADENCE * 0.5)
        hud.speed = _pace
        return
    if _barriers.smashing():
        boxer.face(_barriers.aim(boxer.shift), delta)
        boxer.running_steps = 0.0
        if _black_sheep != null:
            _black_sheep.position.y = 0.12 * absf(sin(_time * PI / _beat_seconds))
        hud.speed = -1.0
        return
    if _fighting >= 0:
        # NOTE (mristin):
        # In a fight, he stays where he crashed (the slips must not steer).
        var figure: Opponent = _encounters.at(_fighting)["figure"]
        boxer.face(figure.global_position, delta)
        boxer.running_steps = 0.0
        if _black_sheep != null:
            _black_sheep.position.y = 0.12 * absf(sin(_time * PI / _beat_seconds))
        hud.speed = -1.0
        return
    boxer.shift = lerpf(boxer.shift, _body.steer * Scenery.LANE, minf(1.0, delta * 10.0))
    boxer.face(SPOT + Vector3(boxer.shift, 0, -6.0), delta)
    hud.speed = _pace
    # NOTE (mristin):
    # His arms pump at his own steps.
    boxer.running_steps = maxf(0.001, _pace * NORMAL_CADENCE * 0.5)
    _strip.follow(boxer.shift, _rolled)


## He runs as fast as he lifts his knees (see VisionService.GetCadence: the
## knees lifted a second): at NORMAL_CADENCE the notes come at their pace,
## faster quicker (up to FASTEST), slower slower, and standing still stops
## him. The obstacles stand on the road: he reaches them at his own pace.
func _advance(played: float) -> void:
    _run_pace(played)
    var boost := Boosters.SPEED_BOOST if _now < _speed_until else 1.0
    boost *= _climbs.pace(_t)
    var before := _t
    _t += played * _pace * boost
    var meters := played * _pace * boost * SPEED
    _rolled += meters
    _scenery.scroll(meters)
    var meeting := _encounters.move(meters, played, _time, boxer.shift, SPOT)
    if meeting >= 0:
        _crash(meeting)
    if _fighting >= 0:
        return
    var barrier := _barriers.reached(_t)
    if barrier >= 0:
        _start_smash(barrier)
        return
    var ladder := _climbs.ladder(_t, SPEED)
    if ladder >= 0:
        _t = _climbs.climb(ladder, SPEED)
        _laddering = ladder
        _climbed = 0.0
        _on_climb("ladder")
        return
    for going in _climbs.entered(before, _t):
        _on_climb(going)
    _turn(meters)
    _on_platforms()
    for look in _boosters.take(_t, boxer.shift, _ground()):
        _boost(look)
    var fork := _forks.reached(before, _t, boxer.shift)
    if not fork.is_empty():
        _log.write("fork", {"taken": fork["state"] == "taken", "song": _now})
        if fork["state"] == "taken":
            _shortcut(float(fork["skip"]))


## How fast he runs (see _advance), after [param played] seconds of the song.
func _run_pace(played: float) -> void:
    var cadence := 0.0
    if vision != null and vision.GetStatus() != "Disabled":
        cadence = vision.GetCadence()
    var wanted := clampf(cadence / NORMAL_CADENCE, 0.0, FASTEST)
    # NOTE (mristin):
    # He speeds up quickly, but slows down only very gradually, and not at all
    # while he jumps or ducks: he can not run then.
    if wanted > _pace:
        _pace = lerpf(_pace, wanted, minf(1.0, played * SPEED_UP))
    elif not (_body.jumping or _body.ducking):
        _pace = maxf(wanted, _pace - SLOW_DOWN * played)


## How high he stands: on the climb under him (up the ladder), or on the
## level of a platform (see Platforms).
func _ground() -> float:
    if _laddering >= 0:
        return _climbed
    return maxf(_climbs.height(_t), Platforms.HEIGHT * _level)


## He goes on [param going] a climb (see Climbs): up it, on its top (points),
## or down it.
func _on_climb(going: String) -> void:
    match going:
        "stairs", "slope", "ladder":
            hud.announce("CLIMB!", 1.2)
            hud.say(
                "UP %s!" % str(Climbs.LOOKS[_climb_look()]["title"]).trim_prefix("THE "), Hud.GOLD
            )
        "top":
            _scoring.bonus(TOP_BONUS)
            hud.announce("TOP!", 1.2)
            hud.say("ON TOP! +%d" % TOP_BONUS, Hud.GOLD)
            _play("perfect")
        "slide":
            hud.announce("WHEEE!", 1.2)
            _play("dodge")
        "down_stairs":
            hud.say("DOWN THE STAIRS!", Hud.GOLD)
    _log.write("climb", {"part": going, "song": _now})


## The look of the climb under him (or the one he climbs up).
func _climb_look() -> String:
    return str(level.get("climb", "hill"))


## Curve the road as he runs [param meters] on: it turns now and then to
## another curve (or straight), gradually.
func _turn(meters: float) -> void:
    if _rolled >= _curve_next:
        _curve_goal = [-1.0, -0.5, 0.0, 0.0, 0.5, 1.0].pick_random() * CURVE_MOST
        _curve_next = _rolled + randf_range(CURVE_EVERY.x, CURVE_EVERY.y)
    _curve = move_toward(_curve, _curve_goal, CURVE_MOST / CURVE_TURN * meters)
    _scenery.set_bend(_curve)


## Up onto a platform, along it and down again: he steps up onto a level
## which comes under him (he need not jump), and falls to the level under him
## if he does not jump over a gap (or steps off the side): one level does
## not hurt, two at once do (see Platforms). A gap which he jumped over gives
## points.
func _on_platforms() -> void:
    var ground := _platforms.ground(_t, boxer.shift)
    if ground >= _level:
        if _over_gap:
            _over_gap = false
            _scoring.met("dodged")
            hud.say("NICE JUMP!", Hud.GOLD)
            _play("dodge")
            _log.write("platform", {"result": "jumped", "song": _now})
        if ground > _level:
            _level = ground
            _log.write("platform", {"result": "up", "level": _level, "song": _now})
        return
    if _body.jumping:
        _over_gap = true
        return
    var drop := _level - ground
    _level = ground
    _over_gap = false
    _log.write("platform", {"result": "fell", "levels": drop, "song": _now})
    if drop < 2:
        return
    if _now < _shield_until:
        hud.say("SHIELD!", Boosters.KINDS["shield"]["color"])
        return
    _scoring.failed("hit")
    _play("hurt")
    boxer.take_damage(HURT)
    hud.say("OUCH! TWO DOWN!", Hud.RED)
    if boxer.health <= 0.0:
        _finish(false)


## He picked up the booster of the [param look] (see Boosters).
func _boost(look: String) -> void:
    var kind: String = Boosters.LOOKS[look]["kind"]
    var spec: Dictionary = Boosters.KINDS[kind]
    match kind:
        "speed":
            _speed_until = _now + float(spec["seconds"])
        "health":
            boxer.health = minf(Boxer.MAX_HEALTH, boxer.health + Boosters.HEALTH)
        "power":
            _powered = true
            _brawl.power = Boosters.POWER
        "shield":
            _shield_until = _now + float(spec["seconds"])
    hud.say("%s: %s" % [Boosters.LOOKS[look]["title"], spec["effect"]], spec["color"])
    _play("perfect")
    _log.write("booster", {"look": look, "kind": kind, "song": _now})


## The boosters which work now, on the HUD.
func _show_boosts() -> void:
    var boosts: Array = []
    var timed := {"speed": _speed_until, "shield": _shield_until}
    for kind in timed:
        var spec: Dictionary = Boosters.KINDS[kind]
        var left: float = timed[kind] - _now
        if left > 0.0:
            var name: String = spec["effect"]
            boosts.append([name.trim_suffix("!"), left / float(spec["seconds"]), spec["color"]])
    if _powered:
        boosts.append(["POWER PUNCHES", -1.0, Boosters.KINDS["power"]["color"]])
    hud.boosts = boosts


## He took a fork: the side road takes him [param skip] ahead in the time of
## the notes, past the obstacles and the boosters in between.
func _shortcut(skip: float) -> void:
    var from := _t
    _t += skip
    var meters := skip * SPEED
    _rolled += meters
    _scenery.scroll(meters)
    _encounters.move(meters, 0.0, _time, boxer.shift, SPOT)
    _boosters.skip(from, _t)
    for note in _notes.duplicate():
        if note.result == "" and note.at <= _t + 0.3:
            _notes.erase(note)
            note.queue_free()
    while _next < _chart.size() and _beat_time(_chart[_next]) <= _t + 0.3:
        _next += 1
    _flash = 1.0
    hud.announce("SHORTCUT!", 1.5)
    _play("perfect")


## A shield (see Boosters) keeps the obstacles off him.
func _hurt(note: RhythmNote) -> void:
    if _now < _shield_until:
        _met(note, "dodged")
        hud.say("SHIELD!", Boosters.KINDS["shield"]["color"])
        return
    super(note)


## Call what comes on the road: a gap of the platform under him to jump
## over (not the end of the platform), and a fork with its shortcut, to its
## side.
func _call() -> Array:
    if _barriers.smashing():
        return _barriers.call_target()
    if _fighting >= 0:
        return []
    var drop := _platforms.next_drop(_t, _level)
    var deck := _platforms.under(_t)
    if drop > 0.0 and not deck.is_empty() and drop < float(deck["end"]):
        var left := drop - _t
        var span := _beat_seconds * 2.0
        if left <= span:
            return ["JUMP!", "low", clampf(1.0 - left / span, 0.0, 1.0)]
    var fork := _forks.next(_t)
    if not fork.is_empty():
        var left := float(fork["at"]) - _t
        var span := _beat_seconds * 3.0
        if left <= span:
            var from := "to_left" if float(fork["side"]) < 0.0 else "to_right"
            return ["SHORTCUT!", from, clampf(1.0 - left / span, 0.0, 1.0)]
    return []


## Arrived at the end of the road: the run is won by the grade; the time
## (the song's length and some, see TIME_SLACK) ran out before: too slow.
func _check_end() -> void:
    if _t >= _goal():
        _finish(false)
    elif _now >= _length * TIME_SLACK:
        _failed = true
        _finish(false)


## How far the road goes, in the time of the notes: to the end of its last
## section.
func _goal() -> float:
    var bars: int = _core.IntroBars() + _sections.size() * 6
    return bars * 4.0 * _beat_seconds


func _progress() -> float:
    return clampf(_t / maxf(_goal(), 1.0), 0.0, 1.0)


## The notes which do not span the road (none now; the rings of a fight)
## follow him.
func _place(note: RhythmNote) -> void:
    if not note.spans_road():
        note.follow = boxer.shift
    note.place(_t)


func _set_up(note: RhythmNote, kind: String, side: String, at: float, arrive: Vector3) -> void:
    if kind == "jump":
        # NOTE (mristin):
        # A hole (or a fallen tree) on the road.
        arrive.y = 0.0
    # NOTE (mristin):
    # The free gap of a steering note: anywhere across the road (around the
    # lane which the chart chose), of a width of its own.
    var gap := Vector2.ZERO
    if kind.begins_with("lane_"):
        var width := randf_range(1.2, 1.9)
        var half := RhythmNote.ROAD * 0.5 - width * 0.5
        var middle: float = LANE_OF[kind] * Scenery.LANE + randf_range(-0.6, 0.6)
        gap = Vector2(clampf(middle, -half, half), width)
    var parts: Array = []
    if kind in RhythmNote.COMBOS:
        var across := _combo_parts(kind)
        gap = across[0]
        parts = across[1]
    var color: Color = OBSTACLES.get(level["scenery"], RhythmNote.ATTACK)
    note.setup(kind, side, at, arrive, SPEED, color, level["scenery"], gap, parts)


## The parts across the road of a combined obstacle of the [param kind] (see
## RhythmNote.parts), at random: [its way through (middle, width), the
## parts].
static func _combo_parts(kind: String) -> Array:
    var half := RhythmNote.ROAD * 0.5
    var lane := randi_range(-1, 1) * Scenery.LANE + randf_range(-0.4, 0.4)
    var width := randf_range(1.3, 1.7)
    match kind:
        "plank":
            width = randf_range(0.9, 1.2)
        "split":
            # NOTE (mristin):
            # Where the road splits, and which side asks for which move.
            var divide := randf_range(-0.9, 0.9)
            var moves := ["duck", "jump"]
            moves.shuffle()
            var left := Vector2((-half + divide) * 0.5, divide + half)
            return [left, [[-half, divide, moves[0]], [divide, half, moves[1]]]]
    var middle := clampf(lane, -half + width * 0.5, half - width * 0.5)
    var from := middle - width * 0.5
    var to := middle + width * 0.5
    var way: String = {"fence_jump": "jump", "fence_duck": "duck", "plank": ""}[kind]
    var side := "jump" if kind == "plank" else "block"
    var parts: Array = [[-half, from, side], [from, to, way], [to, half, side]]
    return [
        Vector2(middle, width),
        parts.filter(func(part: Array) -> bool: return float(part[1]) - float(part[0]) > 0.05)
    ]


## Judge a steering note as its obstacles reach him: is he clear of them (in
## the free gap)?
func _judge(note: RhythmNote) -> bool:
    if note.kind in RhythmNote.COMBOS:
        return _judge_combo(note)
    if not note.kind.begins_with("lane_"):
        return false
    if _t < note.at + _latency:
        return true
    # NOTE (mristin):
    # Where he is on the road, not where he steers to.
    var clear := not note.blocks(boxer.shift, BODY_HALF)
    var result := "dodged" if clear else "hit"
    var fields := {
        "kind": note.kind, "beat": note.at, "result": result, "at": boxer.shift, "gap": note.gap
    }
    _log.write("note", fields)
    if clear:
        _met(note, "dodged")
    else:
        _hurt(note)
    return true


## Judge a combined obstacle as it reaches him: is he clear of its blocks, and
## did he make the move which his part of it asks for (see RhythmNote.parts)?
func _judge_combo(note: RhythmNote) -> bool:
    if _t < note.at + _latency:
        return true
    var x := boxer.shift
    var move := note.move_at(x)
    var clear := not note.blocks(x, BODY_HALF)
    if clear and move != "":
        clear = float(_in_pose.get(move, -100.0)) >= note.at - COMBO_EARLY
    var fields := {"kind": note.kind, "beat": note.at, "at": x, "move": move}
    fields["result"] = "dodged" if clear else "hit"
    _log.write("note", fields)
    if clear:
        _met(note, "dodged")
    else:
        _hurt(note)
    return true


## The call of a combined obstacle: where the way through is from him, and
## what to do there; the other notes as usual.
func _note_call(note: RhythmNote) -> Array:
    if not note.kind in RhythmNote.COMBOS:
        return super(note)
    var off := note.gap - boxer.shift
    var from := "front"
    if off < -0.5:
        from = "right"
    elif off > 0.5:
        from = "left"
    match note.kind:
        "fence_jump":
            return ["LOW PART: JUMP!", from if from != "front" else "low"]
        "fence_duck":
            return ["HOLE: DUCK!", from]
        "plank":
            return ["PLANK OR JUMP!", from]
    return ["DUCK OR JUMP!", "front"]


func _on_hurt(_note: RhythmNote) -> void:
    hud.say("OOF!", Hud.RED)


func _banner(won: bool) -> String:
    if _failed:
        return "TOO SLOW!"
    return "ARRIVED!" if won else "TRY AGAIN"


## The music starts again while he still runs (see TIME_SLACK).
func _loop_music() -> void:
    if _phase == Phase.PLAYING:
        _music.play()
