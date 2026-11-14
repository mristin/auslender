"""Cross-validate move classifiers on one labelled recording (5 folds by repetition).

python train.py <recording.jsonl> <poses.jsonl> [models] [windows]
"""

import sys
import time

import numpy as np
import torch
import xgboost as xgb

import moves_ml as M

torch.set_num_threads(2)
RNG = np.random.default_rng(1)

t, k, marks, steps = M.load(sys.argv[1], sys.argv[2])
y, event, fold, events = M.label_frames(t, k, marks, steps, M.load_skips(sys.argv[1]))
C = len(M.CLASSES)
# the features of one pose: x and y of each point
WIDTH = 2 * len(M.POINTS)


def sequences(t, k, offsets):
    """[N, T, WIDTH] oldest first, relative to the shoulders now, in body scales; plus [N, 2] wrist scores."""
    scales = M.body_scales(t, k)
    at = (t[:, None] - offsets[None, :]).ravel()
    w = M.interpolate(t, k, at).reshape(len(t), len(offsets), 17, 3)
    sh = (k[:, 5, :2] + k[:, 6, :2]) / 2
    rel = (w[:, :, M.POINTS, :2] - sh[:, None, None, :]) / scales[:, None, None, None]
    seq = rel.reshape(len(t), len(offsets), -1)[:, ::-1].astype(np.float32)
    score = w[:, :, [9, 10], 2].min(axis=1).astype(np.float32)
    return seq, score


def mirror_labels(y):
    out = y.copy()
    for i, c in enumerate(y):
        if c > 0:
            out[i] = M.CLASSES.index(M.mirror_class(M.CLASSES[c]))
    return out


SCALES = [(0.35, 0.7)] * 3 + [(1.3, 1.8)] * 3 + [(0.8, 1.2)] * 2


def build(offsets):
    """The original stream, its shrunk, enlarged and normal copies and all their mirrors."""
    streams = [(k, y)]
    for low, high in SCALES:
        streams.append((M.augment(k, RNG, scale=RNG.uniform(low, high)), y))
    streams += [(M.mirror(s), mirror_labels(l)) for s, l in streams]
    out = []
    for j, (s, l) in enumerate(streams):
        seq, score = sequences(t, s, offsets)
        out.append((seq, score, l, fold, j == 0))
    return out


def scaled_tests(offsets):
    """The original stream shrunk to a child (0.5, child proportions) and enlarged (1.5), with jitter."""
    rng = np.random.default_rng(99)
    out = {}
    for name, scale, child in (("child 0.5x", 0.5, True), ("enlarged 1.5x", 1.5, False)):
        seq, score = sequences(t, M.augment(k, rng, scale=scale, child=child), offsets)
        out[name] = (seq, score)
    return out


def evaluate(probs, test_fold, name):
    """Event detection, event classification, false alarms and cover, on the frames of the test fold."""
    pred = probs.argmax(1)
    detected = classified = total = 0
    confusion = []
    for e in events:
        if e["fold"] != test_fold:
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
            confusion.append(f"{e['class']}->{M.CLASSES[got]}")
    none = (y == 0) & (fold == test_fold)
    alarms = (pred[none] != 0).mean()
    # false events: rising edges of a non-none argmax within the none frames
    flagged = (pred != 0) & none
    edges = np.sum(flagged[1:] & ~flagged[:-1])
    minutes = none.sum() / 30.0 / 60.0
    cover = (y == M.CLASSES.index("cover")) & (fold == test_fold)
    cover_ok = (pred[cover] == M.CLASSES.index("cover")).mean() if cover.any() else np.nan
    return (
        np.array([detected, classified, total, alarms, edges / max(minutes, 1e-6), cover_ok]),
        confusion,
    )


SCALED = {}
SCALED_ROWS = {}


def report(name, rows, confusions, ms):
    for sname, srows in SCALED_ROWS.items():
        sr = np.array(srows)
        print(
            f"    on the test folds {sname:13s}: detected {sr[:, 0].sum():.0f}/{sr[:, 2].sum():.0f}  classified {sr[:, 1].sum():.0f}/{sr[:, 2].sum():.0f}  false events/min {np.mean(sr[:, 4]):5.1f}"
        )
    SCALED_ROWS.clear()
    r = np.array(rows)
    det, cls, tot = r[:, 0].sum(), r[:, 1].sum(), r[:, 2].sum()
    print(
        f"{name:34s} detected {det:.0f}/{tot:.0f}  classified {cls:.0f}/{tot:.0f}  "
        f"false frames {np.mean(r[:, 3]):5.1%}  false events/min {np.mean(r[:, 4]):5.1f}  "
        f"cover {np.nanmean(r[:, 5]):4.0%}  {ms:.3f} ms/pred"
    )
    if confusions:
        print("    mistakes:", ", ".join(sorted(confusions)))


def weights(labels):
    counts = np.bincount(labels, minlength=C).astype(float)
    w = 1.0 / np.maximum(counts, 1)
    w = w / w[labels].mean()
    return np.minimum(w[labels], 20.0)


def run_xgb(offsets, data):
    rows, confs, ms = [], [], 0.0
    for f in range(5):
        Xtr = np.concatenate(
            [
                np.hstack([s.reshape(len(s), -1), sc])[(l >= 0) & (fo != f)]
                for s, sc, l, fo, _ in data
            ]
        )
        ytr = np.concatenate([l[(l >= 0) & (fo != f)] for s, sc, l, fo, _ in data])
        model = xgb.XGBClassifier(
            n_estimators=150,
            max_depth=4,
            learning_rate=0.15,
            subsample=0.8,
            colsample_bytree=0.5,
            tree_method="hist",
            n_jobs=2,
            num_class=C,
            objective="multi:softprob",
        )
        model.fit(Xtr, ytr, sample_weight=weights(ytr))
        s, sc = data[0][0], data[0][1]
        Xall = np.hstack([s.reshape(len(s), -1), sc])
        start = time.perf_counter()
        probs = model.predict_proba(Xall)
        ms += (time.perf_counter() - start) * 1000 / len(Xall) / 5
        r, c = evaluate(probs, f, "xgb")
        rows.append(r)
        confs += c
        for sname, (ss, ssc) in SCALED.items():
            sr, _ = evaluate(
                model.predict_proba(np.hstack([ss.reshape(len(ss), -1), ssc])), f, sname
            )
            SCALED_ROWS.setdefault(sname, []).append(sr)
    return rows, confs, ms, model


class Conv(torch.nn.Module):
    def __init__(self, steps):
        super().__init__()
        self.net = torch.nn.Sequential(
            torch.nn.Conv1d(WIDTH, 64, 3, padding=1),
            torch.nn.ReLU(),
            torch.nn.Conv1d(64, 64, 3, padding=1),
            torch.nn.ReLU(),
        )
        self.head = torch.nn.Linear(64 + 2, C)

    def forward(self, seq, score):
        h = self.net(seq.transpose(1, 2)).amax(dim=2)
        return self.head(torch.cat([h, score], 1))


class TcnBlock(torch.nn.Module):
    """A causal, dilated convolution with a residual connection."""

    def __init__(self, channels, dilation):
        super().__init__()
        self.pad = 2 * dilation
        self.conv = torch.nn.Conv1d(channels, channels, 3, dilation=dilation)

    def forward(self, x):
        return x + torch.relu(self.conv(torch.nn.functional.pad(x, (self.pad, 0))))


class Tcn(torch.nn.Module):
    """A temporal convolutional network: dilations 1, 2, 4; the newest step is read out."""

    def __init__(self, steps):
        super().__init__()
        self.inp = torch.nn.Conv1d(WIDTH, 48, 1)
        self.blocks = torch.nn.Sequential(TcnBlock(48, 1), TcnBlock(48, 2), TcnBlock(48, 4))
        self.head = torch.nn.Linear(48 + 2, C)

    def forward(self, seq, score):
        h = self.blocks(torch.relu(self.inp(seq.transpose(1, 2))))[:, :, -1]
        return self.head(torch.cat([h, score], 1))


class Gru(torch.nn.Module):
    def __init__(self, steps):
        super().__init__()
        self.gru = torch.nn.GRU(WIDTH, 64, batch_first=True)
        self.head = torch.nn.Linear(64 + 2, C)

    def forward(self, seq, score):
        _, h = self.gru(seq)
        return self.head(torch.cat([h[-1], score], 1))


def run_torch(kind, offsets, data, epochs=25):
    rows, confs, ms = [], [], 0.0
    for f in range(5):
        torch.manual_seed(f)
        S = torch.tensor(np.concatenate([s[(l >= 0) & (fo != f)] for s, sc, l, fo, _ in data]))
        Sc = torch.tensor(np.concatenate([sc[(l >= 0) & (fo != f)] for s, sc, l, fo, _ in data]))
        Y = np.concatenate([l[(l >= 0) & (fo != f)] for s, sc, l, fo, _ in data])
        W = torch.tensor(weights(Y), dtype=torch.float32)
        Y = torch.tensor(Y)
        model = kind(len(offsets))
        opt = torch.optim.Adam(model.parameters(), lr=2e-3)
        for _ in range(epochs):
            perm = torch.randperm(len(Y))
            for b in range(0, len(Y), 256):
                i = perm[b : b + 256]
                loss = (
                    torch.nn.functional.cross_entropy(model(S[i], Sc[i]), Y[i], reduction="none")
                    * W[i]
                ).mean()
                opt.zero_grad()
                loss.backward()
                opt.step()
        model.eval()
        with torch.no_grad():
            s, sc = torch.tensor(data[0][0]), torch.tensor(data[0][1])
            start = time.perf_counter()
            for b in range(0, 64):  # one-at-a-time latency, as in the game
                model(s[b : b + 1], sc[b : b + 1])
            ms += (time.perf_counter() - start) * 1000 / 64 / 5
            probs = torch.softmax(model(s, sc), 1).numpy()
            scaled_probs = {
                n: torch.softmax(model(torch.tensor(a), torch.tensor(b)), 1).numpy()
                for n, (a, b) in SCALED.items()
            }
        r, c = evaluate(probs, f, kind.__name__)
        rows.append(r)
        confs += c
        for sname, sp in scaled_probs.items():
            sr, _ = evaluate(sp, f, sname)
            SCALED_ROWS.setdefault(sname, []).append(sr)
    return rows, confs, ms, model


if __name__ == "__main__":
    windows = {
        "4 poses x 0.05 s (0.15 s)": np.arange(4) * 0.05,
        "4 poses x 0.1 s (0.3 s)": np.arange(4) * 0.1,
        "9 poses x 0.05 s (0.4 s)": np.arange(9) * 0.05,
    }
    which = sys.argv[3].split(",") if len(sys.argv) > 3 else ["xgb", "conv", "tcn", "gru"]
    if len(sys.argv) > 4:
        windows = {n: o for n, o in windows.items() if any(w in n for w in sys.argv[4].split(","))}
    for wname, offsets in windows.items():
        data = build(offsets)
        SCALED.clear()
        SCALED.update(scaled_tests(offsets))
        if "xgb" in which:
            report(f"XGBoost, {wname}", *run_xgb(offsets, data)[:3])
        if "conv" in which:
            report(f"1D-CNN, {wname}", *run_torch(Conv, offsets, data)[:3])
        if "tcn" in which:
            report(f"TCN, {wname}", *run_torch(Tcn, offsets, data)[:3])
        if "gru" in which:
            report(f"GRU, {wname}", *run_torch(Gru, offsets, data)[:3])
