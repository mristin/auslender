class_name Results
extends Control

## The choices after a level (see RhythmLevel): the next level (if he won it
## and there is one), the same level again, or the levels. They stand high on
## the screen, where a raised hand reaches them, over the camera picture (dim,
## see CameraMirror), so that the player sees where his hands point (see
## HandCursor). Enter chooses the main one.

var _main: DwellButton


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


## Show the choices after the level of the id, which he [param won] or not.
func setup(id: String, won: bool) -> void:
    add_child(CameraMirror.new())
    var index := Levels.index_of(id)
    var choices := []
    if won and index + 1 < Levels.ALL_LEVELS.size():
        var next_id: String = Levels.ALL_LEVELS[index + 1]["id"]
        choices.append(["NEXT", func() -> void: Flow.play(get_tree(), next_id)])
    choices.append(["AGAIN", func() -> void: Flow.play(get_tree(), id)])
    choices.append(["LEVELS", func() -> void: Flow.levels(get_tree())])
    var width := 420.0
    var x := (1920.0 - choices.size() * width + 40.0) * 0.5
    for choice in choices:
        var button := DwellButton.new(choice[0], Vector2(x, 260), Vector2(width - 40.0, 150), 52)
        button.pressed.connect(choice[1])
        add_child(button)
        if _main == null:
            _main = button
            button.primary = true
        x += width
    add_child(HandCursor.new())


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var key := event as InputEventKey
        if (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and _main != null:
            _main.click()
            get_viewport().set_input_as_handled()
