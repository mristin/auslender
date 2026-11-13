using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

using Auslender.Vision;

/// <summary>
/// Capture the webcam, find the player's pose and face on background threads,
/// and turn them into the boxing: the room joystick from the head, the punches
/// from the hands, the kicks from the legs, and the anchor of the looks (the
/// unibrow) over the face.
/// </summary>
/// <remarks>
/// <para>
/// As in The Steppe Rescue, two threads run side by side. The pose thread runs
/// RTMO, which is accurate but slow: it tells the left hand from the right, and
/// sees the legs for the kicks. The face thread runs the small YOLOX detector
/// (the heads and the hands) and YuNet (the face) on every camera frame, so
/// that the joystick and the punches are quick.
/// </para>
/// <para>
/// The main thread only copies a camera frame when a thread asks for one, so
/// that we never queue frames (and latency) nor copy frames nobody processes.
/// The threads publish immutable snapshots (<see cref="VisionSnapshot"/> and
/// <see cref="FaceSnapshot"/>), which the main thread feeds into the
/// <see cref="RoomJoystick"/>, the <see cref="PunchDetector"/>s and the
/// <see cref="KickDetector"/>s in <see cref="_Process"/>.
/// </para>
/// <para>
/// There is one player. The game (GDScript) uses only the plain getters, and
/// takes the moves with <see cref="PollMoves"/>; the keyboard is up to the game.
/// </para>
/// </remarks>
public partial class VisionService : Node
{
    public enum ServiceStatus
    {
        Disabled,
        SearchingCamera,
        LoadingModels,
        Running,
        NoCamera,
        ModelsMissing,
        Failed,
    }

    public const string PoseModelPath = "res://scenes/vision/rtmo/model/rtmo_t_body7_416x416.onnx";

    public const string HeadModelPath =
        "res://scenes/vision/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx";

    public const string FaceModelPath =
        "res://scenes/vision/yunet/model/face_detection_yunet_2023mar_dynamic.onnx";

    /// <summary>Give up waiting for the camera server after this many seconds.</summary>
    private const double _cameraSearchTimeout = 7.0;

    /// <summary>Wait this long after the first feed shows up, so that the others can follow.</summary>
    private const double _graceAfterFirstFeed = 1.0;

    /// <summary>The moves are kept at most this long for the game to poll them, in seconds.</summary>
    private const double _moveLifetime = 0.5;

    [Export]
    public bool UseCamera = true;

    /// <summary>Prefer the feed with this index among the compatible ones.</summary>
    [Export]
    public int CameraIndex = 0;

    /// <summary>How many threads the pose estimator may use.</summary>
    [Export]
    public int Threads = 2;

    public ServiceStatus Status { get; private set; } = ServiceStatus.Disabled;

    public string StatusMessage { get; private set; } = "";

    /// <summary>The camera image (not mirrored), for the preview; null without a camera.</summary>
    public CameraTexture? CameraTexture { get; private set; }

    /// <summary>There is one player; the shared parts of the vision take the count.</summary>
    public int PlayerCount => 1;

    public readonly FaceAnchorFilter Face = new();

    /// <summary>The head of the player from the face tracker.</summary>
    public readonly HeadGauge Head = new();

    /// <summary>The hands of the player, from the hand detector, told apart by the poses.</summary>
    public readonly HandTracker Hands = new();

    public readonly RoomJoystick Joystick = new();

    /// <summary>The sizes of the player in the latest face frame and the latest pose, for the depth.</summary>
    private readonly DepthCues _faceCues = new();
    private readonly DepthCues _poseCues = new();

    public readonly PunchDetector[] Punches = { new(HandSide.Left), new(HandSide.Right) };

    public readonly KickDetector[] Kicks = { new(HandSide.Left), new(HandSide.Right) };

    /// <summary>The walking in place, from the knees.</summary>
    public readonly WalkMeter Walk = new();

    /// <summary>The turn of the body, which steers the walking.</summary>
    public readonly TurnGauge Turn = new();

    /// <summary>The punches from the pose: the wrist shoots up from the guard.</summary>
    public readonly PosePunchDetector[] PosePunches = { new(HandSide.Left), new(HandSide.Right) };

    /// <summary>
    /// Whether the punches also come from the growing boxes of the fists (see
    /// <see cref="PunchDetector"/>); off, since they jittered too much on the
    /// recordings at 15 frames a second.
    /// </summary>
    [Export]
    public bool UseBoxPunches = false;

    /// <summary>The recording which we play instead of the camera (see <see cref="StartReplay"/>), or null.</summary>
    private RecordingReader? _replay;
    private string _replayFrames = "";
    private int _replayFace;
    private int _replayPose;
    private int _replayShown = -1;
    private double _replayClock;
    private ImageTexture? _replayTexture;

    /// <summary>
    /// The pose tells the hands apart and sees the legs, so it runs as often as
    /// the computer manages while the faces and the hands keep up (see
    /// <see cref="PoseScheduler"/>).
    /// </summary>
    /// <remarks>
    /// Unlike in The Steppe Rescue, the body matters as much as the face here
    /// (the legs, the turns, the walking), so the pose may run back to back,
    /// at least ten times a second if the computer manages; the face and the
    /// hands get the rest.
    /// </remarks>
    public readonly PoseScheduler PoseRate = new()
    {
        MinInterval = 0.0,
        MaxInterval = 0.1,
        PoseShare = 1.0,
    };

    /// <summary>The hands, [left, right], smoothed for the picture (not for the punches).</summary>
    private readonly OneEuroFilter[] _handFilters = { new(), new() };

    private readonly (float X, float Y)?[] _smoothedHands = new (float X, float Y)?[2];

    /// <summary>The moves found since the game polled the last time.</summary>
    private readonly List<(double T, Godot.Collections.Dictionary Move)> _moves = new();

    /// <summary>The recording of the vision (see dev/moves/), or null.</summary>
    private VisionRecorder? _recorder;

    /// <summary>The jumps of the joystick which became moves.</summary>
    private int _jumpsSeen;

    /// <summary>The time between two camera frames, smoothed, in seconds; NaN before two frames.</summary>
    private double _frameSeconds = double.NaN;
    private double _lastFrameAt = double.NaN;

    /// <summary>
    /// Whether the face tracker follows the head and the hands; if not (its
    /// models are missing, or it failed), the joystick follows the pose, which
    /// then runs as often as it can.
    /// </summary>
    private volatile bool _faceTracking;

    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private double _gameTime;

    /// <summary>
    /// Seconds on the clock of the frame timestamps: the wall clock with the
    /// camera, and the game time without it, so that the tests run in game time.
    /// </summary>
    public double Now => _replay != null ? _replayClock : (UseCamera ? _clock.Elapsed.TotalSeconds : _gameTime);

    private VisionSnapshot? _latest;
    private VisionSnapshot? _consumed;
    private FaceSnapshot? _latestFace;
    private FaceSnapshot? _consumedFace;

    /// <summary>The latest pose, or null before the first one.</summary>
    public VisionSnapshot? Latest => Volatile.Read(ref _latest);

    /// <summary>The latest face, or null before the first one.</summary>
    public FaceSnapshot? LatestFace => Volatile.Read(ref _latestFace);

    private CameraFeed? _feed;

    /// <summary>The camera extension on Windows (see <see cref="StartCameraExtension"/>), or null.</summary>
    private GodotObject? _cameraExtension;

    /// <summary>
    /// Why there may be no camera: "unsupported" (on Windows without the camera
    /// extension), "denied" (Windows does not allow the camera), or "" otherwise.
    /// </summary>
    private string _noCameraReason = "";

    /// <summary>
    /// The chroma plane of a feed which delivers its frames as two planes (Y and
    /// CbCr, e.g., on macOS); <see cref="CameraTexture"/> then holds the Y plane.
    /// </summary>
    private CameraTexture? _cbcrTexture;

    /// <summary>The frames of a two-plane feed converted to RGB, for the preview.</summary>
    private ImageTexture? _ycbcrPreview;

    /// <summary>Try to activate the feed again at this time, see <see cref="RetryActivation"/>.</summary>
    private double _nextActivationAttempt = double.NaN;

    /// <summary>Try to activate an inactive feed again every this many seconds.</summary>
    private const double _activationRetryPeriod = 3.0;

    /// <summary>Convert the two-plane frames down to at most this width.</summary>
    private const int _maxYcbcrWidth = 640;

    private double _searchStarted = double.NaN;
    private double _firstFeedAt = double.NaN;

    /// <summary>Hand the camera frames over to one inference thread.</summary>
    private sealed class FrameSlot
    {
        public volatile bool Requested;
        public readonly AutoResetEvent Ready = new(false);
        private readonly object _lock = new();
        private Frame? _pending;

        public void Put(Frame frame)
        {
            lock (_lock)
            {
                _pending = frame;
            }

            Requested = false;
            Ready.Set();
        }

        public Frame? Take()
        {
            lock (_lock)
            {
                var frame = _pending;
                _pending = null;
                return frame;
            }
        }
    }

    private readonly List<Thread> _threads = new();
    private volatile bool _running;
    private readonly FrameSlot _poseSlot = new();
    private readonly FrameSlot _faceSlot = new();

    public override void _Ready()
    {
        if (!UseCamera)
        {
            SetStatus(ServiceStatus.Disabled, "The camera is switched off.");
            return;
        }

        if (!FileAccess.FileExists(PoseModelPath))
        {
            SetStatus(
                ServiceStatus.ModelsMissing,
                $"The pose model {PoseModelPath} is missing; run `git lfs pull`."
            );
            return;
        }

        CameraServer.MonitoringFeeds = true;
        if (OS.GetName() == "Windows")
        {
            StartCameraExtension();
        }

        _searchStarted = Now;
        SetStatus(ServiceStatus.SearchingCamera, "Looking for a camera...");
    }

    /// <summary>
    /// Load CameraServerExtension, which provides the camera feeds on Windows,
    /// where Godot 4.6 implements no camera (see
    /// addons/CameraServerExtension/CameraServerExtension.gdextension).
    /// </summary>
    /// <remarks>
    /// The extension must be created after <see cref="CameraServer.MonitoringFeeds"/>
    /// is set, and must live as long as its feeds are in use.
    /// </remarks>
    private void StartCameraExtension()
    {
        // NOTE (mristin):
        // The packaging puts the extension next to the executable; in the
        // editor, it stays in the project.
        string directory = OS.HasFeature("editor")
            ? ProjectSettings.GlobalizePath("res://addons/CameraServerExtension")
            : OS.GetExecutablePath().GetBaseDir();
        string path = directory.PathJoin("CameraServerExtension.gdextension");
        if (!System.IO.File.Exists(path))
        {
            GD.PushWarning($"The camera extension {path} is missing; there is no camera on Windows without it.");
            _noCameraReason = "unsupported";
            return;
        }

        var status = GDExtensionManager.LoadExtension(path);
        if (status != GDExtensionManager.LoadStatus.Ok && status != GDExtensionManager.LoadStatus.AlreadyLoaded)
        {
            GD.PushWarning($"The camera extension {path} did not load: {status}.");
            _noCameraReason = "unsupported";
            return;
        }

        if (!ClassDB.ClassExists("CameraServerExtension"))
        {
            GD.PushWarning($"The camera extension {path} loaded, but provides no CameraServerExtension.");
            _noCameraReason = "unsupported";
            return;
        }

        _cameraExtension = ClassDB.Instantiate("CameraServerExtension").AsGodotObject();
        GD.Print($"Loaded the camera extension {path}.");
        if (_cameraExtension != null && !_cameraExtension.Call("permission_granted").AsBool())
        {
            _noCameraReason = "denied";
        }
    }

    /// <summary>
    /// Whether a feed comes from CameraServerExtension, whose formats must be
    /// called by name: the methods of <see cref="CameraFeed"/> do not reach them.
    /// </summary>
    private static bool IsExtensionFeed(CameraFeed feed) => feed.GetClass() == "CameraFeedExtension";

    private static Godot.Collections.Array GetFormats(CameraFeed feed) =>
        IsExtensionFeed(feed) ? feed.Call("get_formats").AsGodotArray() : feed.GetFormats();

    private static void SetFormat(CameraFeed feed, int index)
    {
        var parameters = new Godot.Collections.Dictionary();
        if (IsExtensionFeed(feed))
        {
            feed.Call("set_format", index, parameters);
        }
        else
        {
            feed.SetFormat(index, parameters);
        }
    }

    public override void _Process(double delta)
    {
        _gameTime += delta;
        if (_replay != null)
        {
            PlayReplay(delta);
        }

        double now = Now;

        if (Status == ServiceStatus.SearchingCamera)
        {
            SearchCamera(now);
        }

        RetryActivation(now);

        var snapshot = Latest;
        if (snapshot != null && !ReferenceEquals(snapshot, _consumed))
        {
            _consumed = snapshot;
            ConsumePose(snapshot);
            _recorder?.RecordPose(snapshot, _poseCues);
        }

        var face = LatestFace;
        if (face != null && !ReferenceEquals(face, _consumedFace))
        {
            _consumedFace = face;
            ConsumeFace(face);
            _recorder?.RecordFace(face, Head, Joystick, Hands, _faceCues);
        }

        Face.Update(now);
        Joystick.Update(now);
        Walk.Update(now, delta);
        Turn.Update(now);
        UpdatePictureHands(now);

        _moves.RemoveAll(move => now - move.T > _moveLifetime);
    }

    private void ConsumeFace(FaceSnapshot face)
    {
        var landmarks = face.Faces.Count > 0 ? face.Faces[0] : null;
        if (landmarks != null)
        {
            Face.Observe(face.Timestamp, FaceAnchor.FromLandmarks(landmarks, face.Width));
        }

        var head = face.Heads.Count > 0 ? face.Heads[0] : null;
        _faceCues.SetFace(landmarks, head, face.HeadCount >= 0);
        Joystick.ObserveCues(face.Timestamp, _faceCues);
        if (Head.Measure(face.Timestamp, landmarks, head, face.HeadCount >= 0))
        {
            Joystick.Observe(face.Timestamp, Head.X, Head.Y, Head.RawUnit);
            Hands.SetUnit(0, Head.Unit);
            ObserveJumps(face.Timestamp);
        }

        if (face.Hands != null)
        {
            Hands.Observe(face.Timestamp, face.Hands);
            ObservePunches(face.Timestamp);
        }
    }

    private void ConsumePose(VisionSnapshot snapshot)
    {
        var pose = snapshot.Players.Count > 0 ? snapshot.Players[0] : null;
        if (pose == null)
        {
            return;
        }

        _poseCues.SetPose(pose, 0.4f);
        Joystick.ObserveCues(snapshot.Timestamp, _poseCues);

        if (_faceTracking)
        {
            Hands.ObservePoses(snapshot.Timestamp, snapshot.Players);
        }
        else
        {
            // NOTE (mristin):
            // Without the face tracker, the joystick follows the head of the pose.
            var head = pose.Head(0.5f);
            var unit = pose.Unit(0.5f);
            if (head != null && unit != null)
            {
                Joystick.Observe(snapshot.Timestamp, head.Value.X, head.Value.Y, unit.Value);
                ObserveJumps(snapshot.Timestamp);
            }
        }

        Walk.Observe(snapshot.Timestamp, pose);
        Turn.Observe(snapshot.Timestamp, pose);
        foreach (var detector in PosePunches)
        {
            var punch = detector.Observe(snapshot.Timestamp, pose);
            if (punch != null)
            {
                AddMove(punch.Value.Time, "straight", punch.Value.Side, punch.Value.Power);
            }
        }

        foreach (var detector in Kicks)
        {
            var kick = detector.Observe(snapshot.Timestamp, pose);
            if (kick != null)
            {
                AddMove(kick.Value.Time, kick.Value.Kind == KickKind.Side ? "side_kick" : "front_kick",
                    kick.Value.Side, kick.Value.Power);
            }
        }
    }

    /// <summary>Find the punches of both hands, which the hand tracker follows.</summary>
    private void ObservePunches(double t)
    {
        if (!UseBoxPunches || float.IsNaN(Head.Y) || float.IsNaN(Head.Unit))
        {
            return;
        }

        foreach (var detector in Punches)
        {
            var hand = Hands.Hand(0, detector.Side, t);
            var size = Hands.HandSize(0, detector.Side, t);
            if (hand == null || size == null || Hands.HandSeenAt(0, detector.Side) != t)
            {
                continue;
            }

            var punch = detector.Observe(t, hand.Value.X, hand.Value.Y, size.Value, Head.Y, Head.Unit);
            if (punch != null)
            {
                string kind = punch.Value.Kind switch
                {
                    PunchKind.Hook => "hook",
                    PunchKind.Uppercut => "uppercut",
                    _ => "straight",
                };
                AddMove(punch.Value.Time, kind, punch.Value.Side, punch.Value.Power);
            }
        }
    }

    private void ObserveJumps(double t)
    {
        if (Joystick.Jumps != _jumpsSeen)
        {
            _jumpsSeen = Joystick.Jumps;
            AddMove(t, "jump", null, 1f);
        }
    }

    private void AddMove(double t, string kind, HandSide? side, float power)
    {
        string sideName = side == null ? "" : (side == HandSide.Left ? "left" : "right");
        _recorder?.RecordMove(t, kind, sideName, power);
        _moves.Add((t, new Godot.Collections.Dictionary
        {
            ["kind"] = kind,
            ["side"] = sideName,
            ["power"] = power,
        }));
    }

    /// <summary>Smooth the hands of the player for the picture.</summary>
    private void UpdatePictureHands(double now)
    {
        float unit = Head.Unit;
        for (int side = 0; side < 2; side++)
        {
            var hand = Hands.Hand(0, (HandSide)side, now);
            if (hand == null)
            {
                _handFilters[side].Reset();
                _smoothedHands[side] = null;
                continue;
            }

            _smoothedHands[side] = _handFilters[side].Filter(now, hand.Value.X, hand.Value.Y, unit);
        }
    }

    // NOTE (mristin):
    // The getters below are the API for GDScript. The positions are normalized to
    // [0, 1] of the *mirrored* camera picture, as the player sees herself.

    public string GetStatus() => Status.ToString();

    public string GetStatusMessage() => StatusMessage;

    public bool IsRunning() => Status == ServiceStatus.Running;

    /// <summary>Why there may be no camera, see <see cref="_noCameraReason"/>.</summary>
    public string GetNoCameraReason() => _noCameraReason;

    public Texture2D? GetCameraTexture() =>
        _replay != null ? _replayTexture : (_ycbcrPreview ?? (Texture2D?)CameraTexture);

    /// <summary>
    /// Play a recording of the vision (as dev/replay/ makes from a video)
    /// instead of the camera, again and again, with the frames of the video
    /// (<paramref name="frames"/>/00001.jpg, ..., one per face frame) as the
    /// camera picture. Return whether it started.
    /// </summary>
    public bool StartReplay(string recording, string frames)
    {
        try
        {
            _replay = RecordingReader.Read(recording);
        }
        catch (Exception exception)
        {
            GD.PushError($"Could not read the recording {recording}: {exception.Message}");
            _replay = null;
            return false;
        }

        if (_replay.Faces.Count == 0)
        {
            GD.PushError($"The recording {recording} has no face frames.");
            _replay = null;
            return false;
        }

        _replayFrames = frames;
        RestartReplay();
        SetStatus(ServiceStatus.Running, $"Replaying {recording}");
        return true;
    }

    public bool IsReplaying() => _replay != null;

    /// <summary>The time of the replay (from its first frame) and its length, in seconds.</summary>
    public Vector2 GetReplayTime()
    {
        if (_replay == null)
        {
            return Vector2.Zero;
        }

        double start = _replay.Faces[0].Timestamp;
        return new Vector2((float)(_replayClock - start), (float)(_replay.Faces[^1].Timestamp - start));
    }

    private void RestartReplay()
    {
        ResetPlayer();
        Hands.Reset();
        _replayFace = 0;
        _replayPose = 0;
        _replayShown = -1;
        _replayClock = _replay!.Faces[0].Timestamp;
    }

    /// <summary>Feed the snapshots of the replay up to now, in the order of their time, and show the frame.</summary>
    private void PlayReplay(double delta)
    {
        var replay = _replay!;
        _replayClock += delta;
        if (_replayClock > replay.Faces[^1].Timestamp + 1.5)
        {
            RestartReplay();
        }

        while (true)
        {
            bool faceDue = _replayFace < replay.Faces.Count && replay.Faces[_replayFace].Timestamp <= _replayClock;
            bool poseDue = _replayPose < replay.Poses.Count && replay.Poses[_replayPose].Timestamp <= _replayClock;
            if (!faceDue && !poseDue)
            {
                break;
            }

            // NOTE (mristin):
            // The face of a frame goes first, so that the hand tracker has the
            // frame when the pose of the same frame tells its hands apart.
            if (faceDue && (!poseDue || replay.Faces[_replayFace].Timestamp <= replay.Poses[_replayPose].Timestamp))
            {
                var face = replay.Faces[_replayFace++];
                Volatile.Write(ref _latestFace, face);
                _consumedFace = face;
                ConsumeFace(face);
            }
            else
            {
                var pose = replay.Poses[_replayPose++];
                Volatile.Write(ref _latest, pose);
                _consumed = pose;
                ConsumePose(pose);
            }
        }

        int shown = _replayFace - 1;
        if (shown >= 0 && shown != _replayShown)
        {
            _replayShown = shown;
            string path = $"{_replayFrames}/{shown + 1:00000}.jpg";
            var image = Image.LoadFromFile(path);
            if (image != null && !image.IsEmpty())
            {
                if (_replayTexture == null || _replayTexture.GetSize() != image.GetSize())
                {
                    _replayTexture = ImageTexture.CreateFromImage(image);
                }
                else
                {
                    _replayTexture.Update(image);
                }
            }
        }
    }

    /// <summary>The size of the camera picture in pixels, or (640, 480) before the first frame.</summary>
    public Vector2 GetPictureSize()
    {
        var face = LatestFace;
        if (face != null)
        {
            return new Vector2(face.Width, face.Height);
        }

        var pose = Latest;
        return pose != null ? new Vector2(pose.Width, pose.Height) : new Vector2(640, 480);
    }

    /// <summary>Whether the head of the player was seen lately.</summary>
    public bool HasPlayer() => Joystick.Sees(Now);

    /// <summary>
    /// Take the moves found since the last call, oldest first: each a
    /// dictionary with "kind" ("straight", "hook", "uppercut", "front_kick" or
    /// "side_kick", "jump"), "side" ("left" or "right", of the player's body;
    /// "" for a jump) and
    /// "power" (in [0, 1]).
    /// </summary>
    public Godot.Collections.Array PollMoves()
    {
        var result = new Godot.Collections.Array();
        foreach (var (_, move) in _moves)
        {
            result.Add(move);
        }

        _moves.Clear();
        return result;
    }

    /// <summary>The stick of the room joystick: x to the player's right, y forward, each in [-1, 1].</summary>
    public Vector2 GetStick() => new(Joystick.Stick.X, Joystick.Stick.Y);

    /// <summary>
    /// Where the player stands against home: x sideways in units (to her
    /// right), y the depth (towards the camera); zero before the calibration.
    /// </summary>
    public Vector2 GetRoomOffset() => new(Joystick.Sideways, Joystick.Depth);

    /// <summary>The dead zones and the full offsets of the joystick: (dead x, full x, dead y, full y).</summary>
    public Vector4 GetStickLimits() =>
        new(Joystick.DeadSideways, Joystick.FullSideways, Joystick.DeadDepth, Joystick.FullDepth);

    public bool IsCalibrated() => Joystick.Calibrated;

    /// <summary>How far the calibration got, in [0, 1].</summary>
    public float GetCalibrationProgress() => Joystick.CalibrationProgress;

    /// <summary>Forget the home spot; the player sets it again by holding still.</summary>
    public void Recalibrate() => Joystick.Recalibrate();

    /// <summary>How far the head is below home, in units (positive down).</summary>
    public float GetHeadDown() => Joystick.Down;

    public bool IsDucking() => Joystick.Ducking;

    /// <summary>The box around the head in the mirrored picture, normalized; empty if not seen.</summary>
    public Rect2 GetHeadRect()
    {
        if (!HasPlayer() || float.IsNaN(Head.X) || float.IsNaN(Head.Unit))
        {
            return new Rect2();
        }

        var size = GetPictureSize();
        float width = Head.Unit / Math.Max(0.5f, Head.UnitPerHeadWidth);
        float height = width * 1.3f;
        float centerY = Head.Y - Head.EyesBelowCenter * height;
        float x = 1f - Head.X / size.X;
        return new Rect2(
            (x * size.X - width * 0.5f) / size.X,
            (centerY - height * 0.5f) / size.Y,
            width / size.X,
            height / size.Y
        );
    }

    /// <summary>
    /// The anchor of the looks over the player's face: "center" (normalized),
    /// "eye_distance" (normalized to the width), "angle" (radians, clockwise)
    /// and "alpha" (0 hides it).
    /// </summary>
    public Godot.Collections.Dictionary GetFaceAnchor()
    {
        var size = GetPictureSize();
        var anchor = Face.Anchor;
        return new Godot.Collections.Dictionary
        {
            ["center"] = new Vector2(anchor.X / size.X, anchor.Y / size.Y),
            ["eye_distance"] = anchor.EyeDistance / size.X,
            ["angle"] = anchor.Angle,
            ["alpha"] = Face.Alpha,
        };
    }

    private Variant Mirrored((float X, float Y)? point)
    {
        var size = GetPictureSize();
        return point == null
            ? new Variant()
            : Variant.From(new Vector2(1f - point.Value.X / size.X, point.Value.Y / size.Y));
    }

    /// <summary>
    /// The hands of the player in the mirrored picture, normalized: [left,
    /// right], each null if not seen (left and right of her body).
    /// </summary>
    public Godot.Collections.Array GetPlayerHands() =>
        new() { Mirrored(_smoothedHands[0]), Mirrored(_smoothedHands[1]) };

    /// <summary>The player's 17 key points in the mirrored picture, normalized; empty without her.</summary>
    public Vector2[] GetKeypoints()
    {
        var snapshot = Latest;
        var pose = snapshot != null && snapshot.Players.Count > 0 ? snapshot.Players[0] : null;
        // NOTE (mristin):
        // The pose may come only a few times a second on a slow computer; we
        // keep showing the last one for a second, so that it does not flicker.
        if (pose == null || Now - snapshot!.Timestamp > 1.0)
        {
            return Array.Empty<Vector2>();
        }

        var points = new Vector2[Pose.KeypointCount];
        for (int i = 0; i < Pose.KeypointCount; i++)
        {
            var keypoint = pose.Keypoints[i];
            points[i] = new Vector2(1f - keypoint.X / snapshot.Width, keypoint.Y / snapshot.Height);
        }

        return points;
    }

    /// <summary>The scores of the key points of <see cref="GetKeypoints"/>.</summary>
    public float[] GetKeypointScores()
    {
        var snapshot = Latest;
        var pose = snapshot != null && snapshot.Players.Count > 0 ? snapshot.Players[0] : null;
        if (pose == null)
        {
            return Array.Empty<float>();
        }

        var scores = new float[Pose.KeypointCount];
        for (int i = 0; i < Pose.KeypointCount; i++)
        {
            scores[i] = pose.Keypoints[i].Score;
        }

        return scores;
    }

    /// <summary>Whether the pose sees both knees, which the kicks need.</summary>
    public bool SeesFeet()
    {
        var scores = GetKeypointScores();
        return HasPlayer() && scores.Length == Pose.KeypointCount
            && scores[(int)BodyPart.LeftKnee] >= 0.3f && scores[(int)BodyPart.RightKnee] >= 0.3f;
    }

    /// <summary>How high each knee is above the other, as a share of the thigh: (left, right); NaN if unknown.</summary>
    public Vector2 GetFootLifts() => new(Kicks[0].Lift, Kicks[1].Lift);

    /// <summary>How long the latest pose took, in milliseconds.</summary>
    public double GetInferenceMs() => Latest?.InferenceMs ?? 0.0;

    /// <summary>How many times a second the body pose runs now (see <see cref="PoseRate"/>).</summary>
    public double GetPoseRate() => _faceTracking ? 1.0 / PoseRate.Interval : 0.0;

    /// <summary>How long the latest heads and faces took, in milliseconds.</summary>
    public double GetFaceMs() => LatestFace?.InferenceMs ?? 0.0;

    public bool IsJumping() => Joystick.Jumping;

    /// <summary>How fast the player walks in place, in [0, 1].</summary>
    public float GetWalkSpeed() => Walk.Speed;

    public bool IsWalking() => Walk.Walking;

    /// <summary>The steps per second of the walking (each knee counts), or 0.</summary>
    public float GetCadence() => Walk.Cadence;

    /// <summary>How much higher the left knee is than the right one, in thighs; NaN if unknown.</summary>
    public float GetKneeLift() => Walk.Lift;

    /// <summary>The turn of the body in [-1, 1]: negative to the player's left.</summary>
    public float GetTurn() => Turn.Turn;

    /// <summary>The share of a full turn before the dead zone, positive to the player's left.</summary>
    public float GetTurnRaw() => Turn.Raw;

    /// <summary>The names of the depth cues, in the order of <see cref="GetCueDepths"/>.</summary>
    public string[] GetCueNames() => Enum.GetNames<DepthCue>();

    /// <summary>How much each cue of the depth grew since home (see <see cref="RoomJoystick.CueDepth"/>); NaN if unknown.</summary>
    public float[] GetCueDepths()
    {
        var depths = new float[DepthCues.Count];
        for (int i = 0; i < depths.Length; i++)
        {
            depths[i] = Joystick.CueDepth((DepthCue)i, Now);
        }

        return depths;
    }

    /// <summary>
    /// Start recording what the vision measures into the file (as JSON lines,
    /// see <see cref="VisionRecorder"/>; only numbers, never the pictures).
    /// Return whether it started.
    /// </summary>
    public bool StartRecording(string path)
    {
        StopRecording();
        try
        {
            _recorder = new VisionRecorder(ProjectSettings.GlobalizePath(path));
            var size = GetPictureSize();
            _recorder.RecordStart(Now, (int)size.X, (int)size.Y);
            return true;
        }
        catch (Exception exception)
        {
            GD.PushError($"Could not record into {path}: {exception.Message}");
            _recorder = null;
            return false;
        }
    }

    /// <summary>Label what the player is asked to do from now on in the recording.</summary>
    public void SetRecordingLabel(string label)
    {
        if (_recorder != null)
        {
            _recorder.Label = label;
        }
    }

    /// <summary>Mark this moment in the recording, e.g., when the player was called to jab.</summary>
    public void MarkRecording(string name) => _recorder?.RecordMark(Now, name);

    /// <summary>Stop recording, and return how many lines were recorded.</summary>
    public int StopRecording()
    {
        if (_recorder == null)
        {
            return 0;
        }

        int lines = _recorder.Lines;
        _recorder.Dispose();
        _recorder = null;
        return lines;
    }

    /// <summary>Forget the player, e.g., at the start of a fight.</summary>
    public void ResetPlayer()
    {
        Joystick.Reset();
        foreach (var detector in Punches)
        {
            detector.Reset();
        }

        foreach (var detector in Kicks)
        {
            detector.Reset();
        }

        _moves.Clear();
        _jumpsSeen = 0;
        Walk.Reset();
        Turn.Reset();
        foreach (var detector in PosePunches)
        {
            detector.Reset();
        }
    }

    private void SearchCamera(double now)
    {
        int count = CameraServer.GetFeedCount();
        if (count > 0 && double.IsNaN(_firstFeedAt))
        {
            _firstFeedAt = now;
        }

        bool timeout = now - _searchStarted > _cameraSearchTimeout;
        bool graceOver = !double.IsNaN(_firstFeedAt) && now - _firstFeedAt > _graceAfterFirstFeed;
        if (!timeout && !graceOver)
        {
            return;
        }

        var candidates = new List<(CameraFeed Feed, int Format)>();
        for (int i = 0; i < count; i++)
        {
            CameraFeed feed = CameraServer.GetFeed(i);
            int format = FindFormat(feed);
            if (format >= 0)
            {
                candidates.Add((feed, format));
            }
        }

        GD.Print($"The camera server reports {count} feed(s), {candidates.Count} compatible.");

        if (candidates.Count == 0)
        {
            // NOTE (mristin):
            // Godot 4.6 implements no camera on Windows: without the camera
            // extension, the camera server there never reports a feed, whatever
            // is plugged in. The players see the message of vision_status.gd.
            SetStatus(
                ServiceStatus.NoCamera,
                _noCameraReason switch
                {
                    "unsupported" => "The camera does not work on Windows without the camera extension.",
                    "denied" => "Windows does not allow the camera (Settings, Privacy, Camera).",
                    _ => count == 0 ? "No camera found." : "No camera supports 640x480, which the vision needs.",
                }
            );
            return;
        }

        var (chosen, formatIndex) = candidates[Math.Clamp(CameraIndex, 0, candidates.Count - 1)];
        StartCamera(chosen, formatIndex);
    }

    /// <summary>
    /// Find the 640x480 format, preferring YUYV; return -1 if there is none, and
    /// <see cref="_anyFormat"/> if the feed lists no formats at all.
    /// </summary>
    /// <remarks>
    /// Godot lists the formats only on Linux; elsewhere (e.g., on macOS) the feed
    /// runs at the resolution of the system, which the pipeline letterboxes anyhow.
    /// </remarks>
    private static int FindFormat(CameraFeed feed)
    {
        var formats = GetFormats(feed);
        if (formats.Count == 0)
        {
            return _anyFormat;
        }

        int fallback = -1;
        for (int i = 0; i < formats.Count; i++)
        {
            var format = formats[i].AsGodotDictionary();
            int width = format.ContainsKey("width") ? format["width"].AsInt32() : 0;
            int height = format.ContainsKey("height") ? format["height"].AsInt32() : 0;
            string pixelFormat = format.ContainsKey("format") ? format["format"].AsString() : "";
            if (width != 640 || height != 480)
            {
                continue;
            }

            // NOTE (mristin):
            // V4L2 on Linux calls the format YUYV, Media Foundation on Windows YUY2.
            if (pixelFormat.StartsWith("YUYV") || pixelFormat.StartsWith("YUY2"))
            {
                return i;
            }

            fallback = fallback < 0 ? i : fallback;
        }

        return fallback;
    }

    /// <summary>The format index of a feed which lists no formats (see <see cref="FindFormat"/>).</summary>
    private const int _anyFormat = int.MaxValue;

    private void StartCamera(CameraFeed feed, int formatIndex)
    {
        string description = formatIndex == _anyFormat
            ? $"{feed.GetName()}, the default format"
            : $"{feed.GetName()}, format #{formatIndex}: {GetFormats(feed)[formatIndex]}";
        GD.Print($"Starting the camera {description}");
        _feed = feed;
        if (formatIndex != _anyFormat)
        {
            SetFormat(_feed, formatIndex);
        }

        _feed.FeedIsActive = true;
        _nextActivationAttempt = Now + _activationRetryPeriod;

        CameraTexture = new CameraTexture { CameraFeedId = _feed.GetId(), CameraIsActive = true };
        _cbcrTexture = new CameraTexture
        {
            CameraFeedId = _feed.GetId(),
            WhichFeed = CameraServer.FeedImage.CbcrImage,
            CameraIsActive = true,
        };
        _feed.FrameChanged += OnFrameChanged;

        SetStatus(ServiceStatus.LoadingModels, "Loading the models...");

        byte[] poseModel = FileAccess.GetFileAsBytes(PoseModelPath);
        int threads = Threads;
        _running = true;
        StartThread("Pose", () => PoseLoop(poseModel, threads));

        if (FileAccess.FileExists(HeadModelPath) && FileAccess.FileExists(FaceModelPath))
        {
            byte[] headModel = FileAccess.GetFileAsBytes(HeadModelPath);
            byte[] faceModel = FileAccess.GetFileAsBytes(FaceModelPath);
            _faceTracking = true;
            StartThread("Face", () => FaceLoop(headModel, faceModel));
        }
        else
        {
            GD.PushWarning("The head or the face model is missing; the faces stay bare.");
        }
    }

    private void StartThread(string name, ThreadStart loop)
    {
        var thread = new Thread(loop)
        {
            IsBackground = true,
            Name = name,
            Priority = ThreadPriority.BelowNormal,
        };
        _threads.Add(thread);
        thread.Start();
    }

    private void OnFrameChanged()
    {
        // NOTE (mristin):
        // The time between the frames of the camera, which the faces must keep
        // up with (see PoseRate).
        double now = Now;
        if (!double.IsNaN(_lastFrameAt) && now > _lastFrameAt)
        {
            double seconds = Math.Min(0.2, now - _lastFrameAt);
            double smoothed = double.IsNaN(_frameSeconds) ? seconds : _frameSeconds * 0.9 + seconds * 0.1;
            Volatile.Write(ref _frameSeconds, smoothed);
        }

        _lastFrameAt = now;

        if (CameraTexture == null || _feed == null)
        {
            return;
        }

        bool forPose = _poseSlot.Requested;
        bool forFace = _faceSlot.Requested;
        bool twoPlanes = _feed.GetDatatype() == CameraFeed.FeedDataType.YcbcrSep;
        if (!forPose && !forFace && !twoPlanes)
        {
            return;
        }

        byte[] rgb;
        int width;
        int height;
        if (twoPlanes)
        {
            // NOTE (mristin):
            // A two-plane feed has no RGB texture, so we convert it ourselves, on
            // every frame, as the preview needs it, too.
            Image? luma = CameraTexture.GetImage();
            Image? chroma = _cbcrTexture?.GetImage();
            if (luma == null || luma.IsEmpty() || chroma == null || chroma.IsEmpty())
            {
                return;
            }

            (rgb, width, height) = YcbcrToRgb(luma, chroma, _maxYcbcrWidth);
            var preview = Image.CreateFromData(width, height, false, Image.Format.Rgb8, rgb);
            if (_ycbcrPreview == null || _ycbcrPreview.GetSize() != preview.GetSize())
            {
                _ycbcrPreview = ImageTexture.CreateFromImage(preview);
            }
            else
            {
                _ycbcrPreview.Update(preview);
            }

            if (!forPose && !forFace)
            {
                return;
            }
        }
        else
        {
            Image? image = CameraTexture.GetImage();
            if (image == null || image.IsEmpty())
            {
                return;
            }

            if (image.GetFormat() != Image.Format.Rgb8)
            {
                image.Convert(Image.Format.Rgb8);
            }

            rgb = image.GetData();
            width = image.GetWidth();
            height = image.GetHeight();
        }

        // NOTE (mristin):
        // We copy the raw bytes on the main thread so that the inference threads
        // never touch any engine objects. The threads only read the frame, so
        // they can share it.
        var frame = new Frame(rgb, width, height, Now);
        if (forPose)
        {
            _poseSlot.Put(frame);
        }

        if (forFace)
        {
            _faceSlot.Put(frame);
        }
    }

    /// <summary>Convert a Y plane and a CbCr plane of the camera to RGB8.</summary>
    private static (byte[] Rgb, int Width, int Height) YcbcrToRgb(Image luma, Image chroma, int maxWidth)
    {
        if (luma.GetFormat() != Image.Format.R8)
        {
            luma.Convert(Image.Format.R8);
        }

        if (chroma.GetFormat() != Image.Format.Rg8)
        {
            chroma.Convert(Image.Format.Rg8);
        }

        return YcbcrConverter.ToRgb(
            luma.GetData(), luma.GetWidth(), luma.GetHeight(),
            chroma.GetData(), chroma.GetWidth(), chroma.GetHeight(),
            maxWidth);
    }

    /// <summary>
    /// Activate the feed again if it did not start, which happens on macOS on the
    /// first start: the feed asks for the permission and stays off even when the
    /// players grant it.
    /// </summary>
    /// <remarks>
    /// While the system still asks, every attempt asks again, so we try only every
    /// few seconds; Godot keeps the capture session once there is one.
    /// </remarks>
    private void RetryActivation(double now)
    {
        if (_feed == null || _feed.FeedIsActive || double.IsNaN(_nextActivationAttempt)
            || now < _nextActivationAttempt)
        {
            return;
        }

        _nextActivationAttempt = now + _activationRetryPeriod;
        GD.Print("The camera did not start; trying again (maybe the camera permission was just granted).");
        _feed.FeedIsActive = true;
        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = true;
        }

        if (_cbcrTexture != null)
        {
            _cbcrTexture.CameraIsActive = true;
        }
    }

    /// <summary>Ask for the next camera frame and wait for it; null on a timeout or the exit.</summary>
    private Frame? NextFrame(FrameSlot slot)
    {
        slot.Requested = true;
        if (!slot.Ready.WaitOne(500) || !_running)
        {
            return null;
        }

        return slot.Take();
    }

    private void PoseLoop(byte[] poseModel, int threads)
    {
        RiderVision? vision = null;
        try
        {
            vision = new RiderVision(poseModel, threads);
            Callable.From(() => SetStatus(ServiceStatus.Running, "")).CallDeferred();

            var started = Stopwatch.StartNew();
            while (_running)
            {
                // NOTE (mristin):
                // With the face tracker, the pose only tells the hands apart and
                // dresses the bodies, so it runs only now and then, and leaves the
                // processor to the faces and the hands.
                if (_faceTracking)
                {
                    int wait = (int)((PoseRate.Interval - started.Elapsed.TotalSeconds) * 1000.0);
                    if (wait > 0)
                    {
                        Thread.Sleep(wait);
                    }
                }

                started.Restart();
                var frame = NextFrame(_poseSlot);
                if (frame != null)
                {
                    var snapshot = vision.Process(frame, PlayerCount);
                    PoseRate.ObservePose(snapshot.InferenceMs);
                    Volatile.Write(ref _latest, snapshot);
                }
            }
        }
        catch (Exception exception)
        {
            GD.PushError($"The vision failed: {exception}");
            string message = $"The vision failed: {exception.Message}";
            Callable.From(() => SetStatus(ServiceStatus.Failed, message)).CallDeferred();
        }
        finally
        {
            vision?.Dispose();
        }
    }

    private void FaceLoop(byte[] headModel, byte[] faceModel)
    {
        FaceTracker? tracker = null;
        try
        {
            tracker = new FaceTracker(headModel, faceModel);
            while (_running)
            {
                // NOTE (mristin):
                // The punches follow the hands on every frame.
                tracker.WantHands = true;
                var frame = NextFrame(_faceSlot);
                if (frame == null)
                {
                    continue;
                }

                // NOTE (mristin):
                // The pose tells which head is whose; it may be a few frames
                // old, which is close enough to tell the heads apart.
                var latest = Latest;
                var hints = new (float X, float Y)?[PlayerCount];
                for (int i = 0; i < hints.Length; i++)
                {
                    hints[i] = latest != null && i < latest.Players.Count ? latest.Players[i]?.Head(0.5f) : null;
                }

                var found = tracker.TrackAll(frame, hints);
                PoseRate.ObserveFace(found.InferenceMs, Volatile.Read(ref _frameSeconds));
                Volatile.Write(ref _latestFace, found);
            }
        }
        catch (Exception exception)
        {
            // NOTE (mristin):
            // Without the faces, the joystick follows the pose, which then runs as often as it can.
            GD.PushWarning($"The face tracking stopped: {exception}");
            _faceTracking = false;
        }
        finally
        {
            tracker?.Dispose();
        }
    }

    private void SetStatus(ServiceStatus status, string message)
    {
        Status = status;
        StatusMessage = message;
        GD.Print($"Vision: {status}: {message}");
    }

    public override void _ExitTree()
    {
        StopRecording();
        _running = false;
        _poseSlot.Ready.Set();
        _faceSlot.Ready.Set();
        foreach (var thread in _threads)
        {
            thread.Join(2000);
        }

        _threads.Clear();

        if (_feed != null)
        {
            _feed.FrameChanged -= OnFrameChanged;
            _feed.FeedIsActive = false;
            _feed = null;
        }

        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = false;
        }

        if (_cbcrTexture != null)
        {
            _cbcrTexture.CameraIsActive = false;
        }

        // NOTE (mristin):
        // The extension removes its feeds when it is freed, so it goes last.
        _cameraExtension = null;
    }
}