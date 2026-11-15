class_name Flow
extends RefCounted

## The way through the screens (as in The Steppe Rescue): the sessions (see
## Sessions), the naming of a new one (see SessionName), the levels of a
## session (see LevelSelect), and a level (see Fight), whose end leads back to
## the levels, or on to the next one.

const SESSIONS := "res://scenes/menu/sessions.tscn"
const SESSION_NAME := "res://scenes/menu/session_name.tscn"
const LEVEL_SELECT := "res://scenes/menu/level_select.tscn"
const LEVEL := "res://scenes/fight/fight.tscn"

## The level to play (see Levels).
static var level_id := ""


static func sessions(tree: SceneTree) -> void:
    tree.change_scene_to_file.call_deferred(SESSIONS)


static func new_session(tree: SceneTree) -> void:
    tree.change_scene_to_file.call_deferred(SESSION_NAME)


static func levels(tree: SceneTree) -> void:
    Engine.time_scale = 1.0
    tree.change_scene_to_file.call_deferred(LEVEL_SELECT)


## Play the level of the id (if it is open in the session; else choose).
static func play(tree: SceneTree, id: String) -> void:
    var index := Levels.index_of(id)
    if index < 0 or not Profile.is_open(index):
        levels(tree)
        return
    Engine.time_scale = 1.0
    level_id = id
    tree.change_scene_to_file.call_deferred(LEVEL)
