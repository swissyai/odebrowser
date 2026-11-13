from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ElementTree

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import appcast  # noqa: E402

# A signed feed as generate_appcast writes it: a phased security update with
# deltas, an older release with full notes, an item on the development
# channel and one without a marketing version or signature.
FEED = """<?xml version="1.0" standalone="yes"?><!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires re-signing this file with generate_appcast or sign_update! The signed signature will be embedded at the end of this file.
--><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:ode="https://odebrowser.com/xml-namespaces/ode" version="2.0">
    <channel>
        <title>Ode</title>
        <item>
            <title>0.9.4</title>
            <pubDate>Thu, 29 Oct 2026 09:12:00 -0400</pubDate>
            <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
            <sparkle:version>202610290912</sparkle:version>
            <sparkle:shortVersionString>0.9.4</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.1</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <sparkle:releaseNotesLink>https://odebrowser.com/updates/Ode-0.9.4-202610290912.html</sparkle:releaseNotesLink>
            <enclosure url="https://odebrowser.com/updates/Ode-0.9.4-202610290912.dmg" length="10" type="application/octet-stream" sparkle:edSignature="bmV3ZXN0"></enclosure>
            <sparkle:deltas>
                <enclosure url="https://odebrowser.com/updates/Ode202610290912-202610220900.delta" sparkle:deltaFrom="202610220900" length="3" type="application/octet-stream" sparkle:edSignature="ZGVsdGEx"></enclosure>
                <enclosure url="https://odebrowser.com/updates/Ode202610290912-202610150800.delta" sparkle:deltaFrom="202610150800" length="4" type="application/octet-stream" sparkle:edSignature="ZGVsdGEy"></enclosure>
            </sparkle:deltas>
            <ode:securityOnly>true</ode:securityOnly>
        </item>
        <item>
            <title>0.9.3</title>
            <pubDate>Thu, 22 Oct 2026 09:00:00 -0400</pubDate>
            <sparkle:version>202610220900</sparkle:version>
            <sparkle:shortVersionString>0.9.3</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>https://odebrowser.com/updates/Ode%20release%20notes.html</sparkle:fullReleaseNotesLink>
            <enclosure url="https://odebrowser.com/updates/Ode-0.9.3-202610220900.dmg" length="9" type="application/octet-stream" sparkle:edSignature="b2xkZXI="></enclosure>
        </item>
        <item>
            <title>0.9.5</title>
            <sparkle:channel>development</sparkle:channel>
            <sparkle:version>202610300700</sparkle:version>
            <sparkle:shortVersionString>0.9.5</sparkle:shortVersionString>
            <enclosure url="https://github.com/example/repository/releases/download/development/Ode-0.9.5-development-2026-10-30-3e67cd3-arm64.dmg" length="8" type="application/octet-stream" sparkle:edSignature="ZGV2"></enclosure>
        </item>
        <item>
            <title>Build 202610150800</title>
            <sparkle:version>202610150800</sparkle:version>
            <enclosure url="https://odebrowser.com/updates/Ode-202610150800.dmg" length="7" type="application/octet-stream"></enclosure>
        </item>
    </channel>
</rss><!-- sparkle-signatures:
edSignature: c2lnbmVk
length: 3021
-->
"""


class AppcastTests(unittest.TestCase):
    def test_each_item_reads_as_the_feed_lists_it(self):
        newest, older, development, bare = appcast.items(FEED)
        self.assertEqual(newest, appcast.Item(
            version="202610290912",
            short_version="0.9.4",
            minimum_system_version="26.1",
            channel="",
            downloads=("https://odebrowser.com/updates/Ode-0.9.4-202610290912.dmg",),
            signature="bmV3ZXN0",
            deltas=("https://odebrowser.com/updates/Ode202610290912-202610220900.delta",
                    "https://odebrowser.com/updates/Ode202610290912-202610150800.delta"),
            release_notes=("https://odebrowser.com/updates/Ode-0.9.4-202610290912.html",),
        ))
        self.assertEqual(newest.build, 202610290912)
        self.assertEqual(newest.url, newest.downloads[0])
        self.assertEqual((older.short_version, older.minimum_system_version, older.signature),
                         ("0.9.3", "26.0", "b2xkZXI="))
        self.assertEqual(older.release_notes, ("https://odebrowser.com/updates/Ode%20release%20notes.html",))
        self.assertEqual(older.deltas, ())
        self.assertEqual(development.channel, "development")
        self.assertEqual(development.url, "https://github.com/example/repository/releases/download/development/"
                         "Ode-0.9.5-development-2026-10-30-3e67cd3-arm64.dmg")
        self.assertEqual((bare.version, bare.short_version, bare.minimum_system_version, bare.signature),
                         ("202610150800", "", "", None))

    def test_a_version_that_is_not_only_digits_has_no_build_number(self):
        feed = FEED.replace("<sparkle:version>202610220900</sparkle:version>",
                            "<sparkle:version> 0.9.3b </sparkle:version>")
        feed = feed.replace("<sparkle:version>202610150800</sparkle:version>", "")
        _, older, _, bare = appcast.items(feed)
        self.assertEqual((older.version, older.build), ("0.9.3b", None))
        self.assertEqual((bare.version, bare.build), ("", None))

    def test_an_item_without_a_download_has_no_url_or_signature(self):
        feed = FEED.replace('<enclosure url="https://odebrowser.com/updates/Ode-202610150800.dmg"', "<enclosure")
        bare = appcast.items(feed)[-1]
        self.assertEqual((bare.downloads, bare.url, bare.signature), ((), None, None))

    def test_text_that_is_not_a_feed_is_refused(self):
        with self.assertRaises(ElementTree.ParseError):
            appcast.items(FEED.replace("</channel>", ""))


if __name__ == "__main__":
    unittest.main()
