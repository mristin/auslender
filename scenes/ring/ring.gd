class_name Ring
extends Node3D

## Box against the Rochartis scientist in the ring, in the first person: walk
## in place to walk where you head, and turn your body to your left or right
## to turn (see DESIGN.md). The prototype to find out whether that steers well.
##
## Every frame, we take the walking, the turn and the moves of the vision (or
## of the keyboard), move the player, throw her punches and kicks at the
## scientist (if he is within reach and in front of her), and decide whether
## his attacks hit her.
##
## Start it with [code]-- --replay=<recording.jsonl>[/code] to play a recorded
## video instead of the camera (see dev/replay/).
##
## The keyboard plays without the camera, too:
## [codeblock]
## W or Up (hold)             walk
## A, D or Left, Right        turn left, right
## J, K                       straight punch left, right
## U, I                       hook left, right
## H, L                       uppercut left, right
## N, M                       kick left, right
## Z (hold)                   duck
## X or Space                 jump
## C                          set the home spot again
## R                          fight again
## F1                         show what the vision sees
## F2                         show the camera picture more, or less
## F3                         show the camera picture (or the video) next to the game
## Escape                     quit
## [/codeblock]

## How far each move reaches, in meters from the player to the scientist.
const REACH := {
    "straight": 1.5,
    "hook": 1.3,
    "uppercut": 1.2,
    "front_kick": 1.85,
    "side_kick": 1.75,
}

## The player hits only what is within this angle of where she heads, in radians.
const AIM := 0.7

## Within this distance (in meters), the heading eases towards the scientist
## while the player does not turn, at this speed (in radians per second).
const LOCK_ON_DISTANCE := 2.6
const LOCK_ON_SPEED := 1.2

## His attacks miss if the player stepped this far from where he aimed, in meters.
const DODGE_DISTANCE := 0.45

## His attacks reach this far, in meters: he lunges, so he reaches farther
## than the player's punches, but not as far as her kicks.
const ATTACK_REACH := 2.0

## A jump this recent (in seconds) clears a low sweep.
const JUMP_WINDOW := 0.45

const _HIGH_DAMAGE := 10.0
const _LOW_DAMAGE := 8.0

const _KEYS_PUNCH := {
    KEY_J: ["straight", "left"],
    KEY_K: ["straight", "right"],
    KEY_U: ["hook", "left"],
    KEY_I: ["hook", "right"],
    KEY_H: ["uppercut", "left"],
    KEY_L: ["uppercut", "right"],
    KEY_N: ["front_kick", "left"],
    KEY_M: ["front_kick", "right"],
}

const _HELP := (
    "Keys: W walk, A D turn, J K punch, U I hook, H L uppercut, N M kick, Z duck, X jump,"
    + " R again, F1 debug, F2 camera, F3 video"
)

var vision: Node = null

## The stick of the keyboard, which wins over the room's while a key is held.
var keyboard_stick := Vector2.ZERO

var boxer: Boxer
var scientist: Scientist
var hud: Hud
var overlay: CameraOverlay

var _over_left := 0.0
var _last_jump_at := -10.0
var _time := 0.0
var _keyboard_duck := false
var _keyboard_jump_left := 0.0
var _opacities := [0.25, 0.5, 0.0]
var _opacity := 0


func _ready() -> void:
    add_child(Arena.new())

    scientist = Scientist.new()
    add_child(scientist)
    scientist.struck.connect(_on_struck)
    scientist.knocked_out.connect(_on_knocked_out)

    boxer = Boxer.new()
    add_child(boxer)

    overlay = CameraOverlay.new()
    add_child(overlay)
    hud = Hud.new()
    add_child(hud)
    hud.help = _HELP

    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        vision = holder.service
        overlay.setup(vision)
        if vision.IsReplaying():
            # NOTE (mristin):
            # A replay shows its video next to the game, and not dimly over it.
            overlay.show_pip = true
            overlay.opacity = 0.0
        else:
            vision.ResetPlayer()

    _start()


## Start the fight: both in their corners, full health.
func _start() -> void:
    scientist.global_position = Vector3(0, 0, -0.6)
    scientist.reset()
    boxer.reset(Vector3(0, 0, 1.4), scientist.global_position)
    _over_left = 0.0
    hud.banner = ""
    hud.say("FIGHT!", Hud.GOLD)


## Throw a move of the player at the scientist ("straight", "hook",
## "uppercut", "front_kick" or "side_kick"; "left" or "right"), as the vision
## or the keyboard found it.
func throw(kind: String, side: String, power: float) -> void:
    if _over_left > 0.0:
        return
    var hand := 0 if side == "left" else 1
    if kind.ends_with("kick"):
        boxer.kick(hand)
    else:
        boxer.punch(hand, kind)

    if not boxer.facing(scientist.global_position, AIM):
        hud.say("TURN TO HIM", Color(Hud.PAPER, 0.8))
        return
    var distance := _distance()
    if distance > REACH.get(kind, 1.3):
        hud.say("TOO FAR", Color(Hud.PAPER, 0.8))
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


## How far the player is from the scientist on the floor, in meters.
func _distance() -> float:
    var between := scientist.global_position - boxer.global_position
    between.y = 0.0
    return between.length()


func _process(delta: float) -> void:
    _time += delta
    _keyboard_jump_left = maxf(0.0, _keyboard_jump_left - delta)

    var stick := keyboard_stick
    var ducking := _keyboard_duck
    var jumping := _keyboard_jump_left > 0.0
    if vision != null:
        for move in vision.PollMoves():
            if move["kind"] == "jump":
                _last_jump_at = _time
            else:
                throw(move["kind"], move["side"], move["power"])
            _note_move(move)
        # NOTE (mristin):
        # The stick is the walking and the turn: x turns (negative to the
        # left), y walks.
        if stick == Vector2.ZERO:
            stick = Vector2(vision.GetTurn(), vision.GetWalkSpeed())
        ducking = ducking or vision.IsDucking()
        if vision.IsJumping():
            jumping = true
            _last_jump_at = _time

    if _over_left > 0.0:
        _over_left -= delta
        stick = Vector2.ZERO
        if _over_left <= 0.0:
            _start()

    scientist.target = boxer.global_position
    boxer.walk(maxf(0.0, stick.y), stick.x, delta, scientist.global_position)
    _lock_on(stick.x, delta)
    boxer.duck = lerpf(boxer.duck, 1.0 if ducking else 0.0, minf(1.0, delta * 12.0))
    boxer.jumping = jumping
    boxer.face(scientist.global_position, delta)
    if vision != null and overlay != null:
        boxer.set_hands(vision.GetPlayerHands(), vision.GetHeadRect())

    _update_hud(stick, ducking, jumping)


## Show the move over the picture in the picture.
func _note_move(move: Dictionary) -> void:
    var name: String = move["kind"]
    if move["side"] != "":
        name = "%s %s" % [move["side"], name]
    overlay.moves.append(name.replace("_", " ").to_upper())
    if overlay.moves.size() > 5:
        overlay.moves.pop_front()


## Ease the heading towards the scientist while the player does not turn and
## he is near, as boxers keep facing each other.
func _lock_on(turn: float, delta: float) -> void:
    if absf(turn) > 0.05 or _distance() > LOCK_ON_DISTANCE:
        return
    var towards := scientist.global_position - boxer.global_position
    var wanted := atan2(-towards.x, -towards.z)
    var difference := wrapf(wanted - boxer.heading, -PI, PI)
    boxer.heading += clampf(difference, -LOCK_ON_SPEED * delta, LOCK_ON_SPEED * delta)


func _update_hud(stick: Vector2, ducking: bool, jumping: bool) -> void:
    hud.player_health = boxer.health / Boxer.MAX_HEALTH
    hud.opponent_health = scientist.health / Scientist.MAX_HEALTH
    hud.stick = stick
    hud.ducking = ducking
    hud.jumping = jumping
    hud.hurt = boxer.hurt()
    var high: Variant = scientist.windup_high()
    hud.warning = "" if high == null else ("DUCK!" if high else "JUMP!")
    hud.warning_progress = scientist.windup_progress()
    overlay.threatened = high != null

    if vision == null:
        hud.sees_player = true
        hud.calibrated = true
        return
    var camera_on: bool = vision.GetStatus() != "Disabled"
    hud.sees_player = vision.HasPlayer() or not camera_on
    hud.calibrated = vision.IsCalibrated() or not camera_on
    hud.calibration_progress = vision.GetCalibrationProgress()
    hud.walking = vision.IsWalking()
    hud.cadence = vision.GetCadence()
    hud.knee_lift = vision.GetKneeLift()
    hud.turn_raw = vision.GetTurnRaw()
    hud.replay = vision.GetReplayTime() if vision.IsReplaying() else Vector2(-1, -1)
    hud.room_offset = vision.GetRoomOffset()
    hud.stick_limits = vision.GetStickLimits()
    hud.sees_feet = vision.SeesFeet() or not camera_on
    hud.status = VisionStatus.new().text(vision, true)


func _on_struck(high: bool, aimed_at: Vector3) -> void:
    if _over_left > 0.0:
        return
    var stepped := boxer.global_position.distance_to(aimed_at) >= DODGE_DISTANCE
    if _distance() > ATTACK_REACH or stepped:
        hud.say("STEPPED AWAY!", Hud.GREEN)
        return
    if high and boxer.duck > 0.5:
        hud.say("DUCKED!", Hud.GREEN)
        return
    if not high and _time - _last_jump_at <= JUMP_WINDOW:
        hud.say("JUMPED!", Hud.GREEN)
        return
    boxer.take_damage(_HIGH_DAMAGE if high else _LOW_DAMAGE)
    hud.say("OUCH!", Hud.RED)
    if boxer.health <= 0.0:
        hud.banner = "DOWN!"
        _over_left = 4.0


func _on_knocked_out() -> void:
    hud.banner = "K.O.!"
    _over_left = 4.0


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key := event as InputEventKey
    _update_keyboard_stick()
    if key.keycode == KEY_Z:
        _keyboard_duck = key.pressed
    if not key.pressed or key.echo:
        return
    if _KEYS_PUNCH.has(key.keycode):
        var move: Array = _KEYS_PUNCH[key.keycode]
        throw(move[0], move[1], 0.8)
    match key.keycode:
        KEY_X, KEY_SPACE:
            _keyboard_jump_left = 0.5
            _last_jump_at = _time
        KEY_R:
            _start()
        KEY_F1:
            overlay.debug = not overlay.debug
        KEY_F3:
            overlay.show_pip = not overlay.show_pip
        KEY_F2:
            _opacity = (_opacity + 1) % _opacities.size()
            overlay.opacity = _opacities[_opacity]
        KEY_ESCAPE:
            get_tree().quit()


func _update_keyboard_stick() -> void:
    var x := 0.0
    var y := 0.0
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        y += 1.0
    keyboard_stick = Vector2(x, y)
