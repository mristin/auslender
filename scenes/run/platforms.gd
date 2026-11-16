class_name Platforms
extends Node3D

## The platforms on the road of a run (see Run and DESIGN.md): raised decks
## over a lane or two, with gaps between their blocks, and boosters on them
## (see Boosters). The hero jumps up onto a platform as it reaches him, and
## runs on, above the obstacles; he jumps over its gaps. If he falls through a
## gap (or steps off its side), he goes on, on the road below: the lower
## level. Running into a platform without jumping bumps him, as an obstacle.
##
## Each land has its look: logs in the jungle, ice in the glacier, rock in
## the cave, crates in the city, walls of snow in the suburbs.

## How high the deck is over the road, and how wide (meters).
const HEIGHT := 0.5
const WIDTH := 1.9

## The looks of the decks, by the surroundings (see Scenery): the top, the
## sides, and the edge.
const LOOKS := {
    "jungle": [Color("8a5a2a"), Color("5a3a1a"), Color("3a2410")],
    "ice": [Color("eef6fc"), Color("8ac4e8"), Color("4a8ac0")],
    "cave": [Color("7a6a5a"), Color("4a3e34"), Color("2a221c")],
    "city": [Color("c8a060"), Color("8a6a3a"), Color("e8c020")],
    "suburbs": [Color("f4f7fb"), Color("a04a3a"), Color("d8e2ee")],
}

## The platforms: "node", "x" (the middle across the road), "start" and "end"
## (the times of the notes at which its front and its back reach him), and
## "blocks" (the times from which to which there is a deck, in order).
var _decks: Array = []


## Take all the platforms off the road.
func clear() -> void:
    for deck in _decks:
        (deck["node"] as Node).queue_free()
    _decks.clear()


## Put a platform on the road at [param x] across it, its blocks from and to
## the times of the notes in [param blocks] (in order), at [param speed]
## meters a second of the notes, in the look of the [param theme].
func add(x: float, blocks: Array, speed: float, theme: String) -> void:
    var node := Node3D.new()
    add_child(node)
    var colors: Array = LOOKS.get(theme, LOOKS["jungle"])
    var start: float = blocks[0].x
    for block: Vector2 in blocks:
        var length := (block.y - block.x) * speed
        var middle := -((block.x - start) * speed + length * 0.5)
        var top := Flat.box(
            node, Vector3(WIDTH, 0.08, length), Vector3(0, HEIGHT - 0.04, middle), colors[0]
        )
        (top.mesh as BoxMesh).subdivide_depth = int(length)
        var side := Flat.box(
            node,
            Vector3(WIDTH - 0.1, HEIGHT - 0.08, length - 0.1),
            Vector3(0, (HEIGHT - 0.08) * 0.5, middle),
            colors[1]
        )
        (side.mesh as BoxMesh).subdivide_depth = int(length)
        # NOTE (mristin):
        # A bright edge at its front, so that one sees where to jump.
        Flat.box(
            node,
            Vector3(WIDTH + 0.02, 0.06, 0.12),
            Vector3(0, HEIGHT - 0.02, middle + length * 0.5),
            colors[2]
        )
        _decorate(node, theme, middle, length, colors)
    node.visible = false
    (
        _decks
        . append(
            {
                "node": node,
                "x": x,
                "start": start,
                "end": (blocks[blocks.size() - 1] as Vector2).y,
                "blocks": blocks,
            }
        )
    )


## Place the platforms at the time of the notes [param t], from the player's
## [param spot].
func place(t: float, speed: float, spot: Vector3) -> void:
    for deck in _decks:
        var node: Node3D = deck["node"]
        var ahead: float = (float(deck["start"]) - t) * speed
        var behind: float = (float(deck["end"]) - t) * speed
        node.visible = ahead < Scenery.AHEAD and behind > -Scenery.BEHIND
        node.position = spot + Vector3(deck["x"], 0, -ahead)


## The platform under him at the time of the notes [param t] (between its
## front and its back), or an empty dictionary.
func under(t: float) -> Dictionary:
    for deck in _decks:
        if t >= float(deck["start"]) and t <= float(deck["end"]):
            return deck
    return {}


## The platform whose front reaches him between the times of the notes
## [param before] and [param now], or an empty dictionary.
func reached(before: float, now: float) -> Dictionary:
    for deck in _decks:
        if before < float(deck["start"]) and float(deck["start"]) <= now:
            return deck
    return {}


## The platform whose front he reaches next after the time of the notes
## [param t], or an empty dictionary.
func next(t: float) -> Dictionary:
    for deck in _decks:
        if float(deck["start"]) > t:
            return deck
    return {}


## Whether the platform has a deck at the time of the notes [param t] (not a
## gap).
static func solid(deck: Dictionary, t: float) -> bool:
    for block: Vector2 in deck["blocks"]:
        if t >= block.x and t <= block.y:
            return true
    return false


## Whether he is over the platform, at [param x] across the road.
static func over(deck: Dictionary, x: float) -> bool:
    return absf(x - float(deck["x"])) <= WIDTH * 0.5 + 0.15


## The look of the land on a block of a deck.
static func _decorate(
    node: Node3D, theme: String, middle: float, length: float, colors: Array
) -> void:
    match theme:
        "jungle":
            # NOTE (mristin):
            # Logs across, as a bridge of the jungle.
            var z := middle + length * 0.5 - 0.3
            while z > middle - length * 0.5:
                var trunk := Flat.limb(node, 0.06, 0.06, WIDTH, Vector3(0, HEIGHT, z), colors[2])
                trunk.rotation.z = PI * 0.5
                z -= 0.6
        "city":
            # NOTE (mristin):
            # Crates, with their planks.
            var z := middle + length * 0.5 - 0.6
            while z > middle - length * 0.5:
                for x in [-WIDTH * 0.5, WIDTH * 0.5]:
                    Flat.box(
                        node,
                        Vector3(0.04, HEIGHT - 0.1, 0.1),
                        Vector3(x, HEIGHT * 0.5, z),
                        colors[2]
                    )
                z -= 1.2
        "suburbs":
            # NOTE (mristin):
            # A wall of bricks, its top heavy with snow.
            var z := middle + length * 0.5 - 0.25
            var row := 0
            while z > middle - length * 0.5:
                for x in [-WIDTH * 0.5, WIDTH * 0.5]:
                    Flat.box(
                        node,
                        Vector3(0.02, 0.03, 0.42),
                        Vector3(x, 0.12 + (row % 2) * 0.15, z),
                        Color("6a2a20")
                    )
                z -= 0.5
                row += 1
        "ice", "cave":
            # NOTE (mristin):
            # Lumps of ice or rock along its sides.
            var random := RandomNumberGenerator.new()
            random.seed = hash(middle)
            var z := middle + length * 0.5 - 0.4
            while z > middle - length * 0.5:
                for x in [-WIDTH * 0.5, WIDTH * 0.5]:
                    Flat.ball(
                        node,
                        random.randf_range(0.1, 0.18),
                        Vector3(x, HEIGHT - 0.05, z),
                        colors[1].darkened(random.randf_range(0.0, 0.2))
                    )
                z -= random.randf_range(0.7, 1.3)
