class_name Scoring
extends RefCounted

## The score of a level (see Run and Fight): how the player met the obstacles
## of a run and how he boxed (see Brawl): the punches which landed (a counter
## more), and the attacks he dodged; the combo of these in a row, which
## multiplies the points, the accuracy and the grade. A punch into the guard
## counts for nothing either way.

## The points of each judgement, before the combo's multiplier; the combo
## raises the multiplier by one every this many notes, up to the most.
const POINTS := {"perfect": 100, "good": 50, "dodged": 100, "landed": 100, "countered": 200}
const COMBO_STEP := 8
const MULTIPLIER_MOST := 4

## How much a GOOD counts for the accuracy, against a PERFECT (striking early
## is allowed).
const GOOD_SHARE := 0.75

## The grades, from the accuracy.
const GRADES := [[0.95, "S"], [0.85, "A"], [0.7, "B"], [0.5, "C"]]

## The names of the counts in the results, in order.
const NAMES := {
    "landed": "LANDED",
    "countered": "COUNTERS",
    "perfect": "PERFECT",
    "good": "GOOD",
    "dodged": "DODGED",
    "miss": "MISSED",
    "hit": "HIT",
}

var score := 0
var combo := 0
var best_combo := 0
var counts := {
    "perfect": 0, "good": 0, "dodged": 0, "landed": 0, "countered": 0, "miss": 0, "hit": 0
}


func reset() -> void:
    score = 0
    combo = 0
    best_combo = 0
    for key in counts:
        counts[key] = 0


## A note was met ("perfect", "good" or "dodged"), or a punch landed
## ("landed", "countered").
func met(how: String) -> void:
    counts[how] += 1
    combo += 1
    best_combo = maxi(best_combo, combo)
    score += POINTS[how] * multiplier()


## A note was missed ("miss"), or an attack or an obstacle hit him ("hit").
## Points besides the judgements (smashing a barrier, see Barriers), which
## neither count for the accuracy nor the combo.
func bonus(points: int) -> void:
    score += points


func failed(how: String) -> void:
    counts[how] += 1
    combo = 0


func multiplier() -> int:
    return mini(MULTIPLIER_MOST, 1 + combo / COMBO_STEP)


## The share of the notes met, a GOOD counting a little less.
func accuracy() -> float:
    var total := 0
    for key in counts:
        total += counts[key]
    var met_notes: float = (
        counts["perfect"]
        + GOOD_SHARE * counts["good"]
        + counts["dodged"]
        + counts["landed"]
        + counts["countered"]
    )
    return met_notes / maxf(1.0, total)


func grade() -> String:
    var share := accuracy()
    for step in GRADES:
        if share >= step[0]:
            return step[1]
    return "D"


## The lines of the results.
func lines() -> Array:
    return [
        "SCORE %d   GRADE %s" % [score, grade()],
        _counts_line(),
        "BEST COMBO %d" % best_combo,
    ]


## The accuracy and the counts which happened (always the dodged and the hits).
func _counts_line() -> String:
    var parts := PackedStringArray(["%d%%" % roundi(accuracy() * 100.0)])
    for key in NAMES:
        if counts[key] > 0 or key in ["dodged", "hit"]:
            parts.append("%s %d" % [NAMES[key], counts[key]])
    return "   ".join(parts)
