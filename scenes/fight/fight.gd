class_name Fight
extends RhythmLevel

## A fight against an opponent of the world (see RhythmLevel and Levels): the
## player boxes him to the beat of the song.
##
## A ring asks for a punch (the move and the hand on it, with an arrow: a jab
## straight ahead, a hook from the side, an uppercut up); an attack of the
## opponent asks for a dodge (the cover, or a slip), and he winds up and
## strikes on its beat (see Opponent). A fight has no jumps and no ducks: they
## are the runs'. The punches drain his health, so that the player knocks him
## out in the final section if he met most of the notes. A frame on every beat
## rolls towards the player (see BeatTunnel).

## How far the opponent stands in front of the player, in meters.
const OPPONENT_DISTANCE := 2.0

## A move this close to a note (in seconds), but not close enough to meet it,
## still teaches the latency, and tells the player whether he was late.
const NEAR := 1.0

## The opponent's attack for each dodge.
const ATTACK_OF := {
    "cover": "jab",
    "slip_right": "hook_left",
    "slip_left": "hook_right",
    "duck": "haymaker",
    "jump": "sweep",
}

## How hard a GOOD hits, against a PERFECT.
const GOOD_SHARE := 0.85

## The share of the punches which the player needs to meet to knock him out,
## and his health before the final section (he holds on until then).
const KNOCK_OUT_SHARE := 0.75
const HOLDS_ON := 8.0

## He counters a wrong move at most this often, in seconds; and a wrong
## dodge counts from this long before the attack's beat.
const COUNTER_EVERY := 0.6
const WRONG_DODGE_EARLY := 0.8

## The opponent says a line at most this often, in seconds.
const QUIP_EVERY := 4.0

var opponent: Opponent

var _punches := 0
var _tunnel: BeatTunnel
var _quipped_at := -100.0
var _black_sheep: Node3D
var _countered_at := -100.0


func _build() -> void:
    opponent = Opponent.new()
    opponent.look = level["opponent"]
    add_child(opponent)
    opponent.global_position = SPOT + Vector3(0, 0, -OPPONENT_DISTANCE)
    opponent.target = SPOT
    if level["id"] == "white_sheep":
        # NOTE (mristin):
        # The black sheep is in his corner, cheering him on (see DESIGN.md).
        _black_sheep = Looks.black_sheep()
        add_child(_black_sheep)
        _black_sheep.position = SPOT + Vector3(1.7, 0, -2.4)
        _black_sheep.rotation.y = 0.6
    hud.opponent_name = str(level["title"]).trim_prefix("THE ")
    _tunnel = BeatTunnel.new()
    _tunnel.setup(SPOT + Vector3(0, 1.35, -HIT_AHEAD), LEAD, SPEED, _beat_seconds)
    add_child(_tunnel)


func _help() -> String:
    return "Keys: J K jab, U I hook, H L uppercut, Q E slip, B cover, R again, Esc Esc leave"


func _on_start() -> void:
    _punches = _chart.filter(func(n: Dictionary) -> bool: return n["side"] != "").size()
    if opponent != null:
        opponent.reset()


func _on_frame(delta: float) -> void:
    boxer.face(opponent.global_position, delta)
    _tunnel.place(_now, _phase == Phase.PLAYING)
    if _black_sheep != null:
        _black_sheep.position.y = 0.12 * absf(sin(_time * PI / _beat_seconds))


## The opponent moves to the music, and shows his attack of the moment.
func _on_song(_played: float, attack: RhythmNote) -> void:
    if attack != null:
        opponent.perform(ATTACK_OF[attack.kind], _now - attack.at)
    else:
        opponent.perform("", 0.0)
    var bar_float := _now / (_beat_seconds * 4.0)
    opponent.groove(fposmod(_now / _beat_seconds, 1.0), fposmod(bar_float, 1.0), floori(bar_float))
    # NOTE (mristin):
    # He shows off in the count-in and the breathers (the bars without notes
    # ahead).
    var quiet := true
    for note in _notes:
        if note.result == "" and note.at - _now < _beat_seconds * 4.0:
            quiet = false
            break
    opponent.show_off(quiet and attack == null)


## Throw a punch of the player ("straight", "hook" or "uppercut"; "left" or
## "right"), as the vision or the keyboard ([param source]) found it, and
## meet the note which it fits.
func throw(kind: String, side: String, source := "vision") -> void:
    var hand := 0 if side == "left" else 1
    _last_strike = "%s %s" % [side.to_upper(), "JAB" if kind == "straight" else kind.to_upper()]
    _last_strike_at = _time
    boxer.punch(hand, kind)
    if _phase != Phase.PLAYING or _paused:
        return

    var latency := _latency if source == "vision" else 0.0
    var when := _now - latency
    var best: RhythmNote = null
    var wrong: RhythmNote = null
    for note in _notes:
        if note.result != "" or note.side == "":
            continue
        # NOTE (mristin):
        # To be forgiving, a strike meets a note from the moment it shows (a
        # player strikes as soon as he sees it) until a little after its beat;
        # but only the move and the hand on it do. The earliest note first.
        var off := when - note.at
        if off > GOOD or off < -LEAD:
            continue
        if note.kind != kind or note.side != side:
            if wrong == null or note.at < wrong.at:
                wrong = note
            continue
        if best == null or note.at < best.at:
            best = note
    var entry := {"kind": kind, "side": side, "source": source, "song": _now, "latency": latency}
    if best == null and wrong != null:
        # NOTE (mristin):
        # A wrong move does not count: tell him which move was wanted.
        entry["matched"] = false
        entry["wanted"] = "%s %s" % [wrong.kind, wrong.side]
        _log.write("move", entry)
        var wanted := "%s %s" % [wrong.side.to_upper(), RhythmNote.LABELS[wrong.kind]]
        _counter("WRONG: " + wanted)
        return
    if best == null:
        entry["matched"] = false
        _near_miss(when, source, entry)
        _log.write("move", entry)
        return
    var offset := when - best.at
    var how := "perfect" if absf(offset) <= PERFECT else "good"
    entry["matched"] = true
    entry["note"] = best.kind
    entry["offset"] = offset
    entry["result"] = how
    _log.write("move", entry)
    if source == "vision" and absf(offset) <= GOOD:
        _learn_latency(_now - best.at)
    _met(best, how)
    _hit_opponent(best, how)


## He made a wrong move: the opponent counters at once, and it hurts as an
## attack which he did not dodge (at most every COUNTER_EVERY seconds, so that
## a misread of the vision does not cost too much).
func _counter(text: String) -> void:
    hud.say(text, Color("ff8a65"))
    if _time - _countered_at < COUNTER_EVERY:
        _play("miss")
        return
    _countered_at = _time
    opponent.counter()
    _scoring.failed("hit")
    _play("hurt")
    boxer.take_damage(HURT)
    _quip("landed")
    _log.write("counter", {"why": text, "song": _now})
    if boxer.health <= 0.0:
        _finish(false)


## A wrong dodge (a slip the wrong way, or a slip for a jab, or the cover for a
## hook) close to an attack's beat: he counters, and the attack has landed.
func _judge_wrong_dodge(note: RhythmNote) -> bool:
    if _now < note.at - WRONG_DODGE_EARLY:
        return false
    # NOTE (mristin):
    # The right dodge, if he made it, counts.
    var right := float(_in_pose.get(note.kind, -100.0))
    if right >= note.at - LEAD and right > _dodge_used:
        return false
    for pose in ["slip_left", "slip_right", "cover"]:
        if pose == note.kind:
            continue
        var seen := float(_in_pose.get(pose, -100.0))
        if seen >= note.at - WRONG_DODGE_EARLY and seen > _dodge_used:
            _dodge_used = seen
            _log.write("note", {"kind": note.kind, "beat": note.at, "result": "wrong", "by": pose})
            _counter("WRONG: " + RhythmNote.LABELS[note.kind])
            note.judge("miss", _now)
            return true
    return false


## A dodge note: a wrong dodge is countered at once; else as any dodge.
func _judge(note: RhythmNote) -> bool:
    if note.side != "" or note.result != "":
        return false
    if _judge_wrong_dodge(note):
        return true
    return false


## A strike near a note which it missed: tell him he was late, and learn from
## it how he times his moves.
func _near_miss(when: float, source: String, entry: Dictionary) -> void:
    var near: RhythmNote = null
    for note in _notes:
        if note.result == "" and note.side != "":
            if near == null or absf(when - note.at) < absf(when - near.at):
                near = note
    if near != null and absf(when - near.at) <= NEAR:
        entry["near"] = when - near.at
        hud.say("LATE" if when > near.at else "EARLY", Color(Hud.PAPER, 0.8))
        if source == "vision":
            _learn_latency(_now - near.at)


## The punch landed on the opponent: he flinches and takes its damage.
func _hit_opponent(note: RhythmNote, how: String) -> void:
    # NOTE (mristin):
    # A GOOD hits nearly as hard: striking early is allowed.
    var strength := 1.0 if how == "perfect" else GOOD_SHARE
    var damage := strength * 100.0 / maxf(1.0, KNOCK_OUT_SHARE * _punches)
    var section: int = _core.SectionOf(floori(note.at / _beat_seconds) / 4, _sections.size())
    if section != _sections.size() - 1:
        damage = minf(damage, maxf(0.0, opponent.health - HOLDS_ON))
    opponent.flinch(note.kind, note.side, strength, damage)
    if opponent.health <= 0.0:
        _finish(true)


## Say one of the opponent's lines of the kind now and then.
func _quip(kind: String) -> void:
    var lines: Array = level["lines"].get(kind, [])
    if lines.is_empty() or _time - _quipped_at < QUIP_EVERY or randf() > 0.6:
        return
    _quipped_at = _time
    hud.taunt(lines[randi() % lines.size()])


func _on_missed(note: RhythmNote) -> void:
    opponent.evade(note.side)
    _quip("missed")


func _on_dodged(_note: RhythmNote) -> void:
    opponent.stumble()


func _on_hurt(_note: RhythmNote) -> void:
    opponent.cheer()
    _quip("landed")
    hud.say("OUCH!", Hud.RED)


func _knock_out() -> void:
    opponent.knock_out()
    hud.banner = "K.O.!"
    Engine.time_scale = 0.3
    _slow_until = Time.get_ticks_msec() + 1200


func _his_health() -> float:
    return opponent.health if opponent != null else -1.0
