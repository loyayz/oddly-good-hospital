"""Prepare same-project local A/B scripts, without starting Godot.

The archived A source and current B source differ only by the production change.
Renamed copies keep their exact native-script identity guard. Counted copies
retain the actual seed solely for an untimed container inspection.
"""
import argparse
import hashlib
import json
from pathlib import Path


SOURCE = "game/operations/environment_sample_batch.gd"
PREPARED = "tools/performance/prepared_experience_sample"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def variant(original, resource_path, counted):
    text = original.decode("utf-8")
    original_path = "res://" + SOURCE
    assert text.count(original_path) == 1
    result = text.replace(original_path, resource_path)
    field = "var _prepare_probe_seed: Dictionary = {}\n"
    capture = "\t_prepare_probe_seed = coverage_seed\n"
    field_anchor = "enum RequestSlot { VISIT_ID, ACTOR_ID, FLOOR_ID, CELL }\n"
    capture_anchor = "\tfor index: int in count:\n\t\tvar low: int = worker_requests.size()*index/count\n"
    if counted:
        assert result.count(field_anchor) == result.count(capture_anchor) == 1
        result = result.replace(field_anchor, field + field_anchor, 1)
        result = result.replace(capture_anchor, capture + capture_anchor, 1)
    restored = result
    if counted:
        restored = restored.replace(field + field_anchor, field_anchor, 1)
        restored = restored.replace(capture + capture_anchor, capture_anchor, 1)
    restored = restored.replace(resource_path, original_path)
    assert restored.encode("utf-8") == original
    return result.encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--baseline-source", required=True, type=Path)
    args = parser.parse_args()
    project = args.project.resolve()
    assert project != Path(__file__).resolve().parents[2], "Use a frozen project"
    destination = project / PREPARED
    assert not destination.exists(), destination
    sources = {"a": args.baseline_source.read_bytes(), "b": (project / SOURCE).read_bytes()}
    assert sources["a"] != sources["b"], "A and B must contain the intended change"
    manifest = {"original_source": SOURCE, "original_sha256": {key: digest(value) for key, value in sources.items()}, "scripts": {}, "source": {},
                "scope": "Local prepare/consume only. Plain timings have no counting hooks; counted copies run separately. Native-script path remapping is reversed byte for byte. No engine or test is launched by preparation."}
    generated = {}
    for name, version, counted in [("a", "a", False), ("a_counted", "a", True), ("b_counted", "b", True)]:
        relative = PREPARED + "/" + name + ".gd"
        path = "res://" + relative
        raw = variant(sources[version], path, counted)
        generated[relative] = raw
        manifest["scripts"][name] = path
        manifest["source"][relative] = {"sha256": digest(raw), "original_sha256": digest(sources[version]), "counted": counted, "restoration_exact": True}
    manifest["scripts"]["b"] = "res://" + SOURCE
    destination.mkdir(parents=True)
    for relative, raw in generated.items():
        (project / relative).write_bytes(raw)
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"prepared": True, "project": str(project), "manifest": str(destination / "manifest.json"), "source": manifest["original_sha256"]}))


if __name__ == "__main__":
    main()
