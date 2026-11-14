# Contributing

Thank you for helping with Auslender!
This guide explains how to set up the development environment, how to run and check the game, and how to record more moves and retrain the move classifier.

## Overview

The game is made with [Godot] 4.6 (.NET), written in GDScript and C#:

* The vision runs in C# (`scenes/vision/`), all on the CPU through ONNX Runtime:
  * RTMPose-t follows the player's body pose on every camera frame (`RtmPoseTracker`); RTMO-t only finds her at the start or when she was lost.
  * YOLOX finds the head and the hands, and YuNet the face landmarks, for the looks over the face (the unibrow and the mladež) on another thread.
  * The **move classifier** (`MoveClassifier`) reads the last few poses and gives the moves: the straights, the hooks, the uppercuts and the kicks (a kick is a knee raised high, since the camera need not see the whole leg), left or right, the ducks, the jumps, the slips and the cover. It is an XGBoost model, evaluated in plain C# (`GradientBoostedTrees`), trained on labelled recordings (see [Recording and retraining the moves](#recording-and-retraining-the-moves)).

  The core (`scenes/vision/core/`) does not depend on Godot, so we unit-test it with plain .NET in `tests/Auslender.Tests/`.
  The node `VisionService` runs it all in the game and offers plain getters to GDScript; the autoload `Vision` keeps it running across the scenes.
* The game itself is in GDScript (`scenes/`): for now the fight (`scenes/fight/`). See [DESIGN.md](DESIGN.md) for the design.
* The development tools live in `dev/`, which Godot ignores, so that they are never released with the game.

[Godot]: https://godotengine.org

## Setting up the development environment

You need:

* [Git] and [Git LFS], since we keep the ONNX models and the images in LFS,
* the [.NET 8 SDK],
* the **.NET** build of [Godot 4.6.2] (also called "mono"; the standard build can not run C#),
* [Python] 3.10 or newer, for the formatter, the linter and the training, and
* a webcam which supports 640x480.

[Git]: https://git-scm.com
[Git LFS]: https://git-lfs.com
[.NET 8 SDK]: https://dotnet.microsoft.com/download/dotnet/8.0
[Godot 4.6.2]: https://godotengine.org/download/archive/4.6.2-stable/
[Python]: https://www.python.org/downloads/

Clone the repository with its models:

```
git lfs install
git clone https://github.com/mristin/auslender.git
cd auslender
git lfs pull
```

Download the .NET build of Godot 4.6.2 and unpack it anywhere.
Our scripts find Godot through the `GODOT` environment variable, or as `godot` on your path, e.g.:

```
export GODOT=~/apps/Godot_v4.6.2-stable_mono_linux_x86_64/Godot_v4.6.2-stable_mono_linux.x86_64
```

Install the development tools (the formatters and the linter):

```
python3 -m venv venv
touch venv/.gdignore
venv/bin/pip install -r dev/requirements.txt
```

The tools for the training are separate (they are big, and only needed to retrain):

```
python3 -m venv venv-ml
touch venv-ml/.gdignore
venv-ml/bin/pip install -r dev/moves/ml/requirements.txt
```

Build the C# code once before you start Godot:

```
dotnet build Auslender.sln
```

## Running the game

```
$GODOT --path .
```

Set up the camera as the [README](README.md) describes.
The fight also plays with the keyboard, without the camera (`-- --no-camera`); the keys are listed at the bottom of the screen and in `scenes/fight/fight.gd`.

To play a recording instead of the camera, pass `-- --replay=<recording.jsonl>`: the game shows its frames (from `<recording>.frames/`) as the camera picture.
To see headless what the game makes of a recording, every move with its time:

```
$GODOT --headless --fixed-fps 30 --path . --script dev/moves/print_replay.gd -- --replay=<recording.jsonl>
```

## Checking your changes

Before you push, re-format and run all the checks (the linter, the C# tests, and the scenes started headless):

```
venv/bin/python dev/continuous_integration/precommit.py
```

Pass `--select` or `--skip` with the names of the steps to run only some of them, e.g., `--select test`.
The continuous integration runs the same checks on every pull request.

## Recording and retraining the moves

The move classifier is only as good as its recordings.
All of it so far comes from **one** player in **one** session, so every new recording helps, above all:

* **other players**, especially children (the game is meant for them, and the augmentation only fakes their size and proportions, not how they move);
* **other days, clothes, light and rooms**, and other places of the camera (on the floor worked best so far; also try a chair);
* **more time without moves** (bouncing in the guard, resting, wiping the face, looking around): it teaches the classifier what is *not* a move, and brings down the false moves.

### Privacy and consent

A recording with `--frames` saves **every camera picture** of the session (the game itself never does).
Record only people who agreed to it, and for children their parents, too.
Keep the recordings on your computer (by convention in `~/auslender-video/`); **never commit them** nor upload them anywhere.
Only the trained model (numbers, no pictures) goes into the repository.

### 1. Record a session

Put the camera low (on the floor, tilted up a little, or on a low chair), and stand 2.5 to 3 m away, so that it sees you from the head to below the knees.
Then follow the plan of the fight, with the frames saved:

```
$GODOT --path . --script dev/moves/record_moves.gd -- \
    --plan=res://dev/moves/plans/fight.csv --frames \
    ~/auslender-video/fight-<player>-<date>.jsonl
```

The recorder waits until it sees you, counts down, and then walks you through the plan (`dev/moves/plans/fight.csv`, about 3.5 minutes): the guard, the cover, looking around, the slips, five of each punch with each hand, one-twos, kicks (raise your knee high), ducks, jumps and fighting freely.
At each call, it beeps and shows the move big; do the move once, then go back to your guard.
The recording marks each call, which gives the labels.
Escape stops early and keeps what was recorded.

It writes `fight-<player>-<date>.jsonl` (what the vision measured, the steps and the calls) and `fight-<player>-<date>.frames/` (the pictures, about 375 MB for a session).

If you change the plan, keep the names of the calls (`straight_left`, `hook_right`, `front_kick_left`, `duck`, `cover`, …): the training reads them (see `label_frames` in `dev/moves/ml/moves_ml.py`).

### 2. Compute the poses

Run the pose of the game (RTMPose-t, exactly as in the game) on every frame of the recording:

```
dotnet run --project dev/moves/ml/poses -c Release -- \
    ~/auslender-video/fight-<player>-<date>.jsonl \
    ~/auslender-video/fight-<player>-<date>.poses.jsonl
```

It takes about 2 minutes for a session.
To watch the recording with the pose running live on its frames (space pauses, q quits):

```
venv-ml/bin/python dev/moves/ml/viewer.py ~/auslender-video/fight-<player>-<date>.jsonl \
    ~/auslender-video/fight-<player>-<date>.frames scenes/vision/rtmpose/model/rtmpose_t_body7_256x192.onnx
```

### 3. Evaluate on the new recording

Cross-validate the classifier on the recording (5 folds: each holds out one repetition of every move), also on its poses shrunk to the size of a child and enlarged:

```
cd dev/moves/ml
../../../venv-ml/bin/python train.py \
    ~/auslender-video/fight-<player>-<date>.jsonl ~/auslender-video/fight-<player>-<date>.poses.jsonl \
    xgb "0.3 s"
cd ../../..
```

It prints how many moves it found, how many of the right class, the false moves a minute, how well it holds the cover, and the moves it confused.
Compare with the numbers in `dev/moves/ml/README.md`.
A recording which scores much worse than the others is worth a look with the viewer: the player may have been cut off by the picture, or done the moves late.

### 4. Retrain on all the recordings

Train the model on **all** the recordings together, and write it into the game:

```
cd dev/moves/ml
../../../venv-ml/bin/python export.py ../../../scenes/vision/moves/model \
    ~/auslender-video/fight-floor-20261114-094437.jsonl ~/auslender-video/fight-floor-20261114-094437.poses.jsonl \
    ~/auslender-video/fight-<player>-<date>.jsonl ~/auslender-video/fight-<player>-<date>.poses.jsonl
cd ../../..
```

It augments every recording (shrunk and enlarged copies, half of them with the proportions of a child, a jitter of the key points, and all of them mirrored), and writes `scenes/vision/moves/model/moves.json` (the description: the classes, the offsets of the poses, the recordings it was trained on) and `moves_xgboost.json` (the model).

### 5. Check it in the game

Make a replay of a recording with the poses of the game on every frame, and see what the game makes of it:

```
venv-ml/bin/python dev/moves/ml/replay_with_poses.py \
    ~/auslender-video/fight-<player>-<date>.jsonl ~/auslender-video/fight-<player>-<date>.poses.jsonl
$GODOT --headless --fixed-fps 30 --path . --script dev/moves/print_replay.gd -- \
    --replay=$HOME/auslender-video/fight-<player>-<date>-rtmpose.jsonl
```

Each call of the plan should give its move (e.g., five `hook left` in the step "hook left"), and the steps without moves (the guard, looking around) none.
Play-test it live in front of the camera, too.
Then run the checks (`dev/continuous_integration/precommit.py`; the tests load the model) and commit the two model files.

### Changing the features or the model

The features are computed twice: in Python for the training (`sequences` in `dev/moves/ml/moves_ml.py`) and in C# for the game (`MoveFeatures`).
If you change them, change both, and regenerate the case of the parity test (`tests/Auslender.Tests/data/move_features_cases.json`) with the Python, so that `MoveFeaturesTests` checks that both agree.
Keep every model evaluable in C# without new dependencies (XGBoost as JSON, or a network as ONNX through `OnnxMoveModel`).
