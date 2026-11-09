"""Reproducible Blender entry point for the complete content asset library."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from blender_common import (reset_scene, export_glb, save_blend, glb_metadata,
                            decimate, engine_point, render_preview)
from blender_bodies import body
from catalog import load_catalog, write_json, BODY_SLOTS, EQUIPMENT_SLOTS


def publish(root, identity, kind, mesh, rig, source_group, budgets, preview=False):
    noun = "body" if kind=="body" else "machine"
    stem=f"core_{identity.lower()}_{noun}"
    source=root/f"art-source/production/{source_group}/{stem}.blend"
    save_blend(source)
    anchors={bone.name:engine_point(bone.head_local) for bone in rig.data.bones
             if bone.name in (BODY_SLOTS if kind=="body" else EQUIPMENT_SLOTS)}
    for name in ("patient_support","symptom_target","exit"):
        if name in rig.data.bones: anchors[name]=engine_point(rig.data.bones[name].head_local)
    vertices=[engine_point(v.co) for v in mesh.data.vertices]
    bounds={"minimum_m":[min(v[i] for v in vertices) for i in range(3)],
            "maximum_m":[max(v[i] for v in vertices) for i in range(3)]}
    near_data=mesh.data.copy()
    records=[]
    for lod,budget in budgets:
        mesh.data=near_data.copy()
        decimate(mesh,budget)
        suffix="" if lod=="common" else "_"+lod
        target=root/f"assets/models/{stem}{suffix}.glb"
        export_glb(target,[mesh,rig])
        info=glb_metadata(target)
        if info["triangles"]>budget or info["bone_count"]>40:
            raise ValueError(f"Budget exceeded {identity}/{lod}")
        records.append({"content_id":identity,"kind":kind,"lod":lod,
            "asset_path":target.relative_to(root).as_posix(),
            "source_path":source.relative_to(root).as_posix(),
            "asset_sha256":info.pop("sha256"),"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
            "triangle_count":info["triangles"],"maximum_vertex_influences":1,
            "anchors_engine_local_m":anchors,"rest_mesh_bounds_engine_m":bounds,
            "no_root_motion":True,"source_rig":rig.get("rig_profile","equipment"),**info})
        if preview and lod=="common":
            render_preview(root/f".cache/asset-previews/{identity.lower()}.png",mesh)
    return records


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--root",type=Path,required=True)
    parser.add_argument("--kind",choices=("body","equipment","case","architecture","props","all"),default="all")
    parser.add_argument("--ids",default="")
    parser.add_argument("--preview",action="store_true")
    parser.add_argument("--resume",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    root=args.root.resolve(); catalog=load_catalog(root)
    wanted=set(args.ids.split(",")) if args.ids else None
    index=root/"assets/models/complete-production.json"
    existing=json.loads(index.read_text(encoding="utf-8")) if index.exists() else {"assets":[]}
    records={item["asset_path"]:item for item in existing["assets"]}
    jobs=[]
    if args.kind in ("body","all"):
        jobs.extend(("body",record) for record in catalog["species"])
    if args.kind in ("equipment","all"):
        jobs.extend(("equipment",record) for record in catalog["equipment"])
    for kind,record in jobs:
        if wanted is not None and record["id"] not in wanted: continue
        reset_scene()
        if kind=="body":
            mesh,rig=body(record)
            new=publish(root,record["id"],kind,mesh,rig,"bodies",(("near",3000),("common",1500),("far",500)),args.preview)
        else:
            from blender_equipment import equipment
            mesh,rig=equipment(record)
            budget=3000 if record.get("equipment_class")=="medical" or record["id"]=="FUR02" else 800
            new=publish(root,record["id"],kind,mesh,rig,"equipment",(("common",budget),("far",min(400,budget))),args.preview)
        for item in new: records[item["asset_path"]]=item
        write_json(index,{"schema":1,"source_tool":"Blender "+bpy.app.version_string,
            "generator":"tools/assets/build_models.py","units":"metres",
            "coverage":{"bodies":len({r["content_id"] for r in records.values() if r["kind"]=="body"}),
                        "machines":len({r["content_id"] for r in records.values() if r["kind"]=="equipment"}),
                        "source_rig_classes":sorted({r["source_rig"] for r in records.values() if r["kind"]=="body"}),
                        "lod":"actual near/common/far exports"},
            "assets":sorted(records.values(),key=lambda r:r["asset_path"])})
        print("COMPLETE_ASSET "+record["id"]+" "+str([(r["lod"],r["triangle_count"]) for r in new]),flush=True)
    if args.kind in ("case","all"):
        from blender_cases import build_cases
        build_cases(root,catalog,wanted,args.preview,args.resume)
    if args.kind in ("architecture","all"):
        from blender_equipment import build_architecture
        build_architecture(root,wanted)
    if args.kind in ("props","all"):
        from blender_cases import build_props
        build_props(root,catalog,wanted,args.preview)


if __name__=="__main__":main()
