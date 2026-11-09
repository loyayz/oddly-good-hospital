"""Author native Godot scenes, materials, UI and catalog-linked presentation clips."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path

from catalog import (load_catalog,resource_plan,write_json,PRESENTATION_COLLECTIONS,
                     variants,BODY_ACTIONS,BODY_SLOTS,authored_scenes)

COLORS={"ivory":(.94,.89,.79,1),"teal":(.30,.56,.54,1),"navy":(.12,.20,.27,1),
        "honey":(.85,.65,.36,1),"aqua":(.62,.78,.76,1),"coral":(.84,.40,.32,1),
        "lavender":(.70,.64,.79,1),"stone":(.67,.69,.68,1)}


def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,encoding="utf-8",newline="\n")


def q(value):return json.dumps(str(value),ensure_ascii=False)
def vec(value):return "Vector3("+", ".join(f"{v:.6f}" for v in value)+")"


def textual(value):
    if isinstance(value,str):return value
    if isinstance(value,list):return " ".join(textual(v) for v in value)
    if isinstance(value,dict):return " ".join(textual(v) for v in value.values())
    return ""


def select_props(text):
    rules=(("花盆|盆栽|空盆","plantpot"),("种子|瓜子","seed"),("纸巾|纸片|纸屑|包装","tissue"),
        ("冰壳|冰冻|结霜","ice"),("热风|暖风|气流","air"),("绵羊|毛毡羊","sheep"),
        ("枕头|午睡|睡眠","pillow"),("眼罩","eye_mask"),("绷带|棉花|织布","bandage"),
        ("排队|号签|票号","tickets"),("水滴|雨水|水珠|水迹|水印","rain"),
        ("软环|光环|套圈","rings"),("披风|雨伞|伞架","umbrella"),
        ("扳手|维修|螺丝","wrench"),("清扫|扫帚|拖把|簸箕","broom"),
        ("病例|病历|夹子|记录|床位卡","label"),("小书|页码|书签|画卡|图页|书本","book"),
        ("路线|指路|箭头|标尺","arrow"),("旋律|合唱|音符|乐谱","note"),
        ("礼花|庆祝|彩带","ribbon"),("小白旗|小旗|旗子","flag"),
        ("星光|星星|星点","star"),("相框|合影|照片","frame"),
        ("面条|毛线|线结|彩线","knot"),("小花|花朵|花瓣|树叶","flower"),
        ("杯子|水杯|杯套","cup"),("小钟|时钟|日历|工时","clock"),
        ("屏幕|图符|加载","loading"),("牙齿|梳齿|梳子","comb"),
        ("小勺|勺子","spoon"),("纽扣|表情|笑脸","faces"),("镜子|镜框|观察窗","mirror"),
        ("鞋|滑冰鞋","shoe"),("听诊器","stethoscope"),("滚筒|刷墙","paintroller"),
        ("隐私帘","privacy_curtain"),("纸箱|包体|包摞|治疗包","packaging"),
        ("量尺|标尺|定位尺","ruler"),("问号|省略号|逗号|句号","punctuation"))
    result=[]
    for words,shape in rules:
        if any(word in text for word in words.split("|")) and shape not in result:result.append(shape)
    if "privacy_curtain" in result:
        result.remove("privacy_curtain");result.insert(0,"privacy_curtain")
    return result[:4] or ["label"]


def scene_states(record):
    states={}
    for key,value in record.items():
        if isinstance(value,str) and ("scene" in key or key in ("followup","level1","level2")):
            states[key.removesuffix("_scene") or "scene"]=value
        if key=="beats" and isinstance(value,list):
            for i,beat in enumerate(value):states[f"beat_{i+1}"]=str(beat)
        if isinstance(value,list):
            for i,item in enumerate(value):
                if isinstance(item,dict):
                    for field,text in item.items():
                        if isinstance(text,str) and "scene" in field:
                            states[str(item.get("id",item.get("state",item.get("definition_id",i))))+"_"+field.removesuffix("_scene")]=text
    existing=set(states.values())
    for pointer,text in authored_scenes(record):
        if text not in existing:
            states["authored_"+pointer.strip("/").replace("/","_")]=text
            existing.add(text)
    return states or {"scene":record.get("text",record.get("name",textual(record)))}


def animation_resource(identity,objects,static=False,finish=False,retain=True,visible=None,seed_arcs=False):
    lines=[f'[sub_resource type="Animation" id="{identity}"]',f'resource_name = {q(identity)}','length = 1.0']
    for i,position in enumerate(objects):
        middle=list(position)
        if not static:
            middle[0]+=.025*(1 if i%2 else -1)
            middle[1]+=.04 if i%2 else .02
        final=list(position)
        if finish and not retain:final[1]-=.05
        prefix=f"tracks/{i*2}"
        if seed_arcs and i<3 and not static:
            middle[0]+=.14*(1 if i%2 else -1);middle[1]+=.36+i*.08
            final[0]+=.30*(1 if i%2 else -1)
        lines.extend([f'{prefix}/type = "value"',f'{prefix}/imported = false',
            f'{prefix}/enabled = true',f'{prefix}/path = NodePath("Prop{i}:position")',
            f'{prefix}/interp = 1',f'{prefix}/loop_wrap = false',
            f'{prefix}/keys = {{"times": PackedFloat32Array(0, 0.5, 1), "transitions": PackedFloat32Array(1, 1, 1), "update": 0, "values": [{vec(position)}, {vec(middle)}, {vec(final)}]}}'])
        prefix=f"tracks/{i*2+1}"
        show=True if visible is None else visible[i]
        lines.extend([f'{prefix}/type = "value"',f'{prefix}/path = NodePath("Prop{i}:visible")',
            f'{prefix}/interp = 0',f'{prefix}/keys = {{"times": PackedFloat32Array(0), "transitions": PackedFloat32Array(1), "update": 1, "values": [{str(show).lower()}]}}'])
    return "\n".join(lines)


def presentation(root,requirement):
    record=requirement["record"];collection=requirement["collection"]
    identity=requirement["id"].split(":",1)[1]
    states=scene_states(record)
    physical=collection not in {"onboarding_steps","context_lessons","comedy_corner_guides","history_templates",
        "finance_views","remodel_guides","blueprint_presets","task_guides","journey_reason_cards",
        "observation_cues","rest_cues"}
    path=root/requirement["required_paths"][0]
    if collection=="community_cast":
        visual=f"assets/models/core_{record['species_id'].lower()}_body.glb"
        write(path,'[gd_scene load_steps=2 format=3]\n'
            +'[ext_resource type="PackedScene" path="res://'+visual+'" id="Body"]\n'
            +'[node name="CastVisual" type="Node3D"]\nmetadata/content_id = '+q(identity)+'\n'
            +'metadata/display_name = '+q(record["name"])+'\n'
            +'metadata/profession_id = '+q(record["profession_id"])+'\n'
            +'[node name="Body" parent="." instance=ExtResource("Body")]\n')
        return {"id":requirement["id"],"kind":"named_character_visual","states":list(states),
            "path":path.relative_to(root).as_posix(),"source":requirement["source"],"body_path":visual,
            "identity":"content ID; graphics do not create simulation actors"}
    if not physical:
        title=record.get("name",record.get("text",identity))
        body="\n".join(v for k,v in record.items() if isinstance(v,str) and k not in ("id","name","source","target_panel","state"))
        text='''[gd_scene load_steps=2 format=3]
[ext_resource type="Theme" path="res://assets/ui/hospital_theme.tres" id="1"]
[node name="PresentationCard" type="PanelContainer"]
custom_minimum_size = Vector2(280, 100)
theme = ExtResource("1")
[node name="Content" type="VBoxContainer" parent="."]
layout_mode = 2
[node name="Title" type="Label" parent="Content"]
layout_mode = 2
text = TITLE
[node name="Body" type="Label" parent="Content"]
layout_mode = 2
text = BODY
autowrap_mode = 2
'''.replace("TITLE",q(title)).replace("BODY",q(body))
        write(path,text)
        return {"id":requirement["id"],"kind":"native_ui_card","states":list(states),"path":path.relative_to(root).as_posix(),"source":requirement["source"]}
    chosen=list(dict.fromkeys(shape for text in states.values() for shape in select_props(text)))[:12]
    if collection=="incidents" and identity=="E01":chosen=["seed","seed","seed","shoe","plantpot","plantpot"]
    positions=[((i-(len(chosen)-1)/2)*.25,.38+(i%2)*.09,0) for i in range(len(chosen))]
    if collection=="species_gifts":paths=[f"assets/props/species_gifts/{identity.lower()}.glb"];positions=[(0,0,0)]
    elif collection=="stories":paths=[f"assets/props/mementos/{identity.lower()}.glb"];positions=[(0,0,0)]
    else:paths=[f"assets/props/library/{shape}.{'tscn' if shape=='privacy_curtain' else 'glb'}" for shape in chosen]
    subresources=[];mapping={}
    for n,(name,text) in enumerate(states.items()):
        key=f"Clip{n}"
        static="low_motion" in name or any(k in name for k in ("held","idle","interrupted","paused"))
        active=select_props(text)
        if collection=="incidents" and identity=="E01":active=["plantpot"] if name=="followup" else ["seed","shoe","plantpot"]
        visible=[shape in active for shape in chosen] if collection not in ("species_gifts","stories") else [True]
        arcs=collection=="incidents" and identity=="E01" and name!="followup"
        subresources.append(animation_resource(key,positions,static,finish="finish" in name,retain=True,visible=visible,seed_arcs=arcs))
        mapping[name]=key
        if not static:
            subresources.append(animation_resource(key+"Low",positions,True,visible=visible))
            mapping[name+"_low_motion"]=key+"Low"
    header=f'[gd_scene load_steps={len(paths)+len(subresources)+3} format=3]\n'
    external='\n'.join(f'[ext_resource type="PackedScene" path="res://{p}" id="P{i}"]' for i,p in enumerate(paths))
    library='[sub_resource type="AnimationLibrary" id="Library"]\n_data = {'+', '.join(q(k)+': SubResource('+q(v)+')' for k,v in mapping.items())+'}\n'
    nodes='[node name="Presentation" type="Node3D"]\nmetadata/source_id = '+q(requirement["id"])+'\n'
    actor_actions={name:next((action for words,action in (("眨眼","blink"),("点头|确认","notice"),("睡|小憩","sleep"),
        ("挥手|回应|鞠躬","talk"),("庆祝|鼓掌","cheer"),("整理|核对|取放","interact"))
        if any(word in text for word in words.split("|"))),"idle") for name,text in states.items()}
    if collection=="patient_personalities":
        actor_actions={name:"sit" for name in states}
    if collection=="service_equipment" and identity=="SE04":
        actor_actions={name:"sleep" for name in states}
    nodes+='metadata/actor_actions = '+json.dumps(actor_actions,ensure_ascii=False)+'\n'
    for i,position in enumerate(positions):
        nodes+=f'\n[node name="Prop{i}" parent="." instance=ExtResource("P{i}")]\nposition = {vec(position)}\n'
    nodes+='\n[node name="ActorA" type="Marker3D" parent="."]\nposition = Vector3(-0.65, 0, 0)\n'
    nodes+='\n[node name="ActorB" type="Marker3D" parent="."]\nposition = Vector3(0.65, 0, 0)\n'
    nodes+='\n[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {&"": SubResource("Library")}\n'
    write(path,header+external+'\n\n'+'\n\n'.join(subresources)+'\n\n'+library+'\n'+nodes)
    return {"id":requirement["id"],"kind":"composed_3d_scene","path":path.relative_to(root).as_posix(),
            "states":list(mapping),"props":paths,"source":requirement["source"],"source_text":states,
            "binding":"caller supplies real actor slots, state and normalized progress; no business callbacks"}


def routine_scenes(root,catalog):
    for record in catalog["treatment_routines"]:
        shapes=select_props(" ".join(record["beats"]))
        external='\n'.join(f'[ext_resource type="PackedScene" path="res://assets/props/library/{shape}.glb" id="P{i}"]' for i,shape in enumerate(shapes))
        text=f'[gd_scene load_steps={len(shapes)+2} format=3]\n'+external+f'\n[ext_resource type="AnimationLibrary" path="res://assets/animations/treatments/{record["id"].lower()}.tres" id="L"]\n'
        text+='[node name="TreatmentRoutine" type="Node3D"]\nmetadata/source_id = '+q(record["id"])+'\n'
        for i,beat in enumerate(record["beats"]):text+=f'metadata/beat_{i+1} = '+q(beat)+'\n'
        text+='[node name="Tool" type="Node3D" parent="."]\n'
        for i,shape in enumerate(shapes):
            text+=f'[node name="Prop{i}" parent="Tool" instance=ExtResource("P{i}")]\nposition = '+vec(((i-(len(shapes)-1)/2)*.3,.4,0))+'\n'
        text+='[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {&"": ExtResource("L")}\n'
        write(root/f"assets/presentation/treatments/{record['id'].lower()}.tscn",text)


def materials(root,catalog):
    colors=(COLORS["ivory"],COLORS["stone"],COLORS["honey"],COLORS["aqua"],
            COLORS["ivory"],COLORS["teal"],COLORS["lavender"],COLORS["stone"])
    for i,record in enumerate(catalog["renovation_materials"]):
        rgba=colors[i]
        write(root/f"assets/materials/{record['id'].lower()}.tres",f'''[gd_resource type="StandardMaterial3D" format=3]
[resource]
resource_name = {q(record['name'])}
albedo_color = Color({', '.join(str(v) for v in rgba)})
roughness = 0.88
cull_mode = 0
''')
    for identity,rgba in COLORS.items():
        write(root/f"assets/materials/shared_{identity}.tres",'[gd_resource type="StandardMaterial3D" format=3]\n[resource]\nalbedo_color = Color('+', '.join(str(v) for v in rgba)+')\nvertex_color_use_as_albedo = true\nroughness = 0.8\n')


def theme(root):
    write(root/"assets/ui/hospital_theme.tres",'''[gd_resource type="Theme" load_steps=8 format=3]
[ext_resource type="FontVariation" path="res://assets/fonts/HospitalUI-Regular.tres" id="1"]
[ext_resource type="FontVariation" path="res://assets/fonts/HospitalUI-Medium.tres" id="2"]
[sub_resource type="StyleBoxFlat" id="Panel"]
bg_color = Color(0.95, 0.92, 0.85, 1)
corner_radius_top_left = 14
corner_radius_top_right = 14
corner_radius_bottom_left = 14
corner_radius_bottom_right = 14
content_margin_left = 18.0
content_margin_right = 18.0
content_margin_top = 14.0
content_margin_bottom = 14.0
border_width_left = 1
border_width_right = 1
border_width_top = 1
border_width_bottom = 1
border_color = Color(0.82, 0.79, 0.71, 1)
[sub_resource type="StyleBoxFlat" id="Button"]
bg_color = Color(0.18, 0.29, 0.44, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_left = 9
corner_radius_bottom_right = 9
content_margin_left = 16.0
content_margin_right = 16.0
content_margin_top = 10.0
content_margin_bottom = 10.0
[sub_resource type="StyleBoxFlat" id="Hover"]
bg_color = Color(0.27, 0.40, 0.57, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_left = 9
corner_radius_bottom_right = 9
[sub_resource type="StyleBoxFlat" id="Pressed"]
bg_color = Color(0.12, 0.21, 0.34, 1)
corner_radius_top_left = 9
corner_radius_top_right = 9
corner_radius_bottom_left = 9
corner_radius_bottom_right = 9
[sub_resource type="StyleBoxFlat" id="Focus"]
bg_color = Color(0, 0, 0, 0)
border_width_left = 3
border_width_top = 3
border_width_right = 3
border_width_bottom = 3
border_color = Color(0.85, 0.62, 0.29, 1)
corner_radius_top_left = 10
corner_radius_top_right = 10
corner_radius_bottom_left = 10
corner_radius_bottom_right = 10
[resource]
default_font = ExtResource("1")
default_font_size = 18
PanelContainer/styles/panel = SubResource("Panel")
Button/styles/normal = SubResource("Button")
Button/styles/hover = SubResource("Hover")
Button/styles/pressed = SubResource("Pressed")
Button/styles/focus = SubResource("Focus")
Button/colors/font_color = Color(1, 0.98, 0.91, 1)
Label/colors/font_color = Color(0.14, 0.22, 0.28, 1)
RichTextLabel/colors/default_color = Color(0.14, 0.22, 0.28, 1)
RichTextLabel/fonts/normal_font = ExtResource("1")
RichTextLabel/fonts/bold_font = ExtResource("2")
RichTextLabel/font_sizes/normal_font_size = 18
RichTextLabel/styles/focus = SubResource("Focus")
Header/fonts/font = ExtResource("2")
Header/font_sizes/font_size = 24
''')


def appearances(root,catalog):
    for species in catalog["species"]:
        rig=species["rig"]
        write_json(root/f"assets/appearances/core_{species['id'].lower()}.json",{
            "species_id":species["id"],"rig":rig,"dimensions":species["body"],"body_path":f"assets/models/core_{species['id'].lower()}_body.glb",
            "variants":[{"id":i,"accessory_path":f"assets/accessories/looks/{'core_s49' if species['id']=='S49' else rig}_look_{i:02}.glb",
                "slot":"head" if i in (1,3) or species["id"]=="S49" else "carry_anchor", "tint":tint,
                "human_hair":("short brown","grey bun and glasses","dark curls","honey bob")[i-1] if species["id"]=="S49" else None,
                "distinguishing_attributes":["accessory silhouette","body color temperature"]}
                for i,tint in enumerate(((1,1,1,1),(1,.92,.84,1),(.86,.96,1,1),(.96,.88,1,1)),1)]})
    for adapter in catalog["staff_rig_adapters"]:
        rig=adapter["rig"]
        sample=next(s for s in catalog["species"] if s["rig"]==rig)
        write_json(root/f"assets/rigs/{rig}.json",{"id":rig,"reference_species":sample["id"],
            "actions":list(BODY_ACTIONS),"staff_actions":adapter["actions"],"slots":list(BODY_SLOTS),
            "animation_library":f"assets/animations/staff/{rig}.tres","source":adapter,
            "root_motion":False,"max_bones":40})
    maintained=set(catalog["rules"]["equipment"]["maintained_definition_ids"])
    definitions=[]
    for equipment in catalog["equipment"]:
        identity=equipment["id"]
        states=["idle","working","paused","using"]
        if identity in maintained:states += ["broken","repairing","maintenance","construction"]
        definitions.append({"id":identity,"name":equipment["name"],"base_path":f"assets/models/core_{identity.lower()}_machine.glb",
            "maintainable":identity in maintained,"states":states,
            "upgrade_paths":{str(level):f"assets/upgrades/{identity.lower()}_level_{level}.glb" for level in (1,2)
                             if any(p["definition_id"]==identity for p in catalog["upgrade_presentations"])},
            "fit_profile_id":equipment.get("fit_profile_id"),"footprint":equipment.get("footprint"),
            "resize":"segmented door" if identity.startswith("DR") else ("segmented patient support" if identity=="EQ05" else "fixed furniture body"),
            "source":"content/core/"+equipment["collection"]+".json#"+identity})
    write_json(root/"assets/models/equipment-states.json",{"definitions":definitions,
        "maintenance_source":"content/core/rules.json#equipment.maintained_definition_ids"})


def fonts(root,catalog):
    from fontTools import subset
    from fontTools.ttLib import TTFont
    text=textual(catalog)+"".join(chr(n) for n in range(32,127))+"素材预览返回播放暂停上一项下一项模型设备病例演出音乐音效进度低动态外观岗位搜索选择尺寸面数未接入游戏运行预算验证"
    records=[]
    for weight in ("Regular","Medium"):
        source=root/f"assets/fonts/NotoSansCJKsc-{weight}.otf"
        target=root/f"assets/fonts/HospitalUI-{weight}.otf"
        font=TTFont(source)
        options=subset.Options();options.layout_features=["*"]
        sub=subset.Subsetter(options=options);sub.populate(text=text);sub.subset(font)
        for name_id in (1,3,4,6,16,17):
            value=("Hospital UI "+weight) if name_id!=6 else ("HospitalUI-"+weight)
            if name_id==17:value=weight
            for name in font["name"].names:
                if name.nameID==name_id:name.string=value.encode(name.getEncoding(),errors="replace")
        font.save(target)
        records.append({"path":target.relative_to(root).as_posix(),"bytes":target.stat().st_size,
                        "source":source.name,"codepoints":len(font.getBestCmap()),"license":"OFL.txt"})
    write_json(root/"assets/fonts/subset-index.json",{"fonts":records,"text_source":"content/core and asset browser labels"})


def effects(root):
    records=[]
    for identity,color in (("smoke","stone"),("rain","aqua"),("sparkle","honey"),("dust","ivory"),
        ("steam","ivory"),("seed","honey"),("confetti","coral"),("paper","ivory"),
        ("snow","ivory"),("bubble","aqua"),("leaf","teal"),("sleep","lavender"),("dream","lavender"),("flow","aqua")):
        rgba=COLORS[color]
        path=f"assets/effects/{identity}.tscn"
        write(root/path,f'''[gd_scene load_steps=3 format=3]
[sub_resource type="StandardMaterial3D" id="Material"]
shading_mode = 0
albedo_color = Color({', '.join(str(v) for v in rgba)})
[sub_resource type="SphereMesh" id="Mesh"]
radius = 0.018
height = 0.036
radial_segments = 6
rings = 3
material = SubResource("Material")
[node name="{identity.title()}" type="Node3D"]
metadata/max_particles = 16
metadata/pool_owner = "scene presentation; global emitter budget 24"
[node name="Particles" type="CPUParticles3D" parent="."]
emitting = false
amount = 16
lifetime = 1.2
one_shot = true
explosiveness = 0.5
mesh = SubResource("Mesh")
direction = Vector3(0, 1, 0)
spread = 35.0
gravity = Vector3(0, -0.18, 0)
initial_velocity_min = 0.08
initial_velocity_max = 0.22
[node name="LowMotion" type="MeshInstance3D" parent="."]
visible = false
mesh = SubResource("Mesh")
position = Vector3(0, 0.1, 0)
''')
        records.append({"id":identity,"path":path,"max_particles":16,"renderer":"Compatibility CPU particles"})
    write_json(root/"assets/effects/index.json",{"effects":records,"max_concurrent_emitters":24})


def audio_import(root):
    data=json.loads((root/"assets/audio/index.json").read_text(encoding="utf-8"))
    # Resource remap import metadata is generated by Godot, never hand-written.
    # Loop policy is applied to the actual imported AudioStream by finish_import.gd.
    for clip in data["clips"]:
        clip.pop("stream_resource",None)
        clip["loop_policy"]="sound_bank applies current-state loop flag to imported Ogg stream"
    write_json(root/"assets/audio/index.json",data)


def main():
    p=argparse.ArgumentParser();p.add_argument("--root",type=Path,required=True);a=p.parse_args();root=a.root.resolve()
    c=load_catalog(root);plan=resource_plan(c);theme(root);materials(root,c);appearances(root,c);fonts(root,c);effects(root);audio_import(root);routine_scenes(root,c)
    scenes=[presentation(root,item) for item in plan["requirements"] if item["kind"]=="presentation"]
    write_json(root/"assets/presentation/index.json",{"schema":1,"scenes":scenes})
    write_json(root/"art-source/production/resource-plan.json",plan)
    write_json(root/"assets/asset-plan.json",plan)
    from design_assets import build
    build(root)
    print(json.dumps({"requirements":len(plan["requirements"]),"counts":plan["counts"],"presentation_scenes":len(scenes)},ensure_ascii=False))


if __name__=="__main__":main()
