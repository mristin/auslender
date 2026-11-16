class_name Encounters
extends Node3D

## The opponents on the road of a run (see Run), one after the other: each
## shows from afar, in random colors of his own (see Looks.recolor), charges
## at the hero, weaving across the road from side to side, and in the last
## meters homes in on him: there is no way around him, he always meets the
## hero (then they fight, see Run). Those knocked out are dragged to the side
## of the road and roll past.

## How far the opponents show ahead on the road, from how far they charge at
## him (at random speeds in the range, meters a second), in meters.
const APPEAR := 24.0
const CHARGE_FROM := 14.0
const CHARGE := Vector2(1.0, 2.2)

## As he comes, an opponent weaves across the road: he side-steps to a spot
## (anywhere across the road, at most this far from the middle, in lanes) at
## this speed (meters a second), and picks a new one every while (seconds, at
## random); from this far (meters), he homes in on the hero to meet him.
const WEAVE_MOST := 1.2
const SIDESTEP := 2.6
const WEAVE_EVERY := Vector2(0.6, 1.3)
const MEET_FROM := 7.0

## The opponents on the road, in order: "id", "dist" (how far ahead of the
## hero, in meters), "x" (across the road), "charge" (his speed, meters a
## second), "spot" (where across the road he side-steps to, see WEAVE_MOST)
## and "spot_until" (when he picks a new one), "figure" (an
## Opponent, once he shows), "state" ("ahead", "fight", "down" or "gone").
var _items: Array = []


## Take all the opponents off the road.
func clear() -> void:
    for item in _items:
        if item["figure"] != null:
            (item["figure"] as Node).queue_free()
    _items.clear()


## Put the opponent of the [param id] on the road, [param dist] meters ahead.
func add(id: String, dist: float) -> void:
    (
        _items
        . append(
            {
                "id": id,
                "dist": dist,
                "x": randf_range(-1.0, 1.0) * Scenery.LANE,
                "charge": randf_range(CHARGE.x, CHARGE.y),
                "spot": 0.0,
                "spot_until": 0.0,
                "figure": null,
                "state": "ahead",
                "seed": randi() & 0xffff,
            }
        )
    )


## The opponent of the [param index] (see _items).
func at(index: int) -> Dictionary:
    return _items[index]


## Move the opponents as the hero runs [param meters] on, in [param played]
## seconds (at the time [param time], at [param shift] across the road, from
## his [param spot]): the index of the one who reaches him now (-1 if none).
func move(meters: float, played: float, time: float, shift: float, spot: Vector3) -> int:
    for i in range(_items.size()):
        var item: Dictionary = _items[i]
        var figure: Opponent = item["figure"]
        match item["state"]:
            "ahead":
                if i != _next_ahead():
                    continue
                var dist: float = item["dist"] - meters
                if dist < CHARGE_FROM:
                    dist -= float(item["charge"]) * played
                item["dist"] = dist
                if dist > APPEAR:
                    continue
                if figure == null:
                    figure = _new_figure(item)
                var x := _weave(item, dist, played, time, shift)
                figure.global_position = spot + Vector3(x, 0, -dist)
                figure.target = spot + Vector3(shift, 0, 0)
                var stride := fposmod(time * 2.6, 1.0)
                figure.groove(stride, fposmod(time * 0.65, 1.0), floori(time * 0.65))
                if dist <= Fight.OPPONENT_DISTANCE:
                    return i
            "down":
                var side := 1.0 if figure.global_position.x >= shift else -1.0
                var roadside := side * (RhythmNote.ROAD * 0.5 + 0.8)
                figure.global_position.x = lerpf(
                    figure.global_position.x, roadside, minf(1.0, played * 3.0)
                )
                figure.global_position.z += meters
                if figure.global_position.z > spot.z + 3.0:
                    figure.queue_free()
                    item["figure"] = null
                    item["state"] = "gone"
    return -1


## Where across the road the opponent is now: far off, he weaves from side to
## side (side-steps to a spot, then to another); from MEET_FROM on, he homes
## in on the hero (at [param shift]), faster and faster, so that he meets him
## wherever he is.
func _weave(item: Dictionary, dist: float, played: float, time: float, shift: float) -> float:
    if time >= float(item["spot_until"]):
        var spot := randf_range(-WEAVE_MOST, WEAVE_MOST) * Scenery.LANE
        # NOTE (mristin):
        # A real side-step: never just a little over.
        if absf(spot - float(item["x"])) < Scenery.LANE * 0.6:
            spot = -signf(float(item["x"]) + 0.01) * randf_range(0.5, WEAVE_MOST) * Scenery.LANE
        item["spot"] = spot
        item["spot_until"] = time + randf_range(WEAVE_EVERY.x, WEAVE_EVERY.y)
    var meet := clampf(
        1.0 - (dist - Fight.OPPONENT_DISTANCE) / (MEET_FROM - Fight.OPPONENT_DISTANCE), 0.0, 1.0
    )
    var goal := lerpf(float(item["spot"]), shift, meet)
    var speed := SIDESTEP * (1.0 + 2.0 * meet)
    var x := move_toward(float(item["x"]), goal, speed * played)
    if meet >= 1.0:
        x = shift
    item["x"] = x
    return x


## The index of the next opponent still ahead (-1 if none).
func _next_ahead() -> int:
    for i in range(_items.size()):
        if _items[i]["state"] == "ahead":
            return i
    return -1


func _new_figure(item: Dictionary) -> Opponent:
    var figure := Opponent.new()
    figure.look = Levels.opponent(item["id"])["look"]
    figure.tint = item["seed"]
    add_child(figure)
    item["figure"] = figure
    return figure
