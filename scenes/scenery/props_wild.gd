class_name PropsWild
extends RefCounted

## The props of the Ice Age (see Scenery): the savannah of the fights and the
## jungle of the run, each of many kinds, varied at random in size, color and
## turn, in three rows: small things by the road ("near"), the main props
## ("middle"), and big ones further away ("far").

const BARK := Color("5a4028")
const BARK_DARK := Color("3f2c1a")
const LEAF := Color("6a8a2a")
const LEAF_DARK := Color("3f6a24")
const JUNGLE := Color("2f7a2a")
const JUNGLE_DARK := Color("1f5a22")
const ROCK := Color("9a8a6a")
const BONE := Color("eee4cc")
const HIDE := Color("a07a4a")
const FIRE := Color("f08a24")
const WATER := Color("4a8ac0")
const ICE := Color("bfe4f2")
const ICE_DEEP := Color("8ac4e0")
const SNOW := Color("f2f6fa")
const CAVE_ROCK := Color("5a4e46")
const CAVE_DARK := Color("3a322c")


## Dress the prop of the savannah in its row.
static func savannah(p: Node3D, r: RandomNumberGenerator, row: String) -> void:
    match row:
        "near":
            _pick(p, r, [_grass, _grass, _flowers, _pebbles, _bones, _bush_small, _termite_small])
        "far":
            _pick(p, r, [_baobab, _boulders, _hut, _standing_stones, _herd, _cliff])
        _:
            _pick(
                p,
                r,
                [
                    _acacia,
                    _acacia,
                    _dead_tree,
                    _rock,
                    _termite_mound,
                    _campfire,
                    _skeleton,
                    _bush,
                    _pond,
                    _tusk_arch,
                    _hut,
                    _boulders,
                ]
            )


## Dress the prop of the jungle in its row.
static func jungle(p: Node3D, r: RandomNumberGenerator, row: String) -> void:
    match row:
        "near":
            _pick(p, r, [_fern, _fern, _mushrooms, _flowers, _grass_tall, _mossy_rock, _log])
        "far":
            _pick(p, r, [_broadleaf, _broadleaf, _bamboo, _stilt_hut, _idol, _waterfall])
        _:
            _pick(
                p,
                r,
                [
                    _palm,
                    _palm,
                    _banana,
                    _broadleaf,
                    _bamboo,
                    _lianas,
                    _parrot_tree,
                    _fern_big,
                    _mossy_rock,
                    _idol,
                    _log,
                    _mushrooms_big,
                ]
            )


## Dress the prop of the cave (the Ice Age's cave of the bear) in its row.
static func cave(p: Node3D, r: RandomNumberGenerator, row: String) -> void:
    match row:
        "near":
            _pick(p, r, [_stalagmites, _crystals, _bones, _mushrooms, _puddle, _pebbles])
        "far":
            _pick(p, r, [_cave_wall, _cave_wall, _cave_wall])
        _:
            _pick(
                p,
                r,
                [
                    _rock_column,
                    _rock_column,
                    _torch,
                    _crystal_cluster,
                    _stalactites,
                    _stalactites,
                    _boulders_dark,
                    _painting,
                    _bats,
                    _skeleton,
                    _campfire,
                ]
            )


## Dress the prop of the ice (the Ice Age's glacier) in its row.
static func ice(p: Node3D, r: RandomNumberGenerator, row: String) -> void:
    match row:
        "near":
            _pick(p, r, [_snow_drift, _snow_drift, _ice_shards, _bones, _snowy_rock, _footprints])
        "far":
            _pick(p, r, [_glacier, _glacier, _iceberg, _frozen_mammoth, _ice_spires])
        _:
            _pick(
                p,
                r,
                [
                    _ice_block,
                    _ice_block,
                    _iceberg,
                    _frozen_tree,
                    _snowy_rock,
                    _icicle_rock,
                    _frozen_lake,
                    _frozen_mammoth,
                    _hide_tent,
                    _ice_spires,
                    _skeleton,
                    _snow_pine,
                ]
            )


static func _pick(p: Node3D, r: RandomNumberGenerator, builders: Array) -> void:
    (builders[r.randi() % builders.size()] as Callable).call(p, r)
    p.rotation.y = r.randf_range(-PI, PI)
    p.scale *= r.randf_range(0.8, 1.25)


static func _tint(color: Color, r: RandomNumberGenerator) -> Color:
    return (
        color.lightened(r.randf_range(-0.12, 0.12))
        if r.randf() < 0.5
        else color.darkened(r.randf_range(0.0, 0.12))
    )


static func _acacia(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(2.0, 3.0)
    var trunk := Flat.limb(p, 0.07, 0.14, height, Vector3(0, height * 0.5, 0), BARK, false, 6)
    trunk.rotation.z = r.randf_range(-0.12, 0.12)
    for k in range(r.randi_range(1, 3)):
        var crown := Flat.limb(
            p,
            r.randf_range(1.0, 1.8),
            r.randf_range(0.8, 1.3),
            0.3,
            Vector3(r.randf_range(-0.6, 0.6), height + k * 0.25, r.randf_range(-0.5, 0.5)),
            _tint(LEAF, r),
            false,
            8
        )
        crown.scale = Vector3(1, 1, 0.8)


static func _baobab(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.45, 0.8, 4.0, Vector3(0, 2.0, 0), _tint(Color("8a7058"), r), false, 8)
    for k in range(5):
        var branch := Flat.limb(p, 0.05, 0.15, 1.2, Vector3(0, 4.3, 0), BARK, false, 5)
        branch.rotation = Vector3(0, k * TAU / 5.0, 0.8)
        Flat.ball(p, 0.45, Vector3(cos(k * TAU / 5.0) * 0.9, 4.8, -sin(k * TAU / 5.0) * 0.9), LEAF)


static func _dead_tree(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.05, 0.12, 2.2, Vector3(0, 1.1, 0), Color("8a7a6a"), false, 5)
    for k in range(r.randi_range(2, 4)):
        var branch := Flat.limb(
            p, 0.02, 0.05, 0.9, Vector3(0, 1.4 + k * 0.3, 0), Color("8a7a6a"), false, 5
        )
        branch.rotation = Vector3(
            r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(0.6, 1.1)
        )


static func _rock(p: Node3D, r: RandomNumberGenerator) -> void:
    var rock := Flat.ball(
        p, r.randf_range(0.4, 0.9), Vector3(0, 0.2, 0), _tint(ROCK, r), false, 1.0, 7, 4
    )
    rock.scale = Vector3(r.randf_range(1.0, 1.6), r.randf_range(0.5, 0.9), 1.0)


static func _boulders(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 6)):
        var size := r.randf_range(0.4, 1.4)
        var at := Vector3(r.randf_range(-1.5, 1.5), size * 0.5 + k * 0.1, r.randf_range(-1.0, 1.0))
        Flat.ball(p, size, at, _tint(ROCK, r), false, 1.0, 6, 4)


static func _cliff(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(3.0, 6.0)
    var cliff := Flat.limb(
        p, 1.5, 2.5, height, Vector3(0, height * 0.5, 0), _tint(Color("a08a68"), r), false, 6
    )
    cliff.scale = Vector3(1.4, 1, 0.8)
    # NOTE (mristin):
    # A cave in it, dark.
    Flat.box(p, Vector3(1.2, 1.4, 0.2), Vector3(0, 0.7, -1.5), Color("2a2018"))


static func _grass(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 7)):
        var blade := Flat.limb(
            p,
            0.005,
            0.03,
            r.randf_range(0.3, 0.6),
            Vector3.ZERO,
            _tint(Color("b8a040"), r),
            false,
            3
        )
        blade.position = Vector3(r.randf_range(-0.2, 0.2), 0.2, r.randf_range(-0.2, 0.2))
        blade.rotation = Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4))


static func _grass_tall(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(5, 9)):
        var blade := Flat.limb(
            p, 0.005, 0.035, r.randf_range(0.6, 1.1), Vector3.ZERO, _tint(JUNGLE, r), false, 3
        )
        blade.position = Vector3(r.randf_range(-0.3, 0.3), 0.4, r.randf_range(-0.3, 0.3))
        blade.rotation = Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))


static func _flowers(p: Node3D, r: RandomNumberGenerator) -> void:
    var colors := [
        Color("e05a5a"), Color("f2c14e"), Color("e8e4f0"), Color("b04de8"), Color("f08a24")
    ]
    for k in range(r.randi_range(3, 6)):
        var at := Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4))
        Flat.limb(p, 0.008, 0.008, 0.3, at + Vector3(0, 0.15, 0), Color("3f6a24"), false, 3)
        Flat.ball(
            p, 0.05, at + Vector3(0, 0.32, 0), colors[r.randi() % colors.size()], false, 0.6, 6, 3
        )


static func _pebbles(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(4, 9)):
        Flat.ball(
            p,
            r.randf_range(0.05, 0.15),
            Vector3(r.randf_range(-0.5, 0.5), 0.03, r.randf_range(-0.5, 0.5)),
            _tint(ROCK, r),
            false,
            0.6,
            5,
            3
        )


static func _bones(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(2, 4)):
        var bone := Flat.limb(
            p,
            0.03,
            0.03,
            0.4,
            Vector3(r.randf_range(-0.3, 0.3), 0.03, r.randf_range(-0.3, 0.3)),
            BONE,
            false,
            5
        )
        bone.rotation = Vector3(PI * 0.5, r.randf() * TAU, 0)
    Flat.ball(p, 0.12, Vector3(0.3, 0.1, 0), BONE, false, 1.1)


static func _skeleton(p: Node3D, _r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # The ribs of a mammoth, arching out of the grass, and its skull.
    for k in range(6):
        var rib := Flat.limb(p, 0.03, 0.05, 1.2, Vector3(-0.6 + k * 0.25, 0.5, 0), BONE, false, 5)
        rib.rotation.x = 0.5
        var other := Flat.limb(
            p, 0.03, 0.05, 1.2, Vector3(-0.6 + k * 0.25, 0.5, 0.6), BONE, false, 5
        )
        other.rotation.x = -0.5
    Flat.ball(p, 0.35, Vector3(1.1, 0.3, 0.3), BONE, false, 1.0, 7, 4)
    var tusk := Flat.limb(p, 0.02, 0.06, 1.0, Vector3(1.5, 0.4, 0.3), BONE, false, 5)
    tusk.rotation.z = -1.0


static func _tusk_arch(p: Node3D, _r: RandomNumberGenerator) -> void:
    for x in [-0.7, 0.7]:
        var tusk := Flat.limb(p, 0.04, 0.12, 2.6, Vector3(x * 0.8, 1.2, 0), BONE, false, 6)
        tusk.rotation.z = 0.45 if x > 0 else -0.45
    Flat.box(p, Vector3(0.4, 0.4, 0.3), Vector3(0, 2.4, 0), HIDE)


static func _bush(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 5)):
        Flat.ball(
            p,
            r.randf_range(0.3, 0.6),
            Vector3(r.randf_range(-0.5, 0.5), 0.3, r.randf_range(-0.5, 0.5)),
            _tint(LEAF_DARK, r),
            false,
            0.9,
            6,
            4
        )


static func _bush_small(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.ball(
        p, r.randf_range(0.2, 0.35), Vector3(0, 0.15, 0), _tint(LEAF_DARK, r), false, 0.8, 6, 4
    )


static func _termite_mound(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(1.2, 2.4)
    Flat.limb(
        p, 0.08, 0.45, height, Vector3(0, height * 0.5, 0), _tint(Color("b0703a"), r), false, 6
    )
    Flat.limb(
        p, 0.05, 0.2, height * 0.6, Vector3(0.35, height * 0.3, 0.1), Color("a0603a"), false, 6
    )


static func _termite_small(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.04, 0.18, 0.6, Vector3(0, 0.3, 0), Color("b0703a"), false, 5)


static func _campfire(p: Node3D, _r: RandomNumberGenerator) -> void:
    for k in range(7):
        var angle := k * TAU / 7.0
        Flat.ball(
            p, 0.12, Vector3(cos(angle) * 0.45, 0.06, sin(angle) * 0.45), ROCK, false, 0.7, 5, 3
        )
    for k in range(3):
        var trunk_log := Flat.limb(p, 0.05, 0.05, 0.7, Vector3(0, 0.1, 0), BARK, false, 5)
        trunk_log.rotation = Vector3(PI * 0.5, k * PI / 3.0, 0)
    Flat.limb(p, 0.02, 0.2, 0.5, Vector3(0, 0.35, 0), FIRE, false, 6)
    Flat.limb(p, 0.01, 0.1, 0.35, Vector3(0, 0.4, 0), Color("f2d24a"), false, 6)


static func _hut(p: Node3D, r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # A tent of hides on poles.
    Flat.limb(p, 0.05, 1.2, 2.0, Vector3(0, 1.0, 0), _tint(HIDE, r), false, 7)
    for k in range(5):
        var pole := Flat.limb(p, 0.02, 0.03, 0.6, Vector3(0, 2.1, 0), BARK, false, 4)
        pole.rotation = Vector3(0, k * TAU / 5.0, 0.4)
    Flat.box(p, Vector3(0.5, 0.8, 0.1), Vector3(0, 0.4, -1.0), Color("2a2018"))


static func _standing_stones(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 5)):
        var angle := k * TAU / 5.0
        var stone := Flat.box(
            p,
            Vector3(0.5, r.randf_range(1.5, 2.6), 0.35),
            Vector3(cos(angle) * 1.5, 1.0, sin(angle) * 1.5),
            _tint(Color("8a8a84"), r)
        )
        stone.rotation.y = -angle


static func _herd(p: Node3D, r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # Mammoths grazing far away: brown humps with tusks.
    for k in range(r.randi_range(2, 4)):
        var at := Vector3(r.randf_range(-3, 3), 0, r.randf_range(-2, 2))
        Flat.ball(p, 0.8, at + Vector3(0, 1.4, 0), Color("6b4a2e"), false, 1.0, 7, 5)
        Flat.ball(p, 0.45, at + Vector3(0.8, 1.6, 0), Color("6b4a2e"), false, 1.0, 6, 4)
        for x in [-0.4, 0.4]:
            Flat.limb(p, 0.15, 0.15, 1.0, at + Vector3(x, 0.5, 0), Color("4a3220"), false, 5)


static func _pond(p: Node3D, r: RandomNumberGenerator) -> void:
    var water := Flat.limb(p, 1.2, 1.2, 0.03, Vector3(0, 0.02, 0), WATER, false, 10)
    water.scale = Vector3(1.5, 1, 1)
    for k in range(5):
        var reed := Flat.limb(
            p,
            0.01,
            0.02,
            0.8,
            Vector3(1.5 + k * 0.1, 0.4, r.randf_range(-0.4, 0.4)),
            LEAF_DARK,
            false,
            3
        )
        reed.rotation.z = r.randf_range(-0.2, 0.2)


static func _palm(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(2.6, 4.0)
    var lean := r.randf_range(-0.25, 0.25)
    var trunk := Flat.limb(
        p,
        0.09,
        0.16,
        height,
        Vector3(sin(lean) * height * 0.5, height * 0.5, 0),
        _tint(Color("6a5030"), r),
        false,
        6
    )
    trunk.rotation.z = -lean
    var top := Vector3(sin(lean) * height, height, 0)
    for k in range(r.randi_range(5, 8)):
        var angle := k * TAU / 7.0 + r.randf() * 0.3
        var leaf := Flat.box(p, Vector3(1.7, 0.04, 0.35), top, _tint(JUNGLE, r))
        leaf.rotation = Vector3(0, angle, -0.4)
        leaf.position += Vector3(cos(angle), -0.2, -sin(angle)) * 0.75
    for k in range(3):
        Flat.ball(p, 0.08, top + Vector3(0.1 * k - 0.1, -0.15, 0.1), Color("7a5a2a"))


static func _banana(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.limb(p, 0.08, 0.12, 1.8, Vector3(0, 0.9, 0), Color("5a7a3a"), false, 6)
    for k in range(6):
        var leaf := Flat.box(
            p, Vector3(1.4, 0.03, 0.5), Vector3(0, 1.8, 0), _tint(Color("4aa03a"), r)
        )
        leaf.rotation = Vector3(0, k * TAU / 6.0, -0.6)
        leaf.position += Vector3(cos(k * TAU / 6.0), 0, -sin(k * TAU / 6.0)) * 0.6
    for k in range(4):
        var fruit := Flat.limb(
            p, 0.03, 0.03, 0.2, Vector3(0.15, 1.4 - k * 0.08, 0.05 * k), Color("f2d24a"), false, 4
        )
        fruit.rotation.z = 0.6


static func _broadleaf(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(4.0, 7.0)
    Flat.limb(p, 0.2, 0.35, height, Vector3(0, height * 0.5, 0), _tint(BARK_DARK, r), false, 7)
    # NOTE (mristin):
    # Buttress roots, and a wide crown of several balls.
    for k in range(4):
        var root := Flat.box(p, Vector3(0.08, 0.8, 0.9), Vector3(0, 0.4, 0), BARK_DARK)
        root.rotation.y = k * PI * 0.5
        root.position += Vector3(cos(k * PI * 0.5), 0, -sin(k * PI * 0.5)) * 0.4
    for k in range(r.randi_range(4, 7)):
        var at := Vector3(
            r.randf_range(-1.5, 1.5), height + r.randf_range(-0.5, 1.0), r.randf_range(-1.5, 1.5)
        )
        Flat.ball(p, r.randf_range(1.0, 1.6), at, _tint(JUNGLE_DARK, r), false, 0.8, 7, 4)


static func _bamboo(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(5, 10)):
        var height := r.randf_range(2.5, 5.0)
        var at := Vector3(r.randf_range(-0.6, 0.6), height * 0.5, r.randf_range(-0.6, 0.6))
        var stalk := Flat.limb(p, 0.04, 0.05, height, at, _tint(Color("8aa83a"), r), false, 5)
        stalk.rotation.z = r.randf_range(-0.1, 0.1)
        Flat.box(p, Vector3(0.5, 0.02, 0.12), at + Vector3(0.2, height * 0.4, 0), JUNGLE)


static func _lianas(p: Node3D, r: RandomNumberGenerator) -> void:
    _broadleaf(p, r)
    for k in range(r.randi_range(3, 6)):
        Flat.limb(
            p,
            0.015,
            0.015,
            r.randf_range(2.0, 4.0),
            Vector3(r.randf_range(-1.2, 1.2), 3.5, r.randf_range(-1.2, 1.2)),
            Color("3a5a20"),
            false,
            3
        )


static func _parrot_tree(p: Node3D, r: RandomNumberGenerator) -> void:
    _palm(p, r)
    var colors := [Color("e03a2a"), Color("2a8ae0"), Color("f2c14e"), Color("3ac04a")]
    for k in range(r.randi_range(1, 3)):
        var at := Vector3(r.randf_range(-0.5, 0.5), r.randf_range(2.0, 3.0), 0.2)
        Flat.ball(p, 0.1, at, colors[r.randi() % colors.size()], false, 1.4, 6, 4)
        Flat.limb(
            p,
            0.01,
            0.04,
            0.2,
            at + Vector3(0, -0.15, 0.05),
            colors[r.randi() % colors.size()],
            false,
            4
        )


static func _fern(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(4, 7)):
        var angle := k * TAU / 6.0
        var frond := Flat.box(
            p, Vector3(0.9, 0.03, 0.25), Vector3(0, 0.35, 0), _tint(Color("3f8a30"), r)
        )
        frond.rotation = Vector3(0, angle, 0.5)
        frond.position += Vector3(cos(angle), 0, -sin(angle)) * 0.35


static func _fern_big(p: Node3D, r: RandomNumberGenerator) -> void:
    _fern(p, r)
    p.scale = Vector3.ONE * 2.0


static func _mushrooms(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(2, 5)):
        var at := Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3))
        var height := r.randf_range(0.1, 0.3)
        Flat.limb(
            p, 0.03, 0.04, height, at + Vector3(0, height * 0.5, 0), Color("f1e8d8"), false, 5
        )
        var cap := Color("d03a2a") if r.randf() < 0.5 else Color("c8a060")
        Flat.ball(p, 0.08, at + Vector3(0, height, 0), cap, false, 0.6, 7, 3)


static func _mushrooms_big(p: Node3D, r: RandomNumberGenerator) -> void:
    _mushrooms(p, r)
    p.scale = Vector3.ONE * 4.0


static func _mossy_rock(p: Node3D, r: RandomNumberGenerator) -> void:
    var size := r.randf_range(0.3, 0.8)
    var rock := Flat.ball(p, size, Vector3(0, size * 0.4, 0), Color("6a6a60"), false, 1.0, 6, 4)
    rock.scale = Vector3(1.3, 0.8, 1.0)
    Flat.ball(
        p, size * 0.8, Vector3(0, size * 0.75, 0), _tint(Color("4a7a2a"), r), false, 0.5, 6, 3
    )


static func _log(p: Node3D, r: RandomNumberGenerator) -> void:
    var trunk_log := Flat.limb(
        p, 0.2, 0.25, r.randf_range(1.5, 3.0), Vector3(0, 0.22, 0), _tint(BARK, r), false, 7
    )
    trunk_log.rotation.z = PI * 0.5
    Flat.ball(p, 0.12, Vector3(0.3, 0.42, 0), Color("4a7a2a"), false, 0.6)


static func _stilt_hut(p: Node3D, _r: RandomNumberGenerator) -> void:
    for x in [-0.9, 0.9]:
        for z in [-0.9, 0.9]:
            Flat.limb(p, 0.06, 0.06, 1.6, Vector3(x, 0.8, z), BARK, false, 5)
    Flat.box(p, Vector3(2.2, 1.4, 2.2), Vector3(0, 2.3, 0), Color("b08a5a"))
    Flat.limb(p, 0.1, 1.9, 1.2, Vector3(0, 3.6, 0), Color("c8a868"), false, 4)


static func _idol(p: Node3D, r: RandomNumberGenerator) -> void:
    var stone := _tint(Color("8a8a7a"), r)
    Flat.box(p, Vector3(0.8, 2.0, 0.6), Vector3(0, 1.0, 0), stone)
    Flat.box(p, Vector3(1.0, 0.8, 0.7), Vector3(0, 2.3, 0), stone)
    for x in [-0.22, 0.22]:
        Flat.box(p, Vector3(0.2, 0.12, 0.05), Vector3(x, 2.4, -0.36), Color("2a2a24"))
    Flat.box(p, Vector3(0.5, 0.1, 0.05), Vector3(0, 2.05, -0.36), Color("2a2a24"))
    Flat.ball(p, 0.4, Vector3(0.3, 2.8, 0), Color("4a7a2a"), false, 0.5)


static func _waterfall(p: Node3D, _r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(4.0, 5.0, 1.5), Vector3(0, 2.5, 0.6), Color("6a6a60"))
    Flat.box(p, Vector3(1.2, 5.0, 0.1), Vector3(0, 2.5, -0.2), Color("a8d8f0"))
    var pool := Flat.limb(p, 1.4, 1.4, 0.05, Vector3(0, 0.03, -1.0), WATER, false, 10)
    pool.scale = Vector3(1.4, 1, 0.8)
    for k in range(4):
        Flat.ball(p, 0.6, Vector3(-2.0 + k * 1.3, 5.0, 0.3), JUNGLE_DARK, false, 0.7, 6, 4)


static func _ice_block(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(1, 3)):
        var size := Vector3(
            r.randf_range(0.6, 1.4), r.randf_range(0.5, 1.6), r.randf_range(0.6, 1.4)
        )
        var block := Flat.box(
            p,
            size,
            Vector3(r.randf_range(-0.6, 0.6), size.y * 0.5, r.randf_range(-0.6, 0.6)),
            _tint(ICE, r)
        )
        block.rotation = Vector3(
            r.randf_range(-0.15, 0.15), r.randf() * TAU, r.randf_range(-0.15, 0.15)
        )


static func _iceberg(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(2.5, 5.0)
    Flat.limb(
        p,
        0.3,
        r.randf_range(1.5, 2.5),
        height,
        Vector3(0, height * 0.5, 0),
        _tint(ICE, r),
        false,
        5
    )
    Flat.limb(p, 0.1, 0.9, height * 0.6, Vector3(0.8, height * 0.3, 0.5), ICE_DEEP, false, 4)
    Flat.limb(p, 0.2, 0.7, 0.3, Vector3(0, height, 0), SNOW, false, 5)


static func _glacier(p: Node3D, r: RandomNumberGenerator) -> void:
    var height := r.randf_range(6.0, 12.0)
    var wall := Flat.box(
        p, Vector3(r.randf_range(6, 10), height, 3.0), Vector3(0, height * 0.5, 0), _tint(ICE, r)
    )
    wall.rotation.x = 0.1
    Flat.box(p, Vector3(wall.mesh.size.x + 0.2, 0.6, 3.2), Vector3(0, height, 0), SNOW)
    for k in range(4):
        Flat.box(
            p,
            Vector3(0.3, height * 0.8, 0.1),
            Vector3(-2.5 + k * 1.6, height * 0.45, -1.55),
            ICE_DEEP
        )


static func _ice_spires(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 6)):
        var height := r.randf_range(1.5, 4.0)
        var spire := Flat.limb(
            p,
            0.02,
            r.randf_range(0.3, 0.6),
            height,
            Vector3(r.randf_range(-1, 1), height * 0.5, r.randf_range(-1, 1)),
            _tint(ICE_DEEP, r),
            false,
            5
        )
        spire.rotation.z = r.randf_range(-0.2, 0.2)


static func _ice_shards(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 6)):
        var shard := Flat.limb(
            p,
            0.01,
            0.08,
            r.randf_range(0.2, 0.5),
            Vector3(r.randf_range(-0.4, 0.4), 0.15, r.randf_range(-0.4, 0.4)),
            ICE,
            false,
            4
        )
        shard.rotation = Vector3(r.randf_range(-0.6, 0.6), 0, r.randf_range(-0.6, 0.6))


static func _snow_drift(p: Node3D, r: RandomNumberGenerator) -> void:
    var drift := Flat.ball(p, r.randf_range(0.4, 0.9), Vector3(0, 0.0, 0), SNOW, false, 1.0, 7, 4)
    drift.scale = Vector3(1.6, 0.35, 1.0)


static func _footprints(p: Node3D, _r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # The round prints of a mammoth's feet in the snow.
    for k in range(4):
        Flat.limb(
            p,
            0.18,
            0.18,
            0.02,
            Vector3(0.3 * (k % 2), 0.01, -0.8 + k * 0.55),
            Color("c8d8e4"),
            false,
            8
        )


static func _snowy_rock(p: Node3D, r: RandomNumberGenerator) -> void:
    var size := r.randf_range(0.4, 1.0)
    var rock := Flat.ball(
        p, size, Vector3(0, size * 0.3, 0), _tint(Color("7a7a84"), r), false, 1.0, 6, 4
    )
    rock.scale = Vector3(1.3, 0.75, 1.0)
    var cover := Flat.ball(p, size * 0.85, Vector3(0, size * 0.62, 0), SNOW, false, 0.45, 6, 3)
    cover.scale = Vector3(1.3, 1, 1.0)


static func _icicle_rock(p: Node3D, r: RandomNumberGenerator) -> void:
    Flat.box(p, Vector3(2.0, 1.6, 1.2), Vector3(0, 0.8, 0), Color("6a6a74"))
    Flat.box(p, Vector3(2.2, 0.3, 1.4), Vector3(0, 1.7, 0), SNOW)
    for k in range(r.randi_range(4, 8)):
        var icicle := Flat.limb(
            p,
            0.06,
            0.005,
            r.randf_range(0.3, 0.7),
            Vector3(-0.9 + k * 0.25, 1.4, -0.62),
            ICE,
            false,
            4
        )
        icicle.rotation.x = PI


static func _frozen_tree(p: Node3D, r: RandomNumberGenerator) -> void:
    var bark := Color("6a6a78")
    Flat.limb(p, 0.06, 0.13, 2.4, Vector3(0, 1.2, 0), bark, false, 6)
    for k in range(r.randi_range(4, 6)):
        var branch := Flat.limb(p, 0.02, 0.05, 1.0, Vector3(0, 1.6 + k * 0.2, 0), bark, false, 5)
        branch.rotation = Vector3(
            r.randf_range(-0.3, 0.3), r.randf() * TAU, r.randf_range(0.6, 1.0)
        )
        var frost := Flat.box(p, Vector3(0.6, 0.05, 0.08), Vector3(0, 2.0 + k * 0.2, 0), ICE)
        frost.rotation = branch.rotation


static func _snow_pine(p: Node3D, r: RandomNumberGenerator) -> void:
    var tall := r.randf_range(0.9, 1.6)
    Flat.limb(p, 0.08, 0.12, 0.6, Vector3(0, 0.3, 0), Color("4a3020"), false, 6)
    for k in range(3):
        var y := (0.8 + k * 0.6) * tall
        var radius := (0.9 - k * 0.25) * tall
        Flat.limb(p, 0.05, radius, 0.8 * tall, Vector3(0, y, 0), Color("2a4a3a"), false, 7)
        Flat.limb(
            p, 0.05, radius * 0.75, 0.3 * tall, Vector3(0, y + 0.28 * tall, 0), SNOW, false, 7
        )


static func _frozen_lake(p: Node3D, r: RandomNumberGenerator) -> void:
    var lake := Flat.limb(p, 1.6, 1.6, 0.03, Vector3(0, 0.02, 0), ICE_DEEP, false, 10)
    lake.scale = Vector3(1.6, 1, 1.1)
    for k in range(3):
        var crack := Flat.box(
            p,
            Vector3(1.4, 0.01, 0.03),
            Vector3(r.randf_range(-0.6, 0.6), 0.04, r.randf_range(-0.6, 0.6)),
            Color("eaf6fc")
        )
        crack.rotation.y = r.randf() * TAU


static func _frozen_mammoth(p: Node3D, _r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # A mammoth frozen in a block of ice: his shape inside, his tusks out.
    var fur := Color("6b4a2e")
    Flat.ball(p, 0.9, Vector3(0, 1.4, 0), fur, false, 1.0, 7, 5)
    Flat.ball(p, 0.5, Vector3(0.9, 1.7, 0), fur, false, 1.0, 6, 4)
    for x in [-0.4, 0.4]:
        Flat.limb(p, 0.18, 0.18, 1.0, Vector3(x, 0.5, 0), fur, false, 6)
    var block := Flat.box(p, Vector3(3.2, 2.8, 2.2), Vector3(0.2, 1.4, 0), Color(0.75, 0.9, 0.97))
    block.material_override = _glassy()
    for z in [-0.2, 0.2]:
        var tusk := Flat.limb(p, 0.03, 0.08, 1.2, Vector3(1.9, 1.3, z), BONE, false, 6)
        tusk.rotation.z = -1.2


static func _hide_tent(p: Node3D, r: RandomNumberGenerator) -> void:
    _hut(p, r)
    Flat.limb(p, 0.05, 0.6, 0.6, Vector3(0, 1.7, 0), SNOW, false, 7)
    _snow_drift(p, r)


## A see-through ice.
static func _glassy() -> StandardMaterial3D:
    var glass := StandardMaterial3D.new()
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.albedo_color = Color(0.75, 0.92, 1.0, 0.45)
    glass.roughness = 0.1
    return glass


static func _stalagmites(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(2, 5)):
        var height := r.randf_range(0.3, 1.4)
        var at := Vector3(r.randf_range(-0.5, 0.5), height * 0.5, r.randf_range(-0.5, 0.5))
        Flat.limb(p, 0.01, r.randf_range(0.1, 0.25), height, at, _tint(CAVE_ROCK, r), false, 6)


static func _stalactites(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(3, 6)):
        var length := r.randf_range(0.6, 2.0)
        var at := Vector3(r.randf_range(-1.0, 1.0), 6.0 - length * 0.5, r.randf_range(-1.0, 1.0))
        var spike := Flat.limb(
            p, r.randf_range(0.12, 0.3), 0.01, length, at, _tint(CAVE_ROCK, r), false, 6
        )
        spike.rotation.x = 0.0
    _stalagmites(p, r)


static func _rock_column(p: Node3D, r: RandomNumberGenerator) -> void:
    var width := r.randf_range(0.5, 1.0)
    Flat.limb(p, width, width * 1.4, 6.0, Vector3(0, 3.0, 0), _tint(CAVE_ROCK, r), false, 7)
    Flat.ball(p, width * 1.2, Vector3(0, 0.3, 0), CAVE_DARK, false, 0.6, 7, 4)


static func _boulders_dark(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(2, 4)):
        var size := r.randf_range(0.4, 1.1)
        Flat.ball(
            p,
            size,
            Vector3(r.randf_range(-1, 1), size * 0.5, r.randf_range(-1, 1)),
            _tint(CAVE_DARK, r),
            false,
            1.0,
            6,
            4
        )


static func _crystals(p: Node3D, r: RandomNumberGenerator) -> void:
    var color: Color = [Color("6ad8f0"), Color("b06af0"), Color("6af0b0")][r.randi() % 3]
    for k in range(r.randi_range(3, 6)):
        var shard := Flat.limb(
            p,
            0.01,
            0.07,
            r.randf_range(0.3, 0.7),
            Vector3(r.randf_range(-0.3, 0.3), 0.2, r.randf_range(-0.3, 0.3)),
            color,
            false,
            5
        )
        shard.rotation = Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
        shard.material_override = _glowing(color)


static func _crystal_cluster(p: Node3D, r: RandomNumberGenerator) -> void:
    _crystals(p, r)
    p.scale = Vector3.ONE * 2.5
    var light := OmniLight3D.new()
    light.position = Vector3(0, 0.6, 0)
    light.light_color = Color("8ad8ff")
    light.omni_range = 4.0
    light.light_energy = 1.2
    p.add_child(light)


static func _torch(p: Node3D, _r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # A torch on a pole, its flame glowing, lighting the cave around it.
    Flat.limb(p, 0.04, 0.05, 1.8, Vector3(0, 0.9, 0), Color("6a4a2a"), false, 5)
    var flame := Flat.limb(p, 0.01, 0.12, 0.35, Vector3(0, 1.95, 0), FIRE, false, 6)
    flame.material_override = _glowing(FIRE)
    var light := OmniLight3D.new()
    light.position = Vector3(0, 2.1, 0)
    light.light_color = Color("ffb060")
    light.omni_range = 6.0
    light.light_energy = 1.8
    p.add_child(light)


static func _painting(p: Node3D, r: RandomNumberGenerator) -> void:
    # NOTE (mristin):
    # A slab of the wall with paintings on it: hands, a mammoth, a hunter.
    var slab := Flat.box(p, Vector3(0.4, 2.8, 3.0), Vector3(0, 1.4, 0), CAVE_ROCK)
    slab.rotation.y = 0.0
    var ochre := Color("c06a3a")
    for k in range(3):
        Flat.box(p, Vector3(0.03, 0.18, 0.14), Vector3(-0.21, 1.9, -1.0 + k * 0.3), ochre)
    Flat.ball(p, 0.3, Vector3(-0.22, 1.3, 0.4), Color("7a3a2a"), false, 1.0, 6, 4).scale = Vector3(
        0.1, 0.8, 1.3
    )
    for z in [0.15, 0.65]:
        Flat.box(p, Vector3(0.03, 0.35, 0.05), Vector3(-0.22, 0.95, z), Color("7a3a2a"))
    Flat.box(
        p,
        Vector3(0.03, 0.4, 0.04),
        Vector3(-0.22, 1.2, -0.5 + r.randf_range(-0.1, 0.1)),
        Color("2a2a2a")
    )


static func _bats(p: Node3D, r: RandomNumberGenerator) -> void:
    for k in range(r.randi_range(2, 5)):
        var at := Vector3(r.randf_range(-1, 1), r.randf_range(4.5, 5.6), r.randf_range(-1, 1))
        Flat.ball(p, 0.08, at, Color("1a1416"), false, 1.4, 6, 4)
        for side in [-1.0, 1.0]:
            var wing := Flat.box(
                p, Vector3(0.22, 0.02, 0.12), at + Vector3(side * 0.13, 0.03, 0), Color("1a1416")
            )
            wing.rotation.z = side * 0.4


static func _puddle(p: Node3D, r: RandomNumberGenerator) -> void:
    var water := Flat.limb(
        p, r.randf_range(0.3, 0.6), 0.5, 0.02, Vector3(0, 0.01, 0), Color("2a3a4a"), false, 9
    )
    water.scale = Vector3(1.4, 1, 1)


static func _cave_wall(p: Node3D, r: RandomNumberGenerator) -> void:
    var wall := Flat.box(
        p, Vector3(4.0, 8.0, r.randf_range(6, 10)), Vector3(0, 4.0, 0), _tint(CAVE_DARK, r)
    )
    wall.rotation = Vector3(0, r.randf_range(-0.2, 0.2), r.randf_range(-0.08, 0.08))


## A material which glows (crystals, flames).
static func _glowing(color: Color) -> StandardMaterial3D:
    var glow := StandardMaterial3D.new()
    glow.albedo_color = color
    glow.emission_enabled = true
    glow.emission = color
    glow.emission_energy_multiplier = 1.5
    return glow
