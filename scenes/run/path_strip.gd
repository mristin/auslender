class_name PathStrip
extends MeshInstance3D

## The strip on the floor ahead of the player in a run (see Run): the path he
## is heading on, as wide as his body, glowing all the way to the horizon,
## following where he steers (see path_strip.gdshader).

const _SHADER := preload("res://scenes/run/path_strip.gdshader")

## How far ahead it reaches (to the horizon), in meters, and how far apart its
## chevrons are.
const LENGTH := 60.0
const SPACING := 1.0

var _spot := Vector3.ZERO


## Lay it ahead of the player's spot, as wide as his body.
func setup(spot: Vector3, width: float) -> void:
    _spot = spot
    var plane := PlaneMesh.new()
    plane.size = Vector2(width, LENGTH)
    # NOTE (mristin):
    # Fine along, so that it bends with the road (see bend.gdshaderinc).
    plane.subdivide_depth = int(LENGTH)
    mesh = plane
    var material := ShaderMaterial.new()
    material.shader = _SHADER
    material.set_shader_parameter("chevrons", LENGTH / SPACING)
    material_override = material
    position = spot + Vector3(0, 0.035, -0.3 - LENGTH * 0.5)


## Follow where he is across the road, and roll its dashes with the run
## ([param rolled]: how far the run went, in meters).
func follow(shift: float, rolled: float) -> void:
    position.x = _spot.x + shift
    (material_override as ShaderMaterial).set_shader_parameter("scroll", rolled / SPACING)
