class_name Moves
extends RefCounted

## The moves of the opponents, captured from people (see
## dev/animation/extract_moves.py): the guard, the punches, the knees, the
## slips, the duck and the cover, each the average of some thirty repetitions
## of the guided recordings, lifted to 3D and fitted to the rig of the
## opponents (see Looks). The opponent plays them (see Opponent) instead of
## poses set by hand, so that he moves as a person moves.
##
## A pose is a PackedFloat32Array of POSE_SIZE: for each arm (his left first,
## at -X) the rotation of the shoulder (y, x, z) and of the elbow (x); for
## each leg the rotation of the hip (x, z) and of the knee (x); the rotation
## of the torso (x, y, z) and of the head (x, y, z); and the offset of the body
## (x, y, z), in meters. The rotations are those of the pivots as they are, in
## radians.

const PATH := "res://scenes/opponent/moves/moves.json"

## Where the parts of a pose start (see the class).
const ARMS := 0
const LEGS := 8
const TORSO := 14
const HEAD := 17
const OFFSET := 20
const POSE_SIZE := 23

## The clips by name: {"fps", "hit" (the frame of the impact or the peak),
## "frames" (poses)}.
static var _clips := {}


## Whether the clip of the name is there.
static func has(clip: String) -> bool:
    _load()
    return _clips.has(clip)


## How long the clip of the name runs, in seconds.
static func length(clip: String) -> float:
    _load()
    var spec: Dictionary = _clips[clip]
    return (spec["frames"].size() - 1) / float(spec["fps"])


## When the clip of the name strikes (or peaks), in seconds from its start.
static func hit(clip: String) -> float:
    _load()
    var spec: Dictionary = _clips[clip]
    return int(spec["hit"]) / float(spec["fps"])


## The pose of the clip of the name at [param seconds] from its start
## (held at its ends; looped around with [param loop]).
static func sample(clip: String, seconds: float, loop := false) -> PackedFloat32Array:
    _load()
    var spec: Dictionary = _clips[clip]
    var frames: Array = spec["frames"]
    var at := seconds * float(spec["fps"])
    if loop:
        at = fposmod(at, float(frames.size()))
    else:
        at = clampf(at, 0.0, frames.size() - 1.0)
    var index := floori(at)
    var next := (index + 1) % frames.size() if loop else mini(index + 1, frames.size() - 1)
    return mix(frames[index], frames[next], at - index)


## The pose between two poses, by [param weight].
static func mix(
    from: PackedFloat32Array, to: PackedFloat32Array, weight: float
) -> PackedFloat32Array:
    var mixed := PackedFloat32Array()
    mixed.resize(POSE_SIZE)
    for i in range(POSE_SIZE):
        mixed[i] = lerpf(from[i], to[i], weight)
    return mixed


## The pose of a frame of moves.json.
static func _pose(frame: Dictionary) -> PackedFloat32Array:
    var pose := PackedFloat32Array()
    for arm: Array in frame["arms"]:
        pose.append_array(PackedFloat32Array(arm))
    for leg: Array in frame["legs"]:
        pose.append_array(PackedFloat32Array(leg))
    for key in ["torso", "head", "offset"]:
        pose.append_array(PackedFloat32Array(frame[key]))
    assert(pose.size() == POSE_SIZE)
    return pose


static func _load() -> void:
    if not _clips.is_empty():
        return
    var file := FileAccess.open(PATH, FileAccess.READ)
    if file == null:
        push_error("Could not read the moves of the opponents from %s." % PATH)
        return
    var data: Dictionary = JSON.parse_string(file.get_as_text())
    for clip: String in data["clips"]:
        var spec: Dictionary = data["clips"][clip]
        var frames: Array = []
        for frame: Dictionary in spec["frames"]:
            frames.append(_pose(frame))
        _clips[clip] = {"fps": float(spec["fps"]), "hit": int(spec["hit"]), "frames": frames}
