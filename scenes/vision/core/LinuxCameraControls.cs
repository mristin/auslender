using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

// NOTE (mristin):
// This file does not depend on Godot, so that we can unit-test the computer
// vision outside of the engine. See tests/Auslender.Tests.

namespace Auslender.Vision
{
    /// <summary>
    /// Set the controls of a webcam on Linux (Video4Linux), which Godot does not offer.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Many webcams halve their frame rate in dim light, to expose each frame longer
    /// (the control "Exposure, Dynamic Framerate"): the laptop's camera gave 15 instead of
    /// 30 frames a second in a living room in the evening. Fast moves then blur and come
    /// in half as many poses, so we switch it off; the picture gets a little darker
    /// (a mean brightness of 96 instead of 111 of 255), which the pose does not mind.
    /// </para>
    /// <para>
    /// Only on Linux. Nothing here throws: a camera without the control, a device which
    /// we can not open or which is no camera, a system without /sys or without libc,
    /// all leave the camera as it is.
    /// </para>
    /// </remarks>
    public static class LinuxCameraControls
    {
        /// <summary>V4L2_CID_EXPOSURE_AUTO_PRIORITY: "Exposure, Dynamic Framerate".</summary>
        public const uint DynamicFrameRate = 0x009A0903;

        // NOTE (mristin):
        // _IOWR('V', 28, struct v4l2_control): struct v4l2_control is { __u32 id; __s32 value; }.
        private const ulong SetControl = 0xC008561C;

        private const int ReadWrite = 0x2;
        private const int NonBlocking = 0x800;

        [StructLayout(LayoutKind.Sequential)]
        private struct Control
        {
            public uint Id;
            public int Value;
        }

        [DllImport("libc", EntryPoint = "open", SetLastError = true)]
        private static extern int Open(string path, int flags);

        [DllImport("libc", EntryPoint = "ioctl", SetLastError = true)]
        private static extern int Ioctl(int descriptor, ulong request, ref Control control);

        [DllImport("libc", EntryPoint = "close", SetLastError = true)]
        private static extern int Close(int descriptor);

        /// <summary>
        /// The video devices (e.g., "/dev/video0") of the camera with the given name, as
        /// listed under <paramref name="sysRoot"/>; a camera often has two (the picture and
        /// its metadata).
        /// </summary>
        public static List<string> DevicesOf(string cameraName, string sysRoot = "/sys/class/video4linux")
        {
            var devices = new List<string>();
            string[] entries;
            try
            {
                if (!Directory.Exists(sysRoot))
                {
                    return devices;
                }

                entries = Directory.GetDirectories(sysRoot);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                return devices;
            }

            foreach (string entry in entries)
            {
                string name;
                try
                {
                    string nameFile = Path.Combine(entry, "name");
                    if (!File.Exists(nameFile))
                    {
                        continue;
                    }

                    name = File.ReadAllText(nameFile).Trim();
                }
                catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
                {
                    continue;
                }

                if (name.Length > 0 && name == cameraName.Trim())
                {
                    devices.Add("/dev/" + Path.GetFileName(entry));
                }
            }

            devices.Sort(StringComparer.Ordinal);
            return devices;
        }

        /// <summary>
        /// Keep the full frame rate of the camera with the given name (switch off the
        /// dynamic frame rate); return the devices on which it was switched off.
        /// </summary>
        public static List<string> KeepFullFrameRate(string cameraName)
        {
            var done = new List<string>();
            if (!OperatingSystem.IsLinux() || string.IsNullOrWhiteSpace(cameraName))
            {
                return done;
            }

            foreach (string device in DevicesOf(cameraName))
            {
                if (TrySet(device, DynamicFrameRate, 0))
                {
                    done.Add(device);
                }
            }

            return done;
        }

        /// <summary>Set a control of a video device; false if it could not.</summary>
        public static bool TrySet(string device, uint id, int value)
        {
            if (!OperatingSystem.IsLinux())
            {
                return false;
            }

            // NOTE (mristin):
            // The ioctl fails (with -1) on a camera without the control, and on
            // anything which is no video device; we only report that it did not work.
            int descriptor = -1;
            try
            {
                descriptor = Open(device, ReadWrite | NonBlocking);
                if (descriptor < 0)
                {
                    return false;
                }

                var control = new Control { Id = id, Value = value };
                return Ioctl(descriptor, SetControl, ref control) == 0;
            }
            catch (Exception exception) when (
                exception is DllNotFoundException or EntryPointNotFoundException or MarshalDirectiveException)
            {
                return false;
            }
            finally
            {
                if (descriptor >= 0)
                {
                    Close(descriptor);
                }
            }
        }
    }
}
