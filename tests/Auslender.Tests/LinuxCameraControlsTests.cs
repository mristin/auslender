using System;
using System.IO;

using Auslender.Vision;
using Xunit;

namespace Auslender.Tests
{
    public class LinuxCameraControlsTests
    {
        private static string FakeSys()
        {
            string root = Path.Combine(Path.GetTempPath(), "auslender-v4l-" + Guid.NewGuid().ToString("N"));
            foreach (var (device, name) in new[]
            {
                ("video0", "Integrated Camera: Integrated C\n"),
                ("video1", "Integrated Camera: Integrated C\n"),
                ("video2", "USB Camera\n"),
            })
            {
                Directory.CreateDirectory(Path.Combine(root, device));
                File.WriteAllText(Path.Combine(root, device, "name"), name);
            }

            // NOTE (mristin):
            // A device without a name file must not get in the way.
            Directory.CreateDirectory(Path.Combine(root, "video3"));
            return root;
        }

        [Fact]
        public void Finds_the_devices_of_a_camera_by_its_name()
        {
            string root = FakeSys();
            try
            {
                Assert.Equal(
                    new[] { "/dev/video0", "/dev/video1" },
                    LinuxCameraControls.DevicesOf("Integrated Camera: Integrated C", root));
                Assert.Equal(new[] { "/dev/video2" }, LinuxCameraControls.DevicesOf("USB Camera", root));
                Assert.Empty(LinuxCameraControls.DevicesOf("No Such Camera", root));
                Assert.Empty(LinuxCameraControls.DevicesOf("", root));
            }
            finally
            {
                Directory.Delete(root, recursive: true);
            }
        }

        [Fact]
        public void Finds_nothing_without_the_system_directory()
        {
            Assert.Empty(LinuxCameraControls.DevicesOf("Any", "/no/such/directory"));
        }

        [Fact]
        public void Does_not_break_on_what_is_no_camera()
        {
            // NOTE (mristin):
            // A missing device, and a plain file (the control can not be set on it).
            Assert.False(LinuxCameraControls.TrySet("/no/such/device", LinuxCameraControls.DynamicFrameRate, 0));
            string file = Path.GetTempFileName();
            try
            {
                Assert.False(LinuxCameraControls.TrySet(file, LinuxCameraControls.DynamicFrameRate, 0));
            }
            finally
            {
                File.Delete(file);
            }
        }

        [Fact]
        public void Does_not_break_on_an_unknown_camera()
        {
            Assert.Empty(LinuxCameraControls.KeepFullFrameRate("No Such Camera"));
            Assert.Empty(LinuxCameraControls.KeepFullFrameRate(""));
        }
    }
}
