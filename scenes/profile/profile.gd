class_name Profile
extends RefCounted

## The player's sessions and his progress in them, saved (as in The Steppe
## Rescue and Bird Dog, see DESIGN.md).
##
## A session is a named playthrough, like a save slot: its name (by default
## the date and the time it started), and the best result of every level the
## player finished in it. One may keep as many sessions as one likes. Each is
## one JSON file in user://saves/, written whole on every change (to a
## temporary file, then renamed over the old one, so that a crash never leaves
## half a file). user://settings.cfg remembers the last session.
##
## A level opens once the one before it is finished (see [method is_open]):
## the opening is never stored, only the results.

const DIRECTORY := "user://saves"
const SETTINGS := "user://settings.cfg"

## The format of the files: a newer one is not read.
const FORMAT := 1

## The longest name of a session.
const MAX_NAME := 24

## The session now (empty if none): "id", "name", "created", "updated", and
## "levels": {level id: {"stars", "score", "won"}}.
static var session := {}


## Start a new session of the name, and make it the session now.
static func start_session(name: String) -> void:
    var now := Time.get_datetime_dict_from_system()
    var id := (
        "%04d%02d%02d-%02d%02d%02d"
        % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]
    )
    var unique := id
    var count := 2
    while FileAccess.file_exists(_path(unique)):
        unique = "%s-%d" % [id, count]
        count += 1
    var stamp := Time.get_datetime_string_from_system()
    session = {
        "format": FORMAT,
        "id": unique,
        "name": name.strip_edges().left(MAX_NAME),
        "created": stamp,
        "updated": stamp,
        "levels": {},
    }
    save()


## The default name of a new session: the date and the time.
static func default_name() -> String:
    var now := Time.get_datetime_dict_from_system()
    return (
        "%04d-%02d-%02d %02d:%02d"
        % [now["year"], now["month"], now["day"], now["hour"], now["minute"]]
    )


## Continue the session of the id; whether it could be read.
static func continue_session(id: String) -> bool:
    var data := read(id)
    if data.is_empty():
        return false
    session = data
    _remember_last()
    return true


## All the sessions, the last played first.
static func sessions() -> Array:
    var found := []
    var directory := DirAccess.open(DIRECTORY)
    if directory == null:
        return found
    for file in directory.get_files():
        if file.ends_with(".json"):
            var data := read(file.trim_suffix(".json"))
            if not data.is_empty():
                found.append(data)
    found.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool: return a["updated"] > b["updated"]
    )
    return found


## The id of the last session played ("" if none).
static func last_session() -> String:
    var settings := ConfigFile.new()
    if settings.load(SETTINGS) != OK:
        return ""
    return str(settings.get_value("general", "last_session", ""))


## Read the session of the id (empty if missing, broken or too new).
static func read(id: String) -> Dictionary:
    var file := FileAccess.open(_path(id), FileAccess.READ)
    if file == null:
        return {}
    var data: Variant = JSON.parse_string(file.get_as_text())
    if not data is Dictionary or int(data.get("format", 0)) > FORMAT:
        return {}
    if not data.has("levels") or not data["levels"] is Dictionary:
        data["levels"] = {}
    return data


## Delete the session of the id (and forget it if it was the last one).
static func delete(id: String) -> void:
    DirAccess.remove_absolute(_path(id))
    if session.get("id", "") == id:
        session = {}
    if last_session() == id:
        var settings := ConfigFile.new()
        settings.load(SETTINGS)
        settings.set_value("general", "last_session", "")
        settings.save(SETTINGS)


## Write the session now (atomically).
static func save() -> void:
    if session.is_empty():
        return
    DirAccess.make_dir_recursive_absolute(DIRECTORY)
    session["updated"] = Time.get_datetime_string_from_system()
    var path := _path(session["id"])
    var temporary := path + ".tmp"
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        push_warning("Could not save the session to %s." % path)
        return
    file.store_string(JSON.stringify(session, "  "))
    file.close()
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
    DirAccess.rename_absolute(temporary, path)
    _remember_last()


## Note the result of a level: whether he won it (which opens the next), his
## stars (see Scoring.stars) and his score; the best ones are kept.
static func finish_level(id: String, won: bool, stars: int, score: int) -> void:
    if session.is_empty():
        return
    var levels: Dictionary = session["levels"]
    var best: Dictionary = levels.get(id, {"won": false, "stars": 0, "score": 0})
    best["won"] = best["won"] or won
    best["score"] = maxi(int(best["score"]), score)
    best["stars"] = maxi(stars_of(best), stars)
    best.erase("grade")
    levels[id] = best
    save()


## Whether he won the level of the id in the session now.
static func has_won(id: String) -> bool:
    var levels: Dictionary = session.get("levels", {})
    return levels.has(id) and bool(levels[id]["won"])


## His best result of the level of the id ({} if none).
static func best(id: String) -> Dictionary:
    return session.get("levels", {}).get(id, {})


## Whether the level at the index is open: the first one, and every one after
## a level he won.
static func is_open(index: int) -> bool:
    if index <= 0:
        return true
    return has_won(Levels.ALL_LEVELS[index - 1]["id"])


## The index of the next level to play: the first open one he has not won yet
## (else the last).
static func next_index() -> int:
    for i in range(Levels.ALL_LEVELS.size()):
        if is_open(i) and not has_won(Levels.ALL_LEVELS[i]["id"]):
            return i
    return Levels.ALL_LEVELS.size() - 1


## The best stars of a result (see [method best]); the sessions of before
## kept a grade instead (S to D), which counts as its stars.
static func stars_of(result: Dictionary) -> int:
    if result.has("stars"):
        return int(result["stars"])
    return {"S": 6, "A": 5, "B": 4, "C": 3, "D": 1}.get(str(result.get("grade", "")), 0)


static func _path(id: String) -> String:
    return "%s/%s.json" % [DIRECTORY, id]


static func _remember_last() -> void:
    var settings := ConfigFile.new()
    settings.load(SETTINGS)
    settings.set_value("general", "last_session", session.get("id", ""))
    settings.save(SETTINGS)
