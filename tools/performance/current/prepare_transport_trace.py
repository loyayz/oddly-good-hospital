"""Add reversible transport diagnostics to an already frozen diagnostic copy.

This does not run Godot. Apply after the clinical and queue overlays. Every
reverse replacement restores the complete input file bytes, including earlier
overlays. Timing with these hooks is diagnostic, never performance evidence.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


HELPER = "tools/performance/current/transport_diagnostic_trace.gd"
PREFIX = 'const _TransportDiagnostic = preload("res://' + HELPER + '")\n'


def sha(value):
    return hashlib.sha256(value).hexdigest()


class Patch:
    def __init__(self, path):
        self.path = path
        self.original = path.read_bytes()
        self.text = self.original.decode("utf-8")
        assert "\r" not in self.text, (path, "Expected frozen LF source")
        assert "_TransportDiagnostic" not in self.text, (path, "Overlay already present")
        self.pairs = []

    def replace(self, old, new):
        assert self.text.count(old) == 1, (self.path, old, self.text.count(old))
        self.text = self.text.replace(old, new, 1)
        self.pairs.append((old, new))

    def wrap(self, name, arguments, before, after, result_type="void"):
        pattern = r"^(?:static )?func " + re.escape(name) + r"\([^\n]*\) -> " + re.escape(result_type) + r":$"
        headers = re.findall(pattern, self.text, re.M)
        assert len(headers) == 1, (self.path, name, headers)
        header = headers[0]
        original_name = "_transport_trace_original_" + name
        renamed = header.replace("func " + name + "(", "func " + original_name + "(", 1)
        self.replace(header, renamed)
        call = original_name + "(" + arguments + ")"
        body = header + "\n" + before
        body += "\t" + ("var _trace_value: " + result_type + " = " if result_type != "void" else "") + call + "\n"
        body += after
        if result_type != "void":
            body += "\treturn _trace_value\n"
        # The appended block is itself a reversible replacement of a unique EOF.
        suffix = "\n# Generated transport diagnostic wrapper: " + name + "\n" + body
        self.text += suffix
        self.pairs.append(("", suffix))

    def checked(self):
        restored = self.text
        for old, new in reversed(self.pairs):
            if not old:
                assert restored.endswith(new), (self.path, "Wrapper no longer at EOF")
                restored = restored[:-len(new)]
            else:
                assert restored.count(new) == 1, (self.path, "Ambiguous inverse", new)
                restored = restored.replace(new, old, 1)
        assert restored.encode("utf-8") == self.original, (self.path, "Removing hooks changed source bytes")
        return {
            "original_sha256": sha(self.original),
            "instrumented_sha256": sha(self.text.encode("utf-8")),
            "whole_file_restoration_exact": True,
            "replacements": [{"original": old, "instrumented": new} for old, new in self.pairs],
        }


def transit_patch(path):
    patch = Patch(path)
    patch.replace("extends RefCounted\n", "extends RefCounted\n" + PREFIX)
    # Branch hooks refer to the original line/function, not an inferred phase.
    functions = list(re.finditer(r"^static func (\w+)\([^\n]*\)[^\n]*:\n[\s\S]*?(?=^static func |\Z)", patch.text, re.M))
    for match in functions:
        function, body = match[1], match[0]
        rebuilt = []
        for number, line in enumerate(body.splitlines(keepends=True), 1):
            location = function + ":function_line_" + str(number)
            indent = line[:len(line) - len(line.lstrip("\t"))]
            before, after = "", ""
            if re.fullmatch(r'\t+connection\.phase\s*=\s*"\w+"\n', line):
                after = indent + '_TransportDiagnostic.phase_entered(world,connection,"' + location + '")\n'
            elif re.fullmatch(r"\t+movement\.transit_ticket\s*=.*\n", line):
                after = indent + '_TransportDiagnostic.ticket_created(world,movement,"' + location + '")\n'
            elif re.fullmatch(r"\t+cancel_waiting\(world,movement\)\n", line):
                # The common wrapper covers callers outside Transit too.
                before = indent + '_TransportDiagnostic.cancel_site(world,movement,"' + location + '")\n'
            elif line.strip() == 'movement.erase("transit_ticket")' and function in ["begin", "_begin_convoy"]:
                before = indent + '_TransportDiagnostic.ticket_consumed(world,movement,"' + location + '")\n'
            elif line.strip().startswith("space.queue_waypoint(") and function in ["_stand_aside", "_stand_aside_convoy"]:
                before = indent + '_TransportDiagnostic.before_aside_commit(world,connection,movement,"' + location + '")\n'
                after = indent + '_TransportDiagnostic.after_aside_commit(world,connection,movement,"' + location + '")\n'
            elif line.strip() == "movement.travelled.append(space.movement._checkpoint(world.facts.actors[primary]))" or line.strip() == "movement.travelled.append(space.movement._checkpoint(world.facts.actors[movement.actor_id]))":
                after = indent + '_TransportDiagnostic.alight_committed(world,connection,movement,"' + location + '")\n'
            rebuilt.append(before + line + after)
        revised = "".join(rebuilt)
        if revised != body:
            patch.replace(body, revised)
    old = '\tif not egress_clear(space,world,connection,primary,int(connection.to),connection.riders,offsets):\n'
    patch.replace(old, old + '\t\t_TransportDiagnostic.alight_rejected(world,connection,"egress_clear_false")\n')
    old = '\t\t\t\tmovement.waiting_reason="护理床岗位已有使用预约："+held\n'
    # This branch exists in both ordinary and convoy advancement.
    for function in ["_alight", "_advance_convoy"]:
        match = re.search(r"^static func " + function + r"\([^\n]*\)[^\n]*:\n([\s\S]*?)(?=^static func |\Z)", patch.text, re.M)
        assert match, function
        body = match[0]
        assert body.count(old) == 1, (function, "Expected bed-claim rejection")
        patched = body.replace(old, old + '\t\t\t\t_TransportDiagnostic.alight_rejected(world,connection,"bed_destination_claim:"+held)\n', 1)
        patch.replace(body, patched)
    patch.wrap("cancel_waiting", "world,movement",
               '\tvar _trace_ticket: Dictionary = _TransportDiagnostic.before_cancel(world,movement)\n',
               '\t_TransportDiagnostic.after_cancel(world,movement,_trace_ticket)\n')
    patch.wrap("_alight", "space,world,connection",
               '\tvar _trace_attempt: Dictionary = _TransportDiagnostic.alight_attempt(world,connection)\n',
               '\t_TransportDiagnostic.alight_finished(world,connection,_trace_attempt)\n')
    for name, arguments in [
        ("_stand_aside", "space,world,connection,actor,movement,members,offsets"),
        ("_stand_aside_convoy", "space,world,connection,actor,movement,plan"),
    ]:
        patch.wrap(name, arguments,
                   '\tvar _trace_aside: Dictionary = _TransportDiagnostic.aside_begin(world,connection,movement,"' + name + '")\n',
                   '\t_TransportDiagnostic.aside_end(world,connection,movement,_trace_aside)\n')
    for method, count in {
        "ticket_created": 2, "ticket_consumed": 2,
        "before_aside_commit": 2, "after_aside_commit": 2,
        "alight_committed": 2, "alight_rejected": 3,
    }.items():
        assert patch.text.count("_TransportDiagnostic." + method + "(") == count, (path, "Missing actual branch", method)
    return patch


def movement_patch(path):
    patch = Patch(path)
    header = "class_name HospitalMovement\nextends RefCounted\n"
    patch.replace(header, header + PREFIX)
    patch.wrap("advance", "world,present_at_start",
               '\tvar _trace_before: Dictionary = _TransportDiagnostic.before_movement(world)\n',
               '\t_TransportDiagnostic.after_movement(world,_trace_before)\n')
    patch.wrap("_move_convoy_portal", "world,actor,movement,targets,floor_id,connector_id",
               '\tvar _trace_portal: Dictionary = _TransportDiagnostic.portal_begin(world,movement,connector_id,floor_id)\n',
               '\t_TransportDiagnostic.portal_end(world,movement,_trace_portal,_trace_value)\n', "MotionResult")
    return patch


def prepare(project, check_only=False):
    root = Path(__file__).resolve().parents[3]
    project = project.resolve()
    assert project.is_relative_to(root / ".cache") and project != root, "Overlay only an isolated .cache project"
    assert (project / "project.godot").is_file(), project
    manifest_path = project / "transport-diagnostic-identity.json"
    assert not manifest_path.exists(), "Preserve existing transport identity; use an uninstrumented copy"
    patches = {
        "game/building/hospital_transit.gd": transit_patch(project / "game/building/hospital_transit.gd"),
        "game/building/hospital_movement.gd": movement_patch(project / "game/building/hospital_movement.gd"),
    }
    driver_name = "tools/performance/current/plain_v4.gd"
    driver = Patch(project / driver_name)
    driver.replace("extends SceneTree\n", "extends SceneTree\n" + PREFIX)
    marker = "\tvar initial: Dictionary = snapshot(world)\n"
    driver.replace(marker, "\t_TransportDiagnostic.prepare(world,content) # Outside every timed simulation step.\n" + marker)
    marker = "\tvar attribution: Dictionary = profiler.report() if profile_stages else {}\n"
    driver.replace(marker, '\t_TransportDiagnostic.finish(output+".transport.json",world)\n' + marker)
    patches[driver_name] = driver
    reversible = {name: patch.checked() for name, patch in patches.items()}
    helper_path = Path(__file__).with_name("transport_diagnostic_trace.gd")
    manifest = {
        "project": str(project), "overlay_order": "clinical -> queue shortcut -> transport",
        "reversible_hooks": reversible, "helper_sha256": sha(helper_path.read_bytes()),
        "prepare_script_sha256": sha(Path(__file__).read_bytes()),
        "sidecar": "<driver output>.transport.json",
        "scope": "Read-only branch diagnostics. No navigation/cache/quote/move/reservation/RNG calls. One first committed stand-aside before/after full fact copy. All hook and snapshot costs are diagnostic, not speed evidence.",
        "engine_run": False,
    }
    if not check_only:
        # Validate every inverse before writing anything. Earlier overlays are input.
        for name, patch in patches.items():
            assert (project / name).read_bytes() == patch.original, (name, "Input changed during preparation")
        for patch in patches.values():
            patch.path.write_bytes(patch.text.encode("utf-8"))
        shutil.copy2(helper_path, project / HELPER)
        script_name = "tools/performance/current/" + Path(__file__).name
        shutil.copy2(Path(__file__), project / script_name)
        inventory_path = project / "source-inventory.json"
        if inventory_path.exists():
            inventory = json.loads(inventory_path.read_text(encoding="utf-8-sig"))
            for name in [HELPER, script_name]:
                if name not in inventory:
                    inventory.append(name)
            inventory_path.write_text(json.dumps(inventory, ensure_ascii=False, indent=2), encoding="utf-8")
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"check_only": check_only, "project": str(project), "patched_files": list(patches), "whole_file_restoration_exact": True, "hook_count": sum(len(p.pairs) for p in patches.values()), "manifest": str(manifest_path) if not check_only else None}))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--check-only", action="store_true")
    options = parser.parse_args()
    prepare(options.project, options.check_only)
