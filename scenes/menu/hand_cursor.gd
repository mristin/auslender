class_name HandCursor
extends Control

## Cursors which the player's raised hands move, seen by the camera (as in The
## Steppe Rescue): each hand above his shoulders moves a glove of its own
## across the screen; a hand below the shoulders does not count. A hand held on
## a button (see DwellButton) for its dwell (three seconds) clicks it.
##
## The gloves are calm and sticky: a glove glides towards its hand instead of
## jumping; on a button it sticks, staying well inside it (it moves only a
## share of the hand's way from the middle of the button), and leaves it only
## when the hand goes clearly beyond its edge.

## How far the hand moves (a share of the picture's width, around the
## shoulder) to cross the whole screen.
const REACH := 0.35

## A glove on a button leaves it only when the hand is this far beyond its
## edge, in pixels (at most a share of the button's smaller side).
const STICKY_MARGIN := 48.0
const STICKY_MARGIN_SHARE := 0.35

## On a button, the glove moves only this share of the way of the hand from
## the middle of the button.
const STICKY_SHARE := 0.35

## The time constant of the glove gliding, in seconds.
const GLIDE_SECONDS := 0.1

## The COCO points of the shoulders and the wrists.
const _SHOULDERS := [5, 6]
const _WRISTS := [9, 10]

var _vision: Node
## Per hand (left, right): where its glove is, whether the hand is raised, and
## the button it sticks to.
var _gloves: Array[Vector2] = [Vector2(-1, -1), Vector2(-1, -1)]
var _raised: Array[bool] = [false, false]
var _stuck: Array = [null, null]


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 100
    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        _vision = holder.service


func _process(delta: float) -> void:
    var hands := _raised_hands()
    var held := {}
    for i in range(2):
        var target: Vector2 = hands[i]
        _raised[i] = target.x >= 0.0
        if not _raised[i]:
            _stuck[i] = null
            _gloves[i] = Vector2(-1, -1)
            continue
        if _gloves[i].x < 0.0:
            _gloves[i] = target
        _gloves[i] = _glide(i, target, delta)
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
                for i in range(2):
                    _stuck[i] = null
        elif button.dwell > 0.0:
            button.dwell = 0.0
    queue_redraw()


## The glove glides towards its hand, and sticks to the button under it.
func _glide(i: int, target: Vector2, delta: float) -> Vector2:
    var glide := 1.0 - exp(-delta / GLIDE_SECONDS)
    var button: DwellButton = null
    var stuck: Variant = _stuck[i]
    if is_instance_valid(stuck):
        var held := stuck as DwellButton
        var margin := minf(STICKY_MARGIN, minf(held.size.x, held.size.y) * STICKY_MARGIN_SHARE)
        if (
            held.is_visible_in_tree()
            and not held.disabled
            and held.get_global_rect().grow(margin).has_point(target)
        ):
            button = held
    if button == null:
        button = _button_at(target)
    _stuck[i] = button
    if button == null:
        return _gloves[i].lerp(target, glide)
    var middle := button.get_global_rect().get_center()
    var wanted := middle + (target - middle) * STICKY_SHARE
    if not button.get_global_rect().has_point(wanted):
        wanted = middle
    return _gloves[i].lerp(wanted, glide)


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


## Where each raised hand (left, right) points on the screen (negative if the
## hand is not raised).
func _raised_hands() -> Array[Vector2]:
    var none: Array[Vector2] = [Vector2(-1, -1), Vector2(-1, -1)]
    if _vision == null or _vision.GetStatus() == "Disabled":
        return none
    var points: PackedVector2Array = _vision.GetKeypoints()
    if points.size() < 11:
        return none
    var shoulders := (points[_SHOULDERS[0]] + points[_SHOULDERS[1]]) * 0.5
    var screen := get_viewport_rect().size
    var found: Array[Vector2] = []
    for i in range(2):
        var wrist: Vector2 = points[_WRISTS[i]]
        # NOTE (mristin):
        # Above the shoulders (y grows down).
        if wrist.y >= shoulders.y:
            found.append(Vector2(-1, -1))
            continue
        var x := 0.5 + (wrist.x - shoulders.x) / REACH
        var y := 0.5 + (wrist.y - (shoulders.y - REACH * 0.5)) / REACH
        found.append(Vector2(clampf(x, 0.0, 1.0) * screen.x, clampf(y, 0.0, 1.0) * screen.y))
    return found


func _draw() -> void:
    for i in range(2):
        if not _raised[i]:
            continue
        var at := _gloves[i]
        # NOTE (mristin):
        # A big glove, its thumb on the inner side.
        var inner := 22.0 if i == 0 else -22.0
        draw_circle(at, 36, Color("0c0e14"))
        draw_circle(at, 30, Color("2a5bd7"))
        draw_circle(at + Vector2(inner, -6), 13, Color("3d6fe6"))
