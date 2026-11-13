"""The helpers release and maintenance scripts share answer as the copies they replace did."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import _common  # noqa: E402
import bundle_info  # noqa: E402


class ScriptCommonTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)

    def tearDown(self):
        self.folder.cleanup()

    def test_the_repository_root_holds_the_scripts(self):
        self.assertEqual(_common.REPO / "Scripts" / "_common.py", Path(_common.__file__).resolve())

    def test_a_command_runs_with_each_part_as_text_and_fails_loudly(self):
        printed = _common.run(sys.executable, "-c", "import sys; print(sys.argv[1])", 42, stdout=subprocess.PIPE)
        self.assertEqual(printed.stdout, "42\n")
        with self.assertRaises(subprocess.CalledProcessError):
            _common.run(sys.executable, "-c", "raise SystemExit(3)")

    def test_a_file_digest_reads_every_block(self):
        path = self.root / "archive"
        data = bytes(range(256)) * 9000
        path.write_bytes(data)
        self.assertEqual(_common.sha256(path), hashlib.sha256(data).hexdigest())
        self.assertEqual(_common.sha256(str(path)), hashlib.sha256(data).hexdigest())
        (self.root / "empty").write_bytes(b"")
        self.assertEqual(_common.sha256(self.root / "empty"), hashlib.sha256(b"").hexdigest())

    def test_a_json_file_reads_as_its_value(self):
        path = self.root / "lock.json"
        path.write_text(json.dumps({"key": "a" * 64, "assets": [1, 2]}))
        self.assertEqual(_common.read_json(path), {"key": "a" * 64, "assets": [1, 2]})

    def test_a_property_list_reads_in_either_format(self):
        values = {"CFBundleShortVersionString": "1.2.3", "com.apple.developer.icloud-services": ["CloudKit"]}
        for name, form in (("xml.plist", plistlib.FMT_XML), ("binary.plist", plistlib.FMT_BINARY)):
            path = self.root / name
            path.write_bytes(plistlib.dumps(values, fmt=form))
            self.assertEqual(bundle_info.read_plist(path), values)

    def test_an_app_bundle_reads_its_info_plist(self):
        contents = self.root / "Example.app" / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.example.app"}))
        self.assertEqual(bundle_info.info(self.root / "Example.app")["CFBundleIdentifier"], "com.example.app")


if __name__ == "__main__":
    unittest.main()
