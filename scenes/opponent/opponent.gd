class_name Opponent
extends Node3D

## The opponent of a fight: one of the looks (see Looks), all on the same rig,
## so that all box alike.
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

## How long his counter to a wrong move takes, in seconds.
const COUNTER_SECONDS := 0.35

## How long he strikes and comes back after it lands, in seconds.
const STRIKE_SECONDS := 0.45

const MAX_HEALTH := 100.0

const RAGE := Color("ff9a1f")

var health := MAX_HEALTH

## Which look he has (see Looks.IDS); set it before he enters the scene.
var look := "scientist"

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
var _counter_left := 0.0

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


## The player made a wrong move: he counters at once, a quick jab.
func counter() -> void:
    if not _down:
        _counter_left = COUNTER_SECONDS


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
    _counter_left = maxf(0.0, _counter_left - delta)

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

    if _counter_left > 0.0:
        # NOTE (mristin):
        # The counter: his lead hand straight out, and back.
        var out := sin(_counter_left / COUNTER_SECONDS * PI)
        arm_left = [lerpf(0.55, 1.6, out), 0.0, lerpf(1.95, 0.05, out)]
        torso_yaw = -0.25 * out
        lunge = 0.5 * out
        speed = 30.0
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
    var parts := Looks.build(_body, look)
    _torso = parts["torso"]
    _head = parts["head"]
    _arms.assign(parts["arms"])
    _elbows.assign(parts["elbows"])
    _legs.assign(parts["legs"])
    _knees.assign(parts["knees"])
    _flashing.assign(parts["flashing"])
