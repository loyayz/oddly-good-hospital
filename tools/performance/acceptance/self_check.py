"""Synthetic offline checks only. Never starts a game, ETW or GPU sampler."""
import csv
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
spec = importlib.util.spec_from_file_location("acceptance_analyze", HERE/"analyze.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ledger_spec = importlib.util.spec_from_file_location("acceptance_gpu_ledger", HERE/"gpu-ledger.py")
ledger_module = importlib.util.module_from_spec(ledger_spec)
sys.modules[ledger_spec.name] = ledger_module
ledger_spec.loader.exec_module(ledger_module)
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
            "processes":[{"stem":"game","pid":7,"start_utc_ticks":123,"exit_code":0}],"trace_final":{"code":0,"events_lost":0,"log_buffers_lost":0,"realtime_buffers_lost":0}})
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
        self.assertTrue(any("graphics allocation ledger" in item for item in report["missing"]))
        self.assertIsNone(report["presentmon_quality"]["internal_lost_present_count"])

    def test_formal_pass_is_evidence_driven_not_hardcoded_false(self):
        root = self.full_fixture()
        self.ledger_fixture(root, complete=True)
        report = module.analyze(root,REPO/"docs/data/balance.json")
        self.assertTrue(report["formal_pass"],report["missing"]+report["errors"])

    def ledger_fixture(self, root, complete=False):
        """Synthetic proof records; no ETL APIs, process or counters are invoked."""
        meta = module.load(root/"capture.json")
        chains, _, _, _ = module.displayed_intervals(root/"presentmon.csv",7,1000000)
        start = min(f["start_ms"]*1000000/1000 for f in chains["0x0"] if f["start_ms"]*1000000/1000 >= meta["window_start_qpc"])
        window = {"verified":True,"start_qpc":start,"end_qpc":meta["window_end_qpc"],"qpc_frequency":1000000,
                  "known_sequence_peak_alloc_size_bytes":100,"known_same_timestamp_upper_peak_alloc_size_bytes":100}
        (root/"allocation").mkdir()
        def write(name, value): (root/name).write_text(json.dumps(value),encoding="utf-8")
        (root/"allocation/dxgkrnl.etl").write_bytes(b"synthetic ETL identity only; never opened as ETL")
        (root/"raw-events.ndjson").write_text('{"synthetic":true}\n',encoding="utf-8")
        write("allocation/trace.json",{"target_pid":7,"target_start_utc_ticks":123,"qpc_frequency":1000000,"started_before_target":True,"error":None,
              "trace_final":{"code":0,"events_lost":0,"log_buffers_lost":0,"realtime_buffers_lost":0}})
        write("allocation/provider-schema.json",[])
        digest = lambda name: module.sha256_file(root/name)
        write("raw-events.ndjson.meta.json",{"kind":"offline_raw_etl_decode","raw_qpc_valid":True,"tool_error":None,
            "process_trace_mode_bits":"0x10001000","qpc_ticks_are_raw_header_timestamp":True,"raw_timestamp_is_unconverted_header_timestamp":True,"qpc_frequency":1000000,
            "etl_path":"allocation/dxgkrnl.etl","etl_sha256":digest("allocation/dxgkrnl.etl"),"etl_sha256_after":digest("allocation/dxgkrnl.etl"),
            "schema_path":"allocation/provider-schema.json","schema_sha256":digest("allocation/provider-schema.json"),"schema_sha256_after":digest("allocation/provider-schema.json"),
            "output":"raw-events.ndjson","output_sha256":digest("raw-events.ndjson"),
            "result":{"RawFileReadComplete":True,"ProcessStatus":0,"CloseStatus":0,"FirstRawTimestamp":0,"LastRawTimestamp":106000000,
                      "TraceHeader":{"reserved_flags_clock_type":1,"perf_frequency":1000000,"events_lost":0,"buffers_lost":0,"end_time_filetime":1}}})
        value = {"schema_version":2,"kind":"dxgkrnl_allocation_ledger","status":"incomplete","target_pid":7,"target_start_utc_ticks":123,"qpc_frequency":1000000,
            "allocation_identity":{"status":"verified"},"allocation_accounting":{"status":"verified" if complete else "incomplete","backend_coverage_verified":complete,"unreleased_observed_globals_included":True,
                "upper_bound_allocated_bytes":100,
                "coverage_method":"owner_bridged_target_graph", "owner_coverage":{"status":"verified","unresolved_kernel_lifetimes":0},
                "qualification_checks":dict.fromkeys(("preserved_raw_event_provenance","complete_raw_qpc_decode","target_identity_and_alias_join","all_process_alias_capture","all_required_event_families_armed","saved_schema_covers_interpreted_versions","formal_actual_display_window","all_target_global_sizes_joined","no_event_or_identity_gaps","unreleased_globals_included","positive_formal_extent_upper_bound","backend_target_scope_bounded"),complete)},
            "allocations":[{"adapter_pointer":"0x1","physical_adapter_index":0}],
            "peak_coverage_complete":complete,"shared_dedup_verified":complete,"formal_window":window,"raw_qpc_verified":True,
            "raw_qpc_checks":dict.fromkeys(("decoder_raw_qpc_valid","full_etl_read_complete","process_and_close_succeeded","qpc_header_clock","zero_file_loss","all_interpreted_events_have_raw_qpc","one_matching_positive_frequency"),True),
            "input_provenance":{"verified":True,"checks":dict.fromkeys(("events_hash_matches_decode_output","schema_hash_matches_decode_input","etl_input_unchanged_during_decode","supplemental_provenance_verified","required_event_families_in_decode_selection"),True)},
            "os_aggregate_counters":[{"kind":"usage","adapter_pointer":"0x1","continuous":True,"samples":1,"adapter_identity":{"AdapterLuid":"0x1","VendorID":32902,"DeviceID":32085},
                "physical_adapter_index":0,"memory_segment_group":0,"observed_peak_bytes":90,"formal_window":{**window,"observed_peak_bytes":80}}],
            "sources":[{"path":name,"sha256":digest(name)} for name in ("capture.json","allocation/trace.json","allocation/provider-schema.json","raw-events.ndjson","raw-events.ndjson.meta.json")]}
        write("allocation-ledger.json",value)
        return value

    def graphics(self, root):
        value = module.load(root/"allocation-ledger.json")
        return module.allocation_evidence(root,module.load(root/"capture.json"),value["formal_window"].get("start_qpc"),104000000,1000000,512*1024*1024)

    def save_ledger(self, root, ledger):
        (root/"allocation-ledger.json").write_text(json.dumps(ledger),encoding="utf-8")

    def test_local_identity_verified_never_upgrades_incomplete_accounting(self):
        root = self.full_fixture()
        ledger = self.ledger_fixture(root)
        ledger["known_sequence_peak_allocated_bytes"] = 600*1024*1024
        self.save_ledger(root,ledger)
        result = self.graphics(root)
        self.assertEqual(result["allocation_identity"]["status"],"verified")
        self.assertEqual(result["allocation_accounting"]["status"],"incomplete")
        self.assertFalse(result["verified"])
        self.assertFalse(result["errors"])
        self.assertFalse(module.analyze(root,REPO/"docs/data/balance.json")["formal_pass"])

    def test_backing_ambiguity_stays_separate_from_complete_direct_allocation_bound(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["backing_size_corroboration"] = {"status":"incomplete", "pending_or_ambiguous_cycles":23}
        ledger["allocation_accounting"]["physical_resident_bytes"] = None
        self.save_ledger(root,ledger)
        result = self.graphics(root)
        self.assertTrue(result["verified"],result)
        self.assertEqual(result["budget"]["upper_bound_allocated_bytes"],100)
        self.assertEqual(result["backing_size_corroboration"]["status"],"incomplete")
        self.assertIsNone(result["allocation_accounting"]["physical_resident_bytes"])

    def test_comparable_same_window_allocation_bounds_cannot_contradict_each_other(self):
        for lower in (False,True):
            with self.subTest(proven_target_lower_bound=lower):
                root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
                accounting = ledger["allocation_accounting"]
                if lower:
                    accounting.update(lower_bound_allocated_bytes=200,lower_bound_scope="target_allocations",
                        lower_bound_qualification=dict.fromkeys(("actual_target_allocation_scope","canonical_allocation_identity_deduplicated",
                            "extent_size_semantics_verified","simultaneous_actual_window_observation"),True))
                else:
                    accounting["peak_allocated_bytes"] = 200
                self.save_ledger(root,ledger)
                result = self.graphics(root)
                self.assertFalse(result["verified"])
                self.assertEqual(result["budget"]["status"],"incomplete")
                self.assertIn("contradicts its supplied upper bound",str(result["missing"]))

    def test_bad_raw_source_hash_is_not_a_verified_proof(self):
        root = self.full_fixture(); self.ledger_fixture(root,True)
        (root/"raw-events.ndjson").write_text("changed",encoding="utf-8")
        result = self.graphics(root)
        self.assertFalse(result["checks"]["preserved_source_hashes"])
        self.assertFalse(result["verified"])

    def test_same_etl_is_rehashed_not_only_trusted_from_flags(self):
        root = self.full_fixture(); self.ledger_fixture(root,True)
        (root/"allocation/dxgkrnl.etl").write_bytes(b"another ETL")
        result = self.graphics(root)
        self.assertFalse(result["checks"]["same_original_etl"])
        self.assertFalse(result["verified"])

    def test_graphics_pid_start_and_frequency_are_bound(self):
        for key, value, check in (("target_pid",8,"same_pid_and_lifetime"),("target_start_utc_ticks",124,"same_pid_and_lifetime"),("qpc_frequency",1000,"matching_positive_frequency")):
            with self.subTest(key=key):
                root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
                ledger[key] = value; self.save_ledger(root,ledger)
                self.assertFalse(self.graphics(root)["checks"][check])
                self.assertFalse(self.graphics(root)["verified"])

    def test_graphics_raw_clock_and_loss_are_required(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["raw_qpc_checks"]["qpc_header_clock"] = False
        self.save_ledger(root,ledger)
        self.assertFalse(self.graphics(root)["checks"]["ledger_raw_qpc"])
        trace = module.load(root/"allocation/trace.json"); trace["trace_final"]["events_lost"] = 1
        (root/"allocation/trace.json").write_text(json.dumps(trace),encoding="utf-8")
        self.assertFalse(self.graphics(root)["checks"]["zero_trace_loss"])

    def test_uncovered_actual_window_cannot_pass_graphics(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["formal_window"]["end_qpc"] -= 1; self.save_ledger(root,ledger)
        self.assertFalse(self.graphics(root)["checks"]["formal_window_covers_actual"])
        self.assertFalse(self.graphics(root)["verified"])

    def test_complete_wider_window_below_target_is_a_valid_upper_bound(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["formal_window"]["start_qpc"] -= 1000; self.save_ledger(root,ledger)
        actual = ledger["os_aggregate_counters"][0]["formal_window"]["start_qpc"]
        result = module.allocation_evidence(root,module.load(root/"capture.json"),actual,104000000,1000000,512*1024*1024)
        self.assertTrue(result["verified"],result)
        self.assertIn("wider-window",result["budget"]["scope"])

    def test_wider_window_excess_is_not_actual_window_failure(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        actual = ledger["formal_window"]["start_qpc"]
        ledger["formal_window"]["start_qpc"] -= 1000
        ledger["formal_window"]["known_same_timestamp_upper_peak_alloc_size_bytes"] = 600*1024*1024
        ledger["allocation_accounting"]["peak_allocated_bytes"] = 600*1024*1024
        self.save_ledger(root,ledger)
        result = module.allocation_evidence(root,module.load(root/"capture.json"),actual,104000000,1000000,512*1024*1024)
        self.assertFalse(result["verified"])
        self.assertFalse(result["errors"])

    def test_verified_exact_allocation_peak_can_fail_budget(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["formal_window"]["known_same_timestamp_upper_peak_alloc_size_bytes"] = 600*1024*1024
        ledger["allocation_accounting"]["peak_allocated_bytes"] = 600*1024*1024
        self.save_ledger(root,ledger)
        self.assertIn("graphics allocation target exceeded",self.graphics(root)["errors"])

    def test_adapter_kernel_upper_above_target_is_incomplete_not_target_failure(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["unattributed_kernel_global_bound"] = {"status":"bounded","formal_upper_bound_bytes":1024**3}
        ledger["allocation_accounting"].update(coverage_method="adapter_kernel_fallback_upper_bound",
            upper_bound_allocated_bytes=1024**3+100,peak_allocated_bytes=1024**3)
        self.save_ledger(root,ledger)
        result = self.graphics(root)
        self.assertEqual(result["status"],"incomplete")
        self.assertFalse(result["errors"])

    def test_large_diagnostic_foreign_kernel_does_not_change_owner_target_budget(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["unattributed_kernel_global_bound"] = {"status":"bounded","formal_upper_bound_bytes":1024**3}
        self.save_ledger(root,ledger)
        self.assertTrue(self.graphics(root)["verified"])

    def test_proven_target_lower_bound_can_fail_without_complete_backend_upper(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root)
        ledger["allocation_accounting"].update(lower_bound_allocated_bytes=600*1024**2,lower_bound_scope="target_allocations",
            lower_bound_qualification=dict.fromkeys(("actual_target_allocation_scope","canonical_allocation_identity_deduplicated",
                "extent_size_semantics_verified","simultaneous_actual_window_observation"),True))
        self.save_ledger(root,ledger)
        result = self.graphics(root)
        self.assertEqual(result["status"],"failed")
        self.assertIn("graphics allocation target exceeded",result["errors"])
        ledger["allocation_accounting"]["lower_bound_scope"] = "adapter_kernel_fallback"
        self.save_ledger(root,ledger)
        self.assertFalse(self.graphics(root)["errors"])

    def test_commitment_does_not_substitute_for_os_usage_or_allocation(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["os_aggregate_counters"][0]["kind"] = "commitment"
        self.save_ledger(root,ledger)
        result = self.graphics(root)
        self.assertFalse(result["verified"])
        self.assertEqual(result["os_residency_view_status"],"incomplete")
        self.assertFalse(result["os_aggregate_counters"][0]["added_to_allocated_bytes"])

    def test_one_adapter_usage_does_not_cover_another_target_adapter(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["allocations"].append({"adapter_pointer":"0x2","physical_adapter_index":1})
        self.save_ledger(root,ledger)
        self.assertFalse(self.graphics(root)["verified"])

    def test_summary_flags_cannot_replace_accounting_qualification_checks(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
        ledger["allocation_accounting"]["qualification_checks"].pop("all_required_event_families_armed")
        self.save_ledger(root,ledger)
        self.assertFalse(self.graphics(root)["verified"])

    def test_decoder_header_clock_and_loss_are_independently_rechecked(self):
        for field, value in (("reserved_flags_clock_type",2),("events_lost",1)):
            with self.subTest(field=field):
                root = self.full_fixture(); ledger = self.ledger_fixture(root,True)
                path = root/"raw-events.ndjson.meta.json"
                decode = module.load(path); decode["result"]["TraceHeader"][field] = value
                path.write_text(json.dumps(decode),encoding="utf-8")
                next(s for s in ledger["sources"] if s["path"] == path.name)["sha256"] = module.sha256_file(path)
                self.save_ledger(root,ledger)
                result = self.graphics(root)
                self.assertTrue(result["checks"]["preserved_source_hashes"])
                self.assertFalse(result["checks"]["decode_clock_api_loss"])
                self.assertFalse(result["verified"])

    def test_actual_display_window_reuses_analyzer_and_preserves_ack(self):
        root = self.full_fixture()
        capture = module.load(root/"capture.json")
        resolved = ledger_module.resolve_capture_window(capture,root/"capture.json")
        report = module.analyze(root,REPO/"docs/data/balance.json")
        self.assertTrue(resolved["window_resolution"]["verified"])
        self.assertEqual(resolved["window_start_qpc"],report["window"]["start_qpc"])
        self.assertGreater(resolved["window_start_qpc"],capture["window_start_qpc"])
        self.assertEqual(resolved["acknowledged_window"]["start_qpc"],capture["window_start_qpc"])
        self.assertEqual(len(resolved["window_resolution"]["sources"]),3)

    def test_failed_display_resolution_cannot_claim_ack_is_actual_window(self):
        root = self.full_fixture()
        (root/"presentmon.csv").write_text("wrong,columns\n1,2\n",encoding="utf-8")
        resolved = ledger_module.resolve_capture_window(module.load(root/"capture.json"),root/"capture.json")
        self.assertFalse(resolved["window_resolution"]["verified"])
        window = ledger_module.window_summary([],resolved,7,{"target_start_utc_ticks":123},
                    {"result":{"FirstRawTimestamp":0,"LastRawTimestamp":106000000}},{1000000})
        self.assertFalse(window["verified"])

    def test_legacy_graphics_flag_cannot_bypass_schema2_accounting(self):
        root = self.full_fixture()
        (root/"graphics-evidence.json").write_text(json.dumps({"status":"verified","pid":7,"peak_allocated_bytes":0}),encoding="utf-8")
        report = module.analyze(root,REPO/"docs/data/balance.json")
        self.assertFalse(report["graphics_evidence_verified"])
        self.assertFalse(report["formal_pass"])

    def test_no_formal_window_preserves_local_identity_and_os_lifecycle_only(self):
        root = self.full_fixture(); ledger = self.ledger_fixture(root)
        ledger["formal_window"] = {"verified":False}
        self.save_ledger(root,ledger)
        result = module.allocation_evidence(root,module.load(root/"capture.json"),None,None,1000000,512*1024*1024)
        self.assertEqual(result["allocation_identity"]["status"],"verified")
        self.assertTrue(result["allocation_identity"]["source_validated"])
        self.assertEqual(result["os_aggregate_counters"][0]["status"],"observed_lifecycle_only")
        self.assertEqual(result["os_aggregate_counters"][0]["lifecycle_observed_peak_bytes"],90)
        self.assertFalse(result["verified"])

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
