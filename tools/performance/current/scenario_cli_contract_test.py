"""Pure argv contracts; does not launch Godot, create inputs or measure a game."""
import ast
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

import campaign160
import paired160


def arguments(**changes):
    values = dict(scenario=None, main_thread_policy="app", worker_tasks=4,
                  profile_stages=False, require_coverage=False, smoke=False,
                  engine=Path("engine.exe"), input=Path("input.bin"),
                  prefix_steps=1000, sample_steps=6000)
    values.update(changes)
    return SimpleNamespace(**values)


class ScenarioCliContract(unittest.TestCase):
    def test_both_parsers_leave_generic_default_unspecified(self):
        for module in (campaign160, paired160):
            with self.subTest(module=module.__name__):
                tree = ast.parse(Path(module.__file__).read_text(encoding="utf-8"))
                calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                         and isinstance(node.func, ast.Attribute) and node.func.attr == "add_argument"
                         and node.args and isinstance(node.args[0], ast.Constant)
                         and node.args[0].value == "--scenario"]
                self.assertEqual(len(calls), 1)
                default = next((key.value for key in calls[0].keywords if key.arg == "default"), ast.Constant(None))
                self.assertIsNone(ast.literal_eval(default))

    def test_campaign_generic_command_matches_original_complete_argv(self):
        command = campaign160.build_engine_command(Path("project"), Path("engine.exe"),
                                                   Path("input.bin"), Path("result.json"), 1000, 6000,
                                                   arguments())
        self.assertEqual(command, ["engine.exe", "--headless", "--path", "project", "--script",
                                  "res://tools/performance/current/plain_v4.gd", "--",
                                  "--input=input.bin", "--output=result.json", "--prefix-steps=1000",
                                  "--steps=6000", "--observed-floor=1", "--main-thread-policy=app",
                                  "--worker-tasks=4"])

    def test_each_explicit_campaign_row_adds_only_its_expected_gate(self):
        generic = campaign160.build_engine_command(Path("p"), Path("e"), Path("i"), Path("o"),
                                                   1000, 6000, arguments())
        for scenario in campaign160.SCENARIOS:
            with self.subTest(scenario=scenario):
                actual = campaign160.build_engine_command(Path("p"), Path("e"), Path("i"), Path("o"),
                                                          1000, 6000, arguments(scenario=scenario))
                self.assertEqual(actual, generic + [f"--expected-scenario={scenario}"])

    def test_profile_coverage_worker_and_window_are_retained(self):
        command = campaign160.build_engine_command(Path("p"), Path("e"), Path("i"), Path("o"),
                                                   1000, 6000, arguments(profile_stages=True, require_coverage=True))
        self.assertEqual(command[-2:], ["--profile-stages", "--require-coverage"])
        self.assertIn("--prefix-steps=1000", command)
        self.assertIn("--steps=6000", command)
        self.assertIn("--worker-tasks=4", command)
        self.assertFalse(any(value.startswith("--expected-scenario") for value in command))

    def test_smoke_retains_two_real_steps_without_coverage_claim(self):
        command = campaign160.build_engine_command(Path("p"), Path("e"), Path("i"), Path("o"), 0, 2,
                                                   arguments(smoke=True, require_coverage=True))
        self.assertIn("--prefix-steps=0", command)
        self.assertIn("--steps=2", command)
        self.assertNotIn("--require-coverage", command)

    def test_paired_default_command_matches_original_complete_argv(self):
        args = arguments()
        actual = paired160.build_campaign_command(Path("A"), Path("A1"), 1, args)
        self.assertEqual(actual, [sys.executable, "-X", "utf8", "-B",
                                  str(Path("A") / "tools/performance/current/campaign160.py"),
                                  "--engine", str(args.engine.resolve()), "--input", str(args.input.resolve()),
                                  "--output", "A1", "--repeat-number", "1", "--prefix-steps", "1000",
                                  "--sample-steps", "6000"])

    def test_each_paired_explicit_row_is_forwarded_unchanged(self):
        generic = paired160.build_campaign_command(Path("A"), Path("A1"), 1, arguments())
        for scenario in campaign160.SCENARIOS:
            with self.subTest(scenario=scenario):
                command = paired160.build_campaign_command(Path("A"), Path("A1"), 1,
                                                           arguments(scenario=scenario))
                self.assertEqual(command, generic + ["--scenario", scenario])

    def test_paired_keeps_flags_and_explicit_outcome_reference(self):
        command = paired160.build_campaign_command(Path("B"), Path("B2"), 2,
                                                   arguments(profile_stages=True, require_coverage=True), Path("A1"))
        self.assertEqual(command[-4:], ["--profile-stages", "--require-coverage", "--outcome-reference", "A1"])
        self.assertNotIn("--scenario", command)


if __name__ == "__main__":
    unittest.main(verbosity=2)
