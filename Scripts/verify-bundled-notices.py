#!/usr/bin/env python3
"""Compare an app or app ZIP's offline notices with this exact source checkout."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import plistlib
import re
import sys
import zipfile

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


def canonical_notices(repo: Path) -> dict[str, bytes]:
    paths = {name: repo / name for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "TRADEMARKS.md")}
    paths.update({"ThirdParty/" + path.name: path for path in (repo / "ThirdParty").iterdir() if path.is_file()})
    paths["ThirdPartyDependencies.json"] = repo / "Config/ThirdPartyDependencies.json"
    for name in ("SFSymbolCatalog-LICENSE.txt", "HeraldicArtworkCredits.txt"):
        paths[name] = repo / "OdeShared/Resources" / name
    paths["Mori-LICENSE"] = repo / "CrestEngines/Chromium/ThirdParty/Mori-LICENSE"
    inventory = json.loads(paths["ThirdPartyDependencies.json"].read_bytes())
    for category in ("runtimeDependencies", "bundledData", "bundledComponents"):
        for dependency in inventory[category]:
            source = dependency["notice"]
            paths[source.removeprefix("OdeShared/Resources/")] = repo / source
    if not any(name.startswith("ThirdParty/") for name in paths):
        raise ValueError("Canonical ThirdParty collection is empty")
    notices = {name: path.read_bytes() for name, path in paths.items()}
    if any(not data.strip() for data in notices.values()):
        raise ValueError("Canonical notice is empty")
    return notices


@contextmanager
def artifact_reader(artifact: Path):
    if artifact.is_dir() and artifact.suffix == ".app":
        mac = (artifact / "Contents/Info.plist").is_file()
        info = artifact / ("Contents/Info.plist" if mac else "Info.plist")
        resources = artifact / "Contents/Resources" if mac else artifact
        yield plistlib.loads(info.read_bytes()), lambda name: (resources / name).read_bytes()
        return
    with zipfile.ZipFile(artifact) as archive:
        candidates = []
        for name in archive.namelist():
            if sum(part.endswith(".app") for part in name.split("/")) != 1:
                continue
            if name.endswith(".app/Contents/Info.plist") or name.endswith(".app/Info.plist"):
                candidates.append(name)
        if len(candidates) != 1:
            raise ValueError("ZIP must contain exactly one top-level app")
        info = candidates[0]
        resources = info.removesuffix("Info.plist")
        if info.endswith("/Contents/Info.plist"):
            resources += "Resources/"
        yield plistlib.loads(archive.read(info)), lambda name: archive.read(resources + name)


def verify(artifact: Path, version: str, repo: Path = REPOSITORY_ROOT) -> dict:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected version must be a three-component marketing version")
    notices = canonical_notices(repo)
    with artifact_reader(artifact) as (info, read):
        if info.get("CFBundleShortVersionString") != version:
            raise ValueError("Packaged marketing version differs from expected source version")
        for name, expected in notices.items():
            try:
                actual = read(name)
            except (OSError, KeyError) as error:
                raise ValueError(f"Missing bundled notice: {name}") from error
            if actual != expected:
                raise ValueError(f"Bundled notice differs from canonical bytes: {name}")
    return {"notice_files": len(notices), "version": version,
            "intended_source_url": f"https://github.com/swissyai/odebrowser/tree/v{version}",
            "source_publication_verified": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help="Built .app or ZIP containing one app")
    parser.add_argument("--version", required=True, help="Marketing version of the exact release source")
    args = parser.parse_args()
    try:
        result = verify(args.artifact, args.version)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
