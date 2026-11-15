class_name HandCursor
extends Control

## Cursors on the player's hands, as the hand detector of the vision finds
## them (see VisionService.GetPlayerHands: the hands in the mirrored camera
## picture, smoothed with a 1€ filter): each glove is drawn exactly where its
## hand is in the camera picture behind the menu (see CameraMirror), so that
## the player sees where he points. A hand held on a button (see DwellButton)
## for its dwell (three seconds) clicks it (as in The Steppe Rescue).
##
## The choice of the button is sticky: a hand stays on its button until it
## goes clearly beyond its edge, so that a trembling hand does not lose it. A
## hand below his hips (resting) is drawn dim and does not click.

## A hand leaves its button only when it is this far beyond its edge, in
## pixels (at most a share of the button's smaller side).
const STICKY_MARGIN := 48.0
const STICKY_MARGIN_SHARE := 0.35

## The COCO points of the hips.
const _HIPS := [11, 12]

var _vision: Node
## Per hand (left, right): where it is on the screen (negative if not seen),
## whether it may click, and the button it is on.
var _hands: Array[Vector2] = [Vector2(-1, -1), Vector2(-1, -1)]
var _active: Array[bool] = [false, false]
var _stuck: Array = [null, null]


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 100
    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        _vision = holder.service


func _process(delta: float) -> void:
    _read_hands()
    var held := {}
    for i in range(2):
        if _hands[i].x < 0.0 or not _active[i]:
            _stuck[i] = null
            continue
        _stuck[i] = _button_for(i)
        if _stuck[i] != null:
            held[_stuck[i]] = true
    # NOTE (mristin):
    # A button held by a hand fills; the others empty.
    for node in get_tree().get_nodes_in_group("dwell"):
        var button := node as DwellButton
        if held.has(button):
            button.dwell += delta / DwellButton.DWELL_SECONDS
            if button.dwell >= 1.0:
                button.click()
                _stuck = [null, null]
        elif button.dwell > 0.0:
            button.dwell = 0.0
    queue_redraw()


## Where the hands are on the screen: exactly where they are in the mirrored
## camera picture, which fills the screen.
func _read_hands() -> void:
    _hands = [Vector2(-1, -1), Vector2(-1, -1)]
    _active = [false, false]
    if _vision == null or _vision.GetStatus() == "Disabled":
        return
    var screen := get_viewport_rect().size
    var found: Array = _vision.GetPlayerHands()
    var hips := -1.0
    var points: PackedVector2Array = _vision.GetKeypoints()
    if points.size() > _HIPS[1]:
        hips = (points[_HIPS[0]].y + points[_HIPS[1]].y) * 0.5
    for i in range(mini(2, found.size())):
        if found[i] == null:
            continue
        var hand: Vector2 = found[i]
        _hands[i] = Vector2(hand.x * screen.x, hand.y * screen.y)
        _active[i] = hips < 0.0 or hand.y < hips


## The button the hand is on: the one it was on while it stays near it, else
## the one under it.
func _button_for(i: int) -> DwellButton:
    var at := _hands[i]
    var stuck: Variant = _stuck[i]
    if is_instance_valid(stuck):
        var held := stuck as DwellButton
        var margin := minf(STICKY_MARGIN, minf(held.size.x, held.size.y) * STICKY_MARGIN_SHARE)
        if (
            held.is_visible_in_tree()
            and not held.disabled
            and held.get_global_rect().grow(margin).has_point(at)
        ):
            return held
    return _button_at(at)


## The smallest open, visible button under the point, or null.
func _button_at(point: Vector2) -> DwellButton:
    var best: DwellButton = null
    for node in get_tree().get_nodes_in_group("dwell"):
        var button := node as DwellButton
        if not button.is_visible_in_tree() or button.disabled:
            continue
        if not button.get_global_rect().has_point(point):
            continue
        if best == null or button.size.x * button.size.y < best.size.x * best.size.y:
            best = button
    return best


func _draw() -> void:
    for i in range(2):
        var at := _hands[i]
        if at.x < 0.0:
            continue
        var alpha := 1.0 if _active[i] else 0.35
        # NOTE (mristin):
        # A big glove, its thumb on the inner side; a gold ring when it is on
        # a button.
        var inner := 22.0 if i == 0 else -22.0
        draw_circle(at, 36, Color(Color("0c0e14"), alpha))
        draw_circle(at, 30, Color(Color("2a5bd7"), alpha))
        draw_circle(at + Vector2(inner, -6), 13, Color(Color("3d6fe6"), alpha))
        if _stuck[i] != null:
            draw_arc(at, 44, 0, TAU, 40, Color("f2c14e"), 5)
