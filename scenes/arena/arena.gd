class_name Arena
extends Node3D

## Build the boxing ring and the hall around it out of flat-shaded boxes: the
## canvas, the apron, the four corner posts, three ropes on each side, the
## crowd on the dark stands and the lights above.

## The ropes stand this far from the middle, in meters.
const HALF := 3.0

## The boxers stay this far within the ropes, in meters.
const INSIDE := HALF - 0.35

const CANVAS := Color("8fa3b8")
const APRON := Color("2f4b7c")
const FLOOR := Color("1a1d26")
const ROPE := Color("e9e3d3")
const POST_RED := Color("b8312f")
const POST_BLUE := Color("2b59a8")
const POST_WHITE := Color("dad6cc")


func _ready() -> void:
    _build_ring()
    _build_hall()
    _build_lights()


## Keep the point on the floor within the ropes.
static func clamp_inside(point: Vector3) -> Vector3:
    return Vector3(clampf(point.x, -INSIDE, INSIDE), point.y, clampf(point.z, -INSIDE, INSIDE))


func _build_ring() -> void:
    # NOTE (mristin):
    # The ring floor is at y = 0, so the boxers stand on it; the platform
    # goes down to the floor of the hall.
    Flat.box(self, Vector3(HALF * 2.0 + 0.6, 0.06, HALF * 2.0 + 0.6), Vector3(0, -0.03, 0), CANVAS)
    Flat.box(self, Vector3(HALF * 2.0 + 0.9, 1.0, HALF * 2.0 + 0.9), Vector3(0, -0.56, 0), APRON)

    var corners := [
        [Vector3(-HALF, 0, -HALF), POST_RED],
        [Vector3(HALF, 0, -HALF), POST_WHITE],
        [Vector3(HALF, 0, HALF), POST_BLUE],
        [Vector3(-HALF, 0, HALF), POST_WHITE],
    ]
    for corner in corners:
        var at: Vector3 = corner[0]
        Flat.post(self, 0.07, 1.5, at + Vector3(0, 0.75, 0), corner[1])
        Flat.box(self, Vector3(0.2, 0.18, 0.2), at + Vector3(0, 1.45, 0), corner[1])

    for height in [0.55, 0.95, 1.35]:
        for i in range(4):
            var a: Vector3 = corners[i][0]
            var b: Vector3 = corners[(i + 1) % 4][0]
            var middle := (a + b) * 0.5 + Vector3(0, height, 0)
            var length := a.distance_to(b)
            var size := Vector3(length, 0.035, 0.035)
            if absf(a.x - b.x) < 0.01:
                size = Vector3(0.035, 0.035, length)
            Flat.box(self, size, middle, ROPE)


func _build_hall() -> void:
    Flat.box(self, Vector3(40, 0.1, 40), Vector3(0, -1.1, 0), FLOOR)

    # NOTE (mristin):
    # The crowd: rows of seated people on stands which rise away from the
    # ring, each a torso and a head in a random color; the seed keeps the hall
    # the same every time.
    var random := RandomNumberGenerator.new()
    random.seed = 1991
    var shirts := [
        Color("6d2f2f"),
        Color("2f4f6d"),
        Color("4f6d2f"),
        Color("6d5a2f"),
        Color("4a3a5e"),
        Color("5e5e5e"),
        Color("7a4a2a"),
    ]
    var skins := [Color("d9a57a"), Color("a8714a"), Color("e8c3a0"), Color("6b4428")]
    for side in range(4):
        for row in range(4):
            var distance := HALF + 2.2 + row * 1.1
            var height := -0.6 + row * 0.55
            var stand := Vector3(distance * 2.0 + 2.0, 0.5, 1.0)
            var place := Vector3(0, height - 0.25, -distance)
            _rotated_box(stand, place, side, Color("252a38"))
            var count := 14 + row * 3
            for i in range(count):
                if random.randf() < 0.15:
                    continue
                var x := lerpf(-distance, distance, (i + 0.5) / count) + random.randf_range(-0.1, 0.1)
                var shirt: Color = shirts[random.randi() % shirts.size()]
                var skin: Color = skins[random.randi() % skins.size()]
                _rotated_box(Vector3(0.38, 0.5, 0.25), Vector3(x, height + 0.25, -distance), side, shirt)
                _rotated_box(Vector3(0.2, 0.22, 0.2), Vector3(x, height + 0.65, -distance), side, skin)


## Add a box on the side of the hall: 0 behind the ring, then clockwise.
func _rotated_box(size: Vector3, at: Vector3, side: int, color: Color) -> void:
    var angle := side * PI * 0.5
    var turned := at.rotated(Vector3.UP, angle)
    var instance := Flat.box(self, size, turned, color)
    instance.rotation.y = angle


func _build_lights() -> void:
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, 35, 0)
    sun.light_energy = 1.1
    add_child(sun)

    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-30, -140, 0)
    fill.light_energy = 0.35
    add_child(fill)

    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color("0c0e14")
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color("6a7088")
    settings.ambient_light_energy = 0.6
    environment.environment = settings
    add_child(environment)

    # NOTE (mristin):
    # The lamps over the ring, only for the look.
    for x in [-1.5, 1.5]:
        for z in [-1.5, 1.5]:
            Flat.box(self, Vector3(0.6, 0.15, 0.6), Vector3(x, 5.0, z), Color("f4eccc"))
