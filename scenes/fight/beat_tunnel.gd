class_name BeatTunnel
extends Node3D

## The tunnel through which the notes of the rhythm fight come (see Fight): a
## frame around their lanes on every beat, which rolls towards the player with
## the music (the floor near him is out of the view, so the beats show in the
## air). A frame fades as it comes close; the first beat of a bar is brighter.

## The size of a frame (around the lanes), and the width of its bars, in
## meters.
const SIZE := Vector2(1.5, 1.1)
const WIDTH := 0.025

var _arrive := Vector3.ZERO
var _lead := 2.0
var _speed := 3.0
var _beat_seconds := 0.6
var _frames: Array[MeshInstance3D] = []


## Set it up: where the frames arrive (the middle of the lanes where the notes
## meet the player), how long ahead and how fast the notes come, and the
## length of a beat (seconds).
func setup(arrive: Vector3, lead: float, speed: float, beat_seconds: float) -> void:
    _arrive = arrive
    _lead = lead
    _speed = speed
    _beat_seconds = beat_seconds
    for i in range(ceili(lead / beat_seconds) + 2):
        var frame := MeshInstance3D.new()
        var mesh := ImmediateMesh.new()
        frame.mesh = mesh
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        material.albedo_color = Color(0.6, 0.85, 1.0, 0.0)
        frame.material_override = material
        _draw_frame(mesh)
        add_child(frame)
        _frames.append(frame)


## Place the frames at the song time [param now] (hidden unless [param on]).
func place(now: float, on: bool) -> void:
    var first := ceili(now / _beat_seconds)
    for i in range(_frames.size()):
        var frame := _frames[i]
        var beat := first + i
        var ahead := beat * _beat_seconds - now
        frame.visible = on and ahead <= _lead
        frame.position = _arrive + Vector3(0, 0, -ahead * _speed)
        var material := frame.material_override as StandardMaterial3D
        var strong := 0.7 if beat % 4 == 0 else 0.3
        var near := clampf(ahead / 0.5, 0.0, 1.0)
        var far := clampf((_lead - ahead) / 0.6, 0.0, 1.0)
        material.albedo_color.a = strong * near * far


## A rectangular frame of four thin bars (in the plane of x and y).
static func _draw_frame(mesh: ImmediateMesh) -> void:
    var half := SIZE * 0.5
    var corners := [
        Vector2(-half.x, -half.y),
        Vector2(half.x, -half.y),
        Vector2(half.x, half.y),
        Vector2(-half.x, half.y),
    ]
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
    for k in range(4):
        var a: Vector2 = corners[k]
        var b: Vector2 = corners[(k + 1) % 4]
        var inner_a := a - a.sign() * WIDTH
        var inner_b := b - b.sign() * WIDTH
        for point in [a, b, inner_b, a, inner_b, inner_a]:
            mesh.surface_add_vertex(Vector3(point.x, point.y, 0.0))
    mesh.surface_end()
