"""Publishing an engine checks that the checkout holds this branch's host and a
current build, never overwrites a published engine, and publishes a draft only
once every asset has uploaded."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CONTROL_PLANE = REPOSITORY_ROOT / "Scripts/control-plane"
sys.path.insert(0, str(CONTROL_PLANE))
import chromium_engine  # noqa: E402

SPEC = importlib.util.spec_from_file_location("publish_chromium_engine", CONTROL_PLANE / "publish-chromium-engine.py")
PUBLISHING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLISHING)
HEADERS = ("CrestEngines/Chromium/Apple/CrestChromiumHost.h",
           "CrestCore/native/ContentFilter/include/crest_content_filter.h",
           "CrestContracts/include/crest_core.h", "CrestContracts/include/crest_app.h",
           "CrestContracts/include/crest_engine.h", "CrestContracts/include/crest_engine_contract.h")
COMMIT = "0123456789abcdef0123456789abcdef01234567"


class Checkout:
    """An external Chromium checkout holding this branch's overlay and headers,
    with the commands publishing runs recorded and answered."""

    def __init__(self, root: Path) -> None:
        self.source = root / "src"
        overlay = REPOSITORY_ROOT / "CrestEngines/Chromium/Overlay"
        shutil.copytree(overlay, self.source)
        for header in HEADERS:
            destination = self.source / "chrome/browser/ui/crest" / Path(header).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPOSITORY_ROOT / header, destination)
        self.validation = "Host inputs (after) match.\n"
        self.plan = "ninja: no work to do.\n"
        self.release = None
        self.commands: list[list[str]] = []
        self.uploads: dict[str, str] = {}
        self.key = chromium_engine.engine_key(REPOSITORY_ROOT)
        self.tag, self.asset = chromium_engine.release_tag(self.key), chromium_engine.asset_name(self.key)

    def run(self, command, check=False, **kwargs):
        command = [str(part) for part in command]
        self.commands.append(command)
        stdout = ""
        returncode = 0
        if command[1:2] == [str(CONTROL_PLANE / "apply-chromium-host.py")]:
            stdout = self.validation
        elif "-n" in command and command[-1] == "chrome":
            stdout = self.plan
        elif command[:3] == ["gh", "release", "view"]:
            returncode, stdout = (1, "") if self.release is None else (0, json.dumps(self.release))
        elif command[0] == "ditto":
            Path(command[-1]).write_bytes(b"engine archive")
        elif command[:3] == ["gh", "release", "upload"]:
            self.uploads = {Path(path).name: Path(path).read_text() for path in command[4:7]}
        elif command[:2] == ["git", "-C"]:
            stdout = COMMIT + "\n"
        return subprocess.CompletedProcess(command, returncode, stdout, "")

    def publish(self, *arguments: str, configuration_matches: bool = True) -> str:
        argv = ["publish-chromium-engine.py", "--source", str(self.source), "--ninja", "/opt/ninja", *arguments]
        printed = io.StringIO()
        with mock.patch.object(sys, "argv", argv), \
                mock.patch.object(PUBLISHING.subprocess, "run", side_effect=self.run), \
                mock.patch.object(PUBLISHING, "performance_configuration_matches",
                                  return_value=configuration_matches), \
                contextlib.redirect_stdout(printed):
            PUBLISHING.main()
        return printed.getvalue()

    def gh(self) -> list[list[str]]:
        return [command for command in self.commands if command[0] == "gh"]


class PublishChromiumEngineTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.checkout = Checkout(Path(directory.name).resolve())
        self.lock = json.loads((REPOSITORY_ROOT / "CrestEngines/Chromium/source.lock.json").read_text())

    def refusal(self, **options) -> str:
        with self.assertRaises(SystemExit) as stopped:
            self.checkout.publish(**options)
        return str(stopped.exception.code)

    def test_a_checkout_that_is_not_this_branchs_current_engine_is_refused(self) -> None:
        checkout = self.checkout
        self.assertEqual(self.refusal(configuration_matches=False),
                         "Published engines require the pinned performance configuration, SDK and PGO profile")
        self.assertEqual(checkout.commands, [])

        checkout.validation = "Host inputs (before) match.\n"
        self.assertEqual(self.refusal(), "Apply the host to the checkout before publishing: Host inputs (before) match.")
        checkout.validation = "Host inputs (after) match.\n"

        overlay_file = next(path for path in sorted(checkout.source.rglob("*")) if path.is_file()
                            and "chrome/browser/ui/crest" not in path.as_posix())
        original = overlay_file.read_bytes()
        overlay_file.write_bytes(original + b"\n")
        self.assertEqual(self.refusal(), "The checkout's overlay differs from the branch: "
                         + overlay_file.relative_to(checkout.source).as_posix())
        overlay_file.write_bytes(original)

        header = checkout.source / "chrome/browser/ui/crest/crest_engine.h"
        header.write_text("changed")
        self.assertEqual(self.refusal(), "The checkout's contract header differs from the branch: crest_engine.h")
        shutil.copy2(REPOSITORY_ROOT / "CrestContracts/include/crest_engine.h", header)

        checkout.plan = "[1/2] CXX obj/chrome/browser.o\n"
        self.assertEqual(self.refusal(), "The engine build is not current; run build-chromium-baseline.py first")
        self.assertEqual(checkout.gh(), [])

    def test_checks_run_in_order_before_anything_is_packaged(self) -> None:
        self.checkout.release = {"isDraft": True, "assets": [], "body": ""}
        self.checkout.publish("--dry-run")
        commands = self.checkout.commands
        self.assertEqual(commands[0], [sys.executable, str(CONTROL_PLANE / "prepare-chromium.py"),
                                       "--source", str(self.checkout.source), "--verify-only"])
        self.assertEqual(commands[1], [sys.executable, str(CONTROL_PLANE / "apply-chromium-host.py"),
                                       "--source", str(self.checkout.source)])
        self.assertEqual(commands[2], ["/opt/ninja", "-C", str(self.checkout.source / "out/CrestBaseline"),
                                       "-n", "chrome"])
        self.assertEqual(commands[3], ["gh", "release", "view", self.checkout.tag, "--repo", "pauljoda/Crest",
                                       "--json", "assets,isDraft,body"])
        self.assertEqual(commands[4][:5], ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent"])
        self.assertEqual(commands[4][5], str(self.checkout.source / "out/CrestBaseline/Chromium.app"))
        self.assertEqual(len(commands), 5)

    def test_a_published_engine_is_left_as_it_is_and_never_overwritten(self) -> None:
        checkout = self.checkout
        complete = {"isDraft": False, "body": f"Engine key `{checkout.key}`",
                    "assets": [{"name": checkout.asset}, {"name": checkout.asset + ".sha256"}]}
        checkout.release = complete
        self.assertEqual(checkout.publish(), f"{checkout.tag} is already published.\n")
        refused = "Published engine release is incomplete or has a different full key; refusing to overwrite it"
        for release in (complete | {"assets": complete["assets"][:1]}, complete | {"body": "Engine key `other`"}):
            with self.subTest(release=release):
                checkout.release = release
                self.assertEqual(self.refusal(), refused)
        self.assertEqual([command[:3] for command in checkout.gh()], [["gh", "release", "view"]] * 3)

    def test_a_dry_run_packages_without_uploading(self) -> None:
        printed = self.checkout.publish("--dry-run")
        digest = hashlib.sha256(b"engine archive").hexdigest()
        self.assertEqual(printed, f"Packaged {self.checkout.asset} (0 MiB, sha256 {digest}).\n")
        self.assertEqual([command[:3] for command in self.checkout.gh()], [["gh", "release", "view"]])

    def test_a_new_engine_is_drafted_uploaded_then_published(self) -> None:
        checkout = self.checkout
        printed = checkout.publish("--repository", "example/engines")

        digest = hashlib.sha256(b"engine archive").hexdigest()
        create, upload, edit = checkout.gh()[1:]
        notes = (f"Chromium {self.lock['chromium']['version']} with Ode's native host, for release packaging.\n\n"
                 f"Engine key `{checkout.key}`, computed by `Scripts/control-plane/chromium_engine.py` over the "
                 f"engine inputs of commit `{COMMIT}`.\n"
                 "This is not an installable browser; releases package it with Ode's UI and sign it.")
        self.assertEqual(create, ["gh", "release", "create", checkout.tag, "--repo", "example/engines", "--draft",
                                  "--prerelease", "--latest=false", "--title",
                                  f"Ode Chromium engine {checkout.key[:16]}", "--notes", notes])
        self.assertEqual(upload[-3:], ["--repo", "example/engines", "--clobber"])
        self.assertEqual(edit, ["gh", "release", "edit", checkout.tag, "--repo", "example/engines",
                                "--draft=false", "--latest=false"])
        self.assertEqual(checkout.uploads[checkout.asset], "engine archive")
        self.assertEqual(checkout.uploads[checkout.asset + ".sha256"], f"{digest}  {checkout.asset}\n")
        self.assertEqual(json.loads(checkout.uploads[checkout.asset + ".json"]), {
            "schemaVersion": 1, "engineKey": checkout.key, "chromium": self.lock["chromium"]["version"],
            "sourceArchiveSHA256": self.lock["chromium"]["sourceArchiveSha256"], "configuration": "performance",
            "sdkVersion": self.lock["performanceInputs"]["macSDKVersion"],
            "pgoSHA256": self.lock["performanceInputs"]["pgoSHA256"], "archiveSHA256": digest,
            "sourceCommit": COMMIT})
        self.assertTrue(checkout.uploads[checkout.asset + ".json"].endswith("}\n"))
        self.assertEqual(printed, f"Packaged {checkout.asset} (0 MiB, sha256 {digest}).\nPublished {checkout.tag}.\n")

    def test_an_unpublished_draft_is_resumed_without_a_second_release(self) -> None:
        self.checkout.release = {"isDraft": True, "assets": [], "body": ""}
        self.checkout.publish()
        self.assertEqual([command[:3] for command in self.checkout.gh()],
                         [["gh", "release", "view"], ["gh", "release", "upload"], ["gh", "release", "edit"]])


if __name__ == "__main__":
    unittest.main()
