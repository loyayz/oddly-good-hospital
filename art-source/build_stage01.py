"""Build the Stage 01 original low-poly assets with Blender 4.5.14 LTS.

Source units are metres, Z is up, and source -Y is engine +Z. Every body is
one actor mesh and one armature; coloured colonies and equipment props are
visual mesh parts, never simulation entities.
"""

import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


PALETTE = {
    "cream": (0.88, 0.86, 0.81, 1.0),
    "clinic_blue": (0.53, 0.64, 0.80, 1.0),
    "slate_blue": (0.28, 0.38, 0.56, 1.0),
    "coral": (0.82, 0.47, 0.39, 1.0),
    "gold": (0.78, 0.62, 0.36, 1.0),
    "ink": (0.12, 0.16, 0.27, 1.0),
    "skin": (0.77, 0.55, 0.40, 1.0),
    "stone": (0.50, 0.55, 0.65, 1.0),
    "leaf": (0.35, 0.53, 0.27, 1.0),
    "ghost": (0.69, 0.78, 0.90, 0.48),
    "night": (0.39, 0.36, 0.61, 1.0),
}
BODY_SLOTS = ("head", "look_target", "hand_l", "hand_r", "treatment_anchor",
              "emotion_anchor", "carry_anchor")
MACHINE_SLOTS = ("patient_anchor", "operator_anchor", "repair_anchor",
                 "effect_anchor", "camera_focus")
CELL_METRES = 1.5


class MeshBuilder:
    """One shared material, vertex colour, and explicit rigid bone weights."""

    def __init__(self):
        self.vertices = []
        self.faces = []
        self.colours = []
        self.bones = []
        self.surfaces = []

    def part(self, vertices, faces, colour, bone, surface=0):
        offset = len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.colours.extend([PALETTE[colour]] * len(vertices))
        self.bones.extend([bone] * len(vertices))
        for face in faces:
            for index in range(1, len(face) - 1):
                self.faces.append((offset + face[0], offset + face[index], offset + face[index + 1]))
                self.surfaces.append(surface)

    def box(self, centre, size, colour, bone, surface=0):
        x, y, z = centre
        w, d, h = (value / 2 for value in size)
        vertices = [(x + a * w, y + b * d, z + c * h)
                    for a, b, c in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                                    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                 (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.part(vertices, faces, colour, bone, surface)

    def ellipsoid(self, centre, size, colour, bone, segments=8, rings=4, surface=0):
        vertices = [(centre[0], centre[1], centre[2] - size[2] / 2)]
        for ring in range(1, rings):
            latitude = -math.pi / 2 + math.pi * ring / rings
            for segment in range(segments):
                longitude = 2 * math.pi * segment / segments
                vertices.append((centre[0] + math.cos(latitude) * math.cos(longitude) * size[0] / 2,
                                 centre[1] + math.cos(latitude) * math.sin(longitude) * size[1] / 2,
                                 centre[2] + math.sin(latitude) * size[2] / 2))
        vertices.append((centre[0], centre[1], centre[2] + size[2] / 2))
        faces = []
        for segment in range(segments):
            following = (segment + 1) % segments
            faces.append((0, 1 + following, 1 + segment))
            for ring in range(rings - 2):
                current = 1 + ring * segments
                next_ring = current + segments
                faces.append((current + segment, current + following,
                              next_ring + following, next_ring + segment))
            top = 1 + (rings - 2) * segments
            faces.append((top + segment, top + following, len(vertices) - 1))
        self.part(vertices, faces, colour, bone, surface)

    def rod(self, start, end, radius, colour, bone, sides=8, surface=0):
        start, end = Vector(start), Vector(end)
        axis = (end - start).normalized()
        helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((0, 1, 0))
        first = axis.cross(helper).normalized()
        second = axis.cross(first).normalized()
        vertices = [point + radius * (math.cos(index * math.tau / sides) * first
                                      + math.sin(index * math.tau / sides) * second)
                    for point in (start, end) for index in range(sides)]
        faces = [tuple(reversed(range(sides))), tuple(range(sides, sides * 2))]
        faces.extend((index, (index + 1) % sides, (index + 1) % sides + sides, index + sides)
                     for index in range(sides))
        self.part(vertices, faces, colour, bone, surface)

    def create(self, name, armature, ghost=False):
        mesh = bpy.data.meshes.new(name + "_rest")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        colours = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        uv = mesh.uv_layers.new(name="UVMap")
        for polygon, surface in zip(mesh.polygons, self.surfaces):
            polygon.material_index = surface
            for corner, loop_index in enumerate(polygon.loop_indices):
                vertex_index = mesh.loops[loop_index].vertex_index
                colours.data[loop_index].color = self.colours[vertex_index]
                uv.data[loop_index].uv = ((0, 0), (1, 0), (0, 1))[corner]
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(make_material("stage01_vertex_colour_alpha" if ghost else "stage01_vertex_colour", ghost))
        if ghost:
            mesh.materials.append(make_material("stage01_ghost_face", False))
        for bone_name in sorted(set(self.bones)):
            group = obj.vertex_groups.new(name=bone_name)
            group.add([index for index, bone in enumerate(self.bones) if bone == bone_name], 1.0, "REPLACE")
        modifier = obj.modifiers.new("OriginalBonePipeline", "ARMATURE")
        modifier.object = armature
        obj.parent = armature
        obj["content_id"] = name.split("_")[1].upper()
        obj["one_actor_mesh"] = True
        obj["no_root_motion"] = True
        return obj


def make_material(name, transparent):
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.75
    colours = material.node_tree.nodes.new("ShaderNodeVertexColor")
    colours.layer_name = "Col"
    material.node_tree.links.new(colours.outputs["Color"], principled.inputs["Base Color"])
    if transparent:
        # Both surfaces use the same colour stream. The required ghost opacity
        # belongs to its material, while the face remains an opaque surface.
        principled.inputs["Alpha"].default_value = .48
        material.surface_render_method = "DITHERED"
        material.use_transparency_overlap = False
    return material


def make_armature(name, definitions):
    armature = bpy.data.objects.new(name, bpy.data.armatures.new(name + "_rig"))
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent in definitions:
        bone = armature.data.edit_bones.new(bone_name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = armature.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
    armature["source_units"] = "metres"
    armature["root_motion"] = False
    return armature


def body_rig(width, depth, height, kind):
    def point(x, y, z):
        return (x * width, y * depth, z * height)

    definitions = [
        ("root", point(0, 0, 0), point(0, 0, 0.04), None),
        ("hips", point(0, 0, .43), point(0, 0, .55), "root"),
        ("spine", point(0, 0, .55), point(0, 0, .78), "hips"),
        ("neck", point(0, 0, .78), point(0, 0, .85), "spine"),
        ("head", point(0, 0, .85), point(0, 0, .99), "neck"),
    ]
    for side, sign in (("l", -1), ("r", 1)):
        definitions.extend([
            ("upper_arm_" + side, point(sign * .26, 0, .76), point(sign * .40, 0, .64), "spine"),
            ("forearm_" + side, point(sign * .40, 0, .64), point(sign * .43, 0, .51), "upper_arm_" + side),
            ("hand_" + side, point(sign * .43, 0, .51), point(sign * .43, -.06, .48), "forearm_" + side),
            ("thigh_" + side, point(sign * .13, 0, .43), point(sign * .13, 0, .24), "hips"),
            ("shin_" + side, point(sign * .13, 0, .24), point(sign * .13, 0, .06), "thigh_" + side),
            ("foot_" + side, point(sign * .13, 0, .06), point(sign * .13, -.22, .06), "shin_" + side),
        ])
    definitions.extend([
        ("look_target", point(0, -.40, .91), point(0, -.45, .91), "head"),
        ("treatment_anchor", point(0, -.08, .49), point(0, -.08, .54), "hips"),
        ("emotion_anchor", point(0, 0, 1.04), point(0, 0, 1.09), "head"),
        ("carry_anchor", point(0, -.25, .68), point(0, -.25, .73), "spine"),
    ])
    return definitions


def build_biped(record):
    w, d, h = (record["body"][key] for key in ("width_m", "depth_m", "height_m"))
    rig = make_armature("core_" + record["id"].lower() + "_rig", body_rig(w, d, h, "biped"))
    mesh = MeshBuilder()
    def box(centre, size, colour, bone):
        mesh.box((centre[0] * w, centre[1] * d, centre[2] * h),
                 (size[0] * w, size[1] * d, size[2] * h), colour, bone)
    def ball(centre, size, colour, bone):
        mesh.ellipsoid((centre[0] * w, centre[1] * d, centre[2] * h),
                       (size[0] * w, size[1] * d, size[2] * h), colour, bone)
    def rod(start, end, radius, colour, bone):
        mesh.rod((start[0] * w, start[1] * d, start[2] * h),
                 (end[0] * w, end[1] * d, end[2] * h), radius * w, colour, bone)
    identity = record["id"]
    head_colour = "skin" if identity == "S49" else "leaf" if identity == "S55" else "stone"
    torso_colour = "cream" if identity == "S49" else head_colour
    if identity == "S55":
        rod((0, 0, .43), (0, 0, .82), .14, "leaf", "spine")
        for height in (.50, .61, .72):
            box((0, 0, height), (.34, .37, .018), "gold", "spine")
        rod((0, 0, .82), (0, 0, .99), .16, "leaf", "head")
        # Leaf sleeves and crown retain the thin, tall bamboo silhouette.
        for sign in (-1, 1):
            mesh.part([(.10 * w, 0, .96 * h), (0, sign * .50 * d, .94 * h),
                       (.20 * w, 0, h)], [(0, 1, 2)], "clinic_blue", "head")
    elif identity == "S59":
        box((0, 0, .63), (.57, .74, .31), "stone", "spine")
        box((0, 0, .45), (.44, .63, .12), "slate_blue", "hips")
        ball((0, 0, .89), (.47, .72, .22), "stone", "head")
        box((0, -.38, .69), (.17, .04, .03), "clinic_blue", "spine")
        for sign in (-1, 1):
            ball((sign * .27, 0, .74), (.25, .78, .13), "stone", "upper_arm_l" if sign < 0 else "upper_arm_r")
    else:
        ball((0, 0, .63), (.57, .71, .29), torso_colour, "spine")
        box((0, 0, .45), (.45, .58, .14), "slate_blue", "hips")
        ball((0, 0, .895), (.51, .65, .21), "skin", "head")
        ball((0, .035, .96), (.53, .66, .08), "ink", "head")
        box((0, -.36, .73), (.11, .015, .055), "cream", "spine")
    rod((0, 0, .76), (0, 0, .85), .12, head_colour, "neck")
    for sign, side in ((-1, "l"), (1, "r")):
        rod((sign * .27, 0, .75), (sign * .40, 0, .64), .065 if identity == "S55" else .08,
            torso_colour, "upper_arm_" + side)
        rod((sign * .40, 0, .64), (sign * .43, 0, .51), .045 if identity == "S55" else .075,
            head_colour, "forearm_" + side)
        ball((sign * .43, 0, .51), (.14, .21, .075), head_colour, "hand_" + side)
        rod((sign * .13, 0, .43), (sign * .13, 0, .24), .05 if identity == "S55" else .085,
            "leaf" if identity == "S55" else "slate_blue", "thigh_" + side)
        rod((sign * .13, 0, .24), (sign * .13, 0, .06), .045 if identity == "S55" else .07,
            head_colour, "shin_" + side)
        box((sign * .13, -.07, .03), (.21, .56, .06), "slate_blue", "foot_" + side)
        ball((sign * .105, -.315, .906), (.045, .04, .025), "ink", "head")
    box((0, -.35, .867), (.08, .01, .010), "ink", "head")
    # Bounds belong to the registered physical body, never a universal proxy.
    fit_body(mesh, record["body"])
    mesh.create("core_" + identity.lower() + "_body", rig)
    animate_body(rig)
    return rig


def fit_body(mesh, body):
    minimum = [min(vertex[axis] for vertex in mesh.vertices) for axis in range(3)]
    maximum = [max(vertex[axis] for vertex in mesh.vertices) for axis in range(3)]
    target = (body["width_m"], body["depth_m"], body["height_m"])
    factors = [target[axis] / (maximum[axis] - minimum[axis]) for axis in range(3)]
    mesh.vertices = [((vertex[0] - (minimum[0] + maximum[0]) / 2) * factors[0],
                      (vertex[1] - (minimum[1] + maximum[1]) / 2) * factors[1],
                      (vertex[2] - minimum[2]) * factors[2]) for vertex in mesh.vertices]


def build_nonbiped(record):
    identity = record["id"]
    w, d, h = (record["body"][key] for key in ("width_m", "depth_m", "height_m"))
    rig = make_armature("core_" + identity.lower() + "_rig", body_rig(w, d, h, record["rig"]))
    mesh = MeshBuilder()
    if identity == "S21":
        mesh.rod((0, 0, .03), (0, 0, .17), w / 2, "clinic_blue", "root", sides=12)
        mesh.rod((0, 0, .17), (0, 0, .22), w * .46, "cream", "root", sides=12)
        for index in range(5):
            angle = index * math.tau / 5
            mesh.ellipsoid((math.cos(angle) * .19, math.sin(angle) * .19, .29),
                           (.15, .12, .13), "coral" if index % 2 else "gold", "head", segments=6)
        mesh.rod((.20, .12, .2), (.20, .12, .82), .025, "slate_blue", "root")
        mesh.box((.20, .10, .85), (.28, .06, .30), "cream", "head")
        mesh.ellipsoid((.17, .06, .89), (.055, .03, .045), "ink", "head", segments=6)
        mesh.ellipsoid((.24, .06, .89), (.055, .03, .045), "ink", "head", segments=6)
        mesh.box((.205, .06, .81), (.08, .015, .015), "coral", "head")
        for sign, side in ((-1, "l"), (1, "r")):
            mesh.rod((sign * .27, -.07, .15), (sign * .27, -.07, .45), .025, "slate_blue", "hand_" + side)
            mesh.ellipsoid((sign * .27, -.07, .45), (.10, .10, .10), "coral", "hand_" + side)
        rig["colony_is_one_actor"] = True
        rig["carrier_included_in_body"] = True
    else:
        # One bell-shaped translucent body and an opaque face surface.
        levels = ((0.0, .25), (.18, .50), (.43, .44), (.70, .37), (.92, .22), (1.0, .01))
        vertices = []
        sides = 12
        for level, radius in levels:
            for index in range(sides):
                angle = index * math.tau / sides
                scallop = (.028 * h * (1 + math.cos(index * math.pi))) if level == 0 else 0
                vertices.append((math.cos(angle) * radius * w, math.sin(angle) * radius * d,
                                 level * h + scallop))
        faces = []
        for row in range(len(levels) - 1):
            for index in range(sides):
                following = (index + 1) % sides
                faces.append((row * sides + index, row * sides + following,
                              (row + 1) * sides + following, (row + 1) * sides + index))
        faces.extend((tuple(reversed(range(sides))), tuple(range((len(levels) - 1) * sides, len(levels) * sides))))
        mesh.part(vertices, faces, "ghost", "spine")
        for sign, side in ((-1, "l"), (1, "r")):
            mesh.ellipsoid((sign * .17, -.24, 1.15), (.075, .035, .115), "ink", "head", segments=6, surface=1)
            mesh.ellipsoid((sign * .32, 0, .79), (.16, .24, .16), "ghost", "hand_" + side)
        mesh.ellipsoid((0, -.27, 1.03), (.06, .02, .04), "ink", "head", segments=6, surface=1)
        rig["required_original_pipeline"] = "alpha_blend_sorting"
    fit_body(mesh, record["body"])
    mesh.create("core_" + identity.lower() + "_body", rig, identity == "S14")
    animate_body(rig, record["rig"])
    return rig


def animate_body(armature, kind="biped"):
    animations = ("idle", "walk", "sit", "notice", "talk", "cheer", "upset",
                  "recover", "interact", "symptom", "work", "pause", "recovery", "low_motion")
    for name in animations:
        action = bpy.data.actions.new(name)
        armature.animation_data_create()
        armature.animation_data.action = action
        for step, frame in enumerate((1, 16, 31, 46, 61)):
            wave = math.sin(step * math.pi / 2)
            for bone in armature.pose.bones:
                bone.rotation_euler = (0, 0, 0)
                bone.location = (0, 0, 0)
                bone.scale = (1, 1, 1)
            head = armature.pose.bones["head"]
            # Local Y is the bone axis: yaw without changing body height.
            head.rotation_euler.y = wave * (.13 if name in ("notice", "talk", "symptom") else .04)
            for sign, side in ((-1, "l"), (1, "r")):
                arm = armature.pose.bones["upper_arm_" + side]
                if name in ("work", "interact", "pause", "low_motion"):
                    arm.rotation_euler.x = -.18 + (.05 * wave if name in ("work", "interact") else 0)
                elif name in ("recover", "recovery", "cheer"):
                    arm.rotation_euler.x = -.15 + sign * .06 * wave
                elif name == "symptom":
                    arm.rotation_euler.x = -.10 + .025 * wave
                elif name == "walk" and kind == "biped":
                    arm.rotation_euler.x = -.06 + sign * .025 * wave
                    # A modest cartoon step lifts the foot inside its physical
                    # body envelope; forward travel belongs to the world actor.
                    thigh = armature.pose.bones["thigh_" + side]
                    height = max(bone.head_local.z for bone in armature.data.bones if bone.name == "head") / .85
                    thigh.location = thigh.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, max(0, sign * wave) * .025 * height))
                elif name == "upset":
                    arm.rotation_euler.x = -.07
                elif name == "sit" and kind == "biped":
                    armature.pose.bones["thigh_" + side].rotation_euler.x = -.9
                    armature.pose.bones["shin_" + side].rotation_euler.x = .9
                else:
                    arm.rotation_euler.x = -.025 + .012 * wave
                if kind in ("micro", "float"):
                    armature.pose.bones["hand_" + side].rotation_euler.x = -.04 + .02 * wave if name in ("walk", "work", "symptom") else 0
            if name in ("pause", "low_motion"):
                head.rotation_euler.y = .04
            for bone in armature.pose.bones:
                if bone.name != "root":
                    bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
                    bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
        action["stage01_phase"] = name
        action["root_motion"] = False
    armature.animation_data.action = None
    for bone in armature.pose.bones:
        bone.rotation_euler = (0, 0, 0)
    bpy.context.scene.frame_set(1)


def machine_rig(identity, anchors):
    definitions = [("root", (0, 0, 0), (0, 0, .15), None)]
    for name, engine_point in anchors.items():
        source_point = (engine_point[0], -engine_point[2], engine_point[1])
        definitions.append((name, source_point, (source_point[0], source_point[1], source_point[2] + .12), "root"))
    windmill_depth = -2.70 if identity == "M37" else -1.40
    bag_depth = -2.75 if identity == "M37" else -1.25
    definitions.extend([
        ("windmill", (1.60, windmill_depth, 1.90), (1.60, windmill_depth, 2.08), "root"),
        ("cloud_bag", (.40, bag_depth, 1.5), (.40, bag_depth, 1.65), "root"),
        ("night_curtain", (1.8, -1.5, 2.0), (1.8, -1.5, 2.20), "root"),
        ("record_clip", (.35, -.35, 1.50), (.35, -.35, 1.65), "root"),
    ])
    return make_armature("core_" + identity.lower() + "_rig", definitions)


def build_machine(record):
    identity = record["id"]
    width, depth = (cells * CELL_METRES for cells in record["footprint"])
    if identity in ("M37", "M17"):
        anchors = {"patient_anchor": (.75, 0, depth + .75), "operator_anchor": (width + .75, 0, depth - .75),
                   "repair_anchor": (width - .75, 0, -.75), "effect_anchor": (.75, 1.65, depth + .75),
                   "camera_focus": (width / 2, 1.25, depth / 2),
                   "patient_support": (.75, .68, depth + .75), "symptom_target": (.75, 1.6, depth + .70),
                   "exit": (.75, 0, depth + 2.25)}
    else:
        anchors = {"patient_anchor": (width / 2, 1.04, depth / 2), "operator_anchor": (-.75, 0, 2.25),
                   "repair_anchor": (-.75, 0, .75 if identity == "EQ01" else 2.25),
                   "effect_anchor": (width / 2, 1.65, depth / 2), "camera_focus": (width / 2, 1.25, depth / 2),
                   "patient_support": (width / 2, 1.04, depth / 2), "symptom_target": (width / 2, 1.7, depth / 2),
                   "exit": (.75, 0, depth + .75)}
        if identity == "EQ01":
            anchors.update({"operator_surgeon": (-.75, 0, 2.25), "operator_anesthetist": (5.25, 0, .75),
                            "operator_nurse": (5.25, 0, 3.75)})
    rig = machine_rig(identity, anchors)
    mesh = MeshBuilder()
    mesh.box((width / 2, -depth / 2, .12), (width, depth, .24), "slate_blue", "root")
    if identity in ("M37", "M17"):
        # The seat uses the real adjacent patient reservation, not machine base cells.
        mesh.box((.75, -(depth + .75), .46), (.96, 1.00, .24), "clinic_blue", "patient_support")
        mesh.ellipsoid((.75, -(depth + .75), .59), (.96, 1.00, .18), "cream", "patient_support")
        mesh.box((.75, -(depth + 1.18), 1.03), (.92, .12, .74), "coral", "patient_support")
        for x in (.37, 1.13):
            mesh.rod((x, -(depth + .45), .03), (x, -(depth + .45), .36), .055, "slate_blue", "patient_support")
    if identity == "M37":
        # Rounded climate hood, scarf rail, and a clearly readable toy windmill.
        mesh.ellipsoid((1.5, -1.2, 1.25), (2.55, 1.8, 2.15), "clinic_blue", "root", segments=10)
        mesh.box((.65, -2.20, .90), (1.05, .75, .65), "cream", "root")
        mesh.ellipsoid((.75, -2.48, 1.37), (.90, .20, .85), "coral", "root")
        mesh.box((1.62, -2.33, 1.2), (.30, .16, .35), "slate_blue", "root")
        for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
            centre = (1.60 + math.cos(angle) * .30, -2.72, 1.90 + math.sin(angle) * .30)
            mesh.ellipsoid(centre, (.35, .10, .35), "gold", "windmill", segments=6)
        mesh.ellipsoid((.40, -2.75, 1.50), (.55, .36, .50), "cream", "cloud_bag")
        mesh.box((2.5, -2.2, 1.18), (.38, .32, .14), "coral", "root")
    elif identity == "M17":
        # Loom frame and a night-sky curtain, rather than a generic cabinet.
        mesh.box((1.5, -1.5, .77), (2.60, 2.50, .25), "clinic_blue", "root")
        for x in (.35, 2.65):
            mesh.rod((x, -.50, .30), (x, -.50, 2.65), .12, "slate_blue", "root")
        mesh.rod((.35, -.50, 2.60), (2.65, -.50, 2.60), .10, "gold", "root")
        mesh.box((1.80, -1.50, 2.0), (1.15, .08, 1.0), "night", "night_curtain")
        for x, z in ((1.5, 2.2), (1.95, 1.8), (2.13, 2.30)):
            mesh.ellipsoid((x, -1.56, z), (.08, .03, .08), "gold", "night_curtain", segments=6)
        for x in (.75, 1.0, 1.25):
            mesh.rod((x, -.60, 1.0), (x, -2.20, 1.0), .014, "cream", "root", sides=4)
        mesh.ellipsoid((.55, -1.15, 1.25), (.55, .34, .40), "cream", "cloud_bag")
        mesh.box((2.40, -2.05, 1.05), (.40, .38, .14), "coral", "root")
    else:
        # Stable patient support with bedside records; all operating tools remain soft/toy-like.
        for x in (1.1, 3.4):
            for y in (-.80, -3.7):
                mesh.rod((x, y, .2), (x, y, .8), .10, "clinic_blue", "root")
        mesh.box((2.25, -2.25, .81), (2.75, 3.75, .30), "clinic_blue", "root")
        mesh.box((2.25, -2.25, 1.0), (2.45, 3.45, .08), "cream", "root")
        mesh.ellipsoid((2.25, -1.0, 1.15), (1.6, .60, .30), "coral", "root")
        for x in (.93, 3.57):
            mesh.rod((x, -.55, 1.35), (x, -3.8, 1.35), .055, "slate_blue", "root")
        mesh.box((.35, -.35, 1.50), (.48, .09, .60), "cream", "record_clip")
        mesh.box((.35, -.41, 1.55), (.26, .025, .05), "coral", "record_clip")
        if identity == "EQ01":
            mesh.rod((3.95, -.70, .3), (3.95, -.70, 2.65), .10, "slate_blue", "root")
            mesh.rod((3.95, -.70, 2.65), (2.25, -1.6, 2.65), .09, "slate_blue", "root")
            mesh.ellipsoid((2.25, -1.6, 2.48), (.85, .85, .25), "gold", "root", segments=10)
            mesh.box((1.80, -1.50, 2.0), (.72, .045, .60), "night", "night_curtain")
            mesh.ellipsoid((1.80, -1.55, 2.0), (.38, .03, .26), "cream", "night_curtain", segments=6)
            mesh.ellipsoid((.40, -1.25, 1.50), (.35, .28, .40), "cream", "cloud_bag")
        else:
            mesh.box((3.9, -3.95, 1.10), (.65, .16, .72), "slate_blue", "root")
            mesh.box((3.9, -4.05, 1.15), (.48, .025, .37), "clinic_blue", "root")
    mesh.create("core_" + identity.lower() + "_machine", rig)
    animate_machine(rig)
    rig["local_origin"] = "registered_base_top_left_ground"
    rig["clinical_beat_source"] = "treatment_routines_or_treatment_plan"
    return rig


def animate_machine(armature):
    for name in ("idle", "work", "pause", "recovery", "low_motion",
                 "prepare", "process", "climax", "safe_finish"):
        armature.animation_data_create()
        armature.animation_data.action = bpy.data.actions.new(name)
        for step, frame in enumerate((1, 16, 31, 46, 61)):
            wave = math.sin(step * math.pi / 2)
            for bone in armature.pose.bones:
                bone.rotation_euler = (0, 0, 0)
            if name in ("work", "process", "climax"):
                armature.pose.bones["windmill"].rotation_euler.z = (frame - 1) / 60 * math.tau
                armature.pose.bones["night_curtain"].rotation_euler.y = .07 * wave
                armature.pose.bones["cloud_bag"].rotation_euler.x = .10 * wave
            elif name in ("prepare", "safe_finish", "recovery"):
                armature.pose.bones["record_clip"].rotation_euler.x = .06 * wave
            for name_ in ("windmill", "cloud_bag", "night_curtain", "record_clip"):
                armature.pose.bones[name_].keyframe_insert(data_path="rotation_euler", frame=frame, group=name_)
        armature.animation_data.action["root_motion"] = False
    armature.animation_data.action = None
    for bone in armature.pose.bones:
        bone.rotation_euler = (0, 0, 0)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 61


def export_asset(root, name):
    source = root / "art-source" / (name + ".blend")
    target = root / "assets" / "models" / (name + ".glb")
    source.parent.mkdir(parents=True, exist_ok=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_yup=True,
                              export_extras=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_skins=True, export_all_influences=False,
                              export_normals=True, export_tangents=True,
                              export_materials="EXPORT", export_def_bones=False,
                              export_cameras=False, export_lights=False,
                              export_optimize_animation_size=False)
    print("ASSET_EXPORTED=" + name + ";BYTES=" + str(target.stat().st_size), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    root = args.root.resolve()
    catalog = json.loads((root / "docs/data/content-catalog.json").read_text(encoding="utf-8-sig"))
    for identity in ("S49", "S21", "S59", "S55", "S14"):
        reset_scene()
        record = next(row for row in catalog["species"] if row["id"] == identity)
        build_nonbiped(record) if identity in ("S21", "S14") else build_biped(record)
        export_asset(root, "core_" + identity.lower() + "_body")
    for identity in ("M37", "M17", "EQ01", "EQ05"):
        reset_scene()
        record = next(row for row in catalog["machines"] + catalog["clinical_equipment"] if row["id"] == identity)
        build_machine(record)
        export_asset(root, "core_" + identity.lower() + "_machine")
    print("BLENDER_SOURCE_EXPORT_PASS=9", flush=True)


if __name__ == "__main__":
    main()
