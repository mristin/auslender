"""Play a recording's frames at their real speed with RTMPose-t running live on each frame.

python viewer.py <recording.jsonl> <frames dir> <rtmpose.onnx>   (q or Escape quits, space pauses)
"""

import json, sys, time
import cv2, numpy as np, onnxruntime as ort

rec, frames_dir, model = sys.argv[1:4]
rows = [json.loads(l) for l in open(rec)]
frames = [(r["t"], r["index"]) for r in rows if r["kind"] == "frame"]
poses = [
    (r["t"], np.array(r["pose"][:51]).reshape(17, 3))
    for r in rows
    if r["kind"] == "pose" and r.get("pose")
]
labels = [(r["t"], r["label"]) for r in rows if r["kind"] == "face"]
calls = [(r["t"], r["name"][5:]) for r in rows if r["kind"] == "mark"]
opts = ort.SessionOptions()
opts.intra_op_num_threads = 2
sess = ort.InferenceSession(model, opts, providers=["CPUExecutionProvider"])
mean = np.array([123.675, 116.28, 103.53], np.float32)
std = np.array([58.395, 57.12, 57.375], np.float32)
BONES = [
    (5, 6),
    (5, 7),
    (7, 9),
    (6, 8),
    (8, 10),
    (5, 11),
    (6, 12),
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (0, 5),
    (0, 6),
]


def box_from(k, thr):
    v = k[k[:, 2] >= thr]
    if len(v) < 5:
        return None
    x0, y0 = v[:, :2].min(0)
    x1, y1 = v[:, :2].max(0)
    cx, cy, w, h = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 1.25, (y1 - y0) * 1.25
    if w * 256 > h * 192:
        h = w * 256 / 192
    else:
        w = h * 192 / 256
    return cx, cy, w, h


box = None
pi = 0
li = 0
ci = 0
ms_avg = None
call_text = ""
call_until = -1
start_wall = time.perf_counter()
t0 = frames[0][0]
paused = False
cv2.namedWindow("RTMPose-t live", cv2.WINDOW_NORMAL)
cv2.resizeWindow("RTMPose-t live", 1280, 960)
i = 0
while i < len(frames):
    t, idx = frames[i]
    # keep real time: skip frames if we fall behind
    due = start_wall + (t - t0)
    if time.perf_counter() > due + 0.05 and i + 1 < len(frames):
        i += 1
        continue
    img = cv2.imread(f"{frames_dir}/{idx:05d}.jpg")
    while pi + 1 < len(poses) and poses[pi + 1][0] <= t:
        pi += 1
    while li + 1 < len(labels) and labels[li + 1][0] <= t:
        li += 1
    while ci < len(calls) and calls[ci][0] <= t:
        call_text, call_until = calls[ci][1].replace("_", " ").upper(), calls[ci][0] + 0.9
        ci += 1
    if box is None and poses and poses[pi][0] <= t:
        box = box_from(poses[pi][1], 0.3)
    k = None
    if box is not None:
        a = time.perf_counter()
        cx, cy, w, h = box
        M = np.float32([[w / 192, 0, cx - w / 2], [0, h / 256, cy - h / 2]])
        crop = cv2.warpAffine(
            img, M, (192, 256), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP, borderValue=(0, 0, 0)
        )
        x = ((crop[:, :, ::-1].astype(np.float32) - mean) / std).transpose(2, 0, 1)[None]
        sx, sy = sess.run(["simcc_x", "simcc_y"], {"input": x})
        bx, by = sx[0].argmax(1), sy[0].argmax(1)
        score = np.minimum(sx[0].max(1), sy[0].max(1))
        k = np.stack([cx - w / 2 + bx / 2 * w / 192, cy - h / 2 + by / 2 * h / 256, score], 1)
        ms = (time.perf_counter() - a) * 1000
        ms_avg = ms if ms_avg is None else ms_avg * 0.9 + ms * 0.1
        box = box_from(k, 0.4)
    view = cv2.flip(img, 1)  # mirrored, as the player sees himself
    if k is not None:
        p = k.copy()
        p[:, 0] = img.shape[1] - p[:, 0]
        for a_, b_ in BONES:
            if p[a_, 2] > 0.3 and p[b_, 2] > 0.3:
                cv2.line(
                    view,
                    tuple(int(v) for v in p[a_, :2]),
                    tuple(int(v) for v in p[b_, :2]),
                    (90, 230, 120),
                    2,
                    cv2.LINE_AA,
                )
        for j in range(17):
            if p[j, 2] > 0.3:
                color = (40, 200, 255) if j in (9, 10) else (90, 230, 120)
                cv2.circle(
                    view,
                    (int(p[j, 0]), int(p[j, 1])),
                    5 if j in (9, 10) else 3,
                    color,
                    -1,
                    cv2.LINE_AA,
                )
    big = cv2.resize(view, (1280, 960))
    cv2.putText(
        big,
        f"RTMPose-t live: {ms_avg or 0:.1f} ms/frame   t {t - t0:5.1f} s   step: {labels[li][1]}",
        (20, 40),
        cv2.FONT_HERSHEY_SIMPLEX,
        1.0,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )
    if t < call_until:
        cv2.putText(
            big, call_text, (20, 120), cv2.FONT_HERSHEY_SIMPLEX, 2.4, (80, 200, 255), 5, cv2.LINE_AA
        )
    cv2.imshow("RTMPose-t live", big)
    wait = max(1, int((due - time.perf_counter()) * 1000))
    key = cv2.waitKey(wait) & 0xFF
    if key in (27, ord("q")):
        break
    if key == ord(" "):
        paused_at = time.perf_counter()
        while (cv2.waitKey(50) & 0xFF) != ord(" "):
            pass
        start_wall += time.perf_counter() - paused_at
    i += 1
