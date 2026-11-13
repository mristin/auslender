class_name FaceLooks
extends RefCounted

## Draw the looks over the player's face in the camera picture: the unibrow
## over her brows, and the mole (the mladež) on her cheek.
##
## Each look is a picture of the face box [constant BOX] around the point
## between the eyes, in eye distances, as the cut pictures of
## dev/pictures/cut_overlay.py are: [code]assets/pictures/overlay/unibrow.png[/code]
## and [code]mole.png[/code]. Until they are painted, we draw simple ones.

## The face box of the pictures, in eye distances from the point between the
## eyes: x to the right, y down.
const BOX := Rect2(-1.5, -1.2, 3.0, 2.8)

const UNIBROW_PATH := "res://assets/pictures/overlay/unibrow.png"
const MOLE_PATH := "res://assets/pictures/overlay/mole.png"

const HAIR := Color("15110f")
const MOLE := Color("4a2a1c")

var _unibrow: Texture2D = null
var _mole: Texture2D = null
var _strokes: PackedVector2Array = PackedVector2Array()


func _init() -> void:
    if ResourceLoader.exists(UNIBROW_PATH):
        _unibrow = load(UNIBROW_PATH)
    if ResourceLoader.exists(MOLE_PATH):
        _mole = load(MOLE_PATH)

    # NOTE (mristin):
    # The hairs of the drawn unibrow, so that it looks bushy; the seed keeps
    # them the same from frame to frame.
    var random := RandomNumberGenerator.new()
    random.seed = 42
    for i in range(90):
        var x := random.randf_range(-1.0, 1.0)
        var root := Vector2(x, brow_y(x) + random.randf_range(-0.04, 0.06))
        var lean := 0.09 * signf(x) if absf(x) > 0.15 else random.randf_range(-0.04, 0.04)
        _strokes.append(root)
        _strokes.append(root + Vector2(lean, random.randf_range(-0.1, -0.06)))


## The height of the middle of the unibrow at x, in eye distances (negative is up).
static func brow_y(x: float) -> float:
    # A bushy arch over each eye, which dips a little where the brows meet.
    return -0.42 - 0.07 * cos(clampf(absf(x) - 0.5, -0.5, 0.5) * PI) + 0.03 * maxf(0.0, 0.3 - absf(x))


## Draw the looks on the canvas over the face with its center (between the
## eyes, in screen pixels), the eye distance (in screen pixels), the tilt
## (radians, clockwise) and the alpha.
func draw(canvas: CanvasItem, center: Vector2, eye_distance: float, angle: float, alpha: float) -> void:
    if alpha <= 0.0 or eye_distance <= 1.0:
        return
    canvas.draw_set_transform(center, angle, Vector2(eye_distance, eye_distance))
    var tint := Color(1, 1, 1, alpha)
    if _unibrow != null:
        canvas.draw_texture_rect(_unibrow, BOX, false, tint)
    else:
        _draw_unibrow(canvas, alpha, eye_distance)
    if _mole != null:
        canvas.draw_texture_rect(_mole, BOX, false, tint)
    else:
        canvas.draw_circle(Vector2(-0.62, 0.55), 0.065, Color(MOLE, alpha))
        canvas.draw_circle(Vector2(-0.64, 0.53), 0.02, Color(MOLE.lightened(0.3), alpha))
    canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_unibrow(canvas: CanvasItem, alpha: float, eye_distance: float) -> void:
    var line := PackedVector2Array()
    for i in range(21):
        var x := lerpf(-1.0, 1.0, i / 20.0)
        line.append(Vector2(x, brow_y(x)))
    var color := Color(HAIR, alpha)
    canvas.draw_polyline(line, color, 0.14, true)
    # NOTE (mristin):
    # The width of a line is in the units of the transform, i.e., eye
    # distances; a hair is a few screen pixels thick.
    canvas.draw_multiline(_strokes, color, 2.5 / eye_distance)
