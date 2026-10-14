"""Original Stage 01 case props; Blender 4.5.14 LTS, metres, Z up.

The root stays at its external semantic slot. Named child nodes contain
only display transforms, never actors, game clocks, or treatment results.
"""

import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from build_stage01 import MeshBuilder, make_material


def empty(name, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    obj.rotation_mode = "XYZ"
    return obj


def mesh(name, geometry, parent, transparent=False):
    data = bpy.data.meshes.new(name + "_mesh")
    data.from_pydata(geometry.vertices, [], geometry.faces)
    data.update()
    colours = data.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    uv = data.uv_layers.new(name="UVMap")
    for polygon in data.polygons:
        for corner, loop_index in enumerate(polygon.loop_indices):
            colours.data[loop_index].color = geometry.colours[data.loops[loop_index].vertex_index]
            uv.data[loop_index].uv = ((0, 0), (1, 0), (0, 1))[corner]
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    material = make_material("gag_projection" if transparent else "gag_vertex_colour", transparent)
    if transparent:
        material.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = .22
    data.materials.append(material)
    return obj


def geometry():
    return MeshBuilder()


def set_default(obj, location=None, rotation=None, scale=None):
    if location is not None:
        obj.location = location
    obj.rotation_euler = rotation if rotation is not None else (0, 0, 0)
    obj.scale = scale if scale is not None else (1, 1, 1)


def clip(name, nodes, pose, duration=2.0):
    end = 1 + round(duration * 30)
    frames = (1, 1 + round((end - 1) * .25), 1 + round((end - 1) * .5),
              1 + round((end - 1) * .75), end)
    for node in nodes:
        node.animation_data_create()
        node.animation_data.action = bpy.data.actions.new(name + "_" + node.name)
    for frame in frames:
        progress = (frame - 1) / (end - 1)
        pose(progress)
        for node in nodes:
            for path in ("location", "rotation_euler", "scale"):
                node.keyframe_insert(data_path=path, frame=frame)
    for node in nodes:
        action = node.animation_data.action
        slot = node.animation_data.action_slot
        track = node.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.action_slot = slot
        strip.blend_type = "REPLACE"
        strip.extrapolation = "NOTHING"
        track.mute = True
        node.animation_data.action = None
    pose(0)


def tissue():
    root = empty("case_d37_tissue")
    root["attach_slot"] = "hand_l"
    root["binding_id"] = "B_S49_D37_M37"
    paper = geometry()
    paper.box((.045, -.005, .025), (.09, .022, .05), "cream", None)
    paper.box((.044, -.018, .021), (.073, .003, .004), "clinic_blue", None)
    mesh("paper_body", paper, root)
    sail = empty("sail", root, (.035, 0, .035))
    flap = geometry()
    flap.part([(0, 0, 0), (.135, 0, .015), (.065, -.010, .18),
               (.07, -.004, .058)], [(0, 1, 3), (1, 2, 3), (2, 0, 3)], "cream", None)
    flap.part([(.004, -.002, .002), (.062, -.005, .022), (.044, -.009, .058)],
              [(0, 1, 2)], "clinic_blue", None)
    mesh("sail_mesh", flap, sail)
    grip = empty("grip", root)
    grip["remains_attached"] = True
    def pose(name, progress):
        wave = math.sin(progress * math.tau)
        if name in ("recovery", "recovery_hold", "low_motion_recovery"):
            fold = progress if name == "recovery" else 1
            factor = 1 - .94 * fold
            set_default(sail, rotation=(0, 1.25 * fold, 0), scale=(factor, factor, factor))
        elif name in ("symptom", "work", "short_loop"):
            set_default(sail, rotation=(.025 * wave, -.10, .04 * wave))
        else:
            set_default(sail, rotation=(0, -.10, 0))
    for name in ("symptom", "work", "paused", "recovery", "recovery_hold", "low_motion", "low_motion_recovery", "short_loop"):
        clip(name, [sail], lambda progress, name=name: pose(name, progress), 1 if name == "recovery" else 2)
    pose("symptom", 0)
    return root


def filter_device():
    root = empty("device_m37_filter")
    root["definition_id"] = "M37"
    root["attachment_engine_m"] = [1.5, 1.3, 1.5]
    fan = empty("fan", root, (-.55, -.95, .50))
    blades = geometry()
    for index in range(4):
        angle = index * math.pi / 2
        shape = ((.03, -.018, .02), (.24, -.018, .03), (.28, -.018, .16), (.085, -.034, .095))
        points = [(x * math.cos(angle) - z * math.sin(angle), y,
                   x * math.sin(angle) + z * math.cos(angle)) for x, y, z in shape]
        blades.part(points, [(0, 1, 3), (1, 2, 3)], "coral" if index % 2 else "gold", None)
    blades.ellipsoid((0, -.047, 0), (.09, .055, .09), "slate_blue", None, segments=6, rings=3)
    mesh("fan_blades", blades, fan)
    base = geometry()
    base.rod((-.55, -.93, .06), (-.55, -.93, .50), .018, "slate_blue", None, sides=6)
    base.box((-.55, -.93, .06), (.24, .16, .025), "clinic_blue", None)
    mesh("fan_stand", base, root)
    bag = empty("cloud_bag", root, (.74, -.80, .18))
    body = geometry()
    body.ellipsoid((0, 0, 0), (.44, .30, .40), "cream", None)
    body.box((0, -.145, -.025), (.20, .014, .13), "clinic_blue", None)
    mesh("bag_body", body, bag)
    cloud = empty("cloud", bag, (0, -.19, .14))
    cotton = geometry()
    for point, shape in (((-.12, 0, 0), (.20, .16, .15)), ((0, -.025, .04), (.24, .17, .20)), ((.13, 0, 0), (.19, .16, .15))):
        cotton.ellipsoid(point, shape, "cream", None, segments=6, rings=3)
    mesh("cotton_cloud", cotton, cloud)
    seal = empty("filter_seal", bag, (0, 0, .20))
    ties = geometry()
    ties.box((0, 0, 0), (.18, .20, .020), "coral", None)
    ties.box((0, -.035, .018), (.09, .10, .016), "gold", None)
    mesh("seal_ribbon", ties, seal)
    def pose(name, progress):
        if name in ("safe_finish", "recovery", "recovery_hold"):
            fraction = progress if name != "recovery_hold" else 1
            set_default(fan, rotation=(0, math.tau * (1 - fraction), 0))
            factor = 1 - .93 * fraction
            set_default(cloud, scale=(factor, factor, factor))
            factor = .30 + .70 * fraction
            set_default(seal, scale=(factor, factor, factor))
        elif name in ("work", "short_loop", "symptom"):
            set_default(fan, rotation=(0, math.tau * progress, 0))
            factor = .80 + .13 * math.sin(progress * math.tau)
            set_default(cloud, scale=(factor, factor, factor))
            set_default(seal, scale=(.30, .30, .30))
        else:
            set_default(fan, rotation=(0, math.pi / 4, 0))
            set_default(cloud, scale=(.80, .80, .80))
            set_default(seal, scale=(.30, .30, .30))
    for name in ("symptom", "work", "paused", "recovery", "recovery_hold", "safe_finish", "low_motion", "short_loop"):
        clip(name, [fan, cloud, seal], lambda progress, name=name: pose(name, progress))
    pose("paused", 0)
    return root


def sheep_mesh(parent, pillow=False):
    wool = geometry()
    wool.ellipsoid((0, 0, .005), (.14, .09, .085), "cream", None, segments=6, rings=3)
    for point in ((-.03, -.012, .035), (.025, -.012, .043)):
        wool.ellipsoid(point, (.074, .068, .056), "cream", None, segments=4, rings=3)
    wool.ellipsoid((.074, -.008, .020), (.056, .06, .072), "slate_blue", None, segments=6, rings=3)
    wool.box((.085, -.041, .035), (.020, .009, .014), "ink", None)
    wool.part([(.070, -.025, .05), (.053, -.065, .051), (.070, -.033, .025)], [(0, 1, 2)], "slate_blue", None)
    for x in (-.043, .038):
        for y in (-.027, .026):
            wool.box((x, y, -.049), (.014, .014, .035), "ink", None)
    mesh(parent.name + "_wool", wool, parent)
    if pillow:
        cushion = geometry()
        cushion.box((-.025, -.074, .004), (.072, .025, .055), "clinic_blue", None)
        cushion.box((-.024, -.089, .005), (.060, .004, .044), "cream", None)
        mesh("pillow", cushion, parent)


def dream():
    root = empty("case_d23_dream")
    root["attach_slot"] = "head"
    root["binding_id"] = "B_S49_D23_M23"
    root["projection_only"] = True
    bubble = empty("bubble", root, (0, 0, .50))
    shell = geometry()
    shell.ellipsoid((0, .025, .025), (.62, .12, .36), "ghost", None)
    mesh("bubble_shell", shell, bubble, transparent=True)
    fence = empty("dream_fence", bubble, (0, .055, 0))
    rails = geometry()
    for x in (-.20, -.067, .067, .20):
        rails.box((x, .018, -.058), (.016, .016, .105), "clinic_blue", None)
    rails.box((0, .014, -.055), (.44, .016, .014), "gold", None)
    rails.box((0, .014, -.016), (.44, .016, .014), "gold", None)
    mesh("dream_gate", rails, fence)
    positions = ((-.26, -.085, -.008), (-.015, -.075, .025), (.235, -.085, -.030))
    sheeps = [empty(name, bubble, location) for name, location in zip(("sheep", "sheep_2", "sheep_pillow"), positions)]
    for index, sheep in enumerate(sheeps):
        sheep_mesh(sheep, pillow=index == 2)
    stitches = empty("star_stitches", bubble)
    stars = geometry()
    for x, z in ((-.27, .09), (.255, .115)):
        stars.part([(x - .018, -.012, z), (x, -.012, z + .025), (x + .018, -.012, z), (x, -.012, z - .025)],
                   [(0, 1, 2), (0, 2, 3)], "gold", None)
    mesh("seam_stars", stars, stitches)
    seam = empty("closed_seam", root, (0, 0, .50))
    closure = geometry()
    closure.box((0, -.02, .016), (.22, .014, .018), "clinic_blue", None)
    closure.ellipsoid((0, -.035, .025), (.04, .025, .04), "gold", None, segments=6, rings=3)
    mesh("closed_seam_mesh", closure, seam)
    nodes = [bubble, fence, *sheeps, stitches, seam]
    def pose(name, progress):
        for sheep, location in zip(sheeps, positions):
            set_default(sheep, location=location)
        set_default(bubble)
        set_default(fence, scale=(.001, .001, .001))
        set_default(stitches, scale=(.001, .001, .001))
        set_default(seam, scale=(.001, .001, .001))
        if name in ("work", "awaiting_result", "low_motion_work"):
            set_default(fence)
            set_default(stitches)
            for index, (sheep, origin) in enumerate(zip(sheeps, positions)):
                fraction = max(0, min(1, (progress - index * .12) / .62)) if name == "work" else 1
                target = ((index - 1) * .18, .013, -.005)
                location = tuple(first + (second - first) * fraction for first, second in zip(origin, target))
                location = (location[0], location[1], location[2] + .008 * math.sin(fraction * math.pi))
                set_default(sheep, location=location)
        elif name in ("recovery", "recovery_hold", "low_motion_recovery"):
            fraction = progress if name == "recovery" else 1
            for index, sheep in enumerate(sheeps):
                set_default(sheep, location=((index - 1) * .18, .013, -.005))
            factor = 1 - .96 * fraction
            set_default(bubble, scale=(factor, factor, factor))
            factor = .001 + .999 * fraction
            set_default(seam, scale=(factor, factor, factor))
        elif name in ("symptom", "short_loop"):
            for index, (sheep, origin) in enumerate(zip(sheeps, positions)):
                set_default(sheep, location=(origin[0], origin[1], origin[2] + .006 * math.sin(progress * math.tau + index * .6)))
    for name in ("symptom", "work", "paused", "awaiting_result", "recovery", "recovery_hold", "low_motion", "low_motion_work", "low_motion_recovery", "short_loop"):
        clip(name, nodes, lambda progress, name=name: pose(name, progress), 1 if name == "recovery" else 2)
    pose("symptom", 0)
    return root


def export(root_path, name, build):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 61
    root = build()
    root["metres"] = True
    root["no_root_motion"] = True
    root["simulation_entities"] = 0
    source = root_path / "art-source/gags" / (name + ".blend")
    target = root_path / "assets/gags" / (name + ".glb")
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_yup=True,
                              export_extras=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_merge_animation="NLA_TRACK", export_force_sampling=True,
                              export_anim_slide_to_zero=True,
                              export_normals=True, export_tangents=True,
                              export_optimize_animation_keep_anim_object=True,
                              export_optimize_animation_size=False, export_cameras=False, export_lights=False)
    print("GAG_EXPORTED=" + name + ";BYTES=" + str(target.stat().st_size), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    root = args.root.resolve()
    for name, factory in (("case_d37_tissue", tissue), ("device_m37_filter", filter_device), ("case_d23_dream", dream)):
        export(root, name, factory)
    print("BLENDER_GAG_EXPORT_PASS=3", flush=True)


if __name__ == "__main__":
    main()
