class_name Barriers
extends Node3D

## The barriers on the road of a run (see Run and DESIGN.md), as the car in the
## bonus stage of the old fighting games: a barrier spans the whole road, and
## there is no way around it, over it or under it. As the hero reaches it, the
## run stops (as for a fight), and he smashes it with his punches and kicks:
## every one knocks chunks off it, which fly away, until nothing is left.
##
## Where he hits it goes by the punch: a hook to its side (a left hook to the
## left of him), a jab or an uppercut straight ahead; a kick to its side, too.
## One part of it glows, a target, and the call on the screen says which
## punch hits it ("LEFT HOOK!", "JAB!", ...): a hit into the target counts
## twice, and the target moves on. The faster he smashes it, the more points
## (a clock counts down; after it, no bonus, but he must still smash it).
##
## Each land has its own, in the spirit of the songs: the palisade and the wall
## of those who were here first, the ice wall, the laundry-room roster and the
## Bünzli's car, the crates of patents and the gate of Rochartis, the Thuja
## hedge, and the poster of the herd.

## The barriers: their title (on the HUD, as an opponent's name).
const LOOKS := {
    "palisade": {"title": "THE PALISADE OF THE FIRST ONES"},
    "stone_wall": {"title": "THE WALL: WE WERE HERE FIRST"},
    "ice_wall": {"title": "THE ICE WALL"},
    "laundry": {"title": "THE LAUNDRY-ROOM ROSTER"},
    "car": {"title": "THE BÜNZLI'S CAR"},
    "crates": {"title": "THE CRATES OF PATENTS"},
    "gate": {"title": "THE GATE OF ROCHARTIS"},
    "hedge": {"title": "THE THUJA HEDGE"},
    "poster": {"title": "THE POSTER OF THE HERD"},
}

## How far in front of him he stops at a barrier, in meters.
const STAND := 1.5

## How wide a barrier is: the whole road and its edges.
const WIDTH := 5.4

## How much of its health a punch takes (of 100), how many times as much into
## the target, and how far across from him the middle of it reaches.
const HIT := 8.0
const TARGET := 2.0
const MIDDLE := 0.45

## How long he has for the bonus, in seconds, and its points a second left.
const LIMIT := 15.0
const BONUS := 50

## How long a target glows before it moves on, at random, in seconds.
const TARGET_HOLDS := Vector2(2.0, 3.0)

## How long a chunk flies before it is gone, in seconds.
const FLY_SECONDS := 2.0

## The parts of a barrier from him (see [method start]), and the share of its
## health which each has.
const ZONES := {"left": 0.3, "middle": 0.4, "right": 0.3}

## The calls of the targets: the text, and where the arrow comes from.
const CALLS := {
    "left": ["LEFT HOOK!", "left"],
    "middle": ["JAB!", "front"],
    "right": ["RIGHT HOOK!", "right"],
}

## The barriers on the road: "node", "look", "at" (the time of the notes at
## which he reaches it), "state" ("ahead", "smashing", "smashed") and
## "labels" (the texts on it, which the shaders do not bend; see place).
var _items: Array = []

## The barrier which he smashes now (-1 if none), the health of each of its
## parts and what they had, their chunks in the order they fly off, the
## target, and the clock of the smashing.
var _current := -1
var _health := {}
var _full := {}
var _chunks := {}
var _target := ""
var _target_until := 0.0
var _clock := 0.0
## The chunks which fly: [node, velocity, spin, age].
var _flying: Array = []
## How much the barrier shakes after a hit, in [0, 1].
var _shake := 0.0


## Take all the barriers off the road.
func clear() -> void:
    for item in _items:
        (item["node"] as Node).queue_free()
    _items.clear()
    _flying.clear()
    _current = -1


## Put a barrier of the [param look] (see LOOKS) on the road, which he reaches
## at the time of the notes [param at], in the colors of the [param theme]
## (see Scenery).
func add(look: String, at: float, theme: String) -> void:
    var node := Node3D.new()
    add_child(node)
    var chunks := Node3D.new()
    chunks.name = "Chunks"
    node.add_child(chunks)
    build(look, chunks, theme)
    var target := _target_mark()
    target.name = "Target"
    target.visible = false
    node.add_child(target)
    var labels: Array = node.find_children("*", "Label3D", true, false)
    for label: Label3D in labels:
        label.set_meta("x", label.position.x)
    node.visible = false
    _items.append({"node": node, "look": look, "at": at, "state": "ahead", "labels": labels})


## Place the barriers at the time of the notes [param t], from the player's
## [param spot], with the road bending by [param bend] (see Scenery.set_bend).
func place(t: float, speed: float, spot: Vector3, bend: float) -> void:
    for item in _items:
        var node: Node3D = item["node"]
        var ahead: float = (float(item["at"]) - t) * speed + STAND
        node.visible = ahead < Scenery.AHEAD and ahead > -Scenery.BEHIND
        node.position = spot + Vector3(0, 0, -ahead)
        # NOTE (mristin):
        # The texts do not bend with the shaders: move them as the road bends.
        var offset := bend * maxf(0.0, ahead) * maxf(0.0, ahead)
        for label: Label3D in item["labels"]:
            if is_instance_valid(label):
                label.position.x = float(label.get_meta("x")) + offset


## The index of the barrier which he reaches by the time of the notes
## [param t], or -1.
func reached(t: float) -> int:
    for i in range(_items.size()):
        if _items[i]["state"] == "ahead" and t >= float(_items[i]["at"]):
            return i
    return -1


## Start smashing the barrier of the [param index], as he stands at
## [param x] across the road: its parts are to his left, in front of him and
## to his right; the nearest chunks of each fly off first.
func start(index: int, x: float) -> void:
    _current = index
    var item: Dictionary = _items[index]
    item["state"] = "smashing"
    _clock = 0.0
    _shake = 0.0
    _chunks = {"left": [], "middle": [], "right": []}
    for chunk: Node3D in (item["node"] as Node3D).get_node("Chunks").get_children():
        var dx := chunk.position.x - x
        var zone := "middle"
        if dx < -MIDDLE:
            zone = "left"
        elif dx > MIDDLE:
            zone = "right"
        _chunks[zone].append(chunk)
    var shares := 0.0
    for zone in ZONES:
        if not _chunks[zone].is_empty():
            shares += ZONES[zone]
        # NOTE (mristin):
        # The nearest first, and of those the top first.
        (_chunks[zone] as Array).sort_custom(
            func(a: Node3D, b: Node3D) -> bool:
                var da := snappedf(absf(a.position.x - x), 0.3)
                var db := snappedf(absf(b.position.x - x), 0.3)
                if da != db:
                    return da < db
                return a.position.y > b.position.y
        )
    for zone in ZONES:
        var share: float = ZONES[zone] / shares if not _chunks[zone].is_empty() else 0.0
        _full[zone] = 100.0 * share
        _health[zone] = _full[zone]
    _target = ""
    _new_target()


## The look of the barrier which he smashes now ("" if none).
func look() -> String:
    return "" if _current < 0 else str(_items[_current]["look"])


## The health of the barrier which he smashes now, in [0, 100].
func health() -> float:
    var total := 0.0
    for zone in _health:
        total += _health[zone]
    return total


## How long he has left for the bonus, in seconds (negative after it).
func time_left() -> float:
    return LIMIT - _clock


## Whether he still smashes a barrier.
func smashing() -> bool:
    return _current >= 0


## The call of the target: its text, where its arrow comes from, and how it
## pulses (see RhythmLevel._call); empty if none.
func call_target() -> Array:
    if _current < 0 or _target == "":
        return []
    var call: Array = CALLS[_target]
    return [call[0], call[1], 0.5 + 0.5 * sin(_clock * 6.0)]


## Where he looks while he smashes it, in the world: the middle of it, before
## him.
func aim(x: float) -> Vector3:
    if _current < 0:
        return Vector3.ZERO
    var node: Node3D = _items[_current]["node"]
    return node.position + Vector3(x, -0.35, 0)


## He threw a punch ([param kind] "straight", "hook", "uppercut" or "kick";
## [param side] "left" or "right"), [param power] times as hard as a plain
## one: it knocks chunks off the part which it hits (see the class). Returns
## "target" (into the target), "hit", "smashed" (the last of it), or "" (no
## barrier).
func hit(kind: String, side: String, power: float) -> String:
    if _current < 0:
        return ""
    var zone := "middle"
    if kind == "hook" or kind == "kick":
        zone = side
    if float(_health[zone]) <= 0.0:
        # NOTE (mristin):
        # Nothing left there: the punch goes to what is left elsewhere.
        for other in _health:
            if float(_health[other]) > float(_health[zone]):
                zone = other
    var into_target := zone == _target
    var damage := HIT * power * (TARGET if into_target else 1.0)
    _health[zone] = maxf(0.0, float(_health[zone]) - damage)
    _shake = 1.0
    _knock_off(zone)
    if health() <= 0.0:
        _smash()
        return "smashed"
    if into_target or float(_health[_target]) <= 0.0:
        _new_target()
    return "target" if into_target else "hit"


## Play the barriers on by [param delta] seconds: the chunks fly, the one he
## smashes shakes, and its target glows and moves on now and then.
func step(delta: float) -> void:
    for flying in _flying.duplicate():
        var chunk: Node3D = flying[0]
        flying[3] += delta
        if flying[3] >= FLY_SECONDS or not is_instance_valid(chunk):
            _flying.erase(flying)
            if is_instance_valid(chunk):
                chunk.queue_free()
            continue
        flying[1] += Vector3.DOWN * 9.8 * delta
        chunk.position += flying[1] * delta
        chunk.rotation += flying[2] * delta
    if _current < 0:
        return
    _clock += delta
    _shake = maxf(0.0, _shake - delta * 5.0)
    var node: Node3D = _items[_current]["node"]
    var chunks: Node3D = node.get_node("Chunks")
    chunks.position = (
        Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * _shake * 0.06
    )
    if _clock >= _target_until:
        _new_target()
    var target: Node3D = node.get_node("Target")
    var next := _next_chunk(_target)
    target.visible = next != null
    if next != null:
        var at := Vector3(next.position.x, clampf(next.position.y, 0.7, 1.5), 0.25)
        target.position = target.position.lerp(at, minf(1.0, delta * 12.0))
        target.scale = Vector3.ONE * (1.0 + 0.15 * sin(_clock * 10.0))
        target.rotation.z = _clock * 1.5


## Move the target to another part which is left (not the same, if there is
## another).
func _new_target() -> void:
    var choices: Array = []
    for zone in _health:
        if float(_health[zone]) > 0.0 and zone != _target:
            choices.append(zone)
    if choices.is_empty() and float(_health.get(_target, 0.0)) <= 0.0:
        _target = ""
        return
    if not choices.is_empty():
        _target = choices.pick_random()
    _target_until = _clock + randf_range(TARGET_HOLDS.x, TARGET_HOLDS.y)


## The next chunk of the part to fly off, or null.
func _next_chunk(zone: String) -> Node3D:
    for chunk: Node3D in _chunks.get(zone, []):
        if is_instance_valid(chunk) and not chunk.has_meta("flying"):
            return chunk
    return null


## Knock off the chunks of the part as its health goes: as many of them as it
## lost of its health, and at least one.
func _knock_off(zone: String) -> void:
    var chunks: Array = _chunks[zone]
    var gone := chunks.size()
    if float(_health[zone]) > 0.0:
        var lost := 1.0 - float(_health[zone]) / maxf(1.0, float(_full[zone]))
        gone = clampi(ceili(chunks.size() * lost), 1, chunks.size() - 1)
    var flown := 0
    for chunk: Node3D in chunks:
        if chunk.has_meta("flying"):
            flown += 1
    var more := maxi(1 if float(_health[zone]) > 0.0 else 0, gone - flown)
    for chunk: Node3D in chunks:
        if more <= 0:
            break
        if not chunk.has_meta("flying"):
            _fly(chunk, 1.0)
            more -= 1


## The barrier is smashed: all that is left of it flies apart.
func _smash() -> void:
    for zone in _chunks:
        for chunk: Node3D in _chunks[zone]:
            if is_instance_valid(chunk) and not chunk.has_meta("flying"):
                _fly(chunk, 1.4)
    var node: Node3D = _items[_current]["node"]
    node.get_node("Target").visible = false
    _items[_current]["state"] = "smashed"
    _current = -1
    _target = ""


## Send the chunk flying away from him, up and spinning; [param force] the
## harder.
func _fly(chunk: Node3D, force: float) -> void:
    chunk.set_meta("flying", true)
    var side := signf(chunk.position.x + randf_range(-0.2, 0.2))
    var velocity := Vector3(
        side * randf_range(0.5, 2.0), randf_range(2.5, 4.5), -randf_range(1.5, 4.0)
    )
    var spin := Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
    _flying.append([chunk, velocity * force, spin, 0.0])


## The target which glows on the part to hit: a ring of gold beads around a
## star.
static func _target_mark() -> Node3D:
    var mark := Node3D.new()
    for k in range(12):
        var angle := k * TAU / 12.0
        Flat.ball(mark, 0.035, Vector3(cos(angle), sin(angle), 0) * 0.24, Color("f2c14e"))
    for k in range(4):
        var ray := Flat.box(mark, Vector3(0.3, 0.05, 0.02), Vector3.ZERO, Color("fff2b0"))
        ray.rotation.z = k * PI * 0.25
    return mark


## A chunk of a barrier at [param at] (its middle), which flies off as one.
static func _chunk(chunks: Node3D, at: Vector3) -> Node3D:
    var chunk := Node3D.new()
    chunk.position = at
    chunks.add_child(chunk)
    return chunk


## A text on a barrier, facing him.
static func _label(parent: Node3D, text: String, at: Vector3, size: int, color: Color) -> Label3D:
    var label := Label3D.new()
    label.text = text
    label.font_size = size
    label.outline_size = 8
    label.outline_modulate = Color("1a1a1a")
    label.pixel_size = 0.004
    label.modulate = color
    label.position = at
    parent.add_child(label)
    return label


## Build the barrier of the [param look] into [param chunks], in the colors of
## the [param theme]: across the road, its front at z = 0, out of chunks of
## about half a meter (see _chunk).
static func build(look: String, chunks: Node3D, theme: String) -> void:
    var random := RandomNumberGenerator.new()
    random.seed = hash(look)
    match look:
        "palisade":
            _build_palisade(chunks, random, theme)
        "stone_wall":
            _build_stone_wall(chunks, random)
        "ice_wall":
            _build_ice_wall(chunks, random)
        "laundry":
            _build_laundry(chunks)
        "car":
            _build_car(chunks, theme)
        "crates":
            _build_crates(chunks, random)
        "gate":
            _build_gate(chunks)
        "hedge":
            _build_hedge(chunks, random)
        "poster":
            _build_poster(chunks)


## A palisade of sharpened logs, bound with a mammoth's tusks, a hide hung on
## it: "WE WERE HERE FIRST" (on the glacier, the logs are frosted).
static func _build_palisade(chunks: Node3D, random: RandomNumberGenerator, theme: String) -> void:
    var wood := Color("7a4a22") if theme != "ice" else Color("8a7a6a")
    var x := -WIDTH * 0.5 + 0.17
    while x < WIDTH * 0.5:
        var height := random.randf_range(1.6, 1.9)
        var chunk := _chunk(chunks, Vector3(x, height * 0.5, -0.15))
        Flat.limb(
            chunk,
            0.15,
            0.16,
            height - 0.25,
            Vector3(0, -0.12, 0),
            wood.darkened(random.randf_range(0, 0.25))
        )
        Flat.limb(chunk, 0.0, 0.15, 0.25, Vector3(0, height * 0.5 - 0.12, 0), Color("c8a070"))
        if theme == "ice":
            Flat.limb(chunk, 0.05, 0.16, 0.08, Vector3(0, height * 0.5 - 0.3, 0), Color("eef6fc"))
        x += 0.34
    # NOTE (mristin):
    # The tusks across, in pieces of a meter.
    for row in [0.55, 1.25]:
        var at := -WIDTH * 0.5 + 0.5
        while at < WIDTH * 0.5:
            var chunk := _chunk(chunks, Vector3(at, row, 0.05))
            var tusk := Flat.limb(chunk, 0.05, 0.07, 1.0, Vector3.ZERO, Color("f2ead8"))
            tusk.rotation.z = PI * 0.5 + random.randf_range(-0.08, 0.08)
            at += 1.0
    var hide := _chunk(chunks, Vector3(0, 0.95, 0.12))
    var pelt := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.3, 0.75, 0.04)
    pelt.mesh = box
    pelt.material_override = Flat.striped(Color("c88a3a"), Color("3a2a1a"), 18.0)
    hide.add_child(pelt)
    for k in range(3):
        Flat.box(
            hide, Vector3(0.1, 0.12, 0.02), Vector3(-0.45 + k * 0.45, -0.25, 0.03), Color("a8281e")
        )
    _label(hide, "WE WERE\nHERE FIRST!", Vector3(0, 0.05, 0.03), 72, Color("f6e8c8"))


## A wall of boulders, piled in rows, a slab in it painted as a cave wall:
## "OURS!"
static func _build_stone_wall(chunks: Node3D, random: RandomNumberGenerator) -> void:
    var rows := [0.3, 0.8, 1.3]
    for r in range(rows.size()):
        var x := -WIDTH * 0.5 + 0.3 + (r % 2) * 0.3
        while x < WIDTH * 0.5:
            if r >= 1 and absf(x) < 0.7:
                x += 0.6
                continue
            var chunk := _chunk(chunks, Vector3(x, rows[r], -0.3))
            var stone := Flat.ball(
                chunk,
                random.randf_range(0.3, 0.36),
                Vector3.ZERO,
                Color("7a6a5a").lightened(random.randf_range(-0.15, 0.15)),
                false,
                0.8
            )
            stone.rotation = Vector3(random.randf(), random.randf(), random.randf())
            x += 0.6
    var slab := _chunk(chunks, Vector3(0, 1.05, -0.2))
    Flat.box(slab, Vector3(1.3, 0.95, 0.3), Vector3.ZERO, Color("b8a080"))
    for k in range(4):
        var hand := Vector3(-0.45 + k * 0.3, -0.25 + (k % 2) * 0.1, 0.16)
        Flat.ball(slab, 0.06, hand, Color("a8281e"), false, 0.4)
    _label(slab, "OURS!", Vector3(0, 0.12, 0.16), 120, Color("a8281e"))


## A wall of ice blocks, with icicles, and a sign scratched in it: "MAMMOTHS
## ONLY".
static func _build_ice_wall(chunks: Node3D, random: RandomNumberGenerator) -> void:
    var colors := [Color("dff0fb"), Color("b8dcf2"), Color("9ccbea")]
    for row in range(4):
        var x := -WIDTH * 0.5 + 0.35 + (row % 2) * 0.35
        while x < WIDTH * 0.5:
            var chunk := _chunk(chunks, Vector3(x, 0.22 + row * 0.42, -0.25))
            Flat.box(chunk, Vector3(0.66, 0.4, 0.5), Vector3.ZERO, colors[random.randi() % 3])
            if row == 3:
                for k in range(2):
                    var icicle := Flat.limb(
                        chunk,
                        0.05,
                        0.0,
                        0.22,
                        Vector3(-0.15 + k * 0.3, -0.31, 0.24),
                        Color("eef6fc")
                    )
                    icicle.rotation.y = 0.3
            x += 0.7
    var sign := _chunk(chunks, Vector3(0, 1.1, 0.03))
    Flat.box(sign, Vector3(1.4, 0.5, 0.04), Vector3.ZERO, Color("4a8ac0"))
    _label(sign, "MAMMOTHS ONLY", Vector3(0, 0, 0.03), 72, Color("eef6fc"))


## The washing machines of the laundry room, two high across the road, and the
## roster over them: "WASCHPLAN: NOT YOUR DAY!"
static func _build_laundry(chunks: Node3D) -> void:
    var x := -WIDTH * 0.5 + 0.32
    while x < WIDTH * 0.5:
        for row in range(2):
            var chunk := _chunk(chunks, Vector3(x, 0.43 + row * 0.86, -0.3))
            Flat.box(chunk, Vector3(0.62, 0.84, 0.6), Vector3.ZERO, Color("f4f4f0"))
            var door := Flat.limb(chunk, 0.2, 0.2, 0.04, Vector3(0, -0.04, 0.3), Color("8a9aa8"))
            door.rotation.x = PI * 0.5
            var glass := Flat.limb(
                chunk, 0.14, 0.14, 0.05, Vector3(0, -0.04, 0.31), Color("3a5a7a")
            )
            glass.rotation.x = PI * 0.5
            Flat.box(chunk, Vector3(0.5, 0.08, 0.02), Vector3(0, 0.33, 0.3), Color("c8c8c0"))
            Flat.ball(chunk, 0.03, Vector3(0.2, 0.33, 0.32), Color("c8302c"))
        x += 0.64
    var roster := _chunk(chunks, Vector3(0, 2.0, -0.05))
    Flat.box(roster, Vector3(1.8, 0.62, 0.04), Vector3.ZERO, Color("fffdf0"))
    for row in range(3):
        for col in range(7):
            var filled := (row * 7 + col) % 3 != 1
            Flat.box(
                roster,
                Vector3(0.2, 0.1, 0.01),
                Vector3(-0.72 + col * 0.24, -0.05 - row * 0.12, 0.025),
                Color("c8302c") if filled else Color("6ccf5e")
            )
    _label(roster, "WASCHPLAN", Vector3(0, 0.2, 0.03), 64, Color("1a1a1a"))
    var note := _chunk(chunks, Vector3(0.75, 1.55, 0.03))
    var paper := Flat.box(note, Vector3(0.5, 0.3, 0.01), Vector3.ZERO, Color("f8e070"))
    paper.rotation.z = -0.12
    var text := _label(note, "NOT YOUR\nDAY!", Vector3(0, 0, 0.01), 40, Color("c8302c"))
    text.rotation.z = -0.12


## The Bünzli's car, parked across the road, waxed, a garden gnome on its
## roof: its body, its windows and its wheels in chunks.
static func _build_car(chunks: Node3D, theme: String) -> void:
    var paint := Color("c8b890") if theme != "suburbs" else Color("a8b8c8")
    var length := 4.4
    var pieces := 8
    var piece := length / pieces
    for k in range(pieces):
        var x := -length * 0.5 + piece * (k + 0.5)
        var low := _chunk(chunks, Vector3(x, 0.55, -0.9))
        Flat.box(low, Vector3(piece, 0.6, 1.8), Vector3.ZERO, paint)
        Flat.box(low, Vector3(piece, 0.05, 0.02), Vector3(0, 0.1, 0.91), Color("e8e8e8"))
        if k == 0 or k == pieces - 1:
            var end := signf(x) * (piece * 0.5 + 0.01)
            Flat.box(low, Vector3(0.04, 0.12, 0.3), Vector3(end, 0.15, 0.7), Color("f8f0a0"))
        if k >= 1 and k <= pieces - 2:
            var top := _chunk(chunks, Vector3(x, 1.1, -0.9))
            Flat.box(top, Vector3(piece, 0.5, 1.5), Vector3.ZERO, paint)
            var window := Color("3a5a7a") if k != pieces / 2 else Color("4a6a8a")
            Flat.box(top, Vector3(piece - 0.06, 0.36, 0.02), Vector3(0, 0.02, 0.76), window)
    for x in [-1.45, 1.45]:
        var wheel := _chunk(chunks, Vector3(x, 0.34, -0.05))
        var tire := Flat.limb(wheel, 0.34, 0.34, 0.22, Vector3.ZERO, Color("1a1a1a"))
        tire.rotation.x = PI * 0.5
        var rim := Flat.limb(wheel, 0.18, 0.18, 0.24, Vector3.ZERO, Color("c8c8c8"))
        rim.rotation.x = PI * 0.5
    var sticker := _chunk(chunks, Vector3(0.3, 0.62, 0.02))
    Flat.box(sticker, Vector3(0.9, 0.22, 0.01), Vector3.ZERO, Color("ffffff"))
    _label(sticker, "ORDNUNG MUSS SEIN", Vector3(0, 0, 0.01), 30, Color("c8302c"))
    var gnome := _chunk(chunks, Vector3(-0.6, 1.55, -0.8))
    Flat.limb(gnome, 0.1, 0.13, 0.25, Vector3.ZERO, Color("3060c0"))
    Flat.ball(gnome, 0.09, Vector3(0, 0.2, 0), Color("f0c8a0"))
    Flat.ball(gnome, 0.08, Vector3(0, 0.13, 0.04), Color("ffffff"))
    Flat.limb(gnome, 0.0, 0.1, 0.25, Vector3(0, 0.38, 0), Color("c8302c"))


## Crates of the patents of Rochartis, stacked three high, pills spilling
## out on top: "PATENTED".
static func _build_crates(chunks: Node3D, random: RandomNumberGenerator) -> void:
    for row in range(3):
        var x := -WIDTH * 0.5 + 0.35 + (row % 2) * 0.2
        while x < WIDTH * 0.5:
            var chunk := _chunk(chunks, Vector3(x, 0.32 + row * 0.62, -0.3))
            Flat.box(chunk, Vector3(0.62, 0.6, 0.6), Vector3.ZERO, Color("f4f4f4"))
            Flat.box(chunk, Vector3(0.62, 0.1, 0.02), Vector3(0, 0.15, 0.3), Color("d0202a"))
            Flat.box(chunk, Vector3(0.12, 0.12, 0.02), Vector3(-0.2, -0.1, 0.3), Color("d0202a"))
            if row == 2:
                for k in range(3):
                    var pill := Vector3(
                        random.randf_range(-0.2, 0.2), 0.33, random.randf_range(-0.2, 0.2)
                    )
                    var capsule := Flat.ball(chunk, 0.05, pill, Color("f2c14e"), false, 1.6)
                    capsule.rotation.z = PI * 0.5
            x += 0.68
    var sign := _chunk(chunks, Vector3(0, 0.95, 0.03))
    Flat.box(sign, Vector3(1.2, 0.3, 0.03), Vector3.ZERO, Color("d0202a"))
    _label(sign, "PATENTED", Vector3(0, 0, 0.02), 72, Color("ffffff"))


## The gate of Rochartis: panes of glass in a steel frame, a turnstile in the
## middle, and a sign over it: "AUTHORIZED PERSONNEL ONLY".
static func _build_gate(chunks: Node3D) -> void:
    var steel := Color("8a9098")
    var x := -WIDTH * 0.5 + 0.3
    while x < WIDTH * 0.5:
        if absf(x) < 0.5:
            x += 0.6
            continue
        for row in range(2):
            var chunk := _chunk(chunks, Vector3(x, 0.5 + row * 0.95, -0.1))
            Flat.box(chunk, Vector3(0.58, 0.9, 0.04), Vector3.ZERO, Color("a8d8e8"))
            Flat.box(chunk, Vector3(0.6, 0.05, 0.08), Vector3(0, 0.45, 0), steel)
            Flat.box(chunk, Vector3(0.05, 0.92, 0.08), Vector3(0.3, 0, 0), steel)
            Flat.box(chunk, Vector3(0.12, 0.3, 0.01), Vector3(-0.15, 0.2, 0.03), Color("e4f4fa"))
        x += 0.6
    for row in range(3):
        var turn := _chunk(chunks, Vector3(0, 0.55 + row * 0.4, -0.05))
        Flat.box(turn, Vector3(0.9, 0.07, 0.07), Vector3.ZERO, Color("d0d4da"))
        Flat.post(turn, 0.07, 0.3, Vector3(0, 0, -0.1), steel)
    var reader := _chunk(chunks, Vector3(0.62, 1.05, 0.05))
    Flat.box(reader, Vector3(0.14, 0.22, 0.08), Vector3.ZERO, Color("2a2a2a"))
    Flat.box(reader, Vector3(0.06, 0.06, 0.01), Vector3(0, 0.05, 0.045), Color("d0202a"))
    var sign := _chunk(chunks, Vector3(0, 2.15, -0.05))
    Flat.box(sign, Vector3(2.6, 0.32, 0.05), Vector3.ZERO, Color("d0202a"))
    _label(sign, "AUTHORIZED PERSONNEL ONLY", Vector3(0, 0, 0.03), 56, Color("ffffff"))


## A Thuja hedge, trimmed to the millimeter, snow on top, garden gnomes on
## guard and a sign: "PRIVAT".
static func _build_hedge(chunks: Node3D, random: RandomNumberGenerator) -> void:
    var x := -WIDTH * 0.5 + 0.27
    while x < WIDTH * 0.5:
        for row in range(2):
            var chunk := _chunk(chunks, Vector3(x, 0.42 + row * 0.84, -0.3))
            Flat.box(
                chunk,
                Vector3(0.54, 0.84, 0.6),
                Vector3.ZERO,
                Color("2f6a32").darkened(random.randf_range(0, 0.15))
            )
            for k in range(3):
                var leaf := Vector3(
                    random.randf_range(-0.2, 0.2), random.randf_range(-0.3, 0.3), 0.3
                )
                Flat.box(chunk, Vector3(0.12, 0.08, 0.02), leaf, Color("4a8a3a"))
            if row == 1:
                Flat.box(chunk, Vector3(0.56, 0.08, 0.62), Vector3(0, 0.44, 0), Color("f4f7fb"))
        x += 0.54
    for gx in [-1.2, 1.4]:
        var gnome := _chunk(chunks, Vector3(gx, 1.97, -0.2))
        Flat.limb(gnome, 0.08, 0.1, 0.2, Vector3.ZERO, Color("3060c0"))
        Flat.ball(gnome, 0.07, Vector3(0, 0.16, 0), Color("f0c8a0"))
        Flat.ball(gnome, 0.06, Vector3(0, 0.1, 0.04), Color("ffffff"))
        Flat.limb(gnome, 0.0, 0.08, 0.2, Vector3(0, 0.3, 0), Color("c8302c"))
    var sign := _chunk(chunks, Vector3(0.2, 1.0, 0.05))
    Flat.box(sign, Vector3(0.8, 0.3, 0.03), Vector3.ZERO, Color("ffffff"))
    _label(sign, "PRIVAT", Vector3(0, 0, 0.02), 80, Color("c8302c"))


## The poster of the herd on its stand: white sheep in a row under a blue sky,
## smug, "WE STAY AMONG OURSELVES" (the black sheep cheers on as he smashes
## it, see Run).
static func _build_poster(chunks: Node3D) -> void:
    var columns := 8
    var piece := WIDTH / columns
    for col in range(columns):
        var x := -WIDTH * 0.5 + piece * (col + 0.5)
        for row in range(3):
            var chunk := _chunk(chunks, Vector3(x, 0.55 + row * 0.6, -0.1))
            var color := Color("4a8ac8") if row > 0 else Color("6ab04a")
            Flat.box(chunk, Vector3(piece - 0.01, 0.59, 0.06), Vector3.ZERO, color)
            if row == 1:
                # NOTE (mristin):
                # A white sheep on each piece, smug.
                Flat.ball(chunk, 0.2, Vector3(0, -0.1, 0.06), Color("f6f6f2"), false, 0.7)
                Flat.ball(chunk, 0.08, Vector3(0.18, -0.02, 0.08), Color("1a1a1a"))
                Flat.ball(chunk, 0.02, Vector3(0.2, 0.0, 0.14), Color("ffffff"))
        var leg := _chunk(chunks, Vector3(x, 0.12, -0.18))
        Flat.post(leg, 0.04, 0.25, Vector3.ZERO, Color("6a6a6a"))
    var line := _chunk(chunks, Vector3(0, 1.75, 0.0))
    _label(line, "WE STAY AMONG OURSELVES", Vector3(0, 0, 0.0), 72, Color("ffffff"))
