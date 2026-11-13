#!/usr/bin/env python3
"""List functions over the complexity limits and fail on new ones.

Measures every function's cyclomatic complexity (CCN) and length in lines
with lizard over the Swift app and shared modules, the C# core and the
Python scripts. A function is over the limits when its CCN exceeds 15 or it
spans more than 80 lines. `complexity-baseline.json` beside this script
records the functions that were over the limits when it was written: they
are listed as existing debt and pass while neither number grows past its
recorded value. A function over the limits that the baseline does not
record, or that grew past its record, is new and fails the check.

lizard's Swift reader misreads some ordinary Swift: it takes `URL.init`,
`super.init(...)`, `defaults.set(...)`, `private(set)` and a value named
`set` for declarations, which swallows or splits the functions around them;
it reads JavaScript held in multi-line string literals as Swift; and it
skips computed properties, SwiftUI's `body` among them. Swift files are
therefore measured from a copy that keeps every line where it was, with
those names renamed, multi-line string contents blanked and each computed
property declared as a function, which the listing names `var <name>`.

Usage:
  Scripts/check_complexity.py --lizard COMMAND [--base GIT_REF] [-- PATH ...]
  Scripts/check_complexity.py --lizard COMMAND --all
  Scripts/check_complexity.py --lizard COMMAND --write-baseline

Without `--all` it measures the files changed against `--base` (as
`GIT_REF...HEAD`) plus uncommitted and untracked changes, or the paths after
`--`. `Scripts/check-complexity.sh` supplies the lizard command. Exits 1 when
a new function is over the limits, 2 when measuring fails.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import fnmatch
import io
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import tempfile
from collections import defaultdict
from collections.abc import Iterable, Sequence


SCRIPT_ROOT = pathlib.Path(__file__).resolve().parent
DEFAULT_BASELINE = SCRIPT_ROOT / "complexity-baseline.json"
CCN_LIMIT = 15
LENGTH_LIMIT = 80
MEASURED_ROOTS = {
    ".swift": ("OdeShared", "OdeMac", "OdeMobile", "OdeNative", "OdeAgents", "OdeAgentHelper"),
    ".cs": ("OdeCore/src",),
    ".py": ("Scripts",),
}
GENERATED = ("*/Generated/*", "*.generated.swift", "*.g.cs")
COMPUTED_PREFIX = "__var_"

_MULTILINE_OPENING = re.compile(r'(#*)"""\s*$')
_SETTER_ACCESS = re.compile(r"\(set\)")
_MEMBER_KEYWORD = re.compile(r"\.(init|get|set|willSet|didSet)\b")
_ACCESSOR_NAMED_VALUE = re.compile(r"(?<![\w.])(get|set)\b(?=\s*(?:=(?!=)|:|\.|,|\)|\]))")
_COMPUTED_PROPERTY = re.compile(
    r"^(?P<indent>\s*)(?:@[\w.]+(?:\([^)]*\))?\s+|\w+(?:\(\w+\))?\s+)*var\s+`?(?P<name>\w+)`?\s*:"
    r"\s*[^={}]+?\{(?P<rest>.*)$"
)
_ACCESSOR = re.compile(r"^\s*(get|set|willSet|didSet|_read|_modify)\b")


# MARK: - Types


@dataclasses.dataclass(frozen=True)
class Measurement:
    """One function as lizard measured it; `function` is its signature."""

    file: str
    function: str
    line: int
    ccn: int
    length: int

    @property
    def over_limits(self) -> bool:
        return self.ccn > CCN_LIMIT or self.length > LENGTH_LIMIT

    @property
    def key(self) -> tuple[str, str]:
        return self.file, self.function

    def describe(self) -> str:
        return f"{self.file}:{self.line}  {self.function}  CCN {self.ccn}, {self.length} lines"


@dataclasses.dataclass(frozen=True)
class Verdict:
    """A function over the limits and whether the baseline already allows it."""

    measurement: Measurement
    recorded: Measurement | None

    @property
    def is_new(self) -> bool:
        if self.recorded is None:
            return True
        grew_ccn = self.measurement.ccn > max(self.recorded.ccn, CCN_LIMIT)
        grew_length = self.measurement.length > max(self.recorded.length, LENGTH_LIMIT)
        return grew_ccn or grew_length

    def line(self) -> str:
        label = "new     " if self.is_new else "existing"
        text = f"{label}  {self.measurement.describe()}"
        if self.recorded is not None:
            text += f"  (baseline CCN {self.recorded.ccn}, {self.recorded.length} lines)"
        return text


# MARK: - Selecting files


def is_measured(path: str) -> bool:
    """Whether `path`, relative to the repository root, is a measured source file."""
    roots = MEASURED_ROOTS.get(pathlib.PurePosixPath(path).suffix)
    if roots is None or not any(path.startswith(root + "/") for root in roots):
        return False
    return not any(fnmatch.fnmatchcase(path, pattern) for pattern in GENERATED)


def git_paths(root: pathlib.Path, *arguments: str) -> list[str]:
    output = subprocess.run(
        ["git", *arguments], cwd=root, check=True, capture_output=True, text=True
    ).stdout
    return [path for path in output.split("\0") if path]


def changed_paths(root: pathlib.Path, base: str | None) -> list[str]:
    paths: list[str] = []
    if base is not None:
        paths += git_paths(root, "diff", "--name-only", "-z", "--diff-filter=ACMR", f"{base}...HEAD")
    paths += git_paths(root, "diff", "--name-only", "-z", "--diff-filter=ACMR")
    paths += git_paths(root, "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR")
    paths += git_paths(root, "ls-files", "--others", "--exclude-standard", "-z")
    return paths


def selected(root: pathlib.Path, paths: Iterable[str]) -> list[str]:
    return sorted({path for path in paths if is_measured(path) and (root / path).is_file()})


# MARK: - Measuring


def measurable_swift(text: str) -> str:
    """Rewrites Swift so lizard reads every function, keeping each line in place."""
    lines = text.split("\n")
    output: list[str] = []
    closing: str | None = None
    for index, line in enumerate(lines):
        if closing is not None:
            content = line.lstrip()
            if not content.startswith(closing):
                output.append("")
                continue
            line = line[: len(line) - len(content)] + content[len(closing) :]
            closing = None
        opening = _MULTILINE_OPENING.search(line)
        if opening is not None:
            closing = '"""' + opening.group(1)
            line = line[: opening.start()] + '""'
        line = _SETTER_ACCESS.sub("", line)
        line = _MEMBER_KEYWORD.sub(lambda match: "." + match.group(1) + "_", line)
        line = _ACCESSOR_NAMED_VALUE.sub(lambda match: match.group(1) + "_", line)
        output.append(_computed_property_as_function(line, lines[index + 1 :]))
    return "\n".join(output)


def _computed_property_as_function(line: str, following: Sequence[str]) -> str:
    declaration = _COMPUTED_PROPERTY.match(line)
    if declaration is None:
        return line
    rest = declaration.group("rest")
    first = rest if rest.strip() else next((candidate for candidate in following if candidate.strip()), "")
    if _ACCESSOR.match(first):
        return line
    return f"{declaration.group('indent')}func {COMPUTED_PREFIX}{declaration.group('name')}() {{{rest}"


def function_name(long_name: str) -> str:
    name = " ".join(long_name.split())
    if name.startswith(COMPUTED_PREFIX):
        return "var " + name[len(COMPUTED_PREFIX) :].split(" ", 1)[0]
    return name


def parse_lizard_csv(text: str) -> list[Measurement]:
    measurements = []
    for row in csv.reader(io.StringIO(text)):
        if len(row) < 11 or not row[1].isdigit():
            continue
        if row[7] == "*global*":
            continue
        measurements.append(
            Measurement(
                file=row[6],
                function=function_name(row[8]),
                line=int(row[9]),
                ccn=int(row[1]),
                length=int(row[4]),
            )
        )
    return measurements


def measure(root: pathlib.Path, paths: Sequence[str], lizard: Sequence[str]) -> list[Measurement]:
    """Measures `paths` from a scratch copy, the Swift files rewritten for lizard."""
    if not paths:
        return []
    with tempfile.TemporaryDirectory(prefix="ode-complexity.") as scratch:
        scratch_root = pathlib.Path(scratch)
        for path in paths:
            text = (root / path).read_text(encoding="utf-8", errors="replace")
            if path.endswith(".swift"):
                text = measurable_swift(text)
            target = scratch_root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
        listing = scratch_root / ".lizard-files"
        listing.write_text("\n".join(paths) + "\n", encoding="utf-8")
        threads = str(min(8, os.cpu_count() or 1))
        result = subprocess.run(
            [*lizard, "--csv", "-t", threads, "-f", str(listing)],
            cwd=scratch_root,
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        raise RuntimeError(f"lizard failed with status {result.returncode}: {result.stderr.strip()}")
    return parse_lizard_csv(result.stdout)


# MARK: - Comparing with the baseline


def load_baseline(path: pathlib.Path) -> list[Measurement]:
    document = json.loads(path.read_text(encoding="utf-8"))
    return [
        Measurement(file=entry["file"], function=entry["function"], line=0, ccn=entry["ccn"], length=entry["length"])
        for entry in document["functions"]
    ]


def baseline_document(measurements: Iterable[Measurement]) -> dict:
    over = sorted((m for m in measurements if m.over_limits), key=lambda m: (m.file, m.function, -m.ccn, -m.length))
    return {
        "limits": {"ccn": CCN_LIMIT, "length": LENGTH_LIMIT},
        "functions": [
            {"file": m.file, "function": m.function, "ccn": m.ccn, "length": m.length} for m in over
        ],
    }


def compare(measurements: Iterable[Measurement], baseline: Iterable[Measurement]) -> list[Verdict]:
    """Pairs each function over the limits with the baseline entry that allows it.

    Functions sharing a file and signature, such as same-named initialisers of
    nested types, pair with that signature's entries largest first, so each
    entry allows at most one function.
    """
    recorded: dict[tuple[str, str], list[Measurement]] = defaultdict(list)
    for entry in baseline:
        recorded[entry.key].append(entry)
    for entries in recorded.values():
        entries.sort(key=lambda m: (m.ccn, m.length), reverse=True)
    over: dict[tuple[str, str], list[Measurement]] = defaultdict(list)
    for measurement in measurements:
        if measurement.over_limits:
            over[measurement.key].append(measurement)
    verdicts = []
    for key, functions in over.items():
        functions.sort(key=lambda m: (m.ccn, m.length), reverse=True)
        entries = recorded.get(key, [])
        for index, function in enumerate(functions):
            verdicts.append(Verdict(function, entries[index] if index < len(entries) else None))
    verdicts.sort(key=lambda v: (not v.is_new, v.measurement.file, v.measurement.line))
    return verdicts


# MARK: - Command line


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="List functions over the complexity limits; fail on new ones.")
    parser.add_argument("--lizard", required=True, help="command that runs lizard 1.24.0, such as 'uvx lizard==1.24.0'")
    parser.add_argument("--root", type=pathlib.Path, default=SCRIPT_ROOT.parent, help="repository root")
    parser.add_argument("--baseline", type=pathlib.Path, default=DEFAULT_BASELINE, help="baseline JSON")
    parser.add_argument("--base", help="also measure files changed in GIT_REF...HEAD")
    parser.add_argument("--all", action="store_true", help="measure every tracked source file")
    parser.add_argument("--write-baseline", action="store_true", help="measure every file and rewrite the baseline")
    parser.add_argument("paths", nargs="*", help="measure these paths instead of the changed files")
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(sys.argv[1:] if arguments is None else arguments)
    root = options.root.resolve()
    lizard = shlex.split(options.lizard)
    try:
        if options.all or options.write_baseline:
            paths = selected(root, git_paths(root, "ls-files", "-z"))
        elif options.paths:
            paths = selected(root, options.paths)
        else:
            paths = selected(root, changed_paths(root, options.base))
        measurements = measure(root, paths, lizard)
        if options.write_baseline:
            document = baseline_document(measurements)
            options.baseline.write_text(json.dumps(document, indent=1) + "\n", encoding="utf-8")
            print(f"Recorded {len(document['functions'])} functions over the limits from {len(paths)} files.")
            return 0
        verdicts = compare(measurements, load_baseline(options.baseline))
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    for verdict in verdicts:
        print(verdict.line())
    new = sum(verdict.is_new for verdict in verdicts)
    print(
        f"Measured {len(measurements)} functions in {len(paths)} files: {new} new and "
        f"{len(verdicts) - new} existing over CCN {CCN_LIMIT} or {LENGTH_LIMIT} lines."
    )
    if new:
        print(
            "Split the new ones, or, when moving existing debt, rewrite the baseline with "
            "Scripts/check-complexity.sh --write-baseline and explain the change."
        )
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
