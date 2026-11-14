#!/usr/bin/env python3
"""Assemble a separate, signed Chromium host from built products: an isolated experiment by default, or Ode's own product identity."""
import argparse
import dataclasses
import fnmatch
import json
import os
import re
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone


# Chromium's browser-process device access (chrome/app/app-entitlements.plist);
# Ode's own entitlements are applied over these.
ENGINE_APP_ENTITLEMENTS = {
    "com.apple.security.device.audio-input": True,
    "com.apple.security.device.bluetooth": True,
    "com.apple.security.device.camera": True,
    "com.apple.security.device.print": True,
    "com.apple.security.device.usb": True,
    "com.apple.security.personal-information.location": True,
    "com.apple.security.personal-information.photos-library": True,
}
# Standard and Aperitif helpers use the same renderer/GPU entitlements
# (chrome/installer/mac/signing/parts.py); V8 maps executable memory in both.
JIT_HELPER_SUFFIXES = (
    "Helper (Renderer).app", "Helper (GPU).app",
    "Helper (Aperitif Renderer).app", "Helper (Aperitif GPU).app",
)
# macOS kills an app at launch when it claims one of these without an
# embedded provisioning profile that grants it.
PROFILE_ENTITLEMENT_KEYS = {"com.apple.application-identifier", "keychain-access-groups"}
PROFILE_ENTITLEMENT_PREFIX = "com.apple.developer."
BUNDLE_SUFFIXES = {".app", ".framework", ".xpc", ".appex", ".plugin", ".docktileplugin", ".bundle"}
MACHO_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
# The engine is built as Chromium and finds its helpers by these built names
# (chrome/BUILD.gn, chrome/common/chrome_constants.cc).
ENGINE_HELPER_NAME = "Chromium Helper"
ENGINE_ALERTS_HELPER = "Chromium Helper (Alerts).app"
# How the engine's localized InfoPlist.strings spell its product name.
ENGINE_PRODUCT_NAMES = ("Chromium", "क्रोमियम")



def product_identity(repo_root):
    """The product name, the released app's bundle identifier and the
    development identifier other builds start with, as the Swift
    ProductIdentity declares them."""
    source = (repo_root / "OdeShared/Application/ProductIdentity.swift").read_text()
    name = re.search(r'static let name = "([^"]+)"', source)
    release = re.search(r'static let releaseBundleIdentifier = "([^"]+)"', source)
    development = re.search(r'static let developmentBundleIdentifier = "([^"]+)"', source)
    if not name or not release or not development:
        raise SystemExit("ProductIdentity.swift must declare name, releaseBundleIdentifier and developmentBundleIdentifier")
    return name.group(1), release.group(1), development.group(1)


def is_macho(path):
    with path.open("rb") as stream:
        return stream.read(4) in MACHO_MAGICS


def engine_helpers(frameworks):
    """The engine's helper apps, found once through its versioned framework."""
    return sorted(
        path for path in frameworks.glob("*.framework/Versions/*/Helpers/*.app")
        if not path.parent.parent.is_symlink())


def remove_engine_alerts_helper(frameworks):
    """Chromium posts alert-style notifications from a helper app with its own
    bundle identifier, which Notification Center lists as "Chromium". A host
    package replaces the engine's macOS notification bridge before the bridge
    creates that helper's launcher, and nothing else launches it, so the
    package leaves it out rather than ship an app that could register under
    another name."""
    for helper in engine_helpers(frameworks):
        if helper.name == ENGINE_ALERTS_HELPER:
            shutil.rmtree(helper)


def name_engine_helpers(frameworks, product_name):
    """Show the engine's helpers as the product's wherever macOS names one
    from its bundle, the way Chromium names its own alert helper: a localized
    display name. Bundle and executable names, identifiers and paths keep the
    engine's built names, which the engine resolves at run time. The name is
    localized for the helper's development region, the one localization
    Launch Services falls back to for every language, so the helper process
    keeps the language it runs in today."""
    for helper in engine_helpers(frameworks):
        if not helper.stem.startswith(ENGINE_HELPER_NAME):
            continue
        suffix = helper.stem.removeprefix(ENGINE_HELPER_NAME)
        with (helper / "Contents/Info.plist").open("rb") as stream:
            region = plistlib.load(stream)["CFBundleDevelopmentRegion"]
        strings = helper / f"Contents/Resources/{region}.lproj/InfoPlist.strings"
        strings.parent.mkdir(parents=True, exist_ok=True)
        strings.write_bytes(plistlib.dumps(
            {"CFBundleDisplayName": f"{product_name} Helper{suffix}"}, fmt=plistlib.FMT_BINARY))


def name_product_in_localized_info(resources, product_name):
    """The engine's localized Info.plist strings supply the text macOS shows
    in camera, microphone, location, Bluetooth and passkey prompts, and they
    name Chromium. Name the product there instead and drop Chromium's version
    line; its copyright notice and file-type names stay."""
    for strings in sorted(resources.glob("*.lproj/InfoPlist.strings")):
        values = json.loads(subprocess.check_output(
            ["plutil", "-convert", "json", "-o", "-", str(strings)]))
        values.pop("CFBundleGetInfoString", None)
        for key, value in values.items():
            if key.endswith("UsageDescription"):
                for name in ENGINE_PRODUCT_NAMES:
                    value = value.replace(name, product_name)
                values[key] = value
        strings.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))


def is_bundle_executable(path):
    # An app or XPC service's own executable, or a framework's versioned binary,
    # is signed together with its bundle.
    if path.parent.name == "MacOS" and path.parent.parent.name == "Contents":
        return True
    return path.parent.parent.name == "Versions" and path.parent.parent.parent.name == f"{path.name}.framework"


def sign_for_distribution(output, identity, app_entitlements):
    """Sign every piece of code for notarization, innermost first: loose
    executables and libraries, then bundles, then the app. Everything gets the
    hardened runtime and a secure timestamp; the engine's JIT helpers keep the
    one exception they need."""
    def codesign(path, entitlements=None):
        command = ["codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity]
        with tempfile.TemporaryDirectory(prefix="crest-distribution-sign-") as temporary:
            if entitlements:
                plist = Path(temporary) / "entitlements.plist"
                plist.write_bytes(plistlib.dumps(entitlements))
                command += ["--entitlements", str(plist)]
            subprocess.run(command + [str(path)], check=True)

    depth = lambda path: len(path.parts)
    code = [path for path in output.rglob("*") if not path.is_symlink()]
    loose = [path for path in code if path.is_file() and is_macho(path) and not is_bundle_executable(path)]
    bundles = [path for path in code if path.is_dir() and path.suffix in BUNDLE_SUFFIXES]
    for path in sorted(loose, key=depth, reverse=True):
        codesign(path)
    for path in sorted(bundles, key=depth, reverse=True):
        jit = path.name.endswith(JIT_HELPER_SUFFIXES)
        codesign(path, {"com.apple.security.cs.allow-jit": True} if jit else None)
    codesign(output, app_entitlements)


def unbacked_entitlements(entitlements, granted):
    """The entitlements in `entitlements` that need a provisioning profile and
    that `granted`, the embedded profile's entitlements, does not cover. A
    profile value may be a wildcard such as `TEAM.*` or a list of allowed
    values; a boolean must be granted as true."""
    def allows(allowed, value):
        if isinstance(allowed, list):
            return any(allows(item, value) for item in allowed)
        if isinstance(allowed, str) and isinstance(value, str):
            return fnmatch.fnmatchcase(value, allowed)
        return allowed == value
    missing = []
    for key, value in sorted(entitlements.items()):
        if key not in PROFILE_ENTITLEMENT_KEYS and not key.startswith(PROFILE_ENTITLEMENT_PREFIX):
            continue
        if key not in granted:
            missing.append(key)
            continue
        values = value if isinstance(value, list) else [value]
        if not all(allows(granted[key], item) for item in values):
            missing.append(key)
    return missing


def default_update_channel(repo):
    override = os.environ.get("ODE_DEFAULT_UPDATE_CHANNEL", "").strip()
    if override:
        return override
    channels = set(re.findall(r"^\s*ODE_DEFAULT_UPDATE_CHANNEL:\s*([a-z]+)\s*$",
                              (repo / "project.yml").read_text(), re.MULTILINE))
    if len(channels) != 1:
        raise SystemExit(f"project.yml must name one default update channel; found {sorted(channels)}")
    return channels.pop()


def minimum_system_version(engine_info, ui_info):
    """Launch Services and Sparkle must require every bundled component's OS."""
    versions = [info["LSMinimumSystemVersion"] for info in (engine_info, ui_info)]
    for version in versions:
        if not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
            raise ValueError(f"Invalid minimum macOS version: {version!r}")
    return max(versions, key=lambda version: tuple(int(part) for part in version.split(".")))


def argument_problem(args, repo):
    """The first reason `args` cannot make a package, or None when they can."""
    if args.signing_identity.strip() in ("", "-"):
        return "Use a stable signing identity so keychain access survives rebuilds"
    return output_problem(args.output, repo) or option_problem(args) or products_problem(args)


def output_problem(output, repo):
    """Why `output` is no place for a new package, or None."""
    if not output.is_absolute() or output.exists() or output.suffix != ".app":
        return "The output must be a new absolute .app path"
    if output.resolve().is_relative_to(Path("/Applications")) or output.resolve().is_relative_to(repo):
        return "Keep experimental browser products outside /Applications and the repository"
    return None


def option_problem(args):
    """Which options contradict the kind of package asked for, or None."""
    if args.baseline and (args.ui or args.core):
        return "A baseline package must not include host libraries"
    if args.automatic_updates and not args.product:
        return "Only a product package has an update feed to check automatically"
    if args.baseline and args.product:
        return "The stock baseline has no Ode product identity"
    if args.entitlements and not args.product:
        return "Entitlements belong to the product identity; review packages preserve the existing signature"
    return None


def products_problem(args):
    """Which built product the package needs is missing or unusable, or None."""
    if not (args.browser.resolve() / "Contents/Info.plist").is_file():
        return "Provide a built Chromium app"
    if args.baseline:
        return None
    ui = args.ui.resolve() if args.ui else None
    core = args.core.resolve() if args.core else None
    if ui is None or core is None or not core.is_file() or not (ui / "Resources/Info.plist").is_file():
        return "Provide the linked browser, native UI framework, and NativeAOT library"
    return ui_framework_problem(ui, args.product)


def ui_framework_problem(ui, product):
    """Why the native UI framework at `ui` cannot go into a `product` or review
    package, or None."""
    with (ui / "Resources/Info.plist").open("rb") as stream:
        ui_executable = plistlib.load(stream).get("CFBundleExecutable", "")
    if not ui_executable or not (ui / ui_executable).is_file():
        return "The native UI framework has no linked executable"
    # Only the product target compiles without review isolation and carries
    # its marker resource. Read which composition this is instead of
    # trusting the path it was built at.
    is_product_framework = (ui / "Resources/Crest-Native-Host").is_file()
    if product and not is_product_framework:
        return "Build CrestChromiumUIProduct for a product package; this framework is the isolated review composition"
    if not product and is_product_framework:
        return "Build CrestChromiumUI for a review package; this framework is the normal product composition"
    return None


def granted_cloud_environment(granted, product):
    """The CloudKit environment a package claims from the profile's `granted`
    entitlements, or None when they do not grant it with push. A product
    profile may carry either environment; an experiment profile stays on
    development so it can never reach production records."""
    environments = granted.get("com.apple.developer.icloud-container-environment", [])
    if isinstance(environments, str):
        environments = [environments]
    push = granted.get("com.apple.developer.aps-environment")
    if not product:
        return "Development" if "Development" in environments and push == "development" else None
    environment = next((value for value in ("Production", "Development") if value in environments), None)
    return environment if environment is not None and push in ("development", "production") else None


def profile_entitlements(profile, identity, container, product, without_cloudkit):
    """What a package of `identity` claims from its provisioning `profile`:
    the app identity alone `without_cloudkit`, otherwise with CloudKit in
    `container` and push; and why the profile cannot back it, or None."""
    granted = profile.get("Entitlements", {})
    application_id = granted.get("com.apple.application-identifier", "")
    team = granted.get("com.apple.developer.team-identifier", "")
    expiration = profile.get("ExpirationDate")
    if (not team or application_id != team + "." + identity or not expiration
            or expiration.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc)):
        return None, f"The profile must be an unexpired profile for {identity}"
    identity_entitlements = {
        "com.apple.application-identifier": application_id,
        "com.apple.developer.team-identifier": team,
    }
    if without_cloudkit:
        return identity_entitlements, None
    environment = granted_cloud_environment(granted, product)
    if container not in granted.get("com.apple.developer.icloud-container-identifiers", []) or environment is None:
        return None, f"The profile must grant {identity} CloudKit and push access"
    service = granted.get("com.apple.developer.icloud-services", [])
    if service != "*" and "CloudKit" not in service:
        return None, "The provisioning profile does not grant CloudKit"
    return {
        **identity_entitlements,
        "com.apple.developer.icloud-container-identifiers": [container],
        "com.apple.developer.icloud-container-environment": environment,
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.aps-environment": granted.get("com.apple.developer.aps-environment"),
    }, None


class Refusal(Exception):
    """Why the package cannot be made; main reports it as a usage error."""


@dataclasses.dataclass(frozen=True)
class Package:
    """A package being made: the command line, the identity it takes and the
    entitlements it claims, with `granted` the provisioning profile's own."""

    args: argparse.Namespace
    repo: Path
    product_name: str
    identity: str
    product_entitlements: dict | None
    cloud_entitlements: dict | None
    granted: dict

    @property
    def output(self):
        return self.args.output

    @property
    def ui(self):
        return self.args.ui.resolve() if self.args.ui else None

    @property
    def frameworks(self):
        return self.output / "Contents/Frameworks"

    @property
    def resources(self):
        return self.output / "Contents/Resources"

    @property
    def claimed_entitlements(self):
        return {**(self.product_entitlements or {}), **(self.cloud_entitlements or {})}


def argument_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", required=True, type=Path, help="Built Chromium.app with the Ode overlay")
    parser.add_argument("--signing-identity", required=True,
                        help="Stable Apple Development or Developer ID signing identity; ad-hoc is rejected")
    parser.add_argument("--provisioning-profile", type=Path, help="Profile granting this app access to Ode CloudKit")
    parser.add_argument("--without-cloudkit", action="store_true",
                        help="Accept a profile that grants the app identity and keychain but no CloudKit container; sync stays off")
    parser.add_argument("--baseline", action="store_true", help="Package the stock baseline without the Ode host libraries")
    parser.add_argument("--product", action="store_true",
                        help="Package Ode's own desktop identity from CrestChromiumUIProduct: browser registration, "
                             "document types and the Sparkle update feed instead of the isolated review identity")
    parser.add_argument("--entitlements", type=Path,
                        help="Resolved entitlements plist for the product identity; build-setting variables must already be expanded")
    parser.add_argument("--ui", type=Path, help="Built CrestChromiumUI.framework or CrestChromiumUIProduct.framework")
    parser.add_argument("--core", type=Path, help="Published OdeCore.Native.dylib")
    parser.add_argument("--output", required=True, type=Path, help="New absolute .app path outside /Applications")
    parser.add_argument("--distribution", action="store_true",
                        help="Sign for notarization: hardened runtime, secure timestamps and the engine's helper entitlements")
    parser.add_argument("--automatic-updates", action="store_true",
                        help="Check for, download and install updates automatically: for a release on the published feed. "
                             "Without it a product package leaves them off")
    return parser


def ode_info(repo):
    with (repo / "OdeMac/Configuration/Ode-Info.plist").open("rb") as stream:
        return plistlib.load(stream)


def package_identity(args, release_identifier, development_identifier):
    """Review and baseline packages are development builds: their preferences,
    data and crash reports stay apart from the released app's."""
    if args.product:
        return release_identifier
    if args.baseline:
        return f"{development_identifier}.chromium-baseline"
    return f"{development_identifier}.control-plane.chromium"


def read_product_entitlements(path):
    """The product entitlements at `path`, None without one; refused while a
    build-setting variable in them is still unexpanded."""
    if not path:
        return None
    with path.open("rb") as stream:
        entitlements = plistlib.load(stream)
    unexpanded = sorted(
        key for key, value in entitlements.items()
        if any(isinstance(item, str) and "$(" in item for item in (value if isinstance(value, list) else [value])))
    if unexpanded:
        raise Refusal(f"Expand these entitlement build settings before packaging: {', '.join(unexpanded)}")
    return entitlements


def provisioned_entitlements(args, repo, identity):
    """What the provisioning profile lets the package claim, and everything it
    grants; (None, {}) without a profile."""
    if args.without_cloudkit and not args.provisioning_profile:
        raise Refusal("--without-cloudkit describes a provisioning profile; pass one with --provisioning-profile")
    if not args.provisioning_profile:
        return None, {}
    if args.baseline:
        raise Refusal("CloudKit is only supported by the native Ode composition")
    profile = plistlib.loads(subprocess.check_output(
        ["security", "cms", "-D", "-i", str(args.provisioning_profile)]))
    container = ode_info(repo)["OdeCloudKitContainerIdentifier"]
    entitlements, problem = profile_entitlements(
        profile, identity, container, product=args.product, without_cloudkit=args.without_cloudkit)
    if problem is not None:
        raise Refusal(problem)
    return entitlements, profile.get("Entitlements", {})


def planned_package(args, repo):
    """The package `args` describe, once its arguments, entitlements and
    profile can make one."""
    problem = argument_problem(args, repo)
    if problem is not None:
        raise Refusal(problem)
    product_name, release_identifier, development_identifier = product_identity(repo)
    identity = package_identity(args, release_identifier, development_identifier)
    product_entitlements = read_product_entitlements(args.entitlements)
    cloud_entitlements, granted = provisioned_entitlements(args, repo, identity)
    package = Package(args, repo, product_name, identity, product_entitlements, cloud_entitlements, granted)
    unbacked = unbacked_entitlements(package.claimed_entitlements, granted)
    if unbacked:
        raise Refusal("macOS refuses to launch an app that claims these entitlements without a provisioning "
                      f"profile granting them: {', '.join(unbacked)}")
    return package


# MARK: - Assembling


def copy_host(package):
    """Copy the native UI framework, the core and what the UI build supplies
    beside them into the package; returns the app icon."""
    ui, frameworks, resources = package.ui, package.frameworks, package.resources
    subprocess.run(["ditto", str(ui), str(frameworks / ui.name)], check=True)
    shutil.copy2(package.args.core.resolve(), frameworks / "OdeCore.Native.dylib")
    resources.mkdir(exist_ok=True)
    # Ode's existing views resolve assets and catalogs through Bundle.main.
    # Preserve those resources when its window composition is framework-hosted.
    for resource in (ui / "Resources").iterdir():
        if resource.name != "Info.plist":
            subprocess.run(["ditto", str(resource), str(resources / resource.name)], check=True)
    sparkle = ui.parent / "Sparkle.framework"
    if not sparkle.is_dir():
        raise Refusal("The native UI build must supply Sparkle.framework beside the host framework")
    subprocess.run(["ditto", str(sparkle), str(frameworks / "Sparkle.framework")], check=True)
    icon = copy_dock_tile(package)
    copy_agent_helper(package)
    # Chromium's native menus also resolve its legacy app.icns resource.
    shutil.copy2(icon, resources / "app.icns")
    return icon


def copy_dock_tile(package):
    """Copy the Dock tile plug-in that draws over the app icon; returns the icon."""
    icon = package.resources / f"{package.product_name}.icns"
    if not icon.is_file():
        icon = package.resources / "Ode.icns"
    dock_plugin = package.ui.parent / "OdeDockTilePlugin.docktileplugin"
    if not icon.is_file() or not dock_plugin.is_dir():
        raise Refusal("The native UI build must supply Ode.icns and OdeDockTilePlugin.docktileplugin")
    plugins = package.output / "Contents/PlugIns"
    plugins.mkdir(exist_ok=True)
    subprocess.run(["ditto", str(dock_plugin), str(plugins / dock_plugin.name)], check=True)
    return icon


def copy_agent_helper(package):
    """The helper agents run, ode-browser, which reaches Ode over its agent
    socket. It lives in Contents/Helpers, where signing treats it as loose
    code with the hardened runtime; its embedded Info.plist names its
    signing identifier."""
    agent_helper = package.ui.parent / "ode-browser"
    if not agent_helper.is_file():
        raise Refusal("The native UI build must supply ode-browser beside the host framework")
    helpers = package.output / "Contents/Helpers"
    helpers.mkdir(exist_ok=True)
    shutil.copy2(agent_helper, helpers / agent_helper.name)


def write_markers(package):
    resources = package.resources
    if package.args.product:
        # The product hosts the native UI on every launch, including the ones
        # that carry no switches: Finder, a login item, the default-browser
        # role and Dock reopen.
        (resources / "Crest-Native-Host").write_text("Native Ode host composition.\n")
    else:
        (resources / "Crest-Isolated-Experiment").write_text("Explicit experimental profile required.\n")
    if package.args.ui:
        (resources / "Crest-App-Owned-Host").write_text("Ode starts engines on demand.\n")
    shutil.copy2(package.repo / "CrestEngines/Chromium/ThirdParty/Mori-LICENSE", resources / "Ode-Mori-LICENSE.txt")


def assemble(package):
    """Copy the engine and, unless this is the stock baseline, the host into
    the package; returns the app icon, None for the baseline."""
    # APFS clones avoid another complete copy of Chromium's framework while
    # retaining independent files for signing. No input bundle is modified.
    package.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-cR", str(package.args.browser.resolve()), str(package.output)], check=True)
    icon = None
    if package.args.baseline:
        package.resources.mkdir(exist_ok=True)
    else:
        icon = copy_host(package)
    write_markers(package)
    return icon


# MARK: - Info.plist


# Ode's own browser registration, document handling and session versions;
# its update feed and privacy prompt text are the SU and UsageDescription keys.
PRODUCT_INFO_KEYS = ("CFBundleURLTypes", "CFBundleDocumentTypes", "OdeSessionStorageVersion", "OdeSessionJournalVersion")


def is_product_info(key, value):
    """Whether a key of Ode's Info.plist goes into a product package. The keys
    stay owned by the app's Info.plist; nothing is restated here, and a value
    left to a build setting is not copied."""
    if isinstance(value, str) and "$(" in value:
        return False
    return key.startswith("SU") or key.endswith("UsageDescription") or key in PRODUCT_INFO_KEYS


def display_name(package):
    if package.args.product:
        return package.product_name
    return "Ode Chromium Baseline" if package.args.baseline else "Ode Chromium Experiment"


def take_host_info(info, package, icon):
    """The host's version, icon and CloudKit container replace the engine's."""
    with (package.ui / "Resources/Info.plist").open("rb") as stream:
        ui_info = plistlib.load(stream)
    info["OdeChromiumEngineVersion"] = info["CFBundleShortVersionString"]
    info["CFBundleShortVersionString"] = ui_info["CFBundleShortVersionString"]
    info["CFBundleVersion"] = ui_info["CFBundleVersion"]
    info["LSMinimumSystemVersion"] = minimum_system_version(info, ui_info)
    info["CFBundleIconFile"] = icon.stem
    info["CFBundleIconName"] = icon.stem
    info["NSDockTilePlugIn"] = "OdeDockTilePlugin.docktileplugin"
    info["OdeAppIconPreferenceDomain"] = info["CFBundleIdentifier"]
    # Chromium's scripting dictionary names Chromium's application class,
    # which Ode's application is not. Once any script loaded it, a quit
    # Apple Event (the updater's relaunch, the Dock's Quit, a logout) found
    # no application to quit; without it, AppKit handles the quit itself.
    info.pop("NSAppleScriptEnabled", None)
    info.pop("OSAScriptingDefinition", None)
    info["OdeCloudKitContainerIdentifier"] = ode_info(package.repo)["OdeCloudKitContainerIdentifier"]


def take_product_info(info, package):
    """Ode's browser registration, document handling, update feed, privacy
    prompt text and the session versions it reads."""
    info.update((key, value) for key, value in ode_info(package.repo).items() if is_product_info(key, value))
    # Ode's Info.plist leaves the channel to its target's build setting;
    # a packaged product follows that same default, read from project.yml
    # unless ODE_DEFAULT_UPDATE_CHANNEL overrides it.
    info["OdeDefaultUpdateChannel"] = default_update_channel(package.repo)
    # A release on the published feed delivers fixes without anyone
    # asking: checks, downloads and installs at quit start on. Any other
    # product package leaves them off, so it never replaces itself with
    # a published release.
    info["SUEnableAutomaticChecks"] = package.args.automatic_updates
    info["SUAutomaticallyUpdate"] = package.args.automatic_updates
    if "SUFeedURL" not in info or "SUPublicEDKey" not in info:
        raise Refusal("Ode's Info.plist must supply the Sparkle feed and public key for a product package")


def write_info(package, icon):
    """Give the package its identity in its Info.plist; returns what it wrote."""
    info_path = package.output / "Contents/Info.plist"
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleIdentifier"] = package.identity
    info["CFBundleDisplayName"] = display_name(package)
    info["CFBundleName"] = info["CFBundleDisplayName"]
    if not package.args.baseline:
        take_host_info(info, package, icon)
    if package.args.product:
        take_product_info(info, package)
    else:
        # This experiment must not register as the system HTTP/HTTPS handler.
        info.pop("CFBundleURLTypes", None)
        info.pop("CFBundleDocumentTypes", None)
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)
    # Chromium dynamically validates Foundation's XML serialization against
    # the signed Info.plist slot. Normalize Python's XML before signing so
    # equivalent values (such as real 3600.0) have identical signed bytes.
    subprocess.run(["plutil", "-convert", "xml1", str(info_path)], check=True)
    return info


def name_host(package, name):
    """The system names a host package after its own identity, never the
    engine's: in Notifications, privacy prompts and process lists."""
    remove_engine_alerts_helper(package.frameworks)
    name_engine_helpers(package.frameworks, name)
    name_product_in_localized_info(package.resources, name)


# MARK: - Signing


def signing_targets(package):
    """The code re-signed before the app, innermost first: the host's own
    pieces, then the engine's helper apps and frameworks."""
    frameworks, ui, output = package.frameworks, package.ui, package.output
    depth = lambda path: len(path.parts)
    targets = [] if package.args.baseline else [
        frameworks / "OdeCore.Native.dylib", frameworks / ui.name,
        output / "Contents/PlugIns/OdeDockTilePlugin.docktileplugin", output / "Contents/Helpers/ode-browser"]
    targets += sorted((p for p in frameworks.rglob("*.app") if not p.is_symlink()), key=depth, reverse=True)
    targets += sorted((p for p in frameworks.glob("*.framework") if ui is None or p.name != ui.name),
                      key=depth, reverse=True)
    return targets


def resign(target, identity):
    subprocess.run(["codesign", "--force", "--sign", identity, "--preserve-metadata=entitlements,flags,runtime",
                    str(target)], check=True)


def resign_app(package):
    """Re-sign the app, adding the entitlements the package claims to the
    engine's own."""
    output, identity = package.output, package.args.signing_identity
    claimed = package.claimed_entitlements
    if not claimed:
        resign(output, identity)
        return
    existing = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(output)],
                              capture_output=True, check=True).stdout
    entitlements = plistlib.loads(existing) if existing.strip() else {}
    entitlements.update(claimed)
    with tempfile.TemporaryDirectory(prefix="crest-cloud-sign-") as temporary:
        path = Path(temporary) / "entitlements.plist"
        path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(["codesign", "--force", "--sign", identity,
                        "--preserve-metadata=flags,runtime", "--entitlements", str(path), str(output)], check=True)


def sign(package):
    """Sign for notarization with `--distribution`, otherwise re-sign keeping
    each piece's signing metadata; then verify the whole app."""
    if package.cloud_entitlements:
        shutil.copy2(package.args.provisioning_profile, package.output / "Contents/embedded.provisionprofile")
    if package.args.distribution:
        sign_for_distribution(package.output, package.args.signing_identity, {
            **(ENGINE_APP_ENTITLEMENTS if package.args.product else {}), **package.claimed_entitlements})
    else:
        for target in signing_targets(package):
            resign(target, package.args.signing_identity)
        resign_app(package)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(package.output)], check=True)


# MARK: - Command line


def make_package(args, repo):
    package = planned_package(args, repo)
    icon = assemble(package)
    info = write_info(package, icon)
    if not args.baseline:
        name_host(package, info["CFBundleDisplayName"])
    sign(package)
    return package


def report(package):
    if package.args.product:
        print(f"Packaged {package.output} with Ode's product identity. It launches without switches and registers "
              "for HTTP, HTTPS and HTML documents once it is installed and its signature is accepted. "
              "Distribution still requires signing and provisioning that identity.")
        return
    mode = "" if package.args.baseline else "--crest-control-plane and "
    print(f"Packaged {package.output}. Launch its executable with {mode}an explicit experimental --user-data-dir.")


def main():
    parser = argument_parser()
    args = parser.parse_args()
    try:
        package = make_package(args, Path(__file__).resolve().parents[2])
    except Refusal as refusal:
        parser.error(str(refusal))
    report(package)


if __name__ == "__main__":
    main()
