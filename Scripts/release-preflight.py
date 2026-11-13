#!/usr/bin/env python3
"""Read-only release evidence; success is NOT permission or readiness to release.

Use --online for provider GETs of the keyed release and its small sidecars, or
supply --release-metadata, --provenance and --checksum to reproduce an inspection.
No build, archive download, Apple account request, profile read or app launch occurs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "control-plane"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import sha256
from bundle_info import read_plist
import chromium_engine
from chromium_artifact import published_release


def publication_recipe(lock):
    """Validate the source identity before comparing publisher provenance schema 1."""
    if not isinstance(lock, dict):
        raise ValueError("Invalid source lock: expected object")
    schema = lock.get("schemaVersion")
    if type(schema) is not int:
        raise ValueError("Invalid source lock field: schemaVersion (expected integer)")
    if schema not in (1, 2):
        raise ValueError("Unsupported source lock schemaVersion: " + str(schema))

    def required(path, pattern=None):
        value = lock
        for part in path.split("."):
            if not isinstance(value, dict):
                raise ValueError("Invalid source lock field: " + path)
            value = value.get(part)
        if (not isinstance(value, str) or not value.strip()
                or (pattern is not None and not re.fullmatch(pattern, value))):
            raise ValueError("Invalid source lock field: " + path)
        return value

    required("status")
    expected = {"schemaVersion": 1, "configuration": "performance",
                "chromium": required("chromium.version", r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"),
                "sdkVersion": required("performanceInputs.macSDKVersion", r"[0-9]+(?:\.[0-9]+)*"),
                "pgoSHA256": required("performanceInputs.pgoSHA256", r"[0-9a-f]{64}")}
    # Both publishers emit provenance schema 1. The lock schema selects the
    # source binding; missing fields must never fall back to the other recipe.
    if schema == 1:
        expected["upstreamCommit"] = required("ungoogledMac.commit", r"[0-9a-f]{40}")
    else:
        expected["sourceArchiveSHA256"] = required("chromium.sourceArchiveSha256", r"[0-9a-f]{64}")
    return expected


def release_problems(release, tag, key):
    """The release metadata's problems, and whether it is too malformed to check further."""
    problems = []
    if (release.get("draft") is not False or not isinstance(release.get("published_at"), str)
            or not release.get("published_at")):
        problems.append("Release is not published")
    body = release.get("body")
    if body is not None and not isinstance(body, str):
        return problems + ["Invalid release body metadata"], True
    if release.get("tag_name") != tag or key not in (body or ""):
        problems.append("Release tag or full engine key differs")
    assets = release.get("assets", [])
    if not isinstance(assets, list) or not all(isinstance(item, dict) for item in assets):
        return problems + ["Invalid release asset metadata"], True
    return problems, False


def asset_problems(assets, asset):
    """The archive and its two sidecars must each be uploaded once, with a size."""
    problems = []
    for name in (asset, asset + ".sha256", asset + ".json"):
        found = [item for item in assets if item.get("name") == name]
        if (len(found) != 1 or found[0].get("state") != "uploaded"
                or type(found[0].get("size")) is not int or found[0]["size"] <= 0):
            problems.append("Missing, duplicate or incomplete asset: " + name)
    return problems


def provenance_problems(provenance, expected):
    """Provenance must carry exactly the recipe's values and a full source commit."""
    problems = []
    for field, value in expected.items():
        if type(provenance.get(field)) is not type(value) or provenance.get(field) != value:
            problems.append("Provenance mismatch: " + field)
    source_commit = provenance.get("sourceCommit")
    if not isinstance(source_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        problems.append("Missing or invalid provenance source commit")
    return problems


def digest_problems(checksum, provenance, assets, asset):
    """The archive digest the checksum sidecar names, and where it disagrees with the
    provenance or the provider's own digest of the archive."""
    problems = []
    match = re.fullmatch(r"([0-9a-f]{64})  " + re.escape(asset) + r"\n?", checksum)
    digest = match[1] if match else None
    if not digest or digest != provenance.get("archiveSHA256"):
        problems.append("Checksum sidecar differs from provenance or names another archive")
    archive_assets = [item for item in assets if item.get("name") == asset]
    if len(archive_assets) == 1:
        provider_digest = archive_assets[0].get("digest")
        if provider_digest and provider_digest != "sha256:" + (digest or ""):
            problems.append("Provider archive digest differs from checksum")
    return digest, problems


def archive_integrity(archive, digest):
    """Whether the local archive's bytes hash to `digest`."""
    return "matched" if sha256(archive) == digest else "mismatch"


def inspect_publication(release, provenance, checksum, lock, key, archive=None):
    asset = chromium_engine.asset_name(key)
    problems = []
    result = {"status": "blocked", "tag": chromium_engine.release_tag(key), "asset": asset,
              "archive_integrity": "not_checked", "runtime_capability": "not_tested",
              "security_freshness": "not_assessed", "problems": problems}
    try:
        expected = publication_recipe(lock)
    except ValueError as error:
        problems.append(str(error))
        return result
    expected["engineKey"] = key
    if not isinstance(release, dict):
        problems.append("No published release metadata available")
        return result
    if not isinstance(provenance, dict):
        problems.append("Invalid provenance metadata")
        return result
    found, unreadable = release_problems(release, result["tag"], key)
    problems += found
    if unreadable:
        return result
    assets = release.get("assets", [])
    problems += asset_problems(assets, asset)
    problems += provenance_problems(provenance, expected)
    digest, found = digest_problems(checksum, provenance, assets, asset)
    problems += found
    result["archive_sha256"] = digest
    result["source_commit"] = provenance.get("sourceCommit")
    result["published_at"] = release.get("published_at")
    if archive is not None:
        result["archive_integrity"] = archive_integrity(archive, digest)
        if result["archive_integrity"] != "matched":
            problems.append("Local archive bytes differ from published checksum")
    if not problems:
        result["status"] = "archive_matched" if archive is not None else "metadata_matched"
    return result


def inspect_entitlements(path):
    values = read_plist(path)
    return {"source": str(path), "status": "declaration_only",
            "cloudkit_declared": "CloudKit" in values.get("com.apple.developer.icloud-services", []),
            "push_declared": "aps-environment" in values or "com.apple.developer.aps-environment" in values,
            "browser_passkeys_declared": values.get("com.apple.developer.web-browser.public-key-credential") is True,
            "signed_package_grants": "not_checked",
            "ode_passwords": "separate_origin_bound_keychain_feature"}


def verify_sidecar(release, name, data):
    if not isinstance(release, dict) or not isinstance(release.get("assets"), list):
        raise ValueError("Invalid release metadata")
    found = [item for item in release["assets"] if isinstance(item, dict) and item.get("name") == name]
    if len(found) != 1 or len(data) > 65536:
        raise ValueError("Missing, duplicate or oversized metadata sidecar: " + name)
    provider_digest = found[0].get("digest")
    if provider_digest and provider_digest != "sha256:" + hashlib.sha256(data).hexdigest():
        raise ValueError("Provider sidecar digest differs: " + name)


def fetch_sidecar(release, name, repository):
    assets = release.get("assets")
    if not isinstance(assets, list) or not all(isinstance(item, dict) for item in assets):
        raise ValueError("Invalid release asset metadata")
    found = [item for item in assets if item.get("name") == name]
    if (len(found) != 1 or not isinstance(found[0].get("id"), int)
            or type(found[0].get("size")) is not int or not 0 < found[0]["size"] <= 65536):
        raise ValueError("Missing, duplicate or oversized metadata sidecar: " + name)
    # Fixed provider endpoint, not a URL supplied by the release body.
    fetched = subprocess.run(["gh", "api", "-H", "Accept: application/octet-stream",
                              f"repos/{repository}/releases/assets/{found[0]['id']}"],
                             capture_output=True, check=True, timeout=30)
    verify_sidecar(release, name, fetched.stdout)
    return fetched.stdout.decode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--repository", default="pauljoda/Crest")
    parser.add_argument("--online", action="store_true")
    parser.add_argument("--release-metadata", type=Path)
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--checksum", type=Path)
    parser.add_argument("--archive", type=Path, help="Optional existing archive; never downloaded by this script")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
        parser.error("repository must be owner/name")
    if args.online and any((args.release_metadata, args.provenance, args.checksum)):
        parser.error("choose online retrieval or recorded evidence, not both")
    repo = args.repo.resolve()
    report = {"schema_version": 1, "release_ready": False,
              "source": {"engine_key_inputs": list(chromium_engine.INPUTS)},
              "prerequisites": {"status": "partial_tool_check_only",
                                "tools": {tool: shutil.which(tool) is not None for tool in
                                          ("gh", "dotnet", "xcodebuild", "xcodegen", "hdiutil", "ditto")},
                                "signing_identity_api_key_sparkle_key": "not_checked",
                                "next": "Authorized release operator runs release-ode.sh --check; that checks prerequisites only"},
              "direct_entitlements": inspect_entitlements(repo / "OdeMac/Configuration/Ode-Direct.entitlements"),
              "runtime": {"status": "not_tested", "page_operations": "require_nonempty_all_webkit_roster",
                          "resident_page": "must_not_be_non_webkit", "screenshots": "always_refused", "packaged_engine_and_navigation_boundaries": "not_tested"},
              "security_freshness": {"status": "not_assessed", "next":
                  "Security owner compares exact shipped engine/backports and supported OS WebKit with vendor advisories; a milestone announcement is not installed Ode status"},
              "remaining": ["Verify exact packaged engine identity, signatures, notarization and managed entitlements",
                            "Exercise redirects, popups/new windows, engine transitions, revocation and private/locked Spaces",
                            "Validate clean-account install, update, interruption and rollback; assign security/backport owner"]}
    try:
        try:
            lock = json.loads((repo / "CrestEngines/Chromium/source.lock.json").read_text())
        except json.JSONDecodeError as error:
            raise ValueError("Invalid source lock JSON: " + str(error)) from error
        recipe = publication_recipe(lock)
        key = chromium_engine.engine_key(repo)
        report["source"].update({"engine_key": key, "chromium": recipe["chromium"],
                                 "lock_status": lock["status"]})
        if args.online:
            release = published_release(args.repository, key)
            if release is not None and not isinstance(release, dict):
                raise ValueError("Invalid provider release metadata")
            if release is None:
                provenance, checksum = {}, ""
            else:
                asset = chromium_engine.asset_name(key)
                provenance = json.loads(fetch_sidecar(release, asset + ".json", args.repository))
                checksum = fetch_sidecar(release, asset + ".sha256", args.repository)
        elif all((args.release_metadata, args.provenance, args.checksum)):
            release = json.loads(args.release_metadata.read_text())
            provenance_bytes = args.provenance.read_bytes()
            checksum_bytes = args.checksum.read_bytes()
            asset = chromium_engine.asset_name(key)
            verify_sidecar(release, asset + ".json", provenance_bytes)
            verify_sidecar(release, asset + ".sha256", checksum_bytes)
            provenance = json.loads(provenance_bytes)
            checksum = checksum_bytes.decode("utf-8")
        else:
            raise ValueError("Supply --online or all three recorded metadata files")
        report["publication"] = inspect_publication(release, provenance, checksum, lock, key, args.archive)
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        report["publication"] = {"status": "blocked", "problems": [str(error)]}
    print(json.dumps(report, indent=2))
    return 1 if report["publication"]["status"] == "blocked" else 0


if __name__ == "__main__":
    sys.exit(main())
