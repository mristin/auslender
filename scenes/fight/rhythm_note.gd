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
const LABELS := {
    "straight": "JAB",
    "hook": "HOOK",
    "uppercut": "UPPERCUT",
    "cover": "COVER",
    "slip_left": "SLIP",
    "slip_right": "SLIP",
    "duck": "DUCK",
    "jump": "JUMP",
}

## The width of a symbol's stroke, and the size of its arrowhead, in meters.
const STROKE := 0.03
const HEAD_LENGTH := 0.075
const HEAD_WIDTH := 0.07

## How long the approach ring shrinks, in seconds, and from how many times
## the size of the note.
const APPROACH_SECONDS := 1.2
const APPROACH_FROM := 3.5

## How long a judged note lasts, in seconds.
const AFTER_SECONDS := 0.35

var kind := ""
var side := ""
## The song time of its beat, in seconds.
var at := 0.0
## How it was judged ("" not yet; "perfect", "good", "dodged", "miss").
var result := ""

var _arrive := Vector3.ZERO
var _from := Vector3.ZERO
var _speed := 3.0
var _judged_at := 0.0
var _materials: Array[StandardMaterial3D] = []
var _label: Label3D
var _shape: Node3D
var _approach: MeshInstance3D


## Set the note up: its move, its side ("" for an attack), the song time of
## its beat, where it arrives (in the fight's space), and how fast it flies
## (meters per second).
func setup(
    note_kind: String, note_side: String, time: float, arrive: Vector3, speed: float
) -> void:
    kind = note_kind
    side = note_side
    at = time
    _arrive = arrive
    _speed = speed
    # NOTE (mristin):
    # It comes from far ahead, closer to the middle, and spreads out to its
    # lane as it comes.
    _from = Vector3(arrive.x * 0.4, lerpf(arrive.y, 1.4, 0.5), arrive.z)
    _build()


## Place it at the song time [param now], and fade it in and out.
func place(now: float) -> void:
    var ahead := at - now
    if result != "" and result != "miss":
        ahead = at - _judged_at
    var distance := ahead * _speed
    var spread := clampf(1.0 - distance / 6.0, 0.0, 1.0)
    var lane := _from.lerp(_arrive, smoothstep(0.0, 1.0, spread))
    position = Vector3(lane.x, lane.y, _arrive.z - distance)
    var alpha := clampf((6.6 - distance) / 1.2, 0.0, 1.0)
    if result != "":
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


## Judge it at the song time [param now].
func judge(how: String, now: float) -> void:
    result = how
    _judged_at = now
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
    return result != "" and now - _judged_at > AFTER_SECONDS


func _build() -> void:
    _shape = Node3D.new()
    add_child(_shape)
    var color := ATTACK if side == "" else (LEFT if side == "left" else RIGHT)
    match kind:
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

    _add_symbol()

    _label = Label3D.new()
    _label.text = LABELS.get(kind, kind.to_upper())
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
