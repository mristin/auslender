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
## branches, looking straight ahead (the view does not tilt). A run has no
## punches. A strip on the floor shows the path he is heading on (see
## PathStrip), and the camera picture lies faintly over the scene, so that he
## sees where he stands (see CameraVeil).

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
const NORMAL_CADENCE := 2.0
const FASTEST := 1.5

## How high he flies in a jump, in meters.
const JUMP_HEIGHT := 0.8

var _veil: CameraVeil
var _strip: PathStrip
var _rolled := 0.0
var _pace := 0.0


func _is_run() -> bool:
    return true


func _build() -> void:
    _body.running = true
    boxer.jump_height = JUMP_HEIGHT
    boxer.jump_seconds = BodyReader.RUN_JUMP_HOLD
    boxer.running_steps = 0.001
    boxer.level_gaze = true
    hud.opponent_name = ""
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


func _idle_command() -> String:
    if _pace < 0.15:
        return "LIFT YOUR KNEES!"
    return "RUN! %d%%" % roundi(_pace * 100.0)


func _on_frame(delta: float) -> void:
    boxer.shift = lerpf(boxer.shift, _body.steer * Scenery.LANE, minf(1.0, delta * 10.0))
    boxer.face(SPOT + Vector3(boxer.shift, 0, -6.0), delta)
    _veil.steer = _body.steer
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
    _pace = lerpf(_pace, wanted, minf(1.0, played * 3.0))
    _t += played * _pace
    var meters := played * _pace * SPEED
    _rolled += meters
    _scenery.scroll(meters)


## Arrived at the end of the road: the run is won by the grade; the song (the
## time) ran out before: too slow.
func _check_end() -> void:
    if _t >= _goal():
        _finish(false)
    elif _now >= _length:
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
