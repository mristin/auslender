class_name Flat
extends RefCounted

## Make the flat-shaded meshes of the polygon look: boxes, low-poly balls and
## prisms with a material of one color (see flat.gdshader).

const _SHADER := preload("res://scenes/flat/flat.gdshader")

static var _materials: Dictionary = {}


## A material of the color, shared by every mesh of that color.
static func material(color: Color) -> ShaderMaterial:
    var key := color.to_html()
    if not _materials.has(key):
        var made := ShaderMaterial.new()
        made.shader = _SHADER
        made.set_shader_parameter("albedo", color)
        _materials[key] = made
    return _materials[key]


## A material of the color of its own, so that it can flash alone.
static func own_material(color: Color) -> ShaderMaterial:
    var made := ShaderMaterial.new()
    made.shader = _SHADER
    made.set_shader_parameter("albedo", color)
    return made


## Add a box of the size and the color to the parent, centered at the position.
static func box(
    parent: Node3D, size: Vector3, at: Vector3, color: Color, own := false
) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    return _add(parent, mesh, at, color, own)


## Add a ball with few facets (a low-poly sphere) to the parent; more facets
## (sides around, rings from top to bottom) for what is seen up close.
static func ball(
    parent: Node3D,
    radius: float,
    at: Vector3,
    color: Color,
    own := false,
    stretch := 1.0,
    sides := 7,
    rings := 4
) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0 * stretch
    mesh.radial_segments = sides
    mesh.rings = rings
    return _add(parent, mesh, at, color, own)


## Add a limb: a tapered prism of few facets along y (the top at +y), as the
## bodies of 4D Sports Boxing, rather than a box; flatten it with its scale
## for a torso.
static func limb(
    parent: Node3D,
    top_radius: float,
    bottom_radius: float,
    length: float,
    at: Vector3,
    color: Color,
    own := false,
    sides := 8
) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = top_radius
    mesh.bottom_radius = bottom_radius
    mesh.height = length
    mesh.radial_segments = sides
    mesh.rings = 1
    return _add(parent, mesh, at, color, own)


## Add a cylinder with few facets to the parent, upright.
static func post(
    parent: Node3D, radius: float, height: float, at: Vector3, color: Color
) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 6
    mesh.rings = 1
    return _add(parent, mesh, at, color, false)


static func _add(
    parent: Node3D, mesh: Mesh, at: Vector3, color: Color, own: bool
) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = at
    instance.material_override = own_material(color) if own else material(color)
    parent.add_child(instance)
    return instance
