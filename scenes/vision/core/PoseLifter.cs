using System;
using System.Linq;
using System.Numerics;

using Microsoft.ML.OnnxRuntime;

// NOTE (mristin):
// This file does not depend on Godot, so that we can unit-test the computer
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Lift the 2D pose of the player to 3D with a small network (VideoPose3D of
    /// one frame, see dev/lifting/export_videopose.py), in well under a millisecond.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The network takes the 17 joints of Human3.6M, which we make from the 17
    /// key points of COCO (<see cref="ToH36m"/>), and gives them in 3D: in meters,
    /// relative to the pelvis, in the axes of the camera (x right, y down, z away
    /// from the camera).
    /// </para>
    /// <para>
    /// It learned on Human3.6M, filmed by cameras at the height of the chest; from a
    /// camera on the floor, it mistakes a straight punch at the camera for an arm
    /// raised up (the wrist rises in the picture), so the depth of the straights is
    /// not to be trusted. The data of Human3.6M is licensed for research only.
    /// </para>
    /// </remarks>
    public sealed class PoseLifter : IDisposable
    {
        public const int JointCount = 17;

        /// <summary>The joints of Human3.6M, in the order of the network.</summary>
        public enum Joint
        {
            Pelvis,
            RightHip,
            RightKnee,
            RightAnkle,
            LeftHip,
            LeftKnee,
            LeftAnkle,
            Spine,
            Thorax,
            Nose,
            Head,
            LeftShoulder,
            LeftElbow,
            LeftWrist,
            RightShoulder,
            RightElbow,
            RightWrist,
        }

        /// <summary>The bones of the skeleton of Human3.6M, as pairs of joints.</summary>
        public static readonly (Joint A, Joint B)[] Bones =
        {
            (Joint.Pelvis, Joint.RightHip), (Joint.RightHip, Joint.RightKnee), (Joint.RightKnee, Joint.RightAnkle),
            (Joint.Pelvis, Joint.LeftHip), (Joint.LeftHip, Joint.LeftKnee), (Joint.LeftKnee, Joint.LeftAnkle),
            (Joint.Pelvis, Joint.Spine), (Joint.Spine, Joint.Thorax), (Joint.Thorax, Joint.Nose),
            (Joint.Nose, Joint.Head), (Joint.Thorax, Joint.LeftShoulder), (Joint.LeftShoulder, Joint.LeftElbow),
            (Joint.LeftElbow, Joint.LeftWrist), (Joint.Thorax, Joint.RightShoulder),
            (Joint.RightShoulder, Joint.RightElbow), (Joint.RightElbow, Joint.RightWrist),
        };

        /// <summary>Below this score, an ankle is guessed from the leg (the camera often misses the feet).</summary>
        public const float AnkleThreshold = 0.3f;

        private readonly InferenceSession _session;
        private readonly RunOptions _runOptions = new();
        private readonly float[] _input = new float[JointCount * 2];
        private readonly float[] _output = new float[JointCount * 3];
        private readonly OrtValue _inputValue;
        private readonly OrtValue _outputValue;
        private readonly string[] _inputNames = { "keypoints_2d" };
        private readonly string[] _outputNames = { "keypoints_3d" };
        private readonly Vector2[] _joints2d = new Vector2[JointCount];

        public PoseLifter(byte[] model)
        {
            OnnxRuntimePrivacy.DisableTelemetry();
            using var options = new SessionOptions
            {
                GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR,
                IntraOpNumThreads = 1,
                InterOpNumThreads = 1,
            };
            options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");
            _session = new InferenceSession(model, options);
            if (!_session.InputMetadata.ContainsKey(_inputNames[0]) || !_session.OutputMetadata.ContainsKey(_outputNames[0]))
            {
                string inputs = string.Join(", ", _session.InputMetadata.Keys);
                string outputs = string.Join(", ", _session.OutputMetadata.Keys);
                _session.Dispose();
                throw new InvalidOperationException(
                    $"Expected the lifting network to have the input keypoints_2d and the output keypoints_3d, " +
                    $"but got the inputs {inputs} and the outputs {outputs}.");
            }

            _inputValue = OrtValue.CreateTensorValueFromMemory(_input, new long[] { 1, JointCount * 2 });
            _outputValue = OrtValue.CreateTensorValueFromMemory(_output, new long[] { 1, JointCount * 3 });
        }

        /// <summary>
        /// The 17 joints of Human3.6M in the picture, in pixels, from the 17 key points
        /// of COCO (as in MMPose); an ankle which the camera does not see well is guessed
        /// below its knee, along the thigh.
        /// </summary>
        public static void ToH36m(Pose pose, Vector2[] joints)
        {
            if (joints.Length != JointCount)
            {
                throw new ArgumentException($"Expected {JointCount} joints, but got {joints.Length}.", nameof(joints));
            }

            Vector2 At(BodyPart part) => new(pose[part].X, pose[part].Y);

            Vector2 Ankle(BodyPart hip, BodyPart knee, BodyPart ankle) =>
                pose[ankle].Score >= AnkleThreshold ? At(ankle) : At(knee) + (At(knee) - At(hip));

            var pelvis = (At(BodyPart.LeftHip) + At(BodyPart.RightHip)) * 0.5f;
            var thorax = (At(BodyPart.LeftShoulder) + At(BodyPart.RightShoulder)) * 0.5f;
            joints[(int)Joint.Pelvis] = pelvis;
            joints[(int)Joint.RightHip] = At(BodyPart.RightHip);
            joints[(int)Joint.RightKnee] = At(BodyPart.RightKnee);
            joints[(int)Joint.RightAnkle] = Ankle(BodyPart.RightHip, BodyPart.RightKnee, BodyPart.RightAnkle);
            joints[(int)Joint.LeftHip] = At(BodyPart.LeftHip);
            joints[(int)Joint.LeftKnee] = At(BodyPart.LeftKnee);
            joints[(int)Joint.LeftAnkle] = Ankle(BodyPart.LeftHip, BodyPart.LeftKnee, BodyPart.LeftAnkle);
            joints[(int)Joint.Spine] = (pelvis + thorax) * 0.5f;
            joints[(int)Joint.Thorax] = thorax;
            joints[(int)Joint.Nose] = At(BodyPart.Nose);
            joints[(int)Joint.Head] = (At(BodyPart.LeftEye) + At(BodyPart.RightEye)) * 0.5f;
            joints[(int)Joint.LeftShoulder] = At(BodyPart.LeftShoulder);
            joints[(int)Joint.LeftElbow] = At(BodyPart.LeftElbow);
            joints[(int)Joint.LeftWrist] = At(BodyPart.LeftWrist);
            joints[(int)Joint.RightShoulder] = At(BodyPart.RightShoulder);
            joints[(int)Joint.RightElbow] = At(BodyPart.RightElbow);
            joints[(int)Joint.RightWrist] = At(BodyPart.RightWrist);
        }

        /// <summary>
        /// Lift the pose (in a picture of the size) to 3D: the joints of Human3.6M in
        /// meters, relative to the pelvis (x right, y down, z away from the camera);
        /// and the same joints in the picture, in pixels.
        /// </summary>
        public void Lift(Pose pose, int width, int height, Vector3[] joints3d, Vector2[] joints2d)
        {
            if (joints3d.Length != JointCount)
            {
                throw new ArgumentException($"Expected {JointCount} joints, but got {joints3d.Length}.", nameof(joints3d));
            }

            ToH36m(pose, joints2d);
            float half = width * 0.5f;
            for (int j = 0; j < JointCount; j++)
            {
                // NOTE (mristin):
                // As MMPose's ImageCoordinateNormalization: by half the width, about
                // the middle of the picture.
                _input[2 * j] = (joints2d[j].X - half) / half;
                _input[2 * j + 1] = (joints2d[j].Y - height * 0.5f) / half;
            }

            _session.Run(_runOptions, _inputNames, new[] { _inputValue }, _outputNames, new[] { _outputValue });
            for (int j = 0; j < JointCount; j++)
            {
                joints3d[j] = new Vector3(_output[3 * j], _output[3 * j + 1], _output[3 * j + 2]);
            }
        }

        public void Dispose()
        {
            _inputValue.Dispose();
            _outputValue.Dispose();
            _runOptions.Dispose();
            _session.Dispose();
        }
    }
}
