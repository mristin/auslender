class_name CavePaint
extends RefCounted

## Cave drawings, for the ice age instead of texts (nobody writes yet): stick
## figures of people with spears, mammoths, a peak, a cross; painted as thin
## flat strokes (see Flat) on the plane in front of the parent (facing +z),
## so that they bend with the road and fly off with what they are painted on.
##
## A drawing is [param size] meters high, its feet at [param at].

## How thick the strokes are, of the size of the drawing.
const STROKE := 0.06


## A person: a head, a body, legs and arms (up, or down); with a spear in his
## right hand, if [param spear].
static func person(
    parent: Node3D, at: Vector3, size: float, color: Color, arms_up := false, spear := false
) -> Node3D:
    var node := _node(parent, at, size)
    Flat.ball(node, 0.1, Vector3(0, 0.88, 0), color).scale.z = 0.1
    _line(node, [Vector2(0, 0.78), Vector2(0, 0.4)], color)
    _line(node, [Vector2(-0.16, 0), Vector2(0, 0.4), Vector2(0.16, 0)], color)
    var hand := 0.95 if arms_up else 0.45
    _line(node, [Vector2(-0.22, hand), Vector2(0, 0.68), Vector2(0.22, hand)], color)
    if spear:
        _line(node, [Vector2(0.26, -0.05), Vector2(0.26, 1.1)], color)
        _line(node, [Vector2(0.2, 1.0), Vector2(0.26, 1.18), Vector2(0.32, 1.0)], color)
    return node


## A mammoth, facing right: its back, its head, the trunk, a tusk, the legs and
## the tail; about 1.3 times as wide as high.
static func mammoth(parent: Node3D, at: Vector3, size: float, color: Color) -> Node3D:
    var node := _node(parent, at, size)
    var back := [
        Vector2(-0.5, 0.3),
        Vector2(-0.55, 0.55),
        Vector2(-0.4, 0.75),
        Vector2(-0.1, 0.85),
        Vector2(0.2, 0.8),
        Vector2(0.35, 0.92),
        Vector2(0.5, 0.78),
        Vector2(0.56, 0.55),
        Vector2(0.62, 0.3),
        Vector2(0.56, 0.1),
        Vector2(0.64, 0.04),
    ]
    _line(node, back, color)
    _line(node, [Vector2(-0.48, 0.3), Vector2(0.42, 0.3)], color)
    for x in [-0.42, -0.24, 0.16, 0.36]:
        _line(node, [Vector2(x, 0.3), Vector2(x, 0.0)], color)
    _line(node, [Vector2(0.5, 0.45), Vector2(0.72, 0.36), Vector2(0.8, 0.5)], color)
    _line(node, [Vector2(-0.53, 0.5), Vector2(-0.64, 0.32)], color)
    Flat.ball(node, 0.04, Vector3(0.42, 0.68, 0), color).scale.z = 0.1
    return node


## A peak, and a person on its top with his arms up.
static func summit(parent: Node3D, at: Vector3, size: float, color: Color) -> Node3D:
    var node := _node(parent, at, size)
    _line(node, [Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0.6, 0)], color)
    _line(node, [Vector2(-0.3, 0.3), Vector2(-0.12, 0.38), Vector2(0, 0.3)], color)
    person(node, Vector3(0, 0.6, 0), 0.4, color, true)
    return node


## A cross over what is [param size] high: not allowed.
static func cross(parent: Node3D, at: Vector3, size: float, color: Color) -> Node3D:
    var node := _node(parent, at, size)
    _line(node, [Vector2(-0.45, 0), Vector2(0.45, 1)], color, 1.6)
    _line(node, [Vector2(-0.45, 1), Vector2(0.45, 0)], color, 1.6)
    return node


static func _node(parent: Node3D, at: Vector3, size: float) -> Node3D:
    var node := Node3D.new()
    node.position = at
    node.scale = Vector3.ONE * size
    parent.add_child(node)
    return node


## The strokes through the [param points] (in the drawing's own units, a
## meter high, see _node), [param thick] times as thick as a plain one.
static func _line(node: Node3D, points: Array, color: Color, thick := 1.0) -> void:
    for k in range(points.size() - 1):
        var a: Vector2 = points[k]
        var b: Vector2 = points[k + 1]
        var middle := (a + b) * 0.5
        var stroke := Flat.box(
            node,
            Vector3(a.distance_to(b) + STROKE * thick, STROKE * thick, 0.02),
            Vector3(middle.x, middle.y, 0),
            color
        )
        stroke.rotation.z = (b - a).angle()
