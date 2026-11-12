"""Fork an imported immutable acceptance project for counts or local timing."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def method(source, name):
    start = re.search(r"^func " + re.escape(name) + r"\([^\n]+\) -> [^\n]+:\n", source, re.M)
    assert start, name
    end = re.search(r"^(?:static )?func ", source[start.end():], re.M)
    stop = start.end() + end.start() if end else len(source)
    return start[0], source[start.start():stop]


def instrument(source, original, mode):
    prefix = 'const _RectangleProbe = preload("res://tools/performance/resident_rectangle_trace.gd")\n'
    names = ["position_reason", "sweep_reason"] + (["reason", "_resident_first_disabled"] if mode == "counts" else [])
    text = source
    renamed = []
    appended = ""
    for name in names:
        header, _ = method(source, name)
        changed = header.replace("func " + name, "func _rectangle_body_" + name, 1)
        assert text.count(header) == 1
        text = text.replace(header, changed, 1)
        renamed.append((header, changed))
        arguments = {"position_reason":"origin", "sweep_reason":"from,to", "reason":"origin", "_resident_first_disabled":"low,high"}[name]
        if name == "reason":
            wrapper = header + '\t_RectangleProbe.reason()\n\treturn _rectangle_body_reason(origin)\n'
        elif name == "_resident_first_disabled":
            wrapper = header + '\tvar result: int = _rectangle_body__resident_first_disabled(low,high)\n\t_RectangleProbe.rectangle(low,high,result)\n\treturn result\n'
        else:
            wrapper = header + f'\tif _RectangleProbe.replaying and OS.get_thread_caller_id()==_RectangleProbe.thread_id:\n\t\tif _RectangleProbe.reference_replay: return _rectangle_original_{name}({arguments})\n\t\treturn _rectangle_body_{name}({arguments})\n\tif _RectangleProbe.baseline: return _rectangle_original_{name}({arguments})\n\tif not _RectangleProbe.observing(): return _rectangle_body_{name}({arguments})\n\t_RectangleProbe.enter("{name}",self,[{arguments}])\n\tvar result: String = _rectangle_body_{name}({arguments})\n\t_RectangleProbe.leave(result)\n\treturn result\n'
        appended += "\n" + wrapper
    references = {}
    for name in ["position_reason", "sweep_reason"]:
        header, body = method(original, name)
        copied = body.replace(header, header.replace("func " + name, "func _rectangle_original_" + name, 1), 1)
        appended += "\n" + copied
        references[name] = {"header":header,"complete_original_method_sha256":hashlib.sha256(body.encode("utf-8")).hexdigest(),"copied_body_byte_exact_except_function_name":True}
    assert text.count("extends RefCounted\n") == 1
    text = text.replace("extends RefCounted\n", "extends RefCounted\n" + prefix, 1) + appended
    restored = text.removesuffix(appended).replace(prefix, "", 1)
    for header, changed in renamed:
        assert restored.count(changed) == 1
        restored = restored.replace(changed, header, 1)
    assert restored.encode("utf-8") == source.encode("utf-8"), "Complete production body restoration failed"
    return text, {"prefix":prefix,"appended":appended,"renamed":renamed,"references":references,"complete_source_restores_exactly":True,"reason_and_resident_helper_uninstrumented_for_timing":mode=="timing"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-project", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--overlay", choices=["counts", "timing"], required=True)
    parser.add_argument("--reference-commit", default="6e8d59c", help="Git methods used for A; defaults to the original resident-mask comparison")
    parser.add_argument("--candidate-source", type=Path, help="Optional RouteClearance with only the count/bounds gate reordered")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    base, target = args.base_project.resolve(), args.output.resolve()
    target.relative_to(repo / ".cache")
    metadata = json.loads((base / "source-identity.json").read_text(encoding="utf-8-sig"))
    paths = [row["path"] for row in metadata["source"]]
    before = {name:digest(base/name) for name in paths}
    assert before == {row["path"]:row["sha256"] for row in metadata["source"]}, "Frozen baseline source changed"
    reference_commit = subprocess.check_output(["git","-C",str(repo),"rev-parse",args.reference_commit+"^{commit}"]).decode().strip()
    target.mkdir(parents=True, exist_ok=False)
    for name in paths:
        destination = (target/name).resolve()
        destination.relative_to(target)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base/name, destination)
    for name in [".godot/imported", "game/platform/windows/bin"]:
        shutil.copytree(base/name, target/name, dirs_exist_ok=True)
    for name in [".godot/global_script_class_cache.cfg", ".godot/extension_list.cfg"]:
        shutil.copy2(base/name, target/name)
    relative = "game/building/route_clearance.gd"
    source = (target/relative).read_bytes().decode("utf-8")
    candidate_overlay = None
    if args.candidate_source:
        old_gate = "if x0>=0 and y0>=0 and x1<FloorNavigation.SIDE and y1<FloorNavigation.SIDE and (x1-x0+1)*(y1-y0+1)>=MIN_RESIDENT_MASK_ORIGINS:"
        new_gate = "if (x1-x0+1)*(y1-y0+1)>=MIN_RESIDENT_MASK_ORIGINS and x0>=0 and y0>=0 and x1<FloorNavigation.SIDE and y1<FloorNavigation.SIDE:"
        candidate = args.candidate_source.resolve().read_bytes().decode("utf-8")
        assert source.count(old_gate) == 1 and candidate == source.replace(old_gate,new_gate,1), "Only the exact count/bounds gate reorder is allowed"
        candidate_overlay = {"path":relative,"source":str(args.candidate_source.resolve()),"baseline_sha256":hashlib.sha256(source.encode("utf-8")).hexdigest(),"candidate_sha256":hashlib.sha256(candidate.encode("utf-8")).hexdigest(),"only_condition_reordered":True}
        source = candidate
    original = subprocess.check_output(["git","-C",str(repo),"show",reference_commit+":"+relative]).decode("utf-8")
    updated, hooks = instrument(source, original, args.overlay)
    (target/relative).write_bytes(updated.encode("utf-8"))
    trace_path = target/"tools/performance/resident_rectangle_trace.gd"
    trace = trace_path.read_bytes()
    old_label = b"calls complete6e8d59c method bodies for A."
    assert trace.count(old_label) == 1
    trace_path.write_bytes(trace.replace(old_label,("calls complete"+reference_commit[:7]+" method bodies for A.").encode("utf-8"),1))
    assert all(digest(base/name)==sha for name,sha in before.items()), "Imported source changed during freeze"
    identity = {"base_project":str(base),"overlay":args.overlay,"reference_commit":reference_commit,"candidate_overlay":candidate_overlay,"original_source":before,"source":{name:digest(target/name) for name in paths},"hooks":hooks,"native":{path.name:digest(path) for path in (target/"game/platform/windows/bin").glob("*.dll")},"engine":metadata["engine"],"engine_sha256":metadata["engine_sha256"],"scope":"Same imported source and DLL. RouteClearance has reversible observation wrappers and exact recorded-reference public method bodies; optional production difference is only the asserted count/bounds gate reorder. The trace reference label follows the recorded commit. Counts and timing are separate. No engine runs during this preparation."}
    (target/"resident-rectangle-identity.json").write_text(json.dumps(identity,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"project":str(target),"overlay":args.overlay,"source_files":len(paths),"byte_exact_restoration":True,"engine_runs_started":0}))


if __name__ == "__main__":
    main()
