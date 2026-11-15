class_name DwellButton
extends Button

## A big button which the hand cursor clicks by holding still on it (see
## HandCursor), as in The Steppe Rescue; the mouse and the keys click it, too.
## A ring fills while the hand holds on it.

## How long the hand holds still on it to click it, in seconds.
const DWELL_SECONDS := 2.0

const PAPER := Color("f1f0ea")
const INK := Color("0c0e14")
const GOLD := Color("f2c14e")
const CRIMSON := Color("b3263a")

## How far the hand's hold got, in [0, 1].
var dwell := 0.0:
    set(value):
        dwell = value
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
    if dwell > 0.0:
        var center := Vector2(size.x - size.y * 0.5, size.y * 0.5)
        draw_arc(center, size.y * 0.32, -PI * 0.5, -PI * 0.5 + TAU * dwell, 40, GOLD, 10)
