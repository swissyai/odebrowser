#!/usr/bin/env python3
"""The complexity check fails on new functions over the limits, not on recorded debt."""

from __future__ import annotations

import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from check_complexity import Measurement, compare, is_measured, main, measurable_swift  # noqa: E402


def measured(function: str, ccn: int, length: int = 10, file: str = "OdeShared/A.swift", line: int = 1) -> Measurement:
    return Measurement(file=file, function=function, line=line, ccn=ccn, length=length)


def verdicts(current: list[Measurement], baseline: list[Measurement]) -> list[tuple[str, bool]]:
    return [(verdict.measurement.function, verdict.is_new) for verdict in compare(current, baseline)]


class BaselineComparisonTests(unittest.TestCase):
    def test_functions_within_the_limits_are_not_listed(self) -> None:
        self.assertEqual(verdicts([measured("small", ccn=15, length=80)], []), [])

    def test_a_function_over_either_limit_without_a_record_is_new(self) -> None:
        self.assertEqual(verdicts([measured("branchy", ccn=16)], []), [("branchy", True)])
        self.assertEqual(verdicts([measured("long", ccn=2, length=81)], []), [("long", True)])

    def test_recorded_debt_passes_until_it_grows(self) -> None:
        baseline = [measured("debt", ccn=30, length=120)]
        self.assertEqual(verdicts([measured("debt", ccn=30, length=120, line=90)], baseline), [("debt", False)])
        self.assertEqual(verdicts([measured("debt", ccn=22, length=95)], baseline), [("debt", False)])
        self.assertEqual(verdicts([measured("debt", ccn=31, length=120)], baseline), [("debt", True)])
        self.assertEqual(verdicts([measured("debt", ccn=30, length=121)], baseline), [("debt", True)])

    def test_a_function_recorded_for_one_limit_is_new_when_it_crosses_the_other(self) -> None:
        baseline = [measured("long", ccn=4, length=120)]
        self.assertEqual(verdicts([measured("long", ccn=15, length=120)], baseline), [("long", False)])
        self.assertEqual(verdicts([measured("long", ccn=16, length=120)], baseline), [("long", True)])

    def test_a_record_belongs_to_its_file_and_signature(self) -> None:
        baseline = [measured("debt", ccn=30)]
        moved = measured("debt", ccn=30, file="OdeMac/B.swift")
        renamed = measured("debt(other)", ccn=30)
        self.assertEqual(verdicts([moved, renamed], baseline), [("debt", True), ("debt(other)", True)])

    def test_each_record_allows_one_function_of_its_signature(self) -> None:
        baseline = [measured("init", ccn=20)]
        current = [measured("init", ccn=18, line=10), measured("init", ccn=19, line=40)]
        results = compare(current, baseline)
        self.assertEqual(sorted((v.measurement.line, v.is_new) for v in results), [(10, True), (40, False)])

    def test_new_functions_are_listed_before_existing_debt(self) -> None:
        baseline = [measured("debt", ccn=30, file="OdeCore/src/A.cs")]
        current = [measured("debt", ccn=30, file="OdeCore/src/A.cs"), measured("fresh", ccn=17, file="Scripts/z.py")]
        self.assertEqual(verdicts(current, baseline), [("fresh", True), ("debt", False)])


class MeasuredFilesTests(unittest.TestCase):
    def test_only_the_measured_sources_count(self) -> None:
        self.assertTrue(is_measured("OdeMac/App/Shell.swift"))
        self.assertTrue(is_measured("OdeCore/src/OdeCore/Domain/Tabs/Tabs.cs"))
        self.assertTrue(is_measured("Scripts/control-plane/tool.py"))
        self.assertFalse(is_measured("OdeTests/ShellTests.swift"))
        self.assertFalse(is_measured("OdeCore/tests/OdeCore.Tests/TabsTests.cs"))
        self.assertFalse(is_measured("OdeShared/Infrastructure/Core/Generated/CoreCodec.generated.swift"))
        self.assertFalse(is_measured("OdeCore/src/OdeCore.Native/Generated/ContractCodec.g.cs"))
        self.assertFalse(is_measured("CrestEngines/Chromium/Apple/Host.swift"))
        self.assertFalse(is_measured("Scripts/pad-mac-app-icon.swift"))


class MeasurableSwiftTests(unittest.TestCase):
    def test_rewrites_keep_every_line_in_place(self) -> None:
        source = textwrap.dedent('''\
            final class Store {
                private(set) var count = 0
                var isEmpty: Bool {
                    count == 0
                }
                var limit: Int { get }
                override init() {
                    super.init()
                    let urls = names.compactMap(URL.init(string:))
                    defaults.set(true, forKey: "k")
                    let script = """
                        state.elements.set(node, uid);
                        """
                }
            }
            ''')
        rewritten = measurable_swift(source)
        self.assertEqual(len(rewritten.split("\n")), len(source.split("\n")))
        lines = rewritten.split("\n")
        self.assertEqual(lines[1].strip(), "private var count = 0")
        self.assertEqual(lines[2].strip(), "func __var_isEmpty() {")
        self.assertEqual(lines[5].strip(), "var limit: Int { get }")
        self.assertEqual(lines[6].strip(), "override init() {")
        self.assertEqual(lines[7].strip(), "super.init_()")
        self.assertIn("URL.init_(string:)", lines[8])
        self.assertIn("defaults.set_(true", lines[9])
        self.assertEqual(lines[10].strip(), 'let script = ""')
        self.assertEqual(lines[11], "")
        self.assertEqual(lines[12].strip(), "")


FAKE_LIZARD = textwrap.dedent('''\
    import sys
    rows = [
        '20,18,100,1,22,"long@1-22@OdeShared/A.swift","OdeShared/A.swift","long","long ( )",1,22',
        '5,2,30,0,5,"small@30-34@OdeShared/A.swift","OdeShared/A.swift","small","small ( )",30,34',
        '90,40,500,2,95,"debt@40-134@OdeShared/A.swift","OdeShared/A.swift","debt","debt a , b",40,134',
    ]
    print("\\n".join(rows))
    ''')


class CommandLineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        (self.root / "OdeShared").mkdir()
        (self.root / "OdeShared/A.swift").write_text("func long() {}\n")
        fake = self.root / "fake_lizard.py"
        fake.write_text(FAKE_LIZARD)
        self.lizard = f"{sys.executable} {fake}"
        self.baseline = self.root / "baseline.json"

    def tearDown(self) -> None:
        self.directory.cleanup()

    def run_check(self, *arguments: str) -> tuple[int, str]:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = main(["--root", str(self.root), "--lizard", self.lizard, "--baseline", str(self.baseline),
                           *arguments])
        return status, output.getvalue()

    def test_recorded_debt_passes_and_a_new_function_fails(self) -> None:
        self.baseline.write_text(json.dumps({"functions": [
            {"file": "OdeShared/A.swift", "function": "debt a , b", "ccn": 40, "length": 95}]}))
        status, output = self.run_check("OdeShared/A.swift")
        self.assertEqual(status, 1)
        self.assertIn("new       OdeShared/A.swift:1  long ( )  CCN 18, 22 lines", output)
        self.assertIn("existing  OdeShared/A.swift:40  debt a , b  CCN 40, 95 lines", output)
        self.assertIn("1 new and 1 existing", output)

    def test_a_written_baseline_records_every_function_over_the_limits(self) -> None:
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "OdeShared/A.swift"], cwd=self.root, check=True)
        status, _ = self.run_check("--write-baseline")
        self.assertEqual(status, 0)
        recorded = json.loads(self.baseline.read_text())
        self.assertEqual(recorded["limits"], {"ccn": 15, "length": 80})
        self.assertEqual([entry["function"] for entry in recorded["functions"]], ["debt a , b", "long ( )"])
        status, output = self.run_check("OdeShared/A.swift")
        self.assertEqual(status, 0, output)

    def test_without_uvx_the_shell_check_passes_with_a_note(self) -> None:
        environment = {key: value for key, value in os.environ.items() if key != "ODE_LIZARD"}
        environment["PATH"] = "/usr/bin:/bin"
        result = subprocess.run(["/bin/zsh", str(REPOSITORY_ROOT / "Scripts/check-complexity.sh"), "--base", "HEAD"],
                                env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("brew install uv", result.stdout)


if __name__ == "__main__":
    unittest.main()
