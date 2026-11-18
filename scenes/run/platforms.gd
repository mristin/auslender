class_name Platforms
extends Node3D

## The platforms on the road of a run (see Run and DESIGN.md): raised blocks in
## a lane, one level high or two, with gaps, and boosters on them (see
## Boosters). He need not jump up onto a platform: running into it, he steps
## up onto it (a level at a time or two), and runs on, above the obstacles. A
## gap goes one level down (a notch in the upper level, or down to the road
## from the lower one) or two (through both levels, down to the road): he
## jumps over it, or falls through. Falling one level does not hurt; falling
## through two at once (or off the side of the upper level) hurts him, as an
## obstacle.
##
## Each land has its look: logs in the jungle, ice in the glacier, rock in
## the cave, crates in the city, walls of snow in the suburbs.

## How high a level is over the one below (meters), and how wide a platform.
const HEIGHT := 0.5
const WIDTH := 1.9

## The looks of the blocks, by the surroundings (see Scenery): the top, the
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
## "segments" (in order, each [from, to, level] in the times of the notes: a
## block of the level, 1 or 2, or a gap down to the level, 0 or 1).
var _decks: Array = []


## Take all the platforms off the road.
func clear() -> void:
    for deck in _decks:
        (deck["node"] as Node).queue_free()
    _decks.clear()


## Put a platform on the road at [param x] across it, of the
## [param segments] (see _decks), at [param speed] meters a second of the
## notes, in the look of the [param theme].
func add(x: float, segments: Array, speed: float, theme: String) -> void:
    var node := Node3D.new()
    add_child(node)
    var colors: Array = LOOKS.get(theme, LOOKS["jungle"])
    var start: float = segments[0][0]
    var below := 0
    for segment: Array in segments:
        var level: int = segment[2]
        var length := (float(segment[1]) - float(segment[0])) * speed
        var middle := -((float(segment[0]) - start) * speed + length * 0.5)
        if level > 0:
            _build_block(node, level, middle, length, colors, theme, level > below)
        below = level
    node.visible = false
    (
        _decks
        . append(
            {
                "node": node,
                "x": x,
                "start": start,
                "end": float(segments[segments.size() - 1][1]),
                "segments": segments,
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


## The level under him at the time of the notes [param t], at [param x]
## across the road: 0 the road, 1 or 2 on a platform.
func ground(t: float, x: float) -> int:
    var deck := under(t)
    if deck.is_empty() or not over(deck, x):
        return 0
    for segment: Array in deck["segments"]:
        if t >= float(segment[0]) and t <= float(segment[1]):
            return segment[2]
    return 0


## When the next drop below [param level] comes under him after the time of
## the notes [param t] (a gap, or the end of the platform), or -1 if none
## within the platform under him.
func next_drop(t: float, level: int) -> float:
    var deck := under(t)
    if deck.is_empty():
        return -1.0
    for segment: Array in deck["segments"]:
        if float(segment[0]) > t and int(segment[2]) < level:
            return segment[0]
    return float(deck["end"]) if level > 0 else -1.0


## Whether he is over the platform, at [param x] across the road.
static func over(deck: Dictionary, x: float) -> bool:
    return absf(x - float(deck["x"])) <= WIDTH * 0.5 + 0.15


## The segments of a platform from the time of the notes [param start] to
## about [param end], at random: it starts and ends one level high; a gap is
## [param gap] long, one level deep or (from the upper level) sometimes two.
static func segments(start: float, end: float, gap: float) -> Array:
    var out: Array = [[start, start + randf_range(0.8, 1.1), 1]]
    var level := 1
    var t: float = out[0][1]
    while t < end - 1.2:
        var length := randf_range(0.8, 1.2)
        if level == 1 and randf() < 0.65:
            level = 2
        else:
            var depth := 2 if level == 2 and randf() < 0.5 else 1
            out.append([t, t + gap, level - depth])
            t += gap
        out.append([t, t + length, level])
        t += length
    if level == 2:
        out.append([t, t + 0.9, 1])
    return out


## A block of the [param level], [param length] long around [param middle]
## (along the platform), with a bright edge at its front if it rises there
## ([param rises]), so that one sees where it goes up.
static func _build_block(
    node: Node3D,
    level: int,
    middle: float,
    length: float,
    colors: Array,
    theme: String,
    rises: bool
) -> void:
    var height := HEIGHT * level
    var top := Flat.box(
        node, Vector3(WIDTH, 0.08, length), Vector3(0, height - 0.04, middle), colors[0]
    )
    (top.mesh as BoxMesh).subdivide_depth = int(length)
    var side := Flat.box(
        node,
        Vector3(WIDTH - 0.1, height - 0.08, length - 0.1),
        Vector3(0, (height - 0.08) * 0.5, middle),
        colors[1].darkened(0.1 * (level - 1))
    )
    (side.mesh as BoxMesh).subdivide_depth = int(length)
    if rises:
        Flat.box(
            node,
            Vector3(WIDTH + 0.02, 0.06, 0.12),
            Vector3(0, height - 0.02, middle + length * 0.5),
            colors[2]
        )
    _decorate(node, theme, middle, length, height, colors)


## The look of the land on a block, [param height] high.
static func _decorate(
    node: Node3D, theme: String, middle: float, length: float, height: float, colors: Array
) -> void:
    match theme:
        "jungle":
            # NOTE (mristin):
            # Logs across, as a bridge of the jungle.
            var z := middle + length * 0.5 - 0.3
            while z > middle - length * 0.5:
                var trunk := Flat.limb(node, 0.06, 0.06, WIDTH, Vector3(0, height, z), colors[2])
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
                        Vector3(0.04, height - 0.1, 0.1),
                        Vector3(x, height * 0.5, z),
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
                    var y := 0.12 + (row % 2) * 0.15
                    while y < height - 0.1:
                        Flat.box(node, Vector3(0.02, 0.03, 0.42), Vector3(x, y, z), Color("6a2a20"))
                        y += 0.3
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
                        Vector3(x, height - 0.05, z),
                        colors[1].darkened(random.randf_range(0.0, 0.2))
                    )
                z -= random.randf_range(0.7, 1.3)
