extends SceneTree

## Play a recording of the vision headless (see dev/replay/), and print what
## the game makes of it: twice a second the likeliest class of the move
## classifier, and every move which it found, with its time.
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
        var classes: PackedStringArray = _service.GetMoveClasses()
        var probabilities: PackedFloat32Array = _service.GetMoveProbabilities()
        var best := 0
        for i in range(probabilities.size()):
            if probabilities[i] > probabilities[best]:
                best = i
        var likeliest := "-"
        if probabilities.size() > 0:
            likeliest = "%s %.2f" % [classes[best], probabilities[best]]
        print(
            (
                "%6.2f   likeliest %s  cover %s  lean %+.2f"
                % [
                    replay.x,
                    likeliest,
                    "Y" if _service.IsCovering() else "-",
                    _service.GetLean(),
                ]
            )
        )
    return replay.x >= _length
