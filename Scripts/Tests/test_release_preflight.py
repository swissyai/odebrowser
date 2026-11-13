"""Release evidence must not silently become a runtime or security claim."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS / "control-plane"))
spec = importlib.util.spec_from_file_location("release_preflight", SCRIPTS / "release-preflight.py")
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        self.key = "a" * 64
        self.digest = "b" * 64
        self.asset = preflight.chromium_engine.asset_name(self.key)
        self.lock = {"schemaVersion": 1, "status": "source-preparation", "chromium": {"version": "155.0.8059.84"},
                     "ungoogledMac": {"commit": "c" * 40},
                     "performanceInputs": {"macSDKVersion": "26.5", "pgoSHA256": "d" * 64}}
        self.release = {"tag_name": preflight.chromium_engine.release_tag(self.key), "draft": False,
                        "published_at": "2026-10-22T21:52:38Z", "body": self.key,
                        "assets": [{"name": self.asset + suffix, "state": "uploaded", "size": 100,
                                    "digest": "sha256:" + self.digest} for suffix in ("", ".sha256", ".json")]}
        self.provenance = {"schemaVersion": 1, "engineKey": self.key, "chromium": "155.0.8059.84",
                           "upstreamCommit": "c" * 40, "configuration": "performance", "sdkVersion": "26.5",
                           "pgoSHA256": "d" * 64, "archiveSHA256": self.digest, "sourceCommit": "e" * 40}
        self.checksum = f"{self.digest}  {self.asset}\n"

    def evaluate(self, archive=None):
        return preflight.inspect_publication(self.release, self.provenance, self.checksum,
                                             self.lock, self.key, archive)

    def test_metadata_match_does_not_attest_downloaded_bytes_or_runtime(self):
        result = self.evaluate()
        self.assertEqual(result["status"], "metadata_matched")
        self.assertEqual(result["archive_integrity"], "not_checked")
        self.assertEqual(result["runtime_capability"], "not_tested")
        self.assertEqual(result["security_freshness"], "not_assessed")

    def test_mismatched_full_key_recipe_digest_and_checksum_fail_closed(self):
        for field in ("engineKey", "chromium", "upstreamCommit", "configuration", "sdkVersion", "pgoSHA256",
                      "archiveSHA256", "sourceCommit", "schemaVersion"):
            with self.subTest(field=field):
                original = copy.deepcopy(self.provenance)
                self.provenance[field] = "incorrect"
                self.assertEqual(self.evaluate()["status"], "blocked")
                self.provenance = original
        for checksum in (f"{'f' * 64}  {self.asset}\n", f"{self.digest}  ../other.zip\n",
                         self.checksum + self.checksum, "malformed"):
            with self.subTest(checksum=checksum):
                self.checksum = checksum
                self.assertEqual(self.evaluate()["status"], "blocked")

    def test_schema2_binds_source_archive_without_changing_provenance_schema(self):
        self.lock["schemaVersion"] = 2
        del self.lock["ungoogledMac"]
        self.lock["chromium"]["sourceArchiveSha256"] = "f" * 64
        del self.provenance["upstreamCommit"]
        self.provenance["sourceArchiveSHA256"] = "f" * 64
        result = self.evaluate()
        self.assertEqual(result["status"], "metadata_matched")
        self.assertEqual(result["archive_integrity"], "not_checked")
        self.assertEqual(result["runtime_capability"], "not_tested")
        self.assertEqual(result["security_freshness"], "not_assessed")
        for value in (None, "0" * 64, True):
            with self.subTest(source_archive=value):
                if value is None:
                    self.provenance.pop("sourceArchiveSHA256", None)
                else:
                    self.provenance["sourceArchiveSHA256"] = value
                # A valid legacy field cannot replace the schema-2 source binding.
                self.provenance["upstreamCommit"] = "c" * 40
                result = self.evaluate()
                self.assertEqual(result["status"], "blocked")
                self.assertIn("Provenance mismatch: sourceArchiveSHA256", result["problems"])
        self.provenance["sourceArchiveSHA256"] = "f" * 64
        self.provenance["schemaVersion"] = 2
        self.assertIn("Provenance mismatch: schemaVersion", self.evaluate()["problems"])

    def test_schema1_still_requires_upstream_commit_even_with_source_archive(self):
        self.lock["chromium"]["sourceArchiveSha256"] = "f" * 64
        self.provenance["sourceArchiveSHA256"] = "f" * 64
        del self.provenance["upstreamCommit"]
        result = self.evaluate()
        self.assertEqual(result["status"], "blocked")
        self.assertIn("Provenance mismatch: upstreamCommit", result["problems"])

    def test_invalid_lock_cannot_match_equally_invalid_provenance(self):
        for schema, section, field, provenance_field in (
                (1, "ungoogledMac", "commit", "upstreamCommit"),
                (2, "chromium", "sourceArchiveSha256", "sourceArchiveSHA256"),
                (2, "performanceInputs", "pgoSHA256", "pgoSHA256")):
            for value in (None, True, "", "not-a-digest"):
                with self.subTest(schema=schema, field=field, value=value):
                    lock, provenance = copy.deepcopy(self.lock), copy.deepcopy(self.provenance)
                    lock["schemaVersion"] = schema
                    lock["chromium"]["sourceArchiveSha256"] = "f" * 64
                    lock[section][field] = value
                    provenance[provenance_field] = value
                    result = preflight.inspect_publication(self.release, provenance, self.checksum, lock, self.key)
                    self.assertEqual(result["status"], "blocked")
                    self.assertIn("Invalid source lock field: " + section + "." + field, result["problems"])

    def test_cli_reports_invalid_missing_and_unknown_locks_as_blocked_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            for name in preflight.chromium_engine.INPUTS:
                source, destination = SCRIPTS.parent / name, repo / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                if name != "CrestEngines/Chromium/source.lock.json":
                    destination.symlink_to(source, target_is_directory=source.is_dir())
            entitlement = repo / "OdeMac/Configuration/Ode-Direct.entitlements"
            entitlement.parent.mkdir(parents=True)
            entitlement.symlink_to(SCRIPTS.parent / entitlement.relative_to(repo))
            lock_path = repo / "CrestEngines/Chromium/source.lock.json"
            cases = [(None, "Invalid source lock: expected object"),
                     ([], "Invalid source lock: expected object"),
                     ({}, "Invalid source lock field: schemaVersion"),
                     (dict(self.lock, schemaVersion=True), "Invalid source lock field: schemaVersion"),
                     (dict(self.lock, schemaVersion="2"), "Invalid source lock field: schemaVersion"),
                     (dict(self.lock, schemaVersion=3), "Unsupported source lock schemaVersion: 3"),
                     (dict(self.lock, chromium=[]), "Invalid source lock field: chromium.version"),
                     (dict(self.lock, performanceInputs=None), "Invalid source lock field: performanceInputs.macSDKVersion"),
                     (dict(self.lock, ungoogledMac={}), "Invalid source lock field: ungoogledMac.commit"),
                     (dict(self.lock, schemaVersion=2), "Invalid source lock field: chromium.sourceArchiveSha256")]
            inputs = [(json.dumps(lock), problem) for lock, problem in cases]
            inputs += [("{", "Invalid source lock JSON:"), (None, "source.lock.json")]
            for content, problem in inputs:
                with self.subTest(content=content):
                    if content is None:
                        lock_path.unlink()
                    else:
                        lock_path.write_text(content)
                    process = subprocess.run(
                        [sys.executable, str(SCRIPTS / "release-preflight.py"), "--repo", str(repo)],
                        capture_output=True, text=True, timeout=15)
                    self.assertEqual(process.returncode, 1)
                    self.assertEqual(process.stderr, "", process.stderr)
                    report = json.loads(process.stdout)
                    self.assertIs(report["release_ready"], False)
                    self.assertEqual(report["publication"]["status"], "blocked")
                    self.assertTrue(any(problem in item for item in report["publication"]["problems"]), report)

    def test_missing_draft_wrong_tag_duplicate_or_incomplete_assets_are_not_published(self):
        for change in ({"draft": True}, {"tag_name": "other"}, {"published_at": None}, {"assets": []},
                       {"assets": self.release["assets"] * 2}, {"body": "wrong full key"}):
            original = copy.deepcopy(self.release)
            self.release.update(change)
            self.assertEqual(self.evaluate()["status"], "blocked")
            self.release = original
        self.release = None
        self.assertEqual(self.evaluate()["status"], "blocked")

    def test_problems_follow_the_check_order_and_stop_at_unreadable_metadata(self):
        assets = self.release["assets"]
        incomplete = copy.deepcopy(assets)
        incomplete[1]["state"] = "starting"
        incomplete[2]["size"] = 0
        incomplete.append(dict(incomplete[0]))
        misdigested = copy.deepcopy(assets)
        misdigested[0]["digest"] = "sha256:" + "9" * 64
        unpublished = "Release is not published"
        cases = (
            ({"release": None}, ["No published release metadata available"], False),
            ({"provenance": []}, ["Invalid provenance metadata"], False),
            ({"release": dict(self.release, draft=True, body=7)}, [unpublished, "Invalid release body metadata"], False),
            ({"release": dict(self.release, draft=None, tag_name="other", assets={})},
             [unpublished, "Release tag or full engine key differs", "Invalid release asset metadata"], False),
            ({"release": dict(self.release, published_at="", assets=assets + [3])},
             [unpublished, "Invalid release asset metadata"], False),
            ({"release": dict(self.release, assets=incomplete)},
             ["Missing, duplicate or incomplete asset: " + self.asset + suffix for suffix in ("", ".sha256", ".json")],
             True),
            ({"release": dict(self.release, assets=misdigested),
              "provenance": dict(self.provenance, sourceCommit="E" * 40, chromium=155)},
             ["Provenance mismatch: chromium", "Missing or invalid provenance source commit",
              "Provider archive digest differs from checksum"], True),
            ({"checksum": "malformed"},
             ["Checksum sidecar differs from provenance or names another archive",
              "Provider archive digest differs from checksum"], True),
        )
        for change, problems, reports_digest in cases:
            with self.subTest(change=sorted(change)):
                arguments = {"release": self.release, "provenance": self.provenance, "checksum": self.checksum}
                arguments.update(change)
                result = preflight.inspect_publication(arguments["release"], arguments["provenance"],
                                                       arguments["checksum"], self.lock, self.key)
                self.assertEqual(result["problems"], problems)
                self.assertEqual(result["status"], "blocked")
                self.assertEqual(result["archive_integrity"], "not_checked")
                self.assertEqual("archive_sha256" in result, reports_digest)
        result = preflight.inspect_publication(self.release, dict(self.provenance, sourceCommit="E" * 40),
                                               "malformed", self.lock, self.key)
        self.assertIsNone(result["archive_sha256"])
        self.assertEqual(result["source_commit"], "E" * 40)
        self.assertEqual(result["published_at"], self.release["published_at"])

    def test_local_archive_bytes_must_match_not_just_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / self.asset
            archive.write_bytes(b"published engine fixture")
            self.digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            self.release["assets"][0]["digest"] = "sha256:" + self.digest
            self.provenance["archiveSHA256"] = self.digest
            self.checksum = f"{self.digest}  {self.asset}\n"
            result = self.evaluate(archive)
            self.assertEqual(result["status"], "archive_matched")
            self.assertEqual(result["archive_integrity"], "matched")
            self.assertEqual(result["runtime_capability"], "not_tested")
            archive.write_bytes(b"replaced engine")
            self.assertEqual(self.evaluate(archive)["status"], "blocked")

    def test_sidecar_digest_rejects_replaced_recorded_evidence(self):
        name = self.asset + ".json"
        data = b'{"schemaVersion": 1}'
        self.release["assets"][2]["digest"] = "sha256:" + hashlib.sha256(data).hexdigest()
        preflight.verify_sidecar(self.release, name, data)
        with self.assertRaisesRegex(ValueError, "digest differs"):
            preflight.verify_sidecar(self.release, name, data + b" ")

    def test_direct_entitlement_declaration_is_not_a_managed_grant(self):
        result = preflight.inspect_entitlements(SCRIPTS.parent / "OdeMac/Configuration/Ode-Direct.entitlements")
        self.assertFalse(result["cloudkit_declared"])
        self.assertFalse(result["browser_passkeys_declared"])
        self.assertEqual(result["signed_package_grants"], "not_checked")
        self.assertEqual(result["ode_passwords"], "separate_origin_bound_keychain_feature")

    def test_cli_rejects_malformed_publication_fields_with_a_blocked_report(self):
        repo = SCRIPTS.parent
        key = preflight.chromium_engine.engine_key(repo)
        lock = json.loads((repo / "CrestEngines/Chromium/source.lock.json").read_text())
        asset = preflight.chromium_engine.asset_name(key)
        provenance = {"schemaVersion": 1, "engineKey": key, "chromium": lock["chromium"]["version"],
                      "configuration": "performance",
                      "sdkVersion": lock["performanceInputs"]["macSDKVersion"],
                      "pgoSHA256": lock["performanceInputs"]["pgoSHA256"],
                      "archiveSHA256": self.digest, "sourceCommit": "e" * 40}
        if lock["schemaVersion"] == 1:
            provenance["upstreamCommit"] = lock["ungoogledMac"]["commit"]
        else:
            self.assertEqual(lock["schemaVersion"], 2)
            provenance["sourceArchiveSHA256"] = lock["chromium"]["sourceArchiveSha256"]
        release = {"tag_name": preflight.chromium_engine.release_tag(key), "draft": False,
                   "published_at": "2026-10-22T21:52:38Z", "body": key,
                   "assets": [{"name": asset + suffix, "state": "uploaded", "size": 100,
                               "digest": "sha256:" + self.digest} for suffix in ("", ".sha256", ".json")]}
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            release_path = directory / "release.json"
            provenance_path = directory / "provenance.json"
            checksum_path = directory / "checksum.sha256"
            checksum_path.write_text(f"{self.digest}  {asset}\n")

            def inspect(record, recipe):
                provenance_path.write_text(json.dumps(recipe))
                # Keep provider digests consistent so only the selected field is faulty.
                for index, sidecar in ((1, checksum_path), (2, provenance_path)):
                    record["assets"][index]["digest"] = "sha256:" + hashlib.sha256(sidecar.read_bytes()).hexdigest()
                    record["assets"][index]["size"] = sidecar.stat().st_size
                release_path.write_text(json.dumps(record))
                result = subprocess.run(
                    [sys.executable, str(SCRIPTS / "release-preflight.py"), "--repo", str(repo),
                     "--release-metadata", str(release_path), "--provenance", str(provenance_path),
                     "--checksum", str(checksum_path)], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.stderr, "", result.stderr)
                report = json.loads(result.stdout)
                self.assertIs(report["release_ready"], False)
                return result.returncode, report

            code, report = inspect(copy.deepcopy(release), copy.deepcopy(provenance))
            self.assertEqual(code, 0)
            self.assertEqual(report["publication"]["status"], "metadata_matched")
            self.assertEqual(report["publication"]["archive_integrity"], "not_checked")
            self.assertEqual(report["runtime"]["status"], "not_tested")
            self.assertEqual(report["security_freshness"]["status"], "not_assessed")

            cases = [("body", value, "Invalid release body metadata")
                     for value in ([key], {key: True}, 42)]
            cases += [("published_at", True, "Release is not published"),
                      ("schemaVersion", True, "Provenance mismatch: schemaVersion"),
                      ("sourceCommit", int("1" * 40), "Missing or invalid provenance source commit")]
            cases += [("size", value, "Missing, duplicate or incomplete asset: " + asset)
                      for value in (True, "100", None, 1.25)]
            for field, value, problem in cases:
                with self.subTest(field=field, value=value):
                    record, recipe = copy.deepcopy(release), copy.deepcopy(provenance)
                    if field == "size":
                        record["assets"][0][field] = value
                    elif field in ("schemaVersion", "sourceCommit"):
                        recipe[field] = value
                    else:
                        record[field] = value
                    code, report = inspect(record, recipe)
                    self.assertEqual(code, 1)
                    self.assertEqual(report["publication"]["status"], "blocked")
                    self.assertIn(problem, report["publication"]["problems"])

    def test_online_cli_reports_malformed_assets_before_fetching_sidecars(self):
        repo = SCRIPTS.parent
        key = preflight.chromium_engine.engine_key(repo)
        asset = preflight.chromium_engine.asset_name(key)
        release = copy.deepcopy(self.release)
        for item, suffix in zip(release["assets"], ("", ".sha256", ".json")):
            item["name"] = asset + suffix
            item["id"] = 1
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            release_path = directory / "release.json"
            calls_path = directory / "calls.txt"
            gh = directory / "gh"
            gh.write_text(
                f"#!{sys.executable}\nfrom pathlib import Path\nimport sys\n"
                f"with Path({str(calls_path)!r}).open('a') as calls: calls.write(sys.argv[-1] + '\\n')\n"
                f"print(Path({str(release_path)!r}).read_text())\n")
            gh.chmod(0o755)
            env = dict(os.environ, PATH=str(directory))
            for field, value in (("assets", None), ("assets", [42]), ("size", "100"), ("size", None)):
                with self.subTest(field=field, value=value):
                    record = copy.deepcopy(release)
                    if field == "assets":
                        record[field] = value
                        problem = "Invalid release asset metadata"
                    else:
                        record["assets"][2][field] = value
                        problem = "Missing, duplicate or oversized metadata sidecar: " + asset + ".json"
                    release_path.write_text(json.dumps(record))
                    calls_path.write_text("")
                    result = subprocess.run(
                        [sys.executable, str(SCRIPTS / "release-preflight.py"), "--repo", str(repo), "--online"],
                        capture_output=True, text=True, timeout=15, env=env)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(result.stderr, "", result.stderr)
                    report = json.loads(result.stdout)
                    self.assertIs(report["release_ready"], False)
                    self.assertEqual(report["publication"]["status"], "blocked")
                    self.assertIn(problem, report["publication"]["problems"])
                    self.assertEqual(len(calls_path.read_text().splitlines()), 1, "Invalid sidecars must not be fetched")
