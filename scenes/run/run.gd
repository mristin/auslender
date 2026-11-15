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
## floor shows the path he is heading on (see PathStrip), and the camera
## picture lies faintly over the scene, so that he sees where he stands (see
## CameraVeil).
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

## How far the opponents show ahead on the road, from how far they charge at
## him (at random speeds in the range, meters a second), in meters.
const APPEAR := 24.0
const CHARGE_FROM := 14.0
const CHARGE := Vector2(1.0, 2.2)

## As he comes, an opponent weaves across the road: he side-steps to a spot
## (anywhere across the road, at most this far from the middle, in lanes) at
## this speed (meters a second), and picks a new one every while (seconds, at
## random); from this far (meters), he homes in on the hero to meet him.
const WEAVE_MOST := 1.2
const SIDESTEP := 2.6
const WEAVE_EVERY := Vector2(0.6, 1.3)
const MEET_FROM := 7.0

## How much energy comes back after a knock-out.
const HEAL := 15.0

var _veil: CameraVeil
var _strip: PathStrip
var _rolled := 0.0
var _pace := 0.0
var _brawl := Brawl.new()
## The opponents on the road, in order: "id", "dist" (how far ahead of the
## hero, in meters), "x" (across the road), "charge" (his speed, meters a
## second), "spot" (where across the road he side-steps to, see WEAVE_MOST)
## and "spot_until" (when he picks a new one), "figure" (an
## Opponent, once he shows), "state" ("ahead", "fight", "down" or "gone").
var _encounters: Array = []
## The opponent fighting now (-1 if none).
var _fighting := -1
## The black sheep, who cheers the hero on from the roadside while he boxes a
## white sheep (see DESIGN.md).
var _black_sheep: Node3D


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
    # NOTE (mristin):
    # The camera picture over the scene (under the HUD).
    var layer := CanvasLayer.new()
    layer.layer = 1
    add_child(layer)
    _veil = CameraVeil.new()
    _veil.vision = vision
    layer.add_child(_veil)
    _brawl.setup(hud, boxer, _scoring, _log, play_sound, _beat_seconds)


## Put the opponents of the level on the road, each in a breather between two
## sections (spread over the run, a little off at random), and clear the road
## of obstacles around them.
func _on_start() -> void:
    for encounter in _encounters:
        if encounter["figure"] != null:
            (encounter["figure"] as Node).queue_free()
    _encounters.clear()
    _fighting = -1
    _end_fight_mode()
    var ids: Array = level.get("opponents", [])
    var bar := 4.0 * _beat_seconds
    var used := {}
    for i in range(ids.size()):
        var k := clampi(roundi((i + 1) * float(_sections.size()) / (ids.size() + 1)), 1, 99)
        while used.has(k):
            k += 1
        used[k] = true
        # NOTE (mristin):
        # The middle of the breather, the last bar of the section before.
        var at: float = (_intro_bars + _core.SectionBars() * k - 0.5) * bar
        at += randf_range(-0.2, 0.2) * bar
        _chart = _chart.filter(
            func(n: Dictionary) -> bool:
                var t := _beat_time(n)
                return t < at - 1.5 * bar or t > at + 0.75 * bar
        )
        (
            _encounters
            . append(
                {
                    "id": ids[i],
                    "dist": at * SPEED + Fight.OPPONENT_DISTANCE,
                    "x": randf_range(-1.0, 1.0) * Scenery.LANE,
                    "charge": randf_range(CHARGE.x, CHARGE.y),
                    "spot": 0.0,
                    "spot_until": 0.0,
                    "figure": null,
                    "state": "ahead",
                    "seed": randi() & 0xffff,
                }
            )
        )


func _holds() -> bool:
    return _fighting >= 0


## While they box: the brawl plays; at its end, the run goes on.
func _hold(delta: float) -> void:
    _brawl.step(delta, _body.dodges())
    if boxer.health <= 0.0:
        _finish(false)
        return
    if _brawl.active():
        return
    var encounter: Dictionary = _encounters[_fighting]
    encounter["state"] = "down"
    _fighting = -1
    boxer.health = minf(Boxer.MAX_HEALTH, boxer.health + HEAL)
    _end_fight_mode()
    hud.announce("RUN!", 1.5)
    _log.write("run_on", {"song": _now})


func _threatened() -> bool:
    return _fighting >= 0 and _brawl.threatened()


## The hero crashed into the opponent: the run turns into a fight.
func _crash(index: int) -> void:
    var encounter: Dictionary = _encounters[index]
    encounter["state"] = "fight"
    _fighting = index
    var figure: Opponent = encounter["figure"]
    figure.global_position = SPOT + Vector3(boxer.shift, 0, -Fight.OPPONENT_DISTANCE)
    figure.target = SPOT + Vector3(boxer.shift, 0, 0)
    boxer.running_steps = 0.0
    boxer.level_gaze = false
    boxer.take_damage(0.0, true)
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


## The opponents on the road: they show from afar, charge at the hero, swaying,
## and steer into his path; the one who reaches him starts a fight. Those
## knocked out are dragged to the side of the road and roll past.
func _move_opponents(meters: float, played: float) -> void:
    for i in range(_encounters.size()):
        var encounter: Dictionary = _encounters[i]
        var figure: Opponent = encounter["figure"]
        match encounter["state"]:
            "ahead":
                if i != _next_ahead():
                    continue
                var dist: float = encounter["dist"] - meters
                if dist < CHARGE_FROM:
                    dist -= float(encounter["charge"]) * played
                encounter["dist"] = dist
                if dist > APPEAR:
                    continue
                if figure == null:
                    figure = _new_figure(encounter)
                var x := _weave(encounter, dist, played)
                figure.global_position = SPOT + Vector3(x, 0, -dist)
                figure.target = SPOT + Vector3(boxer.shift, 0, 0)
                var stride := fposmod(_time * 2.6, 1.0)
                figure.groove(stride, fposmod(_time * 0.65, 1.0), floori(_time * 0.65))
                if dist <= Fight.OPPONENT_DISTANCE:
                    _crash(i)
                    return
            "down":
                var side := 1.0 if figure.global_position.x >= boxer.shift else -1.0
                var roadside := side * (RhythmNote.ROAD * 0.5 + 0.8)
                figure.global_position.x = lerpf(
                    figure.global_position.x, roadside, minf(1.0, played * 3.0)
                )
                figure.global_position.z += meters
                if figure.global_position.z > SPOT.z + 3.0:
                    figure.queue_free()
                    encounter["figure"] = null
                    encounter["state"] = "gone"


## Where across the road the opponent is now: far off, he weaves from side to
## side (side-steps to a spot, then to another); from MEET_FROM on, he homes
## in on the hero, faster and faster, so that he meets him wherever he is.
func _weave(encounter: Dictionary, dist: float, played: float) -> float:
    if _time >= float(encounter["spot_until"]):
        var spot := randf_range(-WEAVE_MOST, WEAVE_MOST) * Scenery.LANE
        # NOTE (mristin):
        # A real side-step: never just a little over.
        if absf(spot - float(encounter["x"])) < Scenery.LANE * 0.6:
            spot = (
                -signf(float(encounter["x"]) + 0.01) * randf_range(0.5, WEAVE_MOST) * Scenery.LANE
            )
        encounter["spot"] = spot
        encounter["spot_until"] = _time + randf_range(WEAVE_EVERY.x, WEAVE_EVERY.y)
    var meet := clampf(
        1.0 - (dist - Fight.OPPONENT_DISTANCE) / (MEET_FROM - Fight.OPPONENT_DISTANCE), 0.0, 1.0
    )
    var goal := lerpf(float(encounter["spot"]), boxer.shift, meet)
    var speed := SIDESTEP * (1.0 + 2.0 * meet)
    var x := move_toward(float(encounter["x"]), goal, speed * played)
    if meet >= 1.0:
        x = boxer.shift
    encounter["x"] = x
    return x


## The index of the next opponent still ahead (-1 if none).
func _next_ahead() -> int:
    for i in range(_encounters.size()):
        if _encounters[i]["state"] == "ahead":
            return i
    return -1


func _new_figure(encounter: Dictionary) -> Opponent:
    var figure := Opponent.new()
    figure.look = Levels.opponent(encounter["id"])["look"]
    figure.tint = encounter["seed"]
    add_child(figure)
    encounter["figure"] = figure
    return figure


## A punch or a kick of the player counts only in a fight (running lifts the
## knees, too, which the classifier may take for kicks).
func throw(kind: String, side: String, _source := "vision") -> void:
    if _fighting < 0 or _phase != Phase.PLAYING or _paused:
        return
    _show_strike(kind, side)
    _brawl.punch(kind, side)


func _his_health() -> float:
    if _fighting < 0:
        return -1.0
    return (_encounters[_fighting]["figure"] as Opponent).health


func _idle_command() -> String:
    if _fighting >= 0:
        return "READY"
    if _pace < 0.15:
        return "LIFT YOUR KNEES!"
    return "RUN!"


func _on_frame(delta: float) -> void:
    if _fighting >= 0:
        # NOTE (mristin):
        # In a fight, he stays where he crashed (the slips must not steer).
        var figure: Opponent = _encounters[_fighting]["figure"]
        boxer.face(figure.global_position, delta)
        boxer.running_steps = 0.0
        if _black_sheep != null:
            _black_sheep.position.y = 0.12 * absf(sin(_time * PI / _beat_seconds))
        hud.speed = -1.0
        return
    boxer.shift = lerpf(boxer.shift, _body.steer * Scenery.LANE, minf(1.0, delta * 10.0))
    boxer.face(SPOT + Vector3(boxer.shift, 0, -6.0), delta)
    _veil.steer = _body.steer
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
    _t += played * _pace
    var meters := played * _pace * SPEED
    _rolled += meters
    _scenery.scroll(meters)
    _move_opponents(meters, played)


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
    var color: Color = OBSTACLES.get(level["scenery"], RhythmNote.ATTACK)
    note.setup(kind, side, at, arrive, SPEED, color, level["scenery"], gap)


## Judge a steering note as its obstacles reach him: is he clear of them (in
## the free gap)?
func _judge(note: RhythmNote) -> bool:
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
