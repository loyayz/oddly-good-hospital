"""Render close source-asset views from actual GLBs, with Cycles CPU."""

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def render(root, name, clip, seconds, target, camera_position, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    previous = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(root / "assets/gags" / (name + ".glb")))
    imported = set(bpy.data.objects) - previous
    matched = 0
    for obj in imported:
        if not obj.animation_data:
            continue
        obj.animation_data.action = None
        obj.animation_data.use_nla = False
        for track in obj.animation_data.nla_tracks:
            if track.name == clip:
                obj.animation_data.action = track.strips[0].action
                obj.animation_data.action_slot = track.strips[0].action_slot
                matched += 1
                break
    assert matched, f"Actual GLB preview clip missing: {name}/{clip}"
    scene.frame_set(round(seconds * 30))
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 900, 650
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new("SourcePreviewWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.55, .68, .73, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = .70
    bpy.ops.object.light_add(type="AREA", location=(target[0] - 1.5, -3, target[2] + 4))
    light = bpy.context.object
    light.data.energy = 100
    light.data.size = 3
    light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=camera_position)
    camera = bpy.context.object
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = size
    scene.camera = camera
    scene.view_settings.view_transform = "Standard"
    output = root / "art-source/gags/preview" / (name + "-" + clip + ".png")
    output.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    print("GAG_SOURCE_PREVIEW=" + output.relative_to(root).as_posix(), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    root = args.root.resolve()
    for clip, seconds in (("symptom", .50), ("recovery", 1.0)):
        render(root, "case_d37_tissue", clip, seconds, (.080, 0, .108), (.25, -.8, .32), .38)
    render(root, "device_m37_filter", "work", .50, (.07, -.90, .35), (.80, -4, 1.8), 2.15)
    for clip, seconds in (("symptom", .50), ("work", 1.5), ("recovery", 1.0)):
        render(root, "case_d23_dream", clip, seconds, (0, 0, .51), (.35, -1.8, .90), .82)


if __name__ == "__main__":
    main()
