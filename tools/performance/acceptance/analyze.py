"""Offline acceptance of one owned Release condition; no collection or pooling."""
from __future__ import annotations
import argparse
import bisect
import csv
import hashlib
import json
import math
import re
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rows(path):
    path = Path(path)
    return [json.loads(s) for s in path.read_text(encoding="utf-8-sig").splitlines() if s.strip()] if path.exists() else []


def distribution(values):
    values = sorted(values)
    return {"samples": len(values), "p95_ms": values[math.ceil(.95*len(values))-1] if values else None,
            "p99_ms": values[math.ceil(.99*len(values))-1] if values else None,
            "max_ms": max(values) if values else None, "mean_ms": sum(values)/len(values) if values else None}


def bounded_distribution(definite, optional, minimum, limits):
    """Every possible membership, without picking a favourable boundary subset.

    For k optional observations the largest quantile uses the k largest optional
    values, the smallest uses the k smallest. Evaluate every k with nearest rank.
    """
    base = distribution(definite)
    possible = sorted(optional)
    candidates_low = [distribution(definite+possible[:k]) for k in range(len(possible)+1)]
    candidates_high = [distribution(definite+possible[len(possible)-k:]) for k in range(len(possible)+1)]
    lower = {key: min((d[key] for d in candidates_low if d[key] is not None), default=None) for key in limits}
    upper = {key: max((d[key] for d in candidates_high if d[key] is not None), default=None) for key in limits}
    status = "observed_within_limits"
    if any(lower[key] is not None and lower[key] > limit for key, limit in limits.items()):
        status = "failed"
    elif len(definite) < minimum:
        status = "insufficient_samples"
    elif any(upper[key] is None or upper[key] > limit for key, limit in limits.items()):
        status = "boundary_uncertain"
    return {**base, "status": status, "definite_samples": len(definite), "boundary_optional_samples": len(optional),
            "possible_samples": len(definite)+len(optional), "metric_lower": lower, "metric_upper": upper,
            "percentile": "nearest_rank_ceil_p_times_n", "maximum_population": "same complete original intervals"}


def limits_status(stats, minimum, limits):
    if stats["samples"] < minimum:
        return "insufficient_samples"
    return "failed" if any(stats[k] > v for k, v in limits.items()) else "observed_within_limits"


def numeric(value):
    if value is None or str(value).strip().lower() in ("", "na", "nan"):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def swapchain(value):
    return hex(int(str(value), 16))


def displayed_intervals(path, target_pid, frequency):
    intervals, endpoints, errors = {}, {}, []
    skipped = {"not_displayed": 0, "first_display_without_interval": 0, "duplicate_display_endpoint": 0}
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = {f.lower() for f in (reader.fieldnames or [])}
        required = {"processid", "swapchainaddress", "qpctime", "dropped", "msuntildisplayed", "msbetweendisplaychange"}
        if not required <= fields:
            return {}, {}, ["PresentMon v1 raw-QPC schema missing; no CPUStart fallback"], skipped
        for number, original in enumerate(reader, 2):
            row = {k.lower(): v for k, v in original.items() if k is not None}
            if int(row["processid"]) != target_pid:
                errors.append(f"foreign_pid_at_row_{number}"); continue
            if row["dropped"] == "1":
                skipped["not_displayed"] += 1; continue
            if row["dropped"] != "0":
                errors.append(f"unknown_dropped_value_row_{number}"); continue
            chain = swapchain(row["swapchainaddress"])
            present, until, duration = (numeric(row.get(k)) for k in ("qpctime", "msuntildisplayed", "msbetweendisplaychange"))
            if present is None or until is None or until < 0:
                errors.append(f"display_timestamp_missing_row_{number}"); continue
            end = present*1000.0/frequency+until
            previous = endpoints.get(chain)
            if previous is not None and end == previous:
                skipped["duplicate_display_endpoint"] += 1; continue
            if previous is not None and end < previous:
                errors.append(f"nonincreasing_display_timestamp_row_{number}"); continue
            endpoints[chain] = end
            intervals.setdefault(chain, [])
            if duration is None or duration <= 0:
                if previous is not None:
                    errors.append(f"missing_display_interval_row_{number}")
                skipped["first_display_without_interval"] += 1; continue
            start = end-duration
            if previous is not None and abs(start-previous) > .05:
                errors.append(f"display_chain_gap_row_{number}")
            intervals[chain].append({"start_ms": start, "end_ms": end, "duration_ms": duration, "present_qpc_ticks":present, "row": number})
    return intervals, endpoints, errors, skipped


class ClockBounds:
    """Monotonic enclosure from actual QPC-before/engine/QPC-after samples.

    No fitted clock rate, offset midpoint, zero drift or exact historical QPC.
    """
    def __init__(self, telemetry, frequency):
        self.samples = sorted([r for r in telemetry if r.get("kind") == "clock_sample" and r.get("valid") is True], key=lambda r: r["engine_us"])
        self.times = [r["engine_us"] for r in self.samples]
        for index, row in enumerate(self.samples):
            if row.get("qpc_frequency") != frequency or row["qpc_before_ticks"] > row["qpc_after_ticks"]:
                raise ValueError("invalid native clock bracket")
            if index and (row["engine_us"] < self.samples[index-1]["engine_us"] or row["qpc_before_ticks"] < self.samples[index-1]["qpc_before_ticks"]):
                raise ValueError("nonmonotonic clock samples")

    def map(self, engine_us, upper_observation=None):
        if engine_us is None:
            return None
        # Integer microsecond equality does not imply identical observation
        # time. Strict neighbours retain the clock's quantization uncertainty.
        left = bisect.bisect_left(self.times, engine_us)-1
        right = bisect.bisect_right(self.times, engine_us)
        if left < 0 or (right >= len(self.samples) and upper_observation is None):
            return None
        lower = self.samples[left]["qpc_before_ticks"]
        upper = self.samples[right]["qpc_after_ticks"] if right < len(self.samples) else upper_observation
        if upper_observation is not None:
            upper = min(upper, upper_observation)
        if upper < lower:
            raise ValueError("historical engine endpoint contradicts notification QPC")
        return lower, upper


def membership(bounds, start, end):
    if bounds is None:
        return "unmapped"
    lower, upper = bounds
    if lower >= start and upper < end:
        return "definite"
    if upper < start or lower >= end:
        return "outside"
    return "optional"


def union_length(intervals, start, end):
    total, current = 0.0, start
    for lower, upper in sorted(intervals):
        lower, upper = max(start, lower), min(end, upper)
        if upper > max(current, lower):
            total += upper-max(current, lower)
            current = upper
    return total


def speed_window(telemetry, steps, clock, start, end, frequency, selected_speed):
    states = [r for r in telemetry if r.get("kind") == "session_state" and r.get("qpc_ticks") is not None]
    states.sort(key=lambda r: r["qpc_ticks"])
    definite_pauses, possible_pauses, issues = [], [], []
    opened = None
    if not states or not any(r["qpc_ticks"] <= start for r in states):
        issues.append("playback state before window unavailable")
    for row in states:
        actual = row.get("actual_speed")
        if start <= row["qpc_ticks"] < end and actual not in (0, selected_speed):
            issues.append("speed changed within condition; separate windows required")
        # Only explicit player pause/focus may leave the denominator. Save and
        # unknown automatic waits keep the selected-speed denominator.
        paused = actual == 0 and (row.get("requested_speed") == 0 or "focus" in row.get("pause_reasons", []))
        bounds = clock.map(row.get("engine_us"))
        if bounds is None:
            if start <= row["qpc_ticks"] < end:
                issues.append("playback transition clock enclosure unavailable")
            continue
        if paused and row.get("step_in_progress"):
            matching = [s for s in steps if s.get("hospital_session") == row.get("hospital_session") and s.get("started_engine_us") == row.get("original_step_started_us")]
            if not matching:
                issues.append("started step missing at pause boundary"); continue
            finished = matching[0].get("_completion_bounds")
            if finished is None:
                issues.append("started step completion cannot be mapped"); continue
            bounds = max(bounds[0], finished[0]), max(bounds[1], finished[1])
        if paused and opened is None:
            opened = bounds
        elif not paused and opened is not None:
            definite_pauses.append((opened[1], bounds[0]))
            possible_pauses.append((opened[0], bounds[1]))
            opened = None
    if opened is not None:
        definite_pauses.append((opened[1], end)); possible_pauses.append((opened[0], end))
    active_lower = (end-start-union_length(possible_pauses, start, end))/frequency
    active_upper = (end-start-union_length(definite_pauses, start, end))/frequency
    counts = {"definite": 0, "optional": 0, "unmapped": 0, "outside": 0}
    per_session = {}
    for row in steps:
        member = membership(row.get("_completion_bounds"), start, end)
        counts[member] += 1
        if member in ("definite", "optional"):
            bucket = per_session.setdefault(str(row.get("hospital_session")), {"definite_completions": 0, "optional_completions": 0})
            bucket[member+"_completions"] += 1
    if counts["unmapped"]:
        issues.append("unmapped step completions")
    lower = counts["definite"]*.1/(active_upper*selected_speed) if active_upper > 0 else None
    upper = (counts["definite"]+counts["optional"])*.1/(active_lower*selected_speed) if active_lower > 0 else None
    return {"ratio_lower": lower, "ratio_upper": upper, "active_real_seconds_lower": active_lower,
            "active_real_seconds_upper": active_upper, "completed_ticks": counts, "per_session": per_session,
            "issues": sorted(set(issues)), "definite_pause_intervals_qpc":definite_pauses,
            "possible_pause_intervals_qpc":possible_pauses,
            "pause_policy": "player/focus only; already-started waiting charged until original completion"}


def step_population(steps, start, end, minimum, limits):
    definite, optional = [], []
    for row in steps:
        category = membership(row.get("_start_bounds"), start, end)
        if category == "definite": definite.append(row["elapsed_us"]/1000)
        elif category == "optional": optional.append(row["elapsed_us"]/1000)
    result = bounded_distribution(definite, optional, minimum, limits)
    selected = [r for r in steps if membership(r.get("_start_bounds"), start, end) in ("definite", "optional")]
    result["main_execution_ms"] = distribution([r["main_elapsed_us"]/1000 for r in selected])
    result["between_slices_wall_ms"] = distribution([r["between_slices_wall_us"]/1000 for r in selected])
    result["main_time_kind"] = "sum of main-thread execution wall slices; not OS CPU time"
    return result


def check_status(label, status, errors, missing):
    if status == "failed": errors.append(label+" threshold failed")
    elif status != "observed_within_limits": missing.append(label+": "+status)


def evidence_sources(root, sources):
    """A conclusion flag is insufficient without preserved, hashed artifacts."""
    if not isinstance(sources, list) or not sources:
        return False
    for source in sources:
        if not isinstance(source, dict) or not source.get("path") or not source.get("sha256"):
            return False
        path = Path(source["path"])
        path = path if path.is_absolute() else root/path
        if not path.is_file() or sha256_file(path) != source["sha256"]:
            return False
    return True


def analyze(root, balance):
    root, balance = Path(root), Path(balance)
    meta, config = load(root/"capture.json"), load(root/"scenario.json")
    targets = load(balance)["performance_targets"]
    errors, missing = [], []
    frequency = meta["qpc_frequency"]
    if not isinstance(frequency, int) or frequency <= 0: raise ValueError("invalid QPC frequency")
    if meta.get("error"): errors.append(meta["error"])
    if meta.get("forced_processes") or meta.get("watchdog_expired"): errors.append("forced_or_timed_out_process")
    for process in meta.get("processes", []):
        if process.get("exit_code") != 0: errors.append(f"{process['stem']}_exit_{process.get('exit_code')}")
    if not any(r.get("stem") == "game" for r in meta.get("processes", [])): missing.append("owned game exit identity")
    for path in root.glob("*.log"):
        if re.search(r"SCRIPT ERROR:|(?m:^ERROR:)", path.read_text(encoding="utf-8-sig", errors="replace")):
            errors.append("runtime_script_error")
    trace = meta.get("trace_final") or {}
    loss_fields = ("events_lost", "log_buffers_lost", "realtime_buffers_lost")
    if trace.get("code") != 0 or any(trace.get(k) is None for k in loss_fields): missing.append("final ETW loss counters")
    elif any(trace[k] > 0 for k in loss_fields): errors.append("ETW events/buffers lost")
    diagnostics = load(root/"presentmon-diagnostics.json") if (root/"presentmon-diagnostics.json").exists() else {}
    internal_loss = diagnostics.get("internal_lost_present_count", meta.get("presentmon_internal_lost_present_count"))
    if diagnostics and diagnostics.get("presentmon_sha256") != meta.get("presentmon_sha256"):
        errors.append("PresentMon diagnostic tool identity mismatch")
    if diagnostics and not evidence_sources(root, diagnostics.get("sources")):
        missing.append("PresentMon diagnostic source identity")
    if internal_loss is not None and internal_loss != 0: errors.append("PresentMon internal presents lost")
    chains, endpoints, frame_errors, skipped = displayed_intervals(root/"presentmon.csv", meta["pid"], frequency)
    errors.extend(frame_errors)
    selected = config.get("swapchain_address") or meta.get("selected_swapchain")
    selected = swapchain(selected) if selected else None
    if len(chains) != 1 and not config.get("swapchain_address"): missing.append("primary window swapchain attribution")
    all_frames = chains.get(selected, [])
    request_start = meta.get("window_start_qpc", meta.get("window_start_request_qpc"))
    end = meta.get("window_end_qpc", meta.get("window_end_request_qpc"))
    if request_start is None or end is None or end <= request_start: raise ValueError("no complete acknowledged window")
    starts = [f["start_ms"]*frequency/1000 for f in all_frames if f["start_ms"]*frequency/1000 >= request_start]
    start = min(starts) if starts else request_start
    frames = [f for f in all_frames if start <= f["start_ms"]*frequency/1000 < end]
    tail_complete = bool(frames) and frames[-1]["end_ms"]*frequency/1000 >= end
    if not tail_complete: missing.append("complete original tail display interval")
    telemetry = rows(root/"telemetry.ndjson")
    if any(r.get("kind") == "incomplete" for r in telemetry): errors.append("runner incomplete marker")
    if not any(r.get("kind") == "scenario_complete" for r in telemetry): missing.append("scenario_complete marker")
    if not any(r.get("kind") == "exit" and r.get("exit_code") == 0 for r in telemetry): missing.append("normal runner exit marker")
    clock = ClockBounds(telemetry, frequency)
    if not clock.samples: missing.append("native QPC/engine/QPC samples")
    steps = [dict(r) for r in telemetry if r.get("kind") == "step"]
    sessions = {}
    for row in steps:
        required = ("started_engine_us", "completed_engine_us", "elapsed_us", "main_elapsed_us", "between_slices_wall_us", "tick", "hospital_session")
        if any(row.get(k) is None for k in required): raise ValueError("step lacks original four timing fields/session/tick")
        if row["completed_engine_us"]-row["started_engine_us"] != row["elapsed_us"] or not 0 <= row["main_elapsed_us"] <= row["elapsed_us"] or row["between_slices_wall_us"] != row["elapsed_us"]-row["main_elapsed_us"]:
            errors.append("step timing invariant violated")
        previous = sessions.get(row["hospital_session"])
        if previous is not None and row["tick"] != previous+1: errors.append("missing_or_duplicate_tick_in_session")
        sessions[row["hospital_session"]] = row["tick"]
        if row.get("qpc_frequency") != frequency: errors.append("step QPC frequency mismatch")
        row["_start_bounds"] = clock.map(row["started_engine_us"], row.get("completion_qpc_ticks"))
        row["_completion_bounds"] = clock.map(row["completed_engine_us"], row.get("completion_qpc_ticks"))
    frame_limits = dict(zip(("p95_ms", "p99_ms", "max_ms"), (targets["metrics"][k] for k in ("frame_p95_ms", "frame_p99_ms", "ordinary_frame_max_ms"))))
    step_limits = dict(zip(("p95_ms", "p99_ms", "max_ms"), (targets["metrics"][k] for k in ("sim_step_p95_ms", "sim_step_p99_ms", "sim_step_ordinary_max_ms"))))
    speed = speed_window(telemetry, steps, clock, start, end, frequency, config["speed"])
    definite_frames, optional_frames = [], []
    for frame in frames:
        at = frame["start_ms"]*frequency/1000
        if any(a <= at < b for a,b in speed["definite_pause_intervals_qpc"]): continue
        (optional_frames if any(a <= at < b for a,b in speed["possible_pause_intervals_qpc"]) else definite_frames).append(frame["duration_ms"])
    frame_stats = bounded_distribution(definite_frames, optional_frames, targets["capture"]["minimum_frame_samples"], frame_limits)
    frame_stats.update(tail_complete=tail_complete, skipped=skipped, swapchains_observed=list(chains), pause_frames_excluded=len(frames)-len(definite_frames)-len(optional_frames))
    check_status("frame", frame_stats["status"], errors, missing)
    step_stats = step_population(steps, start, end, targets["capture"]["minimum_step_samples"], step_limits)
    step_stats["clock_enclosure_max_ms"] = max(((r["_start_bounds"][1]-r["_start_bounds"][0])*1000/frequency for r in steps if r["_start_bounds"]), default=None)
    if any(r["_start_bounds"] is None and r.get("capture_step") for r in steps): missing.append("capture step start cannot be clock-enclosed")
    check_status("step", step_stats["status"], errors, missing)
    missing.extend(speed["issues"])
    threshold = targets["metrics"]["sim_speed_ratio_min"]
    speed["status"] = "observed_within_limits" if speed["ratio_lower"] is not None and speed["ratio_lower"] >= threshold else "failed" if speed["ratio_upper"] is not None and speed["ratio_upper"] < threshold else "boundary_uncertain"
    check_status("speed", speed["status"], errors, missing)
    dense = []
    if config.get("dense"):
        opened = None
        for row in telemetry:
            if row.get("kind") == "dense_segment_begin": opened = row
            elif row.get("kind") == "dense_segment_end" and opened:
                lower, upper = max(start, opened["qpc_ticks"]), min(end, row["qpc_ticks"])
                if upper > lower:
                    members = [f for f in all_frames if lower <= f["start_ms"]*frequency/1000 < upper]
                    ss = step_population(steps, lower, upper, targets["capture"]["minimum_step_samples"], step_limits)
                    ds = speed_window(telemetry, steps, clock, lower, upper, frequency, config["speed"])
                    definite_dense, optional_dense = [], []
                    for frame in members:
                        at = frame["start_ms"]*frequency/1000
                        if any(a <= at < b for a,b in ds["definite_pause_intervals_qpc"]): continue
                        (optional_dense if any(a <= at < b for a,b in ds["possible_pause_intervals_qpc"]) else definite_dense).append(frame["duration_ms"])
                    fs = bounded_distribution(definite_dense, optional_dense, targets["capture"]["minimum_frame_samples"], frame_limits)
                    fs["tail_complete"] = bool(members) and members[-1]["end_ms"]*frequency/1000 >= upper
                    ds["status"] = "observed_within_limits" if ds["ratio_lower"] is not None and ds["ratio_lower"] >= threshold else "failed" if ds["ratio_upper"] is not None and ds["ratio_upper"] < threshold else "boundary_uncertain"
                    observations = [d for d in telemetry if d.get("kind") == "density" and lower <= d["qpc_ticks"] < upper]
                    density_ok = bool(observations) and all(d.get("density_bp", 0) >= targets["spatial_samples"]["minimum_density_bp"] and d.get("denominator") == config.get("dense_target_actors", config["actors"]) for d in observations)
                    dense.append({"segment":opened.get("segment"), "start_qpc":lower,"end_qpc":upper,"frames":fs,"steps":ss,"speed":ds,"logical_density_qualifies":density_ok,"observations":len(observations)})
                    check_status("dense frame "+str(opened.get("segment")), fs["status"], errors, missing)
                    check_status("dense step "+str(opened.get("segment")), ss["status"], errors, missing)
                    check_status("dense speed "+str(opened.get("segment")), ds["status"], errors, missing)
                    if not fs["tail_complete"]: missing.append("dense complete tail interval")
                    missing.extend(ds["issues"])
                    if not density_ok: missing.append("dense >=90% continuity evidence")
                opened = None
        if not dense: missing.append("qualified dense segments")
        missing.append("raster-visible density corroboration (frustum bindings alone insufficient)")
    process_all = rows(root/"process.ndjson")
    process = [r for r in process_all if start <= r["qpc_ticks"] <= end]
    memory = {"samples":len(process),"requested_poll_ms":meta["poll_requested_ms"],"polling_peak_is_strict_upper_bound":False}
    for output, source in (("observed_peak_working_set_bytes","working_set_bytes"),("observed_peak_private_commit_bytes","private_commit_bytes")):
        memory[output] = max((r[source] for r in process), default=None)
    for field in ("lifetime_peak_working_set_bytes","lifetime_peak_private_commit_bytes"):
        memory[field] = max((r[field] for r in process_all if field in r), default=None)
    memory["observed_max_poll_gap_ms"] = max(((b["qpc_ticks"]-a["qpc_ticks"])*1000/frequency for a,b in zip(process,process[1:])), default=None)
    memory["kernel_lifetime_peaks_cover_window"] = any(r["qpc_ticks"] >= end and all(r.get(k) is not None for k in ("lifetime_peak_working_set_bytes","lifetime_peak_private_commit_bytes")) for r in process_all)
    memory["kernel_peak_scope"] = "OS lifetime peaks sampled after window; upper bound for this window, not its exact local peak"
    if not process: missing.append("OS process memory samples")
    elif config.get("actors") == 160 and not config.get("large_world") and memory["observed_peak_working_set_bytes"] > targets["metrics"]["working_set_target_bytes"]: errors.append("baseline working set observed above target")
    graphics = load(root/"graphics-evidence.json") if (root/"graphics-evidence.json").exists() else {}
    graphics_valid = graphics.get("status") == "verified" and graphics.get("pid") == meta["pid"] and graphics.get("window_start_qpc", end) <= start and graphics.get("window_end_qpc", 0) >= end and evidence_sources(root, graphics.get("allocation_identity_sources")) and graphics.get("shared_dedup_verified") is True and graphics.get("unreleased_included") is True
    if not graphics_valid: missing.append("actual graphics allocation/residency/shared-dedup evidence")
    elif graphics.get("peak_allocated_bytes") is None: missing.append("complete graphics allocation peak")
    elif graphics["peak_allocated_bytes"] > targets["metrics"]["graphics_resources_target_bytes"]: errors.append("graphics allocation target exceeded")
    if not memory["kernel_lifetime_peaks_cover_window"]: missing.append("transient process allocation peak coverage beyond polling")
    elif config.get("actors") == 160 and not config.get("large_world") and memory["lifetime_peak_working_set_bytes"] > targets["metrics"]["working_set_target_bytes"] and not any("working set" in e for e in errors):
        missing.append("lifetime working-set peak exceeds target; exact window peak attribution required")
    def opkey(value): return str(value.get("id", value.get("action"))) if isinstance(value, dict) else str(value)
    operations = [r for r in telemetry if r.get("kind") == "operation_complete"]
    required = {opkey(o) for o in config.get("operations", [])}
    completed = {opkey(r.get("operation")) for r in operations}
    if required-completed: missing.append("operation evidence: "+",".join(sorted(required-completed)))
    for operation in operations:
        if opkey(operation.get("operation")) in required and operation.get("ok") is False: errors.append("operation failed: "+opkey(operation.get("operation")))
    saves = []
    copy_spans = []
    baseline_save = config.get("actors") == 160 and config.get("workload_kind","reference") == "reference" and not config.get("large_world")
    for row in telemetry:
        if row.get("kind") == "save_receipt" and row.get("elapsed_us") is not None and row.get("request_observation"):
            origin = row["request_observation"]
            category = membership(clock.map(origin.get("begin_engine_us"),row.get("qpc_ticks")),start,end)
            if category in ("definite","optional"):
                saves.append({"request_id":row.get("receipt",{}).get("request_id"),"slot_kind":origin.get("slot_kind"),"seconds":row["elapsed_us"]/1000000,"membership":category,"ok":row.get("receipt",{}).get("ok"),"scope":row.get("duration_kind")})
                if not row.get("receipt",{}).get("ok"): errors.append("original save receipt failed")
                if baseline_save and row["elapsed_us"]/1000000 > targets["metrics"]["save_max_seconds"]:
                    (errors if category == "definite" else missing).append("save total exceeds baseline target" if category == "definite" else "save total boundary uncertainty")
        if row.get("kind") == "main_phase" and row.get("stage") == "snapshot_begin_world_main_inclusive":
            category = membership(clock.map(row.get("begin_us"),row.get("qpc_ticks")),start,end)
            if category in ("definite","optional"): copy_spans.append(row["elapsed_us"]/1000)
    save_required = any(o.get("action") in ("save","wait_autosave") for o in config.get("operations",[]))
    if save_required and not saves: missing.append("matched original save request-to-receipt duration")
    copy_stats = distribution(copy_spans)
    if baseline_save and save_required and (not copy_spans or copy_stats["p95_ms"] > targets["metrics"]["snapshot_copy_p95_ms"]):
        missing.append("isolated DTO copy timing; inclusive validate/estimate/freeze span cannot assign its excess to copy")
    previews = [r for r in telemetry if r.get("kind") == "preview_target_complete"]
    if any(o.get("action") == "preview_input" for o in config.get("operations",[])):
        if not previews: missing.append("real input to complete target preview")
        missing.append("correct displayed preview frame association; callback and next-present candidate are separate")
    for preview in previews:
        candidate = next((f for f in all_frames if f["present_qpc_ticks"] >= preview.get("completion_qpc_ticks",math.inf)),None)
        preview["next_present_candidate_display_qpc"] = candidate["end_ms"]*frequency/1000 if candidate else None
        preview["display_content_verified"] = False
        if preview.get("operation_input_to_target_result_us",0)/1000 > targets["metrics"]["room_preview_p95_ms"]:
            errors.append("complete room preview callback alone exceeds displayed-latency target")
    boot = next((r for r in telemetry if r.get("kind") == "boot"), {})
    if not boot: missing.append("actual Release/renderer/settings identity")
    elif boot.get("settings", {}).get("window_pixels") != config.get("window_pixels"): errors.append("actual window pixels mismatch")
    if (end-start)/frequency < config.get("minimum_capture_real_seconds", 0): missing.append("minimum scenario wall duration")
    timing_missing = [m for m in missing if not any(x in m for x in ("graphics", "transient", "raster"))]
    report = {"schema_version":2,"kind":"formal_condition_analysis","scenario":config.get("name",config.get("run_id")),
              "condition":{k:config.get(k) for k in ("actors","layout","window_pixels","scene_scale_bp","ui_scale_percent","speed")},
              "window":{"start_qpc":start,"end_qpc":end,"frequency":frequency,"duration_seconds":(end-start)/frequency,"start_kind":"first distinct display boundary after native started ACK","end_kind":"native complete-boundary stopped ACK"},
              "frames":frame_stats,"steps":step_stats,"speed":speed,"speed_ratio":speed["ratio_lower"],"dense_segments":dense,"memory":memory,
              "gpu_pid_aggregate_samples":sum(r.get("status")=="observed" for r in rows(root/"gpu-process-memory.ndjson")),
              "presentmon_quality":{"etw_loss":trace,"dropped_not_displayed":skipped["not_displayed"],"internal_lost_present_count":internal_loss,
                  "internal_loss_scope":"diagnostic unavailable in standard CSV when null; not inferred zero; frame validity uses ETW loss, actual distinct display fields, chain continuity and complete tail"},
              "graphics_evidence_verified":graphics_valid,"operations":operations,"save_totals":saves,
              "snapshot_main_inclusive_ms":copy_stats,"snapshot_copy_evidence":"upper bound only when whole inclusive span meets copy target; excess requires isolated evidence",
              "preview_targets":previews,"main_phases":[r for r in telemetry if r.get("kind")=="main_phase"],
              "errors":sorted(set(errors)),"missing":sorted(set(missing)),"timing_pass":not errors and not timing_missing,
              "formal_pass":not errors and not missing,"status":"failed" if errors else "incomplete" if missing else "passed",
              "balance_sha256":hashlib.sha256(balance.read_bytes()).hexdigest(),"scope":"one condition only; not complete product/matrix acceptance"}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("--balance", type=Path, default=Path(__file__).resolve().parents[3]/"docs/data/balance.json")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = analyze(args.run, args.balance)
        code = 1 if report["errors"] else 2 if report["missing"] else 0
    except (ValueError, KeyError, OSError, csv.Error, TypeError, OverflowError) as error:
        report = {"status":"incomplete","formal_pass":False,"tool_error":str(error)}; code = 2
    output = args.output or args.run/"analysis.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status":report["status"],"formal_pass":report["formal_pass"],"output":str(output)},ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
