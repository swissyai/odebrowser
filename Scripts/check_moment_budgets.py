#!/usr/bin/env python3
"""Check a moments summary from a harnessed run against the release ceilings.

The summary is the JSON the test harness's `moments` command answers, as
`tools/dev/ode-harness.py moments` writes it: per moment, the count of every
moment recorded, the median, 95th percentile and longest of the recent ones,
the same statistics per tag, and the moment's counters. The ceilings are in
`moment-budgets.json` beside this script. Each gate names a moment and either
a statistic, optionally of the samples carrying one tag, or a counter, and
the most it may be. A statistic with no samples is a miss unless
`--allow-missing`, which reports it and passes; a counter or a count never
recorded is zero.

Usage:
  Scripts/check_moment_budgets.py SUMMARY.json [--gates PATH] [--allow-missing]

Prints one line per gate and exits 1 when any gate misses, 2 when the input
cannot be read.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import pathlib
import sys
from collections.abc import Sequence
from typing import Any


DEFAULT_GATES = pathlib.Path(__file__).resolve().with_name("moment-budgets.json")
STATISTICS = ("count", "median", "p95", "max")


@dataclasses.dataclass(frozen=True)
class Gate:
    moment: str
    ceiling: float
    statistic: str | None = None
    tag: str | None = None
    counter: str | None = None

    @property
    def label(self) -> str:
        measure = self.counter or self.statistic or ""
        return f"{self.moment}{'[' + self.tag + ']' if self.tag else ''}.{measure}"

    @staticmethod
    def from_json(entry: dict[str, Any]) -> "Gate":
        statistic = entry.get("statistic")
        counter = entry.get("counter")
        if (statistic is None) == (counter is None):
            raise ValueError(f"A gate names a statistic or a counter: {entry}")
        if statistic is not None and statistic not in STATISTICS:
            raise ValueError(f"Unknown statistic {statistic!r}")
        if counter is not None and entry.get("tag") is not None:
            raise ValueError(f"A counter has no tags: {entry}")
        return Gate(
            moment=str(entry["moment"]),
            ceiling=float(entry["ceiling"]),
            statistic=statistic,
            tag=entry.get("tag"),
            counter=counter,
        )


@dataclasses.dataclass(frozen=True)
class Result:
    gate: Gate
    value: float | None
    passed: bool

    def line(self) -> str:
        value = "not measured" if self.value is None else f"{self.value:g}"
        verdict = "pass" if self.passed else "MISS"
        return f"{verdict:<5} {self.gate.label:<40} {value:>14} <= {self.gate.ceiling:g}"


def load_gates(path: pathlib.Path) -> list[Gate]:
    table = json.loads(path.read_text())
    if table.get("version") != 1:
        raise ValueError(f"{path} is not a version 1 gate table")
    return [Gate.from_json(entry) for entry in table["gates"]]


def measure(summary: dict[str, Any], gate: Gate) -> float | None:
    """The gate's value in the summary, or None when nothing was measured."""
    moment = summary.get("moments", {}).get(gate.moment)
    if gate.counter is not None:
        return float((moment or {}).get("counters", {}).get(gate.counter, 0))
    if gate.tag is not None:
        values = (moment or {}).get("tags", {}).get(gate.tag)
        if values is None:
            return 0.0 if gate.statistic == "count" else None
        return float(values[gate.statistic])
    if moment is None:
        return 0.0 if gate.statistic == "count" else None
    value = moment.get(gate.statistic)
    return None if value is None else float(value)


def evaluate(summary: dict[str, Any], gates: Sequence[Gate], *, allow_missing: bool = False) -> list[Result]:
    if summary.get("version") != 1:
        raise ValueError("The summary is not a version 1 moments summary")
    results = []
    for gate in gates:
        value = measure(summary, gate)
        passed = allow_missing if value is None else value <= gate.ceiling
        results.append(Result(gate=gate, value=value, passed=passed))
    return results


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("summary", type=pathlib.Path)
    parser.add_argument("--gates", type=pathlib.Path, default=DEFAULT_GATES)
    parser.add_argument("--allow-missing", action="store_true")
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(sys.argv[1:] if arguments is None else arguments)
    try:
        summary = json.loads(options.summary.read_text())
        results = evaluate(summary, load_gates(options.gates), allow_missing=options.allow_missing)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    for result in results:
        print(result.line())
    missed = [result for result in results if not result.passed]
    print(f"{len(results) - len(missed)} of {len(results)} gates pass")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
