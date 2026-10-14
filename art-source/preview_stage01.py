"""Source-art contact sheets rendered from the exported GLBs.

Cycles CPU contact sheets are visual QA only, not Godot Compatibility or
game-performance acceptance evidence. They preserve the body sizes.
"""

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def render(root, kind, identities, positions, camera_position, target, scale):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for identity, position in zip(identities, positions):
        previous = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(root / "assets/models" / f"core_{identity}_{kind}.glb"))
        imported = set(bpy.data.objects) - previous
        for obj in imported:
            if obj.animation_data:
                obj.animation_data.action = None
            if obj.parent not in imported:
                obj.location += Vector(position)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new("WarmWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.66, .79, .83, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = .35
    bpy.ops.mesh.primitive_plane_add(size=70, location=(target[0], 0, -.01))
    floor = bpy.context.object
    material = bpy.data.materials.new("ContactSheetFloor")
    material.diffuse_color = (.91, .88, .81, 1)
    floor.data.materials.append(material)
    bpy.ops.object.light_add(type="AREA", location=(target[0] - 4, -8, 15))
    key = bpy.context.object
    key.data.energy = 1800
    key.data.size = 9
    key.rotation_euler = (Vector(target) - key.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=camera_position)
    camera = bpy.context.object
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scale
    scene.camera = camera
    scene.view_settings.view_transform = "Standard"
    output = root / "art-source/preview" / ("stage01-bodies.png" if kind == "body" else "stage01-machines.png")
    output.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    print("GLB_SOURCE_CONTACT_SHEET=" + output.relative_to(root).as_posix(), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    root = args.root.resolve()
    render(root, "body", ("s49", "s21", "s59", "s55", "s14"),
           ((0, 0, 0), (1.5, 0, 0), (5, 0, 0), (8.8, 0, 0), (10.6, 0, 0)),
           (14, -24, 16), (5.3, 0, 2.6), 15)
    render(root, "machine", ("m37", "m17", "eq01", "eq05"),
           ((0, 0, 0), (4.2, 0, 0), (8.4, 0, 0), (14.2, 0, 0)),
           (25, -25, 20), (9.3, -1.8, 1.0), 23)


if __name__ == "__main__":
    main()
