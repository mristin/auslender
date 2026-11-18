class_name RhythmNote
extends Node3D

## A note of the rhythm fight as it flies at the player (see Fight): it comes
## out of the distance along its lane and arrives where the player meets it on
## its beat.
##
## A punch or a kick of the player is a ring which his glove meets: cyan for
## his left hand, orange for his right, labelled with the move (JAB, HOOK,
## UPPERCUT) and with an arrow of its path (see [method _symbol]): a jab
## straight at the opponent, a hook sweeping in from its side, an uppercut
## up. They arrive where the move lands: a jab in front of his face, a hook out
## to the side, an uppercut low. An attack of the opponent is purple and says
## how to dodge it, with an arrow, too: a glove at his face (COVER: gloves
## up), a glove from the side (SLIP away from it), a bar at the height of his
## head (DUCK: down), or a bar low over the floor (JUMP: up).
##
## An approach ring shrinks onto it in the last APPROACH_SECONDS and touches
## it exactly on its beat: the "now" (one can hardly tell when a note which
## flies at oneself arrives). It is drawn over everything (the ropes and the
## opponent never hide it), and fades in out of the distance. Once judged, a
## struck or dodged note bursts, and a missed one turns grey and flies on past.

## The colors of the player's left and right, and of the attacks.
const LEFT := Color("4fc3f7")
const RIGHT := Color("ffa726")
const ATTACK := Color("b04de8")
const MISSED := Color(0.55, 0.55, 0.6)

## The labels of the notes.
## How far apart the lanes of a run are, and how wide the road is (for the
## obstacles across it), in meters.
const LANE := Scenery.LANE
const ROAD := LANE * 3.0 + 0.4

const _HOLE := preload("res://scenes/run/hole.gdshader")

## The obstacles of a run which ask for a way and a move at once (see
## [member parts]): a fence, low in one part only, to jump over there; a wall
## with a hole, to duck through; the road split, a beam to duck under on one
## side and a hurdle to jump on the other (he picks); a hole across the road
## with a plank over it (run over the plank, or jump anywhere).
const COMBOS := ["fence_jump", "fence_duck", "split", "plank"]

## How high the fences are, and their low part; how high the hole in a wall,
## and the wall.
const FENCE_HIGH := 1.5
const FENCE_LOW := 0.4
const HOLE_HIGH := 0.95
const WALL_HIGH := 2.1

## The colors of the fences and walls, by the surroundings: the boards, the
## posts, and the mark of the way through.
const FENCES := {
    "jungle": [Color("a8a048"), Color("6a5a2a"), Color("f2c14e")],
    "ice": [Color("bfe4f2"), Color("6aaad8"), Color("f2c14e")],
    "cave": [Color("7a6a5a"), Color("4a3e34"), Color("f2c14e")],
    "city": [Color("c8ccd2"), Color("8a2a24"), Color("f2c14e")],
    "suburbs": [Color("f4f2ee"), Color("8a6a4a"), Color("e8701a")],
}

const LABELS := {
    "lane_left": "",
    "lane_middle": "",
    "lane_right": "",
    "straight": "JAB",
    "hook": "HOOK",
    "uppercut": "UPPERCUT",
    "cover": "COVER",
    "slip_left": "SLIP",
    "slip_right": "SLIP",
    "duck": "DUCK",
    "jump": "JUMP",
    "fence_jump": "",
    "fence_duck": "",
    "split": "",
    "plank": "",
}

## The width of a symbol's stroke, and the size of its arrowhead, in meters.
const STROKE := 0.03
const HEAD_LENGTH := 0.075
const HEAD_WIDTH := 0.07

## How far out to its hand's side a punch comes in from, in meters.
const SIDE_FROM := 2.2

## How long the approach ring shrinks, in seconds, and from how many times
## the size of the note.
const APPROACH_SECONDS := 1.2
const APPROACH_FROM := 3.5

## How long a judged note lasts, in seconds.
const AFTER_SECONDS := 0.35

## The free gap of a steering note: its middle (meters from the middle of the
## road) and its width.
var gap := 0.0
var gap_width := 1.5

## How far to the side it follows the player (meters; in a run, where he
## steers), added to where it flies.
var follow := 0.0

var kind := ""
var side := ""
## The song time of its beat, in seconds.
var at := 0.0
## How it was judged ("" not yet; "perfect", "good", "dodged", "miss").
var result := ""
## The parts across the road of a combined obstacle (see COMBOS), from left
## to right: [from, to, what] (meters from the middle of the road), where
## "what" is "block" (no way through), "" (free), "jump" or "duck" (the move
## it asks for).
var parts: Array = []

var _arrive := Vector3.ZERO
var _from := Vector3.ZERO
var _speed := 3.0
var _judged_at := 0.0
var _materials: Array[StandardMaterial3D] = []
var _label: Label3D
var _shape: Node3D
var _approach: MeshInstance3D
var _attack_color := ATTACK
## The surroundings of a run (see Scenery), whose obstacles it shows; "" in a
## fight.
var _theme := ""
## The obstacles of a steering note across the road (from, to; meters from
## the middle of the road).
var _blocks: Array[Vector2] = []
var _symbol_parts: Array[MeshInstance3D] = []
var _words: Array[Label3D] = []


## Set the note up: its move, its side ("" for an attack), the song time of
## its beat, where it arrives (in the fight's space), how fast it flies
## (meters per second), and the color of the attacks or obstacles.
func setup(
    note_kind: String,
    note_side: String,
    time: float,
    arrive: Vector3,
    speed: float,
    attack_color := ATTACK,
    theme := "",
    gap_at := Vector2(0.0, 1.5),
    across: Array = []
) -> void:
    kind = note_kind
    side = note_side
    at = time
    _arrive = arrive
    _speed = speed
    _attack_color = attack_color
    _theme = theme
    gap = gap_at.x
    gap_width = gap_at.y
    parts = across
    for part: Array in parts:
        if part[2] == "block":
            _blocks.append(Vector2(part[0], part[1]))
    # NOTE (mristin):
    # It comes from far ahead, closer to the middle, and spreads out to its
    # lane as it comes.
    _from = Vector3(arrive.x * 0.4, lerpf(arrive.y, 1.4, 0.5), arrive.z)
    if side != "":
        # NOTE (mristin):
        # A punch comes in from its hand's side, far out, so that one sees
        # clearly which hand it asks for.
        var out := -1.0 if side == "left" else 1.0
        _from = Vector3(out * SIDE_FROM, arrive.y + 0.3, arrive.z)
    if spans_road():
        # NOTE (mristin):
        # The obstacles stand on the road, across it or in their lanes, from
        # far away.
        _from = arrive
    _build()


## Whether it is an obstacle of a run which spans the road (it stays on the
## road, rather than following the player): a branch, a hole, or blocks in
## the lanes.
func spans_road() -> bool:
    return (
        kind.begins_with("lane_") or kind in COMBOS or (_theme != "" and kind in ["duck", "jump"])
    )


## Place it at the song time [param now], and fade it in and out.
func place(now: float) -> void:
    var ahead := at - now
    var obstacle := spans_road()
    if result != "" and result != "miss" and not obstacle:
        ahead = at - _judged_at
    var distance := ahead * _speed
    var spread := clampf(1.0 - distance / 6.0, 0.0, 1.0)
    var lane := _from.lerp(_arrive, smoothstep(0.0, 1.0, spread))
    position = Vector3(lane.x + follow, lane.y, _arrive.z - distance)
    var alpha := clampf((6.6 - distance) / 1.2, 0.0, 1.0)
    if result != "" and not obstacle:
        var age := (now - _judged_at) / AFTER_SECONDS
        alpha *= clampf(1.0 - age, 0.0, 1.0)
        if result != "miss":
            # NOTE (mristin):
            # A burst: it swells as it fades.
            _shape.scale = Vector3.ONE * (1.0 + 1.2 * age)
    var left := at - now
    _approach.visible = result == "" and left > 0.0 and left < APPROACH_SECONDS
    if _approach.visible:
        var share := left / APPROACH_SECONDS
        _approach.scale = Vector3.ONE * lerpf(1.0, APPROACH_FROM, share)
        (_approach.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - share)
    for material in _materials:
        material.albedo_color.a = alpha * (0.35 if material.has_meta("fill") else 1.0)
    _label.modulate.a = alpha
    _label.outline_modulate.a = alpha
    for word in _words:
        word.modulate.a = alpha
        word.outline_modulate.a = alpha


## Judge it at the song time [param now].
func judge(how: String, now: float) -> void:
    result = how
    _judged_at = now
    if spans_road():
        # NOTE (mristin):
        # An obstacle of a run stays as it is and rolls on past him (he
        # ducked under it, jumped over it, or ran through its gap); only its
        # marks go.
        _label.visible = false
        for word in _words:
            word.visible = false
        _symbol_parts_hide()
        return
    if how == "miss":
        for material in _materials:
            var a := material.albedo_color.a
            material.albedo_color = Color(MISSED, a)
        _label.modulate = Color(MISSED, 1.0)
    else:
        var glow := Color(1.0, 0.95, 0.6) if how == "perfect" else Color(0.75, 1.0, 0.75)
        for material in _materials:
            material.albedo_color = Color(glow, material.albedo_color.a)


## Whether it is done (judged and faded out), at the song time [param now].
func is_done(now: float) -> bool:
    if spans_road():
        # NOTE (mristin):
        # Once behind him, out of the view.
        return result != "" and (now - at) * _speed > 3.0
    return result != "" and now - _judged_at > AFTER_SECONDS


func _build() -> void:
    _shape = Node3D.new()
    add_child(_shape)
    var color := _attack_color if side == "" else (LEFT if side == "left" else RIGHT)
    match kind:
        "lane_left", "lane_middle", "lane_right":
            _build_lanes(color)
        "duck", "jump" when _theme != "":
            _build_across(color)
        "fence_jump", "fence_duck", "split", "plank":
            _build_combo()
        "duck", "jump":
            var bar := MeshInstance3D.new()
            var box := BoxMesh.new()
            box.size = Vector3(1.3, 0.12, 0.12)
            bar.mesh = box
            bar.material_override = _material(color, false)
            _shape.add_child(bar)
        "cover", "slip_left", "slip_right":
            var glove := MeshInstance3D.new()
            var ball := SphereMesh.new()
            ball.radius = 0.14
            ball.height = 0.28
            ball.radial_segments = 16
            ball.rings = 8
            glove.mesh = ball
            glove.material_override = _material(color, false)
            _shape.add_child(glove)
        _:
            var big := kind == "kick"
            var ring := MeshInstance3D.new()
            var torus := TorusMesh.new()
            torus.inner_radius = 0.13 if big else 0.09
            torus.outer_radius = 0.17 if big else 0.125
            torus.rings = 24
            torus.ring_segments = 8
            ring.mesh = torus
            ring.rotation.x = PI * 0.5
            ring.material_override = _material(color, false)
            _shape.add_child(ring)
            var disc := MeshInstance3D.new()
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = torus.inner_radius
            cylinder.bottom_radius = torus.inner_radius
            cylinder.height = 0.005
            cylinder.radial_segments = 24
            disc.mesh = cylinder
            disc.rotation.x = PI * 0.5
            disc.material_override = _material(color, true)
            _shape.add_child(disc)

    # NOTE (mristin):
    # The approach ring: thin, white, about as wide as the note.
    _approach = MeshInstance3D.new()
    var approach_torus := TorusMesh.new()
    var size := 0.22 if kind in ["duck", "jump"] else 0.16
    approach_torus.inner_radius = size
    approach_torus.outer_radius = size * 1.08
    approach_torus.rings = 32
    approach_torus.ring_segments = 4
    _approach.mesh = approach_torus
    _approach.rotation.x = PI * 0.5
    var white := StandardMaterial3D.new()
    white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    white.no_depth_test = true
    white.render_priority = 2
    white.albedo_color = Color(1, 1, 1, 0)
    _approach.material_override = white
    add_child(_approach)
    if kind.begins_with("lane_") or kind in COMBOS:
        _approach.position = Vector3(gap, 0.5, 0)

    _add_symbol()

    _label = Label3D.new()
    _label.text = LABELS.get(kind, kind.to_upper())
    if side != "":
        _label.text = "%s %s" % [side.to_upper(), _label.text]
    _label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _label.no_depth_test = true
    _label.render_priority = 3
    _label.outline_render_priority = 2
    _label.font_size = 64
    _label.outline_size = 14
    _label.pixel_size = 0.0018
    _label.modulate = Color.WHITE
    _label.outline_modulate = Color(color.darkened(0.6), 1.0)
    _label.position = Vector3(0, 0.22 if kind != "jump" else 0.18, 0)
    add_child(_label)


func _material(color: Color, fill: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.no_depth_test = true
    material.render_priority = 1
    material.albedo_color = Color(color, 0.0)
    if fill:
        material.set_meta("fill", true)
    _materials.append(material)
    return material


## The strokes of the note's symbol, in its plane (x to the player's right, y
## up), each a polyline and whether it ends in an arrowhead.
func _symbol() -> Array:
    var s := -1.0 if side == "left" else 1.0
    var strokes := []
    match kind:
        "straight":
            # NOTE (mristin):
            # Straight at him: from the hand, in towards the middle and up.
            strokes = [
                [PackedVector2Array([Vector2(s * 0.1, -0.12), Vector2(-s * 0.04, 0.07)]), true]
            ]
        "uppercut":
            strokes = [
                [
                    PackedVector2Array(
                        [Vector2(s * 0.06, -0.16), Vector2(0.0, -0.08), Vector2(0.0, 0.1)]
                    ),
                    true,
                ]
            ]
        "hook":
            # NOTE (mristin):
            # A curve which sweeps in from the hand's side, over and across.
            var curve := PackedVector2Array()
            var from := Vector2(s * 0.24, -0.06)
            var over := Vector2(s * 0.1, 0.13)
            var to := Vector2(-s * 0.1, 0.05)
            for i in range(11):
                var t := i / 10.0
                curve.append(from.lerp(over, t).lerp(over.lerp(to, t), t))
            strokes = [[curve, true]]
        "slip_left":
            strokes = [[PackedVector2Array([Vector2(0.14, 0.0), Vector2(-0.12, 0.0)]), true]]
        "slip_right":
            strokes = [[PackedVector2Array([Vector2(-0.14, 0.0), Vector2(0.12, 0.0)]), true]]
        "duck":
            strokes = [[PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.0, -0.12)]), true]]
        "jump":
            strokes = [[PackedVector2Array([Vector2(0.0, -0.08), Vector2(0.0, 0.14)]), true]]
        "lane_left", "lane_middle", "lane_right":
            # NOTE (mristin):
            # Down into the free lane.
            var x := gap
            strokes = [[PackedVector2Array([Vector2(x, 0.75), Vector2(x, 0.5)]), true]]
        "fence_jump", "fence_duck", "split", "plank":
            # NOTE (mristin):
            # Over each way through: up for a jump, down for a duck, into it
            # for a free one.
            for part: Array in parts:
                var x := (float(part[0]) + float(part[1])) * 0.5
                match part[2]:
                    "jump":
                        var y := FENCE_LOW + 0.25 if kind != "plank" else 0.35
                        strokes.append(
                            [PackedVector2Array([Vector2(x, y), Vector2(x, y + 0.3)]), true]
                        )
                    "duck":
                        strokes.append(
                            [PackedVector2Array([Vector2(x, 0.75), Vector2(x, 0.45)]), true]
                        )
                    "":
                        strokes.append(
                            [PackedVector2Array([Vector2(x, 0.75), Vector2(x, 0.5)]), true]
                        )
        "cover":
            # NOTE (mristin):
            # Both gloves up: two upright bars.
            strokes = [
                [PackedVector2Array([Vector2(-0.05, -0.09), Vector2(-0.05, 0.09)]), false],
                [PackedVector2Array([Vector2(0.05, -0.09), Vector2(0.05, 0.09)]), false],
            ]
    return strokes


## Draw the symbol: white over a dark outline, over everything.
func _add_symbol() -> void:
    for layer in [[Color(0.05, 0.05, 0.1), 0.022, 3], [Color.WHITE, 0.0, 4]]:
        var mesh := ImmediateMesh.new()
        mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
        for stroke in _symbol():
            _stroke(mesh, stroke[0], stroke[1], layer[1])
        mesh.surface_end()
        var instance := MeshInstance3D.new()
        instance.mesh = mesh
        var material := _material(layer[0], false)
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        material.render_priority = layer[2]
        instance.material_override = material
        instance.position.z = 0.01
        add_child(instance)
        _symbol_parts.append(instance)


## A thick polyline (wider by [param grow] on each side), ending in an
## arrowhead if [param head].
static func _stroke(
    mesh: ImmediateMesh, points: PackedVector2Array, head: bool, grow: float
) -> void:
    var half := STROKE * 0.5 + grow
    for i in range(points.size() - 1):
        var a := points[i]
        var b := points[i + 1]
        var along := (b - a).normalized()
        var across := Vector2(-along.y, along.x) * half
        # NOTE (mristin):
        # Overlap the segments a little, so that the joints have no gaps.
        a -= along * half * 0.5
        b += along * half * 0.5
        for p in [a + across, b + across, b - across, a + across, b - across, a - across]:
            mesh.surface_add_vertex(Vector3(p.x, p.y, 0.0))
    if head and points.size() >= 2:
        var end := points[points.size() - 1]
        var along := (end - points[points.size() - 2]).normalized()
        var across := Vector2(-along.y, along.x)
        var tip := end + along * (HEAD_LENGTH + grow * 1.5)
        var back := end - along * grow
        for p in [tip, back + across * (HEAD_WIDTH + grow), back - across * (HEAD_WIDTH + grow)]:
            mesh.surface_add_vertex(Vector3(p.x, p.y, 0.0))


## What a combined obstacle asks of a body at [param x] (meters from the
## middle of the road; see parts): "block", "", "jump" or "duck".
func move_at(x: float) -> String:
    for part: Array in parts:
        if x >= float(part[0]) and x <= float(part[1]):
            return part[2]
    return ""


## Whether the obstacles of a steering note block a body at [param x] (meters
## from the middle of the road), [param half] wide on each side.
func blocks(x: float, half: float) -> bool:
    for block in _blocks:
        if x + half > block.x and x - half < block.y:
            return true
    return false


## The parts across the road of a combined obstacle of the [param kind] (see
## RhythmNote.parts), at random: [its way through (middle, width), the
## parts].
static func combo_parts(kind: String) -> Array:
    var half := ROAD * 0.5
    var lane := randi_range(-1, 1) * Scenery.LANE + randf_range(-0.4, 0.4)
    var width := randf_range(1.3, 1.7)
    match kind:
        "plank":
            width = randf_range(0.9, 1.2)
        "split":
            # NOTE (mristin):
            # Where the road splits, and which side asks for which move.
            var divide := randf_range(-0.9, 0.9)
            var moves := ["duck", "jump"]
            moves.shuffle()
            var left := Vector2((-half + divide) * 0.5, divide + half)
            return [left, [[-half, divide, moves[0]], [divide, half, moves[1]]]]
    var middle := clampf(lane, -half + width * 0.5, half - width * 0.5)
    var from := middle - width * 0.5
    var to := middle + width * 0.5
    var way: String = {"fence_jump": "jump", "fence_duck": "duck", "plank": ""}[kind]
    var side := "jump" if kind == "plank" else "block"
    var parts: Array = [[-half, from, side], [from, to, way], [to, half, side]]
    return [
        Vector2(middle, width),
        parts.filter(func(part: Array) -> bool: return float(part[1]) - float(part[0]) > 0.05)
    ]


## The call of a combined obstacle for him at [param x] across the road:
## what to do at its way through, and where the way through is from him.
func combo_call(x: float) -> Array:
    var off := gap - x
    var from := "front"
    if off < -0.5:
        from = "right"
    elif off > 0.5:
        from = "left"
    match kind:
        "fence_jump":
            return ["LOW PART: JUMP!", from if from != "front" else "low"]
        "fence_duck":
            return ["HOLE: DUCK!", from]
        "plank":
            return ["PLANK OR JUMP!", from]
    return ["DUCK OR JUMP!", "front"]


## The obstacles of a steering note: blocks of varied widths across the road,
## but in its free gap (anywhere, of any width: as the holes of Antarctic
## Adventure, the road is not cut into lanes).
func _build_lanes(color: Color) -> void:
    var half := ROAD * 0.5
    for segment in [Vector2(-half, gap - gap_width * 0.5), Vector2(gap + gap_width * 0.5, half)]:
        var length: float = segment.y - segment.x
        if length < 0.2:
            continue
        _blocks.append(segment)
        var count := maxi(1, roundi(length / 1.0))
        var width := length / count
        for k in range(count):
            _build_block(segment.x + width * (k + 0.5), color, width - 0.06)


## An obstacle across the road: to duck under, a branch (with leaves; in the
## city, a beam with warning stripes; in the suburbs, a branch heavy with
## snow); to jump over, a hole in the road with a rim (in the ice, a
## crevasse).
func _build_across(_color: Color) -> void:
    if kind == "duck":
        var city := _theme == "city"
        var beam := _part(
            Vector3(ROAD, 0.16, 0.16), Vector3.ZERO, Color("e8c020") if city else Color("6a4a2a")
        )
        beam.rotation.z = 0.04
        if city:
            for k in range(8):
                _part(
                    Vector3(0.25, 0.17, 0.17),
                    Vector3(-ROAD * 0.5 + 0.3 + k * 0.6, 0, 0),
                    Color("1a1a1a")
                )
            for x in [-ROAD * 0.5, ROAD * 0.5]:
                _part(Vector3(0.12, 1.7, 0.12), Vector3(x, -0.85, 0), Color("c8c8c8"))
        else:
            var leaf := Color("f4f7fb") if _theme == "suburbs" else Color("3f8a30")
            for k in range(7):
                var x := -ROAD * 0.5 + 0.4 + k * 0.65
                var tuft := _part(
                    Vector3(0.45, 0.22, 0.3), Vector3(x, 0.12 + (k % 2) * 0.06, 0), leaf
                )
                tuft.rotation.z = (k % 3 - 1) * 0.3
        return
    var random := RandomNumberGenerator.new()
    random.seed = hash(at)
    if _theme == "jungle" and random.randf() < 0.5:
        _build_log(random)
    else:
        _build_hole(random)


## A hole across the road, as real as flat polygons make it: an irregular pit,
## its far inner wall showing the layers of the earth (blue ice going dark in
## a crevasse of the glacier), black at the bottom; clods and stones around
## its rim. Seen from above and ahead, the near wall hides, the far one shows.
func _build_hole(random: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # The colors of the rim, the wall, its layers and the depth, by the
    # surroundings.
    var tones := {
        "ice": [Color("eef4fa"), Color("8ac4e8"), Color("4a8ac0"), Color("06142a")],
        "city": [Color("3a3c42"), Color("6a4a2c"), Color("4a3220"), Color("080605")],
        "suburbs": [Color("f4f7fb"), Color("6a4a2c"), Color("4a3220"), Color("080605")],
        "cave": [Color("5a4a3c"), Color("3e3026"), Color("2a2018"), Color("040302")],
    }
    var colors: Array = tones.get(
        _theme, [Color("8a6a44"), Color("7a5634"), Color("5a3c22"), Color("080605")]
    )
    var quad := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(ROAD + 1.0, 1.8)
    quad.mesh = plane
    quad.position = Vector3(0, 0.02, 0)
    var material := ShaderMaterial.new()
    material.shader = _HOLE
    material.set_shader_parameter("rim", colors[0])
    material.set_shader_parameter("wall", colors[1])
    material.set_shader_parameter("strata", colors[2])
    material.set_shader_parameter("deep", colors[3])
    material.set_shader_parameter("size", plane.size)
    material.set_shader_parameter("hole", Vector2(ROAD * 0.5 + 0.1, 0.5))
    material.set_shader_parameter("seed", random.randf() * 100.0)
    quad.material_override = material
    _shape.add_child(quad)
    # NOTE (mristin):
    # A few stones on its rim, for the depth.
    for k in range(random.randi_range(4, 8)):
        var at := Vector3(
            random.randf_range(-ROAD * 0.5, ROAD * 0.5), 0.04, 0.55 * (1 if k % 2 == 0 else -1)
        )
        var stone := _ball(random.randf_range(0.05, 0.11), at, colors[0].darkened(0.25))
        stone.scale = Vector3(1.3, 0.55, 1.0)


## A fallen tree across the path (in the jungle): a thick trunk of bark, with
## broken stubs of branches, a tuft of leaves, and its roots at one end.
func _build_log(random: RandomNumberGenerator) -> void:
    var bark := Color("5a3e26")
    var length := ROAD + 1.4
    var radius := random.randf_range(0.26, 0.34)
    var trunk := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius * 0.85
    cylinder.bottom_radius = radius
    cylinder.height = length
    cylinder.radial_segments = 9
    trunk.mesh = cylinder
    trunk.rotation.z = PI * 0.5
    trunk.rotation.y = random.randf_range(-0.12, 0.12)
    trunk.position = Vector3(0, radius, 0)
    trunk.material_override = _material(bark, false)
    _shape.add_child(trunk)
    # NOTE (mristin):
    # The bark's grooves along it, the stubs of the branches, moss.
    for k in range(5):
        var groove := _part(
            Vector3(length * 0.9, 0.03, 0.04),
            Vector3(0, radius + random.randf_range(-0.1, 0.25), random.randf_range(-0.2, 0.2)),
            bark.darkened(0.35)
        )
        groove.rotation.y = trunk.rotation.y
    for k in range(random.randi_range(2, 4)):
        var stub := _part(
            Vector3(0.08, 0.45, 0.08),
            Vector3(
                random.randf_range(-length * 0.4, length * 0.4),
                radius * 2.0 + 0.15,
                random.randf_range(-0.1, 0.1)
            ),
            bark
        )
        stub.rotation.z = random.randf_range(-0.6, 0.6)
    for k in range(3):
        var at := Vector3(random.randf_range(-length * 0.4, length * 0.4), radius * 1.8, 0)
        var moss := _ball(random.randf_range(0.12, 0.2), at, Color("4a7a2a"))
        moss.scale = Vector3(1.5, 0.5, 1.0)
    var top_end := (1.0 if random.randf() < 0.5 else -1.0) * length * 0.5
    for k in range(4):
        _ball(
            random.randf_range(0.3, 0.5),
            Vector3(
                top_end + random.randf_range(-0.3, 0.3),
                0.5 + random.randf_range(0, 0.4),
                random.randf_range(-0.4, 0.4)
            ),
            Color("3f7a2a")
        )
    for k in range(5):
        var root := _part(
            Vector3(0.06, 0.6, 0.06), Vector3(-top_end, radius, 0), bark.darkened(0.2)
        )
        root.rotation = Vector3(random.randf_range(-1.0, 1.0), 0, random.randf_range(-1.2, 1.2))


## A block in a lane, as the surroundings have it: a boulder (in the jungle
## and the cave, an ice block on the glacier), a barrier with a cone (in the
## city), a snowman (in the suburbs).
func _build_block(x: float, color: Color, width := 1.0) -> void:
    var holder := _shape
    # NOTE (mristin):
    # The blocks are a meter wide; stretched to the width.
    _shape = Node3D.new()
    holder.add_child(_shape)
    _shape.position.x = x
    _shape.scale.x = width
    x = 0.0
    match _theme:
        "city":
            _part(Vector3(1.0, 0.25, 0.12), Vector3(x, 0.75, 0), Color("e8701a"))
            _part(Vector3(1.0, 0.1, 0.13), Vector3(x, 0.75, 0), Color("f4f2ee"))
            for dx in [-0.4, 0.4]:
                _part(Vector3(0.08, 0.75, 0.08), Vector3(x + dx, 0.37, 0), Color("4a4a4a"))
            var cone := _ball(0.22, Vector3(x, 0.25, -0.3), Color("e8701a"))
            cone.scale = Vector3(1, 1.6, 1)
        "suburbs":
            _ball(0.35, Vector3(x, 0.32, 0), Color("f4f7fb"))
            _ball(0.25, Vector3(x, 0.85, 0), Color("f4f7fb"))
            _ball(0.06, Vector3(x, 0.9, -0.25), Color("f08a24"))
        "ice":
            var ice := _part(Vector3(0.9, 0.9, 0.7), Vector3(x, 0.45, 0), Color("bfe4f2"))
            ice.rotation.y = 0.3
        _:
            var rock := _ball(0.45, Vector3(x, 0.35, 0), color)
            rock.scale = Vector3(1.2, 0.85, 1.0)
    _shape = holder


## A box of the obstacle (it fades with the note).
func _part(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    instance.mesh = box
    instance.position = at
    instance.material_override = _material(color, false)
    _shape.add_child(instance)
    return instance


## A ball of the obstacle (it fades with the note).
func _ball(radius: float, at: Vector3, color: Color) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    sphere.radial_segments = 10
    sphere.rings = 6
    instance.mesh = sphere
    instance.position = at
    instance.material_override = _material(color, false)
    _shape.add_child(instance)
    return instance


## Hide the symbol and the approach ring (once judged).
func _symbol_parts_hide() -> void:
    for part in _symbol_parts:
        part.visible = false
    _approach.visible = false


## A combined obstacle (see COMBOS), in the look of the surroundings: its
## parts across the road, the way through marked, with a word over it.
func _build_combo() -> void:
    var colors: Array = FENCES.get(_theme, FENCES["jungle"])
    if kind == "plank":
        var random := RandomNumberGenerator.new()
        random.seed = hash(at)
        _build_hole(random)
    for part: Array in parts:
        var from: float = part[0]
        var to: float = part[1]
        var middle := (from + to) * 0.5
        var width := to - from
        match [kind, part[2]]:
            ["fence_jump", "block"]:
                _fence(from, to, FENCE_HIGH, colors)
            ["fence_jump", "jump"]:
                _fence(from, to, FENCE_LOW, colors)
                _stripes(middle, width, FENCE_LOW, colors[2])
                _word("JUMP", middle, FENCE_LOW + 0.75)
            ["fence_duck", "block"]:
                _part(
                    Vector3(width, WALL_HIGH, 0.25), Vector3(middle, WALL_HIGH * 0.5, 0), colors[0]
                )
                _joints(from, to, 0.0, WALL_HIGH, colors[1])
            ["fence_duck", "duck"]:
                var lintel := WALL_HIGH - HOLE_HIGH
                _part(
                    Vector3(width, lintel, 0.25),
                    Vector3(middle, HOLE_HIGH + lintel * 0.5, 0),
                    colors[0]
                )
                _joints(from, to, HOLE_HIGH, WALL_HIGH, colors[1])
                _stripes(middle, width, HOLE_HIGH, colors[2])
                _word("DUCK", middle, HOLE_HIGH + 0.45)
            ["split", "duck"]:
                # NOTE (mristin):
                # A beam at the height of his head, on posts.
                _part(Vector3(width, 0.2, 0.2), Vector3(middle, 1.3, 0), colors[1])
                _stripes(middle, width, 1.2, colors[2])
                _word("DUCK", middle, 1.75)
            ["split", "jump"]:
                # NOTE (mristin):
                # A hurdle, low.
                _part(Vector3(width, 0.12, 0.12), Vector3(middle, FENCE_LOW, 0), colors[0])
                _stripes(middle, width, FENCE_LOW + 0.06, colors[2])
                for x in [from + 0.1, to - 0.1]:
                    _part(Vector3(0.08, FENCE_LOW, 0.08), Vector3(x, FENCE_LOW * 0.5, 0), colors[1])
                _word("JUMP", middle, FENCE_LOW + 0.75)
            ["plank", ""]:
                _part(Vector3(width, 0.06, 2.0), Vector3(middle, 0.05, 0), Color("8a5a2a"))
                for x in [from + 0.04, to - 0.04]:
                    _part(Vector3(0.05, 0.08, 2.0), Vector3(x, 0.1, 0), Color("5a3a1a"))
                _word("RUN", middle, 0.9)
    if kind == "split":
        # NOTE (mristin):
        # A post where the road splits.
        var divide: float = parts[0][1]
        _part(Vector3(0.14, 1.6, 0.14), Vector3(divide, 0.8, 0), colors[1])
    if kind == "plank":
        _word("OR JUMP", 0.0, 1.5)


## A fence from [param from] to [param to] across the road, [param height]
## high: posts and boards.
func _fence(from: float, to: float, height: float, colors: Array) -> void:
    var width := to - from
    var middle := (from + to) * 0.5
    var rails := maxi(1, roundi(height / 0.45))
    for k in range(rails):
        var y := height * (k + 0.6) / (rails + 0.1)
        _part(Vector3(width, 0.16, 0.06), Vector3(middle, y, 0), colors[0])
    var x := from + 0.05
    while x <= to:
        _part(Vector3(0.1, height + 0.08, 0.1), Vector3(x, (height + 0.08) * 0.5, -0.04), colors[1])
        x += 0.6


## The joints of the bricks (or the blocks of ice, the logs) of a wall, from
## [param from] to [param to] across the road, between the heights
## [param low] and [param high].
func _joints(from: float, to: float, low: float, high: float, color: Color) -> void:
    var row := 0
    var y := low + 0.3
    while y < high:
        _part(Vector3(to - from, 0.03, 0.02), Vector3((from + to) * 0.5, y, 0.13), color)
        var x := from + (0.3 if row % 2 == 0 else 0.6)
        while x < to:
            _part(Vector3(0.03, 0.3, 0.02), Vector3(x, y - 0.15, 0.13), color)
            x += 0.6
        y += 0.3
        row += 1


## Warning stripes along the top of the way through, at [param y].
func _stripes(middle: float, width: float, y: float, color: Color) -> void:
    var count := maxi(2, roundi(width / 0.3))
    for k in range(count):
        var x := middle - width * 0.5 + width * (k + 0.5) / count
        _part(
            Vector3(width / count - 0.02, 0.07, 0.08),
            Vector3(x, y, 0.1),
            color if k % 2 == 0 else Color("1a1a1a")
        )


## A word over the way through (it fades with the note, and goes once
## judged).
func _word(text: String, x: float, y: float) -> void:
    var word := Label3D.new()
    word.text = text
    word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    word.no_depth_test = true
    word.render_priority = 3
    word.outline_render_priority = 2
    word.font_size = 64
    word.outline_size = 14
    word.pixel_size = 0.004
    word.outline_modulate = Color("1a1a1a")
    word.position = Vector3(x, y, 0)
    _shape.add_child(word)
    _words.append(word)
