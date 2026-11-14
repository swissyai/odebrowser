import contextlib
import datetime
import importlib.util
import io
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
PACKAGING_SPEC = importlib.util.spec_from_file_location(
    "package_chromium_host", REPOSITORY_ROOT / "Scripts/control-plane/package-chromium-host.py")
PACKAGING = importlib.util.module_from_spec(PACKAGING_SPEC)
PACKAGING_SPEC.loader.exec_module(PACKAGING)
# The resource only the product composition of the native UI framework carries.
PRODUCT_MARKER = "Crest-Native-Host"

DEVICE_ACCESS = {
    "com.apple.security.device.camera": True,
    "com.apple.security.device.audio-input": True,
    "com.apple.security.personal-information.location": True,
}
PROFILE = {
    "com.apple.application-identifier": "TEAM123456.com.example.browser",
    "com.apple.developer.team-identifier": "TEAM123456",
    "keychain-access-groups": ["TEAM123456.*"],
}


class ChromiumPackageEntitlementTests(unittest.TestCase):
    def test_device_access_needs_no_profile(self) -> None:
        self.assertEqual(PACKAGING.unbacked_entitlements(DEVICE_ACCESS, {}), [])

    def test_keychain_group_without_a_profile_is_refused(self) -> None:
        requested = {**DEVICE_ACCESS, "keychain-access-groups": ["TEAM123456.com.example.browser"]}
        self.assertEqual(PACKAGING.unbacked_entitlements(requested, {}), ["keychain-access-groups"])

    def test_profile_wildcard_covers_the_team_keychain_group(self) -> None:
        requested = {
            "com.apple.application-identifier": "TEAM123456.com.example.browser",
            "com.apple.developer.team-identifier": "TEAM123456",
            "keychain-access-groups": ["TEAM123456.com.example.browser"],
        }
        self.assertEqual(PACKAGING.unbacked_entitlements(requested, PROFILE), [])

    def test_keychain_group_of_another_prefix_is_refused(self) -> None:
        requested = {"keychain-access-groups": ["OTHER00000.com.example.browser"]}
        self.assertEqual(PACKAGING.unbacked_entitlements(requested, PROFILE), ["keychain-access-groups"])

    def test_managed_capability_missing_from_the_profile_is_refused(self) -> None:
        requested = {"com.apple.developer.web-browser.public-key-credential": True}
        self.assertEqual(PACKAGING.unbacked_entitlements(requested, PROFILE),
                         ["com.apple.developer.web-browser.public-key-credential"])
        granted = {**PROFILE, "com.apple.developer.web-browser.public-key-credential": True}
        self.assertEqual(PACKAGING.unbacked_entitlements(requested, granted), [])

    def test_cloud_environment_must_be_one_the_profile_lists(self) -> None:
        granted = {**PROFILE, "com.apple.developer.icloud-container-environment": ["Development", "Production"],
                   "com.apple.developer.aps-environment": "production"}
        self.assertEqual(PACKAGING.unbacked_entitlements(
            {"com.apple.developer.icloud-container-environment": "Production",
             "com.apple.developer.aps-environment": "production"}, granted), [])
        self.assertEqual(PACKAGING.unbacked_entitlements(
            {"com.apple.developer.aps-environment": "development"}, granted),
            ["com.apple.developer.aps-environment"])


class PackageFixture:
    """Built products a package can be made from, and the refusal main reports."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.directory.name)
        self.browser = root / "Chromium.app"
        (self.browser / "Contents").mkdir(parents=True)
        (self.browser / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Chromium"}))
        self.ui = root / "UI.framework"
        (self.ui / "Resources").mkdir(parents=True)
        (self.ui / "Resources/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "UI"}))
        (self.ui / "UI").write_bytes(b"")
        self.core = root / "OdeCore.Native.dylib"
        self.core.write_bytes(b"")
        self.root = root

    def tearDown(self) -> None:
        self.directory.cleanup()

    def refusal(self, *arguments: str) -> str:
        argv = ["package-chromium-host.py", "--browser", str(self.browser), "--signing-identity", "Developer",
                "--output", str(self.root / "Out.app"), *arguments]
        errors = io.StringIO()
        with mock.patch.object(sys, "argv", argv), contextlib.redirect_stderr(errors), \
                self.assertRaises(SystemExit) as stopped:
            PACKAGING.main()
        self.assertEqual(stopped.exception.code, 2)
        return errors.getvalue().strip().splitlines()[-1]


class ChromiumPackageArgumentTests(PackageFixture, unittest.TestCase):
    """Packaging refuses arguments that cannot make a package before it touches anything."""

    def test_each_refusal_names_the_first_argument_that_cannot_work(self) -> None:
        review = ("--ui", str(self.ui), "--core", str(self.core))
        new_output = "The output must be a new absolute .app path"
        cases = (
            (("--signing-identity", "-"), "Use a stable signing identity so keychain access survives rebuilds"),
            (("--output", "Out.app"), new_output),
            (("--output", str(self.core)), new_output),
            (("--output", str(self.root / "Out.bundle")), new_output),
            (("--output", str(REPOSITORY_ROOT / "Out.app")),
             "Keep experimental browser products outside /Applications and the repository"),
            (("--baseline", "--ui", str(self.ui)), "A baseline package must not include host libraries"),
            (("--automatic-updates",), "Only a product package has an update feed to check automatically"),
            (("--baseline", "--product"), "The stock baseline has no Ode product identity"),
            (("--entitlements", str(self.core)),
             "Entitlements belong to the product identity; review packages preserve the existing signature"),
            (("--browser", str(self.root), *review), "Provide a built Chromium app"),
            (("--ui", str(self.ui)), "Provide the linked browser, native UI framework, and NativeAOT library"),
            (("--core", str(self.root / "missing.dylib"), "--ui", str(self.ui)),
             "Provide the linked browser, native UI framework, and NativeAOT library"),
        )
        for arguments, message in cases:
            with self.subTest(arguments=arguments):
                self.assertTrue(self.refusal(*arguments).endswith("error: " + message))
        (self.ui / "UI").unlink()
        self.assertTrue(self.refusal(*review).endswith("error: The native UI framework has no linked executable"))
        (self.ui / "UI").write_bytes(b"")
        self.assertIn("for a product package", self.refusal("--product", *review))
        (self.ui / "Resources" / PRODUCT_MARKER).write_bytes(b"")
        self.assertIn("for a review package", self.refusal(*review))


class ChromiumPackageProfileTests(PackageFixture, unittest.TestCase):
    """What a provisioning profile lets a package claim, before anything is copied or signed."""

    class Stop(Exception):
        pass

    def setUp(self) -> None:
        super().setUp()
        self.profile_path = self.root / "profile.provisionprofile"
        self.profile_path.write_bytes(b"")
        _, product, development = PACKAGING.product_identity(REPOSITORY_ROOT)
        self.review_identity = development + ".control-plane.chromium"
        self.product_identity = product
        with (REPOSITORY_ROOT / "OdeMac/Configuration/Ode-Info.plist").open("rb") as stream:
            self.container = plistlib.load(stream)["OdeCloudKitContainerIdentifier"]

    def profile(self, identity: str, **changes: object) -> dict:
        granted = {
            "com.apple.application-identifier": "TEAM123456." + identity,
            "com.apple.developer.team-identifier": "TEAM123456",
            "com.apple.developer.icloud-container-identifiers": [self.container],
            "com.apple.developer.icloud-container-environment": ["Development"],
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.aps-environment": "development",
        }
        granted.update(changes)
        return {"Entitlements": {key: value for key, value in granted.items() if value is not None},
                "ExpirationDate": datetime.datetime(2999, 1, 1)}

    def claimed(self, profile: dict, *arguments: str) -> tuple[dict, dict]:
        """The entitlements the package would claim and the profile's grants."""
        argv = ["package-chromium-host.py", "--browser", str(self.browser), "--signing-identity", "Developer",
                "--output", str(self.root / "Out.app"), "--ui", str(self.ui), "--core", str(self.core),
                "--provisioning-profile", str(self.profile_path), *arguments]
        seen = {}

        def unbacked(claims: dict, granted: dict) -> list:
            seen.update(claims=claims, granted=granted)
            raise self.Stop

        with mock.patch.object(sys, "argv", argv), \
                mock.patch.object(PACKAGING.subprocess, "check_output", return_value=plistlib.dumps(profile)), \
                mock.patch.object(PACKAGING, "unbacked_entitlements", side_effect=unbacked), \
                self.assertRaises(self.Stop):
            PACKAGING.main()
        return seen["claims"], seen["granted"]

    def profile_refusal(self, profile: dict, *arguments: str) -> str:
        with mock.patch.object(PACKAGING.subprocess, "check_output", return_value=plistlib.dumps(profile)):
            return self.refusal("--ui", str(self.ui), "--core", str(self.core),
                                "--provisioning-profile", str(self.profile_path), *arguments)

    def test_a_review_profile_claims_development_cloudkit_and_push(self) -> None:
        claims, granted = self.claimed(self.profile(self.review_identity))
        self.assertEqual(claims, {
            "com.apple.application-identifier": "TEAM123456." + self.review_identity,
            "com.apple.developer.team-identifier": "TEAM123456",
            "com.apple.developer.icloud-container-identifiers": [self.container],
            "com.apple.developer.icloud-container-environment": "Development",
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.aps-environment": "development",
        })
        self.assertEqual(granted, self.profile(self.review_identity)["Entitlements"])
        claims, _ = self.claimed(self.profile(
            self.review_identity, **{"com.apple.developer.icloud-container-environment": "Development",
                                     "com.apple.developer.icloud-services": "*"}))
        self.assertEqual(claims["com.apple.developer.icloud-container-environment"], "Development")
        self.assertEqual(claims["com.apple.developer.icloud-services"], ["CloudKit"])

    def test_a_product_profile_claims_production_when_it_grants_it(self) -> None:
        (self.ui / "Resources" / PRODUCT_MARKER).write_bytes(b"")
        profile = self.profile(self.product_identity, **{
            "com.apple.developer.icloud-container-environment": ["Development", "Production"],
            "com.apple.developer.aps-environment": "production"})
        claims, _ = self.claimed(profile, "--product")
        self.assertEqual(claims["com.apple.developer.icloud-container-environment"], "Production")
        self.assertEqual(claims["com.apple.developer.aps-environment"], "production")

    def test_a_profile_without_cloudkit_claims_only_the_app_identity(self) -> None:
        profile = self.profile(self.review_identity, **{"com.apple.developer.icloud-container-identifiers": None})
        claims, _ = self.claimed(profile, "--without-cloudkit")
        self.assertEqual(claims, {"com.apple.application-identifier": "TEAM123456." + self.review_identity,
                                  "com.apple.developer.team-identifier": "TEAM123456"})

    def test_profiles_that_cannot_back_the_package_are_refused(self) -> None:
        identity = self.review_identity
        unexpired = f"error: The profile must be an unexpired profile for {identity}"
        access = f"error: The profile must grant {identity} CloudKit and push access"
        expired = self.profile(identity)
        expired["ExpirationDate"] = datetime.datetime(2001, 1, 1)
        cases = (
            (expired, (), unexpired),
            (self.profile(identity, **{"com.apple.application-identifier": "TEAM123456.other"}), (), unexpired),
            (self.profile(identity, **{"com.apple.developer.team-identifier": None}), (), unexpired),
            (self.profile(identity, **{"com.apple.developer.icloud-container-identifiers": ["iCloud.other"]}), (),
             access),
            (self.profile(identity, **{"com.apple.developer.aps-environment": "production"}), (), access),
            (self.profile(identity, **{"com.apple.developer.icloud-container-environment": ["Production"]}), (),
             access),
            (self.profile(identity, **{"com.apple.developer.icloud-services": ["CloudDocuments"]}), (),
             "error: The provisioning profile does not grant CloudKit"),
        )
        for profile, arguments, message in cases:
            with self.subTest(message=message, granted=profile["Entitlements"]):
                self.assertTrue(self.profile_refusal(profile, *arguments).endswith(message))
        self.assertTrue(self.refusal("--ui", str(self.ui), "--core", str(self.core), "--without-cloudkit").endswith(
            "error: --without-cloudkit describes a provisioning profile; pass one with --provisioning-profile"))
        self.assertTrue(self.refusal("--baseline", "--provisioning-profile", str(self.profile_path)).endswith(
            "error: CloudKit is only supported by the native Ode composition"))


MACHO = b"\xcf\xfa\xed\xfe"
IDENTITY = "Developer ID Application: Example (TEAM123456)"


def write(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def write_plist(path: pathlib.Path, value: dict) -> None:
    write(path, plistlib.dumps(value))


def read_plist(path: pathlib.Path) -> dict:
    with path.open("rb") as stream:
        return plistlib.load(stream)


class BuiltProducts:
    """An engine, a native UI build and a core shaped like the ones a release
    packages, and the commands packaging runs on them, with paths relative to
    the fixture and each signature's entitlements read when it is made."""

    def __init__(self, root: pathlib.Path, product: bool) -> None:
        self.root = root
        self.browser = root / "Chromium.app"
        contents = self.browser / "Contents"
        write_plist(contents / "Info.plist", {
            "CFBundleExecutable": "Chromium", "CFBundleIdentifier": "org.chromium.Chromium",
            "CFBundleShortVersionString": "156.0.8078.80", "LSMinimumSystemVersion": "12.0",
            "NSAppleScriptEnabled": True, "OSAScriptingDefinition": "scripting.sdef",
            "CFBundleURLTypes": [{"CFBundleURLSchemes": ["http"]}],
            "CFBundleDocumentTypes": [{"CFBundleTypeName": "HTML"}]})
        write(contents / "MacOS/Chromium", MACHO)
        write_plist(contents / "Resources/en.lproj/InfoPlist.strings", {
            "CFBundleGetInfoString": "Chromium 156", "NSCameraUsageDescription": "Chromium needs the camera.",
            "NSHumanReadableCopyright": "Copyright Chromium"})
        framework = contents / "Frameworks/Chromium Framework.framework"
        version = framework / "Versions/A"
        write(version / "Chromium Framework", MACHO)
        write(version / "Libraries/libEGL.dylib", MACHO)
        for helper in ("Chromium Helper", "Chromium Helper (Renderer)", "Chromium Helper (GPU)",
                       "Chromium Helper (Alerts)"):
            write_plist(version / f"Helpers/{helper}.app/Contents/Info.plist", {"CFBundleDevelopmentRegion": "en"})
            write(version / f"Helpers/{helper}.app/Contents/MacOS/{helper}", MACHO)
        (framework / "Versions/Current").symlink_to("A")
        self.ui = root / "Build/UI.framework"
        write_plist(self.ui / "Resources/Info.plist", {
            "CFBundleExecutable": "UI", "CFBundleShortVersionString": "0.8.144",
            "CFBundleVersion": "202611091200", "LSMinimumSystemVersion": "15.0"})
        write(self.ui / "UI", MACHO)
        write(self.ui / "Resources/Ode.icns", b"icon")
        write_plist(self.ui / "Resources/de.lproj/InfoPlist.strings",
                    {"NSMicrophoneUsageDescription": "Chromium braucht das Mikrofon."})
        if product:
            write(self.ui / "Resources" / PRODUCT_MARKER, b"")
        write(self.ui.parent / "Sparkle.framework/Versions/B/Sparkle", MACHO)
        write(self.ui.parent / "OdeDockTilePlugin.docktileplugin/Contents/MacOS/OdeDockTilePlugin", MACHO)
        write(self.ui.parent / "ode-browser", MACHO)
        self.core = root / "OdeCore.Native.dylib"
        write(self.core, MACHO)
        self.output = root / "Out/Ode.app"
        self.profile = None
        self.signed_entitlements = {"com.apple.security.device.audio-input": True}
        self.commands = []
        self.plutil_run = None

    def relative(self, part: str) -> str:
        return part.replace(str(self.root), "<root>")

    def record(self, command: list) -> None:
        recorded = []
        for index, part in enumerate(command):
            if index and command[index - 1] == "--entitlements" and part != ":-":
                recorded.append(read_plist(pathlib.Path(part)))
            else:
                recorded.append(self.relative(part))
        self.commands.append(recorded)

    def run(self, command, **kwargs):
        command = [str(part) for part in command]
        self.record(command)
        if command[:2] == ["cp", "-cR"]:
            shutil.copytree(command[2], command[3], symlinks=True)
        elif command[0] == "ditto":
            source, destination = pathlib.Path(command[1]), pathlib.Path(command[2])
            if source.is_dir():
                shutil.copytree(source, destination, symlinks=True, dirs_exist_ok=True)
            else:
                shutil.copy2(source, destination)
        elif command[0] == "plutil" and self.plutil_run is not None:
            return self.plutil_run(command, **kwargs)
        elif command[:2] == ["codesign", "-d"]:
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(self.signed_entitlements), b"")
        return subprocess.CompletedProcess(command, 0, b"", b"")

    def check_output(self, command, **kwargs):
        if command[0] == "plutil":
            return json.dumps(read_plist(pathlib.Path(command[-1]))).encode()
        if command[:2] == ["security", "cms"]:
            return plistlib.dumps(self.profile)
        raise AssertionError(f"Unexpected command: {command}")

    def package(self, *arguments: str) -> str:
        argv = ["package-chromium-host.py", "--browser", str(self.browser), "--signing-identity", IDENTITY,
                "--output", str(self.output), *arguments]
        printed = io.StringIO()
        with mock.patch.object(sys, "argv", argv), \
                mock.patch.object(PACKAGING.subprocess, "run", side_effect=self.run), \
                mock.patch.object(PACKAGING.subprocess, "check_output", side_effect=self.check_output), \
                mock.patch.dict(os.environ, {"ODE_DEFAULT_UPDATE_CHANNEL": "stable"}), \
                contextlib.redirect_stdout(printed):
            PACKAGING.main()
        return printed.getvalue()

    def signatures(self) -> list:
        """(signed path, entitlements or None) for each codesign that signs, in order."""
        signed = []
        for command in self.commands:
            if command[0] != "codesign" or "--sign" not in command:
                continue
            entitlements = command[command.index("--entitlements") + 1] if "--entitlements" in command else None
            signed.append((command[-1], entitlements))
        return signed


class ChromiumPackageAssemblyTests(unittest.TestCase):
    """What a package holds and how each piece of it is signed."""

    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = pathlib.Path(directory.name)
        _, self.product_identity, development = PACKAGING.product_identity(REPOSITORY_ROOT)
        self.review_identity = development + ".control-plane.chromium"
        self.ode_info = read_plist(REPOSITORY_ROOT / "OdeMac/Configuration/Ode-Info.plist")

    def products(self, product: bool) -> BuiltProducts:
        return BuiltProducts(self.root, product)

    def assert_innermost_first(self, signed: list) -> None:
        paths = [path for path, _ in signed]
        for index, path in enumerate(paths):
            inside = [later for later in paths[index + 1:] if later.startswith(path + "/")]
            self.assertEqual(inside, [], f"{path} is signed before code inside it")

    def assert_host_contents(self, built: BuiltProducts, product_name: str) -> None:
        contents = built.output / "Contents"
        for relative in ("Frameworks/UI.framework/UI", "Frameworks/OdeCore.Native.dylib",
                         "Frameworks/Sparkle.framework/Versions/B/Sparkle",
                         "PlugIns/OdeDockTilePlugin.docktileplugin", "Helpers/ode-browser",
                         "Resources/Ode.icns", "Resources/app.icns", "Resources/Crest-App-Owned-Host",
                         "Resources/Ode-Mori-LICENSE.txt"):
            self.assertTrue((contents / relative).exists(), relative)
        self.assertFalse((contents / "Resources/Info.plist").exists())
        helpers = contents / "Frameworks/Chromium Framework.framework/Versions/A/Helpers"
        self.assertEqual(sorted(path.name for path in helpers.iterdir()),
                         ["Chromium Helper (GPU).app", "Chromium Helper (Renderer).app", "Chromium Helper.app"])
        self.assertEqual(read_plist(helpers / "Chromium Helper (Renderer).app/Contents/Resources/en.lproj/"
                                              "InfoPlist.strings"),
                         {"CFBundleDisplayName": f"{product_name} Helper (Renderer)"})
        self.assertEqual(read_plist(contents / "Resources/en.lproj/InfoPlist.strings"), {
            "NSCameraUsageDescription": f"{product_name} needs the camera.",
            "NSHumanReadableCopyright": "Copyright Chromium"})
        self.assertEqual(read_plist(contents / "Resources/de.lproj/InfoPlist.strings"),
                         {"NSMicrophoneUsageDescription": f"{product_name} braucht das Mikrofon."})

    @unittest.skipUnless(sys.platform == "darwin", "Requires macOS Foundation plutil serialization")
    def test_packaged_info_is_foundation_stable_without_changing_dictionary_semantics(self) -> None:
        built = self.products(product=True)
        built.plutil_run = subprocess.run  # Real Foundation serialization; copying and signing stay mocked.
        built.package("--product", "--distribution", "--ui", str(built.ui), "--core", str(built.core))

        info_path = built.output / "Contents/Info.plist"
        packaged = info_path.read_bytes()
        info = plistlib.loads(packaged)
        self.assertIsInstance(info["SUScheduledCheckInterval"], float)
        self.assertEqual(info["SUScheduledCheckInterval"], 3600.0)
        python_xml = plistlib.dumps(info)
        self.assertIn(b"<real>3600.0</real>", python_xml)
        source = self.root / "python-info.plist"
        source.write_bytes(python_xml)
        foundation_xml = subprocess.check_output(
            ["plutil", "-convert", "xml1", "-o", "-", str(source)])
        self.assertEqual(plistlib.loads(foundation_xml), info)
        self.assertEqual(packaged, foundation_xml)
        self.assertEqual(subprocess.check_output(
            ["plutil", "-convert", "xml1", "-o", "-", str(info_path)]), packaged)

    def test_failed_info_normalization_stops_before_signing(self) -> None:
        built = self.products(product=True)
        built.plutil_run = mock.Mock(side_effect=subprocess.CalledProcessError(1, "plutil"))
        with self.assertRaises(subprocess.CalledProcessError):
            built.package("--product", "--distribution", "--ui", str(built.ui), "--core", str(built.core))
        built.plutil_run.assert_called_once_with(
            ["plutil", "-convert", "xml1", str(built.output / "Contents/Info.plist")], check=True)
        self.assertFalse(any(command[0] == "codesign" for command in built.commands))

    def test_a_release_package_claims_the_product_identity_and_signs_for_notarization(self) -> None:
        built = self.products(product=True)
        built.profile = {"Entitlements": {
            "com.apple.application-identifier": "TEAM123456." + self.product_identity,
            "com.apple.developer.team-identifier": "TEAM123456",
            "keychain-access-groups": ["TEAM123456.*"]}, "ExpirationDate": datetime.datetime(2999, 1, 1)}
        profile_path = self.root / "profile.provisionprofile"
        write(profile_path, b"signed profile")
        entitlements = {"com.apple.security.device.camera": True,
                        "keychain-access-groups": ["TEAM123456." + self.product_identity]}
        entitlements_path = self.root / "entitlements.plist"
        write_plist(entitlements_path, entitlements)

        printed = built.package("--product", "--distribution", "--automatic-updates", "--ui", str(built.ui),
                                "--core", str(built.core), "--entitlements", str(entitlements_path),
                                "--provisioning-profile", str(profile_path), "--without-cloudkit")

        contents = built.output / "Contents"
        info = read_plist(contents / "Info.plist")
        self.assertEqual(info["CFBundleIdentifier"], self.product_identity)
        self.assertEqual((info["CFBundleDisplayName"], info["CFBundleName"]), ("Ode", "Ode"))
        self.assertEqual((info["CFBundleShortVersionString"], info["CFBundleVersion"]), ("0.8.144", "202611091200"))
        self.assertEqual(info["OdeChromiumEngineVersion"], "156.0.8078.80")
        self.assertEqual(info["LSMinimumSystemVersion"], "15.0")
        self.assertEqual((info["CFBundleIconFile"], info["CFBundleIconName"]), ("Ode", "Ode"))
        self.assertEqual(info["OdeAppIconPreferenceDomain"], self.product_identity)
        self.assertNotIn("NSAppleScriptEnabled", info)
        self.assertNotIn("OSAScriptingDefinition", info)
        for key in ("SUFeedURL", "SUPublicEDKey", "CFBundleURLTypes", "CFBundleDocumentTypes",
                    "NSCameraUsageDescription", "OdeSessionStorageVersion", "OdeCloudKitContainerIdentifier"):
            self.assertEqual(info[key], self.ode_info[key], key)
        self.assertEqual(info["OdeDefaultUpdateChannel"], "stable")
        self.assertIs(info["SUEnableAutomaticChecks"], True)
        self.assertIs(info["SUAutomaticallyUpdate"], True)
        self.assertTrue((contents / "Resources" / PRODUCT_MARKER).is_file())
        self.assertFalse((contents / "Resources/Crest-Isolated-Experiment").exists())
        self.assertEqual((contents / "embedded.provisionprofile").read_bytes(), b"signed profile")
        self.assert_host_contents(built, "Ode")

        normalization = ["plutil", "-convert", "xml1", "<root>/Out/Ode.app/Contents/Info.plist"]
        self.assertEqual(built.commands.count(normalization), 1)
        first_signature = next(index for index, command in enumerate(built.commands)
                               if command[0] == "codesign" and "--sign" in command)
        self.assertLess(built.commands.index(normalization), first_signature)
        signed = built.signatures()
        self.assert_innermost_first(signed)
        jit = {"com.apple.security.cs.allow-jit": True}
        frameworks = "<root>/Out/Ode.app/Contents/Frameworks"
        helpers = frameworks + "/Chromium Framework.framework/Versions/A/Helpers"
        by_path = dict(signed)
        self.assertEqual(len(by_path), len(signed), "a piece of code is signed twice")
        self.assertEqual(by_path[helpers + "/Chromium Helper (Renderer).app"], jit)
        self.assertEqual(by_path[helpers + "/Chromium Helper (GPU).app"], jit)
        self.assertIsNone(by_path[helpers + "/Chromium Helper.app"])
        for loose in ("/OdeCore.Native.dylib", "/Chromium Framework.framework/Versions/A/Libraries/libEGL.dylib"):
            self.assertIsNone(by_path[frameworks + loose])
        self.assertIsNone(by_path["<root>/Out/Ode.app/Contents/Helpers/ode-browser"])
        self.assertNotIn(frameworks + "/Chromium Framework.framework/Versions/A/Chromium Framework", by_path)
        self.assertEqual(signed[-1], ("<root>/Out/Ode.app", {
            **PACKAGING.ENGINE_APP_ENTITLEMENTS, **entitlements,
            "com.apple.application-identifier": "TEAM123456." + self.product_identity,
            "com.apple.developer.team-identifier": "TEAM123456"}))
        for command in built.commands:
            if command[0] == "codesign" and "--sign" in command:
                self.assertEqual(command[1:7], ["--force", "--timestamp", "--options", "runtime", "--sign", IDENTITY])
        self.assertEqual(built.commands[-1], ["codesign", "--verify", "--deep", "--strict", "<root>/Out/Ode.app"])
        self.assertEqual(printed, f"Packaged {built.output} with Ode's product identity. It launches without "
                         "switches and registers for HTTP, HTTPS and HTML documents once it is installed and its "
                         "signature is accepted. Distribution still requires signing and provisioning that "
                         "identity.\n")

    def test_distribution_preserves_jit_for_standard_and_aperitif_renderer_and_gpu_helpers(self) -> None:
        built = self.products(product=True)
        helpers = built.browser / "Contents/Frameworks/Chromium Framework.framework/Versions/A/Helpers"
        for suffix in ("Aperitif", "Aperitif Renderer", "Aperitif GPU", "Aperitif Alerts"):
            name = f"Chromium Helper ({suffix})"
            write_plist(helpers / f"{name}.app/Contents/Info.plist", {"CFBundleDevelopmentRegion": "en"})
            write(helpers / f"{name}.app/Contents/MacOS/{name}", MACHO)

        built.package("--product", "--distribution", "--ui", str(built.ui), "--core", str(built.core))

        signatures = built.signatures()
        self.assert_innermost_first(signatures)
        prefix = "<root>/Out/Ode.app/Contents/Frameworks/Chromium Framework.framework/Versions/A/Helpers/"
        jit = {"com.apple.security.cs.allow-jit": True}
        self.assertEqual({path for path, entitlements in signatures if entitlements == jit}, {
            prefix + "Chromium Helper (Renderer).app",
            prefix + "Chromium Helper (GPU).app",
            prefix + "Chromium Helper (Aperitif Renderer).app",
            prefix + "Chromium Helper (Aperitif GPU).app",
        })
        by_path = dict(signatures)
        for name in ("Chromium Helper.app", "Chromium Helper (Aperitif).app",
                     "Chromium Helper (Aperitif Alerts).app"):
            self.assertIsNone(by_path[prefix + name])

    def test_a_product_package_signed_for_development_adds_its_entitlements_to_the_engine_signature(self) -> None:
        built = self.products(product=True)
        entitlements_path = self.root / "entitlements.plist"
        write_plist(entitlements_path, {"com.apple.security.device.camera": True})

        built.package("--product", "--ui", str(built.ui), "--core", str(built.core),
                      "--entitlements", str(entitlements_path))

        info = read_plist(built.output / "Contents/Info.plist")
        self.assertIs(info["SUEnableAutomaticChecks"], False)
        self.assertIs(info["SUAutomaticallyUpdate"], False)
        self.assertFalse((built.output / "Contents/embedded.provisionprofile").exists())
        app_signatures = [command for command in built.commands
                          if command[0] == "codesign" and command[-1] == "<root>/Out/Ode.app"]
        self.assertEqual(app_signatures, [
            ["codesign", "-d", "--entitlements", ":-", "<root>/Out/Ode.app"],
            ["codesign", "--force", "--sign", IDENTITY, "--preserve-metadata=flags,runtime", "--entitlements",
             {"com.apple.security.device.audio-input": True, "com.apple.security.device.camera": True},
             "<root>/Out/Ode.app"],
            ["codesign", "--verify", "--deep", "--strict", "<root>/Out/Ode.app"]])

    def test_a_review_package_keeps_an_isolated_identity_and_the_engine_signature_metadata(self) -> None:
        built = self.products(product=False)

        printed = built.package("--ui", str(built.ui), "--core", str(built.core))

        contents = built.output / "Contents"
        info = read_plist(contents / "Info.plist")
        self.assertEqual(info["CFBundleIdentifier"], self.review_identity)
        self.assertEqual((info["CFBundleDisplayName"], info["CFBundleName"]),
                         ("Ode Chromium Experiment", "Ode Chromium Experiment"))
        self.assertEqual(info["OdeCloudKitContainerIdentifier"], self.ode_info["OdeCloudKitContainerIdentifier"])
        for key in ("CFBundleURLTypes", "CFBundleDocumentTypes", "SUFeedURL", "OdeDefaultUpdateChannel",
                    "NSAppleScriptEnabled"):
            self.assertNotIn(key, info)
        self.assertTrue((contents / "Resources/Crest-Isolated-Experiment").is_file())
        self.assertFalse((contents / "Resources" / PRODUCT_MARKER).exists())
        self.assert_host_contents(built, "Ode Chromium Experiment")

        signed = built.signatures()
        self.assert_innermost_first(signed)
        frameworks = "<root>/Out/Ode.app/Contents/Frameworks"
        self.assertEqual([path for path, _ in signed[:4]], [
            frameworks + "/OdeCore.Native.dylib", frameworks + "/UI.framework",
            "<root>/Out/Ode.app/Contents/PlugIns/OdeDockTilePlugin.docktileplugin",
            "<root>/Out/Ode.app/Contents/Helpers/ode-browser"])
        self.assertEqual(sorted(path for path, _ in signed[4:-1]), sorted([
            frameworks + "/Chromium Framework.framework",
            frameworks + "/Sparkle.framework",
            *(frameworks + f"/Chromium Framework.framework/Versions/A/Helpers/Chromium Helper{suffix}.app"
              for suffix in ("", " (GPU)", " (Renderer)"))]))
        self.assertEqual(signed[-1][0], "<root>/Out/Ode.app")
        for command in built.commands:
            if command[0] == "codesign" and "--sign" in command:
                self.assertEqual(command[1:5], ["--force", "--sign", IDENTITY,
                                                "--preserve-metadata=entitlements,flags,runtime"])
        self.assertEqual(printed, f"Packaged {built.output}. Launch its executable with --crest-control-plane "
                         "and an explicit experimental --user-data-dir.\n")

    def test_a_baseline_package_holds_and_signs_only_the_engine(self) -> None:
        built = self.products(product=False)

        printed = built.package("--baseline")

        contents = built.output / "Contents"
        info = read_plist(contents / "Info.plist")
        _, _, development = PACKAGING.product_identity(REPOSITORY_ROOT)
        self.assertEqual(info["CFBundleIdentifier"], development + ".chromium-baseline")
        self.assertEqual(info["CFBundleDisplayName"], "Ode Chromium Baseline")
        self.assertEqual(info["CFBundleShortVersionString"], "156.0.8078.80")
        self.assertEqual(sorted(path.name for path in (contents / "Frameworks").iterdir()),
                         ["Chromium Framework.framework"])
        self.assertFalse((contents / "PlugIns").exists() or (contents / "Helpers").exists())
        self.assertEqual(sorted(path.name for path in (contents / "Resources").iterdir()),
                         ["Crest-Isolated-Experiment", "Ode-Mori-LICENSE.txt", "en.lproj"])
        signed = built.signatures()
        self.assert_innermost_first(signed)
        self.assertEqual(signed[-2:], [("<root>/Out/Ode.app/Contents/Frameworks/Chromium Framework.framework", None),
                                       ("<root>/Out/Ode.app", None)])
        self.assertEqual(len(signed), 6)
        self.assertEqual(printed, f"Packaged {built.output}. Launch its executable with an explicit experimental "
                         "--user-data-dir.\n")

    def test_a_host_build_without_its_companions_is_refused(self) -> None:
        companions = (
            ("Sparkle.framework", "The native UI build must supply Sparkle.framework beside the host framework"),
            ("OdeDockTilePlugin.docktileplugin",
             "The native UI build must supply Ode.icns and OdeDockTilePlugin.docktileplugin"),
            ("ode-browser", "The native UI build must supply ode-browser beside the host framework"),
        )
        for name, message in companions:
            with self.subTest(missing=name):
                root = self.root / name
                root.mkdir()
                built = BuiltProducts(root, product=False)
                missing = built.ui.parent / name
                shutil.rmtree(missing) if missing.is_dir() else missing.unlink()
                errors = io.StringIO()
                with contextlib.redirect_stderr(errors), self.assertRaises(SystemExit) as stopped:
                    built.package("--ui", str(built.ui), "--core", str(built.core))
                self.assertEqual(stopped.exception.code, 2)
                self.assertTrue(errors.getvalue().strip().endswith("error: " + message))
                self.assertFalse(any(command[0] == "codesign" for command in built.commands))

    def test_unexpanded_and_unbacked_entitlements_are_refused_before_anything_is_copied(self) -> None:
        built = self.products(product=True)
        entitlements_path = self.root / "entitlements.plist"
        write_plist(entitlements_path, {"keychain-access-groups": ["$(AppIdentifierPrefix)com.example"],
                                        "com.apple.security.device.camera": True})
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors), self.assertRaises(SystemExit) as stopped:
            built.package("--product", "--ui", str(built.ui), "--core", str(built.core),
                          "--entitlements", str(entitlements_path))
        self.assertEqual(stopped.exception.code, 2)
        self.assertTrue(errors.getvalue().strip().endswith(
            "error: Expand these entitlement build settings before packaging: keychain-access-groups"))
        self.assertEqual(built.commands, [])

        errors = io.StringIO()
        write_plist(entitlements_path, {"keychain-access-groups": ["TEAM123456.com.example"]})
        with contextlib.redirect_stderr(errors), self.assertRaises(SystemExit):
            built.package("--product", "--ui", str(built.ui), "--core", str(built.core),
                          "--entitlements", str(entitlements_path))
        self.assertTrue(errors.getvalue().strip().endswith(
            "error: macOS refuses to launch an app that claims these entitlements without a provisioning profile "
            "granting them: keychain-access-groups"))
        self.assertEqual(built.commands, [])


if __name__ == "__main__":
    unittest.main()
