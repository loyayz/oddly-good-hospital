"""Prepare runner controls for production WorkerThreadPool sampling.

Example: python tools/performance/experiments/worker_sample_experiment.py
         --project=C:/path/prepared-copy

This command does not launch Godot. The generated representative_worker.gd keeps
the measured runtime flags; its default is --workers=on, with an explicit off control.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PROOF_NAME = "worker-sample-source-proof.json"


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def inside(project: Path, relative: str) -> Path:
    path = (project / relative).resolve()
    if not path.is_relative_to(project):
        raise ValueError(f"Path escapes the prepared project: {relative}")
    return path


def transform(original: bytes, replacements: list[dict], path: str) -> bytes:
    generated = original
    for index, row in enumerate(replacements):
        before, after = row["original"].encode("utf-8"), row["generated"].encode("utf-8")
        if generated.count(before) != 1:
            raise ValueError(f"Exact fragment {index + 1} must occur once: {path}")
        generated = generated.replace(before, after, 1)
    restored = generated
    for row in reversed(replacements):
        before, after = row["original"].encode("utf-8"), row["generated"].encode("utf-8")
        if restored.count(after) != 1:
            raise ValueError(f"Generated fragment cannot be reversed uniquely: {path}")
        restored = restored.replace(after, before, 1)
    if restored != original:
        raise ValueError(f"Inverse byte verification failed: {path}")
    return generated


def prepare(project: Path) -> dict:
    project = project.resolve(strict=True)
    if project == REPO:
        raise ValueError("--project must be a prepared Godot project copy, not this repository")
    if not project.is_dir() or not inside(project, "project.godot").is_file():
        raise ValueError("--project must contain an already prepared project.godot")
    manifest_path = HERE / "worker_sample_patches.json"
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw)
    rows = manifest["files"]
    writes: dict[Path, bytes] = {}
    inputs: dict[Path, bytes] = {manifest_path: manifest_raw}
    production = manifest["production_helper"]
    production_path = inside(project, production["path"])
    production_raw = production_path.read_bytes()
    if digest(production_raw) != production["sha256"]:
        raise ValueError("Prepared project must already contain the integrated production Worker helper")
    inputs[production_path] = production_raw
    proofs = []
    for row in rows:
        source = inside(project, row["source"])
        target = inside(project, row["target"])
        if source != target and target.exists():
            raise ValueError(f"Experiment output already exists: {row['target']}")
        original = source.read_bytes()
        generated = transform(original, row["replacements"], row["source"])
        inputs[source] = original
        writes[target] = generated
        proofs.append({"source": row["source"], "target": row["target"],
                       "original_sha256": digest(original), "generated_sha256": digest(generated),
                       "inverse_byte_equal": True, "replacements": row["replacements"]})
    proof_path = inside(project, PROOF_NAME)
    if proof_path.exists():
        raise ValueError(f"Source proof already exists: {proof_path}")
    proof = {"schema_version": 1, "diagnostic_only": True, "formal_pass": False,
             "engine_started": False, "project": str(project),
             "tool_sha256": digest(Path(__file__).read_bytes()),
             "patch_manifest_sha256": digest(manifest_raw), "files": proofs,
             "production_helper": production,
             "all_fragments_checked_before_writes": True,
             "switches": {"sample_workers_enabled": True, "sample_worker_tasks": 4,
                          "sample_worker_diagnostics": False},
             "runner": {"script": "res://tools/performance/representative_worker.gd",
                        "defaults": {"workers": "on", "worker-tasks": "4",
                                     "worker-diagnostics": "false", "worker-records": "false"},
                        "worker_records_outside_step_timing": True,
                        "initialization_or_warming_outside_step": False},
             "report": "departments.sample_worker_report()"}
    writes[proof_path] = (json.dumps(proof, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    # Finish every match, inverse check and output check before creating files.
    for source, original in inputs.items():
        if source.read_bytes() != original:
            raise ValueError(f"Source changed during preparation: {source}")
    for target, raw in writes.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    return {"project": str(project), "proof": str(proof_path),
            "changed_files": [row["target"] for row in proofs], "engine_started": False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True,
                        help="Existing prepared Godot copy; the current repository is rejected")
    args = parser.parse_args()
    try:
        result = prepare(args.project)
    except (OSError, ValueError) as error:
        parser.exit(2, f"worker_sample_experiment: {error}\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
