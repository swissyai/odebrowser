#!/usr/bin/env python3
"""Refresh the name-only SF catalog from an explicit SFSafeSymbols revision.

Usage: python3 Scripts/update-sf-symbol-catalog.py --revision <40-character commit SHA>
The picker draws Apple's system artwork; no SF Symbol images are redistributed.
The catalog keeps only the symbols the oldest supported macOS and iOS draw,
read from the same revision's availability table, because Ode never checks a
name at run time: asking the system for a symbol loads its artwork.
"""
import argparse
import json
import plistlib
import re
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--revision", required=True)
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
    parser.error("Use an immutable, 40-character commit SHA.")


def version(text):
    return tuple(int(part) for part in text.split("."))


def deployment_targets(project):
    """The oldest macOS and iOS releases project.yml supports."""
    block = re.search(r"^  deploymentTarget:\n((?:    \w+: \"[\d.]+\"\n)+)", project.read_text(), re.MULTILINE)
    if not block:
        raise SystemExit("project.yml declares no deployment targets; no files were changed.")
    targets = dict(re.findall(r"(\w+): \"([\d.]+)\"", block.group(1)))
    if not {"macOS", "iOS"} <= targets.keys():
        raise SystemExit("project.yml must declare macOS and iOS deployment targets; no files were changed.")
    return {platform: version(targets[platform]) for platform in ("macOS", "iOS")}


root = Path(__file__).resolve().parents[1]
base = f"https://raw.githubusercontent.com/SFSafeSymbols/SFSafeSymbols/{args.revision}/"
resources = base + "SymbolsGenerator/Sources/SymbolsGenerator/Resources/"
source = resources + "symbol_names.txt"
with urllib.request.urlopen(source, timeout=30) as response:
    names = response.read().decode("utf-8")
with urllib.request.urlopen(resources + "name_availability.plist", timeout=30) as response:
    availability = plistlib.loads(response.read())
with urllib.request.urlopen(base + "LICENSE", timeout=30) as response:
    license_text = response.read().decode("utf-8")
entries = [line.strip() for line in names.splitlines() if line.strip() and not line.startswith("//")]
if not entries or any(not re.fullmatch(r"[a-z0-9.]+", name) for name in entries):
    raise SystemExit("Unexpected symbol catalog format; no files were changed.")

targets = deployment_targets(root / "project.yml")
introduced, releases = availability["symbols"], availability["year_to_release"]


def drawable(name):
    """Whether every supported macOS and iOS release has the symbol."""
    release = releases.get(introduced.get(name, ""))
    return release is not None and all(version(release[platform]) <= oldest for platform, oldest in targets.items())


newer = {name for name in entries if not drawable(name)}
kept = "".join(line for line in names.splitlines(keepends=True)
               if not line.strip() or line.startswith("//") or line.strip() not in newer)

metadata_path = root / "Config/ThirdPartyDependencies.json"
metadata = json.loads(metadata_path.read_text())
record = next(item for item in metadata["bundledData"] if item["identity"] == "sf-symbol-names")
record.update(version=args.revision, source=source)
(root / "OdeShared/Resources/SFSymbolNames.txt").write_text(kept)
(root / record["notice"]).write_text(
    "SF symbol name catalog from SFSafeSymbols\nRevision: " + args.revision
    + "\nhttps://github.com/SFSafeSymbols/SFSafeSymbols\n"
    + "Only symbol names are included; artwork is supplied by the operating system.\n\n" + license_text
)
metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
print(f"Updated {len(entries) - len(newer)} SF symbol names at {args.revision}; "
      f"left out {len(newer)} that macOS {'.'.join(map(str, targets['macOS']))} "
      f"or iOS {'.'.join(map(str, targets['iOS']))} cannot draw.")
