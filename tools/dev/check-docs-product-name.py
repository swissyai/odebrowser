#!/usr/bin/env python3
"""Fail when developer documentation names Crest in prose.

Scans Documentation/ and CrestEngines/Chromium/ Markdown outside code spans
and fenced blocks, where names the prebuilt engine binds keep the base name.
A reference to the base project says "upstream Crest" or "derived from Crest".
"""
import pathlib, re, sys
word = re.compile(r"(?<![\w/.\-@`])Crest(?![\w\-/]|\.[A-Za-z])")
allowed = re.compile(r"upstream Crest|Crest upstream|based on Crest|derived from Crest|Crest's (engine|published|release) artifacts")
bad = []
roots = [pathlib.Path("Documentation"), pathlib.Path("CrestEngines/Chromium")]
for root in roots:
    for path in sorted(root.rglob("*.md")):
        if "ThirdParty" in path.parts: continue
        fenced = False
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("```"): fenced = not fenced; continue
            if fenced: continue
            prose = re.sub(r"`[^`]*`", "", line)
            prose = allowed.sub("", prose)
            if word.search(prose): bad.append(f"{path}:{number}: {line.strip()[:100]}")
print("\n".join(bad[:40])); print(len(bad), "lines name Crest in prose", file=sys.stderr)
sys.exit(1 if bad else 0)
