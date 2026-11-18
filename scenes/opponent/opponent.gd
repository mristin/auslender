class_name Opponent
extends Node3D

## The opponent of a fight: one of the looks (see Looks), all on the same rig,
## so that all box alike.
##
## A brawl (see Brawl) moves him: he bobs to the music ([method groove]); the
## brawl shows his attacks with [method perform], so that he winds up through
## [member windup_seconds] before it lands, and strikes then: the wind-up is
## his tell, quiet but clear (he draws the arm back slowly, shifts his weight,
## and a faint glint creeps over him), never an alarm. His guard shows where
## the player's punches land ([method open_for]); a punch into his guard is
## blocked ([method block]); he flinches when the player's
## punches land ([method flinch]): his head snaps aside from a hook, back from
## a straight, up from an uppercut, and a kick knocks him back a step; and at
## the end, a boss goes down ([method knock_out]), while the opponents on the
## road turn and run away ([method flee]): the game does not knock them out.
## He moves as people move: his guard, his punches, his slips and his cover
## are captured from people (see Moves). He is never still: he bounces on the
## beat and sways from side to side over each bar ([method groove]),
## steps in as he winds up; he slips aside, mocking, when the player misses
## ([method evade]), stumbles past when the player dodges him ([method
## stumble]: a small step, his guard up), throws up his arms when his attack
## lands ([method cheer]), and beckons the player in and shimmies in the
## breathers ([method show_off]).
## He faces the player all the time; his front is -Z, as in Godot.
##
## His attacks, and how the player dodges them: a jab straight at the face
## (cover), a hook from the player's left (slip right) or right (slip left), a
## wild haymaker at head height (duck), and a low sweep of his leg (jump).

## How long he winds up before an attack lands, in seconds, by default (see
## [member windup_seconds]).
const WINDUP_SECONDS := 0.6

## How long his counter to a wrong move takes, in seconds.
const COUNTER_SECONDS := 0.35

## How long he strikes and comes back after it lands, in seconds.
const STRIKE_SECONDS := 0.45

const MAX_HEALTH := 100.0

const RAGE := Color("ff9a1f")

## How fast he runs away (see [method flee]), in meters a second (faster than
## the hero runs, see RhythmLevel.SPEED), and how long he runs off to the
## side before he runs straight away, in seconds.
const FLEE_SPEED := 5.0
const FLEE_ASIDE := 1.1

## His attacks, by the captured moves (see Moves) which he throws them with:
## a hook from the player's left is his right hook, and so on; the haymaker is
## a wilder cross, over the top.
const ATTACK_CLIPS := {
    "jab": "jab",
    "hook_left": "hook_right",
    "hook_right": "hook_left",
    "haymaker": "cross",
}

## How he draws back for his attacks over the wind-up, the tell of the brawl
## (see Brawl), over the start of the captured move: the arm (0: his left),
## its pose as in [method _set_arm], and the turn of his torso.
const WINDUPS := {
    "jab": [0, [0.3, 0.1, 2.4], 0.25],
    "hook_left": [1, [0.5, 1.2, 1.4], -0.45],
    "hook_right": [0, [0.5, 1.2, 1.4], 0.45],
    "haymaker": [1, [1.2, 0.8, 1.5], -0.4],
}

## How far he steps into his punch as it lands, in meters, so that his glove
## (not his chest) reaches the player.
const STRIKE_REACH := 0.22

## How long he slips aside when the player misses, in seconds, and how much of
## the captured slip (which is wide) he does.
const EVADE_SECONDS := 0.6
const SLIP_SHARE := 0.75

## How long his thigh and his shin are (see Looks), in meters of his rig.
const THIGH := 0.46
const SHIN := 0.42

## The glint which creeps over him as he winds up: faint and warm, a hint
## rather than an alarm.
const TELL := Color("ffd9a0")
const TELL_MOST := 0.14

var health := MAX_HEALTH

## Which look he has (see Looks.IDS); set it before he enters the scene.
var look := "scientist"

## The seed of his random colors and size (see Looks.recolor; negative: his
## own colors); set it before he enters the scene.
var tint := -1

## Whether he runs (on the road, towards the hero; see Encounters), rather
## than stands in his guard.
var running := false

## Where the player is, which the fight tells him on every frame.
var target := Vector3.ZERO

## How long he winds up before an attack lands, in seconds (see Brawl).
var windup_seconds := WINDUP_SECONDS

var _attack := ""
var _share := 1.0
var _beat := 0.0
var _down := false
## Whether he runs away (see [method flee]), since when, and to which side.
var _fleeing := false
var _fled_for := 0.0
var _flee_side := 1.0
var _time := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _head_kick := Vector3.ZERO
## The head's pose of the moves, without the snap of a punch.
var _head_pose := Vector3.ZERO
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
var _open := ""
var _open_side := ""
var _block_left := 0.0

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
    _fleeing = false
    _raging = false
    _knock = 0.0
    _evade_left = 0.0
    _stumble_left = 0.0
    _cheer_left = 0.0
    _block_left = 0.0
    _showing_off = false
    _open = ""


## Move to the music: [param phase] is how far the current beat is, in [0,
## 1), and [param bar] how far the current bar is, in [0, 1): he bounces on
## every beat and sways over to one side and back over two bars.
func groove(phase: float, bar: float, bar_index: int) -> void:
    _beat = phase
    var over_two := (float(bar_index % 2) + bar) * 0.5
    _sway_x = 0.22 * sin(over_two * TAU)


## Open his guard where the player's next punch is to land ([param kind]:
## "straight", "hook" or "uppercut"; [param side]: the player's hand; "" for
## his usual guard): for a jab, his arms wide, the middle open; for a hook,
## one arm covering the other side of his head, the side of the hook open;
## for an uppercut, a high guard, his gloves at his forehead, the chin open;
## "open" for his guard down altogether (winded, after he missed).
func open_for(kind: String, side: String) -> void:
    _open = kind
    _open_side = side


## Show off (in a breather): beckon the player in, and shimmy.
func show_off(on: bool) -> void:
    _showing_off = on


## The player missed: slip aside from his punch, mocking ([param side]: the
## player's hand).
func evade(side: String) -> void:
    if _down:
        return
    _evade_left = EVADE_SECONDS
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


## The player's punch hit his guard: he tightens it with a jolt.
func block() -> void:
    if not _down:
        _block_left = 0.25
        _flash = 0.25
        _flash_color = Color.WHITE


## The player made a wrong move: he counters at once, a quick jab.
func counter() -> void:
    if not _down:
        _counter_left = COUNTER_SECONDS


## Show his attack ("jab", "hook_left", "hook_right", "haymaker" or "sweep";
## "" for none) at [param seconds] from the moment it lands (negative before
## it): he winds up in the last [member windup_seconds], strikes then, and
## comes back.
func perform(attack: String, seconds: float) -> void:
    if seconds < -windup_seconds or seconds > STRIKE_SECONDS:
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


## Go down: the knock-out (of a boss).
func knock_out() -> void:
    _down = true
    _attack = ""


## Give up and run away (an opponent on the road; see Brawl): he turns, runs
## off to the side and then straight on down the road, faster than the hero,
## looking back over his shoulder now and then. He moves himself.
func flee() -> void:
    _down = true
    _fleeing = true
    _fled_for = 0.0
    _attack = ""
    _flee_side = 1.0 if global_position.x >= target.x else -1.0


## Whether he runs away (see [method flee]).
func fleeing() -> bool:
    return _fleeing


func _process(delta: float) -> void:
    _time += delta
    if _fleeing:
        _run_away(delta)
    elif running:
        _face_target()
        _run_cycle(delta, _time * 9.0, 0.0)
    else:
        _face_target()
        _animate(delta)
    _flash = maxf(0.0, _flash - delta * 4.0)
    var glow := _flash
    var color := _flash_color
    if _attack != "" and _share < 0.0 and _flash <= 0.0:
        # NOTE (mristin):
        # A faint warm glint creeps over him through the second half of the
        # wind-up: a hint for who watches him, not an alarm.
        var p := clampf(1.0 + _share / windup_seconds, 0.0, 1.0)
        glow = TELL_MOST * smoothstep(0.4, 1.0, p)
        color = TELL
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


## Run away (see [method flee]): off to the side, then straight on down the
## road (-Z), away from the hero; arms pumping, legs striding, leaning into
## the run, and a glance back over the shoulder now and then.
func _run_away(delta: float) -> void:
    _fled_for += delta
    var aside := clampf(1.0 - (_fled_for - FLEE_ASIDE) / 0.5, 0.0, 1.0)
    var heading := Vector3(_flee_side * 0.8 * aside, 0, -1).normalized()
    # NOTE (mristin):
    # He gets going in the first moments.
    var speed := FLEE_SPEED * smoothstep(0.0, 0.4, _fled_for)
    global_position += heading * speed * delta
    var turned := atan2(heading.x, heading.z) + PI
    rotation.y = lerp_angle(rotation.y, turned, minf(1.0, delta * 10.0))

    # NOTE (mristin):
    # A scared glance back every second or so.
    var glance := smoothstep(0.6, 0.9, sin(_fled_for * 2.8)) * 1.1
    _run_cycle(delta, _fled_for * 9.0, glance * _flee_side)


## Stride as he runs, at the [param stride] (radians of the cycle), his head
## turned by [param look] (to look back over his shoulder).
func _run_cycle(delta: float, stride: float, look: float) -> void:
    var swing := sin(stride)
    var weight := minf(1.0, delta * 20.0)
    for i in range(2):
        var phase := swing if i == 0 else -swing
        var outwards := -1.0 if i == 0 else 1.0
        _arms[i].rotation.x = lerpf(_arms[i].rotation.x, 0.25 + 0.9 * phase, weight)
        _arms[i].rotation.z = lerpf(_arms[i].rotation.z, 0.15 * outwards, weight)
        _elbows[i].rotation.x = lerpf(_elbows[i].rotation.x, 1.5, weight)
        _legs[i].rotation.x = lerpf(_legs[i].rotation.x, -0.75 * phase, weight)
        _knees[i].rotation.x = lerpf(_knees[i].rotation.x, -(0.4 + 0.8 * maxf(0.0, phase)), weight)
    _torso.rotation = _torso.rotation.lerp(Vector3(0.3, 0.12 * swing, 0.0), weight)
    _head.rotation = _head.rotation.lerp(Vector3(0.0, look, 0.0), weight)
    _body.rotation = _body.rotation.lerp(Vector3.ZERO, weight)
    _body.position = Vector3(0, 0.06 * absf(cos(stride)), 0)


## Move the limbs towards the pose of the moment. Its ground is the guard of
## the moves captured from people (see Moves), looped; his attacks, his
## counter, his slips and his cover play their captured moves over it; his
## guard's openings, his cheering, his showing off and his stumbling are
## poses of their own, as the brawl needs them to be read.
func _animate(delta: float) -> void:
    var pose := Moves.sample("guard", _time, true)
    var speed := 14.0
    var lunge := 0.0
    var torso_yaw := 0.0
    var torso_pitch := 0.0
    var torso_roll := 0.0

    # NOTE (mristin):
    # He bobs down on every beat, and sways with the bars.
    var bob := -0.03 * pow(1.0 - _beat, 3.0)
    var side_shift := _sway_x
    torso_roll -= _sway_x * 0.15
    _evade_left = maxf(0.0, _evade_left - delta)
    _stumble_left = maxf(0.0, _stumble_left - delta)
    _cheer_left = maxf(0.0, _cheer_left - delta)
    _counter_left = maxf(0.0, _counter_left - delta)
    _block_left = maxf(0.0, _block_left - delta)

    var cover := Moves.sample("cover", Moves.length("cover"))
    match _open:
        # NOTE (mristin):
        # The openings of his guard are clear poses (the player reads where
        # to punch from them), the rest of him in his guard.
        "straight":
            _set_arm(pose, 0, [0.6, 0.6, 1.6])
            _set_arm(pose, 1, [0.6, 0.6, 1.6])
        "uppercut":
            # NOTE (mristin):
            # A high guard: his gloves at his forehead, as people cover.
            pose = _with_arms(pose, cover, 1.0)
            torso_pitch -= 0.05
        "hook":
            # NOTE (mristin):
            # The player's left hook lands on his right side (on the player's
            # left): his right arm drops, his left one covers his left side;
            # and the other way round.
            var high := [1.1, 0.5, 2.2]
            var low := [0.35, 0.25, 1.3]
            _set_arm(pose, 0, high if _open_side == "left" else low)
            _set_arm(pose, 1, low if _open_side == "left" else high)
        "open":
            # NOTE (mristin):
            # Winded: his gloves sag, and he hangs forward.
            _set_arm(pose, 0, [0.3, 0.3, 1.1])
            _set_arm(pose, 1, [0.3, 0.3, 1.1])
            torso_pitch += 0.2
            bob -= 0.04
    if _block_left > 0.0:
        # NOTE (mristin):
        # He snaps into his cover, and rocks back.
        pose = _with_arms(pose, cover, sin(_block_left / 0.25 * PI * 0.5) * 0.5 + 0.5)
        lunge = -0.06 * sin(_block_left / 0.25 * PI)
        speed = 25.0
    if _showing_off:
        # NOTE (mristin):
        # He beckons with his left glove (the elbow pumping), and shimmies.
        _set_arm(pose, 0, [1.35, 0.1, 0.9 + 0.7 * sin(_time * 9.0)])
        torso_yaw += 0.2 * sin(_time * 12.0)
    if _cheer_left > 0.0:
        _set_arm(pose, 0, [3.0, 0.35, 0.3])
        _set_arm(pose, 1, [3.0, 0.35, 0.3])
        torso_pitch -= 0.15
        bob += 0.06 * absf(sin(_time * 14.0))
    if _evade_left > 0.0:
        # NOTE (mristin):
        # He slips aside as people slip, a little less far, and quicker.
        var clip := "slip_left" if _evade_side < 0.0 else "slip_right"
        var done := 1.0 - _evade_left / EVADE_SECONDS
        pose = Moves.mix(pose, Moves.sample(clip, done * Moves.length(clip)), SLIP_SHARE)
        speed = 24.0
    if _stumble_left > 0.0:
        var stumble := sin(_stumble_left / 0.6 * PI)
        lunge = 0.1 * stumble
        torso_pitch += 0.1 * stumble

    if _attack != "":
        var p := smoothstep(0.0, 1.0, clampf(1.0 + _share / windup_seconds, 0.0, 1.0))
        if _attack == "sweep":
            pose = _sweep(pose, p)
        else:
            var clip: String = ATTACK_CLIPS[_attack]
            pose = Moves.sample(clip, _attack_time(clip))
            var drawn := _drawn_back(clip)
            if drawn > 0.0:
                var windup: Array = WINDUPS[_attack]
                var drawn_pose := pose.duplicate()
                _set_arm(drawn_pose, windup[0], windup[1])
                pose = _with_arms(pose, drawn_pose, drawn)
                torso_yaw += float(windup[2]) * drawn
            if _attack == "haymaker":
                # NOTE (mristin):
                # Wilder than a cross: wound up wider, swung over the top.
                pose[Moves.ARMS + 5] += 0.35 * p * float(_share < 0.0)
                pose[Moves.ARMS + 6] += 0.3 * p
        # NOTE (mristin):
        # He steps in as he winds up, back to the middle, and through the
        # punch, so that his glove reaches the player.
        speed = 30.0
        lunge = (0.08 * p) if _share < 0.0 else STRIKE_REACH
        side_shift *= 1.0 - p

    if _counter_left > 0.0:
        # NOTE (mristin):
        # The counter: a quick jab, from its chambering on.
        var start := Moves.hit("jab") * 0.4
        var done := 1.0 - _counter_left / COUNTER_SECONDS
        pose = Moves.sample("jab", start + done * (Moves.length("jab") - start) * 0.8)
        lunge = STRIKE_REACH * sin(done * PI)
        speed = 30.0
        side_shift *= 0.5

    if _down:
        _set_arm(pose, 0, [-0.2, 1.2, 0.3])
        _set_arm(pose, 1, [-0.2, 1.2, 0.3])
        _body.rotation.x = lerpf(_body.rotation.x, PI * 0.5, minf(1.0, delta * 3.0))
        _body.position.y = lerpf(_body.position.y, 0.15, minf(1.0, delta * 3.0))

    var weight := minf(1.0, delta * speed)
    for i in range(2):
        var a := Moves.ARMS + 4 * i
        _arms[i].rotation = _arms[i].rotation.lerp(
            Vector3(pose[a + 1], pose[a], pose[a + 2]), weight
        )
        _elbows[i].rotation.x = lerpf(_elbows[i].rotation.x, pose[a + 3], weight)
        var l := Moves.LEGS + 3 * i
        _legs[i].rotation.x = lerpf(_legs[i].rotation.x, pose[l], weight)
        _legs[i].rotation.z = lerpf(_legs[i].rotation.z, pose[l + 1], weight)
        _knees[i].rotation.x = lerpf(_knees[i].rotation.x, pose[l + 2], weight)
    var torso := Vector3(
        pose[Moves.TORSO] + torso_pitch,
        pose[Moves.TORSO + 1] + torso_yaw,
        pose[Moves.TORSO + 2] + torso_roll
    )
    _torso.rotation = _torso.rotation.lerp(torso, weight)
    # NOTE (mristin):
    # A punch snaps his head, which comes back slowly.
    _head_kick = _head_kick.lerp(Vector3.ZERO, minf(1.0, delta * 5.0))
    var head := Vector3(pose[Moves.HEAD], pose[Moves.HEAD + 1], pose[Moves.HEAD + 2])
    _head_pose = _head_pose.lerp(head, weight)
    _head.rotation = _head_pose + _head_kick
    _knock = lerpf(_knock, 0.0, minf(1.0, delta * 3.0))
    if not _down:
        var at := Vector3(
            side_shift + pose[Moves.OFFSET],
            _standing() + bob,
            -lunge + _knock + pose[Moves.OFFSET + 2]
        )
        _body.position = _body.position.lerp(at, weight)


## Where his attack of the [param clip] is now, in the clip's time: the
## captured move is quick (a punch takes a few tenths of a second), but his
## wind-up is long, as the tell of the brawl (see Brawl): he chambers the
## punch slowly over the wind-up (the first part of the move), then throws it
## so that it lands on time, and comes back within STRIKE_SECONDS.
func _attack_time(clip: String) -> float:
    var impact := Moves.hit(clip)
    var chambered := impact * 0.35
    if _share >= 0.0:
        return impact + _share / STRIKE_SECONDS * (Moves.length(clip) - impact)
    if _share >= -impact:
        return chambered + (impact - chambered) * (1.0 + _share / impact)
    var loading := clampf(1.0 + (_share + impact) / maxf(windup_seconds - impact, 0.01), 0.0, 1.0)
    return chambered * smoothstep(0.0, 1.0, loading)


## How far he has drawn back for his attack of the [param clip] (in [0, 1]):
## more and more over the wind-up, and let go as he throws it.
func _drawn_back(clip: String) -> float:
    var impact := Moves.hit(clip)
    if _share >= -impact:
        return clampf(-_share / impact, 0.0, 1.0) * 0.8
    var loading := clampf(1.0 + _share / windup_seconds, 0.0, 1.0)
    return smoothstep(0.0, 1.0, loading) * 0.8


## The low sweep of his right leg (wound up by [param p] before it lands): no
## person in the recordings swept, so it is a pose of its own.
func _sweep(pose: PackedFloat32Array, p: float) -> PackedFloat32Array:
    var leg := Moves.LEGS + 3
    if _share < 0.0:
        pose[leg] = -0.6 * p
        pose[leg + 2] = -0.9 * p
        pose[Moves.TORSO] -= 0.1
    else:
        pose[leg] = 1.1
        pose[leg + 1] = 0.0
        pose[leg + 2] = -0.1
        pose[Moves.TORSO] -= 0.2
    return pose


## Set the arm of the [param index] (0: his left) of the [param pose] to a
## pose of the brawl: [shoulder pitch, shoulder roll outwards, elbow pitch].
static func _set_arm(pose: PackedFloat32Array, index: int, arm: Array) -> void:
    var a := Moves.ARMS + 4 * index
    var outwards := -1.0 if index == 0 else 1.0
    pose[a] = 0.0
    pose[a + 1] = arm[0]
    pose[a + 2] = arm[1] * outwards
    pose[a + 3] = arm[2]


## The [param pose] with its arms moved towards those of [param other], by
## [param weight].
static func _with_arms(
    pose: PackedFloat32Array, other: PackedFloat32Array, weight: float
) -> PackedFloat32Array:
    for i in range(Moves.ARMS, Moves.ARMS + 8):
        pose[i] = lerpf(pose[i], other[i], weight)
    return pose


## How high his body stands now: as low as his bent legs carry it, so that
## his lower foot stays on the ground.
func _standing() -> float:
    var reach := 0.0
    for i in range(2):
        var hip := _legs[i].rotation.x
        reach = maxf(reach, THIGH * cos(hip) + SHIN * cos(hip + _knees[i].rotation.x))
    return -(THIGH + SHIN - reach) * _body.scale.y


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
    if tint >= 0:
        Looks.recolor(_body, parts, tint)
        var random := RandomNumberGenerator.new()
        random.seed = tint + 1
        scale = Vector3.ONE * random.randf_range(0.92, 1.08)


## The pose between two poses of a limb (arrays of angles), by [param weight].
static func _mix(from: Array, to: Array, weight: float) -> Array:
    var mixed := []
    for i in range(from.size()):
        mixed.append(lerpf(from[i], to[i], weight))
    return mixed
