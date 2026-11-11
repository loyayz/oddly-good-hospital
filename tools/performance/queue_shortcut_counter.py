"""Add work counters to a dedicated frozen project containing the old shortcut.

This prepares source only. Run that project's normal campaign separately after
preparation. Counters change private diagnostics, never hospital facts. Their
instrumented timings are not plain performance measurements.
"""
import argparse
import hashlib
import json
from pathlib import Path


TAG = " # queue-shortcut-counter"
PREFIX = "guidance_shortcut_"
ROUTES = "game/operations/guidance_queue_routes.gd"
DRIVER = "tools/performance/current/plain_v4.gd"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def add_routes_counters(source):
    assert "_shortcut_work_count" not in source
    lines = []
    observed = {}

    def insert(line, marker):
        lines.append(line + TAG + "\n")
        observed[marker] = observed.get(marker, 0) + 1

    for line in source.splitlines(keepends=True):
        if line.startswith("  for row: Dictionary in provider._queue_members("):
            insert('  _shortcut_work_count(space,"queues_read")', "queues")
        if line.startswith("  var slots: Array=provider._queue_slots("):
            insert('  _shortcut_work_count(space,"slots_requested")', "slots")
        if line == ' var fixed: RouteClearance=space.navigation.structural_clearance(world,actor,source_floor)\n':
            insert(' _shortcut_work_count(space,"cross_floor_clearance")', "clearance")
        if line.startswith('  return {"ok":true,"path":path}') or line == "  return result\n":
            insert('  _shortcut_work_count(space,"nonempty_returns")', "success")
        lines.append(line)
        if line.startswith("static func quote("):
            insert(' _shortcut_work_count(space,"quotes")', "quotes")
        if line.startswith("static func _cross_floor_exit("):
            insert(' _shortcut_work_count(space,"cross_floor_quotes")', "cross")
        if line == ' for desk_id: String in world.facility_ids("SE01"):\n':
            insert('  _shortcut_work_count(space,"desks_visited")', "desks")
        if line.startswith("  for row: Dictionary in provider._queue_members("):
            insert('   _shortcut_work_count(space,"members_visited")', "members")
        if line.startswith("  var slots: Array=provider._queue_slots("):
            insert('  if slots.is_empty(): _shortcut_work_count(space,"empty_slots")', "empty")
    assert observed == {"quotes": 1, "desks": 2, "queues": 2, "members": 2,
                        "slots": 2, "empty": 2, "success": 2, "cross": 1,
                        "clearance": 1}, observed
    insert("static func _shortcut_work_count(space: HospitalSpace, name: String) -> void:", "helper")
    insert(' space.query_counts["' + PREFIX + '"+name]=int(space.query_counts.get("' + PREFIX + '"+name,0))+1', "helper")
    result = "".join(lines)
    assert "".join(line for line in result.splitlines(keepends=True)
                   if not line.rstrip("\r\n").endswith(TAG)) == source
    return result


def add_driver_output(source):
    assert "_shortcut_count_difference" not in source
    edits = [
        ("\tvar sample_wall_start: int = 0\n",
         "\tvar shortcut_start_counts: Dictionary = {}\n"),
        ("\t\tif index==prefix_steps:\n",
         "\t\t\tshortcut_start_counts=sim.space.query_counts.duplicate()\n"),
        ("\tvar final: Dictionary = snapshot(world)\n",
         '\twrite_json(output+".shortcut-counts.json",{"diagnostic_only":true,"sample_counts":_shortcut_count_difference(sim.space.query_counts,shortcut_start_counts),"total_counts":_shortcut_count_difference(sim.space.query_counts,{}),"scope":"Work counts only; counter overhead is included in this diagnostic run. No plain timing or speed claim."})\n'),
    ]
    result = source
    for anchor, addition in edits:
        assert result.count(anchor) == 1, anchor
        result = result.replace(anchor, anchor + addition, 1)
    helper = ('\nfunc _shortcut_count_difference(after: Dictionary, before: Dictionary) -> Dictionary:\n'
              '\tvar result: Dictionary={}\n\tfor key: String in after:\n'
              '\t\tif key.begins_with("' + PREFIX + '"): result[key]=int(after[key])-int(before.get(key,0))\n'
              '\treturn result\n')
    result += helper
    restored = result.removesuffix(helper)
    for anchor, addition in reversed(edits):
        restored = restored.replace(anchor + addition, anchor, 1)
    assert restored == source
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--baseline-snapshot", type=Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    assert project != Path(__file__).resolve().parents[2], "Use a dedicated frozen project"
    baseline = json.loads((args.baseline_snapshot / "source-identity.json").read_text(encoding="utf-8"))
    for relative, identity in baseline["source"].items():
        assert sha((project / relative).read_bytes()) == identity["sha256"], relative
    originals = {relative: (project / relative).read_bytes() for relative in [ROUTES, DRIVER]}
    updated = {ROUTES: add_routes_counters(originals[ROUTES].decode("utf-8")),
               DRIVER: add_driver_output(originals[DRIVER].decode("utf-8"))}
    assert not (project / "queue-shortcut-counter-identity.json").exists()
    for relative, source in updated.items():
        (project / relative).write_bytes(source.encode("utf-8"))
    identity = {"baseline_commit": baseline["commit"], "source": {
        relative: {"before_sha256": sha(originals[relative]),
                   "after_sha256": sha(source.encode("utf-8")),
                   "business_statement_restoration_exact": True}
        for relative, source in updated.items()},
        "scope": "Counts only; no engine or tests are launched by this preparer."}
    (project / "queue-shortcut-counter-identity.json").write_text(
        json.dumps(identity, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"project": str(project), "prepared": True}))


if __name__ == "__main__":
    main()
