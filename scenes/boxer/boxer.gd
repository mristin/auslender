class_name Boxer
extends Node3D

## The player in a fight, in the first person: the camera at the height of her
## eyes, looking at the opponent, and her two red gloves in front of it.
##
## She stays on her spot (see DESIGN.md): leaning moves the camera to the
## side, ducking lowers it, and a jump lifts it. Her arms (upper arm, elbow,
## forearm and glove, as in 4D Sports Boxing) follow her hands in the camera
## picture, and every punch takes its own path, so that one sees which it was:
## a straight shoots out to the middle, a hook swings across with the elbow up,
## an uppercut dips and rises. The gloves cover the face while she covers her
## head. A kick lifts the knee and shoots the whole leg out to the opponent.

const MAX_HEALTH := 100.0

const GLOVE := Color("c8302c")
const CUFF := Color("f2efe6")
const SHOE := Color("f2efe6")
const SKIN := Color("d9a07a")
const SKIN_DARK := Color("b98264")
## The shorts: light, so that the legs stand out against the dark ring.
const SHORTS := Color("e9c46a")

## The arms: where the shoulders are (from the eyes; x for the right, the left
## is mirrored), and how long the upper arm and the forearm are, in meters.
const SHOULDER := Vector3(0.22, -0.3, -0.02)
const UPPER_ARM := 0.34
const FOREARM := 0.36

## The legs: where the hips are, and how long the thigh and the shin are.
const HIP := Vector3(0.12, -0.75, 0.05)
const THIGH := 0.45
const SHIN := 0.45

## How long each punch takes, in seconds.
const PUNCH_SECONDS := {"straight": 0.26, "hook": 0.38, "uppercut": 0.38}

## How long a kick (the knee up and down) takes, in seconds.
const KICK_SECONDS := 0.65

## The height of the eyes, in meters.
const EYES := 1.62

## A full lean moves the eyes this far to the side, in meters.
const LEAN_SHIFT := 0.35

var health := MAX_HEALTH

## How far she leans, in [-1, 1]: negative to her left, positive to her right.
var lean := 0.0

## How far she ducks, in [0, 1].
var duck := 0.0

## Whether she is in a jump now.
var jumping := false

## Whether she holds both gloves up in front of her face.
var covering := false

var camera: Camera3D

var _gloves: Array[Node3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _elbows: Array[MeshInstance3D] = []
var _poles: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var _punch_time: Array[float] = [-1.0, -1.0]
var _punch_kind: Array[String] = ["straight", "straight"]
var _hands: Array = [null, null]
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

    for i in range(2):
        # NOTE (mristin):
        # The segments are tapered limbs of unit length (the narrow end at the
        # top), which _span() stretches and turns between two joints every
        # frame.
        _upper_arms.append(Flat.limb(camera, 0.045, 0.06, 1.0, Vector3.ZERO, SKIN_DARK))
        _forearms.append(Flat.limb(camera, 0.034, 0.046, 1.0, Vector3.ZERO, SKIN))
        _elbows.append(Flat.ball(camera, 0.05, Vector3.ZERO, SKIN_DARK))

        var glove := Node3D.new()
        camera.add_child(glove)
        var ball := Flat.ball(glove, 0.06, Vector3.ZERO, GLOVE, false, 1.15)
        ball.scale = Vector3(1.0, 1.0, 1.25)
        Flat.ball(glove, 0.028, Vector3(0.05 if i == 0 else -0.05, 0.01, -0.015), GLOVE)
        Flat.box(glove, Vector3(0.06, 0.045, 0.04), Vector3(0, -0.03, 0.07), CUFF)
        _gloves.append(glove)
        glove.position = _side(SHOULDER, i) + Vector3(0, 0.1, -0.5)

        _thighs.append(Flat.limb(camera, 0.07, 0.09, 1.0, Vector3.ZERO, SHORTS))
        _shins.append(Flat.limb(camera, 0.042, 0.058, 1.0, Vector3.ZERO, SKIN))
        _knees.append(Flat.ball(camera, 0.07, Vector3.ZERO, SKIN_DARK))
        _shoes.append(Flat.box(camera, Vector3(0.13, 0.11, 1.0), Vector3.ZERO, SHOE))


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
    camera.position = Vector3(lean * LEAN_SHIFT, EYES - duck * 0.45 + _jump_height, 0) + shake
    var look := opponent + Vector3(0, 1.45, 0)
    if camera.global_position.distance_to(look) > 0.1:
        camera.look_at(look, Vector3.UP)
    # NOTE (mristin):
    # Tilt the head a little into the lean, as one does when slipping a punch.
    camera.rotate_object_local(Vector3.BACK, -lean * 0.12)


## Set where the hands are, in the mirrored camera picture (normalized, each
## null if not seen), with the head there, so that the gloves follow them.
func set_hands(hands: Array, head: Rect2) -> void:
    for i in range(2):
        var hand: Variant = hands[i] if i < hands.size() else null
        if hand == null or head.size.x <= 0.0:
            _hands[i] = null
            continue
        # NOTE (mristin):
        # Relative to the head, in head widths: so it does not matter how far
        # from the camera the player stands.
        var relative: Vector2 = (hand - head.get_center()) / head.size.x
        _hands[i] = relative


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
    _shake = maxf(0.0, _shake - delta * 3.0)
    _hurt = maxf(0.0, _hurt - delta * 2.0)
    for i in range(2):
        _place_arm(i, delta)
        _place_leg(i, delta)


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


## Where the glove rests: in the guard, or where the hand is in the camera
## picture, or in front of the face while she covers.
func _rest(i: int) -> Vector3:
    var sign_x := -1.0 if i == 0 else 1.0
    if covering:
        # NOTE (mristin):
        # The gloves cover the face, close together, so that the player sees
        # that the cover counts.
        return Vector3(0.065 * sign_x, -0.04, -0.3)
    var hand: Variant = _hands[i]
    if hand != null:
        # NOTE (mristin):
        # Her left hand is on the left of the mirrored picture.
        var relative: Vector2 = hand
        return Vector3(
            clampf(relative.x * 0.12, -0.4, 0.4),
            clampf(-relative.y * 0.1 - 0.05, -0.38, 0.05),
            -0.5
        )
    return Vector3(0.15 * sign_x, -0.2, -0.5)


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
    var pole := Vector3(sign_x, 0.9, 0.3)
    var glove: Vector3
    if p < 0.2:
        glove = rest.lerp(shoulder + _arc(sign_x, 0.95), smoothstep(0.0, 1.0, p / 0.2))
    elif p < 0.6:
        glove = shoulder + _arc(sign_x, lerpf(0.95, -0.5, smoothstep(0.0, 1.0, (p - 0.2) / 0.4)))
    else:
        var swing_end := shoulder + _arc(sign_x, -0.5)
        glove = swing_end.lerp(rest, smoothstep(0.0, 1.0, (p - 0.6) / 0.4))
    return [glove, pole]


## An uppercut: down first, then steeply up to above the eyes, the elbow under
## the glove; then back.
func _uppercut_path(i: int, p: float, rest: Vector3) -> Array:
    var sign_x := -1.0 if i == 0 else 1.0
    var pole := Vector3(sign_x * 0.3, -1.0, 0.3)
    var dip := rest + Vector3(-sign_x * 0.02, -0.17, 0.06)
    var top := Vector3(-sign_x * 0.07, 0.12, -0.5)
    var glove: Vector3
    if p < 0.3:
        glove = rest.lerp(dip, smoothstep(0.0, 1.0, p / 0.3))
    elif p < 0.62:
        glove = dip.lerp(top, smoothstep(0.0, 1.0, (p - 0.3) / 0.32))
    else:
        glove = top.lerp(rest, smoothstep(0.0, 1.0, (p - 0.62) / 0.38))
    return [glove, pole]


## A point on the swing of a hook around the shoulder, at the angle (0 straight
## ahead, positive out to the side), at the height of the chin.
static func _arc(sign_x: float, angle: float) -> Vector3:
    var radius := 0.6
    return Vector3(sign_x * radius * sin(angle), 0.2, -radius * cos(angle))


func _place_arm(i: int, delta: float) -> void:
    var rest := _rest(i)
    var pole := Vector3(-1.0 if i == 0 else 1.0, -1.0, 0.1) * 0.5 + Vector3.DOWN * 0.5
    var glove := _gloves[i]
    if _punch_time[i] >= 0.0:
        var seconds: float = PUNCH_SECONDS[_punch_kind[i]]
        _punch_time[i] += delta
        var p := minf(1.0, _punch_time[i] / seconds)
        var path := _punch_path(i, _punch_kind[i], p, rest)
        glove.position = path[0]
        pole = path[1]
        if p >= 1.0:
            _punch_time[i] = -1.0
    else:
        glove.position = glove.position.lerp(rest, minf(1.0, delta * 14.0))
    _poles[i] = _poles[i].lerp(pole, minf(1.0, delta * 20.0))

    var shoulder := _side(SHOULDER, i)
    # NOTE (mristin):
    # The glove can not go farther than the arm reaches.
    var reach := glove.position - shoulder
    if reach.length() > UPPER_ARM + FOREARM:
        glove.position = shoulder + reach.normalized() * (UPPER_ARM + FOREARM)
    var wrist := glove.position + (shoulder - glove.position).normalized() * 0.06
    var elbow := bend(shoulder, wrist, UPPER_ARM, FOREARM, _poles[i])
    _span(_upper_arms[i], shoulder, elbow)
    _span(_forearms[i], elbow, wrist)
    _elbows[i].position = elbow
    # NOTE (mristin):
    # The glove points along the forearm: so a hook turns it on its side and
    # an uppercut points it up.
    var along := (glove.position - elbow).normalized()
    var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.BACK
    glove.basis = Basis.looking_at(along, up)


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
