extends SceneTree

## Record what the vision measures while the player follows a plan of moves
## (stand, look around, step to each side, punch, kick, duck and jump), to
## study how they look to the vision and to infer the rules which tell them.
##
## [codeblock]
## $GODOT --path . --script dev/moves/record_moves.gd -- \
##     [--plan=res://dev/moves/plans/moves.csv] [--quick] [--frames] [<recording.jsonl>]
## [/codeblock]
##
## The plan is a CSV file with a header and one step per row: the label which
## the recording gives the step (e.g., "hook left"), how long it lasts in
## seconds, its title, what the player should do, and optionally the calls:
## "<seconds>:<name>" separated by spaces, e.g., "1.5:hook_left 3:hook_left".
## At each call, the screen shows the name big, a beep sounds, and the
## recording marks it ("mark" with the name), so that dev/moves/analyze.py
## knows when each move was asked for.
##
## It needs the camera and a display (not --headless). First, it waits until
## the camera sees the player, and the first step ("stand 1") sets her home
## spot. Meanwhile, the vision service records what it measures (see
## VisionRecorder): only numbers, never the pictures. The recording goes to
## ~/Downloads/move_recordings/<plan>-<time>.jsonl by default.
##
## The screen shows the camera picture with what the vision sees (the
## skeleton, the hands, the unibrow), the room pad, the depth of each cue and
## the moves which the game detected, so you see at once what works.
##
## With [code]--frames[/code], it also saves every camera frame as a picture
## into [code]<recording>.frames/[/code] (00001.jpg, ...; each written as a
## "frame" line with its time), to replay the session frame by frame offline.
## Only for developing the vision: the game itself never saves the pictures.
##
## Escape stops early; what was recorded so far is kept. [code]--quick[/code]
## makes every step ten times shorter, to try the tool (e.g., with --no-camera).

const _DEFAULT_PLAN := "res://dev/moves/plans/moves.csv"

const _GET_READY_SECONDS := 10.0

## How long a call shows, in seconds.
const _CALL_SECONDS := 0.9

const _PAPER := Color("f1f0ea")
const _GOLD := Color("f2c14e")
const _GREY := Color("9aa0ad")
const _RED := Color("ff5a4f")

var _service: Node
var _path := ""
var _steps: Array[Dictionary] = []
var _step := -1
var _left := 0.0
var _elapsed := 0.0
var _calls: Array = []
var _call_left := 0.0
var _done := false
var _quick := false
var _recording := false
var _detected: Array[String] = []

var _overlay: CameraOverlay
var _hud: Hud
var _frames := false
var _title: Label
var _text: Label
var _count: Label
var _next: Label
var _call: Label
var _readout: Label
var _beep: AudioStreamPlayer


func _initialize() -> void:
    var plan := _DEFAULT_PLAN
    for arg in OS.get_cmdline_user_args():
        if arg == "--quick":
            _quick = true
        elif arg == "--frames":
            _frames = true
        elif arg.begins_with("--plan="):
            plan = arg.trim_prefix("--plan=")
        elif not arg.begins_with("--"):
            _path = arg
    if _path == "":
        _path = (
            "%s/Downloads/move_recordings/%s-%s.jsonl"
            % [
                OS.get_environment("HOME"),
                plan.get_file().get_basename(),
                Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
            ]
        )

    (
        _steps
        . append(
            {
                "label": "",
                "seconds": _GET_READY_SECONDS,
                "title": "Get ready",
                "text":
                (
                    "Step back (2.5 to 3 m) until the camera sees you from your head down to "
                    + "below your knees, with room above your head."
                ),
                "calls": [],
            }
        )
    )
    var error := _load_plan(plan)
    _build.call_deferred(error)


## Read the steps of the plan; return what went wrong, or "".
func _load_plan(plan: String) -> String:
    var file := FileAccess.open(plan, FileAccess.READ)
    if file == null:
        return "Could not read the plan %s." % plan
    file.get_csv_line()
    while not file.eof_reached():
        var row := file.get_csv_line()
        if row.size() < 4 or row[0].strip_edges() == "":
            continue
        var calls: Array = []
        if row.size() > 4:
            for call in row[4].split(" ", false):
                var parts := call.split(":")
                if parts.size() == 2:
                    calls.append([float(parts[0]), parts[1]])
        (
            _steps
            . append(
                {
                    "label": row[0],
                    "seconds": float(row[1]),
                    "title": row[2],
                    "text": row[3],
                    "calls": calls,
                }
            )
        )
    if _steps.size() < 2:
        return "The plan %s has no steps." % plan
    return ""


func _build(error: String) -> void:
    _service = root.get_node("Vision").service
    _service.ResetPlayer()

    var screen := ColorRect.new()
    screen.color = Color("0c0e14")
    screen.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(screen)

    _overlay = CameraOverlay.new()
    _overlay.opacity = 0.75
    _overlay.debug = true
    root.add_child(_overlay)
    _overlay.setup(_service)

    _hud = Hud.new()
    _hud.opponent_name = ""
    root.add_child(_hud)

    var layer := CanvasLayer.new()
    layer.layer = 3
    root.add_child(layer)
    var panel := ColorRect.new()
    panel.color = Color(0.05, 0.06, 0.09, 0.78)
    panel.position = Vector2(1240, 120)
    panel.size = Vector2(660, 940)
    layer.add_child(panel)

    _title = _label(layer, Vector2(1260, 130), Vector2(620, 60), 40, _GOLD)
    _text = _label(layer, Vector2(1260, 200), Vector2(620, 170), 26, _PAPER)
    _text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _count = _label(layer, Vector2(1260, 370), Vector2(620, 110), 90, _PAPER)
    _next = _label(layer, Vector2(1260, 480), Vector2(620, 60), 22, _GREY)
    _next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _readout = _label(layer, Vector2(1260, 560), Vector2(620, 480), 22, _PAPER)
    _call = _label(layer, Vector2(0, 420), Vector2(1240, 160), 120, _RED)
    _call.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _call.add_theme_color_override("font_outline_color", Color.BLACK)
    _call.add_theme_constant_override("outline_size", 16)
    _call.visible = false

    _beep = AudioStreamPlayer.new()
    _beep.stream = _make_beep()
    root.add_child(_beep)

    if error != "":
        _title.text = error
        _done = true
        return
    _go_to(0)


func _label(parent: Node, at: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.position = at
    label.size = size
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label


## A short beep, so that the player hears the call even when she looks away.
func _make_beep() -> AudioStreamWAV:
    var rate := 22050
    var samples := PackedByteArray()
    var count := int(rate * 0.12)
    samples.resize(count * 2)
    for i in range(count):
        var fade := 1.0 - float(i) / count
        var value := int(sin(TAU * 880.0 * i / rate) * 12000.0 * fade)
        samples.encode_s16(i * 2, value)
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = rate
    stream.data = samples
    return stream


func _go_to(step: int) -> void:
    _step = step
    if step >= _steps.size():
        _finish()
        return
    var current := _steps[step]
    var scale := 0.1 if _quick else 1.0
    _left = current["seconds"] * scale
    _elapsed = 0.0
    _calls.clear()
    for call in current["calls"]:
        _calls.append([call[0] * scale, call[1]])
    _title.text = "%s   (%d of %d)" % [current["title"], step + 1, _steps.size()]
    _text.text = current["text"]
    var following := "Then you are done."
    if step + 1 < _steps.size():
        following = "Next: %s." % _steps[step + 1]["title"]
    _next.text = following
    if step == 1:
        if not _service.StartRecordingWithFrames(_path, _frames):
            _title.text = "Could not record into %s" % _path
            _done = true
            return
        _recording = true
        # NOTE (mristin):
        # The first step sets the home spot afresh.
        _service.Recalibrate()
    _service.SetRecordingLabel(current["label"])
    _beep.play()


func _finish() -> void:
    var lines: int = _service.StopRecording() if _recording else 0
    _recording = false
    _done = true
    _call.visible = false
    _title.text = "Thank you, all done!"
    _text.text = "Recorded %d lines into:\n%s" % [lines, _path]
    _count.text = ""
    _next.text = "Close the window, or press Escape."
    print("Recorded %d lines into %s" % [lines, _path])


func _process(delta: float) -> bool:
    if Input.is_key_pressed(KEY_ESCAPE):
        if not _done:
            _finish()
        return true
    if _service == null:
        return false

    _update_readout()
    if _done or _step < 0:
        return false

    # NOTE (mristin):
    # The countdown to start waits until the camera sees the player.
    var seen: bool = _service.IsRunning() and _service.HasPlayer()
    if _step == 0 and not seen and _service.GetStatus() != "Disabled":
        _count.text = "..."
        _next.text = "Waiting until the camera sees you."
        return false

    _left -= delta
    _elapsed += delta
    _count.text = str(ceili(maxf(0.0, _left)))

    _call_left = maxf(0.0, _call_left - delta)
    if not _calls.is_empty() and _elapsed >= _calls[0][0]:
        var call: Array = _calls.pop_front()
        _call_left = _CALL_SECONDS
        _call.text = (call[1] as String).replace("_", " ").to_upper() + "!"
        _service.MarkRecording("call:" + call[1])
        _beep.play()
    _call.visible = _call_left > 0.0

    if _left <= 0.0:
        _go_to(_step + 1)
    return false


## Show what the vision measures now: the offsets of the head, the cues of the depth and
## the moves which the game detected lately.
func _update_readout() -> void:
    _overlay.calibrated = _service.IsCalibrated()
    _overlay.calibration_progress = _service.GetCalibrationProgress()
    _overlay.pose = "COVER" if _service.IsCovering() else ""
    _hud.sees_player = _service.HasPlayer() or _service.GetStatus() == "Disabled"
    _hud.sees_feet = _service.SeesFeet() or _service.GetStatus() == "Disabled"
    _hud.status = VisionStatus.new().text(_service, true)

    for move in _service.PollMoves():
        var name: String = move["kind"]
        if move["side"] != "":
            name = "%s %s" % [move["side"], name]
        _detected.append(name.replace("_", " "))
        if _detected.size() > 6:
            _detected.pop_front()

    var lines: Array[String] = []
    var offset: Vector2 = _service.GetRoomOffset()
    var stick: Vector2 = _service.GetStick()
    lines.append(
        "sideways %+.2f   depth %+.3f   down %+.2f" % [offset.x, offset.y, _service.GetHeadDown()]
    )
    lines.append("stick (%+.2f, %+.2f)" % [stick.x, stick.y])
    var names: PackedStringArray = _service.GetCueNames()
    var depths: PackedFloat32Array = _service.GetCueDepths()
    var cues := ""
    for i in range(names.size()):
        var value := "  -  " if is_nan(depths[i]) else "%+.3f" % depths[i]
        cues += "%-12s %s\n" % [names[i], value]
    lines.append("depth of each cue:\n" + cues)
    var classes: PackedStringArray = _service.GetMoveClasses()
    var probabilities: PackedFloat32Array = _service.GetMoveProbabilities()
    var likely := ""
    for i in range(probabilities.size()):
        if probabilities[i] >= 0.2:
            likely += "%s %.2f  " % [classes[i], probabilities[i]]
    lines.append("classifier: " + likely)
    lines.append("detected: " + ", ".join(_detected))
    _readout.text = "\n".join(lines)
