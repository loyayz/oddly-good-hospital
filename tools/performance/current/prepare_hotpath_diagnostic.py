"""Prepare main-thread function diagnostics from a measured frozen project.

Preparation never runs Godot. Complete original source bytes are recoverable by
removing the recorded wrappers and spans. Diagnostic elapsed times include
instrumentation, waits and untimed descendants; they are not plain performance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import time

from function_probe import arguments


METHODS = {
    "game/building/hospital_movement.gd": [
        "advance", "_dispatch_routes", "_active_route_clear", "_move_step",
        "_movement_contacts", "_reserve_doors", "_local_collision", "_local_resume",
        "_local_try_return", "_local_return", "_local_path_clear",
        "_local_return_around_nearby", "_bed_goal_blocker",
    ],
    "game/building/hospital_space.gd": [
        "_ensure_actor_index", "_dynamic_clear", "reservation_view", "_sync_actor",
    ],
    "game/building/navigation_cache.gd": [
        "_source_record", "floor_geometry", "graph", "clearance", "_travel_distance",
    ],
    "game/operations/patient_experience.gd": ["sample"],
    "game/operations/environment_sample_batch.gd": [
        "prepare", "_prepare_empty_samples", "begin_apply", "consume", "end_apply",
    ],
    "game/operations/environment_service.gd": [
        "_prepare_facility_sources", "_prepare_sample_sources",
        "_prepare_observation_bounds", "_water_usable",
    ],
}
TIMER_PATH = "tools/performance/current/hotpath_diagnostic_timer.gd"
DRIVER = "tools/performance/current/plain_v4.gd"
BATCH = "game/operations/environment_sample_batch.gd"
PREFIX = 'const _HotpathTimer = preload("res://' + TIMER_PATH + '")\n'
SCOPE = (
    "Main-driver-thread selected inclusive/exclusive elapsed. Exclusive removes "
    "only selected nested spans; it still contains untimed work, waits and hook "
    "overhead and is not CPU time. Outermost probed-method labels and parent "
    "edges distinguish movement descendants from other callers. Workers never "
    "write this timer. No worker_diagnostics or production rule is changed."
)

TIMER = '''extends RefCounted
static var active: bool = false
static var owner_thread: int = 0
static var stack: Array = []
static var rows: Dictionary = {}
static var edges: Dictionary = {}
static var errors: Array = []
static var steps: Array = []
static var current_index: int = -1
static var tick_before: int = -1

static func begin_step(index: int, tick: int) -> void:
	owner_thread=OS.get_thread_caller_id()
	stack=[];rows={};edges={};errors=[]
	current_index=index;tick_before=tick;active=true
	if owner_thread!=OS.get_main_thread_id(): errors.append("Driver is not the main thread")

static func enter(name: String) -> bool:
	# No shared timer mutation on a worker, including counters or error arrays.
	if not active or OS.get_thread_caller_id()!=owner_thread: return false
	var root: String=name if stack.is_empty() else str(stack.front().root)
	var parent: String="" if stack.is_empty() else str(stack.back().name)
	stack.append({"name":name,"root":root,"parent":parent,"started":Time.get_ticks_usec(),"children":0})
	return true

static func leave(name: String) -> void:
	if not active or OS.get_thread_caller_id()!=owner_thread: return
	var now: int=Time.get_ticks_usec()
	if stack.is_empty() or stack.back().name!=name:
		errors.append("Unbalanced main-thread timer: "+name)
		return
	var frame: Dictionary=stack.pop_back()
	var elapsed: int=now-int(frame.started)
	var exclusive: int=elapsed-int(frame.children)
	if exclusive<0: errors.append("Negative selected exclusive span: "+name)
	var key: String=str(frame.root)+"\\n"+name
	var row: Dictionary=rows.get(key,{"name":name,"root":frame.root,"calls":0,"inclusive_us":0,"exclusive_us":0,"max_us":0})
	row.calls+=1;row.inclusive_us+=elapsed;row.exclusive_us+=exclusive
	row.max_us=maxi(int(row.max_us),elapsed);rows[key]=row
	var edge_key: String=str(frame.root)+"\\n"+str(frame.parent)+"\\n"+name
	var edge: Dictionary=edges.get(edge_key,{"root":frame.root,"parent":frame.parent,"child":name,"calls":0,"inclusive_us":0})
	edge.calls+=1;edge.inclusive_us+=elapsed;edges[edge_key]=edge
	if not stack.is_empty(): stack.back().children+=elapsed

static func end_step(tick: int, outer_elapsed_us: int) -> void:
	active=false
	if not stack.is_empty(): errors.append("Unclosed main-thread timer")
	steps.append({"index":current_index,"tick_before":tick_before,"tick":tick,"main_thread_id":owner_thread,"outer_step_elapsed_us":outer_elapsed_us,"rows":rows.values(),"edges":edges.values(),"errors":errors})

static func report() -> Dictionary:
	return {"diagnostic_only":true,"main_thread_only":true,"steps":steps,"scope":"Main-thread selected elapsed. Exclusive subtracts only selected children and includes untimed work/waits/hook overhead. Root is the outermost probed method, not an unobserved caller. Never sum nested inclusive rows or treat diagnostic spans as CPU or speedup."}

static func count_difference(after: Dictionary, before: Dictionary) -> Dictionary:
	var keys: Dictionary={}
	for key: String in before: keys[key]=true
	for key: String in after: keys[key]=true
	var result: Dictionary={}
	for key: String in keys:
		# This field is a peak, not an accumulated event count.
		if key!="native_field_threads": result[key]=int(after.get(key,0))-int(before.get(key,0))
	return result
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    return digest(path.read_bytes())


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def inverse(text, replacements):
    for row in reversed(replacements):
        before, after = row["original"], row["instrumented"]
        if before:
            assert text.count(after) == 1, "Ambiguous reverse replacement"
            text = text.replace(after, before, 1)
        else:
            assert text.endswith(after), "Generated wrapper suffix changed"
            text = text[:-len(after)]
    return text


class Patch:
    def __init__(self, relative, data):
        self.relative, self.original = relative, data
        self.text = data.decode("utf-8")
        assert "\r" not in self.text, (relative, "Expected the frozen LF source")
        assert "_HotpathTimer" not in self.text, (relative, "Already instrumented")
        self.replacements = []

    def replace(self, before, after):
        assert before and self.text.count(before) == 1, (self.relative, before)
        self.text = self.text.replace(before, after, 1)
        self.replacements.append({"original": before, "instrumented": after})

    def append(self, suffix):
        self.text += suffix
        self.replacements.append({"original": "", "instrumented": suffix})

    def add_timer(self):
        matches = list(re.finditer(r"^extends RefCounted\n", self.text, re.M))
        assert len(matches) == 1, self.relative
        header = self.text[:matches[0].end()]
        self.replace(header, header + PREFIX)

    def wrap(self, name):
        pattern = r"^func " + re.escape(name) + r"\((.*)\)[ \t]*->[ \t]*([^:\n]+):[ \t]*$"
        matches = list(re.finditer(pattern, self.text, re.M))
        assert len(matches) == 1, (self.relative, name, len(matches))
        match = matches[0]
        header, result_type = match[0], match[2].strip()
        original_name = "_hotpath_original_" + name
        renamed = header.replace("func " + name + "(", "func " + original_name + "(", 1)
        self.replace(header, renamed)
        label = self.relative + ":" + name
        wrapper = header + '\n\tvar _hotpath_traced: bool=_HotpathTimer.enter("' + label + '")\n'
        call = original_name + "(" + arguments(match[1]) + ")"
        wrapper += "\t" + ("var _hotpath_value: " + result_type + "=" if result_type != "void" else "") + call + "\n"
        wrapper += '\tif _hotpath_traced: _HotpathTimer.leave("' + label + '")\n'
        if result_type != "void":
            wrapper += "\treturn _hotpath_value\n"
        self.append("\n# Generated main-thread diagnostic wrapper: " + name + "\n" + wrapper)

    def span(self, name, start, end):
        label = self.relative + ":" + name
        indent = start[:len(start) - len(start.lstrip("\t"))]
        token = "_hotpath_" + name.replace(".", "_")
        self.replace("\n" + start, "\n" + indent + 'var ' + token + ': bool=_HotpathTimer.enter("' + label + '")\n' + start)
        indent = end[:len(end) - len(end.lstrip("\t"))]
        self.replace("\n" + end, "\n" + end + indent + 'if ' + token + ': _HotpathTimer.leave("' + label + '")\n')

    def checked(self, names):
        assert inverse(self.text, self.replacements).encode("utf-8") == self.original, self.relative
        return {
            "methods": names, "original_sha256": digest(self.original),
            "instrumented_sha256": digest(self.text.encode("utf-8")),
            "whole_file_and_method_bodies_restore_exactly": True,
            "replacements": self.replacements,
        }


def batch_spans(patch):
    patch.span("prepare.seed", "\t# Copy the historical mappings once. Workers share this immutable seed and\n\t# write only their own overlays; completed coverage values stay borrowed.\n\tvar coverage_seed: Dictionary = {}\n", "\tcoverage_seed.make_read_only()\n")
    patch.span("prepare.pool_dispatch", '\t\tgroup = WorkerThreadPool.add_group_task(_run_job,count,count,false,"Department environment observations")\n', '\t\tgroup = WorkerThreadPool.add_group_task(_run_job,count,count,false,"Department environment observations")\n')
    patch.span("prepare.pool_wait", "\t\tWorkerThreadPool.wait_for_group_task_completion(group)\n", "\t\tWorkerThreadPool.wait_for_group_task_completion(group)\n")
    patch.span("prepare.harvest", "\tvar valid: bool = true\n", '\t_mark("harvest_us",stamp)\n')


def driver_patch(data):
    patch = Patch(DRIVER, data)
    patch.replace("extends SceneTree\n", "extends SceneTree\n" + PREFIX)
    window_guard = "\tif input.is_empty() or output.is_empty() or steps<=0 or prefix_steps<0 or FileAccess.file_exists(output): quit(2);return\n"
    patch.replace(window_guard, window_guard + "\tif not (prefix_steps==1000 and steps==6000 or prefix_steps==0 and steps==2): quit(2);return\n")
    patch.replace("\tvar initial: Dictionary = snapshot(world)\n", "\tvar initial: Dictionary = snapshot(world)\n\tvar hotpath_initial_counts: Dictionary=sim.space.query_counts.duplicate()\n\tvar hotpath_sample_counts: Dictionary={}\n")
    patch.replace("\t\tif index==prefix_steps:\n", "\t\tif index==prefix_steps:\n\t\t\thotpath_sample_counts=sim.space.query_counts.duplicate()\n")
    patch.replace("\t\tvar started: int = Time.get_ticks_usec()\n", "\t\tif index>=prefix_steps: _HotpathTimer.begin_step(index,world.sim_tick)\n\t\tvar started: int = Time.get_ticks_usec()\n")
    patch.replace("\t\tvar elapsed: int = Time.get_ticks_usec()-started\n", "\t\tvar elapsed: int = Time.get_ticks_usec()-started\n\t\tif index>=prefix_steps: _HotpathTimer.end_step(world.sim_tick,elapsed)\n")
    patch.replace("\tvar window_end: int = Time.get_ticks_usec()\n", '\tvar window_end: int = Time.get_ticks_usec()\n\twrite_json(output+".hotpath.json",_HotpathTimer.report())\n\tvar hotpath_final_counts: Dictionary=sim.space.query_counts.duplicate()\n\twrite_json(output+".query-counts.json",{"diagnostic_only":true,"after_initialization":hotpath_initial_counts,"at_sample_start":hotpath_sample_counts,"after_window":hotpath_final_counts,"prefix_counts":_HotpathTimer.count_difference(hotpath_sample_counts,hotpath_initial_counts),"sample_counts":_HotpathTimer.count_difference(hotpath_final_counts,hotpath_sample_counts),"window_counts":_HotpathTimer.count_difference(hotpath_final_counts,hotpath_initial_counts),"gauge_keys":["native_field_threads"],"scope":"Existing production query counters; window deltas exclude initialization. native_field_threads is a cumulative peak retained only in raw snapshots. Counts do not establish elapsed cost, graph misses or work omitted by existing counters."})\n')
    return patch


def prepare(args):
    started = time.perf_counter()
    base, target = args.base_project.resolve(), args.output.resolve()
    input_path, reference = args.input.resolve(), args.reference.resolve()
    root = Path(__file__).resolve().parents[3]
    assert target.is_relative_to(root / ".cache") and not target.exists(), "Use a new .cache project path"
    protocol, result = read(reference / "protocol.json"), read(reference / "r1.json")
    assert result["all_completed_steps"] == 7000 and result["metrics"]["count"] == 6000
    assert result["requested_prefix_steps"] == 1000 and result["requested_sample_steps"] == 6000
    assert file_digest(input_path) == result["source_input_sha256"]
    assert file_digest(reference / "r1.json.final.bin") == result["final_sha256"]
    inventory = read(base / "source-inventory.json")
    assert inventory and len(inventory) == len(set(inventory))
    original = {}
    for relative in inventory:
        source = (base / relative).resolve()
        assert source.is_relative_to(base) and source.is_file(), relative
        original[relative] = file_digest(source)
    assert {name: value for name, value in original.items() if not name.endswith(".gd.uid")} == read(reference / "source-identity.json"), "Base differs from the measured A source"
    assert all(file_digest(Path(name)) == value for name, value in protocol["engine_executables"].items())
    native = {path.name: file_digest(path) for path in (base / "game/platform/windows/bin").glob("*.dll")}
    assert native == protocol["native"]
    methods = read(args.methods) if args.methods else METHODS
    assert methods and all(isinstance(names, list) and names and len(names) == len(set(names)) for names in methods.values())
    assert "advance" in methods.get("game/building/hospital_movement.gd", []) and "sample" in methods.get("game/operations/patient_experience.gd", []), "Retain the movement and experience outer-call anchors"
    patches, changes = {}, {}
    for relative, names in methods.items():
        assert relative in original and all(isinstance(name, str) for name in names), relative
        patch = Patch(relative, (base / relative).read_bytes())
        patch.add_timer()
        if relative == BATCH:
            batch_spans(patch)
        for name in names:
            patch.wrap(name)
        patches[relative] = patch
        changes[relative] = patch.checked(names)
    assert DRIVER not in patches
    patches[DRIVER] = driver_patch((base / DRIVER).read_bytes())
    changes[DRIVER] = patches[DRIVER].checked([])
    method_count = sum(map(len, methods.values()))
    if args.check_only:
        print(json.dumps({"checked_only": True, "base_source_files": len(original), "methods": method_count, "original_bytes_restore_exactly": True, "engine_started": False}))
        return
    target.mkdir(parents=True, exist_ok=False)
    for relative in inventory:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base / relative, destination)
    for relative in [".godot/imported", "game/platform/windows/bin"]:
        shutil.copytree(base / relative, target / relative, dirs_exist_ok=True)
    for relative in [".godot/global_script_class_cache.cfg", ".godot/extension_list.cfg"]:
        shutil.copy2(base / relative, target / relative)
    for relative, patch in patches.items():
        (target / relative).write_bytes(patch.text.encode("utf-8"))
    helpers = {TIMER_PATH: TIMER.encode("utf-8"), "tools/performance/current/" + Path(__file__).name: Path(__file__).read_bytes()}
    for relative, data in helpers.items():
        assert relative not in original
        (target / relative).write_bytes(data)
        inventory.append(relative)
    write(target / "source-inventory.json", inventory)
    source = {relative: file_digest(target / relative) for relative in inventory}
    for relative, expected in original.items():
        actual = inverse((target / relative).read_text(encoding="utf-8"), changes[relative]["replacements"]).encode("utf-8") if relative in changes else (target / relative).read_bytes()
        assert digest(actual) == expected and actual == (base / relative).read_bytes(), relative
    assert all(file_digest(base / relative) == expected for relative, expected in original.items()), "Base changed during the freeze"
    identity = {
        "base_project": str(base), "original_source": original, "source": source,
        "changes": changes, "methods": methods, "method_count": method_count,
        "main_thread_only": True, "source_files": len(source),
        "canonical_source_map_fingerprint": {"sha256": digest(json.dumps(source, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")), "algorithm": "SHA256(UTF8(json.dumps(path_to_sha256_map,sort_keys=True,separators=(',',':'),ensure_ascii=True))) without trailing newline"},
        "raw_source_inventory_json_file_sha256": file_digest(target / "source-inventory.json"),
        "all_original_file_bytes_restore_exactly": True,
        "input": str(input_path), "input_sha256": file_digest(input_path),
        "reference": str(reference), "expected_final_bin_sha256": result["final_sha256"],
        "prefix_steps": 1000, "sample_steps": 6000,
        "root_stage_flag": "--profile-stages",
        "engine_executables": protocol["engine_executables"], "native": native,
        "main_thread_policy": protocol["main_thread_policy"], "worker_tasks": protocol["worker_tasks"],
        "scope": SCOPE, "freeze_seconds": time.perf_counter() - started,
    }
    write(target / "hotpath-diagnostic-identity.json", identity)
    print(json.dumps({"project": str(target), "base_source_files": len(original), "source_files": len(source), "methods": method_count, "original_bytes_restore_exactly": True, "freeze_seconds": identity["freeze_seconds"], "engine_started": False}))


def verify(args):
    project, output, reference = args.project.resolve(), args.diagnostic_output.resolve(), args.reference.resolve()
    report = output / "hotpath-equivalence.json"
    assert not report.exists(), "Preserve existing verification evidence"
    identity = read(project / "hotpath-diagnostic-identity.json")
    actual, expected = read(output / "r1.json"), read(reference / "r1.json")
    protocol = read(output / "protocol.json")
    measured_source = read(output / "source-identity.json")
    calls, counts = read(output / "r1.json.hotpath.json"), read(output / "r1.json.query-counts.json")
    execution = read(output / "r1.json.execution.json")
    stages = read(output / "r1.json.stages.json")
    prefix, samples = (0, 2) if args.smoke else (1000, 6000)
    rows = calls["steps"]
    required_roots = {"game/building/hospital_movement.gd:advance", "game/operations/patient_experience.gd:sample"}
    counters = lambda after, before: {key: int(after.get(key, 0)) - int(before.get(key, 0)) for key in set(after) | set(before) if key != "native_field_threads"}
    source_unchanged = all(file_digest(project / name) == expected_sha for name, expected_sha in identity["source"].items())
    body_restored = all(digest(inverse((project / name).read_text(encoding="utf-8"), change["replacements"]).encode("utf-8")) == change["original_sha256"] for name, change in identity["changes"].items())
    final_sha = file_digest(output / "r1.json.final.bin")
    checks = {
        "source_unchanged": source_unchanged,
        "measured_source_matches_frozen_inventory": measured_source == {name: value for name, value in identity["source"].items() if not name.endswith(".gd.uid")} and protocol["source_inventory_sha256"] == file_digest(project / "source-inventory.json") == identity["raw_source_inventory_json_file_sha256"],
        "all_wrapped_source_bytes_restore_exactly": body_restored,
        "input_unchanged": file_digest(Path(identity["input"])) == actual["source_input_sha256"] == expected["source_input_sha256"] == identity["input_sha256"],
        "complete_requested_window": actual["all_completed_steps"] == prefix + samples and actual["metrics"]["count"] == samples and actual["requested_prefix_steps"] == expected["requested_prefix_steps"] == prefix and actual["requested_sample_steps"] == expected["requested_sample_steps"] == samples,
        "complete_world_and_ordered_events_identical": final_sha == actual["final_sha256"] == expected["final_sha256"] and (args.smoke or final_sha == identity["expected_final_bin_sha256"]),
        "main_thread_function_records_complete": calls["main_thread_only"] and len(rows) == samples and [row["index"] for row in rows] == list(range(prefix, prefix + samples)) and all(not row["errors"] and row["tick"] == row["tick_before"] + 1 and row["main_thread_id"] > 0 for row in rows),
        "movement_and_experience_roots_observed": all(required_roots <= {row["name"] for row in step["rows"] if row["root"] == row["name"]} for step in rows),
        "main_thread_owner_matches_execution": all(step["main_thread_id"] == execution["main_thread_policy"]["caller_thread_id"] for step in rows),
        "selected_exclusive_intervals_valid": all(0 <= row["exclusive_us"] <= row["inclusive_us"] and row["calls"] > 0 and 0 <= row["max_us"] <= row["inclusive_us"] for step in rows for row in step["rows"]),
        "selected_root_partition_exact": all(sum(row["exclusive_us"] for row in step["rows"]) == sum(edge["inclusive_us"] for edge in step["edges"] if not edge["parent"]) <= step["outer_step_elapsed_us"] for step in rows),
        "query_count_sample_and_prefix_deltas_exact": counts["sample_counts"] == counters(counts["after_window"], counts["at_sample_start"]) and counts["prefix_counts"] == counters(counts["at_sample_start"], counts["after_initialization"]) and counts["window_counts"] == counters(counts["after_window"], counts["after_initialization"]),
        "engine_unchanged": all(file_digest(Path(name)) == value for name, value in identity["engine_executables"].items()),
        "measured_engine_and_native_match_frozen_identity": protocol["engine_executables"] == identity["engine_executables"] and protocol["native"] == identity["native"] and protocol["input_sha256"] == identity["input_sha256"],
        "native_unchanged": {path.name: file_digest(path) for path in (project / "game/platform/windows/bin").glob("*.dll")} == identity["native"],
        "worker_policy_and_diagnostics_unchanged": execution["worker_tasks"] == identity["worker_tasks"] and execution["main_thread_policy"]["requested"] == identity["main_thread_policy"] and (identity["main_thread_policy"] != "app" or execution["main_thread_policy"]["applied"]) and not execution["worker_samples"]["diagnostics_enabled"],
        "root_stages_complete": protocol["profile_stages"] and stages["step_records_complete"] and stages["complete_steps"] == samples and not stages["errors"] and stages["partition_check_us"] == 0,
        "business_coverage_gate_retained": args.smoke or protocol["require_coverage"],
    }
    value = {"passed": all(checks.values()), "checks": checks, "final_bin_sha256": final_sha, "reference": str(reference), "smoke_only": args.smoke, "scope": SCOPE + " Business-coverage errors remain separate; exact diagnostic equality does not establish coverage or performance compliance."}
    write(report, value)
    print(json.dumps({"passed": value["passed"], "checks": checks, "report": str(report)}))
    assert value["passed"], checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    build = modes.add_parser("prepare")
    for name in ["base-project", "output", "input", "reference"]:
        build.add_argument("--" + name, type=Path, required=True)
    build.add_argument("--methods", type=Path, help="Optional path-to-methods JSON; default covers movement, space, navigation and experience on the frozen A")
    build.add_argument("--check-only", action="store_true", help="Check immutable inputs, signatures and complete reverse transformations without writing a project")
    check = modes.add_parser("verify")
    for name in ["project", "diagnostic-output", "reference"]:
        check.add_argument("--" + name, type=Path, required=True)
    check.add_argument("--smoke", action="store_true", help="Verify only the fixed two-step smoke against its two-step reference")
    args = parser.parse_args()
    prepare(args) if args.mode == "prepare" else verify(args)


if __name__ == "__main__":
    main()
