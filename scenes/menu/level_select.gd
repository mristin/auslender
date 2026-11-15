class_name LevelSelect
extends MenuScreen

## Choose a level of the session (see Levels and Profile): the worlds side by
## side, each with its levels in order. A level opens once the one before it
## is won; the locked ones are dim. The next level to play is crimson; the
## levels won show their best grade.
##
## Keys: the arrows move between the levels, Enter plays, Esc goes back to the
## sessions.

var _buttons: Array[DwellButton] = []


func _build() -> void:
    _title(Profile.session.get("name", "").to_upper(), Vector2(80, 30), 56)
    var next := Profile.next_index()
    for w in range(Levels.WORLDS.size()):
        var world: Dictionary = Levels.WORLDS[w]
        var x := 60 + w * 610
        _title(world["title"], Vector2(x, 130), 48, PAPER)
        var row := 0
        for i in range(Levels.ALL_LEVELS.size()):
            var level: Dictionary = Levels.ALL_LEVELS[i]
            if level["world"] != world["id"]:
                continue
            var open := Profile.is_open(i)
            var best := Profile.best(level["id"])
            var text: String = level["title"]
            if not open:
                text = "LOCKED"
            elif best.get("won", false):
                text += "   " + str(best.get("grade", ""))
            var button := _button(text, Vector2(x, 210 + row * 135), Vector2(580, 115), 32)
            button.disabled = not open
            button.primary = i == next
            button.pressed.connect(func() -> void: Flow.play(get_tree(), level["id"]))
            _buttons.append(button)
            if i == next:
                button.grab_focus.call_deferred()
            row += 1
    var back := _button("BACK", Vector2(60, 920), Vector2(360, 110), 40)
    back.pressed.connect(_back)


func _back() -> void:
    Flow.sessions(get_tree())


func _key(code: int) -> void:
    if code == KEY_ENTER or code == KEY_KP_ENTER:
        var focused := get_viewport().gui_get_focus_owner()
        if focused is DwellButton:
            (focused as DwellButton).click()
