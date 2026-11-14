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

    if replay.x >= 0.0:
        _text(
            "REPLAY %4.1f / %.0f s" % [replay.x, replay.y], Vector2(_SCREEN.x * 0.5, 50), 30, PAPER
        )

    if warning != "":
        _draw_warning()

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
    _text(warning, Vector2(_SCREEN.x * 0.5, 300), size, color)

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
