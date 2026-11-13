import importlib.util
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "control-plane" / "update-feed.py"
spec = importlib.util.spec_from_file_location("update_feed", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FEED = """<?xml version="1.0" standalone="yes"?><!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle.
--><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Ode</title>
        <item>
            <title>0.9.4</title>
            <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
            <sparkle:version>202610290912</sparkle:version>
            <sparkle:shortVersionString>0.9.4</sparkle:shortVersionString>
            <enclosure url="https://odebrowser.com/updates/Ode-0.9.4-202610290912.dmg" length="10" type="application/octet-stream" sparkle:edSignature="new"></enclosure>
            <sparkle:deltas>
                <enclosure url="https://odebrowser.com/updates/Ode202610290912-202610220900.delta" sparkle:deltaFrom="202610220900" length="3" type="application/octet-stream" sparkle:edSignature="delta"></enclosure>
            </sparkle:deltas>
        </item>
        <item>
            <title>0.9.3</title>
            <sparkle:version>202610220900</sparkle:version>
            <sparkle:shortVersionString>0.9.3</sparkle:shortVersionString>
            <enclosure url="https://odebrowser.com/updates/Ode-0.9.3-202610220900.dmg" length="9" type="application/octet-stream" sparkle:edSignature="old"></enclosure>
        </item>
    </channel>
</rss><!-- sparkle-signatures:
edSignature: abc
length: 10
-->
"""

NEWEST = "Ode-0.9.4-202610290912.dmg"
OLDER = "Ode-0.9.3-202610220900.dmg"
DELTA = "Ode202610290912-202610220900.delta"


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.root))
        self.previous = self.root / "previous"
        self.previous.mkdir()
        (self.previous / "appcast.xml").write_text(FEED)
        for name in (NEWEST, OLDER, DELTA, "Ode-0.9.4-202610290912.html", "unrelated.dmg"):
            (self.previous / name).write_text(name)

    def test_a_release_carries_the_previous_feed_and_only_the_files_it_names(self):
        updates = self.root / "release" / "updates"
        carried = module.carry(self.previous, updates)
        self.assertEqual(sorted(carried), sorted(["appcast.xml", NEWEST, OLDER, DELTA, "Ode-0.9.4-202610290912.html"]))
        self.assertFalse((updates / "unrelated.dmg").exists())
        self.assertEqual((updates / OLDER).read_text(), OLDER)

    def test_a_feed_item_without_its_disk_image_stops_the_carry(self):
        (self.previous / OLDER).unlink()
        with self.assertRaises(SystemExit):
            module.carry(self.previous, self.root / "release" / "updates")

    def test_files_the_feed_no_longer_names_move_aside_and_nothing_is_deleted(self):
        moved = module.prune(self.previous)
        self.assertEqual(moved, ["unrelated.dmg"])
        self.assertTrue((self.previous / "old_updates" / "unrelated.dmg").is_file())
        self.assertTrue((self.previous / NEWEST).is_file())

    def test_a_local_copy_points_downloads_at_this_mac_and_leaves_the_release_unchanged(self):
        served = self.root / "served"
        module.localize(self.previous, served, "http://127.0.0.1:8787/")
        feed = (served / "appcast.xml").read_text()
        self.assertIn('url="http://127.0.0.1:8787/' + NEWEST + '"', feed)
        self.assertIn('url="http://127.0.0.1:8787/' + DELTA + '"', feed)
        self.assertNotIn("odebrowser.com", feed)
        self.assertNotIn("phasedRolloutInterval", feed)
        self.assertNotIn("sparkle-signatures", feed, "The copy must be signed again")
        self.assertTrue((served / NEWEST).is_symlink())
        self.assertEqual((self.previous / "appcast.xml").read_text(), FEED)

    def test_a_local_copy_is_only_ever_served_from_this_mac(self):
        for prefix in ("https://odebrowser.com/updates/", "http://192.168.1.4:8787/", "http://127.0.0.1:8787"):
            with self.subTest(prefix=prefix), self.assertRaises(SystemExit):
                module.localize(self.previous, self.root / f"served-{abs(hash(prefix))}", prefix)

    def test_an_item_is_offered_only_when_both_its_build_and_its_version_are_newer(self):
        installed = {"CFBundleShortVersionString": "0.9.3", "CFBundleVersion": "202610220900"}
        lines = module.describe(FEED, installed)
        self.assertIn("  Ode 0.9.4 (202610290912)  the installed Ode takes it", lines)
        self.assertTrue(any(line.startswith("  Ode 0.9.3 (202610220900)  not offered") for line in lines))
        same_version = {"CFBundleShortVersionString": "0.9.4", "CFBundleVersion": "202610010000"}
        self.assertTrue(any("marketing version not newer" in line for line in module.describe(FEED, same_version)))


if __name__ == "__main__":
    unittest.main()
