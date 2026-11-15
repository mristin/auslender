class_name MenuScreen
extends Control

## The base of the menu screens: the dark background, the title, the hand
## cursor (see HandCursor), and Esc: back, or on the first screen twice to quit
## (see QuitHint).

const PAPER := Color("f1f0ea")
const INK := Color("0c0e14")
const GOLD := Color("f2c14e")

var _quit: QuitHint


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    var background := ColorRect.new()
    background.color = INK
    background.set_anchors_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    _build()
    _quit = QuitHint.new()
    add_child(_quit)
    add_child(HandCursor.new())


## Build the screen (in the subclasses).
func _build() -> void:
    pass


## Esc: go back (in the subclasses); the first screen quits on a second Esc.
func _back() -> void:
    if _quit.press():
        get_tree().quit()


## A big text.
func _title(text: String, at: Vector2, font_size := 72, color := GOLD) -> Label:
    var label := Label.new()
    label.text = text
    label.position = at
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    add_child(label)
    return label


func _button(
    text: String, at: Vector2, extent := Vector2(600, 110), font_size := 44
) -> DwellButton:
    var button := DwellButton.new(text, at, extent, font_size)
    add_child(button)
    return button


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if (event as InputEventKey).keycode == KEY_ESCAPE:
            _back()
            get_viewport().set_input_as_handled()
        else:
            _key((event as InputEventKey).keycode)


## A key (but Esc) was pressed (in the subclasses).
func _key(_code: int) -> void:
    pass
