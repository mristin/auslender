class_name RunMode
extends RefCounted

## A mode of a run in which the road holds (see Run): the song's clock stops,
## and something else goes on until it is over: a fight with an opponent
## (see BrawlMode), smashing a barrier (see SmashMode), climbing a ladder (see
## LadderMode). The run asks its mode, while it has one, what to do every
## frame, what to call, how to take his punches. The modes are parts of the
## run: they reach into its state.

## The run of the mode.
var run: Run

## The black sheep, who cheers the hero on from the roadside while he boxes a
## white sheep or smashes the poster of the herd (see DESIGN.md).
var _black_sheep: Node3D


func _init(of: Run) -> void:
    run = of


## The mode starts.
func enter() -> void:
    pass


## Go on by [param delta] seconds while the clock holds: whether the mode is
## over (then the run goes on, see [method leave]).
func hold(_delta: float) -> bool:
    return true


## Every frame, how he moves and looks (see Run._on_frame).
func frame(_delta: float) -> void:
    pass


## The call on the screen (see RhythmLevel._call), or an empty array.
func cue() -> Array:
    return []


## The command on the camera panel (see RhythmLevel._idle_command).
func command() -> String:
    return "RUN!"


## A punch or a kick of the player (see Run.throw).
func throw(_kind: String, _side: String) -> void:
    pass


## The health of what he fights (see RhythmLevel._his_health), or -1.
func health() -> float:
    return -1.0


## Whether an attack is clearly coming (see RhythmLevel._threatened).
func threatened() -> bool:
    return false


## How high he stands (see Run._ground), or -1 to stand on the road.
func ground() -> float:
    return -1.0


## How far up he looks (see Boxer.gaze_rise).
func gaze_rise() -> float:
    return 0.0


## The mode is over: back to running.
func leave() -> void:
    run.boxer.level_gaze = true
    run.hud.opponent_name = ""
    if _black_sheep != null:
        _black_sheep.queue_free()
        _black_sheep = null


## He stops running and stands, to fight.
func _stand() -> void:
    run.boxer.running_steps = 0.0
    run.boxer.level_gaze = false
    run.hud.speed = -1.0
    run.stand_on_road()


## The black sheep comes out, beside him and [param ahead] meters ahead.
func _bring_black_sheep(ahead: float) -> void:
    _black_sheep = Looks.black_sheep()
    run.add_child(_black_sheep)
    _black_sheep.position = Run.SPOT + Vector3(run.boxer.shift + 1.6, 0, -ahead)
    _black_sheep.rotation.y = 0.6


## He stands and fights, facing [param target]; the black sheep jumps to the
## beat.
func _fight_frame(target: Vector3, delta: float) -> void:
    run.boxer.face(target, delta)
    run.boxer.running_steps = 0.0
    run.hud.speed = -1.0
    if _black_sheep != null:
        _black_sheep.position.y = 0.12 * absf(sin(run.song_clock() * PI / run.beat_seconds()))
