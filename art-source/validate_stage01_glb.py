"""Measure exported GLBs, not Blender construction estimates.

This is the source-asset acceptance tool. It records actual glTF topology,
skin streams, inverse binds, semantic anchors and sampled poses. It does
not claim GPU equivalence, renderer throughput, or full content coverage.
"""

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import struct


BODY_SLOTS = ("head", "look_target", "hand_l", "hand_r", "treatment_anchor", "emotion_anchor", "carry_anchor")
MACHINE_SLOTS = ("patient_anchor", "operator_anchor", "repair_anchor", "effect_anchor", "camera_focus")
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
IDENTITY = [1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def multiply(a, b):
    return [sum(a[k * 4 + row] * b[column * 4 + k] for k in range(4))
            for column in range(4) for row in range(4)]


def transform(matrix, point, direction=False):
    values = (*point, 0 if direction else 1)
    return tuple(sum(matrix[column * 4 + row] * values[column] for column in range(4)) for row in range(3))


def compose(node):
    if "matrix" in node:
        return node["matrix"]
    x, y, z, w = node.get("rotation", (0, 0, 0, 1))
    scale = node.get("scale", (1, 1, 1))
    rotation = [1 - 2 * (y*y + z*z), 2 * (x*y + z*w), 2 * (x*z - y*w), 0,
                2 * (x*y - z*w), 1 - 2 * (x*x + z*z), 2 * (y*z + x*w), 0,
                2 * (x*z + y*w), 2 * (y*z - x*w), 1 - 2 * (x*x + y*y), 0,
                *node.get("translation", (0, 0, 0)), 1]
    for column in range(3):
        for row in range(3):
            rotation[column * 4 + row] *= scale[column]
    return rotation


def bounds(points):
    return {"minimum_m": [min(point[axis] for point in points) for axis in range(3)],
            "maximum_m": [max(point[axis] for point in points) for axis in range(3)]}


def size(box):
    return [box["maximum_m"][axis] - box["minimum_m"][axis] for axis in range(3)]


def support_surface_height(glb, mesh_index, mesh_node, anchor):
    hits = []
    for primitive in glb.document["meshes"][mesh_node["mesh"]]["primitives"]:
        points = [transform(glb.world[mesh_index], point) for point in glb.accessor(primitive["attributes"]["POSITION"])]
        indices = [index[0] for index in glb.accessor(primitive["indices"])]
        for offset in range(0, len(indices), 3):
            a, b, c = (points[index] for index in indices[offset:offset + 3])
            determinant = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
            if abs(determinant) < 1e-10:
                continue
            first = ((b[2] - c[2]) * (anchor[0] - c[0]) + (c[0] - b[0]) * (anchor[2] - c[2])) / determinant
            second = ((c[2] - a[2]) * (anchor[0] - c[0]) + (a[0] - c[0]) * (anchor[2] - c[2])) / determinant
            third = 1 - first - second
            if min(first, second, third) >= -1e-5:
                height = first * a[1] + second * b[1] + third * c[1]
                if height < 1.5:
                    hits.append(height)
    assert hits, "Patient support must have a real mesh surface beneath its anchor"
    return max(hits)


def standing_anchor_references(identity, record, root):
    if identity in ("M37", "M17"):
        width, depth = record["footprint"]
        return {"patient_anchor": (.75, 0, (depth + .5) * 1.5),
                "operator_anchor": ((width + .5) * 1.5, 0, (depth - .5) * 1.5),
                "repair_anchor": ((width - .5) * 1.5, 0, -.75)}, "docs/design/01-simulation.md#2"
    layouts = json.loads((root / "docs/data/clinical-layouts.json").read_text(encoding="utf-8-sig"))["layouts"]
    layout = next(row for row in layouts if row["id"] == ("or_standard" if identity == "EQ01" else "ward_two_beds"))
    equipment = next(row for row in layout["objects"] if row["definition_id"] == identity)
    def engine_point(point):
        return ((point[0] - equipment["anchor"][0] + .5) * 1.5, 0,
                (point[1] - equipment["anchor"][1] + .5) * 1.5)
    surgeon = next(point for point in layout["service_points"] if point["kind"] == ("surgeon" if identity == "EQ01" else "care_1"))
    expected = {"operator_anchor": engine_point(surgeon["anchor"]), "repair_anchor": engine_point(layout["repair_points"][0])}
    if identity == "EQ01":
        for role in ("surgeon", "anesthetist", "nurse"):
            expected["operator_" + role] = engine_point(next(point["anchor"] for point in layout["service_points"] if point["kind"] == role))
    return expected, "docs/data/clinical-layouts.json#" + layout["id"]


class Glb:
    def __init__(self, path):
        self.path = path
        raw = path.read_bytes()
        magic, version, length = struct.unpack_from("<III", raw, 0)
        assert magic == 0x46546C67 and version == 2 and length == len(raw), f"Invalid GLB header: {path}"
        cursor = 12
        self.document, self.binary = None, None
        while cursor < len(raw):
            chunk_length, kind = struct.unpack_from("<II", raw, cursor)
            chunk = raw[cursor + 8:cursor + 8 + chunk_length]
            if kind == 0x4E4F534A:
                self.document = json.loads(chunk)
            elif kind == 0x004E4942:
                self.binary = chunk
            cursor += 8 + chunk_length
        assert self.document and self.binary, "GLB must contain embedded JSON and BIN"
        assert all("uri" not in buffer for buffer in self.document["buffers"]), "External GLB buffers are forbidden"
        self.accessor_values = {}
        self.world = self.world_matrices(self.document["nodes"])

    def accessor(self, index):
        if index in self.accessor_values:
            return self.accessor_values[index]
        accessor = self.document["accessors"][index]
        assert "sparse" not in accessor, "Stage 01 streams must be explicit"
        view = self.document["bufferViews"][accessor["bufferView"]]
        code, byte_width = COMPONENTS[accessor["componentType"]]
        element_width = WIDTHS[accessor["type"]]
        stride = view.get("byteStride", byte_width * element_width)
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = [struct.unpack_from("<" + code * element_width, self.binary, offset + row * stride)
                  for row in range(accessor["count"])]
        if accessor.get("normalized"):
            maximum = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}[accessor["componentType"]]
            values = [tuple(max(-1, component / maximum) for component in row) for row in values]
        self.accessor_values[index] = values
        return values

    def world_matrices(self, nodes):
        parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}
        result = {}
        def visit(index):
            if index not in result:
                local = compose(nodes[index])
                result[index] = multiply(visit(parents[index]), local) if index in parents else local
            return result[index]
        return [visit(index) for index in range(len(nodes))]

    def sampled_world(self, animation_name, seconds):
        animation = next(animation for animation in self.document["animations"] if animation["name"] == animation_name)
        nodes = copy.deepcopy(self.document["nodes"])
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            times = [value[0] for value in self.accessor(sampler["input"])]
            values = self.accessor(sampler["output"])
            index = max(0, min(len(times) - 2, next((i - 1 for i, time in enumerate(times) if time >= seconds), len(times) - 2)))
            fraction = max(0, min(1, (seconds - times[index]) / (times[index + 1] - times[index])))
            first, second = values[index], values[index + 1]
            if channel["target"]["path"] == "rotation" and sum(a*b for a, b in zip(first, second)) < 0:
                second = tuple(-value for value in second)
            value = tuple(a + (b-a) * fraction for a, b in zip(first, second))
            if channel["target"]["path"] == "rotation":
                magnitude = math.sqrt(sum(component**2 for component in value))
                value = tuple(component / magnitude for component in value)
            nodes[channel["target"]["node"]][channel["target"]["path"]] = value
        return self.world_matrices(nodes)

    def skin_vertices(self, world):
        result = []
        for node in self.document["nodes"]:
            if "mesh" not in node:
                continue
            skin = self.document["skins"][node["skin"]]
            inverse_binds = self.accessor(skin["inverseBindMatrices"])
            palette = [multiply(world[joint], inverse_binds[index]) for index, joint in enumerate(skin["joints"])]
            for primitive in self.document["meshes"][node["mesh"]]["primitives"]:
                attributes = primitive["attributes"]
                for position, joints, weights in zip(self.accessor(attributes["POSITION"]), self.accessor(attributes["JOINTS_0"]), self.accessor(attributes["WEIGHTS_0"])):
                    destinations = [(transform(palette[joint], position), weight) for joint, weight in zip(joints, weights) if weight > 0]
                    result.append(tuple(sum(destination[axis] * weight for destination, weight in destinations) for axis in range(3)))
        return result


def validate(path, catalog, root):
    glb = Glb(path)
    document = glb.document
    identity = path.stem.split("_")[1].upper()
    is_body = path.stem.endswith("_body")
    record = next(row for row in catalog["species" if is_body else "machines"]
                  + ([] if is_body else catalog["clinical_equipment"]) if row["id"] == identity)
    meshes = [(index, node) for index, node in enumerate(document["nodes"]) if "mesh" in node]
    assert len(meshes) == 1, f"{identity} must be one skinned visual mesh group"
    mesh_index, mesh_node = meshes[0]
    skin = document["skins"][mesh_node["skin"]]
    names = [document["nodes"][joint]["name"] for joint in skin["joints"]]
    required_slots = BODY_SLOTS if is_body else MACHINE_SLOTS
    assert set(required_slots) <= set(names), f"{identity}: missing semantic slots"
    assert len(names) <= 40, f"{identity}: bone limit"
    root_joint = skin["joints"][names.index("root")]
    assert max(abs(value) for value in transform(glb.world[root_joint], (0, 0, 0))) < 0.0001, "Ground root must be at zero"
    for node in document["nodes"]:
        assert all(value > 0 for value in node.get("scale", (1, 1, 1))), "Negative or zero scale is forbidden"
    triangles = 0
    vertex_count = 0
    surfaces = []
    rest_vertices = []
    used_materials = set()
    maximum_influences = 0
    for primitive in document["meshes"][mesh_node["mesh"]]["primitives"]:
        assert primitive.get("mode", 4) == 4, "Assets must contain triangle surfaces"
        attributes = primitive["attributes"]
        positions = glb.accessor(attributes["POSITION"])
        joints = glb.accessor(attributes["JOINTS_0"])
        weights = glb.accessor(attributes["WEIGHTS_0"])
        assert "NORMAL" in attributes and "TANGENT" in attributes and "COLOR_0" in attributes, "Rest streams must include normals, tangents, colours"
        for indices, values in zip(joints, weights):
            assert all(0 <= index < len(names) for index in indices)
            assert abs(sum(values) - 1) <= .0001 and all(value >= 0 for value in values)
            maximum_influences = max(maximum_influences, sum(value > 0 for value in values))
        assert maximum_influences <= 4
        count = len(glb.accessor(primitive["indices"])) // 3
        triangles += count
        vertex_count += len(positions)
        rest_vertices.extend(transform(glb.world[mesh_index], point) for point in positions)
        used_materials.add(primitive["material"])
        material = document["materials"][primitive["material"]]
        surfaces.append({"triangle_count": count, "vertex_count": len(positions), "material": material["name"],
                         "alpha_mode": material.get("alphaMode", "OPAQUE"), "attribute_accessors": attributes,
                         "index_accessor": primitive["indices"]})
    assert triangles <= (1500 if is_body else 3000), f"{identity}: {triangles} triangles exceed common-view budget"
    assert len(used_materials) <= (2 if is_body else 3)
    rest_bounds = bounds(rest_vertices)
    rest_skin = glb.skin_vertices(glb.world)
    inverse_bind_error = max(math.dist(first, second) for first, second in zip(rest_vertices, rest_skin))
    assert inverse_bind_error <= .0001, f"{identity}: rest inverse-bind mismatch {inverse_bind_error}"
    if is_body:
        expected = [record["body"][key] for key in ("width_m", "height_m", "depth_m")]
        assert max(abs(actual - target) for actual, target in zip(size(rest_bounds), expected)) <= .0001, f"{identity}: body dimensions differ: {size(rest_bounds)}"
        assert abs(rest_bounds["minimum_m"][1]) < .0001, f"{identity}: not rooted at ground"
    else:
        assert rest_bounds["minimum_m"][0] >= -.0001 and rest_bounds["minimum_m"][2] >= -.0001, "Machine base must extend on positive local axes"
        footprint = [cells * 1.5 for cells in record["footprint"]]
        maximum_depth = footprint[1] + (1.5 if identity in ("M37", "M17") else 0)
        assert rest_bounds["maximum_m"][0] <= footprint[0] + .0001 and rest_bounds["maximum_m"][2] <= maximum_depth + .0001, "Machine extends outside base and patient reservation"
        if identity in ("M37", "M17"):
            support_index = names.index("patient_support")
            for primitive in document["meshes"][mesh_node["mesh"]]["primitives"]:
                attributes = primitive["attributes"]
                for point, joints, weights in zip(glb.accessor(attributes["POSITION"]), glb.accessor(attributes["JOINTS_0"]), glb.accessor(attributes["WEIGHTS_0"])):
                    actual = transform(glb.world[mesh_index], point)
                    if any(joint == support_index and weight > 0 for joint, weight in zip(joints, weights)):
                        assert 0 <= actual[0] <= 1.5 and footprint[1] <= actual[2] <= footprint[1] + 1.5, "Seat exceeds actual patient reservation"
                    else:
                        assert -.0001 <= actual[0] <= footprint[0] + .0001 and -.0001 <= actual[2] <= footprint[1] + .0001, "Main machine geometry exceeds base"
    if identity == "S14":
        assert any(surface["alpha_mode"] == "BLEND" for surface in surfaces), "Ghost body must retain transparency"
        assert any(surface["alpha_mode"] == "OPAQUE" for surface in surfaces), "Ghost face needs opaque readable surface"
    animations = {animation["name"]: animation for animation in document["animations"]}
    assert set(("idle", "work", "pause", "recovery", "low_motion")) <= set(animations), f"{identity}: phase clips missing: {list(animations)}"
    if is_body:
        assert "symptom" in animations and "walk" in animations
    else:
        assert set(("prepare", "process", "climax", "safe_finish")) <= set(animations)
    for animation in animations.values():
        for channel in animation["channels"]:
            if channel["target"]["node"] == root_joint:
                # Blender's forced sampling writes static root channels too.
                # Root motion means a changing transform, not channel presence.
                path_ = channel["target"]["path"]
                rest = document["nodes"][root_joint].get(path_, {"translation": (0, 0, 0), "rotation": (0, 0, 0, 1), "scale": (1, 1, 1)}[path_])
                stream = glb.accessor(animation["samplers"][channel["sampler"]]["output"])
                assert all(max(abs(a-b) for a, b in zip(value, rest)) < .0001 for value in stream), "Root motion is forbidden"
    anchors = {name: list(transform(glb.world[skin["joints"][names.index(name)]], (0, 0, 0))) for name in required_slots}
    for name in ("patient_support", "symptom_target", "exit", "operator_surgeon", "operator_anesthetist", "operator_nurse"):
        if name in names:
            anchors[name] = list(transform(glb.world[skin["joints"][names.index(name)]], (0, 0, 0)))
    if not is_body:
        expected_anchors, anchor_source = standing_anchor_references(identity, record, root)
        anchor_errors = {name: math.dist(anchors[name], expected) for name, expected in expected_anchors.items()}
        assert max(anchor_errors.values()) <= .05, f"{identity}: anchor differs from actual operation area"
        support_height = support_surface_height(glb, mesh_index, mesh_node, anchors["patient_support"])
        support_error = abs(support_height - anchors["patient_support"][1])
        assert support_error <= .05, f"{identity}: support anchor does not match actual cushion surface"
    poses = []
    for animation_name in ("walk", "symptom", "work", "pause", "recovery", "low_motion") if is_body else ("prepare", "process", "climax", "safe_finish", "pause", "low_motion"):
        sampled_bounds = []
        for sample_index in range(5):
            world = glb.sampled_world(animation_name, sample_index * .5)
            sampled_bounds.append(bounds(glb.skin_vertices(world)))
        poses.append({"animation": animation_name, "sampled_seconds": [0, .5, 1, 1.5, 2], "measured_world_bounds": sampled_bounds})
    if is_body:
        for pose in poses:
            for box in pose["measured_world_bounds"]:
                excess = max(max(rest_bounds["minimum_m"][axis] - box["minimum_m"][axis],
                                 box["maximum_m"][axis] - rest_bounds["maximum_m"][axis]) for axis in range(3))
                assert excess <= .001, f"{identity}: {pose['animation']} exceeds physical body envelope by {excess:.6f} m"
        dense_envelopes = []
        for animation_name in ("idle", "walk", "symptom", "work", "pause", "recovery", "low_motion"):
            samples = [bounds(glb.skin_vertices(glb.sampled_world(animation_name, frame / 30))) for frame in range(61)]
            dense = {"minimum_m": [min(sample["minimum_m"][axis] for sample in samples) for axis in range(3)],
                     "maximum_m": [max(sample["maximum_m"][axis] for sample in samples) for axis in range(3)]}
            excess = max(max(rest_bounds["minimum_m"][axis] - dense["minimum_m"][axis],
                             dense["maximum_m"][axis] - rest_bounds["maximum_m"][axis]) for axis in range(3))
            assert excess <= .001, f"{identity}: {animation_name} dense pose envelope exceeds body by {excess:.6f} m"
            dense_envelopes.append({"animation": animation_name, "samples_at_30hz": 61,
                                    "measured_world_bounds": dense, "maximum_bound_excess_m": max(0, excess)})
    measured = {"content_id": identity, "asset_path": path.relative_to(root).as_posix(), "source_path": f"art-source/{path.stem}.blend",
                "asset_sha256": sha256(path), "source_sha256": sha256(root / "art-source" / (path.stem + ".blend")),
                "bytes": path.stat().st_size, "kind": "body" if is_body else "machine", "one_actor_mesh": True,
                "triangle_count": triangles, "vertex_count": vertex_count, "surface_count": len(surfaces),
                "bone_count": len(names), "maximum_vertex_influences": maximum_influences, "surfaces": surfaces,
                "rest_mesh_bounds_engine_m": rest_bounds, "rest_inverse_bind_maximum_error_m": inverse_bind_error,
                "joint_order": names, "inverse_bind_matrices_column_major": glb.accessor(skin["inverseBindMatrices"]),
                "rest_joint_world_matrices_column_major": [glb.world[joint] for joint in skin["joints"]],
                "anchors_engine_local_m": anchors, "animation_names": list(animations), "sampled_pose_envelopes": poses,
                "root_motion": False, "original_pipeline_required": identity == "S14",
                "license_source": "project-original procedural meshes and vertex colours; no external art",
                "definition_source": f"docs/data/content-catalog.json#{identity}"}
    if identity in ("M37", "M17"):
        measured["support_component"] = {"bone": "patient_support", "spatial_owner": "actual adjacent patient reservation; not base footprint"}
    if not is_body:
        measured["standing_anchor_reference_source"] = anchor_source
        measured["standing_anchor_errors_m"] = anchor_errors
        measured["patient_support_surface_height_m"] = support_height
        measured["patient_support_surface_error_m"] = support_error
    if is_body:
        measured["dense_normal_pose_envelopes"] = dense_envelopes
    if identity == "S49":
        independent_poses = []
        for label, animation_name, seconds in (("A_work", "work", .5), ("B_walk", "walk", 1.5)):
            world = glb.sampled_world(animation_name, seconds)
            independent_poses.append({"label": label, "animation": animation_name, "seconds": seconds,
                                      "joint_world_matrices_column_major": [world[joint] for joint in skin["joints"]],
                                      "anchors_engine_local_m": {name: list(transform(world[skin["joints"][names.index(name)]], (0, 0, 0))) for name in BODY_SLOTS}})
        assert independent_poses[0]["joint_world_matrices_column_major"][names.index("head")] != independent_poses[1]["joint_world_matrices_column_major"][names.index("head")]
        assert independent_poses[0]["joint_world_matrices_column_major"][names.index("upper_arm_l")] != independent_poses[1]["joint_world_matrices_column_major"][names.index("upper_arm_l")]
        measured["independent_pose_reference"] = independent_poses
        measured["backend_equivalence_status"] = "not_measured_by_asset_export; requires_actual_Compatibility_original_pipeline_comparison"
    print(f"ASSET_VALIDATED={identity};TRIANGLES={triangles};BONES={len(names)};SURFACES={len(surfaces)};INVERSE_BIND_ERROR_M={inverse_bind_error:.9f}")
    return measured


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    catalog_path = root / "docs/data/content-catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8-sig"))
    names = [f"core_{identity}_body.glb" for identity in ("s49", "s21", "s59", "s55", "s14")]
    names.extend(f"core_{identity}_machine.glb" for identity in ("m37", "m17", "eq01", "eq05"))
    assets = [validate(root / "assets/models" / name, catalog, root) for name in names]
    metadata = {"schema": 1, "source_tool": "Blender 4.5.14 LTS", "generator": "art-source/build_stage01.py",
                "generator_sha256": sha256(root / "art-source/build_stage01.py"), "catalog_source_sha256": sha256(catalog_path),
                "units": "metres", "engine_axes": "X right, Y up, Z local grid depth", "matrix_layout": "glTF column-major",
                "semantic_slots": "bone names, resolved through actual imported Skeleton3D; no species-name branching",
                "coverage": {"bodies": 5, "machines": 4, "source_rig_classes": ["biped", "micro", "float"],
                             "uncovered_rig_classes": ["quadruped", "longneck", "plant", "tentacle", "blob", "object"],
                             "gpu_equivalence": "requires_main_stage01_actual_backend_validation", "lod": "common-view mesh only"},
                "assets": assets}
    output = root / "assets/models/stage01-production.json"
    output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"GLB_ACCEPTANCE_PASS={len(assets)};METADATA={output.relative_to(root).as_posix()};TOTAL_GLB_BYTES={sum(asset['bytes'] for asset in assets)}")


if __name__ == "__main__":
    main()
