"""Eighty authored silhouettes and nine semantic rig configurations."""
import math

from blender_common import Model, armature, skin, actions
from catalog import BODY_ACTIONS


def definitions(kind):
    bones = [("root", (0, 0, 0), None), ("hips", (0, 0, .42), "root"),
             ("spine", (0, 0, .62), "hips"), ("neck", (0, 0, .76), "spine"),
             ("head", (0, -.02, .83), "neck")]
    for side, sign in (("l", -1), ("r", 1)):
        bones += [("upper_arm_" + side, (sign * .25, 0, .69), "spine"),
                  ("forearm_" + side, (sign * .36, 0, .54), "upper_arm_" + side),
                  ("hand_" + side, (sign * .40, -.03, .42), "forearm_" + side),
                  ("thigh_" + side, (sign * .17, 0, .42), "hips"),
                  ("shin_" + side, (sign * .17, 0, .23), "thigh_" + side),
                  ("foot_" + side, (sign * .17, -.08, .07), "shin_" + side)]
    if kind in ("quadruped", "longneck"):
        bones = [("root", (0, 0, 0), None), ("hips", (0, .16, .48), "root"),
                 ("spine", (0, 0, .55), "hips"),
                 ("neck", (0, -.25, .58 if kind == "quadruped" else .45), "spine"),
                 ("neck_mid", (0, -.29, .73), "neck"),
                 ("head", (0, -.33, .78 if kind == "quadruped" else .91), "neck_mid")]
        for side, sign in (("l", -1), ("r", 1)):
            for limb, y in (("front", -.25), ("hind", .25)):
                root = "spine" if limb == "front" else "hips"
                bones += [(limb + "_upper_" + side, (sign * .24, y, .47), root),
                          (limb + "_lower_" + side, (sign * .24, y, .24), limb + "_upper_" + side),
                          (limb + "_paw_" + side, (sign * .24, y - .025, .08), limb + "_lower_" + side)]
        bones += [("tail", (0, .36, .5), "hips")]
        bones += [("hand_l", (-.3, -.3, .1), "front_paw_l"),
                  ("hand_r", (.3, -.3, .1), "front_paw_r")]
    elif kind == "tentacle":
        bones = [("root", (0, 0, 0), None), ("hips", (0, 0, .3), "root"),
                 ("spine", (0, 0, .55), "hips"), ("neck", (0, 0, .7), "spine"),
                 ("head", (0, 0, .78), "neck")]
        for i in range(8):
            a = math.tau * i / 8
            bones += [(f"arm_{i}", (.15 * math.cos(a), .15 * math.sin(a), .35), "hips"),
                      (f"tip_{i}", (.33 * math.cos(a), .33 * math.sin(a), .14), f"arm_{i}")]
        bones += [("hand_l", (-.4, -.2, .12), "tip_5"), ("hand_r", (.4, -.2, .12), "tip_7")]
    elif kind in ("plant", "float", "blob", "object", "micro"):
        bones = [("root", (0, 0, 0), None), ("hips", (0, 0, .28), "root"),
                 ("spine", (0, 0, .5), "hips"), ("neck", (0, 0, .68), "spine"),
                 ("head", (0, 0, .78), "neck"),
                 ("hand_l", (-.28, -.05, .42), "spine"),
                 ("hand_r", (.28, -.05, .42), "spine"),
                 ("foot_l", (-.18, 0, .07), "hips"),
                 ("foot_r", (.18, 0, .07), "hips"),
                 ("lid", (0, .13, .7), "head"), ("display", (0, -.3, .6), "spine")]
        if kind == "micro":
            bones += [(f"colony_{i}", ((i % 3 - 1) * .16, (i // 3) * .1, .4 + (i % 2) * .1), "spine") for i in range(6)]
    bones += [("look_target", (0, -.55, .85), "head"),
              ("treatment_anchor", (0, -.4, .57), "spine"),
              ("emotion_anchor", (0, 0, 1.04), "head"),
              ("carry_anchor", (.30, -.1, .5), "spine")]
    return bones


def biped(m, identity):
    color = {4:"navy",8:"wood",9:"lavender",10:"mint",12:"brown",13:"mint",15:"ivory",
             16:"ivory",17:"purple",25:"aqua",35:"white",38:"honey",41:"honey",42:"blue",
             49:"skin",55:"leaf",59:"stone",60:"skin",62:"silver",65:"lavender",75:"rose",77:"wood",79:"ivory"}[identity]
    squared = identity in (25,42,59,62,65,77)
    body = m.box if squared else m.ball
    body("Torso", (0, 0, .55), (.49, .37, .38), color, "spine")
    body("Head", (0, -.015, .85), (.48, .41, .31), color, "head")
    for side, sign in (("l",-1),("r",1)):
        if identity != 60:
            m.rod("LegUpper", (sign*.16,0,.40),(sign*.17,0,.23),.085,color,"thigh_"+side)
            m.rod("LegLower", (sign*.17,0,.23),(sign*.17,0,.08),.067,color,"shin_"+side)
            m.ball("Foot",(sign*.17,-.08,.065),(.19,.28,.13),"orange" if identity==4 else color,"foot_"+side)
        m.rod("ArmUpper",(sign*.24,0,.70),(sign*.35,0,.54),.075,color,"upper_arm_"+side)
        m.rod("ArmLower",(sign*.35,0,.54),(sign*.39,-.03,.43),.06,color,"forearm_"+side)
        m.ball("Hand",(sign*.4,-.03,.42),(.15,.15,.14),color,"hand_"+side)
    if identity==4:
        m.ball("WhiteBreast",(0,-.175,.54),(.36,.08,.36),"white","spine")
        m.rod("Beak",(0,-.19,.82),(0,-.34,.80),.085,"orange","head",tip_radius=0)
    if identity in (9,10,12,13,49,77):
        m.box("Shirt",(0,-.035,.55),(.48,.36,.30),"navy" if identity==9 else "teal","spine")
        m.box("Collar",(0,-.225,.68),(.19,.035,.06),"white","spine")
        for x in (-.055,.055):
            m.ball("Button",(x,-.227,.56),(.025,.016,.025),"honey","spine",segments=6,rings=3)
    if identity in (9,12,41,75):
        for s in (-1,1):
            m.ball("Ear",(s*.23,0,.99),(.18,.17,.22 if identity in (12,9) else .15),color,"head")
    if identity==8:
        for x,z,r in ((-.19,.96,.22),(0,1.04,.25),(.21,.96,.22)):
            m.ball("Crown",(x,.03,z),(r*1.4,.32,r*1.3),"leaf","head")
        for s in (-1,1):
            m.rod("Branch",(s*.32,0,.62),(s*.48,0,.76),.035,"wood","hand_"+("l" if s<0 else "r"))
    elif identity==9:
        m.polygon("Cape",[(-.37,.13,.73),(0,.16,.80),(.37,.13,.73),(.40,.18,.22),(-.40,.18,.22)],"red","spine")
        m.box("Hair",(0,.0,.99),(.45,.36,.08),"ink","head")
        for s in (-1,1):
            m.rod("Fang",(s*.07,-.233,.78),(s*.07,-.237,.74),.018,"white","head",tip_radius=0)
    elif identity==10:
        for s in (-1,1):
            m.polygon("GoblinEar",[(s*.20,0,.91),(s*.44,0,.95),(s*.27,0,.78)],"mint","head")
        m.box("Pocket",(.18,-.24,.51),(.16,.08,.15),"brown","spine")
    elif identity==12:
        m.ball("Muzzle",(0,-.23,.80),(.31,.21,.16),"ivory","head")
        m.ball("Nose",(0,-.34,.84),(.12,.07,.07),"ink","head")
        m.line("Tail",[(0,.17,.48),(.3,.34,.39),(.40,.4,.57)],.075,"brown","hips")
    elif identity==13:
        m.line("Stitch",[(-.14,-.23,.92),(.03,-.23,.95),(.11,-.23,.92)],.008,"ink","head")
        m.box("Hair",(0,.015,1),(.43,.37,.06),"brown","head")
    elif identity==15:
        for z in (.48,.55,.62):
            m.line("Ribs",[(-.19,-.18,z),(0,-.22,z+.025),(.19,-.18,z)],.018,"white","spine")
        m.ball("NoseHole",(0,-.22,.82),(.05,.025,.04),"ink","head",segments=6,rings=3)
    elif identity==16:
        for z in (.44,.51,.59,.66,.78,.85,.94):
            m.line("Bandage",[(-.2,-.17,z),(0,-.22,z-.025),(.2,-.17,z-.04)],.018,"white","head" if z>.75 else "spine")
        m.line("BandageTail",[(.22,0,.57),(.4,.13,.4),(.46,.12,.46)],.025,"ivory","forearm_r")
    elif identity==17:
        for s in (-1,1):
            m.line("Antenna",[(s*.13,0,.98),(s*.23,0,1.13)],.018,"purple","head")
            m.ball("AntennaTip",(s*.23,0,1.13),(.10,.1,.1),"honey","head")
    elif identity==25:
        m.box("Display",(0,-.23,.86),(.37,.035,.21),"navy","head")
        m.box("ChestScreen",(0,-.21,.57),(.25,.035,.14),"navy","spine")
        m.line("Signal",[(-.09,-.24,.56),(-.04,-.24,.56),(0,-.24,.62),(.04,-.24,.52),(.09,-.24,.56)],.012,"aqua","spine")
    elif identity==35:
        m.ball("SnowBelly",(0,0,.38),(.65,.53,.5),"white","hips")
        m.rod("CarrotNose",(0,-.22,.84),(0,-.44,.83),.06,"orange","head",tip_radius=0)
        m.ring("Scarf",(0,0,.71),.22,.045,"coral","neck")
        for z in (.44,.55,.64):
            m.ball("CoalButton",(0,-.28,z),(.05,.025,.05),"ink","spine",segments=6,rings=3)
    elif identity==38:
        m.box("ToastCrust",(0,.02,.73),(.60,.36,.62),"wood","spine",bevel=.10)
        m.box("ToastCenter",(0,-.17,.74),(.50,.025,.50),"honey","spine",bevel=.06)
    elif identity==41:
        m.ball("Muzzle",(0,-.22,.79),(.24,.09,.13),"ivory","head")
        m.line("Seam",[(0,-.20,.44),(0,-.20,.61)],.009,"brown","spine")
        m.ring("Bow",(0,-.21,.68),.065,.018,"coral","spine",(math.pi/2,0,0))
    elif identity==42:
        m.rod("HeadStud",(0,0,1),(0,0,1.08),.1,"honey","head")
        m.box("WaistBrick",(0,0,.41),(.48,.37,.11),"coral","hips")
    elif identity==49:
        m.ball("Hair",(0,.025,.97),(.48,.40,.17),"brown","hair")
        m.box("Trousers",(0,0,.38),(.40,.33,.14),"navy","hips")
    elif identity==55:
        for z in (.13,.30,.48,.66,.83,.96):
            m.ring("BambooNode",(0,0,z),.135,.026,"honey","spine" if z<.75 else "head")
        for s in (-1,1):
            m.polygon("BambooLeaf",[(s*.16,0,.94),(s*.39,0,1.08),(s*.28,0,.88)],"mint","head")
    elif identity==59:
        for s in (-1,1):
            m.box("ShoulderBoulder",(s*.30,0,.69),(.24,.37,.25),"stone","upper_arm_"+("l" if s<0 else "r"),bevel=.07)
        m.line("StoneCrack",[(-.15,-.205,.97),(-.10,-.22,.91),(-.16,-.22,.87)],.01,"brown","head")
        m.ball("Moss",(.19,-.18,.65),(.12,.04,.12),"leaf","spine")
    elif identity==60:
        m.rod("FishTail",(0,0,.5),(0,.12,.10),.20,"teal","hips",tip_radius=.07)
        for s in (-1,1):
            m.polygon("TailFin",[(0,.1,.13),(s*.31,.2,.02),(s*.15,.05,.22)],"aqua","hips")
        m.ball("Hair",(0,.09,.88),(.50,.35,.39),"red","head")
    elif identity==62:
        m.box("Helmet",(0,0,.88),(.50,.42,.31),"silver","head")
        m.box("VisorVoid",(0,-.223,.86),(.35,.025,.10),"ink","head")
        m.rod("Plume",(0,.02,1),(0,.06,1.15),.06,"coral","head")
        for s in (-1,1):
            m.ball("Pauldron",(s*.30,0,.72),(.22,.42,.23),"silver","upper_arm_"+("l" if s<0 else "r"))
    elif identity==65:
        for s in (-1,1):
            m.polygon("FoldedHead",[(0,-.3,1.12),(s*.30,.03,.83),(0,-.2,.75)],"purple","head",.06)
            m.polygon("Pleat",[(0,-.23,.64),(s*.3,-.1,.7),(s*.19,-.2,.43)],"lavender","spine")
    elif identity==75:
        m.ball("GummyMuzzle",(0,-.22,.80),(.22,.10,.12),"rose","head")
        m.ball("JellyGlint",(-.12,-.19,.97),(.09,.02,.05),"white","head",segments=8,rings=4)
    elif identity==77:
        m.rod("ToyNose",(0,-.22,.83),(0,-.35,.82),.035,"honey","head")
        m.box("Vest",(0,-.2,.56),(.30,.04,.22),"coral","spine")
        for s in (-1,1):
            m.ball("WoodJoint",(s*.35,-.02,.54),(.13,.15,.13),"honey","forearm_"+("l" if s<0 else "r"))
    elif identity==79:
        for s in (-1,1):
            m.line("DrawnOutline",[(s*.16,-.21,.96),(s*.22,-.21,.83),(s*.17,-.21,.72)],.022,"ink","head")
        m.box("PaintSwatch",(0,-.21,.56),(.32,.03,.15),"coral","spine")
    front = -.25 if identity not in (38,60) else -.23
    m.face((0,front,.86),.27,eyes=3 if identity==17 else 2)


def quadruped(m, identity):
    color={1:"honey",3:"brown",11:"mint",50:"orange",51:"brown",53:"stone",58:"white",64:"navy"}[identity]
    long = identity==1
    m.ball("Torso",(0,.05,.45),(.68,.72,.43 if long else .54),color,"spine")
    for side,s in (("l",-1),("r",1)):
        for limb,y in (("front",-.23),("hind",.27)):
            m.rod("LegUpper",(s*.24,y,.46),(s*.24,y,.25),.064 if long else .09,color,limb+"_upper_"+side)
            m.rod("LegLower",(s*.24,y,.25),(s*.24,y,.08),.048 if long else .07,color,limb+"_lower_"+side)
            m.ball("Paw",(s*.24,y-.03,.065),(.16,.20,.13),"wood" if long else color,limb+"_paw_"+side)
    if long:
        for a,b,bone in (((0,-.23,.50),(0,-.27,.74),"neck"),((0,-.27,.74),(0,-.32,.95),"neck_mid")):
            m.rod("LongNeck",a,b,.10,color,bone,tip_radius=.085)
        m.ball("Head",(0,-.34,.98),(.29,.32,.15),color,"head")
        for s in (-1,1):
            m.rod("Ossicone",(s*.075,-.30,1.03),(s*.075,-.3,1.13),.022,"wood","head")
            m.ball("Ear",(s*.16,-.29,1.03),(.14,.06,.07),"honey","head")
        for i in range(8):
            z=.55+i*.05
            m.ball("NeckSpot",((-.055 if i%2 else .055),-.355,z),(.06,.016,.035),"wood","neck" if z<.75 else "neck_mid",segments=6,rings=3)
        facez,facey=.98,-.5
    else:
        m.ball("Head",(0,-.27,.74),(.58,.47,.41),color,"head")
        m.ball("Muzzle",(0,-.48,.66),(.41,.23,.22),"ivory" if identity in (50,58,64) else color,"head")
        for s in (-1,1):
            m.ball("Ear",(s*.23,-.16,.92),(.18,.11,.17),color,"head")
        facez,facey=.78,-.49
    if identity==3:
        m.ball("CapyNose",(0,-.58,.70),(.20,.08,.10),"brown","head")
    elif identity==11:
        for s in (-1,1):
            m.polygon("DragonWing",[(s*.18,.10,.60),(s*.55,.10,.96),(s*.48,.32,.48)],"teal","spine",.04)
            m.rod("Horn",(s*.19,-.16,.91),(s*.23,-.09,1.10),.05,"honey","head",tip_radius=0)
        m.line("DragonTail",[(0,.38,.49),(.12,.56,.35),(.35,.65,.5)],.06,"mint","tail")
    elif identity==50:
        for s in (-1,1):
            m.ball("WhiteMask",(s*.15,-.48,.78),(.19,.045,.19),"white","head")
        m.line("FluffyTail",[(0,.34,.44),(.25,.48,.40),(.43,.48,.63)],.11,"orange","tail")
        for i in range(4):
            m.ball("TailRing",(.12+i*.085,.43+i*.016,.40+i*.045),(.13,.2,.06),"brown","tail",segments=8,rings=4)
    elif identity==51:
        for i in range(18):
            x=(i%6-2.5)*.105; y=(i//6-1)*.15+.08
            m.rod("SoftSpine",(x,y,.64),(x*1.25,y+.03,.83+(i%2)*.08),.04,"honey","spine",tip_radius=0,vertices=5)
    elif identity==53:
        for s in (-1,1):
            m.ball("ElephantEar",(s*.34,-.17,.74),(.36,.17,.43),"stone","head")
            m.rod("Tusk",(s*.15,-.48,.63),(s*.20,-.60,.51),.035,"ivory","head",tip_radius=0)
        m.line("Trunk",[(0,-.48,.69),(0,-.58,.43),(.12,-.61,.28),(.19,-.63,.39)],.075,"stone","head")
    elif identity==58:
        m.rod("UnicornHorn",(0,-.30,.92),(0,-.35,1.20),.07,"honey","head",tip_radius=0)
        m.line("Mane",[(0,-.06,.95),(0,.04,.75),(0,.15,.65)],.065,"lavender","neck")
        m.line("UnicornTail",[(0,.36,.51),(.10,.55,.48),(.2,.59,.28)],.055,"lavender","tail")
    elif identity==64:
        for s in (-1,1):
            m.polygon("CatEar",[(s*.1,-.18,.87),(s*.24,-.13,1.05),(s*.29,-.10,.87)],"navy","head")
        m.line("CometTail",[(0,.36,.5),(.25,.6,.63),(.49,.65,.86)],.07,"blue","tail")
        m.star("TailStar",(.48,.65,.86),.12,"yellow","tail")
    m.face((0,facey,facez),.30)


def plant(m, identity):
    if identity==5:
        m.rod("Stem",(0,0,.08),(0,0,.75),.055,"leaf","spine")
        for i in range(12):
            a=i*math.tau/12
            m.ball("Petal",(.27*math.cos(a),0,.78+.21*math.sin(a)),(.20,.09,.16),"yellow","head",segments=8,rings=4)
        m.ball("SeedFace",(0,-.055,.78),(.4,.13,.35),"brown","head")
    elif identity==6:
        m.rod("MushroomStalk",(0,0,.08),(0,0,.70),.16,"ivory","spine",tip_radius=.12)
        m.ball("MushroomCap",(0,0,.77),(.92,.64,.42),"red","head")
        for x,y,z in ((-.27,-.12,.88),(0,-.27,.87),(.27,-.12,.87),(0,.08,.98)):
            m.ball("CapSpot",(x,y,z),(.16,.13,.035),"ivory","head",segments=8,rings=4)
    elif identity==7:
        m.ball("CactusBody",(0,0,.51),(.42,.40,.85),"leaf","spine")
        for side,s in (("l",-1),("r",1)):
            m.line("CactusArm",[(s*.16,0,.42),(s*.34,0,.43),(s*.34,0,.72)],.08,"leaf","hand_"+side)
        for x,z in ((-.13,.32),(.11,.40),(-.10,.64),(.09,.75)):
            m.rod("CactusSpine",(x,-.19,z),(x,-.25,z+.025),.012,"ivory","spine",tip_radius=0,vertices=5)
    elif identity==54:
        m.rod("Carrot",(0,0,.12),(0,0,.70),.03,"orange","spine",tip_radius=.24)
        for i in range(5):
            a=math.tau*i/5
            m.line("CarrotLeaf",[(0,0,.68),(.15*math.cos(a),.10*math.sin(a),.90),(.24*math.cos(a),.13*math.sin(a),1.03)],.035,"leaf","head")
    elif identity==56:
        m.rod("PlantStem",(0,0,.09),(0,0,.64),.09,"leaf","spine")
        for s in (-1,1):
            m.ball("FlytrapJaw",(s*.19,0,.77),(.36,.43,.39),"leaf","head")
            m.ball("JawInside",(s*.16,-.17,.77),(.26,.07,.28),"red","head")
            for z in (.64,.74,.84,.94):
                m.rod("SoftTooth",(s*.1,-.22,z),(s*.015,-.22,z+.015),.025,"ivory","head",tip_radius=0,vertices=5)
    for side,s in (("l",-1),("r",1)):
        if identity!=7:
            m.polygon("LeafHand",[(0,0,.42),(s*.37,0,.55),(s*.29,-.02,.33)],"mint","hand_"+side)
        m.ball("RootFoot",(s*.13,-.03,.05),(.25,.34,.1),"wood" if identity!=54 else "orange","foot_"+side)
    m.face((0,-.22,.51 if identity in (6,54) else .77),.25,"spine" if identity in (6,54) else "head")


def tentacle(m, identity):
    jelly=identity==20
    m.ball("Bell" if jelly else "OctopusHead",(0,0,.70 if jelly else .64),(.61,.59,.47 if jelly else .64),"aqua" if jelly else "rose","head")
    for i in range(8):
        a=math.tau*i/8; x,y=math.cos(a),math.sin(a)
        m.line("Tentacle",[(x*.16,y*.16,.43),(x*.32,y*.32,.20),(x*.44,y*.44,.10),(x*.45,y*.45,.18)],.033 if jelly else .05,"lavender" if jelly else "rose",f"arm_{i}")
        if not jelly:
            m.ball("Sucker",(x*.35,y*.35-.02,.19),(.05,.03,.05),"ivory",f"tip_{i}",segments=6,rings=3)
    if jelly:
        m.ring("SpaceCollar",(0,0,.45),.32,.04,"honey","neck")
        m.ball("HelmetDome",(0,.03,.72),(.74,.67,.58),"blue","head",alpha=True)
    m.face((0,-.31,.73),.28)


def micro(m, identity):
    m.rod("CarrierBase",(0,0,.035),(0,0,.13),.40,"teal","root",vertices=16)
    m.ring("CarrierRim",(0,0,.17),.37,.035,"honey","root")
    m.ball("CarrierWindow",(0,.04,.45),(.70,.61,.62),"aqua","root",alpha=True)
    count=1 if identity in (22,23,66,67) else 6
    for i in range(count):
        x=(i%3-1)*.17 if count>1 else 0; z=.39+(i//3)*.17
        bone=f"colony_{i}"
        color={21:"mint",22:"rose",23:"lavender",24:"blue",66:"honey",67:"aqua"}[identity]
        m.ball("ColonyMember",(x,-.04,z),(.13 if count>1 else .37,.14 if count>1 else .28,.14 if count>1 else .30),color,bone)
        if identity in (22,66):
            for j in range(8):
                a=j*math.tau/8
                m.rod("Pseudopod" if identity==22 else "Cilia",(x+.15*math.cos(a),-.03,z+.11*math.sin(a)),(x+.22*math.cos(a),-.02,z+.17*math.sin(a)),.018,color,bone,tip_radius=.008,vertices=5)
        if identity==23:
            m.ball("Nucleus",(0,-.19,.42),(.12,.04,.12),"purple",bone)
        if identity==67:
            m.ring("DiatomShell",(0,-.07,.44),.21,.025,"honey",bone,(math.pi/2,0,0))
        m.face((x,-.13 if count>1 else -.20,z+.015),.065 if count>1 else .16,bone)
    m.rod("ControlStem",(.29,-.14,.12),(.29,-.14,.38),.018,"wood","hand_r")
    m.ball("ControlKnob",(.29,-.14,.38),(.08,.07,.07),"coral","hand_r")
    m.box("FacePlaque",(0,-.36,.19),(.30,.035,.11),"ivory","root")
    if identity==24:
        m.line("ConductorBaton",[(-.26,-.1,.18),(-.32,-.1,.62)],.012,"honey","hand_l")


def floating(m, identity):
    if identity==18:
        m.star("StarBody",(0,0,.55),.45,"yellow","head")
    elif identity==19:
        m.ball("Meteor",(0,0,.54),(.7,.66,.75),"stone","head",segments=9,rings=5)
        for x,z in ((-.15,.70),(.18,.43),(-.07,.29)):
            m.ball("Crater",(x,-.31,z),(.14,.025,.11),"brown","head",segments=8,rings=4)
    elif identity==14:
        m.ball("GhostHead",(0,0,.74),(.59,.42,.49),"aqua","head",alpha=True)
        m.rod("GhostSheet",(0,0,.13),(0,0,.75),.34,"aqua","spine",tip_radius=.22,vertices=14)
        for s in (-1,1):
            m.ball("GhostHand",(s*.36,0,.47),(.20,.25,.22),"aqua","hand_"+("l" if s<0 else "r"),alpha=True)
    elif identity in (33,45,72):
        for x,z,r in ((-.23,.55,.35),(0,.70,.50),(.23,.53,.38)):
            m.ball("CloudLobe",(x,0,z),(r,.40,r),"white" if identity!=45 else "lavender","spine")
        if identity==33:
            for i in range(3):
                m.ball("RainDrop",((i-1)*.19,0,.15+(i%2)*.10),(.09,.09,.14),"blue","hips")
        elif identity==45:
            m.star("DreamStar",(.30,-.03,.86),.10,"honey","head")
            m.ball("Pillow",(0,0,.20),(.55,.35,.19),"aqua","hips")
        else:
            for i,color in enumerate(("coral","orange","yellow","mint","blue","lavender")):
                radius=.48-i*.045
                m.line("RainbowBand",[(math.cos(a)*radius, .06, .47+math.sin(a)*radius) for a in (0,math.pi/4,math.pi/2,3*math.pi/4,math.pi)],.025,color,"head")
    elif identity==34:
        m.ball("Flame",(0,0,.45),(.52,.40,.65),"orange","spine")
        m.rod("FlameTip",(0,0,.53),(.15,0,1),.20,"orange","head",tip_radius=0)
        m.ball("FlameCore",(0,-.20,.42),(.25,.06,.37),"yellow","spine")
    elif identity==43:
        m.polygon("CraneBody",[(0,-.26,.5),(-.13,.12,.4),(0,.30,.66),(.13,.12,.4)],"ivory","spine")
        for s in (-1,1):
            m.polygon("PaperWing",[(0,0,.5),(s*.54,.15,.88),(s*.23,-.1,.48)],"white","hand_"+("l" if s<0 else "r"))
        m.line("PaperNeck",[(0,-.12,.5),(0,-.31,.89),(0,-.43,.84)],.035,"ivory","neck")
    elif identity==46:
        for s in (-1,1):
            m.ball("NoteHead",(s*.18,0,.22),(.28,.19,.17),"purple","spine")
            m.rod("NoteStem",(s*.27,0,.22),(s*.27,0,.83),.028,"purple","head")
        m.box("NoteBeam",(0,0,.84),(.60,.09,.11),"purple","head")
    elif identity==47:
        m.ball("ShadowHead",(0,0,.81),(.40,.11,.34),"navy","head")
        m.ball("ShadowBody",(0,0,.43),(.62,.13,.52),"navy","spine")
        m.ball("ShadowBase",(0,0,.11),(.78,.35,.07),"navy","hips")
    elif identity==48:
        m.rod("Exclamation",(0,0,.43),(0,0,.97),.12,"coral","head",tip_radius=.17)
        m.ball("ExclamationDot",(0,0,.18),(.24,.18,.24),"coral","hips")
    elif identity==61:
        m.ball("LanternPaper",(0,0,.57),(.57,.47,.57),"red","spine")
        for z in (.3,.8):
            m.ring("LanternBand",(0,0,z),.23,.03,"honey","spine")
        m.line("LanternHandle",[(-.17,0,.8),(-.17,0,1.02),(.17,0,1.02),(.17,0,.8)],.02,"honey","head")
        m.line("Tassel",[(0,0,.30),(0,0,.03)],.04,"honey","hips")
    elif identity==63:
        m.ball("Planet",(0,0,.52),(.57,.57,.57),"honey","head")
        m.ring("SaturnRing",(0,0,.50),.43,.048,"ivory","spine",(.25,.15,0))
        m.ball("Moon",(.38,0,.87),(.12,.12,.12),"blue","head")
    elif identity==78:
        m.ball("SpeechBubble",(0,0,.6),(.7,.27,.59),"white","head")
        m.polygon("BubbleTail",[(-.14,0,.44),(-.33,0,.2),(.03,0,.38)],"white","spine")
        for i in range(3):
            m.ball("ResponseDot",((i-1)*.13,-.15,.60),(.065,.03,.065),"teal","head",segments=8,rings=4)
    elif identity==80:
        m.ball("MondayCloud",(0,0,.55),(.7,.49,.70),"lavender","spine")
        m.box("Calendar",(0,-.25,.45),(.38,.035,.33),"ivory","spine")
        m.box("CalendarHeader",(0,-.28,.59),(.38,.025,.07),"coral","spine")
        m.box("MondayMark",(0,-.28,.46),(.055,.02,.15),"ink","spine")
    if identity not in (43,46,78):
        m.face((0,-.24 if identity!=47 else -.07,.72 if identity in (14,19,47) else .59),.25)


def blob(m, identity):
    if identity==36:
        m.ball("WaterBody",(0,0,.4),(.64,.55,.62),"blue","spine")
        m.rod("DropletTip",(0,0,.52),(.05,0,.98),.23,"blue","head",tip_radius=0)
    elif identity==37:
        m.rod("Custard",(0,0,.12),(0,0,.72),.39,"honey","spine",tip_radius=.28,vertices=16)
        m.rod("Caramel",(0,0,.70),(0,0,.75),.29,"brown","head",vertices=16)
        m.ball("Cherry",(0,0,.84),(.14,.14,.14),"coral","head")
    elif identity==40:
        m.rod("Cone",(0,0,.02),(0,0,.54),.025,"honey","hips",tip_radius=.25,vertices=12)
        m.ball("Scoop",(0,0,.64),(.63,.57,.39),"rose","spine")
        m.ball("TopScoop",(0,0,.87),(.41,.39,.31),"ivory","head")
    elif identity==44:
        m.ball("YarnBall",(0,0,.48),(.72,.66,.68),"coral","spine")
        for i in range(5):
            m.line("YarnStrand",[(-.30,-.17,.24+i*.04),(-.16,-.34,.48+i*.04),(.16,-.34,.63-i*.03),(.32,-.15,.62-i*.05)],.015,"rose","spine")
        m.line("YarnEnd",[(.25,0,.3),(.46,-.1,.14),(.4,-.23,.07)],.018,"coral","hand_r")
    elif identity==52:
        m.ball("SnailFoot",(0,0,.13),(.58,.95,.23),"honey","hips")
        m.ball("SnailHead",(0,-.36,.38),(.33,.28,.38),"honey","head")
        m.ball("Shell",(0,.13,.55),(.68,.59,.70),"wood","spine")
        for radius in (.25,.17,.09):
            m.ring("ShellSpiral",(0,-.19,.58),radius,.025,"honey","spine",(math.pi/2,0,0))
        for s in (-1,1):
            m.rod("EyeStalk",(s*.09,-.4,.48),(s*.15,-.46,.72),.018,"honey","head")
            m.ball("EyeBulb",(s*.15,-.46,.73),(.09,.08,.09),"ivory","head")
    elif identity==73:
        for i in range(5):
            m.ball("SandSwirl",(math.sin(i)*.05,0,.15+i*.16),(.7-i*.09,.5-i*.06,.25),"honey","spine" if i<3 else "head")
    elif identity==74:
        for i in range(5):
            m.line("NoodleCoil",[(-.27,0,.15+i*.14),(-.3,-.13,.23+i*.14),(.27,-.14,.22+i*.14),(.3,0,.29+i*.14)],.045,"ivory","spine" if i<3 else "head")
        m.line("NoodleHand",[(-.28,0,.5),(-.45,-.1,.4)],.04,"ivory","hand_l")
    m.face((0,-.30 if identity!=52 else -.52,.5 if identity!=52 else .42),.25)


def objects(m, identity):
    if identity==26:
        m.ball("ClockBody",(0,0,.53),(.64,.30,.66),"teal","spine")
        m.ball("ClockDial",(0,-.16,.53),(.53,.035,.54),"ivory","display")
        for s in (-1,1):
            m.ball("ClockBell",(s*.22,0,.88),(.24,.24,.15),"honey","head")
        m.line("ClockHands",[(0,-.19,.72),(0,-.19,.53),(.14,-.19,.55)],.018,"wood","display")
    elif identity in (27,28,29,57,69,70):
        color={27:"wood",28:"teal",29:"coral",57:"wood",69:"blue",70:"coral"}[identity]
        m.box("ObjectBody",(0,0,.48),(.71,.39,.66),color,"spine",bevel=.055)
        if identity==27:
            m.ball("Speaker",(-.14,-.21,.47),(.31,.035,.31),"navy","spine")
            for z in (.38,.44,.5,.56):
                m.box("SpeakerGrille",(-.14,-.24,z),(.27,.02,.017),"honey","spine",bevel=0)
            m.rod("RadioAntenna",(.25,0,.8),(.36,0,1.12),.014,"silver","head")
            m.box("Tuner",(.19,-.22,.57),(.18,.035,.12),"ivory","display")
        elif identity==28:
            m.box("DisplayWindow",(-.06,-.22,.56),(.49,.035,.42),"navy","display")
            for i in range(6):
                m.rod("Snack",((i%3-1)*.13-.06,-.25,.45+(i//3)*.19),((i%3-1)*.13-.06,-.25,.55+(i//3)*.19),.04,("coral","honey","aqua")[i%3],"display",vertices=8)
            m.box("Pickup",(0,-.22,.22),(.37,.03,.12),"ink","spine")
            for z in (.48,.55,.62):
                m.ball("Button",(.29,-.23,z),(.045,.025,.045),"honey","spine",segments=6,rings=3)
        elif identity==29:
            for s in (-1,1):
                m.box("SuitcaseStrap",(s*.22,-.22,.48),(.055,.035,.64),"honey","spine")
            m.line("CaseHandle",[(-.15,0,.82),(-.15,0,.95),(.15,0,.95),(.15,0,.82)],.025,"wood","head")
            m.box("TravelSticker",(.1,-.25,.59),(.18,.025,.13),"ivory","spine")
        elif identity==57:
            m.box("ChestLid",(0,0,.82),(.75,.44,.19),"wood","lid",bevel=.055)
            for s in (-1,1):
                m.box("ChestBand",(s*.24,-.23,.53),(.07,.035,.61),"honey","spine")
            m.box("Mouth",(0,-.22,.70),(.48,.035,.12),"ink","spine")
            for x in (-.17,-.06,.06,.17):
                m.rod("ChestTooth",(x,-.26,.76),(x,-.26,.68),.03,"ivory","lid",tip_radius=0,vertices=5)
        elif identity==69:
            m.box("TrainCab",(0,.09,.76),(.59,.32,.40),"teal","head")
            m.box("TrainWindow",(0,-.08,.80),(.40,.025,.22),"ivory","display")
            m.rod("Smokestack",(0,-.23,.78),(0,-.23,1),.09,"honey","head")
            for s in (-1,1):
                for y in (-.22,.22):
                    m.ring("TrainWheel",(s*.35,y,.17),.11,.035,"wood","hips",(0,math.pi/2,0))
        elif identity==70:
            m.box("Pages",(0,-.03,.52),(.61,.39,.59),"ivory","spine")
            m.box("FrontCover",(0,-.25,.52),(.71,.045,.67),"coral","display")
            for z in (.32,.4,.48,.56,.64):
                m.box("PageLine",(.32,0,z),(.015,.32,.008),"honey","spine",bevel=0)
            m.line("Bookmark",[(.15,0,.84),(.15,-.26,.72),(.15,-.26,.55)],.018,"teal","head")
    elif identity==30:
        m.rod("UmbrellaShaft",(0,0,.08),(0,0,.84),.025,"wood","spine")
        m.rod("UmbrellaCanopy",(0,0,.68),(0,0,.90),.46,"blue","head",tip_radius=0,vertices=12)
        for i in range(6):
            a=i*math.tau/6
            m.line("UmbrellaRib",[(0,0,.90),(.46*math.cos(a),.46*math.sin(a),.68)],.009,"ivory","head")
        m.line("UmbrellaHandle",[(0,0,.18),(0,0,.06),(.12,0,.03),(.15,0,.15)],.03,"wood","hips")
    elif identity==31:
        m.rod("LampBase",(0,0,.01),(0,0,.07),.28,"teal","hips",vertices=16)
        m.line("LampArm",[(0,0,.08),(0,.08,.51),(0,-.15,.74)],.035,"wood","spine")
        m.rod("LampShade",(0,-.15,.69),(0,-.15,.90),.30,"honey","head",tip_radius=.16,vertices=12)
        m.ball("Bulb",(0,-.15,.67),(.22,.22,.11),"ivory","head")
    elif identity==32:
        m.ball("Teapot",(0,0,.49),(.58,.47,.54),"ivory","spine")
        m.ring("Handle",(.33,0,.53),.18,.035,"teal","hand_r",(math.pi/2,0,0))
        m.line("Spout",[(-.20,0,.43),(-.39,0,.55),(-.44,0,.74)],.07,"ivory","hand_l")
        m.rod("Lid",(0,0,.75),(0,0,.79),.19,"teal","lid")
        m.ball("LidKnob",(0,0,.85),(.11,.1,.1),"honey","lid")
    elif identity==39:
        m.rod("PopcornBox",(0,0,.08),(0,0,.65),.23,"coral","spine",tip_radius=.35,vertices=8)
        for i in range(8):
            a=math.tau*i/8
            m.ball("Kernel",(.20*math.cos(a),.17*math.sin(a),.72+(i%3)*.08),(.23,.20,.22),"ivory","head",segments=8,rings=4)
    elif identity==68:
        m.rod("VacuumDisc",(0,0,.08),(0,0,.40),.41,"teal","spine",vertices=16)
        m.rod("VacuumTop",(0,0,.40),(0,0,.44),.36,"ivory","head",vertices=16)
        m.box("VacuumDisplay",(0,-.23,.41),(.28,.17,.025),"navy","display")
        for s in (-1,1):
            m.line("SideBrush",[(s*.3,0,.09),(s*.48,-.1,.08)],.025,"brown","hand_"+("l" if s<0 else "r"))
    elif identity==71:
        m.ball("MirrorFrame",(0,0,.58),(.65,.17,.76),"honey","spine")
        m.ball("MirrorFace",(0,-.095,.58),(.54,.025,.64),"silver","display")
        for s in (-1,1):
            m.rod("MirrorLeg",(s*.19,0,.35),(s*.28,0,.04),.03,"wood","foot_"+("l" if s<0 else "r"))
    elif identity==76:
        m.ball("ClockworkFrog",(0,0,.45),(.55,.55,.45),"leaf","spine")
        for s in (-1,1):
            m.ball("FrogEye",(s*.18,-.18,.73),(.19,.17,.20),"honey","head")
            m.ball("FrogFoot",(s*.32,-.06,.17),(.25,.36,.14),"teal","foot_"+("l" if s<0 else "r"))
        m.ring("WindKey",(0,.31,.50),.12,.025,"honey","lid",(math.pi/2,0,0))
    if identity not in (28,57,68):
        m.face((0,-.25 if identity not in (30,31,71) else -.12,.56 if identity!=76 else .70),.24)


def body(record):
    m=Model(face_rig=True); identity=int(record["id"][1:]); kind=record["rig"]
    dispatch={"biped":biped,"quadruped":quadruped,"longneck":quadruped,
              "plant":plant,"tentacle":tentacle,"micro":micro,
              "float":floating,"blob":blob,"object":objects}
    dispatch[kind](m,identity)
    mesh=m.join("core_"+record["id"].lower()+"_body",3000)
    low=[min(v.co[i] for v in mesh.data.vertices) for i in range(3)]
    high=[max(v.co[i] for v in mesh.data.vertices) for i in range(3)]
    size=[record["body"][k] for k in ("width_m","depth_m","height_m")]
    factor=[size[i]/(high[i]-low[i]) for i in range(3)]
    offset=[(high[0]+low[0])/2,(high[1]+low[1])/2,low[2]]
    def fitted(p): return tuple((p[i]-offset[i])*factor[i] for i in range(3))
    for vertex in mesh.data.vertices:
        vertex.co=fitted(vertex.co)
    extra=[("hair",(0,.025,.97),"head")] if identity==49 else []
    bones=[(name,fitted(point),parent) for name,point,parent in definitions(kind)+m.face_bones+extra]
    rig=armature("Body",bones)
    skin(mesh,rig)
    h=record["body"]["height_m"]
    def pose(action,t,b):
        wave=math.sin(t*math.tau); half=math.sin(t*math.pi)
        static=action in ("pause","low_motion")
        for name in b.keys():
            if name.startswith("eye_"):
                if action=="blink": b[name].scale.y=.08 if abs(t-.5)<.1 else 1.0
                elif action in ("sleep","rest"): b[name].scale.y=.10
                elif action=="upset": b[name].scale.y=.65
        b["spine"].rotation_euler.y=0 if static else .025*wave
        if action=="walk":
            if kind in ("biped","quadruped","longneck"):
                for name in b.keys():
                    if any(k in name for k in ("thigh_","front_upper_","hind_upper_")):
                        b[name].rotation_euler.x=.28*wave*(-1 if name.endswith("l") else 1)*(-1 if "hind" in name else 1)
                    if "upper_arm_" in name: b[name].rotation_euler.x=-.22*wave*(-1 if name.endswith("l") else 1)
            elif kind=="tentacle":
                for i in range(8): b[f"arm_{i}"].rotation_euler.y=.18*math.sin(t*math.tau+i*.8)
            elif kind=="micro":
                for i in range(6): b[f"colony_{i}"].rotation_euler.z=.13*math.sin(t*math.tau+i)
            else: b["spine"].rotation_euler.z=.07*wave
        if action in ("sit","sleep","rest"):
            if kind=="biped":
                for side in ("l","r"):
                    b["thigh_"+side].rotation_euler.x=-1.0
                    b["shin_"+side].rotation_euler.x=.90
                b["spine"].rotation_euler.x=.08
            elif kind in ("quadruped","longneck"):
                for name in b.keys():
                    if "_upper_" in name: b[name].rotation_euler.x=.55 if name.startswith("front") else -.55
                    if "_lower_" in name: b[name].rotation_euler.x=-.55 if name.startswith("front") else .55
            elif kind=="tentacle":
                for i in range(8): b[f"arm_{i}"].rotation_euler.y=.18
            elif kind=="plant": b["spine"].rotation_euler.y=.06
            elif kind=="object": b["lid"].rotation_euler.x=-.08
            elif kind=="micro":
                for i in range(6): b[f"colony_{i}"].rotation_euler.x=.12
            if action=="sleep": b["head"].rotation_euler.x=.20
        if action in ("notice","talk","upset","symptom"):
            b["head"].rotation_euler.z=(.16 if action=="upset" else .09)*wave
            b["neck"].rotation_euler.x=.06*half
        if action in ("work","interact","recreation","cheer"):
            for side,s in (("l",-1),("r",1)):
                b["hand_"+side].rotation_euler.x=-.22+.14*wave
                if "upper_arm_"+side in b:
                    b["upper_arm_"+side].rotation_euler.y=s*(.35 if action=="cheer" else .12)*half
        if action in ("recover","recovery","wake"):
            b["head"].rotation_euler.x=-.10*half
            b["spine"].rotation_euler.y=.06*half
    actions(rig,BODY_ACTIONS,pose)
    mesh["content_id"]=record["id"]
    mesh["one_actor_mesh"]=True
    mesh["source_dimensions_m"]=','.join(str(v) for v in size)
    rig["rig_profile"]=kind
    return mesh,rig
