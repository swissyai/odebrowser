import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location(
    "verify_bundled_notices", Path(__file__).resolve().parents[1] / "verify-bundled-notices.py")
NOTICES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NOTICES)


class BundledNoticesTests(unittest.TestCase):
    """Distribution must retain exact notices and the expected source version."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "source"
        files = {name: b"Copyright upstream\r\nLicense text\n" for name in (
            "LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "TRADEMARKS.md",
            "ThirdParty/Dependency.txt", "OdeShared/Resources/SFSymbolCatalog-LICENSE.txt",
            "OdeShared/Resources/HeraldicArtworkCredits.txt", "CrestEngines/Chromium/ThirdParty/Mori-LICENSE")}
        files["Config/ThirdPartyDependencies.json"] = json.dumps({
            "runtimeDependencies": [{"notice": "ThirdParty/Dependency.txt"}],
            "bundledData": [], "bundledComponents": []}).encode()
        for name, data in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def app(self, mac):
        app = self.root / ("Mac.app" if mac else "Mobile.app")
        resources = app / "Contents/Resources" if mac else app
        resources.mkdir(parents=True)
        info = app / "Contents/Info.plist" if mac else app / "Info.plist"
        info.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.2.3"}))
        for name, data in NOTICES.canonical_notices(self.repo).items():
            path = resources / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        return app, resources

    def test_mac_and_mobile_resources_survive_archiving(self):
        for mac in (True, False):
            with self.subTest(mac=mac):
                app, _ = self.app(mac)
                result = NOTICES.verify(app, "1.2.3", self.repo)
                archive = app.with_suffix(".zip")
                with zipfile.ZipFile(archive, "w") as output:
                    for path in app.rglob("*"):
                        if path.is_file():
                            output.write(path, path.relative_to(self.root))
                self.assertEqual(NOTICES.verify(archive, "1.2.3", self.repo), result)
                self.assertEqual(result["intended_source_url"], "https://github.com/swissyai/odebrowser/tree/v1.2.3")
                self.assertFalse(result["source_publication_verified"])

    def test_missing_or_rewritten_notice_is_refused(self):
        app, resources = self.app(True)
        notice = resources / "ThirdParty/Dependency.txt"
        notice.write_bytes(b"Copyright upstream\nLicense text\n")
        with self.assertRaisesRegex(ValueError, "differs from canonical bytes"):
            NOTICES.verify(app, "1.2.3", self.repo)
        notice.unlink()
        with self.assertRaisesRegex(ValueError, "Missing bundled notice"):
            NOTICES.verify(app, "1.2.3", self.repo)

    def test_source_version_mismatch_or_invalid_version_is_refused(self):
        app, _ = self.app(False)
        for version in ("1.2.4", "main", "", "1.2.3/path"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                NOTICES.verify(app, version, self.repo)

    def test_empty_canonical_notice_is_not_success(self):
        app, _ = self.app(False)
        (self.repo / "LICENSE").write_bytes(b"\n")
        with self.assertRaisesRegex(ValueError, "Canonical notice is empty"):
            NOTICES.verify(app, "1.2.3", self.repo)
