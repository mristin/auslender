class_name LadderMode
extends RunMode

## He reached the ladder of a climb (see Climbs): the road holds, and he
## climbs straight up as fast as he runs (lifting his knees), up the ladder
## nearest to him, and on at its top.

## How far up he looks, up the ladder (see Boxer.gaze_rise).
const LOOK_UP := 2.5

var _climbs: Climbs
var _index := 0
## How high he got.
var _climbed := 0.0


func _init(of: Run, index: int) -> void:
    super(of)
    _climbs = run.climbs()
    _index = index


func enter() -> void:
    run.move_to(_climbs.climb(_index, Run.SPEED))
    _climbed = 0.0
    run.on_climb("ladder")


func hold(delta: float) -> bool:
    _climbed += delta * run.run_pace(delta) * Climbs.LADDER_SPEED
    if _climbed < Climbs.HEIGHT:
        return false
    run.move_to(_climbs.climbed(_index))
    run.on_climb("top")
    return true


func frame(delta: float) -> void:
    var boxer := run.boxer
    boxer.shift = lerpf(boxer.shift, Climbs.ladder_at(boxer.shift), minf(1.0, delta * 6.0))
    boxer.face(Run.SPOT + Vector3(boxer.shift, 0, -6.0), delta)
    run.show_running()


func command() -> String:
    return "CLIMB: KNEES UP!"


func ground() -> float:
    return _climbed


func gaze_rise() -> float:
    return LOOK_UP
