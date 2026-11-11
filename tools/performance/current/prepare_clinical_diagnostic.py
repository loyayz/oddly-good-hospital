"""Prepare reversible clinical branch hooks in an existing frozen project.

No engine runs here. Diagnostic windows stay 1000 + 6000 steps; verification
compares the complete final binary (world and ordered events), even when the
unchanged business-coverage gate makes the campaign return a failure.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def prepare(args):
    started = time.perf_counter()
    base, target = args.base_project.resolve(), args.output.resolve()
    reference, input_path = args.reference.resolve(), args.input.resolve()
    result = read(reference / "r1.json")
    protocol = read(reference / "protocol.json")
    assert result["all_completed_steps"] == 7000 and result["metrics"]["count"] == 6000
    assert result["requested_prefix_steps"] == 1000 and result["requested_sample_steps"] == 6000
    assert digest(input_path) == result["source_input_sha256"]
    assert digest(reference / "r1.json.final.bin") == result["final_sha256"]
    assert all(digest(Path(name)) == sha for name, sha in protocol["engine_executables"].items())
    native = {p.name: digest(p) for p in (base / "game/platform/windows/bin").glob("*.dll")}
    assert native == protocol["native"]
    inventory = read(base / "source-inventory.json")
    original = {name: digest(base / name) for name in inventory}
    assert {k: v for k, v in original.items() if not k.endswith(".gd.uid")} == read(reference / "source-identity.json"), "Base differs from the measured plain source"
    target.mkdir(parents=True, exist_ok=False)
    for name in inventory:
        source, destination = (base / name).resolve(), (target / name).resolve()
        assert source.is_relative_to(base) and destination.is_relative_to(target)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    for name in [".godot/imported", "game/platform/windows/bin"]:
        shutil.copytree(base / name, target / name, dirs_exist_ok=True)
    for name in [".godot/global_script_class_cache.cfg", ".godot/extension_list.cfg"]:
        shutil.copy2(base / name, target / name)
    prefix = 'const ClinicalDiagnostic = preload("res://tools/performance/current/clinical_diagnostic_trace.gd")\n'
    replacements = {}

    def patch(name, pairs):
        path = target / name
        original_bytes = path.read_bytes()
        text = original_bytes.decode("utf-8")
        assert "\r" not in text, "Exact source restoration requires repository LF"
        saved = text
        for old, new in pairs:
            assert text.count(old) == 1, (name, old, text.count(old))
            text = text.replace(old, new, 1)
        restored = text
        for old, new in reversed(pairs):
            assert restored.count(new) == 1, (name, "reverse patch is ambiguous")
            restored = restored.replace(new, old, 1)
        assert restored == saved and restored.encode("utf-8") == original_bytes, (name, "Removing hooks changed original file/body bytes")
        path.write_bytes(text.encode("utf-8"))
        replacements[name] = {"original_sha256": original[name], "instrumented_sha256": digest(path), "whole_file_and_method_bodies_restore_exactly": True, "replacements": [{"original": old, "instrumented": new} for old, new in pairs]}

    name = "game/clinic/hospital_visitors.gd"
    patch(name, [
        ("extends RefCounted\n", "extends RefCounted\n" + prefix),
        ("\t\tstay.remaining_ticks=maxi(0,int(stay.remaining_ticks)-1)\n", "\t\tClinicalDiagnostic.before_decrement(world,stay,ward,visit,content)\n\t\tstay.remaining_ticks=maxi(0,int(stay.remaining_ticks)-1)\n"),
        ("\t\tif terminal:\n\t\t\tstay.remaining_ticks=0\n", "\t\tif terminal:\n\t\t\tClinicalDiagnostic.before_terminal_clear(world,stay,ward,visit,content)\n\t\t\tstay.remaining_ticks=0\n"),
    ])
    name = "tools/performance/current/comprehensive_observer.gd"
    text = (target / name).read_text(encoding="utf-8")
    start = text.index("func capture(world: WorldState) -> Dictionary:\n")
    end = text.index("\n", text.index("\tvar state: Dictionary=", start)) + 1
    header = text[start:end]
    predicate = next(line for line in text.splitlines(keepends=True) if 'if not family.inside_ward or not family.patient_in_ward' in line and 'Effective visit time advanced' in line)
    observed = predicate.replace(': _error(', ':\n\t\t\t\tClinicalDiagnostic.observer_failure(world,id,before,after,_geometry.content)\n\t\t\t\t_error(', 1)
    patch(name, [
        ("extends RefCounted\n", "extends RefCounted\n" + prefix),
        (header, header + "\tstate.clinical_diagnostic=ClinicalDiagnostic.capture(world,_geometry.content)\n"),
        (predicate, observed),
    ])
    name = "tools/performance/current/plain_v4.gd"
    marker = "\tvar attribution: Dictionary = profiler.report() if profile_stages else {}\n"
    patch(name, [("extends SceneTree\n", "extends SceneTree\n" + prefix), (marker, "\tClinicalDiagnostic.finish(world,content)\n" + marker)])
    helpers = ["clinical_diagnostic_trace.gd", Path(__file__).name]
    for helper in helpers:
        name = "tools/performance/current/" + helper
        shutil.copy2(Path(__file__).with_name(helper), target / name)
        assert name not in inventory, "Use the original plain base, not a diagnostic copy"
        inventory.append(name)
    write(target / "source-inventory.json", inventory)
    source = {name: digest(target / name) for name in inventory}
    assert all(digest(base / name) == sha for name, sha in original.items()), "Plain source changed during diagnostic freeze"
    write(target / "clinical-diagnostic-identity.json", {
        "base_project": str(base), "original_source": original, "source": source,
        "reversible_hooks": replacements, "input": str(input_path),
        "input_sha256": digest(input_path), "reference": str(reference),
        "expected_final_bin_sha256": result["final_sha256"], "prefix_steps": 1000,
        "sample_steps": 6000, "root_stage_flag": "--profile-stages",
        "engine_executables": protocol["engine_executables"], "native": native,
        "main_thread_policy": protocol["main_thread_policy"], "worker_tasks": protocol["worker_tasks"],
        "scope": "Read-only actual decrement and terminal-clear hooks, first observer-error raw contexts, independent room/body/medical conditions. No production condition, actor, route, RNG, rule or window is changed. Stage and whole-step diagnostic durations include hook perturbation and are not performance qualification.",
        "freeze_seconds": time.perf_counter() - started,
    })
    print(json.dumps({"project": str(target), "original_files": len(original), "instrumented_files": len(replacements), "source_files": len(source), "body_restoration_exact": True, "freeze_seconds": time.perf_counter() - started}))


def verify(args):
    output, reference, project = args.diagnostic_output.resolve(), args.reference.resolve(), args.project.resolve()
    target = output / "clinical-equivalence.json"
    assert not target.exists(), "Preserve existing equivalence evidence"
    actual, expected = read(output / "r1.json"), read(reference / "r1.json")
    identity = read(project / "clinical-diagnostic-identity.json")
    source_unchanged = all(digest(project / name) == sha for name, sha in identity["source"].items())
    final_hash = digest(output / "r1.json.final.bin")
    stages = read(output / "r1.json.stages.json")
    checks = {
        "source_unchanged": source_unchanged,
        "same_input": actual["source_input_sha256"] == expected["source_input_sha256"] == identity["input_sha256"],
        "complete_fixed_window": actual["all_completed_steps"] == 7000 and actual["metrics"]["count"] == 6000 and actual["requested_prefix_steps"] == 1000 and actual["requested_sample_steps"] == 6000,
        "complete_world_and_ordered_events_identical": final_hash == actual["final_sha256"] == expected["final_sha256"] == identity["expected_final_bin_sha256"],
        "root_stage_records_complete": stages.get("step_records_complete", False) and stages.get("complete_steps") == 6000 and not stages.get("errors") and stages.get("partition_check_us") == 0,
        "input_unchanged": digest(Path(identity["input"])) == identity["input_sha256"],
        "engine_unchanged": all(digest(Path(name)) == sha for name, sha in identity["engine_executables"].items()),
        "native_unchanged": {p.name: digest(p) for p in (project / "game/platform/windows/bin").glob("*.dll")} == identity["native"],
    }
    write(target, {"checks": checks, "passed": all(checks.values()), "final_bin_sha256": final_hash, "reference": str(reference), "scope": "Exact complete world and ordered event witness. Coverage failure remains reported separately; diagnostic elapsed times cannot establish speedup or target compliance."})
    print(json.dumps({"passed": all(checks.values()), "checks": checks, "report": str(target)}))
    assert all(checks.values()), checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    build = modes.add_parser("prepare")
    for name in ["base-project", "output", "input", "reference"]:
        build.add_argument("--" + name, type=Path, required=True)
    check = modes.add_parser("verify")
    for name in ["diagnostic-output", "reference", "project"]:
        check.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    prepare(args) if args.mode == "prepare" else verify(args)


if __name__ == "__main__":
    main()
