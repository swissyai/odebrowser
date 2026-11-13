"""The app declares the session versions its core reads, so going back to an
earlier version can tell when that version cannot open the person's data."""

import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def constant(path: str, name: str) -> int:
    match = re.search(rf"const int {name} = (\d+);", (ROOT / path).read_text())
    if not match:
        raise AssertionError(f"{path} declares no {name}")
    return int(match.group(1))


class SessionFormatContractTests(unittest.TestCase):
    def test_the_info_plist_names_the_session_versions_the_core_reads(self):
        with (ROOT / "OdeMac/Configuration/Ode-Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(
            info["OdeSessionStorageVersion"],
            constant("OdeCore/src/OdeCore/Application/Storage/SessionStorage.cs", "StorageVersion"))
        self.assertEqual(
            info["OdeSessionJournalVersion"],
            constant("OdeCore/src/OdeCore/Application/Storage/StoredSession.cs", "JournalSchemaVersion"))


if __name__ == "__main__":
    unittest.main()
