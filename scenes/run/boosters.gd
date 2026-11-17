class_name Boosters
extends Node3D

## The boosters on the road of a run (see Run and DESIGN.md): things floating
## over the road (and on the platforms, see Platforms) which the hero picks up
## by running through them. Each works in one of four ways (its kind):
##
## - "speed": he runs faster for a while, as fast as his knees go and some;
## - "health": some of his energy comes back;
## - "power": his punches hit twice as hard in the next fight;
## - "shield": the obstacles do not hurt him for a while.
##
## Each level has three of its own (see Levels), with a look of its land: a
## banana in the jungle, an espresso in the city, a Grittibänz in the winter.

## The kinds: what the HUD and the announcement call them, their color (the
## glow under and around the booster, see booster_glow.gdshader), and how
## long they work (seconds; 0: at once, -1: until the next fight).
const KINDS := {
    "speed": {"effect": "FASTER!", "color": Color("f2c14e"), "seconds": 6.0},
    "health": {"effect": "+ENERGY!", "color": Color("6ccf5e"), "seconds": 0.0},
    "power": {"effect": "POWER PUNCHES!", "color": Color("ff7a3a"), "seconds": -1.0},
    "shield": {"effect": "SHIELD!", "color": Color("4fc3f7"), "seconds": 8.0},
}

## The looks of the boosters, by their names (see Levels): their kind and
## their title.
const LOOKS := {
    "banana": {"kind": "speed", "title": "BANANA"},
    "berries": {"kind": "health", "title": "BERRIES"},
    "steak": {"kind": "power", "title": "MAMMOTH STEAK"},
    "fish": {"kind": "health", "title": "FISH"},
    "fur": {"kind": "shield", "title": "FUR"},
    "espresso": {"kind": "speed", "title": "ESPRESSO"},
    "apple": {"kind": "health", "title": "APPLE"},
    "chocolate": {"kind": "power", "title": "CHOCOLATE"},
    "helmet": {"kind": "shield", "title": "HELMET"},
    "grittibaenz": {"kind": "health", "title": "GRITTIBÄNZ"},
    "mandarin": {"kind": "speed", "title": "MANDARIN"},
    "scarf": {"kind": "shield", "title": "SCARF"},
    "peanuts": {"kind": "power", "title": "PEANUTS"},
}

## How fast he runs with a speed booster, as many times his pace.
const SPEED_BOOST := 1.4
## How much energy a health booster gives back.
const HEALTH := 25.0
## How many times as hard his punches hit with a power booster.
const POWER := 2.0

## How close across the road he must run to a booster to pick it up (from its
## middle to his), in meters; and how high it floats over its ground.
const REACH := 0.6
const FLOAT := 0.9

## The glow of the boosters: how wide the pool of light under it is, and how
## high its column of light reaches, in meters.
const GLOW_WIDE := 1.8
const GLOW_HIGH := 1.7

static var _glow_shader: Shader = preload("res://scenes/run/booster_glow.gdshader")

## The boosters on the road: "node", "look", "at" (the time of the notes at
## which he reaches it), "x" (across the road), "y" (the height of its ground:
## 0 the road, above a platform's deck) and "state" ("ahead", "taken",
## "missed").
var _items: Array = []
var _clock := 0.0


## Take all the boosters off the road.
func clear() -> void:
    for item in _items:
        (item["node"] as Node).queue_free()
    _items.clear()


## Put a booster of the [param look] on the road, which he reaches at the time
## of the notes [param at], at [param x] across the road, over a ground at the
## height [param y].
func add(look: String, at: float, x: float, y := 0.0) -> void:
    var node := Node3D.new()
    add_child(node)
    var kind: String = LOOKS[look]["kind"]
    _glow(node, KINDS[kind]["color"], at)
    var thing := Node3D.new()
    thing.name = "Thing"
    node.add_child(thing)
    build(look, thing)
    node.visible = false
    _items.append({"node": node, "look": look, "at": at, "x": x, "y": y, "state": "ahead"})


## Place the boosters at the time of the notes [param t] (meters a second of
## the notes: [param speed]), from the player's [param spot]; they spin and bob.
func place(t: float, speed: float, spot: Vector3, delta: float) -> void:
    _clock += delta
    for item in _items:
        var node: Node3D = item["node"]
        var ahead: float = (float(item["at"]) - t) * speed
        node.visible = item["state"] != "taken" and ahead < Scenery.AHEAD and ahead > -3.0
        if not node.visible:
            continue
        # NOTE (mristin):
        # The thing bobs; its glow stays on the ground.
        var bob := 0.08 * sin(_clock * 3.0 + float(item["at"]))
        node.position = spot + Vector3(item["x"], float(item["y"]) + FLOAT, -ahead)
        var thing := node.get_node("Thing") as Node3D
        thing.position.y = bob
        thing.rotation.y = _clock * 2.0


## The boosters which he picks up as he reaches them by the time of the notes
## [param t], at [param x] across the road and the height [param y] (on a
## platform, or on the road); the others he passes are missed.
func take(t: float, x: float, y: float) -> Array[String]:
    var taken: Array[String] = []
    for item in _items:
        if item["state"] != "ahead" or t < float(item["at"]):
            continue
        var close := absf(float(item["x"]) - x) <= REACH
        var level := absf(float(item["y"]) - y) < 0.3
        if close and level:
            item["state"] = "taken"
            taken.append(item["look"])
        else:
            item["state"] = "missed"
    return taken


## Drop the boosters which he would reach in the times of the notes from
## [param from] to [param to] (a shortcut skips them).
func skip(from: float, to: float) -> void:
    for item in _items:
        if item["state"] == "ahead" and float(item["at"]) > from and float(item["at"]) <= to:
            item["state"] = "missed"


## The glow of a booster of the [param color] under the [param node] (which
## floats FLOAT over the ground), to draw the eye: a pool of light with rings
## spreading out on the ground, and a column of light around the booster.
static func _glow(node: Node3D, color: Color, seed: float) -> void:
    for aura in [false, true]:
        var material := ShaderMaterial.new()
        material.shader = _glow_shader
        material.set_shader_parameter("color", color)
        material.set_shader_parameter("aura", aura)
        material.set_shader_parameter("phase", fposmod(seed * 1.7, TAU))
        var instance := MeshInstance3D.new()
        instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        instance.material_override = material
        if aura:
            var column := CylinderMesh.new()
            column.top_radius = 0.42
            column.bottom_radius = 0.55
            column.height = GLOW_HIGH
            column.cap_top = false
            column.cap_bottom = false
            column.radial_segments = 24
            column.rings = 1
            instance.mesh = column
            instance.position = Vector3(0, -FLOAT + GLOW_HIGH * 0.5, 0)
        else:
            var pool := PlaneMesh.new()
            pool.size = Vector2(GLOW_WIDE, GLOW_WIDE)
            instance.mesh = pool
            instance.position = Vector3(0, -FLOAT + 0.02, 0)
        node.add_child(instance)


## Build the look of the booster of the name into the node: a little thing of
## the land, about 0.4 m big, around the node's origin.
static func build(look: String, node: Node3D) -> void:
    match look:
        "banana":
            # NOTE (mristin):
            # A bunch of three, curved, yellow with brown tips.
            for k in range(3):
                var banana := Node3D.new()
                node.add_child(banana)
                banana.rotation = Vector3(0, k * 0.5 - 0.5, 0)
                for s in range(3):
                    var part := Flat.limb(
                        banana, 0.045, 0.05, 0.14, Vector3(0, 0, 0), Color("f4d23a")
                    )
                    part.position = Vector3(0.12 * (s - 1), 0.05 * absf(s - 1), 0)
                    part.rotation.z = (s - 1) * -1.0
                Flat.ball(banana, 0.03, Vector3(0.2, 0.08, 0), Color("4a3a1a"))
        "berries":
            var colors := [Color("c8302c"), Color("7b2a8a"), Color("a02040")]
            for k in range(7):
                var angle := k * TAU / 6.0
                var at := Vector3(cos(angle) * 0.1, (k % 3) * 0.06 - 0.04, sin(angle) * 0.1)
                if k == 6:
                    at = Vector3(0, 0.1, 0)
                Flat.ball(node, 0.07, at, colors[k % 3])
            Flat.box(node, Vector3(0.18, 0.02, 0.08), Vector3(0, 0.17, 0), Color("3f8a30"))
        "steak":
            # NOTE (mristin):
            # Meat on a bone, as the cavemen of the cartoons eat it.
            var meat := Flat.ball(node, 0.16, Vector3.ZERO, Color("a83a2a"), false, 0.8)
            meat.scale = Vector3(1.3, 1, 1)
            var bone := Flat.limb(node, 0.035, 0.035, 0.6, Vector3.ZERO, Color("f2ead8"))
            bone.rotation.z = PI * 0.5
            for x in [-0.3, 0.3]:
                Flat.ball(node, 0.06, Vector3(x, 0.03, 0), Color("f2ead8"))
                Flat.ball(node, 0.06, Vector3(x, -0.04, 0), Color("f2ead8"))
        "fish":
            var body := Flat.ball(node, 0.14, Vector3.ZERO, Color("7a9ab8"), false, 0.6)
            body.scale = Vector3(1.8, 1, 0.6)
            var tail := Flat.box(
                node, Vector3(0.04, 0.2, 0.14), Vector3(0.3, 0, 0), Color("5a7a98")
            )
            tail.rotation.z = 0.2
            Flat.ball(node, 0.025, Vector3(-0.17, 0.03, 0.05), Color("101010"))
        "fur":
            # NOTE (mristin):
            # A pelt, folded: striped as the sabre-tooth tiger's.
            var pelt := MeshInstance3D.new()
            var box := BoxMesh.new()
            box.size = Vector3(0.45, 0.1, 0.32)
            pelt.mesh = box
            pelt.material_override = Flat.striped(Color("c88a3a"), Color("3a2a1a"), 30.0)
            pelt.rotation.z = 0.25
            node.add_child(pelt)
        "espresso":
            Flat.limb(node, 0.2, 0.2, 0.025, Vector3(0, -0.12, 0), Color("f4f2ee"))
            Flat.limb(node, 0.11, 0.08, 0.18, Vector3(0, -0.02, 0), Color("f4f2ee"))
            Flat.limb(node, 0.1, 0.1, 0.01, Vector3(0, 0.07, 0), Color("5a3418"))
            var handle := Flat.box(
                node, Vector3(0.06, 0.08, 0.03), Vector3(0.13, -0.01, 0), Color("f4f2ee")
            )
            handle.rotation.z = 0.3
            # NOTE (mristin):
            # Its steam.
            for k in range(3):
                Flat.ball(
                    node, 0.03 + k * 0.01, Vector3(0.02 * k, 0.14 + k * 0.08, 0), Color("ffffff")
                )
        "apple":
            Flat.ball(node, 0.16, Vector3.ZERO, Color("c8302c"), false, 0.95, 9, 6)
            Flat.limb(node, 0.012, 0.015, 0.08, Vector3(0, 0.17, 0), Color("4a3a1a"))
            var leaf := Flat.box(
                node, Vector3(0.1, 0.01, 0.05), Vector3(0.05, 0.19, 0), Color("3f8a30")
            )
            leaf.rotation.z = 0.4
        "chocolate":
            # NOTE (mristin):
            # A bar, half unwrapped: the red wrapper, the silver foil, and the
            # squares of the chocolate.
            Flat.box(node, Vector3(0.42, 0.04, 0.2), Vector3(0.08, 0, 0), Color("c8302c"))
            Flat.box(node, Vector3(0.1, 0.045, 0.2), Vector3(-0.14, 0, 0), Color("d8dce2"))
            for k in range(2):
                for j in range(2):
                    Flat.box(
                        node,
                        Vector3(0.07, 0.05, 0.085),
                        Vector3(-0.25 + k * 0.08, 0.005, -0.045 + j * 0.09),
                        Color("5a3418")
                    )
            Flat.box(node, Vector3(0.04, 0.05, 0.21), Vector3(0.1, 0.002, 0), Color("ffffff"))
        "helmet":
            var shell := Flat.ball(node, 0.2, Vector3.ZERO, Color("2a6ad8"), false, 1.0, 9, 6)
            shell.scale = Vector3(1, 0.75, 1.15)
            Flat.box(node, Vector3(0.05, 0.16, 0.42), Vector3(0, 0.06, 0), Color("f4f2ee"))
            Flat.box(node, Vector3(0.42, 0.04, 0.04), Vector3(0, -0.08, -0.2), Color("1a1a1a"))
        "grittibaenz":
            # NOTE (mristin):
            # The bread man of Samichlaus' day: a head, a body, arms and legs,
            # raisins for the eyes and the buttons.
            var bread := Color("c8883a")
            Flat.ball(node, 0.08, Vector3(0, 0.17, 0), bread)
            var body := Flat.ball(node, 0.12, Vector3(0, 0, 0), bread)
            body.scale = Vector3(1, 1.1, 0.6)
            for side in [-1.0, 1.0]:
                var arm := Flat.limb(node, 0.035, 0.04, 0.16, Vector3(side * 0.13, 0.05, 0), bread)
                arm.rotation.z = side * 1.0
                var leg := Flat.limb(node, 0.04, 0.045, 0.16, Vector3(side * 0.06, -0.16, 0), bread)
                leg.rotation.z = side * 0.2
                Flat.ball(node, 0.015, Vector3(side * 0.03, 0.19, -0.07), Color("2a1a10"))
            for y in [0.05, -0.03]:
                Flat.ball(node, 0.018, Vector3(0, y, -0.07), Color("2a1a10"))
        "mandarin":
            Flat.ball(node, 0.15, Vector3.ZERO, Color("f08a1a"), false, 0.85, 9, 6)
            var leaf := Flat.box(
                node, Vector3(0.1, 0.01, 0.05), Vector3(0.04, 0.14, 0), Color("3f8a30")
            )
            leaf.rotation.z = 0.3
        "scarf":
            # NOTE (mristin):
            # A woolly scarf, rolled up, its ends hanging, red and white.
            var roll := MeshInstance3D.new()
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = 0.13
            cylinder.bottom_radius = 0.13
            cylinder.height = 0.22
            cylinder.radial_segments = 8
            roll.mesh = cylinder
            roll.material_override = Flat.striped(Color("c8302c"), Color("f4f2ee"), 40.0)
            roll.rotation.x = PI * 0.5
            node.add_child(roll)
            for x in [-0.06, 0.06]:
                Flat.box(node, Vector3(0.08, 0.26, 0.03), Vector3(x, -0.2, -0.09), Color("c8302c"))
        "peanuts":
            # NOTE (mristin):
            # Peanuts in their shells (Spanisch Nüssli), from Samichlaus'
            # sack: each shell two lobes with a waist, its net of ridges;
            # one shell is cracked open, its two kernels in their red skins.
            var shell := Flat.striped(Color("c89a5e"), Color("9a7040"), 70.0)
            var places := [
                Vector3(-0.1, 0.0, 0.04), Vector3(0.09, 0.04, -0.03), Vector3(0, -0.06, -0.08)
            ]
            for k in range(places.size()):
                var peanut := Node3D.new()
                node.add_child(peanut)
                peanut.position = places[k]
                peanut.rotation = Vector3(0.5 * k, 0.9 * k, 0.4 - 0.5 * k)
                for lobe in [[-0.055, 0.058], [0.055, 0.052], [0.0, 0.043]]:
                    var part := Flat.ball(peanut, lobe[1], Vector3(lobe[0], 0, 0), Color.WHITE)
                    part.material_override = shell
                    part.scale = Vector3(1.0, 0.9, 0.9)
            var open := Node3D.new()
            node.add_child(open)
            open.position = Vector3(0.02, 0.1, 0.08)
            open.rotation = Vector3(0.3, 0.2, 0.1)
            var half := Flat.ball(open, 0.06, Vector3.ZERO, Color.WHITE)
            half.material_override = shell
            half.scale = Vector3(2.0, 0.45, 1.0)
            for x in [-0.045, 0.045]:
                var kernel := Flat.ball(open, 0.038, Vector3(x, 0.03, 0), Color("a0503a"))
                kernel.scale = Vector3(1.15, 0.9, 0.9)
        _:
            Flat.ball(node, 0.15, Vector3.ZERO, Color.WHITE)
