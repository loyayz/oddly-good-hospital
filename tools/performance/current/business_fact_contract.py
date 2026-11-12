"""Offline boundary-log contract. Does not start an engine, query a world or write evidence."""
import argparse
import copy
import json
from pathlib import Path
import unittest

from prepare_builtin_script_profile import digest, read, validate_diagnostic_witness

MIXED_SHA = "75f5e1d922f39f12382c0ceb74806bda0293251189f68a1ac158842f65fa78ca"
FULL_SHA = "0daf82b82da618af8818aed962d5ef2bf9bad1b00be01c4f5a7ce71efb52662e"
SMOKE_SHA = "21aff2546935022312333b67605680c491292575aaa845b07733db993a415a51"
EXAMS = [f"bench_visit_{index:04d}" for index in (20, 21, *range(44, 54))]
TARGETS = ["bench_room_2_12_0", "bench_room_2_15_0"]
NUMERIC_FIELDS = ("remaining_ticks", "remaining_milli", "completed_milli")


def validate_rows(rows):
    iterator = iter(rows)
    header = next(iterator)
    assert header["kind"] == "header" and header["row_number"] == 0 and header["schema"] == 1
    assert header["input_sha256"] == MIXED_SHA and header["exam_visits"] == EXAMS
    assert header["operation_facilities"] == TARGETS
    prefix, samples = header["prefix_steps"], header["sample_steps"]
    assert (prefix, samples) in ((1000, 6000), (0, 2)), "Window changed"
    assert header["expected_final_sha256"] == (FULL_SHA if prefix else SMOKE_SHA)
    state, counts = {}, {"input": 0, "prefix": 0, "sample": 0}
    number, last_index, footer = 0, -1, None
    input_exams, operation_facilities = set(), set()
    for row in iterator:
        number += 1
        assert row["row_number"] == number and footer is None, "Missing, repeated or post-footer row"
        if row["kind"] == "footer":
            footer = row["summary"]
            continue
        assert row["kind"] == "change"
        index = row["index"]
        assert type(index) is int and -1 <= index < prefix + samples and index >= last_index
        last_index = index
        window = "input" if index < 0 else "prefix" if index < prefix else "sample"
        assert row["window"] == window
        assert row["tick"] == header["initial_tick"] + (0 if index < 0 else index + 1)
        key = row["key"]
        assert key == row["collection"] + "/" + row["id"]
        operation, changes = row["operation"], row["fields"]
        assert operation in ("create", "update", "remove") and changes, "Empty or unknown change"
        assert (key in state) == (operation != "create"), "Owner creation/removal history is inconsistent"
        before = copy.deepcopy(state.get(key, {}))
        after = copy.deepcopy(before)
        for field, change in changes.items():
            assert type(change["before_present"]) is bool and type(change["after_present"]) is bool
            assert change["before_present"] == (field in before)
            assert change["before"] == before.get(field), "Prior owner value differs"
            assert change["before_present"] != change["after_present"] or change["before"] != change["after"], "Unchanged field logged"
            if change["after_present"]:
                after[field] = change["after"]
            else:
                assert change["after"] is None
                after.pop(field, None)
        expected_deltas = {field: after[field] - before[field] for field in NUMERIC_FIELDS
                           if field in before and field in after}
        assert row["raw_numeric_deltas"] == expected_deltas, "Raw owner delta changed or was classified as work"
        if operation == "remove":
            assert not after, "Removed owner retains fields"
            del state[key]
        else:
            assert after
            state[key] = after
        if row["collection"] == "visits" and index < 0 and row["id"] in EXAMS:
            input_exams.add(row["id"])
        if row["collection"] in ("maintenance.jobs", "maintenance.upgrades"):
            if after.get("facility_id") in TARGETS: operation_facilities.add(after["facility_id"])
        counts[window] += 1
    assert footer is not None, "No completed footer"
    assert footer["observed_steps"] == prefix + samples and footer["change_rows"] == counts
    assert footer["errors"] == []
    return {"ok": True, "prefix_steps": prefix, "sample_steps": samples,
            "change_rows": counts, "retained_records": len(state),
            "input_exam_records": sorted(input_exams), "operation_facilities_seen": sorted(operation_facilities),
            "scope": "Ordered owner-field reconstruction only. A remaining delta is not accepted as valid work or effective visitation."}


def validate_result(result_path):
    result = read(result_path)
    if result["requested_prefix_steps"]:
        witness = validate_diagnostic_witness(result_path, MIXED_SHA)
        assert witness["final_sha256"] == FULL_SHA
    else:
        assert result["complete"] and result["errors"] == []
        assert result["all_completed_steps"] == result["metrics"]["count"] == 2
        assert result["final_sha256"] == SMOKE_SHA
    assert digest(Path(str(result_path) + ".final.bin")) == result["final_sha256"]
    assert result["world_validation"] == "" and result["source_input_sha256"] == MIXED_SHA
    assert result["initial"]["population"]["present"] == 160
    execution = read(Path(str(result_path) + ".execution.json"))
    assert execution["main_thread_policy"]["applied"] and execution["worker_tasks"] == 4
    assert execution["profile_stages"] is False and execution["worker_samples"]["diagnostics_enabled"] is False
    with Path(str(result_path) + ".business.ndjson").open(encoding="utf-8-sig") as stream:
        summary = validate_rows(json.loads(line) for line in stream)
    assert summary["input_exam_records"] == sorted(EXAMS)
    if result["requested_prefix_steps"]:
        assert summary["operation_facilities_seen"] == TARGETS
    assert result["trace"]["observed_steps"] == result["all_completed_steps"]
    entered, completed = 0, 0
    with Path(str(result_path) + ".steps.ndjson").open(encoding="utf-8-sig") as stream:
        for line in stream:
            row = json.loads(line)
            if row["kind"] == "enter":
                assert row["index"] == entered and row["tick"] == result["initial"]["tick"] + entered
                entered += 1
            else:
                assert row["kind"] == "complete" and row["sample"]["index"] == completed
                assert row["sample"]["tick"] == result["initial"]["tick"] + completed + 1
                completed += 1
    assert entered == completed == result["all_completed_steps"]
    return {**summary, "final_sha256": result["final_sha256"], "result_sha256": digest(result_path),
            "business_coverage_pass": result["sample_business"]["comprehensive"]["coverage_pass"],
            "uncovered": result["sample_business"]["comprehensive"]["uncovered"], "performance_pass": None}


def fixture_rows():
    """Sparse test log: cancellation/reset is retained, not accepted as work."""
    header = {"kind": "header", "row_number": 0, "schema": 1, "input_sha256": MIXED_SHA,
              "exam_visits": EXAMS, "operation_facilities": TARGETS, "initial_tick": 633,
              "prefix_steps": 1000, "sample_steps": 6000, "expected_final_sha256": FULL_SHA}
    rows = [header]
    state = {}
    for index, new in ((-1, {"phase": "waiting", "remaining_ticks": 300}),
                       (999, {"phase": "waiting", "remaining_ticks": 299}),
                       (1000, {"phase": "leaving", "remaining_ticks": 0}),
                       (1001, {}), (1002, {"phase": "outside"})):
        fields = {key: {"before_present": key in state, "after_present": key in new,
                        "before": state.get(key), "after": new.get(key)}
                  for key in sorted(state.keys() | new.keys()) if (key in state) != (key in new) or state.get(key) != new.get(key)}
        rows.append({"kind": "change", "row_number": len(rows), "key": "visitors.stays/example",
                     "collection": "visitors.stays", "id": "example", "index": index,
                     "tick": 633 if index < 0 else 634 + index,
                     "window": "input" if index < 0 else "prefix" if index < 1000 else "sample",
                     "operation": "create" if not state else "remove" if not new else "update",
                     "fields": fields, "raw_numeric_deltas": {field: new[field] - state[field]
                                                              for field in NUMERIC_FIELDS if field in state and field in new}})
        state = new
    rows.append({"kind": "footer", "row_number": len(rows),
                 "summary": {"observed_steps": 7000, "change_rows": {"input": 1, "prefix": 1, "sample": 3}, "errors": []}})
    return rows


class OfflineBoundaryContract(unittest.TestCase):
    def test_sparse_creation_cancellation_removal_and_recreation(self):
        self.assertTrue(validate_rows(fixture_rows())["ok"])

    def test_exact_prefix_to_sample_boundary(self):
        rows = fixture_rows()
        rows[3]["window"] = "prefix"
        with self.assertRaises(AssertionError): validate_rows(rows)

    def test_stale_before_field_is_rejected(self):
        rows = fixture_rows()
        rows[2]["fields"]["remaining_ticks"]["before"] = 1
        with self.assertRaises(AssertionError): validate_rows(rows)

    def test_terminal_clear_remains_a_raw_negative_delta(self):
        rows = fixture_rows()
        self.assertEqual(rows[3]["raw_numeric_deltas"], {"remaining_ticks": -299})
        self.assertNotIn("work", validate_rows(rows))
        rows[3]["raw_numeric_deltas"]["remaining_ticks"] = -1
        with self.assertRaises(AssertionError): validate_rows(rows)

    def test_truncation_duplicate_and_wrong_tick_are_rejected(self):
        for mode in ("truncate", "duplicate", "tick"):
            rows = fixture_rows()
            if mode == "truncate": rows.pop()
            elif mode == "duplicate": rows.insert(2, copy.deepcopy(rows[1]))
            else: rows[2]["tick"] += 1
            with self.subTest(mode=mode), self.assertRaises(AssertionError): validate_rows(rows)

    def test_wrong_input_window_and_owner_removal_are_rejected(self):
        for mode in ("input", "window", "remove"):
            rows = fixture_rows()
            if mode == "input": rows[0]["input_sha256"] = "another input"
            elif mode == "window": rows[0]["sample_steps"] = 1000
            else: rows[4]["fields"].pop("phase")
            with self.subTest(mode=mode), self.assertRaises(AssertionError): validate_rows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--self-test", action="store_true")
    action.add_argument("--result", type=Path)
    action.add_argument("--inspect-report", type=Path)
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(OfflineBoundaryContract)
        raise SystemExit(0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1)
    if args.inspect_report:
        report = read(args.inspect_report)
        assert report["mode"] == "read_only_final_boundary" and report["complete"]
        assert report["input_sha256"] == digest(Path(report["input"])) == FULL_SHA
        assert report["complete_facts_and_rng_unchanged"] and report["world_validation"] == ""
        assert all("visits/" + visit in report["records"] for visit in EXAMS)
        print(json.dumps({"ok": True, "mode": report["mode"], "tick": report["tick"],
                          "records": len(report["records"]), "input_sha256": FULL_SHA}))
    else:
        print(json.dumps(validate_result(args.result), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
