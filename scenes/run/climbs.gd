class_name Climbs
extends Node3D

## The climbs on the road of a run (see Run and DESIGN.md): stairs, a slope
## up a mountain or a hill, or a ladder up a wall, across the whole road. He
## climbs them as he runs, lifting his knees, only slower: up the stairs and
## the slopes he goes on at a part of his pace, up a ladder straight up (the
## road holds, as in a fight, while he climbs). On the top, he runs on (a
## booster waits there, and the top gives points), and down the other side,
## quickly: down the stairs, or down a slide (much faster than he runs).
##
## Each land has its own: the stacked boulders in the jungle, the snowy
## mountain on the glacier, the stairs up to a footbridge in the streets, the
## ladders up the scaffold of the new tower of Rochartis on the campus, the
## ladders up a garden shed, and a hill with its summit cross by the meadow.

## The climbs: their title, how one goes up ("stairs", "slope" or "ladder")
## and down ("stairs" or "slide"), and its colors: the top, the front of the
## steps, the sides, and the slide; a mountain or a hill has slopes on its
## sides, too ("skirt": how far out they reach for each meter up).
const LOOKS := {
    "boulders":
    {
        "title": "THE BOULDERS",
        "up": "stairs",
        "down": "slide",
        "colors": [Color("8a8a74"), Color("6a6a58"), Color("5a5a48"), Color("6a4a28")],
    },
    "mountain":
    {
        "title": "THE MOUNTAIN",
        "up": "slope",
        "down": "slide",
        "colors": [Color("f2f8fc"), Color("8a9aaa"), Color("7a8a9c"), Color("a8dcf4")],
        "skirt": 1.3,
    },
    "footbridge":
    {
        "title": "THE FOOTBRIDGE",
        "up": "stairs",
        "down": "stairs",
        "colors": [Color("bab6ae"), Color("8a8680"), Color("9a968e"), Color("bab6ae")],
    },
    "scaffold":
    {
        "title": "THE SCAFFOLD OF THE NEW TOWER",
        "up": "ladder",
        "down": "slide",
        "colors": [Color("b08a5a"), Color("7a5a3a"), Color("2a6ac0"), Color("e8701a")],
    },
    "shed":
    {
        "title": "THE GARDEN SHED",
        "up": "ladder",
        "down": "slide",
        "colors": [Color("f4f7fb"), Color("8a5a2a"), Color("7a4a22"), Color("e4ecf4")],
    },
    "hill":
    {
        "title": "THE HILL",
        "up": "slope",
        "down": "slide",
        "colors": [Color("f4f7fb"), Color("c8d4e0"), Color("e4ecf4"), Color("dce8f4")],
        "skirt": 1.6,
    },
}

## How high a climb goes (meters), how high a step is, and how wide a climb
## is (the whole road and its edges).
const HEIGHT := 3.0
const STEP := 0.25
const WIDTH := 5.4

## How steep the ways are (up over along), and how long the top is (meters).
const STEEP := {"stairs": 0.5, "slope": 0.35, "slide": 0.5, "down_stairs": 0.55}
const TOP := 6.0

## How much of his pace he keeps going up, and how many times as fast he goes
## down a slide, or down the stairs.
const UPHILL := 0.6
const DOWNHILL := {"slide": 1.8, "down_stairs": 1.3}

## How far in front of a ladder he stops to climb it (meters), how fast he
## climbs it at the normal pace (meters a second), and where across the road
## its ladders stand.
const STAND := 0.6
const LADDER_SPEED := 0.9
const LADDERS: Array[float] = [-1.4, 0.0, 1.4]

## How far apart the rungs of a ladder are.
const RUNG := 0.3

## The climbs on the road: "node", "look", "start" (the time of the notes at
## which its foot reaches him), "end" (at which its end does), "parts" (in
## order, each [from, to, height at from, height at to, way]: a way is
## "stairs", "slope" or "ladder" (from and to the same) up, "top", or
## "down_stairs" or "slide" down), "state" ("ahead", "climbing" a ladder, or
## "done"), and "labels" (the texts on it, which the shaders do not bend).
var _items: Array = []


## Take all the climbs off the road.
func clear() -> void:
    for item in _items:
        (item["node"] as Node).queue_free()
    _items.clear()


## Put a climb of the [param look] on the road, its foot at the time of the
## notes [param start], at [param speed] meters a second of the notes; the
## time of the notes at which it ends.
func add(look: String, start: float, speed: float) -> float:
    var spec: Dictionary = LOOKS[look]
    var up: String = spec["up"]
    var down: String = "down_stairs" if spec["down"] == "stairs" else "slide"
    var rise := 0.0 if up == "ladder" else HEIGHT / float(STEEP[up]) / speed
    var top := start + rise
    var fall := top + TOP / speed
    var end := fall + HEIGHT / float(STEEP[down]) / speed
    var parts: Array = [
        [start, top, 0.0, HEIGHT, up],
        [top, fall, HEIGHT, HEIGHT, "top"],
        [fall, end, HEIGHT, 0.0, down],
    ]
    var node := Node3D.new()
    add_child(node)
    _build(node, look, parts, start, speed)
    var labels: Array = node.find_children("*", "Label3D", true, false)
    for label: Label3D in labels:
        label.set_meta("x", label.position.x)
    node.visible = false
    (
        _items
        . append(
            {
                "node": node,
                "look": look,
                "start": start,
                "end": end,
                "parts": parts,
                "state": "ahead",
                "labels": labels,
            }
        )
    )
    return end


## Place the climbs at the time of the notes [param t], from the player's
## [param spot], with the road bending by [param bend] (see Scenery.set_bend).
func place(t: float, speed: float, spot: Vector3, bend: float) -> void:
    for item in _items:
        var node: Node3D = item["node"]
        var ahead: float = (float(item["start"]) - t) * speed
        var behind: float = (float(item["end"]) - t) * speed
        node.visible = ahead < Scenery.AHEAD and behind > -Scenery.BEHIND
        node.position = spot + Vector3(0, 0, -ahead)
        # NOTE (mristin):
        # The texts do not bend with the shaders: move them as the road bends.
        for label: Label3D in item["labels"]:
            var there := maxf(0.0, ahead - label.position.z)
            label.position.x = float(label.get_meta("x")) + bend * there * there


## Where the props beside the road must give way to the slopes of the
## mountains and the hills in sight (see Scenery.keep_clear).
func clearings() -> Array:
    var out: Array = []
    for item in _items:
        var node: Node3D = item["node"]
        if node.visible and LOOKS[item["look"]].has("skirt"):
            var z := node.position.z
            var length := (float(item["end"]) - float(item["start"])) * RhythmLevel.SPEED
            for side in [-1.0, 1.0]:
                out.append([side, z + 1.0, z - length - 1.0])
    return out


## The part of a climb under him at the time of the notes [param t] (see
## _items; not a ladder), or an empty array.
func part(t: float) -> Array:
    for item in _items:
        if t < float(item["start"]) or t > float(item["end"]):
            continue
        for piece: Array in item["parts"]:
            if piece[4] != "ladder" and t >= float(piece[0]) and t <= float(piece[1]):
                return piece
    return []


## How he goes at the time of the notes [param t]: the way of the part under
## him (see _items), or "" off the climbs.
func way(t: float) -> String:
    var piece := part(t)
    return "" if piece.is_empty() else str(piece[4])


## How high the climb is under him at the time of the notes [param t], in
## meters (0 off the climbs): the stairs step by step.
func height(t: float) -> float:
    var piece := part(t)
    if piece.is_empty():
        return 0.0
    var from: float = piece[0]
    var to: float = piece[1]
    var low: float = piece[2]
    var high: float = piece[3]
    var along := clampf((t - from) / maxf(to - from, 0.001), 0.0, 1.0)
    match str(piece[4]):
        "stairs":
            return minf(HEIGHT, (floorf(along * HEIGHT / STEP) + 1.0) * STEP)
        "down_stairs":
            return maxf(0.0, HEIGHT - (floorf(along * HEIGHT / STEP) + 1.0) * STEP)
    return lerpf(low, high, along)


## How many times as fast as he runs he goes on at the time of the notes
## [param t]: slower up, faster down.
func pace(t: float) -> float:
    var going := way(t)
    if going == "stairs" or going == "slope":
        return UPHILL
    return float(DOWNHILL.get(going, 1.0))


## The ways of the parts which he entered between the times of the notes
## [param before] and [param now] (not a ladder; see climb).
func entered(before: float, now: float) -> Array[String]:
    var out: Array[String] = []
    for item in _items:
        for piece: Array in item["parts"]:
            var from: float = piece[0]
            if piece[4] != "ladder" and from > before and from <= now:
                out.append(str(piece[4]))
    return out


## The index of the climb with a ladder which he reaches by the time of the
## notes [param t] (at [param speed]), or -1.
func ladder(t: float, speed: float) -> int:
    for i in range(_items.size()):
        var item: Dictionary = _items[i]
        if item["state"] != "ahead" or LOOKS[item["look"]]["up"] != "ladder":
            continue
        if t >= float(item["start"]) - STAND / speed and t < float(item["end"]):
            return i
    return -1


## He starts to climb the ladder of the climb of the [param index]: the time
## of the notes at which he stands at its foot (at [param speed]).
func climb(index: int, speed: float) -> float:
    var item: Dictionary = _items[index]
    item["state"] = "climbing"
    return float(item["start"]) - STAND / speed


## He climbed up the ladder of the climb of the [param index]: the time of
## the notes at its top.
func climbed(index: int) -> float:
    var item: Dictionary = _items[index]
    item["state"] = "done"
    return float(item["start"]) + 0.01


## The look of the climb of the [param index].
func look(index: int) -> String:
    return _items[index]["look"]


## Where across the road the ladder nearest to [param x] stands.
static func ladder_at(x: float) -> float:
    var best := LADDERS[0]
    for at in LADDERS:
        if absf(at - x) < absf(best - x):
            best = at
    return best


## Build the climb of the [param look] into the [param node], its foot at
## z = 0, of the [param parts] (from the time of the notes [param start], at
## [param speed]).
static func _build(node: Node3D, look: String, parts: Array, start: float, speed: float) -> void:
    var colors: Array = LOOKS[look]["colors"]
    var profiles: Array = []
    for piece: Array in parts:
        var from := (float(piece[0]) - start) * speed
        var to := (float(piece[1]) - start) * speed
        var points := _profile(str(piece[4]), from, to, float(piece[2]), float(piece[3]))
        profiles.append(points)
        var top: Color = colors[3] if piece[4] == "slide" else colors[0]
        _solid(node, points, top, colors[1], colors[2], float(LOOKS[look].get("skirt", 0.0)))
    var rise: PackedVector2Array = profiles[0]
    var flat_from: float = rise[rise.size() - 1].x
    var flat: PackedVector2Array = profiles[1]
    var flat_to: float = flat[flat.size() - 1].x
    var down: PackedVector2Array = profiles[2]
    var end: float = down[down.size() - 1].x
    match look:
        "boulders":
            _build_boulders(node, flat_from, flat_to, end)
        "mountain":
            _build_mountain(node, flat_from, flat_to, end)
        "footbridge":
            _build_footbridge(node, flat_from, flat_to, end)
        "scaffold":
            _build_scaffold(node, flat_from, flat_to, end)
        "shed":
            _build_shed(node, flat_from, flat_to, end)
        "hill":
            _build_hill(node, flat_from, flat_to, end)


## The profile of a part: the points (along the road, up) of its top from
## [param from] to [param to] (meters from the foot), from the height
## [param low] to [param high], of the [param way]; the stairs step by step.
static func _profile(
    way: String, from: float, to: float, low: float, high: float
) -> PackedVector2Array:
    var points := PackedVector2Array()
    var steps := roundi(HEIGHT / STEP)
    match way:
        "ladder":
            points.append(Vector2(from, low))
            points.append(Vector2(from, high))
        "stairs":
            points.append(Vector2(from, 0.0))
            for i in range(steps):
                var z := from + (to - from) * i / steps
                points.append(Vector2(z, (i + 1) * STEP))
                points.append(Vector2(from + (to - from) * (i + 1) / steps, (i + 1) * STEP))
        "down_stairs":
            points.append(Vector2(from, HEIGHT))
            for i in range(steps):
                var z := from + (to - from) * i / steps
                points.append(Vector2(z, HEIGHT - (i + 1) * STEP))
                points.append(
                    Vector2(from + (to - from) * (i + 1) / steps, HEIGHT - (i + 1) * STEP)
                )
        _:
            points.append(Vector2(from, low))
            points.append(Vector2(to, high))
    # NOTE (mristin):
    # Fine enough along the road that the road's bend (a shader) curves it.
    var fine := PackedVector2Array([points[0]])
    for i in range(1, points.size()):
        var a := points[i - 1]
        var b := points[i]
        var pieces := maxi(1, ceili((b.x - a.x) / 1.0))
        for k in range(1, pieces + 1):
            fine.append(a.lerp(b, float(k) / pieces))
    return fine


## A solid across the road of the profile [param points] (see _profile): its
## top of the color [param top] (its upright faces, the fronts of the steps,
## of [param front]), and its sides, down to the road, of [param side]:
## upright, or sloping out by [param skirt] meters for each meter up.
static func _solid(
    node: Node3D, points: PackedVector2Array, top: Color, front: Color, side: Color, skirt: float
) -> void:
    var tops := SurfaceTool.new()
    var fronts := SurfaceTool.new()
    var sides := SurfaceTool.new()
    for tool in [tops, fronts, sides]:
        (tool as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
    var half := WIDTH * 0.5
    for i in range(1, points.size()):
        var a := points[i - 1]
        var b := points[i]
        var upright := absf(b.x - a.x) < 0.001
        _quad(
            fronts if upright else tops,
            Vector3(-half, a.y, -a.x),
            Vector3(half, a.y, -a.x),
            Vector3(half, b.y, -b.x),
            Vector3(-half, b.y, -b.x)
        )
        if upright:
            continue
        for x: float in [-half, half]:
            _quad(
                sides,
                Vector3(x + signf(x) * a.y * skirt, 0, -a.x),
                Vector3(x, a.y, -a.x),
                Vector3(x, b.y, -b.x),
                Vector3(x + signf(x) * b.y * skirt, 0, -b.x)
            )
    for pair in [[tops, top], [fronts, front], [sides, side]]:
        var mesh := (pair[0] as SurfaceTool).commit()
        if mesh.get_surface_count() == 0:
            continue
        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        instance.material_override = Flat.material(pair[1])
        node.add_child(instance)


## A quad of the corners, seen from both sides (the shader shades by the
## screen, see flat.gdshader).
static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    for corner in [a, b, c, a, c, d, a, c, b, a, d, c]:
        tool.add_vertex(corner)


## A slanted bar from [param from] to [param to], [param thick] thick.
static func _bar(node: Node3D, from: Vector3, to: Vector3, thick: float, color: Color) -> void:
    var bar := Flat.box(node, Vector3(thick, thick, from.distance_to(to)), (from + to) * 0.5, color)
    if from.distance_to(to) > 0.01:
        bar.basis = Basis.looking_at(to - from, Vector3.UP)
    (bar.mesh as BoxMesh).subdivide_depth = int(from.distance_to(to))


## Railings on both sides, along the profile from [param from] to
## [param to] (meters from the foot, at the heights [param low] and
## [param high]), of the color.
static func _railings(
    node: Node3D, from: float, to: float, low: float, high: float, color: Color
) -> void:
    var half := WIDTH * 0.5 - 0.1
    for x in [-half, half]:
        var a := Vector3(x, low + 0.9, -from)
        var b := Vector3(x, high + 0.9, -to)
        _bar(node, a, b, 0.05, color)
        var posts := maxi(1, ceili((to - from) / 1.5))
        for k in range(posts + 1):
            var at := a.lerp(b, float(k) / posts)
            Flat.box(node, Vector3(0.04, 0.9, 0.04), at - Vector3(0, 0.45, 0), color)


## A text on the climb, [param size] big.
static func _label(node: Node3D, text: String, at: Vector3, size: int, color: Color) -> Label3D:
    var label := Label3D.new()
    label.text = text
    label.font_size = size
    label.outline_size = 8
    label.outline_modulate = Color("1a1a1a")
    label.pixel_size = 0.004
    label.modulate = color
    label.position = at
    node.add_child(label)
    return label


## The ladders up the front of a climb, from the road to its top and a little
## over it, of the colors of the rails and the rungs.
static func _ladders(node: Node3D, rail: Color, rung: Color) -> void:
    for x in LADDERS:
        for side in [-0.24, 0.24]:
            Flat.box(
                node,
                Vector3(0.06, HEIGHT + 0.7, 0.06),
                Vector3(x + side, (HEIGHT + 0.7) * 0.5, 0.1),
                rail
            )
        var y := RUNG
        while y < HEIGHT + 0.6:
            Flat.box(node, Vector3(0.5, 0.04, 0.05), Vector3(x, y, 0.1), rung)
            y += RUNG


## A fir tree, [param high] high, at the foot [param at].
static func _fir(node: Node3D, at: Vector3, high: float) -> void:
    Flat.limb(node, 0.06, 0.08, high * 0.3, at + Vector3(0, high * 0.15, 0), Color("5a3a1a"))
    Flat.limb(node, 0.0, high * 0.32, high * 0.8, at + Vector3(0, high * 0.6, 0), Color("2a5a3a"))
    Flat.limb(node, 0.0, high * 0.2, high * 0.3, at + Vector3(0, high * 0.92, 0), Color("f4f7fb"))


## The boulders of the jungle: stones stacked into rough steps (each step a
## row of boulders of all sizes), moss and ferns between them, vines down
## their sides, and a slide of mud down.
static func _build_boulders(node: Node3D, flat_from: float, flat_to: float, end: float) -> void:
    var half := WIDTH * 0.5
    var random := RandomNumberGenerator.new()
    random.seed = 7
    var stone := Color("7a7a68")
    var steps := roundi(HEIGHT / STEP)
    for i in range(steps):
        var z := flat_from * i / steps
        var y := (i + 0.5) * STEP
        var x := -half
        while x < half:
            var size := random.randf_range(0.22, 0.4)
            var boulder := Flat.ball(
                node,
                size,
                Vector3(x + size * 0.6, y, -z - size * 0.3),
                stone.darkened(random.randf_range(-0.1, 0.25)),
                false,
                0.6
            )
            boulder.rotation.y = random.randf_range(0.0, TAU)
            if random.randf() < 0.15:
                Flat.ball(node, 0.12, Vector3(x + size, y + size * 0.3, -z - 0.1), Color("4a8a3a"))
            x += size * random.randf_range(1.1, 1.5)
    for side: float in [-1.0, 1.0]:
        var z := 0.6
        while z < end - 0.6:
            var top := minf(HEIGHT, minf(z * 0.5, (end - z) * 0.5))
            var boulder := Flat.ball(
                node,
                random.randf_range(0.3, 0.55),
                Vector3(side * (half + 0.1), random.randf_range(0.2, maxf(0.3, top - 0.2)), -z),
                stone.darkened(random.randf_range(0.0, 0.25)),
                false,
                0.7
            )
            boulder.rotation.y = random.randf_range(0.0, TAU)
            if random.randf() < 0.5:
                var vine := Flat.limb(
                    node,
                    0.03,
                    0.03,
                    top * 0.8,
                    Vector3(side * (half + 0.05), top * 0.6, -z - 0.3),
                    Color("3a7a2a")
                )
                vine.rotation.z = random.randf_range(-0.2, 0.2)
                Flat.ball(node, 0.14, Vector3(side * (half + 0.05), top, -z - 0.3), Color("4a9a3a"))
            z += random.randf_range(0.7, 1.1)
    for k in range(4):
        var x := random.randf_range(-half + 0.4, half - 0.4)
        var z := random.randf_range(flat_from + 0.5, flat_to - 0.5)
        for leaf in range(5):
            var frond := Flat.limb(
                node, 0.0, 0.08, 0.6, Vector3(x, HEIGHT + 0.25, -z), Color("3a8a3a")
            )
            frond.rotation = Vector3(0.7, leaf * TAU / 5.0, 0)
    for x in [-1.0, 0.0, 1.0]:
        _bar(
            node, Vector3(x, HEIGHT + 0.01, -flat_to), Vector3(x, 0.01, -end), 0.08, Color("4a3018")
        )


## The mountain of the glacier: rocks on its sides, a flag on its summit,
## and the ice of the slide down.
static func _build_mountain(node: Node3D, flat_from: float, flat_to: float, end: float) -> void:
    var half := WIDTH * 0.5
    var random := RandomNumberGenerator.new()
    random.seed = 11
    var skirt: float = LOOKS["mountain"]["skirt"]
    for side: float in [-1.0, 1.0]:
        var z := 0.5
        while z < end:
            var top := minf(HEIGHT, minf(z * 0.35, (end - z) * 0.5))
            var up := random.randf_range(0.0, top)
            Flat.ball(
                node,
                random.randf_range(0.25, 0.5),
                Vector3(side * (half + (top - up) * skirt), up, -z),
                Color("6a7a8c").darkened(random.randf_range(0.0, 0.2))
            )
            z += random.randf_range(0.8, 1.4)
    var z := (flat_from + flat_to) * 0.5
    Flat.post(node, 0.04, 2.2, Vector3(half - 0.4, HEIGHT + 1.1, -z), Color("4a4a4a"))
    Flat.box(
        node, Vector3(0.02, 0.5, 0.8), Vector3(half - 0.4, HEIGHT + 1.95, -z + 0.4), Color("d82020")
    )
    _label(node, "SUMMIT", Vector3(0, HEIGHT + 1.6, -flat_from), 96, Color("ffffff"))
    for x in [-1.2, 0.0, 1.2]:
        _bar(
            node, Vector3(x, HEIGHT + 0.01, -flat_to), Vector3(x, 0.01, -end), 0.06, Color("e8f6ff")
        )


## The footbridge of the streets: concrete stairs with railings, a bridge
## over the road with its sign, and stairs down.
static func _build_footbridge(node: Node3D, flat_from: float, flat_to: float, end: float) -> void:
    var rail := Color("4a6a8a")
    _railings(node, 0.0, flat_from, 0.0, HEIGHT, rail)
    _railings(node, flat_from, flat_to, HEIGHT, HEIGHT, rail)
    _railings(node, flat_to, end, HEIGHT, 0.0, rail)
    var z := (flat_from + flat_to) * 0.5
    Flat.box(
        node, Vector3(WIDTH - 0.6, 0.5, 0.06), Vector3(0, HEIGHT + 1.9, -flat_from), Color("2a5aa0")
    )
    _label(node, "PASSERELLE", Vector3(0, HEIGHT + 1.9, -flat_from + 0.05), 80, Color("ffffff"))
    for x in [-WIDTH * 0.5 + 0.1, WIDTH * 0.5 - 0.1]:
        Flat.post(node, 0.05, 1.5, Vector3(x, HEIGHT + 1.6, -flat_from), rail)
    Flat.box(
        node,
        Vector3(0.05, 0.5, 0.9),
        Vector3(WIDTH * 0.5 - 0.05, HEIGHT + 0.6, -z),
        Color("e8e0c0")
    )


## The scaffold of the new tower of Rochartis: ladders up its front, poles,
## its tarp with a banner, planks on its top, and the chute for the rubble
## down.
static func _build_scaffold(node: Node3D, _flat_from: float, flat_to: float, end: float) -> void:
    var half := WIDTH * 0.5
    var pole := Color("9aa0a8")
    _ladders(node, Color("e8c020"), Color("c8a010"))
    for x in [-half, -half * 0.33, half * 0.33, half]:
        for z in [0.05, flat_to]:
            Flat.post(node, 0.04, HEIGHT + 1.2, Vector3(x, (HEIGHT + 1.2) * 0.5, -z), pole)
    for y in [1.0, 2.0, HEIGHT + 1.1]:
        Flat.box(node, Vector3(WIDTH, 0.05, 0.05), Vector3(0, y, 0.05), pole)
        for x in [-half, half]:
            Flat.box(node, Vector3(0.05, 0.05, flat_to), Vector3(x, y, -flat_to * 0.5), pole)
    var z := 0.4
    while z < flat_to - 0.2:
        Flat.box(node, Vector3(WIDTH, 0.03, 0.04), Vector3(0, HEIGHT + 0.01, -z), Color("8a6a3a"))
        z += 0.8
    for x: float in [-half - 0.02, half + 0.02]:
        var tarp := _label(
            node, "ROCHARTIS TOWER", Vector3(x, 1.8, -flat_to * 0.5), 110, Color("ffffff")
        )
        tarp.rotation.y = PI * 0.5 * signf(x)
    var banner := _label(
        node, "COMING SOON: MORE PATENTS", Vector3(0, HEIGHT + 0.6, 0.12), 70, Color("ffe060")
    )
    banner.outline_size = 12
    for x in [-half + 0.05, half - 0.05]:
        _bar(node, Vector3(x, HEIGHT + 0.5, -flat_to), Vector3(x, 0.5, -end), 0.08, Color("c85010"))


## The garden shed: ladders up its wooden front, snow on its roof, a garden
## gnome, and a sledge run down.
static func _build_shed(node: Node3D, flat_from: float, flat_to: float, end: float) -> void:
    var half := WIDTH * 0.5
    _ladders(node, Color("6a4a2a"), Color("8a6a3a"))
    var x := -half + 0.3
    while x < half:
        Flat.box(
            node,
            Vector3(0.03, HEIGHT - 0.1, 0.03),
            Vector3(x, (HEIGHT - 0.1) * 0.5, 0.02),
            Color("5a3a1a")
        )
        x += 0.45
    Flat.box(node, Vector3(0.9, 0.7, 0.04), Vector3(-half + 0.9, 1.6, 0.03), Color("a8d0e8"))
    Flat.box(node, Vector3(WIDTH + 0.3, 0.2, 0.3), Vector3(0, HEIGHT + 0.08, 0.05), Color("f4f7fb"))
    _label(node, "PRIVAT", Vector3(half - 1.0, 1.4, 0.06), 90, Color("d02020"))
    var z := (flat_from + flat_to) * 0.5
    Flat.limb(node, 0.0, 0.14, 0.35, Vector3(half - 0.4, HEIGHT + 0.6, -z), Color("d02020"))
    Flat.ball(node, 0.12, Vector3(half - 0.4, HEIGHT + 0.36, -z), Color("f0c8a0"))
    Flat.limb(node, 0.12, 0.18, 0.3, Vector3(half - 0.4, HEIGHT + 0.15, -z), Color("2a5aa0"))
    for side in [-1.0, 1.0]:
        _bar(
            node,
            Vector3(side * 0.6, HEIGHT + 0.01, -flat_to),
            Vector3(side * 0.6, 0.01, -end),
            0.05,
            Color("a8c0dc")
        )


## The hill by the meadow: firs on its sides, the summit cross and a Swiss
## flag on its top, and a sledge run down.
static func _build_hill(node: Node3D, flat_from: float, flat_to: float, end: float) -> void:
    var half := WIDTH * 0.5
    var random := RandomNumberGenerator.new()
    random.seed = 5
    var skirt: float = LOOKS["hill"]["skirt"]
    for side: float in [-1.0, 1.0]:
        var z := 1.0
        while z < end - 0.5:
            var top := minf(HEIGHT, minf(z * 0.35, (end - z) * 0.5))
            var up := top * random.randf_range(0.2, 0.6)
            _fir(
                node,
                Vector3(side * (half + (top - up) * skirt), up, -z),
                random.randf_range(1.2, 1.8)
            )
            z += random.randf_range(1.5, 2.5)
    var z := (flat_from + flat_to) * 0.5
    var wood := Color("6a4a2a")
    Flat.box(node, Vector3(0.14, 2.6, 0.14), Vector3(-half + 0.5, HEIGHT + 1.3, -z), wood)
    Flat.box(node, Vector3(1.1, 0.14, 0.14), Vector3(-half + 0.5, HEIGHT + 1.9, -z), wood)
    Flat.post(node, 0.03, 2.0, Vector3(half - 0.5, HEIGHT + 1.0, -z), Color("8a8a8a"))
    Flat.box(
        node, Vector3(0.02, 0.6, 0.6), Vector3(half - 0.5, HEIGHT + 1.7, -z + 0.32), Color("d82020")
    )
    Flat.box(
        node,
        Vector3(0.03, 0.36, 0.1),
        Vector3(half - 0.5, HEIGHT + 1.7, -z + 0.32),
        Color("ffffff")
    )
    Flat.box(
        node,
        Vector3(0.03, 0.1, 0.36),
        Vector3(half - 0.5, HEIGHT + 1.7, -z + 0.32),
        Color("ffffff")
    )
    for side in [-1.0, 1.0]:
        _bar(
            node,
            Vector3(side * 0.6, HEIGHT + 0.01, -flat_to),
            Vector3(side * 0.6, 0.01, -end),
            0.05,
            Color("a8c0dc")
        )
