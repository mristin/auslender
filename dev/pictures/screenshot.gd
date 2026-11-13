extends SceneTree

## Take a screenshot of a scene of the game, as the player sees it on a 1080p
## screen, to review it in place (it needs a display, not --headless):
##
## [codeblock]
## $GODOT --path . --windowed --resolution 1920x1080 \
##     --script dev/pictures/screenshot.gd -- res://scenes/ring/ring.tscn shot.png [frames] \
##     [--press=<keys>] --no-camera
## [/codeblock]
##
## With [code]--press=JKX[/code], it presses the keys one after the other, a
## few frames apart, before the screenshot (e.g., to see a punch).

var _frames := 0
var _wait := 90
var _target := ""
var _keys := ""


func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    _target = args[1]
    if args.size() > 2 and args[2].is_valid_int():
        _wait = int(args[2])
    for arg in args:
        if arg.begins_with("--press="):
            _keys = arg.trim_prefix("--press=")
    change_scene_to_file.call_deferred(args[0])


func _process(_delta: float) -> bool:
    _frames += 1
    if not _keys.is_empty() and _frames >= _wait - 4 * _keys.length() and _frames % 4 == 0:
        var index := (_frames - (_wait - 4 * _keys.length())) / 4
        if index < _keys.length():
            for pressed in [true, false]:
                var event := InputEventKey.new()
                event.keycode = OS.find_keycode_from_string(_keys[index])
                event.pressed = pressed
                Input.parse_input_event(event)
    if _frames == _wait:
        root.get_texture().get_image().save_png(_target)
        print("Wrote ", _target)
        quit()
    return false
