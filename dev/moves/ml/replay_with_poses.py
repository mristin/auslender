"""Make a replay of a recording with the poses of the game on every frame.

A recording holds the poses of RTMO, a few times a second; poses/ (the pose
of the game, RTMPose-t) gives one on every frame. This writes a copy of the
recording with those poses instead, and links its frames, so that the game
replays the session as it would see it live:

    python replay_with_poses.py <recording.jsonl> <poses.jsonl>

writes <recording>-rtmpose.jsonl (and <recording>-rtmpose.frames), to play
with `$GODOT --path . -- --replay=<recording>-rtmpose.jsonl`, or headless with
dev/moves/print_replay.gd.
"""

import json
import pathlib
import sys


def main() -> int:
    recording = pathlib.Path(sys.argv[1])
    poses = pathlib.Path(sys.argv[2])
    stem = recording.with_suffix("")
    out = pathlib.Path(f"{stem}-rtmpose.jsonl")
    with out.open("w") as writer:
        for line in recording.open():
            if json.loads(line)["kind"] != "pose":
                writer.write(line)
        for line in poses.open():
            row = json.loads(line)
            writer.write(
                json.dumps({"kind": "pose", "t": row["t"], "label": "", "pose": row["pose"]}) + "\n"
            )

    frames = pathlib.Path(f"{stem}.frames")
    link = pathlib.Path(f"{stem}-rtmpose.frames")
    if frames.exists() and not link.exists():
        link.symlink_to(frames.name)
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
