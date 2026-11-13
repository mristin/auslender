class_name Scientist
extends Node3D

## The opponent: an evil scientist of Rochartis, the fictional pharma giant, in
## his lab coat, his goggles and his purple lab gloves, built of flat-shaded
## boxes and low-poly balls.
##
## He keeps his distance to the player, guards his face, and now and then
## attacks: a high punch (duck or step aside), or a low sweep of his leg (jump
## or step back). Each attack winds up first, long enough for the player to
## react with her body ([member windup_seconds]); after it, he stands open for
## a moment. He faces the player all the time; his front is -Z, as in Godot.
##
## The ring decides whether his attacks hit (see [signal struck]), and he
## takes the player's punches and kicks with [method take_hit].

## He winds up an attack; [param high] is a punch, else a low sweep.
signal winding_up(high: bool)

## His attack lands now, aimed at where the player stood when he wound up.
signal struck(high: bool, aimed_at: Vector3)

signal knocked_out

enum State { GUARD, WINDUP, STRIKE, RECOVER, STAGGER, KNOCKED_OUT }

const MAX_HEALTH := 100.0

const SKIN := Color("e0b48e")
const COAT := Color("f1f0ea")
const COAT_SHADE := Color("cfcfc7")
const TROUSERS := Color("3a3f4a")
const SHOES := Color("1b1b1e")
const GLOVES := Color("7b3fb0")
const HAIR := Color("b9b9b9")
const GOGGLES := Color("26303a")
const LENS := Color("5fd3e6")
const TIE := Color("b3262a")
const SHIRT := Color("8fb1d6")
const BADGE := Color("1f8f8a")

## How long he winds up, in seconds: the time the player has to react.
@export var windup_seconds := 0.9

## He likes to stand this far from the player, in meters.
@export var preferred_distance := 1.35

## He walks at most this fast, in meters per second.
@export var walk_speed := 0.7

## He attacks only from within this distance, in meters.
@export var attack_range := 1.95

var health := MAX_HEALTH
var state := State.GUARD

## Where the player is, which the ring tells him on every frame.
var target := Vector3.ZERO

var _state_left := 2.0
var _high := true
var _aimed_at := Vector3.ZERO
var _random := RandomNumberGenerator.new()
var _circle := 1.0
var _time := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _stagger_push := Vector3.ZERO

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _flashing: Array[ShaderMaterial] = []


func _ready() -> void:
    _random.seed = 7
    _build()
    _enter(State.GUARD)


## Start the fight again: full health, on his feet.
func reset() -> void:
    health = MAX_HEALTH
    _body.rotation = Vector3.ZERO
    _body.position = Vector3.ZERO
    _enter(State.GUARD)


## Whether he guards his face now (straight punches mostly bounce off).
func is_guarding() -> bool:
    return state == State.GUARD


## Whether he stands open now (after an attack), and takes more.
func is_open() -> bool:
    return state == State.RECOVER or state == State.STAGGER


## Whether he winds up an attack now, and which: true for high.
func windup_high() -> Variant:
    return _high if state == State.WINDUP else null


## How far the wind-up got, in [0, 1]; 0 outside of it.
func windup_progress() -> float:
    if state != State.WINDUP:
        return 0.0
    return 1.0 - _state_left / windup_seconds


## Take a punch or a kick of the player; return what came of it: "blocked",
## "hit" or "open" (a hit while he stood open), and the damage.
func take_hit(kind: String, power: float) -> Dictionary:
    if state == State.KNOCKED_OUT:
        return {"result": "down", "damage": 0.0}

    var base := {
        "straight": 6.0,
        "hook": 8.0,
        "uppercut": 10.0,
        "front_kick": 12.0,
        "side_kick": 12.0,
    }
    var damage: float = base.get(kind, 6.0) * lerpf(0.6, 1.2, power)
    var result := "hit"
    if is_guarding():
        # NOTE (mristin):
        # The guard covers the front: straights bounce off it, hooks get half
        # around it, and uppercuts and kicks go under it.
        var through := {"straight": 0.25, "hook": 0.6}
        if through.has(kind):
            damage *= through[kind]
            result = "blocked" if kind == "straight" else "hit"
    elif is_open():
        damage *= 1.5
        result = "open"

    health = maxf(0.0, health - damage)
    _flash_color = Color.WHITE
    _flash = 1.0
    if health <= 0.0:
        _enter(State.KNOCKED_OUT)
        knocked_out.emit()
    elif result != "blocked" and (kind.ends_with("kick") or kind == "uppercut" or power > 0.8):
        var away := global_position - target
        away.y = 0.0
        _stagger_push = away.normalized() * (0.5 if kind.ends_with("kick") else 0.3)
        _enter(State.STAGGER)
    else:
        _head.rotation.x = -0.35
    return {"result": result, "damage": damage}


func _process(delta: float) -> void:
    _time += delta
    _state_left -= delta
    _think(delta)
    _animate(delta)
    _flash = maxf(0.0, _flash - delta * 4.0)
    var glow := _flash
    var color := _flash_color
    if state == State.WINDUP:
        # NOTE (mristin):
        # The wind-up glows red, brighter as it comes, so that the player sees
        # it even when she looks at herself in the camera picture.
        glow = maxf(glow, 0.25 + 0.5 * windup_progress())
        color = Color("ff3b2f") if _flash <= 0.0 else _flash_color
    for material in _flashing:
        material.set_shader_parameter("flash", glow)
        material.set_shader_parameter("flash_color", color)


func _think(delta: float) -> void:
    if state == State.KNOCKED_OUT:
        return

    _face_target()
    var to_target := target - global_position
    to_target.y = 0.0
    var distance := to_target.length()
    var forward := to_target / maxf(distance, 0.001)

    match state:
        State.GUARD:
            # NOTE (mristin):
            # He keeps his distance and circles a little, changing the
            # direction now and then, as a boxer does.
            var step := (distance - preferred_distance) * 1.5
            var side := forward.cross(Vector3.UP) * _circle * 0.25
            var velocity := forward * clampf(step, -walk_speed, walk_speed) + side
            global_position = Arena.clamp_inside(global_position + velocity * delta)
            if _random.randf() < delta * 0.3:
                _circle = -_circle
            if _state_left <= 0.0:
                if distance <= attack_range:
                    _high = _random.randf() < 0.7
                    _aimed_at = target
                    _enter(State.WINDUP)
                    winding_up.emit(_high)
                else:
                    _state_left = 0.3
        State.WINDUP:
            if _state_left <= 0.0:
                _enter(State.STRIKE)
                struck.emit(_high, _aimed_at)
        State.STRIKE:
            if _state_left <= 0.0:
                _enter(State.RECOVER)
        State.RECOVER:
            if _state_left <= 0.0:
                _enter(State.GUARD)
        State.STAGGER:
            global_position = Arena.clamp_inside(global_position + _stagger_push * delta * 3.0)
            _stagger_push = _stagger_push.lerp(Vector3.ZERO, delta * 6.0)
            if _state_left <= 0.0:
                _enter(State.GUARD)

    # NOTE (mristin):
    # He never walks into the player.
    var away := global_position - target
    away.y = 0.0
    if away.length() < 0.75:
        global_position = Arena.clamp_inside(target + away.normalized() * 0.75)


func _face_target() -> void:
    var look := Vector3(target.x, global_position.y, target.z)
    if look.distance_to(global_position) > 0.05:
        look_at(look, Vector3.UP)


func _enter(next: State) -> void:
    state = next
    match next:
        State.GUARD:
            _state_left = _random.randf_range(1.4, 2.8)
        State.WINDUP:
            _state_left = windup_seconds
        State.STRIKE:
            _state_left = 0.18
        State.RECOVER:
            _state_left = 0.8
        State.STAGGER:
            _state_left = 0.45
        State.KNOCKED_OUT:
            _state_left = 0.0


## Move the limbs towards the pose of the state.
func _animate(delta: float) -> void:
    # Each arm: [shoulder pitch, shoulder roll, elbow pitch]; each leg: [hip pitch, knee pitch].
    var arm_left := [0.55, -0.25, 1.95]
    var arm_right := [0.55, 0.25, 1.95]
    var leg_left := [0.0, 0.0]
    var leg_right := [0.0, 0.0]
    var torso_yaw := 0.0
    var torso_pitch := 0.05
    var lunge := 0.0
    var speed := 10.0

    var bob := sin(_time * 5.0) * 0.02
    match state:
        State.WINDUP:
            var p := windup_progress()
            if _high:
                arm_right = [0.2, 0.5, 2.4]
                torso_yaw = -0.45 * p
            else:
                leg_right = [-0.6 * p, 0.9 * p]
                torso_pitch = -0.1
            speed = 6.0
        State.STRIKE:
            if _high:
                arm_right = [1.6, 0.05, 0.05]
                torso_yaw = 0.35
                lunge = 0.55
            else:
                leg_right = [1.1, 0.1]
                lunge = 0.4
                torso_pitch = -0.2
            speed = 30.0
        State.RECOVER:
            arm_left = [0.25, -0.15, 0.8]
            arm_right = [0.25, 0.15, 0.8]
            torso_pitch = 0.15
            speed = 6.0
        State.STAGGER:
            arm_left = [0.1, -0.5, 0.6]
            arm_right = [0.1, 0.5, 0.6]
            torso_pitch = -0.3
        State.KNOCKED_OUT:
            arm_left = [-0.2, -1.2, 0.3]
            arm_right = [-0.2, 1.2, 0.3]
            _body.rotation.x = lerpf(_body.rotation.x, PI * 0.5, minf(1.0, delta * 3.0))
            _body.position.y = lerpf(_body.position.y, 0.15, minf(1.0, delta * 3.0))

    var weight := minf(1.0, delta * speed)
    for i in range(2):
        var arm: Array = arm_left if i == 0 else arm_right
        _arms[i].rotation.x = lerpf(_arms[i].rotation.x, arm[0], weight)
        _arms[i].rotation.z = lerpf(_arms[i].rotation.z, arm[1], weight)
        _elbows[i].rotation.x = lerpf(_elbows[i].rotation.x, arm[2], weight)
        var leg: Array = leg_left if i == 0 else leg_right
        _legs[i].rotation.x = lerpf(_legs[i].rotation.x, leg[0], weight)
        _knees[i].rotation.x = lerpf(_knees[i].rotation.x, -leg[1], weight)
    _torso.rotation.y = lerpf(_torso.rotation.y, torso_yaw, weight)
    _torso.rotation.x = lerpf(_torso.rotation.x, torso_pitch, weight)
    _head.rotation.x = lerpf(_head.rotation.x, 0.0, minf(1.0, delta * 5.0))
    if state != State.KNOCKED_OUT:
        _body.position = _body.position.lerp(Vector3(0, bob, -lunge), weight)


func _build() -> void:
    _body = Node3D.new()
    add_child(_body)

    for i in range(2):
        var x := -0.12 if i == 0 else 0.12
        var hip := _pivot(_body, Vector3(x, 0.92, 0))
        Flat.box(hip, Vector3(0.15, 0.44, 0.16), Vector3(0, -0.22, 0), TROUSERS)
        var knee := _pivot(hip, Vector3(0, -0.46, 0))
        Flat.box(knee, Vector3(0.13, 0.42, 0.14), Vector3(0, -0.21, 0), TROUSERS)
        Flat.box(knee, Vector3(0.13, 0.08, 0.27), Vector3(0, -0.42, -0.05), SHOES)
        _legs.append(hip)
        _knees.append(knee)

    _torso = _pivot(_body, Vector3(0, 0.95, 0))
    # The lab coat: the skirt down to the knees, the chest, the lapels.
    _flashing.append(_own(Flat.box(_torso, Vector3(0.5, 0.45, 0.3), Vector3(0, -0.18, 0), COAT, true)))
    _flashing.append(_own(Flat.box(_torso, Vector3(0.52, 0.62, 0.3), Vector3(0, 0.33, 0), COAT, true)))
    Flat.box(_torso, Vector3(0.16, 0.36, 0.01), Vector3(0, 0.44, -0.152), SHIRT)
    Flat.box(_torso, Vector3(0.05, 0.3, 0.01), Vector3(0, 0.42, -0.158), TIE)
    Flat.box(_torso, Vector3(0.02, 0.5, 0.01), Vector3(-0.1, 0.36, -0.155), COAT_SHADE)
    Flat.box(_torso, Vector3(0.02, 0.5, 0.01), Vector3(0.1, 0.36, -0.155), COAT_SHADE)
    Flat.box(_torso, Vector3(0.12, 0.05, 0.01), Vector3(0.17, 0.5, -0.155), BADGE)
    var badge := Label3D.new()
    badge.text = "ROCHARTIS"
    badge.font_size = 18
    badge.pixel_size = 0.0012
    badge.modulate = Color.WHITE
    badge.position = Vector3(0.17, 0.5, -0.162)
    badge.rotation.y = PI
    _torso.add_child(badge)
    Flat.box(_torso, Vector3(0.12, 0.08, 0.12), Vector3(0, 0.68, 0), SKIN)

    _head = _pivot(_torso, Vector3(0, 0.7, 0))
    _flashing.append(_own(Flat.ball(_head, 0.13, Vector3(0, 0.14, 0), SKIN, true, 1.2)))
    # The grey fringe around his bald head, and the goatee.
    Flat.box(_head, Vector3(0.05, 0.1, 0.18), Vector3(-0.12, 0.13, 0.03), HAIR)
    Flat.box(_head, Vector3(0.05, 0.1, 0.18), Vector3(0.12, 0.13, 0.03), HAIR)
    Flat.box(_head, Vector3(0.22, 0.08, 0.05), Vector3(0, 0.15, 0.12), HAIR)
    Flat.box(_head, Vector3(0.06, 0.07, 0.04), Vector3(0, 0.01, -0.1), HAIR)
    # The goggles, the evil brows, the nose and the grin.
    Flat.box(_head, Vector3(0.25, 0.035, 0.03), Vector3(0, 0.17, -0.11), GOGGLES)
    for x in [-0.05, 0.05]:
        Flat.box(_head, Vector3(0.07, 0.055, 0.03), Vector3(x, 0.17, -0.125), LENS)
    var brow_left := Flat.box(_head, Vector3(0.08, 0.02, 0.02), Vector3(-0.05, 0.22, -0.125), SHOES)
    brow_left.rotation.z = -0.35
    var brow_right := Flat.box(_head, Vector3(0.08, 0.02, 0.02), Vector3(0.05, 0.22, -0.125), SHOES)
    brow_right.rotation.z = 0.35
    Flat.box(_head, Vector3(0.035, 0.06, 0.05), Vector3(0, 0.11, -0.135), SKIN.darkened(0.1))
    Flat.box(_head, Vector3(0.09, 0.015, 0.02), Vector3(0, 0.06, -0.12), Color("5a1f1f"))

    for i in range(2):
        var x := -0.31 if i == 0 else 0.31
        var shoulder := _pivot(_torso, Vector3(x, 0.58, 0))
        _flashing.append(
            _own(Flat.box(shoulder, Vector3(0.12, 0.3, 0.12), Vector3(0, -0.15, 0), COAT, true))
        )
        var elbow := _pivot(shoulder, Vector3(0, -0.3, 0))
        Flat.box(elbow, Vector3(0.1, 0.26, 0.1), Vector3(0, -0.13, 0), COAT)
        Flat.ball(elbow, 0.085, Vector3(0, -0.3, 0), GLOVES)
        _arms.append(shoulder)
        _elbows.append(elbow)


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
    var pivot := Node3D.new()
    pivot.position = at
    parent.add_child(pivot)
    return pivot


func _own(instance: MeshInstance3D) -> ShaderMaterial:
    return instance.material_override
