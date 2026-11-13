class_name CameraOverlay
extends CanvasLayer

## Show the webcam dimly over the whole screen, like a mirror, as in Splash 'n'
## Splat: so that the player sees where her head is. A soft, glowing outline
## goes around her head, and turns orange and pulses while the opponent winds
## up an attack. Her unibrow and her mole sit on her face (see [FaceLooks]).
##
## We show the middle of the camera picture which fills the screen (the 4:3
## picture cut to 16:9), so the picture and the looks line up.
##
## With [member debug], it also draws what the vision sees: the key points of
## the body, the hands and the home spot.

const _SCREEN := Vector2(1920, 1080)

## The ellipse quad around the head, as a factor of its radii; see the shader.
const _MARGIN := 1.4

## How strongly the camera shows through.
@export_range(0.0, 1.0) var opacity := 0.25

## Whether the opponent winds up an attack now, which makes the outline glow.
var threatened := false

## Whether to draw what the vision sees.
var debug := false

## Whether to show the camera picture (or the video of a replay) next to the
## game, in [member pip_rect], with the skeleton and the latest moves over it.
var show_pip := false

## Where the picture in the picture goes, in screen pixels.
var pip_rect := Rect2(1300, 190, 600, 450)

## The latest moves to show over the picture in the picture, newest last.
var moves: Array[String] = []

var vision: Node = null

var _canvas: Node2D
var _outline: Node2D
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


func setup(vision_service: Node) -> void:
    vision = vision_service


func _process(delta: float) -> void:
    _time += delta
    _canvas.queue_redraw()
    _outline.queue_redraw()


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
    var a := to_pip(head.position) if show_pip else to_screen(head.position)
    var b := to_pip(head.end) if show_pip else to_screen(head.end)
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
    if show_pip:
        _draw_pip(texture)

    # NOTE (mristin):
    # The looks sit on the face: in the picture in the picture if it shows,
    # else in the picture over the whole screen.
    var anchor: Dictionary = vision.GetFaceAnchor()
    var alpha: float = anchor["alpha"]
    if alpha > 0.0:
        if show_pip:
            _looks.draw(
                _canvas,
                to_pip(anchor["center"]),
                anchor["eye_distance"] * pip_rect.size.x,
                anchor["angle"],
                alpha
            )
        else:
            var eyes: float = anchor["eye_distance"] / region().size.x
            _looks.draw(_canvas, to_screen(anchor["center"]), eyes * _SCREEN.x, anchor["angle"], alpha)


func _draw_outline() -> void:
    var head := head_on_screen()
    if head.size.x <= 0.0:
        return
    var radii := head.size * 0.5 * 1.1
    var color := Color(1, 1, 1, 0.7)
    if threatened:
        var pulse := 0.5 + 0.5 * sin(_time * 12.0)
        color = Color(1.0, 0.55, 0.2, 0.75 + 0.25 * pulse)
        radii *= 1.0 + 0.05 * pulse
    var quad := radii * _MARGIN
    _outline.draw_texture_rect(_white, Rect2(head.get_center() - quad, quad * 2.0), false, color)


## Map a point of the mirrored picture (normalized) into the picture in the picture.
func to_pip(point: Vector2) -> Vector2:
    return pip_rect.position + point * pip_rect.size


func _draw_pip(texture: Texture2D) -> void:
    _canvas.draw_rect(pip_rect.grow(6), Color(0.05, 0.06, 0.09, 0.9))
    if texture != null and texture.get_size().x > 0:
        # NOTE (mristin):
        # Mirrored, as the player sees herself.
        _canvas.draw_set_transform(Vector2(pip_rect.end.x, pip_rect.position.y), 0, Vector2(-1, 1))
        _canvas.draw_texture_rect(texture, Rect2(Vector2.ZERO, pip_rect.size), false)
        _canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
    var points: PackedVector2Array = vision.GetKeypoints()
    var scores: PackedFloat32Array = vision.GetKeypointScores()
    if points.size() == 17 and scores.size() == 17:
        for bone in _BONES:
            if scores[bone[0]] >= 0.4 and scores[bone[1]] >= 0.4:
                _canvas.draw_line(
                    to_pip(points[bone[0]]), to_pip(points[bone[1]]), Color(0.4, 1, 0.6, 0.9), 3
                )
        for i in range(17):
            if scores[i] >= 0.4:
                _canvas.draw_circle(to_pip(points[i]), 4, Color(0.4, 1, 0.6, 1))
    var font := ThemeDB.fallback_font
    var y := pip_rect.end.y - 12.0
    for i in range(moves.size() - 1, -1, -1):
        var fade := 1.0 - 0.18 * (moves.size() - 1 - i)
        _canvas.draw_string_outline(
            font, Vector2(pip_rect.position.x + 12, y), moves[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8,
            Color(0, 0, 0, fade)
        )
        _canvas.draw_string(
            font, Vector2(pip_rect.position.x + 12, y), moves[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
            Color(1, 0.85, 0.3, fade)
        )
        y -= 30.0


const _BONES := [
    [5, 6], [5, 7], [7, 9], [6, 8], [8, 10], [5, 11], [6, 12], [11, 12],
    [11, 13], [13, 15], [12, 14], [14, 16],
]


func _draw_debug() -> void:
    var points: PackedVector2Array = vision.GetKeypoints()
    var scores: PackedFloat32Array = vision.GetKeypointScores()
    if points.size() == 17 and scores.size() == 17:
        for bone in _BONES:
            if scores[bone[0]] >= 0.4 and scores[bone[1]] >= 0.4:
                _canvas.draw_line(
                    to_screen(points[bone[0]]), to_screen(points[bone[1]]), Color(0.4, 1, 0.6, 0.8), 4
                )
        for i in range(17):
            if scores[i] >= 0.4:
                _canvas.draw_circle(to_screen(points[i]), 6, Color(0.4, 1, 0.6, 0.9))
    var hands: Array = vision.GetPlayerHands()
    var colors := [Color(0.3, 0.7, 1.0), Color(1.0, 0.8, 0.2)]
    for i in range(hands.size()):
        if hands[i] != null:
            _canvas.draw_circle(to_screen(hands[i]), 18, colors[i])
