"""Serial Windows 160-person measurements. Never overwrites an evidence directory."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def source_identity(root):
    # A frozen diagnostic beneath .cache is not the parent Git worktree.
    # Its preparer supplies the source inventory, excluding runtime outputs.
    inventory = root / "source-inventory.json"
    paths = read(inventory) if inventory.is_file() else git(root, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    assert paths, "Empty measured source inventory; provide source-inventory.json for an isolated project"
    return {p: digest(root / p) for p in sorted(set(paths))
            if (root / p).is_file() and not p.endswith(".gd.uid")}


def native_identity(root):
    return {p.name: digest(p) for p in (root / "game/platform/windows/bin").glob("*.dll")}


def engine_identity(engine):
    executables = [engine]
    # The Windows console launcher executes its sibling engine binary.
    if engine.stem.endswith("_console"):
        actual = engine.with_name(engine.stem.removesuffix("_console") + engine.suffix)
        assert actual.is_file(), f"Missing console launcher's engine: {actual}"
        executables.append(actual)
    return {str(path): digest(path) for path in executables}


def stop_owned_process_tree(process):
    if process.poll() is not None:
        return
    if os.name == "nt":
        # Limit termination to this run's Popen identity and its descendants.
        script = (f"$ownedProcess=[System.Diagnostics.Process]::GetProcessById({process.pid}); "
                  "$ownedProcess.Kill($true); $ownedProcess.WaitForExit()")
        subprocess.run(["pwsh", "-NoProfile", "-Command", script],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                       creationflags=subprocess.CREATE_NO_WINDOW, check=True)
    if process.poll() is None:
        process.kill()
    process.wait(timeout=10)


def processes():
    script = ("@(Get-Process | Where-Object {$_.ProcessName -match "
              "'^(Godot.*|zig|clang.*|gcc|g\\+\\+|ninja|cmake)$'} | "
              "Select-Object Id,ProcessName,CPU)|ConvertTo-Json -Compress")
    raw = subprocess.check_output(["pwsh", "-NoProfile", "-Command", script],
                                  text=True, encoding="utf-8")
    return json.loads(raw) if raw.strip() else []


def target_checks(metrics, targets):
    return {
        "p95": metrics["p95_us"] <= targets["sim_step_p95_ms"] * 1000,
        "p99": metrics["p99_us"] <= targets["sim_step_p99_ms"] * 1000,
        "ordinary_maximum": metrics["max_us"] <= targets["sim_step_ordinary_max_ms"] * 1000,
        "speed_1x_including_observation": metrics["simulation_seconds_per_wall_second"] >= targets["sim_speed_ratio_min"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile-stages", action="store_true")
    parser.add_argument("--main-thread-policy", choices=["app", "default"], default="app")
    parser.add_argument("--worker-tasks", choices=[0, 1, 4], type=int, default=4)
    parser.add_argument("--outcome-reference", "--exact-reference", dest="outcome_reference", type=Path,
                        help="Same input/window full final-world and ordered-event hash witness; not the retired clinical capacity reference")
    parser.add_argument("--smoke", action="store_true", help="Two-step tool qualification, no performance claim")
    parser.add_argument("--repeat-number", type=int, choices=[1, 2, 3], help="One full repeat for the serial paired controller; never shortens either window")
    parser.add_argument("--prefix-steps", type=int, default=1000)
    parser.add_argument("--sample-steps", type=int, default=6000)
    parser.add_argument("--require-coverage", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output, engine, input_path = args.output.resolve(), args.engine.resolve(), args.input.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = source_identity(root)
    targets = read(root / "docs/data/balance.json")["performance_targets"]["metrics"]
    assert args.prefix_steps >= 0 and args.sample_steps >= 1000, "A measured window requires at least 1000 samples"
    prefix, steps, repeats = (0, 2, 1) if args.smoke else (args.prefix_steps, args.sample_steps, 3)
    assert not (args.smoke and args.repeat_number), "Smoke is not a paired measurement"
    if args.repeat_number:
        repeats = 1
    protocol = {"commit": git(root, "rev-parse", "HEAD"),
                "tree": git(root, "rev-parse", "HEAD^{tree}"),
                "tracked_diff": git(root, "diff", "HEAD", "--"),
                "input_sha256": digest(input_path), "input": str(input_path),
                "engine": str(engine), "engine_sha256": digest(engine),
                "engine_executables": engine_identity(engine),
                "runner_sha256": digest(root / "tools/performance/current/plain_v4.gd"),
                "native": native_identity(root),
                "prefix_steps": prefix, "sample_steps": steps, "repeats": repeats,
                "main_thread_policy": args.main_thread_policy, "worker_tasks": args.worker_tasks,
                "profile_stages": args.profile_stages, "OMP_NUM_THREADS": "1",
                "require_coverage": args.require_coverage and not args.smoke,
                "cpu_targets": {key: targets[key] for key in (
                    "sim_step_p95_ms", "sim_step_p99_ms", "sim_step_ordinary_max_ms", "sim_speed_ratio_min")},
                "source_inventory_sha256": digest(root / "source-inventory.json") if (root / "source-inventory.json").is_file() else None,
                "git_metadata_scope": "Enclosing Git checkout; frozen source identity is source-identity.json and its preparation record" if (root / "source-inventory.json").is_file() else "Measured Git worktree",
                "paired_repeat": args.repeat_number,
                "outcome_reference": str(args.outcome_reference.resolve()) if args.outcome_reference else None,
                "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "scope": "Simulation.step elapsed, no renderer/GameSession. Fresh processes; OS caches retained. Desktop applications remain running. Stage timers are diagnostic."}
    write(output / "protocol.json", protocol)
    write(output / "source-identity.json", source)
    environment = dict(os.environ, OMP_NUM_THREADS="1")
    results = []
    for repeat in range(1, repeats + 1):
        assert source_identity(root) == source, "Source changed during the series"
        assert native_identity(root) == protocol["native"], "Native libraries changed during the series"
        assert digest(engine) == protocol["engine_sha256"], "Engine changed during the series"
        assert engine_identity(engine) == protocol["engine_executables"], "Executed engine changed during the series"
        assert digest(input_path) == protocol["input_sha256"], "Input changed"
        before = processes()
        write(output / f"r{repeat}.processes-before.json", before)
        assert not before, f"Another engine/compiler is active: {before}"
        result_path = output / f"r{repeat}.json"
        command = [str(engine), "--headless", "--path", str(root), "--script",
                   "res://tools/performance/current/plain_v4.gd", "--",
                   f"--input={input_path}", f"--output={result_path}",
                   f"--prefix-steps={prefix}", f"--steps={steps}", "--observed-floor=1",
                   f"--main-thread-policy={args.main_thread_policy}", f"--worker-tasks={args.worker_tasks}"]
        if args.profile_stages:
            command.append("--profile-stages")
        if args.require_coverage and not args.smoke:
            command.append("--require-coverage")
        write(output / "status.json", {"state": "running", "repeat": repeat, "command": command})
        print(f"START repeat={repeat} output={result_path}", flush=True)
        started = time.perf_counter()
        log_path = output / f"r{repeat}.log"
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=environment,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                while process.poll() is None:
                    time.sleep(2)
                    messages = log_path.read_text(encoding="utf-8")
                    if "SCRIPT ERROR:" in messages or any(l.startswith("ERROR:") for l in messages.splitlines()):
                        stop_owned_process_tree(process)
                        break
                    if time.perf_counter() - started > 1800:
                        raise TimeoutError("Engine exceeded 1800 seconds")
                process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    stop_owned_process_tree(process)
        elapsed = time.perf_counter() - started
        data = read(result_path) if result_path.exists() else {}
        raw = (output / f"r{repeat}.log").read_text(encoding="utf-8")
        assert process.returncode == 0 and data.get("complete") and not data.get("errors"), {
            "returncode": process.returncode, "reason": data.get("reason"), "errors": data.get("errors"),
            "coverage": data.get("sample_business", {}).get("comprehensive"), "log_tail": raw[-2500:]}
        assert "SCRIPT ERROR" not in raw and not any(l.startswith("ERROR:") for l in raw.splitlines()), raw[-5000:]
        assert data["all_completed_steps"] == prefix + steps and data["metrics"]["count"] == steps
        if args.require_coverage and not args.smoke:
            assert data["sample_business"]["comprehensive"]["coverage_pass"], data["sample_business"]["comprehensive"]
        metrics = data["metrics"]
        checks = target_checks(metrics, targets)
        dense = metrics["dense_intervals"]
        dense_checks = [{"first_index": interval["first_index"], "last_index": interval["last_index"],
                         "count": interval["metrics"]["count"], "sample_count_qualified": interval["sample_count_qualified"],
                         "checks": target_checks(interval["metrics"], targets)}
                        for interval in dense["segments"]]
        checks["dense_interval_samples"] = dense["has_qualified_segment"]
        checks["dense_interval_targets"] = bool(dense_checks) and all(all(row["checks"].values()) for row in dense_checks)
        if not args.smoke:
            assert data["initial"]["population"]["present"] == 160, "The measured initial population is not 160 real actors"
        assert digest(Path(str(result_path) + ".final.bin")) == data["final_sha256"]
        execution = read(Path(str(result_path) + ".execution.json"))
        if args.main_thread_policy == "app":
            assert execution["main_thread_policy"]["applied"], execution["main_thread_policy"]
        if results:
            assert data["final_sha256"] == results[0]["final_sha256"], "Repeat business outcome changed"
        if args.outcome_reference:
            reference = read(args.outcome_reference / "r1.json")
            assert reference["source_input_sha256"] == protocol["input_sha256"], "Outcome witness used a different complete input"
            assert reference["requested_sample_steps"] == steps and reference["requested_prefix_steps"] == prefix, "Outcome witness used another window"
            assert data["final_sha256"] == reference["final_sha256"], "Diagnostic/candidate final world or ordered events differ from the requested witness"
        assert source_identity(root) == source, "Source changed during execution"
        assert native_identity(root) == protocol["native"], "Native libraries changed during execution"
        assert digest(input_path) == protocol["input_sha256"], "Input changed during execution"
        assert digest(engine) == protocol["engine_sha256"], "Engine changed during execution"
        assert engine_identity(engine) == protocol["engine_executables"], "Executed engine changed during execution"
        row = {"repeat": repeat, "returncode": process.returncode, "wall_seconds": elapsed,
               "metrics": data["metrics"], "business": data["sample_business"],
               "cpu_target_checks": checks, "cpu_targets_pass": all(checks.values()) if not args.smoke else None,
               "dense_interval_checks": dense_checks,
               "final_sha256": data["final_sha256"], "execution": execution}
        results.append(row)
        write(output / "summary.json", results)
        print(json.dumps({"repeat": repeat, "metrics": data["metrics"], "policy": execution["main_thread_policy"]}), flush=True)
    write(output / "status.json", {"state": "complete", "repeats": repeats,
                                   "ended_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()})


if __name__ == "__main__":
    main()
