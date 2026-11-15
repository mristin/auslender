class_name Fight
extends Node3D

## Box against the Rochartis scientist in the ring, to the beat: the rhythm
## fight (see DESIGN.md).
##
## A song plays (synthesized, see RhythmCore), and its chart sends notes at
## the player along lanes (see RhythmNote): each arrives on a beat, and he
## meets it then. A ring asks for a punch (the move and the hand on it, with
## an arrow: a jab straight at him, a hook from the side, an uppercut up); an
## attack of the scientist asks for a dodge (cover, slip, duck or jump), and
## the scientist winds up and strikes on that beat. The notes show
## two seconds ahead, so that the player always knows what comes, and when.
##
## The camera and the move classifier see a move a while after the player made
## it. So the fight judges a move at the time it was seen, less that latency,
## which it learns from the player's own hits (the keyboard has none); and a
## dodge counts if the player was in it around the beat. It is forgiving in
## time, not in the move: the right move on its beat is PERFECT, and from the
## moment its note shows until a little after its beat GOOD; a wrong move
## (another punch, the other hand, another dodge) does not count. A note not
## met is a MISS; a missed attack hurts the player.
##
## The hits fill the score, times the combo of notes met in a row; and they
## drain the scientist's health, so that the player knocks him out in the
## final section if he met most of the notes. The song has sections, harder
## one after the other (see Chart): straights, hooks, dodges, uppercuts and
## jumps, combos, and the final round; the last bar of each is a breather.
## There are no kicks: the vision saw them too late and too seldom.
##
## A panel in the upper left (see [CameraPanel]) shows the player how the game
## sees him: the camera picture, his body pose as a wire, and on top the
## command which his body gives now. The fight pauses while the camera does
## not see the player. Every fight writes a log (see [FightLog]).
##
## Start it with [code]-- --replay=<recording.jsonl>[/code] to play a recorded
## video instead of the camera (see dev/replay/).
##
## The keyboard plays without the camera, too:
## [codeblock]
## J, K                       jab left, right
## U, I                       hook left, right
## H, L                       uppercut left, right
## Q, E (hold)                slip left, right
## Z (hold)                   duck
## B (hold)                   cover the head
## X or Space                 jump
## C                          set the home spot again
## R                          fight again
## F1                         hide or show the camera panel
## F3                         the next look of the hero
## Escape                     quit
## [/codeblock]

## The phases of the fight.
enum Phase { WAITING, PLAYING, OVER }

## The tempo of the song.
const BPM := 90.0

## How long a note shows before its beat, in seconds, and how fast it flies
## (meters per second).
const LEAD := 2.0
const SPEED := 3.3

## Where the player stands, and the scientist in front of him.
const SPOT := Vector3(0, 0, 1.5)
const OPPONENT_DISTANCE := 2.0

## How far ahead of the player the notes arrive (most of them), in meters.
const HIT_AHEAD := 0.75

## Where each note arrives, from the player's eyes on the floor (x to his
## right, y up from the floor, z ahead): the left hand's are mirrored.
const ARRIVE := {
    "straight": Vector3(0.2, 1.45, HIT_AHEAD),
    "hook": Vector3(0.45, 1.5, HIT_AHEAD),
    "uppercut": Vector3(0.18, 1.15, HIT_AHEAD),
    "cover": Vector3(0.0, 1.55, HIT_AHEAD),
    "slip_left": Vector3(0.4, 1.55, HIT_AHEAD),
    "slip_right": Vector3(-0.4, 1.55, HIT_AHEAD),
    "duck": Vector3(0.0, 1.62, HIT_AHEAD),
    "jump": Vector3(0.0, 0.6, 1.3),
}

## How far off its beat a move may be, in seconds: PERFECT, and GOOD (late;
## early, any strike after its note shows is GOOD).
const PERFECT := 0.2
const GOOD := 0.5

## How long after its beat a move is seen at first, in seconds, before the
## fight learned it from the player's moves; and the range of it. It is the
## latency of the vision and the player's own habit together: in a play-test,
## a player struck 0.36 s early, so it may be negative.
const LATENCY_START := 0.15
const LATENCY_LEAST := -0.4
const LATENCY_MOST := 0.6

## A move this close to a note (in seconds), but not close enough to meet it,
## still teaches the latency, and tells the player whether he was early or
## late.
const NEAR := 1.0

## A dodge counts if the player was in it from the moment its note shows
## (it counts at once) until this long after its beat (plus the latency of
## the vision), in seconds: in the first play-test, the slips came up to
## 0.6 s after the beat.
const DODGE_LATE := 0.7

## His attack for each dodge, and the dodges which count against it: only the
## one asked for (the player wanted no wrong moves to count).
const ATTACK_OF := {
    "cover": "jab",
    "slip_right": "hook_left",
    "slip_left": "hook_right",
    "duck": "haymaker",
    "jump": "sweep",
}
const DODGES := {
    "cover": ["cover"],
    "slip_left": ["slip_left"],
    "slip_right": ["slip_right"],
    "duck": ["duck"],
    "jump": ["jump"],
}

## The call and its direction on the screen, for each dodge (see Hud).
const CALLS := {
    "cover": ["COVER!", "front"],
    "slip_left": ["SLIP LEFT!", "right"],
    "slip_right": ["SLIP RIGHT!", "left"],
    "duck": ["DUCK!", "front"],
    "jump": ["JUMP!", "low"],
}

## The points of each judgement, before the combo's multiplier; the combo
## raises the multiplier by one every this many notes, up to the most.
const POINTS := {"perfect": 100, "good": 50, "dodged": 100}
const COMBO_STEP := 8
const MULTIPLIER_MOST := 4

## How hard a GOOD hits, against a PERFECT.
const GOOD_SHARE := 0.85

## The share of the punches which the player needs to meet to knock him out,
## and his health before the final section (he holds on until then).
const KNOCK_OUT_SHARE := 0.75
const HOLDS_ON := 8.0

## How much a missed attack hurts the player.
const HURT := 8.0

## A lean this far (in units, about the shoulder width) is a slip, as
## LeanGauge.SlipFrom.
const SLIP_FROM := 0.5

## With the move classifier, a duck, a slip or a jump counts this long after
## it was found, in seconds: the classifier finds the move, not how long he
## holds it.
const DUCK_HOLD := 0.7
const SLIP_HOLD := 0.6
const JUMP_HOLD := 0.5

## How long the camera may lose the player before the fight pauses, in seconds.
const PAUSE_AFTER := 1.0

## How long a strike shows as the command of the body, in seconds.
const STRIKE_SHOWS := 0.8

## How often the log writes the state of the fight, in seconds.
const LOG_EVERY := 1.0

## The scientist's lines as each section starts (satire of a pharma giant).
const TAUNTS := [
    "Time for your check-up!",
    "This won't hurt. Much.",
    "Side effects may include bruising.",
    "Take your medicine!",
    "Billed to your insurance!",
    "The trial is not over!",
]

## His lines when the player misses, and when his attack lands.
const MISSED_LINES := ["Missed me!", "Too slow!", "Is that all?", "Ha! Placebo punch!"]
const LANDED_LINES := ["Billed to your insurance!", "Side effects!", "Next patient!"]

## He says a line at most this often, in seconds.
const QUIP_EVERY := 4.0

const _KEYS_PUNCH := {
    KEY_J: ["straight", "left"],
    KEY_K: ["straight", "right"],
    KEY_U: ["hook", "left"],
    KEY_I: ["hook", "right"],
    KEY_H: ["uppercut", "left"],
    KEY_L: ["uppercut", "right"],
}

const _HELP := (
    "Keys: J K jab, U I hook, H L uppercut, Q E slip, Z duck, B cover, X jump,"
    + " R again, F1 camera, F3 hero"
)

var vision: Node = null

var boxer: Boxer
var scientist: Scientist
var hud: Hud
var panel: CameraPanel

var _core: RefCounted
var _phase := Phase.WAITING
var _wait_left := 0.0
var _paused := false
var _unseen := 0.0
## The song's time now, in seconds, and how long the song is.
var _now := 0.0
var _length := 0.0
var _beat_seconds := 60.0 / BPM
var _intro_bars := 4
var _music: AudioStreamPlayer
var _sounds := {}
var _chart: Array = []
var _next := 0
var _notes: Array[RhythmNote] = []
var _punches := 0
var _latency := LATENCY_START
var _offsets: Array[float] = []
var _last_beat := -1
## The last song time at which the player was in each dodge, and the time of
## the last dodge which counted (no dodge counts twice).
var _in_pose := {}
var _dodge_used := -100.0
var _score := 0
var _combo := 0
var _best_combo := 0
var _counts := {"perfect": 0, "good": 0, "dodged": 0, "miss": 0, "hit": 0}
var _seed := 1

var _time := 0.0
var _keyboard_jump_left := 0.0
var _last_jump_at := -10.0
var _last_duck_at := -10.0
var _last_slip_at := {"left": -10.0, "right": -10.0}
var _last_strike := ""
var _last_strike_at := -10.0
var _slow_until := 0
var _log := FightLog.new()
var _logged_at := -10.0
var _logged_pose := ""
var _tunnel: BeatTunnel
var _quipped_at := -100.0


func _ready() -> void:
    add_child(Arena.new())

    scientist = Scientist.new()
    add_child(scientist)
    scientist.global_position = SPOT + Vector3(0, 0, -OPPONENT_DISTANCE)
    scientist.target = SPOT

    boxer = Boxer.new()
    add_child(boxer)
    boxer.global_position = SPOT

    var layer := CanvasLayer.new()
    layer.layer = 2
    add_child(layer)
    panel = CameraPanel.new()
    layer.add_child(panel)
    # NOTE (mristin):
    # In the upper left, under the health bar: the lower corners are where his
    # arms swing and his knees come up.
    panel.position = Vector2(24, 140)
    hud = Hud.new()
    add_child(hud)
    hud.help = _HELP

    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        vision = holder.service
        panel.setup(vision)
        if not vision.IsReplaying():
            vision.ResetPlayer()

    _core = (load("res://scenes/fight/RhythmCore.cs") as Script).new()
    _intro_bars = _core.IntroBars()
    _music = AudioStreamPlayer.new()
    _music.stream = _wav(_core.Song(BPM, 1))
    add_child(_music)
    for name in ["hit", "perfect", "miss", "dodge", "hurt", "bell", "count"]:
        var player := AudioStreamPlayer.new()
        player.stream = _wav(_core.Sound(name))
        player.volume_db = -4.0
        add_child(player)
        _sounds[name] = player
    var levels: PackedInt32Array = _core.Levels()
    _length = levels.size() * 4.0 * _beat_seconds
    _tunnel = BeatTunnel.new()
    _tunnel.setup(SPOT + Vector3(0, 1.35, -HIT_AHEAD), LEAD, SPEED, _beat_seconds)
    add_child(_tunnel)

    _log.write("scene", {"input": _input_source(), "hero": RiggedFigure.chosen, "bpm": BPM})
    if _log.path != "":
        print("Fight log: ", ProjectSettings.globalize_path(_log.path))
    _start()


## Start the fight: wait for the player, then play the song from the start.
func _start() -> void:
    for note in _notes:
        note.queue_free()
    _notes.clear()
    _chart = _core.Notes(_seed)
    _seed += 1
    _punches = _chart.filter(func(n: Dictionary) -> bool: return n["side"] != "").size()
    _next = 0
    _now = 0.0
    _last_beat = -1
    _score = 0
    _combo = 0
    _best_combo = 0
    for key in _counts:
        _counts[key] = 0
    _in_pose.clear()
    _dodge_used = -100.0
    _music.stop()
    scientist.reset()
    boxer.reset()
    _phase = Phase.WAITING
    _wait_left = 1.5
    _paused = false
    Engine.time_scale = 1.0
    hud.banner = ""
    hud.results = []
    _log.write("fight_start", {"notes": _chart.size(), "punches": _punches})


func _process(delta: float) -> void:
    if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _slow_until:
        Engine.time_scale = 1.0
    _time += delta
    _keyboard_jump_left = maxf(0.0, _keyboard_jump_left - delta)

    var body := _read_body()
    var lean: float = body[0]
    var ducking: bool = body[1]
    var jumping: bool = body[2]
    var covering: bool = body[3]

    match _phase:
        Phase.WAITING:
            hud.banner = "GET READY"
            if _sees_player():
                _wait_left -= delta
            if _wait_left <= 0.0:
                _phase = Phase.PLAYING
                hud.banner = ""
                _music.play()
                _play("bell")
                _log.write("song_start")
        Phase.PLAYING:
            _run_song(delta)

    _remember_pose(lean, ducking, jumping, covering)
    boxer.lean = lerpf(boxer.lean, clampf(lean, -1.0, 1.0), minf(1.0, delta * 14.0))
    boxer.duck = lerpf(boxer.duck, 1.0 if ducking else 0.0, minf(1.0, delta * 12.0))
    boxer.jumping = jumping
    boxer.covering = covering
    boxer.face(scientist.global_position, delta)
    _tunnel.place(_now, _phase == Phase.PLAYING)
    _update_hud(lean, ducking, jumping, covering)
    _log_state(lean, ducking, jumping, covering)


## Read the player's body: the moves of the vision (or the keys), and his
## dodges now: [lean, ducking, jumping, covering].
func _read_body() -> Array:
    var lean := 0.0
    if Input.is_key_pressed(KEY_Q):
        lean -= 0.8
    if Input.is_key_pressed(KEY_E):
        lean += 0.8
    var ducking := Input.is_key_pressed(KEY_Z)
    var covering := Input.is_key_pressed(KEY_B)
    var jumping := _keyboard_jump_left > 0.0

    if vision != null:
        for move in vision.PollMoves():
            match move["kind"]:
                "jump":
                    _last_jump_at = _time
                "duck":
                    _last_duck_at = _time
                "slip":
                    _last_slip_at[move["side"]] = _time
                "kick":
                    # NOTE (mristin):
                    # The fight has no kicks: the vision saw them too late
                    # and too seldom (see DESIGN.md).
                    _log.write("move", {"kind": "kick", "side": move["side"], "ignored": true})
                _:
                    throw(move["kind"], move["side"], "vision")
            if move["kind"] in ["jump", "duck", "slip"]:
                _log.write(
                    "dodge_move", {"kind": move["kind"], "side": move.get("side", ""), "song": _now}
                )
        if lean == 0.0:
            # NOTE (mristin):
            # The lean against where the player stood lately (see
            # LeanGauge), in units, positive to his right.
            lean = vision.GetLean()
        # NOTE (mristin):
        # The classifier finds the slips, the ducks and the jumps from the
        # whole body, and the cover; the head alone is fooled by where the
        # camera stands (e.g., on the floor).
        if _time - _last_slip_at["left"] <= SLIP_HOLD:
            lean = minf(lean, -0.8)
        elif _time - _last_slip_at["right"] <= SLIP_HOLD:
            lean = maxf(lean, 0.8)
        ducking = ducking or _time - _last_duck_at <= DUCK_HOLD
        covering = covering or vision.IsCovering()
    jumping = jumping or _time - _last_jump_at <= JUMP_HOLD
    return [lean, ducking, jumping, covering]


## Whether the camera sees the player (always, without the camera).
func _sees_player() -> bool:
    if vision == null or vision.GetStatus() == "Disabled":
        return true
    return vision.HasPlayer()


## Play the song on: its clock, the notes, the judging, the opponent.
func _run_song(delta: float) -> void:
    # NOTE (mristin):
    # Pause while the camera does not see the player.
    _unseen = 0.0 if _sees_player() else _unseen + delta
    var pause := _unseen > PAUSE_AFTER
    if pause != _paused:
        _paused = pause
        _music.stream_paused = pause
        hud.banner = "PAUSED" if pause else ""
        _log.write("pause" if pause else "resume", {"song": _now})
    if _paused:
        return

    _now += delta
    if _music.playing:
        # NOTE (mristin):
        # Follow the music: where it plays now, as heard.
        var heard := (
            _music.get_playback_position()
            + AudioServer.get_time_since_last_mix()
            - AudioServer.get_output_latency()
        )
        if absf(heard - _now) > 0.1:
            _now = heard
        else:
            _now = lerpf(_now, heard, 0.1)

    _on_beats()
    while _next < _chart.size() and _beat_time(_chart[_next]) - _now <= LEAD:
        _spawn(_chart[_next])
        _next += 1

    var attack := ""
    var attack_seconds := 0.0
    for note in _notes.duplicate():
        note.place(_now)
        if note.result == "":
            if note.side == "":
                if attack == "" and absf(_now - note.at) <= 0.7:
                    attack = ATTACK_OF[note.kind]
                    attack_seconds = _now - note.at
                _judge_dodge(note, _now >= note.at + _latency + DODGE_LATE)
            elif _now > note.at + GOOD + _latency:
                _miss(note)
        if note.is_done(_now):
            _notes.erase(note)
            note.queue_free()
        if _phase == Phase.OVER:
            return
    scientist.perform(attack, attack_seconds)
    var bar_float := _now / (_beat_seconds * 4.0)
    scientist.groove(fposmod(_now / _beat_seconds, 1.0), fposmod(bar_float, 1.0), floori(bar_float))
    # NOTE (mristin):
    # He shows off in the count-in and the breathers (the bars without notes
    # ahead).
    var quiet := true
    for note in _notes:
        if note.result == "" and note.at - _now < _beat_seconds * 4.0:
            quiet = false
            break
    scientist.show_off(quiet and attack == "")

    if _now >= _length:
        _finish(scientist.health <= 0.0)


## Things which happen on the beats: the count-in, the sections' titles, and
## the scientist's lines.
func _on_beats() -> void:
    var beat := floori(_now / _beat_seconds)
    if beat == _last_beat:
        return
    _last_beat = beat
    var bar := beat / 4
    var in_bar := beat % 4
    if bar == _intro_bars - 1:
        var counts := ["3", "2", "1", "BOX!"]
        hud.say(counts[in_bar], Hud.GOLD)
        _play("count" if in_bar < 3 else "bell")
    # NOTE (mristin):
    # Each section is announced a bar ahead.
    var coming: int = _core.SectionOf(bar + 1)
    if in_bar == 0 and coming >= 0 and coming != _core.SectionOf(bar):
        var titles: PackedStringArray = _core.Sections()
        hud.announce(titles[coming], 2.0)
        hud.taunt(TAUNTS[coming % TAUNTS.size()])
        _log.write("section", {"section": coming, "title": titles[coming], "song": _now})


## The song time of a note's beat.
func _beat_time(note: Dictionary) -> float:
    return float(note["beat"]) * _beat_seconds


func _spawn(entry: Dictionary) -> void:
    var kind: String = entry["kind"]
    var side: String = entry["side"]
    var offset: Vector3 = ARRIVE[kind]
    var x := -offset.x if side == "left" else offset.x
    var arrive := SPOT + Vector3(x, offset.y, -offset.z)
    var note := RhythmNote.new()
    add_child(note)
    note.setup(kind, side, _beat_time(entry), arrive, SPEED)
    note.place(_now)
    _notes.append(note)


## Throw a punch of the player ("straight", "hook" or "uppercut";
## "left" or "right"), as the vision or the keyboard ([param source]) found it,
## and meet the note which it fits.
func throw(kind: String, side: String, source := "vision") -> void:
    var hand := 0 if side == "left" else 1
    _last_strike = "%s %s" % [side.to_upper(), _name(kind).to_upper()]
    _last_strike_at = _time
    boxer.punch(hand, kind)
    if _phase != Phase.PLAYING or _paused:
        return

    var latency := _latency if source == "vision" else 0.0
    var when := _now - latency
    var best: RhythmNote = null
    var best_rank := INF
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
        if note.at < best_rank:
            best_rank = note.at
            best = note
    var entry := {"kind": kind, "side": side, "source": source, "song": _now, "latency": latency}
    if best == null and wrong != null:
        # NOTE (mristin):
        # A wrong move does not count: tell him which move was wanted.
        entry["matched"] = false
        entry["wanted"] = "%s %s" % [wrong.kind, wrong.side]
        _log.write("move", entry)
        hud.say(
            "WRONG: %s %s" % [wrong.side.to_upper(), RhythmNote.LABELS[wrong.kind]], Color("ff8a65")
        )
        _play("miss")
        return
    if best == null:
        entry["matched"] = false
        # NOTE (mristin):
        # Near a note, tell him whether he was early or late, and learn from
        # it how he times his moves.
        var near: RhythmNote = null
        for note in _notes:
            if note.result == "" and note.side != "":
                if near == null or absf(when - note.at) < absf(when - near.at):
                    near = note
        if near != null and absf(when - near.at) <= NEAR:
            entry["near"] = when - near.at
            hud.say("EARLY" if when < near.at else "LATE", Color(Hud.PAPER, 0.8))
            if source == "vision":
                _learn_latency(_now - near.at)
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
    # NOTE (mristin):
    # A GOOD hits nearly as hard: striking early is allowed.
    var strength := 1.0 if how == "perfect" else GOOD_SHARE
    var damage := strength * 100.0 / maxf(1.0, KNOCK_OUT_SHARE * _punches)
    var final_section: bool = (
        _core.SectionOf(floori(best.at / _beat_seconds) / 4) == _core.Sections().size() - 1
    )
    if not final_section:
        damage = minf(damage, maxf(0.0, scientist.health - HOLDS_ON))
    scientist.flinch(best.kind, best.side, strength, damage)
    if scientist.health <= 0.0:
        _finish(true)


## Learn the latency from the player's moves near the notes: the median of
## the last ones (the time a move was seen after its beat).
func _learn_latency(seen_after: float) -> void:
    _offsets.append(seen_after)
    if _offsets.size() > 12:
        _offsets.pop_front()
    if _offsets.size() < 3:
        return
    var sorted := _offsets.duplicate()
    sorted.sort()
    _latency = clampf(sorted[sorted.size() / 2], LATENCY_LEAST, LATENCY_MOST)


## A note was met (struck or dodged): its points, the combo and the sound.
func _met(note: RhythmNote, how: String) -> void:
    note.judge(how, _now)
    _counts[how] += 1
    _combo += 1
    _best_combo = maxi(_best_combo, _combo)
    _score += POINTS[how] * _multiplier()
    var texts := {"perfect": "PERFECT!", "good": "GOOD", "dodged": "DODGED!"}
    hud.say(texts[how], Hud.GOLD if how == "perfect" else Hud.GREEN)
    match how:
        "perfect":
            _play("perfect")
            _play("hit")
        "good":
            _play("hit")
        "dodged":
            _play("dodge")


## Say one of the lines now and then.
func _quip(lines: Array) -> void:
    if _time - _quipped_at < QUIP_EVERY or randf() > 0.6:
        return
    _quipped_at = _time
    hud.taunt(lines[randi() % lines.size()])


func _multiplier() -> int:
    return mini(MULTIPLIER_MOST, 1 + _combo / COMBO_STEP)


func _miss(note: RhythmNote) -> void:
    note.judge("miss", _now)
    _counts["miss"] += 1
    _combo = 0
    hud.say("MISS", Color(Hud.PAPER, 0.7))
    _play("miss")
    scientist.evade(note.side)
    _quip(MISSED_LINES)
    _log.write("note", {"kind": note.kind, "side": note.side, "beat": note.at, "result": "miss"})


## Judge a dodge: did the player dodge the attack since its note showed? It
## counts as soon as he does; at the [param last] chance, it hits him if not.
func _judge_dodge(note: RhythmNote, last: bool) -> void:
    var since := note.at - LEAD
    var how := ""
    var used := 0.0
    for pose in DODGES[note.kind]:
        var seen := float(_in_pose.get(pose, -100.0))
        if seen >= since and seen > _dodge_used:
            how = pose
            used = seen
            break
    if how == "" and not last:
        return
    (
        _log
        . write(
            "note",
            {
                "kind": note.kind,
                "beat": note.at,
                "result": "dodged" if how != "" else "hit",
                "by": how,
                "poses": _in_pose.duplicate(),
            }
        )
    )
    if how != "":
        _dodge_used = used
        scientist.stumble()
        _met(note, "dodged")
        return
    note.judge("miss", _now)
    _counts["hit"] += 1
    _combo = 0
    boxer.take_damage(HURT)
    scientist.cheer()
    _quip(LANDED_LINES)
    hud.say("OUCH!", Hud.RED)
    _play("hurt")
    if boxer.health <= 0.0:
        _finish(false)


## Remember when the player was in each dodge last.
func _remember_pose(lean: float, ducking: bool, jumping: bool, covering: bool) -> void:
    if _phase != Phase.PLAYING:
        return
    if lean <= -SLIP_FROM:
        _in_pose["slip_left"] = _now
    if lean >= SLIP_FROM:
        _in_pose["slip_right"] = _now
    if ducking:
        _in_pose["duck"] = _now
    if jumping:
        _in_pose["jump"] = _now
    if covering:
        _in_pose["cover"] = _now


## End the fight: [param knocked_out] if the player knocked him out (else
## the song ended, or the player went down).
func _finish(knocked_out: bool) -> void:
    if _phase == Phase.OVER:
        return
    _phase = Phase.OVER
    _music.stop()
    _play("bell")
    hud.warning = ""
    var total := 0
    for key in _counts:
        total += _counts[key]
    var accuracy: float = (
        (_counts["perfect"] + 0.75 * _counts["good"] + _counts["dodged"]) / maxf(1.0, total)
    )
    var grade := "D"
    for step in [[0.95, "S"], [0.85, "A"], [0.7, "B"], [0.5, "C"]]:
        if accuracy >= step[0]:
            grade = step[1]
            break
    var why := "time"
    if knocked_out:
        why = "knock_out"
        scientist.knock_out()
        hud.banner = "K.O.!"
        Engine.time_scale = 0.3
        _slow_until = Time.get_ticks_msec() + 1200
    elif boxer.health <= 0.0:
        why = "down"
        hud.banner = "DOWN!"
    else:
        hud.banner = "TIME!"
    hud.results = [
        "SCORE %d   GRADE %s" % [_score, grade],
        (
            "%d%%   PERFECT %d   GOOD %d   DODGED %d   MISSED %d   HIT %d"
            % [
                roundi(accuracy * 100.0),
                _counts["perfect"],
                _counts["good"],
                _counts["dodged"],
                _counts["miss"],
                _counts["hit"],
            ]
        ),
        "BEST COMBO %d    R: AGAIN" % _best_combo,
    ]
    (
        _log
        . write(
            "fight_end",
            {
                "why": why,
                "song": _now,
                "score": _score,
                "grade": grade,
                "accuracy": accuracy,
                "counts": _counts.duplicate(),
                "best_combo": _best_combo,
                "latency": _latency,
                "health": boxer.health,
                "his_health": scientist.health,
            }
        )
    )


func _play(sound: String) -> void:
    (_sounds[sound] as AudioStreamPlayer).play()


func _name(kind: String) -> String:
    return "jab" if kind == "straight" else kind


## A stream of 16-bit mono samples (see RhythmCore).
func _wav(samples: PackedByteArray) -> AudioStreamWAV:
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = _core.SampleRate()
    stream.stereo = false
    stream.data = samples
    return stream


func _update_hud(lean: float, ducking: bool, jumping: bool, covering: bool) -> void:
    hud.player_health = boxer.health / Boxer.MAX_HEALTH
    hud.opponent_health = scientist.health / Scientist.MAX_HEALTH
    hud.hurt = boxer.hurt()
    hud.score = _score
    hud.combo = _combo
    hud.multiplier = _multiplier()
    hud.progress = clampf(_now / maxf(_length, 1.0), 0.0, 1.0)

    # NOTE (mristin):
    # The call of the next attack, in its last beat and a half.
    var call := ""
    var call_from := ""
    var call_progress := 0.0
    if _phase == Phase.PLAYING:
        for note in _notes:
            if note.side != "" or note.result != "":
                continue
            var left := note.at - _now
            if left <= _beat_seconds * 1.5 and left > -0.1:
                call = CALLS[note.kind][0]
                call_from = CALLS[note.kind][1]
                call_progress = clampf(1.0 - left / (_beat_seconds * 1.5), 0.0, 1.0)
            break
    hud.warning = call
    hud.warning_from = call_from
    hud.warning_progress = call_progress

    # NOTE (mristin):
    # The command of the body: a strike for a moment, else the dodge which
    # counts, else "READY".
    var dodge := _pose(lean, ducking, jumping, covering)
    panel.threatened = call != ""
    panel.dodging = dodge != ""
    if _time - _last_strike_at <= STRIKE_SHOWS:
        panel.command = _last_strike
        panel.command_color = Hud.GOLD
    elif dodge != "":
        panel.command = dodge
        panel.command_color = Color("6ccf5e")
    else:
        panel.command = "READY"
        panel.command_color = Color(0.75, 0.77, 0.82)

    if vision == null:
        hud.sees_player = true
        return
    var camera_on: bool = vision.GetStatus() != "Disabled"
    hud.sees_player = vision.HasPlayer() or not camera_on
    if camera_on and not vision.HasPlayer():
        panel.command = "STEP IN FRONT"
        panel.command_color = Color("ff5a4f")
    panel.calibrated = vision.IsCalibrated() or not camera_on
    panel.calibration_progress = vision.GetCalibrationProgress()
    hud.replay = vision.GetReplayTime() if vision.IsReplaying() else Vector2(-1, -1)
    hud.sees_feet = vision.SeesFeet() or not camera_on
    hud.status = VisionStatus.new().text(vision, true)


## The dodge which counts now, by its name ("" if none).
func _pose(lean: float, ducking: bool, jumping: bool, covering: bool) -> String:
    if jumping:
        return "JUMP"
    if ducking:
        return "DUCK"
    if covering:
        return "COVER"
    if lean <= -SLIP_FROM:
        return "SLIP LEFT"
    if lean >= SLIP_FROM:
        return "SLIP RIGHT"
    return ""


## Log the state of the fight now and then, and every change of the pose.
func _log_state(lean: float, ducking: bool, jumping: bool, covering: bool) -> void:
    var pose := _pose(lean, ducking, jumping, covering)
    if pose != _logged_pose:
        _log.write("pose", {"pose": pose, "was": _logged_pose, "song": _now})
        _logged_pose = pose
    if _time - _logged_at < LOG_EVERY:
        return
    _logged_at = _time
    var fields := {
        "phase": Phase.keys()[_phase],
        "paused": _paused,
        "song": _now,
        "health": boxer.health,
        "his_health": scientist.health,
        "score": _score,
        "combo": _combo,
        "latency": _latency,
        "lean": lean,
        "pose": pose,
    }
    if vision != null and vision.GetStatus() != "Disabled":
        fields["sees_player"] = vision.HasPlayer()
    _log.write("state", fields)


func _input_source() -> String:
    if vision != null and vision.IsReplaying():
        return "replay"
    if vision != null and vision.GetStatus() != "Disabled":
        return "camera"
    return "keyboard"


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key := event as InputEventKey
    if not key.pressed or key.echo:
        return
    if _KEYS_PUNCH.has(key.keycode):
        var move: Array = _KEYS_PUNCH[key.keycode]
        throw(move[0], move[1], "keyboard")
    match key.keycode:
        KEY_X, KEY_SPACE:
            _keyboard_jump_left = 0.5
            _last_jump_at = _time
        KEY_C:
            if vision != null:
                vision.Recalibrate()
        KEY_R:
            if _phase != Phase.OVER:
                _log.write("fight_end", {"why": "restarted", "song": _now, "score": _score})
            _start()
        KEY_F1:
            panel.visible = not panel.visible
        KEY_F3:
            RiggedFigure.chosen = RiggedFigure.next_hero()
            panel.rebuild_figure()
            hud.say(RiggedFigure.chosen.to_upper(), Hud.GOLD)
        KEY_ESCAPE:
            get_tree().quit()
