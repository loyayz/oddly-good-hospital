"""Blender-native low-poly modelling, rigid skinning and glTF delivery.

Geometry comes from Blender operators, bevels and curves. No custom primitive
mesher or animation exporter is used. Source -Y is front; Z is up; metres.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PALETTE = {
    "ivory": (.91, .85, .72, 1), "white": (.97, .95, .89, 1),
    "wood": (.58, .32, .13, 1), "honey": (.85, .59, .25, 1),
    "teal": (.22, .51, .49, 1), "aqua": (.53, .75, .71, 1),
    "blue": (.36, .53, .68, 1), "navy": (.08, .16, .24, 1),
    "ink": (.035, .055, .065, 1), "coral": (.83, .30, .22, 1),
    "rose": (.80, .43, .46, 1), "purple": (.48, .34, .63, 1),
    "lavender": (.69, .61, .80, 1), "leaf": (.24, .46, .15, 1),
    "mint": (.48, .68, .37, 1), "yellow": (.98, .73, .15, 1),
    "orange": (.90, .40, .10, 1), "skin": (.77, .50, .31, 1),
    "stone": (.44, .48, .48, 1), "silver": (.65, .72, .72, 1),
    "brown": (.31, .16, .085, 1), "red": (.66, .11, .13, 1),
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1
    scene.render.fps = 24
    scene.frame_start, scene.frame_end = 1, 49
    bpy.context.preferences.filepaths.save_version = 0


def vertex_material(alpha=False):
    name = "hospital_vertex_alpha" if alpha else "hospital_vertex_opaque"
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .78
    shader.inputs["Specular IOR Level"].default_value = .22
    color = material.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Col"
    material.node_tree.links.new(color.outputs["Color"], shader.inputs["Base Color"])
    material.use_backface_culling = True
    if alpha:
        shader.inputs["Alpha"].default_value = .42
        material.surface_render_method = "DITHERED"
        material.use_transparency_overlap = False
    return material


class Model:
    def __init__(self, face_rig=False):
        self.parts = []
        self.face_rig = face_rig
        self.face_bones = []

    def finish(self, obj, name, color, bone="root", alpha=False):
        obj.name = name
        bpy.context.view_layer.objects.active = obj
        if obj.type != "MESH":
            bpy.ops.object.convert(target="MESH")
            obj = bpy.context.object
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        rgba = PALETTE[color] if isinstance(color, str) else color
        attribute = obj.data.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        attribute.data.foreach_set("color", list(rgba) * len(attribute.data))
        obj.data.materials.clear()
        obj.data.materials.append(vertex_material(alpha))
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
        obj["semantic_part"] = name
        self.parts.append(obj)
        return obj

    def ball(self, name, center, size, color, bone="spine", alpha=False, segments=12, rings=6):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
        obj = bpy.context.object
        obj.scale = tuple(v / 2 for v in size)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        return self.finish(obj, name, color, bone, alpha)

    def box(self, name, center, size, color, bone="root", bevel=.035):
        bpy.ops.mesh.primitive_cube_add(size=1, location=center)
        obj = bpy.context.object
        obj.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel:
            modifier = obj.modifiers.new("SoftToyEdges", "BEVEL")
            modifier.width = min(bevel, min(size) * .22)
            modifier.segments = 1
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        return self.finish(obj, name, color, bone)

    def rod(self, name, start, end, radius, color, bone="root", tip_radius=None, vertices=10):
        start, end = Vector(start), Vector(end)
        length = (end - start).length
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
                                       radius2=radius if tip_radius is None else tip_radius,
                                       depth=length, location=(start + end) / 2)
        obj = bpy.context.object
        obj.rotation_euler = (end - start).to_track_quat("Z", "Y").to_euler()
        for polygon in obj.data.polygons:
            polygon.use_smooth = len(polygon.vertices) == 4
        return self.finish(obj, name, color, bone)

    def ring(self, name, center, radius, tube, color, bone="root", rotation=(0, 0, 0)):
        bpy.ops.mesh.primitive_torus_add(major_segments=16, minor_segments=5,
                                       major_radius=radius, minor_radius=tube, location=center,
                                       rotation=rotation)
        return self.finish(bpy.context.object, name, color, bone)

    def line(self, name, points, radius, color, bone="root", cyclic=False):
        curve = bpy.data.curves.new(name, "CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 2
        curve.bevel_depth, curve.bevel_resolution = radius, 0
        spline = curve.splines.new("BEZIER")
        spline.bezier_points.add(len(points) - 1)
        for point, value in zip(spline.bezier_points, points):
            point.co = value
            point.handle_left_type = point.handle_right_type = "AUTO"
        spline.use_cyclic_u = cyclic
        obj = bpy.data.objects.new(name, curve)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        return self.finish(obj, name, color, bone)

    def polygon(self, name, points, color, bone="root", thickness=.03):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(points, [], [tuple(range(len(points)))])
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        solid = obj.modifiers.new("PaperThickness", "SOLIDIFY")
        solid.thickness = thickness
        bpy.ops.object.modifier_apply(modifier=solid.name)
        return self.finish(obj, name, color, bone)

    def star(self, name, center, radius, color, bone="head", points=5):
        x, y, z = center
        vertices = [(x + math.sin(i * math.pi / points) * radius * (1 if i % 2 == 0 else .47),
                     y, z + math.cos(i * math.pi / points) * radius * (1 if i % 2 == 0 else .47))
                    for i in range(points * 2)]
        return self.polygon(name, list(reversed(vertices)), color, bone, radius * .40)

    def face(self, center, width=.25, bone="head", eyes=2):
        x, y, z = center
        for i in range(eyes):
            xx = x + (i - (eyes - 1) / 2) * width * .6
            eye_bone=bone
            if self.face_rig:
                eye_bone=f"eye_{len(self.face_bones):02}"
                self.face_bones.append((eye_bone,(xx,y,z),bone))
            self.ball("Eye", (xx, y, z), (width * .20, .035, width * .27), "ink", eye_bone, segments=8, rings=4)
            self.ball("EyeGlint", (xx - width * .024, y - .017, z + width * .040),
                      (width * .052, .014, width * .055), "white", eye_bone, segments=6, rings=3)
        self.line("Smile", [(x - width * .13, y, z - width * .32),
                            (x, y - .005, z - width * .38),
                            (x + width * .13, y, z - width * .32)], .009, "ink", bone)

    def join(self, name, budget=None):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in self.parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = self.parts[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        if budget:
            decimate(obj, budget)
        self.parts = [obj]
        return obj


def triangle_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def decimate(obj, budget):
    count = triangle_count(obj)
    if count <= budget:
        return
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("BlenderLOD", "DECIMATE")
    modifier.ratio = max(.01, (budget - 16) / count)
    modifier.use_collapse_triangulate = True
    while obj.modifiers.find(modifier.name) > 0:
        bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.validate(clean_customdata=False)
    if triangle_count(obj) > budget:
        raise ValueError(f"Triangle budget not met: {obj.name} {triangle_count(obj)}>{budget}")


def armature(name, definitions):
    bpy.ops.object.select_all(action="DESELECT")
    obj = bpy.data.objects.new(name, bpy.data.armatures.new(name + "_bones"))
    bpy.context.collection.objects.link(obj)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for identity, head, parent in definitions:
        bone = obj.data.edit_bones.new(identity)
        bone.head, bone.tail = head, (head[0], head[1], head[2] + .05)
        if parent:
            bone.parent = obj.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in obj.pose.bones:
        bone.rotation_mode = "XYZ"
    obj["root_motion"] = False
    obj["source_units"] = "metres"
    return obj


def skin(mesh, rig):
    modifier = mesh.modifiers.new("HospitalSkin", "ARMATURE")
    modifier.object = rig
    mesh.parent = rig
    missing = {group.name for group in mesh.vertex_groups} - set(rig.data.bones.keys())
    if missing:
        raise ValueError("Mesh groups without bones: " + str(missing))


def actions(rig, names, pose):
    rig.animation_data_create()
    for identity in names:
        action = bpy.data.actions.new(identity)
        action.use_fake_user = True
        action["root_motion"] = False
        rig.animation_data.action = action
        for frame in (1, 13, 25, 37, 49):
            for bone in rig.pose.bones:
                bone.rotation_euler = (0, 0, 0)
                bone.location = (0, 0, 0)
                bone.scale = (1, 1, 1)
            pose(identity, (frame - 1) / 48, rig.pose.bones)
            for bone in rig.pose.bones:
                if bone.name == "root":
                    continue
                for prop in ("rotation_euler", "location", "scale"):
                    bone.keyframe_insert(data_path=prop, frame=frame, group=bone.name)
        if rig.pose.bones["root"].location.length > 1e-6:
            raise ValueError("Root motion")
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)
    bpy.context.scene.frame_set(1)


def export_glb(target: Path, objects=None):
    target.parent.mkdir(parents=True, exist_ok=True)
    if objects:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_yup=True,
        export_extras=True, export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_skins=True, export_all_influences=False,
        export_normals=True, export_materials="EXPORT", export_def_bones=False,
        export_cameras=False, export_lights=False, export_optimize_animation_size=True,
        use_selection=bool(objects))


def save_blend(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)


def engine_point(p):
    return [round(float(p[0]), 6), round(float(p[2]), 6), round(float(-p[1]), 6)]


def glb_metadata(path: Path):
    import struct
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        raise ValueError("Not a binary glTF: " + str(path))
    length = struct.unpack_from("<I", raw, 12)[0]
    data = json.loads(raw[20:20 + length])
    meshes = data.get("meshes", [])
    primitives = [p for mesh in meshes for p in mesh["primitives"]]
    accessors = data.get("accessors", [])
    materials = data.get("materials", [])
    surfaces = [{"mesh": mesh["name"], "material": materials[p.get("material", 0)]["name"],
                 "alpha_mode": materials[p.get("material", 0)].get("alphaMode", "OPAQUE"),
                 "triangles": accessors[p["indices"]]["count"] // 3}
                for mesh in meshes for p in mesh["primitives"]]
    joints = data.get("skins", [{}])[0].get("joints", [])
    return {"sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw),
            "surfaces": surfaces, "surface_count": len(primitives),
            "triangles": sum(p["triangles"] for p in surfaces),
            "joint_order": [data["nodes"][i]["name"] for i in joints],
            "bone_count": len(joints),
            "animation_names": [a["name"] for a in data.get("animations", [])]}


def render_preview(path: Path, mesh, width=384, yaw=45):
    scene = bpy.context.scene
    bounds = [mesh.matrix_world @ Vector(corner) for corner in mesh.bound_box]
    low = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    center, span = (low + high) / 2, max(high - low)
    bpy.ops.object.camera_add(location=center + Vector((1.6, -2, 1.5)) * max(span, .5))
    camera = bpy.context.object
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type, camera.data.ortho_scale = "ORTHO", max(span, .5) * 1.25
    scene.camera = camera
    lights = []
    for offset, energy, size in (((-3, -4, 6), 850, 5), ((4, -1, 3), 500, 4)):
        bpy.ops.object.light_add(type="AREA", location=center + Vector(offset) * max(span, .5))
        light = bpy.context.object
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
        light.data.energy, light.data.shape, light.data.size = energy * max(span, .5) ** 2, "DISK", size * max(span, .5)
        lights.append(light)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12
    scene.render.resolution_x = scene.render.resolution_y = width
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.77, .80, .82, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .3
    path.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    for obj in [camera] + lights:
        bpy.data.objects.remove(obj, do_unlink=True)
