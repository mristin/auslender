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
    /// Read a recording of the vision (see <see cref="VisionRecorder"/>, e.g.,
    /// from dev/replay/) back into the snapshots which the face tracker and the
    /// pose estimator made, so that the game can play them as if live.
    /// </summary>
    public sealed class RecordingReader
    {
        /// <summary>The face snapshots, in the order of time.</summary>
        public readonly List<FaceSnapshot> Faces = new();

        /// <summary>The pose snapshots, in the order of time.</summary>
        public readonly List<VisionSnapshot> Poses = new();

        public int Width { get; private set; } = 640;
        public int Height { get; private set; } = 480;

        public static RecordingReader Read(string path)
        {
            var reader = new RecordingReader();
            foreach (var line in File.ReadLines(path))
            {
                if (string.IsNullOrWhiteSpace(line))
                {
                    continue;
                }

                using var document = JsonDocument.Parse(line);
                var row = document.RootElement;
                switch (row.GetProperty("kind").GetString())
                {
                    case "start":
                        reader.Width = row.GetProperty("width").GetInt32() > 0 ? row.GetProperty("width").GetInt32() : 640;
                        reader.Height = row.GetProperty("height").GetInt32() > 0 ? row.GetProperty("height").GetInt32() : 480;
                        break;
                    case "face":
                        reader.Faces.Add(reader.ReadFace(row));
                        break;
                    case "pose":
                        reader.Poses.Add(reader.ReadPose(row));
                        break;
                }
            }

            reader.Faces.Sort((a, b) => a.Timestamp.CompareTo(b.Timestamp));
            reader.Poses.Sort((a, b) => a.Timestamp.CompareTo(b.Timestamp));
            return reader;
        }

        private static float[]? Numbers(JsonElement row, string name)
        {
            if (!row.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Array)
            {
                return null;
            }

            var result = new float[value.GetArrayLength()];
            int i = 0;
            foreach (var item in value.EnumerateArray())
            {
                result[i++] = item.ValueKind == JsonValueKind.Number ? item.GetSingle() : float.NaN;
            }

            return result;
        }

        private FaceSnapshot ReadFace(JsonElement row)
        {
            double t = row.GetProperty("t").GetDouble();
            var face = Numbers(row, "face");
            FaceLandmarks? landmarks = null;
            if (face != null && face.Length >= 14)
            {
                landmarks = new FaceLandmarks
                {
                    Box = new BoundingBox(face[0], face[1], face[2], face[3]),
                    Score = 1f,
                    LeftEyeX = face[4],
                    LeftEyeY = face[5],
                    RightEyeX = face[6],
                    RightEyeY = face[7],
                    NoseX = face[8],
                    NoseY = face[9],
                    MouthLeftX = face[10],
                    MouthLeftY = face[11],
                    MouthRightX = face[12],
                    MouthRightY = face[13],
                };
            }

            var head = Numbers(row, "head");
            BoundingBox? box = head != null && head.Length == 4 ? new BoundingBox(head[0], head[1], head[2], head[3]) : null;
            bool detected = row.TryGetProperty("detected", out var flag) && flag.GetBoolean();

            List<BoundingBox>? hands = null;
            if (row.TryGetProperty("hands", out var found) && found.ValueKind == JsonValueKind.Array)
            {
                hands = new List<BoundingBox>();
                foreach (var hand in found.EnumerateArray())
                {
                    var b = new float[4];
                    int i = 0;
                    foreach (var value in hand.EnumerateArray())
                    {
                        b[i++] = value.GetSingle();
                    }

                    hands.Add(new BoundingBox(b[0], b[1], b[2], b[3]));
                }
            }

            return new FaceSnapshot
            {
                Timestamp = t,
                Width = Width,
                Height = Height,
                Heads = new BoundingBox?[] { box },
                Faces = new FaceLandmarks?[] { landmarks },
                HeadCount = detected ? (box == null ? 0 : 1) : -1,
                Hands = hands,
                InferenceMs = row.TryGetProperty("ms", out var ms) ? ms.GetDouble() : 0.0,
            };
        }

        private VisionSnapshot ReadPose(JsonElement row)
        {
            double t = row.GetProperty("t").GetDouble();
            var points = Numbers(row, "pose");
            Pose? pose = null;
            if (points != null && points.Length == Pose.KeypointCount * 3)
            {
                var keypoints = new Keypoint[Pose.KeypointCount];
                float x1 = float.PositiveInfinity, y1 = float.PositiveInfinity;
                float x2 = float.NegativeInfinity, y2 = float.NegativeInfinity;
                for (int k = 0; k < Pose.KeypointCount; k++)
                {
                    keypoints[k] = new Keypoint(points[k * 3], points[k * 3 + 1], points[k * 3 + 2]);
                    x1 = MathF.Min(x1, points[k * 3]);
                    y1 = MathF.Min(y1, points[k * 3 + 1]);
                    x2 = MathF.Max(x2, points[k * 3]);
                    y2 = MathF.Max(y2, points[k * 3 + 1]);
                }

                pose = new Pose(keypoints, new BoundingBox(x1, y1, x2, y2), 1f);
            }

            return new VisionSnapshot
            {
                Timestamp = t,
                Width = Width,
                Height = Height,
                Players = new Pose?[] { pose },
                PersonCount = pose == null ? 0 : 1,
                InferenceMs = row.TryGetProperty("ms", out var ms) ? ms.GetDouble() : 0.0,
            };
        }
    }
}  // namespace Auslender.Vision
