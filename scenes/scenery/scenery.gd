class_name Scenery
extends Node3D

## The surroundings of a level (see Levels), built of flat-shaded boxes, tapered
## limbs and low-poly balls: no ring, but the land of the world.
##
## - "cave": the cave of the bear, under the rock: stalagmites and stalactites,
##   rock columns, glowing crystals, torches, paintings on the walls, bats
##   (see PropsWild);
## - "ice": the mammoth's glacier: ice blocks, icebergs, frozen trees, snowy
##   rocks with icicles, frozen lakes, a mammoth frozen in a block of ice (see
##   PropsWild);
## - "savannah": the Ice Age's other fights, on yellow grass among acacias, baobabs,
##   termite mounds, bones, huts of hides, herds of mammoths, and blue
##   mountains far away (see PropsWild);
## - "jungle": the Ice Age's run, on a path of earth through palms, bamboo,
##   giant trees with lianas, ferns, idols and huts on stilts (see PropsWild);
## - "city": the Swiss street, between houses of many colors with shutters,
##   shops, cars, tram stops, fountains and recycling bins (see PropsCity);
## - "lab": the Rochartis laboratory, a hall of benches with its equipment,
##   machines along the walls, and posters (see PropsLab);
## - "suburbs": the winter's evening among little houses with their snowy
##   roofs and lit windows, gardens, gnomes, snowmen and pines (see
##   PropsSuburbs).
##
## The props stand in three rows on both sides: small things by the road,
## the main props, and big ones further away, each picked at random of many
## kinds and varied. The player stands at [member spot], looking along -Z. In
## a run ([method scroll]), the props roll towards him on the beat, as the road
## of Antarctic Adventure, and come round again from far ahead; the road has
## three lanes (see [constant LANE]).
##
## The road of a run curves (see [method set_bend]): only the look, drawn by
## the shaders (see bend.gdshaderinc), while the game measures everything on
## the straight road. What the shaders can not bend (the text of the signs,
## glass and glowing things) is moved along with the curve here.

## How far apart the lanes of a run are, in meters.
const LANE := 1.4

## How far the props reach ahead, and behind the player, in meters.
const AHEAD := 45.0
const BEHIND := 6.0

## The rows of props: how far beyond the edge of the road (or of the ground
## of a fight) to the side (from, to), and how far apart along the road (from,
## to), in meters.
const ROWS := {
    "near": [Vector2(0.2, 0.8), Vector2(1.2, 2.4)],
    "middle": [Vector2(1.4, 3.2), Vector2(2.6, 4.2)],
    "far": [Vector2(5.5, 11.5), Vector2(6.0, 10.0)],
}

## The dusty paths of the prehistoric runs (no lanes then): their earth, their
## dust and their stones.
const DUSTY := {
    "jungle": [Color("6a4a2c"), Color("8a6a44"), Color("3a2c20")],
    "ice": [Color("c8dce8"), Color("eef4fa"), Color("8aa4b8")],
    "cave": [Color("4a3a2e"), Color("6a5644"), Color("2a221c")],
}

const _DUST := preload("res://scenes/scenery/road_dust.gdshader")

## The sidewalks of the city: how wide, and how high over the road (meters).
const SIDEWALK := 1.3
const SIDEWALK_HEIGHT := 0.12

## How far the edge of the ground of a fight is from the middle, in meters.
const FIGHT_EDGE := 1.4

## The looks: the ground, the road on it, the sky, the light.
const LOOKS := {
    "savannah":
    {
        "ground": Color("c9b04a"),
        "road": Color("b09440"),
        "sky": Color("f2c58a"),
        "ambient": Color("c8a87a"),
        "sun": 1.2,
    },
    "cave":
    {
        "ground": Color("4a3e34"),
        "road": Color("5a4a3c"),
        "sky": Color("1a1412"),
        "ambient": Color("6a5a4a"),
        "sun": 0.25,
    },
    "ice":
    {
        "ground": Color("eef4fa"),
        "road": Color("d4e4f0"),
        "sky": Color("b8d8ec"),
        "ambient": Color("a8c0d8"),
        "sun": 1.1,
    },
    "jungle":
    {
        "ground": Color("3f6a2a"),
        "road": Color("7a5a36"),
        "sky": Color("9ec9a0"),
        "ambient": Color("7a9a6a"),
        "sun": 0.9,
    },
    "city":
    {
        "ground": Color("8a8a86"),
        "road": Color("44464c"),
        "sky": Color("a8c8e8"),
        "ambient": Color("8a94a8"),
        "sun": 1.1,
    },
    "lab":
    {
        "ground": Color("e8ecef"),
        "road": Color("d4dce2"),
        "sky": Color("f4f6f8"),
        "ambient": Color("b8c4cc"),
        "sun": 0.8,
    },
    "suburbs":
    {
        "ground": Color("eef2f8"),
        "road": Color("9aa2b0"),
        "sky": Color("2a3358"),
        "ambient": Color("8a94c0"),
        "sun": 0.55,
    },
}

## Where the player stands.
var spot := Vector3.ZERO

## How much the road curves now (see [method set_bend]).
var bend := 0.0

var _look := "savannah"
var _edge := FIGHT_EDGE
var _dust: ShaderMaterial
var _scrolled := 0.0
var _props: Array[Node3D] = []
var _random := RandomNumberGenerator.new()
## The parts which the shaders do not bend (see [method _rigid_parts]), each
## [node, its position in its parent].
var _rigid: Array = []


## Build the look at the player's spot; with [param road], a road of three
## lanes leads ahead (a run).
func setup(look: String, player_spot: Vector3, road: bool) -> void:
    _look = look if LOOKS.has(look) else "savannah"
    spot = player_spot
    _random.seed = hash(_look)
    var colors: Dictionary = LOOKS[_look]
    _build_light(colors)
    var ground := Flat.box(
        self, Vector3(80, 0.1, 80), spot + Vector3(0, -0.05, -20), colors["ground"]
    )
    _fine(ground, 40)
    _edge = LANE * 1.5 + 0.5 if road else FIGHT_EDGE
    if road or _look == "city":
        var width := _edge * 2.0 - 0.2
        var middle := spot + Vector3(0, 0.0, (BEHIND - AHEAD) * 0.5)
        var strip := Flat.box(self, Vector3(width, 0.02, AHEAD + BEHIND), middle, colors["road"])
        _fine(strip, 50)
        if DUSTY.has(_look):
            # NOTE (mristin):
            # No lanes in prehistoric times: a dusty path (see
            # road_dust.gdshader), which rolls with the run.
            _dust = ShaderMaterial.new()
            _dust.shader = _DUST
            var tones: Array = DUSTY[_look]
            _dust.set_shader_parameter("base", tones[0])
            _dust.set_shader_parameter("dust", tones[1])
            _dust.set_shader_parameter("stone", tones[2])
            strip.material_override = _dust
        elif road:
            # NOTE (mristin):
            # The dashes between the lanes, which roll with the run.
            for x in [-LANE * 0.5, LANE * 0.5]:
                var z := BEHIND
                while z > -AHEAD:
                    _props.append(
                        Flat.box(
                            self, Vector3(0.05, 0.03, 0.8), spot + Vector3(x, 0.01, z), Color.WHITE
                        )
                    )
                    z -= 2.5
    if _look == "city":
        _build_sidewalks()
    if _look == "lab":
        _build_lab()
    else:
        for row in ROWS:
            _build_row(row)
        _build_horizon()
    if _look == "cave":
        # NOTE (mristin):
        # The rock overhead.
        _fine(
            Flat.box(self, Vector3(40, 0.5, 80), spot + Vector3(0, 6.2, -20), Color("2a2420")), 40
        )
    for prop in _props:
        _rigid_parts(prop)
    set_bend(0.0)


## Curve the road by [param amount] (meters to the side per square meter
## ahead; positive to the right, see bend.gdshaderinc), or straighten it with
## zero. The shaders bend everything at once; the rigid parts follow here.
func set_bend(amount: float) -> void:
    bend = amount
    RenderingServer.global_shader_parameter_set("road_bend", amount)
    RenderingServer.global_shader_parameter_set("road_spot_z", spot.z)
    _bend_rigid()


## Keep the props off the [param clearings] beside the road (the side roads
## of the forks, see Forks), each [the side (-1 left, 1 right), the nearest z,
## the farthest z] in the world; the others show.
func keep_clear(clearings: Array) -> void:
    for node in _props:
        var hide := false
        for clearing in clearings:
            var side: float = clearing[0]
            var near: float = clearing[1]
            var far: float = clearing[2]
            var z := node.position.z
            if node.position.x * side > _edge - 0.1 and z <= near and z >= far:
                hide = true
                break
        node.visible = not hide


## How far to the side the road is bent at [param z] (in the world), in
## meters.
func bend_at(z: float) -> float:
    var ahead := maxf(0.0, spot.z - z)
    return bend * ahead * ahead


func _exit_tree() -> void:
    # NOTE (mristin):
    # The curve is global to every shader: straight again for the menus.
    RenderingServer.global_shader_parameter_set("road_bend", 0.0)


## Split a long box into many pieces along, so that it bends smoothly.
static func _fine(box: MeshInstance3D, pieces: int) -> void:
    (box.mesh as BoxMesh).subdivide_depth = pieces


## Remember the parts of the prop which the shaders do not bend: the text and
## the meshes of a material of Godot's own (the glass of the ice, the
## glowing crystals and flames).
func _rigid_parts(node: Node) -> void:
    for child in node.get_children():
        var rigid := child is Label3D
        if child is MeshInstance3D:
            rigid = (child as MeshInstance3D).material_override is BaseMaterial3D
        if rigid:
            _rigid.append([child, (child as Node3D).position])
        else:
            _rigid_parts(child)


## Move the rigid parts to the side by the bend of the road where they are.
func _bend_rigid() -> void:
    for entry in _rigid:
        var node: Node3D = entry[0]
        var parent := node.get_parent() as Node3D
        var rest: Vector3 = entry[1]
        var world := parent.global_transform * rest
        var shift := parent.global_basis.inverse() * Vector3(bend_at(world.z), 0, 0)
        node.position = rest + shift


## Roll the props towards the player by [param distance] meters (a run); those
## behind him come round again from far ahead.
func scroll(distance: float) -> void:
    _scrolled += distance
    if _dust != null:
        _dust.set_shader_parameter("scroll", _scrolled)
    for node in _props:
        node.position.z += distance
        if node.position.z > spot.z + BEHIND:
            node.position.z -= AHEAD + BEHIND
    _bend_rigid()


func _build_light(colors: Dictionary) -> void:
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, 30, 0)
    sun.light_energy = colors["sun"]
    add_child(sun)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-25, -150, 0)
    fill.light_energy = 0.35
    add_child(fill)
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = colors["sky"]
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = colors["ambient"]
    settings.ambient_light_energy = 0.7
    # NOTE (mristin):
    # A haze far ahead, so that the props come out of it rather than pop up.
    settings.fog_enabled = true
    settings.fog_light_color = colors["sky"]
    settings.fog_density = 0.03
    environment.environment = settings
    add_child(environment)


## A row of props on both sides along the road (or around the fight).
func _build_row(row: String) -> void:
    var across: Vector2 = ROWS[row][0]
    var apart: Vector2 = ROWS[row][1]
    for side in [-1.0, 1.0]:
        var z := BEHIND
        while z > -AHEAD:
            var prop := Node3D.new()
            add_child(prop)
            var x: float = side * (_edge + _random.randf_range(across.x, across.y))
            # NOTE (mristin):
            # In the city, the small things stand on the sidewalk.
            var y := SIDEWALK_HEIGHT if _look == "city" and row == "near" else 0.0
            prop.position = spot + Vector3(x, y, z)
            match _look:
                "savannah":
                    PropsWild.savannah(prop, _random, row)
                "jungle":
                    PropsWild.jungle(prop, _random, row)
                "ice":
                    PropsWild.ice(prop, _random, row)
                "cave":
                    PropsWild.cave(prop, _random, row)
                "city":
                    PropsCity.build(prop, _random, row, side)
                "suburbs":
                    PropsSuburbs.build(prop, _random, row, side)
            _props.append(prop)
            z -= _random.randf_range(apart.x, apart.y)


## Far away (they stay): mountains on the savannah and behind the jungle, a
## skyline of the city, hills and the moon over the suburbs.
func _build_horizon() -> void:
    match _look:
        "savannah", "jungle", "ice":
            for i in range(9):
                var color: Color = {
                    "savannah": Color("8a9ab8"), "jungle": Color("5a7a6a"), "ice": Color("dceaf4")
                }[_look]
                var mountain := Flat.limb(
                    self,
                    0.2 if i % 3 != 1 else 1.5,
                    _random.randf_range(6.0, 11.0),
                    _random.randf_range(5.0, 12.0),
                    spot + Vector3(-48 + i * 12, 3.0, -58 + _random.randf_range(-4, 4)),
                    color,
                    false,
                    5
                )
                mountain.scale = Vector3(1, 1, 0.4)
            if _look == "savannah":
                # NOTE (mristin):
                # A volcano, smoking.
                Flat.limb(
                    self, 2.0, 9.0, 10.0, spot + Vector3(18, 5.0, -62), Color("6a5a5a"), false, 6
                )
                for k in range(4):
                    var at := spot + Vector3(18 + k * 2.0, 11.0 + k * 2.5, -62)
                    Flat.ball(self, 2.0 + k, at, Color("c8c0b8"))
        "city":
            for i in range(16):
                var height := _random.randf_range(8.0, 24.0)
                Flat.box(
                    self,
                    Vector3(_random.randf_range(4.0, 7.0), height, 4.0),
                    spot + Vector3(-45 + i * 6.0, height * 0.5, -60),
                    Color("9aa6b8").darkened(_random.randf_range(0.0, 0.2))
                )
        "suburbs":
            for i in range(6):
                var at := spot + Vector3(-40 + i * 16, -3.0, -60)
                var hill := Flat.ball(self, _random.randf_range(8, 14), at, Color("d8e2ee"))
                hill.scale = Vector3(1.6, 0.6, 1.0)
            # NOTE (mristin):
            # The moon.
            Flat.ball(self, 3.0, spot + Vector3(-20, 22, -70), Color("f4f0d8"))


## The laboratory around the fight: a hall of white walls, with benches of
## equipment along both sides, machines by the walls, posters, and lamps.
func _build_lab() -> void:
    var wall := Color("f0f2f4")
    for side in [-1.0, 1.0]:
        Flat.box(self, Vector3(0.2, 4.0, 30.0), spot + Vector3(side * 5.5, 2.0, -10.0), wall)
    Flat.box(self, Vector3(11.2, 4.0, 0.2), spot + Vector3(0, 2.0, -14.0), wall)
    Flat.box(self, Vector3(11.2, 0.2, 30.0), spot + Vector3(0, 4.0, -10.0), Color("dde2e6"))
    for k in range(18):
        Flat.box(
            self, Vector3(11.0, 0.012, 0.03), spot + Vector3(0, 0.006, 3.0 - k), Color("c4ccd2")
        )
    var logo := Label3D.new()
    logo.text = "ROCHARTIS"
    logo.font_size = 160
    logo.pixel_size = 0.004
    logo.modulate = Color("1f8f8a")
    logo.position = spot + Vector3(0, 3.0, -13.85)
    add_child(logo)
    for side in [-1.0, 1.0]:
        var z := 2.0
        while z > -13.0:
            # NOTE (mristin):
            # A bench with two things on it, a machine by the wall, and
            # something on the wall above.
            var x: float = side * 3.2
            Flat.box(self, Vector3(1.2, 0.9, 2.2), spot + Vector3(x, 0.45, z), PropsLab.STEEL)
            Flat.box(self, Vector3(1.3, 0.06, 2.3), spot + Vector3(x, 0.93, z), PropsLab.TOP)
            for dz in [-0.55, 0.55]:
                var item := Node3D.new()
                add_child(item)
                item.position = spot + Vector3(x, 0.96, z + dz)
                item.rotation.y = PI * 0.5 * side + _random.randf_range(-0.3, 0.3)
                PropsLab.on_bench(item, _random)
            var machine := Node3D.new()
            add_child(machine)
            machine.position = spot + Vector3(side * 4.7, 0, z - 1.5)
            machine.rotation.y = PI if side > 0 else 0.0
            PropsLab.by_wall(machine, _random)
            var poster := Node3D.new()
            add_child(poster)
            poster.position = spot + Vector3(side * 5.38, 2.3, z)
            poster.rotation.y = PI if side > 0 else 0.0
            PropsLab.on_wall(poster, _random)
            z -= 3.2
    for k in range(5):
        Flat.box(
            self, Vector3(1.6, 0.06, 0.4), spot + Vector3(0, 3.85, 2.0 - k * 3.5), Color("fffbe8")
        )


## The sidewalks along both sides of the city's road: raised pavement, a
## light curb, and joints which roll with a run.
func _build_sidewalks() -> void:
    var length := AHEAD + BEHIND
    var middle_z := (BEHIND - AHEAD) * 0.5
    for side in [-1.0, 1.0]:
        var x: float = side * (_edge + SIDEWALK * 0.5)
        var pavement := Flat.box(
            self,
            Vector3(SIDEWALK, SIDEWALK_HEIGHT, length),
            spot + Vector3(x, SIDEWALK_HEIGHT * 0.5, middle_z),
            Color("b4b0a8")
        )
        _fine(pavement, 50)
        var curb := Flat.box(
            self,
            Vector3(0.14, SIDEWALK_HEIGHT + 0.01, length),
            spot + Vector3(side * (_edge + 0.07), SIDEWALK_HEIGHT * 0.5, middle_z),
            Color("d8d4cc")
        )
        _fine(curb, 50)
        var z := BEHIND
        while z > -AHEAD:
            _props.append(
                Flat.box(
                    self,
                    Vector3(SIDEWALK, 0.01, 0.03),
                    spot + Vector3(x, SIDEWALK_HEIGHT + 0.005, z),
                    Color("8a867e")
                )
            )
            z -= 1.2
