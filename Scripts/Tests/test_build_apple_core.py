"""The core build phase reuses a current core, rebuilds when an input changes,
and passes .NET only the environment it needs."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


CONTROL_PLANE = Path(__file__).resolve().parents[1] / "control-plane"


class CoreBuild:
    """A repository holding the core build phase and the inputs it hashes,
    with the dotnet and xcrun calls the phase makes recorded instead of run."""

    def __init__(self, root: Path) -> None:
        self.repo = root / "repo"
        scripts = self.repo / "Scripts/control-plane"
        scripts.mkdir(parents=True)
        for name in ("build-apple-core.py", "content_filter.py"):
            shutil.copy2(CONTROL_PLANE / name, scripts / name)
        self.write("Scripts/control-plane/package-apple-core.py", "packages a framework")
        self.write("Scripts/control-plane/fetch-content-filter.py", "fetches the filter")
        self.write("OdeCore/global.json", "{}")
        self.write("OdeCore/Directory.Build.props", "<Project/>")
        self.write("OdeCore/src/OdeCore.Native/Exports.cs", "class Exports {}")
        self.write("OdeCore/src/OdeCore.Native/obj/project.assets.json", "ignored")
        self.write("OdeCore/tools/OdeCore.Generator/Program.cs", "class Program {}")
        self.write("OdeShared/Infrastructure/Core/Generated/Models.swift", "struct Model {}")
        crate = "CrestCore/native/ContentFilter"
        for name in ("Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "src/lib.rs",
                     "include/crest_content_filter.h", "artifact.lock.json"):
            self.write(f"{crate}/{name}", name)
        self.dotnet = self.write("dotnet/dotnet", "")
        self.products = root / "Build/Products/Debug"
        spec = importlib.util.spec_from_file_location("build_apple_core", scripts / "build-apple-core.py")
        self.module = importlib.util.module_from_spec(spec)
        with mock.patch.object(sys, "path", list(sys.path)):
            spec.loader.exec_module(self.module)
        self.commands: list[list[str]] = []
        self.environments: list[dict] = []

    def write(self, relative: str, text: str) -> Path:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def check_output(self, command, **kwargs):
        if command[0] == "xcrun":
            return "/SDKs/Platform.sdk\n" if "--show-sdk-path" in command else "26.0\n"
        if command[1:] == ["--version"]:
            return "10.0.100\n"
        raise AssertionError(f"Unexpected command: {command}")

    def run(self, command, **kwargs):
        command = [str(part) for part in command]
        self.commands.append(command)
        if "env" in kwargs:
            self.environments.append(kwargs["env"])
        if command[1] == "publish":
            publish = Path(command[command.index("-o") + 1])
            publish.mkdir(parents=True, exist_ok=True)
            (publish / "OdeCore.Native.dylib").write_text("core")
        if command[1].endswith("package-apple-core.py"):
            output = Path(command[command.index("--output") + 1])
            output.mkdir(parents=True)
            (output / "OdeCoreABI").write_text("core")
        return subprocess.CompletedProcess(command, 0)

    def environment(self, platform: str, **values: str) -> dict:
        variables = {
            "PLATFORM_NAME": platform, "BUILT_PRODUCTS_DIR": str(self.products), "ODE_DOTNET": str(self.dotnet),
            "CONFIGURATION": "Debug", "PATH": "/usr/bin:/bin", "HOME": "/Users/example", "TARGETNAME": "Ode",
            "DOTNET_CLI_TELEMETRY_OPTOUT": "1", "LC_ALL": "en_US.UTF-8", "ODE_CONTENT_FILTER_FROM_SOURCE": "",
        }
        directory = "ODE_CORE_LIBRARY_DIR" if platform == "macosx" else "ODE_CORE_FRAMEWORK_DIR"
        variables[directory] = str(self.products / "OdeCore")
        variables.update(values)
        return variables

    def build(self, platform: str = "macosx", **values: str) -> str:
        """Runs the phase; returns what it printed."""
        self.commands.clear()
        self.environments.clear()
        printed = io.StringIO()
        with mock.patch.dict(os.environ, self.environment(platform, **values), clear=True), \
                mock.patch.object(self.module.subprocess, "check_output", side_effect=self.check_output), \
                mock.patch.object(self.module.subprocess, "run", side_effect=self.run), \
                contextlib.redirect_stdout(printed):
            self.module.main()
        return printed.getvalue()


class BuildAppleCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.core = CoreBuild(self.root)

    def test_a_macos_build_checks_the_generated_code_then_publishes_and_installs_the_core(self) -> None:
        printed = self.core.build()

        output = self.core.products / "OdeCore"
        self.assertEqual(self.core.commands, [
            [str(self.core.dotnet), "run", "--project", "tools/OdeCore.Generator", "--nologo", "--", "--check",
             "--root", str(self.core.repo)],
            [str(self.core.dotnet), "publish", "src/OdeCore.Native", "-c", "Release", "-r", "osx-arm64",
             "--artifacts-path", str(output / "intermediates"), "-o", str(output / "publish"), "--nologo",
             "-p:OdeCrossChecks=true"],
        ])
        self.assertEqual((output / "OdeCore.Native.dylib").read_text(), "core")
        self.assertFalse((output / "OdeCore.Native.pending").exists())
        self.assertRegex((output / ".source-hash").read_text(), r"^[0-9a-f]{64}$")
        self.assertEqual(printed, "")
        for environment in self.core.environments:
            self.assertEqual(environment, {
                "PATH": "/usr/bin:/bin", "HOME": "/Users/example", "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
                "LC_ALL": "en_US.UTF-8", "ODE_CONTENT_FILTER_FROM_SOURCE": "", "SDKROOT": "/SDKs/Platform.sdk"})

    def test_a_current_core_is_reused_until_an_input_or_the_configuration_changes(self) -> None:
        self.core.build()
        self.assertEqual(self.core.build(), "Ode core is current (osx-arm64, SDK 10.0.100)\n")
        self.assertEqual(self.core.commands, [])

        self.core.write("OdeCore/src/OdeCore.Native/obj/project.assets.json", "still ignored")
        self.assertEqual(self.core.build(), "Ode core is current (osx-arm64, SDK 10.0.100)\n")

        changes = (
            lambda: self.core.write("OdeCore/src/OdeCore.Native/Exports.cs", "class Exports { int Changed; }"),
            lambda: self.core.write("OdeShared/Infrastructure/Core/Generated/Models.swift", "struct Changed {}"),
            lambda: self.core.write("CrestCore/native/ContentFilter/src/lib.rs", "changed"),
            lambda: self.core.write("Scripts/control-plane/fetch-content-filter.py", "changed"),
        )
        for change in changes:
            change()
            self.core.build()
            self.assertEqual(len(self.core.commands), 2)
            self.assertEqual(self.core.build(), "Ode core is current (osx-arm64, SDK 10.0.100)\n")
        self.core.build(CONFIGURATION="Release")
        self.assertEqual(self.core.commands[-1][-1], "-p:OdeCrossChecks=false")
        self.core.build(ODE_CONTENT_FILTER_FROM_SOURCE="1")
        self.assertEqual(len(self.core.commands), 2)

    def test_an_ios_build_packages_the_core_as_a_framework(self) -> None:
        output = self.core.products / "OdeCore"
        (output / "OdeCoreABI.framework").mkdir(parents=True)
        (output / "OdeCoreABI.framework/Stale").write_text("stale")

        self.core.build("iphonesimulator", CONFIGURATION="Release")

        publish, package = self.core.commands[1:]
        self.assertEqual(publish[publish.index("-r") + 1], "iossimulator-arm64")
        self.assertEqual(publish[-2:], ["-p:OdeCrossChecks=false", "-p:PublishAotUsingRuntimePack=true"])
        self.assertEqual(package[2:], ["--library", str(output / "publish/OdeCore.Native.dylib"),
                                       "--output", str(output / "OdeCoreABI.framework"),
                                       "--platform", "iphonesimulator"])
        self.assertEqual(sorted(path.name for path in (output / "OdeCoreABI.framework").iterdir()), ["OdeCoreABI"])
        self.assertEqual(self.core.build("iphonesimulator", CONFIGURATION="Release"),
                         "Ode core is current (iossimulator-arm64, SDK 10.0.100)\n")

    def test_an_explicit_core_is_used_as_it_is(self) -> None:
        explicit = self.root / "Prebuilt"
        explicit.mkdir()
        with self.assertRaises(RuntimeError) as refused:
            self.core.build(ODE_CORE_LIBRARY_DIR=str(explicit))
        self.assertEqual(str(refused.exception),
                         f"Explicit ODE_CORE_LIBRARY_DIR has no core library: {explicit / 'OdeCore.Native.dylib'}")
        (explicit / "OdeCore.Native.dylib").write_text("prebuilt")
        self.assertEqual(self.core.build(ODE_CORE_LIBRARY_DIR=str(explicit)),
                         f"Using explicitly supplied core: {explicit / 'OdeCore.Native.dylib'}\n")
        self.assertEqual(self.core.commands, [])

    def test_other_platforms_and_architectures_are_refused_with_the_phase_error(self) -> None:
        message = "The Ode core currently supports Apple silicon macOS and arm64 iOS/device Simulator builds"
        for platform, architectures in (("appletvos", "arm64"), ("macosx", "arm64 x86_64"), ("macosx", "x86_64")):
            with self.subTest(platform=platform, architectures=architectures):
                environment = self.core.environment(platform, ARCHS=architectures)
                result = subprocess.run([sys.executable, str(self.core.repo / "Scripts/control-plane/build-apple-core.py")],
                                        env=environment, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stderr, f"error: Ode core build failed: {message}\n")


if __name__ == "__main__":
    unittest.main()
