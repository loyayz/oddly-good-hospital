"""Prepare a small, isolated bed-query A/B overlay without running Godot.

The baseline is a Git commit. B transplants only the named bed helpers from the
working tree; unrelated movement/life changes remain excluded. Installation
requires a separately prepared project matching the baseline runtime blobs.
Plain and counted variants are distinct sources and separate engine processes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


SPACE = "game/building/hospital_space.gd"
MOVEMENT = "game/building/hospital_movement.gd"
CHANGED = {
    SPACE: ["_build_reservation_view", "_index_reservation", "has_bed_destination_claims", "bed_destination_blocker"],
    MOVEMENT: ["_bed_goal_blocker", "_bed_local_path_blocker"],
}
ADDED = {SPACE: ["bed_destination_view", "_bed_destination_blocker_in_view"]}
HELPERS = [
    "tools/performance/current/bed_destination_probe.gd",
    "tests/acceptance/bed_destination_oracle.gd",
    "tests/acceptance/bed_destination_index.gd",
    "tests/acceptance/bed_destination_index_runner.gd",
    "tests/acceptance/bed_destination_index.md",
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


def method(source, name):
    matches = list(re.finditer(r"^func " + re.escape(name) + r"\([^\n]*\)[^\n]*:\n(?:\t[^\n]*\n|\n)*", source, re.M))
    assert len(matches) == 1, (name, len(matches))
    return matches[0][0].rstrip("\n") + "\n"


def candidate(relative, before, current):
    source = before
    replacements = []
    for name in CHANGED[relative]:
        old, new = method(before, name), method(current, name)
        assert old != new, (relative, name, "Expected the pending bed-query change")
        assert source.count(old) == 1
        source = source.replace(old, new, 1)
        replacements.append({"method": name, "original": old, "candidate": new})
    for name in ADDED.get(relative, []):
        assert not re.search(r"^func " + re.escape(name) + r"\(", before, re.M)
        addition = "\n" + method(current, name)
        source += addition
        replacements.append({"method": name, "original": "", "candidate": addition})
    restored = source
    for row in reversed(replacements):
        if row["original"]:
            assert restored.count(row["candidate"]) == 1
            restored = restored.replace(row["candidate"], row["original"], 1)
        else:
            assert restored.endswith(row["candidate"])
            restored = restored[:-len(row["candidate"])]
    assert restored.encode("utf-8") == before.encode("utf-8"), relative
    for name in CHANGED[relative] + ADDED.get(relative, []):
        assert method(source, name) == method(current, name), (relative, name, "Transplanted body differs from the candidate")
    return source, replacements


def counted(relative, plain):
    name = "reservation_view" if relative == SPACE else "_bed_goal_regions"
    key = "bed_probe_reservation_view_calls" if relative == SPACE else "bed_probe_goal_region_calls"
    owner = "query_counts" if relative == SPACE else "space.query_counts"
    block = method(plain, name)
    header = block.splitlines(keepends=True)[0]
    insertion = '\t' + owner + '["' + key + '"]=int(' + owner + '.get("' + key + '",0))+1\n'
    assert plain.count(header) == 1
    result = plain.replace(header, header + insertion, 1)
    assert result.replace(header + insertion, header, 1).encode("utf-8") == plain.encode("utf-8")
    return result, {"method": name, "header": header, "insertion": insertion, "whole_file_restoration_exact": True}


def runtime_blobs(root, commit):
    rows = {}
    for record in git(root, "ls-tree", "-r", "-z", commit, "--", "game", "docs/data").split(b"\0"):
        if not record:
            continue
        metadata, name = record.split(b"\t", 1)
        _, kind, oid = metadata.split()
        assert kind == b"blob"
        rows[name.decode("utf-8")] = oid.decode("ascii")
    assert rows
    return rows


def prepare(args):
    started = time.perf_counter()
    root = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    assert output.is_relative_to(root / ".cache") and not output.exists(), "Use a new .cache overlay path"
    commit = git(root, "rev-parse", args.baseline + "^{commit}").decode().strip()
    originals, variants, changes, counters, current_hashes = {}, {name: {} for name in ["a", "b", "a_counted", "b_counted"]}, {}, {}, {}
    for relative in [SPACE, MOVEMENT]:
        raw = git(root, "show", commit + ":" + relative)
        current_raw = (root / relative).read_bytes()
        assert b"\r" not in raw and b"\r" not in current_raw
        originals[relative] = sha(raw)
        current_hashes[relative] = sha(current_raw)
        updated, edits = candidate(relative, raw.decode("utf-8"), current_raw.decode("utf-8"))
        changes[relative] = edits
        variants["a"][relative], variants["b"][relative] = raw, updated.encode("utf-8")
        for version in ["a", "b"]:
            instrumented, proof = counted(relative, variants[version][relative].decode("utf-8"))
            variants[version + "_counted"][relative] = instrumented.encode("utf-8")
            counters[version + ":" + relative] = proof
    # The pending staff local-movability change must not enter this comparison.
    assert method(variants["a"][MOVEMENT].decode(), "_local_movable") == method(variants["b"][MOVEMENT].decode(), "_local_movable")
    protocol = read(args.reference / "protocol.json")
    expected_input = args.input.resolve()
    assert expected_input.is_file()
    input_sha = sha(expected_input.read_bytes())
    reference = read(args.reference / "r1.json")
    assert input_sha in [reference["source_input_sha256"], reference["final_sha256"]], "Use the complete measured initial input or complete final witness"
    inventory = runtime_blobs(root, commit)
    output.mkdir(parents=True, exist_ok=False)
    paths = {}
    for version, sources in variants.items():
        paths[version] = {}
        for relative, data in sources.items():
            path = output / "sources" / version / relative
            path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(data)
            paths[version][relative] = {"sha256": sha(data), "path": str(path.relative_to(output))}
    helpers = {}
    for relative in HELPERS + ["tools/performance/current/" + Path(__file__).name]:
        data = (root / relative).read_bytes();path = output / "helpers" / relative
        path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(data)
        helpers[relative] = {"sha256": sha(data), "path": str(path.relative_to(output))}
    assert all(sha((root / name).read_bytes()) == value for name, value in current_hashes.items()), "Candidate changed during the overlay freeze"
    identity = {"baseline_commit": commit, "baseline_tree": git(root, "rev-parse", commit + "^{tree}").decode().strip(), "git_object_format": git(root, "rev-parse", "--show-object-format").decode().strip(), "baseline_runtime_blobs": inventory, "original_sha256": originals, "working_tree_source_sha256_not_used_whole": current_hashes, "bed_only_reversible_changes": changes, "counted_source_reversible_changes": counters, "variants": paths, "helpers": helpers, "input": str(expected_input), "input_sha256": input_sha, "engine_executables": protocol["engine_executables"], "native": protocol["native"], "prepare_seconds": time.perf_counter() - started, "scope": "Small source overlay only; no full-project copy, engine or simulation. Only named bed helpers differ between A and B. Plain timing sources contain no bed-probe counter hooks; counted processes report calls separately. All runtime files outside the two bed source files must match the baseline Git objects before installation."}
    write(output / "identity.json", identity)
    print(json.dumps({"overlay": str(output), "baseline": commit, "source_variants": len(paths), "bed_only_files": 2, "full_project_copied": False, "engine_started": False, "prepare_seconds": identity["prepare_seconds"]}))


def install(args):
    overlay, project, record = args.overlay.resolve(), args.project.resolve(), args.record.resolve()
    assert not record.exists(), "Preserve the previous installation record"
    identity = read(overlay / "identity.json")
    assert args.variant in identity["variants"]
    object_format = identity["git_object_format"]
    assert object_format in ["sha1", "sha256"]
    for relative, oid in identity["baseline_runtime_blobs"].items():
        path = (project / relative).resolve()
        assert path.is_relative_to(project) and path.is_file(), relative
        data = path.read_bytes()
        if relative in [SPACE, MOVEMENT]:
            assert sha(data) in [row[relative]["sha256"] for row in identity["variants"].values()], (relative, "Unknown source; preserve it")
        else:
            assert hashlib.new(object_format, b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == oid, (relative, "Unrelated runtime difference from the baseline")
    assert {path.name: sha(path.read_bytes()) for path in (project / "game/platform/windows/bin").glob("*.dll")} == identity["native"]
    assert sha(Path(identity["input"]).read_bytes()) == identity["input_sha256"]
    inventory_path = project / "source-inventory.json"
    assert inventory_path.is_file(), "Prepare a complete baseline project and its inventory first"
    inventory = read(inventory_path)
    planned = dict(identity["helpers"])
    planned.update(identity["variants"][args.variant])
    for relative, row in planned.items():
        source = (overlay / row["path"]).resolve()
        assert source.is_relative_to(overlay) and sha(source.read_bytes()) == row["sha256"], relative
        target = (project / relative).resolve()
        assert target.is_relative_to(project)
        if relative not in [SPACE, MOVEMENT] and target.exists():
            assert sha(target.read_bytes()) == row["sha256"], (relative, "Existing helper differs; preserve it")
    for relative, row in planned.items():
        target = project / relative;target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((overlay / row["path"]).read_bytes())
        if relative not in inventory: inventory.append(relative)
    write(inventory_path, inventory)
    source = {name: sha((project / name).read_bytes()) for name in inventory}
    write(record, {"project": str(project), "overlay": str(overlay), "variant": args.variant, "baseline_commit": identity["baseline_commit"], "baseline_runtime_other_blobs_verified": True, "source": source, "source_inventory_json_file_sha256": sha(inventory_path.read_bytes()), "input_sha256": identity["input_sha256"], "engine_executables": identity["engine_executables"], "native": identity["native"], "scope": identity["scope"]})
    print(json.dumps({"installed": args.variant, "project": str(project), "record": str(record), "source_files": len(source), "engine_started": False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    build = modes.add_parser("prepare")
    build.add_argument("--baseline", default="e5a0ffb")
    for name in ["output", "input", "reference"]: build.add_argument("--" + name, type=Path, required=True)
    apply = modes.add_parser("install")
    for name in ["overlay", "project", "record"]: apply.add_argument("--" + name, type=Path, required=True)
    apply.add_argument("--variant", choices=["a", "b", "a_counted", "b_counted"], required=True)
    args = parser.parse_args()
    prepare(args) if args.mode == "prepare" else install(args)


if __name__ == "__main__": main()
