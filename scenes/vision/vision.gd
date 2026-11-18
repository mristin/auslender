extends Node

## Keep the camera and the vision running for the whole game, across all the
## scenes, so that the camera starts only once (which takes a few seconds).
##
## The scenes use `get_node("/root/Vision").service` (the VisionService, in
## C#): the camera picture, the room joystick, the punches and the kicks
## (`PollMoves`) and the anchor of the looks over the face.
##
## Start with `-- --no-camera` to run without the camera, e.g., in the tests,
## and with `-- --replay=<recording.jsonl>` to play a recording of the vision
## instead of the camera (made from a video with dev/replay/), with the frames
## of the video in `<recording>.frames/` (00001.jpg, ...) as the camera picture.

@onready var service: Node = $Service


func _enter_tree() -> void:
    # NOTE (mristin):
    # The service starts the camera in its _ready, which runs before ours.
    for arg in OS.get_cmdline_user_args():
        if arg == "--no-camera" or arg.begins_with("--replay="):
            $Service.UseCamera = false


func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--replay-from="):
            service.ReplayFrom(float(arg.trim_prefix("--replay-from=")))
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--replay="):
            var recording := arg.trim_prefix("--replay=")
            service.StartReplay(recording, recording.get_basename() + ".frames")
