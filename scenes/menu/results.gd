class_name Results
extends Control

## The choices after a level (see Fight): the next level (if he won it and
## there is one), the same level again, or the levels; with the hand cursor.


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


## Show the choices after the level of the id, which he [param won] or not.
func setup(id: String, won: bool) -> void:
    var index := Levels.index_of(id)
    var x := 360.0
    if won and index + 1 < Levels.ALL_LEVELS.size():
        var next_id: String = Levels.ALL_LEVELS[index + 1]["id"]
        var next := DwellButton.new("NEXT", Vector2(x, 860), Vector2(380, 120), 48)
        next.primary = true
        next.pressed.connect(func() -> void: Flow.play(get_tree(), next_id))
        add_child(next)
        x += 420.0
    var again := DwellButton.new("AGAIN", Vector2(x, 860), Vector2(380, 120), 48)
    again.primary = not won
    again.pressed.connect(func() -> void: Flow.play(get_tree(), id))
    add_child(again)
    x += 420.0
    var back := DwellButton.new("LEVELS", Vector2(x, 860), Vector2(380, 120), 48)
    back.pressed.connect(func() -> void: Flow.levels(get_tree()))
    add_child(back)
    add_child(HandCursor.new())
