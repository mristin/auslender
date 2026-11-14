class_name Boxer
extends Node3D

## The player in a fight, in the first person: the camera at the height of his
## eyes, looking at the opponent, and his two red gloves in front of it.
##
## He stays on his spot (see DESIGN.md): leaning moves the camera to the
## side, ducking lowers it, and a jump lifts it. His arms (upper arm, elbow,
## forearm and glove with its thumb, as in 4D Sports Boxing) do not follow his
## body: they bounce in the guard, and every punch (as the classifier found
## it) plays its own animation, so that one sees which it was: a straight
## shoots out to the middle, turning the fist palm down; a hook swings across
## with the elbow up; an uppercut dips and rises, the palm towards him. The
## gloves cover the face while he covers his head. A kick lifts the knee and
## shoots the whole leg out to the opponent.

const MAX_HEALTH := 100.0

## Dressed as Auslender (scenes/camera_panel/model): blue gloves and the
## sleeves of his yellow suit.
const GLOVE := Color("2a5bd7")
const SLEEVE := Color("e2b328")
const SLEEVE_SHADE := Color("c39722")
const CUFF := Color("f2efe6")
## The thumb, a little lighter than the glove, so that it shows.
const THUMB := Color("3d6fe6")
const SHOE := Color("1e1b1a")
const SKIN := Color("d9a07a")
const SKIN_DARK := Color("b98264")
## The trousers of Auslender's yellow suit (they stand out against the dark
## ring), and their shade.
const SHORTS := Color("e2b328")
const TROUSERS_SHADE := Color("c39722")

## How many sides the arms and the gloves have (they are seen up close).
const ARM_SIDES := 16
const GLOVE_SIDES := 18

## How often he bounces on his feet in the guard (1/s).
const BOUNCE_HZ := 1.6

## Where the gloves rest in the guard, from the eyes (x for the right glove;
## the left is mirrored); they bounce a little there (see _rest()).
const GUARD := Vector3(0.15, -0.2, -0.5)

## The arms: where the shoulders are (from the eyes; x for the right, the left
## is mirrored), and how long the upper arm and the forearm are, in meters.
const SHOULDER := Vector3(0.22, -0.3, -0.02)
const UPPER_ARM := 0.34
const FOREARM := 0.4

## The legs: where the hips are, and how long the thigh and the shin are.
const HIP := Vector3(0.12, -0.75, 0.05)
const THIGH := 0.45
const SHIN := 0.45

## From the wrist to the middle of the glove, in meters.
const WRIST := 0.06

## How long each punch takes, in seconds.
const PUNCH_SECONDS := {"straight": 0.26, "hook": 0.38, "uppercut": 0.45}

## When in each punch (as a share of it) the glove strikes, which leaves a
## trail: so that one sees its path (a straight away, a hook across, an
## uppercut up).
const STRIKES := {"straight": [0.0, 0.5], "hook": [0.2, 0.62], "uppercut": [0.3, 0.55]}

## How long the trail behind a striking glove lasts, in seconds.
const TRAIL_SECONDS := 0.22

## How long a kick (the knee up and down) takes, in seconds.
const KICK_SECONDS := 0.65

## The height of the eyes, in meters.
const EYES := 1.62

## A full lean moves the eyes this far to the side, in meters.
const LEAN_SHIFT := 0.35

var health := MAX_HEALTH

## How far he leans, in [-1, 1]: negative to his left, positive to his right.
var lean := 0.0

## How far he ducks, in [0, 1].
var duck := 0.0

## Whether he is in a jump now.
var jumping := false

## Whether he holds both gloves up in front of his face.
var covering := false

var camera: Camera3D

var _gloves: Array[Node3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _elbows: Array[MeshInstance3D] = []
var _poles: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _punch_time: Array[float] = [-1.0, -1.0]
var _punch_kind: Array[String] = ["straight", "straight"]
var _trails: Array = [[], []]
var _trail_mesh := ImmediateMesh.new()
var _trail: MeshInstance3D
var _clock := 0.0
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _knees: Array[MeshInstance3D] = []
var _shoes: Array[MeshInstance3D] = []
var _kick_time: Array[float] = [-1.0, -1.0]
var _shake := 0.0
var _hurt := 0.0
var _jump_height := 0.0


func _ready() -> void:
    camera = Camera3D.new()
    camera.fov = 75.0
    camera.near = 0.05
    camera.position = Vector3(0, EYES, 0)
    camera.current = true
    add_child(camera)

    _trail = MeshInstance3D.new()
    var trail := _trail
    trail.mesh = _trail_mesh
    var trail_material := StandardMaterial3D.new()
    trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    trail_material.vertex_color_use_as_albedo = true
    trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    trail.material_override = trail_material
    camera.add_child(trail)

    for i in range(2):
        # NOTE (mristin):
        # The segments are tapered limbs of unit length (the narrow end at the
        # top), which _span() stretches and turns between two joints every
        # frame.
        # NOTE (mristin):
        # The arms and the gloves are seen up close, so they get more facets
        # than the rest of the flat-shaded world (still flat, but finer).
        _upper_arms.append(
            Flat.limb(camera, 0.05, 0.065, 1.0, Vector3.ZERO, SLEEVE_SHADE, false, ARM_SIDES)
        )
        _forearms.append(
            Flat.limb(camera, 0.04, 0.052, 1.0, Vector3.ZERO, SLEEVE, false, ARM_SIDES)
        )
        _elbows.append(
            Flat.ball(
                camera, 0.055, Vector3.ZERO, SLEEVE_SHADE, false, 1.0, ARM_SIDES, ARM_SIDES / 2
            )
        )

        var glove := Node3D.new()
        camera.add_child(glove)
        _make_glove(glove, 1.0 if i == 0 else -1.0)
        _gloves.append(glove)
        glove.position = _side(SHOULDER, i) + Vector3(0, 0.1, -0.5)

        _thighs.append(Flat.limb(camera, 0.07, 0.09, 1.0, Vector3.ZERO, SHORTS))
        _shins.append(Flat.limb(camera, 0.05, 0.065, 1.0, Vector3.ZERO, TROUSERS_SHADE))
        _knees.append(Flat.ball(camera, 0.072, Vector3.ZERO, SHORTS))
        _shoes.append(Flat.box(camera, Vector3(0.13, 0.11, 1.0), Vector3.ZERO, SHOE))


## Build a boxing glove under [param glove], from rounded parts: the padded
## back of the hand, the roll of the curled fingers in front of it, the thumb
## along its inner side, and the cuff with its band. Its local +y is the back of
## the hand and -z where the knuckles point (see _place_arm()); the thumb is
## on the side [param inner] (+1 for the left glove: its local +x; -1 for the
## right), towards the palm, so that one sees how the fist turns.
static func _make_glove(glove: Node3D, inner: float) -> void:
    var back := Flat.ball(glove, 0.062, Vector3(0, 0.006, 0.0), GLOVE, false, 1.0, GLOVE_SIDES, 12)
    back.scale = Vector3(0.95, 0.85, 1.2)
    var fingers := Flat.ball(
        glove, 0.052, Vector3(0, -0.018, -0.04), GLOVE, false, 1.0, GLOVE_SIDES, 12
    )
    fingers.scale = Vector3(1.0, 0.95, 0.85)
    # NOTE (mristin):
    # The thumb: long along the glove, from the wrist to the curled fingers,
    # its tip down towards the palm.
    var thumb := Flat.ball(
        glove, 0.022, Vector3(inner * 0.05, -0.03, -0.008), THUMB, false, 2.3, 12, 10
    )
    thumb.rotation = Vector3(-PI * 0.5 + 0.3, 0.0, inner * 0.3)
    # NOTE (mristin):
    # The cuff: a tapered sleeve of the glove (a limb along y, its narrow top
    # towards the elbow), with a light band at its end.
    var cuff := Flat.limb(
        glove, 0.043, 0.05, 0.09, Vector3(0, -0.004, 0.085), GLOVE, false, GLOVE_SIDES
    )
    cuff.rotation.x = PI * 0.5
    var band := Flat.limb(
        glove, 0.045, 0.047, 0.026, Vector3(0, -0.004, 0.112), CUFF, false, GLOVE_SIDES
    )
    band.rotation.x = PI * 0.5


## Start the fight again: full health, standing straight.
func reset() -> void:
    health = MAX_HEALTH
    lean = 0.0
    duck = 0.0
    jumping = false
    covering = false


## Look at the opponent at [param opponent], and set the eyes from the lean,
## the duck and the jump.
func face(opponent: Vector3, delta: float) -> void:
    _jump_height = lerpf(_jump_height, 0.25 if jumping else 0.0, minf(1.0, delta * 12.0))
    var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.03
    var eyes := Vector3(lean * LEAN_SHIFT, EYES - duck * 0.45 + _jump_height, 0)
    var look := opponent + Vector3(0, 1.45, 0)
    var body := _body_motion()
    camera.position = eyes + shake + (body[0] as Vector3)
    if camera.global_position.distance_to(look) > 0.1:
        camera.look_at(look, Vector3.UP)
    # NOTE (mristin):
    # Tilt the head a little into the lean, as one does when slipping a punch.
    camera.rotate_object_local(Vector3.BACK, -lean * 0.12 + float(body[3]))
    camera.rotate_object_local(Vector3.UP, float(body[1]))
    camera.rotate_object_local(Vector3.RIGHT, float(body[2]))


## How his body moves with his punches and kicks, as one sees it through his
## eyes (after the moves which Meshy animated for the hero): [the shift of the
## eyes, the turn about up, the tilt up, the roll]. A jab steps in and leans
## into the punch; a hook twists the body with the swing; an uppercut dips and
## rises; a kick leans back.
func _body_motion() -> Array:
    var shift := Vector3.ZERO
    var yaw := 0.0
    var pitch := 0.0
    var roll := 0.0
    for i in range(2):
        var sign_x := -1.0 if i == 0 else 1.0
        if _punch_time[i] >= 0.0:
            var p := minf(1.0, _punch_time[i] / float(PUNCH_SECONDS[_punch_kind[i]]))
            var s := sin(p * PI)
            match _punch_kind[i]:
                "straight":
                    shift += Vector3(sign_x * 0.03, 0.0, -0.08) * s
                    roll += -sign_x * 0.05 * s
                "hook":
                    # NOTE (mristin):
                    # A left hook turns him to the right, a right one to the left.
                    yaw += sign_x * 0.12 * s
                    shift += Vector3(sign_x * 0.03, 0.0, -0.03) * s
                "uppercut":
                    var dip := smoothstep(0.0, 0.3, p) * (1.0 - smoothstep(0.3, 0.55, p))
                    var rise := smoothstep(0.3, 0.55, p) * (1.0 - smoothstep(0.66, 1.0, p))
                    shift += Vector3(0.0, -0.05 * dip + 0.03 * rise, -0.03 * rise)
                    pitch += 0.04 * rise
        if _kick_time[i] >= 0.0:
            var k := sin(minf(1.0, _kick_time[i] / KICK_SECONDS) * PI)
            shift += Vector3(0.0, 0.03, 0.08) * k
    return [shift, yaw, pitch, roll]


## Throw the punch with the hand (0 left, 1 right).
func punch(side: int, kind: String) -> void:
    _punch_time[side] = 0.0
    _punch_kind[side] = kind if PUNCH_SECONDS.has(kind) else "straight"


## Show the kick of the leg (0 left, 1 right): the knee up, then the whole leg out.
func kick(side: int) -> void:
    _kick_time[side] = 0.0


## Take the damage of a hit: shake and flash (less if it only hit the gloves).
func take_damage(damage: float, covered := false) -> void:
    health = maxf(0.0, health - damage)
    _shake = 0.4 if covered else 1.0
    _hurt = 0.3 if covered else 1.0


## How red the screen flashes now, in [0, 1].
func hurt() -> float:
    return _hurt


func _process(delta: float) -> void:
    _clock += delta
    _shake = maxf(0.0, _shake - delta * 3.0)
    _hurt = maxf(0.0, _hurt - delta * 2.0)
    for i in range(2):
        _place_arm(i, delta)
        _place_leg(i, delta)
    _draw_trails()


## Draw the trails behind the striking gloves: strips which fade and narrow
## with their age, facing the camera.
func _draw_trails() -> void:
    _trail_mesh.clear_surfaces()
    for i in range(2):
        var trail: Array = _trails[i]
        while not trail.is_empty() and _clock - float(trail[0][1]) > TRAIL_SECONDS:
            trail.pop_front()
        if trail.size() < 2:
            continue
        _trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
        for k in range(trail.size()):
            var point: Vector3 = trail[k][0]
            var age := clampf((_clock - float(trail[k][1])) / TRAIL_SECONDS, 0.0, 1.0)
            var before: Vector3 = trail[maxi(k - 1, 0)][0]
            var after: Vector3 = trail[mini(k + 1, trail.size() - 1)][0]
            # NOTE (mristin):
            # Across the path, as seen from the camera (which looks along -z).
            var across := (after - before).cross(Vector3.BACK)
            if across.length_squared() < 1e-8:
                across = Vector3.UP
            # NOTE (mristin):
            # Narrower close to the camera, so that a close glove's trail does
            # not cover the view.
            var near := clampf(-point.z / 0.6, 0.35, 1.0)
            across = across.normalized() * 0.075 * near * (1.0 - 0.6 * age)
            _trail_mesh.surface_set_color(Color(1.0, 0.62, 0.2, 0.85 * (1.0 - age)))
            _trail_mesh.surface_add_vertex(point + across)
            _trail_mesh.surface_add_vertex(point - across)
        _trail_mesh.surface_end()


## Mirror a point of the right side (x > 0) to the side i (0 left, 1 right).
static func _side(point: Vector3, i: int) -> Vector3:
    return Vector3(-point.x if i == 0 else point.x, point.y, point.z)


## The middle joint of a limb of two segments (e.g., the elbow) from its ends,
## bent towards [param pole]: the two-bone inverse kinematics.
static func bend(
    start: Vector3, end: Vector3, first: float, second: float, pole: Vector3
) -> Vector3:
    var reach := end - start
    var distance := clampf(reach.length(), absf(first - second) + 0.001, first + second - 0.001)
    var along := reach.normalized()
    var a := (first * first - second * second + distance * distance) / (2.0 * distance)
    var h := sqrt(maxf(0.0, first * first - a * a))
    var side := pole - along * along.dot(pole)
    if side.length_squared() < 1e-6:
        side = Vector3.DOWN
    return start + along * a + side.normalized() * h


## Stretch and turn a segment of unit length between two joints: a limb (along
## y, its narrow top at b), or a box (along z).
static func _span(segment: MeshInstance3D, a: Vector3, b: Vector3, limb := true) -> void:
    var length := a.distance_to(b)
    if length < 1e-4:
        segment.visible = false
        return
    segment.visible = true
    var forward := (b - a) / length
    var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.BACK
    # NOTE (mristin):
    # Scale along the bone (in its own frame), not along the camera's z.
    var turned := Basis.looking_at(forward, up)
    if limb:
        # NOTE (mristin):
        # Turn the limb's y onto the bone (-z of the turned basis).
        segment.basis = (
            turned * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(1, length, 1))
        )
    else:
        segment.basis = turned * Basis.from_scale(Vector3(1, 1, length))
    segment.position = (a + b) * 0.5


## Where the glove rests: in the guard, bouncing lightly with his steps (the
## gloves a little out of step, and a little forward and back), or in front
## of the face while he covers.
func _rest(i: int) -> Vector3:
    var sign_x := -1.0 if i == 0 else 1.0
    if covering:
        # NOTE (mristin):
        # The gloves cover the face, close together, so that the player sees
        # that the cover counts.
        return Vector3(0.065 * sign_x, -0.04, -0.3)
    var step := _clock * BOUNCE_HZ * TAU + i * 0.8
    return (
        _side(GUARD, i)
        + Vector3(0.006 * sin(step * 0.5), 0.012 * sin(step), 0.015 * sin(step * 0.5 + 1.2))
    )


## Where the glove is during a punch at the share p of it, and where the elbow
## points: each punch has its own path.
func _punch_path(i: int, kind: String, p: float, rest: Vector3) -> Array:
    match kind:
        "hook":
            return _hook_path(i, p, rest)
        "uppercut":
            return _uppercut_path(i, p, rest)
    # NOTE (mristin):
    # A straight: right out to the middle, and back.
    var sign_x := -1.0 if i == 0 else 1.0
    var far := Vector3(-sign_x * 0.05, -0.1, -0.75)
    return [rest.lerp(far, sin(p * PI)), Vector3(sign_x * 0.5, -1.0, 0.0)]


## A hook: out to the side, then a wide swing across at the height of the
## chin, with the elbow up; then back.
func _hook_path(i: int, p: float, rest: Vector3) -> Array:
    var sign_x := -1.0 if i == 0 else 1.0
    var shoulder := _side(SHOULDER, i)
    var pole := Vector3(sign_x, 0.5, -0.1)
    var glove: Vector3
    if p < 0.2:
        glove = rest.lerp(shoulder + _arc(sign_x, 0.95), smoothstep(0.0, 1.0, p / 0.2))
    elif p < 0.6:
        glove = shoulder + _arc(sign_x, lerpf(0.95, -0.5, smoothstep(0.0, 1.0, (p - 0.2) / 0.4)))
    else:
        var swing_end := shoulder + _arc(sign_x, -0.5)
        glove = swing_end.lerp(rest, smoothstep(0.0, 1.0, (p - 0.6) / 0.4))
    return [glove, pole]


## An uppercut, close to the body and from the bottom up, with the arm bent:
## the glove drops to his belly (below the view), then shoots straight up just
## in front of him, to above the height of his eyes, the forearm upright under
## it and the elbow tucked in at his body; a moment there, then back. Besides
## the glove and the pole, it gives where the elbow is, and how much that
## counts (it blends in and out, so that the arm does not jump).
func _uppercut_path(i: int, p: float, rest: Vector3) -> Array:
    var sign_x := -1.0 if i == 0 else 1.0
    var pole := Vector3(sign_x * 0.2, -1.0, 0.5)
    var low := Vector3(sign_x * 0.06, -0.38, -0.3)
    var chin := Vector3(-sign_x * 0.02, 0.1, -0.34)
    var glove: Vector3
    var bent := 1.0
    if p < 0.3:
        bent = smoothstep(0.0, 1.0, p / 0.3)
        glove = rest.lerp(low, bent)
    elif p < 0.48:
        # NOTE (mristin):
        # Fast at the start, as a punch: ease out only.
        var t := (p - 0.3) / 0.18
        glove = low.lerp(chin, 1.0 - (1.0 - t) * (1.0 - t))
    elif p < 0.66:
        glove = chin
    else:
        bent = 1.0 - smoothstep(0.0, 1.0, (p - 0.66) / 0.34)
        glove = chin.lerp(rest, 1.0 - bent)
    # NOTE (mristin):
    # The elbow right under the glove (a little out and back): the forearm
    # stands upright, which tells an uppercut from a straight.
    var elbow := glove + Vector3(sign_x * 0.05, -FOREARM * 0.9, 0.03)
    return [glove, pole, elbow, bent]


## A point on the swing of a hook around the shoulder, at the angle (0 straight
## ahead, positive out to the side), at the height of the chin.
static func _arc(sign_x: float, angle: float) -> Vector3:
    var radius := 0.6
    return Vector3(sign_x * radius * sin(angle), 0.2, -radius * cos(angle))


func _place_arm(i: int, delta: float) -> void:
    var rest := _rest(i)
    var pole := Vector3(-1.0 if i == 0 else 1.0, -1.0, 0.1) * 0.5 + Vector3.DOWN * 0.5
    var glove := _gloves[i]
    var elbow_override := Vector3.ZERO
    var elbow_weight := 0.0
    if _punch_time[i] >= 0.0:
        var seconds: float = PUNCH_SECONDS[_punch_kind[i]]
        _punch_time[i] += delta
        var p := minf(1.0, _punch_time[i] / seconds)
        var path := _punch_path(i, _punch_kind[i], p, rest)
        glove.position = path[0]
        pole = path[1]
        if path.size() > 2:
            elbow_override = path[2]
            elbow_weight = path[3]
        var strike: Array = STRIKES[_punch_kind[i]]
        if p >= strike[0] and p <= strike[1]:
            _trails[i].append([glove.position, _clock])
        if p >= 1.0:
            _punch_time[i] = -1.0
    else:
        glove.position = glove.position.lerp(rest, minf(1.0, delta * 14.0))
    _poles[i] = _poles[i].lerp(pole, minf(1.0, delta * 20.0))

    var shoulder := _side(SHOULDER, i)
    # NOTE (mristin):
    # The glove can not go farther than the arm reaches.
    var reach := glove.position - shoulder
    if reach.length() > UPPER_ARM + FOREARM + WRIST:
        glove.position = shoulder + reach.normalized() * (UPPER_ARM + FOREARM + WRIST)
    # NOTE (mristin):
    # Bend the arm to the glove itself (the forearm and the wrist reach it),
    # and put the wrist on the line from the elbow to the glove: so that the
    # glove flows straight out of the forearm, in a hook, too.
    var elbow := bend(shoulder, glove.position, UPPER_ARM, FOREARM + WRIST, _poles[i])
    if elbow_weight > 0.0:
        elbow = elbow.lerp(elbow_override, elbow_weight)
    var wrist := glove.position + (elbow - glove.position).normalized() * WRIST
    _span(_upper_arms[i], shoulder, elbow)
    _span(_forearms[i], elbow, wrist)
    _elbows[i].position = elbow
    # NOTE (mristin):
    # The glove points along the forearm, and turns about it with the hand:
    # its local +y is the back of the hand (the thumb sits on its side, see
    # _ready), so that the thumb is where it is in each punch.
    var along := (glove.position - elbow).normalized()
    var back := _back_of_hand(i)
    if absf(along.dot(back)) > 0.95:
        back = Vector3.BACK if absf(along.dot(Vector3.BACK)) < 0.95 else Vector3.UP
    glove.basis = Basis.looking_at(along, back)


## Where the back of the hand faces (in the camera's axes): an upright fist in
## the guard (the palms facing each other); turned over, palm down, in a
## straight and a hook; the palm towards him in an uppercut; the back of the
## hands to the opponent while he covers.
func _back_of_hand(i: int) -> Vector3:
    var outwards := -1.0 if i == 0 else 1.0
    var back := Vector3(outwards, 0.35, 0.0).normalized()
    if covering:
        back = Vector3.FORWARD
    if _punch_time[i] < 0.0:
        return back
    var kind := _punch_kind[i]
    var p := minf(1.0, _punch_time[i] / float(PUNCH_SECONDS[kind]))
    match kind:
        "uppercut":
            # NOTE (mristin):
            # Turned while it drops, held up, turned back on the way home.
            var turned := smoothstep(0.0, 0.3, p) * (1.0 - smoothstep(0.66, 1.0, p))
            return back.slerp(Vector3.FORWARD, turned)
        "hook":
            return back.slerp(
                Vector3.UP, sin(minf(1.0, p / 0.62) * PI * 0.5) * (1.0 - smoothstep(0.62, 1.0, p))
            )
    return back.slerp(Vector3.UP, sin(p * PI))


## The leg: standing below the view, or kicking: the knee comes up, the leg
## shoots out straight to the opponent (the shoe in the middle of the view),
## and comes back.
func _place_leg(i: int, delta: float) -> void:
    var hip := _side(HIP, i)
    var inward := 1.0 if i == 0 else -1.0
    var standing := hip + Vector3(-0.02 * inward, -0.86, -0.05)
    var foot := standing
    var pole := Vector3.FORWARD
    if _kick_time[i] >= 0.0:
        _kick_time[i] += delta
        var p := minf(1.0, _kick_time[i] / KICK_SECONDS)
        var chamber := hip + Vector3(0.03 * inward, -0.2, -0.35)
        var out := hip + Vector3(0.1 * inward, 0.55, -0.8)
        if p < 0.3:
            foot = standing.lerp(chamber, smoothstep(0.0, 1.0, p / 0.3))
        elif p < 0.55:
            foot = chamber.lerp(out, smoothstep(0.0, 1.0, (p - 0.3) / 0.25))
        elif p < 0.7:
            foot = out
        else:
            foot = out.lerp(standing, smoothstep(0.0, 1.0, (p - 0.7) / 0.3))
        # NOTE (mristin):
        # The knee bends up and forward, as in a front kick.
        pole = Vector3(0, 0.6, -1.0)
        if p >= 1.0:
            _kick_time[i] = -1.0
    var knee := bend(hip, foot, THIGH, SHIN, pole)
    var reach := foot - hip
    if reach.length() > THIGH + SHIN:
        foot = hip + reach.normalized() * (THIGH + SHIN)
    _span(_thighs[i], hip, knee)
    _span(_shins[i], knee, foot)
    _knees[i].position = knee
    # NOTE (mristin):
    # The shoe at the end of the shin, its sole to where the leg points.
    var along := (foot - knee).normalized()
    _span(_shoes[i], foot - along * 0.02, foot + along * 0.12, false)
