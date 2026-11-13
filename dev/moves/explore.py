"""
Draw the signals of a recording of moves over time, to look for the moves by
eye (e.g., in a free recording without calls, replayed with dev/replay/).

The panels, each over the same time:

* the eyes against their median height, in units (down is positive): the bob
  of walking, the ducks and the jumps;
* the knees: how much higher the left knee is than the right one, in thighs
  (walking in place alternates it; a knee strike is a big peak);
* the rhythm: the strongest frequency of the bob of the eyes and of the
  knees in a sliding window of 2 s, and the amplitude of the knees;
* the turn: the width of the shoulders and of the hips over the torso, the
  signed difference of the shoulders in x, the nose against the middle of the
  shoulders, and the scores of the ears and of the shoulders (left minus
  right);
* the fists: how much each grew within 0.15 s (straights), and the wrists
  against the shoulders, in torsos (x and y);
* the scores of the knees and the ankles.

Needs numpy and pillow:

  python dev/moves/explore.py <recording.jsonl> <out.png> [--from=<s>] [--to=<s>]
"""

import argparse
import json
import pathlib

import numpy as np
from PIL import Image, ImageDraw

NOSE, L_EYE, R_EYE, L_EAR, R_EAR = 0, 1, 2, 3, 4
L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_WRIST, R_WRIST = 5, 6, 7, 8, 9, 10
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE = 11, 12, 13, 14, 15, 16

COLORS = ["#d62728", "#1f77b4", "#2ca02c", "#ff7f0e", "#9467bd", "#8c564b", "#e377c2"]


def load(path):
    rows = [json.loads(line) for line in pathlib.Path(path).read_text().splitlines() if line]
    faces = [r for r in rows if r["kind"] == "face"]
    poses = [r for r in rows if r["kind"] == "pose" and r.get("pose") is not None]
    marks = [r for r in rows if r["kind"] == "mark"]
    return faces, poses, marks


def pose_signals(poses, threshold=0.4):
    t = np.array([p["t"] for p in poses])
    k = np.array([np.array(p["pose"]).reshape(17, 3) for p in poses])

    def point(i):
        xy = k[:, i, :2].copy()
        xy[k[:, i, 2] < threshold] = np.nan
        return xy

    ls, rs, lh, rh = point(L_SHOULDER), point(R_SHOULDER), point(L_HIP), point(R_HIP)
    lk, rk, nose = point(L_KNEE), point(R_KNEE), point(NOSE)
    lw, rw = point(L_WRIST), point(R_WRIST)
    mid_s, mid_h = (ls + rs) / 2, (lh + rh) / 2
    torso = np.hypot(*(mid_s - mid_h).T)
    torso_ref = np.nanmedian(torso)
    thigh = np.nanmedian(np.concatenate([lk[:, 1] - lh[:, 1], rk[:, 1] - rh[:, 1]]))
    score = k[:, :, 2]
    return t, {
        "knee L above R (thighs)": (rk[:, 1] - lk[:, 1]) / thigh,
        "shoulder width / torso": np.hypot(*(ls - rs).T) / torso,
        "hip width / torso": np.hypot(*(lh - rh).T) / torso,
        "shoulders dx / torso": (ls[:, 0] - rs[:, 0]) / torso,
        "nose - shoulders / torso": (nose[:, 0] - mid_s[:, 0]) / torso,
        "shoulders - hips / torso": (mid_s[:, 0] - mid_h[:, 0]) / torso,
        "ear score L-R": score[:, L_EAR] - score[:, R_EAR],
        "shoulder score L-R": score[:, L_SHOULDER] - score[:, R_SHOULDER],
        "L wrist - L shoulder x": (lw[:, 0] - ls[:, 0]) / torso_ref,
        "R wrist - R shoulder x": (rw[:, 0] - rs[:, 0]) / torso_ref,
        "L wrist - L shoulder y": (lw[:, 1] - ls[:, 1]) / torso_ref,
        "R wrist - R shoulder y": (rw[:, 1] - rs[:, 1]) / torso_ref,
        "score L knee": score[:, L_KNEE],
        "score R knee": score[:, R_KNEE],
        "score L ankle": score[:, L_ANKLE],
        "score R ankle": score[:, R_ANKLE],
        "hips y / torso": (mid_h[:, 1] - np.nanmedian(mid_h[:, 1])) / torso_ref,
    }


def face_signals(faces):
    t = np.array([f["t"] for f in faces])
    gauge = np.array([[np.nan if v is None else v for v in f["gauge"]] for f in faces], float)
    eyes = (gauge[:, 1] - np.nanmedian(gauge[:, 1])) / np.nanmedian(gauge[:, 2])
    signals = {"eyes below median (units)": eyes}
    for side in ("left", "right"):
        hand = np.array([f[side] if f.get(side) is not None else [np.nan] * 3 for f in faces], float)
        growth = np.full(len(t), np.nan)
        j = 0
        for i in range(len(t)):
            while t[i] - t[j] > 0.15:
                j += 1
            segment = hand[j : i + 1, 2]
            if not np.isnan(hand[i, 2]) and np.any(~np.isnan(segment)):
                growth[i] = hand[i, 2] / np.nanmin(segment)
        signals[f"{side} fist growth in 0.15 s"] = growth
    face = np.array([f["face"] if f.get("face") is not None else [np.nan] * 14 for f in faces], float)
    eyes_mid = (face[:, 4:6] + face[:, 6:8]) / 2
    signals["face yaw (nose - eyes)"] = (face[:, 8] - eyes_mid[:, 0]) / np.hypot(*(face[:, 4:6] - face[:, 6:8]).T)
    return t, signals


def rhythm(t, values, window=2.0, low=0.5, high=4.0, rate=15.0):
    """The strongest frequency and the amplitude in a sliding window, sampled every 0.25 s."""
    centers, frequencies, amplitudes = [], [], []
    mask = ~np.isnan(values)
    t, values = t[mask], values[mask]
    if len(t) < 10:
        return np.array([]), np.array([]), np.array([])
    for center in np.arange(t[0] + window / 2, t[-1] - window / 2, 0.25):
        m = (t >= center - window / 2) & (t < center + window / 2)
        if m.sum() < 8:
            continue
        grid = np.arange(center - window / 2, center + window / 2, 1.0 / rate)
        v = np.interp(grid, t[m], values[m])
        v = v - np.polyval(np.polyfit(grid, v, 1), grid)
        spectrum = np.abs(np.fft.rfft(v * np.hanning(len(v)), n=256))
        f = np.fft.rfftfreq(256, 1.0 / rate)
        band = (f >= low) & (f <= high)
        centers.append(center)
        frequencies.append(f[band][np.argmax(spectrum[band])])
        amplitudes.append(np.std(v))
    return np.array(centers), np.array(frequencies), np.array(amplitudes)


class Sheet:
    """A tall picture of panels which share the time axis."""

    def __init__(self, start, end, panels, width=2400, height=170):
        self.start, self.end = start, end
        self.width, self.height = width, height
        self.left = 230
        self.image = Image.new("RGB", (width, height * panels + 40), "white")
        self.draw = ImageDraw.Draw(self.image)
        self.row = 0

    def x(self, t):
        return self.left + (t - self.start) / (self.end - self.start) * (self.width - self.left - 20)

    def panel(self, title, series, marks=(), fixed=None):
        top = 30 + self.row * self.height
        bottom = top + self.height - 25
        self.row += 1
        values = np.concatenate([v[~np.isnan(v)] for _, _, v in series if len(v)]) if series else []
        if fixed is not None:
            low, high = fixed
        elif len(values):
            low, high = np.percentile(values, 1), np.percentile(values, 99)
        else:
            low, high = 0, 1
        if high - low < 1e-6:
            high = low + 1
        span = high - low
        low, high = low - 0.05 * span, high + 0.05 * span

        def y(v):
            return bottom - (v - low) / (high - low) * (bottom - top)

        self.draw.rectangle([self.left, top, self.width - 20, bottom], outline="#999999")
        self.draw.text((8, top + 2), title, fill="black")
        self.draw.text((self.left - 60, top), f"{high:.2f}", fill="#666666")
        self.draw.text((self.left - 60, bottom - 12), f"{low:.2f}", fill="#666666")
        if low < 0 < high:
            self.draw.line([self.left, y(0), self.width - 20, y(0)], fill="#dddddd")
        for second in range(int(self.start), int(self.end) + 1):
            if second % 5 == 0:
                self.draw.line([self.x(second), top, self.x(second), bottom], fill="#eeeeee")
                if self.row == 1:
                    self.draw.text((self.x(second) - 8, 12), f"{second}", fill="black")
        for m in marks:
            self.draw.line([self.x(m["t"]), top, self.x(m["t"]), bottom], fill="#ffaaaa")
        for i, (name, t, v) in enumerate(series):
            color = COLORS[i % len(COLORS)]
            self.draw.text((8, top + 16 + 14 * i), name, fill=color)
            previous = None
            for tt, vv in zip(t, v):
                if np.isnan(vv) or tt < self.start or tt > self.end:
                    previous = None
                    continue
                point = (self.x(tt), y(min(max(vv, low), high)))
                if previous is not None:
                    self.draw.line([previous, point], fill=color, width=2)
                previous = point


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recording")
    parser.add_argument("out")
    parser.add_argument("--from", dest="start", type=float)
    parser.add_argument("--to", dest="end", type=float)
    args = parser.parse_args()

    faces, poses, marks = load(args.recording)
    ft, fs = face_signals(faces)
    pt, ps = pose_signals(poses)
    t0 = ft[0]
    ft, pt = ft - t0, pt - t0
    for m in marks:
        m["t"] -= t0
    start = args.start if args.start is not None else 0.0
    end = args.end if args.end is not None else max(ft[-1], pt[-1] if len(pt) else 0)

    ht, hf, ha = rhythm(ft, fs["eyes below median (units)"])
    kt, kf, ka = rhythm(pt, ps["knee L above R (thighs)"], low=0.3, high=3.0)

    sheet = Sheet(start, end, 9)
    sheet.panel("eyes below median (units)", [("eyes", ft, fs["eyes below median (units)"])], marks)
    sheet.panel("knees", [("knee L above R (thighs)", pt, ps["knee L above R (thighs)"]),
                          ("hips y / torso", pt, ps["hips y / torso"])], marks)
    sheet.panel("rhythm (Hz)", [("head bob Hz", ht, hf), ("knees Hz", kt, kf)], marks, fixed=(0, 4))
    sheet.panel("rhythm amplitude", [("head bob (units)", ht, ha), ("knees (thighs)", kt, ka)], marks)
    sheet.panel("turn: widths", [(n, pt, ps[n]) for n in ("shoulder width / torso", "hip width / torso")], marks)
    sheet.panel(
        "turn: signed",
        [(n, pt, ps[n]) for n in ("shoulders dx / torso", "nose - shoulders / torso", "shoulders - hips / torso")]
        + [("face yaw (nose - eyes)", ft, fs["face yaw (nose - eyes)"])],
        marks,
    )
    sheet.panel("turn: scores", [(n, pt, ps[n]) for n in ("ear score L-R", "shoulder score L-R")], marks)
    sheet.panel(
        "fists",
        [(n, ft, fs[n]) for n in ("left fist growth in 0.15 s", "right fist growth in 0.15 s")]
        + [(n, pt, ps[n]) for n in ("L wrist - L shoulder x", "R wrist - R shoulder x",
                                     "L wrist - L shoulder y", "R wrist - R shoulder y")],
        marks,
    )
    sheet.panel("scores", [(n, pt, ps[n]) for n in ("score L knee", "score R knee", "score L ankle", "score R ankle")],
                marks, fixed=(0, 1))
    sheet.image.save(args.out)
    print(f"Wrote {args.out}: {len(ft)} face frames, {len(pt)} poses over {end - start:.0f} s")


if __name__ == "__main__":
    main()
