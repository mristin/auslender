extends SceneTree

## The opponents on the road of a run (see Encounters) keep their places
## among the barriers (see Barriers) as the hero runs: one laid before a
## barrier stays in front of it, one laid after it stays behind it, also when
## he charges. Run with the other Godot tests (see
## dev/continuous_integration/precommit.py), headless, without playing a level.

const SPEED := RhythmLevel.SPEED
const STEP := 1.0 / 60.0

var _failures: Array[String] = []


## The tests run on the first frame, when the nodes can enter the tree.
func _process(_delta: float) -> bool:
    _test_those_behind_the_next_come_closer_too()
    _test_opponents_keep_their_places_among_the_barriers()
    _test_no_charge_through_a_barrier()
    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        for failure in _failures:
            printerr(failure)
        print("RESULT: FAILED")
        quit(1)
    return true


func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures.append(message)


func _road() -> Array:
    var encounters := Encounters.new()
    var barriers := Barriers.new()
    root.add_child(encounters)
    root.add_child(barriers)
    return [encounters, barriers]


func _free(road: Array) -> void:
    for node: Node in road:
        node.free()


## Run on at the normal pace for [param seconds], from the time of the notes
## [param t]; call [param check] after every step with the time.
func _run(road: Array, t: float, seconds: float, check: Callable) -> float:
    var encounters: Encounters = road[0]
    var barriers: Barriers = road[1]
    var time := 0.0
    while time < seconds:
        t += STEP
        time += STEP
        var wall := barriers.wall_ahead(t, SPEED)
        var meeting := encounters.move(STEP * SPEED, STEP, time, 0.0, Vector3.ZERO, wall)
        check.call(t)
        if meeting >= 0:
            # NOTE (mristin):
            # The fight is over at once: he runs away.
            encounters.at(meeting)["state"] = "fled"
    return t


func _test_those_behind_the_next_come_closer_too() -> void:
    var road := _road()
    var encounters: Encounters = road[0]
    encounters.add("bunzli", 40.0)
    encounters.add("nationalist", 90.0)
    _run(road, 0.0, 2.0, func(_t: float) -> void: pass)
    var second: float = encounters.at(1)["dist"]
    _check(
        absf(second - (90.0 - 2.0 * SPEED)) < 0.5,
        "The second opponent should come closer as the hero runs: %.2f m ahead" % second
    )
    _free(road)


func _test_opponents_keep_their_places_among_the_barriers() -> void:
    var road := _road()
    var encounters: Encounters = road[0]
    var barriers: Barriers = road[1]
    # NOTE (mristin):
    # The first opponent, a barrier, the second opponent, as the road plan
    # lays them (see RoadPlan): the second one must never show in front of
    # the barrier, nor behind it before it is smashed.
    encounters.add("bunzli", 30.0)
    var barrier_at := 12.0
    barriers.add("laundry", barrier_at, "city")
    encounters.add("nationalist", barrier_at * SPEED + 20.0)
    var check := func(t: float) -> void:
        var wall := barriers.wall_ahead(t, SPEED)
        var second: Dictionary = encounters.at(1)
        if second["state"] == "ahead":
            _check(
                float(second["dist"]) > wall,
                "The second opponent shows in front of the barrier at t=%.2f" % t
            )
        var first: Dictionary = encounters.at(0)
        if first["state"] == "ahead" and first["figure"] != null:
            _check(
                float(first["dist"]) < wall,
                "The first opponent shows behind the barrier at t=%.2f" % t
            )
    _run(road, 0.0, barrier_at - 0.1, check)
    _free(road)


func _test_no_charge_through_a_barrier() -> void:
    var road := _road()
    var encounters: Encounters = road[0]
    var barriers: Barriers = road[1]
    var barrier_at := 3.0
    barriers.add("laundry", barrier_at, "city")
    # NOTE (mristin):
    # Just behind the barrier: close enough to charge before the hero gets
    # there.
    encounters.add("bunzli", barrier_at * SPEED + Barriers.STAND + 3.0)
    var check := func(t: float) -> void:
        var item: Dictionary = encounters.at(0)
        _check(
            item["state"] == "ahead",
            "The opponent behind the barrier met the hero before it at t=%.2f" % t
        )
        _check(
            float(item["dist"]) > barriers.wall_ahead(t, SPEED),
            "The opponent charged through the barrier at t=%.2f" % t
        )
    _run(road, 0.0, barrier_at - 0.1, check)
    _free(road)
