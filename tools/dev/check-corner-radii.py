#!/usr/bin/env python3
"""Fail when the app's UI sources set corner radii outside Ode's corner scale.

Ode's corners come from OdeCornerScale (and OdeRadius, which draws on it):
radii worked out from the window's own corner so nested shapes stay
concentric, every corner continuous, and pills drawn as capsules. This check
scans the Swift UI sources (not tests, generated code or fixtures) for:

- a numeric radius at a call site, such as `cornerRadius: 12`;
- a numeric corner constant, such as `static let rowCornerRadius: CGFloat = 10`;
- an explicit `.circular` corner style;
- the deprecated `.cornerRadius(_:)` modifier, which clips circular corners;
- an AppKit layer corner in a file that never sets `cornerCurve = .continuous`.

`RoundedRectangle(cornerRadius:)` and `.rect(cornerRadius:)` default to the
continuous style, so they need no explicit style. A radius of 0 is a square
corner and passes, and a constant below 1 or named as a ratio is a
proportion of the element's own size, such as an icon tile's corner.
ALLOWED lists the few remaining literals, each with its reason.
"""

import pathlib
import re
import sys

# The Chromium engine's Swift host draws Ode's surfaces too; its C++ overlay
# is the prebuilt engine's and changes only with an engine build.
ROOTS = ("OdeMac", "OdeShared", "OdeMobile", "CrestEngines/Chromium/Apple")
SKIPPED_PARTS = ("/Generated/", "/Seeds/", "/Fixtures/", "Tests/")
TOKEN_FILES = {
    "OdeShared/DesignSystem/Tokens/OdeCornerScale.swift",
    "OdeShared/DesignSystem/Tokens/OdeRadius.swift",
}
ALLOWED = {
    # A favicon's corner never drops below this at very small sizes, where
    # its size-relative corner would round to nothing.
    ("TabFaviconMetrics.swift", "minimumCornerRadius"),
    # A Peek sheet fills a phone's screen inside its safe area, where the
    # card's corner answers the screen's rather than a window's.
    ("BrowserTransientCardArrangement.swift", "cardCornerRadius"),
}
NUMBER = r"[0-9]+(?:\.[0-9]+)?"
# Any argument naming a corner radius, `cardCornerRadius: 15` as well as
# `cornerRadius: 12`.
CALL_SITE = re.compile(rf"\b(\w*[Cc]ornerRadius):\s*({NUMBER})\b(?!\s*[*/+-])")
# Shadow, blur and motion radii are not corners; only names that say corner count.
CONSTANT = re.compile(
    rf"\b(?:static\s+)?(?:let|var)\s+(\w*[Cc]orner\w*)\s*(?::\s*CGFloat)?\s*=\s*({NUMBER})\s*$")
# Proportions of an element's own size (an icon's or a tile's), and values
# that are not radii at all.
PROPORTION = re.compile(r"Ratio|Fraction|Scale|Divisor|Tolerance|Clearance")
CIRCULAR = re.compile(r"\.circular\b")
# The SwiftUI modifier takes one unlabeled radius; methods of the app named
# cornerRadius take labeled arguments.
MODIFIER = re.compile(r"\.cornerRadius\((?!\s*\w+\s*:)(?!\s*$)")
# A corner set on a Core Animation layer: `layer.cornerRadius =` or a layer
# property such as `highlight.cornerRadius =` in a file that uses CALayer.
LAYER_CORNER = re.compile(r"\b(?:layer\??|\w*[Ll]ayer\??|highlight\??)\.cornerRadius\s*=")
# A layer corner may take its curve from a token, as long as the file sets one.
CONTINUOUS_CURVE = re.compile(r"cornerCurve\s*=\s*(?:\.continuous|\w+\.layerCornerCurve)")


def findings(path):
    text = path.read_text(errors="ignore")
    continuous_layers = bool(CONTINUOUS_CURVE.search(text))
    for number, line in enumerate(text.splitlines(), 1):
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line.split("//", 1)[0])
        if not code.strip():
            continue
        for match in CALL_SITE.finditer(code):
            if float(match.group(2)) != 0 and (path.name, match.group(1)) not in ALLOWED:
                yield number, f"numeric corner radius {match.group(1)}: {match.group(2)}"
        match = CONSTANT.search(code)
        if match and float(match.group(2)) >= 1 and not PROPORTION.search(match.group(1)):
            if (path.name, match.group(1)) not in ALLOWED:
                yield number, f"numeric radius constant {match.group(1)} = {match.group(2)}"
        if CIRCULAR.search(code) and ("RoundedRectangle" in code or "rect(" in code or "style:" in code):
            yield number, "circular corner style"
        if MODIFIER.search(code):
            yield number, "deprecated .cornerRadius modifier"
        if LAYER_CORNER.search(code) and "CALayer" in text and not continuous_layers:
            yield number, "layer corner without cornerCurve = .continuous"


def main():
    problems = []
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob("*.swift")):
            if any(part in str(path) for part in SKIPPED_PARTS) or str(path) in TOKEN_FILES:
                continue
            problems += [f"{path}:{number}: {reason}" for number, reason in findings(path)]
    for problem in problems:
        print(problem)
    print(f"{len(problems)} corners outside Ode's corner scale", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
