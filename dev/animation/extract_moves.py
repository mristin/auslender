"""Extract the moves of the opponents from the guided recordings of the players.

venv-ml/bin/python dev/animation/extract_moves.py [--videos ~/auslender-video] \
    [--out scenes/opponent/moves/moves.json]

(in venv-ml, see dev/moves/ml/requirements.txt: numpy, scipy, onnxruntime).

The opponents (see scenes/opponent/opponent.gd) box on a simple rig (see
scenes/opponent/looks.gd): a torso on the hips, two arms of an upper arm and a
forearm, two legs of a thigh and a shin, and a head. Posed by hand, they moved
as robots. Here we take their moves from people instead: the adult players
who recorded the guided fight plan (dev/moves/plans/fight.csv, see
CONTRIBUTING.md) threw every punch, knee, slip, duck and jump about five times
a session, each on a call. The recorded person faces the camera as the
opponent faces the player, so that what the player sees of the opponent is
what the camera saw of the player.

For each session (the child's is left out: he moves as a child, and the
picture was crowded):

1. We read the 2D poses of RTMPose (<session>.poses.jsonl), resample them to
   30 frames a second and smooth them (Savitzky-Golay).
2. We lift them to 3D (VideoPose3D of one frame, see
   dev/lifting/export_videopose.py), but trust it only for the torso: the
   depth of each joint of the torso relative to the pelvis, less its depth
   while he stands (so that he stands upright). The camera was on the floor,
   and the lifter, which learned from cameras at the height of the chest,
   mistakes a straight punch at the camera for an arm raised up.
3. The limbs come from the geometry instead: each joint (an elbow, a wrist, a
   knee) lies on the ray of the camera through its key point, at the length
   of its bone from its parent joint (a pinhole camera with a focal length of
   FOCAL pixels); of the two points on the ray, we take the one nearer the
   camera (a boxer's hands, elbows and knees are in front of him), unless the
   lifter puts it well behind. The camera does not see the feet of the
   adults: the shins hang straight down where the ankles are not seen.
   The camera lay low (on the floor, CAMERA_HEIGHT), looking up at him: we
   turn its rays by its tilt, so that the ray through the middle of his torso
   rises as it would from there; then a punch at the camera rises in the
   picture as it comes nearer, not because the arm goes up.
4. We turn the axes into the rig's: x to his right, y up, z backwards (he
   faces -z, as in Godot), the pelvis of his standing at the origin, scaled
   to the size of the rig.

For each move, we find every repetition after its call (the moment where it
peaks: the farthest reach of the punching glove, the highest knee, the
lowest duck, ...), align them all on that moment, and average them: the
directions of the bones, the turn of the torso, and the shift of the body.
At last we fit the angles of the rig to each frame of the averaged moves
(the shoulders turn in Godot's order YXZ, the elbows and the knees bend about
their x) and write them to the JSON, frame by frame, as the raw rotations of
the rig's pivots (see the "format" in the JSON).

The lifter was trained on Human3.6M, whose license allows only academic,
non-commercial research (see scenes/vision/lifting/model/lifting.json); the
moves are derived from it, so check this before releasing the game.
"""

import argparse
import bisect
import json
import pathlib
import sys

import numpy as np
import onnxruntime as ort
from scipy.optimize import least_squares
from scipy.signal import savgol_filter

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

SESSIONS = [
    "fight-floor-20261114-094437",
    "fight-floor-20261114-161309",
    "fight-floor-20261114-200552",
    "fight-floor-20261114-201645",
    "fight-floor-20261114-203041",
    "fight-floor-20261114-204458",
]

FPS = 30.0

## The focal length of the webcam, in pixels of 640 x 480 (about 56 degrees
## across), and the width of the shoulders (between the shoulder joints of
## COCO) of an adult, in meters: from it, how far he stood.
FOCAL = 600.0
SHOULDERS = 0.34

## Where the camera lay (on the floor, the top of the laptop's screen) and the
## middle of an adult's torso, above the floor, in meters.
CAMERA_HEIGHT = 0.25
TORSO_MIDDLE = 1.2

## The rig (see scenes/opponent/looks.gd), in meters.
RIG_TORSO_Y = 0.95
RIG_SHOULDER = np.array([0.31, 0.58, 0.0])
RIG_UPPER_ARM = 0.30
RIG_FOREARM = 0.30
RIG_HIP = np.array([0.12, 0.92, 0.0])
RIG_THIGH = 0.46
RIG_SHIN = 0.42
## From the middle of the hips to the middle of the shoulders, in the rig.
RIG_TORSO_LENGTH = float(np.linalg.norm([0.0, RIG_TORSO_Y + RIG_SHOULDER[1] - RIG_HIP[1]]))

## The joints of Human3.6M (see PoseLifter.cs).
PELVIS, R_HIP, R_KNEE, R_ANKLE, L_HIP, L_KNEE, L_ANKLE = 0, 1, 2, 3, 4, 5, 6
SPINE, THORAX, NOSE, HEAD = 7, 8, 9, 10
L_SHOULDER, L_ELBOW, L_WRIST, R_SHOULDER, R_ELBOW, R_WRIST = 11, 12, 13, 14, 15, 16

## The moves: the clip, the call in the plan, how its peak is measured, and
## the side (0: his left, 1: his right).
MOVES = {
    "jab": ("straight_left", "wrist", 0),
    "cross": ("straight_right", "wrist", 1),
    "hook_left": ("hook_left", "wrist", 0),
    "hook_right": ("hook_right", "wrist", 1),
    "uppercut_left": ("uppercut_left", "wrist", 0),
    "uppercut_right": ("uppercut_right", "wrist", 1),
    "knee_left": ("front_kick_left", "knee", 0),
    "knee_right": ("front_kick_right", "knee", 1),
    "slip_left": ("slip_left", "slip", 0),
    "slip_right": ("slip_right", "slip", 1),
    "duck": ("duck", "duck", 0),
    "jump": ("jump", "jump", 0),
    "cover": ("cover", "cover", 0),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--videos", default=str(pathlib.Path.home() / "auslender-video"))
    parser.add_argument("--out", default=str(REPO_ROOT / "scenes/opponent/moves/moves.json"))
    args = parser.parse_args()

    lifter = ort.InferenceSession(
        str(REPO_ROOT / "scenes/vision/lifting/model/videopose3d_h36m_1frame.onnx")
    )
    sessions = []
    for name in SESSIONS:
        directory = pathlib.Path(args.videos) / name
        if not directory.exists():
            print(f"Skipped the missing session {directory}.", file=sys.stderr)
            continue
        sessions.append(load_session(directory, name, lifter))
        print(f"Loaded {name}: {len(sessions[-1]['t'])} frames.", flush=True)

    clips = {"guard": guard_loop(sessions)}
    for clip, (call, measure, side) in MOVES.items():
        clips[clip] = average_move(sessions, call, measure, side)

    errors = []
    out_clips = {}
    for clip, features in clips.items():
        frames, error = fit_clip(features["frames"])
        errors.append(error)
        out_clips[clip] = {"fps": int(FPS), "hit": int(features["hit"]), "frames": frames}
        if "reps" in features:
            out_clips[clip]["reps"] = int(features["reps"])
        report(clip, out_clips[clip], features, error)

    result = {
        "source": (
            "Averaged from the guided fight recordings of adult players (dev/moves/plans/fight.csv) "
            "by dev/animation/extract_moves.py: 2D poses of RTMPose, the torso lifted to 3D with "
            "VideoPose3D (MMPose, one frame). The lifter was trained on Human3.6M, whose license "
            "allows only academic, non-commercial research. Check this before releasing the game "
            "with this file."
        ),
        "format": (
            "Each frame: arms [his left, his right], each [shoulder rotation.y, rotation.x, "
            "rotation.z, elbow rotation.x]; legs [his left, his right], each [hip rotation.x, "
            "rotation.z, knee rotation.x]; torso [rotation.x, rotation.y, rotation.z]; head "
            "[rotation.x, rotation.y, rotation.z]; offset: the shift of the body [x, y, z] in "
            "meters. Raw rotations of the pivots of the rig (radians, Euler order YXZ), his left "
            "arm and leg at -x. 'hit' is the frame of the peak (the impact of a strike)."
        ),
        "clips": out_clips,
    }
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    print(f"Mean error of the fitted rig: {np.mean(errors) * 100:.1f} cm")
    print(f"Wrote {out} ({out.stat().st_size} bytes).")
    return 0


# ---------------------------------------------------------------------------
# Loading and 3D
# ---------------------------------------------------------------------------


def load_session(directory: pathlib.Path, name: str, lifter: ort.InferenceSession) -> dict:
    rows = [json.loads(line) for line in (directory / f"{name}.jsonl").open()]
    start = next(row for row in rows if row["kind"] == "start")
    width, height = start["width"], start["height"]
    frame_rows = [row for row in rows if row["kind"] == "frame"]
    frame_times = [row["t"] for row in frame_rows]
    marks = [(row["t"], row["name"]) for row in rows if row["kind"] == "mark"]
    skips = load_skips(directory / f"{name}.skip.csv")

    poses = [json.loads(line) for line in (directory / f"{name}.poses.jsonl").open()]
    times = np.array([pose["t"] for pose in poses])
    points = np.array([pose["pose"] for pose in poses]).reshape(-1, 17, 3)

    # NOTE (mristin):
    # On a grid of 30 frames a second; where the poses are more than 0.2 s
    # apart, nothing (NaN).
    grid = np.arange(times[0], times[-1], 1.0 / FPS)
    after = np.clip(np.searchsorted(times, grid), 1, len(times) - 1)
    gap = times[after] - times[after - 1]
    share = np.clip((grid - times[after - 1]) / np.maximum(gap, 1e-6), 0.0, 1.0)
    coco = points[after - 1] * (1 - share)[:, None, None] + points[after] * share[:, None, None]
    coco[gap > 0.2] = np.nan
    valid = ~np.isnan(coco[:, 0, 0])
    coco[valid, :, :2] = savgol_filter(coco[valid, :, :2], 7, 2, axis=0)

    labels = np.array(
        [frame_rows[max(0, bisect.bisect_right(frame_times, t) - 1)]["label"] for t in grid]
    )
    joints_2d = to_h36m(coco)

    lifted = np.full((len(grid), 17, 3), np.nan)
    normalized = (joints_2d - np.array([width / 2, height / 2])) / (width / 2)
    lifted[valid] = lifter.run(
        None, {"keypoints_2d": normalized[valid].reshape(-1, 34).astype(np.float32)}
    )[0].reshape(-1, 17, 3)

    standing = valid & np.isin(labels, ["stand 1", "guard", "stand 2"])
    joints = reconstruct(joints_2d, lifted, standing, valid, width, height)

    for begin, end in skips:
        valid &= ~((grid >= begin) & (grid <= end))
    return {
        "name": name,
        "t": grid,
        "labels": labels,
        "marks": marks,
        "valid": valid & ~np.isnan(joints[:, 0, 0]),
        "joints": joints,
        "standing": standing,
    }


def load_skips(path: pathlib.Path) -> list:
    if not path.exists():
        return []
    spans = []
    for line in path.read_text().splitlines():
        if line.strip() == "" or line.startswith("#"):
            continue
        parts = line.split(",")
        spans.append((float(parts[0]), float(parts[1])))
    return spans


def to_h36m(coco: np.ndarray) -> np.ndarray:
    """The 17 joints of Human3.6M from the key points of COCO, as PoseLifter.ToH36m."""
    a = coco[..., :2]
    joints = np.zeros(coco.shape[:-2] + (17, 2))
    pelvis = (a[..., 11, :] + a[..., 12, :]) / 2
    thorax = (a[..., 5, :] + a[..., 6, :]) / 2

    def ankle(hip, knee, foot):
        guess = a[..., knee, :] + (a[..., knee, :] - a[..., hip, :])
        return np.where((coco[..., foot, 2] >= 0.3)[..., None], a[..., foot, :], guess)

    joints[..., PELVIS, :] = pelvis
    joints[..., R_HIP, :] = a[..., 12, :]
    joints[..., R_KNEE, :] = a[..., 14, :]
    joints[..., R_ANKLE, :] = ankle(12, 14, 16)
    joints[..., L_HIP, :] = a[..., 11, :]
    joints[..., L_KNEE, :] = a[..., 13, :]
    joints[..., L_ANKLE, :] = ankle(11, 13, 15)
    joints[..., SPINE, :] = (pelvis + thorax) / 2
    joints[..., THORAX, :] = thorax
    joints[..., NOSE, :] = a[..., 0, :]
    joints[..., HEAD, :] = (a[..., 1, :] + a[..., 2, :]) / 2
    joints[..., L_SHOULDER, :] = a[..., 5, :]
    joints[..., L_ELBOW, :] = a[..., 7, :]
    joints[..., L_WRIST, :] = a[..., 9, :]
    joints[..., R_SHOULDER, :] = a[..., 6, :]
    joints[..., R_ELBOW, :] = a[..., 8, :]
    joints[..., R_WRIST, :] = a[..., 10, :]
    return joints


def reconstruct(joints_2d, lifted, standing, valid, width, height) -> np.ndarray:
    """The joints in 3D, in the rig's axes (x to his right, y up, he faces -z),
    the pelvis of his standing at the origin, scaled to the rig."""
    center = np.array([width / 2, height / 2])
    rays = np.concatenate([(joints_2d - center) / FOCAL, np.ones(joints_2d.shape[:-1] + (1,))], -1)
    # NOTE (mristin):
    # The camera's axes (x right, y down, z away) to ours, of the world: x
    # right, y up, z away from the camera.
    rays = rays * np.array([1.0, -1.0, 1.0])

    stand_2d = np.nanmedian(joints_2d[standing], axis=0)
    shoulder_px = np.linalg.norm(stand_2d[L_SHOULDER] - stand_2d[R_SHOULDER])
    distance = FOCAL * SHOULDERS / shoulder_px

    # NOTE (mristin):
    # The tilt of the camera: it lay low (at CAMERA_HEIGHT), so that it
    # looked up at the middle of his torso (at TORSO_MIDDLE) from his
    # distance. Turn the rays up by the tilt about the x axis.
    middle = (stand_2d[PELVIS] + stand_2d[THORAX]) / 2
    seen = np.arctan2(center[1] - middle[1], FOCAL)
    tilt = np.arctan2(TORSO_MIDDLE - CAMERA_HEIGHT, distance) - seen
    c, s = np.cos(tilt), np.sin(tilt)
    up = np.array([[1, 0, 0], [0, c, s], [0, -s, c]])
    rays = rays @ up.T

    # NOTE (mristin):
    # The torso from the lifter: how far each of its joints is in front of
    # or behind the pelvis, less that while he stands, so that he stands
    # upright; on its ray at that distance (along the floor) from the camera.
    torso_joints = [PELVIS, R_HIP, L_HIP, SPINE, THORAX, NOSE, HEAD, L_SHOULDER, R_SHOULDER]
    calibration = np.nanmedian(lifted[standing], axis=0)
    joints = np.full(lifted.shape, np.nan)
    for j in torso_joints:
        z = (
            distance
            + (lifted[:, j, 2] - lifted[:, PELVIS, 2])
            - (calibration[j, 2] - calibration[PELVIS, 2])
        )
        joints[:, j] = rays[:, j] * (z / rays[:, j, 2])[:, None]

    # NOTE (mristin):
    # The bones of the limbs: their lengths as the longest they show (in the
    # plane of the picture, at his distance), and each child joint on its ray
    # at that length from its parent.
    # NOTE (mristin):
    # The hands and the elbows of a boxer are in front of him; the knees
    # follow the lifter, which knows the legs well (a standing leg is
    # straight, not bent forward).
    limbs = [
        (L_SHOULDER, L_ELBOW, True),
        (L_ELBOW, L_WRIST, True),
        (R_SHOULDER, R_ELBOW, True),
        (R_ELBOW, R_WRIST, True),
        (L_HIP, L_KNEE, False),
        (R_HIP, R_KNEE, False),
    ]
    for parent, child, front in limbs:
        flat = (
            np.linalg.norm(joints_2d[valid, child] - joints_2d[valid, parent], axis=-1)
            * distance
            / FOCAL
        )
        length = np.percentile(flat, 95)
        hint = (lifted[:, child, 2] - lifted[:, parent, 2]) - (
            calibration[child, 2] - calibration[parent, 2]
        )
        joints[:, child] = on_ray(joints[:, parent], rays[:, child], length, hint, front)

    # NOTE (mristin):
    # The shins: hanging straight down from the knees (the camera does not
    # see the feet of the adults), the length of the thighs a little less.
    for hip, knee, ankle in [(L_HIP, L_KNEE, L_ANKLE), (R_HIP, R_KNEE, R_ANKLE)]:
        thigh = np.nanmedian(np.linalg.norm(joints[valid, knee] - joints[valid, hip], axis=-1))
        joints[:, ankle] = joints[:, knee] - np.array([0.0, thigh * RIG_SHIN / RIG_THIGH, 0.0])

    # NOTE (mristin):
    # He faces the camera: his right is to the left of the camera, and he
    # faces -z, as in Godot.
    joints = joints * np.array([-1.0, 1.0, 1.0])
    origin = np.nanmedian(joints[standing, PELVIS], axis=0)
    torso = np.nanmedian(
        np.linalg.norm(joints[standing, THORAX] - joints[standing, PELVIS], axis=-1)
    )
    return (joints - origin) * (RIG_TORSO_LENGTH / torso)


def on_ray(
    parent: np.ndarray, ray: np.ndarray, length: float, hint: np.ndarray, front: bool
) -> np.ndarray:
    """The points on the rays (from the camera) at the length from the
    parents (the nearest point on the ray if none): if [param front], the one
    nearer the camera, unless the hint (the lifter's depth of the child
    relative to the parent, along the floor) puts it well behind; else the one
    nearer the hint."""
    a = np.sum(ray * ray, axis=-1)
    b = -2 * np.sum(ray * parent, axis=-1)
    c = np.sum(parent * parent, axis=-1) - length * length
    root = np.sqrt(np.maximum(b * b - 4 * a * c, 0.0))
    near = (-b - root) / (2 * a)
    far = (-b + root) / (2 * a)
    if front:
        pick = np.where(hint > 0.5 * length, far, near)
    else:
        target = parent[:, 2] + hint
        pick = np.where(
            np.abs(near * ray[:, 2] - target) <= np.abs(far * ray[:, 2] - target), near, far
        )
    return ray * pick[:, None]


# ---------------------------------------------------------------------------
# Features, alignment and averaging
# ---------------------------------------------------------------------------


def unit(v: np.ndarray) -> np.ndarray:
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def features(joints: np.ndarray) -> dict:
    """What the rig can show of the joints (frames x 17 x 3): the torso's
    frame, the directions of the bones of the arms in it, of the legs in the
    body's, the neck's in the torso's, and the shift of the pelvis."""
    up = unit(joints[:, THORAX] - joints[:, PELVIS])
    across = joints[:, R_SHOULDER] - joints[:, L_SHOULDER]
    across = unit(across - np.sum(across * up, -1, keepdims=True) * up)
    back = np.cross(across, up)
    frame = np.stack([across, up, back], axis=-1)

    def local(v):
        return np.einsum("nji,nj->ni", frame, v)

    return {
        "frame": frame,
        "upper": np.stack(
            [
                unit(local(joints[:, e] - joints[:, s]))
                for s, e in [(L_SHOULDER, L_ELBOW), (R_SHOULDER, R_ELBOW)]
            ],
            1,
        ),
        "fore": np.stack(
            [
                unit(local(joints[:, w] - joints[:, e]))
                for e, w in [(L_ELBOW, L_WRIST), (R_ELBOW, R_WRIST)]
            ],
            1,
        ),
        "thigh": np.stack(
            [unit(joints[:, k] - joints[:, h]) for h, k in [(L_HIP, L_KNEE), (R_HIP, R_KNEE)]], 1
        ),
        "shin": np.stack(
            [unit(joints[:, a] - joints[:, k]) for k, a in [(L_KNEE, L_ANKLE), (R_KNEE, R_ANKLE)]],
            1,
        ),
        "neck": unit(local(joints[:, HEAD] - joints[:, THORAX])),
        "nose": unit(local(joints[:, NOSE] - joints[:, HEAD])),
        "offset": joints[:, PELVIS],
    }


def measure(joints: np.ndarray, kind: str, side: int) -> np.ndarray:
    """How far the move went at each frame, from its first frame (larger:
    further)."""
    base = joints[:3].mean(axis=0)
    if kind == "wrist":
        wrist = [L_WRIST, R_WRIST][side]
        return np.linalg.norm(joints[:, wrist] - base[wrist], axis=-1)
    if kind == "knee":
        knee = [L_KNEE, R_KNEE][side]
        return joints[:, knee, 1] - base[knee, 1]
    if kind == "duck":
        return base[PELVIS, 1] - joints[:, PELVIS, 1]
    if kind == "jump":
        return joints[:, PELVIS, 1] - base[PELVIS, 1]
    if kind == "slip":
        lean = joints[:, HEAD, 0] - joints[:, PELVIS, 0]
        return (lean[:3].mean() - lean) if side == 0 else (lean - lean[:3].mean())
    if kind == "cover":
        return 0.5 * (
            np.linalg.norm(joints[:, L_WRIST] - base[L_WRIST], axis=-1)
            + np.linalg.norm(joints[:, R_WRIST] - base[R_WRIST], axis=-1)
        )
    raise ValueError(kind)


def average_move(sessions: list, call: str, kind: str, side: int) -> dict:
    """Find the repetitions of the move after each of its calls, align them on
    their peaks, and average them."""
    reps = []
    for session in sessions:
        t = session["t"]
        for at, name in session["marks"]:
            if name != f"call:{call}":
                continue
            begin = np.searchsorted(t, at - 0.1)
            end = np.searchsorted(t, at + 1.9)
            if end - begin < 40 or not session["valid"][begin:end].all():
                continue
            joints = session["joints"][begin:end]
            amount = measure(joints, kind, side)
            # NOTE (mristin):
            # He reacts to the call after a moment; the peak comes within 1.5 s.
            search = int(1.5 * FPS)
            peak = int(np.argmax(amount[:search]))
            if kind == "cover":
                peak = int(np.argmax(amount[:search] >= 0.9 * amount[:search].max()))
            height = amount[peak]
            onset = peak
            while onset > 0 and amount[onset] > 0.15 * height:
                onset -= 1
            back = peak
            while back < len(amount) - 1 and amount[back] > 0.2 * height:
                back += 1
            reps.append(
                {"joints": joints, "peak": peak, "onset": onset, "back": back, "height": height}
            )
    heights = np.array([rep["height"] for rep in reps])
    typical = np.median(heights)
    reps = [
        rep for rep in reps if 0.4 * typical <= rep["height"] <= 2.5 * typical and rep["onset"] > 0
    ]
    before = min(int(np.median([rep["peak"] - rep["onset"] for rep in reps])) + 3, int(0.8 * FPS))
    if kind == "cover":
        after = int(0.3 * FPS)
    else:
        after = min(int(np.median([rep["back"] - rep["peak"] for rep in reps])) + 3, int(0.9 * FPS))
    stacks = []
    for rep in reps:
        joints = rep["joints"]
        lo, hi = rep["peak"] - before, rep["peak"] + after + 1
        if lo < 0 or hi > len(joints):
            continue
        stacks.append(features(joints[lo:hi]))
    mean = mean_features(stacks)
    hit = before
    if call.startswith("hook") or call.startswith("uppercut"):
        # NOTE (mristin):
        # The farthest reach from the guard is the swing out of a hook and the
        # dip of an uppercut; the impact comes after: a hook lands when the
        # glove has come across, nearest the middle of him, and an uppercut
        # at its highest.
        gloves = glove_path(mean, side)
        span = range(before, min(len(gloves), before + int(0.5 * FPS)))
        if call.startswith("hook"):
            hit = min(span, key=lambda n: abs(gloves[n][0]))
        else:
            hit = max(span, key=lambda n: gloves[n][1])
    return {"frames": mean, "hit": hit, "reps": len(stacks), "kind": kind}


def glove_path(mean: dict, side: int) -> np.ndarray:
    """The glove of the side through the averaged move, in the rig's body."""
    shoulder = RIG_SHOULDER * np.array([-1.0 if side == 0 else 1.0, 1.0, 1.0])
    local = shoulder + mean["upper"][:, side] * RIG_UPPER_ARM + mean["fore"][:, side] * RIG_FOREARM
    return (
        np.einsum("nij,nj->ni", mean["frame"], local)
        + mean["offset"]
        + np.array([0.0, RIG_TORSO_Y, 0.0])
    )


def mean_features(stacks: list) -> dict:
    mean = {}
    for key in stacks[0]:
        values = np.mean([stack[key] for stack in stacks], axis=0)
        if key == "frame":
            u, _, vt = np.linalg.svd(values)
            values = u @ vt
        elif key != "offset":
            values = unit(values)
        mean[key] = values
    return mean


def guard_loop(sessions: list) -> dict:
    """A loop of 2 s of the guard: of all the windows of the guard of all the
    sessions, the one whose end best meets its start, and the end blended into
    the start."""
    length, blend = int(2 * FPS), int(0.4 * FPS)
    best = None
    for session in sessions:
        mask = (session["labels"] == "guard") & session["valid"]
        indices = np.flatnonzero(mask)
        for start in indices[::3]:
            span = np.arange(start, start + length + blend)
            if span[-1] >= len(mask) or not mask[span].all():
                continue
            joints = session["joints"][span]
            jump = np.linalg.norm(joints[length] - joints[0], axis=-1).mean()
            # NOTE (mristin):
            # Some bounce, but not a step aside.
            drift = np.linalg.norm(joints[:, PELVIS] - joints[:, PELVIS].mean(0), axis=-1).max()
            score = jump + 0.5 * max(0.0, drift - 0.08)
            if best is None or score < best[0]:
                best = (score, session["name"], joints)
    joints = best[2]
    loop = joints[:length].copy()
    for j in range(blend):
        weight = j / blend
        loop[j] = joints[length + j] * (1 - weight) + joints[j] * weight
    loop[:, :, :] -= loop[:, PELVIS : PELVIS + 1, :].mean(axis=0) * np.array([1, 0, 1])
    print(f"The guard loop from {best[1]} (score {best[0]:.3f}).")
    return {"frames": features(loop), "hit": 0, "kind": "guard"}


# ---------------------------------------------------------------------------
# Fitting the rig
# ---------------------------------------------------------------------------


def rx(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler_yxz(m: np.ndarray) -> np.ndarray:
    """The angles [x, y, z] of Godot's order YXZ (m = Ry Rx Rz)."""
    x = np.arcsin(np.clip(-m[1, 2], -1.0, 1.0))
    y = np.arctan2(m[0, 2], m[2, 2])
    z = np.arctan2(m[1, 0], m[1, 1])
    return np.array([x, y, z])


DOWN = np.array([0.0, -1.0, 0.0])


def arm_points(p):
    """The elbow and the glove of an arm, from its shoulder, in the torso:
    p = [yaw, pitch, roll, elbow]."""
    shoulder = ry(p[0]) @ rx(p[1]) @ rz(p[2])
    elbow = shoulder @ DOWN * RIG_UPPER_ARM
    glove = elbow + shoulder @ rx(p[3]) @ DOWN * RIG_FOREARM
    return elbow, glove


def leg_points(p):
    """The knee and the ankle of a leg, from its hip: p = [pitch, roll, knee]."""
    hip = rx(p[0]) @ rz(p[1])
    knee = hip @ DOWN * RIG_THIGH
    ankle = knee + hip @ rx(p[2]) @ DOWN * RIG_SHIN
    return knee, ankle


def fit_clip(f: dict) -> tuple:
    count = len(f["offset"])
    arms = [np.array([0.0, 0.55, -0.25, 1.95]), np.array([0.0, 0.55, 0.25, 1.95])]
    legs = [np.zeros(3), np.zeros(3)]
    frames = []
    errors = []
    for n in range(count):
        out_arms = []
        for i in range(2):
            elbow = f["upper"][n, i] * RIG_UPPER_ARM
            glove = elbow + f["fore"][n, i] * RIG_FOREARM
            outwards = -1.0 if i == 0 else 1.0

            def residual(p, elbow=elbow, glove=glove, outwards=outwards):
                e, g = arm_points(p)
                # NOTE (mristin):
                # A light pull towards no twist, for the straight arm, whose
                # twist the joints do not tell.
                return np.concatenate(
                    [e - elbow, g - glove, [0.05 * p[0], 0.02 * (p[2] - 0.25 * outwards)]]
                )

            lower = [-1.6, -1.2, -2.0, 0.0]
            upper = [1.6, 3.2, 2.0, 2.6]
            start = np.clip(arms[i], np.array(lower) + 1e-3, np.array(upper) - 1e-3)
            solution = least_squares(residual, start, bounds=(lower, upper)).x
            arms[i] = solution
            e, g = arm_points(solution)
            errors.append(0.5 * (np.linalg.norm(e - elbow) + np.linalg.norm(g - glove)))
            out_arms.append([solution[0], solution[1], solution[2], solution[3]])
        out_legs = []
        for i in range(2):
            knee = f["thigh"][n, i] * RIG_THIGH
            ankle = knee + f["shin"][n, i] * RIG_SHIN

            def residual(p, knee=knee, ankle=ankle):
                k, a = leg_points(p)
                return np.concatenate([k - knee, a - ankle])

            lower, upper = [-0.8, -0.6, -2.5], [2.2, 0.6, 0.0]
            start = np.clip(legs[i], np.array(lower) + 1e-3, np.array(upper) - 1e-3)
            solution = least_squares(residual, start, bounds=(lower, upper)).x
            legs[i] = solution
            k, a = leg_points(solution)
            errors.append(0.5 * (np.linalg.norm(k - knee) + np.linalg.norm(a - ankle)))
            out_legs.append(list(solution))
        torso = euler_yxz(f["frame"][n])
        neck = f["neck"][n]
        nose = f["nose"][n]
        # NOTE (mristin):
        # The depths of the torso's joints are calibrated on his standing, so
        # that the neck stands upright in the torso then.
        head = [
            float(np.arctan2(neck[2], neck[1])),
            # NOTE (mristin):
            # The turn of the head from how far the nose is to the side of the
            # eyes (its depth is not to be trusted): to his left, positive.
            float(np.arcsin(np.clip(-nose[0], -0.6, 0.6))),
            float(np.arctan2(-neck[0], neck[1])),
        ]
        frames.append(
            {
                "arms": [[round(float(v), 3) for v in arm] for arm in out_arms],
                "legs": [[round(float(v), 3) for v in leg] for leg in out_legs],
                "torso": [round(float(v), 3) for v in torso],
                "head": [round(v, 3) for v in head],
                "offset": [round(float(v), 3) for v in f["offset"][n]],
            }
        )
    return frames, float(np.mean(errors))


def glove(frame: dict, i: int) -> np.ndarray:
    """Where the glove of the arm is in the body (the rig's root), by forward
    kinematics of the fitted angles."""
    torso_angles = frame["torso"]
    torso = ry(torso_angles[1]) @ rx(torso_angles[0]) @ rz(torso_angles[2])
    shoulder = RIG_SHOULDER * np.array([-1.0 if i == 0 else 1.0, 1.0, 1.0])
    _, g = arm_points(frame["arms"][i])
    return np.array([0.0, RIG_TORSO_Y, 0.0]) + np.array(frame["offset"]) + torso @ (shoulder + g)


def report(clip: str, data: dict, features: dict, error: float) -> None:
    frames = data["frames"]
    hit = frames[data["hit"]]
    first = frames[0]
    gloves = " ".join(
        f"{side} {np.round(glove(first, i), 2)}->{np.round(glove(hit, i), 2)}"
        for i, side in enumerate(["L", "R"])
    )
    knees = [round(float(-np.cos(hit["legs"][i][0]) * RIG_THIGH + RIG_HIP[1]), 2) for i in range(2)]
    print(
        f"{clip:15s} frames {len(frames):3d} hit {data['hit']:3d} reps {data.get('reps', '-')} "
        f"fit {error * 100:.1f} cm | gloves {gloves} | knees y {knees} | "
        f"offset {np.round(hit['offset'], 2)} | torso {np.round(hit['torso'], 2)}"
    )


if __name__ == "__main__":
    sys.exit(main())
