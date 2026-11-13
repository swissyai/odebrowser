#!/usr/bin/env python3
"""Regression coverage for Ode's direct macOS release signing path."""

from __future__ import annotations

import importlib.util
import pathlib
import plistlib
import re
import unittest

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
EXPORT_OPTIONS = REPOSITORY_ROOT / "Config" / "DeveloperIDExportOptions.plist"
RELEASE_SCRIPT = REPOSITORY_ROOT / "Scripts" / "release-ode.sh"
PACKAGING_SPEC = importlib.util.spec_from_file_location(
    "package_chromium_host", REPOSITORY_ROOT / "Scripts/control-plane/package-chromium-host.py")
PACKAGING = importlib.util.module_from_spec(PACKAGING_SPEC)
PACKAGING_SPEC.loader.exec_module(PACKAGING)


def release_script_variable(name: str) -> str:
    match = re.search(rf'^{name}="([^"]+)"$', RELEASE_SCRIPT.read_text(), re.MULTILINE)
    if match is None:
        raise AssertionError(f"Scripts/release-ode.sh does not set {name}")
    return match.group(1)


class DirectDistributionContractTests(unittest.TestCase):

    def test_updates_require_the_newest_os_needed_by_the_engine_or_native_ui(self) -> None:
        for engine, native_ui, expected in (("13.0", "26.1", "26.1"), ("27.0", "26.1", "27.0"),
                                            ("10.9", "10.15.1", "10.15.1")):
            with self.subTest(engine=engine, native_ui=native_ui):
                self.assertEqual(PACKAGING.minimum_system_version(
                    {"LSMinimumSystemVersion": engine}, {"LSMinimumSystemVersion": native_ui}), expected)
        with self.assertRaises(KeyError):
            PACKAGING.minimum_system_version({"LSMinimumSystemVersion": "13.0"}, {})
        with self.assertRaises(ValueError):
            PACKAGING.minimum_system_version({"LSMinimumSystemVersion": "13.0"},
                                             {"LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)"})

    def test_export_uses_the_named_developer_id_profile(self) -> None:
        with EXPORT_OPTIONS.open("rb") as stream:
            options = plistlib.load(stream)

        self.assertEqual(options["method"], "developer-id")
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["signingCertificate"], "Developer ID Application")
        self.assertEqual(options["teamID"], "WUMLCL8SAZ")
        self.assertEqual(
            options["provisioningProfiles"],
            {"com.odebrowser.ode": "Ode Developer ID"},
        )

    def test_release_script_signs_the_released_identity_for_direct_distribution(self) -> None:
        script = RELEASE_SCRIPT.read_text()

        self.assertEqual(release_script_variable("team_id"), "WUMLCL8SAZ")
        self.assertEqual(release_script_variable("bundle_identifier"), "com.odebrowser.ode")
        self.assertEqual(
            release_script_variable("entitlements_source"), "OdeMac/Configuration/Ode-Direct.entitlements")
        self.assertEqual(release_script_variable("feed_prefix"), "https://odebrowser.com/updates/")
        for required in (
            "--product --distribution",
            '--provisioning-profile "$work/profile.provisionprofile"',
            '--signing-identity "$identity_hash"',
            "--without-cloudkit",
            'codesign --verify --deep --strict "$app"',
            "xcrun notarytool submit",
            "xcrun stapler staple",
            'spctl --assess --type execute "$app"',
        ):
            with self.subTest(required=required):
                self.assertIn(required, script)
        self.assertNotIn("CODE_SIGN_STYLE=Automatic", script)


if __name__ == "__main__":
    unittest.main()
