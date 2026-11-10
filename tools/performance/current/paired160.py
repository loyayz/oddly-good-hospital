"""Three adjacent, serial A/B pairs with unchanged full 160-person windows."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import sys

from campaign160 import digest, read, source_identity, write


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile-stages", action="store_true")
    args = parser.parse_args()
    roots = {"A": args.baseline.resolve(), "B": args.candidate.resolve()}
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    identities = {name: source_identity(root) for name, root in roots.items()}
    order = [("A", 1), ("B", 1), ("B", 2), ("A", 2), ("A", 3), ("B", 3)]
    write(output / "protocol.json", {"order": order, "roots": {k: str(v) for k, v in roots.items()},
          "input_sha256": digest(args.input), "prefix": 1000, "samples": 2000, "repeats_per_variant": 3,
          "profile_stages": args.profile_stages, "main_thread_policy": "app", "worker_tasks": 4,
          "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    rows = []
    for name, repeat in order:
        for variant, root in roots.items():
            assert source_identity(root) == identities[variant], f"{variant} source changed"
        command = [sys.executable, "-X", "utf8", "-B", str(roots[name] / "tools/performance/current/campaign160.py"),
                   "--engine", str(args.engine.resolve()), "--input", str(args.input.resolve()),
                   "--output", str(output / f"{name}{repeat}"), "--repeat-number", str(repeat)]
        if args.profile_stages:
            command.append("--profile-stages")
        if rows:
            command += ["--exact-reference", str(output / "A1")]
        print(f"PAIR {name}{repeat}", flush=True)
        subprocess.run(command, check=True, cwd=roots[name])
        row = read(output / f"{name}{repeat}" / "summary.json")[0]
        rows.append({"variant": name, "pair": repeat, **row})
        write(output / "summary.json", rows)
    write(output / "status.json", {"state": "complete", "repeats_per_variant": 3,
          "ended_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()})


if __name__ == "__main__":
    main()
