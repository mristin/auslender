class_name PropsCity
extends RefCounted

## The props of the Swiss city (see Scenery): the houses in many colors and
## heights (flat roofs and pitched ones, with shutters, balconies, flower
## boxes, shops with awnings), and the life of the street: lamp posts, trees in
## planters, benches, bicycles, parked cars, a tram stop, recycling bins, flags,
## a fountain, a kiosk, pigeons, bollards and signs. Each varied at random, in
## three rows: small things by the road ("near"), the houses ("middle"), and
## the skyline ("far").

const WALLS := [
    Color("e8d8b8"),
    Color("d8b8a0"),
    Color("c8d0c0"),
    Color("e0c8c8"),
    Color("f0e8d8"),
    Color("c8d8e8"),
    Color("e8e0a8"),
    Color("d0b0c8"),
]
const SHUTTERS := [Color("3a7a4a"), Color("8a3a2a"), Color("3a5a8a"), Color("6a6a6a")]
const GLASS := Color("5a7a9a")
const STEEL := Color("3a3f4a")
const RED := Color("d0282a")
const WHITE := Color("f4f2ee")


## Dress the prop of the city in its row ([param side]: -1 left of the road,
## 1 right).
static func build(p: Node3D, r: RandomNumberGenerator, row: String, side: float) -> void:
    match row:
        "near":
            var builders := [
                _lamp,
                _lamp,
                _planter,
                _bench,
                _bicycle,
                _bins,
                _bollards,
                _sign,
                _pigeons,
                _hydrant,
                _flower_pot,
                _scooter,
            ]
            (builders[r.randi() % builders.size()] as Callable).call(p, r, side)
        "far":
            _tower(p, r, side)
        _:
            var builders := [
                _house,
                _house,
                _house,
                _shop,
                _shop,
                _old_house,
                _car,
                _tram_stop,
                _fountain,
                _kiosk,
                _flag_pole,
                _tree,
            ]
            (builders[r.randi() % builders.size()] as Callable).call(p, r, side)


static func _wall(r: RandomNumberGenerator) -> Color:
    return WALLS[r.randi() % WALLS.size()]


## A house: a box of floors, with rows of windows (and shutters) facing the
## road, a roof (flat or pitched), sometimes balconies and flower boxes.
static func _house(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    var floors := r.randi_range(2, 6)
    var width := r.randf_range(2.5, 4.0)
    var height := floors * 2.2 + 0.5
    var front := -side * width * 0.5
    Flat.box(p, Vector3(width, height, 3.0), Vector3(0, height * 0.5, 0), _wall(r))
    var shutter: Color = SHUTTERS[r.randi() % SHUTTERS.size()]
    var balconies := r.randf() < 0.4
    for f in range(floors):
        for w in range(2):
            var y := 1.4 + f * 2.2
            var z := -0.7 + w * 1.4
            Flat.box(p, Vector3(0.05, 1.0, 0.7), Vector3(front, y, z), GLASS)
            for dz in [-0.45, 0.45]:
                Flat.box(
                    p, Vector3(0.06, 1.0, 0.18), Vector3(front - side * 0.01, y, z + dz), shutter
                )
            if f > 0 and r.randf() < 0.3:
                Flat.box(
                    p,
                    Vector3(0.2, 0.18, 0.7),
                    Vector3(front - side * 0.1, y - 0.6, z),
                    Color("8a5a3a")
                )
                Flat.ball(p, 0.1, Vector3(front - side * 0.15, y - 0.45, z - 0.2), Color("e05a7a"))
                Flat.ball(p, 0.1, Vector3(front - side * 0.15, y - 0.45, z + 0.2), Color("f2c14e"))
        if balconies and f > 0:
            Flat.box(
                p, Vector3(0.6, 0.08, 2.6), Vector3(front - side * 0.3, 0.5 + f * 2.2, 0), WHITE
            )
            Flat.box(
                p, Vector3(0.04, 0.5, 2.6), Vector3(front - side * 0.58, 0.75 + f * 2.2, 0), STEEL
            )
    if r.randf() < 0.5:
        # NOTE (mristin):
        # A pitched roof of red tiles.
        for dz in [-0.75, 0.75]:
            var roof := Flat.box(
                p, Vector3(width * 1.05, 0.15, 1.8), Vector3(0, height + 0.5, dz), Color("a84a3a")
            )
            roof.rotation.x = 0.55 if dz > 0 else -0.55
    else:
        Flat.box(p, Vector3(width, 0.2, 3.0), Vector3(0, height + 0.1, 0), Color("6a6a6a"))
        if r.randf() < 0.5:
            Flat.limb(p, 0.4, 0.4, 0.8, Vector3(0.5, height + 0.6, 0.5), STEEL, false, 8)


## An old town house: narrow, with a stepped gable and a painted front.
static func _old_house(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    _house(p, r, side)
    var top := 0.0
    for child in p.get_children():
        top = maxf(top, (child as Node3D).position.y)
    for k in range(3):
        Flat.box(p, Vector3(2.0 - k * 0.6, 0.6, 2.8), Vector3(0, top + 0.4 + k * 0.6, 0), _wall(r))
    Flat.box(p, Vector3(0.05, 1.2, 1.6), Vector3(-side * 1.25, 3.5, 0), Color("c8a040"))


## A shop: a house with a shop window and an awning in stripes, and a sign.
static func _shop(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    _house(p, r, side)
    var front := -side * 1.6
    Flat.box(p, Vector3(0.06, 1.6, 2.4), Vector3(front, 1.0, 0), Color("9ac0d8"))
    var stripes: Color = [RED, Color("2a7a3a"), Color("2a4a9a"), Color("e8a020")][r.randi() % 4]
    for k in range(5):
        var awning := Flat.box(
            p,
            Vector3(1.0, 0.05, 0.5),
            Vector3(front - side * 0.4, 2.2, -1.0 + k * 0.5),
            stripes if k % 2 == 0 else WHITE
        )
        awning.rotation.z = side * 0.35
    var names := ["KÄSE", "BECK", "UHREN", "COIFFEUR", "APOTHEKE", "SCHOGGI", "KIOSK", "MIGROLI"]
    var sign := Label3D.new()
    sign.text = names[r.randi() % names.size()]
    sign.font_size = 96
    sign.pixel_size = 0.004
    sign.modulate = Color("1a1a1a")
    sign.position = Vector3(front - side * 0.05, 2.7, 0)
    sign.rotation.y = -side * PI * 0.5
    p.add_child(sign)


static func _tower(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var height := r.randf_range(12.0, 28.0)
    Flat.box(
        p,
        Vector3(r.randf_range(4, 8), height, 4.0),
        Vector3(0, height * 0.5, 0),
        _wall(r).darkened(0.15)
    )
    if r.randf() < 0.3:
        # NOTE (mristin):
        # A church tower with its spire.
        Flat.limb(p, 0.05, 1.6, 5.0, Vector3(0, height + 2.5, 0), Color("4a6a5a"), false, 4)


static func _lamp(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.04, 0.06, 3.4, Vector3(0, 1.7, 0), STEEL, false, 6)
    var arm := Flat.box(p, Vector3(0.6, 0.05, 0.05), Vector3(0.25, 3.35, 0), STEEL)
    arm.rotation.z = 0.1
    Flat.ball(p, 0.13, Vector3(0.5, 3.2, 0), Color("fff2c8"))


static func _planter(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.box(p, Vector3(0.9, 0.5, 0.9), Vector3(0, 0.25, 0), Color("9a9a96"))
    Flat.limb(p, 0.05, 0.08, 1.4, Vector3(0, 1.0, 0), Color("5a4028"), false, 5)
    Flat.ball(p, r.randf_range(0.5, 0.8), Vector3(0, 2.0, 0), Color("4a8a3a"), false, 1.0, 7, 4)


static func _tree(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.12, 0.18, 2.6, Vector3(0, 1.3, 0), Color("5a4028"), false, 6)
    for k in range(r.randi_range(3, 5)):
        Flat.ball(
            p,
            r.randf_range(0.8, 1.3),
            Vector3(
                r.randf_range(-0.6, 0.6), 3.2 + r.randf_range(-0.3, 0.6), r.randf_range(-0.6, 0.6)
            ),
            Color("3f7a32"),
            false,
            0.9,
            7,
            4
        )


static func _bench(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.box(p, Vector3(0.45, 0.06, 1.6), Vector3(0, 0.45, 0), Color("8a5a3a"))
    Flat.box(p, Vector3(0.06, 0.45, 1.6), Vector3(0.22, 0.75, 0), Color("8a5a3a"))
    for z in [-0.7, 0.7]:
        Flat.box(p, Vector3(0.4, 0.45, 0.05), Vector3(0, 0.22, z), STEEL)


static func _bicycle(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var frame: Color = [RED, Color("2a7a3a"), Color("2a4a9a"), Color("1a1a1a")][r.randi() % 4]
    for z in [-0.45, 0.45]:
        var wheel := Flat.limb(p, 0.33, 0.33, 0.03, Vector3(0, 0.34, z), Color("1a1a1a"), false, 12)
        wheel.rotation.z = PI * 0.5
    var bar := Flat.box(p, Vector3(0.04, 0.04, 0.9), Vector3(0, 0.6, 0), frame)
    bar.rotation.x = 0.1
    Flat.box(p, Vector3(0.04, 0.4, 0.04), Vector3(0, 0.6, -0.35), frame)
    Flat.box(p, Vector3(0.3, 0.04, 0.04), Vector3(0, 0.82, -0.4), STEEL)


static func _bins(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    # NOTE (mristin):
    # The recycling bins, of course sorted: glass, paper, PET, metal.
    var colors := [Color("2a7a3a"), Color("2a4a9a"), Color("e8c020"), Color("8a8a8a")]
    for k in range(r.randi_range(2, 4)):
        Flat.box(p, Vector3(0.6, 1.0, 0.6), Vector3(0, 0.5, -0.9 + k * 0.65), colors[k])
        Flat.box(
            p, Vector3(0.62, 0.05, 0.62), Vector3(0, 1.02, -0.9 + k * 0.65), colors[k].darkened(0.3)
        )


static func _bollards(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    for k in range(r.randi_range(2, 4)):
        Flat.limb(p, 0.08, 0.08, 0.8, Vector3(0, 0.4, -1.0 + k * 0.7), STEEL, false, 6)
        Flat.limb(p, 0.085, 0.085, 0.08, Vector3(0, 0.65, -1.0 + k * 0.7), WHITE, false, 6)


static func _sign(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.03, 0.03, 2.2, Vector3(0, 1.1, 0), Color("9a9a9a"), false, 5)
    var face := Flat.limb(
        p,
        0.3,
        0.3,
        0.03,
        Vector3(0, 2.2, 0),
        RED if r.randf() < 0.5 else Color("2a5ab0"),
        false,
        12
    )
    face.rotation.z = PI * 0.5
    var text := Label3D.new()
    text.text = ["30", "50", "STOP", "P", "!"][r.randi() % 5]
    text.font_size = 120
    text.pixel_size = 0.003
    text.position = Vector3(0, 2.2, 0)
    text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    p.add_child(text)


static func _pigeons(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    for k in range(r.randi_range(2, 5)):
        var at := Vector3(r.randf_range(-0.6, 0.6), 0.12, r.randf_range(-0.6, 0.6))
        Flat.ball(p, 0.09, at, Color("8a8a96"), false, 0.8, 6, 4)
        Flat.ball(p, 0.05, at + Vector3(0, 0.08, -0.08), Color("6a6a7a"), false, 1.0, 5, 3)


static func _hydrant(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.12, 0.14, 0.7, Vector3(0, 0.35, 0), RED, false, 8)
    Flat.ball(p, 0.13, Vector3(0, 0.72, 0), RED, false, 0.8, 8, 4)
    Flat.limb(p, 0.05, 0.05, 0.35, Vector3(0, 0.45, 0), Color("c8c8c8"), false, 6).rotation.z = (
        PI * 0.5
    )


static func _flower_pot(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.3, 0.22, 0.4, Vector3(0, 0.2, 0), Color("b0603a"), false, 8)
    var colors := [Color("e05a7a"), Color("f2c14e"), Color("b04de8"), RED]
    for k in range(5):
        Flat.ball(
            p,
            0.09,
            Vector3(r.randf_range(-0.2, 0.2), 0.48, r.randf_range(-0.2, 0.2)),
            colors[r.randi() % colors.size()]
        )


static func _scooter(p: Node3D, r: RandomNumberGenerator, _side: float) -> void:
    var body := Color("e0e0e0") if r.randf() < 0.5 else Color("4ab0a0")
    Flat.box(p, Vector3(0.15, 0.05, 0.8), Vector3(0, 0.1, 0), body)
    Flat.limb(p, 0.02, 0.02, 1.0, Vector3(0, 0.6, -0.38), STEEL, false, 5)
    for z in [-0.38, 0.38]:
        var wheel := Flat.limb(p, 0.08, 0.08, 0.04, Vector3(0, 0.08, z), Color("1a1a1a"), false, 8)
        wheel.rotation.z = PI * 0.5


static func _car(p: Node3D, r: RandomNumberGenerator, side: float) -> void:
    var paint: Color = [
        RED, Color("2a4a9a"), Color("e0e0e0"), Color("1a1a1a"), Color("e8c020"), Color("4a7a4a")
    ][r.randi() % 6]
    p.position.x -= side * 1.4
    Flat.box(p, Vector3(1.7, 0.6, 4.0), Vector3(0, 0.55, 0), paint)
    Flat.box(p, Vector3(1.5, 0.55, 2.0), Vector3(0, 1.1, 0.2), paint)
    Flat.box(p, Vector3(1.52, 0.4, 1.8), Vector3(0, 1.1, 0.2), GLASS)
    for x in [-0.8, 0.8]:
        for z in [-1.3, 1.3]:
            var wheel := Flat.limb(
                p, 0.32, 0.32, 0.2, Vector3(x, 0.32, z), Color("1a1a1a"), false, 10
            )
            wheel.rotation.z = PI * 0.5


static func _tram_stop(p: Node3D, _r: RandomNumberGenerator, side: float) -> void:
    p.position.x -= side * 1.0
    Flat.box(p, Vector3(1.4, 0.08, 3.0), Vector3(0, 2.4, 0), STEEL)
    Flat.box(p, Vector3(0.04, 2.3, 3.0), Vector3(side * 0.7, 1.2, 0), Color("b8d8e8"))
    Flat.box(p, Vector3(0.4, 0.06, 2.0), Vector3(side * 0.4, 0.45, 0), Color("8a5a3a"))
    Flat.box(p, Vector3(0.05, 0.6, 0.9), Vector3(-side * 0.6, 2.0, 1.4), Color("2a5ab0"))
    var text := Label3D.new()
    text.text = "TRAM 4"
    text.font_size = 64
    text.pixel_size = 0.004
    text.position = Vector3(-side * 0.64, 2.0, 1.4)
    text.rotation.y = -side * PI * 0.5
    p.add_child(text)


static func _fountain(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 1.1, 1.2, 0.5, Vector3(0, 0.25, 0), Color("9a9a90"), false, 10)
    Flat.limb(p, 1.0, 1.0, 0.05, Vector3(0, 0.5, 0), Color("6aa8d8"), false, 10)
    Flat.limb(p, 0.12, 0.15, 1.8, Vector3(0, 1.2, 0), Color("9a9a90"), false, 8)
    # NOTE (mristin):
    # A statue on top: a figure with a flag, in colors.
    Flat.limb(p, 0.12, 0.15, 0.6, Vector3(0, 2.4, 0), Color("2a4a9a"), false, 6)
    Flat.ball(p, 0.1, Vector3(0, 2.8, 0), Color("e0b48e"))
    Flat.box(p, Vector3(0.03, 0.5, 0.4), Vector3(0.2, 3.0, 0), RED)


static func _kiosk(p: Node3D, _r: RandomNumberGenerator, side: float) -> void:
    Flat.box(p, Vector3(1.8, 2.2, 1.8), Vector3(0, 1.1, 0), Color("2a5a3a"))
    Flat.limb(p, 0.1, 1.5, 0.6, Vector3(0, 2.5, 0), Color("2a5a3a"), false, 8)
    Flat.box(p, Vector3(0.05, 0.8, 1.2), Vector3(-side * 0.92, 1.3, 0), Color("f0e8a0"))
    for k in range(3):
        Flat.box(
            p,
            Vector3(0.05, 0.35, 0.25),
            Vector3(-side * 0.95, 0.6, -0.4 + k * 0.4),
            [RED, Color("2a4a9a"), Color("e8c020")][k]
        )


static func _flag_pole(p: Node3D, _r: RandomNumberGenerator, _side: float) -> void:
    Flat.limb(p, 0.04, 0.06, 6.0, Vector3(0, 3.0, 0), WHITE, false, 6)
    Flat.box(p, Vector3(0.04, 1.0, 1.0), Vector3(0, 5.4, 0.55), RED)
    Flat.box(p, Vector3(0.05, 0.2, 0.6), Vector3(0, 5.4, 0.55), WHITE)
    Flat.box(p, Vector3(0.05, 0.6, 0.2), Vector3(0, 5.4, 0.55), WHITE)
