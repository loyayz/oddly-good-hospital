"""Synthetic offline checks only. Never starts a game, ETW or GPU sampler."""
import csv
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
spec = importlib.util.spec_from_file_location("acceptance_analyze", HERE/"analyze.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
LIMITS = {"p95_ms":16.7,"p99_ms":25,"max_ms":50}


class OfflineChecks(unittest.TestCase):
    def temporary(self):
        cache = REPO/".cache/acceptance-tool-checks"
        cache.mkdir(parents=True, exist_ok=True)
        directory = tempfile.TemporaryDirectory(dir=cache, prefix="synthetic-")
        assert Path(directory.name).resolve().is_relative_to(cache.resolve())
        self.addCleanup(directory.cleanup)
        return Path(directory.name)

    def fixture(self, durations, *, foreign=False, gap=False, dropped=False):
        root = self.temporary()
        path = root/"presentmon.csv"
        with path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["ProcessID","SwapChainAddress","QPCTime","Dropped","msUntilDisplayed","msBetweenDisplayChange"])
            end = 1000
            writer.writerow([7,"0x0",end,0,1,0])
            for index, duration in enumerate(durations):
                end += duration
                writer.writerow([8 if foreign and index==0 else 7,"0x0",end,1 if dropped else 0,1,duration+(2 if gap and index==0 else 0)])
        return path

    def test_nearest_rank_and_max_share_population(self):
        stats = module.distribution([16]*990+[80]*10)
        self.assertEqual((stats["p95_ms"],stats["p99_ms"],stats["max_ms"]),(16,16,80))
        self.assertEqual(module.limits_status(stats,1000,LIMITS),"failed")

    def test_eleven_tail_samples_fail_p99(self):
        self.assertEqual(module.distribution([16]*989+[40]*11)["p99_ms"],40)

    def test_optional_boundary_cannot_drop_long_max(self):
        stats = module.bounded_distribution([16]*1000,[80],1000,LIMITS)
        self.assertEqual(stats["status"],"boundary_uncertain")
        self.assertEqual(stats["metric_upper"]["max_ms"],80)

    def test_optional_fast_boundary_cannot_dilute_failure(self):
        stats = module.bounded_distribution([60]*1000,[1]*20,1000,LIMITS)
        self.assertEqual(stats["status"],"failed")

    def test_display_timestamp_is_present_plus_until(self):
        chains, _, errors, skipped = module.displayed_intervals(self.fixture([16,80]),7,1000)
        self.assertFalse(errors)
        self.assertEqual(chains["0x0"][1]["end_ms"],1097)
        self.assertEqual(skipped["first_display_without_interval"],1)

    def test_foreign_pid_not_pooled(self):
        _,_,errors,_ = module.displayed_intervals(self.fixture([16],foreign=True),7,1000)
        self.assertTrue(any("foreign_pid" in e for e in errors))

    def test_gap_not_silently_repaired(self):
        _,_,errors,_ = module.displayed_intervals(self.fixture([16],gap=True),7,1000)
        self.assertTrue(any("gap" in e for e in errors))

    def test_dropped_present_is_not_displayed_or_etw_loss(self):
        chains,_,errors,skipped = module.displayed_intervals(self.fixture([16],dropped=True),7,1000)
        self.assertFalse(errors)
        self.assertFalse(chains["0x0"])
        self.assertEqual(skipped["not_displayed"],1)

    def test_samples_not_synthesized(self):
        self.assertEqual(module.limits_status(module.distribution([16]*999),1000,LIMITS),"insufficient_samples")

    def clock(self):
        records = [{"kind":"clock_sample","engine_us":v,"qpc_before_ticks":v+1000,"qpc_after_ticks":v+1002,"qpc_frequency":1000000,"valid":True} for v in (0,500000,1000000)]
        return module.ClockBounds(records,1000000)

    def test_historical_clock_not_notification_minus_elapsed(self):
        clock = self.clock()
        self.assertEqual(clock.map(750000,900000),(501000,900000))
        self.assertNotEqual(clock.map(750000,900000)[0],750000)

    def test_equal_integer_microsecond_is_not_exact_same_instant(self):
        self.assertEqual(self.clock().map(500000,900000),(1000,900000))

    def test_complete_step_tail_kept_by_start(self):
        steps = [{"_start_bounds":(100,101),"elapsed_us":80000,"main_elapsed_us":5000,"between_slices_wall_us":75000}]
        stats = module.step_population(steps,0,200,1,LIMITS)
        self.assertEqual(stats["max_ms"],80)
        self.assertEqual(stats["status"],"failed")

    def test_pending_pause_does_not_remove_original_step_wait(self):
        clock = self.clock()
        step = {"hospital_session":"a","started_engine_us":100000,"_completion_bounds":(501000,900000)}
        states = [{"kind":"session_state","engine_us":0,"qpc_ticks":1000,"actual_speed":1,"requested_speed":1,"hospital_session":"a"},
                  {"kind":"session_state","engine_us":200000,"qpc_ticks":201002,"actual_speed":0,"requested_speed":0,"step_in_progress":True,"original_step_started_us":100000,"hospital_session":"a"}]
        result = module.speed_window(states,[step],clock,1003,1001002,1000000,1)
        self.assertGreaterEqual(result["active_real_seconds_upper"],.8)
        self.assertFalse(result["issues"])

    def full_fixture(self):
        root = self.temporary()
        def write(name, value):
            (root/name).write_text(json.dumps(value),encoding="utf-8")
        with (root/"presentmon.csv").open("w",newline="",encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["ProcessID","SwapChainAddress","QPCTime","Dropped","msUntilDisplayed","msBetweenDisplayChange"])
            for end in range(0,106001,16):
                writer.writerow([7,"0x0",(end-1)*1000,0,1,16 if end else 0])
        write("capture.json",{"qpc_frequency":1000000,"pid":7,"selected_swapchain":"0x0","window_start_qpc":1000000,"window_end_qpc":104000000,"poll_requested_ms":100,
            "processes":[{"stem":"game","exit_code":0}],"trace_final":{"code":0,"events_lost":0,"log_buffers_lost":0,"realtime_buffers_lost":0}})
        write("scenario.json",{"name":"synthetic","actors":160,"speed":1,"window_pixels":[2560,1440],"operations":[]})
        telemetry = [{"kind":"clock_sample","engine_us":v,"qpc_before_ticks":v,"qpc_after_ticks":v+2,"qpc_frequency":1000000,"valid":True} for v in range(0,106000001,500000)]
        telemetry += [{"kind":"step","tick":tick,"started_engine_us":tick*100000-5000,"completed_engine_us":tick*100000,"elapsed_us":5000,"main_elapsed_us":4000,"between_slices_wall_us":1000,"completion_qpc_ticks":tick*100000+2,"qpc_frequency":1000000,"hospital_session":"a","capture_step":True} for tick in range(1,1060)]
        telemetry += [{"kind":"session_state","engine_us":0,"qpc_ticks":2,"actual_speed":1,"requested_speed":1,"pause_reasons":[],"hospital_session":"a"},
            {"kind":"boot","settings":{"window_pixels":[2560,1440]}},{"kind":"scenario_complete"},{"kind":"exit","exit_code":0}]
        (root/"telemetry.ndjson").write_text("\n".join(json.dumps(r) for r in telemetry),encoding="utf-8")
        (root/"process.ndjson").write_text("\n".join(json.dumps({"qpc_ticks":v,"working_set_bytes":100,"private_commit_bytes":80,"lifetime_peak_working_set_bytes":110,"lifetime_peak_private_commit_bytes":90}) for v in range(0,106000001,100000)),encoding="utf-8")
        return root

    def test_real_clock_contract_can_pass_timing_without_fake_exact_qpc(self):
        report = module.analyze(self.full_fixture(),REPO/"docs/data/balance.json")
        self.assertTrue(report["timing_pass"],report["missing"]+report["errors"])
        self.assertGreaterEqual(report["steps"]["definite_samples"],1000)
        self.assertFalse(report["formal_pass"])
        self.assertIn("actual graphics allocation/residency/shared-dedup evidence",report["missing"])
        self.assertIsNone(report["presentmon_quality"]["internal_lost_present_count"])

    def test_formal_pass_is_evidence_driven_not_hardcoded_false(self):
        root = self.full_fixture()
        source = root/"synthetic-allocation-proof.json"
        source.write_text("synthetic test data only",encoding="utf-8")
        proof = {"path":source.name,"sha256":hashlib.sha256(source.read_bytes()).hexdigest()}
        (root/"graphics-evidence.json").write_text(json.dumps({"status":"verified","pid":7,"window_start_qpc":0,"window_end_qpc":106000000,"allocation_identity_sources":[proof],"shared_dedup_verified":True,"unreleased_included":True,"peak_allocated_bytes":100,"transient_process_peak_covered":True}),encoding="utf-8")
        report = module.analyze(root,REPO/"docs/data/balance.json")
        self.assertTrue(report["formal_pass"],report["missing"]+report["errors"])

    def test_missing_tail_stays_incomplete(self):
        root = self.full_fixture()
        meta = module.load(root/"capture.json"); meta["window_end_qpc"] = 108000000
        (root/"capture.json").write_text(json.dumps(meta),encoding="utf-8")
        report = module.analyze(root,REPO/"docs/data/balance.json")
        self.assertFalse(report["formal_pass"])
        self.assertIn("complete original tail display interval",report["missing"])

    def test_nonzero_etw_loss_fails(self):
        root = self.full_fixture()
        meta = module.load(root/"capture.json");meta["trace_final"]["events_lost"] = 1
        (root/"capture.json").write_text(json.dumps(meta),encoding="utf-8")
        self.assertIn("ETW events/buffers lost",module.analyze(root,REPO/"docs/data/balance.json")["errors"])

    def test_baseline_save_total_uses_matching_real_receipt(self):
        root = self.full_fixture()
        with (root/"telemetry.ndjson").open("a",encoding="utf-8") as stream:
            stream.write("\n"+json.dumps({"kind":"save_receipt","qpc_ticks":14000000,"elapsed_us":3000000,"receipt":{"request_id":"save-a","ok":True},"request_observation":{"begin_engine_us":11000000,"slot_kind":"manual"},"duration_kind":"matching original request through receipt"}))
        report = module.analyze(root,REPO/"docs/data/balance.json")
        self.assertIn("save total exceeds baseline target",report["errors"])
        self.assertEqual(report["save_totals"][0]["seconds"],3)


if __name__ == "__main__":
    unittest.main()
