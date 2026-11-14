"""Recompute the features of the parity test of the move features with the Python of the training.

python parity_cases.py [<cases.json>]

The cases (by default tests/Auslender.Tests/data/move_features_cases.json)
hold a synthetic pose stream at an uneven frame rate ("t", "poses", the
"offsets") and its "features" frame by frame; MoveFeaturesTests checks that
the C# (MoveFeatures) computes the same. Run this after changing the features
(moves_ml.sequences) to rewrite the "features" of the stream.
"""

import json
import pathlib
import sys

import numpy as np

import moves_ml as M

DEFAULT = pathlib.Path(__file__).parents[3] / "tests/Auslender.Tests/data/move_features_cases.json"


def main():
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    cases = json.loads(path.read_text())
    t = np.array(cases["t"])
    k = np.array(cases["poses"], dtype=np.float64).reshape(-1, 17, 3)
    seq, score = M.sequences(t, k, np.array(cases["offsets"]))
    features = np.hstack([seq.reshape(len(seq), -1), score])
    cases["features"] = features.astype(np.float32).tolist()
    path.write_text(json.dumps(cases))
    print(f"Wrote {len(features)} frames of {features.shape[1]} features into {path}")


if __name__ == "__main__":
    main()
