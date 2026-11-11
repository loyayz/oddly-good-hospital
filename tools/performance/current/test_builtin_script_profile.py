"""Offline diagnostic-witness contracts; opaque files are not gameplay fixtures."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from prepare_builtin_script_profile import COVERAGE_FAILURE, validate_diagnostic_witness

INPUT = "1" * 64


class DiagnosticWitnessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="builtin-profile-offline-")
        self.addCleanup(self.temporary.cleanup)
        self.result = Path(self.temporary.name) / "r1.json"
        self.final = Path(str(self.result) + ".final.bin")
        self.payload = b"Opaque offline SHA fixture; no simulated facts are claimed."
        self.final.write_bytes(self.payload)
        self.data = {
            "complete": True, "errors": [], "source_input_sha256": INPUT,
            "requested_prefix_steps": 1000, "requested_sample_steps": 6000,
            "all_completed_steps": 7000, "metrics": {"count": 6000},
            "initial": {"tick": 633}, "final": {"tick": 7633},
            "final_sha256": hashlib.sha256(self.payload).hexdigest(),
            "sample_business": {"comprehensive": {
                "coverage_pass": True, "uncovered": [], "errors": [],
                "invariant_failure_counts": {},
                "coverage": {"gp": {"covered": True, "actual": 2, "lower_bound": 1},
                             "examination": {"covered": True, "actual": 1, "lower_bound": 1}},
            }},
        }

    def coverage_failure(self):
        data = copy.deepcopy(self.data)
        data.update(complete=False, errors=[COVERAGE_FAILURE])
        observer = data["sample_business"]["comprehensive"]
        observer.update(coverage_pass=False, uncovered=["examination"], errors=["No measured activity: examination"])
        observer["coverage"]["examination"].update(covered=False, actual=0)
        return data

    def validate(self, data):
        self.result.write_text(json.dumps(data), encoding="utf-8")
        return validate_diagnostic_witness(self.result, INPUT)

    def rejected(self, data):
        with self.assertRaises((AssertionError, KeyError)):
            self.validate(data)

    def test_complete_pass(self):
        result = self.validate(self.data)
        self.assertTrue(result["complete_execution_witness"])
        self.assertTrue(result["coverage_pass"])
        self.assertIsNone(result["acceptance_pass"])

    def test_only_coverage_failure_is_preserved(self):
        data = self.coverage_failure()
        result = self.validate(data)
        self.assertFalse(result["source_result_complete"])
        self.assertFalse(result["coverage_pass"])
        self.assertEqual(result["errors"], data["errors"])
        self.assertEqual(result["uncovered"], ["examination"])
        self.assertEqual(result["comprehensive_errors"], ["No measured activity: examination"])
        self.assertIsNone(result["acceptance_pass"])

    def test_short_or_wrong_window_rejected(self):
        for key, value in [("all_completed_steps", 6999), ("requested_prefix_steps", 999),
                           ("requested_sample_steps", 5999), ("requested_sample_steps", True)]:
            with self.subTest(key=key, value=value):
                data = self.coverage_failure()
                data[key] = value
                self.rejected(data)

    def test_wrong_metrics_or_actual_final_tick_rejected(self):
        for section, key, value in [("metrics", "count", 5999), ("final", "tick", 7632), ("initial", "tick", True)]:
            with self.subTest(section=section, key=key):
                data = self.coverage_failure()
                data[section][key] = value
                self.rejected(data)

    def test_wrong_input_rejected(self):
        data = self.coverage_failure()
        data["source_input_sha256"] = "2" * 64
        self.rejected(data)

    def test_different_or_additional_top_error_rejected(self):
        for errors in [["Unexpected tick increment"], [COVERAGE_FAILURE, "Other error"], [], [COVERAGE_FAILURE + " "]]:
            with self.subTest(errors=errors):
                data = self.coverage_failure()
                data["errors"] = errors
                self.rejected(data)

    def test_business_invariant_rejected(self):
        for base in [self.data, self.coverage_failure()]:
            data = copy.deepcopy(base)
            data["sample_business"]["comprehensive"]["invariant_failure_counts"] = {"invalid_owner": 1}
            self.rejected(data)

    def test_missing_final_binary_rejected(self):
        self.final.unlink()
        self.rejected(self.coverage_failure())

    def test_changed_final_binary_rejected(self):
        self.final.write_bytes(self.payload + b"changed")
        self.rejected(self.coverage_failure())

    def test_wrong_declared_binary_sha_rejected(self):
        data = self.coverage_failure()
        data["final_sha256"] = "0" * 64
        self.rejected(data)

    def test_forged_uncovered_rejected(self):
        for uncovered in [[], ["unknown"], ["gp"], ["examination", "gp"], ["examination", "examination"]]:
            with self.subTest(uncovered=uncovered):
                data = self.coverage_failure()
                data["sample_business"]["comprehensive"]["uncovered"] = uncovered
                self.rejected(data)

    def test_forged_coverage_row_rejected(self):
        data = self.coverage_failure()
        data["sample_business"]["comprehensive"]["coverage"]["examination"]["covered"] = True
        self.rejected(data)

    def test_extra_or_mismatching_observer_error_rejected(self):
        for errors in [["No measured activity: gp"], ["No measured activity: examination", "Unsafe movement"], []]:
            with self.subTest(errors=errors):
                data = self.coverage_failure()
                data["sample_business"]["comprehensive"]["errors"] = errors
                self.rejected(data)

    def test_inconsistent_complete_or_coverage_flag_rejected(self):
        data = self.coverage_failure()
        data["complete"] = True
        self.rejected(data)
        data = self.coverage_failure()
        data["sample_business"]["comprehensive"]["coverage_pass"] = True
        self.rejected(data)

    def test_missing_required_field_rejected(self):
        data = self.coverage_failure()
        del data["sample_business"]["comprehensive"]["invariant_failure_counts"]
        self.rejected(data)


if __name__ == "__main__":
    unittest.main(verbosity=2)
