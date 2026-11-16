class_name RhythmLevel
extends Node3D

## The base of a level (see DESIGN.md and Levels): a run (see Run), in which
## the hero meets opponents on the road and boxes them (see Brawl), or the
## fight against the boss of a world (see Fight), a brawl to music.
##
## While a brawl goes on, the song's clock holds (see [method _holds]): the
## notes wait, and the brawl plays instead.
##
## A song plays (synthesized, see RhythmCore), and its chart sends notes at
## the player (see RhythmNote): each arrives on a beat, and he meets it then.
## The notes show two seconds ahead, so that the player always knows what
## comes, and when.
##
## The camera and the move classifier see a move a while after the player made
## it. So the level judges a move at the time it was seen, less that latency,
## which it learns from the player's own moves. It is forgiving in time, not
## in the move: the right move on its beat is PERFECT, and from the moment its
## note shows until a little after its beat GOOD; a wrong move does not count.
## A note not met is a MISS; an attack or an obstacle which he did not dodge
## costs him energy, and with none left he is down.
##
## A level is won with a grade of C or better at the end of the song (see
## Scoring; a fight also with a knock-out); winning opens the next level (see
## Profile). A panel in the upper left (see [CameraPanel]) shows the player
## how the game sees him. The level pauses while the camera does not see the
## player. Every level writes a log (see [FightLog]). Esc twice leaves the
## level.
##
## Start it with [code]-- --level=<id>[/code] to play a level directly, and
## with [code]-- --replay=<recording.jsonl>[/code] to play a recorded video
## instead of the camera (see dev/replay/).
##
## A level is played with the body only, not the keyboard (Esc twice leaves
## it).

## The phases of a level.
enum Phase { WAITING, PLAYING, OVER }

## How long a note shows before its beat, in seconds, and how fast it flies
## (meters per second).
const LEAD := 2.0
const SPEED := 3.3

## Where the player stands.
const SPOT := Vector3(0, 0, 1.5)

## How far ahead of the player the notes arrive (most of them), in meters.
const HIT_AHEAD := 0.75

## How far ahead the punches arrive, in meters: on the face of the opponent,
## who stands close (see Fight.OPPONENT_DISTANCE).
const PUNCH_AHEAD := 0.88

## Where each note arrives, from the player's eyes on the floor (x to his
## right, y up from the floor, z ahead): the left hand's are mirrored. The
## punches arrive on the opponent's head: a jab on his face, a hook at its
## side, an uppercut at his chin.
const ARRIVE := {
    "straight": Vector3(0.12, 1.66, PUNCH_AHEAD),
    "hook": Vector3(0.3, 1.64, PUNCH_AHEAD),
    "uppercut": Vector3(0.1, 1.5, PUNCH_AHEAD),
    "cover": Vector3(0.0, 1.55, HIT_AHEAD),
    "slip_left": Vector3(0.4, 1.55, HIT_AHEAD),
    "slip_right": Vector3(-0.4, 1.55, HIT_AHEAD),
    "duck": Vector3(0.0, 1.62, HIT_AHEAD),
    "jump": Vector3(0.0, 0.6, 1.3),
    "lane_left": Vector3(0.0, 0.0, HIT_AHEAD),
    "lane_middle": Vector3(0.0, 0.0, HIT_AHEAD),
    "lane_right": Vector3(0.0, 0.0, HIT_AHEAD),
    "fence_jump": Vector3(0.0, 0.0, HIT_AHEAD),
    "fence_duck": Vector3(0.0, 0.0, HIT_AHEAD),
    "split": Vector3(0.0, 0.0, HIT_AHEAD),
    "plank": Vector3(0.0, 0.0, HIT_AHEAD),
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

## A dodge counts from the moment its note shows until this long after its
## beat (plus the latency), in seconds: in the first play-test, the slips came
## up to 0.6 s after the beat.
const DODGE_LATE := 0.7

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

## How much an attack or an obstacle which he did not dodge costs him.
const HURT := 8.0

## How long the camera may lose the player before the level pauses, in seconds.
const PAUSE_AFTER := 1.0

## How long a strike shows as the command of the body, in seconds.
const STRIKE_SHOWS := 0.8

## How often the log writes the state of the level, in seconds.
const LOG_EVERY := 1.0

var vision: Node = null

var boxer: Boxer
var hud: Hud
var panel: CameraPanel

## The level now (see Levels).
var level := {}

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
## The time of the notes, in seconds: in a fight the song's; in a run, how far
## he ran, at the pace of the notes (see Run: he sets the pace).
var _t := 0.0
## Whether he lost before the end (e.g., a run too slow for its time).
var _failed := false
var _announced_bar := -1
## Whether the clock follows the music as heard (a fight: the notes are on
## its beats; a run sets its own pace, and loops its music).
var _follow_music := true
var _length := 0.0
var _beat_seconds := 0.6
var _intro_bars := 4
var _music: AudioStreamPlayer
var _sounds := {}
var _chart: Array = []
var _next := 0
var _notes: Array[RhythmNote] = []
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
var _quit: QuitHint
var _results: Control


func _ready() -> void:
    level = _chosen_level()
    RiggedFigure.chosen = Levels.hero_of(level)
    _beat_seconds = 60.0 / float(level["bpm"])
    _sections = PackedStringArray(level["sections"])

    _scenery = Scenery.new()
    add_child(_scenery)
    _scenery.setup(level["scenery"], SPOT, _is_run())

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
    for name in ["hit", "perfect", "miss", "dodge", "hurt", "bell", "count", "tell", "block"]:
        var player := AudioStreamPlayer.new()
        player.stream = _wav(_core.Sound(name))
        player.volume_db = -4.0
        add_child(player)
        _sounds[name] = player
    var levels: PackedInt32Array = _core.Levels(_sections.size())
    _length = levels.size() * 4.0 * _beat_seconds
    _build()

    var fields := {
        "input": _input_source(),
        "hero": RiggedFigure.chosen,
        "bpm": level["bpm"],
        "level": level["id"],
    }
    _log.write("scene", fields)
    if _log.path != "":
        print("Fight log: ", ProjectSettings.globalize_path(_log.path))
    _start()


## The level to play: the one the flow chose, or the one given with --level,
## or the first one of its kind.
func _chosen_level() -> Dictionary:
    var id := Flow.level_id
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--level="):
            id = arg.trim_prefix("--level=")
    var kind := "run" if _is_run() else "boss"
    var chosen := Levels.by_id(id)
    if not chosen.is_empty() and chosen["kind"] == kind:
        return chosen
    for entry in Levels.ALL_LEVELS:
        if entry["kind"] == kind:
            return entry
    return Levels.ALL_LEVELS[0]


## Whether it is a run (in the subclasses).
func _is_run() -> bool:
    return false


## Build what the kind of level has besides (in the subclasses).
func _build() -> void:
    pass


## Start the level: wait for the player, then play the song from the start.
func _start() -> void:
    for note in _notes:
        note.queue_free()
    _notes.clear()
    for child in _results.get_children():
        child.queue_free()
    var seed := hash(str(level["id"]) + str(Time.get_ticks_msec())) & 0xffff
    _chart = _core.Notes(_sections, seed, not _is_run(), not _is_run())
    _next = 0
    _now = 0.0
    _t = 0.0
    _failed = false
    _announced_bar = -1
    _last_beat = -1
    _scoring.reset()
    _in_pose.clear()
    _dodge_used = -100.0
    _music.stop()
    boxer.reset()
    _phase = Phase.WAITING
    _wait_left = 1.5
    _paused = false
    Engine.time_scale = 1.0
    hud.banner = ""
    hud.results = []
    hud.announce(level["title"], 3.0)
    _on_start()
    _log.write("fight_start", {"notes": _chart.size()})


## Start what the kind of level has besides (in the subclasses).
func _on_start() -> void:
    pass


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
    _on_frame(delta)
    _update_hud()
    _log_state()


## Every frame, what the kind of level does besides: at least, face the
## player where he looks (in the subclasses).
func _on_frame(delta: float) -> void:
    boxer.face(SPOT + Vector3(0, 0, -6.0), delta)


## Play the song on: its clock, the notes, the judging.
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
    if _holds():
        _hold(delta)
        return

    var before := _now
    _now += delta
    if _music.playing and _follow_music:
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

    _advance(maxf(0.0, _now - before))
    _on_beats()
    while _next < _chart.size() and _beat_time(_chart[_next]) - _t <= LEAD:
        _spawn(_chart[_next])
        _next += 1

    var attack: RhythmNote = null
    for note in _notes.duplicate():
        _place(note)
        if note.result == "" and not _judge(note):
            if note.side == "":
                if attack == null and absf(_t - note.at) <= 0.7:
                    attack = note
                _judge_dodge(note, _t >= note.at + _latency + DODGE_LATE)
            elif _t > note.at + GOOD + _latency:
                _miss(note)
        if note.is_done(_t):
            _notes.erase(note)
            note.queue_free()
        if _phase == Phase.OVER:
            return
    _on_song(maxf(0.0, _now - before), attack)
    _check_end()


## Whether the song's clock holds now, while a brawl goes on (in the
## subclasses).
func _holds() -> bool:
    return false


## Play on by [param delta] seconds while the song's clock holds (in the
## subclasses).
func _hold(_delta: float) -> void:
    pass


## The call of an opponent's attack which comes (see Brawl.dodge_call; in the
## subclasses): its text, where it comes from, and how far it got.
func _call() -> Array:
    return []


## Show the player's strike (a punch or a kick of the side) on the camera
## panel and with the gloves (or the leg).
func _show_strike(kind: String, side: String) -> void:
    var names := {"straight": "JAB", "hook": "HOOK", "uppercut": "UPPERCUT", "kick": "KICK"}
    _last_strike = "%s %s" % [side.to_upper(), names.get(kind, kind.to_upper())]
    _last_strike_at = _time
    if kind == "kick":
        boxer.kick(0 if side == "left" else 1)
    else:
        boxer.punch(0 if side == "left" else 1, kind)


## Whether an attack of an opponent is clearly coming (in the subclasses).
func _threatened() -> bool:
    return false


## Play the sound of the name at the volume (in dB), for a brawl.
func play_sound(sound: String, volume_db: float) -> void:
    var player := _sounds[sound] as AudioStreamPlayer
    player.volume_db = volume_db
    player.play()


## Move the time of the notes on by the song's [param played] seconds: in a
## fight, the song's time (a run, see Run, sets its own pace).
func _advance(_played: float) -> void:
    _t = _now


## End the level when it is over: at the end of the song (in the subclasses,
## besides).
func _check_end() -> void:
    if _now >= _length:
        _finish(false)


## Place a note at the time of the notes now (the subclasses move some
## besides).
func _place(note: RhythmNote) -> void:
    note.place(_t)


## Judge a note of the kind of level's own (in the subclasses); whether it did.
func _judge(_note: RhythmNote) -> bool:
    return false


## What the kind of level does as the song plays on by [param played] seconds,
## with the attack of the moment (if any; in the subclasses).
func _on_song(_played: float, _attack: RhythmNote) -> void:
    pass


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
        var counts := ["3", "2", "1", "GO!" if _is_run() else "BOX!"]
        hud.say(counts[in_bar], Hud.GOLD)
        _play("count" if in_bar < 3 else "bell")
    # NOTE (mristin):
    # Each section is announced a bar ahead, by the time of the notes (in a
    # run, as far as he ran).
    var note_bar := floori(_t / (_beat_seconds * 4.0))
    if note_bar == _announced_bar:
        return
    _announced_bar = note_bar
    var coming: int = _core.SectionOf(note_bar + 1, _sections.size())
    if coming >= 0 and coming != _core.SectionOf(note_bar, _sections.size()):
        var title := Levels.section_title(_sections, coming, _is_run())
        hud.announce(title, 2.0)
        var lines: Array = level.get("lines", {}).get("section", [])
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
    var note := RhythmNote.new()
    add_child(note)
    _set_up(note, kind, side, _beat_time(entry), SPOT + Vector3(x, offset.y, -offset.z))
    note.place(_t)
    _notes.append(note)


## Set a new note up (the subclasses give their obstacles their looks).
func _set_up(note: RhythmNote, kind: String, side: String, at: float, arrive: Vector3) -> void:
    note.setup(kind, side, at, arrive, SPEED)


## Throw a punch of the player (in a fight; see Fight).
func throw(_kind: String, _side: String, _source := "vision") -> void:
    pass


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
    note.judge(how, _t)
    _scoring.met(how)
    var gap := note.kind.begins_with("lane_")
    var texts := {"perfect": "PERFECT!", "good": "GOOD", "dodged": "CLEAR!" if gap else "DODGED!"}
    hud.say(texts[how], Hud.GOLD if how == "perfect" else Hud.GREEN)
    match how:
        "perfect":
            _play("perfect")
            _play("hit")
        "good":
            _play("hit")
        "dodged":
            _play("dodge")


func _miss(note: RhythmNote) -> void:
    note.judge("miss", _t)
    _scoring.failed("miss")
    hud.say("MISS", Color(Hud.PAPER, 0.7))
    _play("miss")
    _on_missed(note)
    _log.write("note", {"kind": note.kind, "side": note.side, "beat": note.at, "result": "miss"})


## What the kind of level does when he missed a note (in the subclasses).
func _on_missed(_note: RhythmNote) -> void:
    pass


## Judge a dodge: did the player dodge the attack (or the obstacle) since its
## note showed? It counts as soon as he does; at the [param last] chance, it
## hits him if not.
func _judge_dodge(note: RhythmNote, last: bool) -> void:
    var since := note.at - LEAD
    var seen := float(_in_pose.get(note.kind, -100.0))
    var dodged := seen >= since and seen > _dodge_used
    if not dodged and not last:
        return
    var fields := {
        "kind": note.kind,
        "beat": note.at,
        "result": "dodged" if dodged else "hit",
        "poses": _in_pose.duplicate(),
    }
    _log.write("note", fields)
    if dodged:
        _dodge_used = seen
        _on_dodged(note)
        _met(note, "dodged")
        return
    _hurt(note)


## What the kind of level does when he dodged (in the subclasses).
func _on_dodged(_note: RhythmNote) -> void:
    pass


## An attack or an obstacle hit him: it costs him energy.
func _hurt(note: RhythmNote) -> void:
    note.judge("miss", _t)
    _scoring.failed("hit")
    _play("hurt")
    boxer.take_damage(HURT)
    _on_hurt(note)
    if boxer.health <= 0.0:
        _finish(false)


## What the kind of level does when he was hit (in the subclasses).
func _on_hurt(_note: RhythmNote) -> void:
    hud.say("OUCH!", Hud.RED)


## Remember when the player was in each dodge last.
func _remember_pose() -> void:
    if _phase != Phase.PLAYING:
        return
    for pose in _body.dodges():
        _in_pose[pose] = _t


## End the level: [param knocked_out] if the player knocked the opponent out
## (in a fight; else the song ended, or the player went down).
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
        _knock_out()
    elif boxer.health <= 0.0:
        why = "down"
        hud.banner = "DOWN!"
    else:
        won = grade != "D" and not _failed
        hud.banner = _banner(won)
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
        "his_health": _his_health(),
    }
    _log.write("fight_end", fields)


## The knock-out (in a fight).
func _knock_out() -> void:
    pass


## The banner at the end of the song (in the subclasses).
func _banner(won: bool) -> String:
    return "YOU WIN!" if won else "TIME!"


## How far the level is, in [0, 1] (the song's time; a run, see Run, its
## way).
func _progress() -> float:
    return clampf(_now / maxf(_length, 1.0), 0.0, 1.0)


## The opponent's health (-1 without one).
func _his_health() -> float:
    return -1.0


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
    var his := _his_health()
    hud.opponent_health = his / Opponent.MAX_HEALTH if his >= 0.0 else -1.0
    hud.hurt = boxer.hurt()
    hud.score = _scoring.score
    hud.combo = _scoring.combo
    hud.multiplier = _scoring.multiplier()
    hud.progress = _progress()

    # NOTE (mristin):
    # The call of the next attack or obstacle, in its last beat and a half.
    var call := ""
    var call_from := ""
    var call_progress := 0.0
    if _phase == Phase.PLAYING:
        for note in _notes:
            if note.side != "" or note.result != "":
                continue
            var left := note.at - _t
            if left <= _beat_seconds * 1.5 and left > -0.1:
                var called: Array = _note_call(note)
                call = called[0]
                call_from = called[1]
                call_progress = clampf(1.0 - left / (_beat_seconds * 1.5), 0.0, 1.0)
            break
    if call == "" and _phase == Phase.PLAYING:
        var called := _call()
        if not called.is_empty():
            call = called[0]
            call_from = called[1]
            call_progress = called[2]
    hud.warning = call
    hud.warning_from = call_from
    hud.warning_progress = call_progress
    _update_panel(call != "" or _threatened())


## The call of a note which comes, and where its arrow comes from (see
## CALLS; the subclasses call their own obstacles).
func _note_call(note: RhythmNote) -> Array:
    return CALLS[note.kind]


## The command of the body when he does nothing (in the subclasses).
func _idle_command() -> String:
    return "READY"


## The command of the body on the camera panel: a strike for a moment, else
## the dodge which counts, else the idle one.
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
    else:
        panel.command = _idle_command()
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
        "his_health": _his_health(),
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
    return "none"


## The levels are played with the body only: the only key is Esc, twice, to
## leave the level.
func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key := event as InputEventKey
    if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
        return
    if _quit.press():
        if _phase != Phase.OVER:
            _log.write("fight_end", {"why": "left", "song": _now, "score": _scoring.score})
        Flow.levels(get_tree())
