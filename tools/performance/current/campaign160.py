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
    paths = git(root, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    return {p: digest(root / p) for p in sorted(set(paths))
            if (root / p).is_file() and not p.endswith(".gd.uid")}


def processes():
    script = ("@(Get-Process | Where-Object {$_.ProcessName -match "
              "'^(Godot.*|zig|clang.*|gcc|g\\+\\+|ninja|cmake)$'} | "
              "Select-Object Id,ProcessName,CPU)|ConvertTo-Json -Compress")
    raw = subprocess.check_output(["pwsh", "-NoProfile", "-Command", script],
                                  text=True, encoding="utf-8")
    return json.loads(raw) if raw.strip() else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile-stages", action="store_true")
    parser.add_argument("--main-thread-policy", choices=["app", "default"], default="app")
    parser.add_argument("--worker-tasks", choices=[0, 1, 4], type=int, default=4)
    parser.add_argument("--exact-reference", type=Path)
    parser.add_argument("--smoke", action="store_true", help="Two-step tool qualification, no performance claim")
    parser.add_argument("--repeat-number", type=int, choices=[1, 2, 3], help="One full repeat for the serial paired controller; never shortens either window")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output, engine, input_path = args.output.resolve(), args.engine.resolve(), args.input.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = source_identity(root)
    prefix, steps, repeats = (0, 2, 1) if args.smoke else (1000, 2000, 3)
    assert not (args.smoke and args.repeat_number), "Smoke is not a paired measurement"
    if args.repeat_number:
        repeats = 1
    protocol = {"commit": git(root, "rev-parse", "HEAD"),
                "tree": git(root, "rev-parse", "HEAD^{tree}"),
                "tracked_diff": git(root, "diff", "HEAD", "--"),
                "input_sha256": digest(input_path), "input": str(input_path),
                "engine": str(engine), "engine_sha256": digest(engine),
                "runner_sha256": digest(root / "tools/performance/current/plain_v4.gd"),
                "native": {p.name: digest(p) for p in (root / "game/platform/windows/bin").glob("*.dll")},
                "prefix_steps": prefix, "sample_steps": steps, "repeats": repeats,
                "main_thread_policy": args.main_thread_policy, "worker_tasks": args.worker_tasks,
                "profile_stages": args.profile_stages, "OMP_NUM_THREADS": "1",
                "paired_repeat": args.repeat_number,
                "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "scope": "Simulation.step elapsed, no renderer/GameSession. Fresh processes; OS caches retained. Desktop applications remain running. Stage timers are diagnostic."}
    write(output / "protocol.json", protocol)
    write(output / "source-identity.json", source)
    environment = dict(os.environ, OMP_NUM_THREADS="1")
    results = []
    for repeat in range(1, repeats + 1):
        assert source_identity(root) == source, "Source changed during the series"
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
                        process.terminate()
                        break
                    if time.perf_counter() - started > 1800:
                        raise TimeoutError("Engine exceeded 1800 seconds")
                process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
        elapsed = time.perf_counter() - started
        data = read(result_path) if result_path.exists() else {}
        raw = (output / f"r{repeat}.log").read_text(encoding="utf-8")
        assert process.returncode == 0 and data.get("complete") and not data.get("errors"), raw[-5000:]
        assert "SCRIPT ERROR" not in raw and not any(l.startswith("ERROR:") for l in raw.splitlines()), raw[-5000:]
        assert data["all_completed_steps"] == prefix + steps and data["metrics"]["count"] == steps
        assert digest(Path(str(result_path) + ".final.bin")) == data["final_sha256"]
        execution = read(Path(str(result_path) + ".execution.json"))
        if args.main_thread_policy == "app":
            assert execution["main_thread_policy"]["applied"], execution["main_thread_policy"]
        if results:
            assert data["final_sha256"] == results[0]["final_sha256"], "Repeat business outcome changed"
        if args.exact_reference:
            assert data["final_sha256"] == read(args.exact_reference / "r1.json")["final_sha256"], "Diagnostic/candidate outcome differs from the reference"
        assert source_identity(root) == source, "Source changed during execution"
        row = {"repeat": repeat, "returncode": process.returncode, "wall_seconds": elapsed,
               "metrics": data["metrics"], "business": data["sample_business"],
               "final_sha256": data["final_sha256"], "execution": execution}
        results.append(row)
        write(output / "summary.json", results)
        print(json.dumps({"repeat": repeat, "metrics": data["metrics"], "policy": execution["main_thread_policy"]}), flush=True)
    write(output / "status.json", {"state": "complete", "repeats": repeats,
                                   "ended_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()})


if __name__ == "__main__":
    main()
