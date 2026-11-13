import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "control-plane" / "mark-security-update.py"
spec = importlib.util.spec_from_file_location("mark_security_update", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

FEED = """<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Ode</title>
        <item>
            <title>0.9.4</title>
            <sparkle:version>202610290912</sparkle:version>
        </item>
        <item>
            <title>0.9.3</title>
            <sparkle:version>202610220900</sparkle:version>
        </item>
    </channel>
</rss>
<!-- sparkle-signatures:
edSignature: abc
length: 10
-->
"""


class MarkSecurityUpdateTests(unittest.TestCase):
    def test_marks_only_the_named_build_and_drops_the_old_signature(self):
        marked = module.mark(FEED, "202610290912")
        self.assertIn('xmlns:ode="https://odebrowser.com/xml-namespaces/ode"', marked)
        self.assertEqual(marked.count(module.ELEMENT), 1)
        newest = marked.index("202610290912")
        self.assertLess(newest, marked.index(module.ELEMENT))
        self.assertLess(marked.index(module.ELEMENT), marked.index("202610220900"))
        self.assertNotIn("sparkle-signatures", marked)

    def test_marking_twice_changes_nothing_more(self):
        once = module.mark(FEED, "202610290912")
        self.assertEqual(module.mark(once, "202610290912"), once)

    def test_an_unknown_build_is_refused(self):
        with self.assertRaises(SystemExit):
            module.mark(FEED, "1")


if __name__ == "__main__":
    unittest.main()
