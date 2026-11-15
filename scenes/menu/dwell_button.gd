class_name DwellButton
extends Button

## A big button which a hand cursor clicks by holding on it for three seconds
## (see HandCursor), as in The Steppe Rescue; the mouse and the keys click it,
## too.
## A ring fills while the hand holds on it.

## How long a hand holds on it to click it, in seconds (as in The Steppe
## Rescue).
const DWELL_SECONDS := 3.0

const PAPER := Color("f1f0ea")
const INK := Color("0c0e14")
const GOLD := Color("f2c14e")
const CRIMSON := Color("b3263a")

## How far the hand's hold got, in [0, 1].
var dwell := 0.0:
    set(value):
        dwell = value
        queue_redraw()

## A small symbol drawn left of the text: "" for none, or "trash" (a bin, for
## deleting, as in Bird Dog).
var symbol := "":
    set(value):
        symbol = value
        queue_redraw()

## Whether it is the main choice of its screen (crimson).
var primary := false:
    set(value):
        primary = value
        _style()


func _init(label := "", at := Vector2.ZERO, extent := Vector2(600, 110), font_size := 44) -> void:
    text = label
    position = at
    size = extent
    add_theme_font_size_override("font_size", font_size)
    add_to_group("dwell")
    _style()


## Click it (as the hand does).
func click() -> void:
    if not disabled:
        dwell = 0.0
        pressed.emit()


func _style() -> void:
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var box := StyleBoxFlat.new()
        box.bg_color = CRIMSON if primary else Color(0.16, 0.18, 0.24)
        if state == "hover" or state == "focus":
            box.bg_color = box.bg_color.lightened(0.15)
            box.border_color = GOLD
            box.set_border_width_all(6)
        if state == "disabled":
            box.bg_color = Color(0.1, 0.11, 0.14)
        box.set_corner_radius_all(14)
        add_theme_stylebox_override(state, box)
    add_theme_color_override("font_color", PAPER)
    add_theme_color_override("font_hover_color", PAPER)
    add_theme_color_override("font_focus_color", PAPER)
    add_theme_color_override("font_disabled_color", Color(PAPER, 0.4))


func _draw() -> void:
    if symbol == "trash":
        var font := get_theme_font("font")
        var font_size := get_theme_font_size("font_size")
        var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        var height := font_size * 1.1
        _draw_trash(Vector2(size.x * 0.5 - width * 0.5 - height * 0.6, size.y * 0.5), height)
    if dwell > 0.0:
        var center := Vector2(size.x - size.y * 0.5, size.y * 0.5)
        draw_arc(center, size.y * 0.32, -PI * 0.5, -PI * 0.5 + TAU * dwell, 40, GOLD, 10)


## A bin centered at the point, about as high as the height: the lid with its
## handle, and the can, narrower at the bottom, with three grooves (as in Bird
## Dog).
func _draw_trash(center: Vector2, height: float) -> void:
    var h := height
    var width := maxf(2.0, h * 0.08)
    var color := Color(PAPER, 0.4) if disabled else PAPER
    var lid := center.y - h * 0.36
    draw_line(
        Vector2(center.x - h * 0.36, lid), Vector2(center.x + h * 0.36, lid), color, width, true
    )
    draw_rect(
        Rect2(Vector2(center.x - h * 0.1, lid - h * 0.1), Vector2(h * 0.2, h * 0.1)),
        color,
        false,
        width * 0.8
    )
    var can := PackedVector2Array(
        [
            center + Vector2(-h * 0.3, -h * 0.28),
            center + Vector2(h * 0.3, -h * 0.28),
            center + Vector2(h * 0.24, h * 0.42),
            center + Vector2(-h * 0.24, h * 0.42),
            center + Vector2(-h * 0.3, -h * 0.28),
        ]
    )
    draw_polyline(can, color, width, true)
    for x in [-0.1, 0.0, 0.1]:
        draw_line(
            center + Vector2(h * x, -h * 0.18),
            center + Vector2(h * x * 0.85, h * 0.32),
            color,
            width * 0.7,
            true
        )
