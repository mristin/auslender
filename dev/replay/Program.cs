using System;
using System.Diagnostics;
using System.IO;

using Auslender.Vision;

namespace Auslender.Replay
{
    /// <summary>
    /// Run the vision of the game on every frame of a video, offline, and write
    /// what it measures as JSON lines, as dev/moves/record_moves.gd records them
    /// in the game (see <see cref="VisionRecorder"/>).
    /// </summary>
    /// <remarks>
    /// <para>
    /// In the game, the body pose runs only a few times a second on a slow
    /// computer. Offline, it runs on every frame, so the recording shows what
    /// the moves look like at the full rate of the camera, however busy the
    /// computer is. The time of a frame is its number over the frame rate.
    /// </para>
    /// <para>
    /// The video is decoded with ffmpeg (on the path) to 640x480 RGB:
    /// </para>
    /// <code>
    /// dotnet run --project dev/replay -c Release -- &lt;video&gt; &lt;out.jsonl&gt; [--fps=30] [--every=1]
    /// </code>
    /// <para>
    /// With <c>--every=n</c>, the pose runs only on every n-th frame (to mimic
    /// a slower computer); the face and the hands run on every frame.
    /// </para>
    /// </remarks>
    public static class Program
    {
        private const int Width = 640;
        private const int Height = 480;

        public static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.Error.WriteLine("Usage: <video> <out.jsonl> [--fps=30] [--every=1]");
                return 1;
            }

            double fps = 30.0;
            int every = 1;
            foreach (var arg in args)
            {
                if (arg.StartsWith("--fps="))
                {
                    fps = double.Parse(arg["--fps=".Length..], System.Globalization.CultureInfo.InvariantCulture);
                }
                else if (arg.StartsWith("--every="))
                {
                    every = Math.Max(1, int.Parse(arg["--every=".Length..]));
                }
            }

            string root = FindRoot();
            byte[] Model(string path) => File.ReadAllBytes(Path.Combine(root, path));
            using var vision = new RiderVision(Model("scenes/vision/rtmo/model/rtmo_t_body7_416x416.onnx"), 4);
            using var tracker = new FaceTracker(
                Model("scenes/vision/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx"),
                Model("scenes/vision/yunet/model/face_detection_yunet_2023mar_dynamic.onnx")
            );
            tracker.WantHands = true;

            var head = new HeadGauge();
            var hands = new HandTracker();
            var joystick = new RoomJoystick();
            var faceCues = new DepthCues();
            var poseCues = new DepthCues();
            using var recorder = new VisionRecorder(args[1]);
            recorder.RecordStart(0.0, Width, Height);

            var decoder = Process.Start(new ProcessStartInfo
            {
                FileName = "ffmpeg",
                ArgumentList =
                {
                    "-loglevel", "error", "-i", args[0],
                    "-vf", $"scale={Width}:{Height}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
                },
                RedirectStandardOutput = true,
                UseShellExecute = false,
            })!;
            var stream = decoder.StandardOutput.BaseStream;

            var clock = Stopwatch.StartNew();
            VisionSnapshot? pose = null;
            int index = 0;
            while (true)
            {
                var rgb = new byte[Width * Height * 3];
                int read = 0;
                while (read < rgb.Length)
                {
                    int n = stream.Read(rgb, read, rgb.Length - read);
                    if (n <= 0)
                    {
                        break;
                    }

                    read += n;
                }

                if (read < rgb.Length)
                {
                    break;
                }

                double t = index / fps;
                var frame = new Frame(rgb, Width, Height, t);

                if (index % every == 0)
                {
                    pose = vision.Process(frame);
                }

                var hints = new (float X, float Y)?[] { pose?.Player?.Head(0.5f) };
                var face = tracker.TrackAll(frame, hints);

                // NOTE (mristin):
                // As VisionService does, but in the order of the frame: the face
                // and the hands first (so that the hand tracker has this frame),
                // then the pose which tells the hands apart.
                var landmarks = face.Faces.Count > 0 ? face.Faces[0] : null;
                var box = face.Heads.Count > 0 ? face.Heads[0] : null;
                faceCues.SetFace(landmarks, box, face.HeadCount >= 0);
                joystick.ObserveCues(t, faceCues);
                if (head.Measure(t, landmarks, box, face.HeadCount >= 0))
                {
                    joystick.Observe(t, head.X, head.Y, head.RawUnit);
                    hands.SetUnit(0, head.Unit);
                }

                if (face.Hands != null)
                {
                    hands.Observe(t, face.Hands);
                }

                if (pose != null && index % every == 0)
                {
                    hands.ObservePoses(t, pose.Players);
                    poseCues.SetPose(pose.Player, 0.4f);
                    joystick.ObserveCues(t, poseCues);
                    recorder.RecordPose(pose, poseCues);
                }

                joystick.Update(t);
                recorder.RecordFace(face, head, joystick, hands, faceCues);

                index++;
                if (index % 150 == 0)
                {
                    Console.WriteLine(
                        $"{index} frames ({t:F0} s of video) in {clock.Elapsed.TotalSeconds:F0} s"
                    );
                }
            }

            decoder.WaitForExit();
            Console.WriteLine($"Replayed {index} frames into {args[1]} ({recorder.Lines} lines).");
            return 0;
        }

        /// <summary>The root of the repository, where project.godot is.</summary>
        private static string FindRoot()
        {
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while (directory != null && !File.Exists(Path.Combine(directory.FullName, "project.godot")))
            {
                directory = directory.Parent;
            }

            return directory?.FullName ?? Directory.GetCurrentDirectory();
        }
    }
}  // namespace Auslender.Replay
