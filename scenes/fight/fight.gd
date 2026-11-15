class_name Fight
extends Node3D

## A rhythm level (see DESIGN.md and Levels): a fight against an opponent of
## the world, or a run through its land.
##
## A song plays (synthesized, see RhythmCore), and its chart sends notes at
## the player (see RhythmNote): each arrives on a beat, and he meets it then.
## A ring asks for a punch (the move and the hand on it, with an arrow: a jab
## straight ahead, a hook from the side, an uppercut up); an attack of the
## opponent, or an obstacle of the run, asks for a dodge (cover, slip, duck or
## jump); in a run, obstacles block two of the three lanes, and the player
## steers into the free one with his body, as the penguin of Antarctic
## Adventure (see BodyReader). The notes show two seconds ahead, so that the
## player always knows what comes, and when.
##
## The camera and the move classifier see a move a while after the player made
## it. So the level judges a move at the time it was seen, less that latency,
## which it learns from the player's own moves. It is forgiving in time, not
## in the move: the right move on its beat is PERFECT, and from the moment its
## note shows until a little after its beat GOOD; a wrong move does not count.
## A note not met is a MISS; a missed attack, or an obstacle of a run which
## he did not jump, duck or steer around, costs him energy, and with none left
## he is down.
##
## In a fight, the punches drain the opponent's health, so that the player
## knocks him out in the final section if he met most of the notes. A level is
## won with a knock-out, or with a grade of C or better at the end of the song
## (see Scoring); winning opens the next level (see Profile).
##
## A panel in the upper left (see [CameraPanel]) shows the player how the game
## sees him. The level pauses while the camera does not see the player. Every
## level writes a log (see [FightLog]). Esc twice leaves the level.
##
## Start it with [code]-- --level=<id>[/code] to play a level directly, and
## with [code]-- --replay=<recording.jsonl>[/code] to play a recorded video
## instead of the camera (see dev/replay/).
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
## Left, Right (hold)         steer (in a run)
## C                          set the home spot again
## R                          play again
## F1                         hide or show the camera panel
## F3                         the next look of the hero
## Esc, Esc                   leave the level
## [/codeblock]

## The phases of a level.
enum Phase { WAITING, PLAYING, OVER }

## How long a note shows before its beat, in seconds, and how fast it flies
## (meters per second).
const LEAD := 2.0
const SPEED := 3.3

## Where the player stands, and the opponent in front of him.
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
    "lane_left": Vector3(0.0, 0.0, HIT_AHEAD),
    "lane_middle": Vector3(0.0, 0.0, HIT_AHEAD),
    "lane_right": Vector3(0.0, 0.0, HIT_AHEAD),
}

## How far off its beat a move may be, in seconds: PERFECT, and GOOD (late;
## early, any strike after its note shows is GOOD).
const PERFECT := 0.2
const GOOD := 0.5

## How long after its beat a move is seen at first, in seconds, before the
## level learned it from the player's moves; and the range of it. It is never
## negative: an early strike counts anyway, and a negative latency (learned
## from early strikes in the slow sections) made the late ones of the fast
## sections miss, in a play-test.
const LATENCY_START := 0.15
const LATENCY_LEAST := 0.0
const LATENCY_MOST := 0.6

## A move this close to a note (in seconds), but not close enough to meet it,
## still teaches the latency, and tells the player whether he was late.
const NEAR := 1.0

## A dodge counts from the moment its note shows until this long after its
## beat (plus the latency), in seconds: in the first play-test, the slips came
## up to 0.6 s after the beat.
const DODGE_LATE := 0.7

## The opponent's attack for each dodge.
const ATTACK_OF := {
    "cover": "jab",
    "slip_right": "hook_left",
    "slip_left": "hook_right",
    "duck": "haymaker",
    "jump": "sweep",
}

## The free lane of each steering note (-1 left, 0 the middle, 1 right).
const LANE_OF := {"lane_left": -1, "lane_middle": 0, "lane_right": 1}

## The call and its direction on the screen, for each dodge (see Hud).
const CALLS := {
    "cover": ["COVER!", "front"],
    "slip_left": ["SLIP LEFT!", "right"],
    "slip_right": ["SLIP RIGHT!", "left"],
    "duck": ["DUCK!", "front"],
    "jump": ["JUMP!", "low"],
    "lane_left": ["GO LEFT!", "right"],
    "lane_middle": ["MIDDLE!", "front"],
    "lane_right": ["GO RIGHT!", "left"],
}

## The color of the obstacles of a run, by its surroundings (the attacks of
## an opponent are purple).
const OBSTACLES := {
    "jungle": Color("8a5a2a"),
    "cave": Color("7a6a5a"),
    "city": Color("e8701a"),
    "suburbs": Color("c8302c"),
}

## How hard a GOOD hits, against a PERFECT.
const GOOD_SHARE := 0.85

## The share of the punches which the player needs to meet to knock him out,
## and his health before the final section (he holds on until then).
const KNOCK_OUT_SHARE := 0.75
const HOLDS_ON := 8.0

## How much a missed attack, or an obstacle of a run, costs the player.
const HURT := 8.0

## How long the camera may lose the player before the level pauses, in seconds.
const PAUSE_AFTER := 1.0

## How long a strike shows as the command of the body, in seconds.
const STRIKE_SHOWS := 0.8

## How often the log writes the state of the level, in seconds.
const LOG_EVERY := 1.0

## The opponent says a line at most this often, in seconds.
const QUIP_EVERY := 4.0

const _HELP := (
    "Keys: J K jab, U I hook, H L uppercut, Q E slip, Z duck, B cover, X jump,"
    + " arrows steer, R again, Esc Esc leave"
)

var vision: Node = null

var boxer: Boxer
## The opponent (null in a run).
var opponent: Opponent
var hud: Hud
var panel: CameraPanel

## The level now (see Levels), and whether it is a run.
var level := {}
var run := false

var _core: RefCounted
var _scenery: Scenery
var _body := BodyReader.new()
var _scoring := Scoring.new()
var _phase := Phase.WAITING
var _wait_left := 0.0
var _paused := false
var _unseen := 0.0
var _sections := PackedStringArray()
## The song's time now, in seconds, and how long the song is.
var _now := 0.0
var _length := 0.0
var _beat_seconds := 0.6
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
var _time := 0.0
var _last_strike := ""
var _last_strike_at := -10.0
var _slow_until := 0
var _log := FightLog.new()
var _logged_at := -10.0
var _logged_pose := ""
var _tunnel: BeatTunnel
var _quipped_at := -100.0
var _black_sheep: Node3D
var _quit: QuitHint
var _results: Control
var _veil: CameraVeil


func _ready() -> void:
    level = _chosen_level()
    run = level["kind"] == "run"
    RiggedFigure.chosen = Levels.hero_of(level)
    _beat_seconds = 60.0 / float(level["bpm"])
    _sections = PackedStringArray(level["sections"])

    _scenery = Scenery.new()
    add_child(_scenery)
    _scenery.setup(level["scenery"], SPOT, run)

    if not run:
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
    hud.opponent_name = "" if run else str(level["title"]).trim_prefix("THE ")
    var overlay := CanvasLayer.new()
    overlay.layer = 3
    add_child(overlay)
    _quit = QuitHint.new("Press Esc again to leave the level.")
    overlay.add_child(_quit)
    _results = Control.new()
    _results.set_anchors_preset(Control.PRESET_FULL_RECT)
    _results.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(_results)

    var holder := get_node_or_null("/root/Vision")
    if holder != null:
        vision = holder.service
        panel.setup(vision)
    if run:
        # NOTE (mristin):
        # In a run, the camera picture over the scene, so that he sees where
        # he stands (under the HUD).
        var veil_layer := CanvasLayer.new()
        veil_layer.layer = 1
        add_child(veil_layer)
        _veil = CameraVeil.new()
        _veil.vision = vision
        veil_layer.add_child(_veil)
        if not vision.IsReplaying():
            vision.ResetPlayer()

    _core = (load("res://scenes/fight/RhythmCore.cs") as Script).new()
    _intro_bars = _core.IntroBars()
    var seed := hash(level["id"]) & 0xffff
    _music = AudioStreamPlayer.new()
    _music.stream = _wav(
        _core.Song(
            float(level["bpm"]), _sections.size(), seed, level["progression"], level["transpose"]
        )
    )
    add_child(_music)
    for name in ["hit", "perfect", "miss", "dodge", "hurt", "bell", "count"]:
        var player := AudioStreamPlayer.new()
        player.stream = _wav(_core.Sound(name))
        player.volume_db = -4.0
        add_child(player)
        _sounds[name] = player
    var levels: PackedInt32Array = _core.Levels(_sections.size())
    _length = levels.size() * 4.0 * _beat_seconds
    _tunnel = BeatTunnel.new()
    _tunnel.setup(SPOT + Vector3(0, 1.35, -HIT_AHEAD), LEAD, SPEED, _beat_seconds)
    add_child(_tunnel)

    (
        _log
        . write(
            "scene",
            {
                "input": _input_source(),
                "hero": RiggedFigure.chosen,
                "bpm": level["bpm"],
                "level": level["id"],
            }
        )
    )
    if _log.path != "":
        print("Fight log: ", ProjectSettings.globalize_path(_log.path))
    _start()


## The level to play: the one the flow chose, or the one given with --level,
## or the first one.
static func _chosen_level() -> Dictionary:
    var id := Flow.level_id
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--level="):
            id = arg.trim_prefix("--level=")
    var chosen := Levels.by_id(id)
    return chosen if not chosen.is_empty() else Levels.ALL_LEVELS[0]


## Start the level: wait for the player, then play the song from the start.
func _start() -> void:
    for note in _notes:
        note.queue_free()
    _notes.clear()
    for child in _results.get_children():
        child.queue_free()
    var seed := hash(str(level["id"]) + str(Time.get_ticks_msec())) & 0xffff
    _chart = _core.Notes(_sections, seed, not run)
    _punches = _chart.filter(func(n: Dictionary) -> bool: return n["side"] != "").size()
    _next = 0
    _now = 0.0
    _last_beat = -1
    _scoring.reset()
    _in_pose.clear()
    _dodge_used = -100.0
    _music.stop()
    if opponent != null:
        opponent.reset()
    boxer.reset()
    _phase = Phase.WAITING
    _wait_left = 1.5
    _paused = false
    Engine.time_scale = 1.0
    hud.banner = ""
    hud.results = []
    hud.announce(level["title"], 3.0)
    _log.write("fight_start", {"notes": _chart.size(), "punches": _punches})


func _process(delta: float) -> void:
    if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _slow_until:
        Engine.time_scale = 1.0
    _time += delta

    _body.read(vision, delta)
    for move in _body.take():
        throw(move[0], move[1], move[2])
    for other in _body.others:
        _log.write("dodge_move", {"kind": other[0], "side": other[1], "song": _now})
    _body.others.clear()

    match _phase:
        Phase.WAITING:
            hud.banner = "GET READY"
            if BodyReader.sees(vision):
                _wait_left -= delta
            if _wait_left <= 0.0:
                _phase = Phase.PLAYING
                hud.banner = ""
                _music.play()
                _play("bell")
                _log.write("song_start")
        Phase.PLAYING:
            _run_song(delta)

    _remember_pose()
    boxer.lean = lerpf(boxer.lean, clampf(_body.lean, -1.0, 1.0), minf(1.0, delta * 14.0))
    boxer.duck = lerpf(boxer.duck, 1.0 if _body.ducking else 0.0, minf(1.0, delta * 12.0))
    boxer.jumping = _body.jumping
    boxer.covering = _body.covering
    var target := SPOT + Vector3(0, 0, -6.0)
    if run:
        boxer.shift = lerpf(boxer.shift, _body.steer * Scenery.LANE, minf(1.0, delta * 10.0))
        target.x = boxer.shift
        _veil.steer = _body.steer
    else:
        target = opponent.global_position
    boxer.face(target, delta)
    _tunnel.position.x = boxer.shift
    _tunnel.place(_now, _phase == Phase.PLAYING)
    if _black_sheep != null:
        _black_sheep.position.y = 0.12 * absf(sin(_time * PI / _beat_seconds))
    _update_hud()
    _log_state()


## Play the song on: its clock, the notes, the judging, the opponent.
func _run_song(delta: float) -> void:
    # NOTE (mristin):
    # Pause while the camera does not see the player.
    _unseen = 0.0 if BodyReader.sees(vision) else _unseen + delta
    var pause := _unseen > PAUSE_AFTER
    if pause != _paused:
        _paused = pause
        _music.stream_paused = pause
        hud.banner = "PAUSED" if pause else ""
        _log.write("pause" if pause else "resume", {"song": _now})
    if _paused:
        return

    var before := _now
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
    if run:
        # NOTE (mristin):
        # The land rolls towards him as fast as the notes.
        _scenery.scroll(maxf(0.0, _now - before) * SPEED)

    _on_beats()
    while _next < _chart.size() and _beat_time(_chart[_next]) - _now <= LEAD:
        _spawn(_chart[_next])
        _next += 1

    var attack := ""
    var attack_seconds := 0.0
    for note in _notes.duplicate():
        if run and not note.spans_road():
            note.follow = boxer.shift
        note.place(_now)
        if note.result == "":
            if note.kind.begins_with("lane_"):
                if _now >= note.at + _latency:
                    _judge_lane(note)
            elif note.side == "":
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
    if opponent != null:
        _move_opponent(attack, attack_seconds)

    if _now >= _length:
        _finish(opponent != null and opponent.health <= 0.0)


## The opponent moves to the music, and shows his attacks.
func _move_opponent(attack: String, attack_seconds: float) -> void:
    opponent.perform(attack, attack_seconds)
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
    opponent.show_off(quiet and attack == "")


## Things which happen on the beats: the count-in, the sections' titles, and
## the opponent's lines.
func _on_beats() -> void:
    var beat := floori(_now / _beat_seconds)
    if beat == _last_beat:
        return
    _last_beat = beat
    var bar := beat / 4
    var in_bar := beat % 4
    if bar == _intro_bars - 1:
        var counts := ["3", "2", "1", "GO!" if run else "BOX!"]
        hud.say(counts[in_bar], Hud.GOLD)
        _play("count" if in_bar < 3 else "bell")
    # NOTE (mristin):
    # Each section is announced a bar ahead.
    var coming: int = _core.SectionOf(bar + 1, _sections.size())
    if in_bar == 0 and coming >= 0 and coming != _core.SectionOf(bar, _sections.size()):
        var title := Levels.section_title(_sections, coming, run)
        hud.announce(title, 2.0)
        var lines: Array = level["lines"].get("section", [])
        if not lines.is_empty():
            hud.taunt(lines[coming % lines.size()])
        _log.write("section", {"section": coming, "title": title, "song": _now})


## The song time of a note's beat.
func _beat_time(note: Dictionary) -> float:
    return float(note["beat"]) * _beat_seconds


func _spawn(entry: Dictionary) -> void:
    var kind: String = entry["kind"]
    var side: String = entry["side"]
    var offset: Vector3 = ARRIVE[kind]
    var x := -offset.x if side == "left" else offset.x
    var arrive := SPOT + Vector3(x, offset.y, -offset.z)
    if run and kind == "jump":
        # NOTE (mristin):
        # A hole in the road, on the ground.
        arrive.y = 0.0
    var note := RhythmNote.new()
    add_child(note)
    var color := RhythmNote.ATTACK
    var theme := ""
    if run:
        color = OBSTACLES.get(level["scenery"], RhythmNote.ATTACK)
        theme = level["scenery"]
    note.setup(kind, side, _beat_time(entry), arrive, SPEED, color, theme)
    note.place(_now)
    _notes.append(note)


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
        hud.say("WRONG: " + wanted, Color("ff8a65"))
        _play("miss")
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
    if opponent != null:
        _hit_opponent(best, how)


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
    _scoring.met(how)
    var lane := note.kind.begins_with("lane_")
    var texts := {"perfect": "PERFECT!", "good": "GOOD", "dodged": "COIN!" if lane else "DODGED!"}
    hud.say(texts[how], Hud.GOLD if how == "perfect" else Hud.GREEN)
    match how:
        "perfect":
            _play("perfect")
            _play("hit")
        "good":
            _play("hit")
        "dodged":
            _play("perfect" if lane else "dodge")


## Say one of the opponent's lines of the kind now and then.
func _quip(kind: String) -> void:
    var lines: Array = level["lines"].get(kind, [])
    if lines.is_empty() or _time - _quipped_at < QUIP_EVERY or randf() > 0.6:
        return
    _quipped_at = _time
    hud.taunt(lines[randi() % lines.size()])


func _miss(note: RhythmNote) -> void:
    note.judge("miss", _now)
    _scoring.failed("miss")
    hud.say("MISS", Color(Hud.PAPER, 0.7))
    _play("miss")
    if opponent != null:
        opponent.evade(note.side)
        _quip("missed")
    _log.write("note", {"kind": note.kind, "side": note.side, "beat": note.at, "result": "miss"})


## Judge a dodge: did the player dodge the attack (or the obstacle) since its
## note showed? It counts as soon as he does; at the [param last] chance, it
## hits him if not.
func _judge_dodge(note: RhythmNote, last: bool) -> void:
    var since := note.at - LEAD
    var seen := float(_in_pose.get(note.kind, -100.0))
    var dodged := seen >= since and seen > _dodge_used
    if not dodged and not last:
        return
    (
        _log
        . write(
            "note",
            {
                "kind": note.kind,
                "beat": note.at,
                "result": "dodged" if dodged else "hit",
                "poses": _in_pose.duplicate(),
            }
        )
    )
    if dodged:
        _dodge_used = seen
        if opponent != null:
            opponent.stumble()
        _met(note, "dodged")
        return
    _hurt(note)


## Judge a steering note as its obstacles reach him: is he in the free lane?
func _judge_lane(note: RhythmNote) -> void:
    var free: int = LANE_OF[note.kind]
    # NOTE (mristin):
    # Where he is on the road, not where he steers to.
    var lane := clampi(roundi(boxer.shift / Scenery.LANE), -1, 1)
    var in_lane := lane == free
    var result := "dodged" if in_lane else "hit"
    _log.write("note", {"kind": note.kind, "beat": note.at, "result": result, "lane": lane})
    if in_lane:
        _met(note, "dodged")
    else:
        _hurt(note)


## An attack or an obstacle hit him: it costs him energy.
func _hurt(note: RhythmNote) -> void:
    note.judge("miss", _now)
    _scoring.failed("hit")
    _play("hurt")
    boxer.take_damage(HURT)
    if run:
        hud.say("OOF!", Hud.RED)
    else:
        opponent.cheer()
        _quip("landed")
        hud.say("OUCH!", Hud.RED)
    if boxer.health <= 0.0:
        _finish(false)


## Remember when the player was in each dodge last.
func _remember_pose() -> void:
    if _phase != Phase.PLAYING:
        return
    for pose in _body.dodges():
        _in_pose[pose] = _now


## End the level: [param knocked_out] if the player knocked the opponent out
## (else the song ended, or the player went down).
func _finish(knocked_out: bool) -> void:
    if _phase == Phase.OVER:
        return
    _phase = Phase.OVER
    _music.stop()
    _play("bell")
    hud.warning = ""
    var grade := _scoring.grade()
    var why := "time"
    var won := false
    if knocked_out:
        why = "knock_out"
        won = true
        opponent.knock_out()
        hud.banner = "K.O.!"
        Engine.time_scale = 0.3
        _slow_until = Time.get_ticks_msec() + 1200
    elif boxer.health <= 0.0:
        why = "down"
        hud.banner = "DOWN!"
    else:
        won = grade != "D"
        if run:
            hud.banner = "ARRIVED!" if won else "TRY AGAIN"
        else:
            hud.banner = "YOU WIN!" if won else "TIME!"
    Profile.finish_level(level["id"], won, grade, _scoring.score)
    hud.results = _scoring.lines()
    var results := Results.new()
    _results.add_child(results)
    results.setup(level["id"], won)
    var fields := {
        "why": why,
        "won": won,
        "song": _now,
        "score": _scoring.score,
        "grade": grade,
        "accuracy": _scoring.accuracy(),
        "counts": _scoring.counts.duplicate(),
        "best_combo": _scoring.best_combo,
        "latency": _latency,
        "health": boxer.health,
        "his_health": opponent.health if opponent != null else 0.0,
    }
    _log.write("fight_end", fields)


func _play(sound: String) -> void:
    (_sounds[sound] as AudioStreamPlayer).play()


## A stream of 16-bit mono samples (see RhythmCore).
func _wav(samples: PackedByteArray) -> AudioStreamWAV:
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = _core.SampleRate()
    stream.stereo = false
    stream.data = samples
    return stream


func _update_hud() -> void:
    hud.player_health = boxer.health / Boxer.MAX_HEALTH
    hud.opponent_health = opponent.health / Opponent.MAX_HEALTH if opponent != null else -1.0
    hud.hurt = boxer.hurt()
    hud.score = _scoring.score
    hud.combo = _scoring.combo
    hud.multiplier = _scoring.multiplier()
    hud.progress = clampf(_now / maxf(_length, 1.0), 0.0, 1.0)

    # NOTE (mristin):
    # The call of the next attack or obstacle, in its last beat and a half.
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
    _update_panel(call != "")


## The command of the body on the camera panel: a strike for a moment, else
## the dodge which counts, else the lane (in a run), else "READY".
func _update_panel(threatened: bool) -> void:
    var dodge := _body.pose()
    panel.threatened = threatened
    panel.dodging = dodge != ""
    if _time - _last_strike_at <= STRIKE_SHOWS:
        panel.command = _last_strike
        panel.command_color = Hud.GOLD
    elif dodge != "":
        panel.command = dodge
        panel.command_color = Color("6ccf5e")
    elif run:
        panel.command = ["LEFT", "MIDDLE", "RIGHT"][_body.lane() + 1]
        panel.command_color = Color(0.75, 0.77, 0.82)
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


## Log the state of the level now and then, and every change of the pose.
func _log_state() -> void:
    var pose := _body.pose()
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
        "his_health": opponent.health if opponent != null else 0.0,
        "score": _scoring.score,
        "combo": _scoring.combo,
        "latency": _latency,
        "lean": _body.lean,
        "steer": _body.steer,
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
    _body.key(key.keycode)
    match key.keycode:
        KEY_C:
            if vision != null:
                vision.Recalibrate()
        KEY_R:
            if _phase != Phase.OVER:
                _log.write("fight_end", {"why": "restarted", "song": _now, "score": _scoring.score})
            _start()
        KEY_F1:
            panel.visible = not panel.visible
        KEY_F3:
            RiggedFigure.chosen = RiggedFigure.next_hero()
            panel.rebuild_figure()
            hud.say(RiggedFigure.chosen.to_upper(), Hud.GOLD)
        KEY_ESCAPE:
            if _quit.press():
                if _phase != Phase.OVER:
                    _log.write("fight_end", {"why": "left", "song": _now, "score": _scoring.score})
                Flow.levels(get_tree())
