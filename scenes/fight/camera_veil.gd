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
const MARK := Color("f2c14e")

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
    # The lanes in the picture: each a lane's width (BodyReader.STEER_LANE)
    # around its middle; the one he is in lit.
    var lane := clampi(roundi(steer), -1, 1)
    for k in [-1, 0, 1]:
        var left: float = (0.5 + (k - 0.5) * BodyReader.STEER_LANE) * screen.x
        var width: float = BodyReader.STEER_LANE * screen.x
        if k == lane:
            draw_rect(Rect2(left, 0, width, screen.y), LANE_LIGHT)
        draw_line(Vector2(left, 0), Vector2(left, screen.y), LINE, 3.0)
    var right: float = (0.5 + 1.5 * BodyReader.STEER_LANE) * screen.x
    draw_line(Vector2(right, 0), Vector2(right, screen.y), LINE, 3.0)
    var x: float = (0.5 + steer * BodyReader.STEER_LANE) * screen.x
    draw_circle(Vector2(x, screen.y * 0.5), 22.0, Color(MARK, 0.85))
    draw_arc(Vector2(x, screen.y * 0.5), 34.0, 0, TAU, 32, Color(MARK, 0.85), 4.0)
