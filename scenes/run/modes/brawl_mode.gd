class_name BrawlMode
extends RunMode

## The hero crashed into an opponent on the road (see Encounters): the run
## turns into a fight (see Brawl), the land stops, and they box freely until
## one goes down. After the knock-out, the opponent is dragged to the side of
## the road, a little of the hero's energy comes back, and the run goes on.

## How much energy comes back after a knock-out.
const HEAL := 35.0

## The opponent (see Encounters), and his figure.
var _encounter: Dictionary
var _figure: Opponent


func _init(of: Run, index: int) -> void:
    super(of)
    _encounter = run.encounters().at(index)
    _figure = _encounter["figure"]


func enter() -> void:
    _encounter["state"] = "fight"
    var shift := run.boxer.shift
    _figure.global_position = Run.SPOT + Vector3(shift, 0, -Fight.OPPONENT_DISTANCE)
    _figure.target = Run.SPOT + Vector3(shift, 0, 0)
    _stand()
    run.boxer.take_damage(0.0, true)
    run.hud.announce("FIGHT!", 1.5)
    run.play_sound("hurt", -8.0)
    run.play_sound("bell", -6.0)
    run.brawl().start(_encounter["id"], _figure)
    if _figure.look == "white_sheep":
        _bring_black_sheep(2.4)


func hold(delta: float) -> bool:
    var brawl := run.brawl()
    brawl.step(delta, run.dodges())
    if run.boxer.health <= 0.0:
        run.lose()
        return false
    if brawl.active():
        return false
    _encounter["state"] = "down"
    run.spend_power()
    run.boxer.health = minf(Boxer.MAX_HEALTH, run.boxer.health + HEAL)
    run.hud.announce("RUN!", 1.5)
    run.log_event("run_on", {})
    return true


## In a fight, he stays where he crashed (the slips must not steer).
func frame(delta: float) -> void:
    _fight_frame(_figure.global_position, delta)


func command() -> String:
    return "READY"


func throw(kind: String, side: String) -> void:
    run.show_strike(kind, side)
    run.brawl().punch(kind, side)


func health() -> float:
    return _figure.health


func threatened() -> bool:
    return run.brawl().threatened()
