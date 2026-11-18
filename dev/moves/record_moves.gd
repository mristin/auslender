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
## the camera sees the player, and the first step ("stand 1") sets his home
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
##
## A stick figure (see [MoveFigure]) shows the expected move of the step,
## timed to the calls, as in a mirror, so that the player can copy it.


## A stick figure which shows a move, as in a mirror: its left side (the
## player's left) is on the left of the screen, like in the camera picture.
## The limb which moves is gold.
class MoveFigure:
    extends Control

    ## How long the move takes from the guard to its peak, holds, and comes
    ## back, in seconds.
    const RISE := 0.3
    const HOLD := 0.25
    const BACK := 0.35

    const _LINE := Color("f1f0ea")
    const _ACTIVE := Color("f2c14e")
    const _DIM := Color(0.6, 0.62, 0.68)

    ## The points of the figure in its guard, in torso lengths, x to the
    ## figure's left (the screen's left), y down; the hips at the origin.
    const GUARD := {
        "head": Vector2(0.0, -1.5),
        "l_sh": Vector2(-0.33, -1.1),
        "r_sh": Vector2(0.33, -1.1),
        "l_elb": Vector2(-0.5, -0.55),
        "r_elb": Vector2(0.5, -0.55),
        "l_wri": Vector2(-0.17, -1.2),
        "r_wri": Vector2(0.17, -1.2),
        "l_hip": Vector2(-0.22, 0.0),
        "r_hip": Vector2(0.22, 0.0),
        "l_knee": Vector2(-0.26, 0.85),
        "r_knee": Vector2(0.26, 0.85),
        "l_ank": Vector2(-0.28, 1.7),
        "r_ank": Vector2(0.28, 1.7),
    }

    ## The peak of each move of the left side (the right side is its mirror),
    ## as the points which differ from the guard; "l_fist" is the size of the
    ## left glove (a straight comes at the camera, so the glove grows).
    const PEAKS := {
        "straight": {"l_elb": Vector2(-0.24, -1.0), "l_wri": Vector2(-0.12, -1.25), "l_fist": 2.0},
        "hook": {"l_elb": Vector2(-0.75, -1.1), "l_wri": Vector2(-0.3, -1.3), "l_fist": 1.3},
        "uppercut": {"l_elb": Vector2(-0.3, -0.85), "l_wri": Vector2(-0.08, -1.55)},
        "kick": {"l_knee": Vector2(-0.4, -0.4), "l_ank": Vector2(-0.42, 0.35)},
        "cover":
        {
            "l_elb": Vector2(-0.16, -1.0),
            "r_elb": Vector2(0.16, -1.0),
            "l_wri": Vector2(-0.1, -1.6),
            "r_wri": Vector2(0.1, -1.6),
        },
    }

    ## The move to show: "guard", "straight", "hook", "uppercut", "kick",
    ## "one_two", "slip", "duck", "jump", "cover", "look" or "free".
    var move := "guard"
    ## "left", "right" or "" (both, or none).
    var side := ""
    ## Seconds since the move started (the call); the figure waits in its
    ## guard before 0.
    var since := -1.0
    ## Whether the move stays at its peak (the cover until the next call).
    var held := false

    ## Start the move now (at its call).
    func play(new_move: String, new_side: String, hold := false) -> void:
        move = new_move
        side = new_side
        held = hold
        since = 0.0

    ## Show the move of a step without calls, e.g., the guard or looking around.
    func show_still(new_move: String) -> void:
        move = new_move
        side = ""
        held = false
        since = -1.0

    func _process(delta: float) -> void:
        since += delta
        queue_redraw()

    ## How far the move is from the guard to its peak (0 to 1) at the time t.
    static func amount(t: float) -> float:
        if t < 0.0:
            return 0.0
        if t < RISE:
            return smoothstep(0.0, 1.0, t / RISE)
        if t < RISE + HOLD:
            return 1.0
        return 1.0 - smoothstep(0.0, 1.0, (t - RISE - HOLD) / BACK)

    func _pose() -> Dictionary:
        var points := GUARD.duplicate()
        points["l_fist"] = 1.0
        points["r_fist"] = 1.0
        var bob := 0.03 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)
        var t := since
        var name := move
        var right := side == "right"
        if move == "free":
            # NOTE (mristin):
            # Cycle through a few moves, one every 1.5 seconds.
            var cycle := ["straight", "hook", "slip", "uppercut", "duck", "kick"]
            var now := Time.get_ticks_msec() / 1000.0
            var index := int(now / 1.5)
            name = cycle[index % cycle.size()]
            right = index % 2 == 1
            t = fmod(now, 1.5) - 0.2
        elif move == "one_two":
            # NOTE (mristin):
            # A straight left, then at once a straight right.
            name = "straight"
            right = t > RISE + 0.1
            if right:
                t -= RISE + 0.1
        var a := 1.0 if held and since >= RISE else amount(t)
        var offset := Vector2(0.0, bob)
        match name:
            "duck":
                offset.y += 0.55 * a
            "jump":
                offset.y -= 0.5 * a
            "slip":
                var lean := (0.3 if right else -0.3) * a
                for key in points.keys():
                    if key.ends_with("fist") or key.contains("hip") or key.contains("knee"):
                        continue
                    if key.contains("ank"):
                        continue
                    var p: Vector2 = points[key]
                    points[key] = p.rotated(lean)
            "look":
                var turn := sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.4)
                points["head"] += Vector2(0.12 * turn, 0.0)
            _:
                if PEAKS.has(name):
                    var peak: Dictionary = PEAKS[name]
                    for key in peak.keys():
                        var target_key: String = key
                        var value: Variant = peak[key]
                        if right:
                            target_key = (
                                ("r_" + key.substr(2))
                                if key.begins_with("l_")
                                else ("l_" + key.substr(2))
                            )
                            if value is Vector2:
                                value = Vector2(-value.x, value.y)
                        if value is Vector2:
                            points[target_key] = points[target_key].lerp(value, a)
                        else:
                            points[target_key] = lerpf(points[target_key], value, a)
        for key in points.keys():
            if key.ends_with("fist"):
                continue
            # NOTE (mristin):
            # In a duck, the body goes down but the feet stay on the floor.
            if name == "duck" and key.contains("ank"):
                points[key] += Vector2(0.0, bob)
                continue
            points[key] += offset
        if name == "duck":
            # NOTE (mristin):
            # The knees bend out, half way between the hips and the feet.
            for s in ["l_", "r_"]:
                var out := -1.0 if s == "l_" else 1.0
                var middle: Vector2 = (points[s + "hip"] + points[s + "ank"]) / 2.0
                points[s + "knee"] = middle + Vector2(0.3 * out * a, 0.0)
        points["_name"] = name
        points["_right"] = right
        return points

    func _active(points: Dictionary) -> Array:
        var name: String = points["_name"]
        var s := "r_" if points["_right"] else "l_"
        match name:
            "straight", "hook", "uppercut":
                return [s + "arm"]
            "kick":
                return [s + "leg"]
            "cover":
                return ["l_arm", "r_arm"]
            "slip", "look":
                return ["head"]
            "duck", "jump":
                return ["l_leg", "r_leg"]
        return []

    func _draw() -> void:
        var points := _pose()
        var active := _active(points)
        var unit := size.y / 4.2
        var origin := Vector2(size.x / 2.0, size.y * 0.5)

        var at := func(key: String) -> Vector2: return origin + (points[key] as Vector2) * unit

        var width := maxf(4.0, unit * 0.1)
        var limb := func(keys: Array, color: Color) -> void:
            for i in range(keys.size()):
                draw_circle(at.call(keys[i]), width / 2.0, color)
                if i > 0:
                    draw_line(at.call(keys[i - 1]), at.call(keys[i]), color, width)

        # the floor, so that a jump shows
        var floor_y: float = origin.y + (GUARD["l_ank"].y + 0.05) * unit
        draw_line(Vector2(size.x * 0.2, floor_y), Vector2(size.x * 0.8, floor_y), _DIM, width * 0.5)

        var neck: Vector2 = (at.call("l_sh") + at.call("r_sh")) / 2.0
        var pelvis: Vector2 = (at.call("l_hip") + at.call("r_hip")) / 2.0
        draw_line(at.call("l_sh"), at.call("r_sh"), _LINE, width)
        draw_line(at.call("l_hip"), at.call("r_hip"), _LINE, width)
        draw_line(neck, pelvis, _LINE, width)
        for s in ["l_", "r_"]:
            var leg := _ACTIVE if active.has(s + "leg") else _LINE
            limb.call([s + "hip", s + "knee", s + "ank"], leg)

        # NOTE (mristin):
        # The head before the arms: the gloves come in front of the face, as
        # the player sees them in the mirror.
        var head_color := _ACTIVE if active.has("head") else _LINE
        draw_line(neck, at.call("head"), _LINE, width)
        draw_circle(at.call("head"), unit * 0.24, Color("0c0e14"))
        draw_arc(at.call("head"), unit * 0.24, 0.0, TAU, 32, head_color, width)
        # the unibrow, as on the player's head
        var brow: Vector2 = at.call("head") + Vector2(0, -unit * 0.05)
        var half_brow := Vector2(unit * 0.13, 0)
        draw_line(brow - half_brow, brow + half_brow, head_color, width * 0.7)

        for s in ["l_", "r_"]:
            var arm := _ACTIVE if active.has(s + "arm") else _LINE
            limb.call([s + "sh", s + "elb", s + "wri"], arm)
            var glove := _ACTIVE if active.has(s + "arm") else Color("c8302c")
            draw_circle(at.call(s + "wri"), unit * 0.12 * float(points[s + "fist"]), glove)

        var font := get_theme_default_font()
        var caption := ""
        if move == "free":
            caption = "anything!"
        elif side != "" and move != "one_two":
            caption = side.to_upper() + (" knee" if move == "kick" else " hand")
            if move == "slip":
                caption = "to your " + side.to_upper()
        elif move == "one_two":
            caption = "LEFT, then RIGHT"
        if caption != "":
            var font_size := int(unit * 0.3)
            var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
            var x := size.x / 2.0 - text_size.x / 2.0
            draw_string(
                font,
                Vector2(x, size.y - 6.0),
                caption,
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                font_size,
                _ACTIVE
            )
        draw_string(
            font, Vector2(8.0, 22.0), "as in a mirror", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _DIM
        )


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
var _figure: MoveFigure
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
    _figure = MoveFigure.new()
    _figure.position = Vector2(1260, 540)
    _figure.size = Vector2(620, 390)
    layer.add_child(_figure)
    _readout = _label(layer, Vector2(1260, 935), Vector2(620, 120), 18, _PAPER)
    _readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


## A short beep, so that the player hears the call even when he looks away.
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
    _show_step(current)
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


## Show the move of the step on the figure: in the guard until the first call
## (with the side of the move), or the step's own move if it has no calls.
func _show_step(step: Dictionary) -> void:
    var calls: Array = step["calls"]
    if calls.is_empty():
        var label: String = step["label"]
        var still := "guard"
        if label == "look around":
            still = "look"
        elif label == "free":
            still = "free"
        elif label == "":
            still = "guard"
        _figure.show_still(still)
        return
    var first: Array = _move_of(calls[0][1])
    _figure.show_still("guard")
    _figure.side = first[1]
    _figure.move = first[0]


## The move and the side of a call of the plan, e.g., ["kick", "left"] for
## "front_kick_left".
func _move_of(call: String) -> Array:
    for kind in ["straight", "hook", "uppercut", "front_kick", "slip"]:
        for side in ["left", "right"]:
            if call == "%s_%s" % [kind, side]:
                return ["kick" if kind == "front_kick" else kind, side]
    return [call, ""]


## Show the move of a call on the figure, at once.
func _play_call(call: String) -> void:
    if call == "guard":
        _figure.show_still("guard")
        return
    var move: Array = _move_of(call)
    _figure.play(move[0], move[1], call == "cover")


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
        _play_call(call[1])
        _beep.play()
    _call.visible = _call_left > 0.0

    if _left <= 0.0:
        _go_to(_step + 1)
    return false


## Show what the vision measures now: the lean, what the classifier thinks and
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
    lines.append("lean %+.2f" % _service.GetLean())
    var classes: PackedStringArray = _service.GetMoveClasses()
    var probabilities: PackedFloat32Array = _service.GetMoveProbabilities()
    var likely := ""
    for i in range(probabilities.size()):
        if probabilities[i] >= 0.2:
            likely += "%s %.2f  " % [classes[i], probabilities[i]]
    lines.append("classifier: " + likely)
    lines.append("detected: " + ", ".join(_detected))
    _readout.text = "\n".join(lines)
