# Frozen exhaustive reference from dev 9f7dc5b for differential tests.
# Exact boundary assertions in test_analysis.py remain independently specified.
import math


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
