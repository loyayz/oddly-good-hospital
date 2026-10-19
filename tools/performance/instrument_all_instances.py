"""Reversible, diagnostic-only wrappers in an already frozen performance project.

Run prepare.ps1 first. This tool never edits the working game's source tree and
does not invoke Godot. A separate, untransformed frozen project is the plain
control. All original method bodies are retained byte for byte; only their
declaration names change, and same-signature wrappers call them synchronously.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

META = "oddly_good_tail_profile_observer_v1"
PREFIX = "_tail_profile_original_"
IDENTITY = "all-instance-profile-identity.json"
CLASS_GROUPS = {
    "HospitalSpace": "space", "NavigationCache": "navigation",
    "HospitalClinic": "clinic", "HospitalVisitors": "visitors",
    "HospitalPublicAreas": "public_areas", "HospitalPersonalBeds": "personal_beds",
    "FloorNavigation": "floor_graph",
}
EXTRA = {
    "space": ["begin_route_query", "end_route_query", "begin_dynamic_route_query",
              "static_reason", "_facility_quote", "_facility_exit_quote", "facility_trip_quote",
              "can_reach", "_route_result", "_travel_route_quote", "_floor_travel_quote"],
    "navigation": ["inherit_projection", "forward_distance", "_travel_distance", "_forward_field"],
    "floor_graph": ["find_path"],
    "clinic": ["_service_pair_reachable", "_plan_quote_in_query", "_select_plan_in_query"],
    "public_areas": ["_queue_fit_in_query", "_intent_view", "_wait_estimate_view"],
    "transit": ["route", "fits", "quote", "_quote_known_fit", "_prefix", "egress_clear"],
    "clearance": ["_init", "_build_static", "capture_source", "capture_occupancy"],
}
# Full worlds and source structures are deliberately not serialized per call.
# The observer samples these selected arguments and records world identity apart
# from the identity-agnostic parameter key. Equality of keys is diagnostic only.
PARAMETERS = {
    "space.route", "space.can_reach", "space._route_result", "space.travel_quote", "space._floor_route", "space.static_reason",
    "space._travel_route_quote", "space._floor_travel_quote",
    "space.facility_quote", "space.facility_preflight_quote", "space.facility_geometry_quote",
    "space._facility_quote", "space._facility_exit_quote", "space.facility_trip_quote",
    "clinic.service_candidates", "clinic._service_pair_reachable",
    "public_areas.select", "public_areas._waiting_point", "public_areas._queue_fit",
    "transit.route", "transit.fits", "transit.quote", "transit._quote_known_fit",
    "transit._prefix", "transit.egress_clear", "navigation.travel_distance",
    "navigation.forward_distance", "navigation._travel_distance",
    "clearance.capture_source",
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def split_arguments(text: str) -> list[str]:
    """Split only top-level commas, retaining quoted/default collection values."""
    result, start, level, quote, escape = [], 0, 0, "", False
    for i, char in enumerate(text):
        if quote:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char in "([{":
            level += 1
        elif char in ")]}":
            level -= 1
        elif char == "," and level == 0:
            result.append(text[start:i].strip())
            start = i + 1
    if text[start:].strip():
        result.append(text[start:].strip())
    if quote or level:
        raise ValueError("Unbalanced method arguments")
    return result


def transform(source: str, group: str, methods: set[str], ledger: bool = False) -> tuple[str, list[dict]]:
    if PREFIX in source or META in source:
        raise ValueError("Source already contains diagnostic wrappers")
    declarations = list(re.finditer(r"^(static )?func ([A-Za-z_][A-Za-z_0-9]*)\(", source, re.M))
    replacements, wrappers, records = [], [], []
    for declaration in declarations:
        name = declaration.group(2)
        if name not in methods:
            continue
        # Find the header's matching close parenthesis. Default arguments may
        # themselves contain parentheses, dictionaries, lists or strings.
        args_start = declaration.end()
        level, quote, escape, args_end = 1, "", False, None
        for i in range(args_start, len(source)):
            char = source[i]
            if quote:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == quote:
                    quote = ""
            elif char in "\"'":
                quote = char
            elif char == "(":
                level += 1
            elif char == ")":
                level -= 1
                if level == 0:
                    args_end = i
                    break
        if args_end is None:
            raise ValueError(f"Unclosed header: {name}")
        header_end = source.index("\n", args_end)
        header = source[declaration.start():header_end]
        if not header.rstrip().endswith(":"):
            raise ValueError(f"Unsupported method header: {name}")
        args = [re.split(r"\s*[:=]", value, maxsplit=1)[0].strip()
                for value in split_arguments(source[args_start:args_end])]
        if any(not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", arg) for arg in args):
            raise ValueError(f"Unsupported argument in {name}")
        returns = not bool(re.search(r"->\s*void\s*:$", header))
        original = PREFIX + name
        call = original + "(" + ",".join(args) + ")"
        operation = group + "." + name
        instance = "0" if declaration.group(1) else "get_instance_id()"
        payload = ("{" + ",".join(json.dumps(arg) + ":" + arg for arg in args) + "}"
                   if ledger or operation in PARAMETERS else "{}")
        result = "_tail_profile_result"
        lines = [header,
                 f'\tvar _tail_profile_observer: Variant = Engine.get_meta(&"{META}") if Engine.has_meta(&"{META}") else null',
                 "\tif _tail_profile_observer==null:",
                 "\t\t" + ("return " if returns else "") + call]
        if not returns:
            lines.append("\t\treturn")
        lines += [f'\t_tail_profile_observer.enter_instance("{operation}",{instance},{payload})',
                  "\t" + (f"var {result}: Variant = " if returns else "") + call,
                  f'\t_tail_profile_observer.exit_instance("{operation}",{result if returns else "null"})']
        if returns:
            lines.append("\treturn " + result)
        wrapper = "\n".join(lines) + "\n"
        name_start, name_end = declaration.span(2)
        replacements.append((name_start, name_end, original))
        wrappers.append(wrapper)
        # The original method spans through the next declaration. Hashing that
        # exact region demonstrates that no original statements were rewritten.
        next_start = next((other.start() for other in declarations if other.start() > declaration.start()), len(source))
        body = source[header_end:next_start]
        records.append({"method": name, "operation": operation,
                        "static": bool(declaration.group(1)), "arguments": args,
                        "original_header_sha256": sha(header.encode()),
                        "original_body_sha256": sha(body.encode()),
                        "wrapper_sha256": sha(wrapper.encode()),
                        "parameters_sampled": ledger or operation in PARAMETERS})
    rewritten = source
    for start, finish, value in reversed(replacements):
        rewritten = rewritten[:start] + value + rewritten[finish:]
    marker = "\n# All-instance diagnostic wrappers; original bodies above are unchanged.\n"
    generated = rewritten + marker + "\n".join(wrappers) if records else source
    # Independent inverse: strip the exact appended suffix and undo only the
    # renamed declarations. Nothing else may differ, including whitespace.
    inverse = generated[:len(rewritten)]
    inverse = re.sub(r"^((?:static )?func )" + re.escape(PREFIX) + r"([A-Za-z_][A-Za-z_0-9]*)\(", r"\1\2(", inverse, flags=re.M)
    if inverse != source:
        raise AssertionError("Source transformation is not exactly reversible")
    return generated, records


def instrument(project: Path, ledger: bool = False) -> dict:
    project = project.resolve()
    repository = Path(__file__).resolve().parents[2]
    if project == repository or not (project / "source-identity.json").is_file():
        raise ValueError("Expected a separate frozen project created by prepare.ps1")
    identity_path = project / IDENTITY
    if identity_path.exists():
        raise FileExistsError(identity_path)
    profile = (project / "tools/performance/step_profile.gd").read_text(encoding="utf-8")
    common = set(json.loads(re.search(r"const COMMON_METHODS: Array\[String\] = (\[[^\n]+\])", profile).group(1)))
    hot = json.loads(re.search(r"const HOT_METHODS: Dictionary = (\{.*?^\})", profile, re.M | re.S).group(1))
    simulation = (project / "game/sim/simulation.gd").read_text(encoding="utf-8")
    groups = dict(CLASS_GROUPS)
    groups.update({klass: group for group, klass in re.findall(r'_register_service\("([^"]+)",([A-Za-z_0-9]+)\.new\(', simulation)})
    groups.update({"HospitalTransit": "transit", "RouteClearance": "clearance"})
    prepared = []
    for path in sorted((project / "game").rglob("*.gd")):
        raw = path.read_bytes()
        source = raw.decode("utf-8")
        match = re.search(r"^class_name ([A-Za-z_0-9]+)", source, re.M)
        if not match or match.group(1) not in groups:
            continue
        # Refuse newline conversion instead of concealing it in identity proof.
        if b"\r" in raw:
            raise ValueError(f"Frozen source must use LF: {path}")
        group = groups[match.group(1)]
        methods = common | set(hot.get(group, [])) | set(EXTRA.get(group, []))
        if ledger and group == "space":
            methods |= {"reserve_facility", "facility_reservation_reason", "_facility_region_reason"}
        generated, records = transform(source, group, methods, ledger)
        if records:
            prepared.append((path, raw, generated.encode("utf-8"), records))
    if not all(any(record["operation"] == required for _, _, _, records in prepared for record in records)
               for required in ["space.route", "navigation.floor_source", "transit._prefix", "transit.egress_clear", "clearance.capture_source", "clearance.capture_occupancy"]):
        raise ValueError("Required all-instance coverage missing")
    result = {"schema_version": 1, "diagnostic_only": True,
              "formal_acceptance_paused": True, "engine_metadata_key": META,
              "decision_ledger": ledger,
              "transformer_sha256": sha(Path(__file__).read_bytes()),
              "frozen_source_identity_sha256": sha((project / "source-identity.json").read_bytes()),
              "original_method_bodies_preserved": True,
              "transformed_file_count": len(prepared),
              "actual_method_count": sum(len(records) for _, _, _, records in prepared),
              "files": []}
    # Do not partially modify a project until every selected source parses and
    # reconstructs. Original copies are inside a dot-directory Godot ignores.
    for path, original, generated, records in prepared:
        relative = path.relative_to(project)
        backup = project / ".cache/tail-profile-originals" / relative
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_bytes(original)
        path.write_bytes(generated)
        result["files"].append({"path": relative.as_posix(), "original_sha256": sha(original),
                                "generated_sha256": sha(generated), "reconstructed_original_sha256": sha(original),
                                "actual_method_count": len(records), "methods": records})
    identity_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--ledger", action="store_true", help="Record the complete nested call ledger with compact business arguments")
    args = parser.parse_args()
    result = instrument(args.project, args.ledger)
    print(json.dumps({"identity": str(args.project / IDENTITY), "files": len(result["files"]),
                      "methods": sum(len(item["methods"]) for item in result["files"]),
                      "original_method_bodies_preserved": True}))
