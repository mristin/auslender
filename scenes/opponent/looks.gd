class_name Looks
extends RefCounted

## The looks of the opponents (see Opponent), built of flat-shaded boxes, tapered
## limbs and low-poly balls, as in 4D Sports Boxing.
##
## Every opponent stands on the same rig, so that all box alike (the animals,
## too, upright as boxers): the hips and the knees, the torso, the head, the
## shoulders and the elbows, each a pivot which the Opponent turns. A look
## dresses the rig: its body, its head, its gloves (or paws) and its props.
## Their front is -Z, as in Godot.
##
## They are caricatures of types (see DESIGN.md), never of real people:
##
## - the mammoth, the sabre-tooth tiger and the cave bear of the Ice Age;
## - the Bünzlis of many kinds (see [method _bunzli]), the nationalist
##   (edelweiss shirt, a cowbell and a cape of the flag), the Rochartis
##   scientist (lab coat, goggles) and the Rochartis CEO (suit, golden tie);
## - the Nörgeli (a grumpy old man in a woolly hat, the boss of the winter),
##   and the white sheep (a smug woolly ball; the black sheep cheers the
##   player on from the ringside, see [method black_sheep]).

const SKIN := Color("e0b48e")
const DARK := Color("1b1b1e")
const WHITE := Color("f1f0ea")

## The ids of the looks.
const IDS := [
    "scientist",
    "mammoth",
    "sabre_tiger",
    "cave_bear",
    "bunzli",
    "bunzli_shovel",
    "bunzli_hedge",
    "nationalist",
    "ceo",
    "norgeli",
    "white_sheep",
]


## Dress the rig of the look under [param body]; return its pivots: "torso",
## "head", "legs" and "knees" (left, right), "arms" (the shoulders) and
## "elbows", and "flashing" (the materials which flash when he is hit).
static func build(body: Node3D, look: String) -> Dictionary:
    var parts := {"legs": [], "knees": [], "arms": [], "elbows": [], "flashing": []}
    match look:
        "mammoth":
            _mammoth(body, parts)
        "sabre_tiger":
            _sabre_tiger(body, parts)
        "cave_bear":
            _cave_bear(body, parts)
        "bunzli", "bunzli_shovel", "bunzli_hedge":
            _bunzli(body, parts, look)
        "nationalist":
            _nationalist(body, parts)
        "ceo":
            _ceo(body, parts)
        "norgeli":
            _norgeli(body, parts)
        "white_sheep":
            _white_sheep(body, parts)
        _:
            _scientist(body, parts)
    return parts


## Dress the look built under [param body] (see [method build]) in random
## colors of the [param seed], so that the minor opponents whom the hero
## meets on the road look each his own: the colors of the clothes, the fur
## and the props shift their hue all together (a purple tiger, a green
## Bünzli), each a little brighter or darker; the skin, the blacks and the
## whites stay. The parts which flash (see [member parts]) keep their
## materials, recolored in place.
static func recolor(body: Node3D, parts: Dictionary, seed: int) -> void:
    var random := RandomNumberGenerator.new()
    random.seed = seed
    var hue := random.randf_range(0.12, 0.88)
    var done := {}
    for node in body.find_children("*", "MeshInstance3D", true, false):
        var instance := node as MeshInstance3D
        var material := instance.material_override as ShaderMaterial
        if material == null:
            continue
        var albedo: Variant = material.get_shader_parameter("albedo")
        if not albedo is Color or _keeps(albedo):
            continue
        var color: Color = albedo
        if not parts["flashing"].has(material):
            # NOTE (mristin):
            # The plain materials are shared by every mesh of the color (see
            # Flat.material): a copy of its own, so that only he changes.
            if not done.has(material):
                done[material] = material.duplicate()
            material = done[material]
            instance.material_override = material
        elif done.has(material):
            continue
        else:
            done[material] = material
        var shifted := Color.from_hsv(
            fposmod(color.h + hue, 1.0),
            clampf(color.s * random.randf_range(0.9, 1.25), 0.0, 1.0),
            clampf(color.v * random.randf_range(0.85, 1.15), 0.05, 1.0)
        )
        material.set_shader_parameter("albedo", shifted)
        var stripe: Variant = material.get_shader_parameter("stripe_color")
        if stripe is Color and not _keeps(stripe):
            var c: Color = stripe
            material.set_shader_parameter(
                "stripe_color", Color.from_hsv(fposmod(c.h + hue, 1.0), c.s, c.v)
            )


## Whether a color stays as it is when he is recolored: the skin, and the
## colors without much color (blacks, whites, greys).
static func _keeps(color: Color) -> bool:
    if color.s < 0.18 or color.v < 0.15:
        return true
    var skin := Color("e0b48e")
    return absf(color.h - skin.h) < 0.04 and absf(color.s - skin.s) < 0.15


## The black sheep, who cheers the player on (bouncing, see Fight): a small
## woolly ball with a black face and black legs.
static func black_sheep() -> Node3D:
    var sheep := Node3D.new()
    var wool := Color("2b2b30")
    Flat.ball(sheep, 0.3, Vector3(0, 0.55, 0), wool, false, 0.9, 12, 8)
    for x in [-0.12, 0.12]:
        Flat.limb(sheep, 0.04, 0.035, 0.32, Vector3(x, 0.16, 0), DARK)
    var head := Flat.ball(sheep, 0.13, Vector3(0, 0.82, -0.22), Color("141416"), false, 1.2)
    head.rotation.x = -0.4
    for x in [-0.045, 0.045]:
        Flat.ball(sheep, 0.022, Vector3(x, 0.86, -0.33), WHITE)
    for x in [-0.14, 0.14]:
        var ear := Flat.box(sheep, Vector3(0.12, 0.04, 0.06), Vector3(x, 0.86, -0.18), DARK)
        ear.rotation.z = 0.4 if x > 0 else -0.4
    # NOTE (mristin):
    # A little flag of support: "GO!" on a stick.
    Flat.limb(sheep, 0.01, 0.01, 0.5, Vector3(0.3, 0.9, 0), Color("8a6a3a"))
    var flag := Label3D.new()
    flag.text = "GO!"
    flag.font_size = 64
    flag.outline_size = 12
    flag.pixel_size = 0.004
    flag.modulate = Color("6ccf5e")
    flag.position = Vector3(0.3, 1.25, 0)
    flag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sheep.add_child(flag)
    return sheep


static func _pivot(parent: Node3D, at: Vector3) -> Node3D:
    var pivot := Node3D.new()
    pivot.position = at
    parent.add_child(pivot)
    return pivot


## A part which flashes when he is hit (see Opponent).
static func _flash(parts: Dictionary, instance: MeshInstance3D) -> MeshInstance3D:
    parts["flashing"].append(instance.material_override)
    return instance


## The legs: thighs, knees, shins and feet.
static func _legs(
    body: Node3D, parts: Dictionary, color: Color, foot: Color, thick := 1.0, apart := 0.12
) -> void:
    for i in range(2):
        var x := -apart if i == 0 else apart
        var hip := _pivot(body, Vector3(x, 0.92, 0))
        Flat.limb(hip, 0.085 * thick, 0.065 * thick, 0.46, Vector3(0, -0.22, 0), color)
        var knee := _pivot(hip, Vector3(0, -0.46, 0))
        Flat.ball(knee, 0.066 * thick, Vector3.ZERO, color)
        Flat.limb(knee, 0.064 * thick, 0.05 * thick, 0.42, Vector3(0, -0.21, 0), color)
        Flat.box(knee, Vector3(0.13 * thick, 0.08, 0.27), Vector3(0, -0.42, -0.05), foot)
        parts["legs"].append(hip)
        parts["knees"].append(knee)


## The torso pivot (at the hips' height).
static func _torso(body: Node3D, parts: Dictionary) -> Node3D:
    var torso := _pivot(body, Vector3(0, 0.95, 0))
    parts["torso"] = torso
    return torso


## A chest: wide at the shoulders, flattened; the main part which flashes.
static func _chest(
    torso: Node3D, parts: Dictionary, color: Color, wide := 1.0, deep := 0.55
) -> MeshInstance3D:
    var chest := Flat.limb(torso, 0.3 * wide, 0.23 * wide, 0.62, Vector3(0, 0.33, 0), color, true)
    chest.scale = Vector3(1, 1, deep)
    return _flash(parts, chest)


## The arms: the upper arm, the elbow, the forearm and the glove (or paw).
static func _arms(
    torso: Node3D,
    parts: Dictionary,
    color: Color,
    glove: Color,
    glove_radius := 0.085,
    wide := 1.0,
    thick := 1.0
) -> void:
    for i in range(2):
        var x := (-0.31 if i == 0 else 0.31) * wide
        var shoulder := _pivot(torso, Vector3(x, 0.58, 0))
        _flash(parts, Flat.ball(shoulder, 0.075 * thick, Vector3.ZERO, color, true))
        _flash(
            parts,
            Flat.limb(
                shoulder, 0.068 * thick, 0.055 * thick, 0.3, Vector3(0, -0.15, 0), color, true
            )
        )
        var elbow := _pivot(shoulder, Vector3(0, -0.3, 0))
        Flat.ball(elbow, 0.055 * thick, Vector3.ZERO, color)
        Flat.limb(elbow, 0.053 * thick, 0.042 * thick, 0.26, Vector3(0, -0.13, 0), color)
        Flat.ball(elbow, glove_radius, Vector3(0, -0.3, 0), glove)
        parts["arms"].append(shoulder)
        parts["elbows"].append(elbow)


## The head pivot on the neck, and the head ball (which flashes).
static func _head(
    torso: Node3D, parts: Dictionary, color: Color, radius := 0.13, stretch := 1.2
) -> Node3D:
    Flat.limb(torso, 0.055, 0.065, 0.1, Vector3(0, 0.68, 0), color)
    var head := _pivot(torso, Vector3(0, 0.7, 0))
    parts["head"] = head
    _flash(parts, Flat.ball(head, radius, Vector3(0, 0.14, 0), color, true, stretch))
    return head


## Give every part of the color stripes of the other color (a texture; see
## Flat.striped), each part its own material, which flashes if it did.
static func _stripe(
    body: Node3D, parts: Dictionary, fur: Color, stripe: Color, frequency: float
) -> void:
    for node in body.find_children("*", "MeshInstance3D", true, false):
        var instance := node as MeshInstance3D
        var old := instance.material_override as ShaderMaterial
        if old == null or old.get_shader_parameter("albedo") != fur:
            continue
        var striped := Flat.striped(fur, stripe, frequency)
        instance.material_override = striped
        var index: int = parts["flashing"].find(old)
        if index >= 0:
            parts["flashing"][index] = striped


## Angry brows over the eyes.
static func _brows(head: Node3D, y: float, z: float, color := DARK) -> void:
    for x in [-0.05, 0.05]:
        var brow := Flat.box(head, Vector3(0.08, 0.02, 0.02), Vector3(x, y, z), color)
        brow.rotation.z = 0.35 if x > 0 else -0.35


## Eyes: two small balls.
static func _eyes(head: Node3D, y: float, z: float, apart := 0.05, color := DARK) -> void:
    for x in [-apart, apart]:
        Flat.ball(head, 0.018, Vector3(x, y, z), color)


## A label on the chest (e.g., a badge).
static func _label(
    parent: Node3D, text: String, at: Vector3, color := Color.WHITE, size := 18
) -> void:
    var label := Label3D.new()
    label.text = text
    label.font_size = size
    label.pixel_size = 0.0012
    label.modulate = color
    label.position = at
    label.rotation.y = PI
    parent.add_child(label)


static func _scientist(body: Node3D, parts: Dictionary) -> void:
    var coat := Color("f1f0ea")
    var shade := Color("cfcfc7")
    _legs(body, parts, Color("3a3f4a"), DARK)
    var torso := _torso(body, parts)
    # NOTE (mristin):
    # The lab coat: the skirt down to the knees, the chest, the lapels.
    var skirt := _flash(parts, Flat.limb(torso, 0.24, 0.29, 0.45, Vector3(0, -0.18, 0), coat, true))
    skirt.scale = Vector3(1, 1, 0.6)
    _chest(torso, parts, coat)
    Flat.box(torso, Vector3(0.16, 0.36, 0.01), Vector3(0, 0.44, -0.152), Color("8fb1d6"))
    Flat.box(torso, Vector3(0.05, 0.3, 0.01), Vector3(0, 0.42, -0.158), Color("b3262a"))
    for x in [-0.1, 0.1]:
        Flat.box(torso, Vector3(0.02, 0.5, 0.01), Vector3(x, 0.36, -0.155), shade)
    Flat.box(torso, Vector3(0.12, 0.05, 0.01), Vector3(0.17, 0.5, -0.155), Color("1f8f8a"))
    _label(torso, "ROCHARTIS", Vector3(0.17, 0.5, -0.162))
    var head := _head(torso, parts, SKIN)
    # NOTE (mristin):
    # The grey fringe around the back of his bald head, the goatee, the
    # goggles, the evil brows, the nose and the grin.
    var hair := Color("b9b9b9")
    Flat.limb(head, 0.15, 0.14, 0.1, Vector3(0, 0.11, 0.045), hair, false, 10)
    Flat.limb(head, 0.035, 0.02, 0.07, Vector3(0, 0.0, -0.105), hair, false, 6)
    Flat.limb(head, 0.138, 0.138, 0.035, Vector3(0, 0.17, 0), Color("26303a"), false, 12)
    for x in [-0.05, 0.05]:
        Flat.box(head, Vector3(0.07, 0.055, 0.03), Vector3(x, 0.17, -0.125), Color("5fd3e6"))
    _brows(head, 0.22, -0.125)
    Flat.box(head, Vector3(0.035, 0.06, 0.05), Vector3(0, 0.11, -0.135), SKIN.darkened(0.1))
    Flat.box(head, Vector3(0.09, 0.015, 0.02), Vector3(0, 0.06, -0.12), Color("5a1f1f"))
    _arms(torso, parts, coat, Color("7b3fb0"))


static func _mammoth(body: Node3D, parts: Dictionary) -> void:
    var fur := Color("6b4a2e")
    var dark := Color("4a3220")
    body.scale = Vector3.ONE * 1.25
    _legs(body, parts, fur, dark, 1.6, 0.14)
    var torso := _torso(body, parts)
    var belly := _flash(parts, Flat.ball(torso, 0.36, Vector3(0, 0.25, 0), fur, true, 1.3, 12, 8))
    belly.scale = Vector3(1, 1, 0.8)
    _chest(torso, parts, fur, 1.2, 0.8)
    var head := _head(torso, parts, fur, 0.18, 1.1)
    # NOTE (mristin):
    # The hump of hair on his head, the floppy ears, the small eyes, the
    # trunk curling down (three tapered limbs), and the two long tusks.
    Flat.ball(head, 0.12, Vector3(0, 0.3, 0.03), dark)
    for x in [-0.17, 0.17]:
        var ear := Flat.box(head, Vector3(0.05, 0.2, 0.16), Vector3(x, 0.15, 0.02), dark)
        ear.rotation.z = 0.25 if x > 0 else -0.25
    _eyes(head, 0.2, -0.16, 0.08)
    _brows(head, 0.24, -0.16)
    var trunk := _pivot(head, Vector3(0, 0.1, -0.15))
    var bend := 0.0
    var at := Vector3.ZERO
    for k in range(3):
        var piece := Flat.limb(trunk, 0.045 - k * 0.01, 0.055 - k * 0.01, 0.16, Vector3.ZERO, fur)
        bend += 0.35
        piece.rotation.x = -bend
        piece.position = at + Vector3(0, -0.08, -0.02).rotated(Vector3.RIGHT, -bend + 0.35)
        at += Vector3(0, -0.15, -0.05).rotated(Vector3.RIGHT, -bend + 0.35)
    for x in [-0.09, 0.09]:
        var tusk := Flat.limb(head, 0.012, 0.03, 0.34, Vector3(x, 0.0, -0.22), Color("f2ead2"))
        tusk.rotation = Vector3(-1.1, 0.0, 0.3 if x > 0 else -0.3)
    _arms(torso, parts, fur, dark, 0.11, 1.25, 1.5)


static func _sabre_tiger(body: Node3D, parts: Dictionary) -> void:
    var fur := Color("d98a2b")
    var stripe := Color("2a1a10")
    var cream := Color("f2e2c4")
    _legs(body, parts, fur, cream, 1.2)
    var torso := _torso(body, parts)
    _chest(torso, parts, fur, 1.0, 0.7)
    Flat.box(torso, Vector3(0.2, 0.4, 0.01), Vector3(0, 0.32, -0.18), cream)
    # NOTE (mristin):
    # The tail, curling up behind him.
    var tail := Flat.limb(torso, 0.025, 0.04, 0.6, Vector3(0, 0.0, 0.3), fur)
    tail.rotation.x = 0.9
    var head := _head(torso, parts, fur, 0.15, 1.0)
    Flat.box(head, Vector3(0.14, 0.08, 0.1), Vector3(0, 0.08, -0.12), cream)
    Flat.ball(head, 0.025, Vector3(0, 0.12, -0.18), stripe)
    for x in [-0.11, 0.11]:
        Flat.ball(head, 0.05, Vector3(x, 0.28, 0), fur)
        # NOTE (mristin):
        # The sabre teeth, long, down past the chin.
        var fang := Flat.limb(head, 0.006, 0.02, 0.17, Vector3(x * 0.35, -0.0, -0.15), WHITE)
        fang.rotation.x = -0.15
    for x in [-0.05, 0.05]:
        Flat.box(head, Vector3(0.045, 0.025, 0.02), Vector3(x, 0.19, -0.14), Color("e8d24a"))
    _brows(head, 0.23, -0.14, stripe)
    _arms(torso, parts, fur, cream, 0.095)
    # NOTE (mristin):
    # The stripes are a texture on all of his fur (see Flat.striped).
    _stripe(body, parts, fur, stripe, 38.0)


static func _cave_bear(body: Node3D, parts: Dictionary) -> void:
    var fur := Color("4b3424")
    var light := Color("8a6a4a")
    body.scale = Vector3.ONE * 1.25
    _legs(body, parts, fur, Color("2a1c12"), 1.6, 0.14)
    var torso := _torso(body, parts)
    var belly := _flash(parts, Flat.ball(torso, 0.34, Vector3(0, 0.22, 0), fur, true, 1.3, 12, 8))
    belly.scale = Vector3(1, 1, 0.85)
    _chest(torso, parts, fur, 1.25, 0.8)
    Flat.ball(torso, 0.22, Vector3(0, 0.25, -0.18), light, false, 1.3)
    var head := _head(torso, parts, fur, 0.17, 1.0)
    for x in [-0.12, 0.12]:
        Flat.ball(head, 0.055, Vector3(x, 0.3, 0.0), fur)
        Flat.ball(head, 0.03, Vector3(x, 0.3, -0.03), light)
    Flat.ball(head, 0.08, Vector3(0, 0.09, -0.14), light, false, 0.8)
    Flat.ball(head, 0.03, Vector3(0, 0.12, -0.21), DARK)
    _eyes(head, 0.2, -0.15, 0.06)
    _brows(head, 0.24, -0.15)
    _arms(torso, parts, fur, Color("2a1c12"), 0.11, 1.3, 1.5)


## The Bünzlis, each with his own rules: the laundry-room one ("bunzli": a
## beige cardigan, socks in sandals, the house rules), the snow-shovel one
## ("bunzli_shovel": a puffy jacket, a cap with ear flaps, the shovel on his
## back, the winter duty), and the hedge one ("bunzli_hedge": a green garden
## vest over a checked shirt, a bucket hat, the measuring tape at his belt).
## All have the neat side parting (under the hat), the round glasses, the
## mustache and the pursed lips.
static func _bunzli(body: Node3D, parts: Dictionary, kind := "bunzli") -> void:
    var top: Color = {
        "bunzli": Color("c9b48a"), "bunzli_shovel": Color("2a4a7a"), "bunzli_hedge": Color("4a7a3a")
    }[kind]
    var shirt: Color = {
        "bunzli": Color("e8e4d4"), "bunzli_shovel": Color("d8d8d8"), "bunzli_hedge": Color("d84a4a")
    }[kind]
    var trousers: Color = {
        "bunzli": Color("7a6a52"), "bunzli_shovel": Color("2a2a30"), "bunzli_hedge": Color("b8a07a")
    }[kind]
    var gloves: Color = {
        "bunzli": Color("c03030"), "bunzli_shovel": Color("e0a020"), "bunzli_hedge": Color("5a9a3a")
    }[kind]
    var badge: String = {
        "bunzli": "HAUSORDNUNG", "bunzli_shovel": "WINTERDIENST", "bunzli_hedge": "HECKE MAX 1.20 M"
    }[kind]
    _legs(body, parts, trousers, Color("6a4a2a") if kind != "bunzli_shovel" else DARK)
    if kind == "bunzli":
        # NOTE (mristin):
        # White socks in his sandals.
        for knee in parts["knees"]:
            Flat.limb(knee, 0.052, 0.05, 0.12, Vector3(0, -0.36, 0), WHITE)
    var torso := _torso(body, parts)
    _chest(torso, parts, top, 1.15 if kind == "bunzli_shovel" else 1.05, 0.65)
    var belly := _flash(parts, Flat.ball(torso, 0.24, Vector3(0, 0.1, -0.02), top, true))
    belly.scale = Vector3(1, 0.9, 0.7)
    Flat.box(torso, Vector3(0.1, 0.45, 0.01), Vector3(0, 0.38, -0.175), shirt)
    match kind:
        "bunzli":
            for y in [0.2, 0.32, 0.44]:
                Flat.ball(torso, 0.015, Vector3(0.07, y, -0.18), Color("6a4a2a"))
            # NOTE (mristin):
            # A pen in his breast pocket, for the notes in the house book.
            Flat.limb(torso, 0.008, 0.008, 0.12, Vector3(-0.15, 0.55, -0.17), Color("2050c0"))
        "bunzli_shovel":
            # NOTE (mristin):
            # The quilting of the puffy jacket, a scarf, and the snow shovel
            # on his back.
            for y in [0.15, 0.3, 0.45]:
                Flat.box(torso, Vector3(0.5, 0.02, 0.02), Vector3(0, y, -0.17), top.darkened(0.3))
            Flat.limb(torso, 0.1, 0.12, 0.08, Vector3(0, 0.66, 0), Color("c8302c"), false, 10)
            var handle := Flat.limb(
                torso, 0.02, 0.02, 1.2, Vector3(0.12, 0.6, 0.2), Color("8a6a4a"), false, 5
            )
            handle.rotation.z = -0.3
            var blade := Flat.box(
                torso, Vector3(0.4, 0.45, 0.03), Vector3(0.3, 1.2, 0.22), Color("d03020")
            )
            blade.rotation.z = -0.3
        "bunzli_hedge":
            # NOTE (mristin):
            # The checks of his shirt, and the measuring tape at his belt.
            for y in [0.25, 0.4, 0.55]:
                Flat.box(torso, Vector3(0.1, 0.015, 0.01), Vector3(0, y, -0.178), WHITE)
            Flat.box(torso, Vector3(0.1, 0.1, 0.06), Vector3(-0.18, 0.02, -0.17), Color("e8c020"))
            Flat.box(torso, Vector3(0.02, 0.2, 0.01), Vector3(-0.18, -0.1, -0.18), Color("e8c020"))
    _label(torso, badge, Vector3(0.15, 0.48, -0.18), DARK if kind == "bunzli" else WHITE, 14)
    var head := _head(torso, parts, SKIN)
    var hair := Color("6a5a3a")
    var cap := Flat.ball(head, 0.135, Vector3(0, 0.2, 0.01), hair, false, 0.8)
    cap.scale = Vector3(1, 0.75, 1)
    match kind:
        "bunzli":
            Flat.box(head, Vector3(0.12, 0.04, 0.03), Vector3(-0.04, 0.27, -0.09), hair)
        "bunzli_shovel":
            # NOTE (mristin):
            # A cap with ear flaps, checked red and black.
            Flat.limb(head, 0.14, 0.145, 0.14, Vector3(0, 0.27, 0), Color("b8302a"), false, 12)
            for x in [-0.14, 0.14]:
                Flat.box(head, Vector3(0.03, 0.12, 0.1), Vector3(x, 0.17, 0), Color("2a2a2a"))
            Flat.box(head, Vector3(0.24, 0.03, 0.1), Vector3(0, 0.25, -0.13), Color("2a2a2a"))
        "bunzli_hedge":
            # NOTE (mristin):
            # A bucket hat.
            Flat.limb(head, 0.11, 0.2, 0.08, Vector3(0, 0.29, 0), Color("6a8a4a"), false, 12)
            Flat.limb(head, 0.1, 0.11, 0.08, Vector3(0, 0.35, 0), Color("6a8a4a"), false, 12)
    for x in [-0.05, 0.05]:
        var lens := Flat.limb(head, 0.032, 0.032, 0.01, Vector3(x, 0.16, -0.13), DARK, false, 10)
        lens.rotation.x = PI * 0.5
    Flat.box(head, Vector3(0.1, 0.025, 0.02), Vector3(0, 0.09, -0.135), hair)
    Flat.box(head, Vector3(0.05, 0.012, 0.02), Vector3(0, 0.055, -0.125), Color("8a3a3a"))
    _arms(torso, parts, top, gloves, 0.085, 1.1 if kind == "bunzli_shovel" else 1.0)


static func _nationalist(body: Node3D, parts: Dictionary) -> void:
    var shirt := Color("2a4f9a")
    var vest := Color("b8282a")
    _legs(body, parts, Color("3a2a1a"), DARK)
    var torso := _torso(body, parts)
    # NOTE (mristin):
    # A cape of the flag behind him: red with a white cross.
    var cape := Flat.box(torso, Vector3(0.6, 0.8, 0.03), Vector3(0, 0.25, 0.2), vest)
    cape.rotation.x = -0.12
    Flat.box(torso, Vector3(0.24, 0.07, 0.02), Vector3(0, 0.35, 0.225), WHITE)
    Flat.box(torso, Vector3(0.07, 0.24, 0.02), Vector3(0, 0.35, 0.225), WHITE)
    _chest(torso, parts, shirt, 1.05, 0.6)
    # NOTE (mristin):
    # The edelweiss shirt (white flowers on blue), the red vest, and a
    # cowbell on his chest.
    for y in [0.25, 0.4, 0.55]:
        for x in [-0.05, 0.05]:
            Flat.ball(torso, 0.018, Vector3(x, y, -0.172), WHITE)
    for x in [-0.17, 0.17]:
        Flat.box(torso, Vector3(0.11, 0.5, 0.02), Vector3(x, 0.32, -0.16), vest)
    Flat.limb(torso, 0.05, 0.075, 0.11, Vector3(0, 0.12, -0.2), Color("c9a03a"))
    Flat.ball(torso, 0.012, Vector3(0, 0.05, -0.2), DARK)
    var head := _head(torso, parts, SKIN)
    # NOTE (mristin):
    # A red-faced scowl, a big mustache, and a felt hat with a feather.
    Flat.limb(head, 0.17, 0.17, 0.02, Vector3(0, 0.26, 0), Color("3a3020"), false, 12)
    Flat.limb(head, 0.1, 0.12, 0.1, Vector3(0, 0.31, 0), Color("3a3020"), false, 12)
    var feather := Flat.limb(head, 0.005, 0.015, 0.14, Vector3(0.1, 0.36, 0.02), WHITE)
    feather.rotation.z = -0.5
    _eyes(head, 0.17, -0.13)
    _brows(head, 0.21, -0.13)
    var mustache := Flat.box(
        head, Vector3(0.14, 0.03, 0.03), Vector3(0, 0.09, -0.135), Color("5a3a20")
    )
    mustache.rotation.z = 0.05
    Flat.ball(head, 0.03, Vector3(0, 0.13, -0.15), SKIN.darkened(0.15))
    _arms(torso, parts, shirt, vest)


static func _ceo(body: Node3D, parts: Dictionary) -> void:
    var suit := Color("23252e")
    var gold := Color("e2b33a")
    _legs(body, parts, suit, DARK)
    var torso := _torso(body, parts)
    _chest(torso, parts, suit, 1.1, 0.6)
    Flat.box(torso, Vector3(0.14, 0.4, 0.01), Vector3(0, 0.42, -0.172), WHITE)
    Flat.box(torso, Vector3(0.05, 0.36, 0.01), Vector3(0, 0.4, -0.178), gold)
    for x in [-0.09, 0.09]:
        var lapel := Flat.box(
            torso, Vector3(0.06, 0.3, 0.01), Vector3(x, 0.47, -0.175), Color("15161c")
        )
        lapel.rotation.z = 0.25 if x > 0 else -0.25
    _label(torso, "CEO", Vector3(0.17, 0.52, -0.18), gold, 22)
    # NOTE (mristin):
    # A golden watch on the wrist, a golden pin.
    var head := _head(torso, parts, SKIN)
    var hair := Color("2a2622")
    var slick := Flat.ball(head, 0.137, Vector3(0, 0.2, 0.02), hair, false, 0.8)
    slick.scale = Vector3(1, 0.7, 1.05)
    for x in [-0.05, 0.05]:
        Flat.box(head, Vector3(0.06, 0.035, 0.02), Vector3(x, 0.16, -0.13), gold)
    Flat.box(head, Vector3(0.12, 0.01, 0.02), Vector3(0, 0.16, -0.132), gold)
    _brows(head, 0.2, -0.13)
    # NOTE (mristin):
    # A smug grin.
    Flat.box(head, Vector3(0.1, 0.02, 0.02), Vector3(0, 0.07, -0.125), WHITE)
    _arms(torso, parts, suit, gold)
    for elbow in parts["elbows"]:
        Flat.limb(elbow, 0.046, 0.046, 0.03, Vector3(0, -0.22, 0), gold)


static func _norgeli(body: Node3D, parts: Dictionary) -> void:
    var cardigan := Color("6a4a3a")
    var wool := Color("8a8a8f")
    body.scale = Vector3.ONE * 1.0
    _legs(body, parts, Color("4a4a52"), Color("3a2a1a"))
    var torso := _torso(body, parts)
    _chest(torso, parts, cardigan, 0.95, 0.65)
    var hunch := _flash(parts, Flat.ball(torso, 0.2, Vector3(0, 0.5, 0.1), cardigan, true))
    hunch.scale = Vector3(1.2, 0.8, 0.8)
    for y in [0.2, 0.32, 0.44]:
        Flat.ball(torso, 0.015, Vector3(0, y, -0.17), Color("c9b48a"))
    var head := _head(torso, parts, SKIN, 0.14, 1.15)
    # NOTE (mristin):
    # A woolly hat with a bobble, a big nose, bushy grey brows, and the
    # corners of his mouth down.
    Flat.limb(head, 0.12, 0.145, 0.12, Vector3(0, 0.27, 0), wool, false, 12)
    Flat.ball(head, 0.05, Vector3(0, 0.36, 0), Color("c8302c"))
    Flat.ball(head, 0.045, Vector3(0, 0.13, -0.155), SKIN.darkened(0.12), false, 1.3)
    _eyes(head, 0.18, -0.13)
    for x in [-0.05, 0.05]:
        var brow := Flat.box(head, Vector3(0.09, 0.035, 0.03), Vector3(x, 0.215, -0.13), WHITE)
        brow.rotation.z = 0.3 if x > 0 else -0.3
    for x in [-0.035, 0.035]:
        var mouth := Flat.box(
            head, Vector3(0.045, 0.012, 0.02), Vector3(x, 0.06, -0.13), Color("5a1f1f")
        )
        mouth.rotation.z = -0.4 if x > 0 else 0.4
    _arms(torso, parts, cardigan, wool, 0.08, 0.95)


static func _white_sheep(body: Node3D, parts: Dictionary) -> void:
    var wool := Color("f4f1e6")
    var face := Color("f8e8dc")
    var hoof := Color("3a3030")
    _legs(body, parts, face, hoof, 0.8)
    var torso := _torso(body, parts)
    # NOTE (mristin):
    # A big smug ball of wool, of many puffs.
    var fleece := _flash(parts, Flat.ball(torso, 0.4, Vector3(0, 0.3, 0), wool, true, 1.1, 12, 8))
    fleece.scale = Vector3(1, 1, 0.85)
    for k in range(8):
        var angle := k * TAU / 8.0
        Flat.ball(torso, 0.13, Vector3(cos(angle) * 0.36, 0.3 + sin(angle) * 0.38, -0.05), wool)
    var head := _head(torso, parts, face, 0.12, 1.3)
    Flat.ball(head, 0.1, Vector3(0, 0.27, 0.02), wool)
    for x in [-0.13, 0.13]:
        var ear := Flat.box(head, Vector3(0.12, 0.035, 0.06), Vector3(x, 0.18, 0.0), face)
        ear.rotation.z = 0.35 if x > 0 else -0.35
    # NOTE (mristin):
    # Half-closed, smug eyes, and a little smirk.
    for x in [-0.045, 0.045]:
        Flat.box(head, Vector3(0.04, 0.012, 0.02), Vector3(x, 0.17, -0.12), DARK)
    Flat.box(head, Vector3(0.05, 0.012, 0.02), Vector3(0.01, 0.07, -0.12), Color("8a5050"))
    _arms(torso, parts, wool, hoof, 0.08)
