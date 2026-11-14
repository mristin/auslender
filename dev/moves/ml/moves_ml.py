"""Train and evaluate a move classifier on the top-down poses of a labelled recording.

Kept deliberately simple, so that the features can be ported to C# exactly:

* the pose stream is resampled at fixed time offsets (0, 0.05, ..., 0.4 s back),
  by linear interpolation, so the frame rate does not matter;
* every sample is expressed relative to the middle of the shoulders *now*, in
  units of the body scale: the median torso length (mid-shoulders to mid-hips)
  over the last 2 s; so the features are scale invariant.
"""

import json
import sys

import numpy as np

# COCO: nose, shoulders, elbows, wrists, hips, knees, ankles
POINTS = [0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
# NOTE: swap left and right when mirroring
MIRROR = {
    0: 0,
    5: 6,
    6: 5,
    7: 8,
    8: 7,
    9: 10,
    10: 9,
    11: 12,
    12: 11,
    13: 14,
    14: 13,
    15: 16,
    16: 15,
}
OFFSETS = np.arange(0, 9) * 0.05  # seconds back
SCALE_HISTORY = 2.0

CLASSES = [
    "none",
    "straight_left",
    "straight_right",
    "hook_left",
    "hook_right",
    "uppercut_left",
    "uppercut_right",
    "kick_left",
    "kick_right",
    "duck",
    "jump",
    "slip_left",
    "slip_right",
    "cover",
]


def mirror_class(name):
    if name.endswith("_left"):
        return name[:-5] + "_right"
    if name.endswith("_right"):
        return name[:-6] + "_left"
    return name


def load(recording, poses_path):
    rows = [json.loads(l) for l in open(recording)]
    marks = [(r["t"], r["name"][5:], r["label"]) for r in rows if r["kind"] == "mark"]
    steps = {}
    for r in rows:
        if r.get("label"):
            a = steps.setdefault(r["label"], [r["t"], r["t"]])
            a[1] = r["t"]
    ps = [json.loads(l) for l in open(poses_path)]
    t = np.array([p["t"] for p in ps])
    k = np.array([p["pose"] for p in ps], dtype=np.float64).reshape(-1, 17, 3)
    return t, k, marks, steps


# ---------------------------------------------------------------- features


def torso(k):
    sh = (k[..., 5, :2] + k[..., 6, :2]) / 2
    hip = (k[..., 11, :2] + k[..., 12, :2]) / 2
    return sh, np.linalg.norm(sh - hip, axis=-1)


def body_scales(t, k):
    """The median torso length over the last SCALE_HISTORY seconds, per frame."""
    _, length = torso(k)
    out = np.empty(len(t))
    start = 0
    for i in range(len(t)):
        while t[start] < t[i] - SCALE_HISTORY:
            start += 1
        out[i] = np.median(length[start : i + 1])
    return out


def interpolate(t, k, at):
    """The poses at the times `at` (clamped to the stream), linearly interpolated."""
    at = np.clip(at, t[0], t[-1])
    j = np.searchsorted(t, at, side="right") - 1
    j = np.clip(j, 0, len(t) - 2)
    w = ((at - t[j]) / np.maximum(t[j + 1] - t[j], 1e-6)).clip(0, 1)
    return k[j] * (1 - w)[:, None, None] + k[j + 1] * w[:, None, None]


def features(t, k, scales, i):
    """The feature vector of frame i (looking back over OFFSETS)."""
    window = interpolate(t, k, t[i] - OFFSETS)  # [9, 17, 3]
    sh_now = (k[i, 5, :2] + k[i, 6, :2]) / 2
    rel = (window[:, POINTS, :2] - sh_now) / scales[i]  # [9, 13, 2]
    score = window[:, [9, 10], 2].min(axis=0)  # wrists' confidence over the window
    return np.concatenate([rel.ravel(), score])


FEATURE_COUNT = len(OFFSETS) * len(POINTS) * 2 + 2


def all_features(t, k):
    scales = body_scales(t, k)
    return np.array([features(t, k, scales, i) for i in range(len(t))], dtype=np.float32)


# ---------------------------------------------------------------- augmentation


def augment(k, rng, scale=None, child=None, jitter=1.5):
    """A whole stream, with one random body: size, place, child-like proportions, jitter.

    The scale wobbles slightly from frame to frame (as the size of a detected
    body does), and every keypoint jitters by `jitter` pixels.
    """
    k = k.copy()
    s = scale if scale is not None else rng.uniform(0.5, 1.3)
    if child is None:
        child = rng.random() < 0.5
    limbs = rng.uniform(0.8, 0.95) if child else rng.uniform(0.95, 1.05)  # children: shorter limbs
    head = rng.uniform(1.1, 1.3) if child else rng.uniform(0.95, 1.05)  # children: a bigger head
    xy = k[..., :2]
    sh = (xy[:, 5] + xy[:, 6]) / 2
    hip = (xy[:, 11] + xy[:, 12]) / 2
    # limbs: scale each segment and re-chain from the shoulder / hip
    for a, b, c in ((5, 7, 9), (6, 8, 10), (11, 13, 15), (12, 14, 16)):
        upper = xy[:, b] - xy[:, a]
        lower = xy[:, c] - xy[:, b]
        xy[:, b] = xy[:, a] + upper * limbs
        xy[:, c] = xy[:, b] + lower * limbs
    xy[:, 0] = sh + (xy[:, 0] - sh) * head
    centre = hip.mean(axis=0)
    shift = rng.uniform(-80, 80, size=2)
    wobble = s * (1.0 + np.convolve(rng.normal(0, 0.01, len(xy)), np.ones(5) / 5, mode="same"))
    xy[:] = (xy - centre) * wobble[:, None, None] + centre + shift
    # NOTE: jitter in pixels, so a small (child-sized or far) body is relatively noisier
    xy += rng.normal(0, jitter, size=xy.shape)
    return k


def mirror(k, width=640.0):
    m = k.copy()
    for a, b in MIRROR.items():
        m[:, a] = k[:, b]
    m[..., 0] = width - m[..., 0]
    # the 4 face points we do not use stay as they are
    return m


# ---------------------------------------------------------------- labels


def label_frames(t, k, marks, steps):
    """Per frame: the class index, the event id (or -1), and the repetition index for the split."""
    y = np.full(len(t), -1)  # -1: unlabelled, ignored
    event = np.full(len(t), -1)
    fold = np.full(len(t), -1)
    events = []

    sh = (k[:, 5, :2] + k[:, 6, :2]) / 2
    hip = (k[:, 11, :2] + k[:, 12, :2]) / 2
    _, length = torso(k)
    scale = np.median(length)

    def window(a, b):
        return np.where((t >= a) & (t <= b))[0]

    def peak_wrist(side, a, b):
        w = 9 if side == "left" else 10
        idx = window(a, b)
        rest = k[idx[0], w, :2] - sh[idx[0]]
        d = np.linalg.norm((k[idx, w, :2] - sh[idx]) - rest, axis=1)
        return t[idx[np.argmax(d)]]

    # static steps: none, split into 5 time chunks for the folds
    for name in ("stand 1", "guard", "look around", "stand 2"):
        if name not in steps:
            continue
        a, b = steps[name]
        idx = window(a + 0.5, b - 0.2)
        y[idx] = 0
        fold[idx] = np.arange(len(idx)) * 5 // len(idx)

    count = {}
    calls = [(tc, n, lab) for tc, n, lab in marks]
    for ci, (tc, n, lab) in enumerate(calls):
        rep = count.get(lab, 0)
        count[lab] = rep + 1
        nxt = calls[ci + 1][0] if ci + 1 < len(calls) and calls[ci + 1][2] == lab else steps[lab][1]
        anchors = []
        if n in ("cover", "guard"):
            idx = window(tc + 0.6, nxt - 0.1)
            y[idx] = CLASSES.index("cover") if n == "cover" else 0
            fold[idx] = rep // 2 % 5
            continue
        if n.startswith(("straight_", "hook_", "uppercut_")):
            side = n.rsplit("_", 1)[1]
            anchors.append((n, peak_wrist(side, tc + 0.15, tc + 1.5)))
        elif n == "one_two":
            pl = peak_wrist("left", tc + 0.1, tc + 1.2)
            pr = peak_wrist("right", pl + 0.1, pl + 1.0)
            anchors += [("straight_left", pl), ("straight_right", pr)]
        elif n.startswith("front_kick_"):
            # NOTE: a kick is a knee raised high; the camera need not see the whole leg
            side = n.rsplit("_", 1)[1]
            kn, hp = (13, 11) if side == "left" else (14, 12)
            idx = window(tc + 0.15, tc + 1.8)
            anchors.append(("kick_" + side, t[idx[np.argmin(k[idx, kn, 1] - k[idx, hp, 1])]]))
        elif n == "duck":
            idx = window(tc + 0.15, tc + 1.8)
            anchors.append(("duck", t[idx[np.argmax(k[idx, 0, 1])]]))
        elif n == "jump":
            idx = window(tc + 0.15, tc + 1.8)
            feet = (k[idx, 15, 1] + k[idx, 16, 1]) / 2
            anchors.append(("jump", t[idx[np.argmin(feet)]]))
        elif n.startswith("slip_"):
            idx = window(tc + 0.15, tc + 1.8)
            off = (k[idx, 0, 0] - hip[idx, 0]) / scale
            # NOTE: the picture is not mirrored: the player's left is the picture's right
            anchors.append((n, t[idx[np.argmax(off if n == "slip_left" else -off)]]))
        for cls, at in anchors:
            eid = len(events)
            events.append({"class": cls, "t": at, "fold": rep % 5, "call": tc})
            idx = window(at - 0.05, at + 0.15)
            y[idx] = CLASSES.index(cls)
            event[idx] = eid
            fold[idx] = rep % 5
        # the rest of a move step, away from the move: none
        if anchors:
            idx = window(tc - 0.2, nxt - 0.1)
            far = np.ones(len(idx), bool)
            for _, at in anchors:
                far &= np.abs(t[idx] - at) > 0.6
            sel = idx[far & (y[idx] == -1)]
            y[sel] = 0
            fold[sel] = rep % 5
    return y, event, fold, events


if __name__ == "__main__":
    t, k, marks, steps = load(sys.argv[1], sys.argv[2])
    y, event, fold, events = label_frames(t, k, marks, steps)
    import collections

    print(collections.Counter(CLASSES[c] for c in y if c >= 0))
    print(len(events), "events")


def sequences(t, k, offsets):
    """[N, T, 26] oldest first, relative to the shoulders now, in body scales; plus [N, 2] wrist scores.

    The reference of scenes/vision/core/MoveFeatures.cs: the features of
    frame i are seq[i].ravel() followed by score[i].
    """
    scales = body_scales(t, k)
    at = (t[:, None] - offsets[None, :]).ravel()
    w = interpolate(t, k, at).reshape(len(t), len(offsets), 17, 3)
    sh = (k[:, 5, :2] + k[:, 6, :2]) / 2
    rel = (w[:, :, POINTS, :2] - sh[:, None, None, :]) / scales[:, None, None, None]
    seq = rel.reshape(len(t), len(offsets), -1)[:, ::-1].astype(np.float32)
    score = w[:, :, [9, 10], 2].min(axis=1).astype(np.float32)
    return seq, score
