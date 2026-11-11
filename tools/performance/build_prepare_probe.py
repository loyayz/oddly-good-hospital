"""Freeze and instrument synchronous build preparation without changing bodies."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "current"))
from function_probe import arguments


METHODS = {
    "game/building/build_service.gd": ["prepare_preview", "_remember_shape", "_plan", "_scratch", "_add_room", "_change_walls", "_wall_crossing_view", "_add_door", "_prune_room_assignments"],
    "game/building/room_structure.gd": ["reconcile", "_component", "seeds", "units", "edges"],
    "game/building/build_geometry.gd": ["shape", "_flood", "walls"],
    "game/building/build_preview_job.gd": ["dependency_basis", "dependencies"],
}
PREFIX = 'const _BuildPrepareTimer = preload("res://tools/performance/build_prepare_timer.gd")\n'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def instrument(relative, source, names):
    text = source
    spans = []
    anchors = []
    if relative == "game/building/room_structure.gd":
        if "cells.sort_custom(" in source:
            anchors = [
                ('\tvar cells: Array = []\n\tfor point: Vector2i in pending: cells.append([point.x,point.y])\n', '"' + relative + ':_component.collect_cells/"+("closed" if closed else "open")', "cells"),
                ('\tcells.sort_custom(func(a: Array,b: Array)->bool: return a[1]<b[1] or a[1]==b[1] and a[0]<b[0])\n', '"' + relative + ':_component.sort_cells/"+("closed" if closed else "open")', "cells"),
            ]
        else:
            anchors = [
                ('\tvar order: PackedInt32Array = PackedInt32Array()\n\torder.resize(pending.size())\n\tfor index: int in pending.size():\n\t\tvar point: Vector2i = pending[index]\n\t\torder[index] = point.y*96+point.x\n', '"' + relative + ':_component.encode_cells/"+("closed" if closed else "open")', "order"),
                ('\torder.sort()\n', '"' + relative + ':_component.sort_cells/"+("closed" if closed else "open")', "order"),
                ('\tvar cells: Array = []\n\tfor id: int in order: cells.append([id%96,int(id/96)])\n', '"' + relative + ':_component.collect_cells/"+("closed" if closed else "open")', "cells"),
            ]
    elif relative == "game/building/build_geometry.gd":
        if "actual.sort_custom(" in source:
            anchors = [('\tactual.sort_custom(func(a: Array,b: Array) -> bool: return a[1]<b[1] or (a[1]==b[1] and a[0]<b[0]))\n', '"' + relative + ':shape.sort_cells"', "actual")]
        else:
            anchors = [
                ('\torder.sort()\n', '"' + relative + ':shape.sort_cells"', "order"),
                ('\tfor index: int in actual.size():\n\t\tvar id: int = order[index]\n\t\tactual[index] = occupied[Vector2i(id%96,id/96)]\n', '"' + relative + ':shape.restore_cells"', "actual"),
            ]
    for anchor, label, value in anchors:
        assert text.count(anchor) == 1, (relative, "Changed block anchor", anchor)
        updated = "\t_BuildPrepareTimer.enter(" + label + ")\n" + anchor + "\t_BuildPrepareTimer.leave(" + label + "," + value + ")\n"
        text = text.replace(anchor, updated, 1)
        spans.append((anchor, updated))
    wrappers = []
    for name in names:
        matches = list(re.finditer(r"^(?:static )?func " + re.escape(name) + r"\((.*)\) -> ([^\n]+):$", text, re.M))
        assert len(matches) == 1, (relative, name, len(matches))
        match = matches[0]
        header, result_type = match[0], match[2]
        renamed = header.replace("func " + name + "(", "func _prepare_probe_body_" + name + "(", 1)
        text = text[:match.start()] + renamed + text[match.end():]
        key = relative + ":" + name
        call = "_prepare_probe_body_" + name + "(" + arguments(match[1]) + ")"
        wrapper = header + '\n\t_BuildPrepareTimer.enter("' + key + '")\n\t'
        wrapper += ("var value: " + result_type + " = " if result_type != "void" else "") + call
        wrapper += '\n\t_BuildPrepareTimer.leave("' + key + '"' + (",value" if result_type != "void" else "") + ')\n'
        if result_type != "void":
            wrapper += "\treturn value\n"
        wrappers.append((header, renamed, wrapper))
    assert "extends RefCounted\n" in text and PREFIX not in text
    text = text.replace("extends RefCounted\n", "extends RefCounted\n" + PREFIX, 1)
    text += "".join("\n" + wrapper for _, _, wrapper in wrappers)
    restored = text.replace(PREFIX, "", 1)
    for header, renamed, wrapper in wrappers:
        restored = restored.replace("\n" + wrapper, "", 1).replace(renamed, header, 1)
    for anchor, updated in reversed(spans):
        restored = restored.replace(updated, anchor, 1)
    assert restored.encode("utf-8") == source.encode("utf-8"), (relative, "Business method restoration failed")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--plain", action="store_true", help="Freeze without diagnostic wrappers for comparable local timing.")
    parser.add_argument("--geometry-reference", help="With --plain, take only the two geometry files from this Git revision.")
    parser.add_argument("--source-project", type=Path, help="Reuse an immutable acceptance project instead of the live worktree.")
    parser.add_argument("--overlay", action="append", default=[], help="Copy this explicit repository-relative diagnostic file from the worktree.")
    args = parser.parse_args()
    if args.geometry_reference and not args.plain:
        parser.error("--geometry-reference requires --plain")
    root = Path(__file__).resolve().parents[2]
    source_root = args.source_project.resolve() if args.source_project else root
    target = args.output.resolve()
    target.relative_to(root / ".cache")
    target.mkdir(parents=True, exist_ok=False)
    if args.source_project:
        source_manifest = source_root / "source-identity.json"
        paths = [row["path"] for row in json.loads(source_manifest.read_text(encoding="utf-8-sig"))["source"]]
    else:
        source_manifest = None
        paths = subprocess.check_output(["git", "-C", str(root), "-c", "core.quotePath=false", "ls-files", "--cached", "--others", "--exclude-standard"], text=True, encoding="utf-8").splitlines()
    identity = {}
    for relative in sorted(set(paths)):
        source = source_root / relative
        if not source.is_file():
            continue
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        identity[relative] = digest(destination.read_bytes())
    for relative in [".godot/imported", "game/platform/windows/bin"]:
        shutil.copytree(source_root / relative, target / relative, dirs_exist_ok=True)
    for relative in [".godot/global_script_class_cache.cfg", ".godot/extension_list.cfg"]:
        shutil.copy2(source_root / relative, target / relative)
    changes = {}
    assert all(digest((source_root / relative).read_bytes()) == value for relative, value in identity.items()), "Source changed during freezing"
    for relative in args.overlay:
        source = (root / relative).resolve()
        source.relative_to(root)
        if not relative.startswith("tools/performance/") or not source.is_file():
            parser.error("Only explicit existing tools/performance diagnostic overlays are allowed")
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        changes[relative] = {"base_sha256": identity.get(relative), "overlay_sha256": digest(destination.read_bytes()), "diagnostic_overlay": True}
        identity[relative] = digest(destination.read_bytes())
    for relative, names in ([] if args.plain else METHODS.items()):
        path = target / relative
        source = path.read_bytes().decode("utf-8")
        assert "\r\n" not in source, (relative, "LF required for exact restoration")
        path.write_bytes(instrument(relative, source, names).encode("utf-8"))
        changes[relative] = {"methods": names, "block_spans": ["open/closed collect_cells", "open/closed sort_cells"] if relative.endswith("room_structure.gd") else (["shape sort_cells"] if relative.endswith("build_geometry.gd") else []), "original_sha256": identity[relative], "instrumented_sha256": digest(path.read_bytes()), "method_body_restoration_byte_exact": True}
    if args.geometry_reference:
        for relative in ["game/building/build_geometry.gd", "game/building/room_structure.gd"]:
            raw = subprocess.check_output(["git", "-C", str(root), "show", args.geometry_reference + ":" + relative])
            (target / relative).write_bytes(raw)
            changes[relative] = {"worktree_sha256": identity[relative], "reference_sha256": digest(raw), "reference": args.geometry_reference, "instrumented": False}
            identity[relative] = digest(raw)
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    metadata = {"head": head, "source_project": str(source_root), "source_manifest_sha256": digest(source_manifest.read_bytes()) if source_manifest else None, "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "source": identity, "changes": changes, "instrumented": not args.plain, "geometry_reference": args.geometry_reference, "native_sha256": digest((target / "game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll").read_bytes()), "scope": "Plain local comparison snapshot." if args.plain else "Diagnostic wrappers/spans only; restored method bodies are byte-identical. Instrumented times do not prove speedup."}
    (target / "build-prepare-identity.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    (target / "source-inventory.json").write_text(json.dumps(sorted(identity), ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"project": str(target), "head": head, "files": len(identity), "wrapped_methods": 0 if args.plain else sum(map(len, METHODS.values()))}))


if __name__ == "__main__":
    main()
