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
## On the road, he meets the opponents of the level (see Levels and
## Encounters), one by one, in the breathers between the sections (see
## RoadPlan): there is no way around them, and the run turns into a fight
## (see BrawlMode). While he fights, smashes a barrier or climbs a ladder, the
## run is in a mode (see RunMode): the clock of the run holds, and the mode
## says what goes on.
##
## The road has more on it (see DESIGN.md and RoadPlan): boosters to pick up
## (see Boosters and Boosts), platforms to jump up on, with gaps to jump over,
## which he may fall through to the road below (see Platforms), forks with a
## shortcut for him who runs all the way to their side (see Forks), barriers
## across the road which he must smash to pass (see Barriers and SmashMode),
## climbs up stairs, slopes and ladders, which he runs up and slides down
## (see Climbs and LadderMode), and curves (only the look, see
## Scenery.set_bend).

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

## How early before the beat of a combined obstacle (see RhythmNote.COMBOS;
## in seconds of the notes) his jump or duck counts for it.
const COMBO_EARLY := 1.2

## The points for the top of a climb.
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
var _boosters := Boosters.new()
var _platforms := Platforms.new()
var _forks := Forks.new()
var _barriers := Barriers.new()
var _climbs := Climbs.new()
var _boosts := Boosts.new()
## The mode which holds the run now (see RunMode), or null while he runs.
var _mode: RunMode
## On which level of a platform he runs now (see Platforms): 0 the road, 1
## or 2 on a platform.
var _level := 0
## Whether he flies over a gap now, which he jumped (see _on_platforms).
var _over_gap := false
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
    for node: Node in [_encounters, _boosters, _platforms, _forks, _barriers, _climbs]:
        add_child(node)


## Lay out the road (see RoadPlan) and start afresh.
func _on_start() -> void:
    if _mode != null:
        _leave_mode()
    hud.countdown = -1.0
    _level = 0
    _over_gap = false
    _boosts.reset()
    _brawl.power = 1.0
    _curve = 0.0
    _curve_goal = 0.0
    _curve_next = 0.0
    _scenery.set_bend(0.0)
    var road := {
        "encounters": _encounters,
        "boosters": _boosters,
        "platforms": _platforms,
        "forks": _forks,
        "barriers": _barriers,
        "climbs": _climbs,
    }
    var plan := RoadPlan.new(
        level,
        _chart,
        _beat_time,
        _beat_seconds,
        _intro_bars,
        _core.SectionBars(),
        _sections,
        _goal(),
        road
    )
    plan.lay()
    _chart = plan.chart


func _holds() -> bool:
    return _mode != null


## While the run is in a mode: the mode goes on, until it is over.
func _hold(delta: float) -> void:
    if _mode.hold(delta) and _phase == Phase.PLAYING:
        _leave_mode()


## The run goes into the [param mode] (see RunMode).
func _enter_mode(mode: RunMode) -> void:
    _mode = mode
    mode.enter()


## The mode is over: back to running.
func _leave_mode() -> void:
    var mode := _mode
    _mode = null
    mode.leave()


func _threatened() -> bool:
    return _mode != null and _mode.threatened()


## A punch or a kick of the player counts only in a mode (running lifts the
## knees, too, which the classifier may take for kicks).
func throw(kind: String, side: String, _source := "vision") -> void:
    if _phase != Phase.PLAYING or _paused or _mode == null:
        return
    _mode.throw(kind, side)


func _his_health() -> float:
    return -1.0 if _mode == null else _mode.health()


func _idle_command() -> String:
    if _mode != null:
        return _mode.command()
    var going := _climbs.way(_t)
    if going == "stairs" or going == "slope":
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
    hud.boosts = _boosts.shown(_now)
    hud.flash = _flash
    _flash = maxf(0.0, _flash - delta * 2.0)
    var ground := _ground()
    var climb := 4.0 if ground > boxer.elevation else 3.0
    if _climbs.way(_t) != "" or (_mode != null and _mode.ground() >= 0.0):
        climb = 8.0
    boxer.elevation = move_toward(boxer.elevation, ground, delta * climb)
    # NOTE (mristin):
    # He looks up the climb ahead, and down it.
    var rise := _climbs.height(_t + 4.0 / SPEED) - _climbs.height(_t)
    if _mode != null:
        rise = _mode.gaze_rise()
    boxer.gaze_rise = lerpf(boxer.gaze_rise, rise, minf(1.0, delta * 4.0))
    if _mode != null:
        _mode.frame(delta)
        return
    boxer.shift = lerpf(boxer.shift, _body.steer * Scenery.LANE, minf(1.0, delta * 10.0))
    boxer.face(SPOT + Vector3(boxer.shift, 0, -6.0), delta)
    show_running()
    _strip.follow(boxer.shift, _rolled)


## He runs as fast as he lifts his knees (see VisionService.GetCadence: the
## knees lifted a second): at NORMAL_CADENCE the notes come at their pace,
## faster quicker (up to FASTEST), slower slower, and standing still stops
## him. The obstacles stand on the road: he reaches them at his own pace.
func _advance(played: float) -> void:
    var pace := run_pace(played) * _boosts.speed(_now) * _climbs.pace(_t)
    var before := _t
    _t += played * pace
    var meters := played * pace * SPEED
    _rolled += meters
    _scenery.scroll(meters)
    var meeting := _encounters.move(meters, played, _time, boxer.shift, SPOT)
    if meeting >= 0:
        _enter_mode(BrawlMode.new(self, meeting))
        return
    var barrier := _barriers.reached(_t)
    if barrier >= 0:
        _enter_mode(SmashMode.new(self, barrier))
        return
    var ladder := _climbs.ladder(_t, SPEED)
    if ladder >= 0:
        _enter_mode(LadderMode.new(self, ladder))
        return
    for going in _climbs.entered(before, _t):
        on_climb(going)
    _turn(meters)
    _on_platforms()
    for look in _boosters.take(_t, boxer.shift, _ground()):
        _boost(look)
    var fork := _forks.reached(before, _t, boxer.shift)
    if not fork.is_empty():
        _log.write("fork", {"taken": fork["state"] == "taken", "song": _now})
        if fork["state"] == "taken":
            _shortcut(float(fork["skip"]))


## How fast he runs now (see _advance), after [param played] seconds of the
## song: the share of the normal pace.
func run_pace(played: float) -> float:
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
    return _pace


## How high he stands: as the mode says (up a ladder), on the climb under
## him, or on the level of a platform (see Platforms).
func _ground() -> float:
    if _mode != null and _mode.ground() >= 0.0:
        return _mode.ground()
    return maxf(_climbs.height(_t), Platforms.HEIGHT * _level)


## He goes on [param going] a climb (see Climbs): up it, on its top (points),
## or down it.
func on_climb(going: String) -> void:
    match going:
        "stairs", "slope", "ladder":
            var title := str(Climbs.LOOKS[level.get("climb", "hill")]["title"])
            hud.announce("CLIMB!", 1.2)
            hud.say("UP %s!" % title.trim_prefix("THE "), Hud.GOLD)
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
    log_event("climb", {"part": going})


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
    if _boosts.shields(_now):
        hud.say("SHIELD!", Boosters.KINDS["shield"]["color"])
        return
    _scoring.failed("hit")
    _play("hurt")
    boxer.take_damage(HURT)
    hud.say("OUCH! TWO DOWN!", Hud.RED)
    if boxer.health <= 0.0:
        _finish(false)


## He picked up the booster of the [param look] (see Boosters and Boosts).
func _boost(look: String) -> void:
    var kind: String = Boosters.LOOKS[look]["kind"]
    var spec: Dictionary = Boosters.KINDS[kind]
    _boosts.take(kind, _now)
    if kind == "health":
        boxer.health = minf(Boxer.MAX_HEALTH, boxer.health + Boosters.HEALTH)
    _brawl.power = _boosts.power()
    hud.say("%s: %s" % [Boosters.LOOKS[look]["title"], spec["effect"]], spec["color"])
    _play("perfect")
    _log.write("booster", {"look": look, "kind": kind, "song": _now})


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
    if _boosts.shields(_now):
        _met(note, "dodged")
        hud.say("SHIELD!", Boosters.KINDS["shield"]["color"])
        return
    super(note)


## Call what comes: what the mode calls, if any; else on the road, a gap of
## the platform under him to jump over (not the end of the platform), and a
## fork with its shortcut, to its side.
func _call() -> Array:
    if _mode != null:
        return _mode.cue()
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
        var across := RhythmNote.combo_parts(kind)
        gap = across[0]
        parts = across[1]
    var color: Color = OBSTACLES.get(level["scenery"], RhythmNote.ATTACK)
    note.setup(kind, side, at, arrive, SPEED, color, level["scenery"], gap, parts)


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


## The call of a combined obstacle (see RhythmNote.combo_call); the other
## notes as usual.
func _note_call(note: RhythmNote) -> Array:
    if not note.kind in RhythmNote.COMBOS:
        return super(note)
    return note.combo_call(boxer.shift)


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


# NOTE (mristin):
# Below, what the modes of the run (see RunMode) use of it.


## The opponents on the road.
func encounters() -> Encounters:
    return _encounters


## The barriers on the road.
func barriers() -> Barriers:
    return _barriers


## The climbs on the road.
func climbs() -> Climbs:
    return _climbs


## The fight with an opponent.
func brawl() -> Brawl:
    return _brawl


## The score of the run.
func score() -> Scoring:
    return _scoring


## How he dodges now (see BodyReader.dodges).
func dodges() -> Array:
    return _body.dodges()


## The song's clock (seconds since the level started, running on while the
## run holds).
func song_clock() -> float:
    return _time


## How long a beat of the song is, in seconds.
func beat_seconds() -> float:
    return _beat_seconds


## He lost: knocked out.
func lose() -> void:
    _finish(false)


## The fight is over: the power punches are spent.
func spend_power() -> void:
    _boosts.spend_power()
    _brawl.power = _boosts.power()


## Write the event of the [param name] with the [param fields] into the log,
## at the song's time.
func log_event(name: String, fields: Dictionary) -> void:
    fields["song"] = _now
    _log.write(name, fields)


## Show his strike (see RhythmLevel._show_strike).
func show_strike(kind: String, side: String) -> void:
    _show_strike(kind, side)


## He stands on the road, off any platform (to fight).
func stand_on_road() -> void:
    _level = 0
    _over_gap = false


## Put him at the time of the notes [param t] on the road.
func move_to(t: float) -> void:
    _t = t


## Show him running at his pace: his arms pump at his own steps, and the
## speedometer.
func show_running() -> void:
    boxer.running_steps = maxf(0.001, _pace * NORMAL_CADENCE * 0.5)
    hud.speed = _pace
