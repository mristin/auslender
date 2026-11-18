#!/usr/bin/env python3

"""
Package the game for Linux, Windows and macOS into build/.

We export with the presets of export_presets.cfg, and add what Godot does not
export itself: our license and the licenses of the third parties, and, on
Windows, the camera extension next to the executable (see
addons/CameraServerExtension/CameraServerExtension.gdextension).

You need the export templates of Godot 4.6.2 (.NET); see CONTRIBUTING.md,
"Packaging".
"""

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import zipfile
from typing import List, Optional

REPO_ROOT = pathlib.Path(os.path.realpath(__file__)).parent.parent

BUILD_DIR = REPO_ROOT / "build"

EXTENSION_DIR = REPO_ROOT / "addons" / "CameraServerExtension"

# NOTE (mristin):
# The export preset and the path of the export in build/; macOS exports an
# archive, the others a folder.
PLATFORMS = {
    "linux": ("Linux", "linux/auslender.x86_64"),
    "windows": ("Windows", "windows/auslender.exe"),
    "macos": ("macOS", "macos/auslender.zip"),
}


def find_godot(explicit: Optional[str]) -> Optional[str]:
    """Find the Godot 4.6 .NET executable in the arguments, environment or path."""
    if explicit is not None:
        return explicit

    from_env = os.environ.get("GODOT")
    if from_env:
        return from_env

    for name in ("godot", "godot4", "godot-mono", "godot4-mono"):
        found = shutil.which(name)
        if found is not None:
            return found

    return None


def run(cmd: List[str]) -> None:
    """Run the command in the repository, and stop on failure."""
    print(f"Executing: {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def copy_licenses(directory: pathlib.Path) -> None:
    """Copy our license and the third-party licenses into the package folder."""
    shutil.copy2(REPO_ROOT / "LICENSE", directory / "LICENSE")
    shutil.copytree(
        REPO_ROOT / "licenses",
        directory / "licenses",
        dirs_exist_ok=True,
        ignore=shutil.ignore_patterns(".gdignore"),
    )


def add_camera_extension(directory: pathlib.Path) -> None:
    """Put the camera extension next to the Windows executable, with its license."""
    for name in (
        "CameraServerExtension.gdextension",
        "libcameraserver-extension.windows.dll",
    ):
        shutil.copy2(EXTENSION_DIR / name, directory / name)

    license_dir = directory / "licenses" / "camera-server-extension"
    license_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EXTENSION_DIR / "LICENSE", license_dir / "LICENSE")


def add_licenses_to_archive(archive: pathlib.Path) -> None:
    """Add our license and the third-party licenses to the macOS archive, beside the app."""
    with zipfile.ZipFile(archive, "a", compression=zipfile.ZIP_DEFLATED) as zip_file:
        existing = set(zip_file.namelist())
        sources = [REPO_ROOT / "LICENSE"] + sorted(
            path
            for path in (REPO_ROOT / "licenses").rglob("*")
            if path.is_file() and path.name != ".gdignore"
        )
        for source in sources:
            name = source.relative_to(REPO_ROOT).as_posix()
            if name not in existing:
                zip_file.write(source, name)


def main() -> int:
    """Execute the main routine."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--platforms",
        nargs="+",
        choices=sorted(PLATFORMS),
        default=sorted(PLATFORMS),
        help="Which platforms to package (default: all)",
    )
    parser.add_argument("--godot", help="The Godot executable (default: $GODOT or the path)")
    args = parser.parse_args()

    godot = find_godot(args.godot)
    if godot is None:
        print("Could not find Godot; set GODOT or pass --godot.", file=sys.stderr)
        return 1

    # NOTE (mristin):
    # The .gdignore hides the packages from Godot, which would otherwise import
    # them, and try to load the camera extension of the Windows package on
    # every platform, and fail.
    BUILD_DIR.mkdir(exist_ok=True)
    (BUILD_DIR / ".gdignore").touch()

    try:
        run(["dotnet", "build", "Auslender.sln", "-c", "Release"])

        for platform in args.platforms:
            preset, relative = PLATFORMS[platform]
            output = BUILD_DIR / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            run([godot, "--headless", "--path", ".", "--export-release", preset, str(output)])

            if platform == "macos":
                add_licenses_to_archive(output)
            else:
                copy_licenses(output.parent)

            if platform == "windows":
                add_camera_extension(output.parent)

            print(f"Packaged {preset} into {output.relative_to(REPO_ROOT)}.", flush=True)
    except subprocess.CalledProcessError as exception:
        print(f"Failed with exit code {exception.returncode}.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
