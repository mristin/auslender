extends SceneTree

## Play a recording of the vision headless (see dev/replay/), and print what
## the game makes of it: twice a second the walking, the cadence and the turn,
## and every move which the detectors found, with its time.
##
## [codeblock]
## $GODOT --headless --fixed-fps 30 --path . --script dev/moves/print_replay.gd -- \
##     --replay=<recording.jsonl>
## [/codeblock]

var _service: Node
var _next := 0.0
var _length := -1.0


func _initialize() -> void:
    _start.call_deferred()


func _start() -> void:
    _service = root.get_node("Vision").service


func _process(_delta: float) -> bool:
    if _service == null or not _service.IsReplaying():
        return false
    var replay: Vector2 = _service.GetReplayTime()
    if _length < 0.0:
        _length = replay.y
    for move in _service.PollMoves():
        print("%6.2f   MOVE %s %s (%.2f)" % [replay.x, move["side"], move["kind"], move["power"]])
    if replay.x >= _next:
        _next += 0.5
        print(
            (
                "%6.2f   walk %.2f%s  cadence %.1f  turn %+.2f (raw %+.2f)  duck %s  jump %s"
                % [
                    replay.x,
                    _service.GetWalkSpeed(),
                    " W" if _service.IsWalking() else "  ",
                    _service.GetCadence(),
                    _service.GetTurn(),
                    _service.GetTurnRaw(),
                    "Y" if _service.IsDucking() else "-",
                    "Y" if _service.IsJumping() else "-",
                ]
            )
        )
    return replay.x >= _length
