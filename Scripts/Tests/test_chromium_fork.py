"""Protect upstream selection, persistent build ownership, and publication gates."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "control-plane"
sys.path.insert(0, str(SCRIPTS))
from chromium_fork import (BUILD_DIRECTORY, PREPARATION_FIELDS, REPO, Workspace, exclusive_workspace,
                           ninja_is_building, preparation_key, prune_sources, refresh_host_inputs, restore_host_base,
                           select_update, sha256, validate_workspace)
from chromium_artifact import release_ready
from chromium_engine import asset_name, host_patch

spec = importlib.util.spec_from_file_location("publish_chromium_update", SCRIPTS / "publish-chromium-update.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


class UpstreamSelectionTests(unittest.TestCase):
    def test_patch_releases_stay_eligible_after_the_next_milestone_ships(self):
        releases = ["157.0.8103.26", "156.0.8078.80", "156.0.8078.47", "unrecognized"]
        result = select_update("156.0.8078.47", releases)
        self.assertEqual(result["candidate"], "156.0.8078.80")
        self.assertEqual(result["latest"], "157.0.8103.26")
        self.assertTrue(result["majorReviewRequired"])
        self.assertEqual(select_update("156.0.8078.47", releases, True)["candidate"], "157.0.8103.26")

    def test_updates_advance_but_downgrades_and_equal_versions_do_not(self):
        releases = ["156.0.8078.80", "156.0.8078.79"]
        self.assertEqual(select_update("156.0.8078.79", releases)["candidate"], "156.0.8078.80")
        self.assertIsNone(select_update("156.0.8078.80", releases)["candidate"])


class WorkspaceTests(unittest.TestCase):
    def test_switching_host_revisions_accepts_an_exact_legacy_install_but_preserves_local_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            path = source / "sample.cc"
            hashes = {}
            for state in ("base", "old", "desired"):
                path.write_text(f"{state}\n")
                hashes[state] = sha256(path)
            previous = {"patch": "--- a/sample.cc\n+++ b/sample.cc\n@@ -1 +1 @@\n-base\n+old\n",
                        "inputs": {"sample.cc": {"before": hashes["base"], "after": hashes["old"]}}}
            desired = {"sample.cc": {"before": hashes["base"], "after": hashes["desired"]}}
            restore_host_base(source, previous, desired)
            self.assertEqual(path.read_text(), "desired\n")
            path.write_text("old\n")
            restore_host_base(source, previous, desired)
            self.assertEqual(path.read_text(), "base\n")
            path.write_text("unreviewed local edit\n")
            with self.assertRaisesRegex(ValueError, "Locally modified"):
                restore_host_base(source, previous, desired)
            self.assertEqual(path.read_text(), "unreviewed local edit\n")

    def test_a_workspace_is_named_by_the_preparation_inputs_of_the_pinned_lock(self):
        lock = json.loads((REPO / "CrestEngines/Chromium/source.lock.json").read_text())
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Workspace(Path(temporary) / "OdeChromium")
            self.assertEqual(workspace.directory, workspace.root / "sources" / workspace.key[:20])
        self.assertEqual(workspace.key, preparation_key(REPO, lock))
        patches = {name: "0" * 64 for name in lock["crestPatches"]}
        self.assertNotEqual(preparation_key(REPO, dict(lock, crestPatches=patches)), workspace.key)
        self.assertEqual(preparation_key(REPO, dict(lock, buildArguments={})), workspace.key)

    def test_independent_operations_cannot_share_a_locked_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with exclusive_workspace(root):
                with self.assertRaisesRegex(ValueError, "Another Chromium operation"):
                    with exclusive_workspace(root):
                        self.fail("Second writer obtained the lock")
            with exclusive_workspace(root):
                pass

    def test_workspace_cannot_alias_or_contain_the_product_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "Ode"
            repo.mkdir()
            alias = root / "alias"
            alias.symlink_to(repo, target_is_directory=True)
            for workspace in (root, repo, repo / "build", alias / "build"):
                with self.subTest(workspace=workspace), self.assertRaises(ValueError):
                    validate_workspace(workspace, repo)
            self.assertEqual(validate_workspace(root / "OdeChromium", repo), (root / "OdeChromium").resolve())

    def test_the_workspace_runner_may_check_crest_out_in_its_own_work_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary) / "OdeChromium"
            checkout = workspace / "runner-work" / "Ode" / "Ode"
            checkout.mkdir(parents=True)
            self.assertEqual(validate_workspace(workspace, checkout), workspace.resolve())
            elsewhere = workspace / "sources" / "Ode"
            elsewhere.mkdir(parents=True)
            with self.assertRaises(ValueError):
                validate_workspace(workspace, elsewhere)

    def test_host_changes_wait_for_a_ninja_build_of_the_engine_directory(self):
        self.assertEqual(BUILD_DIRECTORY, "out/CrestBaseline")
        building = f"ninja              ninja -C {BUILD_DIRECTORY} -j8 chrome\n"
        self.assertTrue(ninja_is_building(building))
        self.assertTrue(ninja_is_building(f"/opt/bin/ninja /opt/bin/ninja -C /work/src/{BUILD_DIRECTORY} chrome\n"))
        for idle in ("", "\n", "ninja ninja -C out/Default chrome\n", f"python3 python3 build.py {BUILD_DIRECTORY}\n",
                     "ninja ninja -C out/OdeBaseline chrome\n"):
            with self.subTest(processes=idle):
                self.assertFalse(ninja_is_building(idle))
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "Ode"
            (repo / "CrestEngines/Chromium").mkdir(parents=True)
            (repo / "Scripts/control-plane").mkdir(parents=True)
            (repo / "Scripts/control-plane/prepare-chromium.py").write_text("")
            (repo / "CrestEngines/Chromium/source.lock.json").write_text(
                json.dumps({field: {} for field in PREPARATION_FIELDS}))
            workspace = Workspace(Path(temporary) / "OdeChromium", repo)
            with mock.patch("chromium_fork.run", return_value=building):
                with self.assertRaisesRegex(ValueError, "Wait for the active Chromium build"):
                    workspace.apply_host()

    def test_pruning_removes_only_other_prepared_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertEqual(prune_sources(root, set()), [])
            sources = root / "sources"
            pinned, update, superseded = "a" * 20, "b" * 20, "c" * 20
            for name in (pinned, update, superseded, "manual-build"):
                (sources / name / "upstream").mkdir(parents=True)
            (sources / ("d" * 20)).symlink_to(sources / pinned)
            self.assertEqual(prune_sources(root, {pinned, update}), [superseded])
            self.assertEqual(sorted(path.name for path in sources.iterdir()),
                             [pinned, update, "d" * 20, "manual-build"])
            self.assertTrue((sources / pinned / "upstream").is_dir())
    def host(self, root, patches):
        repo = root / "repo"
        host = repo / "CrestEngines/Chromium"
        (host / "Patches").mkdir(parents=True)
        for name, text in patches.items():
            (host / "Patches" / name).write_text(text)
        (host / "Patches/series").write_text("# order\n" + "".join(f"{name}\n" for name in patches))
        return repo, host

    def test_host_refresh_requires_every_patch_hunk_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "src"
            patch = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail\n"
            repo, host = self.host(root, {"native-host.patch": patch})
            source.mkdir()
            original = "context\nold\ntail\n"
            (source / "sample.cc").write_text(original)
            refresh_host_inputs(repo, source)
            pinned = (host / "host-inputs.json").read_text()
            hashes = json.loads(pinned)["sample.cc"]
            self.assertNotEqual(hashes["before"], hashes["after"])
            self.assertEqual((source / "sample.cc").read_text(), original)
            installed = root / "host.json"
            installed.write_text(json.dumps({"patch": patch, "inputs": json.loads(pinned)}))
            (source / "sample.cc").write_text("context\nnew\ntail\n")
            refresh_host_inputs(repo, source, installed)
            self.assertEqual((host / "host-inputs.json").read_text(), pinned)
            self.assertEqual((source / "sample.cc").read_text(), "context\nnew\ntail\n")
            (source / "sample.cc").write_text("changed context\nold\ntail\n")
            with self.assertRaises(subprocess.CalledProcessError):
                refresh_host_inputs(repo, source)
            self.assertEqual((host / "host-inputs.json").read_text(), pinned)

    def test_a_file_two_patches_change_takes_them_in_order_and_restores_in_reverse(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "src"
            first = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n"
            second = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,4 +1,4 @@\n a\n B\n-c\n+C\n d\n"
            repo, host = self.host(root, {"native-host.patch": first, "privacy.patch": second})
            source.mkdir()
            (source / "sample.cc").write_text("a\nb\nc\nd\n")
            refresh_host_inputs(repo, source)
            hashes = json.loads((host / "host-inputs.json").read_text())["sample.cc"]
            combined = host_patch(repo)
            subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-s"], input=combined, text=True, cwd=source, check=True)
            self.assertEqual((source / "sample.cc").read_text(), "a\nB\nC\nd\n")
            self.assertEqual(hashlib.sha256((source / "sample.cc").read_bytes()).hexdigest(), hashes["after"])
            restore_host_base(source, {"patch": combined, "inputs": {"sample.cc": hashes}}, {})
            self.assertEqual((source / "sample.cc").read_text(), "a\nb\nc\nd\n")
            (host / "Patches/privacy.patch").write_text(second + second)
            with self.assertRaises(ValueError):
                host_patch(repo)


class PromotionTests(unittest.TestCase):
    def test_automatic_publication_requires_opt_in_and_development_on_main(self):
        policy = {"automaticChannel": "development", "integrationBranch": "main", "automaticMajorUpdates": False}
        arguments = dict(enabled="true", default_branch="main", major_update=False)
        self.assertTrue(publication.automatic_release_allowed(policy, **arguments))
        for name, value in (("enabled", "false"), ("enabled", None),
                            ("default_branch", "chromium-control-plane"), ("major_update", True)):
            with self.subTest(gate=name):
                self.assertFalse(publication.automatic_release_allowed(policy, **(arguments | {name: value})))
        for channel in ("stable", "experimental", "nightly"):
            with self.subTest(channel=channel):
                self.assertFalse(publication.automatic_release_allowed(policy | {"automaticChannel": channel}, **arguments))

    def test_engine_must_be_complete_and_match_the_full_key(self):
        key = "a" * 64
        asset = asset_name(key)
        release = {"draft": False, "body": f"Engine key `{key}`", "assets": [
            {"name": name, "size": 100, "state": "uploaded"} for name in (asset, f"{asset}.sha256")]}
        self.assertTrue(release_ready(release, key))
        self.assertFalse(release_ready(None, key))
        self.assertFalse(release_ready(release | {"draft": True}, key))
        for incomplete in (release | {"assets": release["assets"][:1]},
                           release | {"body": "a" * 16 + "b" * 48},
                           release | {"assets": [item | {"state": "new"} for item in release["assets"]]},
                           release | {"assets": [item | {"size": 0} for item in release["assets"]]}):
            with self.subTest(release=incomplete), self.assertRaises(ValueError):
                release_ready(incomplete, key)


class ReleaseNoteTests(unittest.TestCase):
    def test_update_note_is_appended_last_without_rewriting_existing_entries(self):
        catalog = ('{\n  "schemaVersion": 2,\n  "entries": {\n    "earlier": {\n      "category": "fixed",\n'
                   '      "message": "Downloads follow the site you\u2019re on. Settings \\u203a About."\n    }\n  }\n}\n')
        note = {"category": "fixed", "message": "Chromium is updated to 156.0.8078.80 with upstream fixes."}
        appended = publication.append_release_note(catalog, "chromium-upstream-154", note)
        self.assertTrue(appended.startswith(catalog[:-len("\n    }\n  }\n}\n")] + "\n    },\n"))
        self.assertEqual(list(json.loads(appended)["entries"].items())[-1], ("chromium-upstream-154", note))
        with self.assertRaises(ValueError):
            publication.append_release_note(appended, "chromium-upstream-154", note)


if __name__ == "__main__":
    unittest.main()
