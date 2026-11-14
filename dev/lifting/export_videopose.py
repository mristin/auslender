"""Export the 2D-to-3D pose lifting network (VideoPose3D, one frame) to ONNX.

python export_videopose.py <checkpoint.pth> <out.onnx>

(in venv-ml, see dev/moves/ml/requirements.txt; PyTorch from
https://download.pytorch.org/whl/cpu is enough). The network was trained on
Human3.6M, whose license allows only research: see
scenes/vision/lifting/model/lifting.json.

The checkpoint is MMPose's VideoPose3D for Human3.6M, one frame, fine-tuned on
the 2D poses of CPN (so used to detected, noisy 2D poses):

    https://download.openmmlab.com/mmpose/body3d/videopose/
    videopose_h36m_1frame_fullconv_supervised_cpn_ft-5c3afaed_20210527.pth

We read it with the safe loader of PyTorch (weights_only=True: only tensors,
no code from the file), rebuild the network (a temporal convolutional network
whose convolutions are all 1 wide for one frame), export it, and check that
ONNX Runtime gives the same as PyTorch.

The input "keypoints_2d" is [N, 34]: the 17 joints of Human3.6M (see
PoseLifter.cs), x and y interleaved, normalized by the width of the picture
((x - w / 2) / (w / 2), (y - h / 2) / (w / 2)). The output "keypoints_3d" is
[N, 51]: the 17 joints in 3D (x, y, z interleaved, in meters, relative to the
pelvis, in the axes of the camera: x right, y down, z away from the camera).
"""

import sys

import numpy as np
import onnxruntime as ort
import torch
from torch import nn

CHANNELS = 1024
BLOCKS = 4
JOINTS = 17


class Unit(nn.Module):
    """A 1-wide convolution (as a linear layer), a batch norm and a ReLU."""

    def __init__(self, inputs, outputs):
        super().__init__()
        self.linear = nn.Linear(inputs, outputs, bias=False)
        self.norm = nn.BatchNorm1d(outputs)

    def forward(self, x):
        return torch.relu(self.norm(self.linear(x)))


class Lifter(nn.Module):
    def __init__(self):
        super().__init__()
        self.expand = Unit(JOINTS * 2, CHANNELS)
        self.blocks = nn.ModuleList(
            [nn.ModuleList([Unit(CHANNELS, CHANNELS), Unit(CHANNELS, CHANNELS)]) for _ in range(BLOCKS)]
        )
        self.head = nn.Linear(CHANNELS, JOINTS * 3)

    def forward(self, keypoints_2d):
        x = self.expand(keypoints_2d)
        for first, second in self.blocks:
            x = x + second(first(x))
        return self.head(x)


def load(checkpoint):
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)["state_dict"]
    model = Lifter()

    def unit(target, prefix):
        target.linear.weight.data = state[f"{prefix}.conv.weight"][:, :, 0]
        for name in ("weight", "bias", "running_mean", "running_var"):
            getattr(target.norm, name).data = state[f"{prefix}.bn.{name}"]

    unit(model.expand, "backbone.expand_conv")
    for i, (first, second) in enumerate(model.blocks):
        unit(first, f"backbone.tcn_blocks.{i}.conv1.0")
        unit(second, f"backbone.tcn_blocks.{i}.conv2.0")
    model.head.weight.data = state["keypoint_head.conv.weight"][:, :, 0]
    model.head.bias.data = state["keypoint_head.conv.bias"]
    # NOTE: MMPose's batch norm uses the default epsilon (1e-5), as nn.BatchNorm1d.
    return model.eval()


def main():
    checkpoint, out = sys.argv[1], sys.argv[2]
    model = load(checkpoint)
    example = torch.zeros(1, JOINTS * 2)
    torch.onnx.export(
        model,
        (example,),
        out,
        input_names=["keypoints_2d"],
        output_names=["keypoints_3d"],
        dynamic_axes={"keypoints_2d": {0: "n"}, "keypoints_3d": {0: "n"}},
        opset_version=17,
        dynamo=False,
    )

    rng = np.random.default_rng(1)
    probe = rng.normal(0, 0.3, size=(8, JOINTS * 2)).astype(np.float32)
    with torch.no_grad():
        expected = model(torch.from_numpy(probe)).numpy()
    session = ort.InferenceSession(out, providers=["CPUExecutionProvider"])
    got = session.run(None, {"keypoints_2d": probe})[0]
    print(f"Wrote {out}; ONNX Runtime vs PyTorch: max difference {np.abs(got - expected).max():.2e}")


if __name__ == "__main__":
    main()
