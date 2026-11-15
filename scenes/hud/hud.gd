class_name Hud
extends CanvasLayer

## Draw what the player needs to know over the fight: both health bars, the
## call of an attack which comes (e.g., "SLIP RIGHT!", with an arrow from where
## it comes), what came of his moves, and the status of the camera (or of the
## replay). What his body does shows on the mirror (see [CameraOverlay]).
##
## The fight sets the fields on every frame; the HUD only draws.

const _SCREEN := Vector2(1920, 1080)

const RED := Color("c8302c")
const PURPLE := Color("7b3fb0")
const GOLD := Color("f2c14e")
const INK := Color("0c0e14")
const PAPER := Color("f1f0ea")
const GREEN := Color("6ccf5e")

## How long a line of the opponent shows, in seconds.
const TAUNT_SECONDS := 2.5

var player_health := 1.0
var opponent_health := 1.0
var opponent_name := "DR. KAPSEL, ROCHARTIS"

## The time of the replay and its length, in seconds; negative without a replay.
var replay := Vector2(-1, -1)

var sees_player := false
var sees_feet := true

## The call of the attack which comes ("" if none), where it comes from
## ("left", "right", "front" or "low", as the player sees it), and how far
## its wind-up got.
var warning := ""
var warning_from := ""
var warning_progress := 0.0

## How red the screen flashes, in [0, 1].
var hurt := 0.0

var status := ""
var help := ""
var banner := ""

## The score, the combo of notes met in a row and its multiplier, and how far
## the song is, in [0, 1] (see Fight).
var score := 0
var combo := 0
var multiplier := 1
var progress := 0.0

## How fast he runs (in a run), as many times the pace of the notes, up to
## [member speed_most]; negative hides the speedometer. The pace he needs on
## average to arrive in time (see Run) is [member speed_needed].
var speed := -1.0
var speed_most := 1.5
var speed_needed := 0.85

## The lines of the results, under the banner at the end of the fight.
var results: Array = []

var _font: Font
var _canvas: Control
var _messages: Array[Dictionary] = []
var _taunt := ""
var _taunt_age := 10.0
var _announcement := ""
var _announcement_left := 0.0


func _ready() -> void:
    layer = 2
    _font = ThemeDB.fallback_font
    _canvas = Control.new()
    _canvas.size = _SCREEN
    _canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_canvas)
    _canvas.draw.connect(_draw_hud)


## Show a short message which rises and fades, e.g., "BLOCKED".
func say(text: String, color: Color = PAPER) -> void:
    _messages.append({"text": text, "color": color, "age": 0.0})
    if _messages.size() > 5:
        _messages.pop_front()


## Announce a title (e.g., of a section) big in the middle, for a while.
func announce(text: String, seconds: float) -> void:
    _announcement = text
    _announcement_left = seconds


## Show a line of the opponent as a subtitle under his bar, for a while.
func taunt(line: String) -> void:
    _taunt = line
    _taunt_age = 0.0


func _process(delta: float) -> void:
    _taunt_age += delta
    _announcement_left -= delta
    for message in _messages:
        message["age"] += delta
    _messages = _messages.filter(func(message: Dictionary) -> bool: return message["age"] < 1.2)
    _canvas.queue_redraw()


func _draw_hud() -> void:
    if hurt > 0.0:
        _canvas.draw_rect(Rect2(Vector2.ZERO, _SCREEN), Color(RED, 0.35 * hurt))

    _bar(Rect2(40, 30, 760, 34), player_health, RED, "YOU", false)
    if opponent_health >= 0.0:
        _bar(Rect2(1120, 30, 760, 34), opponent_health, PURPLE, opponent_name, true)

    # NOTE (mristin):
    # The score in the middle on top, the combo under it, and the song's
    # progress as a thin line under the bars.
    _text("%d" % score, Vector2(_SCREEN.x * 0.5, 70), 56, PAPER)
    if combo >= 2:
        var combo_text := "%d COMBO" % combo
        if multiplier > 1:
            combo_text += "   x%d" % multiplier
        _text(combo_text, Vector2(_SCREEN.x * 0.5, 118), 34, GOLD)
    _canvas.draw_rect(Rect2(40, 4, _SCREEN.x - 80, 6), Color(INK, 0.8))
    _canvas.draw_rect(Rect2(40, 4, (_SCREEN.x - 80) * clampf(progress, 0.0, 1.0), 6), GOLD)

    if _announcement_left > 0.0:
        var fade := clampf(_announcement_left / 0.4, 0.0, 1.0)
        _text(_announcement, Vector2(_SCREEN.x * 0.5, 760), 72, Color(GOLD, fade))

    if _taunt_age < TAUNT_SECONDS:
        var fade := clampf((TAUNT_SECONDS - _taunt_age) / 0.5, 0.0, 1.0)
        _canvas.draw_string_outline(
            _font,
            Vector2(1120, 200),
            "\u201c%s\u201d" % _taunt,
            HORIZONTAL_ALIGNMENT_RIGHT,
            760,
            34,
            10,
            Color(INK, fade)
        )
        _canvas.draw_string(
            _font,
            Vector2(1120, 200),
            "\u201c%s\u201d" % _taunt,
            HORIZONTAL_ALIGNMENT_RIGHT,
            760,
            34,
            Color(Color("d9b8f5"), fade)
        )

    if speed >= 0.0:
        _draw_speedometer()

    if replay.x >= 0.0:
        _text(
            "REPLAY %4.1f / %.0f s" % [replay.x, replay.y], Vector2(_SCREEN.x * 0.5, 50), 30, PAPER
        )

    if warning != "":
        _draw_warning()

    # NOTE (mristin):
    # The newest message on top, the ones before it pushed down and fading.
    for i in range(_messages.size()):
        var message: Dictionary = _messages[i]
        var below := _messages.size() - 1 - i
        if below > 1:
            continue
        var age: float = message["age"]
        var color: Color = message["color"]
        _text(
            message["text"],
            Vector2(_SCREEN.x * 0.5, 200 + 46 * below - age * 40.0),
            56 if below == 0 else 40,
            Color(color, (1.0 - age / 1.2) * (1.0 if below == 0 else 0.5))
        )

    if banner != "":
        _text(banner, Vector2(_SCREEN.x * 0.5, 560), 160, GOLD)
    for i in range(results.size()):
        _text(str(results[i]), Vector2(_SCREEN.x * 0.5, 660 + 56 * i), 44, PAPER)

    if not sees_player:
        _text("Step in front of the camera.", Vector2(_SCREEN.x * 0.5, 680), 48, PAPER)
    elif not sees_feet:
        _text(
            "Step back a little: I can not see your knees for the kicks.",
            Vector2(_SCREEN.x * 0.5, 1000),
            30,
            GOLD
        )

    _canvas.draw_string(
        _font, Vector2(1120, 140), status, HORIZONTAL_ALIGNMENT_RIGHT, 760, 22, PAPER
    )
    _canvas.draw_string(
        _font, Vector2(380, 1050), help, HORIZONTAL_ALIGNMENT_CENTER, 1500, 22, Color(PAPER, 0.8)
    )


## The call of the attack which comes, with an arrow from where it comes:
## a hook from his left comes from the left edge, and so on.
func _draw_warning() -> void:
    var size := 96 + int(32 * warning_progress)
    var color := Color(GOLD, 0.6 + 0.4 * warning_progress)
    _text(warning, Vector2(_SCREEN.x * 0.5, 350), size, color)

    var middle := Vector2(_SCREEN.x * 0.5, 480)
    var reach := 300.0 + 300.0 * (1.0 - warning_progress)
    match warning_from:
        "left":
            _arrow(middle - Vector2(reach, 0), Vector2.RIGHT, color)
        "right":
            _arrow(middle + Vector2(reach, 0), Vector2.LEFT, color)
        "low":
            _arrow(Vector2(middle.x, _SCREEN.y - 60), Vector2.UP, color)
        "front":
            _canvas.draw_arc(middle, 60.0 + 90.0 * (1.0 - warning_progress), 0, TAU, 48, color, 10)


## An arrow which points along the direction, with its tip at [param tip].
func _arrow(tip: Vector2, direction: Vector2, color: Color) -> void:
    var back := tip - direction * 160.0
    var side := Vector2(-direction.y, direction.x) * 50.0
    _canvas.draw_line(back, tip - direction * 40.0, color, 22)
    _canvas.draw_colored_polygon(
        PackedVector2Array([tip, tip - direction * 70.0 + side, tip - direction * 70.0 - side]),
        color
    )


func _bar(rect: Rect2, value: float, color: Color, label: String, right: bool) -> void:
    _canvas.draw_rect(rect.grow(4), Color(INK, 0.8))
    var filled := Rect2(rect.position, Vector2(rect.size.x * clampf(value, 0.0, 1.0), rect.size.y))
    if right:
        filled.position.x = rect.end.x - filled.size.x
    _canvas.draw_rect(filled, color)
    var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
    _canvas.draw_string(
        _font, rect.position + Vector2(0, rect.size.y + 34), label, align, rect.size.x, 28, PAPER
    )


func _text(text: String, center: Vector2, size: int, color: Color) -> void:
    var width := _SCREEN.x
    var at := Vector2(center.x - width * 0.5, center.y)
    _canvas.draw_string_outline(
        _font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 12, Color(INK, color.a)
    )
    _canvas.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


## The speedometer of a run: a dial at the bottom right, red where he is too
## slow to arrive in time, yellow around the pace he needs, green above; and
## its needle.
func _draw_speedometer() -> void:
    var center := Vector2(_SCREEN.x - 190, _SCREEN.y - 150)
    var radius := 120.0
    var start := PI * 0.75
    var sweep := PI * 1.5
    var at := func(share: float) -> float: return start + sweep * clampf(share, 0.0, 1.0)
    _canvas.draw_circle(center, radius + 18, Color(INK, 0.75))
    var needed := speed_needed / speed_most
    var zones := [
        [0.0, needed * 0.8, RED],
        [needed * 0.8, needed, GOLD],
        [needed, 1.0, GREEN],
    ]
    for zone in zones:
        _canvas.draw_arc(
            center, radius, at.call(zone[0]), at.call(zone[1]), 32, Color(zone[2], 0.9), 16
        )
    for k in range(7):
        var angle: float = at.call(k / 6.0)
        var direction := Vector2(cos(angle), sin(angle))
        _canvas.draw_line(
            center + direction * (radius - 24), center + direction * (radius - 8), PAPER, 3
        )
    var angle: float = at.call(speed / speed_most)
    var tip := center + Vector2(cos(angle), sin(angle)) * (radius - 14)
    _canvas.draw_line(center, tip, PAPER, 6)
    _canvas.draw_circle(center, 12, PAPER)
    _text("SPEED", center + Vector2(0, 70), 28, PAPER)
