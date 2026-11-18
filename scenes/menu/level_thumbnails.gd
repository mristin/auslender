class_name LevelThumbnails
extends Node

## Small pictures of the levels for the level selection (see LevelSelect): the
## land of each level (see Scenery) with its first opponent, as the hero sees
## him (a minor one far down the road, in his random colors; a boss close, in
## his lair).
##
## The game renders them itself, one after the other, each in a hidden
## viewport of its own world, and keeps them for as long as it runs, so that
## they always show the levels as they are. Without a display (headless), there
## are none.

## A picture is ready: the id of its level, and the picture.
signal rendered(id: String, texture: Texture2D)

## The size of a picture, in pixels.
const SIZE := Vector2i(352, 198)

## Where the hero stands in the picture (as in a level, see RhythmLevel.SPOT).
const SPOT := Vector3(0, 0, 1.5)

## The pictures rendered so far, by the id of their level.
static var _cache := {}

var _queue: Array[Dictionary] = []
var _busy := false


## The picture of the level, if it is rendered (else null: it is queued, and
## [signal rendered] tells when it is ready).
func request(level: Dictionary) -> Texture2D:
    if _cache.has(level["id"]):
        return _cache[level["id"]]
    if DisplayServer.get_name() != "headless":
        _queue.append(level)
    return null


func _process(_delta: float) -> void:
    if not _busy and not _queue.is_empty():
        _render(_queue.pop_front())


## Render the picture of the level: its land, its first opponent, and a camera
## at the hero's eyes; once drawn, keep it, and free the world.
func _render(level: Dictionary) -> void:
    _busy = true
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.own_world_3d = true
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)

    var run: bool = level["kind"] == "run"
    var scenery := Scenery.new()
    viewport.add_child(scenery)
    scenery.setup(level["scenery"], SPOT, run)

    var opponent := Opponent.new()
    opponent.look = Levels.opponent(level["opponents"][0])["look"]
    if run:
        opponent.tint = hash(level["id"]) & 0xffff
    viewport.add_child(opponent)
    opponent.global_position = SPOT + (Vector3(0.5, 0, -4.0) if run else Vector3(0.25, 0, -1.9))
    opponent.target = SPOT

    var camera := Camera3D.new()
    camera.fov = 60.0
    viewport.add_child(camera)
    camera.position = SPOT + Vector3(0, 1.55, 0)
    camera.look_at(opponent.global_position + Vector3(0, 1.1 if run else 1.3, 0), Vector3.UP)
    camera.current = true

    # NOTE (mristin):
    # A few frames, so that the opponent stands in his guard, then the picture.
    for i in range(4):
        await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    viewport.queue_free()
    _busy = false
    if image == null:
        return
    var texture := ImageTexture.create_from_image(image)
    _cache[level["id"]] = texture
    rendered.emit(level["id"], texture)
