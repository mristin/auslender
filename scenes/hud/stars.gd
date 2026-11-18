class_name Stars
extends Control

## A row of stars, as a level's result (see Scoring.stars): the stars he got
## gold, the others dim, out of Scoring.STARS_MOST. The kids who play know
## stars, not the letters of the English grades.

const GOLD := Color("f2c14e")
const DIM := Color(1, 1, 1, 0.22)
const INK := Color("0c0e14")

## How many stars he got.
var count := 0
## How big a star is (the radius of its points), in pixels.
var radius := 14.0


func _init(stars := 0, star_radius := 14.0) -> void:
    count = stars
    radius = star_radius
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(width(star_radius), star_radius * 2.0)


## How wide the row is, for stars of the [param star_radius].
static func width(star_radius: float) -> float:
    return Scoring.STARS_MOST * star_radius * 2.4


func _draw() -> void:
    draw_row(self, Vector2(radius * 1.2, radius), count, radius)


## Draw the row of stars on [param canvas], the middle of the first at
## [param first].
static func draw_row(canvas: CanvasItem, first: Vector2, stars: int, star_radius: float) -> void:
    for i in range(Scoring.STARS_MOST):
        var center := first + Vector2(i * star_radius * 2.4, 0)
        var points := star(center, star_radius)
        var outline := points.duplicate()
        outline.append(points[0])
        canvas.draw_colored_polygon(points, GOLD if i < stars else DIM)
        canvas.draw_polyline(outline, INK, maxf(2.0, star_radius * 0.12), true)


## The points of a five-pointed star around the [param center].
static func star(center: Vector2, star_radius: float) -> PackedVector2Array:
    var points := PackedVector2Array()
    for k in range(10):
        var reach := star_radius if k % 2 == 0 else star_radius * 0.45
        var angle := -PI * 0.5 + k * PI / 5.0
        points.append(center + Vector2(cos(angle), sin(angle)) * reach)
    return points
