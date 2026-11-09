"""Case-specific symptom objects, clinical tools, gifts and story keepsakes.

The source catalog owns the symptom, routine and recovery texts. Props are
presentation geometry; they never create items, actors or clinical results.
"""
import hashlib
import math

from blender_common import (Model, reset_scene, armature, skin, actions,
                            save_blend, export_glb, glb_metadata, engine_point, render_preview)
from catalog import CASE_ACTIONS, effective_body, write_json

# One authored visual vocabulary per disease, in catalog order. Bindings place
# it on the actual body structure and supply the exact authored presentation.
SYMPTOMS = """
knot tickets sun crown bat pocket smoke moon joint echo gravity star colony pseudopod loading clock clothes umbrella rain knot wave stuffing sheep note spring shoe bone bandage orbit radio beam flower yeast fold shadow punctuation tissue glasses neck lightning stomach pillow pattern yawn arrow seasons ink roots bubble static knot transparency echo footprints orbit meteor moon membrane colony braid blocks screw battery hinge echo label palette air temperature butterfly taste sticky thread proportion manual frames trailing knot ear flower sign knot roots bamboo teeth spoon knot joint fin wick armor rings tail fold cilia fog compass smoke book mirror rainbow sand noodle elastic key strings nested ink calendar drum trumpet furball spring snore echo ends bell pillow stamp faces frame stamp parade confetti weather letters buttons ruler scale planets fold greeting brackets magnify loading reboot subtitle rhyme blanket highlight hats thermometer round punctuation beard ribbon applause hourglass preview pillow countdown queue packaging stamp
""".split()
if len(SYMPTOMS)!=154:
    raise ValueError(f"Disease visual vocabulary must cover 154 definitions: {len(SYMPTOMS)}")


def prop(m,kind,center,size,color="ivory",bone="symptom"):
    x,y,z=center; s=size
    def p(a,b,c):return (x+a*s,y+b*s,z+c*s)
    if kind in ("knot","braid","noodle","strings","thread","trailing","ends","sticky","elastic","bandage"):
        points=[p(-.48,0,-.16),p(-.33,-.04,.40),p(.27,0,.38),p(.34,.04,-.25),p(-.22,0,-.27),p(-.08,-.05,.26),p(.48,0,-.12)]
        m.line(kind,points,s*.055,color,bone)
    elif kind in ("ring","rings","orbit","planet","planets","bubble","nested","membrane","loading","brackets"):
        if kind=="brackets":
            for sign in (-1,1):m.line("Bracket",[p(sign*.36,0,.4),p(sign*.49,0,0),p(sign*.36,0,-.4)],s*.035,color,bone)
        else:
            m.ring(kind,p(0,0,0),s*.32,s*.035,color,bone,(math.pi/2,.15,0))
            if kind in ("nested","rings","orbit","planets"):
                m.ring("InnerRing",p(.1,-.03,.1),s*.20,s*.027,"honey",bone,(math.pi/2,-.2,0))
            if kind in ("bubble","membrane"):
                m.ball("BubbleGlint",p(-.15,-.03,.20),(s*.10,s*.025,s*.07),"white",bone,segments=8,rings=4)
    elif kind in ("star","meteor","static","highlight","stamp","applause","sun"):
        m.star(kind,center,s*.40,color,bone,points=8 if kind in ("sun","stamp") else 5)
        if kind=="sun":
            for i in range(6):
                a=i*math.tau/6
                m.rod("Ray",p(.45*math.cos(a),0,.45*math.sin(a)),p(.60*math.cos(a),0,.60*math.sin(a)),s*.018,color,bone,vertices=5)
    elif kind in ("pocket","clothes","stuffing","blanket","pillow","yeast","softblock","crown","round"):
        m.box(kind,center,(s*.8,s*.38,s*.55),color,bone,bevel=s*.10)
        if kind in ("pillow","blanket","clothes"):
            m.line("Seam",[p(-.3,-.2,-.16),p(.3,-.2,-.16)],s*.012,"honey",bone)
        if kind=="crown":
            for i in range(3):m.ball("GrowthLobe",p((i-1)*.25,0,.15),(s*.43,s*.4,s*.35),color,bone)
    elif kind in ("ticket","tickets","label","manual","calendar","preview","subtitle","frames","packaging","confetti","letters"):
        m.box(kind,center,(s*.68,s*.035,s*.50),color,bone,bevel=s*.02)
        if kind=="calendar":m.box("CalendarTop",p(0,-.03,.19),(s*.68,s*.02,s*.10),"coral",bone)
        if kind in ("tickets","ticket","label","manual","subtitle"):
            for i in range(3):m.box("PrintedLine",p(0,-.025,.12-i*.10),(s*(.38 if i%2==0 else .25),s*.012,s*.025),"teal",bone,bevel=0)
        if kind=="preview":m.polygon("PlayGlyph",[p(-.12,-.04,-.14),p(-.12,-.04,.14),p(.15,-.04,0)],"teal",bone,s*.015)
        if kind=="packaging":
            for a in (-.36,.36):m.line("FoldLine",[p(a,-.04,-.25),p(a,-.04,.25)],s*.01,"coral",bone)
    elif kind in ("note","radio","rhyme","snore","bell","bamboo","ear"):
        m.ball("NoteHead",p(-.10,0,-.23),(s*.31,s*.12,s*.22),color,bone)
        m.rod("NoteStem",p(.03,0,-.23),p(.03,0,.38),s*.023,color,bone)
        m.line("NoteFlag",[p(.03,0,.38),p(.25,0,.27),p(.15,0,.13)],s*.035,color,bone)
    elif kind in ("flower","seasons","butterfly","roots","ink","palette","rainbow"):
        if kind in ("flower","seasons","butterfly"):
            for i in range(5 if kind!="butterfly" else 4):
                a=i*math.tau/(5 if kind!="butterfly" else 4)
                m.ball("Petal",p(.22*math.cos(a),0,.22*math.sin(a)),(s*.28,s*.08,s*.25),color,bone,segments=8,rings=4)
            m.ball("Center",center,(s*.18,s*.10,s*.18),"honey",bone,segments=8,rings=4)
        elif kind=="roots":
            for i in (-1,0,1):m.line("Root",[p(0,0,.35),p(i*.18,0,-.15),p(i*.3,0,-.4)],s*.022,color,bone)
        elif kind=="rainbow":
            for j,c in enumerate(("coral","yellow","aqua")):
                m.line("ColorArc",[p((.42-j*.07)*math.cos(a),0,(.42-j*.07)*math.sin(a)) for a in (0,math.pi/4,math.pi/2,math.pi*.75,math.pi)],s*.028,c,bone)
        else:
            m.ball("InkDrop",center,(s*.32,s*.16,s*.42),color,bone)
    elif kind in ("arrow","compass","greeting","queue","reboot","scale","countdown","sign","weather"):
        if kind=="countdown":
            for i in range(3):m.box("CountdownBar",p((i-1)*.25,0,0),(s*.13,s*.05,s*(.2+i*.13)),color,bone)
        elif kind in ("queue","scale"):
            for i in range(3):m.ball("QueueMark",p((i-1)*.27,0,0),(s*.17,s*.10,s*.17),color,bone,segments=8,rings=4)
        else:
            m.polygon("Arrow",[p(-.43,0,-.07),p(.04,0,-.07),p(.04,0,-.25),p(.42,0,0),p(.04,0,.25),p(.04,0,.07),p(-.43,0,.07)],color,bone,s*.07)
    elif kind in ("frame","mirror","glasses","transparency","fog","magnify","beam"):
        if kind in ("glasses","magnify"):
            for sign in (-1,1) if kind=="glasses" else (0,):
                m.ring("Lens",p(sign*.23,0,0),s*.19,s*.025,color,bone,(math.pi/2,0,0))
            m.rod("BridgeOrHandle",p(-.06,0,0),p(.06 if kind=="glasses" else .35,0,-.30 if kind=="magnify" else 0),s*.018,color,bone)
        else:
            m.line("Frame",[p(-.4,0,-.4),p(-.4,0,.4),p(.4,0,.4),p(.4,0,-.4)],s*.035,color,bone,cyclic=True)
            if kind in ("fog","beam"):
                for i in range(3):m.line("Beam",[p((i-1)*.18,0,-.3),p((i-1)*.22,0,.3)],s*.018,"aqua",bone)
    elif kind in ("smoke","cloud","air","yawn","echo","temperature","gravity","sand","drum","wave"):
        if kind=="smoke":
            for i in range(3):m.ring("SmokeRing",p((i-1)*.14,0,(i-1)*.24),s*(.13+i*.04),s*.022,color,bone,(math.pi/2,0,0))
        elif kind in ("air","echo","yawn","gravity","wave"):
            for i in range(3):m.line("Wave",[p(-.35,0,(i-1)*.20),p(0,-.02,(i-1)*.20+.06),p(.35,0,(i-1)*.20)],s*.022,color,bone)
        else:
            for i in range(3):m.ball("CloudLobe",p((i-1)*.22,0,(i%2)*.14),(s*.45,s*.25,s*.40),color,bone)
            if kind=="drum":m.rod("TinyDrum",p(0,-.1,-.4),p(0,-.1,-.2),s*.20,"honey",bone,vertices=10)
    elif kind in ("rain","footprints","pattern","buttons","screw","spoon","teeth","bone","joint","colony","pseudopod","cilia","faces","parade"):
        if kind in ("spoon","screw","bone","teeth"):
            m.rod(kind,p(0,0,-.4),p(0,0,.22),s*.035,color,bone,tip_radius=0 if kind=="teeth" else s*.035)
            m.ball("SpoonBowlOrHead",p(0,0,.30),(s*.24,s*.08,s*.24),color,bone)
        else:
            for i in range(3):
                m.ball(kind,p((i-1)*.27,0,(i%2)*.12),(s*.19,s*.11,s*(.28 if kind in ("rain","footprints") else .19)),color,bone,segments=8,rings=4)
                if kind=="faces":m.face(p((i-1)*.27,-.07,(i%2)*.12),s*.1,bone)
    elif kind in ("spring","ruler","proportion","hinge","key","battery","armor","blocks","stomach","neck"):
        if kind=="spring":
            m.line("Coil",[p(math.cos(i*math.pi/2)*.15,math.sin(i*math.pi/2)*.15,-.40+i*.05) for i in range(17)],s*.018,color,bone)
        elif kind=="key":
            m.ring("KeyBow",p(0,0,.2),s*.17,s*.025,color,bone,(math.pi/2,0,0))
            m.rod("KeyShaft",p(0,0,.05),p(0,0,-.4),s*.025,color,bone)
        else:
            m.box(kind,center,(s*.50,s*.20,s*.50),color,bone,bevel=s*.03)
            for i in range(3):m.box("IndexMark",p((i-1)*.13,-.11,.14),(s*.035,s*.015,s*.07),"wood",bone,bevel=0)
    elif kind in ("sheep","bat","butterfly"):
        m.ball("SoftAnimal",center,(s*.70,s*.35,s*.40),color,bone)
        m.ball("AnimalHead",p(.35,0,.1),(s*.25,s*.23,s*.25),"brown",bone)
        for sign in (-1,1):
            m.rod("AnimalLeg",p(sign*.20,0,-.13),p(sign*.20,0,-.34),s*.025,"brown",bone)
        if kind=="bat":
            for sign in (-1,1):m.polygon("BatWing",[p(0,0,.1),p(sign*.6,0,.4),p(sign*.45,0,-.15)],"purple",bone,s*.03)
    elif kind in ("tissue","fold","book","umbrella"):
        m.polygon("FoldedPaper",[p(-.4,0,-.3),p(-.05,-.1,-.25),p(.32,0,-.3),p(.4,0,.3),p(0,-.1,.36),p(-.4,0,.25)],color,bone,s*.025)
        if kind=="book":m.line("BookSpine",[p(0,-.12,-.3),p(0,-.12,.35)],s*.018,"wood",bone)
        if kind=="umbrella":m.rod("UmbrellaStem",p(0,0,-.5),p(0,0,.1),s*.02,"wood",bone)
    elif kind in ("punctuation","trumpet","thermometer","wick","beard","fin","tail","hats","ribbon","taste","lightning","furball","braid"):
        if kind=="punctuation":
            m.rod("Exclamation",p(0,0,-.02),p(0,0,.42),s*.06,color,bone,tip_radius=s*.10)
            m.ball("Dot",p(0,0,-.25),(s*.17,s*.10,s*.17),color,bone)
        elif kind=="hats":
            m.box("HatBrim",p(0,0,-.1),(s*.7,s*.3,s*.06),color,bone)
            m.box("TopHat",p(0,0,.13),(s*.35,s*.24,s*.42),color,bone)
        elif kind in ("fin","tail","lightning"):
            m.polygon(kind,[p(-.25,0,-.4),p(.17,0,-.08),p(-.1,0,.02),p(.27,0,.40),p(.02,0,.08),p(.25,0,-.02)],color,bone,s*.04)
        else:m.line(kind,[p(-.4,0,.18),p(-.2,0,-.13),p(.12,0,.14),p(.38,0,-.15)],s*.04,color,bone)
    elif kind in ("comb","soft_tool"):
        m.box("CombBack",p(0,0,.1),(s*.7,s*.13,s*.1),color,bone)
        for i in range(5):m.rod("CombTooth",p((i-2)*.13,0,.08),p((i-2)*.13,0,-.25),s*.018,color,bone)
    elif kind=="hourglass":
        for z0 in (-.3,.3):m.box("HourglassCap",p(0,0,z0),(s*.47,s*.3,s*.045),color,bone)
        m.rod("HourglassTop",p(0,0,0),p(0,0,.28),s*.015,"honey",bone,tip_radius=s*.17)
        m.rod("HourglassBottom",p(0,0,-.28),p(0,0,0),s*.17,"honey",bone,tip_radius=s*.015)
    elif kind=="moon":
        m.line("Crescent",[p(.3*math.cos(a),0,.4*math.sin(a)) for a in
                (math.pi*.25,math.pi*.6,math.pi,math.pi*1.4,math.pi*1.75)],s*.07,color,bone)
    elif kind=="clock":
        m.ring("ClockDial",center,s*.33,s*.035,color,bone,(math.pi/2,0,0))
        m.line("ClockHands",[p(0,0,.25),p(0,0,0),p(.18,0,.06)],s*.025,"wood",bone)
    elif kind=="shadow":
        m.ball("DetachedShadow",p(0,0,-.10),(s*.65,s*.06,s*.45),"navy",bone)
        m.ball("ShadowHead",p(0,0,.24),(s*.29,s*.06,s*.28),"navy",bone)
    elif kind=="shoe":
        m.box("SkateBoot",p(0,0,.10),(s*.35,s*.32,s*.30),color,bone,bevel=s*.06)
        m.line("SkateBlade",[p(-.35,0,-.17),p(-.2,0,-.25),p(.35,0,-.25)],s*.025,"silver",bone)
    elif kind=="seed":
        m.ball("Seed",center,(s*.22,s*.12,s*.35),"honey",bone,segments=8,rings=4)
    elif kind=="plantpot":
        m.rod("EmptyPot",p(0,0,-.33),p(0,0,.22),s*.23,"ivory",bone,tip_radius=s*.34,vertices=10)
        m.ring("PotRim",p(0,0,.24),s*.32,s*.028,"honey",bone)
        m.rod("PotInside",p(0,0,.235),p(0,0,.245),s*.26,"brown",bone,vertices=10)
    elif kind=="ice":
        from blender_common import vertex_material
        block=m.box("IceShell",center,(s*.75,s*.65,s*.94),"aqua",bone,bevel=s*.06)
        block.data.materials[0]=vertex_material(True)
        for sign in (-1,1):m.line("FrostEdge",[p(sign*.32,-.34,-.4),p(sign*.32,-.34,.4)],s*.016,"white",bone)
    elif kind=="flag":
        m.rod("FlagPole",p(-.3,0,-.45),p(-.3,0,.45),s*.025,"wood",bone)
        m.polygon("WhiteFlag",[p(-.3,0,.42),p(.4,0,.3),p(-.3,0,.12)],"ivory",bone,s*.02)
    elif kind in ("broom","paintroller","wrench","stethoscope","cup","eye_mask"):
        if kind=="broom":
            m.rod("BroomHandle",p(0,0,-.20),p(0,0,.5),s*.025,"wood",bone)
            m.box("SoftBroom",p(0,0,-.3),(s*.45,s*.16,s*.23),"honey",bone)
        elif kind=="paintroller":
            m.line("RollerHandle",[p(-.1,0,-.4),p(-.1,0,.2),p(.2,0,.2)],s*.022,"wood",bone)
            m.rod("Roller",p(.05,0,.2),p(.4,0,.2),s*.08,"coral",bone)
        elif kind=="wrench":
            m.rod("WrenchHandle",p(0,0,-.4),p(0,0,.2),s*.045,"silver",bone)
            m.line("WrenchJaw",[p(-.15,0,.40),p(-.18,0,.17),p(.18,0,.17),p(.15,0,.40)],s*.045,"silver",bone)
        elif kind=="stethoscope":
            m.line("ScopeTube",[p(-.2,0,.35),p(-.25,0,-.1),p(.15,0,-.25),p(.25,0,.10)],s*.022,"navy",bone)
            m.ring("ScopeHead",p(.25,0,.17),s*.10,s*.024,"honey",bone,(math.pi/2,0,0))
        elif kind=="cup":
            m.rod("CupBody",p(0,0,-.25),p(0,0,.25),s*.22,"ivory",bone,tip_radius=s*.27,vertices=12)
            m.ring("CupHandle",p(.29,0,0),s*.14,s*.025,"honey",bone,(math.pi/2,0,0))
        else:
            m.ball("SleepMask",center,(s*.7,s*.12,s*.27),"navy",bone)
            for sign in (-1,1):m.line("MaskEye",[p(sign*.2-.06,-.07,0),p(sign*.2,-.08,-.04),p(sign*.2+.06,-.07,0)],s*.012,"ivory",bone)
    else:
        raise ValueError("Unimplemented visual object: "+kind)


def target_for(species,binding):
    w,d,h=[species["body"][k] for k in ("width_m","depth_m","height_m")]
    text=binding["symptom_variant"]
    if species["rig"]=="micro":return (0,-d*.1,h*.51),min(w,h)*.34
    height=.73
    if any(k in text for k in ("脚","鞋","纤毛","重心")):height=.17
    elif any(k in text for k in ("尾","鳍")):return (w*.18,d*.29,h*.46),min(w,h)*.40
    elif any(k in text for k in ("胸","肚","口袋","衣","绷带","纽扣")):height=.52
    elif any(k in text for k in ("头顶","帽","树冠","花瓣","星环","梦")):height=.90
    if species["rig"]=="longneck" and "颈" in text:height=.74
    return (0,-d*.38,h*height),min(w,h)*.44


def build_cases(root,catalog,wanted,preview=False,resume=False):
    index=root/"assets/cases/index.json"
    import json
    previous=json.loads(index.read_text(encoding="utf-8")) if index.exists() else {"cases":[]}
    records={r["id"]:r for r in previous["cases"]}
    rendered=set()
    for binding in catalog["treatment_bindings"]:
        identity=binding["id"]
        if wanted and identity not in wanted:continue
        preview_path=root/f".cache/asset-previews/disease_{binding['disease_id'].lower()}.png"
        needs_preview=preview and binding["disease_id"] not in rendered and not preview_path.exists()
        if resume and identity in records and not needs_preview:
            old=root/records[identity]["path"]
            if old.exists() and hashlib.sha256(old.read_bytes()).hexdigest()==records[identity]["sha256"]:
                rendered.add(binding["disease_id"])
                continue
        reset_scene();m=Model()
        species=catalog["species_by_id"][binding["species_id"]]
        disease=catalog["diseases_by_id"][binding["disease_id"]]
        target,s=target_for(species,binding)
        visual=SYMPTOMS[int(binding["disease_id"][1:])-1]
        primary=("coral","honey","aqua","lavender")[int(binding["disease_id"][1:])%4]
        prop(m,visual,target,s,primary,"symptom")
        routine=next(r for r in catalog["treatment_routines"] if r["id"]==binding["routine_id"])
        text=binding["treatment_variant"]+"".join(routine["beats"])
        tool=next((shape for words,shape in (("梳齿梳子","comb"),("软环光环套环","ring"),
            ("小镜观察框","frame"),("夹子拼装","hinge"),("纸页折叠","fold"),("枕羊梦","pillow"),
            ("水滴雨","rain"),("节拍音","note"),("标签贴纸","label"),("刻度尺","ruler"))
            if any(word in text for word in (words[:2],words[2:]))),"soft_tool")
        tool_center=(target[0]+s*.45,target[1]+s*.05,target[2]+s*.12)
        prop(m,tool,tool_center,s*.65,"ivory","tool")
        # Recovery is a settled version of the original structure. It is only
        # visible in the explicit cured/recovery clip, never in safe_finish.
        prop(m,visual,target,s*.62,"aqua","recovered")
        mesh=m.join(identity.lower(),1000)
        rig=armature("Case",[("root",(0,0,0),None),("symptom",target,"root"),
                              ("tool",tool_center,"root"),("recovered",target,"root"),
                              ("symptom_target",target,"root")])
        skin(mesh,rig)
        def pose(action,t,b):
            cured=action in ("recovery","recovery_hold","low_motion_recovery")
            b["symptom"].scale=(.001,)*3 if cured else (1,)*3
            b["recovered"].scale=(1,)*3 if cured else (.001,)*3
            working=action in ("prepare","process","climax","work","low_motion_work","safe_finish") or action.startswith("gentle_")
            b["tool"].scale=(1,)*3 if working else (.001,)*3
            low=action.startswith("low_motion") or action in ("paused","awaiting_result","recovery_hold")
            gentle=action.startswith("gentle_")
            amplitude=.035 if gentle else .10
            if not low and not cured:b["symptom"].rotation_euler.y=amplitude*math.sin(t*math.tau)
            if working and not low:
                b["tool"].rotation_euler.x=amplitude*.8*math.sin(t*math.pi)
            if action.endswith("safe_finish"):
                b["tool"].scale=(max(.001,1-t),)*3
        actions(rig,CASE_ACTIONS,pose)
        source=root/f"art-source/production/cases/{identity.lower()}.blend"
        target_path=root/f"assets/cases/{identity.lower()}.glb"
        save_blend(source);export_glb(target_path,[mesh,rig])
        info=glb_metadata(target_path)
        if set(CASE_ACTIONS)-set(info["animation_names"]):raise ValueError("Case clips missing "+identity)
        records[identity]={"id":identity,"species_id":binding["species_id"],"disease_id":binding["disease_id"],
            "routine_id":binding["routine_id"],"path":target_path.relative_to(root).as_posix(),
            "source_path":source.relative_to(root).as_posix(),"visual_structure":visual,"tool":tool,
            "symptom":binding["symptom_variant"],"treatment":binding["treatment_variant"],
            "recovery":binding["recovery_variant"],"effective_body":effective_body(catalog,binding),
            "target_engine_m":engine_point(target),"rig":species["rig"],
            "outcome_visibility":{"safe_finish":"symptom retained; tools retract",
                "awaiting_result":"neutral; no success or failure reveal", "failure":"symptom retained",
                "recovery":"settled structure; only after cured"},**info}
        if needs_preview:
            import bpy
            rig.animation_data.action=bpy.data.actions.get("symptom")
            bpy.context.scene.frame_set(1)
            render_preview(preview_path,mesh)
        rendered.add(binding["disease_id"])
        if len(records)%8==0 or wanted:
            write_json(index,{"schema":1,"cases":sorted(records.values(),key=lambda r:r["id"])})
        print("CASE "+identity+" "+visual+" "+str(info["triangles"]),flush=True)
    write_json(index,{"schema":1,"cases":sorted(records.values(),key=lambda r:r["id"])})


def gift_geometry(m,name,number):
    color=("aqua","coral","honey","lavender")[number%4]
    if any(word in name for word in ("瓶","罐","茶筒","杯","蜂蜜","果酱","咖啡")):
        m.rod("GiftJar",(0,0,.02),(0,0,.35),.13,"ivory",vertices=12)
        m.rod("JarLid",(0,0,.35),(0,0,.40),.14,color,vertices=12)
        m.box("HandwrittenLabel",(0,-.135,.21),(.17,.015,.16),color)
        token="star" if any(w in name for w in ("星","光","梦")) else ("rain" if "雨" in name else "flower")
        prop(m,token,(0,-.15,.21),.12,"honey","root")
    elif any(word in name for word in ("书","卡","贴纸","谱","册","日记","车票","画","明信片","章","牌","徽")):
        prop(m,"book" if any(w in name for w in ("书","册","日记")) else "label",(0,0,.18),.43,color,"root")
        prop(m,"star" if "星" in name else "stamp",(0,-.04,.18),.18,"honey","root")
    elif any(word in name for word in ("线","结","围巾","丝带","织带","穗","串")):
        prop(m,"knot",(0,0,.20),.47,color,"root")
    elif any(word in name for word in ("盆","花","萝卜","香袋","柚子","果干","茶","草")):
        m.rod("GiftPot",(0,0,.01),(0,0,.19),.10,"ivory",tip_radius=.15)
        from blender_equipment import flower
        flower(m,(0,0,.45),color)
    elif any(word in name for word in ("琴","钟","盒","箱","架","积木","录音带")):
        m.box("KeepsakeBox",(0,0,.14),(.36,.27,.25),color,bevel=.035)
        m.box("BoxLid",(0,0,.29),(.38,.29,.045),"honey")
        prop(m,"note" if any(w in name for w in ("音","琴","钟","录音")) else "star",(0,-.15,.15),.14,"ivory","root")
    elif any(word in name for word in ("枕","垫","布","棉")):
        prop(m,"pillow",(0,0,.12),.48,color,"root")
    elif any(word in name for word in ("贝","环","碟","托","玻璃","涟漪")):
        prop(m,"rings",(0,0,.18),.45,color,"root")
    elif "梳" in name:prop(m,"comb",(0,0,.18),.45,color,"root")
    elif any(word in name for word in ("像","羊")):prop(m,"sheep",(0,0,.20),.43,color,"root")
    else:
        m.ball("KeepsakeStone",(0,0,.13),(.33,.28,.24),color,"root",segments=10,rings=5)
        prop(m,"stamp",(0,-.14,.16),.14,"honey","root")
    # Maker's small decorative seal varies with the real species identity.
    for i in range(1+number%3):
        m.ball("MakerSeal",((i-1)*.035,-.16,.05),(.017,.01,.017),"honey","root",segments=6,rings=3)


def build_props(root,catalog,wanted,preview=False):
    records=[]
    gifts=[(g["id"],g["name"],"species_gifts",i+1) for i,g in enumerate(catalog["species_gifts"])]
    gifts += [(s["id"],s["reward_text"].split("；")[0],"mementos",i+81) for i,s in enumerate(catalog["stories"])]
    for identity,name,group,number in gifts:
        if wanted and identity not in wanted:continue
        reset_scene();m=Model();gift_geometry(m,name,number)
        mesh=m.join(identity.lower(),600)
        source=root/f"art-source/production/props/{group}/{identity.lower()}.blend"
        target=root/f"assets/props/{group}/{identity.lower()}.glb"
        save_blend(source);export_glb(target,[mesh])
        records.append({"id":identity,"name":name,"group":group,
            "path":target.relative_to(root).as_posix(),"source_path":source.relative_to(root).as_posix(),**glb_metadata(target)})
        print("PROP "+identity+" "+name,flush=True)
    write_json(root/"assets/props/index.json",{"props":records})
