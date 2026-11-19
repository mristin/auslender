class_name RiggedFigure
extends Node3D

## A rigged 3D model of the hero (one of HEROES: skinned meshes on a humanoid
## skeleton with the usual names of the bones), posed on the joints of the
## pose lifted to 3D (see PoseLifter).
##
## We turn each bone of the skeleton, from the hips outwards: the hips, the
## spine and the chest with the torso (the hips, the chest and the shoulders);
## the neck and the head along the line from the chest to the head; every
## upper and lower arm along its bone (the hand goes with the lower arm); every
## upper leg towards the knee, within what a hip can do (see limit_thigh()),
## and the lower leg straight on (the ankles are only guessed). The bones keep
## their lengths; the whole model is scaled by the length of the torso.
##
## The model has no head: the head bone shrinks to nothing (its skin with it),
## so that the player's own head shows in the camera picture (see
## [CameraPanel], which draws a halo around it).
##
## The model faces +z, its left side at +x, as a person who faces the camera
## (x right, y up, z towards the camera): so give the joints as in the picture
## which is not mirrored, and mirror the rendered picture.

## The rigged models of the hero, by name; the player picks one (F3 in the
## fight), which every figure shows (see [member chosen]).
const HEROES := {
    "classic": "res://scenes/camera_panel/model/hero_classic.glb",
    "prehistoric": "res://scenes/camera_panel/model/hero_prehistoric.glb",
    "samichlaus": "res://scenes/camera_panel/model/hero_samichlaus.glb",
}

## The joints of Human3.6M which we use (see PoseLifter.Joint).
const PELVIS := 0
const RIGHT_HIP := 1
const RIGHT_KNEE := 2
const LEFT_HIP := 4
const LEFT_KNEE := 5
const THORAX := 8
const HEAD := 10
const LEFT_SHOULDER := 11
const LEFT_ELBOW := 12
const LEFT_WRIST := 13
const RIGHT_SHOULDER := 14
const RIGHT_ELBOW := 15
const RIGHT_WRIST := 16

## How big the head is (it shrinks to nothing, see above). Not quite zero, so
## that the skinning stays well defined.
const HEAD_SCALE := 1e-3

## How far a thigh may swing from hanging down, in the frame of the torso
## (degrees): forward (a knee up) and backward, outward and inward. A
## direction beyond is clamped, so that the legs never bend as no leg can.
const THIGH_FORWARD := 100.0
const THIGH_BACKWARD := 25.0
const THIGH_OUTWARD := 40.0
const THIGH_INWARD := 10.0

## The bones of a humanoid skeleton, and their names in the models (the
## names of the usual conventions; the first which a model has counts; each
## also with the prefix of Mixamo, see BONE_PREFIXES).
const BONE_NAMES := {
    "Hips": ["Hips", "hips", "Pelvis"],
    "Spine": ["Spine", "spine"],
    "Chest": ["Chest", "chest", "Spine2", "UpperChest", "Spine1"],
    "Neck": ["Neck", "neck"],
    "Head": ["Head", "head"],
    "LeftShoulder": ["LeftShoulder", "Shoulder_L", "shoulder.L"],
    "LeftUpperArm": ["LeftUpperArm", "UpperArm_L", "upper_arm.L", "LeftArm"],
    "LeftLowerArm": ["LeftLowerArm", "Forearm_L", "forearm.L", "LeftForeArm"],
    "LeftHand": ["LeftHand", "Hand_L", "hand.L"],
    "RightShoulder": ["RightShoulder", "Shoulder_R", "shoulder.R"],
    "RightUpperArm": ["RightUpperArm", "UpperArm_R", "upper_arm.R", "RightArm"],
    "RightLowerArm": ["RightLowerArm", "Forearm_R", "forearm.R", "RightForeArm"],
    "RightHand": ["RightHand", "Hand_R", "hand.R"],
    "LeftUpperLeg": ["LeftUpperLeg", "Thigh_L", "thigh.L", "LeftUpLeg"],
    "LeftLowerLeg": ["LeftLowerLeg", "Shin_L", "shin.L", "LeftLeg"],
    "LeftFoot": ["LeftFoot", "Foot_L", "foot.L"],
    "RightUpperLeg": ["RightUpperLeg", "Thigh_R", "thigh.R", "RightUpLeg"],
    "RightLowerLeg": ["RightLowerLeg", "Shin_R", "shin.R", "RightLeg"],
    "RightFoot": ["RightFoot", "Foot_R", "foot.R"],
}

## The prefixes which skeletons put before the names of their bones (Mixamo;
## the import turns its ":" into "_").
const BONE_PREFIXES := ["", "mixamorig_", "mixamorig:", "mixamorig1_"]

## The hero which the figures show.
static var chosen := "classic"

## Whether the pose sees each leg ([left, right]); a leg which it does not see
## hangs down, as at rest.
var legs_seen: Array[bool] = [true, true]

var _model: Node3D
var _skeleton: Skeleton3D
var _bones := {}
## The global rest of every bone (in the space of the skeleton).
var _rest := {}
## The global poses which we give the bones this frame.
var _pose := {}
var _skeleton_in_model := Transform3D.IDENTITY
var _skeleton_turn := Basis.IDENTITY


func _ready() -> void:
    _build()


## The next hero after the chosen one (to cycle through them).
static func next_hero() -> String:
    var names: Array = HEROES.keys()
    return names[(names.find(chosen) + 1) % names.size()]


## Show the chosen hero (after [member chosen] changed).
func rebuild() -> void:
    if _model != null:
        _model.queue_free()
        remove_child(_model)
    _bones.clear()
    _rest.clear()
    _pose.clear()
    _build()


func _build() -> void:
    _model = (load(HEROES[chosen]) as PackedScene).instantiate()
    add_child(_model)
    _skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
    # NOTE (mristin):
    # Where the skeleton sits in the model: e.g., Mixamo's works in
    # centimeters, under a node scaled by 0.01.
    _skeleton_in_model = Transform3D.IDENTITY
    var above: Node = _skeleton
    while above != _model:
        _skeleton_in_model = (above as Node3D).transform * _skeleton_in_model
        above = above.get_parent()
    _skeleton_turn = _skeleton_in_model.basis.orthonormalized()
    # NOTE (mristin):
    # The engine culls a skinned mesh by its box at rest; posed (e.g., an
    # arm stretched out), it may be seen where its rest is not. So every part
    # gets a box which holds all its poses.
    for node in _model.find_children("*", "MeshInstance3D", true, false):
        # NOTE (mristin):
        # Three meters around, in the mesh's own units (centimeters in Mixamo).
        var units := 1.0 / maxf(_mesh_scale(node as Node3D), 1e-6)
        var reach := 3.0 * units
        (node as MeshInstance3D).custom_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * 2.0 * reach)
    for name in BONE_NAMES:
        var bone := -1
        for candidate in BONE_NAMES[name]:
            for prefix in BONE_PREFIXES:
                bone = _skeleton.find_bone(prefix + candidate)
                if bone >= 0:
                    break
            if bone >= 0:
                break
        # NOTE (mristin):
        # Only the shoulders may be missing (they turn with the torso); the
        # spine and the chest are found by the shape of the skeleton, too.
        if bone < 0:
            if not name.ends_with("Shoulder") and name != "Spine" and name != "Chest":
                push_error("The model of the hero %s has no bone %s." % [chosen, name])
            continue
        _bones[name] = bone
        _rest[name] = _skeleton.get_bone_global_rest(bone)
    _find_spine()
    for name in ["Spine", "Chest"]:
        if not _bones.has(name):
            push_error("The model of the hero %s has no bone %s." % [chosen, name])
    visible = false


## Pose the model on the joints of Human3.6M (in the world, as in the picture
## which is not mirrored), or hide it with none.
func set_joints(joints: Array[Vector3]) -> void:
    visible = joints.size() == 17
    if not visible:
        return

    var rest_up: Vector3 = _at("Chest") - _at("Hips")
    var rest_side: Vector3 = _at("LeftUpperArm") - _at("RightUpperArm")
    var up := joints[THORAX] - joints[PELVIS]
    var side := joints[LEFT_SHOULDER] - joints[RIGHT_SHOULDER]
    var frame := _frame(up, side)
    var torso := frame * _frame(rest_up, rest_side).inverse()

    # NOTE (mristin):
    # The model is scaled as a whole, so that its torso is as long as his,
    # and moved so that its hips are at his; the bones only turn.
    var scale_factor := (
        (joints[THORAX] - joints[PELVIS]).length()
        / maxf((_at("Neck") - _at("Hips")).length(), 1e-4)
    )
    _model.transform = Transform3D(
        Basis.IDENTITY.scaled(Vector3.ONE * scale_factor),
        joints[PELVIS] - _at("Hips") * scale_factor
    )

    _pose.clear()
    _turn("Hips", torso)
    _turn("Spine", torso)
    _turn("Chest", torso)
    _turn("LeftShoulder", torso)
    _turn("RightShoulder", torso)
    var neck := _towards("Neck", "Head", joints[HEAD] - joints[THORAX], torso)
    _turn("Neck", neck)
    _turn("Head", neck)
    if _bones.has("Head"):
        _skeleton.set_bone_pose_scale(_bones["Head"], Vector3.ONE * HEAD_SCALE)

    for entry in [
        ["Left", LEFT_SHOULDER, LEFT_ELBOW, LEFT_WRIST],
        ["Right", RIGHT_SHOULDER, RIGHT_ELBOW, RIGHT_WRIST]
    ]:
        var key: String = entry[0]
        var upper := _towards(
            key + "UpperArm", key + "LowerArm", joints[entry[2]] - joints[entry[1]], torso
        )
        _turn(key + "UpperArm", upper)
        # NOTE (mristin):
        # The forearm turns on from the upper arm (not from the torso): so
        # that it keeps the upper arm's twist, and the sleeve does not wring.
        var lower := _towards(
            key + "LowerArm", key + "Hand", joints[entry[3]] - joints[entry[2]], upper
        )
        _turn(key + "LowerArm", lower)
        _turn(key + "Hand", lower)

    for entry in [["Left", LEFT_HIP, LEFT_KNEE, 0, 1.0], ["Right", RIGHT_HIP, RIGHT_KNEE, 1, -1.0]]:
        var key: String = entry[0]
        var wanted: Vector3 = joints[entry[2]] - joints[entry[1]]
        var rest_thigh: Vector3 = _at(key + "LowerLeg") - _at(key + "UpperLeg")
        if not legs_seen[entry[3]]:
            wanted = torso * rest_thigh
        var thigh := frame * limit_thigh(frame.inverse() * wanted, entry[4])
        # NOTE (mristin):
        # The lower leg goes on straight from the thigh (the ankles are
        # guessed), and the foot with it.
        var upper := _towards(key + "UpperLeg", key + "LowerLeg", thigh, torso)
        _turn(key + "UpperLeg", upper)
        var lower := _towards(key + "LowerLeg", key + "Foot", thigh, upper)
        _turn(key + "LowerLeg", lower)
        _turn(key + "Foot", lower)


## The spine and the chest from the skeleton itself: the chest is the parent of
## the neck, the spine the child of the hips on the way up (the names differ:
## e.g., Spine and Spine2 in Mixamo).
func _find_spine() -> void:
    if not _bones.has("Neck") or not _bones.has("Hips"):
        return
    var chain: Array[int] = []
    var bone := _skeleton.get_bone_parent(_bones["Neck"])
    while bone >= 0 and bone != _bones["Hips"]:
        chain.append(bone)
        bone = _skeleton.get_bone_parent(bone)
    if bone != _bones["Hips"] or chain.is_empty():
        return
    _bones["Chest"] = chain[0]
    _bones["Spine"] = chain[-1]
    _rest["Chest"] = _skeleton.get_bone_global_rest(chain[0])
    _rest["Spine"] = _skeleton.get_bone_global_rest(chain[-1])


## Clamp the direction of a thigh (in the frame of the torso: x to his left, y
## up, z forward) to what a hip can do; [param outwards] is +1 for the left
## leg (outward is +x) and -1 for the right one.
static func limit_thigh(direction: Vector3, outwards: float) -> Vector3:
    var d := direction.normalized()
    if not d.is_finite():
        return Vector3.DOWN
    var forward := rad_to_deg(atan2(d.z, -d.y))
    var out := rad_to_deg(atan2(d.x * outwards, Vector2(d.y, d.z).length()))
    forward = clampf(forward, -THIGH_BACKWARD, THIGH_FORWARD)
    out = clampf(out, -THIGH_INWARD, THIGH_OUTWARD)
    var pitch := deg_to_rad(forward)
    var roll := deg_to_rad(out)
    return Vector3(outwards * sin(roll), -cos(roll) * cos(pitch), cos(roll) * sin(pitch))


## Where a bone is at rest (in the space of the skeleton).
func _at(bone: String) -> Vector3:
    return _skeleton_in_model * (_rest[bone] as Transform3D).origin


## The turn of a bone (from its rest) which points it from itself to its child
## along the direction: the turn of its base (the torso, or the bone above
## it), then the shortest turn on.
func _towards(bone: String, child: String, direction: Vector3, torso: Basis) -> Basis:
    var resting := torso * (_at(child) - _at(bone))
    return _between(resting, direction) * torso


## Turn a bone from its rest; its place follows from its parent's pose (the
## bones keep their lengths). Parents must be turned before their children.
func _turn(bone: String, turn: Basis) -> void:
    if not _bones.has(bone):
        return
    var index: int = _bones[bone]
    var rest: Transform3D = _rest[bone]
    var parent := _skeleton.get_bone_parent(index)
    var origin := rest.origin
    var parent_pose := Transform3D.IDENTITY
    if parent >= 0:
        parent_pose = _global(parent)
        origin = parent_pose * _skeleton.get_bone_rest(index).origin
    # NOTE (mristin):
    # The turn is in the space of the model; the skeleton may be turned in it.
    var turned := _skeleton_turn.inverse() * turn * _skeleton_turn
    var global := Transform3D(turned * rest.basis, origin)
    _pose[index] = global
    var local := global
    if parent >= 0:
        local = parent_pose.affine_inverse() * global
    _skeleton.set_bone_pose_position(index, local.origin)
    _skeleton.set_bone_pose_rotation(index, local.basis.get_rotation_quaternion())
    _skeleton.set_bone_pose_scale(index, local.basis.get_scale())


## How much a node of the model is scaled within the model (its units per
## meter of the model).
func _mesh_scale(node: Node3D) -> float:
    var scale := Vector3.ONE
    var above: Node = node
    while above != _model and above != null:
        scale *= (above as Node3D).scale
        above = above.get_parent()
    return scale.x


## The pose of a bone now (in the space of the skeleton): as we turned it, or
## else (a bone we do not turn, e.g., Spine1 of Mixamo between the spine and
## the chest) its own pose under its parent's.
func _global(index: int) -> Transform3D:
    if _pose.has(index):
        return _pose[index]
    var parent := _skeleton.get_bone_parent(index)
    var local := _skeleton.get_bone_pose(index)
    return local if parent < 0 else _global(parent) * local


## The frame of a body part from its up direction and its side (to its left).
static func _frame(up: Vector3, side: Vector3) -> Basis:
    var y := up.normalized()
    var x := (side - y * y.dot(side)).normalized()
    if not x.is_finite() or x.length_squared() < 1e-6:
        x = Vector3.RIGHT
    return Basis(x, y, x.cross(y))


## The shortest turn from one direction to another.
static func _between(from: Vector3, to: Vector3) -> Basis:
    var a := from.normalized()
    var b := to.normalized()
    var axis := a.cross(b)
    if axis.length_squared() < 1e-8:
        return Basis.IDENTITY
    return Basis(axis.normalized(), acos(clampf(a.dot(b), -1.0, 1.0)))
