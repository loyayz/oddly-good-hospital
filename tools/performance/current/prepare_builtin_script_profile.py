"""Prepare a reversible driver-only local Godot profiler; run only on explicit command.

Preparation does not invoke the engine. Qualification uses three fresh serial
processes with the same complete world. No production or shared tool is edited.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import time

from campaign160 import processes
from parse_builtin_script_profile import BEGIN, END, marker_checks, save as parse_log

DRIVER = "tools/performance/current/plain_v4.gd"
MANIFEST = "builtin-script-profile-identity.json"
MODES = ("plain", "debug-off", "scripts")
SCOPE = ("Diagnostic elapsed only; all original gameplay steps, candidates and observers remain. "
         "The local scripts profiler merges threads/callers and includes observer/tool functions. "
         "Its self/inclusive output is not pure step CPU. Debug line polling, profiling and stdout "
         "have unmeasured overhead until compared with the same-input plain mode.")
COVERAGE_FAILURE = "Comprehensive workload did not satisfy its business coverage contract"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def bytes_sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def validate_diagnostic_witness(result_path, input_sha256):
    """A complete full-window fact witness may retain only explicit coverage failure."""
    data = read(result_path)
    assert data["source_input_sha256"] == input_sha256, "Witness used another complete input"
    assert type(data["requested_prefix_steps"]) is int and data["requested_prefix_steps"] == 1000
    assert type(data["requested_sample_steps"]) is int and data["requested_sample_steps"] == 6000
    assert type(data["all_completed_steps"]) is int and data["all_completed_steps"] == 7000
    assert type(data["metrics"]["count"]) is int and data["metrics"]["count"] == 6000
    initial_tick, final_tick = data["initial"]["tick"], data["final"]["tick"]
    assert type(initial_tick) is int and type(final_tick) is int and final_tick == initial_tick + 7000
    final_bin = Path(str(result_path) + ".final.bin")
    assert final_bin.is_file() and digest(final_bin) == data["final_sha256"], "Missing or mismatching full facts/events binary"
    comprehensive = data["sample_business"]["comprehensive"]
    assert comprehensive["invariant_failure_counts"] == {}, "Business invariant failure is not coverage insufficiency"
    coverage, uncovered = comprehensive["coverage"], comprehensive["uncovered"]
    assert isinstance(coverage, dict) and coverage
    assert isinstance(uncovered, list) and all(isinstance(key, str) and key for key in uncovered)
    assert len(uncovered) == len(set(uncovered)), "Duplicate uncovered identities"
    missing = set()
    for key, row in coverage.items():
        assert isinstance(key, str) and key and type(row["covered"]) is bool
        actual, minimum = row["actual"], row["lower_bound"]
        assert type(actual) in (int, float) and type(minimum) in (int, float)
        assert math.isfinite(actual) and math.isfinite(minimum)
        assert row["covered"] == (actual >= minimum), "Coverage row contradicts its declared observation"
        if not row["covered"]:
            missing.add(key)
    assert set(uncovered) == missing, "Uncovered identities differ from the full coverage table"
    assert type(data["complete"]) is bool and type(comprehensive["coverage_pass"]) is bool
    if data["complete"]:
        assert data["errors"] == [] and comprehensive["coverage_pass"] and uncovered == [] and comprehensive["errors"] == []
    else:
        assert data["errors"] == [COVERAGE_FAILURE], "Only the exact top-level coverage failure is diagnostic"
        assert comprehensive["coverage_pass"] is False and uncovered
        assert comprehensive["errors"] == ["No measured activity: " + key for key in uncovered], "Additional or inconsistent observer error"
    return {"complete_execution_witness": True, "source_result_complete": data["complete"],
            "coverage_pass": comprehensive["coverage_pass"], "uncovered": uncovered,
            "errors": data["errors"], "comprehensive_errors": comprehensive["errors"],
            "invariant_failure_counts": comprehensive["invariant_failure_counts"],
            "final_sha256": data["final_sha256"], "result_sha256": digest(result_path),
            "acceptance_pass": None, "scope": "Full facts/events diagnostic witness only; original coverage failure is retained, never accepted as a gameplay or performance pass."}


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def native_identity(project):
    return {path.name: digest(path) for path in (project / "game/platform/windows/bin").glob("*.dll")}


def engine_identity(engine):
    paths = [engine]
    if engine.stem.endswith("_console"):
        paths.append(engine.with_name(engine.stem.removesuffix("_console") + engine.suffix))
    return {str(path): digest(path) for path in paths}


def inverse(data, replacements):
    text = data.decode("utf-8")
    for item in reversed(replacements):
        assert text.count(item["after"]) == 1, "Reverse anchor changed or ambiguous"
        text = text.replace(item["after"], item["before"], 1)
    return text.encode("utf-8")


def patch_driver(original):
    text = original.decode("utf-8")
    assert "_builtin_profile_" not in text, "Driver is already instrumented"
    newline = "\r\n" if "\r\n" in text else "\n"
    assert text.count("\r\n") == text.count("\r"), "Unsupported source line endings"
    replacements = []

    def replace(before, after):
        nonlocal text
        before, after = before.replace("\n", newline), after.replace("\n", newline)
        assert text.count(before) == 1, ("Unique driver anchor required", before)
        text = text.replace(before, after, 1)
        replacements.append({"before": before, "after": after})

    replace('\tvar profile_stages: bool = false\n',
            '\tvar profile_stages: bool = false\n\tvar _builtin_profile_mode: String = "plain"\n')
    replace('\t\tif arg=="--profile-stages": profile_stages=true\n',
            '\t\tif arg=="--profile-stages": profile_stages=true\n'
            '\t\tif arg.begins_with("--builtin-script-profile="): _builtin_profile_mode=arg.trim_prefix("--builtin-script-profile=")\n')
    anchor = '\tvar thread_policy: Dictionary = {"requested":thread_policy_mode'
    replace(anchor,
            '\tvar _builtin_profile_has_scripts: bool = EngineDebugger.has_profiler("scripts")\n'
            '\tvar _builtin_profile_before: Dictionary = {"mode":_builtin_profile_mode,"debugger_active":EngineDebugger.is_active(),"has_scripts":_builtin_profile_has_scripts,"profiling":EngineDebugger.is_profiling("scripts") if _builtin_profile_has_scripts else false}\n'
            '\tif not _builtin_profile_mode in ["plain","debug-off","scripts"] or _builtin_profile_before.profiling or (_builtin_profile_mode=="plain" and _builtin_profile_before.debugger_active) or (_builtin_profile_mode!="plain" and (not _builtin_profile_before.debugger_active or not _builtin_profile_has_scripts)):\n'
            '\t\twrite_json(output,{"complete":false,"reason":"Invalid local scripts-profiler entry state","builtin_profile":_builtin_profile_before});quit(2);return\n'
            '\tvar _builtin_profile_started: bool = false\n'
            '\tvar _builtin_profile_started_tick: int = -1\n'
            '\tvar _builtin_profile_marker_calls: int = 0\n'
            '\tvar _builtin_profile_prefix_marker_calls: int = 0\n' + anchor)
    replace('\t\t\tsample_wall_start=Time.get_ticks_usec();prefix_wall_us=sample_wall_start-wall_start\n',
            '\t\t\t# Native toggles stay in this original long _run frame; it is excluded from hotspots.\n'
            '\t\t\tif _builtin_profile_mode=="scripts":\n'
            '\t\t\t\tEngineDebugger.profiler_enable("scripts",true)\n'
            '\t\t\t\t_builtin_profile_started=EngineDebugger.is_profiling("scripts")\n'
            '\t\t\t\t_builtin_profile_started_tick=world.sim_tick\n'
            '\t\t\t\tif not _builtin_profile_started: errors.append("Local scripts profiler did not start");break\n'
            '\t\t\tsample_wall_start=Time.get_ticks_usec();prefix_wall_us=sample_wall_start-wall_start\n'
            '\t\tif index>=prefix_steps: _builtin_profile_marker_calls+=_builtin_profile_marker()\n'
            '\t\telse: _builtin_profile_prefix_marker_calls+=_builtin_profile_prefix_marker()\n')
    replace('\tvar window_end: int = Time.get_ticks_usec()\n',
            '\tvar window_end: int = Time.get_ticks_usec()\n'
            '\t# The accumulated printout and profiler shutdown are outside the sample wall interval.\n'
            '\tvar _builtin_profile_print_start: int = Time.get_ticks_usec()\n'
            '\tif _builtin_profile_mode=="scripts" and EngineDebugger.is_profiling("scripts"):\n'
            '\t\tprint("' + BEGIN + '")\n'
            '\t\tEngineDebugger.profiler_enable("scripts",false)\n'
            '\t\tprint("' + END + '")\n'
            '\tvar _builtin_profile_print_us: int = Time.get_ticks_usec()-_builtin_profile_print_start\n'
            '\tvar _builtin_profile_after: bool = EngineDebugger.is_profiling("scripts") if _builtin_profile_has_scripts else false\n'
            '\twrite_json(output+".builtin-profile.json",{"before":_builtin_profile_before,"started":_builtin_profile_started,"started_tick":_builtin_profile_started_tick,"ended_tick":world.sim_tick,"profiling_after":_builtin_profile_after,"sample_marker_calls":_builtin_profile_marker_calls,"prefix_marker_calls":_builtin_profile_prefix_marker_calls,"profile_stop_and_print_us":_builtin_profile_print_us,"sample_window_wall_us":window_end-sample_wall_start,"boundary_control_frame":"_run excluded","scope":"Flat elapsed merges threads/callers, includes observers and waits; not pure Simulation.step CPU."})\n')
    suffix = ('\n# Tool-only, pure markers; no world reference, RNG, scheduling or resource work.\n'
              'func _builtin_profile_marker() -> int:\n\treturn 1\n'
              'func _builtin_profile_prefix_marker() -> int:\n\treturn 1\n').replace("\n", newline)
    text += suffix
    replacements.append({"before": "", "after": suffix})
    result = text.encode("utf-8")
    assert inverse(result, replacements) == original, "Byte-exact driver restoration failed"
    assert result.count(b'EngineDebugger.profiler_enable("scripts",true)') == 1
    assert result.count(b'EngineDebugger.profiler_enable("scripts",false)') == 1
    return result, replacements


def prepare(args):
    started = time.perf_counter()
    root = Path(__file__).resolve().parents[3]
    base, target, input_path = args.base_project.resolve(), args.output.resolve(), args.input.resolve()
    assert target.is_relative_to(root / ".cache") and not target.exists(), "Use a new project below .cache"
    authority = read(args.authority)
    metadata_file = base / "source-identity.json"
    assert digest(metadata_file) == authority["stage_identity_sha256"]
    assert Path(authority["production_stage"]).resolve() == base
    metadata = read(metadata_file)
    inventory = read(base / "source-inventory.json")
    expected = {row["path"]: row["sha256"].lower() for row in metadata["source"]}
    assert len(inventory) == len(set(inventory)) and set(inventory) == set(expected)
    for relative in inventory:
        source = (base / relative).resolve()
        assert source.is_relative_to(base) and source.is_file() and digest(source) == expected[relative], relative
    assert all(expected[path] == value for path, value in authority["production_source"].items())
    native = native_identity(base)
    assert len(native) == 5 and native == authority["native"], "The explicit five-DLL input changed"
    assert digest(input_path) == args.input_sha256, "Complete input identity changed"
    engine = Path(metadata["engine"]).resolve()
    engines = engine_identity(engine)
    assert engines[str(engine)] == metadata["engine_sha256"].lower()
    original = (base / DRIVER).read_bytes()
    patched, replacements = patch_driver(original)
    tools = {Path(__file__).name: digest(Path(__file__)), "parse_builtin_script_profile.py": digest(Path(__file__).with_name("parse_builtin_script_profile.py"))}
    summary = {"engine_started": False, "source_files": len(inventory), "driver_inverse_exact": True,
               "native": native, "base_identity_sha256": digest(metadata_file),
               "driver_original_sha256": bytes_sha(original), "driver_overlay_sha256": bytes_sha(patched)}
    if args.check_only:
        print(json.dumps(summary))
        return
    target.mkdir(parents=True, exist_ok=False)
    for relative in inventory:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / relative, destination)
    for relative in (".godot/imported", "game/platform/windows/bin"):
        shutil.copytree(base / relative, target / relative)
    for relative in (".godot/global_script_class_cache.cfg", ".godot/extension_list.cfg"):
        shutil.copy2(base / relative, target / relative)
    (target / DRIVER).write_bytes(patched)
    write(target / "source-inventory.json", inventory)
    after = {path: digest(target / path) for path in inventory}
    assert all(after[path] == value for path, value in expected.items() if path != DRIVER)
    assert inverse((target / DRIVER).read_bytes(), replacements) == original
    assert native_identity(target) == native and all(digest(base / path) == value for path, value in expected.items())
    identity = {**summary, "base_project": str(base), "authority": str(args.authority.resolve()),
                "authority_sha256": digest(args.authority), "base_commit": metadata["head"],
                "original_source": expected, "source": after, "replacements": replacements,
                "input": str(input_path), "input_sha256": args.input_sha256,
                "engine": str(engine), "engine_executables": engines, "tools": tools,
                "prefix_steps_full": 1000, "sample_steps_full": 6000,
                "short_expected_final_sha256": args.short_expected_final_sha256,
                "prepared_utc": utc(), "prepare_seconds": time.perf_counter() - started, "scope": SCOPE}
    write(target / MANIFEST, identity)
    print(json.dumps({**summary, "project": str(target), "prepare_seconds": identity["prepare_seconds"]}))


def verify_sources(project, identity):
    assert read(project / "source-inventory.json") == list(identity["source"])
    assert all(digest(project / path) == value for path, value in identity["source"].items()), "Frozen source changed"
    restored = inverse((project / DRIVER).read_bytes(), identity["replacements"])
    assert bytes_sha(restored) == identity["original_source"][DRIVER]
    assert native_identity(project) == identity["native"]
    assert digest(Path(identity["input"])) == identity["input_sha256"]
    assert engine_identity(Path(identity["engine"])) == identity["engine_executables"]
    assert all(digest(Path(__file__).with_name(name)) == value for name, value in identity["tools"].items()), "Diagnostic tool changed after preparation"


def stop_owned_process_tree(process):
    """Same Popen-owned Kill(true) policy as campaign160, with bounded waits."""
    if process.poll() is not None:
        return
    script = (f"$ownedProcess=[System.Diagnostics.Process]::GetProcessById({process.pid}); "
              "$ownedProcess.Kill($true); "
              'if (-not $ownedProcess.WaitForExit(10000)) { throw "Owned engine tree did not exit" }')
    subprocess.run(["pwsh", "-NoProfile", "-Command", script], stdout=subprocess.DEVNULL,
                   stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW, timeout=15, check=True)
    process.wait(timeout=10)


def run_process(command, project, directory, timeout, allowed_returncodes=(0,)):
    """One owned process; append logs/evidence only, never reopen old outputs."""
    active = processes()
    assert not active, f"Another engine/compiler owns the slot: {active}"
    directory.mkdir(parents=True, exist_ok=False)
    appdata, local, temporary = (directory / name for name in ("appdata", "localappdata", "temp"))
    for path in (appdata, local, temporary):
        path.mkdir()
    environment = dict(os.environ, OMP_NUM_THREADS="1", PYTHONUTF8="1", APPDATA=str(appdata),
                       LOCALAPPDATA=str(local), TEMP=str(temporary), TMP=str(temporary))
    record = {"command": command, "cwd": str(project), "started_utc": utc(),
              "process_guard_source_sha256": digest(Path(__file__).with_name("campaign160.py")),
              "environment_overrides": {key: environment[key] for key in ("OMP_NUM_THREADS", "PYTHONUTF8", "APPDATA", "LOCALAPPDATA", "TEMP", "TMP")}}
    started = time.perf_counter()
    log_path = directory / "engine.log"
    with log_path.open("wb") as log:
        process = subprocess.Popen(command, cwd=project, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        record["owned_launcher_pid"] = process.pid
        write(directory / "process.json", record)
        monitor_offset, error_tail = 0, b""
        try:
            while process.poll() is None:
                time.sleep(0.2)
                with log_path.open("rb") as incoming:
                    incoming.seek(monitor_offset)
                    chunk = incoming.read()
                    monitor_offset += len(chunk)
                scanned = error_tail + chunk
                if b"SCRIPT ERROR:" in scanned or b"\nERROR:" in b"\n" + scanned:
                    raise RuntimeError("Engine script/error log; preserve engine.log")
                error_tail = scanned[-64:]
                if time.perf_counter() - started > timeout:
                    raise TimeoutError(f"Owned engine exceeded {timeout} seconds")
            process.wait(timeout=10)
        finally:
            if process.poll() is None:
                stop_owned_process_tree(process)
            record.update({"returncode": process.returncode, "ended_utc": utc(),
                           "process_wall_seconds": time.perf_counter() - started})
            write(directory / "process.json", record)
    raw = log_path.read_text(encoding="utf-8-sig")
    assert process.returncode in allowed_returncodes and "SCRIPT ERROR:" not in raw and not any(line.startswith("ERROR:") for line in raw.splitlines()), "Engine/tool failure; preserve engine.log"
    record["log_sha256"] = digest(log_path)
    write(directory / "process.json", record)
    return record


def execute(args):
    assert os.name == "nt", "This executor uses the verified Windows owned-process strategy"
    project, output = args.project.resolve(), args.output.resolve()
    identity = read(project / MANIFEST)
    root = Path(__file__).resolve().parents[3]
    assert project.is_relative_to(root / ".cache") and output.is_relative_to(root / ".cache")
    output.mkdir(parents=True, exist_ok=False)
    verify_sources(project, identity)
    engine = identity["engine"]
    modes = MODES if args.action == "qualify" else (args.mode,)
    prefix, steps = (0, 2) if args.action == "qualify" else (1000, 6000)
    expected = identity["short_expected_final_sha256"] if args.action == "qualify" else None
    reference_validation = None
    if args.action == "run":
        reference = read(args.outcome_reference)
        reference_validation = validate_diagnostic_witness(args.outcome_reference, identity["input_sha256"])
        expected = reference["final_sha256"]
    protocol = {"project": str(project), "identity_sha256": digest(project / MANIFEST),
                "input_sha256": identity["input_sha256"], "native": identity["native"],
                "engine_executables": identity["engine_executables"], "prefix_steps": prefix,
                "sample_steps": steps, "modes": list(modes), "profile_stages": args.profile_stages,
                "main_thread_policy": args.main_thread_policy, "worker_tasks": args.worker_tasks,
                "expected_complete_world_events_sha256": expected, "reference_validation": reference_validation,
                "started_utc": utc(), "scope": SCOPE}
    write(output / "protocol.json", protocol)
    if args.import_project:
        run_process([engine, "--headless", "--path", str(project), "--editor", "--import"], project, output / "import", 120)
        verify_sources(project, identity)
    results = []
    for mode in modes:
        verify_sources(project, identity)
        folder = output / mode
        result_path = folder / "result.json"
        command = [engine, "--headless", "--path", str(project)]
        if mode != "plain":
            command += ["--debug", "--ignore-error-breaks"]
        command += ["--script", "res://" + DRIVER, "--", f"--input={identity['input']}",
                    f"--output={result_path}", f"--prefix-steps={prefix}", f"--steps={steps}",
                    "--observed-floor=1", f"--main-thread-policy={args.main_thread_policy}",
                    f"--worker-tasks={args.worker_tasks}", f"--builtin-script-profile={mode}"]
        if args.profile_stages:
            command.append("--profile-stages")
        if args.action == "run":
            command.append("--require-coverage")
        process = run_process(command, project, folder, 120 if args.action == "qualify" else 2400,
                              (0,) if args.action == "qualify" else (0, 1))
        result, status = read(result_path), read(Path(str(result_path) + ".builtin-profile.json"))
        execution = read(Path(str(result_path) + ".execution.json"))
        actual_validation = validate_diagnostic_witness(result_path, identity["input_sha256"]) if args.action == "run" else None
        checks = {
            "complete_window": (actual_validation is not None or (result["complete"] and not result["errors"])) and result["all_completed_steps"] == prefix + steps and result["metrics"]["count"] == steps,
            "same_complete_input": result["source_input_sha256"] == identity["input_sha256"],
            "world_and_ordered_events_witness": digest(Path(str(result_path) + ".final.bin")) == result["final_sha256"] == expected,
            "mode_entry_state": status["before"]["mode"] == mode and not status["before"]["profiling"] and status["before"]["debugger_active"] == (mode != "plain") and status["before"]["has_scripts"] == (mode != "plain"),
            "sample_and_prefix_markers": status["sample_marker_calls"] == steps and status["prefix_marker_calls"] == prefix,
            "native_start_stop": status["started"] == (mode == "scripts") and not status["profiling_after"],
            "worker_configuration": execution["worker_tasks"] == args.worker_tasks,
            "main_thread_policy": args.main_thread_policy != "app" or execution["main_thread_policy"]["applied"],
        }
        if args.action == "run":
            checks["exit_matches_original_coverage_result"] = process["returncode"] == (0 if result["complete"] else 1)
        parsed_summary = None
        if mode == "scripts":
            profile = parse_log(folder / "engine.log", folder / "functions.json", folder / "functions.csv")
            checks.update(marker_checks(profile, steps, status["sample_window_wall_us"] / 1000000))
            checks["start_boundary_tick"] = status["started_tick"] == result["initial"]["tick"] + prefix
            checks["stop_boundary_tick"] = status["ended_tick"] == result["initial"]["tick"] + prefix + steps
            parsed_summary = {key: profile[key] for key in ("function_rows", "active_function_rows", "possible_truncation", "periodic_frame_headers", "log_sha256")}
        else:
            raw = (folder / "engine.log").read_text(encoding="utf-8-sig")
            checks["profiler_not_started"] = "BEGIN PROFILING" not in raw and "ACCUMULATED: total:" not in raw
        if args.profile_stages:
            stages = read(Path(str(result_path) + ".stages.json"))
            checks["complete_root_stage_window"] = not stages["errors"] and stages["step_records_complete"] and stages["complete_steps"] == steps and stages["partition_check_us"] == 0
        verify_sources(project, identity)
        row = {"mode": mode, "ok": all(checks.values()), "checks": checks, "process": process,
               "metrics_diagnostic_only": result["metrics"], "status": status, "function_table": parsed_summary,
               "coverage_validation": actual_validation, "acceptance_pass": None,
               "final_sha256": result["final_sha256"]}
        results.append(row)
        write(output / "summary.json", {"ok": all(row["ok"] for row in results), "completed_modes": results, "scope": SCOPE})
        assert row["ok"], {key: value for key, value in checks.items() if not value}
        print(json.dumps({"mode": mode, "checks": checks, "process_wall_seconds": process["process_wall_seconds"]}), flush=True)
    report = {"ok": True, "completed_modes": results, "diagnostic_only": True, "scope": SCOPE}
    if args.action == "qualify":
        plain, debug_off, scripts = (row["metrics_diagnostic_only"] for row in results)
        report["short_observed_overhead_not_a_full_window_estimate"] = {
            "debug_off_step_us_minus_plain": debug_off["sum_step_us"] - plain["sum_step_us"],
            "scripts_step_us_minus_debug_off": scripts["sum_step_us"] - debug_off["sum_step_us"],
            "scripts_step_us_minus_plain": scripts["sum_step_us"] - plain["sum_step_us"],
        }
    write(output / "summary.json", report)
    write(output / "status.json", {"state": "complete", "ended_utc": utc(), "modes": list(modes)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    prepare_parser = commands.add_parser("prepare", help="Only freeze/patch/verify; never starts Godot")
    for name in ("base-project", "authority", "input", "output"):
        prepare_parser.add_argument("--" + name, type=Path, required=True)
    prepare_parser.add_argument("--input-sha256", required=True)
    prepare_parser.add_argument("--short-expected-final-sha256", required=True)
    prepare_parser.add_argument("--check-only", action="store_true")
    for action in ("qualify", "run"):
        child = commands.add_parser(action, help="Explicit engine execution; obtain the serial engine slot first")
        child.add_argument("--project", type=Path, required=True)
        child.add_argument("--output", type=Path, required=True)
        child.add_argument("--import-project", action="store_true", help="One shared import only if needed")
        child.add_argument("--profile-stages", action="store_true", help="Existing root-only StageTimer; no nested wrappers")
        child.add_argument("--main-thread-policy", choices=("app", "default"), default="app")
        child.add_argument("--worker-tasks", type=int, choices=(0, 1, 4), default=4)
        if action == "run":
            child.add_argument("--mode", choices=MODES, default="scripts")
            child.add_argument("--outcome-reference", type=Path, required=True, help="Completed same-input 1000+6000 plain result JSON")
    args = parser.parse_args()
    try:
        prepare(args) if args.action == "prepare" else execute(args)
    except Exception as error:
        if args.action != "prepare" and args.output.is_dir():
            write(args.output / "status.json", {"state": "failed", "classification": "diagnostic_tool_or_engine_validation",
                                               "error_type": type(error).__name__, "error": str(error), "ended_utc": utc()})
        raise


if __name__ == "__main__":
    main()
