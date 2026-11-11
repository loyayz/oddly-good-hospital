"""Freeze reversible Snapshot preparation/write timing; never launch the engine."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import uuid


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def instrument(raw):
    source = raw.decode("utf-8")
    assert "\r" not in source, "Exact restoration requires repository LF"
    prefix = 'const _SnapshotPrepareTrace = preload("res://tools/performance/snapshot_prepare_trace.gd")\n'
    scope = "_snapshot_prepare_scope"

    def measured(label, function, arguments):
        return f'_SnapshotPrepareTrace.measure({scope},"{label}",{function},[{arguments}])'

    def start(label):
        return f'\t_SnapshotPrepareTrace.start({scope},"{label}")\n'

    def stop(label):
        return f'\t_SnapshotPrepareTrace.stop({scope},"{label}")\n'

    pairs = [("extends RefCounted\n", "extends RefCounted\n" + prefix)]
    begin_header = next(line for line in source.splitlines(True) if line.startswith("func _begin_world("))
    write_header = next(line for line in source.splitlines(True) if line.startswith("func _write("))
    for name, header, extra in [("_begin_world", begin_header, " = {}"), ("_write", write_header, "")]:
        changed = header.replace("func " + name, "func _snapshot_prepare_body" + name, 1).replace(") -> Dictionary:", f", {scope}: Dictionary{extra}) -> Dictionary:", 1)
        pairs.append((header, changed))
    pairs += [
        ('\tvar reason: String = world.validate(content)\n', '\tvar reason: String = ' + measured("validate", "world.validate", "content") + '\n'),
        ('\tif not _budget(estimate(world.facts)):\n', '\tif not ' + measured("budget", "_budget", measured("estimate", "estimate", "world.facts")) + ':\n'),
        ('\tvar snapshot_id: String = str(identity.get("snapshot_id",uuid()))\n', start("request") + '\tvar snapshot_id: String = str(identity.get("snapshot_id",uuid()))\n'),
        ('"slot_kind":kind,"slot_key":slot,"content_packs":_content_identity()}\n', '"slot_kind":kind,"slot_key":slot,"content_packs":' + measured("content_identity", "_content_identity", "") + '}\n' + stop("request")),
        ('\tvar frozen: Dictionary = world.freeze()\n', '\tvar frozen: Dictionary = ' + measured("freeze", "world.freeze", "") + '\n'),
        ('\t_thread = Thread.new()\n', start("thread_start") + '\t_thread = Thread.new()\n'),
        ('\tvar start_error: Error = _thread.start(_write.bind(frozen,_request.duplicate(true)))\n', '\tvar start_error: Error = _thread.start(_write.bind(frozen,_request.duplicate(true)))\n' + stop("thread_start")),
    ]
    begin_start = source.index(begin_header)
    begin_end = source.index('\nfunc ', begin_start + len(begin_header))
    begin = source[begin_start:begin_end]
    instrumented_begin = begin
    for original, changed in pairs[3:]:
        assert instrumented_begin.count(original) == 1, ("begin anchor", original)
        instrumented_begin = instrumented_begin.replace(original, changed, 1)
    pairs = [pairs[0], (begin, instrumented_begin), *pairs[1:3]]
    # Confine worker replacements to its complete original method.
    worker_start = source.index(write_header)
    worker_end = source.index('\nfunc ', worker_start + len(write_header))
    worker = source[worker_start:worker_end]
    worker_pairs = [
        ('\tvar imported: Dictionary = _legacy_import(request.hospital_id)\n', '\tvar imported: Dictionary = ' + measured("legacy_import", "_legacy_import", "request.hospital_id") + '\n'),
        ('\tvar opened: Dictionary = _connect(request.hospital_id,true)\n', start("database_prepare") + '\tvar opened: Dictionary = _connect(request.hospital_id,true)\n'),
        ('\tvar encoder: HospitalJsonStream = HospitalJsonStream.new()\n', stop("database_prepare") + '\tvar encoder: HospitalJsonStream = HospitalJsonStream.new()\n'),
        ('encoder.encode_to(frozen,_budget,sink)', measured("encode_and_chunk_writes", "encoder.encode_to", "frozen,_budget,sink")),
        ('\tif result.ok:\n\t\tvar manifest: Dictionary = ', start("manifest") + '\tif result.ok:\n\t\tvar manifest: Dictionary = '),
        ('\tif result.ok:\n\t\tresult = _read_snapshot(database,request.hospital_id,request.snapshot_id,false)\n', stop("manifest") + '\tif result.ok:\n\t\tresult = ' + measured("read_back_validate", "_read_snapshot", "database,request.hospital_id,request.snapshot_id,false") + '\n'),
        ('\tif result.ok:\n\t\tresult = database.call("execute","COMMIT",[])\n\tdatabase.call("close")\n', start("commit_close") + '\tif result.ok:\n\t\tresult = database.call("execute","COMMIT",[])\n\tdatabase.call("close")\n' + stop("commit_close")),
        ('\tvar final_check: Dictionary = load_commit(request.hospital_id,request.snapshot_id)\n', '\tvar final_check: Dictionary = ' + measured("final_load_validate", "load_commit", "request.hospital_id,request.snapshot_id") + '\n'),
        ('\t_cleanup(request.hospital_id,request.snapshot_id)\n', '\t' + measured("cleanup", "_cleanup", "request.hospital_id,request.snapshot_id") + '\n'),
    ]
    instrumented_worker = worker
    for original, changed in worker_pairs:
        assert instrumented_worker.count(original) == 1, ("worker anchor", original)
        instrumented_worker = instrumented_worker.replace(original, changed, 1)
    # The whole worker block replacement precedes its header rename.
    pairs.insert(1, (worker, instrumented_worker))
    text = source
    for original, changed in pairs:
        assert text.count(original) == 1, ("snapshot anchor", original)
        text = text.replace(original, changed, 1)
    wrappers = '\n' + begin_header + f'\tvar {scope}: Dictionary={{}}\n\tvar started_at: int=Time.get_ticks_usec()\n\tvar result: Dictionary=_snapshot_prepare_body_begin_world(world,session_id,kind,slot,identity,{scope})\n\t{scope}.total_usec=Time.get_ticks_usec()-started_at\n\tresult._snapshot_prepare_begin={scope}\n\treturn result\n\n' + write_header + f'\tvar {scope}: Dictionary={{}}\n\tvar started_at: int=Time.get_ticks_usec()\n\tvar result: Dictionary=_snapshot_prepare_body_write(frozen,request,{scope})\n\t{scope}.total_usec=Time.get_ticks_usec()-started_at\n\tresult._snapshot_prepare_worker={scope}\n\treturn result\n'
    text += wrappers
    restored = text.removesuffix(wrappers)
    for original, changed in reversed(pairs):
        assert restored.count(changed) == 1, ("ambiguous reverse", changed)
        restored = restored.replace(changed, original, 1)
    assert restored.encode("utf-8") == raw, "Removing timing must restore every original file and method-body byte"
    return text.encode("utf-8"), {"whole_file_and_method_bodies_restore_exactly": True, "replacements": [{"original": a, "instrumented": b} for a, b in pairs], "appended_wrappers": wrappers}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-project", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--engine", type=Path, default=Path("C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    base, target, input_path = args.base_project.resolve(), args.output.resolve(), args.input.resolve()
    target.relative_to(repo / ".cache")
    expected_input = "752924c562f275804cee40cbd2a8760f8f0780cab3276a04330db63a2866e780"
    assert digest(input_path) == expected_input, "Use the unchanged frozen complete160 input"
    inventory_path = base / "source-inventory.json"
    inventory = json.loads(inventory_path.read_text(encoding="utf-8-sig"))
    original = {name: digest(base / name) for name in inventory}
    target.mkdir(parents=True, exist_ok=False)
    for name in inventory:
        destination = (target / name).resolve()
        destination.relative_to(target)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / name, destination)
    for name in [".godot/imported", "game/platform/windows/bin"]:
        shutil.copytree(base / name, target / name, dirs_exist_ok=True)
    for name in [".godot/global_script_class_cache.cfg", ".godot/extension_list.cfg"]:
        shutil.copy2(base / name, target / name)
    snapshot_path = target / "game/persistence/snapshot_store.gd"
    instrumented, snapshot = instrument(snapshot_path.read_bytes())
    snapshot_path.write_bytes(instrumented)
    snapshot.update({"original_sha256": original["game/persistence/snapshot_store.gd"], "instrumented_sha256": digest(snapshot_path)})
    for name in ["snapshot_prepare_trace.gd", "snapshot_prepare_probe.gd", Path(__file__).name]:
        relative = "tools/performance/" + name
        shutil.copy2(Path(__file__).with_name(name), target / relative)
        if relative not in inventory: inventory.append(relative)
    profile = "OddlyGoodHospital SnapshotProbe " + uuid.uuid4().hex
    project = target / "project.godot"
    text = project.read_bytes().decode("utf-8")
    text, count = re.subn(r'config/custom_user_dir_name="[^"]*"', 'config/custom_user_dir_name="' + profile + '"', text)
    assert count == 1
    project.write_bytes(text.encode("utf-8"))
    shutil.copy2(input_path, target / "input.bin")
    engine = args.engine.resolve()
    runs = []
    for repeat in [0, 1, 2, 3]:
        runtime = target / "profiles" / ("import" if repeat == 0 else str(repeat))
        environment = {"APPDATA": str(runtime / "Roaming"), "LOCALAPPDATA": str(runtime / "Local")}
        for directory in environment.values(): Path(directory).mkdir(parents=True)
        arguments = ["--headless", "--path", str(target)] + (["--editor", "--import", "--quit"] if repeat == 0 else ["--script", "res://tools/performance/snapshot_prepare_probe.gd", "--", f"--repeat={repeat}"])
        runs.append({"repeat": repeat, "environment": environment, "arguments": arguments, "output": str(target / f"snapshot-prepare-r{repeat}.json")})
    assert all(digest(base / name) == sha for name, sha in original.items()), "Immutable base changed during freeze"
    source = {name: digest(target / name) for name in inventory}
    identity = {"base_project": str(base), "base_inventory_sha256": digest(inventory_path), "original_source": original, "source": source, "snapshot": snapshot, "input": str(target / "input.bin"), "original_input": str(input_path), "input_sha256": expected_input, "profile": profile, "engine": str(engine), "engine_executables": {str(path): digest(path) for path in [engine, engine.with_name(engine.name.replace("_console", ""))]}, "native": {path.name: digest(path) for path in (target / "game/platform/windows/bin").glob("*.dll")}, "import": runs[0], "runs": runs[1:], "scope": "Reversible diagnostic timing of actual synchronous preparation and background save operations; isolated fresh test library for every repeat, no engine execution during freezing and no production source edits."}
    (target / "snapshot-prepare-identity.json").write_text(json.dumps(identity, ensure_ascii=False, indent=2), encoding="utf-8")
    (target / "source-inventory.json").write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"project": str(target), "source_files": len(source), "body_restoration_exact": True, "input_sha256": expected_input, "engine_runs_started": 0}))


if __name__ == "__main__":
    main()
