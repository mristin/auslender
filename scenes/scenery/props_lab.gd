class_name PropsLab
extends RefCounted

## The equipment of the Rochartis laboratory (see Scenery): on the benches,
## microscopes, centrifuges, racks of test tubes, flasks, screens and pill
## machines; along the walls, fume hoods, gas cylinders, server racks, a water
## cooler, plants, fire extinguishers, a robot arm, cabinets and sinks; and on
## the walls, posters and whiteboards (of the shareholder value). Each varied
## at random.

const STEEL := Color("9aa4ae")
const STEEL_DARK := Color("5a646e")
const WHITE := Color("f4f6f8")
const TOP := Color("2a3038")
const FLASKS := [
    Color("5fd3e6"),
    Color("b04de8"),
    Color("6ccf5e"),
    Color("f2c14e"),
    Color("e05a5a"),
    Color("f08ac0"),
]
const POSTERS := [
    "SHAREHOLDER VALUE",
    "PROFIT IS HEALTH",
    "TRIAL 7: SIDE EFFECTS? WHAT SIDE EFFECTS?",
    "BONUS GOALS Q4",
    "A PILL FOR EVERY ILL",
    "NOW 30% MORE EXPENSIVE",
    "CLEAN HANDS, CLEAN BOOKS",
]


## Something on a bench (its top at the prop's origin).
static func on_bench(p: Node3D, r: RandomNumberGenerator) -> void:
    var builders := [
        _microscope,
        _centrifuge,
        _rack,
        _flasks,
        _flasks,
        _screen,
        _pill_machine,
        _scale,
        _burner,
        _pipettes,
    ]
    (builders[r.randi() % builders.size()] as Callable).call(p, r)


## Something standing on the floor by a wall.
static func by_wall(p: Node3D, r: RandomNumberGenerator) -> void:
    var builders := [
        _fume_hood,
        _cylinders,
        _server,
        _cooler,
        _plant,
        _extinguisher,
        _robot_arm,
        _cabinet,
        _sink,
        _fridge,
    ]
    (builders[r.randi() % builders.size()] as Callable).call(p, r)


## Something on a wall: a poster or a whiteboard (facing +x; turn it).
static func on_wall(p: Node3D, r: RandomNumberGenerator) -> void:
    if r.randf() < 0.5:
        Flat.box(p, Vector3(0.04, 1.0, 1.6), Vector3.ZERO, WHITE)
        # NOTE (mristin):
        # A chart which only goes up.
        var points := [
            Vector2(-0.6, -0.3), Vector2(-0.2, -0.1), Vector2(0.2, 0.0), Vector2(0.6, 0.35)
        ]
        for k in range(points.size() - 1):
            var a: Vector2 = points[k]
            var b: Vector2 = points[k + 1]
            var line := Flat.box(
                p,
                Vector3(0.02, 0.03, a.distance_to(b)),
                Vector3(0.03, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5),
                Color("2a9a4a")
            )
            line.rotation.x = -atan2(b.y - a.y, b.x - a.x)
    else:
        var color: Color = FLASKS[r.randi() % FLASKS.size()]
        Flat.box(p, Vector3(0.03, 1.2, 0.9), Vector3.ZERO, color.lightened(0.5))
        var label := Label3D.new()
        label.text = POSTERS[r.randi() % POSTERS.size()]
        label.font_size = 40
        label.width = 400
        label.autowrap_mode = TextServer.AUTOWRAP_WORD
        label.pixel_size = 0.0018
        label.modulate = Color("1a2a3a")
        label.position = Vector3(0.03, 0, 0)
        label.rotation.y = PI * 0.5
        p.add_child(label)


static func _flask(p: Node3D, at: Vector3, color: Color, r: RandomNumberGenerator) -> void:
    var size := r.randf_range(0.7, 1.3)
    Flat.limb(
        p, 0.03 * size, 0.09 * size, 0.2 * size, at + Vector3(0, 0.1 * size, 0), color, false, 8
    )
    Flat.limb(
        p,
        0.025 * size,
        0.025 * size,
        0.12 * size,
        at + Vector3(0, 0.25 * size, 0),
        Color("d8e4ea"),
        false,
        8
    )


static func _flasks(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(2, 5)):
        _flask(
            p,
            Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.6, 0.6)),
            FLASKS[r.randi() % FLASKS.size()],
            r
        )


static func _microscope(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.25, 0.04, 0.3), Vector3(0, 0.02, 0), STEEL_DARK)
    var arm := Flat.box(p, Vector3(0.06, 0.35, 0.06), Vector3(0, 0.2, 0.1), WHITE)
    arm.rotation.x = -0.2
    var tube := Flat.limb(p, 0.03, 0.04, 0.25, Vector3(0, 0.3, 0.0), STEEL_DARK, false, 8)
    tube.rotation.x = 0.4
    Flat.box(p, Vector3(0.16, 0.02, 0.16), Vector3(0, 0.15, -0.02), STEEL)


static func _centrifuge(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.45, 0.3, 0.45), Vector3(0, 0.15, 0), WHITE)
    Flat.limb(p, 0.18, 0.18, 0.03, Vector3(0, 0.31, 0), Color("4a8ac0"), false, 12)
    Flat.box(p, Vector3(0.02, 0.06, 0.12), Vector3(-0.23, 0.2, 0.1), Color("2ac04a"))


static func _rack(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.18, 0.12, 0.6), Vector3(0, 0.06, 0), STEEL)
    for k in range(6):
        var color: Color = FLASKS[r.randi() % FLASKS.size()]
        Flat.limb(p, 0.018, 0.018, 0.22, Vector3(0, 0.17, -0.25 + k * 0.1), color, false, 6)


static func _screen(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.12, 0.25, 0.12), Vector3(0, 0.12, 0), STEEL_DARK)
    Flat.box(p, Vector3(0.05, 0.4, 0.65), Vector3(0, 0.45, 0), Color("1a1e24"))
    var glow := Color("2ac0a0") if r.randf() < 0.5 else Color("4a8ae0")
    Flat.box(p, Vector3(0.01, 0.34, 0.58), Vector3(-0.03, 0.45, 0), glow)
    Flat.box(p, Vector3(0.2, 0.02, 0.45), Vector3(-0.3, 0.01, 0), Color("2a2a30"))


static func _pill_machine(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.5, 0.4, 0.5), Vector3(0, 0.2, -0.3), STEEL)
    Flat.limb(p, 0.12, 0.2, 0.25, Vector3(0, 0.55, -0.3), STEEL_DARK, false, 8)
    Flat.box(p, Vector3(0.3, 0.05, 0.9), Vector3(0, 0.1, 0.35), Color("2a2a30"))
    for k in range(5):
        var pill := Flat.limb(
            p,
            0.025,
            0.025,
            0.07,
            Vector3(0, 0.15, 0.05 + k * 0.15),
            FLASKS[r.randi() % FLASKS.size()],
            false,
            6
        )
        pill.rotation.x = PI * 0.5


static func _scale(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.3, 0.08, 0.3), Vector3(0, 0.04, 0), WHITE)
    Flat.box(p, Vector3(0.22, 0.2, 0.22), Vector3(0, 0.2, 0), Color(0.85, 0.92, 0.96))
    Flat.box(p, Vector3(0.02, 0.05, 0.12), Vector3(-0.16, 0.05, 0), Color("2a2a30"))


static func _burner(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.05, 0.06, 0.15, Vector3(0, 0.07, 0), STEEL_DARK, false, 8)
    Flat.limb(p, 0.005, 0.04, 0.12, Vector3(0, 0.2, 0), Color("4a8af0"), false, 6)
    for k in range(3):
        Flat.limb(
            p,
            0.008,
            0.008,
            0.35,
            Vector3(cos(k * TAU / 3.0) * 0.1, 0.17, sin(k * TAU / 3.0) * 0.1),
            STEEL,
            false,
            4
        )
    Flat.limb(p, 0.12, 0.12, 0.01, Vector3(0, 0.34, 0), STEEL, false, 8)


static func _pipettes(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.12, 0.25, 0.3), Vector3(0, 0.12, 0), WHITE)
    for k in range(3):
        var pipette := Flat.limb(
            p,
            0.01,
            0.02,
            0.3,
            Vector3(0, 0.38, -0.08 + k * 0.08),
            FLASKS[r.randi() % FLASKS.size()],
            false,
            5
        )
        pipette.rotation.x = 0.1


static func _fume_hood(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(1.0, 0.9, 1.8), Vector3(0, 0.45, 0), STEEL)
    Flat.box(p, Vector3(1.0, 1.4, 1.8), Vector3(0, 1.6, 0), WHITE)
    Flat.box(p, Vector3(0.03, 0.8, 1.6), Vector3(-0.5, 1.45, 0), Color(0.75, 0.88, 0.95))
    Flat.box(p, Vector3(0.6, 0.6, 0.6), Vector3(0, 2.6, 0), STEEL)


static func _cylinders(p: Node3D, r: RandomNumberGenerator) -> void:
    var colors := [Color("2a6ab0"), Color("2a8a3a"), Color("c8c8c8"), Color("e8a020")]
    for k in range(r.randi_range(2, 4)):
        var color: Color = colors[r.randi() % colors.size()]
        Flat.limb(p, 0.13, 0.13, 1.4, Vector3(0, 0.7, -0.5 + k * 0.32), color, false, 8)
        Flat.ball(p, 0.13, Vector3(0, 1.4, -0.5 + k * 0.32), color, false, 0.8, 8, 4)
        Flat.limb(p, 0.03, 0.03, 0.15, Vector3(0, 1.55, -0.5 + k * 0.32), STEEL_DARK, false, 5)


static func _server(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.8, 2.0, 0.7), Vector3(0, 1.0, 0), Color("1a1e24"))
    for k in range(8):
        var light := Color("2ac04a") if r.randf() < 0.7 else Color("e05a5a")
        Flat.box(p, Vector3(0.02, 0.03, 0.03), Vector3(-0.41, 0.3 + k * 0.2, 0.2), light)


static func _cooler(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.4, 1.0, 0.4), Vector3(0, 0.5, 0), WHITE)
    Flat.limb(p, 0.15, 0.15, 0.45, Vector3(0, 1.25, 0), Color("8ac8f0"), false, 10)


static func _plant(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.2, 0.15, 0.4, Vector3(0, 0.2, 0), WHITE, false, 8)
    for k in range(r.randi_range(4, 7)):
        var leaf := Flat.box(p, Vector3(0.05, 0.6, 0.15), Vector3(0, 0.7, 0), Color("3f8a30"))
        leaf.rotation = Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5))


static func _extinguisher(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.09, 0.09, 0.55, Vector3(0, 0.6, 0), Color("d0282a"), false, 8)
    Flat.limb(p, 0.03, 0.04, 0.12, Vector3(0, 0.95, 0), Color("2a2a30"), false, 6)
    Flat.box(p, Vector3(0.05, 0.4, 0.3), Vector3(0.1, 1.4, 0), Color("d0282a"))


static func _robot_arm(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.25, 0.3, 0.3, Vector3(0, 0.15, 0), Color("e8a020"), false, 10)
    var upper := Flat.limb(p, 0.08, 0.1, 0.9, Vector3(0, 0.7, 0.15), Color("e8a020"), false, 8)
    upper.rotation.x = 0.4
    Flat.ball(p, 0.11, Vector3(0, 1.1, 0.35), STEEL_DARK)
    var lower := Flat.limb(p, 0.06, 0.08, 0.7, Vector3(0, 1.15, 0.0), Color("e8a020"), false, 8)
    lower.rotation.x = -1.2
    Flat.box(p, Vector3(0.12, 0.1, 0.12), Vector3(0, 0.95, -0.35), STEEL_DARK)


static func _cabinet(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.6, 2.0, 1.2), Vector3(0, 1.0, 0), WHITE)
    for k in range(4):
        Flat.box(p, Vector3(0.03, 0.02, 1.1), Vector3(-0.3, 0.4 + k * 0.45, 0), STEEL)
        for b in range(3):
            if r.randf() < 0.6:
                Flat.box(
                    p,
                    Vector3(0.25, 0.25, 0.25),
                    Vector3(-0.15, 0.55 + k * 0.45, -0.35 + b * 0.35),
                    FLASKS[r.randi() % FLASKS.size()].lightened(0.4)
                )


static func _sink(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.7, 0.9, 1.0), Vector3(0, 0.45, 0), STEEL)
    Flat.box(p, Vector3(0.5, 0.1, 0.7), Vector3(0, 0.88, 0), STEEL_DARK)
    var tap := Flat.limb(p, 0.02, 0.02, 0.4, Vector3(0.2, 1.1, 0), STEEL, false, 6)
    tap.rotation.z = 0.3


static func _fridge(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(0.8, 1.9, 0.8), Vector3(0, 0.95, 0), WHITE)
    Flat.box(p, Vector3(0.02, 1.6, 0.6), Vector3(-0.41, 1.0, 0), Color(0.8, 0.9, 0.95))
    var label := Label3D.new()
    label.text = "SAMPLES\nDO NOT EAT"
    label.font_size = 36
    label.pixel_size = 0.002
    label.modulate = Color("d0282a")
    label.position = Vector3(-0.43, 1.6, 0)
    label.rotation.y = -PI * 0.5
    p.add_child(label)
