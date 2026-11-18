"""Does the frame rate of the camera matter? Train with or without the slow sessions, test at both rates.

python frame_rates.py <recording.jsonl> <poses.jsonl> [...]

The sessions whose camera ran at about 15 frames a second (dim light, see
LinuxCameraControls) are the slow ones; the others are fast (30). For each
session as the test, trained on the other sessions only:

* fast:         the other fast sessions,
* all:          all the other sessions, the slow ones too,
* fast+halved:  the other fast sessions, and copies of them with every other
                frame dropped (as if from a camera at 15 frames a second).

Each fast session is also tested halved, so that we see what a slow camera
costs. To be quick, it augments with fewer copies than export.py (4 sizes
instead of 8, all mirrored); the comparison is fair among the trainings.
"""

import pathlib
import sys

import numpy as np

import cross_session as X
import moves_ml as M

SCALES = [(0.35, 0.7), (0.35, 0.7), (1.3, 1.8), (0.8, 1.2)]
SLOW_FPS = 20.0


class Stream:
    """A session (or a halved one): its times, poses, labels, folds and events."""

    def __init__(self, name, t, k, y, fold, events):
        self.name, self.t, self.k, self.y, self.fold, self.events = name, t, k, y, fold, events
        self.X = X.features(t, k)
        self.scaled = {}

    @property
    def fps(self):
        return (len(self.t) - 1) / (self.t[-1] - self.t[0])

    def halved(self):
        keep = slice(None, None, 2)
        return Stream(
            self.name + " halved",
            self.t[keep],
            self.k[keep],
            self.y[keep],
            self.fold[keep],
            self.events,
        )

    def rows(self, rng):
        """The training rows: the stream, its resized copies, and all of them mirrored."""
        streams = [(self.k, self.y)]
        streams += [
            (M.augment(self.k, rng, scale=rng.uniform(lo, hi)), self.y) for lo, hi in SCALES
        ]
        streams += [(M.mirror(s), X.mirror_labels(l)) for s, l in streams]
        Xs = [X.features(self.t, s)[l >= 0] for s, l in streams]
        Ys = [l[l >= 0] for _, l in streams]
        return np.concatenate(Xs), np.concatenate(Ys)


def load(recording, poses):
    t, k, marks, steps = M.load(recording, poses)
    y, _, fold, events = M.label_frames(t, k, marks, steps, M.load_skips(recording))
    return Stream(pathlib.Path(recording).stem, t, k, y, fold, events)


def main():
    pairs = list(zip(sys.argv[1::2], sys.argv[2::2]))
    sessions = [load(r, p) for r, p in pairs]
    rng = np.random.default_rng(1)
    rows = {s.name: s.rows(rng) for s in sessions}
    halved_rows = {s.name: s.halved().rows(rng) for s in sessions if s.fps > SLOW_FPS}
    for s in sessions:
        print(f"{s.name}: {s.fps:.1f} frames/s, {len(s.events)} moves")

    everything = set(range(5))
    for test in sessions:
        others = [s for s in sessions if s is not test]
        fast = [s.name for s in others if s.fps > SLOW_FPS]
        trainings = {
            "fast": [rows[n] for n in fast],
            "all": [rows[s.name] for s in others],
            "fast+halved": [rows[n] for n in fast] + [halved_rows[n] for n in fast],
        }
        tests = [test] + ([test.halved()] if test.fps > SLOW_FPS else [])
        print(f"\nTest on {test.name} ({test.fps:.0f} frames/s)", flush=True)
        for name, parts in trainings.items():
            model = X.fit(
                np.concatenate([p[0] for p in parts]), np.concatenate([p[1] for p in parts])
            )
            for s in tests:
                label = f"{name:12s} -> {'halved (15/s)' if s is not test else 'as recorded'}"
                X.line(label, [X.evaluate(s, model.predict_proba(s.X), everything)])
            sys.stdout.flush()


if __name__ == "__main__":
    main()
