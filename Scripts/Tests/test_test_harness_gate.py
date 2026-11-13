"""Keep the test harness out of every build people install.

The harness takes commands on a socket and moves windows off the screens, so
it is compiled only into Debug and review builds, and only review targets
define the review flag."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "OdeMac" / "App" / "Harness"
GATE = "#if DEBUG || ODE_REVIEW_BUILD"
REVIEW_TARGETS = {"CrestChromiumUI", "OdeNativeCore", "OdeMobileNativeCore"}


class TestHarnessGateTests(unittest.TestCase):
    def test_every_harness_file_is_compiled_only_into_debug_and_review_builds(self):
        files = sorted(HARNESS.glob("*.swift"))
        self.assertTrue(files)
        for path in files:
            text = path.read_text()
            self.assertIn(GATE, text, path.name)
            if path.name == "BrowserMacHarness.swift":
                # The phase names and a release stub that does nothing stay
                # outside the gate, so the shell's hooks compile everywhere.
                release = text.split("#else", 1)[1]
                for word in ("socket", "Server", "exchange", "setActivationPolicy"):
                    self.assertNotIn(word, release, f"the release stub must not {word}")
            else:
                body = text.strip()
                self.assertTrue(body.startswith(GATE) and body.endswith("#endif"), path.name)

    def test_only_review_targets_define_the_review_flag(self):
        current = None
        defining = set()
        for line in (ROOT / "project.yml").read_text().splitlines():
            match = re.match(r"^  ([A-Za-z]+):\s*$", line)
            if match:
                current = match.group(1)
            if "ODE_REVIEW_BUILD" in line and current:
                defining.add(current)
        self.assertEqual(defining, REVIEW_TARGETS)


if __name__ == "__main__":
    unittest.main()
