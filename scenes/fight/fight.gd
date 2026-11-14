class_name Fight
extends Node3D

## Box against the Rochartis scientist in the ring, in the first person, on
## your spot (see DESIGN.md): the prototype of the fights.
##
## The player never walks: the scientist steps in to attack and steps back
## out. Every frame, we take the moves of the vision (or of the keyboard),
## throw her punches and kicks at him (if he is within their reach), and
## decide whether his attacks hit her: a jab is stopped by covering the head
## with both gloves, a hook is slipped by leaning away from it, anything high
## is ducked, and a low sweep is jumped.
##
## The move classifier of the vision (see MoveClassifier) tells the
## straights, the hooks, the uppercuts and the kicks (a knee raised high:
## the camera need not see the whole leg) apart, and finds the slips, the
## ducks, the jumps and the cover from the whole body.
##
## Start it with [code]-- --replay=<recording.jsonl>[/code] to play a recorded
## video instead of the camera (see dev/replay/).
##
## The keyboard plays without the camera, too:
## [codeblock]
## J, K                       straight punch left, right
## U, I                       hook left, right
## H, L                       uppercut left, right
## N, M                       kick left, right
## Q, E (hold)                lean (slip) left, right
## Z (hold)                   duck
## B (hold)                   cover the head (stops a jab)
## X or Space                 jump
## C                          set the home spot again
## R                          fight again
## F1                         show what the vision sees
## F2                         show the mirror (the camera picture) more, or less
## Escape                     quit
## [/codeblock]

## How far each move reaches, in meters from the player to the scientist: the
## punches reach him only when he stepped in, the kicks also when he waits out.
const REACH := {
    "straight": 1.6,
    "hook": 1.5,
    "uppercut": 1.45,
    "kick": 2.45,
}

## Where the player stands.
const SPOT := Vector3(0, 0, 1.5)

## A lean this far (in units, about the shoulder width) slips a punch, as
## LeanGauge.SlipFrom.
const SLIP_FROM := 0.5

## A jump this recent (in seconds) clears a low sweep.
const JUMP_WINDOW := 0.45

## With the move classifier, a duck or a slip counts this long after it was
## found, in seconds: the classifier finds the move, not how long she holds it.
const DUCK_HOLD := 0.7
const SLIP_HOLD := 0.6

## The damage of his attacks: when they land, and a jab on the gloves.
const DAMAGE := {"jab": 7.0, "hook_left": 10.0, "hook_right": 10.0, "sweep": 8.0}
const COVERED_DAMAGE := 1.5

## The call and the direction of each attack, as the player sees it.
const CALLS := {
    "jab": ["COVER!", "front"],
    "hook_left": ["SLIP RIGHT!", "left"],
    "hook_right": ["SLIP LEFT!", "right"],
    "sweep": ["JUMP!", "low"],
}

const _KEYS_PUNCH := {
    KEY_J: ["straight", "left"],
    KEY_K: ["straight", "right"],
    KEY_U: ["hook", "left"],
    KEY_I: ["hook", "right"],
    KEY_H: ["uppercut", "left"],
    KEY_L: ["uppercut", "right"],
    KEY_N: ["kick", "left"],
    KEY_M: ["kick", "right"],
}

const _HELP := (
    "Keys: J K punch, U I hook, H L uppercut, N M kick, Q E slip, Z duck, B cover, X jump,"
    + " C home, R again, F1 debug, F2 mirror"
)

var vision: Node = null

var boxer: Boxer
var scientist: Scientist
var hud: Hud
var overlay: CameraOverlay

var _over_left := 0.0
var _last_jump_at := -10.0
var _last_duck_at := -10.0
var _last_slip_at := {"left": -10.0, "right": -10.0}
var _time := 0.0
var _keyboard_jump_left := 0.0
var _opacities := [0.3, 0.5, 0.15]
var _opacity := 0


func _ready() -> void:
    add_child(Arena.new())

    scientist = Scientist.new()
    add_child(scientist)
    scientist.struck.connect(_on_struck)
    scientist.knocked_out.connect(_on_knocked_out)

    boxer = Boxer.new()
    add_child(boxer)
    boxer.global_position = SPOT

    overlay = CameraOverlay.new()
    add_child(overlay)
    hud = Hud.new()
    add_child(hud)
    hud.help = _HELP

    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        vision = holder.service
        overlay.setup(vision)
        if not vision.IsReplaying():
            vision.ResetPlayer()

    _start()


## Start the fight: him out of reach, both at full health.
func _start() -> void:
    scientist.global_position = SPOT + Vector3(0, 0, -Scientist.OUT_DISTANCE)
    scientist.target = SPOT
    scientist.reset()
    boxer.reset()
    _over_left = 0.0
    hud.banner = ""
    hud.say("FIGHT!", Hud.GOLD)


## Throw a move of the player at the scientist ("straight", "hook",
## "uppercut" or "kick"; "left" or "right"), as the vision
## or the keyboard found it.
func throw(kind: String, side: String, power: float) -> void:
    if _over_left > 0.0:
        return
    var hand := 0 if side == "left" else 1
    if kind == "kick":
        boxer.kick(hand)
    else:
        boxer.punch(hand, kind)

    if scientist.distance() > REACH.get(kind, 1.5):
        hud.say("TOO FAR: KICK!", Color(Hud.PAPER, 0.8))
        return
    var outcome: Dictionary = scientist.take_hit(kind, power)
    match outcome["result"]:
        "blocked":
            hud.say("BLOCKED", Color("9db4d0"))
        "open":
            hud.say("%s!" % _name(kind).to_upper(), Hud.GOLD)
        "hit":
            hud.say(_name(kind).to_upper(), Hud.PAPER)


func _name(kind: String) -> String:
    return kind.replace("_", " ")


func _process(delta: float) -> void:
    _time += delta
    _keyboard_jump_left = maxf(0.0, _keyboard_jump_left - delta)

    var lean := 0.0
    if Input.is_key_pressed(KEY_Q):
        lean -= 0.6
    if Input.is_key_pressed(KEY_E):
        lean += 0.6
    var ducking := Input.is_key_pressed(KEY_Z)
    var covering := Input.is_key_pressed(KEY_B)
    var jumping := _keyboard_jump_left > 0.0

    if vision != null:
        for move in vision.PollMoves():
            match move["kind"]:
                "jump":
                    _last_jump_at = _time
                "duck":
                    _last_duck_at = _time
                "slip":
                    _last_slip_at[move["side"]] = _time
                _:
                    throw(move["kind"], move["side"], move["power"])
        if lean == 0.0:
            # NOTE (mristin):
            # The lean against where the player stood lately (see
            # LeanGauge), in units, positive to her right: not against the
            # home spot, since she drifts off it.
            lean = vision.GetLean()
        # NOTE (mristin):
        # The classifier finds the slips, the ducks and the jumps from the
        # whole body, and the cover; the head alone is fooled by where the
        # camera stands (e.g., on the floor).
        if _time - _last_slip_at["left"] <= SLIP_HOLD:
            lean = minf(lean, -0.8)
        elif _time - _last_slip_at["right"] <= SLIP_HOLD:
            lean = maxf(lean, 0.8)
        ducking = ducking or _time - _last_duck_at <= DUCK_HOLD
        covering = covering or vision.IsCovering()
        jumping = jumping or _time - _last_jump_at <= JUMP_WINDOW

    if _over_left > 0.0:
        _over_left -= delta
        if _over_left <= 0.0:
            _start()

    scientist.target = SPOT
    boxer.lean = lerpf(boxer.lean, clampf(lean, -1.0, 1.0), minf(1.0, delta * 14.0))
    boxer.duck = lerpf(boxer.duck, 1.0 if ducking else 0.0, minf(1.0, delta * 12.0))
    boxer.jumping = jumping
    boxer.covering = covering
    boxer.face(scientist.global_position, delta)
    if vision != null and overlay != null:
        boxer.set_hands(vision.GetPlayerHands(), vision.GetHeadRect())

    _update_hud(lean, ducking, jumping, covering)


func _update_hud(lean: float, ducking: bool, jumping: bool, covering: bool) -> void:
    hud.player_health = boxer.health / Boxer.MAX_HEALTH
    hud.opponent_health = scientist.health / Scientist.MAX_HEALTH
    hud.hurt = boxer.hurt()
    var attack := scientist.windup_attack()
    hud.warning = "" if attack == "" else CALLS[attack][0]
    hud.warning_from = "" if attack == "" else CALLS[attack][1]
    hud.warning_progress = scientist.windup_progress()

    # NOTE (mristin):
    # What the player's body does shows on the mirror, on her head, and not
    # in a box of its own (as in Splash 'n' Splat).
    overlay.threatened = attack != ""
    overlay.pose = _pose(lean, ducking, jumping, covering)

    if vision == null:
        hud.sees_player = true
        return
    var camera_on: bool = vision.GetStatus() != "Disabled"
    hud.sees_player = vision.HasPlayer() or not camera_on
    overlay.calibrated = vision.IsCalibrated() or not camera_on
    overlay.calibration_progress = vision.GetCalibrationProgress()
    hud.replay = vision.GetReplayTime() if vision.IsReplaying() else Vector2(-1, -1)
    hud.sees_feet = vision.SeesFeet() or not camera_on
    hud.status = VisionStatus.new().text(vision, true)


## The dodge which counts now, by its name ("" if none).
func _pose(lean: float, ducking: bool, jumping: bool, covering: bool) -> String:
    if jumping:
        return "JUMP"
    if ducking:
        return "DUCK"
    if covering:
        return "COVER"
    if lean <= -SLIP_FROM:
        return "SLIP LEFT"
    if lean >= SLIP_FROM:
        return "SLIP RIGHT"
    return ""


## Decide whether his attack hits: how the player dodges it, by the attack.
func _on_struck(attack: String) -> void:
    if _over_left > 0.0:
        return
    var dodge := _dodge(attack)
    if dodge != "":
        scientist.dodged()
        hud.say(dodge, Hud.GREEN)
        return
    if attack == "jab" and boxer.covering:
        boxer.take_damage(COVERED_DAMAGE, true)
        hud.say("COVERED!", Hud.GREEN)
        return
    boxer.take_damage(DAMAGE[attack])
    hud.say("OUCH!", Hud.RED)
    if boxer.health <= 0.0:
        hud.banner = "DOWN!"
        _over_left = 4.0


## How the player dodged the attack ("SLIPPED!", "DUCKED!", "JUMPED!"), or ""
## if she did not.
func _dodge(attack: String) -> String:
    if attack == "sweep":
        var jumped := boxer.jumping or _time - _last_jump_at <= JUMP_WINDOW
        return "JUMPED!" if jumped else ""

    # NOTE (mristin):
    # A hook from her left is slipped by leaning away from it, to her right;
    # a jab by leaning to either side.
    var away := {"jab": 0.0, "hook_left": 1.0, "hook_right": -1.0}
    var direction: float = away[attack]
    var lean := boxer.lean
    var slipped := absf(lean) >= SLIP_FROM if direction == 0.0 else lean * direction >= SLIP_FROM
    if slipped:
        return "SLIPPED!"
    return "DUCKED!" if boxer.duck > 0.5 else ""


func _on_knocked_out() -> void:
    hud.banner = "K.O.!"
    _over_left = 4.0


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key := event as InputEventKey
    if not key.pressed or key.echo:
        return
    if _KEYS_PUNCH.has(key.keycode):
        var move: Array = _KEYS_PUNCH[key.keycode]
        throw(move[0], move[1], 0.8)
    match key.keycode:
        KEY_X, KEY_SPACE:
            _keyboard_jump_left = 0.5
            _last_jump_at = _time
        KEY_C:
            if vision != null:
                vision.Recalibrate()
        KEY_R:
            _start()
        KEY_F1:
            overlay.debug = not overlay.debug
        KEY_F2:
            _opacity = (_opacity + 1) % _opacities.size()
            overlay.opacity = _opacities[_opacity]
        KEY_ESCAPE:
            get_tree().quit()
