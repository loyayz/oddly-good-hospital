"""Accept real GLB props and record their display-only integration contract."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from validate_stage01_glb import Glb, IDENTITY, bounds, compose, transform


CONTRACTS = {
    "case_d37_tissue": {"binding_id": "B_S49_D37_M37", "attach_slot": "hand_l", "attachment_engine_m": [0, 0, 0],
                         "required_nodes": ["sail", "paper_body", "grip"], "projection_only": False},
    "device_m37_filter": {"binding_id": "B_S49_D37_M37", "attach_definition": "M37", "attachment_engine_m": [1.5, 1.3, 1.5],
                           "required_nodes": ["fan", "cloud_bag", "cloud", "filter_seal"], "projection_only": False},
    "case_d23_dream": {"binding_id": "B_S49_D23_M23", "attach_slot": "head", "attachment_engine_m": [0, 0, 0],
                        "required_nodes": ["bubble", "sheep", "sheep_2", "sheep_pillow", "pillow", "dream_fence", "closed_seam"],
                        "projection_only": True},
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def actual_bounds(glb, world):
    points = []
    for index, node in enumerate(glb.document["nodes"]):
        if "mesh" not in node:
            continue
        for primitive in glb.document["meshes"][node["mesh"]]["primitives"]:
            points.extend(transform(world[index], point) for point in glb.accessor(primitive["attributes"]["POSITION"]))
    return bounds(points)


def scale_of(matrix):
    return [math.sqrt(sum(matrix[column * 4 + row] ** 2 for row in range(3))) for column in range(3)]


def validate(root, name, contract):
    path = root / "assets/gags" / (name + ".glb")
    glb = Glb(path)
    document = glb.document
    scene = document["scenes"][document.get("scene", 0)]
    assert len(scene["nodes"]) == 1, "The prop needs exactly one attachment root"
    root_index = scene["nodes"][0]
    assert document["nodes"][root_index]["name"] == name
    assert max(abs(first - second) for first, second in zip(compose(document["nodes"][root_index]), IDENTITY)) <= .00001, "Root must be zero and identity"
    assert not document.get("skins"), "Case props cannot create actors or skeleton simulators"
    names = {node["name"]: index for index, node in enumerate(document["nodes"])}
    assert set(contract["required_nodes"]) <= set(names), f"Required display nodes missing in {name}"
    parents = {child: index for index, node in enumerate(document["nodes"]) for child in node.get("children", [])}
    if name == "case_d37_tissue":
        assert parents[names["sail"]] == root_index and parents[names["grip"]] == root_index
        assert math.dist(transform(glb.world[names["grip"]], (0, 0, 0)), (0, 0, 0)) <= .00001
    if name == "case_d23_dream":
        assert parents[names["pillow"]] == names["sheep_pillow"], "The final sheep must keep its own pillow"
    triangles = 0
    surfaces = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            assert set(("POSITION", "NORMAL", "TANGENT", "COLOR_0")) <= set(attributes)
            count = len(glb.accessor(primitive["indices"])) // 3
            triangles += count
            material = document["materials"][primitive["material"]]
            surfaces.append({"mesh": mesh["name"], "triangles": count, "material": material["name"], "alpha_mode": material.get("alphaMode", "OPAQUE")})
    assert triangles <= 850, "Keep the representative gag inside the common-view character budget"
    clips = {animation["name"]: animation for animation in document["animations"]}
    assert set(("symptom", "work", "paused", "recovery", "recovery_hold", "low_motion", "short_loop")) <= set(clips), f"Missing phase clips in {name}: {list(clips)}"
    durations = {}
    envelopes = []
    for clip_name, animation in clips.items():
        maximum = max(max(value[0] for value in glb.accessor(sampler["input"])) for sampler in animation["samplers"])
        assert 0 < maximum <= 2.01, "Prop clips must be short, and their time does not own game work"
        durations[clip_name] = maximum
        assert all(channel["target"]["node"] != root_index for channel in animation["channels"]), "Props must remain on the real external attachment"
        samples = [actual_bounds(glb, glb.sampled_world(clip_name, maximum * fraction / 8)) for fraction in range(9)]
        aggregate = {"minimum_m": [min(sample["minimum_m"][axis] for sample in samples) for axis in range(3)],
                     "maximum_m": [max(sample["maximum_m"][axis] for sample in samples) for axis in range(3)]}
        envelopes.append({"clip": clip_name, "sample_count": 9, "measured_local_bounds_engine_m": aggregate})
        if name == "device_m37_filter":
            world_box = {key: [point + offset for point, offset in zip(value, contract["attachment_engine_m"])] for key, value in aggregate.items()}
            assert world_box["minimum_m"][0] >= 0 and world_box["maximum_m"][0] <= 3
            assert world_box["minimum_m"][2] >= 0 and world_box["maximum_m"][2] <= 3, "Device parts exceed M37 registered base"
            assert world_box["minimum_m"][1] >= 0 and world_box["maximum_m"][1] <= 2.4, "Device parts exceed actual representative height"
    if name == "case_d37_tissue":
        opened = glb.sampled_world("recovery", 0)
        folded = glb.sampled_world("recovery", durations["recovery"])
        assert max(scale_of(opened[names["sail"]])) > .99
        assert max(scale_of(folded[names["sail"]])) < .07, "Cured paper needs a readable folded hold"
    elif name == "device_m37_filter":
        assert glb.sampled_world("work", .50)[names["fan"]] != glb.sampled_world("work", 0)[names["fan"]]
    else:
        assert "awaiting_result" in clips and "low_motion_work" in clips
        opened = glb.sampled_world("awaiting_result", durations["awaiting_result"])
        closed = glb.sampled_world("recovery", durations["recovery"])
        assert max(scale_of(opened[names["bubble"]])) > .99, "Operation completion cannot imply cured bubble"
        assert max(scale_of(closed[names["bubble"]])) < .05
        for sheep in ("sheep", "sheep_2", "sheep_pillow"):
            assert glb.sampled_world("work", 0)[names[sheep]] != glb.sampled_world("work", durations["work"])[names[sheep]]
        assert any(surface["alpha_mode"] == "BLEND" for surface in surfaces)
    measured = {"name": name, **contract, "asset_path": path.relative_to(root).as_posix(),
                "source_path": f"art-source/gags/{name}.blend", "sha256": sha256(path), "bytes": path.stat().st_size,
                "triangle_count": triangles, "surface_count": len(surfaces), "surfaces": surfaces,
                "node_names": list(names), "clip_durations_seconds": durations,
                "rest_local_bounds_engine_m": actual_bounds(glb, glb.world), "clip_envelopes": envelopes,
                "root_motion": False, "simulation_entities": 0}
    print(f"GAG_ACCEPTED={name};TRIANGLES={triangles};SURFACES={len(surfaces)};CLIPS={len(clips)};BYTES={path.stat().st_size}")
    return measured


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    catalog_path = root / "docs/data/content-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8-sig"))
    bindings = {binding["id"] for binding in catalog["treatment_bindings"]}
    assert all(contract["binding_id"] in bindings for contract in CONTRACTS.values())
    assets = [validate(root, name, contract) for name, contract in CONTRACTS.items()]
    metadata = {"schema": 1, "source_tool": "Blender 4.5.14 LTS", "generator_sha256": sha256(root / "art-source/gags/build_gags.py"),
                "acceptance_tool_sha256": sha256(root / "art-source/gags/validate_gags.py"), "content_source_sha256": sha256(catalog_path),
                "units": "metres", "engine_axes": "X right, Y up, Z depth", "assets": assets,
                "phase_mapping": {"paused": "Pause the current work sample to preserve exact progress; static clip is a readable fallback.",
                                  "recovery": "Only select for an actual cured result. Device safe_finish is allowed for every completed attempt.",
                                  "awaiting_result": "D23 neutral observation with bubble open, even if its committed result is not revealed yet.",
                                  "short_loop": "Secondary display cycle only; clinical milestones use actual progress, never loop completion."},
                "license_source": "Oddly Good Hospital project-original procedural meshes and vertex colours",
                "validation_scope": "Actual Blender export and GLB geometry, node, phase and attachment verification; GPU and game integration measured separately."}
    output = root / "assets/gags/stage01-gags.json"
    output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"GAG_ACCEPTANCE_PASS={len(assets)};TOTAL_GLB_BYTES={sum(asset['bytes'] for asset in assets)}")


if __name__ == "__main__":
    main()
