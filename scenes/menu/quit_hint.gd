class_name QuitHint
extends Label

## Esc twice to leave (as in The Steppe Rescue): the first Esc only shows the
## hint, a second one within [constant WINDOW] seconds leaves.

const WINDOW := 2.0

var _left := 0.0


func _init(text_shown := "Press Esc again to quit.") -> void:
    text = text_shown
    horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_theme_font_size_override("font_size", 40)
    add_theme_color_override("font_color", Color("f2c14e"))
    add_theme_color_override("font_outline_color", Color("0c0e14"))
    add_theme_constant_override("outline_size", 10)
    position = Vector2(0, 1000)
    size = Vector2(1920, 60)
    visible = false


## Esc was pressed: whether it was the second time (then leave).
func press() -> bool:
    if _left > 0.0:
        return true
    _left = WINDOW
    visible = true
    return false


func _process(delta: float) -> void:
    if _left > 0.0:
        _left -= delta
        visible = _left > 0.0
