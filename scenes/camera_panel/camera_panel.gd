class_name CameraPanel
extends Control

## Show the player how the game sees her, in a panel in a corner (as in Bird
## Dog): the mirrored camera picture, her body pose as a wire, her head as a
## circle with her unibrow and her mladež (see [FaceLooks]), and on top of the
## panel the command which her body gives now (see [member command]).
##
## The circle around the head turns orange while the opponent winds up an
## attack, and green while a dodge counts. While the game sets her home spot,
## an arc fills up around the head.

## The size of the panel: the picture (4:3) and the header with the command.
const PICTURE := Vector2(512, 384)
const HEADER := 64.0

## How opaque the camera picture is.
const PICTURE_ALPHA := 0.85

## The distance between the eyes, as a share of the width of the head box.
const HEAD_TO_EYES := 0.4

## The score from which a key point counts for the wire.
const MIN_SCORE := 0.3

## How wide the glow of a bone is, and how big the glow of a joint, in pixels.
const BONE_WIDTH := 22.0
const JOINT_SIZE := 26.0

## The color of the wire, unless a strike shows (then the color of the command).
const WIRE := Color(0.35, 1.0, 0.6)

const _GREEN := Color("6ccf5e")
const _GOLD := Color("f2c14e")
const _ORANGE := Color(1.0, 0.55, 0.2)
const _GREY := Color(0.75, 0.77, 0.82)
const _RED := Color("ff5a4f")
const _INK := Color(0.08, 0.1, 0.14)

const _BONES := [
    [5, 6],
    [5, 7],
    [7, 9],
    [6, 8],
    [8, 10],
    [5, 11],
    [6, 12],
    [11, 12],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
]

## What the body commands now, e.g., "LEFT HOOK", "COVER" or "READY".
var command := ""

## The color of the command: gold for a strike, green for a dodge.
var command_color := _GREY

## Whether the opponent winds up an attack now, which makes the circle glow.
var threatened := false

## Whether a dodge counts now, which turns the circle green.
var dodging := false

## Whether the home spot is set, and how far setting it got, in [0, 1].
var calibrated := true
var calibration_progress := 0.0

var vision: Node = null

var _looks := FaceLooks.new()
var _time := 0.0
var _bones: Node2D
var _joints: Node2D


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(PICTURE.x, HEADER + PICTURE.y)

    # NOTE (mristin):
    # The wire is drawn by shaders, in a layer over the picture which clips its
    # glow, so that it does not spill over the header.
    var layer := Control.new()
    layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.clip_contents = true
    layer.position = Vector2(0, HEADER)
    layer.size = PICTURE
    add_child(layer)
    _bones = _shaded(layer, preload("res://scenes/camera_panel/wire_bone.gdshader"))
    _bones.draw.connect(_draw_bones)
    _joints = _shaded(layer, preload("res://scenes/camera_panel/wire_joint.gdshader"))
    _joints.draw.connect(_draw_joints)


func _shaded(parent: Node, shader: Shader) -> Node2D:
    var node := Node2D.new()
    var shader_material := ShaderMaterial.new()
    shader_material.shader = shader
    node.material = shader_material
    parent.add_child(node)
    return node


func setup(vision_service: Node) -> void:
    vision = vision_service


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()
    _bones.queue_redraw()
    _joints.queue_redraw()


## Map a point of the mirrored picture (normalized) into the panel.
func to_panel(point: Vector2) -> Vector2:
    return Vector2(0, HEADER) + point * PICTURE


func _draw() -> void:
    var whole := Rect2(Vector2.ZERO, size)
    draw_rect(Rect2(Vector2(6, 8), size), Color(0, 0, 0, 0.3))
    draw_rect(whole, _INK)

    var picture := Rect2(Vector2(0, HEADER), PICTURE)
    if vision != null:
        var texture: Texture2D = vision.GetCameraTexture()
        if texture != null and texture.get_size().x > 0:
            # NOTE (mristin):
            # The camera picture is not mirrored; we mirror it as we draw.
            draw_set_transform(Vector2(PICTURE.x, 0), 0, Vector2(-1, 1))
            draw_texture_rect(texture, picture, false, Color(1, 1, 1, PICTURE_ALPHA))
            draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
        _draw_head()

    _draw_command()
    draw_rect(whole, Color(1, 1, 1, 0.85), false, 3.0)
    draw_line(Vector2(0, HEADER), Vector2(size.x, HEADER), Color(1, 1, 1, 0.5), 2.0)


## The key points of the pose in the picture layer, and their scores; empty
## if there is no pose.
func _pose() -> Array:
    if vision == null:
        return []
    var points: PackedVector2Array = vision.GetKeypoints()
    var scores: PackedFloat32Array = vision.GetKeypointScores()
    if points.size() != 17 or scores.size() != 17:
        return []
    var placed := PackedVector2Array()
    for point in points:
        placed.append(point * PICTURE)
    return [placed, scores]


## The color of the wire: gold for a moment after a strike, else green.
func _wire_color() -> Color:
    return command_color if command_color == _GOLD else WIRE


## The bones of the wire, as quads along them for the shader.
func _draw_bones() -> void:
    var pose := _pose()
    if pose.is_empty():
        return
    var points: PackedVector2Array = pose[0]
    var scores: PackedFloat32Array = pose[1]
    var color := _wire_color()
    var colors := PackedColorArray([color, color, color, color])
    var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
    for bone in _BONES:
        if scores[bone[0]] < MIN_SCORE or scores[bone[1]] < MIN_SCORE:
            continue
        var a := points[bone[0]]
        var b := points[bone[1]]
        if a.distance_to(b) < 1.0:
            continue
        var along := (b - a).normalized()
        var across := Vector2(-along.y, along.x) * BONE_WIDTH * 0.5
        # NOTE (mristin):
        # Longer by half a width at each end, where the shader fades it.
        a -= along * BONE_WIDTH * 0.25
        b += along * BONE_WIDTH * 0.25
        _bones.draw_polygon(
            PackedVector2Array([a - across, b - across, b + across, a + across]), colors, uvs
        )


## The joints of the wire, as quads around them for the shader.
func _draw_joints() -> void:
    var pose := _pose()
    if pose.is_empty():
        return
    var points: PackedVector2Array = pose[0]
    var scores: PackedFloat32Array = pose[1]
    var color := _wire_color()
    var colors := PackedColorArray([color, color, color, color])
    var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
    var half := Vector2(JOINT_SIZE, JOINT_SIZE) * 0.5
    for i in range(5, 17):
        if scores[i] < MIN_SCORE:
            continue
        var c := points[i]
        (
            _joints
            . draw_polygon(
                PackedVector2Array(
                    [
                        c - half,
                        c + Vector2(half.x, -half.y),
                        c + half,
                        c + Vector2(-half.x, half.y),
                    ]
                ),
                colors,
                uvs
            )
        )


## The head: a circle (orange while he winds up, green while a dodge counts),
## the unibrow and the mladež, and the arc of the calibration.
func _draw_head() -> void:
    var head: Rect2 = vision.GetHeadRect()
    if head.size.x <= 0.0:
        return
    var a := to_panel(head.position)
    var b := to_panel(head.end)
    var box := Rect2(a, b - a)
    var center := box.get_center()
    var radius := box.size.y * 0.5 * 1.1

    var color := Color(1, 1, 1, 0.85)
    var width := 3.0
    if dodging:
        color = _GREEN
        width = 5.0
    elif threatened:
        var pulse := 0.5 + 0.5 * sin(_time * 12.0)
        color = Color(_ORANGE, 0.75 + 0.25 * pulse)
        width = 4.0 + 2.0 * pulse
    draw_arc(center, radius, 0.0, TAU, 40, color, width, true)

    var anchor: Dictionary = vision.GetFaceAnchor()
    if anchor["alpha"] > 0.0:
        _looks.draw(
            self,
            to_panel(anchor["center"]),
            anchor["eye_distance"] * PICTURE.x,
            anchor["angle"],
            anchor["alpha"]
        )
    else:
        # NOTE (mristin):
        # The face landmarks often fail from 2.5 to 3 m, but the head box is
        # seen on every frame: so the looks go where the eyes are in a head of
        # that size.
        var eyes := center + Vector2(0, -0.05 * box.size.y)
        _looks.draw(self, eyes, HEAD_TO_EYES * box.size.x, 0.0, 1.0)

    if not calibrated:
        var end := -PI * 0.5 + TAU * calibration_progress
        draw_arc(center, radius + 8.0, -PI * 0.5, end, 40, _GOLD, 6.0, true)


## The command of the body, big on top of the panel.
func _draw_command() -> void:
    var text := command
    var color := command_color
    if vision != null and not calibrated:
        text = "HOLD STILL"
        color = _GOLD
    var font := ThemeDB.fallback_font
    var font_size := 44
    var at := Vector2(0, HEADER * 0.5 + font_size * 0.36)
    draw_string_outline(
        font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 8, Color(0, 0, 0, 0.8)
    )
    draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
