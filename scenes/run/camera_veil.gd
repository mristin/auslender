class_name CameraVeil
extends Control

## In a run, the camera picture over the whole scene, faint and mirrored, so
## that the player sees where he stands (see BodyReader: his torso across the
## picture is where he is across the road): the lanes in the picture, the one
## he is in lit, and a marker on his torso.

## How much the picture shows through, in [0, 1].
const ALPHA := 0.28

const LANE_LIGHT := Color(0.95, 0.76, 0.3, 0.16)
const LINE := Color(1, 1, 1, 0.35)

var vision: Node
## Where he steers now, in lanes (see BodyReader.steer).
var steer := 0.0


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    var screen := get_viewport_rect().size
    if vision != null and vision.GetStatus() != "Disabled":
        var texture: Texture2D = vision.GetCameraTexture()
        if texture != null and texture.get_size().x > 0:
            # NOTE (mristin):
            # The camera picture is not mirrored; we mirror it as we draw.
            draw_set_transform(Vector2(screen.x, 0), 0, Vector2(-1, 1))
            draw_texture_rect(texture, Rect2(Vector2.ZERO, screen), false, Color(1, 1, 1, ALPHA))
            draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
    # NOTE (mristin):
    # The edges of the road in the picture, and the middle: he is free to be
    # anywhere between the edges.
    for lanes in [-1.5, 0.0, 1.5]:
        var at: float = (0.5 + lanes * BodyReader.STEER_LANE) * screen.x
        draw_line(Vector2(at, 0), Vector2(at, screen.y), LINE if lanes != 0.0 else LANE_LIGHT, 3.0)
