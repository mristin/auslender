class_name CameraMirror
extends Control

## The camera picture behind the buttons of a menu (as in The Steppe Rescue),
## dim and mirrored, so that the player sees himself and where his raised
## hands point (see HandCursor).

## How much of the picture shows, and how bright.
const ALPHA := 0.55
const BRIGHTNESS := 0.45

var _vision: Node


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        _vision = holder.service


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    if _vision == null or _vision.GetStatus() == "Disabled":
        return
    var texture: Texture2D = _vision.GetCameraTexture()
    if texture == null or texture.get_size().x <= 0:
        return
    var screen := get_viewport_rect().size
    # NOTE (mristin):
    # The camera picture is not mirrored; we mirror it as we draw.
    draw_set_transform(Vector2(screen.x, 0), 0, Vector2(-1, 1))
    var shade := Color(BRIGHTNESS, BRIGHTNESS, BRIGHTNESS, ALPHA)
    draw_texture_rect(texture, Rect2(Vector2.ZERO, screen), false, shade)
    draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
