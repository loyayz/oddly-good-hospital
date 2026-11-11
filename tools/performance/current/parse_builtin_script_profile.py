"""Parse Godot 4.7.2's local accumulated scripts-profiler stdout offline."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re

BEGIN = "BUILTIN_PROFILE_ACCUMULATED_BEGIN"
END = "BUILTIN_PROFILE_ACCUMULATED_END"
CAPACITY = 32768
DRIVER = "res://tools/performance/current/plain_v4.gd"
MARKER = "_builtin_profile_marker"
PREFIX_MARKER = "_builtin_profile_prefix_marker"
NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
VALUES = re.compile(
    rf"^\s*total:\s*({NUMBER})/({NUMBER})\s*%\s*self:\s*"
    rf"({NUMBER})/({NUMBER})\s*%\s*tcalls:\s*(\d+)\s*$"
)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def category(source, function):
    if source == DRIVER and function == "_run":
        return "boundary_control_frame_excluded"
    if source.startswith("res://tools/"):
        return "tool_or_observer"
    if "performance160-profile-sources" in source:
        return "generated_root_stage_source"
    return "production_script" if source.startswith("res://game/") else "other_script"


def parse(text):
    """Accept only the explicitly bracketed final accumulated table."""
    assert text.count(BEGIN) == text.count(END) == 1, "Missing/duplicate accumulated-table brackets"
    start, stop = text.index(BEGIN) + len(BEGIN), text.index(END)
    assert start < stop, "Reversed accumulated-table brackets"
    lines = [line.strip("\r") for line in text[start:stop].splitlines() if line.strip()]
    assert lines and re.fullmatch(rf"ACCUMULATED: total:\s*({NUMBER})", lines[0]), "Missing accumulated header"
    script_self_seconds = float(lines.pop(0).split("total:", 1)[1])
    assert math.isfinite(script_self_seconds) and script_self_seconds >= 0
    assert len(lines) % 2 == 0, "Incomplete signature/value pair"
    rows = []
    for offset in range(0, len(lines), 2):
        signature = re.fullmatch(r"(\d+):(.*)", lines[offset])
        values = VALUES.fullmatch(lines[offset + 1])
        assert signature and int(signature[1]) == len(rows) and values, (offset, lines[offset:offset + 2])
        parts = signature[2].rsplit("::", 2)
        source, line, function = parts if len(parts) == 3 else ("", "", signature[2])
        total, _, own, _, calls = values.groups()
        total, own, calls = float(total), float(own), int(calls)
        assert all(math.isfinite(v) and v >= 0 for v in (total, own))
        assert own <= total + 0.000001, (signature[2], total, own)
        rows.append({"index": len(rows), "signature": signature[2], "source": source,
                     "line": line, "function": function, "calls": calls,
                     "total_seconds": total, "self_seconds": own,
                     "category": category(source, function)})
    assert rows, "Empty function table"
    return {"format": "Godot 4.7.2 LocalDebugger scripts accumulated stdout",
            "function_rows": len(rows), "active_function_rows": sum(row["calls"] > 0 for row in rows),
            "table_capacity": CAPACITY, "possible_truncation": len(rows) >= CAPACITY,
            "script_self_seconds_printed": script_self_seconds,
            "periodic_frame_headers": sum(line.startswith("FRAME: total:") for line in text.splitlines()),
            "rows": rows,
            "scope": "Cross-thread/caller flat elapsed, including observers and untimed native work/waits. "
                     "Printed seconds have engine text precision. Inclusive rows must not be added; "
                     "self sums are not main-thread CPU or full-step wall. The crossing _run control frame is excluded."}


def marker_checks(profile, expected_calls, sample_wall_seconds):
    markers = [row for row in profile["rows"] if row["source"] == DRIVER and row["function"] == MARKER]
    prefixes = [row for row in profile["rows"] if row["source"] == DRIVER and row["function"] == PREFIX_MARKER]
    return {
        "marker_unique": len(markers) == 1,
        "marker_calls": len(markers) == 1 and markers[0]["calls"] == expected_calls,
        "marker_elapsed_healthy": len(markers) == 1 and 0 <= markers[0]["self_seconds"] <= markers[0]["total_seconds"] <= sample_wall_seconds + 0.000001,
        "prefix_not_profiled": len(prefixes) == 1 and prefixes[0]["calls"] == 0 and prefixes[0]["total_seconds"] == 0,
        "capacity_not_reached": not profile["possible_truncation"],
    }


def save(log, output, csv_path=None):
    assert not output.exists(), "Preserve existing parsed evidence"
    result = parse(log.read_text(encoding="utf-8-sig"))
    result["log"] = str(log.resolve())
    result["log_sha256"] = sha(log)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if csv_path:
        assert not csv_path.exists(), "Preserve existing CSV evidence"
        with csv_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(result["rows"][0]))
            writer.writeheader()
            writer.writerows(result["rows"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args()
    result = save(args.log, args.output, args.csv)
    print(json.dumps({key: result[key] for key in ("function_rows", "active_function_rows", "possible_truncation", "log_sha256")}))


if __name__ == "__main__":
    main()
