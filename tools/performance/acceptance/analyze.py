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
    return sorted_distribution(sorted(values))


def sorted_distribution(values):
    return {"samples": len(values), "p95_ms": values[math.ceil(.95*len(values))-1] if values else None,
            "p99_ms": values[math.ceil(.99*len(values))-1] if values else None,
            "max_ms": max(values) if values else None, "mean_ms": sum(values)/len(values) if values else None}


def merged_rank(first, second, begin, count, rank):
    """One-based exact rank in two sorted ranges, without materialising them."""
    low, high = max(0, rank-count), min(rank, len(first))
    while low <= high:
        a = (low+high)//2
        b = rank-a
        a_left = first[a-1] if a else -math.inf
        a_right = first[a] if a < len(first) else math.inf
        b_left = second[begin+b-1] if b else -math.inf
        b_right = second[begin+b] if b < count else math.inf
        if a_left <= b_right and b_left <= a_right:
            return max(a_left, b_left)
        if a_left > b_right:
            high = a-1
        else:
            low = a+1
    raise ValueError("rank outside the complete merged population")


def bounded_distribution(definite, optional, minimum, limits):
    """Every possible membership, without picking a favourable boundary subset.

    For k optional observations the largest quantile uses the k largest optional
    values, the smallest uses the k smallest. Evaluate every k with nearest rank.
    """
    ordered = sorted(definite)
    base = sorted_distribution(ordered)
    possible = sorted(optional)
    prefix = [0]
    for value in possible:
        prefix.append(prefix[-1]+value)
    base_sum = sum(ordered)
    lower = dict.fromkeys(limits)
    upper = dict.fromkeys(limits)
    for count in range(len(possible)+1):
        size = len(ordered)+count
        for begin, bounds, select in ((0, lower, min), (len(possible)-count, upper, max)):
            for key in limits:
                if key == "samples":
                    value = size
                elif not size:
                    value = None
                elif key in ("p95_ms", "p99_ms"):
                    rank = math.ceil((.95 if key == "p95_ms" else .99)*size)
                    value = merged_rank(ordered, possible, begin, count, rank)
                elif key == "max_ms":
                    value = max(ordered[-1] if ordered else -math.inf,
                                possible[begin+count-1] if count else -math.inf)
                elif key == "mean_ms":
                    value = base["mean_ms"] if not count else (base_sum+(prefix[begin+count]-prefix[begin]))/size
                else:
                    raise KeyError(key)
                if value is not None:
                    bounds[key] = value if bounds[key] is None else select(bounds[key], value)
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


class PointWindows:
    """Range lookup which restores original record order, including ties."""
    def __init__(self, records, point):
        self.entries = sorted((point(row), position, row) for position, row in enumerate(records))
        self.points = [entry[0] for entry in self.entries]

    def select(self, start, end):
        selected = self.entries[bisect.bisect_left(self.points, start):bisect.bisect_left(self.points, end)]
        return [entry[2] for entry in sorted(selected, key=lambda entry: entry[1])]


class IntervalWindows:
    """Index lower < end and upper >= start, retaining uncertainty and order."""
    def __init__(self, records, field):
        self.entries = sorted((row[field][0], position, row[field][1], row)
                              for position, row in enumerate(records) if row.get(field) is not None)
        self.lowers = [entry[0] for entry in self.entries]
        self.unmapped = len(records)-len(self.entries)
        self.maxima = [-math.inf]*(4*len(self.entries))
        if self.entries:
            self._build(1, 0, len(self.entries))

    def _build(self, node, lower, upper):
        if upper-lower == 1:
            self.maxima[node] = self.entries[lower][2]
            return
        middle = (lower+upper)//2
        self._build(node*2, lower, middle)
        self._build(node*2+1, middle, upper)
        self.maxima[node] = max(self.maxima[node*2], self.maxima[node*2+1])

    def select(self, start, end):
        found = []
        limit = bisect.bisect_left(self.lowers, end)
        def visit(node, lower, upper):
            if lower >= limit or self.maxima[node] < start:
                return
            if upper-lower == 1:
                found.append(self.entries[lower])
                return
            middle = (lower+upper)//2
            visit(node*2, lower, middle)
            visit(node*2+1, middle, upper)
        if limit:
            visit(1, 0, len(self.entries))
        return [entry[3] for entry in sorted(found, key=lambda entry: entry[1])]


class IntervalUnion:
    def __init__(self, intervals):
        merged = []
        for lower, upper in sorted(intervals):
            if upper <= lower:
                continue
            if merged and lower <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(merged[-1][1], upper))
            else:
                merged.append((lower, upper))
        self.starts = [pair[0] for pair in merged]
        self.ends = [pair[1] for pair in merged]
        self.prefix = [0]
        for lower, upper in merged:
            self.prefix.append(self.prefix[-1]+(upper-lower))

    def before(self, point):
        index = bisect.bisect_right(self.ends, point)
        result = self.prefix[index]
        if index < len(self.starts) and self.starts[index] < point:
            result += point-self.starts[index]
        return result

    def covered(self, start, end):
        return max(0.0, self.before(end)-self.before(start))


class StepWindows:
    def __init__(self, steps):
        self.steps = steps
        self.starts = IntervalWindows(steps, "_start_bounds")
        self.completions = IntervalWindows(steps, "_completion_bounds")
        self.by_start = {}
        for row in steps:
            self.by_start.setdefault((row.get("hospital_session"), row.get("started_engine_us")), row)

    def completed(self, start, end):
        selected = self.completions.select(start, end)
        counts = {"definite": 0, "optional": 0, "unmapped": self.completions.unmapped,
                  "outside": len(self.steps)-self.completions.unmapped-len(selected)}
        per_session = {}
        for row in selected:
            member = membership(row.get("_completion_bounds"), start, end)
            counts[member] += 1
            bucket = per_session.setdefault(str(row.get("hospital_session")), {"definite_completions": 0, "optional_completions": 0})
            bucket[member+"_completions"] += 1
        return counts, per_session


class SpeedWindows:
    """Resolve the immutable playback history and started-step joins once."""
    def __init__(self, telemetry, steps, clock):
        self.steps = steps
        self.states = sorted((r for r in telemetry if r.get("kind") == "session_state" and r.get("qpc_ticks") is not None), key=lambda r: r["qpc_ticks"])
        self.points = PointWindows(self.states, lambda r: r["qpc_ticks"])
        self.unmapped_states = set()
        self.definite, self.possible, self.issues = [], [], []
        self.opened = None
        for position, row in enumerate(self.states):
            actual = row.get("actual_speed")
            paused = actual == 0 and (row.get("requested_speed") == 0 or "focus" in row.get("pause_reasons", []))
            bounds = clock.map(row.get("engine_us"))
            if bounds is None:
                self.unmapped_states.add(id(row))
                continue
            if paused and row.get("step_in_progress"):
                matching = steps.by_start.get((row.get("hospital_session"), row.get("original_step_started_us")))
                if matching is None:
                    self.issues.append("started step missing at pause boundary")
                    continue
                finished = matching.get("_completion_bounds")
                if finished is None:
                    self.issues.append("started step completion cannot be mapped")
                    continue
                bounds = max(bounds[0], finished[0]), max(bounds[1], finished[1])
            if paused and self.opened is None:
                self.opened = bounds
            elif not paused and self.opened is not None:
                self.definite.append((self.opened[1], bounds[0]))
                self.possible.append((self.opened[0], bounds[1]))
                self.opened = None
        self.definite_union = IntervalUnion(self.definite)
        self.possible_union = IntervalUnion(self.possible)

    def _paused_length(self, union, offset, start, end):
        length = union.covered(start, end)
        if self.opened is not None:
            tail_start = max(start, self.opened[offset])
            if tail_start < end:
                length += end-tail_start-union.covered(tail_start, end)
        return length

    def window(self, start, end, frequency, selected_speed):
        issues = list(self.issues)
        if not self.states or self.states[0]["qpc_ticks"] > start:
            issues.append("playback state before window unavailable")
        for row in self.points.select(start, end):
            if row.get("actual_speed") not in (0, selected_speed):
                issues.append("speed changed within condition; separate windows required")
            if id(row) in self.unmapped_states:
                issues.append("playback transition clock enclosure unavailable")
        definite = self.definite+[(self.opened[1], end)] if self.opened is not None else self.definite
        possible = self.possible+[(self.opened[0], end)] if self.opened is not None else self.possible
        active_lower = (end-start-self._paused_length(self.possible_union, 0, start, end))/frequency
        active_upper = (end-start-self._paused_length(self.definite_union, 1, start, end))/frequency
        counts, per_session = self.steps.completed(start, end)
        if counts["unmapped"]:
            issues.append("unmapped step completions")
        lower = counts["definite"]*.1/(active_upper*selected_speed) if active_upper > 0 else None
        upper = (counts["definite"]+counts["optional"])*.1/(active_lower*selected_speed) if active_lower > 0 else None
        return {"ratio_lower": lower, "ratio_upper": upper, "active_real_seconds_lower": active_lower,
                "active_real_seconds_upper": active_upper, "completed_ticks": counts, "per_session": per_session,
                "issues": sorted(set(issues)), "definite_pause_intervals_qpc": definite,
                "possible_pause_intervals_qpc": possible,
                "pause_policy": "player/focus only; already-started waiting charged until original completion"}


def union_length(intervals, start, end):
    total, current = 0.0, start
    for lower, upper in sorted(intervals):
        lower, upper = max(start, lower), min(end, upper)
        if upper > max(current, lower):
            total += upper-max(current, lower)
            current = upper
    return total


def speed_window(telemetry, steps, clock, start, end, frequency, selected_speed, index=None):
    if index is None:
        index = SpeedWindows(telemetry, StepWindows(steps), clock)
    return index.window(start, end, frequency, selected_speed)


def step_population(steps, start, end, minimum, limits, index=None):
    definite, optional, selected = [], [], []
    for row in (index.starts.select(start, end) if index is not None else steps):
        category = membership(row.get("_start_bounds"), start, end)
        if category == "definite": definite.append(row["elapsed_us"]/1000)
        elif category == "optional": optional.append(row["elapsed_us"]/1000)
        if category in ("definite", "optional"): selected.append(row)
    result = bounded_distribution(definite, optional, minimum, limits)
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


def allocation_evidence(root, meta, start, end, frequency, target_bytes):
    """Validate ledger provenance before interpreting its separate proof scopes."""
    root = Path(root)
    path = root/"allocation-ledger.json"
    out = {"present": path.is_file(), "verified": False, "status": "incomplete", "checks": {}, "missing": [], "errors": [],
           "allocation_identity": {"status": "missing"}, "allocation_accounting": {"status": "missing"},
           "formal_window": {"verified": False}, "os_aggregate_counters": [], "budget": {"status": "incomplete", "target_bytes": target_bytes}}
    if not path.is_file():
        out["missing"].append("graphics allocation ledger with complete accounting and OS residency view")
        return out
    checks = out["checks"]
    def integer(value): return type(value) is int and value >= 0
    def bounds(a, b): return type(a) in (int, float) and type(b) in (int, float) and math.isfinite(a) and math.isfinite(b) and a > 0 and a < b
    def resolve(value):
        value = Path(value)
        return (value if value.is_absolute() else root/value).resolve()
    try:
        ledger = load(path)
        if not isinstance(ledger, dict): raise ValueError("ledger must be a JSON object")
        out.update(ledger_source={"path":str(path.resolve()), "sha256":sha256_file(path)},
                   allocation_identity=ledger.get("allocation_identity", {}), allocation_accounting=ledger.get("allocation_accounting", {}),
                   backing_size_corroboration=ledger.get("backing_size_corroboration", {"status":"missing"}),
                   formal_window=ledger.get("formal_window", {}), ledger_status=ledger.get("status"), ledger_missing=ledger.get("missing", []),
                   lifecycle_observed_graph_peak_alloc_size_bytes=ledger.get("known_sequence_peak_allocated_bytes"),
                   lifecycle_observed_graph_upper_peak_alloc_size_bytes=ledger.get("known_same_timestamp_upper_peak_allocated_bytes"))
        checks["schema2"] = ledger.get("schema_version") == 2 and ledger.get("kind") == "dxgkrnl_allocation_ledger"
        games = [p for p in meta.get("processes", []) if p.get("stem") == "game" and p.get("pid") == meta.get("pid")]
        checks["same_pid_and_lifetime"] = (ledger.get("target_pid") == meta.get("pid") and len(games) == 1
            and integer(games[0].get("start_utc_ticks")) and games[0]["start_utc_ticks"] > 0
            and ledger.get("target_start_utc_ticks") == games[0]["start_utc_ticks"])
        checks["matching_positive_frequency"] = type(frequency) is int and frequency > 0 and ledger.get("qpc_frequency") == frequency
        required_provenance = ("events_hash_matches_decode_output", "schema_hash_matches_decode_input", "etl_input_unchanged_during_decode", "supplemental_provenance_verified", "required_event_families_in_decode_selection")
        provenance = ledger.get("input_provenance", {})
        checks["ledger_input_provenance"] = provenance.get("verified") is True and all(provenance.get("checks", {}).get(k) is True for k in required_provenance)
        raw_keys = ("decoder_raw_qpc_valid", "full_etl_read_complete", "process_and_close_succeeded", "qpc_header_clock", "zero_file_loss", "all_interpreted_events_have_raw_qpc", "one_matching_positive_frequency")
        checks["ledger_raw_qpc"] = ledger.get("raw_qpc_verified") is True and all(ledger.get("raw_qpc_checks", {}).get(k) is True for k in raw_keys)
        sources, sources_ok = {}, isinstance(ledger.get("sources"), list) and bool(ledger.get("sources"))
        for source in ledger.get("sources", []):
            source_path = resolve(source["path"])
            actual = sha256_file(source_path) if source_path.is_file() else None
            sources_ok = sources_ok and source_path not in sources and actual == source.get("sha256")
            sources[source_path] = actual
        checks["preserved_source_hashes"] = sources_ok
        trace_path, schema_path, capture_path = (root/"allocation/trace.json").resolve(), (root/"allocation/provider-schema.json").resolve(), (root/"capture.json").resolve()
        checks["same_capture_trace_schema_sources"] = all(p in sources and sources[p] is not None for p in (trace_path, schema_path, capture_path))
        trace = load(trace_path)
        checks["trace_pid_lifetime_frequency"] = (trace.get("target_pid") == meta.get("pid") and trace.get("target_start_utc_ticks") == ledger.get("target_start_utc_ticks")
            and trace.get("qpc_frequency") == frequency and trace.get("started_before_target") is True and trace.get("error") is None)
        final = trace.get("trace_final") or {}
        checks["zero_trace_loss"] = final.get("code") == 0 and all(final.get(k) == 0 for k in ("events_lost", "log_buffers_lost", "realtime_buffers_lost"))
        candidates = [load(p) for p in sources if p.name.endswith(".meta.json") and p.is_file()]
        decodes = [d for d in candidates if isinstance(d, dict) and d.get("kind") == "offline_raw_etl_decode"]
        checks["one_raw_decode_meta"] = len(decodes) == 1
        decode = decodes[0] if len(decodes) == 1 else {}
        result, header = decode.get("result", {}), decode.get("result", {}).get("TraceHeader", {})
        etl_path = (root/"allocation/dxgkrnl.etl").resolve()
        etl_hash = sha256_file(etl_path) if etl_path.is_file() else None
        checks["same_original_etl"] = (bool(etl_hash) and resolve(decode.get("etl_path", ".")) == etl_path
            and etl_hash == decode.get("etl_sha256") == decode.get("etl_sha256_after"))
        output_path = resolve(decode.get("output", "."))
        checks["raw_output_schema_hashes"] = (output_path in sources and bool(sources[output_path]) and sources[output_path] == decode.get("output_sha256")
            and resolve(decode.get("schema_path", ".")) == schema_path and bool(sources.get(schema_path))
            and sources[schema_path] == decode.get("schema_sha256") == decode.get("schema_sha256_after"))
        checks["decode_clock_api_loss"] = (decode.get("raw_qpc_valid") is True and decode.get("tool_error") is None and result.get("RawFileReadComplete") is True
            and decode.get("process_trace_mode_bits") == "0x10001000" and decode.get("qpc_ticks_are_raw_header_timestamp") is True
            and decode.get("raw_timestamp_is_unconverted_header_timestamp") is True and decode.get("qpc_frequency") == frequency
            and result.get("ProcessStatus") == 0 and result.get("CloseStatus") == 0 and header.get("reserved_flags_clock_type") == 1
            and header.get("perf_frequency") == frequency and header.get("events_lost") == 0 and header.get("buffers_lost") == 0
            and integer(header.get("end_time_filetime")) and header["end_time_filetime"] > 0)
        window = out["formal_window"]
        ws, we = window.get("start_qpc"), window.get("end_qpc")
        checks["formal_window_covers_actual"] = window.get("verified") is True and bounds(start, end) and bounds(ws, we) and ws <= start and we >= end
        first, last = result.get("FirstRawTimestamp"), result.get("LastRawTimestamp")
        checks["etl_covers_ledger_and_actual_window"] = integer(first) and integer(last) and bounds(ws, we) and first <= ws < we <= last
        out["formal_window"] = {**window, "actual_analysis_window":{"start_qpc":start, "end_qpc":end},
            "same_actual_window": ws == start and we == end, "covers_actual_window":checks["formal_window_covers_actual"]}
        source_valid = all(checks.values())
        intrinsic_sources_valid = all(valid for name, valid in checks.items() if name not in ("formal_window_covers_actual", "etl_covers_ledger_and_actual_window"))
        identity, accounting = out["allocation_identity"], out["allocation_accounting"]
        out["allocation_identity"] = {**identity, "source_validated":intrinsic_sources_valid}
        out["allocation_accounting"] = {**accounting, "source_validated":intrinsic_sources_valid}
        counters = []
        for counter in ledger.get("os_aggregate_counters", []):
            cw, adapter = counter.get("formal_window", {}), counter.get("adapter_identity", {})
            lifecycle_valid = (intrinsic_sources_valid and counter.get("continuous") is True and integer(counter.get("samples")) and counter["samples"] > 0
                and counter.get("kind") in ("usage", "commitment") and adapter.get("AdapterLuid") is not None
                and adapter.get("VendorID") is not None and adapter.get("DeviceID") is not None
                and integer(counter.get("physical_adapter_index")) and integer(counter.get("memory_segment_group"))
                and integer(counter.get("observed_peak_bytes")))
            valid = (lifecycle_valid and source_valid and cw.get("verified") is True and bounds(cw.get("start_qpc"), cw.get("end_qpc"))
                and cw["start_qpc"] <= start and cw["end_qpc"] >= end and integer(cw.get("observed_peak_bytes")))
            counters.append({**counter, "status":"observed_with_window" if valid else "observed_lifecycle_only" if lifecycle_valid else "incomplete",
                "window_evidence_valid":valid, "lifecycle_evidence_valid":lifecycle_valid,
                "lifecycle_observed_peak_bytes":counter.get("observed_peak_bytes"), "window_observed_peak_bytes":cw.get("observed_peak_bytes"),
                "added_to_allocated_bytes":False})
        out["os_aggregate_counters"] = counters
        target_domains = {(a.get("adapter_pointer"), a.get("physical_adapter_index")) for a in ledger.get("allocations", [])}
        usage_domains = {(c.get("adapter_pointer"), c.get("physical_adapter_index"))
            for c in counters if c["window_evidence_valid"] and c["kind"] == "usage"}
        os_view = bool(target_domains) and target_domains <= usage_domains
        out["os_residency_view_status"] = "observed_with_window" if os_view else "incomplete"
        out["os_memory_semantics"] = "continuous process charge by adapter LUID, physical adapter and memory segment group across engine nodes; not unique physical residency; never added to allocation bound"
        qualification = accounting.get("qualification_checks", {})
        qualification_keys = ("preserved_raw_event_provenance", "complete_raw_qpc_decode", "target_identity_and_alias_join",
            "all_process_alias_capture", "all_required_event_families_armed", "saved_schema_covers_interpreted_versions",
            "formal_actual_display_window", "all_target_global_sizes_joined", "no_event_or_identity_gaps",
            "unreleased_globals_included", "positive_formal_extent_upper_bound", "backend_target_scope_bounded")
        qualification_valid = all(qualification.get(name) is True for name in qualification_keys)
        method = accounting.get("coverage_method")
        owner_coverage = accounting.get("owner_coverage", {})
        owner_valid = (method == "owner_bridged_target_graph" and owner_coverage.get("status") == "verified"
            and owner_coverage.get("unresolved_kernel_lifetimes") == 0)
        fallback = ledger.get("unattributed_kernel_global_bound", {})
        fallback_valid = (method == "adapter_kernel_fallback_upper_bound" and fallback.get("status") == "bounded"
            and integer(fallback.get("formal_upper_bound_bytes")) and fallback["formal_upper_bound_bytes"] >= 0)
        complete = (source_valid and identity.get("status") == "verified" and accounting.get("status") == "verified"
            and accounting.get("backend_coverage_verified") is True and accounting.get("unreleased_observed_globals_included") is True
            and ledger.get("peak_coverage_complete") is True and ledger.get("shared_dedup_verified") is True and qualification_valid
            and (owner_valid or fallback_valid))
        graph_upper = window.get("known_same_timestamp_upper_peak_alloc_size_bytes")
        backend_upper = accounting.get("upper_bound_allocated_bytes")
        if fallback_valid and (not integer(graph_upper) or not integer(backend_upper)
                or backend_upper < graph_upper + fallback["formal_upper_bound_bytes"]):
            complete = False
            out["missing"].append("graphics adapter/kernel fallback does not bound its observed components")
        upper = max(graph_upper, backend_upper) if integer(graph_upper) and integer(backend_upper) else None
        exact_peak = accounting.get("peak_allocated_bytes") if owner_valid else None
        lower = accounting.get("lower_bound_allocated_bytes")
        lower_checks = accounting.get("lower_bound_qualification", {})
        lower_valid = (source_valid and identity.get("status") == "verified" and integer(lower) and lower >= 0
            and ws == start and we == end and accounting.get("lower_bound_scope") == "target_allocations"
            and all(lower_checks.get(name) is True for name in ("actual_target_allocation_scope",
                "canonical_allocation_identity_deduplicated", "extent_size_semantics_verified", "simultaneous_actual_window_observation")))
        if complete and integer(upper) and integer(exact_peak) and exact_peak > upper:
            complete = False
            out["missing"].append("graphics allocation peak contradicts its supplied upper bound")
        if lower_valid and integer(upper) and complete and lower > upper:
            complete = lower_valid = False
            out["missing"].append("graphics target allocation lower bound contradicts its supplied upper bound")
        if lower_valid and lower > target_bytes:
            out["budget"] = {"status":"failed", "target_bytes":target_bytes, "lower_bound_allocated_bytes":lower,
                "scope":"proven simultaneous target allocation lower bound in actual window; not adapter-wide kernel or resident bytes"}
            out["errors"].append("graphics allocation target exceeded")
        elif complete and integer(upper) and upper <= target_bytes:
            out["budget"] = {"status":"verified_within_target", "target_bytes":target_bytes, "upper_bound_allocated_bytes":upper,
                "scope":"same window" if ws == start and we == end else "complete wider-window upper bound covers actual window"}
        elif complete and integer(exact_peak) and ws == start and we == end:
            out["budget"] = {"status":"failed" if exact_peak > target_bytes else "verified_within_target", "target_bytes":target_bytes, "peak_allocated_bytes":exact_peak, "scope":"verified actual-window allocation peak"}
            if exact_peak > target_bytes: out["errors"].append("graphics allocation target exceeded")
        elif complete:
            out["missing"].append("graphics allocation upper bound above target or unavailable; actual-window excess not established")
        if not source_valid:
            out["missing"].extend("graphics allocation evidence: " + key for key, valid in checks.items() if not valid)
        if identity.get("status") != "verified": out["missing"].append("graphics observed allocation identity join")
        if not complete: out["missing"].append("graphics complete allocation accounting: backend/size semantics, shared coverage and unreleased allocation peak")
        if not os_view: out["missing"].append("graphics OS residency view with same PID/LUID/node/segment/window")
        out["verified"] = complete and os_view and out["budget"]["status"] == "verified_within_target"
        out["status"] = "failed" if out["errors"] else "verified" if out["verified"] else "incomplete"
    except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError) as error:
        out["missing"].append("graphics allocation ledger malformed or unavailable: " + str(error))
    return out


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
    step_index = StepWindows(steps)
    speed_index = SpeedWindows(telemetry, step_index, clock)
    frame_limits = dict(zip(("p95_ms", "p99_ms", "max_ms"), (targets["metrics"][k] for k in ("frame_p95_ms", "frame_p99_ms", "ordinary_frame_max_ms"))))
    step_limits = dict(zip(("p95_ms", "p99_ms", "max_ms"), (targets["metrics"][k] for k in ("sim_step_p95_ms", "sim_step_p99_ms", "sim_step_ordinary_max_ms"))))
    speed = speed_window(telemetry, steps, clock, start, end, frequency, config["speed"], speed_index)
    definite_frames, optional_frames = [], []
    for frame in frames:
        at = frame["start_ms"]*frequency/1000
        if any(a <= at < b for a,b in speed["definite_pause_intervals_qpc"]): continue
        (optional_frames if any(a <= at < b for a,b in speed["possible_pause_intervals_qpc"]) else definite_frames).append(frame["duration_ms"])
    frame_stats = bounded_distribution(definite_frames, optional_frames, targets["capture"]["minimum_frame_samples"], frame_limits)
    frame_stats.update(tail_complete=tail_complete, skipped=skipped, swapchains_observed=list(chains), pause_frames_excluded=len(frames)-len(definite_frames)-len(optional_frames))
    check_status("frame", frame_stats["status"], errors, missing)
    step_stats = step_population(steps, start, end, targets["capture"]["minimum_step_samples"], step_limits, step_index)
    step_stats["clock_enclosure_max_ms"] = max(((r["_start_bounds"][1]-r["_start_bounds"][0])*1000/frequency for r in steps if r["_start_bounds"]), default=None)
    if any(r["_start_bounds"] is None and r.get("capture_step") for r in steps): missing.append("capture step start cannot be clock-enclosed")
    check_status("step", step_stats["status"], errors, missing)
    missing.extend(speed["issues"])
    threshold = targets["metrics"]["sim_speed_ratio_min"]
    speed["status"] = "observed_within_limits" if speed["ratio_lower"] is not None and speed["ratio_lower"] >= threshold else "failed" if speed["ratio_upper"] is not None and speed["ratio_upper"] < threshold else "boundary_uncertain"
    check_status("speed", speed["status"], errors, missing)
    dense = []
    if config.get("dense"):
        frame_index = PointWindows(all_frames, lambda row: row["start_ms"]*frequency/1000)
        density_index = PointWindows([row for row in telemetry if row.get("kind") == "density"], lambda row: row["qpc_ticks"])
        opened = None
        for row in telemetry:
            if row.get("kind") == "dense_segment_begin": opened = row
            elif row.get("kind") == "dense_segment_end" and opened:
                lower, upper = max(start, opened["qpc_ticks"]), min(end, row["qpc_ticks"])
                if upper > lower:
                    members = frame_index.select(lower, upper)
                    ss = step_population(steps, lower, upper, targets["capture"]["minimum_step_samples"], step_limits, step_index)
                    ds = speed_window(telemetry, steps, clock, lower, upper, frequency, config["speed"], speed_index)
                    definite_dense, optional_dense = [], []
                    for frame in members:
                        at = frame["start_ms"]*frequency/1000
                        if any(a <= at < b for a,b in ds["definite_pause_intervals_qpc"]): continue
                        (optional_dense if any(a <= at < b for a,b in ds["possible_pause_intervals_qpc"]) else definite_dense).append(frame["duration_ms"])
                    fs = bounded_distribution(definite_dense, optional_dense, targets["capture"]["minimum_frame_samples"], frame_limits)
                    fs["tail_complete"] = bool(members) and members[-1]["end_ms"]*frequency/1000 >= upper
                    ds["status"] = "observed_within_limits" if ds["ratio_lower"] is not None and ds["ratio_lower"] >= threshold else "failed" if ds["ratio_upper"] is not None and ds["ratio_upper"] < threshold else "boundary_uncertain"
                    observations = density_index.select(lower, upper)
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
    graphics = allocation_evidence(root, meta, start, end, frequency, targets["metrics"]["graphics_resources_target_bytes"])
    graphics_valid = graphics["verified"]
    missing.extend(graphics["missing"])
    errors.extend(graphics["errors"])
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
              "graphics_evidence_verified":graphics_valid,"graphics":graphics,"operations":operations,"save_totals":saves,
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
        if (args.run/"allocation-ledger.json").is_file():
            try:
                meta = load(args.run/"capture.json")
                report["graphics"] = allocation_evidence(args.run, meta, None, None, meta.get("qpc_frequency"), load(args.balance)["performance_targets"]["metrics"]["graphics_resources_target_bytes"])
                report["graphics_evidence_verified"] = False
            except (ValueError, KeyError, OSError, TypeError) as graphics_error:
                report["graphics_tool_error"] = str(graphics_error)
    output = args.output or args.run/"analysis.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status":report["status"],"formal_pass":report["formal_pass"],"output":str(output)},ensure_ascii=False))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
