#!/usr/bin/env python3
"""The build scripts find the pinned .NET SDK on their own, and unregister the
apps they built from LaunchServices before deleting them."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROL_PLANE = REPOSITORY_ROOT / "Scripts" / "control-plane"
REQUIRES_ZSH = unittest.skipUnless(Path("/bin/zsh").exists(), "the scripts run in zsh")

# Records each call, and on `publish` leaves an app with an embedded app in
# the one build root under $TMPDIR, then fails, as an interrupted build would.
FAKE_DOTNET = """#!/bin/sh
printf '%s\\n' "$*" >> "$ODE_TEST_DOTNET_LOG"
if [ "$1" = publish ]; then
  for root in "$TMPDIR"/*/; do
    /bin/mkdir -p "${root}DerivedData/Build/Products/Debug/OdeNativeCore.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
  done
  exit 1
fi
exit 0
"""

# Records each call and whether the path it names still exists.
FAKE_LSREGISTER = """#!/bin/sh
if [ -e "$2" ]; then state=present; else state=missing; fi
printf '%s %s %s\\n' "$1" "$state" "$2" >> "$ODE_TEST_LSREGISTER_LOG"
"""


def write_executable(path: Path, contents: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
    path.chmod(0o755)
    return path


@REQUIRES_ZSH
class BuildScriptEnvironmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.scratch = self.root / "tmp"
        self.scratch.mkdir()
        self.dotnet_log = self.root / "dotnet.log"
        self.lsregister_log = self.root / "lsregister.log"
        self.sdk = self.root / "sdk"
        write_executable(self.sdk / "dotnet", FAKE_DOTNET)
        fake_lsregister = write_executable(self.root / "lsregister", FAKE_LSREGISTER)

        # A PATH with the tools the scripts use before dotnet, and no dotnet.
        self.tools = self.root / "tools"
        self.tools.mkdir()
        for tool in ("dirname", "mktemp", "rm"):
            located = shutil.which(tool)
            self.assertIsNotNone(located, tool)
            (self.tools / tool).symlink_to(located)

        self.environment = {
            "HOME": str(self.root / "home"),
            "PATH": str(self.tools),
            "TMPDIR": str(self.scratch),
            "ODE_DOTNET_INSTALL_DIR": str(self.sdk),
            "ODE_LSREGISTER": str(fake_lsregister),
            "ODE_TEST_DOTNET_LOG": str(self.dotnet_log),
            "ODE_TEST_LSREGISTER_LOG": str(self.lsregister_log),
        }

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_script(self, script: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(script), *arguments],
            cwd=REPOSITORY_ROOT,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )

    def calls(self, log: Path) -> list[str]:
        return log.read_text().splitlines() if log.exists() else []

    def new_app_path(self) -> str:
        return str(self.root / "output" / "OdeNativeCore.app")

    def test_dotnet_scripts_find_the_installed_sdk_when_dotnet_is_not_on_path(self) -> None:
        cases = (
            ("build-experiment.sh", (self.new_app_path(),), "test "),
            ("build-ios-experiment.sh", (self.new_app_path(),), "test "),
            ("generate-contracts.sh", ("--check",), "run "),
            ("lint-dotnet.sh", (), "restore "),
        )
        for name, arguments, first_call in cases:
            with self.subTest(script=name):
                self.dotnet_log.unlink(missing_ok=True)
                result = self.run_script(CONTROL_PLANE / name, *arguments)
                self.assertNotIn("command not found", result.stderr)
                calls = self.calls(self.dotnet_log)
                self.assertTrue(calls, result.stderr)
                self.assertTrue(calls[0].startswith(first_call), calls)

    def test_a_dotnet_already_on_path_is_used_instead(self) -> None:
        path_log = self.root / "path-dotnet.log"
        write_executable(
            self.root / "path-bin" / "dotnet",
            f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{path_log}'\n",
        )
        self.environment["PATH"] = f"{self.root / 'path-bin'}{os.pathsep}{self.tools}"

        result = self.run_script(CONTROL_PLANE / "generate-contracts.sh", "--check")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls(path_log)), 1)
        self.assertEqual(self.calls(self.dotnet_log), [])

    def test_a_missing_sdk_stops_before_building_and_names_the_installer(self) -> None:
        self.environment["ODE_DOTNET_INSTALL_DIR"] = str(self.root / "no-sdk")

        result = self.run_script(CONTROL_PLANE / "build-experiment.sh", self.new_app_path())

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("install-dotnet.sh", result.stderr)
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_build_experiment_unregisters_its_apps_before_deleting_them(self) -> None:
        result = self.run_script(CONTROL_PLANE / "build-experiment.sh", self.new_app_path())

        self.assertNotEqual(result.returncode, 0, "the fake publish fails the build")
        calls = self.calls(self.lsregister_log)
        self.assertEqual(len(calls), 2, calls)
        for call in calls:
            self.assertTrue(call.startswith("-u present "), call)
        unregistered = sorted(call.removeprefix("-u present ") for call in calls)
        self.assertTrue(unregistered[0].endswith("/Debug/OdeNativeCore.app"), unregistered)
        self.assertTrue(unregistered[1].endswith("/Versions/B/Updater.app"), unregistered)
        self.assertTrue(all(path.startswith(str(self.scratch)) for path in unregistered))
        self.assertEqual(list(self.scratch.iterdir()), [], "the build root is deleted")

    def test_unregister_apps_names_every_app_bundle_and_nothing_else(self) -> None:
        folder = self.scratch / "DerivedData"
        outer = folder / "Build" / "Products" / "Debug" / "Outer.app"
        inner = outer / "Contents" / "Helpers" / "Inner.app"
        inner.mkdir(parents=True)
        (folder / "Build" / "Products" / "Debug" / "Outer.app.dSYM").mkdir()
        (folder / "Logs").mkdir()

        result = self.run_script(CONTROL_PLANE / "unregister-apps.sh", str(folder))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            sorted(self.calls(self.lsregister_log)),
            sorted(f"-u present {path}" for path in (outer, inner)),
        )
        self.assertTrue(inner.is_dir(), "unregistering leaves the files in place")


if __name__ == "__main__":
    unittest.main()
