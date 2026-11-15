class_name SessionName
extends MenuScreen

## Name a new session (see Profile): the name is the date and the time at
## first, so that OK alone is enough (with the hand); the first key typed
## replaces it. Enter is OK, Backspace deletes a letter, Esc goes back.

var _name := ""
var _fresh := true
var _shown: Label


func _build() -> void:
    _name = Profile.default_name()
    _title("NEW SESSION", Vector2(120, 80), 90)
    _title("Its name (type to change it):", Vector2(124, 240), 36, PAPER)
    _shown = _title(_name, Vector2(124, 300), 80, PAPER)
    var ok := _button("OK", Vector2(120, 500), Vector2(500, 130), 56)
    ok.primary = true
    ok.pressed.connect(_finish)
    var back := _button("BACK", Vector2(700, 500), Vector2(400, 130), 44)
    back.pressed.connect(_back)


func _finish() -> void:
    Profile.start_session(_name if _name.strip_edges() != "" else Profile.default_name())
    Flow.levels(get_tree())


func _back() -> void:
    if Profile.sessions().is_empty():
        super._back()
    else:
        Flow.sessions(get_tree())


func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed):
        return
    var key := event as InputEventKey
    match key.keycode:
        KEY_ESCAPE:
            _back()
        KEY_ENTER, KEY_KP_ENTER:
            _finish()
        KEY_BACKSPACE:
            _name = "" if _fresh else _name.left(-1)
            _fresh = false
        _:
            if key.unicode >= 32 and _name.length() < Profile.MAX_NAME:
                if _fresh:
                    _name = ""
                    _fresh = false
                _name += char(key.unicode)
    _shown.text = _name
    get_viewport().set_input_as_handled()
