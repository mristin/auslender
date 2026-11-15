class_name BodyReader
extends RefCounted

## Read the player's body for a rhythm level (see Fight), from the vision or
## the keyboard: the punches which the move classifier found, the dodges he
## is in (the lean, the duck, the jump, the cover), and in a run the lane in
## which he stands.
##
## The classifier finds the slips, the ducks and the jumps from the whole body
## (the head alone is fooled by where the camera stands); it finds a move, not
## how long he holds it, so each counts for a moment after it was found.
##
## Where he is across the road (in a run) is where his torso is across the
## camera picture (the middle of his shoulders and his hips), absolutely, as a
## mouse: in the middle of the picture, he runs in the middle lane; he moves
## across the road as he moves across the picture, continuously, as the
## penguin of Antarctic Adventure. The keyboard steers with the arrows (or A
## and D), gliding.

## A lean this far (in units, about the shoulder width) is a slip, as
## LeanGauge.SlipFrom.
const SLIP_FROM := 0.5

## How long a found duck, slip or jump counts, in seconds.
const DUCK_HOLD := 0.7
const SLIP_HOLD := 0.6
const JUMP_HOLD := 0.5

## How long a found jump keeps him in the air in a run, in seconds: a flight,
## as in Quake (see Boxer.jump_seconds).
const RUN_JUMP_HOLD := 2.0

## How far from the middle of the picture (a share of its width) his torso
## moves him a lane's width over, and how far beyond the outer lanes he may go
## (in lanes).
const STEER_LANE := 0.1
const STEER_MOST := 1.3

## How fast the keys glide him across, in lanes a second.
const STEER_KEYS := 2.5

## The keys of the punches.
const KEYS_PUNCH := {
    KEY_J: ["straight", "left"],
    KEY_K: ["straight", "right"],
    KEY_U: ["hook", "left"],
    KEY_I: ["hook", "right"],
    KEY_H: ["uppercut", "left"],
    KEY_L: ["uppercut", "right"],
}

## What he does now (after [method read]).
var lean := 0.0
var ducking := false
var jumping := false
var covering := false
## Where he steers in a run, across the road, continuously, in lanes (see
## Scenery.LANE): 0 the middle of the road, -1 a lane's width to the left, 1
## to the right, and anything between.
var steer := 0.0
## The punches found since the last read: [kind, side, source].
var punches: Array = []
## The other moves found since the last read (for the log): [kind, side].
var others: Array = []
## Whether it is a run (the jumps last longer, see RUN_JUMP_HOLD).
var running := false

var _time := 0.0
var _keyboard_jump_left := 0.0
var _last_jump_at := -10.0
var _last_duck_at := -10.0
var _last_slip_at := {"left": -10.0, "right": -10.0}


## A key was pressed: a punch, or the jump.
func key(code: int) -> void:
    if KEYS_PUNCH.has(code):
        var move: Array = KEYS_PUNCH[code]
        punches.append([move[0], move[1], "keyboard"])
    elif code == KEY_X or code == KEY_SPACE:
        _keyboard_jump_left = RUN_JUMP_HOLD if running else JUMP_HOLD
        _last_jump_at = _time


## Read his body now, from the vision (null: the keyboard only).
func read(vision: Node, delta: float) -> void:
    _time += delta
    _keyboard_jump_left = maxf(0.0, _keyboard_jump_left - delta)
    lean = 0.0
    if Input.is_key_pressed(KEY_Q):
        lean -= 0.8
    if Input.is_key_pressed(KEY_E):
        lean += 0.8
    ducking = Input.is_key_pressed(KEY_Z)
    covering = Input.is_key_pressed(KEY_B)
    jumping = _keyboard_jump_left > 0.0

    if vision != null:
        for move in vision.PollMoves():
            match move["kind"]:
                "jump":
                    _last_jump_at = _time
                "duck":
                    _last_duck_at = _time
                "slip":
                    _last_slip_at[move["side"]] = _time
                "straight", "hook", "uppercut":
                    punches.append([move["kind"], move["side"], "vision"])
            if not move["kind"] in ["straight", "hook", "uppercut"]:
                others.append([move["kind"], move.get("side", "")])
        if lean == 0.0:
            # NOTE (mristin):
            # The lean against where the player stood lately (see
            # LeanGauge), in units, positive to his right.
            lean = vision.GetLean()
        if _time - _last_slip_at["left"] <= SLIP_HOLD:
            lean = minf(lean, -0.8)
        elif _time - _last_slip_at["right"] <= SLIP_HOLD:
            lean = maxf(lean, 0.8)
        ducking = ducking or _time - _last_duck_at <= DUCK_HOLD
        covering = covering or vision.IsCovering()
    jumping = jumping or _time - _last_jump_at <= (RUN_JUMP_HOLD if running else JUMP_HOLD)
    _steer(vision, delta)


## Take the moves found since the last time.
func take() -> Array:
    var found := punches
    punches = []
    return found


## The dodge which counts now, by its name ("" if none).
func pose() -> String:
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


## The dodges he is in now (as the notes name them).
func dodges() -> Array:
    var found := []
    if lean <= -SLIP_FROM:
        found.append("slip_left")
    if lean >= SLIP_FROM:
        found.append("slip_right")
    if ducking:
        found.append("duck")
    if jumping:
        found.append("jump")
    if covering:
        found.append("cover")
    return found


## Whether the camera sees him (always, without the camera).
static func sees(vision: Node) -> bool:
    if vision == null or vision.GetStatus() == "Disabled":
        return true
    return vision.HasPlayer()


func _steer(vision: Node, delta: float) -> void:
    var keys := 0
    if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
        keys -= 1
    if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
        keys += 1
    var middle := _body_middle(vision)
    if keys != 0 or middle < 0.0:
        steer = clampf(steer + keys * STEER_KEYS * delta, -STEER_MOST, STEER_MOST)
        return
    steer = clampf((middle - 0.5) / STEER_LANE, -STEER_MOST, STEER_MOST)


## Where the middle of his body is across the mirrored picture (0 to 1;
## negative without him): the middle of his shoulders and his hips.
static func _body_middle(vision: Node) -> float:
    if vision == null:
        return -1.0
    var points: PackedVector2Array = vision.GetKeypoints()
    if points.size() < 13:
        return -1.0
    return (points[5].x + points[6].x + points[11].x + points[12].x) * 0.25
