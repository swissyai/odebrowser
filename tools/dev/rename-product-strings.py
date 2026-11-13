#!/usr/bin/env python3
"""Rename the product in every string people and agents can see.

Rewrites the word "Crest" to the product name in string literals of the app's
Swift, C# and Objective-C sources and in the string catalog's keys, fixing the
article ("a Crest" becomes "an Ode"). Type, module and file names are code,
not text; tools/dev/rename-identifiers.py renames those. Run it after merging
upstream changes.

Left alone on purpose:
- About's credits, which say what Ode is based on;
- the engine's data folder and profile folder prefix, which the Chromium
  engine spells itself until it is rebuilt;
- identifiers, file names, URLs and regular expressions inside literals;
- the heraldic emblem editor and the app icon choices, which name artwork and
  icon assets;
- generated contract sources (regenerate them from the core instead) and the
  Chromium overlay and patches, which are engine inputs.

Test sources get the same rule, so expectations follow the production text,
except the literals in KEPT_IN_TESTS, whose old spelling is what they test.

Usage: tools/dev/rename-product-strings.py [--check]
  --check  change nothing; list what would change and exit 1 if anything would
"""

import json
import re
import subprocess
import sys
from pathlib import Path

PRODUCT = "Ode"
OLD = "Crest"
SOURCE_SUFFIXES = (".swift", ".cs", ".m", ".mm")
EXCLUDED_PARTS = ("/Generated/", "CrestEngines/Chromium/Overlay/", "CrestEngines/Chromium/Patches/", "ThirdParty/",
                  # The emblem editor and the app icon choices name heraldic
                  # artwork and icon assets, not the product.
                  "/Forge/", "Heraldic", "BrandingEditor", "AppIcon")
TEST_ROOTS = ("OdeTests/", "OdeMobileTests/", "OdeUITests/", "OdeCore/tests/")
CATALOG = Path("OdeShared/Resources/Localizable.xcstrings")
# The emblem editor's own vocabulary, removed with that editor.
HERALDRY = re.compile(r"Crest Studio|Layered Crest|Crest colors|Crest preview|Crest branding|color the crest")
# About's credits say where Ode comes from, as the base product's trademark
# policy allows a fork to, beside a statement that the two aren't affiliated.
ATTRIBUTION = frozenset({
    "Ode is based on Crest by Paul Davis and its contributors.",
    "Ode isn’t affiliated with or endorsed by Crest or Paul Davis.",
})
# Folders the Chromium engine names itself until the engine is rebuilt.
ENGINE_BOUND = re.compile(r"Application Support/Crest/Chromium|(?:^|/)Crest-")
# A palette test checks that a suggestion equal to the typed query, in another
# case, is dropped; its fixture must keep spelling the query's words.
KEPT_IN_TESTS = {("PaletteTests.cs", "Crest Browser")}
RENAMED_PATHS = {"Application Support/Crest/Agents": "Application Support/Ode/Agents"}
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
WORD = re.compile(r"(?<![\w/.\-@])Crest(?![\w\-/]|\.[A-Za-z])")
ARTICLE = re.compile(r"\b([Aa]) (?=Crest(?![\w\-/]|\.[A-Za-z]))")


def rename(text):
    """`text` with the product renamed, or unchanged when it must stay."""
    if OLD not in text or HERALDRY.search(text) or text in ATTRIBUTION or ENGINE_BOUND.search(text) \
            or text.startswith("^"):
        return text
    for old, new in RENAMED_PATHS.items():
        text = text.replace(old, new)
    text = ARTICLE.sub(lambda match: ("An " if match.group(1) == "A" else "an "), text)
    return WORD.sub(PRODUCT, text)


def tracked_sources():
    """The sources git tracks, or, in a copy of the tree without git, every
    source file under the current folder."""
    try:
        files = subprocess.check_output(["git", "ls-files"], text=True, stderr=subprocess.DEVNULL).split()
    except (OSError, subprocess.CalledProcessError):
        files = [str(p) for p in Path(".").rglob("*") if p.is_file() and ".build" not in p.parts]
    return [Path(f) for f in files
            if f.endswith(SOURCE_SUFFIXES) and not any(part in f for part in EXCLUDED_PARTS) and Path(f).is_file()]


def is_test(path):
    return str(path).startswith(TEST_ROOTS)


def rename_in_test(path):
    return lambda old: old if (path.name, old) in KEPT_IN_TESTS else rename(old)


def rewrite_lines(path, decide):
    """Rewrites each literal of `path` that `decide` maps to new text; answers
    the changed literals as (old, new) pairs and the new file text."""
    changed = []
    lines = path.read_text().splitlines(keepends=True)
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith(("//", "*", "/*")):
            continue

        def replace(match):
            old = match.group(1)
            new = decide(old)
            if new == old:
                return match.group(0)
            changed.append((old, new))
            return f'"{new}"'

        lines[index] = LITERAL.sub(replace, line)
    return changed, "".join(lines)


def main():
    check = "--check" in sys.argv[1:]
    edits = {}
    renamed = {}
    sources = tracked_sources()
    for path in sources:
        changed, text = rewrite_lines(path, rename_in_test(path) if is_test(path) else rename)
        if changed:
            edits[path] = text
            renamed.update(changed)

    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    renamed_keys = {key: rename(key) for key in strings if rename(key) != key}
    collisions = sorted(new for new in renamed_keys.values() if new in strings and new not in renamed_keys)
    if collisions:
        print("catalog keys that would collide:", *collisions, sep="\n  ")
        return 2
    for old, new in renamed_keys.items():
        entry = strings.pop(old)
        for localization in entry.get("localizations", {}).values():
            unit = localization.get("stringUnit")
            if unit and isinstance(unit.get("value"), str):
                unit["value"] = rename(unit["value"])
        strings[new] = entry

    for path in sorted(edits):
        print(f"{path}: rewritten")
    print(f"{len(edits)} source files, {len(renamed)} distinct literals, {len(renamed_keys)} catalog keys")
    if check:
        return 1 if edits or renamed_keys else 0
    for path, text in edits.items():
        path.write_text(text)
    if renamed_keys:
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False))
        subprocess.run(["swift", "tools/dev/format-xcstrings.swift", str(CATALOG)], check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
