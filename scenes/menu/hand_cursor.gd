class_name HandCursor
extends Control

## A cursor which the player's raised hand moves, seen by the camera (as in The
## Steppe Rescue): a hand above the shoulder moves it across the screen, and
## holding it still on a button (see DwellButton) clicks the button. A hand
## below the shoulders does not count.

## How far the hand moves (a share of the picture's width, around the
## shoulder) to cross the whole screen.
const REACH := 0.35

## How quickly the cursor follows the hand (1/s), and how far it may drift
## while held still on a button (pixels).
const FOLLOW := 10.0

var _vision: Node
var _at := Vector2(960, 540)
var _seen := false
var _over: DwellButton


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 100
    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        _vision = holder.service


func _process(delta: float) -> void:
    var hand := _raised_hand()
    _seen = hand.x >= 0.0
    if _seen:
        _at = _at.lerp(hand, minf(1.0, delta * FOLLOW))
    var over: DwellButton = null
    if _seen:
        for node in get_tree().get_nodes_in_group("dwell"):
            var button := node as DwellButton
            if button.is_visible_in_tree() and not button.disabled:
                if button.get_global_rect().has_point(_at):
                    over = button
    if over != _over and _over != null:
        _over.dwell = 0.0
    _over = over
    if _over != null:
        _over.dwell += delta / DwellButton.DWELL_SECONDS
        if _over.dwell >= 1.0:
            _over.click()
    queue_redraw()


## Where the raised hand points on the screen (negative if none is raised).
func _raised_hand() -> Vector2:
    if _vision == null or _vision.GetStatus() == "Disabled":
        return Vector2(-1, -1)
    var points: PackedVector2Array = _vision.GetKeypoints()
    if points.size() < 11:
        return Vector2(-1, -1)
    var shoulders := (points[5] + points[6]) * 0.5
    var best := Vector2(-1, -1)
    for wrist in [points[9], points[10]]:
        # NOTE (mristin):
        # Above the shoulders (y grows down), the higher the better.
        if wrist.y < shoulders.y and (best.x < 0.0 or wrist.y < best.y):
            best = wrist
    if best.x < 0.0:
        return best
    var screen := get_viewport_rect().size
    var x := 0.5 + (best.x - shoulders.x) / REACH
    var y := 0.5 + (best.y - (shoulders.y - REACH * 0.5)) / REACH
    return Vector2(clampf(x, 0.0, 1.0) * screen.x, clampf(y, 0.0, 1.0) * screen.y)


func _draw() -> void:
    if not _seen:
        return
    # NOTE (mristin):
    # A big glove.
    draw_circle(_at, 34, Color("0c0e14"))
    draw_circle(_at, 28, Color("2a5bd7"))
    draw_circle(_at + Vector2(-22, -6), 13, Color("3d6fe6"))
