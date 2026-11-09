"""Reusable presentation objects, staff accessories, upgrades and surgery supports."""
import argparse
import json
import math
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from blender_common import Model, reset_scene, save_blend, export_glb, glb_metadata, armature, skin, actions
from blender_cases import prop, SYMPTOMS, build_props, target_for
from catalog import load_catalog, write_json, effective_body


def publish(root,m,relative,source_group,identity,budget=800):
    mesh=m.join(identity.lower(),budget)
    source=root/f"art-source/production/{source_group}/{identity.lower()}.blend"
    target=root/(relative+"/"+identity.lower()+".glb")
    save_blend(source);export_glb(target,[mesh])
    return {"id":identity,"path":target.relative_to(root).as_posix(),
            "source_path":source.relative_to(root).as_posix(),**glb_metadata(target)}


def library(root):
    records=[]
    for identity in sorted(set(SYMPTOMS)|{"ring","comb","soft_tool","cloud","ticket","pillow","hourglass",
        "seed","plantpot","ice","flag","broom","paintroller","wrench","stethoscope","cup","eye_mask"}):
        reset_scene();m=Model();prop(m,identity,(0,0,.22),.45,"ivory","root")
        records.append(publish(root,m,"assets/props/library","props/library",identity))
    write_json(root/"assets/props/library/index.json",{"props":records})
    return records


def accessories(root,catalog):
    records=[]
    roles={role for item in catalog["staff_rig_adapters"] for role in item["roles"]}
    for rig in sorted({s["rig"] for s in catalog["species"]}):
        for role in sorted(roles):
            reset_scene();m=Model()
            color={"doctor":"ivory","nurse":"aqua","receptionist":"navy","cleaner":"blue",
                   "mechanic":"honey","researcher":"lavender","decorator":"coral"}[role]
            m.box("UniformPanel",(0,0,0),(.23,.045,.26),color,bevel=.035)
            m.box("RoleBadge",(.055,-.027,.06),(.065,.018,.075),"honey")
            for i in range(sorted(roles).index(role)%3+1):
                m.box("RoleStripe",(-.06+i*.025,-.028,-.04),(.012,.018,.065),"teal",bevel=0)
            tool={"doctor":"ring","nurse":"label","receptionist":"tickets","cleaner":"air",
                  "mechanic":"key","researcher":"book","decorator":"ruler"}[role]
            prop(m,tool,(.17,-.03,-.04),.22,"honey","root")
            if rig in ("micro","object"):
                m.line("ControlMount",[(0,.03,-.13),(0,.14,-.13),(0,.14,.10)],.012,"wood")
            elif rig in ("quadruped","longneck"):
                m.ring("SoftHarness",(0,.04,0),.13,.012,"wood",rotation=(math.pi/2,0,0))
            identity=f"{rig}_{role}"
            record=publish(root,m,"assets/accessories/uniforms","accessories/uniforms",identity,500)
            records.append({**record,"rig":rig,"role":role,"slot":"carry_anchor","fit":"scale to current real body; fixed species dimensions"})
        for look in range(1,5):
            reset_scene();m=Model()
            if look==1:
                prop(m,"flower",(0,0,0),.20,"coral","root")
            elif look==2:
                m.line("SoftScarf",[(-.12,0,0),(0,-.025,-.04),(.12,0,0),(.11,0,-.19)],.035,"aqua")
            elif look==3:
                m.rod("SunHatBrim",(0,0,0),(0,0,.025),.18,"honey",vertices=12)
                m.rod("SunHatCrown",(0,0,.025),(0,0,.15),.11,"honey",tip_radius=.085,vertices=12)
                m.ring("HatBand",(0,0,.05),.108,.015,"teal")
            else:
                m.box("Satchel",(0,0,-.06),(.20,.09,.21),"coral",bevel=.025)
                m.line("SatchelStrap",[(-.07,0,.04),(-.07,0,.16),(.07,0,.16),(.07,0,.04)],.012,"wood")
            identity=f"{rig}_look_{look:02}"
            record=publish(root,m,"assets/accessories/looks","accessories/looks",identity,400)
            records.append({**record,"rig":rig,"look":look,"slot":"head" if look in (1,3) else "carry_anchor"})
    write_json(root/"assets/accessories/index.json",{"accessories":records})


def human_looks(root):
    index=root/"assets/accessories/index.json"
    records=json.loads(index.read_text(encoding="utf-8"))["accessories"]
    records=[r for r in records if not r["id"].startswith("core_s49_look_")]
    for look,color in ((1,"brown"),(2,"silver"),(3,"ink"),(4,"honey")):
        reset_scene();m=Model()
        m.ball("HairCap",(0,.025,0),(.48,.40,.22),color,"root")
        if look==2:
            m.ball("GreyBun",(0,.15,.14),(.18,.18,.18),"silver","root")
            prop(m,"glasses",(0,-.24,-.19),.34,"wood","root")
        elif look==3:
            for i in range(5):m.ball("Curl",((i-2)*.085,-.12,.075+(i%2)*.025),(.16,.15,.15),"ink","root",segments=8,rings=4)
        elif look==4:
            for sign in (-1,1):m.ball("BobSide",(sign*.18,.04,-.11),(.13,.25,.35),"honey","root")
        else:m.line("HairPart",[(-.03,-.17,.09),(.04,0,.11),(.11,.15,.06)],.01,"wood","root")
        identity=f"core_s49_look_{look:02}"
        records.append({**publish(root,m,"assets/accessories/looks","accessories/looks",identity,500),
            "rig":"biped","species_id":"S49","look":look,"slot":"head"})
    write_json(index,{"accessories":records})


def upgrades(root,catalog):
    records=[]
    for upgrade in catalog["upgrade_presentations"]:
        identity=upgrade["definition_id"]
        equipment=catalog["equipment_by_id"][identity]
        w,d=[v*1.5 for v in equipment["footprint"]]
        for level in (1,2):
            reset_scene();m=Model()
            # Units and origins match the stable base; these add-on meshes do
            # not resize its footprint or change the registered patient space.
            def pt(x,y,z):return ((x+.5)*w,(y-.5)*d,z)
            if identity=="FUR02":
                for layer in range(1 if level==1 else 3):
                    x=-.19+layer*.16
                    m.box("SymptomPanelFrame",pt(x,.20,1.19+layer*.10),(.33,.035,.42),"honey")
                    m.box("SymptomPane",pt(x,.19,1.19+layer*.10),(.27,.018,.34),"aqua")
                if level==2:prop(m,"ring",pt(.24,.18,1.65),.22,"wood","root")
            elif identity=="M09":
                for s in (-1,1):
                    m.line("SegmentedTrack",[pt(s*.35,-.32,.74),pt(s*.35,.3,.74)],.035,"honey")
                    for y in (-.2,0,.2):m.box("TrackNode",pt(s*.35,y,.76),(.12,.10,.06),"ivory")
                if level==2:
                    m.line("Cantilever",[pt(.37,.30,.65),pt(.37,.30,1.44),pt(0,.2,1.44)],.035,"teal")
                    for i,tool in enumerate(("comb","hinge","key")):prop(m,tool,pt(-.2+i*.2,.25,1.18),.25,"ivory","root")
            elif identity=="M37":
                for i in range(level):m.ring("ThickConditioningRing",pt(0,.1,.91+i*.38),.35,.04,"honey",rotation=(math.pi/2,0,0))
                if level==2:prop(m,"cloud",pt(.27,.22,1.47),.23,"ivory","root")
            elif identity=="M17":
                m.line("PerspectiveWindow",[pt(-.3,.26,.73),pt(-.3,.26,1.4),pt(.3,.26,1.4),pt(.3,.26,.73)],.03,"honey",cyclic=True)
                if level==2:
                    for s in (-1,1):prop(m,"star",pt(s*.22,.23,1.42),.20,"honey","root")
                    prop(m,"hats",pt(.3,-.15,.75),.32,"navy","root")
            elif identity=="EQ01":
                for s in (-1,1):
                    m.box("LocatorRuler",pt(s*.34,0,.86),(.11,d*.65,.05),"honey")
                    if level==2:
                        m.line("FoldInToolArm",[pt(s*.36,.3,.6),pt(s*.36,.3,1.30),pt(s*.20,.2,1.2)],.025,"teal")
                if level==2:
                    for i,c in enumerate(("aqua","honey","lavender")):m.ball("TeamMark",pt(-.27+i*.27,-.32,.9),(.12,.12,.03),c,"root",segments=8,rings=4)
            else:
                for i in range(4):m.box("SupportSegment",pt(0,-.28+i*.18,.73),(w*.65,d*.15,.10),"aqua")
                if level==2:
                    for s in (-1,1):prop(m,"cloud",pt(s*.36,0,.93),.36,"ivory","root")
                    prop(m,"label",pt(.28,.32,1.06),.27,"honey","root")
            key=f"{identity.lower()}_level_{level}"
            record=publish(root,m,"assets/upgrades","upgrades",key,1000)
            records.append({**record,"definition_id":identity,"level":level,
                            "description":upgrade[f"level{level}"],"static_description":upgrade[f"level{level}_static"]})
    write_json(root/"assets/upgrades/index.json",{"upgrades":records})


def surgery(root,catalog):
    records=[]
    for adapter in catalog["surgical_adapters"]:
        reset_scene();m=Model();binding=catalog["bindings_by_id"][adapter["binding_id"]]
        species=catalog["species_by_id"][binding["species_id"]]
        w,d,h=[effective_body(catalog,binding)[k] for k in ("width_m","depth_m","height_m")]
        target,s=target_for(species,binding)
        rig_kind=species["rig"]
        m.box("StableSoftSupport",(0,0,.17),(w*.92,d*.92,.30),"aqua","support",bevel=.08)
        if rig_kind=="longneck":
            for z in (h*.42,h*.65,h*.85):m.ring("UprightNeckSupport",(0,-d*.24,z),w*.13,.045,"ivory","support")
            m.rod("VerticalSupport",(w*.32,0,.2),(w*.32,0,h*.9),.04,"teal","support")
        elif rig_kind in ("float","micro","blob"):
            m.ring("ContainmentDock",(0,0,.38),max(w,d)*.35,.035,"honey","support")
        elif rig_kind=="tentacle":
            for i in range(8):
                a=i*math.tau/8
                m.ball("ArmSupport",(w*.36*math.cos(a),d*.36*math.sin(a),.30),(w*.22,d*.22,.15),"ivory","support")
        elif rig_kind=="plant":
            m.ring("StemCollar",(0,0,h*.5),w*.22,.035,"ivory","support")
        else:
            m.box("HeadSupport",(0,d*.30,.37),(w*.55,d*.23,.16),"ivory","support")
        prop(m,"frame",target,max(.12,s*.6),"honey","tool")
        mesh=m.join(adapter["id"].lower(),1200)
        skeleton=armature("Surgery",[("root",(0,0,0),None),("support",(0,0,.2),"root"),
            ("tool",target,"root"),("patient_support",(0,0,.33),"root"),
            ("symptom_target",target,"root"),("exit",(0,-d*.65,0),"root")])
        skin(mesh,skeleton)
        def pose(name,t,b):
            if name in ("prepare","safe_finish"):b["tool"].rotation_euler.y=.06*math.sin(t*math.pi)
        actions(skeleton,("prepare","process","climax","safe_finish","paused","low_motion"),pose)
        source=root/f"art-source/production/surgery/{adapter['id'].lower()}.blend"
        path=root/f"assets/surgery/{adapter['id'].lower()}.glb"
        save_blend(source);export_glb(path,[mesh,skeleton])
        records.append({"id":adapter["id"],"binding_id":binding["id"],"rig":rig_kind,
            "patient_pose":adapter["patient_pose"],"target_description":adapter["target_description"],
            "path":path.relative_to(root).as_posix(),"source_path":source.relative_to(root).as_posix(),**glb_metadata(path)})
        print("SURGERY "+adapter["id"],flush=True)
    write_json(root/"assets/surgery/index.json",{"adapters":records})


def main():
    p=argparse.ArgumentParser();p.add_argument("--root",type=Path,required=True)
    p.add_argument("--kind",choices=("library","accessories","human_looks","upgrades","surgery","gifts","all"),default="all")
    a=p.parse_args(sys.argv[sys.argv.index("--")+1:]);root=a.root.resolve();c=load_catalog(root)
    jobs={"library":lambda:library(root),"accessories":lambda:accessories(root,c),"human_looks":lambda:human_looks(root),
          "upgrades":lambda:upgrades(root,c),"surgery":lambda:surgery(root,c),
          "gifts":lambda:build_props(root,c,None)}
    for key,job in jobs.items():
        if a.kind in ("all",key):job()
    print("EXTRA_ASSETS_COMPLETE",flush=True)


if __name__=="__main__":main()
