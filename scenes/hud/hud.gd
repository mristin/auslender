class_name Hud
extends CanvasLayer

## Draw what the player needs to know over the ring: both health bars, the
## walking gauge (how fast she walks, her knees, and how far she turned, with
## its dead zone), the call of an attack which comes ("DUCK!" or "JUMP!"), what
## came of her moves, and the status of the camera (or of the replay).
##
## The ring sets the fields on every frame; the HUD only draws.

const _SCREEN := Vector2(1920, 1080)
const _PAD_CENTER := Vector2(190, 860)
const _PAD_HALF := 150.0

const RED := Color("c8302c")
const PURPLE := Color("7b3fb0")
const GOLD := Color("f2c14e")
const INK := Color("0c0e14")
const PAPER := Color("f1f0ea")
const GREEN := Color("6ccf5e")

var player_health := 1.0
var opponent_health := 1.0
var opponent_name := "DR. KAPSEL, ROCHARTIS"

## Where she stands against home: x sideways in units, y the depth.
var room_offset := Vector2.ZERO

## The dead zones and the full offsets: (dead x, full x, dead y, full y).
var stick_limits := Vector4(0.4, 1.0, 0.07, 0.18)

## The stick now: x to her right, y forward.
var stick := Vector2.ZERO

## The walking: whether she walks, the steps per second, how much higher the
## left knee is than the right one (thighs), and the share of a full turn
## (positive to her left).
var walking := false
var cadence := 0.0
var knee_lift := NAN
var turn_raw := 0.0

## The time of the replay and its length, in seconds; negative without a replay.
var replay := Vector2(-1, -1)

var calibrated := false
var calibration_progress := 0.0
var sees_player := false
var sees_feet := true
var ducking := false
var jumping := false

## The call of the attack which comes ("" if none), and how far its wind-up got.
var warning := ""
var warning_progress := 0.0

## How red the screen flashes, in [0, 1].
var hurt := 0.0

var status := ""
var help := ""
var banner := ""

var _font: Font
var _canvas: Control
var _messages: Array[Dictionary] = []


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


func _process(delta: float) -> void:
    for message in _messages:
        message["age"] += delta
    _messages = _messages.filter(func(message: Dictionary) -> bool: return message["age"] < 1.2)
    _canvas.queue_redraw()


func _draw_hud() -> void:
    if hurt > 0.0:
        _canvas.draw_rect(Rect2(Vector2.ZERO, _SCREEN), Color(RED, 0.35 * hurt))

    _bar(Rect2(40, 30, 760, 34), player_health, RED, "YOU", false)
    _bar(Rect2(1120, 30, 760, 34), opponent_health, PURPLE, opponent_name, true)

    _draw_walk()
    if replay.x >= 0.0:
        _text("REPLAY %4.1f / %.0f s" % [replay.x, replay.y], Vector2(_SCREEN.x * 0.5, 50), 30, PAPER)

    if warning != "":
        var size := 96 + int(32 * warning_progress)
        _text(warning, Vector2(_SCREEN.x * 0.5, 300), size, Color(GOLD, 0.6 + 0.4 * warning_progress))

    for i in range(_messages.size()):
        var message: Dictionary = _messages[i]
        var age: float = message["age"]
        var color: Color = message["color"]
        _text(
            message["text"],
            Vector2(_SCREEN.x * 0.5, 470 - age * 80.0 - 0 * i),
            64,
            Color(color, 1.0 - age / 1.2)
        )

    if banner != "":
        _text(banner, Vector2(_SCREEN.x * 0.5, 560), 160, GOLD)

    if not sees_player:
        _text("Step in front of the camera.", Vector2(_SCREEN.x * 0.5, 680), 48, PAPER)
    elif not sees_feet:
        _text(
            "Step back a little: I can not see your knees for the kicks.",
            Vector2(_SCREEN.x * 0.5, 1000),
            30,
            GOLD
        )

    _canvas.draw_string(_font, Vector2(1120, 140), status, HORIZONTAL_ALIGNMENT_RIGHT, 760, 22, PAPER)
    _canvas.draw_string(
        _font, Vector2(380, 1050), help, HORIZONTAL_ALIGNMENT_CENTER, 1500, 22, Color(PAPER, 0.8)
    )


## The walking gauge: the speed as a bar, the knees as a bar which swings
## left and right, and the turn as a needle on a dial with its dead zone.
func _draw_walk() -> void:
    var rect := Rect2(_PAD_CENTER - Vector2(_PAD_HALF, _PAD_HALF), Vector2(_PAD_HALF, _PAD_HALF) * 2.0)
    _canvas.draw_rect(rect, Color(INK, 0.7))
    _canvas.draw_rect(rect, Color(PAPER, 0.6), false, 2.0)

    # The turn: a dial seen from above, the needle where she heads.
    var dial := _PAD_CENTER + Vector2(0, 10)
    var radius := 95.0
    var dead := 0.35
    _canvas.draw_arc(dial, radius, -PI, 0, 48, Color(PAPER, 0.35), 3)
    _canvas.draw_arc(dial, radius, -PI * 0.5 - dead * 0.9, -PI * 0.5 + dead * 0.9, 16, Color(GREEN, 0.6), 10)
    var angle := -PI * 0.5 - clampf(turn_raw, -1.2, 1.2) * 0.9
    var tip := dial + Vector2(cos(angle), sin(angle)) * radius
    var turning := absf(turn_raw) > dead
    _canvas.draw_line(dial, tip, GOLD if turning else PAPER, 6)
    _canvas.draw_circle(dial, 8, PAPER)
    _canvas.draw_string(_font, dial + Vector2(-radius - 10, 26), "left", HORIZONTAL_ALIGNMENT_LEFT, 80, 18, PAPER)
    _canvas.draw_string(
        _font, dial + Vector2(radius - 70, 26), "right", HORIZONTAL_ALIGNMENT_RIGHT, 80, 18, PAPER
    )

    # The speed: a bar on the right edge.
    var bar := Rect2(rect.end.x - 26, rect.position.y + 12, 14, rect.size.y - 24)
    _canvas.draw_rect(bar, Color(PAPER, 0.2))
    var filled := bar.size.y * clampf(stick.y, 0.0, 1.0)
    _canvas.draw_rect(Rect2(bar.position.x, bar.end.y - filled, bar.size.x, filled), GREEN if walking else PAPER)

    # The knees: a bar which swings to the side of the knee which is up.
    var knees := Rect2(rect.position.x + 30, rect.end.y - 40, rect.size.x - 80, 14)
    _canvas.draw_rect(knees, Color(PAPER, 0.2))
    if not is_nan(knee_lift):
        var middle := knees.position.x + knees.size.x * 0.5
        var swing := clampf(knee_lift, -1.0, 1.0) * knees.size.x * 0.5
        # NOTE (mristin):
        # Her left knee up swings to the left, as she sees herself.
        var a := minf(middle, middle - swing)
        _canvas.draw_rect(Rect2(a, knees.position.y, absf(swing), knees.size.y), GOLD)
    var label := "walking, %.1f steps/s" % cadence if walking else "walk in place to go"
    _canvas.draw_string(
        _font, rect.position + Vector2(0, -12), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, PAPER
    )
    _canvas.draw_string(
        _font,
        Vector2(rect.position.x, rect.end.y + 28),
        "turn your body to turn",
        HORIZONTAL_ALIGNMENT_CENTER,
        rect.size.x,
        18,
        PAPER
    )


## The room seen from above and from behind the player: the camera at the top,
## the home spot in the middle with its dead zone, and the player's dot; so
## her right is on the right, and forward (towards the camera) is up.
func _draw_pad() -> void:
    var rect := Rect2(_PAD_CENTER - Vector2(_PAD_HALF, _PAD_HALF), Vector2(_PAD_HALF, _PAD_HALF) * 2.0)
    _canvas.draw_rect(rect, Color(INK, 0.7))
    _canvas.draw_rect(rect, Color(PAPER, 0.6), false, 2.0)

    # NOTE (mristin):
    # The pad shows the full offsets at its edges: sideways in units, the
    # depth in its own scale.
    var dead := Vector2(stick_limits.x / stick_limits.y, stick_limits.z / stick_limits.w) * _PAD_HALF
    _canvas.draw_rect(Rect2(_PAD_CENTER - dead, dead * 2.0), Color(GREEN, 0.25))
    _canvas.draw_rect(Rect2(_PAD_CENTER - dead, dead * 2.0), Color(GREEN, 0.8), false, 2.0)
    _canvas.draw_rect(
        Rect2(_PAD_CENTER + Vector2(-30, -_PAD_HALF + 4), Vector2(60, 12)), Color(PAPER, 0.8)
    )
    _canvas.draw_string(
        _font,
        _PAD_CENTER + Vector2(-_PAD_HALF, -_PAD_HALF + 40),
        "camera",
        HORIZONTAL_ALIGNMENT_CENTER,
        _PAD_HALF * 2.0,
        18,
        PAPER
    )
    _canvas.draw_string(
        _font,
        _PAD_CENTER + Vector2(-_PAD_HALF, _PAD_HALF + 28),
        "your spot, from above",
        HORIZONTAL_ALIGNMENT_CENTER,
        _PAD_HALF * 2.0,
        18,
        PAPER
    )

    if not calibrated:
        _canvas.draw_arc(_PAD_CENTER, 40, -PI * 0.5, -PI * 0.5 + TAU * calibration_progress, 48, GOLD, 6)
        return

    var full := Vector2(stick_limits.y, stick_limits.w)
    var dot := _PAD_CENTER + Vector2(room_offset.x / full.x, -room_offset.y / full.y) * _PAD_HALF
    dot = dot.clamp(rect.position + Vector2(10, 10), rect.end - Vector2(10, 10))
    if stick.length() > 0.0:
        var tip := _PAD_CENTER + Vector2(stick.x, -stick.y) * _PAD_HALF * 0.9
        _canvas.draw_line(_PAD_CENTER, tip, GOLD, 6)
        _canvas.draw_circle(tip, 9, GOLD)
    var color := RED
    if ducking:
        color = GOLD
    elif jumping:
        color = GREEN
    _canvas.draw_circle(dot, 14, color)
    _canvas.draw_arc(dot, 14, 0, TAU, 24, PAPER, 2)


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
