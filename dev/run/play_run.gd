extends SceneTree

## Play a run end to end without a camera, to see that it works (a smoke
## test): he is seen and runs at the normal pace, keeps his health, throws
## punches at whatever stops him (an opponent, a barrier), and smashes the
## barriers. With --fixed-fps and no cap on the frames, the game runs as fast
## as it renders, faster than real time:
##
## [codeblock]
## $GODOT --path . --fixed-fps 60 --disable-vsync --max-fps 0 \
##     --script dev/run/play_run.gd -- --level=jungle --no-camera \
##     [--seconds=300] [--skip]
## [/codeblock]
##
## With --skip, it skips ahead to just before each barrier. It prints what
## happens and quits after the seconds (of the game) or when the run is over.

const PUNCHES := [["straight", "left"], ["hook", "right"], ["hook", "left"], ["kick", "right"]]

var _run: Node
var _seconds := 300.0
var _skip := false
var _started_ms := 0
var _clock := 0.0
var _punch_in := 0.0
var _punches := 0
var _skipped := {}
var _mode := ""
var _frames := 0


func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--seconds="):
            _seconds = float(arg.trim_prefix("--seconds="))
        if arg == "--skip":
            _skip = true
    _started_ms = Time.get_ticks_msec()
    change_scene_to_file.call_deferred("res://scenes/run/run.tscn")


func _process(delta: float) -> bool:
    _clock += delta
    _frames += 1
    if _run == null:
        _run = current_scene
        return false
    _run.set("_unseen", -1000.0)
    _run.set("_pace", 1.0)
    _run.boxer.health = Boxer.MAX_HEALTH
    if _run.get("_phase") == RhythmLevel.Phase.WAITING:
        _run.set("_wait_left", -1.0)
    var mode: RunMode = _run.get("_mode")
    var now: String = "" if mode == null else str(mode.get_script().get_global_name())
    if now != _mode:
        print(
            "%6.1f s  t=%.1f  mode: %s" % [_clock, _run.get("_t"), now if now != "" else "running"]
        )
        _mode = now
    if mode == null:
        if _skip:
            _skip_to_barrier()
    else:
        _punch_in -= delta
        if _punch_in <= 0.0:
            var punch: Array = PUNCHES[_punches % PUNCHES.size()]
            _run.throw(punch[0], punch[1])
            _punches += 1
            _punch_in = 0.25
    if _run.get("_phase") == RhythmLevel.Phase.OVER or _clock >= _seconds:
        print(
            (
                "%6.1f s  over: phase %d, score %d, %d frames in %.1f s of real time"
                % [
                    _clock,
                    _run.get("_phase"),
                    _run.score().score,
                    _frames,
                    (Time.get_ticks_msec() - _started_ms) / 1000.0
                ]
            )
        )
        quit()
    return false


## Skip to a few seconds before the next barrier which is ahead.
func _skip_to_barrier() -> void:
    var items: Array = _run.barriers().get("_items")
    for i in range(items.size()):
        var item: Dictionary = items[i]
        if item["state"] != "ahead" or _skipped.has(i):
            continue
        var at := float(item["at"]) - 3.0
        if _run.get("_t") < at and _clock > 6.0 + 18.0 * i:
            print("%6.1f s  skip to the barrier %s" % [_clock, item["look"]])
            _run.move_to(at)
            _skipped[i] = true
        return
