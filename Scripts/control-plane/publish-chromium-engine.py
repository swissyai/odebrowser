#!/usr/bin/env python3
"""Publish the locally built Chromium engine for release workflows to download.

Run after `build-chromium-baseline.py` finishes for the current sources. The
engine is only published when the external tree holds exactly this branch's
host patch and overlay and its build output is current, so the release that
downloads it by key compiles against the same engine it was published for.
Publishing is idempotent: an engine already released under its key is left
as it is.
"""
import argparse
from contextlib import nullcontext
import dataclasses
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chromium_engine  # noqa: E402
from chromium_fork import exclusive_workspace, performance_configuration_matches, read_json, sha256  # noqa: E402


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="The pinned external Chromium checkout")
    parser.add_argument("--output", default="out/CrestBaseline", help="Build directory inside the checkout")
    parser.add_argument("--ninja", required=True, type=Path)
    parser.add_argument("--repository", default="pauljoda/Crest")
    parser.add_argument("--dry-run", action="store_true", help="Verify and package without uploading")
    args = parser.parse_args()

    source = args.source.resolve()
    # A managed source is <workspace>/sources/<preparation key>/src.
    managed = source.parent / "prepared.json"
    guard = exclusive_workspace(source.parents[2]) if managed.is_file() else nullcontext()
    with guard:
        publish(args)


# The headers the engine compiles in, as the checkout holds them.
CONTRACT_HEADERS = ("CrestEngines/Chromium/Apple/CrestChromiumHost.h",
                    "CrestCore/native/ContentFilter/include/crest_content_filter.h",
                    *(f"CrestContracts/include/{name}" for name in
                      ("crest_core.h", "crest_app.h", "crest_engine.h", "crest_engine_contract.h")))


@dataclasses.dataclass(frozen=True)
class Engine:
    """The engine being published: its full key and the source lock it was built from."""

    key: str
    lock: dict

    @property
    def tag(self):
        return chromium_engine.release_tag(self.key)

    @property
    def asset(self):
        return chromium_engine.asset_name(self.key)


def require_branch_host(repo, source):
    """The tree must hold this branch's reviewed patch output and overlay."""
    validation = run(sys.executable, repo / "Scripts/control-plane/apply-chromium-host.py",
                     "--source", source, capture_output=True).stdout
    if "(after)" not in validation:
        raise SystemExit("Apply the host to the checkout before publishing: " + validation.strip())
    overlay = repo / "CrestEngines/Chromium/Overlay"
    for path in overlay.rglob("*"):
        if path.is_file() and (source / path.relative_to(overlay)).read_bytes() != path.read_bytes():
            raise SystemExit(f"The checkout's overlay differs from the branch: {path.relative_to(overlay)}")
    for header in (repo / name for name in CONTRACT_HEADERS):
        if (source / "chrome/browser/ui/crest" / header.name).read_bytes() != header.read_bytes():
            raise SystemExit(f"The checkout's contract header differs from the branch: {header.name}")


def require_current_build(args, source):
    """And its build must have nothing left to do."""
    plan = run(args.ninja, "-C", source / args.output, "-n", "chrome", capture_output=True).stdout
    if "no work to do" not in plan:
        raise SystemExit("The engine build is not current; run build-chromium-baseline.py first")


def is_published(release, engine):
    """Whether `release` already publishes `engine`; a published release with
    anything else is refused rather than overwritten."""
    if not release or release["isDraft"]:
        return False
    names = {item["name"] for item in release["assets"]}
    if {engine.asset, f"{engine.asset}.sha256"} <= names and engine.key in release["body"]:
        return True
    raise SystemExit("Published engine release is incomplete or has a different full key; refusing to overwrite it")


def provenance(engine, digest, commit):
    lock = engine.lock
    return {"schemaVersion": 1, "engineKey": engine.key,
            "chromium": lock["chromium"]["version"], "sourceArchiveSHA256": lock["chromium"]["sourceArchiveSha256"],
            "configuration": "performance", "sdkVersion": lock["performanceInputs"]["macSDKVersion"],
            "pgoSHA256": lock["performanceInputs"]["pgoSHA256"], "archiveSHA256": digest,
            "sourceCommit": commit}


def release_notes(engine, commit):
    return (f"Chromium {engine.lock['chromium']['version']} with Ode's native host, for release packaging.\n\n"
            f"Engine key `{engine.key}`, computed by `Scripts/control-plane/chromium_engine.py` over the "
            f"engine inputs of commit `{commit}`.\n"
            "This is not an installable browser; releases package it with Ode's UI and sign it.")


def publish(args):
    repo = Path(__file__).resolve().parents[2]
    source = args.source.resolve()
    lock = read_json(repo / "CrestEngines/Chromium/source.lock.json")
    if not performance_configuration_matches(source, lock):
        raise SystemExit("Published engines require the pinned performance configuration, SDK and PGO profile")
    run(sys.executable, repo / "Scripts/control-plane/prepare-chromium.py", "--source", source, "--verify-only")
    engine = Engine(chromium_engine.engine_key(repo), lock)
    require_branch_host(repo, source)
    require_current_build(args, source)

    existing = subprocess.run(["gh", "release", "view", engine.tag, "--repo", args.repository,
                               "--json", "assets,isDraft,body"], capture_output=True, text=True)
    if is_published(json.loads(existing.stdout) if existing.returncode == 0 else None, engine):
        print(f"{engine.tag} is already published.")
        return
    with tempfile.TemporaryDirectory(prefix="crest-engine-") as temporary:
        archive = Path(temporary) / engine.asset
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", source / args.output / "Chromium.app", archive)
        digest = sha256(archive)
        checksum = Path(temporary) / f"{engine.asset}.sha256"
        checksum.write_text(f"{digest}  {engine.asset}\n")
        print(f"Packaged {engine.asset} ({archive.stat().st_size // (1 << 20)} MiB, sha256 {digest}).")
        if args.dry_run:
            return
        commit = run("git", "-C", repo, "rev-parse", "HEAD", capture_output=True).stdout.strip()
        record = Path(temporary) / f"{engine.asset}.json"
        record.write_text(json.dumps(provenance(engine, digest, commit), indent=2) + "\n")
        if existing.returncode != 0:
            run("gh", "release", "create", engine.tag, "--repo", args.repository, "--draft", "--prerelease",
                "--latest=false", "--title", f"Ode Chromium engine {engine.key[:16]}",
                "--notes", release_notes(engine, commit))
        # Only an unpublished draft can be resumed or replaced. The release becomes
        # visible to app packaging after all assets have uploaded successfully.
        run("gh", "release", "upload", engine.tag, archive, checksum, record, "--repo", args.repository, "--clobber")
        run("gh", "release", "edit", engine.tag, "--repo", args.repository, "--draft=false", "--latest=false")
        print(f"Published {engine.tag}.")


if __name__ == "__main__":
    main()
