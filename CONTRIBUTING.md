# Contributing

Thank you for helping with Auslender!
This guide explains how to set up the development environment, how to run and check the game, and how to record more moves and retrain the move classifier.

## Overview

The game is made with [Godot] 4.6 (.NET), written in GDScript and C#:

* The vision runs in C# (`scenes/vision/`), all on the CPU through ONNX Runtime:
  * RTMPose-t follows the player's body pose on every camera frame (`RtmPoseTracker`); RTMO-t only finds him at the start or when he was lost.
  * YOLOX finds the head and the hands, and YuNet the face landmarks (the eyes, for the size and the height of the head), on another thread.
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

## Packaging

The export presets (`export_presets.cfg`) package the game for Linux, Windows and macOS into `build/`.
You need the export templates of Godot 4.6.2 (.NET) (in the editor: Editor, Manage Export Templates), then:

```
venv/bin/python dev/package.py
```

Pass `--platforms` to package only some, e.g., `--platforms windows`.
The script exports the presets, adds `LICENSE`, `licenses/` and the licenses of the models and of ONNX Runtime to every package, and copies the camera extension next to the Windows executable (see below).
It fails if Godot reports an error (Godot exits with zero even if it fails to build the C# part) or a package misses ONNX Runtime.

When a release is published on GitHub, the workflow `.github/workflows/publish.yaml` runs the script and attaches the zipped packages to the release (`auslender-<version>-linux-x86_64.zip`, `-windows-x86_64.zip`, `-macos-universal.zip`).
You can also start it by hand: without a tag, it only tries out the packaging and keeps the packages as the artifacts of the run; with the tag of an existing release, it attaches them to that release.
It also puts a `.gdignore` into `build/`, which hides the packages from Godot; otherwise Godot would try to load the camera extension of the Windows package on every platform, and fail.

Ship the whole folder (the executable, the `.pck` and the `data_Auslender_*` folder with the .NET runtime and ONNX Runtime), or the archive on macOS.

Mind the limits of the platforms:

* **Windows:** Godot 4.6 implements no camera on Windows, so we use [CameraServerExtension] there, and only there, from `addons/CameraServerExtension/` (the prebuilt Windows x86_64 library of its release 2026.03.27, as in Bird Dog and Steppe Rescue).
  Godot reports an error on every platform which an extension lists no library for, so the directory is hidden from Godot (`.gdignore`); `VisionService` loads the extension itself on Windows (`StartCameraExtension`), from the directory of the executable, or from the project in the editor.
  Hence the packaging copies `CameraServerExtension.gdextension` and `libcameraserver-extension.windows.dll` next to the executable.
  The formats of the extension's feeds are reached by name (the methods of `CameraFeed` do not reach them), and Windows calls YUYV "YUY2".
  Without the extension, or if Windows denies the camera, the game tells so.
  Drop the extension once Godot supports the camera on Windows itself ([godotengine/godot#108538]).
* **macOS:** The app is universal and runs on the Intel and the Apple Silicon Macs.
  We stay with ONNX Runtime 1.19, the last version whose libraries for macOS run on macOS 11 (from 1.20 on, they need macOS 13.3, and from 1.24 on, there is none for the Intel Macs).
  The app is signed ad hoc and not notarized, so the player opens it the first time with a right click and Open.
  The camera on macOS lists no formats and delivers its frames as two planes (Y and CbCr), which `VisionService` converts to RGB itself.
  On the first start, macOS asks for the permission to use the camera.

[CameraServerExtension]: https://github.com/j20001970/godot-cameraserver-extension
[godotengine/godot#108538]: https://github.com/godotengine/godot/pull/108538

## Recording and retraining the moves

The move classifier is only as good as its recordings.
All of it so far comes from three sessions: two of an adult, and one of a child with much of it left out, so every new recording helps, above all:

* **other players**, especially children (the game is meant for them, and the augmentation only fakes their size and proportions, not how they move);
* **other days, clothes, light and rooms**, and other places of the camera (on the floor worked best so far; also try a chair);
* **more time without moves** (bouncing in the guard, resting, wiping the face, looking around): it teaches the classifier what is *not* a move, and brings down the false moves.

### Privacy and consent

A recording with `--frames` saves **every camera picture** of the session (the game itself never does).
Record only people who agreed to it, and for children their parents, too.
Keep the recordings on your computer (by convention in `~/auslender-video/`, a folder for each session); **never commit them** nor upload them anywhere.
Only the trained model (numbers, no pictures) goes into the repository.

### 1. Record a session

Put the camera low (on the floor, tilted up a little, or on a low chair), and stand 2.5 to 3 m away, so that it sees you from the head to below the knees.
Then follow the plan of the fight, with the frames saved:

```
$GODOT --path . --script dev/moves/record_moves.gd -- \
    --plan=res://dev/moves/plans/fight.csv --frames \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl
```

The recorder waits until it sees you, counts down, and then walks you through the plan (`dev/moves/plans/fight.csv`, about 3.5 minutes): the guard, the cover, looking around, the slips, five of each punch with each hand, one-twos, kicks (raise your knee high), ducks, jumps and fighting freely.
At each call, it beeps, shows the name of the move big, and a stick figure next to it does the move, as in a mirror (the moving limb in gold); do the move once with it, then go back to your guard.
The recording marks each call, which gives the labels.
Escape stops early and keeps what was recorded.

It writes, into the folder of the session (made if missing), `fight-<player>-<date>.jsonl` (what the vision measured, the steps and the calls) and `fight-<player>-<date>.frames/` (the pictures, about 375 MB for a session).

If you change the plan, keep the names of the calls (`straight_left`, `hook_right`, `front_kick_left`, `duck`, `cover`, …): the training reads them (see `label_frames` in `dev/moves/ml/moves_ml.py`).

### 2. Compute the poses

Run the pose of the game (RTMPose-t, exactly as in the game) on every frame of the recording:

```
dotnet run --project dev/moves/ml/poses -c Release -- \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.poses.jsonl
```

It takes about 2 minutes for a session.
To watch the recording with the pose running live on its frames (space pauses, q quits):

```
venv-ml/bin/python dev/moves/ml/viewer.py ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.frames scenes/vision/rtmpose/model/rtmpose_t_body7_256x192.onnx
```

### 3. Leave out what went wrong

A recording is only as good as the moves in it.
Leave out the parts where somebody else was in the picture (the vision may then follow the wrong person), and the calls which the player did not follow (a straight left done with the right hand, a slip to the wrong side, a kick without lifting the knee).
List them in `fight-<player>-<date>.skip.csv` next to the recording, one span a line in the time of the recording (`start,end,reason`, `#` starts a comment); the training leaves them out (see `load_skips` in `dev/moves/ml/moves_ml.py`).

`people.py` finds the parts with a second person standing in the picture, and prints them as the lines of the file:

```
venv-ml/bin/python dev/moves/ml/people.py ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl \
    > ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.skip.csv
```

The calls which were not followed you find with the viewer (the times of the calls are the `mark` rows of the recording); add a line for each of them, from just before the call to the next one.

### 4. Evaluate on the new recording

Evaluate the classifier across the sessions:

```
cd dev/moves/ml
../../../venv-ml/bin/python cross_session.py \
    ~/auslender-video/fight-floor-20261114-094437/fight-floor-20261114-094437.jsonl \
    ~/auslender-video/fight-floor-20261114-094437/fight-floor-20261114-094437.poses.jsonl \
    ... \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.poses.jsonl
cd ../../..
```

For each session, it trains on the other sessions only (how well the model does on a session it has never seen), and on the others together with a part of this one (how much the session adds; 5 folds, each holds out one repetition of every move), and tests also on the poses shrunk to the size of a child and enlarged.
It prints how many moves it found, how many of the right class, the false moves a minute, how well it holds the cover, and the moves it confused.
`train.py` cross-validates within a single recording, and compares the XGBoost with the networks.

A recording which scores much worse than the others is worth a look with the viewer: the player may have been cut off by the picture, done the moves late, or not followed the calls.

### 5. Retrain on all the recordings

Train the model on **all** the recordings together, and write it into the game:

```
cd dev/moves/ml
../../../venv-ml/bin/python export.py ../../../scenes/vision/moves/model \
    ~/auslender-video/fight-floor-20261114-094437/fight-floor-20261114-094437.jsonl \
    ~/auslender-video/fight-floor-20261114-094437/fight-floor-20261114-094437.poses.jsonl \
    ~/auslender-video/fight-floor-20261114-161309/fight-floor-20261114-161309.jsonl \
    ~/auslender-video/fight-floor-20261114-161309/fight-floor-20261114-161309.poses.jsonl \
    ~/auslender-video/fight-floor-20261114-164156/fight-floor-20261114-164156.jsonl \
    ~/auslender-video/fight-floor-20261114-164156/fight-floor-20261114-164156.poses.jsonl \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.poses.jsonl
cd ../../..
```

It leaves out the parts in the `.skip.csv` files, augments every recording (shrunk and enlarged copies, half of them with the proportions of a child, a jitter of the key points, and all of them mirrored), and writes `scenes/vision/moves/model/moves.json` (the description: the classes, the offsets of the poses, the recordings it was trained on) and `moves_xgboost.json` (the model).

### 6. Check it in the game

Make a replay of a recording with the poses of the game on every frame, and see what the game makes of it:

```
venv-ml/bin/python dev/moves/ml/replay_with_poses.py \
    ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.jsonl ~/auslender-video/fight-<player>-<date>/fight-<player>-<date>.poses.jsonl
$GODOT --headless --fixed-fps 30 --path . --script dev/moves/print_replay.gd -- \
    --replay=$HOME/auslender-video/fight-<player>-<date>/fight-<player>-<date>-rtmpose.jsonl
```

Each call of the plan should give its move (e.g., five `hook left` in the step "hook left"), and the steps without moves (the guard, looking around) none.
Play-test it live in front of the camera, too.
Then run the checks (`dev/continuous_integration/precommit.py`; the tests load the model) and commit the two model files.

### Changing the features or the model

The features are computed twice: in Python for the training (`sequences` in `dev/moves/ml/moves_ml.py`) and in C# for the game (`MoveFeatures`).
If you change them, change both, regenerate the case of the parity test (`tests/Auslender.Tests/data/move_features_cases.json`) with `venv-ml/bin/python dev/moves/ml/parity_cases.py`, so that `MoveFeaturesTests` checks that both agree, and retrain the model: the game refuses a model which reads another number of features.
Keep every model evaluable in C# without new dependencies (XGBoost as JSON, or a network as ONNX through `OnnxMoveModel`).

### The moves of the opponents

The opponents box with moves captured from the same guided recordings (`scenes/opponent/moves/moves.json`, played by `Moves` and `Opponent`): each punch, knee, slip, duck and cover is the average of the adults' repetitions, lifted to 3D and fitted to the opponents' rig.
After new recordings, regenerate them with:

```
venv-ml/bin/python dev/animation/extract_moves.py
```

and check them in a fight (a boss level shows the attacks best).
The lifter was trained on Human3.6M, licensed for research only (see `scenes/vision/lifting/model/lifting.json`): check this before a release.
