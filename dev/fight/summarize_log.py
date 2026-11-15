"""Summarize the logs of rhythm fights (see scenes/fight/fight_log.gd), to see
how a fight plays: how the player met the notes, kind by kind; how far off
the beat his moves were seen (the latency of the vision); the moves which met
no note; how long he stood in each pose; and how the fights ended.

python summarize_log.py [<fight.jsonl> ...]

Without arguments, it reads the latest log of
~/.local/share/godot/app_userdata/Auslender/fight_logs/.
"""

import collections
import json
import pathlib
import statistics
import sys

LOGS = pathlib.Path.home() / ".local/share/godot/app_userdata/Auslender/fight_logs"


def read(path):
    with open(path, encoding="utf-8") as lines:
        return [json.loads(line) for line in lines if line.strip()]


def summarize(path):
    events = read(path)
    print(f"== {path}")
    if not events:
        print("(empty)")
        return
    scene = next((e for e in events if e["event"] == "scene"), {})
    print(f"input: {scene.get('input')}, length: {events[-1]['t']:.0f} s")

    # NOTE: the notes met come as moves (punches) and notes (dodges); the
    # missed ones as notes.
    by_kind = collections.defaultdict(collections.Counter)
    for e in events:
        if e["event"] == "move" and e.get("matched"):
            by_kind[e["note"]][e["result"]] += 1
        elif e["event"] == "note":
            by_kind[e["kind"]][e["result"]] += 1
    print("\nNotes:")
    for kind, results in sorted(by_kind.items()):
        total = sum(results.values())
        text = ", ".join(f"{r} {n} ({100 * n / total:.0f}%)" for r, n in results.most_common())
        print(f"  {kind:<11} {total:>3}: {text}")

    moves = [e for e in events if e["event"] == "move"]
    matched = [m for m in moves if m.get("matched")]
    if moves:
        print(f"\nMoves: {len(moves)}, met a note: {len(matched)}")
        stray = collections.Counter(
            f"{m['kind']} {m['side']}" for m in moves if not m.get("matched")
        )
        if stray:
            print("  met none:", ", ".join(f"{k} {n}" for k, n in stray.most_common()))
        wrong = sum(1 for m in matched if m["note"] != m["kind"])
        if wrong:
            print(f"  the wrong punch of the right hand: {wrong}")
    seen = [m["song"] - (m["offset"] + m["latency"]) for m in matched if m["source"] == "vision"]
    if matched:
        offsets = [m["offset"] for m in matched]
        print(
            f"  off the beat (after the latency): median {statistics.median(offsets):+.2f} s,"
            f" spread {statistics.pstdev(offsets):.2f} s"
        )
    if seen:
        after = [
            m["song"] - b for m, b in zip([m for m in matched if m["source"] == "vision"], seen)
        ]
        print(f"  seen after the beat: median {statistics.median(after):.2f} s")

    dodges = [
        e
        for e in events
        if e["event"] == "note"
        and e["kind"] in ("cover", "slip_left", "slip_right", "duck", "jump")
    ]
    if dodges:
        print("\nDodges:")
        for d in dodges:
            last = {
                k: round(v - d["beat"], 2)
                for k, v in d.get("poses", {}).items()
                if v - d["beat"] > -3
            }
            print(
                f"  {d['beat']:6.1f} s {d['kind']:<10} {d['result']:<7} {d.get('by', ''):<10} poses vs beat: {last}"
            )

    found = collections.Counter(
        f"{e['kind']} {e.get('side', '')}".strip() for e in events if e["event"] == "dodge_move"
    )
    if found:
        print("\nDodge moves found:", ", ".join(f"{k} {n}" for k, n in found.most_common()))

    poses = [e for e in events if e["event"] == "pose"]
    held = collections.Counter()
    for a, b in zip(poses, poses[1:]):
        held[a["pose"] or "ready"] += b["t"] - a["t"]
    if held:
        print("Time in each pose:", ", ".join(f"{k} {v:.0f} s" for k, v in held.most_common()))

    states = [e for e in events if e["event"] == "state"]
    unseen = sum(1 for s in states if s.get("sees_player") is False)
    if unseen:
        print(f"Player not seen: about {unseen} s")
    pauses = sum(1 for e in events if e["event"] == "pause")
    if pauses:
        print(f"Paused {pauses} time(s)")
    latencies = [s["latency"] for s in states if s.get("phase") == "PLAYING"]
    if latencies:
        print(f"Latency learned: {latencies[0]:.2f} -> {latencies[-1]:.2f} s")

    print("\nEnds:")
    for e in events:
        if e["event"] == "fight_end":
            details = ""
            if "counts" in e:
                details = (
                    f" grade {e['grade']} accuracy {100 * e['accuracy']:.0f}% {e['counts']}"
                    f" best combo {e['best_combo']} health {e['health']:.0f} his {e['his_health']:.0f}"
                )
            print(
                f"  {e['t']:7.1f} s {e['why']:<10} song {e['song']:.0f} s score {e['score']}{details}"
            )
    print()


def main():
    paths = sys.argv[1:] or [max(LOGS.glob("fight-*.jsonl"), key=lambda p: p.stat().st_mtime)]
    for path in paths:
        summarize(path)


if __name__ == "__main__":
    main()
