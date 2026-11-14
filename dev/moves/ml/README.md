# The move classifier

The fight finds the player's moves with a classifier trained on labelled
recordings: the straights, the hooks, the uppercuts and the kicks (each left
or right; a kick is a knee raised high, since the camera need not see the
whole leg), the ducks, the jumps, the slips (left or right) and the cover.
The game runs it in `scenes/vision/core/MoveClassifier.cs`, with the model in
`scenes/vision/moves/model/`.

## How it works

1. **The poses.** RTMPose-t (top-down, `RtmPoseTracker`) follows the player
   on every camera frame; RTMO only finds her at the start or when she was
   lost.
2. **The features** (`MoveFeatures`, the same as `moves_ml.sequences`): the
   last 4 poses, 0.1 s apart (linearly interpolated, so the frame rate does
   not matter), relative to the middle of the shoulders now, in units of the
   median torso length of the last 2 s. So they are scale invariant: a child
   far away and an adult close by give the same features. They use the nose,
   the shoulders, the elbows, the wrists, the hips and the knees, but not the
   ankles: the camera saw a child's feet but not an adult's, and with the
   ankles the classifier made five times more false moves on the child.
3. **The model**: XGBoost (`moves_xgboost.json`), evaluated in plain C#
   (`GradientBoostedTrees`; it agrees with XGBoost to about 1e-7).
4. **The moves** (`MoveClassifier.Decide`): the strikes of one side decide
   within 0.2 s on the class of the most probability over the movement (a hook
   starts like a straight); the ducks, the jumps and the slips fire at once;
   the cover is a state.

## Recording and training

See [Recording and retraining the moves](../../../CONTRIBUTING.md#recording-and-retraining-the-moves)
in CONTRIBUTING.md for the steps: record with the frames, compute the poses
(`poses/`), leave out what went wrong (`<recording>.skip.csv`, `people.py`),
evaluate across the sessions (`cross_session.py`), retrain on all the
recordings (`export.py`) and check it in the game (`replay_with_poses.py`).

The labels come from the calls of the plan: each move is anchored where it
peaks after its call (e.g., where the wrist is farthest from the guard).

The training augments every recording: shrunk (0.35–0.7×) and enlarged
(1.3–1.8×) copies, half of them with the proportions of a child (shorter
limbs, a bigger head), a slight wobble of the scale and a jitter of the key
points, and all of them mirrored (left and right swapped).

`train.py` also compares the time-series networks (`conv`, `tcn`, `gru`). On
the first recording (one player, 54 moves, 5 folds), XGBoost on 4 poses over
0.3 s won: 52 of 54 moves classified right, the fewest false moves (about 8 a
minute) and the same on poses shrunk to a child; the networks were not more
accurate but gave more false moves, and are 10 to 50 times slower.

`viewer.py` plays a recording with RTMPose-t running live on its frames.

## Across the sessions

`cross_session.py` on the three sessions so far (2026-11-14): two of an adult
(54 called moves each) and one of a child (30 moves left after the cuts: the
child skipped or mixed up calls, and other children came into the picture for
the last minute).

| Test on | Trained on the others | + the other folds of the test |
|---|---|---|
| adult, 1st session | 49/54, 26 false/min, cover 75% | 51/54, 17 false/min, cover 96% |
| adult, 2nd session | 48/54, 20 false/min, cover 77% | 51/54, 26 false/min, cover 77% |
| child | **13/30**, 14 false/min | 17/30, 35 false/min |

The adult sessions carry over to each other, but **not to the child**: the
augmentation fakes a child's size and proportions, not how a child moves,
and transforms measured from the child (lower hands, other arm proportions,
slower moves, more jitter) did not help either. With a part of the child's
own session, it got 17 of 30 right. The false moves on the child are partly
the child moving between the calls, which the labels count as no move.

Leaving out the ankles (see above) cut the false moves on the child, trained
on the adults only, from 98 to 14 a minute; on the adults it costs a few
false moves a minute, and with the child's own session 17 instead of 21 of
its 30 moves (few moves, so a noisy number).

## Known limits

It needs more recordings of children above all, with the calls followed (and
nobody else in the picture), then other players, days, clothes, light and
camera places, and more time without moves (to bring down the false moves).
