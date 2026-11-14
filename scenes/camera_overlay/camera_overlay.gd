class_name CameraOverlay
extends CanvasLayer

## Show the webcam dimly over the whole screen, like a mirror, as in Splash 'n'
## Splat: so that the player sees where her head is. There is no other camera
## picture on the screen; all that the player needs to know about her body is
## drawn on the mirror, on her head:
##
## - a soft, glowing circle around the head, which turns orange and pulses
##   while the opponent winds up an attack, and green while a dodge counts
##   (see [member pose]), with the name of the dodge under it;
## - her unibrow and her mladež (the mole) on her face (see [FaceLooks]);
## - while the game sets her home spot, an arc around the head which fills up.
##
## We show the middle of the camera picture which fills the screen (the 4:3
## picture cut to 16:9), so the picture and the looks line up.
##
## With [member debug], it also draws what the vision sees: the key points of
## the body and the hands.

const _SCREEN := Vector2(1920, 1080)

## The ellipse quad around the head, as a factor of its radii; see the shader.
const _MARGIN := 1.4

## The distance between the eyes, as a share of the width of the head box.
const HEAD_TO_EYES := 0.4

const _GREEN := Color("6ccf5e")
const _GOLD := Color("f2c14e")

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

## How strongly the camera shows through.
@export_range(0.0, 1.0) var opacity := 0.3

## Whether the opponent winds up an attack now, which makes the circle glow.
var threatened := false

## The dodge which counts now ("SLIP LEFT", "DUCK", "BLOCK", ...; "" if
## none), which turns the circle green and shows under it.
var pose := ""

## Whether the home spot is set, and how far setting it got, in [0, 1].
var calibrated := true
var calibration_progress := 0.0

## Whether to draw what the vision sees.
var debug := false

var vision: Node = null

var _canvas: Node2D
var _outline: Node2D
var _marks: Node2D
var _looks := FaceLooks.new()
var _white: Texture2D
var _time := 0.0


func _ready() -> void:
    layer = 1
    _canvas = Node2D.new()
    add_child(_canvas)
    _canvas.draw.connect(_draw_camera)

    var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
    image.fill(Color.WHITE)
    _white = ImageTexture.create_from_image(image)
    _outline = Node2D.new()
    var shader_material := ShaderMaterial.new()
    shader_material.shader = preload("res://scenes/camera_overlay/head_outline.gdshader")
    shader_material.set_shader_parameter("margin", _MARGIN)
    _outline.material = shader_material
    add_child(_outline)
    _outline.draw.connect(_draw_outline)

    # NOTE (mristin):
    # The marks over the circle (the arc and the name of the dodge) are drawn
    # after it, so that they are not covered by its glow.
    _marks = Node2D.new()
    add_child(_marks)
    _marks.draw.connect(_draw_marks)


func setup(vision_service: Node) -> void:
    vision = vision_service


func _process(delta: float) -> void:
    _time += delta
    _canvas.queue_redraw()
    _outline.queue_redraw()
    _marks.queue_redraw()


## The region of the picture (normalized) which fills the screen.
func region() -> Rect2:
    var size := Vector2(640, 480)
    if vision != null:
        size = vision.GetPictureSize()
    var aspect := size.x / maxf(1.0, size.y)
    var screen := _SCREEN.x / _SCREEN.y
    if aspect < screen:
        var height := aspect / screen
        return Rect2(0.0, (1.0 - height) * 0.5, 1.0, height)
    var width := screen / aspect
    return Rect2((1.0 - width) * 0.5, 0.0, width, 1.0)


## Map a point of the mirrored picture (normalized) to the screen.
func to_screen(point: Vector2) -> Vector2:
    var shown := region()
    return (point - shown.position) / shown.size * _SCREEN


## The head of the player on the screen, or an empty rectangle.
func head_on_screen() -> Rect2:
    if vision == null:
        return Rect2()
    var head: Rect2 = vision.GetHeadRect()
    if head.size.x <= 0.0:
        return Rect2()
    var a := to_screen(head.position)
    var b := to_screen(head.end)
    return Rect2(a, b - a)


func _draw_camera() -> void:
    if vision == null:
        return
    var texture: Texture2D = vision.GetCameraTexture()
    if texture != null and texture.get_size().x > 0:
        var size := texture.get_size()
        var shown := region()
        var source := Rect2(shown.position * size, shown.size * size)
        # NOTE (mristin):
        # The camera picture is not mirrored; we mirror it as we draw.
        _canvas.draw_set_transform(Vector2(_SCREEN.x, 0), 0, Vector2(-1, 1))
        _canvas.draw_texture_rect_region(
            texture, Rect2(Vector2.ZERO, _SCREEN), source, Color(1, 1, 1, opacity)
        )
        _canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

    if debug:
        _draw_debug()

    var anchor: Dictionary = vision.GetFaceAnchor()
    var alpha: float = anchor["alpha"]
    if alpha > 0.0:
        var eyes: float = anchor["eye_distance"] / region().size.x
        _looks.draw(_canvas, to_screen(anchor["center"]), eyes * _SCREEN.x, anchor["angle"], alpha)
        return

    # NOTE (mristin):
    # The face landmarks often fail from 2.5 to 3 m, but the head box is seen
    # on every frame: so the circle around the head always carries the unibrow
    # and the mladež, put where the eyes are in a head of that size.
    var head := head_on_screen()
    if head.size.x > 0.0:
        var center := head.get_center() + Vector2(0, -0.05 * head.size.y)
        _looks.draw(_canvas, center, HEAD_TO_EYES * head.size.x, 0.0, 1.0)


func _draw_outline() -> void:
    var head := head_on_screen()
    if head.size.x <= 0.0:
        return
    var radii := head.size * 0.5 * 1.1
    var color := Color(1, 1, 1, 0.7)
    if pose != "":
        color = Color(_GREEN, 0.95)
    elif threatened:
        var pulse := 0.5 + 0.5 * sin(_time * 12.0)
        color = Color(1.0, 0.55, 0.2, 0.75 + 0.25 * pulse)
        radii *= 1.0 + 0.05 * pulse
    var quad := radii * _MARGIN
    _outline.draw_texture_rect(_white, Rect2(head.get_center() - quad, quad * 2.0), false, color)


## Draw the arc of the calibration around the head, and the name of the dodge
## under it.
func _draw_marks() -> void:
    var head := head_on_screen()
    if head.size.x <= 0.0:
        return
    var radius := head.size.y * 0.5 * 1.1 + 14.0
    var font := ThemeDB.fallback_font
    var below := head.get_center() + Vector2(-300, radius + 44)
    if not calibrated:
        var end := -PI * 0.5 + TAU * calibration_progress
        _marks.draw_arc(head.get_center(), radius, -PI * 0.5, end, 48, _GOLD, 8)
        _label(font, below, "HOLD STILL", _GOLD)
    elif pose != "":
        _label(font, below, pose, _GREEN)


func _label(font: Font, at: Vector2, text: String, color: Color) -> void:
    _marks.draw_string_outline(
        font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, 10, Color(0, 0, 0, 0.8)
    )
    _marks.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, color)


func _draw_debug() -> void:
    var points: PackedVector2Array = vision.GetKeypoints()
    var scores: PackedFloat32Array = vision.GetKeypointScores()
    if points.size() == 17 and scores.size() == 17:
        for bone in _BONES:
            if scores[bone[0]] >= 0.4 and scores[bone[1]] >= 0.4:
                _canvas.draw_line(
                    to_screen(points[bone[0]]),
                    to_screen(points[bone[1]]),
                    Color(0.4, 1, 0.6, 0.8),
                    4
                )
        for i in range(17):
            if scores[i] >= 0.4:
                _canvas.draw_circle(to_screen(points[i]), 6, Color(0.4, 1, 0.6, 0.9))
    var hands: Array = vision.GetPlayerHands()
    var colors := [Color(0.3, 0.7, 1.0), Color(1.0, 0.8, 0.2)]
    for i in range(hands.size()):
        if hands[i] != null:
            _canvas.draw_circle(to_screen(hands[i]), 18, colors[i])
