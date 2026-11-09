"""Seventy-seven functional furnishings and modular hospital architecture."""
import math
from pathlib import Path

from blender_common import Model, armature, skin, actions, save_blend, export_glb, reset_scene, glb_metadata
from catalog import STRUCTURES, write_json


def legs(m,w=.68,d=.48,height=.62,color="wood"):
    for x in (-w/2,w/2):
        for y in (-d/2,d/2):
            m.rod("Leg",(x,y,.04),(x,y,height),.035,color)


def desk(m,research=False):
    legs(m,height=.69)
    m.box("DeskTop",(0,0,.72),(.91,.67,.10),"honey",bevel=.04)
    m.box("DeskPedestal",(.29,.06,.39),(.24,.48,.57),"ivory")
    for z in (.27,.43,.59):
        m.box("DrawerHandle",(.29,-.20,z),(.10,.025,.025),"wood")
    if research:
        m.box("Book",(-.23,0,.80),(.25,.24,.06),"coral","record_clip")
        m.rod("Microscope",(.15,.08,.80),(.15,.08,1.15),.025,"teal","windmill")
        m.rod("ScopeBarrel",(.15,.08,1.13),(.05,-.1,1.13),.05,"teal","windmill")
    else:
        m.box("Record",(-.18,-.05,.80),(.25,.29,.035),"ivory","record_clip")
        m.box("Monitor",(.18,.12,1),(.31,.07,.28),"teal")
        m.box("Screen",(.18,.075,1.01),(.26,.015,.20),"navy","display")


def chair(m,identity):
    wide=identity in ("FUR06","FUR10","FUR16","RC02")
    w=.84 if wide else .58
    legs(m,w*.8,.45,.40)
    m.box("FixedSeat",(0,0,.44),(w,.57,.14),"aqua" if identity!="FUR14" else "ivory")
    m.box("Backrest",(0,.25,.73),(w,.12,.52),"teal")
    if identity in ("FUR06","FUR10","FUR49","FUR50","RC02"):
        for s in (-1,1):
            m.box("Armrest",(s*w/2,0,.59),(.10,.55,.13),"teal")
    if identity in ("FUR12","FUR50"):
        for s in (-1,1):
            m.rod("ShadePost",(s*w/2,.19,.66),(s*w/2,.19,1.37),.025,"wood")
        m.box("QuietHood" if identity=="FUR50" else "Shade",(0,.08,1.34),(w+.15,.71,.13),"navy" if identity=="FUR50" else "ivory")
    if identity=="FUR13":
        m.box("CatchTray",(0,-.05,.51),(w*.8,.40,.045),"blue")
        m.rod("WaterBottle",(.35,-.19,.58),(.35,-.19,.80),.04,"blue")
    if identity in ("FUR14","FUR15"):
        m.box("DryLinenCushion" if identity=="FUR14" else "CoolingCushion",(0,-.03,.55),(w*.87,.45,.11),"ivory" if identity=="FUR14" else "blue")
    if identity in ("FUR49","RC02"):
        for s in (-1,1):
            m.line("Rocker",[(s*w*.37,-.38,.04),(s*w*.37,0,.015),(s*w*.37,.38,.04)],.025,"wood")
    if identity=="FUR51":
        m.box("ReadingTray",(0,-.35,.76),(.52,.23,.04),"honey")
        m.box("OpenBook",(0,-.35,.8),(.35,.20,.025),"ivory","record_clip")
    if identity=="FUR52":
        m.box("FootRest",(0,-.50,.34),(.51,.41,.08),"teal")


def flower(m,position=(0,0,.5),color="rose"):
    x,y,z=position
    m.rod("Stem",(x,y,z-.35),(x,y,z),.015,"leaf")
    for i in range(5):
        a=i*math.tau/5
        m.ball("Petal",(x+.06*math.cos(a),y+.06*math.sin(a),z),(.10,.10,.04),color,segments=8,rings=4)
    m.ball("FlowerCenter",(x,y,z+.02),(.065,.065,.04),"yellow",segments=8,rings=4)


def clinical(m,identity):
    if identity in ("EQ01","EQ05","SE04"):
        legs(m,.65,.73,.45,"silver")
        m.box("BedBase",(0,0,.46),(.83,.95,.12),"teal")
        m.box("PatientSupport",(0,0,.58),(.73,.89,.15),"ivory","patient_support")
        m.box("HeadPillow",(0,.29,.69),(.47,.20,.12),"white","bed_back")
        for s in (-1,1):
            m.line("SideRail",[(s*.42,-.32,.59),(s*.42,-.32,.85),(s*.42,.35,.85),(s*.42,.35,.59)],.018,"silver","bed_front" if s<0 else "bed_back")
        m.rod("RecordPost",(.43,.39,.10),(.43,.39,1.10),.018,"silver")
        m.box("CareRecord",(.43,.36,1.05),(.20,.035,.26),"ivory","record_clip")
        if identity=="EQ01":
            m.line("SurgeryLightArm",[(-.45,.4,.1),(-.45,.4,1.48),(0,.18,1.48)],.025,"silver")
            m.ball("SurgeryLamp",(0,.17,1.4),(.37,.32,.14),"honey","windmill")
            m.box("AnesthesiaMonitor",(.43,-.28,.96),(.25,.07,.29),"teal")
            m.box("MonitorScreen",(.43,-.33,.98),(.20,.015,.18),"navy","display")
        elif identity=="SE04":
            m.box("QuietSign",(.39,.1,.93),(.22,.025,.16),"honey","record_clip")
            m.ball("EyeMask",(0,.30,.76),(.23,.06,.10),"navy","patient_support")
    elif identity=="M09":
        legs(m,height=.48,color="teal")
        m.box("RestorationTable",(0,0,.54),(.85,.85,.16),"ivory")
        m.box("SoftSupport",(0,-.08,.68),(.63,.58,.16),"aqua","patient_support")
        for s in (-1,1):
            m.rod("FramePost",(s*.39,.23,.57),(s*.39,.23,1.42),.035,"teal")
        m.rod("Crossbar",(-.4,.23,1.4),(.4,.23,1.4),.035,"honey")
        m.ring("SoftSupportRing",(0,.23,1.08),.18,.035,"ivory","windmill",(math.pi/2,0,0))
        for i in range(6):
            m.rod("CombTooth",(-.28+i*.10,-.38,.66),(-.28+i*.10,-.38,.88),.017,"honey","record_clip")
    elif identity=="M37":
        m.rod("ConditioningBase",(0,0,.02),(0,0,.17),.48,"teal",vertices=16)
        for s in (-1,1):
            m.rod("ArchPost",(s*.39,.12,.15),(s*.39,.12,1.15),.09,"ivory")
        m.line("Arch",[(-.39,.12,1.13),(0,.12,1.43),(.39,.12,1.13)],.10,"ivory")
        m.box("StableSeat",(0,0,.45),(.44,.55,.12),"aqua","patient_support")
        m.box("SeatBack",(0,.22,.70),(.44,.10,.43),"aqua","patient_support")
        m.ring("ConditioningFan",(-.29,-.12,1.18),.12,.02,"honey","windmill",(math.pi/2,0,0))
        for a in (0,math.tau/3,math.tau*2/3):
            m.ball("FanBlade",(-.29+.08*math.cos(a),-.12,1.18+.08*math.sin(a)),(.13,.04,.08),"honey","windmill",segments=8,rings=4)
        m.box("Console",(.35,-.25,.68),(.20,.15,.11),"teal","record_clip")
    elif identity=="M17":
        legs(m,height=.42,color="teal")
        m.box("WonderStage",(0,0,.49),(.89,.85,.16),"teal")
        for s in (-1,1):
            m.rod("CurtainPost",(s*.40,.30,.53),(s*.4,.30,1.4),.03,"honey")
        m.rod("CurtainRail",(-.42,.30,1.4),(.42,.30,1.4),.03,"honey")
        m.box("NightCurtain",(.13,.29,1.0),(.52,.025,.68),"navy","night_curtain")
        for x,z in ((.06,1.24),(.26,1.07),(.05,.82)):
            m.star("CurtainStar",(x,.27,z),.035,"yellow","night_curtain")
        m.ball("Pillow",(-.24,0,.68),(.29,.25,.15),"ivory","patient_support")
        m.box("ThoughtTray",(.29,-.22,.65),(.23,.24,.055),"ivory","record_clip")


def furniture(m,identity):
    n=int(identity[3:])
    if n in (1,2,5):
        desk(m,n==5)
        if n==1:
            m.box("ReceptionFront",(0,-.30,.46),(.86,.10,.52),"teal")
            m.box("CounterShelf",(0,-.31,.83),(.91,.17,.07),"ivory")
            m.ring("CallBell",(-.26,-.30,.90),.05,.018,"honey","windmill")
        elif n==2:
            m.box("SymptomPanel",(-.22,.16,1.03),(.27,.04,.32),"ivory","record_clip")
            m.ring("ExamScope",(.16,-.10,.86),.07,.013,"wood","windmill",(math.pi/2,0,0))
    elif n in (6,9,10,12,13,14,15,16,49,50,51,52): chair(m,identity)
    elif n==7:
        m.box("ToiletModule",(0,.04,.57),(.78,.69,1.12),"ivory")
        m.box("PrivacyDoor",(0,-.32,.58),(.65,.04,1.02),"teal","door_l")
        m.box("OccupiedFlag",(.20,-.36,.76),(.11,.025,.08),"coral","record_clip")
    elif n==8:
        m.box("HeaterCart",(0,0,.41),(.63,.47,.52),"ivory")
        m.ring("HeaterFan",(0,-.25,.43),.18,.035,"teal","windmill",(math.pi/2,0,0))
        for i in range(4):
            a=math.tau*i/4
            m.rod("FanSpoke",(0,-.26,.43),(.16*math.cos(a),-.26,.43+.16*math.sin(a)),.018,"honey","windmill")
        legs(m,.48,.32,.16)
        m.line("CartHandle",[(.25,.18,.55),(.25,.18,.86),(-.25,.18,.86),(-.25,.18,.55)],.018,"wood")
    elif n==11:
        legs(m,.54,.43,.35)
        m.rod("PetriDock",(0,0,.38),(0,0,.46),.36,"teal",vertices=16)
        m.ring("DockRim",(0,0,.48),.32,.025,"honey")
    elif n==17:
        m.box("WaterCooler",(0,0,.47),(.41,.41,.84),"ivory")
        m.rod("WaterTank",(0,0,.89),(0,0,1.26),.18,"blue",vertices=12)
        for s in (-1,1): m.rod("Tap",(s*.09,-.2,.70),(s*.09,-.27,.66),.025,"teal")
        m.box("CupTray",(0,-.24,.52),(.29,.18,.035),"teal")
    elif n==18:
        m.rod("Bin",(0,0,.02),(0,0,.65),.25,"teal",tip_radius=.31,vertices=12)
        m.ring("BinRim",(0,0,.68),.30,.025,"honey")
        m.box("SwingLid",(0,0,.7),(.48,.41,.04),"ivory","lid")
    elif n in (19,37,38):
        m.rod("LightBase",(0,0,.01),(0,0,.08),.24,"wood",vertices=12)
        m.rod("LightStem",(0,0,.07),(0,0,1.16),.025,"wood")
        if n==37:
            m.ball("MushroomShade",(0,0,1.19),(.65,.60,.28),"coral","head")
        elif n==38:
            m.ball("GummyLantern",(0,0,1.12),(.43,.43,.44),"honey","head")
        else:m.rod("LampShade",(0,0,1.04),(0,0,1.33),.30,"ivory","head",tip_radius=.17)
    elif n in (20,25,26):
        if n==25:m.box("SquarePlanter",(0,0,.20),(.51,.51,.38),"ivory")
        else:m.rod("RoundPlanter",(0,0,.03),(0,0,.38),.20,"ivory",tip_radius=.28,vertices=12)
        m.rod("Soil",(0,0,.38),(0,0,.40),.23,"brown",vertices=12)
        if n==20:
            m.ball("RainCatchBowl",(0,0,.48),(.49,.49,.16),"blue")
            flower(m,(.10,.09,.81),"aqua")
        else:
            for s in (-1,1):
                m.line("PlantBranch",[(0,0,.39),(s*.18,0,.65),(s*.22,0,.84)],.018,"leaf")
                m.ball("Leaf",(s*.20,0,.73),(.22,.10,.30),"mint")
    elif n==21:
        m.rod("UmbrellaBase",(0,0,.02),(0,0,.09),.25,"ivory")
        m.rod("DryUmbrellaPost",(0,0,.09),(0,0,.95),.025,"wood")
        m.rod("DryCanopy",(0,0,.90),(0,0,1.10),.42,"ivory","head",tip_radius=0,vertices=12)
        for i in range(4):
            x=(i-1.5)*.11
            m.line("DryAir",[(x,0,.38),(x+.025,0,.53),(x,0,.66)],.009,"honey","cloud_bag")
    elif n==22:
        m.rod("FanBase",(0,0,.02),(0,0,.08),.23,"ivory")
        m.rod("FanStand",(0,0,.08),(0,0,.77),.025,"wood")
        m.ring("FanFrame",(0,0,.91),.29,.025,"teal","head",(math.pi/2,0,0))
        for i in range(3):
            a=i*math.tau/3
            m.ball("LeafBlade",(.15*math.cos(a),0,.91+.15*math.sin(a)),(.24,.055,.12),"mint","windmill")
    elif n==23:
        for s in (-1,1):
            m.box("ScreenFoot",(s*.33,0,.035),(.15,.32,.07),"wood")
        m.box("QuietScreen",(0,0,.69),(.81,.10,1.25),"teal")
        for x in (-.33,0,.33):m.rod("ScreenFrame",(x,0,.09),(x,0,1.32),.018,"honey")
    elif n==24:
        m.box("WindowStand",(0,0,.40),(.62,.48,.73),"ivory")
        m.ring("ObservationFrame",(0,-.08,.99),.29,.065,"teal","head",(math.pi/2,0,0))
        m.ball("ObservationPane",(0,-.08,.99),(.46,.035,.46),"aqua","display")
        m.rod("Eyepiece",(.22,.01,1.15),(.37,.01,1.22),.05,"wood","windmill")
    elif n in (27,28):
        m.box("Carpet",(0,0,.012),(.94,.94,.024),"ivory" if n==27 else "teal",bevel=.015)
        if n==27:
            for x in (-.28,0,.28):
                for y in (-.28,0,.28):m.rod("PolkaDot",(x,y,.025),(x,y,.029),.06,"honey",vertices=10)
        else:
            for x in (-.32,-.16,0,.16,.32):m.box("CarpetStripe",(x,0,.026),(.065,.91,.006),"aqua",bevel=0)
    elif n in (29,30):
        m.ball("ClockFrame",(0,0,.7),(.65,.12,.65),"honey","head")
        m.ball("ClockFace",(0,-.07,.7),(.54,.025,.54),"ivory","display")
        m.line("Hands",[(0,-.09,.91),(0,-.09,.70),(.14,-.09,.73)],.018,"wood","display")
        if n==30:m.star("ClockStar",(.19,-.10,.5),.07,"blue","head")
        else:m.face((0,-.10,.63),.23,"head")
    elif n in (31,32,48):
        m.box("WallFrame",(0,0,.67),(.76,.08,.60),"wood")
        m.box("Board",(0,-.05,.67),(.67,.025,.51),"ivory")
        if n==31:
            m.line("PaintStem",[(0,-.08,.48),(0,-.08,.83)],.012,"leaf")
            for s in (-1,1):m.ball("PaintLeaf",(s*.12,-.08,.68),(.23,.02,.12),"mint",segments=8,rings=4)
        elif n==32:
            for i in range(4):m.box("Notice",((i%2-.5)*.29,-.08,.56+(i//2)*.22),(.22,.02,.16),("aqua","honey","coral","lavender")[i])
        else:
            m.star("WelcomeStar",(0,-.09,.68),.18,"honey")
    elif n==33:
        m.rod("SculptureBase",(0,0,.02),(0,0,.20),.25,"ivory")
        m.line("Crescent",[(.16*math.cos(a),0,.63+.25*math.sin(a)) for a in (math.pi*.2,math.pi*.6,math.pi,math.pi*1.4,math.pi*1.8)],.07,"honey")
    elif n==34:
        m.rod("PinwheelBase",(0,0,.02),(0,0,.09),.20,"ivory")
        m.rod("PinwheelStem",(0,0,.09),(0,0,1.0),.02,"wood")
        for i,color in enumerate(("coral","aqua","honey","lavender")):
            a=i*math.tau/4
            p=[(0,-.02,1),(.3*math.cos(a),-.02,1+.3*math.sin(a)),(.23*math.cos(a+.6),-.02,1+.23*math.sin(a+.6))]
            m.polygon("PinwheelBlade",p,color,"windmill")
    elif n==35:
        m.rod("BubbleColumnBase",(0,0,.02),(0,0,.13),.27,"teal")
        m.rod("BubbleColumn",(0,0,.15),(0,0,1.25),.21,"aqua",vertices=12)
        for i in range(4):m.ball("Bubble",((i%2-.5)*.18,-.2,.3+i*.24),(.13,.08,.13),"ivory","cloud_bag",segments=8,rings=4)
    elif n==36:
        m.line("RockerRails",[(-.4,0,.06),(0,0,.01),(.4,0,.06)],.03,"wood")
        m.ball("WoodHorseBody",(0,0,.40),(.48,.29,.25),"honey")
        m.rod("HorseNeck",(-.17,0,.4),(-.25,0,.77),.075,"wood")
        m.ball("HorseHead",(-.28,0,.76),(.27,.18,.14),"honey","head")
        for x in (-.16,.16):m.rod("HorseLeg",(x,0,.37),(x,0,.07),.035,"wood")
    elif n==39:
        m.box("OrbitBase",(0,0,.08),(.49,.41,.16),"wood")
        m.ring("OrbitalTrack",(0,0,.59),.31,.023,"honey","windmill",(.9,.3,0))
        m.ball("OrbitPlanet",(0,0,.59),(.23,.23,.23),"blue")
        m.ball("OrbitMoon",(.29,0,.68),(.10,.10,.10),"coral","windmill")
    elif n==40:
        m.box("CloudBase",(0,0,.07),(.53,.41,.14),"wood")
        for x,z,r in ((-.20,.40,.34),(0,.49,.44),(.22,.4,.31)):
            m.ball("CloudLobe",(x,0,z),(r,.32,r),"ivory")
    elif n in (41,45,46):
        m.box("CabinetBack",(0,.21,.57),(.88,.07,1.10),"ivory")
        for x in (-.42,.42):m.box("CabinetSide",(x,0,.57),(.065,.48,1.10),"wood")
        for z in (.05,.40,.77,1.1):m.box("Shelf",(0,0,z),(.84,.48,.055),"honey")
        for i in range(7):
            if n==45:m.box("Book",(-.31+i*.095,0,.60),(.065,.27,.30),["teal","coral","ivory","blue"][i%4])
            else:m.ball("DisplayedObject",(-.26+(i%3)*.26,0,.20+(i//3)*.34),(.15,.18,.15),["coral","teal","honey"][i%3],segments=8,rings=4)
    elif n==42:
        legs(m,.72,.32,.20)
        for x in (-.39,.39):m.rod("PhotoPost",(x,0,.1),(x,0,1.3),.035,"wood")
        m.rod("PhotoRail",(-.40,0,1.3),(.4,0,1.3),.035,"wood")
        m.box("PhotoFrame",(0,0,.90),(.67,.08,.53),"honey")
        m.box("Photo",(0,-.05,.9),(.56,.02,.42),"aqua")
        m.star("PhotoStar",(0,-.07,.9),.12,"ivory")
    elif n==43:
        legs(m,height=.50)
        m.box("FlowerDisplayTable",(0,0,.54),(.9,.6,.08),"ivory")
        for x in (-.27,0,.27):flower(m,(x,0,.94),"rose" if x else "yellow")
    elif n==44:
        m.line("BuntingLine",[(-.48,0,1), (0,0,.90),(.48,0,1)],.009,"wood")
        for i in range(5):
            x=(i-2)*.17
            m.polygon("BuntingFlag",[(x-.07,0,.94),(x+.07,0,.94),(x,0,.72)],["coral","aqua","honey"][i%3])
    elif n==47:
        m.rod("FountainBasin",(0,0,.05),(0,0,.28),.43,"ivory",vertices=16)
        m.rod("Water",(0,0,.28),(0,0,.30),.36,"blue",vertices=16)
        m.rod("Spout",(0,0,.2),(0,0,.84),.045,"honey")
        for s in (-1,1):m.line("WaterArc",[(0,0,.83),(s*.17,0,.97),(s*.31,0,.30)],.018,"aqua","cloud_bag")


def other_equipment(m,record):
    identity=record["id"]
    if identity in ("M09","M17","M37","EQ01","EQ05","SE04"):clinical(m,identity)
    elif identity.startswith("SE"):
        if identity in ("SE01","SE05","SE06"):desk(m)
        elif identity=="SE02":
            desk(m,True)
            m.line("PaintRoller",[(-.25,0,.82),(-.25,0,1.1),(-.05,0,1.1)],.022,"wood","windmill")
            m.rod("Roller",(-.07,0,1.1),(.12,0,1.1),.065,"coral","windmill")
        else:
            m.box("CallScreenBase",(0,0,.06),(.61,.41,.12),"wood")
            m.rod("ScreenPole",(0,0,.09),(0,0,.94),.03,"wood")
            m.box("WayfindingScreen",(0,0,1.03),(.69,.09,.47),"teal")
            m.box("ScreenFace",(0,-.06,1.03),(.58,.02,.36),"navy","display")
            m.star("QueueIcon",(-.14,-.08,1.03),.08,"honey","display")
            m.box("QueueLine",(.13,-.08,1.03),(.19,.01,.035),"ivory","display")
    elif identity=="AE01":
        m.box("GiantFixedCushion",(0,0,.25),(.96,.96,.4),"aqua",bevel=.1)
        m.box("StableBackrest",(0,.38,.57),(.92,.18,.52),"teal",bevel=.08)
    elif identity=="AE02":
        furniture(m,"FUR17")
        m.rod("FixedControlRail",(.29,0,.2),(.29,0,1.55),.025,"silver")
        m.line("AdjustableTapArm",[(.29,0,1.4),(.05,-.1,1.4),(.05,-.22,1.30)],.025,"teal","windmill")
    elif identity=="AE03":
        m.box("UniversalToiletCabin",(0,.10,1.03),(.93,.79,2.01),"ivory")
        m.box("PrivacyDoor",(0,-.31,1.03),(.78,.035,1.9),"teal","door_l")
        m.box("OccupationPlaque",(.28,-.35,1.3),(.12,.025,.10),"coral","record_clip")
        m.rod("Rail",(-.34,-.35,.72),(.25,-.35,.72),.018,"honey")
    elif identity=="RC01":
        m.box("ArcadeCabinet",(0,0,.64),(.61,.54,1.2),"teal")
        m.box("ArcadeScreen",(0,-.29,.91),(.49,.04,.45),"navy","display")
        m.box("ControlDeck",(0,-.36,.61),(.62,.29,.10),"honey")
        m.rod("Joystick",(-.15,-.38,.65),(-.15,-.38,.8),.015,"wood","windmill")
        m.ball("JoystickBall",(-.15,-.38,.8),(.075,.075,.075),"coral","windmill")
        m.star("PixelPlayer",(0,-.32,.95),.10,"aqua","display")
    elif identity=="RC02":chair(m,"RC02")
    elif identity=="RC03":
        legs(m,height=.61)
        m.box("BilliardFrame",(0,0,.68),(.95,.80,.18),"wood")
        m.box("BilliardCloth",(0,0,.78),(.83,.67,.025),"teal")
        for i,color in enumerate(("white","honey","coral")):
            m.ball("Ball",((i-1)*.18,-.05,.83),(.075,.075,.075),color,"windmill",segments=8,rings=4)
        m.rod("Cue",(-.43,-.32,.85),(.42,.32,.85),.008,"honey","record_clip")
    elif identity=="RC04":
        m.box("WalkingSupport",(0,0,.22),(.94,.86,.37),"aqua")
        for s in (-1,1):
            m.line("WalkingRail",[(s*.43,-.39,.25),(s*.43,-.39,.82),(s*.43,.4,.82),(s*.43,.4,.25)],.018,"honey")
        for i in range(5):m.ball("TrackBubble",(-.34+i*.17,-.33,.85),(.07,.07,.07),"blue","cloud_bag",segments=8,rings=4)
    elif identity.startswith("DR"):
        w=record["clear_width_m"]; h=record["clear_height_m"]
        for s in (-1,1):m.box("DoorPost",(s*(w+.12)/2,0,h/2),(.12,.25,h+.15),"ivory")
        m.box("Lintel",(0,0,h+.06),(w+.24,.25,.12),"honey")
        count=1 if identity in ("DR01","DR03") else 2
        for i in range(count):
            x=(i-(count-1)/2)*w/count
            bone="door_l" if i==0 else "door_r"
            m.box("DoorLeaf",(x,0,h*.50),(w/count-.035,.08,h-.06),"teal",bone)
            m.box("DoorWindow",(x,-.047,h*.66),(w/count*.55,.018,h*.22),"aqua",bone)
            m.rod("DoorHandle",(x+w/count*.28,-.075,h*.40),(x+w/count*.28,-.075,h*.53),.022,"honey",bone)
    elif identity.startswith("VC"):
        if identity=="VC01":
            for i in range(12):m.box("StairTread",(0,.45-i*.077,.125*(i+1)),(.9,.077,.25*(i+1)),"ivory",bevel=.015)
            for s in (-1,1):m.line("Handrail",[(s*.46,.49,.9),(s*.46,-.44,3.65)],.025,"wood")
        else:
            h=record["clear_height_m"]
            m.box("LiftFloor",(0,0,.06),(.95,.95,.12),"teal")
            m.box("LiftBack",(0,.45,h/2),(.95,.10,h),"ivory")
            for s in (-1,1):m.box("LiftSide",(s*.45,0,h/2),(.10,.9,h),"ivory")
            for i in range(2):m.box("LiftDoor",((i-.5)*.44,-.44,h/2),(.43,.07,h-.1),"teal","door_l" if i==0 else "door_r")
            m.box("FloorIndicator",(0,-.49,h-.28),(.35,.025,.18),"navy","display")


def equipment(record):
    m=Model(); identity=record["id"]
    if identity.startswith("FUR"):furniture(m,identity)
    else:other_equipment(m,record)
    mesh=m.join("core_"+identity.lower()+"_machine")
    footprint=record.get("footprint",[record.get("span_cells",1),1])
    width,depth=[float(v)*1.5 for v in footprint]
    is_door=identity.startswith("DR")
    def p(v):
        if is_door: return (v[0]+width/2,v[1]-depth/2,v[2])
        return (v[0]*width+width/2,v[1]*depth-depth/2,v[2])
    for vertex in mesh.data.vertices:vertex.co=p(vertex.co)
    points={"root":(0,0,0),"hips":p((0,0,.3)),"spine":p((0,0,.5)),"head":p((0,0,1)),
            "display":p((0,-.3,.8)),"lid":p((0,.2,.7)),"windmill":p((0,0,1)),
            "cloud_bag":p((0,0,.7)),"night_curtain":p((0,.3,1)),"record_clip":p((0,-.1,.8)),
            "door_l":p((-.4,0,0)),"door_r":p((.4,0,0)),
            "bed_front":p((0,-.3,.6)),"bed_back":p((0,.3,.6)),
            "patient_support":p((0,0,.65)),"symptom_target":p((0,-.1,.85)),"exit":p((0,-.65,0)),
            "patient_anchor":p((0,0,.65)),"operator_anchor":p((0,-.65,0)),
            "repair_anchor":p((.65,0,0)),"effect_anchor":p((0,0,1)),"camera_focus":p((0,0,.75))}
    if is_door:
        points["door_l"]=p((-record["clear_width_m"]/2,0,0))
        points["door_r"]=p((record["clear_width_m"]/2,0,0))
    rig=armature("Equipment",[(name,point,None if name=="root" else "root") for name,point in points.items()])
    rig["rig_profile"]="equipment"
    rig["local_origin"]="registered_base_top_left_ground"
    rig["resize_policy"]="segmented_door" if is_door else ("segmented_support" if identity in ("EQ05","SE04") else "fixed")
    skin(mesh,rig)
    names=("idle","work","pause","recovery","low_motion","prepare","process","climax","safe_finish","open","closed")
    def pose(name,t,b):
        wave=math.sin(t*math.tau)
        if name in ("work","process","climax"):
            b["windmill"].rotation_euler.y=t*math.tau
            b["record_clip"].rotation_euler.x=.07*wave
            b["cloud_bag"].rotation_euler.z=.05*wave
            b["night_curtain"].rotation_euler.y=.025*wave
        elif name=="prepare":b["record_clip"].rotation_euler.x=.18*math.sin(t*math.pi)
        elif name=="safe_finish":b["record_clip"].rotation_euler.x=.08*(1-t)
        if name=="open":
            b["door_l"].rotation_euler.z=1.1*t
            b["door_r"].rotation_euler.z=-1.1*t
    actions(rig,names,pose)
    return mesh,rig


def build_architecture(root,wanted):
    records=[]
    for identity in STRUCTURES:
        if wanted and identity not in wanted:continue
        reset_scene();m=Model()
        if identity in ("floor_tile","path_1","path_2","path_3"):
            cells=int(identity[-1]) if identity.startswith("path_") else 1
            m.box("Surface",(cells*.75,-.75,-.05),(cells*1.5,1.5,.10),"ivory" if identity=="floor_tile" else "stone",bevel=.015)
            if identity.startswith("path_"):
                for x in range(cells):m.box("Paver",(.75+x*1.5,-.75,.008),(1.35,1.32,.015),"honey",bevel=.015)
        elif identity in ("wall_straight","wall_corner"):
            m.box("Wall",(.75,0,1.5),(1.5,.15,3),"ivory",bevel=.015)
            m.box("Skirting",(.75,-.08,.14),(1.5,.035,.28),"wood",bevel=.01)
            if identity=="wall_corner":m.box("CornerWall",(0,-.75,1.5),(.15,1.5,3),"ivory",bevel=.015)
        elif identity=="window":
            for x in (0,1.5):m.box("FrameSide",(x,0,1.7),(.08,.16,1.5),"wood")
            for z in (.95,1.7,2.45):m.box("FrameBar",(.75,0,z),(1.58,.16,.08),"wood")
            m.box("WindowPane",(.75,0,1.7),(1.42,.025,1.42),"aqua")
        elif identity=="fence":
            for x in (0,.75,1.5):m.box("FencePost",(x,0,.6),(.09,.09,1.2),"wood")
            for z in (.4,.9):m.box("FenceRail",(.75,0,z),(1.5,.08,.10),"honey")
        elif identity=="construction_scaffold":
            for x in (0,1.5):
                for y in (0,-1.5):m.rod("ScaffoldPost",(x,y,0),(x,y,3),.035,"silver")
            for z in (1,2,3):m.box("ScaffoldDeck",(.75,-.75,z),(1.6,1.6,.06),"honey")
            m.line("SafetyBrace",[(0,0,0),(1.5,0,3)],.025,"silver")
        elif identity=="land_marker":
            m.rod("BoundaryStake",(0,0,0),(0,0,.7),.035,"wood")
            m.polygon("LandFlag",[(0,0,.7),(.42,0,.57),(0,0,.44)],"coral")
        else:
            m.line("BuildOutline",[(0,0,.02),(1.5,0,.02),(1.5,-1.5,.02),(0,-1.5,.02)],.025,"aqua",cyclic=True)
        mesh=m.join(identity,800)
        source=root/f"art-source/production/architecture/{identity}.blend"
        target=root/f"assets/architecture/{identity}.glb"
        save_blend(source);export_glb(target,[mesh])
        records.append({"id":identity,"path":target.relative_to(root).as_posix(),**glb_metadata(target)})
        print("ARCHITECTURE "+identity,flush=True)
    write_json(root/"assets/architecture/index.json",{"modules":records,"cell_metres":1.5})
