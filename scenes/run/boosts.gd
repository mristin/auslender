class_name Boosts
extends RefCounted

## The boosters which he picked up and which work now (see Boosters): the
## speed and the shield until their time runs out (the song's time), the
## power punches until the end of the next fight.

var _speed_until := -1.0
var _shield_until := -1.0
var _powered := false


## None works any more (a new run).
func reset() -> void:
    _speed_until = -1.0
    _shield_until = -1.0
    _powered = false


## He picked up a booster of the [param kind] at the song's time
## [param now] (its health he gets at once, see Run).
func take(kind: String, now: float) -> void:
    var seconds := float(Boosters.KINDS[kind].get("seconds", 0.0))
    match kind:
        "speed":
            _speed_until = now + seconds
        "shield":
            _shield_until = now + seconds
        "power":
            _powered = true


## How many times as fast he runs at the song's time [param now].
func speed(now: float) -> float:
    return Boosters.SPEED_BOOST if now < _speed_until else 1.0


## Whether the shield keeps the obstacles off him at the song's time
## [param now].
func shields(now: float) -> bool:
    return now < _shield_until


## How strong his punches are (see Brawl.power).
func power() -> float:
    return Boosters.POWER if _powered else 1.0


## The fight is over: the power punches are spent.
func spend_power() -> void:
    _powered = false


## The boosters which work at the song's time [param now], for the HUD (see
## Hud.boosts): the name, how much of its time is left (-1 until spent), and
## the color.
func shown(now: float) -> Array:
    var out: Array = []
    var timed := {"speed": _speed_until, "shield": _shield_until}
    for kind: String in timed:
        var spec: Dictionary = Boosters.KINDS[kind]
        var left: float = timed[kind] - now
        if left > 0.0:
            var name: String = spec["effect"]
            out.append([name.trim_suffix("!"), left / float(spec["seconds"]), spec["color"]])
    if _powered:
        out.append(["POWER PUNCHES", -1.0, Boosters.KINDS["power"]["color"]])
    return out
