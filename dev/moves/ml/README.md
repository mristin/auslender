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
   far away and an adult close by give the same features.
3. **The model**: XGBoost (`moves_xgboost.json`), evaluated in plain C#
   (`GradientBoostedTrees`; it agrees with XGBoost to about 1e-7).
4. **The moves** (`MoveClassifier.Decide`): the strikes of one side decide
   within 0.2 s on the class of the most probability over the movement (a hook
   starts like a straight); the ducks, the jumps and the slips fire at once;
   the cover is a state.

## Recording and training

See [Recording and retraining the moves](../../../CONTRIBUTING.md#recording-and-retraining-the-moves)
in CONTRIBUTING.md for the steps: record with the frames, compute the poses
(`poses/`), cross-validate (`train.py`), retrain on all the recordings
(`export.py`) and check it in the game (`replay_with_poses.py`).

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

## Known limits

All of it so far comes from **one** player in **one** session. It needs more
recordings: other players (above all children), other days, clothes, light
and camera places, and more time without moves (to bring down the false
moves).
