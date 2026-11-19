class_name CameraPanel
extends Control

## Show the player how the game sees him, in a panel in a corner (as in Bird
## Dog): the mirrored camera picture, his body pose as a wire, his head as a
## glowing halo (where the head detector sees it), and on top of the panel the
## command which his body gives now (see [member command]).
##
## The halo turns orange and pulses while the opponent winds up an attack, and
## green while a dodge counts. While the game sets his home spot,
## an arc fills up around the head.
##
## If the vision lifts the pose to 3D (see PoseLifter), the rigged 3D model of
## the hero (see [RiggedFigure]) stands on the wire: its joints where the
## wire's are, at the depth of the 3D pose. The figure has no head: his own
## head shows, and the halo is drawn over the figure.

## The size of the panel: the picture (4:3) and the header with the command.
const PICTURE := Vector2(512, 384)
const HEADER := 64.0

## How opaque the camera picture is.
const PICTURE_ALPHA := 0.85

## The quad of the halo, as a factor of its radii (see head_outline.gdshader).
const HALO_MARGIN := 1.4

## The score from which a key point counts for the wire.
const MIN_SCORE := 0.3

## How wide the glow of a bone is, and how big the glow of a joint, in pixels.
const BONE_WIDTH := 22.0
const JOINT_SIZE := 26.0

## The color of the wire, unless a strike shows (then the color of the command).
const WIRE := Color(0.35, 1.0, 0.6)

## How opaque the 3D figure is over the picture.
const FIGURE_ALPHA := 0.8

## Pixels of the panel per unit of the 3D world of the figure.
const _PIXELS_PER_UNIT := 100.0

## How much the joints of the 3D figure are calmed (a One-Euro filter): the
## cutoff when they stand still (Hz), how much it rises with their speed, and
## the cutoff of the speed itself. Calm when still, quick in a punch.
const CALM_CUTOFF := 1.0
const CALM_BETA := 0.6
const CALM_SPEED_CUTOFF := 1.0

## The score from which the pose sees a knee, for the legs of the figure.
const KNEE_SEEN := 0.4

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

## Whether to show the 3D figure, if there is a 3D pose.
var show_figure := true

var vision: Node = null

var _time := 0.0
var _bones: Node2D
var _joints: Node2D
var _halo: Node2D
var _head: Node2D
var _white: Texture2D
var _figure: RiggedFigure
var _calm: Array[Vector3] = []
var _calm_speed: Array[Vector3] = []
var _front: SubViewport
var _front_view: TextureRect


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(PICTURE.x, HEADER + PICTURE.y)

    # NOTE (mristin):
    # The wire is drawn by shaders, in a layer over the picture which clips its
    # glow, so that it does not spill over the header.
    _build_figure()

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

    # NOTE (mristin):
    # The halo and the arc of the calibration over the figure and the wire
    # (the figure has no head); clipped as the wire.
    var over := Control.new()
    over.mouse_filter = Control.MOUSE_FILTER_IGNORE
    over.clip_contents = true
    over.position = Vector2(0, HEADER)
    over.size = PICTURE
    add_child(over)
    var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
    image.fill(Color.WHITE)
    _white = ImageTexture.create_from_image(image)
    _halo = _shaded(over, preload("res://scenes/camera_overlay/head_outline.gdshader"))
    (_halo.material as ShaderMaterial).set_shader_parameter("margin", HALO_MARGIN)
    _halo.draw.connect(_draw_halo)
    _head = Node2D.new()
    over.add_child(_head)
    _head.draw.connect(_draw_head)


## The 3D figure: a world of its own with the model of Auslender and the
## lights, seen from the front (orthographic, so that it lines up with the
## wire). It is posed as in the picture which is not mirrored, and its view is
## mirrored, as the camera picture.
func _build_figure() -> void:
    var world := World3D.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_CLEAR_COLOR
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.6, 0.6, 0.62)
    world.environment = environment

    _front = SubViewport.new()
    _front.size = Vector2i(PICTURE)
    _front.transparent_bg = true
    _front.world_3d = world
    _front.msaa_3d = Viewport.MSAA_2X
    add_child(_front)
    _front_view = TextureRect.new()
    _front_view.texture = _front.get_texture()
    _front_view.flip_h = true
    _front_view.position = Vector2(0, HEADER)
    _front_view.size = PICTURE
    _front_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _front_view.modulate = Color(1, 1, 1, FIGURE_ALPHA)
    add_child(_front_view)

    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = PICTURE.y / _PIXELS_PER_UNIT
    camera.position = Vector3(
        PICTURE.x * 0.5 / _PIXELS_PER_UNIT, -PICTURE.y * 0.5 / _PIXELS_PER_UNIT, 50.0
    )
    camera.far = 100.0
    _front.add_child(camera)

    _figure = RiggedFigure.new()
    _front.add_child(_figure)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-35, 30, 0)
    sun.light_energy = 1.0
    _front.add_child(sun)


## Put the figure on the wire: x and y where the wire is (in the picture which
## is not mirrored), the depth from the 3D pose, scaled so that its torso is
## as long as the wire's.
func _update_figure() -> void:
    var lifted: Array = vision.GetPose3D() if vision != null and show_figure else []
    var joints: Array[Vector3] = []
    if lifted.size() == 2:
        var points: PackedVector2Array = lifted[0]
        var depths: PackedVector3Array = lifted[1]
        var torso_2d := (points[RiggedFigure.THORAX] - points[RiggedFigure.PELVIS]) * PICTURE
        var torso_3d := depths[RiggedFigure.THORAX].distance_to(depths[RiggedFigure.PELVIS])
        var scale := torso_2d.length() / maxf(torso_3d, 1e-3) / _PIXELS_PER_UNIT
        for j in range(points.size()):
            var at := Vector2(1.0 - points[j].x, points[j].y) * PICTURE / _PIXELS_PER_UNIT
            # NOTE (mristin):
            # The 3D pose has z away from the camera; our camera looks along -z.
            joints.append(Vector3(at.x, -at.y, -depths[j].z * scale))
    if not joints.is_empty():
        # NOTE (mristin):
        # A leg whose knee the pose hardly sees hangs down (COCO: 13 is the
        # left knee, 14 the right one).
        var scores: PackedFloat32Array = vision.GetKeypointScores()
        if scores.size() == 17:
            _figure.legs_seen = [scores[13] >= KNEE_SEEN, scores[14] >= KNEE_SEEN]
    _figure.set_joints(_calmed(joints, get_process_delta_time()))
    _front_view.visible = not joints.is_empty()


## Calm the jitter of the joints with a One-Euro filter (per joint): strong
## while they stand still, little while they move fast.
func _calmed(joints: Array[Vector3], delta: float) -> Array[Vector3]:
    if joints.is_empty() or _calm.size() != joints.size() or delta <= 0.0:
        _calm = joints.duplicate()
        _calm_speed.clear()
        _calm_speed.resize(joints.size())
        _calm_speed.fill(Vector3.ZERO)
        return joints
    var speed_alpha := _alpha(CALM_SPEED_CUTOFF, delta)
    for j in range(joints.size()):
        var speed := (joints[j] - _calm[j]) / delta
        _calm_speed[j] = _calm_speed[j].lerp(speed, speed_alpha)
        var cutoff := CALM_CUTOFF + CALM_BETA * _calm_speed[j].length()
        _calm[j] = _calm[j].lerp(joints[j], _alpha(cutoff, delta))
    return _calm.duplicate()


static func _alpha(cutoff: float, delta: float) -> float:
    var tau := 1.0 / (TAU * cutoff)
    return 1.0 / (1.0 + tau / delta)


## Show the chosen hero (see RiggedFigure.chosen).
func rebuild_figure() -> void:
    _figure.rebuild()


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
    _halo.queue_redraw()
    _head.queue_redraw()
    _update_figure()


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


## The head box of the head detector in the picture layer (see [method
## _draw_halo]); empty if it sees no head.
func _head_box() -> Rect2:
    if vision == null:
        return Rect2()
    var head: Rect2 = vision.GetHeadRect()
    if head.size.x <= 0.0:
        return Rect2()
    return Rect2(head.position * PICTURE, head.size * PICTURE)


## The halo around the head: a soft glowing ellipse
## (a shader on a quad), orange and pulsing while he winds up, green while a
## dodge counts.
func _draw_halo() -> void:
    var box := _head_box()
    if box.size.x <= 0.0:
        return
    var radii := box.size * 0.5 * 1.1
    var color := Color(1, 1, 1, 0.7)
    if dodging:
        color = Color(_GREEN, 0.95)
    elif threatened:
        var pulse := 0.5 + 0.5 * sin(_time * 12.0)
        color = Color(_ORANGE, 0.75 + 0.25 * pulse)
        radii *= 1.0 + 0.05 * pulse
    var quad := radii * HALO_MARGIN
    _halo.draw_texture_rect(_white, Rect2(box.get_center() - quad, quad * 2.0), false, color)


## Over the halo: the arc of the calibration, while the game sets his home spot.
func _draw_head() -> void:
    var box := _head_box()
    if box.size.x <= 0.0 or calibrated:
        return
    var radius := box.size.y * 0.5 * 1.1 * HALO_MARGIN
    var end := -PI * 0.5 + TAU * calibration_progress
    _head.draw_arc(box.get_center(), radius, -PI * 0.5, end, 40, _GOLD, 6.0, true)


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
