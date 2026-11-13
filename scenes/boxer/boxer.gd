class_name Boxer
extends Node3D

## The player in the ring, in the first person: the camera at the height of her
## eyes, looking where she heads, and her two red gloves in front of it.
##
## She walks in place to walk forward where she heads, and turns her body to
## turn ([method walk]). Ducking lowers the camera, and a jump lifts it. The
## gloves follow her hands in the camera picture and fly forward with each
## punch; a kick shows her shoe.

const MAX_HEALTH := 100.0

const GLOVE := Color("c8302c")
const CUFF := Color("f2efe6")
const SHOE := Color("23252b")

## The height of the eyes, in meters.
const EYES := 1.62

## She walks at most this fast, in meters per second.
@export var walk_speed := 1.4

## She circles at most this fast, in meters per second.
@export var circle_speed := 1.6

## She turns at most this fast, in radians per second.
@export var turn_speed := 1.6

## She stands at least this far from the opponent, in meters.
@export var closest := 0.8

var health := MAX_HEALTH

## Where she heads: the angle around the vertical, 0 towards -Z.
var heading := 0.0

## How far she ducks, in [0, 1].
var duck := 0.0

## Whether she is in a jump now.
var jumping := false

var camera: Camera3D

var _gloves: Array[Node3D] = []
var _punch_left: Array[float] = [0.0, 0.0]
var _punch_kind: Array[String] = ["straight", "straight"]
var _hands: Array = [null, null]
var _shoe: Node3D
var _kick_left := 0.0
var _kick_side := 1.0
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
        var glove := Node3D.new()
        camera.add_child(glove)
        var ball := Flat.ball(glove, 0.06, Vector3.ZERO, GLOVE, false, 1.15)
        ball.scale = Vector3(1.0, 1.0, 1.25)
        Flat.ball(glove, 0.028, Vector3(0.05 if i == 0 else -0.05, 0.01, -0.015), GLOVE)
        Flat.box(glove, Vector3(0.06, 0.045, 0.04), Vector3(0, -0.03, 0.07), CUFF)
        _gloves.append(glove)

    _shoe = Node3D.new()
    camera.add_child(_shoe)
    Flat.box(_shoe, Vector3(0.12, 0.1, 0.3), Vector3.ZERO, SHOE)
    Flat.box(_shoe, Vector3(0.11, 0.25, 0.11), Vector3(0, -0.15, 0.1), Color("3a3f4a"))
    _shoe.visible = false


## Start the fight again at the position, facing the point.
func reset(at: Vector3, facing: Vector3) -> void:
    health = MAX_HEALTH
    global_position = at
    duck = 0.0
    var towards := facing - at
    heading = atan2(-towards.x, -towards.z)


## The direction where she heads, on the floor.
func forward() -> Vector3:
    return Vector3(-sin(heading), 0, -cos(heading))


## Walk forward at the speed (in [0, 1]) and turn by the turn (in [-1, 1],
## negative to her left), keeping out of the opponent at [param opponent].
func walk(speed: float, turn: float, delta: float, opponent: Vector3) -> void:
    heading -= turn * turn_speed * delta
    var moved := global_position + forward() * speed * walk_speed * delta
    var away := moved - opponent
    away.y = 0.0
    if away.length() < closest:
        moved = opponent + away.normalized() * closest
    moved.y = 0.0
    global_position = Arena.clamp_inside(moved)


## Whether the point is within the angle (in radians) to either side of where she heads.
func facing(point: Vector3, angle: float) -> bool:
    var towards := point - global_position
    towards.y = 0.0
    if towards.length() < 0.01:
        return true
    return forward().angle_to(towards.normalized()) <= angle


## Move by the stick (x to her right, y forward, each in [-1, 1]) around the
## opponent at [param opponent].
func steer(stick: Vector2, delta: float, opponent: Vector3) -> void:
    var to_opponent := opponent - global_position
    to_opponent.y = 0.0
    var distance := to_opponent.length()
    if distance < 0.001:
        return
    var forward := to_opponent / distance
    var right := forward.cross(Vector3.UP)

    var moved := global_position + right * stick.x * circle_speed * delta
    # NOTE (mristin):
    # Circling keeps the distance to the opponent, as if on a circle around
    # him, unless she also steps forward or back.
    var around := moved - opponent
    around.y = 0.0
    if around.length() > 0.001:
        moved = opponent + around.normalized() * distance
    moved += forward * stick.y * walk_speed * delta

    var away := moved - opponent
    away.y = 0.0
    if away.length() < closest:
        moved = opponent + away.normalized() * closest
    moved.y = 0.0
    global_position = Arena.clamp_inside(moved)


## Look where she heads (with [param at_opponent], at the opponent's head
## instead), and set the height of the eyes from the duck and the jump.
func face(opponent: Vector3, delta: float, at_opponent := false) -> void:
    _jump_height = lerpf(_jump_height, 0.25 if jumping else 0.0, minf(1.0, delta * 12.0))
    var height := EYES - duck * 0.45 + _jump_height
    var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.03
    camera.position = Vector3(0, height, 0) + shake
    var look := global_position + forward() * 3.0 + Vector3(0, 1.45, 0)
    if at_opponent:
        look = opponent + Vector3(0, 1.55, 0)
    if camera.global_position.distance_to(look) > 0.1:
        camera.look_at(look, Vector3.UP)


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
    _punch_left[side] = 0.22
    _punch_kind[side] = kind


## Show the kick of the leg (0 left, 1 right).
func kick(side: int) -> void:
    _kick_left = 0.35
    _kick_side = -1.0 if side == 0 else 1.0


## Take the damage of a hit: shake and flash.
func take_damage(damage: float) -> void:
    health = maxf(0.0, health - damage)
    _shake = 1.0
    _hurt = 1.0


## How red the screen flashes now, in [0, 1].
func hurt() -> float:
    return _hurt


func _process(delta: float) -> void:
    _shake = maxf(0.0, _shake - delta * 3.0)
    _hurt = maxf(0.0, _hurt - delta * 2.0)
    for i in range(2):
        _punch_left[i] = maxf(0.0, _punch_left[i] - delta)
        _place_glove(i, delta)

    _kick_left = maxf(0.0, _kick_left - delta)
    _shoe.visible = _kick_left > 0.0
    if _shoe.visible:
        var p := 1.0 - _kick_left / 0.35
        var out := sin(p * PI)
        _shoe.position = Vector3(0.12 * _kick_side, lerpf(-0.75, -0.3, out), lerpf(-0.4, -0.85, out))


func _place_glove(i: int, delta: float) -> void:
    var sign_x := -1.0 if i == 0 else 1.0
    var rest := Vector3(0.16 * sign_x, -0.21, -0.55)
    var hand: Variant = _hands[i]
    if hand != null:
        # NOTE (mristin):
        # Her left hand is on the left of the mirrored picture.
        var relative: Vector2 = hand
        rest = Vector3(
            clampf(relative.x * 0.12, -0.4, 0.4),
            clampf(-relative.y * 0.1 - 0.05, -0.38, 0.05),
            -0.55
        )
    var target := rest
    if _punch_left[i] > 0.0:
        var p := 1.0 - _punch_left[i] / 0.22
        var out := sin(p * PI)
        match _punch_kind[i]:
            "hook":
                target = rest + Vector3(-sign_x * 0.25 * out, 0.08 * out, -0.25 * out)
            "uppercut":
                target = rest + Vector3(-sign_x * 0.05 * out, 0.25 * out, -0.2 * out)
            _:
                target = rest + Vector3(-sign_x * 0.08 * out, 0.1 * out, -0.4 * out)
        _gloves[i].position = target
    else:
        _gloves[i].position = _gloves[i].position.lerp(target, minf(1.0, delta * 14.0))
