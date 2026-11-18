class_name PropsSuburbs
extends RefCounted

## The props of the suburbs in winter (see Scenery): little houses in many
## colors with snowy roofs, garages, chimneys and lit windows, and their
## gardens: pines and leafless trees under snow, hedges, fences, garden gnomes,
## snowmen, mailboxes, cars under snow, sleds, bird houses, swings, sheds, a
## grill, a trampoline, Christmas lights, lanterns. Each varied at random, in
## three rows: small things by the road ("near"), the houses and gardens
## ("middle"), and big things further away ("far").

const SNOW := Color("f4f7fb")
const SNOW_SHADE := Color("d8e2ee")
const WALLS := [
    Color("e8d0b0"),
    Color("c8d8c0"),
    Color("e0c0c0"),
    Color("c0d0e0"),
    Color("f0e8d0"),
    Color("d8c8e0"),
]
const LIT := Color("ffd98a")
const WOOD := Color("8a6a4a")
const RED := Color("c8302c")
const GREEN := Color("2a5a3a")


## Dress the prop of the suburbs in its row ([param side]: -1 left of the
## road, 1 right).
static func build(p: Node3D, r: RandomNumberGenerator, row: String, side: float) -> void:
    var builders: Array
    match row:
        "near":
            builders = [
                _gnome,
                _gnome,
                _mailbox,
                _snowman,
                _sled,
                _lantern,
                _fence,
                _bird_house,
                _flower_pot,
                _snow_pile,
                _bin,
            ]
        "far":
            builders = [_house, _house, _church, _pine_group, _hill]
        _:
            builders = [
                _house,
                _house,
                _house,
                _pine,
                _bare_tree,
                _hedge,
                _car,
                _shed,
                _swing,
                _trampoline,
                _grill,
                _garage,
            ]
    (builders[r.randi() % builders.size()] as Callable).call(p, r, side)


## A little house: walls, lit windows facing the road, a pitched roof under
## snow, a chimney, sometimes Christmas lights along the eaves.
static func _house(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    var width := r.randf_range(3.0, 4.5)
    var height := r.randf_range(2.6, 4.0)
    var front := -side * width * 0.5
    Flat.box(
        p, Vector3(width, height, 4.0), Vector3(0, height * 0.5, 0), WALLS[r.randi() % WALLS.size()]
    )
    for k in range(r.randi_range(2, 4)):
        var lit := LIT if r.randf() < 0.75 else Color("4a5a7a")
        Flat.box(p, Vector3(0.05, 0.8, 0.7), Vector3(front, height * 0.55, -1.3 + k * 0.9), lit)
    Flat.box(p, Vector3(0.05, 1.6, 0.8), Vector3(front, 0.8, 1.5), WOOD.darkened(0.2))
    for dz in [-1.0, 1.0]:
        var roof := Flat.box(
            p, Vector3(width * 1.1, 0.2, 2.6), Vector3(0, height + 0.7, dz), Color("8a4a3a")
        )
        roof.rotation.x = 0.6 if dz > 0 else -0.6
        var cover := Flat.box(
            p, Vector3(width * 1.12, 0.1, 2.5), Vector3(0, height + 0.82, dz * 0.97), SNOW
        )
        cover.rotation.x = roof.rotation.x
    Flat.box(p, Vector3(0.4, 1.2, 0.4), Vector3(width * 0.25, height + 1.3, 0.6), Color("8a4a3a"))
    if r.randf() < 0.5:
        # NOTE (mristin):
        # Christmas lights along the eaves.
        var colors := [RED, Color("2ac04a"), Color("2a8ae0"), Color("f2c14e")]
        for k in range(9):
            Flat.ball(
                p,
                0.06,
                Vector3(front - side * 0.1, height + 0.05, -2.0 + k * 0.5),
                colors[k % colors.size()]
            )


static func _church(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.box(p, Vector3(5.0, 6.0, 9.0), Vector3(0, 3.0, 0), Color("f0ece0"))
    Flat.box(p, Vector3(2.0, 12.0, 2.0), Vector3(0, 6.0, -4.0), Color("f0ece0"))
    Flat.limb(p, 0.05, 1.5, 4.0, Vector3(0, 14.0, -4.0), Color("4a6a5a"), false, 4)
    Flat.ball(p, 0.5, Vector3(0, 9.0, -5.0), Color("e8c040"))


static func _pine(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var tall := r.randf_range(0.8, 1.6)
    Flat.limb(p, 0.08, 0.12, 0.6, Vector3(0, 0.3, 0), Color("4a3020"), false, 6)
    for k in range(3):
        var y := (0.8 + k * 0.6) * tall
        var radius := (0.9 - k * 0.25) * tall
        Flat.limb(p, 0.05, radius, 0.8 * tall, Vector3(0, y, 0), GREEN, false, 7)
        Flat.limb(p, 0.05, radius * 0.7, 0.25 * tall, Vector3(0, y + 0.3 * tall, 0), SNOW, false, 7)
    if r.randf() < 0.3:
        Flat.ball(p, 0.12, Vector3(0, 2.6 * tall, 0), Color("f2c14e"))


static func _pine_group(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    for k in range(r.randi_range(3, 6)):
        var tree := Node3D.new()
        tree.position = Vector3(r.randf_range(-3, 3), 0, r.randf_range(-3, 3))
        tree.scale = Vector3.ONE * r.randf_range(1.5, 2.5)
        p.add_child(tree)
        _pine(tree, r, side)


static func _hill(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var hill := Flat.ball(
        p, r.randf_range(4.0, 7.0), Vector3(0, -1.0, 0), SNOW_SHADE, false, 1.0, 9, 5
    )
    hill.scale = Vector3(1.6, 0.6, 1.2)


static func _bare_tree(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.08, 0.15, 2.4, Vector3(0, 1.2, 0), Color("5a4a40"), false, 6)
    for k in range(r.randi_range(4, 6)):
        var branch := Flat.limb(
            p, 0.02, 0.06, 1.2, Vector3(0, 1.8 + k * 0.2, 0), Color("5a4a40"), false, 5
        )
        branch.rotation = Vector3(
            r.randf_range(-0.3, 0.3), r.randf() * TAU, r.randf_range(0.6, 1.0)
        )
        Flat.box(p, Vector3(0.5, 0.04, 0.06), Vector3(0, 2.3 + k * 0.2, 0), SNOW).rotation = (
            branch.rotation
        )


static func _hedge(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var length := r.randf_range(2.0, 4.0)
    Flat.box(p, Vector3(0.6, 0.9, length), Vector3(0, 0.45, 0), GREEN)
    Flat.box(p, Vector3(0.62, 0.12, length + 0.02), Vector3(0, 0.95, 0), SNOW)


static func _fence(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var white := r.randf() < 0.5
    var color := Color("f0ece4") if white else WOOD
    for k in range(6):
        Flat.box(p, Vector3(0.06, 0.8, 0.08), Vector3(0, 0.4, -1.25 + k * 0.5), color)
        Flat.box(p, Vector3(0.08, 0.06, 0.1), Vector3(0, 0.83, -1.25 + k * 0.5), SNOW)
    for y in [0.3, 0.6]:
        Flat.box(p, Vector3(0.04, 0.06, 2.7), Vector3(0, y, 0), color)


static func _gnome(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var coat: Color = [Color("2a5aa0"), RED, Color("2a8a3a"), Color("e8c020")][r.randi() % 4]
    Flat.limb(p, 0.1, 0.14, 0.3, Vector3(0, 0.15, 0), coat, false, 7)
    Flat.ball(p, 0.09, Vector3(0, 0.38, 0), Color("e0b48e"))
    Flat.limb(p, 0.08, 0.12, 0.1, Vector3(0, 0.33, -0.04), Color("f1f0ea"), false, 7)
    Flat.limb(p, 0.005, 0.1, 0.28, Vector3(0, 0.58, 0), RED, false, 7)
    Flat.limb(p, 0.005, 0.06, 0.05, Vector3(0, 0.73, 0), SNOW, false, 7)


static func _snowman(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.ball(p, 0.35, Vector3(0, 0.3, 0), SNOW, false, 1.0, 8, 5)
    Flat.ball(p, 0.25, Vector3(0, 0.8, 0), SNOW, false, 1.0, 8, 5)
    Flat.ball(p, 0.17, Vector3(0, 1.18, 0), SNOW, false, 1.0, 8, 5)
    var carrot := Flat.limb(p, 0.005, 0.03, 0.15, Vector3(0, 1.18, -0.2), Color("f08a24"), false, 5)
    carrot.rotation.x = -PI * 0.5
    Flat.limb(
        p,
        0.12,
        0.12,
        0.2,
        Vector3(0, 1.42, 0),
        Color("1a1a1e") if r.randf() < 0.5 else RED,
        false,
        8
    )


static func _mailbox(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.04, 0.04, 1.0, Vector3(0, 0.5, 0), WOOD, false, 5)
    var box := Color("e8c020") if r.randf() < 0.6 else RED
    Flat.box(p, Vector3(0.35, 0.3, 0.45), Vector3(0, 1.1, 0), box)
    Flat.box(p, Vector3(0.37, 0.06, 0.47), Vector3(0, 1.28, 0), SNOW)


static func _sled(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.box(p, Vector3(0.45, 0.05, 1.0), Vector3(0, 0.25, 0), WOOD)
    for x in [-0.2, 0.2]:
        Flat.box(p, Vector3(0.04, 0.2, 1.1), Vector3(x, 0.12, 0), Color("6a4a2a"))
    Flat.box(p, Vector3(0.5, 0.04, 0.04), Vector3(0, 0.35, -0.55), Color("6a4a2a"))


static func _lantern(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.04, 0.05, 2.8, Vector3(0, 1.4, 0), Color("2a2a30"), false, 6)
    Flat.box(p, Vector3(0.25, 0.35, 0.25), Vector3(0, 2.9, 0), LIT)
    Flat.limb(p, 0.01, 0.2, 0.15, Vector3(0, 3.15, 0), Color("2a2a30"), false, 4)


static func _bird_house(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.03, 0.03, 1.5, Vector3(0, 0.75, 0), WOOD, false, 5)
    Flat.box(p, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.6, 0), WALLS[r.randi() % WALLS.size()])
    Flat.limb(p, 0.01, 0.28, 0.2, Vector3(0, 1.85, 0), SNOW, false, 4)
    Flat.ball(p, 0.05, Vector3(0, 1.62, -0.16), Color("1a1a1e"))


static func _flower_pot(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.25, 0.18, 0.35, Vector3(0, 0.17, 0), Color("b0603a"), false, 8)
    Flat.ball(p, 0.22, Vector3(0, 0.38, 0), SNOW, false, 0.6, 7, 3)


static func _snow_pile(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    for k in range(r.randi_range(2, 4)):
        Flat.ball(
            p,
            r.randf_range(0.3, 0.6),
            Vector3(r.randf_range(-0.4, 0.4), 0.05, r.randf_range(-0.4, 0.4)),
            SNOW_SHADE,
            false,
            0.6,
            7,
            4
        )


static func _bin(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var color: Color = [Color("2a5a3a"), Color("6a6a6a"), Color("2a4a9a")][r.randi() % 3]
    Flat.box(p, Vector3(0.6, 1.0, 0.7), Vector3(0, 0.5, 0), color)
    Flat.box(p, Vector3(0.62, 0.1, 0.72), Vector3(0, 1.05, 0), SNOW)


static func _car(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    var paint: Color = [RED, Color("2a4a9a"), Color("4a4a4a"), Color("e0e0e0"), Color("4a7a4a")][
        r.randi() % 5
    ]
    p.position.x -= side * 1.0
    Flat.box(p, Vector3(1.7, 0.6, 3.8), Vector3(0, 0.55, 0), paint)
    Flat.box(p, Vector3(1.5, 0.55, 2.0), Vector3(0, 1.1, 0.2), paint)
    Flat.box(p, Vector3(1.55, 0.2, 2.1), Vector3(0, 1.45, 0.2), SNOW)
    for x in [-0.8, 0.8]:
        for z in [-1.2, 1.2]:
            var wheel := Flat.limb(p, 0.3, 0.3, 0.2, Vector3(x, 0.3, z), Color("1a1a1a"), false, 10)
            wheel.rotation.z = PI * 0.5


static func _shed(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.box(
        p,
        Vector3(1.8, 1.8, 1.6),
        Vector3(0, 0.9, 0),
        WOOD if r.randf() < 0.5 else RED.darkened(0.3)
    )
    Flat.box(p, Vector3(2.0, 0.2, 1.8), Vector3(0, 1.9, 0), SNOW)


static func _swing(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    for z in [-1.0, 1.0]:
        for x in [-0.4, 0.4]:
            var leg := Flat.limb(p, 0.04, 0.04, 2.2, Vector3(x * 0.5, 1.05, z), WOOD, false, 5)
            leg.rotation.z = x * 0.4
    Flat.limb(p, 0.05, 0.05, 2.2, Vector3(0, 2.1, 0), WOOD, false, 5).rotation.x = PI * 0.5
    Flat.box(p, Vector3(0.3, 0.05, 0.5), Vector3(0, 0.5, 0), RED)
    for z in [-0.2, 0.2]:
        Flat.limb(p, 0.01, 0.01, 1.6, Vector3(0, 1.3, z), Color("6a6a6a"), false, 3)


static func _trampoline(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 1.2, 1.2, 0.08, Vector3(0, 0.7, 0), Color("2a2a30"), false, 12)
    Flat.limb(p, 1.15, 1.15, 0.1, Vector3(0, 0.76, 0), SNOW, false, 12)
    for k in range(4):
        Flat.limb(
            p,
            0.03,
            0.03,
            0.7,
            Vector3(cos(k * PI * 0.5) * 1.1, 0.35, sin(k * PI * 0.5) * 1.1),
            Color("2a2a30"),
            false,
            4
        )


static func _grill(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.ball(p, 0.3, Vector3(0, 0.9, 0), Color("1a1a1e"), false, 0.8, 8, 4)
    Flat.ball(p, 0.25, Vector3(0, 1.08, 0), SNOW, false, 0.4, 8, 3)
    for k in range(3):
        var leg := Flat.limb(
            p,
            0.02,
            0.02,
            0.8,
            Vector3(cos(k * TAU / 3.0) * 0.15, 0.4, sin(k * TAU / 3.0) * 0.15),
            Color("1a1a1e"),
            false,
            4
        )
        leg.rotation = Vector3(sin(k * TAU / 3.0) * 0.3, 0, -cos(k * TAU / 3.0) * 0.3)


static func _garage(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    Flat.box(p, Vector3(3.0, 2.6, 3.0), Vector3(0, 1.3, 0), WALLS[r.randi() % WALLS.size()])
    Flat.box(p, Vector3(0.05, 2.0, 2.4), Vector3(-side * 1.52, 1.0, 0), Color("c8c8c8"))
    Flat.box(p, Vector3(3.1, 0.25, 3.1), Vector3(0, 2.72, 0), SNOW)
