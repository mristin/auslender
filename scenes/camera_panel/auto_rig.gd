class_name AutoRig
extends RefCounted

## Rig a static model of a person (one mesh, no skeleton) when it loads, so
## that RiggedFigure can pose it: stand it upright and turn it to face +z (the
## [param turn]), place the joints from its shape and the usual proportions of
## a body, build a humanoid skeleton with the names of RiggedFigure, and weight
## every vertex to its two nearest bones (on its own side), blended by distance,
## so that it bends smoothly at the joints.
##
## The model must stand in a T- or A-pose: the hands are its outermost points,
## to the sides. The result is cached by the path of the model.

## The joints of a body standing in an A-pose, as shares of its height (y from
## the soles; x from the middle, to its left); the hands come from the shape.
const PROPORTIONS := {
    "Hips": Vector2(0.0, 0.36),
    "Spine": Vector2(0.0, 0.46),
    "Chest": Vector2(0.0, 0.62),
    "Neck": Vector2(0.0, 0.74),
    "Head": Vector2(0.0, 0.8),
    "Shoulder": Vector2(0.07, 0.72),
    "UpperArm": Vector2(0.115, 0.72),
    "UpperLeg": Vector2(0.083, 0.35),
    "LowerLeg": Vector2(0.085, 0.22),
    "Foot": Vector2(0.087, 0.07),
}

## The bones: name, parent, and where they end (the joint of the child, for
## the weights).
const BONES := [
    ["Hips", ""],
    ["Spine", "Hips"],
    ["Chest", "Spine"],
    ["Neck", "Chest"],
    ["Head", "Neck"],
    ["LeftShoulder", "Chest"],
    ["LeftUpperArm", "LeftShoulder"],
    ["LeftLowerArm", "LeftUpperArm"],
    ["LeftHand", "LeftLowerArm"],
    ["RightShoulder", "Chest"],
    ["RightUpperArm", "RightShoulder"],
    ["RightLowerArm", "RightUpperArm"],
    ["RightHand", "RightLowerArm"],
    ["LeftUpperLeg", "Hips"],
    ["LeftLowerLeg", "LeftUpperLeg"],
    ["LeftFoot", "LeftLowerLeg"],
    ["RightUpperLeg", "Hips"],
    ["RightLowerLeg", "RightUpperLeg"],
    ["RightFoot", "RightLowerLeg"],
]

static var _cache := {}


## The rigged model (a new scene: a Skeleton3D with the skinned mesh), from a
## static one turned by [param turn]; cached by [param key].
static func rig(model: Node3D, turn: Basis, key: String) -> Node3D:
    if not _cache.has(key):
        _cache[key] = _build(model, turn)
    return (_cache[key] as PackedScene).instantiate()


static func _build(model: Node3D, turn: Basis) -> PackedScene:
    var source: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
    var arrays := source.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
    for i in range(vertices.size()):
        vertices[i] = turn * vertices[i]
    if normals != null:
        var turned: PackedVector3Array = normals
        for i in range(turned.size()):
            turned[i] = turn * turned[i]
        arrays[Mesh.ARRAY_NORMAL] = turned
    arrays[Mesh.ARRAY_VERTEX] = vertices

    var joints := _joints(vertices)
    var root := Node3D.new()
    root.name = "AutoRigged"
    var skeleton := Skeleton3D.new()
    skeleton.name = "Skeleton3D"
    root.add_child(skeleton)
    skeleton.owner = root
    var skin := Skin.new()
    for bone in BONES:
        var index := skeleton.add_bone(bone[0])
        var at: Vector3 = joints[bone[0]]
        var parent_at := Vector3.ZERO
        if bone[1] != "":
            skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
            parent_at = joints[bone[1]]
        skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, at - parent_at))
        skin.add_named_bind(bone[0], Transform3D(Basis.IDENTITY, -at))
    # NOTE (mristin):
    # New bones have no pose; at rest until somebody poses them.
    skeleton.reset_bone_poses()

    var segments := _segments(joints)
    var head := skeleton.find_bone("Head")
    var neck: Vector3 = joints["Neck"]
    var chest: Vector3 = joints["Chest"]
    var head_from := chest.y + (neck.y - chest.y) * 0.3
    var head_width: float = (joints["LeftUpperArm"] as Vector3).x * 0.75
    var bones := PackedInt32Array()
    var weights := PackedFloat32Array()
    bones.resize(vertices.size() * 4)
    weights.resize(vertices.size() * 4)
    for i in range(vertices.size()):
        var v := vertices[i]
        var best := [-1, -1]
        var near := [INF, INF]
        for s in range(segments.size()):
            var segment: Array = segments[s]
            # NOTE (mristin):
            # A vertex binds only to the limbs of its own side (or the middle).
            var side: float = segment[3]
            if side * v.x < -0.02:
                continue
            var d := _distance(v, segment[1], segment[2])
            if d < near[0]:
                near[1] = near[0]
                best[1] = best[0]
                near[0] = d
                best[0] = segment[0]
            elif d < near[1] and segment[0] != best[0]:
                near[1] = d
                best[1] = segment[0]
        # NOTE (mristin):
        # The head with all that hangs from it (a beard, the flaps of a hat),
        # down to the chest and narrower than the shoulders, goes with the
        # head alone: so that hiding the head hides it all.
        if v.y > head_from and absf(v.x) < head_width:
            bones[4 * i] = head
            weights[4 * i] = 1.0
            continue
        var w0 := 1.0 / pow(maxf(near[0], 1e-3), 4.0)
        var w1 := 0.0 if best[1] < 0 else 1.0 / pow(maxf(near[1], 1e-3), 4.0)
        var total := w0 + w1
        bones[4 * i] = best[0]
        bones[4 * i + 1] = maxi(best[1], 0)
        weights[4 * i] = w0 / total
        weights[4 * i + 1] = w1 / total
    arrays[Mesh.ARRAY_BONES] = bones
    arrays[Mesh.ARRAY_WEIGHTS] = weights

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var instance := MeshInstance3D.new()
    instance.name = "Body"
    instance.mesh = mesh
    instance.skin = skin
    # NOTE (mristin):
    # The model's own material (e.g., painted textures), or else its colors
    # per vertex.
    var material := source.get_active_material(0)
    if material == null or arrays[Mesh.ARRAY_TEX_UV] == null:
        var colored := StandardMaterial3D.new()
        colored.vertex_color_use_as_albedo = true
        colored.roughness = 1.0
        material = colored
    instance.material_override = material
    skeleton.add_child(instance)
    instance.owner = root
    instance.skeleton = NodePath("..")

    var scene := PackedScene.new()
    scene.pack(root)
    root.free()
    return scene


## Where the joints are: from the proportions of the height, but the hands at
## the outermost points of each side, and the elbows between the shoulders
## and the hands.
static func _joints(vertices: PackedVector3Array) -> Dictionary:
    var low := INF
    var high := -INF
    for v in vertices:
        low = minf(low, v.y)
        high = maxf(high, v.y)
    var height := high - low
    var joints := {}
    for name in ["Hips", "Spine", "Chest", "Neck", "Head"]:
        var share: Vector2 = PROPORTIONS[name]
        joints[name] = Vector3(0.0, low + share.y * height, 0.0)
    for side in [["Left", 1.0], ["Right", -1.0]]:
        var key: String = side[0]
        var sign: float = side[1]
        for part in ["Shoulder", "UpperArm", "UpperLeg", "LowerLeg", "Foot"]:
            var share: Vector2 = PROPORTIONS[part]
            joints[key + part] = Vector3(sign * share.x * height, low + share.y * height, 0.0)
        # NOTE (mristin):
        # The hand: the middle of the outermost tenth of the arm.
        var reach := 0.0
        for v in vertices:
            reach = maxf(reach, v.x * sign)
        var sum := Vector3.ZERO
        var count := 0
        for v in vertices:
            if v.x * sign > reach - height * 0.05:
                sum += v
                count += 1
        var hand: Vector3 = sum / maxf(count, 1)
        var shoulder: Vector3 = joints[key + "UpperArm"]
        joints[key + "LowerArm"] = shoulder.lerp(hand, 0.5)
        joints[key + "Hand"] = shoulder.lerp(hand, 0.88)
    return joints


## The segments of the bones, for the weights: [bone index, start, end, side
## (+1 left, -1 right, 0 middle)].
static func _segments(joints: Dictionary) -> Array:
    var ends := {
        "Hips": "Spine",
        "Spine": "Chest",
        "Chest": "Neck",
        "Neck": "Head",
        "LeftShoulder": "LeftUpperArm",
        "LeftUpperArm": "LeftLowerArm",
        "LeftLowerArm": "LeftHand",
        "RightShoulder": "RightUpperArm",
        "RightUpperArm": "RightLowerArm",
        "RightLowerArm": "RightHand",
        "LeftUpperLeg": "LeftLowerLeg",
        "LeftLowerLeg": "LeftFoot",
        "RightUpperLeg": "RightLowerLeg",
        "RightLowerLeg": "RightFoot",
    }
    var segments := []
    for b in range(BONES.size()):
        var name: String = BONES[b][0]
        var start: Vector3 = joints[name]
        var end: Vector3
        if ends.has(name):
            end = joints[ends[name]]
        elif name == "Head":
            end = (
                start
                + (
                    Vector3(0, 0.25, 0)
                    * (joints["Head"] as Vector3).distance_to(joints["Neck"])
                    * 4.0
                )
            )
        elif name.ends_with("Hand"):
            var forearm: Vector3 = start - (joints[name.replace("Hand", "LowerArm")] as Vector3)
            end = start + forearm * 0.4
        else:
            end = start + Vector3(0, -0.05, 0.08)
        var side := 0.0
        if name.begins_with("Left"):
            side = 1.0
        elif name.begins_with("Right"):
            side = -1.0
        segments.append([b, start, end, side])
    return segments


static func _distance(point: Vector3, a: Vector3, b: Vector3) -> float:
    var ab := b - a
    var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
    return point.distance_to(a + ab * t)
