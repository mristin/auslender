class_name SmashMode
extends RunMode

## He ran into a barrier (see Barriers): the run stops, and he smashes it
## with his punches and kicks, against its clock; the time left is a bonus.

## The points for a hit into the target, and for another hit.
const TARGET_POINTS := 50
const HIT_POINTS := 20

var _barriers: Barriers
var _index := 0


func _init(of: Run, index: int) -> void:
    super(of)
    _barriers = run.barriers()
    _index = index


func enter() -> void:
    _barriers.start(_index, run.boxer.shift)
    var look := _barriers.look()
    _stand()
    run.hud.opponent_name = str(Barriers.LOOKS[look]["title"]).trim_prefix("THE ")
    run.hud.countdown = Barriers.LIMIT
    run.hud.announce("SMASH IT!", 1.5)
    run.play_sound("bell", -6.0)
    if look == "poster":
        _bring_black_sheep(1.2)
    run.log_event("barrier_start", {"look": look})


func hold(_delta: float) -> bool:
    run.hud.countdown = maxf(0.0, _barriers.time_left())
    return not _barriers.smashing()


func frame(delta: float) -> void:
    _fight_frame(_barriers.aim(run.boxer.shift), delta)


func cue() -> Array:
    return _barriers.call_target()


func command() -> String:
    return "SMASH IT!"


## A punch or a kick at the barrier: chunks fly (see Barriers.hit); the
## power booster works on it, too.
func throw(kind: String, side: String) -> void:
    run.show_strike(kind, side)
    var result := _barriers.hit(kind, side, run.brawl().power)
    run.log_event("barrier_hit", {"kind": kind, "side": side, "result": result})
    match result:
        "target":
            run.score().bonus(TARGET_POINTS)
            run.hud.say("CRASH!", Hud.GOLD)
            run.play_sound("hit", -2.0)
        "hit":
            run.score().bonus(HIT_POINTS)
            run.hud.say("BAM!", Hud.PAPER)
            run.play_sound("hit", -6.0)
        "smashed":
            _smashed()


func health() -> float:
    return _barriers.health()


func leave() -> void:
    run.hud.countdown = -1.0
    super()


## He smashed the barrier: the bonus for the time left, and the run goes on.
func _smashed() -> void:
    var left := _barriers.time_left()
    run.score().met("landed")
    if left > 0.0:
        var points := Barriers.BONUS * ceili(left)
        run.score().bonus(points)
        run.hud.say("SMASHED! +%d" % points, Hud.GOLD)
    else:
        run.hud.say("SMASHED!", Hud.GOLD)
    run.play_sound("perfect", -4.0)
    run.play_sound("hit", -2.0)
    run.hud.announce("RUN!", 1.5)
    run.log_event("barrier_smashed", {"seconds": Barriers.LIMIT - left})
