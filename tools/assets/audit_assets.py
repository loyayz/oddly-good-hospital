"""Independent file, glTF, PNG, source and engine-evidence checks."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

from PIL import Image
from catalog import load_catalog,resource_plan,write_json


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def gltf(path):
    raw=path.read_bytes()
    magic,version,size=struct.unpack_from("<4sII",raw)
    if magic!=b"glTF" or version!=2 or size!=len(raw):raise ValueError("Invalid GLB header: "+str(path))
    length=struct.unpack_from("<I",raw,12)[0]
    return json.loads(raw[20:20+length])


def main():
    p=argparse.ArgumentParser();p.add_argument("--root",type=Path,required=True);a=p.parse_args();root=a.root.resolve()
    c=load_catalog(root);plan=resource_plan(c);errors=[];files={}
    published=json.loads((root/"assets/asset-plan.json").read_text(encoding="utf-8"))
    aliases=published.get("file_aliases",{})
    for requirement in plan["requirements"]:
        requirement["required_paths"]=[aliases.get(path,path) for path in requirement["required_paths"]]
    if aliases:plan["file_aliases"]=aliases
    for requirement in plan["requirements"]:
        for relative in requirement["required_paths"]:
            path=root/relative
            if not path.is_file() or path.stat().st_size==0:errors.append("Missing/empty required file: "+relative)
            else:files[relative]=path.stat().st_size
    model_index=json.loads((root/"assets/models/complete-production.json").read_text(encoding="utf-8"))
    all_models=[];bounds={"body_near":0,"body_common":0,"body_far":0,"furniture":0,"medical":0,"bones":0}
    for relative in sorted({str(p.relative_to(root)).replace("\\","/") for p in (root/"assets").rglob("*.glb") if "gags" not in p.parts}):
        path=root/relative;document=gltf(path);accessors=document.get("accessors",[])
        triangles=sum(accessors[primitive["indices"]]["count"]//3 for mesh in document.get("meshes",[]) for primitive in mesh["primitives"])
        bones=max((len(skin["joints"]) for skin in document.get("skins",[])),default=0)
        if triangles<=0:errors.append("Empty model: "+relative)
        if bones>40:errors.append("More than 40 bones: "+relative)
        for mesh in document.get("meshes",[]):
            for primitive in mesh["primitives"]:
                if "COLOR_0" not in primitive["attributes"]:errors.append("Missing vertex colors: "+relative)
        config=path.with_suffix(path.suffix+".import")
        if not config.exists() or 'import_script/path="res://assets/runtime/import_hospital_assets.gd"' not in config.read_text(encoding="utf-8"):
            errors.append("Portable import contract missing: "+relative)
        all_models.append({"path":relative,"bytes":path.stat().st_size,"triangles":triangles,"bones":bones,"sha256":sha(path)})
        bounds["bones"]=max(bounds["bones"],bones)
    for record in model_index["assets"]:
        relative=record["asset_path"]
        if sha(root/relative)!=record["asset_sha256"]:errors.append("Model index hash mismatch: "+relative)
        if sha(root/record["source_path"])!=record["source_sha256"]:errors.append("Editable source mismatch: "+relative)
        triangles=record["triangle_count"]
        if record["kind"]=="body":
            cap={"near":3000,"common":1500,"far":500}[record["lod"]]
            key="body_"+record["lod"]
        else:
            medical=record["content_id"] in ("FUR02","M09","M37","M17","EQ01","EQ05")
            cap=3000 if medical else 800;key="medical" if medical else "furniture"
        bounds[key]=max(bounds[key],triangles)
        if triangles>cap:errors.append("Triangle budget exceeded: "+relative)
        slots={"head","look_target","hand_l","hand_r","treatment_anchor","emotion_anchor","carry_anchor"} if record["kind"]=="body" else {"patient_anchor","operator_anchor","repair_anchor","effect_anchor","camera_focus"}
        if not slots.issubset(set(record["joint_order"])):errors.append("Semantic slots missing: "+relative)
    icons=[]
    for path in sorted((root/"assets/ui").rglob("*.png")):
        relative=path.relative_to(root).as_posix()
        with Image.open(path) as image:
            image.load();width,height=image.size
            if width>512 or height>512:errors.append("PNG resolution too large: "+relative)
        if path.stat().st_size>=50000:errors.append("PNG is not below 50,000 bytes: "+relative)
        icons.append({"path":relative,"bytes":path.stat().st_size,"width":width,"height":height,"sha256":sha(path)})
    cases=json.loads((root/"assets/cases/index.json").read_text(encoding="utf-8"))["cases"]
    if {r["id"] for r in cases}!={b["id"] for b in c["treatment_bindings"]}:errors.append("Case coverage mismatch")
    if {r["disease_id"] for r in cases}!={b["id"] for b in c["diseases"]}:errors.append("Disease coverage mismatch")
    audio=json.loads((root/"assets/audio/index.json").read_text(encoding="utf-8"))["clips"]
    for clip in audio:
        if clip["sample_rate"]!=48000 or clip["decoded_true_peak_dbfs"]>-1.0:errors.append("Audio format/headroom violation: "+clip["id"])
        if sha(root/clip["path"])!=clip["sha256"]:errors.append("Audio identity mismatch: "+clip["id"])
        if clip["kind"]=="music" and not 120<=clip["duration_seconds"]<=180:errors.append("Music length violation: "+clip["id"])
        if not (root/clip["source_path"]).is_file():errors.append("WAV source missing: "+clip["id"])
    from catalog import authored_scenes
    from design_assets import graphic_specs,validation_fingerprint
    presentations=json.loads((root/"assets/presentation/index.json").read_text(encoding="utf-8"))
    by_id={item["id"]:item for item in presentations["scenes"]}
    authored_count=0
    for collection,records in c.items():
        if not isinstance(records,list) or collection=="equipment":continue
        for record in records:
            if not isinstance(record,dict):continue
            represented=set(by_id.get(collection+":"+str(record.get("id")),{}).get("source_text",{}).values())
            for pointer,text in authored_scenes(record):
                authored_count+=1
                if text not in represented:errors.append("Authored scene not represented: "+collection+":"+str(record.get("id"))+pointer)
    supplement_index=json.loads((root/"assets/ui/supplement-index.json").read_text(encoding="utf-8"))
    expected={(item["group"],item["id"]) for item in graphic_specs(c)}
    if expected!={(item["group"],item["id"]) for item in supplement_index["graphics"]}:
        errors.append("Supplement UI definition coverage mismatch")
    for item in supplement_index["graphics"]:
        if sha(root/item["path"])!=item["sha256"]:errors.append("Supplement graphic hash mismatch: "+item["path"])
    supplement=json.loads((root/"art-source/production/validation/design-supplement.json").read_text(encoding="utf-8"))
    if supplement.get("native_validation",{}).get("failures",["missing evidence"]):
        errors.append("Supplement native verification has not passed")
    if supplement.get("resource_fingerprint")!=validation_fingerprint(root):
        errors.append("Supplement verification is stale")
    engine_path=root/"art-source/production/validation/godot-import.json"
    engine=json.loads(engine_path.read_text(encoding="utf-8")) if engine_path.exists() else {}
    if not engine or engine.get("failures"):errors.append("Godot validation has not passed")
    for key,path in (("model_manifest_sha256","assets/models/complete-production.json"),("case_index_sha256","assets/cases/index.json"),("factory_sha256","tools/assets/asset_factory.gd")):
        if engine.get(key)!=sha(root/path):errors.append("Engine evidence is stale: "+key)
    report={"schema":1,"status":"passed" if not errors else "failed","requirements":len(plan["requirements"]),
        "counts":plan["counts"],"unique_required_files":len(files),"required_bytes":sum(files.values()),
        "glb_files":len(all_models),"geometry_maxima":bounds,"png_count":len(icons),
        "png_max_bytes":max(r["bytes"] for r in icons),"png_total_bytes":sum(r["bytes"] for r in icons),
        "audio_files":len(audio),"music_seconds":sum(r["duration_seconds"] for r in audio if r["kind"]=="music"),
        "worst_audio_true_peak_dbfs":max(r["decoded_true_peak_dbfs"] for r in audio),
        "engine":engine,"source_hashes":c["source_hashes"],"errors":errors,
        "authored_scene_fields":authored_count,"supplement_graphic_definitions":len(expected),
        "supplement_native":supplement.get("native_validation",{}),
        "limits":{"gameplay_handoffs":"not tested; no experimental gameplay code changed",
            "performance":"geometry, files and actual backend previews; not 640-person full-hospital acceptance",
            "visual":"all 80 silhouettes, 77 equipment and 154 disease glyphs reviewed; representative animated backend views"}}
    write_json(root/"art-source/production/validation/asset-audit.json",report)
    write_json(root/"art-source/production/validation/glb-files.json",{"models":all_models})
    write_json(root/"art-source/production/validation/png-files.json",{"images":icons})
    if not errors:
        plan["validation"]={"static":"passed","godot_import":"passed","visual":"catalog contact sheets and representative actual Compatibility renders reviewed",
            "gameplay_handoffs":"not run; asset-only delivery","performance":"asset budgets checked; full-hospital acceptance not run"}
        write_json(root/"assets/asset-plan.json",plan)
        if not aliases:write_json(root/"art-source/production/resource-plan.json",plan)
    print(json.dumps({k:report[k] for k in ("status","requirements","counts","glb_files","geometry_maxima","png_count","png_max_bytes","audio_files","errors")},ensure_ascii=False))
    raise SystemExit(1 if errors else 0)


if __name__=="__main__":main()
