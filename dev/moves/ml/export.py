"""Train the move classifier on whole recordings and export it for the game.

python export.py <out dir> <recording.jsonl> <poses.jsonl> [<recording.jsonl> <poses.jsonl> ...]

Writes <out dir>/moves.json (the description: classes, offsets, format, model)
and <out dir>/moves_xgboost.json (the XGBoost model), which
scenes/vision/core/MoveClassifier.cs loads.
"""

import json
import pathlib
import sys

import numpy as np
import xgboost as xgb

import moves_ml as M

OFFSETS = np.arange(4) * 0.1
SCALES = [(0.35, 0.7)] * 3 + [(1.3, 1.8)] * 3 + [(0.8, 1.2)] * 2


def mirror_labels(y):
    out = y.copy()
    for i, c in enumerate(y):
        if c > 0:
            out[i] = M.CLASSES.index(M.mirror_class(M.CLASSES[c]))
    return out


def dataset(recording, poses, rng):
    t, k, marks, steps = M.load(recording, poses)
    y, _, _, _ = M.label_frames(t, k, marks, steps)
    streams = [(k, y)] + [(M.augment(k, rng, scale=rng.uniform(lo, hi)), y) for lo, hi in SCALES]
    streams += [(M.mirror(s), mirror_labels(l)) for s, l in streams]
    X, Y = [], []
    for s, l in streams:
        seq, score = M.sequences(t, s, OFFSETS)
        X.append(np.hstack([seq.reshape(len(seq), -1), score])[l >= 0])
        Y.append(l[l >= 0])
    return np.concatenate(X), np.concatenate(Y)


def main():
    out = pathlib.Path(sys.argv[1])
    pairs = list(zip(sys.argv[2::2], sys.argv[3::2]))
    rng = np.random.default_rng(1)
    parts = [dataset(r, p, rng) for r, p in pairs]
    X = np.concatenate([p[0] for p in parts])
    Y = np.concatenate([p[1] for p in parts])
    counts = np.bincount(Y, minlength=len(M.CLASSES)).astype(float)
    w = 1.0 / np.maximum(counts, 1)
    w = np.minimum((w / w[Y].mean())[Y], 20.0)
    model = xgb.XGBClassifier(
        n_estimators=150,
        max_depth=4,
        learning_rate=0.15,
        subsample=0.8,
        colsample_bytree=0.5,
        tree_method="hist",
        n_jobs=2,
        num_class=len(M.CLASSES),
        objective="multi:softprob",
        random_state=1,
    )
    model.fit(X, Y, sample_weight=w)
    out.mkdir(parents=True, exist_ok=True)
    model.get_booster().save_model(str(out / "moves_xgboost.json"))
    description = {
        "classes": M.CLASSES,
        "offsets": OFFSETS.tolist(),
        "format": "xgboost",
        "model": "moves_xgboost.json",
        "trained_on": [pathlib.Path(r).name for r, _ in pairs],
        "samples": int(len(Y)),
        "note": "Made with dev/moves/ml/export.py; see dev/moves/ml/README.md.",
    }
    (out / "moves.json").write_text(json.dumps(description, indent=2) + "\n")
    print(f"Trained on {len(Y)} samples; wrote {out}/moves.json and moves_xgboost.json")


if __name__ == "__main__":
    main()
