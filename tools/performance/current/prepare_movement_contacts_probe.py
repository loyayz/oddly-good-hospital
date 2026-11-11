"""Freeze/install a reversible single-function contact A/B; never starts Godot.

A is a committed runtime. B transplants only _movement_contacts from the work
tree. Plain and counted sources are separate variants/processes. Installation
uses an already prepared isolated project and verifies every other runtime blob.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

MOVEMENT = "game/building/hospital_movement.gd"
METHOD = "_movement_contacts"
HELPERS = [
    "tests/acceptance/movement_contacts_oracle.gd",
    "tests/acceptance/movement_contacts_candidates.gd",
    "tests/acceptance/movement_contacts_candidates_runner.gd",
    "tests/acceptance/movement_contacts_candidates.md",
    "tools/performance/current/movement_contacts_probe.gd",
    "tools/performance/current/prepare_movement_contacts_probe.py",
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def method(source):
    found = list(re.finditer(r"^func " + METHOD + r"\([^\n]*\)[^\n]*:\n(?:\t[^\n]*\n|\n)*", source, re.M))
    assert len(found) == 1, "Expected exactly one contact method"
    return found[0][0].rstrip("\n") + "\n"


def counted(source):
    original = method(source)
    rows, hooks = [], []
    for line in original.splitlines(keepends=True):
        if line.startswith("func "):
            rows.append(line)
            hook = '\tspace.query_counts["contacts_probe_calls"]=int(space.query_counts.get("contacts_probe_calls",0))+1\n'
        else:
            key = "contacts_probe_dictionaries" if re.match(r"^\t+var candidates: Dictionary = \{\}", line) else "contacts_probe_sorts" if re.match(r"^\t+ids.sort\(\)", line) else ""
            if not key:
                rows.append(line)
                continue
            indent = line[:len(line) - len(line.lstrip("\t"))]
            hook = indent + 'space.query_counts["' + key + '"]=int(space.query_counts.get("' + key + '",0))+1\n'
        rows.append(hook)
        hooks.append(hook)
        if not line.startswith("func "):
            rows.append(line)
    replacement = "".join(rows)
    result = source.replace(original, replacement, 1)
    restored = result
    for hook in hooks:
        restored = restored.replace(hook, "", 1)
    assert restored == source
    return result, hooks


def prepare(args):
    started = time.perf_counter()
    root = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    assert output.is_relative_to(root / ".cache") and not output.exists()
    commit = git(root, "rev-parse", args.baseline + "^{commit}").decode().strip()
    original = git(root, "show", commit + ":" + MOVEMENT)
    current = (root / MOVEMENT).read_bytes()
    assert b"\r" not in original and b"\r" not in current
    old, new = method(original.decode()), method(current.decode())
    assert old != new
    candidate = original.decode().replace(old, new, 1)
    assert candidate.replace(new, old, 1).encode() == original
    variants = {"a": original, "b": candidate.encode()}
    counters = {}
    for name in ["a", "b"]:
        instrumented, hooks = counted(variants[name].decode())
        variants[name + "_counted"] = instrumented.encode()
        counters[name] = hooks
    reference = read(args.reference / "r1.json")
    assert reference["all_completed_steps"] == 7000 and args.expected_actors > 0
    protocol = read(args.reference / "protocol.json")
    input_path = args.input.resolve()
    input_sha = sha(input_path.read_bytes())
    assert input_sha == reference["final_sha256"], "Use the complete real 7000-step final witness"
    runtime = {}
    for row in git(root, "ls-tree", "-r", "-z", commit, "--", "game", "docs/data").split(b"\0"):
        if row:
            metadata, name = row.split(b"\t", 1)
            runtime[name.decode()] = metadata.split()[2].decode()
    paths = {}
    for name, data in variants.items():
        path = output / "sources" / name / MOVEMENT
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        paths[name] = {"path": str(path.relative_to(output)), "sha256": sha(data)}
    helpers = {}
    for relative in HELPERS:
        data = (root / relative).read_bytes()
        path = output / "helpers" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        helpers[relative] = {"path": str(path.relative_to(output)), "sha256": sha(data)}
    identity = {"baseline_commit": commit, "git_object_format": git(root, "rev-parse", "--show-object-format").decode().strip(), "variants": paths, "helpers": helpers, "baseline_runtime_blobs": runtime, "baseline_file_sha256": sha(original), "candidate_working_file_sha256": sha(current), "baseline_method": old, "candidate_method": new, "counter_hooks": counters, "method_only_reversal_exact": True, "input": str(input_path), "input_sha256": input_sha, "reference": str(args.reference.resolve()), "native": protocol["native"], "engine_executables": protocol["engine_executables"], "expected_actors": args.expected_actors, "expected_source_queries": 0, "recommended_order": ["a_counted", "b_counted", "a", "b", "b", "a", "a", "b"], "prepare_seconds": time.perf_counter() - started, "scope": "Small overlay only. No full-project copy, engine, build or simulation. A/B runtime differs only in _movement_contacts. Counted hooks are separately reversible and never enter plain timing sources. All actors/facts and the complete original Move corpus remain; local geometric subqueries may expand that source corpus, never truncate it. Source Move identities are checked against every ready ground Move; historical 317 is not a fixed workload count. No micro result establishes 160-person gameplay throughput."}
    write(output / "identity.json", identity)
    print(json.dumps({"overlay": str(output), "baseline": commit, "variants": len(paths), "method_only_reversal_exact": True, "engine_started": False}))


def install(args):
    root = Path(__file__).resolve().parents[3]
    overlay, project = args.overlay.resolve(), args.project.resolve()
    assert overlay.is_relative_to(root / ".cache") and project.is_relative_to(root / ".cache")
    assert not args.record.exists()
    identity = read(overlay / "identity.json")
    previous = read(args.previous_overlay / "identity.json") if args.previous_overlay else None
    if previous:
        assert previous["baseline_commit"] == identity["baseline_commit"] and previous["native"] == identity["native"]
    variant = identity["variants"][args.variant]
    for relative, oid in identity["baseline_runtime_blobs"].items():
        data = (project / relative).read_bytes()
        if relative == MOVEMENT:
            assert sha(data) in [row["sha256"] for row in identity["variants"].values()], "Unknown movement source; preserve it"
        else:
            assert hashlib.new(identity["git_object_format"], b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == oid, (relative, "Unrelated runtime drift")
    assert {path.name: sha(path.read_bytes()) for path in (project / "game/platform/windows/bin").glob("*.dll")} == identity["native"]
    assert sha(Path(identity["input"]).read_bytes()) == identity["input_sha256"]
    planned = dict(identity["helpers"])
    planned[MOVEMENT] = variant
    for relative, row in planned.items():
        source = (overlay / row["path"]).resolve()
        assert source.is_relative_to(overlay) and sha(source.read_bytes()) == row["sha256"]
        target = (project / relative).resolve()
        assert target.is_relative_to(project)
        if relative != MOVEMENT and target.exists():
            allowed = [row["sha256"]]
            if previous and relative in previous["helpers"]: allowed.append(previous["helpers"][relative]["sha256"])
            assert sha(target.read_bytes()) in allowed, (relative, "Unknown helper drift; preserve it")
    inventory_path = project / "source-inventory.json"
    assert inventory_path.exists(), "Prepare one complete baseline project before installing variants"
    inventory = read(inventory_path)
    for relative, row in planned.items():
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((overlay / row["path"]).read_bytes())
        if relative not in inventory: inventory.append(relative)
    write(inventory_path, inventory)
    write(args.record, {"project": str(project), "variant": args.variant, "baseline_commit": identity["baseline_commit"], "other_runtime_blobs_verified": True, "movement_sha256": variant["sha256"], "input_sha256": identity["input_sha256"], "native": identity["native"], "helpers": {name: row["sha256"] for name, row in identity["helpers"].items()}, "previous_overlay": str(args.previous_overlay) if previous else None})
    print(json.dumps({"installed": args.variant, "record": str(args.record), "engine_started": False}))


def verify(args):
    identity = read(args.overlay / "identity.json")
    expected_order = identity["recommended_order"]
    assert len(args.results) == len(expected_order), "Two counted runs and three A/B plain pairs are required"
    runs, checks = [], {}
    for index, (path, variant) in enumerate(zip(args.results, expected_order)):
        data = read(path)
        checks[str(index) + ":result"] = data["ok"] and not data["errors"] and data["whole_world_readonly"]
        checks[str(index) + ":source"] = data["source_sha256"]["movement"] == identity["variants"][variant]["sha256"] and data["input_sha256"] == identity["input_sha256"]
        checks[str(index) + ":typed"] = data["oracle_typed_sha256"] == data["actual_typed_sha256"]
        checks[str(index) + ":mode"] = data["mode"] == ("counted" if variant.endswith("counted") else "plain") and data["timings_are_plain"] == (not variant.endswith("counted"))
        if runs:
            for key in ["population", "whole_world_sha256", "oracle_typed_sha256", "actual_typed_sha256", "source_queries", "source_move_ids", "contact_queries"]: checks[str(index) + ":same_" + key] = data[key] == runs[0]["data"][key]
        total = sum(mode["elapsed_us"] for row in data["measurements"].values() for mode in row.values()) if data["timings_are_plain"] else None
        runs.append({"variant": variant, "path": str(path), "sha256": sha(path.read_bytes()), "sum_disjoint_query_elapsed_us": total, "data": data})
    pairs = []
    for index in [2, 4, 6]:
        one, two = runs[index:index + 2]
        a, b = (one, two) if one["variant"] == "a" else (two, one)
        pairs.append({"a_elapsed_us": a["sum_disjoint_query_elapsed_us"], "b_elapsed_us": b["sum_disjoint_query_elapsed_us"], "b_over_a": b["sum_disjoint_query_elapsed_us"] / a["sum_disjoint_query_elapsed_us"]})
    result = {"ok": all(checks.values()), "checks": checks, "pairs": pairs, "runs": [{k: v for k, v in run.items() if k != "data"} for run in runs], "scope": "Typed complete-oracle equality and readonly full-world witness, then three separately timed full-query pairs. No minimum speedup is imposed. Micro timings do not imply whole-step or 160-person performance compliance."}
    assert not args.output.exists()
    write(args.output, result)
    print(json.dumps(result))
    if not result["ok"]: raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    build = modes.add_parser("prepare")
    build.add_argument("--baseline", required=True)
    build.add_argument("--expected-actors", type=int, default=179)
    for name in ["output", "input", "reference"]: build.add_argument("--" + name, type=Path, required=True)
    apply = modes.add_parser("install")
    for name in ["overlay", "project", "record"]: apply.add_argument("--" + name, type=Path, required=True)
    apply.add_argument("--variant", choices=["a", "b", "a_counted", "b_counted"], required=True)
    apply.add_argument("--previous-overlay", type=Path)
    check = modes.add_parser("verify")
    for name in ["overlay", "output"]: check.add_argument("--" + name, type=Path, required=True)
    check.add_argument("--results", type=Path, nargs=8, required=True)
    args = parser.parse_args()
    {"prepare": prepare, "install": install, "verify": verify}[args.mode](args)


if __name__ == "__main__": main()
