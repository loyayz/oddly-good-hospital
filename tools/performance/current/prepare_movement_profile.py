"""Create an isolated same-script movement diagnostic; never edits game sources in the caller."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
import shutil
import subprocess


TIMER = '''extends RefCounted
static var active: bool = false
static var owner_thread: int = 0
static var stack: Array = []
static var rows: Dictionary = {}
static var errors: Array = []
static func start() -> void:
\towner_thread=OS.get_thread_caller_id();stack=[];rows={};errors=[];active=true
static func enter(name: String) -> bool:
\tif not active or OS.get_thread_caller_id()!=owner_thread:return false
\tstack.append({"name":name,"start":Time.get_ticks_usec(),"children":0})
\treturn true
static func leave(name: String) -> void:
\tvar now: int=Time.get_ticks_usec()
\tif stack.is_empty() or stack.back().name!=name:errors.append("stack mismatch "+name);return
\tvar frame: Dictionary=stack.pop_back()
\tvar elapsed: int=now-int(frame.start)
\tvar row: Dictionary=rows.get(name,{"calls":0,"inclusive_us":0,"exclusive_us":0,"max_us":0})
\trow.calls+=1;row.inclusive_us+=elapsed;row.exclusive_us+=elapsed-int(frame.children);row.max_us=maxi(row.max_us,elapsed);rows[name]=row
\tif not stack.is_empty():stack.back().children+=elapsed
static func stop() -> Dictionary:
\tactive=false
\tif not stack.is_empty():errors.append("unclosed calls")
\treturn {"rows":rows,"errors":errors,"scope":"Main driver thread, selected inclusive/exclusive elapsed. Exclusive includes untimed descendants and observer overhead; never sum inclusive rows. Source wrappers preserve exact bodies."}
'''

TARGETS = {
    "game/building/hospital_movement.gd": ["advance", "_dispatch_routes", "_move_step", "_active_route_clear",
        "_local_collision", "_local_choose_options", "_local_side_exit", "_local_resume", "_local_try_return",
        "_local_return_endpoint_clear", "_local_return", "_local_path_clear", "_movement_contacts", "_reserve_doors"],
    "game/building/hospital_space.gd": ["_actor_rect"],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    target = args.output.resolve()
    assert target.is_relative_to(root / ".cache") and not target.exists(), "Use a new diagnostic path beneath .cache"
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    subprocess.run(["git", "-C", str(root), "worktree", "add", "--detach", str(target), commit], check=True)
    (target / ".godot").mkdir(exist_ok=True)
    for name in ["global_script_class_cache.cfg", "extension_list.cfg"]:
        shutil.copy2(root / ".godot" / name, target / ".godot" / name)
    shutil.copytree(root / ".godot/imported", target / ".godot/imported")
    shutil.copytree(root / "game/platform/windows/bin", target / "game/platform/windows/bin")
    split_arguments = runpy.run_path(str(root / "tools/performance/instrument_all_instances.py"))["split_arguments"]
    timer_path = "tools/performance/current/movement_timer.gd"
    (target / timer_path).write_text(TIMER, encoding="utf-8")
    manifest = {"base_commit": commit, "changes": [], "timer_sha256": hashlib.sha256(TIMER.encode()).hexdigest()}
    for path, names in TARGETS.items():
        original = (target / path).read_text(encoding="utf-8")
        source, wrappers, headers = original, [], []
        for name in names:
            matches = list(re.finditer(r"^func " + re.escape(name) + r"\((.*)\)[ \t]*->[ \t]*([^:\n]+):[ \t]*$", source, re.M))
            assert len(matches) == 1, (path, name)
            match = matches[0]
            header, result_type = match[0], match[2].strip()
            arguments = [a.split(":", 1)[0].strip() for a in split_arguments(match[1])]
            renamed = header.replace("func " + name, "func _movement_profile_original_" + name, 1)
            source = source[:match.start()] + renamed + source[match.end():]
            operation = path + ":" + name
            body = header + '\n\tvar traced: bool=_MovementProfile160.enter("' + operation + '")\n'
            call = "_movement_profile_original_" + name + "(" + ",".join(arguments) + ")"
            body += "\t" + ("var value: " + result_type + "=" if result_type != "void" else "") + call + "\n"
            body += '\tif traced:_MovementProfile160.leave("' + operation + '")\n'
            if result_type != "void":
                body += "\treturn value\n"
            wrappers.append(body)
            headers.append((header, renamed))
        # Undo the header renames to prove the original method bodies are untouched.
        undo = source
        for header, renamed in headers:
            undo = undo.replace(renamed, header, 1)
        assert undo == original
        source = source.replace("extends RefCounted\n", 'extends RefCounted\nconst _MovementProfile160=preload("res://' + timer_path + '")\n', 1)
        source += "\n# Generated movement diagnostic wrappers\n" + "\n".join(wrappers)
        (target / path).write_text(source, encoding="utf-8")
        manifest["changes"].append({"path": path, "methods": names,
            "original_sha256": hashlib.sha256(original.encode()).hexdigest(),
            "diagnostic_sha256": hashlib.sha256(source.encode()).hexdigest(), "body_undo_exact": True})
    driver_path = target / "tools/performance/current/plain_v4.gd"
    source = driver_path.read_text(encoding="utf-8")
    source = source.replace("extends SceneTree\n", 'extends SceneTree\nconst _MovementProfile160=preload("res://' + timer_path + '")\n', 1)
    assert source.count("\t\tif index==prefix_steps:\n") == 1
    source = source.replace("\t\tif index==prefix_steps:\n", "\t\tif index==prefix_steps:\n\t\t\t_MovementProfile160.start()\n", 1)
    source = source.replace("\tvar window_end: int = Time.get_ticks_usec()\n", '\tvar window_end: int = Time.get_ticks_usec()\n\tvar movement_calls: Dictionary=_MovementProfile160.stop()\n\twrite_json(output+".calls.json",movement_calls)\n\tif not movement_calls.errors.is_empty():errors.append("Movement diagnostic stack failed")\n', 1)
    driver_path.write_text(source, encoding="utf-8")
    (target / "movement-profile-source.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"project": str(target), "base_commit": commit, "methods": sum(map(len, TARGETS.values()))}))


if __name__ == "__main__":
    main()
