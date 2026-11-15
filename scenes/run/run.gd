class_name Run
extends RhythmLevel

## A run through the land of the world (see RhythmLevel and Levels), as the
## penguin of Antarctic Adventure: the land rolls towards the player on the
## beat, and its obstacles come as notes. He steers continuously with his
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

## How high he flies in a jump, in meters.
const JUMP_HEIGHT := 0.8

var _veil: CameraVeil
var _strip: PathStrip
var _rolled := 0.0


func _is_run() -> bool:
    return true


func _build() -> void:
    _body.running = true
    boxer.jump_height = JUMP_HEIGHT
    boxer.jump_seconds = BodyReader.RUN_JUMP_HOLD
    boxer.running_steps = float(level["bpm"]) / 60.0
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


func _help() -> String:
    return "Keys: arrows steer, X jump, Z duck, R again, Esc Esc leave"


func _idle_command() -> String:
    return "RUN!"


func _on_frame(delta: float) -> void:
    boxer.shift = lerpf(boxer.shift, _body.steer * Scenery.LANE, minf(1.0, delta * 10.0))
    boxer.face(SPOT + Vector3(boxer.shift, 0, -6.0), delta)
    _veil.steer = _body.steer
    _strip.follow(boxer.shift, _rolled)


## The land rolls towards him as fast as the notes.
func _on_song(played: float, _attack: RhythmNote) -> void:
    _rolled += played * SPEED
    _scenery.scroll(played * SPEED)


## The notes which do not span the road (none now; the rings of a fight)
## follow him.
func _place(note: RhythmNote) -> void:
    if not note.spans_road():
        note.follow = boxer.shift
    note.place(_now)


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
    if _now < note.at + _latency:
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
    return "ARRIVED!" if won else "TRY AGAIN"
