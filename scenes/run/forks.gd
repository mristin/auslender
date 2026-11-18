class_name Forks
extends Node3D

## The forks of the road of a run (see Run and DESIGN.md): a side road
## branches off to the left or the right, a signpost points to it, and the
## edge of the road glows on its side as it comes. If the hero runs all the way
## to that side as the fork reaches him, he takes the side road, a shortcut:
## he comes out further ahead on the road, past the obstacles in between.

## How far to the side he must be to take a fork (meters from the middle of
## the road): beyond the outer lane, all the way to the side.
const TAKE_FROM := Scenery.LANE * 1.1

## How long the side road is, and at what angle it leaves the road.
const LENGTH := 30.0
const ANGLE := 0.6

## How far ahead of the fork its edge glows (meters).
const GLOW := 9.0

## The forks: "node", "at" (the time of the notes at which it reaches him),
## "side" (-1 left, 1 right), "skip" (how far ahead in the time of the notes
## the shortcut takes him) and "state" ("ahead", "taken", "passed").
var _forks: Array = []


## Take all the forks off the road.
func clear() -> void:
    for fork in _forks:
        (fork["node"] as Node).queue_free()
    _forks.clear()


## Put a fork on the road, which reaches him at the time of the notes
## [param at], to the [param side] (-1 left, 1 right), with a shortcut of
## [param skip] in the time of the notes; [param road] is the color of the
## road, [param edge] how far its edge is from the middle.
func add(at: float, side: float, skip: float, road: Color, edge: float) -> void:
    var node := Node3D.new()
    add_child(node)
    # NOTE (mristin):
    # The side road, leaving at an angle from the edge of the road, forwards.
    var direction := Vector3(side * sin(ANGLE), 0, -cos(ANGLE))
    # NOTE (mristin):
    # A little raised, over the sidewalks of the city.
    var branch := Flat.box(
        node,
        Vector3(edge * 1.2, 0.14, LENGTH),
        Vector3(side * edge, 0.07, 0) + direction * (LENGTH * 0.5 - 1.0),
        road.lightened(0.12),
        true
    )
    branch.rotation.y = -side * ANGLE
    (branch.mesh as BoxMesh).subdivide_depth = int(LENGTH)
    # NOTE (mristin):
    # The glowing edge on its side, before the fork.
    var glow := Flat.box(
        node,
        Vector3(0.18, 0.03, GLOW),
        Vector3(side * (edge - 0.1), 0.02, GLOW * 0.5),
        Color("f2c14e")
    )
    (glow.mesh as BoxMesh).subdivide_depth = int(GLOW)
    # NOTE (mristin):
    # The signpost: a post and a board, an arrow pointing to the side road.
    var post_at := Vector3(side * (edge + 0.5), 0, 1.5)
    Flat.post(node, 0.05, 2.0, post_at + Vector3(0, 1.0, 0), Color("6a6a6a"))
    var board := Node3D.new()
    node.add_child(board)
    board.position = post_at + Vector3(0, 1.8, 0)
    Flat.box(board, Vector3(1.1, 0.4, 0.05), Vector3.ZERO, Color("f2c14e"))
    Flat.box(board, Vector3(0.6, 0.1, 0.06), Vector3(-side * 0.1, 0, 0), Color("1a1a1a"))
    for k in [-1.0, 1.0]:
        var head := Flat.box(
            board, Vector3(0.28, 0.08, 0.06), Vector3(side * 0.24, k * 0.08, 0), Color("1a1a1a")
        )
        head.rotation.z = side * k * -0.8
    node.visible = false
    _forks.append({"node": node, "at": at, "side": side, "skip": skip, "state": "ahead"})


## Place the forks at the time of the notes [param t], from the player's
## [param spot].
func place(t: float, speed: float, spot: Vector3) -> void:
    for fork in _forks:
        var node: Node3D = fork["node"]
        var ahead: float = (float(fork["at"]) - t) * speed
        node.visible = ahead < Scenery.AHEAD + 10.0 and ahead > -LENGTH
        node.position = spot + Vector3(0, 0, -ahead)


## The fork which he reaches between the times of the notes [param before]
## and [param now] (and passes, or takes, at [param x] across the road), or
## an empty dictionary.
func reached(before: float, now: float, x: float) -> Dictionary:
    for fork in _forks:
        if fork["state"] != "ahead" or before >= float(fork["at"]) or float(fork["at"]) > now:
            continue
        var taken := x * float(fork["side"]) >= TAKE_FROM
        fork["state"] = "taken" if taken else "passed"
        return fork
    return {}


## Where the props beside the road must give way to the side roads of the
## forks in sight (see Scenery.keep_clear).
func clearings() -> Array:
    var out: Array = []
    for fork in _forks:
        var node: Node3D = fork["node"]
        if node.visible:
            var z := node.position.z
            out.append([fork["side"], z + 1.0, z - LENGTH * cos(ANGLE) - 2.0])
    return out


## The next fork ahead of the time of the notes [param t], or an empty
## dictionary.
func next(t: float) -> Dictionary:
    for fork in _forks:
        if fork["state"] == "ahead" and float(fork["at"]) > t:
            return fork
    return {}
