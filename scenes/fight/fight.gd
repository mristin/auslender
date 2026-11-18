class_name Fight
extends RhythmLevel

## The fight against the boss of a world (see Levels), in a level of his own
## at its end: a free brawl (see Brawl), to music, which goes on until one of
## the two goes down. No chart and no notes: the boss guards, opens his guard
## here and there, and attacks when he likes, with a quiet tell (see Brawl).
## The player wins with the knock-out.
##
## As in a real match, the two circle each other: now and then they turn
## around the middle between them to another angle, at random, smoothly
## starting and stopping, so that the land swings past behind the boss. The
## view stays the hero's own (the first person); the circling slows down
## while the boss winds up and strikes, so that one sees where his attack
## comes from.

## How far the opponent stands in front of the player, in meters: close, so
## that the punches land on his head.
const OPPONENT_DISTANCE := 1.05

## How far they circle from where they started at most (radians), how fast at
## most (radians a second), how quickly they get to that speed (1/s), and how
## long they keep to an angle before they move on (seconds, at random).
const CIRCLE_MOST := 0.95
const CIRCLE_SPEED := 0.3
const CIRCLE_EASE := 1.2
const CIRCLE_EVERY := Vector2(3.0, 6.5)

var opponent: Opponent

var _brawl := Brawl.new()
var _started := false
## The angle they circled to, where they circle to, how fast, and when they
## move on.
var _angle := 0.0
var _angle_goal := 0.0
var _angle_speed := 0.0
var _angle_next := 0.0


func _build() -> void:
    opponent = Opponent.new()
    opponent.look = Levels.opponent(level["opponents"][0])["look"]
    add_child(opponent)
    opponent.global_position = SPOT + Vector3(0, 0, -OPPONENT_DISTANCE)
    opponent.target = SPOT
    _brawl.setup(hud, boxer, _scoring, _log, play_sound, _beat_seconds)
    # NOTE (mristin):
    # The music loops, past its quiet intro, for as long as they box.
    _music.finished.connect(_loop_music)


func _on_start() -> void:
    _chart = []
    _started = false
    if opponent != null:
        opponent.reset()
    _brawl.start(level["opponents"][0], opponent)


func _holds() -> bool:
    return true


func _hold(delta: float) -> void:
    if not _started:
        _started = true
        hud.announce("BOX!", 1.5)
    _brawl.step(delta, _body.dodges())
    if boxer.health <= 0.0:
        _finish(false)
    elif _brawl.knocked_out():
        _finish(true)


func _call() -> Array:
    return _brawl.dodge_call()


func _threatened() -> bool:
    return _brawl.threatened()


func _on_frame(delta: float) -> void:
    _circle(delta)
    boxer.face(opponent.global_position, delta)
    if _phase != Phase.PLAYING:
        opponent.perform("", 0.0)


## Throw a punch of the player ("straight", "hook" or "uppercut"; "left" or
## "right"), or a kick ("kick"), as the vision found it: at the boss.
func throw(kind: String, side: String, _source := "vision") -> void:
    _show_strike(kind, side)
    if _phase == Phase.PLAYING and not _paused:
        _brawl.punch(kind, side)


## Circle around the middle between them (see the class): a smooth, random
## turn now and then, while they box.
func _circle(delta: float) -> void:
    if _phase == Phase.PLAYING and not _paused and not _brawl.knocked_out():
        if _time >= _angle_next:
            var goal := randf_range(-CIRCLE_MOST, CIRCLE_MOST)
            # NOTE (mristin):
            # A real turn: never just a little on.
            if absf(goal - _angle) < 0.35:
                goal = clampf(_angle - signf(_angle + 0.01) * 0.6, -CIRCLE_MOST, CIRCLE_MOST)
            _angle_goal = goal
            _angle_next = _time + randf_range(CIRCLE_EVERY.x, CIRCLE_EVERY.y)
    else:
        _angle_goal = _angle
    var most := CIRCLE_SPEED * (0.3 if _brawl.threatened() else 1.0)
    var wanted := clampf((_angle_goal - _angle) * 0.8, -most, most)
    _angle_speed = lerpf(_angle_speed, wanted, minf(1.0, delta * CIRCLE_EASE))
    _angle += _angle_speed * delta
    var middle := SPOT + Vector3(0, 0, -OPPONENT_DISTANCE * 0.5)
    var out := Vector3(sin(_angle), 0, cos(_angle)) * OPPONENT_DISTANCE * 0.5
    boxer.global_position = middle + out
    boxer.rotation.y = _angle
    opponent.global_position = middle - out
    opponent.target = boxer.global_position


func _knock_out() -> void:
    hud.banner = "K.O.!"
    Engine.time_scale = 0.3
    _slow_until = Time.get_ticks_msec() + 1200


func _banner(won: bool) -> String:
    return "YOU WIN!" if won else "DOWN!"


## How far the fight is: how much of the boss's health is gone.
func _progress() -> float:
    return 1.0 - opponent.health / Opponent.MAX_HEALTH if opponent != null else 0.0


func _his_health() -> float:
    return opponent.health if opponent != null else -1.0


func _loop_music() -> void:
    if _phase == Phase.PLAYING:
        _music.play(_intro_bars * 4.0 * _beat_seconds)
