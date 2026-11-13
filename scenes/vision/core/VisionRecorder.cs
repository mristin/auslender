using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Record what the vision measured, as JSON lines, to study the moves of real
    /// players and to infer the rules which tell them (see dev/moves/).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Only numbers are recorded: where the eyes, the head, the hands and the
    /// joints are, and what the detectors made of them. The camera pictures are
    /// never recorded.
    /// </para>
    /// <para>
    /// Every line is one JSON object with its "kind":
    /// </para>
    /// <list type="bullet">
    /// <item>"start": the size of the frames;</item>
    /// <item>
    /// "face": on every frame of the face tracker, the eyes, the head box,
    /// whether the head detector found it in this frame, the head of the
    /// <see cref="HeadGauge"/> (x, y, unit and raw unit), the room joystick
    /// (sideways, depth, down and the stick), the face landmarks ("face": the
    /// box, the eyes, the nose and the corners of the mouth), the sizes of the
    /// face for the depth ("cues", see <see cref="DepthCues"/>) and how much
    /// each cue grew since home ("cue_depths"), every hand box which the
    /// detector found, and the tracked left and right hand (x, y, size);
    /// </item>
    /// <item>"pose": the 17 key points of the player, as x, y and score, and the sizes of the body ("cues");</item>
    /// <item>"move": a move which the game's detectors found (kind, side, power);</item>
    /// <item>"mark": e.g., when the player was called to throw a jab, with its "name".</item>
    /// </list>
    /// <para>
    /// Each line has the time "t" in seconds and the "label" of what the player
    /// was asked to do. The instance is not thread-safe; use it from a single
    /// thread only.
    /// </para>
    /// </remarks>
    public sealed class VisionRecorder : IDisposable
    {
        private readonly StreamWriter _writer;

        /// <summary>What the player is asked to do now, e.g., "jab left 1".</summary>
        public string Label = "";

        /// <summary>How many lines were written.</summary>
        public int Lines { get; private set; }

        public VisionRecorder(string path)
        {
            var directory = Path.GetDirectoryName(Path.GetFullPath(path));
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            _writer = new StreamWriter(path, append: false) { AutoFlush = false };
        }

        /// <summary>Write the start of the recording.</summary>
        public void RecordStart(double t, int width, int height)
        {
            Write(new Dictionary<string, object?>
            {
                ["kind"] = "start",
                ["t"] = t,
                ["label"] = Label,
                ["width"] = width,
                ["height"] = height,
                ["time"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            });
        }

        /// <summary>Write what the face tracker found and what the joystick and the hand tracker made of it.</summary>
        public void RecordFace(
            FaceSnapshot face, HeadGauge head, RoomJoystick joystick, HandTracker hands, DepthCues cues
        )
        {
            var landmarks = face.Faces.Count > 0 ? face.Faces[0] : null;
            var box = face.Heads.Count > 0 ? face.Heads[0] : null;

            List<float[]>? found = null;
            if (face.Hands != null)
            {
                found = new List<float[]>();
                foreach (var hand in face.Hands)
                {
                    found.Add(new[] { hand.X1, hand.Y1, hand.X2, hand.Y2 });
                }
            }

            float[]? Tracked(HandSide side)
            {
                var hand = hands.Hand(0, side, face.Timestamp);
                var size = hands.HandSize(0, side, face.Timestamp);
                return hand == null || size == null ? null : new[] { hand.Value.X, hand.Value.Y, size.Value };
            }

            Write(new Dictionary<string, object?>
            {
                ["kind"] = "face",
                ["t"] = face.Timestamp,
                ["label"] = Label,
                ["ms"] = face.InferenceMs,
                ["eyes"] = landmarks == null
                    ? null
                    : new[] { landmarks.LeftEyeX, landmarks.LeftEyeY, landmarks.RightEyeX, landmarks.RightEyeY },
                ["head"] = box == null ? null : new[] { box.Value.X1, box.Value.Y1, box.Value.X2, box.Value.Y2 },
                ["detected"] = face.HeadCount >= 0,
                ["gauge"] = new[] { Number(head.X), Number(head.Y), Number(head.Unit), Number(head.RawUnit) },
                ["face"] = landmarks == null
                    ? null
                    : new[]
                    {
                        landmarks.Box.X1, landmarks.Box.Y1, landmarks.Box.X2, landmarks.Box.Y2,
                        landmarks.LeftEyeX, landmarks.LeftEyeY, landmarks.RightEyeX, landmarks.RightEyeY,
                        landmarks.NoseX, landmarks.NoseY,
                        landmarks.MouthLeftX, landmarks.MouthLeftY, landmarks.MouthRightX, landmarks.MouthRightY,
                    },
                ["cues"] = Numbers(cues.Sizes),
                ["cue_depths"] = CueDepths(joystick, face.Timestamp),
                ["calibrated"] = joystick.Calibrated,
                ["room"] = new[] { joystick.Sideways, joystick.Depth, joystick.Down, joystick.Stick.X, joystick.Stick.Y },
                ["hands"] = found,
                ["left"] = Tracked(HandSide.Left),
                ["right"] = Tracked(HandSide.Right),
            });
        }

        /// <summary>Write the pose of the player.</summary>
        public void RecordPose(VisionSnapshot snapshot, DepthCues cues)
        {
            var pose = snapshot.Players.Count > 0 ? snapshot.Players[0] : null;
            float[]? points = null;
            if (pose != null)
            {
                points = new float[Pose.KeypointCount * 3];
                for (int k = 0; k < Pose.KeypointCount; k++)
                {
                    points[k * 3] = pose.Keypoints[k].X;
                    points[k * 3 + 1] = pose.Keypoints[k].Y;
                    points[k * 3 + 2] = pose.Keypoints[k].Score;
                }
            }

            Write(new Dictionary<string, object?>
            {
                ["kind"] = "pose",
                ["t"] = snapshot.Timestamp,
                ["label"] = Label,
                ["ms"] = snapshot.InferenceMs,
                ["pose"] = points,
                ["cues"] = Numbers(cues.Sizes),
            });
        }

        /// <summary>Write a move which the game's detectors found.</summary>
        public void RecordMove(double t, string kind, string side, float power)
        {
            Write(new Dictionary<string, object?>
            {
                ["kind"] = "move",
                ["t"] = t,
                ["label"] = Label,
                ["move"] = kind,
                ["side"] = side,
                ["power"] = power,
            });
        }

        /// <summary>Write a mark at the time <paramref name="t"/>, e.g., when the player was called to jab.</summary>
        public void RecordMark(double t, string name)
        {
            Write(new Dictionary<string, object?> { ["kind"] = "mark", ["t"] = t, ["label"] = Label, ["name"] = name });
        }

        private static float? Number(float value) => float.IsNaN(value) ? null : value;

        private static float?[] Numbers(float[] values) => Array.ConvertAll(values, Number);

        private static float?[] CueDepths(RoomJoystick joystick, double t)
        {
            var depths = new float?[DepthCues.Count];
            for (int i = 0; i < depths.Length; i++)
            {
                depths[i] = Number(joystick.CueDepth((DepthCue)i, t));
            }

            return depths;
        }

        private void Write(Dictionary<string, object?> line)
        {
            _writer.WriteLine(JsonSerializer.Serialize(line));
            Lines++;
        }

        public void Dispose()
        {
            _writer.Flush();
            _writer.Dispose();
        }
    }
}  // namespace Auslender.Vision
