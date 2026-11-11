"""Freeze a project and wrap selected methods for inclusive/exclusive wall spans.

Business method bodies remain byte-identical after removing the wrappers.
The frozen project's normal campaign160.py runs the diagnostic; its wall times
must never be presented as uninstrumented performance.
Exclusive spans subtract only other probed descendants, not all child CPU time.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


METHODS = {
    "game/building/navigation_cache.gd": ["_source_record", "_store_source", "_trim_source_payloads", "floor_geometry", "graph", "cached_static_geometry"],
    "game/building/hospital_space.gd": ["movement_doors", "_reservation_regions", "reservation_view", "_ensure_actor_index", "_dynamic_clear"],
    "game/building/body_index.gd": ["_query", "candidates", "update", "intersects"],
    "game/building/hospital_movement.gd": ["advance", "_move_step", "_unit_sweeps", "_movement_contacts", "_reserve_doors", "_yield", "_dispatch_routes"],
    "game/clinic/clinical_runtime.gd": ["dispatch", "_gather_assigned", "_dispatch_service", "_prepare_surgery", "_surgery_quote", "_compatible_bed", "service_candidates", "_select_plan", "_availability"],
    "game/clinic/hospital_visitors.gd": ["dispatch", "advance", "_bedside_in_query"],
    "game/operations/floor_guidance.gd": ["prepare", "_refresh_destinations", "_target_ids", "_approach_desk"],
}

TIMER = '''extends RefCounted
static var active: bool = false
static var stack: Array = []
static var rows: Dictionary = {}
static var errors: Array = []
static func begin() -> void:
	active=true;stack=[];rows={};errors=[]
static func enter(name: String) -> void:
	if active: stack.append({"name":name,"started":Time.get_ticks_usec(),"children":0})
static func leave(name: String) -> void:
	if not active: return
	var now: int = Time.get_ticks_usec()
	if stack.is_empty() or stack.back().name!=name: errors.append("Unbalanced timer: "+name);return
	var frame: Dictionary = stack.pop_back()
	var elapsed: int = now-int(frame.started)
	var row: Dictionary = rows.get(name,{"calls":0,"inclusive_us":0,"exclusive_us":0,"max_us":0})
	row.calls+=1;row.inclusive_us+=elapsed;row.exclusive_us+=elapsed-int(frame.children);row.max_us=maxi(int(row.max_us),elapsed);rows[name]=row
	if not stack.is_empty(): stack.back().children+=elapsed
static func finish() -> Dictionary:
	active=false
	if not stack.is_empty(): errors.append("Unclosed timer")
	return {"rows":rows,"errors":errors}
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def arguments(signature):
    """Split declarations, retaining defaults that contain arrays/dictionaries."""
    start = depth = 0
    quote = None
    result = []
    for index, char in enumerate(signature):
        if quote:
            if char == quote and (not index or signature[index - 1] != "\\"):
                quote = None
        elif char in "\"'":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            result.append(signature[start:index].strip().split(":")[0])
            start = index + 1
    if signature[start:].strip():
        result.append(signature[start:].strip().split(":")[0])
    return ",".join(result)


def instrument(path, source, names):
    wrappers = []
    text = source
    for name in names:
        matches = list(re.finditer(r"^func " + re.escape(name) + r"\((.*)\) -> ([^\n]+):$", text, re.M))
        assert len(matches) == 1, (path, name, len(matches))
        match = matches[0]
        header, result_type = match[0], match[2]
        renamed = header.replace("func " + name + "(", "func _probe_body_" + name + "(", 1)
        text = text[:match.start()] + renamed + text[match.end():]
        key = path + ":" + name
        call = "_probe_body_" + name + "(" + arguments(match[1]) + ")"
        wrapper = header + '\n\t_PerformanceProbe.enter("' + key + '")\n\t'
        wrapper += ("var value: " + result_type + " = " if result_type != "void" else "") + call
        wrapper += '\n\t_PerformanceProbe.leave("' + key + '")\n'
        if result_type != "void":
            wrapper += "\treturn value\n"
        wrappers.append((header, renamed, wrapper))
    prefix = 'const _PerformanceProbe = preload("res://tools/performance/current/function_timer.gd")\n'
    assert "extends RefCounted\n" in text
    text = text.replace("extends RefCounted\n", "extends RefCounted\n" + prefix, 1)
    text += "".join("\n" + wrapper for _, _, wrapper in wrappers)
    restored = text.replace(prefix, "", 1)
    for header, renamed, wrapper in wrappers:
        restored = restored.replace("\n" + wrapper, "", 1).replace(renamed, header, 1)
    assert restored == source, (path, "Business method restoration failed")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    target = args.output.resolve()
    target.mkdir(parents=True, exist_ok=False)
    paths = subprocess.check_output(["git", "-C", str(root), "-c", "core.quotePath=false", "ls-files", "--cached", "--others", "--exclude-standard"], text=True, encoding="utf-8").splitlines()
    assert paths
    identity = {}
    for relative in sorted(set(paths)):
        source = root / relative
        if not source.is_file():
            continue
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        identity[relative] = digest(destination.read_bytes())
    for relative in [".godot/imported", "game/platform/windows/bin"]:
        shutil.copytree(root / relative, target / relative, dirs_exist_ok=True)
    # Global class lookup is editor-generated and has no hospital/runtime state.
    shutil.copy2(root / ".godot/global_script_class_cache.cfg", target / ".godot/global_script_class_cache.cfg")
    shutil.copy2(root / ".godot/extension_list.cfg", target / ".godot/extension_list.cfg")
    changes = {}
    for relative, names in METHODS.items():
        path = target / relative
        source = path.read_bytes().decode("utf-8")
        assert "\r\n" not in source, (relative, "Method restoration requires the repository's LF source")
        updated = instrument(relative, source, names)
        write(path, updated)
        changes[relative] = {"methods": names, "original_sha256": identity[relative], "instrumented_sha256": digest(path.read_bytes()), "method_body_restoration_exact": True}
    timer = "tools/performance/current/function_timer.gd"
    write(target / timer, TIMER)
    driver = target / "tools/performance/current/plain_v4.gd"
    text = driver.read_text(encoding="utf-8").replace("\r\n", "\n")
    text = text.replace("var output: String", 'const FunctionTimer = preload("res://' + timer + '")\nvar output: String', 1)
    text = text.replace("\tvar samples: Array = []", "\tvar function_steps: Array = []\n\tvar samples: Array = []", 1)
    text = text.replace("\t\tvar started: int = Time.get_ticks_usec()", "\t\tif index>=prefix_steps: FunctionTimer.begin()\n\t\tvar started: int = Time.get_ticks_usec()", 1)
    text = text.replace("\t\tvar elapsed: int = Time.get_ticks_usec()-started", "\t\tvar elapsed: int = Time.get_ticks_usec()-started\n\t\tif index>=prefix_steps:\n\t\t\tvar fine: Dictionary = FunctionTimer.finish()\n\t\t\tfunction_steps.append(fine)\n\t\t\tif not fine.errors.is_empty(): errors.append(\"Invalid function timer\");break", 1)
    text = text.replace("\tvar final: Dictionary = snapshot(world)", '\twrite_json(output+".calls.json",{"steps":function_steps,"diagnostic_only":true})\n\tvar final: Dictionary = snapshot(world)', 1)
    write(driver, text)
    inventory = sorted(set(identity) | {timer})
    write(target / "source-inventory.json", json.dumps(inventory, ensure_ascii=False, indent=2))
    assert all(digest((root / path).read_bytes()) == value for path, value in identity.items()), "Source changed while freezing the diagnostic"
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    write(target / "function-probe-identity.json", json.dumps({"original_commit": head, "source": identity, "changes": changes, "driver_sha256": digest(driver.read_bytes()), "scope": "Method wrappers only. Instrumented wall times include observer overhead; compare plain performance separately."}, ensure_ascii=False, indent=2))
    print(json.dumps({"project": str(target), "source_files": len(identity), "methods": sum(map(len, METHODS.values()))}))


if __name__ == "__main__":
    main()
