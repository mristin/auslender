using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

using Auslender.Vision;
using StbImageSharp;

namespace Auslender.Poses
{
    /// <summary>
    /// Run the top-down pose of the game (<see cref="RtmPoseTracker"/>) on
    /// every saved frame of a recording made with <c>--frames</c> (see
    /// dev/moves/record_moves.gd), and write the poses as JSON lines
    /// (<c>{"t": ..., "index": ..., "pose": [x, y, score] * 17}</c>) for the
    /// training of the move classifier (see train.py and export.py).
    /// </summary>
    /// <remarks>
    /// <para>
    /// As in the game, the tracker follows the player from frame to frame,
    /// and starts from a pose of RTMO: here the latest one in the recording.
    /// </para>
    /// <code>
    /// dotnet run --project dev/moves/ml/poses -c Release -- &lt;recording.jsonl&gt; &lt;out.jsonl&gt;
    /// </code>
    /// <para>The frames are expected in <c>&lt;recording&gt;.frames/</c>.</para>
    /// </remarks>
    public static class Program
    {
        private const string Model = "scenes/vision/rtmpose/model/rtmpose_t_body7_256x192.onnx";

        public static int Main(string[] args)
        {
            if (args.Length != 2)
            {
                Console.Error.WriteLine("Usage: <recording.jsonl> <out.jsonl>");
                return 1;
            }

            string recording = args[0];
            string frames = Path.ChangeExtension(recording, null) + ".frames";
            var shots = new List<(double T, int Index)>();
            var seeds = new List<(double T, Pose Pose)>();
            foreach (var line in File.ReadLines(recording))
            {
                using var document = JsonDocument.Parse(line);
                var row = document.RootElement;
                switch (row.GetProperty("kind").GetString())
                {
                    case "frame":
                        shots.Add((row.GetProperty("t").GetDouble(), row.GetProperty("index").GetInt32()));
                        break;
                    case "pose":
                        if (row.TryGetProperty("pose", out var numbers)
                            && numbers.ValueKind == JsonValueKind.Array
                            && numbers.GetArrayLength() >= 51)
                        {
                            var values = numbers.EnumerateArray()
                                .Select(n => n.ValueKind == JsonValueKind.Number ? n.GetSingle() : 0f)
                                .ToArray();
                            var points = Enumerable.Range(0, Pose.KeypointCount)
                                .Select(k => new Keypoint(values[k * 3], values[k * 3 + 1], values[k * 3 + 2]))
                                .ToArray();
                            seeds.Add((row.GetProperty("t").GetDouble(), new Pose(points, new BoundingBox(0, 0, 1, 1), 1f)));
                        }

                        break;
                }
            }

            if (shots.Count == 0)
            {
                Console.Error.WriteLine($"The recording {recording} has no frames; record it with --frames.");
                return 1;
            }

            string root = FindRoot();
            using var tracker = new RtmPoseTracker(File.ReadAllBytes(Path.Combine(root, Model)), 2);
            using var writer = new StreamWriter(args[1]);
            int seed = -1;
            int written = 0;
            foreach (var (t, index) in shots)
            {
                while (seed + 1 < seeds.Count && seeds[seed + 1].T <= t)
                {
                    seed++;
                }

                if (!tracker.Tracking && seed >= 0)
                {
                    tracker.Seed(seeds[seed].Pose);
                }

                if (!tracker.Tracking)
                {
                    continue;
                }

                string file = Path.Combine(frames, $"{index:00000}.jpg");
                if (!File.Exists(file))
                {
                    continue;
                }

                var image = ImageResult.FromMemory(File.ReadAllBytes(file), ColorComponents.RedGreenBlue);
                var pose = tracker.Track(new Frame(image.Data, image.Width, image.Height, t));
                if (pose == null)
                {
                    continue;
                }

                var flat = pose.Keypoints.SelectMany(k => new[] { k.X, k.Y, k.Score }).ToArray();
                writer.WriteLine(JsonSerializer.Serialize(new { t, index, pose = flat }));
                written++;
            }

            Console.WriteLine($"Wrote {written} poses of {shots.Count} frames into {args[1]}");
            return 0;
        }

        private static string FindRoot()
        {
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while (directory != null && !File.Exists(Path.Combine(directory.FullName, "project.godot")))
            {
                directory = directory.Parent;
            }

            return directory?.FullName
                ?? throw new InvalidOperationException("Could not find the repository (project.godot).");
        }
    }
}
