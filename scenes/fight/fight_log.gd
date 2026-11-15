class_name FightLog
extends RefCounted

## A log of a fight, to study how it plays (see dev/fight/README.md): one JSON
## object per line, each with its "event", the seconds of real time since the
## start ("t"), and its own fields. It holds only what happened in the game
## (the moves, the attacks, the dodges, the health), never pictures.
##
## The logs go to user://fight_logs/ (on Linux,
## ~/.local/share/godot/app_userdata/Auslender/fight_logs/), one per start of
## the fight scene.

const DIRECTORY := "user://fight_logs"

## Where the log is written ("" if it could not be opened).
var path := ""

var _file: FileAccess
var _started := 0


func _init() -> void:
    _started = Time.get_ticks_msec()
    DirAccess.make_dir_recursive_absolute(DIRECTORY)
    var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
    path = "%s/fight-%s.jsonl" % [DIRECTORY, stamp.replace("T", "-")]
    _file = FileAccess.open(path, FileAccess.WRITE)
    if _file == null:
        push_warning("Could not write the fight log %s." % path)
        path = ""


## Write an event with its fields.
func write(event: String, fields := {}) -> void:
    if _file == null:
        return
    var line := {"t": snappedf((Time.get_ticks_msec() - _started) / 1000.0, 0.001), "event": event}
    for key in fields:
        var value: Variant = fields[key]
        line[key] = snappedf(value, 0.001) if value is float else value
    _file.store_line(JSON.stringify(line))
    _file.flush()
