"""Evaluate the XGBoost move classifier across the recorded sessions.

python cross_session.py <recording.jsonl> <poses.jsonl> [<recording.jsonl> <poses.jsonl> ...]

For each session as the test, it trains:

1. on the other sessions only: how well the model does on a session it has
   never seen (another day, another place of the camera, another player), and
2. on the other sessions plus the other folds of this one (5 folds, each holds
   out one repetition of every move): how much this session adds.

Each also on the session's poses shrunk to the size of a child and enlarged.
The parts in <recording>.skip.csv are left out (see moves_ml.load_skips).
"""

import pathlib
import sys

import numpy as np
import xgboost as xgb

import moves_ml as M

OFFSETS = np.arange(4) * 0.1
SCALES = [(0.35, 0.7)] * 3 + [(1.3, 1.8)] * 3 + [(0.8, 1.2)] * 2
C = len(M.CLASSES)


def mirror_labels(y):
    out = y.copy()
    for i, c in enumerate(y):
        if c > 0:
            out[i] = M.CLASSES.index(M.mirror_class(M.CLASSES[c]))
    return out


def features(t, k):
    seq, score = M.sequences(t, k, OFFSETS)
    return np.hstack([seq.reshape(len(seq), -1), score])


class Session:
    """A recording with its augmented copies for the training and its scaled copies for the test."""

    def __init__(self, recording, poses, seed):
        rng = np.random.default_rng(seed)
        self.name = pathlib.Path(recording).stem
        self.t, self.k, marks, steps = M.load(recording, poses)
        self.y, _, self.fold, self.events = M.label_frames(
            self.t, self.k, marks, steps, M.load_skips(recording)
        )
        streams = [(self.k, self.y)]
        streams += [
            (M.augment(self.k, rng, scale=rng.uniform(lo, hi)), self.y) for lo, hi in SCALES
        ]
        streams += [(M.mirror(s), mirror_labels(l)) for s, l in streams]
        self.train = [(features(self.t, s), l) for s, l in streams]
        self.X = self.train[0][0]
        test_rng = np.random.default_rng(99)
        self.scaled = {
            name: features(self.t, M.augment(self.k, test_rng, scale=scale, child=child))
            for name, scale, child in (("child 0.5x", 0.5, True), ("enlarged 1.5x", 1.5, False))
        }

    def rows(self, exclude_fold=None):
        X, Y = [], []
        for x, l in self.train:
            keep = l >= 0
            if exclude_fold is not None:
                keep &= self.fold != exclude_fold
            X.append(x[keep])
            Y.append(l[keep])
        return np.concatenate(X), np.concatenate(Y)


def fit(X, Y):
    """The same model as export.py."""
    counts = np.bincount(Y, minlength=C).astype(float)
    w = 1.0 / np.maximum(counts, 1)
    w = np.minimum((w / w[Y].mean())[Y], 20.0)
    model = xgb.XGBClassifier(
        n_estimators=150,
        max_depth=4,
        learning_rate=0.15,
        subsample=0.8,
        colsample_bytree=0.5,
        tree_method="hist",
        n_jobs=4,
        num_class=C,
        objective="multi:softprob",
        random_state=1,
    )
    model.fit(X, Y, sample_weight=w)
    return model


def evaluate(s, probs, folds):
    """On the events of the folds: detected and classified; false events a minute; cover held."""
    t, y, fold = s.t, s.y, s.fold
    pred = probs.argmax(1)
    detected = classified = total = 0
    mistakes = []
    for e in s.events:
        if e["fold"] not in folds:
            continue
        total += 1
        c = M.CLASSES.index(e["class"])
        near = (t >= e["t"] - 0.2) & (t <= e["t"] + 0.3)
        detected += probs[near, c].max() >= 0.5
        mean = probs[near].mean(0)
        mean[0] = 0
        got = mean.argmax()
        classified += got == c
        if got != c:
            mistakes.append(f"{e['class']}->{M.CLASSES[got]}")
    infold = np.isin(fold, list(folds))
    none = (y == 0) & infold
    flagged = (pred != 0) & none
    edges = np.sum(flagged[1:] & ~flagged[:-1])
    minutes = none.sum() / 30.0 / 60.0
    cover = (y == M.CLASSES.index("cover")) & infold
    held = (pred[cover] == M.CLASSES.index("cover")).mean() if cover.any() else np.nan
    return np.array([detected, classified, total, edges, minutes, held]), mistakes


def line(name, results):
    r = np.array([x[0] for x in results])
    mistakes = sum((x[1] for x in results), [])
    det, cls, tot = r[:, 0].sum(), r[:, 1].sum(), r[:, 2].sum()
    print(
        f"  {name:42s} detected {det:3.0f}/{tot:.0f}  classified {cls:3.0f}/{tot:.0f}  "
        f"false/min {r[:, 3].sum() / max(r[:, 4].sum(), 1e-6):5.1f}  cover {np.nanmean(r[:, 5]):4.0%}"
    )
    return mistakes


def main():
    pairs = list(zip(sys.argv[1::2], sys.argv[2::2]))
    sessions = [Session(r, p, seed) for seed, (r, p) in enumerate(pairs, 1)]
    for test in sessions:
        others = [s for s in sessions if s is not test]
        print(f"\nTest on {test.name}")
        if not others:
            print("  (only one session: see train.py for the folds within it)")
            continue
        parts = [s.rows() for s in others]
        Xo = np.concatenate([p[0] for p in parts])
        Yo = np.concatenate([p[1] for p in parts])
        model = fit(Xo, Yo)
        everything = set(range(5))
        mistakes = line(
            "(1) trained on the other sessions",
            [evaluate(test, model.predict_proba(test.X), everything)],
        )
        for name, X in test.scaled.items():
            line(f"    {name}", [evaluate(test, model.predict_proba(X), everything)])
        print("      mistakes:", ", ".join(sorted(mistakes)) or "none")

        results = []
        scaled = {name: [] for name in test.scaled}
        for f in range(5):
            Xt, Yt = test.rows(exclude_fold=f)
            model = fit(np.concatenate([Xt, Xo]), np.concatenate([Yt, Yo]))
            results.append(evaluate(test, model.predict_proba(test.X), {f}))
            for name, X in test.scaled.items():
                scaled[name].append(evaluate(test, model.predict_proba(X), {f}))
        mistakes = line("(2) the others + the other folds of this", results)
        for name in test.scaled:
            line(f"    {name}", scaled[name])
        print("      mistakes:", ", ".join(sorted(mistakes)) or "none")


if __name__ == "__main__":
    main()
