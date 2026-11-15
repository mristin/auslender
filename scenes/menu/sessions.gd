class_name Sessions
extends MenuScreen

## The first screen: the player's sessions (see Profile). Continue the last
## one, start a new one, or pick another one. Every session has a Delete
## button (with a bin) beneath it, as in Bird Dog, which asks before it
## deletes (so that a resting hand never deletes one by accident). Without a
## session, it goes straight to naming the first.
##
## Keys: Enter continues, N starts a new one, 1 to 3 pick another, Del deletes
## the last one (it asks first), Esc twice quits.

var _asked := ""
var _question: Control


func _build() -> void:
    var all := Profile.sessions()
    if all.is_empty():
        Flow.new_session.call_deferred(get_tree())
        return
    _title("AUSLENDER", Vector2(120, 80), 110)
    _title("Box to the beat with your whole body.", Vector2(124, 220), 36, PAPER)
    var last_id := Profile.last_session()
    var last: Dictionary = all[0]
    for entry in all:
        if entry["id"] == last_id:
            last = entry
    var go := _button("CONTINUE: %s" % last["name"], Vector2(120, 330), Vector2(1100, 140), 52)
    go.primary = true
    go.pressed.connect(_choose.bind(last["id"]))
    _delete_button(last["id"], Vector2(120, 482), 1100.0)
    _title(_progress(last), Vector2(130, 562), 32, PAPER)
    var fresh := _button("+ NEW SESSION", Vector2(120, 640), Vector2(700, 110))
    fresh.pressed.connect(func() -> void: Flow.new_session(get_tree()))
    var others := all.filter(func(entry: Dictionary) -> bool: return entry["id"] != last["id"])
    for i in range(mini(3, others.size())):
        var entry: Dictionary = others[i]
        var at := Vector2(1280, 330 + i * 200)
        var other := _button("%d. %s" % [i + 1, entry["name"]], at, Vector2(560, 110), 36)
        other.pressed.connect(_choose.bind(entry["id"]))
        _delete_button(entry["id"], at + Vector2(0, 118), 560.0)


## The Delete button of the session of the id, beneath its button.
func _delete_button(id: String, at: Vector2, width: float) -> void:
    var delete := _button("DELETE", at, Vector2(width, 62), 28)
    delete.symbol = "trash"
    delete.pressed.connect(_ask.bind(id))


func _progress(entry: Dictionary) -> String:
    var levels: Dictionary = entry.get("levels", {})
    var won := 0
    for id in levels:
        if levels[id].get("won", false):
            won += 1
    return "%d of %d levels won" % [won, Levels.ALL_LEVELS.size()]


func _choose(id: String) -> void:
    if Profile.continue_session(id):
        Flow.levels(get_tree())


## Ask whether to delete the session of the id: Delete or Keep.
func _ask(id: String) -> void:
    if _question != null:
        return
    _asked = id
    _question = Control.new()
    _question.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_question)
    var shade := ColorRect.new()
    shade.color = Color(0, 0, 0, 0.8)
    shade.set_anchors_preset(Control.PRESET_FULL_RECT)
    _question.add_child(shade)
    var label := Label.new()
    label.text = 'Delete the session "%s"?' % Profile.read(id).get("name", id)
    label.position = Vector2(360, 340)
    label.add_theme_font_size_override("font_size", 56)
    _question.add_child(label)
    var yes := DwellButton.new("DELETE", Vector2(360, 500), Vector2(500, 120))
    yes.symbol = "trash"
    yes.pressed.connect(_delete)
    _question.add_child(yes)
    var keep := DwellButton.new("KEEP", Vector2(1000, 500), Vector2(500, 120))
    keep.primary = true
    keep.pressed.connect(_close_question)
    _question.add_child(keep)


func _delete() -> void:
    Profile.delete(_asked)
    get_tree().reload_current_scene()


func _close_question() -> void:
    if _question != null:
        _question.queue_free()
        _question = null


func _back() -> void:
    if _question != null:
        _close_question()
        return
    super._back()


func _key(code: int) -> void:
    var all := Profile.sessions()
    if all.is_empty():
        return
    match code:
        KEY_ENTER, KEY_KP_ENTER:
            var last := Profile.last_session()
            _choose(last if last != "" else all[0]["id"])
        KEY_N:
            Flow.new_session(get_tree())
        KEY_DELETE:
            var last := Profile.last_session()
            _ask(last if last != "" else all[0]["id"])
        KEY_1, KEY_2, KEY_3:
            var last := Profile.last_session()
            var others := all.filter(func(e: Dictionary) -> bool: return e["id"] != last)
            var i := code - KEY_1
            if i < others.size():
                _choose(others[i]["id"])
