#!/usr/bin/env python3
"""The release gate over a harnessed run's moments summary."""

from __future__ import annotations

import contextlib
import copy
import io
import json
import pathlib
import sys
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from check_moment_budgets import DEFAULT_GATES, evaluate, load_gates, main  # noqa: E402


def statistics(count: int, median: float, p95: float, maximum: float) -> dict[str, float]:
    return {"count": count, "median": median, "p95": p95, "max": maximum}


PASSING = {
    "version": 1,
    "moments": {
        "tabSwitch": {
            "count": 100, "recent": 100, "median": 60, "p95": 900, "max": 1400,
            "counters": {"blankFrames": 0, "undrawn": 0},
            "tags": {"slept=false": statistics(90, 40, 120, 149), "slept=true": statistics(10, 700, 1400, 1400)},
        },
        "commandBarOpen": {
            "count": 90, "recent": 90, "median": 40, "p95": 60, "max": 80, "counters": {}, "tags": {},
        },
        "commandBarReturn": {
            "count": 30, "recent": 30, "median": 90, "p95": 280, "max": 290, "counters": {}, "tags": {},
        },
        "sessionRestore": {
            "count": 50, "recent": 50, "median": 900, "p95": 1200, "max": 1300,
            "counters": {"differences": 0}, "tags": {},
        },
        "launchWarm": {
            "count": 30, "recent": 30, "median": 500, "p95": 1900, "max": 1950, "counters": {}, "tags": {},
        },
        "wake": {
            "count": 60, "recent": 60, "median": 300, "p95": 1800, "max": 1900,
            "counters": {"typedTextSlept": 0}, "tags": {},
        },
    },
}


class MomentBudgetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.gates = load_gates(DEFAULT_GATES)

    def run_main(self, summary: dict, *extra: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "moments.json"
            path.write_text(json.dumps(summary))
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = main([str(path), *extra])
        return code, output.getvalue()

    def test_the_committed_table_holds_the_release_ceilings(self) -> None:
        ceilings = {gate.label: gate.ceiling for gate in self.gates}
        self.assertEqual(
            ceilings,
            {
                "tabSwitch[slept=false].p95": 150,
                "tabSwitch.blankFrames": 0,
                "commandBarOpen.p95": 100,
                "commandBarReturn.p95": 300,
                "sessionRestore.differences": 0,
                "launchWarm.p95": 2000,
                "wake.p95": 2000,
                "wake.typedTextSlept": 0,
                "hang.count": 0,
            },
        )

    def test_a_run_within_every_ceiling_passes(self) -> None:
        code, output = self.run_main(PASSING)
        self.assertEqual(code, 0, output)
        self.assertIn("9 of 9 gates pass", output)
        self.assertTrue(all(result.passed for result in evaluate(PASSING, self.gates)))

    def test_a_slow_switch_to_a_loaded_tab_misses_while_a_slow_wake_does_not_count_against_it(self) -> None:
        summary = copy.deepcopy(PASSING)
        summary["moments"]["tabSwitch"]["tags"]["slept=false"]["p95"] = 151
        code, output = self.run_main(summary)
        self.assertEqual(code, 1)
        self.assertIn("MISS  tabSwitch[slept=false].p95", output)

    def test_any_correctness_counter_above_zero_misses(self) -> None:
        for moment, counter in (
            ("tabSwitch", "blankFrames"),
            ("sessionRestore", "differences"),
            ("wake", "typedTextSlept"),
        ):
            summary = copy.deepcopy(PASSING)
            summary["moments"][moment]["counters"][counter] = 1
            with self.subTest(counter=counter):
                self.assertEqual(self.run_main(summary)[0], 1)

    def test_one_hang_misses(self) -> None:
        summary = copy.deepcopy(PASSING)
        summary["moments"]["hang"] = {
            "count": 1, "recent": 1, "median": 300, "p95": 300, "max": 300, "counters": {}, "tags": {},
        }
        code, output = self.run_main(summary)
        self.assertEqual(code, 1)
        self.assertIn("MISS  hang.count", output)

    def test_a_moment_never_measured_misses_unless_the_run_allows_it(self) -> None:
        summary = copy.deepcopy(PASSING)
        del summary["moments"]["launchWarm"]
        code, output = self.run_main(summary)
        self.assertEqual(code, 1)
        self.assertIn("launchWarm.p95", output)
        self.assertIn("not measured", output)
        self.assertEqual(self.run_main(summary, "--allow-missing")[0], 0)

    def test_an_unreadable_summary_is_an_error_not_a_pass(self) -> None:
        self.assertEqual(self.run_main({"version": 2, "moments": {}})[0], 2)
        with tempfile.TemporaryDirectory() as folder:
            missing = pathlib.Path(folder) / "missing.json"
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(main([str(missing)]), 2)


if __name__ == "__main__":
    unittest.main()
