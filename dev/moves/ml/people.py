"""Find the parts of a recording with more than one person in the picture.

python people.py <recording.jsonl> [<rtmo.onnx>]

Runs RTMO (the model with which the game finds the player) on every third frame
of the recording, and prints the spans with a second person standing in the
picture (score of at least 0.8, at least 300 pixels tall) as the lines of a
<recording>.skip.csv (see moves_ml.load_skips), with half a second of margin.
Somebody sitting or crouching at the side does not count, nor do the weak
detections of the furniture.
"""

import json
import pathlib
import sys

import cv2
import numpy as np
import onnxruntime as ort

SIZE = 416
EVERY = 3
SCORE = 0.8
TALL = 300
MARGIN = 0.5
MODEL = pathlib.Path(__file__).parents[3] / "scenes/vision/rtmo/model/rtmo_t_body7_416x416.onnx"


def standing_persons(session, bgr):
    """The number of persons standing in the frame."""
    h, w = bgr.shape[:2]
    s = min(SIZE / w, SIZE / h)
    nw, nh = round(w * s), round(h * s)
    canvas = np.full((SIZE, SIZE, 3), 114, np.float32)
    px, py = (SIZE - nw) // 2, (SIZE - nh) // 2
    canvas[py : py + nh, px : px + nw] = cv2.resize(bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
    dets, _ = session.run(None, {"input": canvas.transpose(2, 0, 1)[None]})
    return sum(1 for d in dets[0] if d[4] >= SCORE and (d[3] - d[1]) / s >= TALL)


def main():
    recording = pathlib.Path(sys.argv[1])
    model = sys.argv[2] if len(sys.argv) > 2 else str(MODEL)
    session = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    rows = [json.loads(line) for line in recording.open()]
    frames = [r for r in rows if r["kind"] == "frame"][::EVERY]
    spans = []
    for r in frames:
        bgr = cv2.imread(str(recording.with_suffix(".frames") / f"{r['index']:05d}.jpg"))
        if bgr is None or standing_persons(session, bgr) < 2:
            continue
        if spans and r["t"] - spans[-1][1] < 2.0:
            spans[-1][1] = r["t"]
        else:
            spans.append([r["t"], r["t"]])
    print("# start,end,reason")
    for a, b in spans:
        print(f"{a - MARGIN:.1f},{b + MARGIN:.1f},a second person in the picture")


if __name__ == "__main__":
    main()
