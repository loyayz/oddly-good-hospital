"""Editable UI art and presentation supplements traced to authored design data."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import html
import json
from pathlib import Path
import shutil

from catalog import authored_scenes, load_catalog, write_json

INK = "#293e58"
BLUE = "#6686ac"
PALE = "#dce7f2"
PAPER = "#fffaf0"
GOLD = "#d5ad68"
CORAL = "#cb746a"
ROLES = {
    "doctor": "医生", "nurse": "护士", "receptionist": "接待员",
    "cleaner": "清洁员", "mechanic": "维修员",
    "researcher": "研究员", "decorator": "装修工",
}
PROFESSIONS = {"ordinary":"普通居民","gardener":"园艺师","mage":"法师",
               "priest":"牧师","merchant":"商贩","performer":"表演者"}
GROUPS = {
    "biographies": "staff_biographies", "titles": "doctor_titles",
    "work_styles": "staff_work_styles", "reasons": "journey_reason_cards",
    "queue": "queue_cues", "observation": "observation_cues",
    "onboarding": "onboarding_steps", "context": "context_lessons",
    "remodel": "remodel_guides", "tasks": "task_guides",
    "history": "history_templates", "finance": "finance_views",
    "chairs": "chair_variants", "cleanup": "cleanup_sources",
}
CARD_GROUPS = {
    "biographies", "work_styles", "reasons", "onboarding", "context",
    "remodel", "tasks", "history", "finance", "roles", "blueprints",
}


def graphic_specs(catalog):
    records = []
    for group, collection in GROUPS.items():
        for record in catalog[collection]:
            records.append({"group": group, "id": record["id"], "record": record,
                "name": record.get("name", record.get("text", record["id"])),
                "source": f"content/core/{collection}.json#{record['id']}"})
    for record in catalog["blueprint_presets"]:
        records.append({"group": "blueprints", "id": record["id"],
            "name": record["name"], "record": record,
            "source": "content/core/blueprint_presets.json#" + record["id"]})
    roles = sorted({role for adapter in catalog["staff_rig_adapters"] for role in adapter["roles"]})
    for role in roles:
        records.append({"group": "roles", "id": role, "name": ROLES[role],
            "record": {"name": ROLES[role]},
            "source": "content/core/staff_rig_adapters.json#roles/" + role})
    for profession,name in PROFESSIONS.items():
        records.append({"group":"professions","id":profession,"name":name,"record":{},
            "source":"docs/design/02-content.md#职业基础分布"})
    for cue in catalog["medical_progress_cues"]:
        for result in cue["result_scenes"]:
            records.append({"group": "results", "id": cue["id"] + "_" + result["state"],
                "name": result["label"], "record": result,
                "source": "content/core/medical_progress_cues.json#" + cue["id"] + "/result_scenes/" + result["state"]})
    states = ("idle", "working", "paused", "broken", "repairing", "maintenance",
              "construction", "using", "unavailable", "waiting", "reserved",
              "awaiting_recovery", "retry_ready", "final_failure", "cured")
    for state in states:
        records.append({"group": "states", "id": state, "name": state,
            "record": {}, "source": "docs/design/05-production.md#工作状态表现"})
    for connector in catalog["vertical_connectors"]:
        for field, text in connector["transit_cues"].items():
            if isinstance(text, str) and "scene" in field and "low_motion" not in field:
                records.append({"group": "transit", "id": connector["id"] + "_" + field,
                    "name": connector["name"], "record": {"description": text},
                    "source": "content/core/vertical_connectors.json#" + connector["id"] + "/transit_cues/" + field})
    for item in records:
        group = item["group"]; key = item["id"].lower()
        item["path"] = f"assets/ui/supplements/{group}/{key}.png"
        item["editable"] = (f"art-source/production/ui/{group}/{key}.svg" if group != "roles"
                            else "art-source/production/ui/render_role_portraits.gd")
        if group in CARD_GROUPS:
            item["card"] = f"assets/ui/cards/{group}/{key}.tscn"
    return records


def requirements(catalog):
    items = []
    for record in graphic_specs(catalog):
        paths = [record["path"], record["editable"]]
        if "card" in record:
            paths.append(record["card"])
        items.append({"kind": "ui_supplement", "id": record["group"] + ":" + record["id"],
            "name": record["name"], "required_paths": paths, "source": record["source"],
            "owner": "asset-production", "max_bytes": 50000})
    for name in ("source", "target", "valid", "blocked", "path_width", "path_height",
                 "owned_land", "buyable_land", "unowned_land", "construction", "selection"):
        items.append({"kind": "overlay", "id": name, "name": name,
            "required_paths": [f"assets/ui/overlays/{name}.tscn"],
            "source": "docs/design/03-experience.md#具体工作流", "owner": "asset-production"})
    for name in ("privacy_curtain", "soft_shadow"):
        items.append({"kind": "native_prop", "id": name, "name": name,
            "required_paths": [f"assets/props/library/{name}.tscn"],
            "source": "docs/design/05-production.md#候诊生活表现" if name == "privacy_curtain"
                      else "docs/design/05-production.md#模型与渲染预算", "owner": "asset-production"})
    items.append({"kind": "ui_component", "id": "three_day_timeline", "name": "三日结算时间线",
        "required_paths": ["assets/ui/components/three_day_timeline.tscn"],
        "source": "docs/design/03-experience.md#财务", "owner": "asset-production"})
    items.append({"kind": "ui_illustration", "id": "hospital_welcome", "name": "医院列表空态示意插画",
        "required_paths": ["assets/ui/illustrations/hospital_welcome.png",
                           "assets/ui/cards/hospital_empty.tscn",
                           "art-source/production/ui/hospital_welcome.prompt.txt"],
        "source": "docs/design/03-experience.md#页面与导航", "owner": "asset-production", "max_bytes": 50000})
    for weight in ("Regular","Medium"):
        items.append({"kind":"font_fallback","id":weight,"name":"CJK "+weight,
            "required_paths":[f"assets/fonts/NotoSansCJKsc-{weight}.otf",
                f"assets/fonts/HospitalUI-{weight}.tres","assets/fonts/OFL.txt"],
            "source":"docs/design/05-production.md#字体交付","owner":"asset-production"})
    for profession,name in PROFESSIONS.items():
        items.append({"kind":"profession_accessory","id":profession,"name":name,
            "required_paths":[f"assets/accessories/professions/{profession}.tscn"],
            "source":"docs/design/02-content.md#职业基础分布","owner":"asset-production"})
    return items


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def validation_fingerprint(root):
    plan=json.loads((root/"assets/asset-plan.json").read_text(encoding="utf-8"))
    paths={"assets/presentation/index.json","assets/ui/supplement-index.json","assets/ui/hospital_theme.tres",
           "assets/fonts/HospitalUI-Regular.otf","assets/fonts/HospitalUI-Medium.otf"}
    for item in plan["requirements"]:
        if item["kind"] in {"presentation","ui_supplement","overlay","native_prop",
                            "ui_component","ui_illustration","font_fallback","profession_accessory"}:
            paths.update(p for p in item["required_paths"] if p.startswith("assets/") and not p.endswith("OFL.txt"))
    fingerprints=[(p,hashlib.sha256((root/p).read_bytes()).hexdigest()) for p in sorted(paths)]
    return hashlib.sha256(json.dumps(fingerprints,separators=(",",":")).encode()).hexdigest()


def svg(body, width=192, height=192):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 128 128">'
            f'<g stroke="{INK}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round">'
            + body + "</g></svg>")


def symbol(kind, number=0):
    forms = {
        "card": f'<rect x="25" y="19" width="78" height="91" rx="12" fill="{PAPER}"/>'
                f'<path d="M42 46h44M42 62h32M42 79h40" fill="none"/><circle cx="87" cy="96" r="17" fill="{PALE}"/>',
        "clock": f'<circle cx="64" cy="65" r="40" fill="{PALE}"/><path d="M64 38v29l20 12M48 15h32" fill="none"/>',
        "plant": f'<path d="M38 78h52l-8 34H46Z" fill="{GOLD}"/><path d="M64 78V36" fill="none"/>'
                 f'<path d="M64 55Q24 55 29 27q35-3 35 28Zm0 14q39-5 35-34-37-1-35 34Z" fill="#849b77"/>',
        "book": f'<path d="M64 108V29Q39 14 18 28v68q23-9 46 12Zm0 0V29q25-15 46-1v68q-23-9-46 12Z" fill="{PAPER}"/>'
                '<path d="M32 44h17m-17 16h17m30-16h17m-17 16h17" fill="none"/>',
        "tools": f'<path d="M92 20a27 27 0 0 0-34 34L25 87a12 12 0 0 0 17 17l34-34a27 27 0 0 0 33-31L88 54 74 40Z" fill="{PALE}"/>',
        "people": f'<circle cx="45" cy="43" r="16" fill="{PALE}"/><circle cx="87" cy="49" r="13" fill="{PAPER}"/>'
                  f'<path d="M18 107V88a27 27 0 0 1 54 0v19m8-37a24 24 0 0 1 30 23v14" fill="{PALE}"/>',
        "arrow": f'<path d="M17 49h55V26l38 38-38 38V80H17Z" fill="{PALE}"/>',
        "box": f'<path d="m20 43 44-22 44 22v53l-44 21-44-21Zm0 0 44 22 44-22M64 65v52M42 32l44 22" fill="{PAPER}"/>',
        "bed": f'<path d="M17 109V44m0 44h94V62H58v26m-41-4V65h41M111 62v47" fill="{PALE}"/>'
               f'<circle cx="38" cy="49" r="12" fill="{PAPER}"/>',
        "route": f'<path d="M29 100V69h26V41h26V21h28M17 100h24m56-91 12 12-12 12" fill="none"/>',
        "magnify": f'<circle cx="54" cy="53" r="32" fill="{PALE}"/><path d="m78 78 31 31M54 37v32M39 53h30" fill="none"/>',
        "palette": f'<path d="M96 83c32-40-6-78-46-61S7 84 34 105q24 14 31-6c2-10 22-3 31-16Z" fill="{PAPER}"/>'
                   f'<circle cx="39" cy="52" r="6" fill="{BLUE}"/><circle cx="60" cy="39" r="6" fill="{GOLD}"/>'
                   f'<circle cx="83" cy="45" r="6" fill="{CORAL}"/>',
        "flag": f'<path d="M28 113V18m0 6q20-13 40 0t37 0v47q-18 14-37 0t-40 0" fill="{PALE}"/>',
        "airship": f'<ellipse cx="63" cy="49" rx="47" ry="26" fill="{PALE}"/><path d="m34 71 8 23h42l8-23M42 94v14h42V94M17 49h92" fill="{PAPER}"/>',
        "theatre": f'<path d="M23 22q41 23 82 0v38q-9 43-41 51-32-8-41-51Z" fill="{PALE}"/>'
                   '<path d="M38 49h15m22 0h15M43 77q22 19 42 0" fill="none"/>',
        "bath": f'<path d="M16 65h96q-3 34-26 39H42Q20 100 16 65Zm16 40-5 11m69-11 5 11M31 57V35q0-17 18-17h7v15" fill="{PALE}"/>',
        "blocks": f'<path d="M20 69h43v43H20Zm43-42h43v43H63ZM63 70h43v42H63Z" fill="{PALE}"/>'
                  '<path d="M30 59h21v10M73 17h21v10M74 60h20v10" fill="none"/>',
        "cup": f'<path d="M27 39h61v49q-4 20-30 20T27 88ZM88 47h13q24 1 5 29H88M40 19v8m20-13v13m20-8v8" fill="{PALE}"/>',
        "coin": f'<circle cx="64" cy="64" r="42" fill="{PAPER}"/><path d="M44 39h40M49 56h30M64 39v51M45 90h38" fill="none"/>',
        "frame": f'<rect x="18" y="22" width="92" height="84" rx="10" fill="{PAPER}"/>'
                 f'<path d="m29 92 24-27 17 16 16-24 14 35Z" fill="{PALE}"/><circle cx="81" cy="43" r="9" fill="{GOLD}"/>',
    }
    return forms[kind]


def glyph(record):
    group = record["group"]; identity = record["id"]; n = int("".join(c for c in identity if c.isdigit()) or "1")
    kinds = {
        "biographies": ["airship", "clock", "plant", "book", "theatre", "magnify", "bath", "blocks"],
        "work_styles": ["clock", "people", "magnify", "card", "people", "book"],
        "reasons": ["card", "people", "tools", "route", "bed", "cup", "flag", "bed", "box"],
        "onboarding": ["blocks", "people", "card", "magnify", "tools", "book", "flag", "plant", "people", "frame"],
        "context": ["route", "blocks", "tools", "people", "bed", "palette", "cup", "coin", "clock"],
        "remodel": ["bed", "route", "people", "tools", "palette", "box", "blocks", "flag"],
        "tasks": ["flag", "magnify", "people", "plant", "book", "frame", "tools", "card"],
        "history": ["flag", "people", "plant", "frame", "book", "tools", "bed", "blocks"],
        "finance": ["coin", "card", "tools", "blocks", "people", "arrow"],
        "chairs": ["clock", "frame", "book", "bed"],
        "cleanup": ["cup", "box", "plant", "tools"],
        "queue": ["card", "arrow", "cup", "clock", "flag"],
        "observation": ["magnify", "clock", "arrow", "frame"],
    }
    if group == "titles":
        body = f'<rect x="18" y="27" width="92" height="75" rx="12" fill="{PAPER}"/>'
        body += f'<path d="M45 42v31m-15-15h30" fill="none" stroke="{BLUE}"/>'
        for i in range(n):
            body += f'<path d="M{72+i*8} 45v30" fill="none"/>'
        return svg(body + '<path d="M33 88h63" fill="none"/>')
    if group == "professions":
        kinds={"ordinary":"card","gardener":"plant","mage":"flag",
               "priest":"book","merchant":"box","performer":"theatre"}
        return svg(symbol(kinds[identity])+'<path d="M20 116h23" fill="none" stroke="'+GOLD+'"/>')
    if group in ("states", "results"):
        state = identity.split("_", 1)[-1] if group == "results" else identity
        if "awaiting_recovery" in identity: state = "awaiting_recovery"
        marks = {
            "cured": "M42 66l16 17 31-39", "diagnosis_confirmed": "M42 66l16 17 31-39",
            "retry_ready": "M87 46a29 29 0 1 0 2 34M87 27v22H65",
            "final_failure": "M44 46l40 39m0-39L44 85",
            "awaiting_recovery": "M64 39v27l18 10",
            "more_evidence": "M47 46q21-23 35 0 12 19-18 26v8M64 94v1",
            "broken": "M64 35v37M64 88v1", "paused": "M52 40v49M78 40v49",
            "working": "M42 63l15 15 28-32", "using": "M42 63l15 15 28-32",
            "reserved": "M43 49v39h43V49ZM53 49V37h23v12",
            "idle": "M43 66h42", "waiting": "M64 39v27l18 10",
            "unavailable": "M43 43l42 42", "construction": "M37 85l49-49M45 35l49 49",
            "repairing": "M42 88l44-44M69 35l24 24", "maintenance": "M42 88l44-44M69 35l24 24",
        }
        mark = marks.get(state, "M64 39v27l18 10")
        return svg(f'<circle cx="64" cy="64" r="46" fill="{PAPER}"/><path d="{mark}" fill="none" stroke="{INK}"/>'
                   + (f'<path d="M94 16v14M87 23h14" stroke="{CORAL}" fill="none"/>' if "failure" in state else ""))
    if group == "transit":
        kind = "route" if identity.startswith("VC01") else "bed"
        return svg(symbol(kind) + f'<path d="M98 14v24m-8-16 8-8 8 8" fill="none" stroke="{CORAL}"/>')
    choices = kinds[group]
    return svg(symbol(choices[(n-1) % len(choices)]) +
        f'<path d="M{24+n%5*5} 118h{15+n%4*4}" fill="none" stroke="{GOLD}"/>')


def blueprint(catalog, record):
    source = record["record"]
    if source["source_type"] == "starter_room":
        room = next(r for r in catalog["starter_layout"]["rooms"] if r["id"] == source["source_id"])
        origin = room["anchor"]
        objects = [o for o in catalog["starter_layout"]["objects"] if o.get("room_id") == room["id"]]
    else:
        room = next(r for r in catalog["layouts"]["layouts"] if r["id"] == source["source_id"])
        origin = [0, 0]; objects = room["objects"]
    width, depth = room["size"]; scale = min(96/width, 82/depth)
    x0 = (128-width*scale)/2; y0 = (128-depth*scale)/2
    body = f'<rect x="{x0}" y="{y0}" width="{width*scale}" height="{depth*scale}" fill="{PAPER}"/>'
    for x in range(1,width):
        body += f'<path d="M{x0+x*scale} {y0}v{depth*scale}" stroke="{PALE}" stroke-width=".8"/>'
    for y in range(1,depth):
        body += f'<path d="M{x0} {y0+y*scale}h{width*scale}" stroke="{PALE}" stroke-width=".8"/>'
    for obj in objects:
        definition = catalog["equipment_by_id"][obj["definition_id"]]
        footprint = obj.get("size", definition.get("footprint", [1,1]))
        if isinstance(footprint, dict):
            footprint = [footprint["width"], footprint["depth"]]
        x, y = [obj["anchor"][i]-origin[i] for i in range(2)]
        body += f'<rect x="{x0+x*scale+1}" y="{y0+y*scale+1}" width="{max(1,footprint[0]*scale-2)}" height="{max(1,footprint[1]*scale-2)}" rx="2" fill="{BLUE}" stroke-width="1.4"/>'
        center_x=x0+(x+footprint[0]/2)*scale;center_y=y0+(y+footprint[1]/2)*scale
        motif={"FUR02":"card","M09":"tools","M37":"cup","M17":"magnify","EQ01":"bed","EQ05":"bed",
               "SE04":"bed","SE05":"book","SE06":"card"}.get(obj["definition_id"],"box")
        icon_scale=min(footprint)*scale/150
        body+=f'<g transform="translate({center_x-64*icon_scale},{center_y-64*icon_scale}) scale({icon_scale})" stroke-width="7">{symbol(motif)}</g>'
    if "door" in room:
        door=room["door"];edge=door["edge"];offset=door["offset"]
    else:
        edge="south";offset=room["door_offset"];door={"definition_id":room["door_id"]}
    definition=next(d for d in catalog["doors"] if d["id"]==door["definition_id"])
    opening=int(definition["span_cells"])
    if edge in ("south","north"):
        x=x0+offset*scale;y=y0+(depth*scale if edge=="south" else 0)
        body+=f'<path d="M{x} {y}h{opening*scale}" stroke="{CORAL}" stroke-width="6"/>'
    else:
        x=x0+(width*scale if edge=="east" else 0);y=y0+offset*scale
        body+=f'<path d="M{x} {y}v{opening*scale}" stroke="{CORAL}" stroke-width="6"/>'
    body += '<path d="M12 12h15M12 12v15M116 116h-15m15 0v-15" fill="none" stroke-width="2"/>'
    record["layout"] = {"source_id":source["source_id"],"size":room["size"],"objects":len(objects),
                        "semantic":"authored layout diagram; placement still uses current game validation"}
    return svg(body, 256, 192)


def card(root, item):
    record = item["record"]
    description = record.get("description", record.get("help_text", record.get("text", "")))
    if item["group"] == "biographies":
        description += "\n" + record["hobby"]
    if item["group"] == "blueprints":
        description += "\n" + " × ".join(str(v) for v in item["layout"]["size"])
    title = item["name"]
    text = f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Theme" path="res://assets/ui/hospital_theme.tres" id="Theme"]
[ext_resource type="Texture2D" path="res://{item['path']}" id="Image"]
[node name="AssetCard" type="PanelContainer"]
offset_right = 320.0
offset_bottom = 280.0
custom_minimum_size = Vector2(280, 200)
theme = ExtResource("Theme")
metadata/source = {json.dumps(item['source'],ensure_ascii=False)}
[node name="Content" type="VBoxContainer" parent="."]
layout_mode = 2
theme_override_constants/separation = 12
[node name="Artwork" type="TextureRect" parent="Content"]
custom_minimum_size = Vector2(96, 96)
layout_mode = 2
texture = ExtResource("Image")
expand_mode = 1
stretch_mode = 5
[node name="Title" type="Label" parent="Content"]
layout_mode = 2
theme_override_font_sizes/font_size = 24
text = {json.dumps(title,ensure_ascii=False)}
autowrap_mode = 2
max_lines_visible = 2
[node name="Description" type="RichTextLabel" parent="Content"]
custom_minimum_size = Vector2(0, 112)
layout_mode = 2
focus_mode = 2
text = {json.dumps(description,ensure_ascii=False)}
fit_content = false
scroll_active = true
autowrap_mode = 3
[node name="CurrentFacts" type="Label" parent="Content"]
layout_mode = 2
visible = false
autowrap_mode = 2
[node name="PrimaryAction" type="Button" parent="Content"]
custom_minimum_size = Vector2(96, 40)
layout_mode = 2
visible = false
'''
    if item["group"] == "history":
        text += '''
[node name="ActualPhoto" type="TextureRect" parent="Content"]
layout_mode = 2
visible = false
expand_mode = 1
stretch_mode = 5
'''
    write(root/item["card"], text)


def native_assets(root):
    graphics=graphic_specs(load_catalog(root))
    for item in graphics:
        if item["group"]!="professions":continue
        name=item["id"];subresources="";nodes=""
        if name=="mage":
            subresources='''[sub_resource type="StandardMaterial3D" id="Cloth"]
albedo_color = Color(0.18, 0.25, 0.44, 1)
roughness = 0.9
[sub_resource type="CylinderMesh" id="Garment"]
material = SubResource("Cloth")
top_radius = 0.015
bottom_radius = 0.19
height = 0.36
radial_segments = 10
'''
            nodes='''[node name="Hat" type="MeshInstance3D" parent="."]
position = Vector3(0, 0.22, 0)
mesh = SubResource("Garment")
'''
        elif name=="priest":
            subresources='''[sub_resource type="StandardMaterial3D" id="Cloth"]
albedo_color = Color(0.70, 0.65, 0.83, 1)
roughness = 0.9
[sub_resource type="BoxMesh" id="Garment"]
material = SubResource("Cloth")
size = Vector3(0.33, 0.43, 0.025)
'''
            nodes='''[node name="Tabard" type="MeshInstance3D" parent="."]
position = Vector3(0, -0.15, 0.08)
mesh = SubResource("Garment")
'''
        steps=4 if subresources else 2
        write(root/f"assets/accessories/professions/{name}.tscn",f'''[gd_scene load_steps={steps} format=3]
[ext_resource type="Texture2D" path="res://{item['path']}" id="Badge"]
{subresources}
[node name="ProfessionAccessory" type="Node3D"]
metadata/profession_visual = "{name}"
metadata/target_slot = "{'head' if name=='mage' else 'spine'}"
metadata/allowed_rigs = "{'biped' if name in ('mage','priest') else 'all; generic badge'}"
{nodes}
[node name="Emblem" type="Sprite3D" parent="."]
position = Vector3(0, -0.02, 0.11)
pixel_size = 0.001
texture = ExtResource("Badge")
alpha_cut = 1
''')
    write(root/"assets/props/library/privacy_curtain.tscn",'''[gd_scene load_steps=5 format=3]
[sub_resource type="StandardMaterial3D" id="Fabric"]
albedo_color = Color(0.72, 0.80, 0.90, 1)
roughness = 0.95
[sub_resource type="BoxMesh" id="Panel"]
material = SubResource("Fabric")
size = Vector3(1.0, 1.5, 0.035)
[sub_resource type="StandardMaterial3D" id="FrameMaterial"]
albedo_color = Color(0.26, 0.35, 0.46, 1)
[sub_resource type="CylinderMesh" id="Post"]
material = SubResource("FrameMaterial")
top_radius = 0.018
bottom_radius = 0.018
height = 1.6
radial_segments = 8
[node name="PrivacyCurtain" type="Node3D"]
metadata/placement = "caller supplies actual reserved exterior bounds; no body inside the curtain is rendered"
[node name="Front" type="MeshInstance3D" parent="."]
position = Vector3(0, 0.8, 0.5)
mesh = SubResource("Panel")
[node name="Back" type="MeshInstance3D" parent="."]
position = Vector3(0, 0.8, -0.5)
mesh = SubResource("Panel")
[node name="Left" type="MeshInstance3D" parent="."]
position = Vector3(-0.5, 0.8, 0)
rotation = Vector3(0, 1.570796, 0)
mesh = SubResource("Panel")
[node name="Right" type="MeshInstance3D" parent="."]
position = Vector3(0.5, 0.8, 0)
rotation = Vector3(0, 1.570796, 0)
mesh = SubResource("Panel")
[node name="PostA" type="MeshInstance3D" parent="."]
position = Vector3(-0.5, 0.8, 0.5)
mesh = SubResource("Post")
[node name="PostB" type="MeshInstance3D" parent="."]
position = Vector3(0.5, 0.8, 0.5)
mesh = SubResource("Post")
''')
    write(root/"assets/props/library/soft_shadow.tscn",'''[gd_scene load_steps=4 format=3]
[sub_resource type="Shader" id="Soft"]
code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled; void fragment(){ float r=length(UV-vec2(0.5))*2.0; ALBEDO=vec3(0.12,0.16,0.22); ALPHA=(1.0-smoothstep(0.20,1.0,r))*0.18; }"
[sub_resource type="ShaderMaterial" id="Material"]
shader = SubResource("Soft")
[sub_resource type="PlaneMesh" id="Plane"]
material = SubResource("Material")
size = Vector2(1, 1)
[node name="SoftShadow" type="MeshInstance3D"]
position = Vector3(0, 0.005, 0)
mesh = SubResource("Plane")
cast_shadow = 0
metadata/pipeline = "Compatibility alpha blend; one tightly fitted ground quad; caller scales to actual body"
''')
    overlay_colors = {
        "source":(.40,.52,.72),"target":(.68,.60,.81),"valid":(.40,.57,.76),
        "blocked":(.76,.30,.32),"path_width":(.77,.60,.30),"path_height":(.60,.49,.72),
        "owned_land":(.40,.52,.72),"buyable_land":(.78,.63,.37),"unowned_land":(.48,.51,.57),
        "construction":(.78,.63,.37),"selection":(.95,.78,.44),
    }
    for name, color in overlay_colors.items():
        rgba = ", ".join(str(v) for v in color)
        write(root/f"assets/ui/overlays/{name}.tscn",f'''[gd_scene load_steps=4 format=3]
[sub_resource type="Shader" id="Outline"]
code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled; uniform vec3 tint=vec3({rgba}); void fragment(){{ vec2 e=min(UV,vec2(1.0)-UV); float edge=1.0-step(0.045,min(e.x,e.y)); float stripe=step(0.70,fract((UV.x+UV.y)*10.0)); ALBEDO=tint; ALPHA=max(edge*0.85,stripe*0.13); }}"
[sub_resource type="ShaderMaterial" id="Material"]
shader = SubResource("Outline")
[sub_resource type="PlaneMesh" id="Plane"]
material = SubResource("Material")
size = Vector2(1, 1)
[node name="FootprintOverlay" type="MeshInstance3D"]
position = Vector3(0, 0.012, 0)
mesh = SubResource("Plane")
cast_shadow = 0
metadata/state = "{name}"
metadata/binding = "caller provides current world footprint and reason; marker does not validate routes or grant land"
''')
    timeline = '''[gd_scene load_steps=2 format=3]
[ext_resource type="Theme" path="res://assets/ui/hospital_theme.tres" id="Theme"]
[node name="ThreeDayTimeline" type="HBoxContainer"]
theme = ExtResource("Theme")
theme_override_constants/separation = 16
metadata/binding = "three actual projected settlement days; caller supplies labels and separated cash assumptions"
'''
    for i in range(1,4):
        timeline += f'''
[node name="Day{i}" type="VBoxContainer" parent="."]
layout_mode = 2
size_flags_horizontal = 3
[node name="Date" type="Label" parent="Day{i}"]
layout_mode = 2
[node name="Cash" type="Label" parent="Day{i}"]
layout_mode = 2
[node name="Assumptions" type="Label" parent="Day{i}"]
layout_mode = 2
autowrap_mode = 2
'''
    write(root/"assets/ui/components/three_day_timeline.tscn", timeline)
    write(root/"assets/ui/cards/hospital_empty.tscn",'''[gd_scene load_steps=3 format=3]
[ext_resource type="Theme" path="res://assets/ui/hospital_theme.tres" id="Theme"]
[ext_resource type="Texture2D" path="res://assets/ui/illustrations/hospital_welcome.png" id="Art"]
[node name="HospitalEmptyState" type="PanelContainer"]
theme = ExtResource("Theme")
[node name="Content" type="VBoxContainer" parent="."]
layout_mode = 2
[node name="Illustration" type="TextureRect" parent="Content"]
custom_minimum_size = Vector2(320, 180)
layout_mode = 2
texture = ExtResource("Art")
expand_mode = 1
stretch_mode = 5
[node name="Caption" type="Label" parent="Content"]
layout_mode = 2
text = "医院示意图"
[node name="CreateHospital" type="Button" parent="Content"]
custom_minimum_size = Vector2(96, 40)
layout_mode = 2
text = "开一家医院"
''')
    for weight in ("Regular","Medium"):
        source=Path(__file__).resolve().parents[2]/f"assets/fonts/NotoSansCJKsc-{weight}.otf"
        target=root/f"assets/fonts/NotoSansCJKsc-{weight}.otf"
        if source.resolve()!=target.resolve():
            shutil.copy2(source,target)
        write(root/f"assets/fonts/HospitalUI-{weight}.tres",f'''[gd_resource type="FontVariation" load_steps=3 format=3]
[ext_resource type="FontFile" path="res://assets/fonts/HospitalUI-{weight}.otf" id="Subset"]
[ext_resource type="FontFile" path="res://assets/fonts/NotoSansCJKsc-{weight}.otf" id="Full"]
[resource]
base_font = ExtResource("Subset")
fallbacks = Array[Font]([ExtResource("Full")])
''')


def build(root):
    from make_resources import presentation, scene_states
    catalog = load_catalog(root)
    portrait_source=root/"art-source/production/ui/render_role_portraits.gd"
    portrait_source.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(Path(__file__).with_name("render_role_portraits.gd"),portrait_source)
    index_path = root/"assets/presentation/index.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    current = {item["id"]:item for item in index["scenes"]}
    from catalog import resource_plan
    plan = resource_plan(catalog)
    refreshed = []
    for item in plan["requirements"]:
        if item["kind"] != "presentation":
            continue
        old = current.get(item["id"], {})
        states = scene_states(item["record"])
        seating_or_sleep=item["collection"]=="patient_personalities" or (item["collection"]=="service_equipment" and item["record"]["id"]=="SE04")
        if (old.get("source_text") != states or seating_or_sleep) and old.get("kind") not in ("native_ui_card","named_character_visual"):
            current[item["id"]] = presentation(root, item)
            refreshed.append(item["id"])
    write_json(index_path, {"schema":1,"scenes":list(current.values())})
    graphics = graphic_specs(catalog)
    for item in graphics:
        if item["group"] != "roles":
            art = blueprint(catalog,item) if item["group"] == "blueprints" else glyph(item)
            write(root/item["editable"], art)
        if "card" in item:
            card(root, item)
            collection=GROUPS.get(item["group"],"blueprint_presets" if item["group"]=="blueprints" else "")
            key=collection+":"+item["id"]
            existing=current.get(key)
            if existing and existing.get("kind")=="native_ui_card":
                write(root/existing["path"],'[gd_scene load_steps=2 format=3]\n'
                    +'[ext_resource type="PackedScene" path="res://'+item["card"]+'" id="Card"]\n'
                    +'[node name="PresentationCard" instance=ExtResource("Card")]\n')
    write_json(index_path, {"schema":1,"scenes":list(current.values())})
    native_assets(root)
    from make_resources import theme
    theme(root)
    write_json(root/"assets/ui/supplement-index.json", {"schema":1,"graphics":graphics,
        "rules":"images are illustrative; current facts, qualifications, prices and progress come from the game"})
    old_plan = json.loads((root/"assets/asset-plan.json").read_text(encoding="utf-8"))
    aliases = old_plan.get("file_aliases", {})
    for item in plan["requirements"]:
        item["required_paths"] = [aliases.get(path,path) for path in item["required_paths"]]
    if aliases:
        plan["file_aliases"] = aliases
    write_json(root/"assets/asset-plan.json",plan)
    report = {"schema":1,"graphic_counts":dict(Counter(i["group"] for i in graphics)),
        "graphics":len(graphics),"refreshed_presentations":refreshed,
        "presentation_scene_count":len(current),"standalone_native_components":15+len(PROFESSIONS),
        "ui_card_scenes":1+sum("card" in item for item in graphics),
        "coverage":"authored nested scenes, blueprint diagrams, recruitment, status graphics and native UI components",
        "runtime_handoffs":"not exercised; no gameplay rules changed"}
    write_json(root/"art-source/production/validation/design-supplement.json",report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.root.resolve()),ensure_ascii=False))
