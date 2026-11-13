"""
Study a recording of moves made with dev/moves/record_moves.gd, and infer the
rules which tell the moves apart.

For every kind of move which the plan calls (the straights, the hooks and the
uppercuts of each hand, the kicks of each leg, the ducks and the jumps), we
compute a few candidate measures on the raw numbers of the vision (the head,
the hands and the pose, in the unit of the player), take their peaks in the
moment after each call (the positives) and in windows of the steps where the
player did something else (the negatives), and pick, for each measure, the
threshold which separates them best. We also report how the detectors of the
game did: what they found after each call, and what they found where nothing
was called (the false alarms).

For the walking in place, we measure the rhythm of the steps (from the bob of
the head on every frame, and from the knees and the ankles of the pose) in
windows, and compare standing, walking slowly and walking fast. For the
turns, we compare a dozen measures of the posture while the player faces the
camera, is turned to her left, and to her right, and rank them by how well
they tell the three apart.

Run with numpy (and matplotlib for --plot):

  python dev/moves/analyze.py <recording.jsonl> [--plot out.png]
"""

import argparse
import collections
import json
import pathlib
import sys

import numpy as np

# The key points of the pose, as in Pose.cs; left and right are the player's.
NOSE, L_EYE, R_EYE, L_EAR, R_EAR = 0, 1, 2, 3, 4
L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_WRIST, R_WRIST = 5, 6, 7, 8, 9, 10
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE = 11, 12, 13, 14, 15, 16

THRESHOLD = 0.4

# A move is looked for this long after its call, in seconds.
AFTER_CALL = 1.3

# The windows of the negatives, in seconds.
WINDOW = 1.3

# The steps where the player moves freely, which are neither positive nor negative.
MIXED = {"combos", "free", "walk and punch", ""}


def load(path):
    rows = [json.loads(line) for line in pathlib.Path(path).read_text().splitlines() if line]
    by_kind = collections.defaultdict(list)
    for row in rows:
        by_kind[row["kind"]].append(row)
    return by_kind


def steps_of(rows):
    """The steps in the order of the recording, as (label, start, end)."""
    steps = []
    for row in rows:
        label = row["label"]
        if not steps or steps[-1][0] != label:
            steps.append([label, row["t"], row["t"]])
        steps[-1][2] = row["t"]
    return [tuple(step) for step in steps]


# ---------------------------------------------------------------------------
# The measures


class Face:
    """The face frames as arrays: the time, the eyes, the unit and the hands."""

    def __init__(self, faces):
        self.t = np.array([f["t"] for f in faces])
        self.label = [f["label"] for f in faces]
        gauge = np.array([[np.nan if v is None else v for v in f["gauge"]] for f in faces], float)
        self.x, self.y, self.unit = gauge[:, 0], gauge[:, 1], gauge[:, 2]
        self.hands = {}
        for side in ("left", "right"):
            self.hands[side] = np.array(
                [f[side] if f.get(side) is not None else [np.nan] * 3 for f in faces], float
            )
        self.face = np.array(
            [f["face"] if f.get("face") is not None else [np.nan] * 14 for f in faces], float
        )
        self.headbox = np.array(
            [f["head"] if f.get("head") is not None else [np.nan] * 4 for f in faces], float
        )


class Body:
    """The poses as arrays: the time and the key points (x, y, score)."""

    def __init__(self, poses):
        poses = [p for p in poses if p.get("pose") is not None]
        self.t = np.array([p["t"] for p in poses])
        self.label = [p["label"] for p in poses]
        self.k = np.array([np.array(p["pose"]).reshape(17, 3) for p in poses])

    def point(self, index):
        """The key point over time, NaN where it is not confident."""
        xy = self.k[:, index, :2].copy()
        xy[self.k[:, index, 2] < THRESHOLD] = np.nan
        return xy

    def torso(self):
        """The length from the middle of the shoulders to the middle of the hips: a unit which turning does not shrink."""
        shoulders = (self.point(L_SHOULDER) + self.point(R_SHOULDER)) / 2
        hips = (self.point(L_HIP) + self.point(R_HIP)) / 2
        return np.hypot(*(shoulders - hips).T)


def window_peak(t, values, start, end):
    """The highest value within [start, end], or NaN."""
    mask = (t >= start) & (t <= end) & ~np.isnan(values)
    return float(np.max(values[mask])) if mask.any() else np.nan


def punch_measures(face, side):
    """
    For each face frame, how much the fist grew (straight), swung across
    (hook) and rose (uppercut) within the last 0.15 s, in units.
    """
    hand = face.hands[side]
    n = len(face.t)
    growth = np.full(n, np.nan)
    across = np.full(n, np.nan)
    rise = np.full(n, np.nan)
    sign = -1.0 if side == "left" else 1.0
    j = 0
    for i in range(n):
        while face.t[i] - face.t[j] > 0.15:
            j += 1
        segment = hand[j : i + 1]
        if np.isnan(hand[i]).any() or np.all(np.isnan(segment[:, 2])):
            continue
        unit = face.unit[i]
        growth[i] = hand[i, 2] / np.nanmin(segment[:, 2])
        first = segment[~np.isnan(segment[:, 0])][0]
        # NOTE (mristin):
        # In the not mirrored frame, the player's right is to the left: the left
        # fist swings across towards smaller x.
        across[i] = sign * (hand[i, 0] - first[0]) / unit
        rise[i] = (np.nanmax(segment[:, 1]) - hand[i, 1]) / unit
    return {"growth": growth, "across": across, "rise": rise}


def leg_measures(body):
    """For each pose, how much higher each ankle (or knee) is than the other, in torsos."""
    torso = body.torso()
    torso = np.where(np.isnan(torso), np.nanmedian(torso), torso)
    la, ra = body.point(L_ANKLE)[:, 1], body.point(R_ANKLE)[:, 1]
    lk, rk = body.point(L_KNEE)[:, 1], body.point(R_KNEE)[:, 1]
    lift_left = (ra - la) / torso
    lift_right = (la - ra) / torso
    lh_y, rh_y = body.point(L_HIP)[:, 1], body.point(R_HIP)[:, 1]
    thigh_left = np.nanpercentile(lk - lh_y, 90) if np.any(~np.isnan(lk - lh_y)) else np.nan
    thigh_right = np.nanpercentile(rk - rh_y, 90) if np.any(~np.isnan(rk - rh_y)) else np.nan
    # NOTE (mristin):
    # As in the game: how much higher the knee is than the other, in thighs.
    knee_left = (rk - lk) / thigh_left
    knee_right = (lk - rk) / thigh_right
    lhx, rhx = body.point(L_HIP)[:, 0], body.point(R_HIP)[:, 0]
    out_left = np.abs(body.point(L_ANKLE)[:, 0] - lhx) / torso
    out_right = np.abs(body.point(R_ANKLE)[:, 0] - rhx) / torso
    both_up = -(np.fmax(la, ra) - np.nanmedian(np.fmax(la, ra))) / torso
    return {
        "lift_left": lift_left,
        "lift_right": lift_right,
        "knee_left": knee_left,
        "knee_right": knee_right,
        "out_left": out_left,
        "out_right": out_right,
        "feet_up": both_up,
    }


# ---------------------------------------------------------------------------
# The stumps


def best_threshold(positives, negatives):
    """The threshold (higher is the move) which separates best, with its hit rate and false-alarm rate."""
    positives = np.array([p for p in positives if not np.isnan(p)])
    negatives = np.array([n for n in negatives if not np.isnan(n)])
    if len(positives) == 0 or len(negatives) == 0:
        return None
    candidates = np.unique(np.concatenate([positives, negatives]))
    best = None
    for c in candidates:
        tpr = np.mean(positives >= c)
        fpr = np.mean(negatives >= c)
        score = tpr - fpr
        if best is None or score > best[0] + 1e-9:
            best = (score, c, tpr, fpr)
    _, c, tpr, fpr = best
    # NOTE (mristin):
    # Between the found threshold and the next negative below, for a margin.
    below = negatives[negatives < c]
    if len(below):
        c = (c + below.max()) / 2
    return c, tpr, fpr, len(positives), len(negatives)


def negative_windows(steps, excluded):
    for label, start, end in steps:
        if label in MIXED or label in excluded:
            continue
        at = start + 0.5
        while at + WINDOW <= end:
            yield label, at, at + WINDOW
            at += WINDOW


def report_stumps(title, measures, calls, steps, excluded):
    """Print, for each measure, the peaks after the calls against the peaks of the negatives."""
    print(f"\n{title}  ({len(calls)} calls)")
    if not calls:
        print("  no calls in the recording")
        return
    for name, (t, values) in measures.items():
        positives = [window_peak(t, values, c, c + AFTER_CALL) for c in calls]
        negatives = []
        worst = collections.Counter()
        for label, a, b in negative_windows(steps, excluded):
            negatives.append(window_peak(t, values, a, b))
        found = best_threshold(positives, negatives)
        if found is None:
            print(f"  {name:12s} not enough data")
            continue
        c, tpr, fpr, np_, nn = found
        for label, a, b in negative_windows(steps, excluded):
            if window_peak(t, values, a, b) >= c:
                worst[label] += 1
        offenders = ", ".join(f"{k} {v}" for k, v in worst.most_common(3))
        pos = np.array([p for p in positives if not np.isnan(p)])
        print(
            f"  {name:12s} threshold {c:7.3f}: hits {tpr:5.0%} of {np_}, false alarms {fpr:5.0%}"
            f" of {nn} windows; peaks after calls: median {np.median(pos):.3f},"
            f" min {pos.min():.3f}" + (f"; false alarms in: {offenders}" if offenders else "")
        )


# ---------------------------------------------------------------------------
# The rhythm of the steps


def dominant_frequency(t, values, low=0.5, high=4.0):
    """The strongest frequency (Hz) of the values within the band, and its amplitude (std)."""
    mask = ~np.isnan(values)
    if mask.sum() < 8:
        return np.nan, np.nan
    t, values = t[mask], values[mask]
    if t[-1] - t[0] < 1.0:
        return np.nan, np.nan
    rate = 20.0
    grid = np.arange(t[0], t[-1], 1.0 / rate)
    resampled = np.interp(grid, t, values)
    resampled = resampled - np.polyval(np.polyfit(grid, resampled, 1), grid)
    spectrum = np.abs(np.fft.rfft(resampled * np.hanning(len(resampled))))
    frequencies = np.fft.rfftfreq(len(resampled), 1.0 / rate)
    band = (frequencies >= low) & (frequencies <= high)
    if not band.any():
        return np.nan, np.nan
    return float(frequencies[band][np.argmax(spectrum[band])]), float(np.std(resampled))


def states_from_calls(marks, steps, label, names):
    """Split the step into states by its calls: (state, start, end), the state before the first call being 'facing'."""
    step = [s for s in steps if s[0] == label]
    if not step:
        return []
    _, start, end = step[0]
    calls = [(m["t"], m["name"].removeprefix("call:")) for m in marks if m["label"] == label]
    result = []
    state, since = names.get("", "facing"), start + 0.5
    for t, name in calls:
        result.append((state, since, t))
        state, since = names.get(name, name), t + 1.0
    result.append((state, since, end))
    return [(s, a, b) for s, a, b in result if b - a > 0.5]


def report_gait(face, body, steps, marks):
    print("\nWALKING IN PLACE  (windows of 2 s; the head bob in units, the knees in torsos)")
    eyes_down = face.y / face.unit
    legs = leg_measures(body)
    knees = legs["knee_left"]
    ankles = legs["lift_left"]

    segments = []
    for label in ("stand 1", "look around", "twist", "walk slow", "walk fast", "turn left", "turn right"):
        for name, a, b in [s for s in steps if s[0] == label]:
            state = "walking" if label.startswith("walk") else "standing"
            segments.append((f"{label} ({state})", a + 0.5, b))
    walk_names = {"": "standing", "start_walking": "walking", "stop": "standing"}
    for state, a, b in states_from_calls(marks, steps, "walk stop", walk_names):
        segments.append((f"walk stop ({state})", a, b))
    turn_names = {"": "walking", "turn_left": "walking", "turn_right": "walking", "face_camera": "walking"}
    for label in ("walk turning left", "walk turning right"):
        for state, a, b in states_from_calls(marks, steps, label, turn_names):
            segments.append((f"{label} ({state})", a, b))

    rows = collections.defaultdict(list)
    for name, a, b in segments:
        at = a
        while at + 2.0 <= b:
            fm = (face.t >= at) & (face.t < at + 2.0)
            bm = (body.t >= at) & (body.t < at + 2.0)
            head_f, head_a = dominant_frequency(face.t[fm], eyes_down[fm])
            knee_f, knee_a = dominant_frequency(body.t[bm], knees[bm], 0.3, 3.0)
            ankle_a = np.nanstd(ankles[bm]) if bm.sum() > 3 else np.nan
            rate = bm.sum() / 2.0
            rows[name].append((head_f, head_a, knee_f, knee_a, ankle_a, rate))
            at += 1.0

    print(
        f"  {'segment':36s} {'n':>3s} {'head Hz':>8s} {'head bob':>9s} {'knee Hz':>8s}"
        f" {'knees':>7s} {'ankles':>7s} {'poses/s':>8s}"
    )
    standing, walking = collections.defaultdict(list), collections.defaultdict(list)
    for name, values in rows.items():
        v = np.array(values, float)
        m = np.nanmedian(v, axis=0)
        print(
            f"  {name:36s} {len(v):3d} {m[0]:8.2f} {m[1]:9.3f} {m[2]:8.2f} {m[3]:7.3f}"
            f" {m[4]:7.3f} {m[5]:8.1f}"
        )
        target = walking if "(walking)" in name else standing
        for i, key in enumerate(("head bob", "knees", "ankles")):
            target[key].extend(v[:, i * 2 + 1 if i < 2 else 4])
    print("  telling walking from standing, by the amplitude in a window of 2 s:")
    for key in ("head bob", "knees", "ankles"):
        found = best_threshold(walking[key], standing[key])
        if found:
            c, tpr, fpr, np_, nn = found
            print(f"    {key:9s} from {c:.3f}: walking {tpr:5.0%} of {np_}, standing {fpr:5.0%} of {nn}")
    slow = [r for n, v in rows.items() if n.startswith("walk slow") for r in v]
    fast = [r for n, v in rows.items() if n.startswith("walk fast") for r in v]
    if slow and fast:
        s, f = np.nanmedian(np.array(slow, float), axis=0), np.nanmedian(np.array(fast, float), axis=0)
        print(
            f"  slow against fast: head {s[0]:.2f} against {f[0]:.2f} Hz (bob {s[1]:.3f} against"
            f" {f[1]:.3f}), knees {s[2]:.2f} against {f[2]:.2f} Hz ({s[3]:.3f} against {f[3]:.3f})"
        )


# ---------------------------------------------------------------------------
# The turns


def turn_measures(face, body):
    """Candidate measures of how the body is turned, each over its own time."""
    torso = body.torso()
    ls, rs = body.point(L_SHOULDER), body.point(R_SHOULDER)
    lh, rh = body.point(L_HIP), body.point(R_HIP)
    nose = body.point(NOSE)
    mid_s, mid_h = (ls + rs) / 2, (lh + rh) / 2
    score = body.k[:, :, 2]
    pose = {
        "shoulder width / torso": np.hypot(*(ls - rs).T) / torso,
        "hip width / torso": np.hypot(*(lh - rh).T) / torso,
        "shoulders dx / torso": (ls[:, 0] - rs[:, 0]) / torso,
        "hips dx / torso": (lh[:, 0] - rh[:, 0]) / torso,
        "nose - shoulders / torso": (nose[:, 0] - mid_s[:, 0]) / torso,
        "shoulders - hips / torso": (mid_s[:, 0] - mid_h[:, 0]) / torso,
        "ear score L - R": score[:, L_EAR] - score[:, R_EAR],
        "eye score L - R": score[:, L_EYE] - score[:, R_EYE],
        "shoulder score L - R": score[:, L_SHOULDER] - score[:, R_SHOULDER],
        "hip score L - R": score[:, L_HIP] - score[:, R_HIP],
        "shoulders dy / torso": (ls[:, 1] - rs[:, 1]) / torso,
    }
    f = face.face
    eyes_mid = (f[:, 4:6] + f[:, 6:8]) / 2
    eye_distance = np.hypot(*(f[:, 4:6] - f[:, 6:8]).T)
    box_mid = (f[:, 0] + f[:, 2]) / 2
    head_mid = (face.headbox[:, 0] + face.headbox[:, 2]) / 2
    head_width = face.headbox[:, 2] - face.headbox[:, 0]
    faces = {
        "face yaw (nose - eyes)": (f[:, 8] - eyes_mid[:, 0]) / eye_distance,
        "eyes - face box": (eyes_mid[:, 0] - box_mid) / (f[:, 2] - f[:, 0]),
        "eyes - head box": (eyes_mid[:, 0] - head_mid) / head_width,
        "eye distance / head": eye_distance / head_width,
    }
    return {**{k: (body.t, v) for k, v in pose.items()}, **{k: (face.t, v) for k, v in faces.items()}}


def report_turns(face, body, steps, marks):
    print("\nTURNS  (each measure: mean and std while facing, turned left, turned right)")
    names = {"": "facing", "face_camera": "facing", "turn_left": "left", "turn_right": "right"}
    segments = []
    for label in ("turn left", "turn right", "walk turning left", "walk turning right"):
        segments += [(s, a, b, label) for s, a, b in states_from_calls(marks, steps, label, names)]
    if not segments:
        print("  no turns in the recording")
        return
    ranked = []
    for name, (t, values) in turn_measures(face, body).items():
        groups = {"facing": [], "left": [], "right": []}
        for state, a, b, _ in segments:
            mask = (t >= a) & (t < b) & ~np.isnan(values)
            groups[state].extend(values[mask])
        stats = {k: (np.mean(v), np.std(v), len(v)) if v else (np.nan, np.nan, 0) for k, v in groups.items()}
        spread = np.sqrt(np.nanmean([s[1] ** 2 for s in stats.values()])) + 1e-9
        separation = min(
            abs(stats["left"][0] - stats["facing"][0]),
            abs(stats["right"][0] - stats["facing"][0]),
        ) / spread
        sign_ok = (stats["left"][0] - stats["facing"][0]) * (stats["right"][0] - stats["facing"][0]) < 0
        ranked.append((separation if sign_ok else separation * 0.25, name, stats, sign_ok))
    ranked.sort(reverse=True)
    for separation, name, stats, sign_ok in ranked:
        cells = "  ".join(f"{k} {m:+.3f}±{s:.3f}" for k, (m, s, n) in stats.items())
        note = "" if sign_ok else "  (no sign: left and right go the same way)"
        print(f"  {name:26s} {separation:5.2f}  {cells}{note}")
    print("  (the first column: how far left and right are from facing, in stds; higher is better)")


# ---------------------------------------------------------------------------
# The detectors of the game


def report_game(moves, marks, steps):
    print("\nTHE GAME'S DETECTORS")
    calls = [(m["t"], m["name"].removeprefix("call:")) for m in marks]
    expected = {
        "straight_left": ("straight", "left"),
        "straight_right": ("straight", "right"),
        "hook_left": ("hook", "left"),
        "hook_right": ("hook", "right"),
        "uppercut_left": ("uppercut", "left"),
        "uppercut_right": ("uppercut", "right"),
        "front_kick_left": ("front_kick", "left"),
        "front_kick_right": ("front_kick", "right"),
        "side_kick_left": ("side_kick", "left"),
        "side_kick_right": ("side_kick", "right"),
        "jump": ("jump", ""),
    }
    outcome = collections.defaultdict(collections.Counter)
    latencies = collections.defaultdict(list)
    for t, name in calls:
        if name not in expected:
            continue
        found = [m for m in moves if t <= m["t"] <= t + AFTER_CALL]
        right = [m for m in found if (m["move"], m["side"]) == expected[name]]
        if right:
            outcome[name]["right"] += 1
            latencies[name].append(right[0]["t"] - t)
        elif found:
            outcome[name]["wrong: " + " ".join(f"{m['side']} {m['move']}" for m in found[:2])] += 1
        else:
            outcome[name]["missed"] += 1
    for name in expected:
        if name in outcome:
            counts = ", ".join(f"{k} {v}" for k, v in outcome[name].most_common())
            latency = f"; after {np.median(latencies[name]):.2f} s" if latencies[name] else ""
            print(f"  {name:18s} {counts}{latency}")

    print("  false alarms where nothing was called:")
    quiet = {"stand 1", "look around", "twist", "walk slow", "walk fast", "walk stop", "turn left",
             "turn right", "walk turning left", "walk turning right", "duck", "stand 2"}
    for label, start, end in steps:
        if label not in quiet:
            continue
        found = collections.Counter(f"{m['side']} {m['move']}".strip() for m in moves if start <= m["t"] <= end)
        if found:
            per_minute = sum(found.values()) / max(1e-6, (end - start) / 60.0)
            print(f"    {label:20s} {per_minute:5.1f}/min: " + ", ".join(f"{k} {v}" for k, v in found.most_common()))


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recording")
    parser.add_argument("--plot", help="Draw the main measures over time into this PNG")
    args = parser.parse_args()

    data = load(args.recording)
    everything = sorted(data["face"] + data["pose"] + data["mark"], key=lambda r: r["t"])
    steps = steps_of([r for r in everything if r["label"] != ""])
    face, body = Face(data["face"]), Body(data["pose"])
    marks, moves = data["mark"], data["move"]

    duration = face.t[-1] - face.t[0] if len(face.t) else 0
    print(f"{args.recording}: {duration:.0f} s, {len(face.t)} face frames ({len(face.t) / max(duration, 1):.1f}/s),"
          f" {len(body.t)} poses ({len(body.t) / max(duration, 1):.1f}/s), {len(marks)} calls, {len(moves)} moves")
    seen = collections.Counter(f["label"] for f in data["face"] if f.get("eyes") is not None)
    for label, start, end in steps:
        frames = sum(1 for f in data["face"] if f["label"] == label)
        print(f"  {label:20s} {end - start:5.1f} s, {frames:4d} face frames, face found in {seen[label] / max(frames, 1):4.0%}")

    def calls_of(*names):
        return [m["t"] for m in marks if m["name"].removeprefix("call:") in names]

    punch_steps = {"straight left", "straight right", "hook left", "hook right", "uppercut left", "uppercut right"}
    kick_steps = {"knee left", "knee right"}
    for side in ("left", "right"):
        measures = {k: (face.t, v) for k, v in punch_measures(face, side).items()}
        for kind in ("straight", "hook", "uppercut"):
            report_stumps(
                f"{kind.upper()} {side.upper()}: the peak of each measure of the {side} fist",
                measures,
                calls_of(f"{kind}_{side}"),
                steps,
                excluded={f"{kind} {side}"},
            )

    legs = leg_measures(body)
    for side in ("left", "right"):
        measures = {k: (body.t, legs[f"{k}_{side}"]) for k in ("lift", "knee", "out")}
        for kind in ("front_kick",):
            report_stumps(
                f"{kind.replace('_', ' ').upper()} {side.upper()}: the peak of the {side} leg (lift: ankles in torsos, knee: in thighs)",
                measures,
                calls_of(f"{kind}_{side}"),
                steps,
                excluded=kick_steps,
            )

    down = face.y - np.nanmedian(face.y[[l == "stand 1" for l in face.label]])
    down = down / face.unit
    report_stumps("DUCK: how far the eyes go below home (in units)", {"down": (face.t, down)},
                  calls_of("duck"), steps, excluded={"duck"})
    report_stumps(
        "JUMP: how far the eyes rise above home (units) and both feet rise (torsos)",
        {"up": (face.t, -down), "feet up": (body.t, legs["feet_up"])},
        calls_of("jump"),
        steps,
        excluded={"jump"},
    )

    report_gait(face, body, steps, marks)
    report_turns(face, body, steps, marks)
    report_game(moves, marks, steps)

    if args.plot:
        plot(args.plot, face, body, steps, marks, legs, down)


def plot(path, face, body, steps, marks, legs, down):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    torso = body.torso()
    ls, rs = body.point(L_SHOULDER), body.point(R_SHOULDER)
    panels = [
        ("eyes below home (units)", face.t, [down]),
        ("fist growth in 0.15 s (L, R)", face.t, [punch_measures(face, s)["growth"] for s in ("left", "right")]),
        ("ankle above the other (L, R; torsos)", body.t, [legs["lift_left"], legs["lift_right"]]),
        ("shoulders dx / torso", body.t, [(ls[:, 0] - rs[:, 0]) / torso]),
    ]
    figure, axes = plt.subplots(len(panels), 1, figsize=(24, 3 * len(panels)), sharex=True)
    t0 = face.t[0]
    for axis, (title, t, series) in zip(axes, panels):
        for values in series:
            axis.plot(t - t0, values, lw=0.8)
        axis.set_title(title, loc="left", fontsize=9)
        for label, a, b in steps:
            axis.axvspan(a - t0, b - t0, alpha=0.06, color="grey")
            axis.text(a - t0, axis.get_ylim()[1], label, fontsize=6, va="top", rotation=90)
        for m in marks:
            axis.axvline(m["t"] - t0, color="red", lw=0.4)
    figure.tight_layout()
    figure.savefig(path, dpi=100)
    print(f"Wrote {path}")


if __name__ == "__main__":
    sys.exit(main())
