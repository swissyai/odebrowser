#!/usr/bin/env python3
"""Regression coverage for Ode's semantic-version contract."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-version.sh"
SET_SCRIPT = REPOSITORY_ROOT / "Scripts" / "set-version.sh"
# Only macOS ships plutil; CI runs these on its macOS build runners.
REQUIRES_PLUTIL = unittest.skipUnless(
    shutil.which("plutil"), "check-version.sh reads the Info.plists with macOS plutil"
)


class VersionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.fixture_root = pathlib.Path(self.temporary_directory.name)

        for relative_path in (
            "Config/Version.xcconfig",
            "OdeMac/Configuration/Ode-Info.plist",
            "OdeMobile/Configuration/OdeMobile-Info.plist",
            "Documentation/ReleaseNotes.json",
            "project.yml",
        ):
            source = REPOSITORY_ROOT / relative_path
            destination = self.fixture_root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        (self.fixture_root / "Ode.xcodeproj").mkdir()
        # Git identity overrides from the caller would decide who commits.
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("GIT_", "ODE_"))
        } | {
            "ODE_VERSION_REPOSITORY_ROOT": str(self.fixture_root),
            "ODE_REPOSITORY_OWNER": "fixture-owner",
        }
        self.current_version = self.current_marketing_version()
        major, minor, patch = (
            int(part) for part in self.current_version.split(".")
        )
        self.next_patch_version = f"{major}.{minor}.{patch + 1}"
        self.two_fix_version = f"{major}.{minor}.{patch + 2}"
        self.next_release_line = f"{major}.{minor + 1}.0"

        # The fixture commits on main as someone other than the owner, so a
        # fix commit there still needs its patch bump.
        subprocess.run(
            ["git", "init", "-q", "--initial-branch=main"],
            cwd=self.fixture_root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.email", "crest-tests@example.com"],
            cwd=self.fixture_root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Ode Tests"],
            cwd=self.fixture_root,
            check=True,
        )
        subprocess.run(["git", "add", "."], cwd=self.fixture_root, check=True)
        subprocess.run(
            ["git", "commit", "-qm", "fixture"],
            cwd=self.fixture_root,
            check=True,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CHECK_SCRIPT), *arguments],
            cwd=self.fixture_root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def run_set(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SET_SCRIPT), *arguments],
            cwd=self.fixture_root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def current_marketing_version(self) -> str:
        contents = (
            self.fixture_root / "Config" / "Version.xcconfig"
        ).read_text()
        return contents.split("=", maxsplit=1)[1].strip()

    def write_version(self, version: str) -> None:
        (self.fixture_root / "Config" / "Version.xcconfig").write_text(
            f"MARKETING_VERSION = {version}\n"
        )

    def stage_version(self) -> None:
        subprocess.run(
            ["git", "add", "Config/Version.xcconfig"],
            cwd=self.fixture_root,
            check=True,
        )

    def switch_to_branch(self, name: str) -> None:
        subprocess.run(
            ["git", "switch", "-q", "-c", name],
            cwd=self.fixture_root,
            check=True,
        )

    def commit_as(self, email: str) -> None:
        subprocess.run(
            ["git", "config", "user.email", email],
            cwd=self.fixture_root,
            check=True,
        )

    def stage_release_note(
        self,
        identifier: str = "fixture-change",
        entry: dict[str, str] | None = None,
    ) -> None:
        catalog_path = self.fixture_root / "Documentation" / "ReleaseNotes.json"
        catalog = json.loads(catalog_path.read_text())
        catalog["entries"][identifier] = entry or {
            "category": "fixed",
            "message": "Keep the fixture behavior reliable",
        }
        catalog_path.write_text(json.dumps(catalog, indent=2) + "\n")
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.fixture_root,
            check=True,
        )

    def install_fake_xcodebuild(self, marketing_version: str | None = None) -> None:
        fake_bin = self.fixture_root / "fake-bin"
        fake_bin.mkdir()
        fake_xcodebuild = fake_bin / "xcodebuild"

        if marketing_version is None:
            version_expression = (
                'sed -nE \'s/^[[:space:]]*MARKETING_VERSION[[:space:]]*='
                "[[:space:]]*([^[:space:]]+)[[:space:]]*$/\\1/p' "
                '"$ODE_VERSION_REPOSITORY_ROOT/Config/Version.xcconfig"'
            )
            marketing_line = f'marketing_version="$({version_expression})"'
        else:
            marketing_line = f'marketing_version="{marketing_version}"'

        fake_xcodebuild.write_text(
            "#!/bin/sh\n"
            f"{marketing_line}\n"
            'printf \'    MARKETING_VERSION = %s\\n\' "$marketing_version"\n'
            "printf '    CURRENT_PROJECT_VERSION = 1\\n'\n"
        )
        fake_xcodebuild.chmod(0o755)
        self.environment["PATH"] = f"{fake_bin}{os.pathsep}{os.environ['PATH']}"

    @REQUIRES_PLUTIL
    def test_repository_contract_passes_static_validation(self) -> None:
        result = subprocess.run(
            [str(CHECK_SCRIPT), "--static"],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.current_version, result.stdout)

    def test_static_check_rejects_malformed_semver(self) -> None:
        version_file = self.fixture_root / "Config" / "Version.xcconfig"

        for malformed in (
            "0.3",
            "01.3.0",
            "0.03.0",
            "0.3.00",
            "0.3.0-beta.1",
            "0.3.0+build.1",
        ):
            with self.subTest(version=malformed):
                version_file.write_text(f"MARKETING_VERSION = {malformed}\n")
                result = self.run_check("--static")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("strict X.Y.Z SemVer", result.stderr)

    @REQUIRES_PLUTIL
    def test_static_check_rejects_literal_plist_versions(self) -> None:
        plist = self.fixture_root / "OdeMac" / "Configuration" / "Ode-Info.plist"
        contents = plist.read_text().replace("$(MARKETING_VERSION)", "0.3.0")
        plist.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must substitute $(MARKETING_VERSION)", result.stderr)

    @REQUIRES_PLUTIL
    def test_static_check_rejects_configuration_drift(self) -> None:
        project = self.fixture_root / "project.yml"
        contents = project.read_text().replace(
            "  Release: Config/Version.xcconfig",
            "  Release: Config/ReleaseVersion.xcconfig",
            1,
        )
        project.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release must inherit Config/Version.xcconfig", result.stderr)

    def test_static_check_rejects_build_number_in_marketing_version_file(self) -> None:
        version_file = self.fixture_root / "Config" / "Version.xcconfig"
        version_file.write_text(
            f"MARKETING_VERSION = {self.current_version}\n"
            "CURRENT_PROJECT_VERSION = 2\n"
        )

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must contain only MARKETING_VERSION", result.stderr)

    def test_fix_commit_check_rejects_a_missing_staged_patch_bump(self) -> None:
        self.write_version(self.next_patch_version)

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stage Config/Version.xcconfig", result.stderr)

    @REQUIRES_PLUTIL
    def test_fix_commit_check_accepts_a_staged_patch_bump(self) -> None:
        self.write_version(self.two_fix_version)
        self.stage_version()
        self.stage_release_note()

        result = self.run_check("--fix-commit")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            f"{self.current_version} to {self.two_fix_version}", result.stdout
        )

    @REQUIRES_PLUTIL
    def test_fix_commit_check_requires_a_removal_to_carry_the_version_it_sets(
        self,
    ) -> None:
        self.write_version(self.next_patch_version)
        self.stage_version()

        def removal(removed_in: str) -> dict[str, str]:
            return {
                "category": "removed",
                "message": "The fixture behavior is gone.",
                "replacement": "no replacement",
                "removedIn": removed_in,
            }

        with self.subTest(removed_in="the version before the bump"):
            self.stage_release_note("fixture-removal", removal(self.current_version))
            result = self.run_check("--fix-commit")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fixture-removal", result.stderr)
            self.assertIn(self.next_patch_version, result.stderr)

        with self.subTest(removed_in="the version the commit sets"):
            self.stage_release_note("fixture-removal", removal(self.next_patch_version))
            result = self.run_check("--fix-commit")
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_static_check_rejects_a_removal_from_a_later_version(self) -> None:
        catalog_path = self.fixture_root / "Documentation" / "ReleaseNotes.json"
        catalog = json.loads(catalog_path.read_text())
        catalog["entries"]["fixture-removal"] = {
            "category": "removed",
            "message": "The fixture behavior is gone.",
            "replacement": "no replacement",
            "removedIn": self.next_release_line,
        }
        catalog_path.write_text(json.dumps(catalog, indent=2) + "\n")

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("later than the current version", result.stderr)

    def test_fix_commit_check_rejects_a_missing_staged_release_note(self) -> None:
        self.write_version(self.next_patch_version)
        self.stage_version()

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stage at least one new release-note entry", result.stderr)

    def test_fix_commit_check_rejects_a_new_release_line(self) -> None:
        self.write_version(self.next_release_line)
        self.stage_version()

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("patch version", result.stderr)

    @REQUIRES_PLUTIL
    def test_fix_commit_check_leaves_a_contribution_bump_to_the_maintainer(
        self,
    ) -> None:
        self.switch_to_branch("contribution")

        result = self.run_check("--fix-commit")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("the maintainer adds both when merging", result.stdout)

        self.write_version(self.next_release_line)
        self.stage_version()

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("patch version", result.stderr)

    def test_fix_commit_check_requires_the_bump_on_main_and_from_the_owner(
        self,
    ) -> None:
        with self.subTest(commit="someone else's commit on main"):
            result = self.run_check("--fix-commit")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stage Config/Version.xcconfig", result.stderr)

        self.switch_to_branch("owner-change")
        self.commit_as("1234+fixture-owner@users.noreply.github.com")
        with self.subTest(commit="the owner's commit on a branch"):
            result = self.run_check("--fix-commit")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stage Config/Version.xcconfig", result.stderr)

    def test_set_version_rejects_ambiguous_or_invalid_requests(self) -> None:
        for arguments in (
            (),
            (self.next_patch_version,),
            ("--patch", "0"),
            ("--patch", "-1"),
            ("--patch", "two"),
            ("--release", self.current_version),
            ("--release", self.next_patch_version),
            ("--release", "0.4"),
            ("--release", f"{self.current_version}-beta"),
        ):
            with self.subTest(arguments=arguments):
                result = self.run_set(*arguments)
                self.assertNotEqual(result.returncode, 0)

        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            f"MARKETING_VERSION = {self.current_version}\n",
        )

    @REQUIRES_PLUTIL
    def test_set_version_patch_count_updates_only_the_marketing_version_source(
        self,
    ) -> None:
        self.install_fake_xcodebuild()
        before = {
            path: (self.fixture_root / path).read_bytes()
            for path in (
                "OdeMac/Configuration/Ode-Info.plist",
                "OdeMobile/Configuration/OdeMobile-Info.plist",
                "project.yml",
            )
        }

        result = self.run_set("--patch", "2")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            f"MARKETING_VERSION = {self.two_fix_version}\n",
        )
        for path, contents in before.items():
            self.assertEqual((self.fixture_root / path).read_bytes(), contents)

    @REQUIRES_PLUTIL
    def test_set_version_requires_release_mode_to_change_release_lines(self) -> None:
        self.install_fake_xcodebuild()

        result = self.run_set("--release", self.next_release_line)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            f"MARKETING_VERSION = {self.next_release_line}\n",
        )

    @REQUIRES_PLUTIL
    def test_set_version_restores_the_previous_value_when_resolution_drifts(self) -> None:
        self.install_fake_xcodebuild(marketing_version="9.9.9")

        result = self.run_set("--patch")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"restored {self.current_version}", result.stderr)
        self.assertEqual(
            (self.fixture_root / "Config" / "Version.xcconfig").read_text(),
            f"MARKETING_VERSION = {self.current_version}\n",
        )


if __name__ == "__main__":
    unittest.main()
