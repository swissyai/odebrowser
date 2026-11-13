"""Tab organization providers stay behind their opt-in resolver. Settings
contact those providers only while enabled; Apple's local availability can be
read while off. Private Command-T answers have a separate opt-in and local-only
client, not the configured tab organization provider. This architecture guard
limits Apple's model APIs to those two adapters; behavioral opt-in and remote
lookup coverage lives in the core and native private-answer tests."""

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ["OdeShared", "OdeMac", "OdeMobile"]
INTELLIGENCE = ROOT / "OdeShared/Application/Intelligence"
PREFERENCE = INTELLIGENCE / "BrowserIntelligencePreference.swift"
SETTINGS = ROOT / "OdeShared/Features/Settings/BrowserSearchSettingsPane/Components/BrowserIntelligenceSettingsSection.swift"
PROVIDERS = re.compile(r"\b(OnDeviceIntelligenceProvider|LocalModelIntelligenceProvider|ChatGPTIntelligenceProvider)\(")
MODEL_FRAMEWORKS = re.compile(r"\b(SystemLanguageModel|LanguageModelSession)\b")


def swift_files():
    for root in SOURCES:
        for path in sorted((ROOT / root).rglob("*.swift")):
            if "Tests" not in path.parts:
                yield path


class IntelligenceGateTests(unittest.TestCase):
    def test_providers_are_made_only_from_the_preference(self):
        offenders = [
            str(path.relative_to(ROOT))
            for path in swift_files()
            if path != PREFERENCE and PROVIDERS.search(path.read_text(errors="ignore"))
        ]
        self.assertEqual(offenders, [], "a provider is made outside the preference's choices")

    def test_features_reach_tab_organization_providers_only_through_the_resolver(self):
        offenders = []
        for path in swift_files():
            if INTELLIGENCE in path.parents or path == SETTINGS:
                continue
            text = path.read_text(errors="ignore")
            if ".provider(endpoint:" in text or "makeProvider" in text:
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [], "a feature builds a provider instead of asking the resolver")

    def test_apple_models_are_reached_only_by_the_two_on_device_adapters(self):
        allowed = {
            ROOT / "OdeShared/Infrastructure/Intelligence/OnDeviceIntelligenceProvider.swift",
            ROOT / "OdeShared/Infrastructure/Intelligence/BrowserPrivateAnswerClient.swift",
        }
        offenders = [
            str(path.relative_to(ROOT))
            for path in swift_files()
            if path not in allowed and MODEL_FRAMEWORKS.search(path.read_text(errors="ignore"))
        ]
        self.assertEqual(offenders, [], "Apple's model is used outside the two on-device adapters")

    def test_the_tab_organization_resolver_answers_nothing_while_intelligence_is_off(self):
        resolver = (INTELLIGENCE / "BrowserIntelligenceProvider.swift").read_text()
        self.assertRegex(resolver, r"guard BrowserIntelligencePreference\.isEnabled else \{ return nil \}")
        self.assertIn("static let defaultEnabled = false", PREFERENCE.read_text())

    def test_settings_check_a_tab_organization_provider_only_while_intelligence_is_on(self):
        text = SETTINGS.read_text()
        enabled = text.index("if isEnabled {")
        for call in re.finditer(r"await check\(", text):
            # Every check is reached from inside the enabled section or from
            # the sign-in and sign-out actions its controls run.
            line_start = text.rfind("\n", 0, call.start())
            context = text[max(0, line_start - 400):call.start()]
            self.assertTrue(
                call.start() > enabled or "signIn" in context or "signOut" in context,
                "Settings checks a provider outside the enabled section")


if __name__ == "__main__":
    unittest.main()
