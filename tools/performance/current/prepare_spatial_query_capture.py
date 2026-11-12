"""Install/remove observation hooks in one existing .cache project; never runs Godot."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

BODY = "game/building/body_index.gd"
HELPERS = ["tools/performance/current/spatial_query_capture.gd",
           "tools/performance/current/spatial_query_probe.gd"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "restore"])
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--record", type=Path, required=True)
    parser.add_argument("--expected-body-sha")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    project = args.project.resolve()
    record = args.record.resolve()
    assert project.is_relative_to(root / ".cache") and record.is_relative_to(root / ".cache")
    target = project / BODY
    if args.action == "restore":
        saved = json.loads(record.read_text(encoding="utf-8"))
        assert saved["project"] == str(project) and sha(target.read_bytes()) == saved["capture_sha256"]
        original = base64.b64decode(saved["original_base64"])
        assert sha(original) == saved["original_sha256"]
        target.write_bytes(original)
        assert target.read_bytes() == original
        print(json.dumps({"restored_byte_exact": True, "body_sha256": sha(original)}))
        return
    assert not record.exists() and args.expected_body_sha
    original = target.read_bytes()
    assert sha(original) == args.expected_body_sha and b"\r" not in original
    text = original.decode("utf-8")
    edits = [
        ("class_name BodyIndex\nextends RefCounted\n", 'class_name BodyIndex\nextends RefCounted\n\nconst SpatialCapture = preload("res://tools/performance/current/spatial_query_capture.gd")\nvar _capture_id: int = 0\n'),
        ("\tbucket_cells = cells\n", "\tbucket_cells = cells\n\t_capture_id = SpatialCapture.register_index()\n"),
        ("\t_tree.clear()\n", '\t_tree.clear()\n\tSpatialCapture.event(["clear",_capture_id])\n'),
        ("\t_tree.update(id,floor_id,[rect.position.x,rect.position.y,rect.size.x,rect.size.y])\n", '\t_tree.update(id,floor_id,[rect.position.x,rect.position.y,rect.size.x,rect.size.y])\n\tSpatialCapture.event(["update",_capture_id,id,floor_id,rect])\n'),
        ("\t_tree.remove(id)\n", '\t_tree.remove(id)\n\tSpatialCapture.event(["remove",_capture_id,id])\n'),
        ('\tif not _has_current_records: return []\n\treturn _tree.query_rect(floor_id,rect).ids\n', '\tif not _has_current_records:\n\t\tSpatialCapture.event(["query",_capture_id,floor_id,rect,false,[]])\n\t\treturn []\n\tvar ids: Array = _tree.query(floor_id,[rect.position.x,rect.position.y,rect.size.x,rect.size.y]).ids\n\tSpatialCapture.event(["query",_capture_id,floor_id,rect,true,ids])\n\treturn ids\n'),
    ]
    for before, after in edits:
        assert text.count(before) == 1, before
        text = text.replace(before, after, 1)
    restored = text
    for before, after in reversed(edits):
        assert restored.count(after) == 1
        restored = restored.replace(after, before, 1)
    assert restored.encode() == original
    helpers = {}
    for relative in HELPERS:
        data = (root / relative).read_bytes()
        destination = project / relative
        assert not destination.exists() or destination.read_bytes() == data
        helpers[relative] = {"data": data, "sha256": sha(data)}
    saved = {"project": str(project), "original_sha256": sha(original), "capture_sha256": sha(text.encode()),
             "original_base64": base64.b64encode(original).decode(), "reverse_byte_exact": True,
             "helpers": {name: row["sha256"] for name, row in helpers.items()},
             "scope": "Diagnostic only: _query uses the unchanged Array API while recording all original results. No simulation, compile, native replacement or whole-project copy occurs. Restore removes every runtime hook; helper files remain inert."}
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(json.dumps(saved, indent=2) + "\n", encoding="utf-8")
    for relative, row in helpers.items():
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(row["data"])
    target.write_bytes(text.encode())
    print(json.dumps({"installed": True, "capture_sha256": saved["capture_sha256"], "reverse_byte_exact": True}))


if __name__ == "__main__":
    main()
