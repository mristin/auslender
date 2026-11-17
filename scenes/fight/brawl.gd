class_name Brawl
extends RefCounted

## A free fight between the player and one opponent (see DESIGN.md): no
## chart, no notes; both box when they like, until one goes down. The hero
## crashes into the opponents on the road of a run (see Run), and the boss of
## a world waits in a level of his own (see Fight).
##
## The opponent has a mind of his own. He keeps his guard up, but it is open
## somewhere, and he moves the opening around now and then (see
## Opponent.open_for): his arms wide for a jab, one side of his head bare for
## a hook from that side, his chin for an uppercut. A punch into the opening
## lands; any other is blocked, and only scratches him. Now and then he
## attacks: a jab (dodged with the cover, or a slip to either side, as
## boxers slip a jab) or a hook from one side (dodged with a slip to the
## other); a duck dodges both (the fights do not ask for it, but it works).
## His wind-up is his tell, quiet but long: he draws the arm back slowly and
## shifts his weight, a faint glint creeps over him, and a soft breath sounds
## as he starts it. There are no calls and no
## arrows on the screen.
##
## The camera and the classifier see a move about half a second late (in the
## first free fight of the play-tests, about a second from the cue to a
## recognized dodge, which made it unplayable with short wind-ups). So the
## wind-ups are long, a dodge counts from the second half of the wind-up
## until a while after the strike (as the vision sees it late), and a punch
## counts against his guard as it was a moment before it was seen.
##
## After he strikes, he is open for a moment: long, if the player dodged
## (he stumbles past, winded: a counter hits harder), short, if he landed
## (he cheers). A boss is tougher, winds up and attacks sooner, and throws
## two in a row now and then. A player who hides behind his cover gets
## hooks; one who leans aside all the time gets jabs.

## The states of the brawl.
enum State { GUARD, WINDUP, STRIKE, OPEN, DOWN, OVER }

## How long he winds up, in seconds: a normal opponent and a boss.
const WINDUP := 1.35
const BOSS_WINDUP := 1.05

## How long he waits between his attacks, in seconds (at random in the
## range), and before his first.
const GAP := Vector2(2.2, 3.8)
const BOSS_GAP := Vector2(1.4, 2.6)
const FIRST_ATTACK := 2.5

## How long he holds an opening of his guard, in seconds (at random).
const HOLD := Vector2(1.8, 3.0)
const BOSS_HOLD := Vector2(1.3, 2.2)

## How many clean punches knock him out (a counter counts more): a minor
## opponent in about 30 s, a boss in about a minute.
const CLEAN_HITS := 12.0
const BOSS_CLEAN_HITS := 24.0

## A kick goes to his body, under his guard: it lands whenever he does not
## wind up or strike (a counter while he is winded), but hurts him only this
## much of a clean punch.
const KICK := 0.6

## A blocked punch hurts him this much of a clean one; a counter this many
## times a clean one.
const CHIP := 0.06
const COUNTER := 1.5

## How long he is open after his strike, in seconds: when the player dodged
## it (winded, a counter), and when it landed (he cheers).
const WINDED := 1.7
const CHEERS := 0.9

## The share of the wind-up from which a dodge counts, and how long after the
## strike, in seconds: the vision sees it late.
const DODGE_FROM := 0.35
const DODGE_LATE := 0.55

## How late the vision sees a punch, in seconds, and how far before that his
## guard still counts.
const LATENCY := 0.3
const GRACE := 0.35

## How much his attack hurts the player, and how much less a hook on the
## cover.
const HURT := 6.0
const BOSS_HURT := 11.0
const COVERED := 0.5

## How often a boss throws a second attack at once, and how much quicker he
## winds it up.
const FOLLOW_UP := 0.35
const FOLLOW_UP_WINDUP := 0.85

## How long the player has to hide behind his cover (or lean aside) before
## the opponent picks the attack which beats it, in seconds.
const TURTLE := 1.0

## How long after the knock-out the brawl is over, in seconds.
const DOWN_SECONDS := 2.0

## What an opponent on the road shouts as he runs away, if he has no lines of
## his own ("flee", see Levels.OPPONENTS).
const FLEE_LINES := ["I'm out of here!", "Mommy!", "Not today!", "You win, I'm off!"]

## He says a line at most this often, in seconds.
const QUIP_EVERY := 5.0

## The dodge of each attack which a boss calls (see [method dodge_call]), and
## all the dodges which count against it (in the first free fights, the
## players slipped the jabs rather than covering).
const DODGE_OF := {"jab": "cover", "hook_left": "slip_right", "hook_right": "slip_left"}
const DODGES := {
    "jab": ["cover", "slip_left", "slip_right", "duck"],
    "hook_left": ["slip_right", "duck"],
    "hook_right": ["slip_left", "duck"],
}

var opponent: Opponent
## The opponent (see Levels.OPPONENTS).
var spec := {}
var state := State.OVER
## How many times as hard the player's punches hit (a booster of a run, see
## Boosters).
var power := 1.0

var _hud: Hud
var _boxer: Boxer
var _scoring: Scoring
var _log: FightLog
var _sound: Callable
var _beat_seconds := 0.6

var _clock := 0.0
var _boss := false
var _opening := ""
var _opening_side := ""
var _opening_hits := 0
var _next_opening := 0.0
var _next_attack := 0.0
var _attack := ""
var _windup := WINDUP
var _windup_from := 0.0
var _strike_at := 0.0
var _resolved := false
var _follow_up := false
var _open_until := 0.0
var _winded := false
var _down_at := 0.0
var _quipped_at := -100.0
## When the player was in each dodge last (on the brawl's clock), and since
## when he holds the cover and leans aside.
var _seen := {}
var _covering_since := -1.0
var _leaning_since := -1.0
## The state of his guard over the last moments: [clock, what lands then]:
## "counter", "any", or the opening as "kind side" ("" for nothing).
var _history: Array = []


## Get the brawl ready, with what it reports to: the HUD, the player, the
## score, the log, and [param sound] (called with the name of a sound and its
## volume in dB).
func setup(
    hud: Hud, boxer: Boxer, scoring: Scoring, log: FightLog, sound: Callable, beat_seconds: float
) -> void:
    _hud = hud
    _boxer = boxer
    _scoring = scoring
    _log = log
    _sound = sound
    _beat_seconds = beat_seconds


## Start the brawl against the opponent of the [param id] (see
## Levels.OPPONENTS), whose figure is [param figure].
func start(id: String, figure: Opponent) -> void:
    spec = Levels.opponent(id)
    opponent = figure
    _boss = bool(spec["boss"])
    opponent.windup_seconds = BOSS_WINDUP if _boss else WINDUP
    _clock = 0.0
    _seen.clear()
    _history.clear()
    _covering_since = -1.0
    _leaning_since = -1.0
    _attack = ""
    _quipped_at = -100.0
    _next_attack = FIRST_ATTACK
    _new_opening()
    state = State.GUARD
    _hud.opponent_name = str(spec["title"]).trim_prefix("THE ")
    _quip("taunt", true)
    _log.write("brawl_start", {"opponent": id})


## Whether the brawl goes on (also while he lies down).
func active() -> bool:
    return state != State.OVER


## Whether he is down (knocked out).
func knocked_out() -> bool:
    return state == State.DOWN or (state == State.OVER and opponent.health <= 0.0)


## The call of the dodge of his attack while a boss winds it up (a boss
## telegraphs his attacks plainly; a minor opponent only with his body): its
## text and where it comes from (see RhythmLevel.CALLS), and how far the
## wind-up got; empty if none.
func dodge_call() -> Array:
    if not _boss or state != State.WINDUP:
        return []
    var dodge: String = DODGE_OF.get(_attack, "")
    if dodge == "":
        return []
    var share := clampf(1.0 - (_strike_at - _clock) / _windup, 0.0, 1.0)
    return [RhythmLevel.CALLS[dodge][0], RhythmLevel.CALLS[dodge][1], share]


## Whether his wind-up is clear by now (for the circle on the camera panel,
## which glows only in its second half).
func threatened() -> bool:
    return state == State.WINDUP and _clock >= _strike_at - _windup * 0.5


## Play the brawl on by [param delta] seconds, with the dodges the player is
## in now (see BodyReader.dodges).
func step(delta: float, dodges: Array) -> void:
    if state == State.OVER:
        return
    _clock += delta
    for pose in dodges:
        _seen[pose] = _clock
    _follow_turtle(dodges)
    var bar := _clock / (_beat_seconds * 4.0)
    opponent.groove(fposmod(_clock / _beat_seconds, 1.0), fposmod(bar, 1.0), floori(bar))

    match state:
        State.GUARD:
            opponent.perform("", 0.0)
            if _clock >= _next_opening:
                _new_opening()
            if _clock >= _next_attack:
                _wind_up(_windup_of())
            elif _clock - _quipped_at > QUIP_EVERY * 1.6:
                _quip("taunt")
        State.WINDUP, State.STRIKE:
            opponent.perform(_attack, _clock - _strike_at)
            if state == State.WINDUP and _clock >= _strike_at:
                state = State.STRIKE
            if not _resolved:
                if state == State.STRIKE and _dodged():
                    _on_dodged()
                elif _clock >= _strike_at + DODGE_LATE:
                    _on_landed()
            elif _clock >= _strike_at + Opponent.STRIKE_SECONDS:
                _after_strike()
        State.OPEN:
            opponent.perform("", 0.0)
            if _clock >= _open_until:
                state = State.GUARD
                _next_attack = _clock + _gap()
                _new_opening()
        State.DOWN:
            if _clock - _down_at >= DOWN_SECONDS:
                state = State.OVER
                _log.write("brawl_end", {"opponent": spec["look"], "won": true})
    _remember_guard()


## The player threw a punch ("straight", "hook" or "uppercut"; "left" or
## "right"): it lands, if it went where his guard was open as the player threw
## it (a counter while he is winded), else he blocks it. A "kick" lands
## unless he winds up or strikes (see KICK).
func punch(kind: String, side: String) -> void:
    if state == State.OVER or state == State.DOWN:
        return
    var lands := _lands(kind, side, _clock - LATENCY)
    var clean := 100.0 / (BOSS_CLEAN_HITS if _boss else CLEAN_HITS)
    if kind == "kick":
        clean *= KICK
    clean *= power
    var fields := {"kind": kind, "side": side, "clock": _clock, "result": lands}
    _log.write("punch", fields)
    match lands:
        "counter":
            _scoring.met("countered")
            opponent.flinch(kind, side, 1.0, clean * COUNTER)
            _hud.say("COUNTER!", Hud.GOLD)
            _sound.call("perfect", -4.0)
            _sound.call("hit", -4.0)
        "landed":
            _scoring.met("landed")
            opponent.flinch(kind, side, 0.85, clean)
            _hud.say("HIT!", Hud.GREEN)
            _sound.call("hit", -4.0)
            # NOTE (mristin):
            # Hit twice in the same opening, he moves it soon.
            _opening_hits += 1
            if _opening_hits >= 2 and state == State.GUARD:
                _next_opening = minf(_next_opening, _clock + 0.4)
        _:
            opponent.health = maxf(0.0, opponent.health - clean * CHIP)
            opponent.block()
            _sound.call("block", -8.0)
            _hud.say("blocked", Color(Hud.PAPER, 0.45))
            if randf() < 0.3:
                _quip("blocked")
    if lands != "blocked" and state == State.GUARD:
        # NOTE (mristin):
        # A punch which lands sets him back: his next attack waits a little.
        _next_attack = maxf(_next_attack, _clock + 0.6)
    if opponent.health <= 0.0:
        state = State.DOWN
        _down_at = _clock
        if _boss:
            opponent.knock_out()
            _log.write("knock_out", {"opponent": spec["look"], "clock": _clock})
        else:
            # NOTE (mristin):
            # The game does not knock out the opponents on the road: beaten,
            # they give up and run away.
            opponent.flee()
            _hud.say("HE RUNS AWAY!", Hud.GOLD)
            var lines: Array = spec["lines"].get("flee", FLEE_LINES)
            _hud.taunt(lines[randi() % lines.size()])
            _log.write("flee", {"opponent": spec["look"], "clock": _clock})


## How the punch thrown at [param when] (on the brawl's clock) goes: "counter",
## "landed" or "blocked". It lands if his guard was open for it at any moment
## from a little before then until now.
func _lands(kind: String, side: String, when: float) -> String:
    var best := "blocked"
    for entry in _history:
        if float(entry[0]) < when - GRACE:
            continue
        var open: String = entry[1]
        if open == "counter":
            return "counter"
        if open == "any" or open == kind + " " + side or open == kind + " any":
            best = "landed"
        elif kind == "kick" and open != "":
            best = "landed"
    return best


## Remember what of his guard is open now (see _history).
func _remember_guard() -> void:
    var open := ""
    match state:
        State.GUARD:
            if _opening != "":
                open = _opening + " " + (_opening_side if _opening == "hook" else "any")
        State.OPEN:
            open = "counter" if _winded else "any"
    _history.append([_clock, open])
    while not _history.is_empty() and float(_history[0][0]) < _clock - 2.0:
        _history.pop_front()


## Move the opening of his guard elsewhere (never the same twice in a row,
## if he has more than one).
func _new_opening() -> void:
    var openings: Array = spec["openings"]
    var choices := []
    for kind in openings:
        if kind == "hook":
            choices.append(["hook", "left"])
            choices.append(["hook", "right"])
        else:
            choices.append([kind, ""])
    if choices.size() > 1:
        choices = choices.filter(
            func(c: Array) -> bool: return not (c[0] == _opening and c[1] == _opening_side)
        )
    var chosen: Array = choices[randi() % choices.size()]
    _opening = chosen[0]
    _opening_side = chosen[1]
    _opening_hits = 0
    opponent.open_for(_opening, _opening_side)
    var hold := BOSS_HOLD if _boss else HOLD
    _next_opening = _clock + randf_range(hold.x, hold.y)


## Wind up an attack of his, which lands in [param windup] seconds.
func _wind_up(windup: float) -> void:
    _attack = _choose_attack()
    _windup = windup
    opponent.windup_seconds = windup
    _windup_from = _clock
    _strike_at = _clock + windup
    _resolved = false
    _follow_up = _boss and randf() < FOLLOW_UP
    state = State.WINDUP
    # NOTE (mristin):
    # He closes his guard as he winds up.
    opponent.open_for("", "")
    _sound.call("tell", -14.0)
    _log.write("attack", {"attack": _attack, "clock": _clock, "windup": windup})


func _windup_of() -> float:
    return BOSS_WINDUP if _boss else WINDUP


## His next attack: at random of his, but the hook for a player who hides
## behind his cover, and the jab for one who leans aside all the time.
func _choose_attack() -> String:
    var attacks: Array = spec["attacks"]
    var kind: String = attacks[randi() % attacks.size()]
    if attacks.has("hook") and _covering_since >= 0.0 and _clock - _covering_since >= TURTLE:
        kind = "hook"
    elif attacks.has("jab") and _leaning_since >= 0.0 and _clock - _leaning_since >= TURTLE:
        kind = "jab"
    if kind == "hook":
        return "hook_left" if randf() < 0.5 else "hook_right"
    return kind


## Whether the player made the dodge of the attack, from the second half of
## the wind-up on.
func _dodged() -> bool:
    for dodge in DODGES.get(_attack, []):
        if float(_seen.get(dodge, -100.0)) >= _windup_from + _windup * DODGE_FROM:
            return true
    return false


func _on_dodged() -> void:
    _resolved = true
    _winded = true
    _scoring.met("dodged")
    _hud.say("DODGED!", Hud.GREEN)
    _sound.call("dodge", -4.0)
    opponent.stumble()
    _log.write("attack_end", {"attack": _attack, "result": "dodged", "clock": _clock})


func _on_landed() -> void:
    _resolved = true
    _winded = false
    var covered := _attack != "jab" and float(_seen.get("cover", -100.0)) >= _clock - 0.3
    var hurt := BOSS_HURT if _boss else HURT
    _scoring.failed("hit")
    _sound.call("hurt", -4.0)
    _boxer.take_damage(hurt * (COVERED if covered else 1.0), covered)
    _hud.say("OUCH!", Hud.RED)
    opponent.cheer()
    _quip("landed")
    var fields := {"attack": _attack, "result": "hit", "covered": covered, "clock": _clock}
    _log.write("attack_end", fields)


## After his strike: a boss may throw a second at once; else he is open for a
## moment (winded, if the player dodged).
func _after_strike() -> void:
    if _follow_up and _boxer.health > 0.0:
        _follow_up = false
        _wind_up(_windup_of() * FOLLOW_UP_WINDUP)
        # NOTE (mristin):
        # Never three in a row.
        _follow_up = false
        return
    state = State.OPEN
    _open_until = _clock + (WINDED if _winded else CHEERS)
    opponent.open_for("open" if _winded else "", "")


## Follow how long the player hides behind his cover or leans aside.
func _follow_turtle(dodges: Array) -> void:
    if dodges.has("cover"):
        if _covering_since < 0.0:
            _covering_since = _clock
    else:
        _covering_since = -1.0
    if dodges.has("slip_left") or dodges.has("slip_right"):
        if _leaning_since < 0.0:
            _leaning_since = _clock
    else:
        _leaning_since = -1.0


func _gap() -> float:
    var gap := BOSS_GAP if _boss else GAP
    # NOTE (mristin):
    # Badly hurt, he attacks sooner.
    var rage := 0.75 if opponent.health < Opponent.MAX_HEALTH * 0.35 else 1.0
    return randf_range(gap.x, gap.y) * rage


## Say one of his lines of the kind now and then ([param surely]: now).
func _quip(kind: String, surely := false) -> void:
    var lines: Array = spec["lines"].get(kind, [])
    if lines.is_empty() or _clock - _quipped_at < QUIP_EVERY:
        return
    if not surely and randf() > 0.6:
        return
    _quipped_at = _clock
    _hud.taunt(lines[randi() % lines.size()])
