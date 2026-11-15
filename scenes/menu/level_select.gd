class_name LevelSelect
extends MenuScreen

## Choose a level of the session (see Levels and Profile): the worlds side by
## side, each with its levels in order. A level opens once the one before it
## is won; the locked ones are dim. The next level to play is crimson; the
## levels won show their best grade. Each shows a small picture of its land
## and its opponent (see LevelThumbnails), dim while it is locked.
##
## Keys: the arrows move between the levels, Enter plays, Esc goes back to the
## sessions.

var _buttons: Array[DwellButton] = []
var _thumbnails := LevelThumbnails.new()
## The buttons of the levels, by their id.
var _by_id := {}


func _build() -> void:
    add_child(_thumbnails)
    _thumbnails.rendered.connect(_show_thumbnail)
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
            _dress(button)
            _by_id[level["id"]] = button
            var thumbnail := _thumbnails.request(level)
            if thumbnail != null:
                button.icon = thumbnail
            if i == next:
                button.grab_focus.call_deferred()
            row += 1
    var back := _button("BACK", Vector2(60, 920), Vector2(360, 110), 40)
    back.pressed.connect(_back)


## Make room on the button for the picture of its level, on its left, and
## wrap its title next to it.
func _dress(button: DwellButton) -> void:
    button.expand_icon = true
    button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    button.add_theme_constant_override("icon_max_width", 176)
    button.add_theme_constant_override("h_separation", 20)
    button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.25))
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var box := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
        box.content_margin_left = 8
        box.content_margin_top = 8
        box.content_margin_bottom = 8
        box.content_margin_right = 16
        button.add_theme_stylebox_override(state, box)


func _show_thumbnail(id: String, texture: Texture2D) -> void:
    if _by_id.has(id):
        (_by_id[id] as DwellButton).icon = texture


func _back() -> void:
    Flow.sessions(get_tree())


func _key(code: int) -> void:
    if code == KEY_ENTER or code == KEY_KP_ENTER:
        var focused := get_viewport().gui_get_focus_owner()
        if focused is DwellButton:
            (focused as DwellButton).click()
