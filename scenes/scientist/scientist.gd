class_name Scientist
extends Node3D

## The opponent: an evil scientist of Rochartis, the fictional pharma giant, in
## his lab coat, his goggles and his purple lab gloves, built of flat-shaded
## boxes and low-poly balls.
##
## In the rhythm fight (see Fight), the chart moves him, not a mind of his own:
## he bobs to the beat ([method beat]); the fight shows his attacks with
## [method perform], so that he winds up through the last stretch before the
## beat on which it lands, and strikes on it; he flinches when the player's
## punches land ([method flinch]): his head snaps aside from a hook, back from
## a straight, up from an uppercut, and a kick knocks him back a step; and he
## goes down at the end ([method knock_out]). He is never still: he bounces
## on the beat and sways from side to side over each bar ([method groove]),
## steps in as he winds up; he slips aside, mocking, when the player misses
## ([method evade]), stumbles past when the player dodges him ([method
## stumble]), throws up his arms when his attack lands ([method cheer]), and
## beckons the player in and shimmies in the breathers ([method show_off]).
## He faces the player all the time; his front is -Z, as in Godot.
##
## His attacks, and how the player dodges them: a jab straight at the face
## (cover), a hook from the player's left (slip right) or right (slip left), a
## wild haymaker at head height (duck), and a low sweep of his leg (jump).

## How long he winds up before an attack lands, in seconds (the note of the
## attack shows long before).
const WINDUP_SECONDS := 0.6

## How long he strikes and comes back after it lands, in seconds.
const STRIKE_SECONDS := 0.45

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

const RAGE := Color("ff9a1f")

var health := MAX_HEALTH

## Where the player is, which the fight tells him on every frame.
var target := Vector3.ZERO

var _attack := ""
var _share := 1.0
var _beat := 0.0
var _down := false
var _time := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _head_kick := Vector3.ZERO
var _knock := 0.0
var _raging := false
## The sway from side to side (meters), the moment (seconds) and side of his
## reactions, and whether he shows off now.
var _sway_x := 0.0
var _evade_left := 0.0
var _evade_side := 1.0
var _stumble_left := 0.0
var _cheer_left := 0.0
var _showing_off := false

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _flashing: Array[ShaderMaterial] = []


func _ready() -> void:
    _build()


## Start the fight again: full health, on his feet.
func reset() -> void:
    health = MAX_HEALTH
    _body.rotation = Vector3.ZERO
    _body.position = Vector3.ZERO
    _attack = ""
    _down = false
    _raging = false
    _knock = 0.0
    _evade_left = 0.0
    _stumble_left = 0.0
    _cheer_left = 0.0
    _showing_off = false


## Move to the music: [param phase] is how far the current beat is, in [0,
## 1), and [param bar] how far the current bar is, in [0, 1): he bounces on
## every beat and sways over to one side and back over two bars.
func groove(phase: float, bar: float, bar_index: int) -> void:
    _beat = phase
    var over_two := (float(bar_index % 2) + bar) * 0.5
    _sway_x = 0.22 * sin(over_two * TAU)


## Show off (in a breather): beckon the player in, and shimmy.
func show_off(on: bool) -> void:
    _showing_off = on


## The player missed: slip aside from his punch, mocking ([param side]: the
## player's hand).
func evade(side: String) -> void:
    if _down:
        return
    _evade_left = 0.5
    # NOTE (mristin):
    # Away from where the punch would come: the player's left hand comes from
    # the scientist's right.
    _evade_side = -1.0 if side == "left" else 1.0


## The player dodged his attack: he stumbles past it.
func stumble() -> void:
    if not _down:
        _stumble_left = 0.6


## His attack landed: he throws up his arms.
func cheer() -> void:
    if not _down:
        _cheer_left = 0.9


## Show his attack ("jab", "hook_left", "hook_right", "haymaker" or "sweep";
## "" for none) at [param seconds] from the beat on which it lands (negative
## before it): he winds up in the last WINDUP_SECONDS, strikes on the beat,
## and comes back.
func perform(attack: String, seconds: float) -> void:
    if seconds < -WINDUP_SECONDS or seconds > STRIKE_SECONDS:
        attack = ""
    _attack = attack
    _share = seconds


## The player's punch or kick landed: flinch from it, the more the stronger
## ([param strength] in [0, 1]), and take its damage.
func flinch(kind: String, side: String, strength: float, damage: float) -> void:
    if _down:
        return
    health = maxf(0.0, health - damage)
    _flash = 0.6 + 0.4 * strength
    _flash_color = Color.WHITE
    # NOTE (mristin):
    # The player's left hook comes from his left: from the scientist's right,
    # so that his head turns to his left (the player's right).
    var away := 1.0 if side == "left" else -1.0
    match kind:
        "straight":
            _head_kick = Vector3(-0.35, 0.0, 0.0) * strength
        "hook":
            _head_kick = Vector3(-0.1, -0.6 * away, 0.25 * away) * strength
        "uppercut":
            _head_kick = Vector3(-0.8, 0.0, 0.0) * strength
        "kick":
            _knock = 0.35 * strength
    _raging = health < MAX_HEALTH * 0.35


## Go down: the knock-out.
func knock_out() -> void:
    _down = true
    _attack = ""


func _process(delta: float) -> void:
    _time += delta
    _face_target()
    _animate(delta)
    _flash = maxf(0.0, _flash - delta * 4.0)
    var glow := _flash
    var color := _flash_color
    if _attack != "" and _share < 0.0 and _flash <= 0.0:
        # NOTE (mristin):
        # The wind-up glows red, brighter as it comes.
        glow = 0.25 + 0.5 * (1.0 + _share / WINDUP_SECONDS)
        color = Color("ff3b2f")
    elif _raging and not _down and _flash <= 0.0:
        # NOTE (mristin):
        # Hurt badly, he simmers orange.
        glow = 0.12 + 0.08 * sin(_time * 7.0)
        color = RAGE
    for material in _flashing:
        material.set_shader_parameter("flash", glow)
        material.set_shader_parameter("flash_color", color)


func _face_target() -> void:
    var look := Vector3(target.x, global_position.y, target.z)
    if look.distance_to(global_position) > 0.05:
        look_at(look, Vector3.UP)


## Move the limbs towards the pose of the moment.
func _animate(delta: float) -> void:
    # Each arm: [shoulder pitch, shoulder roll (outwards), elbow pitch]; each
    # leg: [hip pitch, knee pitch]. His right arm is on the player's left.
    var arm_left := [0.55, 0.25, 1.95]
    var arm_right := [0.55, 0.25, 1.95]
    var leg_left := [0.0, 0.0]
    var leg_right := [0.0, 0.0]
    var torso_yaw := 0.0
    var torso_pitch := 0.05
    var lunge := 0.0
    var speed := 12.0

    # NOTE (mristin):
    # He bobs down on every beat, and sways his shoulders with the bars.
    var bob := -0.05 * pow(1.0 - _beat, 3.0)
    torso_yaw = 0.06 * sin(_time * PI * 0.8)
    var side_shift := _sway_x
    var torso_roll := -_sway_x * 0.25
    _evade_left = maxf(0.0, _evade_left - delta)
    _stumble_left = maxf(0.0, _stumble_left - delta)
    _cheer_left = maxf(0.0, _cheer_left - delta)

    if _showing_off:
        # NOTE (mristin):
        # He beckons with his left glove (the elbow pumping), and shimmies.
        arm_left = [1.35, 0.1, 0.9 + 0.7 * sin(_time * 9.0)]
        torso_yaw = 0.2 * sin(_time * 12.0)
    if _cheer_left > 0.0:
        arm_left = [3.0, 0.35, 0.3]
        arm_right = [3.0, 0.35, 0.3]
        torso_pitch = -0.15
        bob += 0.06 * absf(sin(_time * 14.0))
    if _evade_left > 0.0:
        # NOTE (mristin):
        # A quick slip aside, the torso tilted away, and back.
        var slip := sin(_evade_left / 0.5 * PI)
        side_shift += 0.3 * _evade_side * slip
        torso_roll += 0.35 * _evade_side * slip
        speed = 20.0
    if _stumble_left > 0.0:
        var stumble := sin(_stumble_left / 0.6 * PI)
        lunge = 0.35 * stumble
        torso_pitch = 0.35 * stumble
        arm_left = [0.9, 0.9, 0.4]
        arm_right = [0.9, 0.9, 0.4]

    if _attack != "":
        if _share < 0.0:
            var p := 1.0 + _share / WINDUP_SECONDS
            speed = 10.0
            # NOTE (mristin):
            # He steps in as he winds up, back to the middle.
            lunge = 0.25 * p
            side_shift *= 1.0 - p
            match _attack:
                "jab":
                    arm_left = [0.3, 0.1, 2.4]
                    torso_yaw = 0.25 * p
                "hook_left":
                    arm_right = [0.5, 0.9 + 0.3 * p, 1.4]
                    torso_yaw = -0.5 * p
                "hook_right":
                    arm_left = [0.5, 0.9 + 0.3 * p, 1.4]
                    torso_yaw = 0.5 * p
                "haymaker":
                    arm_right = [lerpf(0.55, 2.7, p), 0.4, lerpf(1.95, 1.0, p)]
                    torso_yaw = -0.4 * p
                    torso_pitch = -0.1 * p
                "sweep":
                    leg_right = [-0.6 * p, 0.9 * p]
                    torso_pitch = -0.1
        else:
            speed = 30.0
            match _attack:
                "jab":
                    arm_left = [1.6, 0.0, 0.05]
                    torso_yaw = -0.2
                    lunge = 0.5
                "hook_left":
                    arm_right = [1.45, -0.5, 1.2]
                    torso_yaw = 0.5
                    lunge = 0.35
                "hook_right":
                    arm_left = [1.45, -0.5, 1.2]
                    torso_yaw = -0.5
                    lunge = 0.35
                "haymaker":
                    arm_right = [1.5, -0.6, 0.6]
                    torso_yaw = 0.6
                    lunge = 0.35
                "sweep":
                    leg_right = [1.1, 0.1]
                    lunge = 0.4
                    torso_pitch = -0.2

    if _down:
        arm_left = [-0.2, 1.2, 0.3]
        arm_right = [-0.2, 1.2, 0.3]
        _body.rotation.x = lerpf(_body.rotation.x, PI * 0.5, minf(1.0, delta * 3.0))
        _body.position.y = lerpf(_body.position.y, 0.15, minf(1.0, delta * 3.0))

    var weight := minf(1.0, delta * speed)
    for i in range(2):
        var arm: Array = arm_left if i == 0 else arm_right
        # NOTE (mristin):
        # The roll is outwards for both arms: negative for the left one.
        var outwards := -1.0 if i == 0 else 1.0
        _arms[i].rotation.x = lerpf(_arms[i].rotation.x, arm[0], weight)
        _arms[i].rotation.z = lerpf(_arms[i].rotation.z, arm[1] * outwards, weight)
        _elbows[i].rotation.x = lerpf(_elbows[i].rotation.x, arm[2], weight)
        var leg: Array = leg_left if i == 0 else leg_right
        _legs[i].rotation.x = lerpf(_legs[i].rotation.x, leg[0], weight)
        _knees[i].rotation.x = lerpf(_knees[i].rotation.x, -leg[1], weight)
    _torso.rotation.y = lerpf(_torso.rotation.y, torso_yaw, weight)
    _torso.rotation.x = lerpf(_torso.rotation.x, torso_pitch, weight)
    _torso.rotation.z = lerpf(_torso.rotation.z, torso_roll, weight)
    # NOTE (mristin):
    # A punch snaps his head, which comes back slowly.
    _head_kick = _head_kick.lerp(Vector3.ZERO, minf(1.0, delta * 5.0))
    _head.rotation = _head_kick
    _knock = lerpf(_knock, 0.0, minf(1.0, delta * 3.0))
    if not _down:
        _body.position = _body.position.lerp(Vector3(side_shift, bob, -lunge + _knock), weight)


func _build() -> void:
    _body = Node3D.new()
    add_child(_body)

    for i in range(2):
        var x := -0.12 if i == 0 else 0.12
        var hip := _pivot(_body, Vector3(x, 0.92, 0))
        Flat.limb(hip, 0.085, 0.065, 0.46, Vector3(0, -0.22, 0), TROUSERS)
        var knee := _pivot(hip, Vector3(0, -0.46, 0))
        Flat.ball(knee, 0.066, Vector3.ZERO, TROUSERS)
        Flat.limb(knee, 0.064, 0.05, 0.42, Vector3(0, -0.21, 0), TROUSERS)
        Flat.box(knee, Vector3(0.13, 0.08, 0.27), Vector3(0, -0.42, -0.05), SHOES)
        _legs.append(hip)
        _knees.append(knee)

    _torso = _pivot(_body, Vector3(0, 0.95, 0))
    # The lab coat: the skirt down to the knees, the chest, the lapels.
    # NOTE (mristin):
    # Tapered and flattened prisms, as the bodies of 4D Sports Boxing: the
    # chest wide at the shoulders, the skirt flaring to the knees.
    var skirt := Flat.limb(_torso, 0.24, 0.29, 0.45, Vector3(0, -0.18, 0), COAT, true)
    skirt.scale = Vector3(1, 1, 0.6)
    _flashing.append(_own(skirt))
    var chest := Flat.limb(_torso, 0.3, 0.23, 0.62, Vector3(0, 0.33, 0), COAT, true)
    chest.scale = Vector3(1, 1, 0.55)
    _flashing.append(_own(chest))
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
    Flat.limb(_torso, 0.055, 0.065, 0.1, Vector3(0, 0.68, 0), SKIN)

    _head = _pivot(_torso, Vector3(0, 0.7, 0))
    _flashing.append(_own(Flat.ball(_head, 0.13, Vector3(0, 0.14, 0), SKIN, true, 1.2)))
    # NOTE (mristin):
    # The grey fringe around the back of his bald head: a band, set back so
    # that its front hides inside the head; and the goatee.
    Flat.limb(_head, 0.15, 0.14, 0.1, Vector3(0, 0.11, 0.045), HAIR, false, 10)
    Flat.limb(_head, 0.035, 0.02, 0.07, Vector3(0, 0.0, -0.105), HAIR, false, 6)
    # The goggles (their strap a band around the head), the evil brows, the
    # nose and the grin.
    Flat.limb(_head, 0.138, 0.138, 0.035, Vector3(0, 0.17, 0), GOGGLES, false, 12)
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
        _flashing.append(_own(Flat.ball(shoulder, 0.075, Vector3.ZERO, COAT, true)))
        _flashing.append(
            _own(Flat.limb(shoulder, 0.068, 0.055, 0.3, Vector3(0, -0.15, 0), COAT, true))
        )
        var elbow := _pivot(shoulder, Vector3(0, -0.3, 0))
        Flat.ball(elbow, 0.055, Vector3.ZERO, COAT)
        Flat.limb(elbow, 0.053, 0.042, 0.26, Vector3(0, -0.13, 0), COAT)
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
