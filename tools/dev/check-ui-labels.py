#!/usr/bin/env python3
"""Fail when the app's UI sources style text as micro labels or ornaments.

Ode's interface sets labels in sentence case without letter spacing. This
check scans the Swift UI sources (not tests, generated code or demo fixtures)
for the patterns that produce eyebrows, kickers and overlines:

- `.textCase(.uppercase)` on text;
- `.tracking(...)` or `.kerning(...)` with a positive value;
- an all-caps literal handed to `Text`, a `title:` or a `label:`;
- a type or identifier named eyebrow, kicker or overline;
- a leading-zero ornamental number such as "01", written out or formatted
  with a zero-padded decimal.

ALLOWED lists the few literals that are product state rather than ornament,
each with its reason.
"""

import pathlib
import re
import sys

ROOTS = ("OdeMac", "OdeShared", "OdeMobile")
SKIPPED_PARTS = ("/Generated/", "/Seeds/", "/Fixtures/", "Tests/")
ACRONYMS = {"OK", "URL", "HTTP", "HTTPS", "JSON", "CSV", "PDF", "HTML", "CSS", "DOM", "SVG", "PNG", "UTF", "ID",
            "MCP", "AI", "API", "DNS", "TLS", "SSL", "ASCII", "PIN", "SHA", "GET", "POST", "PIP", "RSS", "QR", "IP"}
ALLOWED = {
    # Marks an update the test fixture served; never shown to people.
    ("BrowserSoftwareUpdateSidebarWidget.swift", "TEST"),
}
UPPERCASE_CASE = re.compile(r"\.textCase\(\s*\.uppercase\s*\)")
SPACING = re.compile(r"\.(?:tracking|kerning)\(\s*([0-9.]+)")
CAPS_LITERAL = re.compile(r'(?:Text\(|title:\s*|label:\s*|String\(localized:\s*)"([A-Z][A-Z0-9 &/\'-]{1,})"')
ORNAMENT_NAME = re.compile(r"\b\w*(?:[Ee]yebrow|[Kk]icker|[Oo]verline)\w*\b")
LEADING_ZERO = re.compile(r'Text\("0[0-9](?:\s*/\s*0[0-9])?"|String\(format: "%0[0-9]+(?:l?l?d|i)"')


def findings(path):
    text = path.read_text(errors="ignore")
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if UPPERCASE_CASE.search(line):
            yield number, "uppercase text case"
        for match in SPACING.finditer(line):
            if float(match.group(1) or 0) > 0:
                yield number, "letter spacing on text"
        for match in CAPS_LITERAL.finditer(line):
            literal = match.group(1)
            if literal in ACRONYMS or (path.name, literal) in ALLOWED:
                continue
            if sum(character.isalpha() for character in literal) >= 2:
                yield number, f'all-caps label "{literal}"'
        # Names in code, not words inside strings such as emoji names.
        if ORNAMENT_NAME.search(re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)):
            yield number, "eyebrow, kicker or overline name"
        if LEADING_ZERO.search(line):
            yield number, "leading-zero ornamental number"


def main():
    problems = []
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob("*.swift")):
            if any(part in str(path) for part in SKIPPED_PARTS):
                continue
            problems += [f"{path}:{number}: {reason}" for number, reason in findings(path)]
    for problem in problems:
        print(problem)
    print(f"{len(problems)} micro-label patterns in the UI sources", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
