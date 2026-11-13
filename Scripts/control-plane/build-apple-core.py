#!/usr/bin/env python3
"""Build the native core for an Xcode target, reusing that build's derived data."""

import dataclasses
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_filter  # noqa: E402


RUNTIMES = {"macosx": "osx-arm64", "iphoneos": "ios-arm64", "iphonesimulator": "iossimulator-arm64"}
# MSBuild imports environment names case-insensitively as project properties.
# Xcode's TARGETNAME otherwise renames every referenced assembly to Ode.
INHERITED = {"PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "SHELL", "LANG", "DEVELOPER_DIR",
             "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy"}
# The content filter's own settings, and where Rust lives, reach its fetch.
INHERITED |= {"ODE_CONTENT_FILTER_FROM_SOURCE", "ODE_CONTENT_FILTER_REPOSITORY", "CARGO_HOME", "RUSTUP_HOME"}
INHERITED_PREFIXES = ("DOTNET_", "NUGET_", "LC_")


@dataclasses.dataclass(frozen=True)
class Target:
    """The core an Xcode target asks for: `product` inside `output`, the
    folder the `key` build setting names, or one supplied prebuilt."""

    platform: str
    key: str
    output: Path
    product: Path
    explicit: bool

    @property
    def runtime(self):
        return RUNTIMES[self.platform]

    @property
    def is_mac(self):
        return self.platform == "macosx"


@dataclasses.dataclass(frozen=True)
class Toolchain:
    """The .NET SDK that builds the core, the environment it runs in, and the
    platform SDK it builds against."""

    dotnet: str
    environment: dict
    version: str
    sdk: str


def requested_target():
    platform = os.environ["PLATFORM_NAME"]
    if platform not in RUNTIMES or os.environ.get("ARCHS", "arm64").split() != ["arm64"]:
        raise RuntimeError("The Ode core currently supports Apple silicon macOS and arm64 iOS/device Simulator builds")
    default = Path(os.environ["BUILT_PRODUCTS_DIR"]) / "OdeCore"
    key = "ODE_CORE_LIBRARY_DIR" if platform == "macosx" else "ODE_CORE_FRAMEWORK_DIR"
    output = Path(os.environ[key]).resolve()
    product = output / ("OdeCore.Native.dylib" if platform == "macosx" else "OdeCoreABI.framework/OdeCoreABI")
    return Target(platform, key, output, product, explicit=output != default.resolve())


def use_explicit_core(target):
    if not target.product.is_file():
        raise RuntimeError(f"Explicit {target.key} has no core library: {target.product}")
    print(f"Using explicitly supplied core: {target.product}")


def find_dotnet():
    candidates = [os.environ.get("ODE_DOTNET"), shutil.which("dotnet"),
                  str(Path.home() / ".dotnet/dotnet"), "/usr/local/share/dotnet/dotnet"]
    dotnet = next((p for p in candidates if p and Path(p).is_file()), None)
    if not dotnet:
        raise RuntimeError("Install the SDK in OdeCore/global.json, or run Scripts/control-plane/install-dotnet.sh")
    return dotnet


def dotnet_toolchain(platform, core):
    dotnet = find_dotnet()
    environment = {k: v for k, v in os.environ.items() if k in INHERITED or k.startswith(INHERITED_PREFIXES)}
    environment["SDKROOT"] = subprocess.check_output(
        ["xcrun", "--sdk", platform, "--show-sdk-path"], text=True).strip()
    version = subprocess.check_output([dotnet, "--version"], cwd=core, env=environment, text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", platform, "--show-sdk-version"], text=True).strip()
    return Toolchain(dotnet, environment, version, sdk)


def fingerprint_inputs(repo):
    """Every file the core is built from, the generated Swift that reads it,
    and the content filter library it links: the one its lock names, or its
    sources compiled while they differ from the lock."""
    core = repo / "OdeCore"
    inputs = [p for folder in ("src", "tools") for p in (core / folder).rglob("*") if p.is_file()
              and not {"bin", "obj"}.intersection(p.relative_to(core).parts)]
    inputs += list((repo / "OdeShared/Infrastructure/Core/Generated").glob("*.swift"))
    inputs += list(core.glob("Directory.*")) + [core / "global.json", Path(__file__).resolve(),
                                               repo / "Scripts/control-plane/package-apple-core.py"]
    for name in content_filter.INPUTS + (content_filter.LOCK, "Scripts/control-plane/fetch-content-filter.py"):
        path = repo / name
        inputs += [p for p in path.rglob("*") if p.is_file()] if path.is_dir() else [path]
    return inputs


def fingerprint(repo, platform, toolchain, cross_checks):
    digest = hashlib.sha256(f"{toolchain.version}:{platform}:{toolchain.sdk}:{os.environ.get('DEVELOPER_DIR', '')}:"
                            f"{os.environ.get('ODE_CONTENT_FILTER_FROM_SOURCE', '')}".encode())
    for path in sorted(fingerprint_inputs(repo)):
        digest.update(str(path.relative_to(repo)).encode())
        digest.update(path.read_bytes())
    digest.update(f"cross-checks:{cross_checks}".encode())
    return digest.hexdigest()


def publish_core(repo, target, toolchain, cross_checks):
    core = repo / "OdeCore"
    # The Swift models and codecs are generated from the same contract
    # records; a stale copy would misread the core, so refuse to build.
    subprocess.run([toolchain.dotnet, "run", "--project", "tools/OdeCore.Generator", "--nologo", "--",
                    "--check", "--root", str(repo)], cwd=core, env=toolchain.environment, check=True)
    publish = target.output / "publish"
    command = [toolchain.dotnet, "publish", "src/OdeCore.Native", "-c", "Release", "-r", target.runtime,
               "--artifacts-path", str(target.output / "intermediates"), "-o", str(publish), "--nologo",
               f"-p:OdeCrossChecks={'true' if cross_checks else 'false'}"]
    if not target.is_mac:
        command += ["-p:PublishAotUsingRuntimePack=true"]
    subprocess.run(command, cwd=core, env=toolchain.environment, check=True)
    install_core(repo, target, publish / "OdeCore.Native.dylib")


def install_core(repo, target, library):
    """Put the published library where the target links it: the dylib itself
    on macOS, a framework around it on iOS."""
    if target.is_mac:
        shutil.copy2(library, target.product.with_suffix(".pending"))
        target.product.with_suffix(".pending").replace(target.product)
        return
    framework = target.output / "OdeCoreABI.framework"
    if framework.exists():
        shutil.rmtree(framework)
    subprocess.run([sys.executable, str(repo / "Scripts/control-plane/package-apple-core.py"),
                    "--library", str(library), "--output", str(framework),
                    "--platform", target.platform], check=True)


def main():
    repo = Path(__file__).resolve().parents[2]
    target = requested_target()
    if target.explicit:
        use_explicit_core(target)
        return
    toolchain = dotnet_toolchain(target.platform, repo / "OdeCore")
    # A Debug app's core runs the core's cross-checks, which Release builds leave out.
    cross_checks = os.environ.get("CONFIGURATION") == "Debug"
    source_hash = fingerprint(repo, target.platform, toolchain, cross_checks)
    target.output.mkdir(parents=True, exist_ok=True)
    # App and framework targets can request the same core in a parallel build.
    with (target.output / ".build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = target.output / ".source-hash"
        if target.product.is_file() and stamp.exists() and stamp.read_text() == source_hash:
            print(f"Ode core is current ({target.runtime}, SDK {toolchain.version})")
            return
        publish_core(repo, target, toolchain, cross_checks)
        stamp.write_text(source_hash)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: Ode core build failed: {error}")
