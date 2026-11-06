from pathlib import Path
import re,subprocess,json,os,sys
import argparse,hashlib,shutil
parser=argparse.ArgumentParser(description="Isolated actual waiting-entry scan; geometry/navigation are explicit adapters.")
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--baseline',default='35d656dc58c4f7afac8419218a12051d3617c47b')
parser.add_argument('--control',action='store_true')
parser.add_argument('--short',action='store_true')
a=parser.parse_args()
root=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(exist_ok=False);p=out/'project';p.mkdir()
source='game/life/public_areas.gd'
def extract(text):return text[text.index('func _waiting_point('):text.index('func _entry_order(')]
c=extract((root/source).read_text())
s=c if a.control else extract(subprocess.check_output(['git','show',f'{a.baseline}:{source}'],cwd=root,text=True))
prefix='''extends RefCounted
const WorldState=preload("res://world.gd")
const FloorNavigation=preload("res://floor.gd")
const HospitalTransit=preload("res://transit.gd")
const ENTRY_GRID_WIDTH:int=96
const ENTRY_CELL_COUNT:int=9216
var space=preload("res://space.gd").new()
var ordered:Dictionary={}
var safe:bool=false
var inside:bool=false
var exists:bool=true
var safe_calls:int=0
func region(_w,_r):return {"exists":true} if exists else {}
func contains(_w,_r,_a):return inside
func safe_wait(_w,_a,_f,_c,_g={}):
 safe_calls+=1
 return safe
func _safe_wait_at(w,a,f,p,_o,_actor,g):return safe_wait(w,a,f,[p.x,p.y],g)
func _entry_landings(_w,_a,_f):return {}
func _entry_geometry_view(_w,_a,_r):return {}
func _entry_order(_a,_o,_b,_g,_m):return ordered
'''
for n,src in [('baseline',s),('current',c)]: (p/(n+'.gd')).write_text(prefix+src)
(p/'world.gd').write_text('extends RefCounted\nconst TICK_SECONDS:float=0.1\nvar facts:Dictionary={"actors":{"a":{"location":{"floor_id":1,"cell":[0,0]}}}}\n')
(p/'floor.gd').write_text('extends RefCounted\nstatic func _id(p):return p.y*96+p.x\n')
(p/'transit.gd').write_text('extends RefCounted\nstatic func _add(a,b):return a+b\n')
(p/'space.gd').write_text('''extends RefCounted
var navigation=preload("res://nav.gd").new()
var query_counts:Dictionary={}
var bounds:Dictionary={"landings":[],"unknown":false}
func read_view(_w,_n,_c):return bounds
func travel_quote(_w,_a,_f,_c):return {"ok":false}
''')
(p/'nav.gd').write_text('''extends RefCounted
var field:Dictionary={}
var leg:Dictionary={}
var calls:int=0
func ready_waiting_cost_field(_w,_a,_f,_b):
 calls+=1
 return field
func waiting_travel_ticks(_w,_a,_f,_p,_b):return leg
''')
(p/'project.godot').write_text('config_version=5\n')
shutil.copyfile(Path(__file__).with_suffix('.gd'),p/'run.gd')
if a.short:
 f=p/'run.gd';r=f.read_text();r=r.replace('for n in [0,1,8,96,512]:\n\t\t\tfor mode in ["unsafe"','for n in [0,1]:\n\t\t\tfor mode in ["unsafe"').replace('iterations=20000 if n<=8 or mode=="success" else 1000','iterations=50000');f.write_text(r)
for f in p.glob('*.gd'):f.write_text(re.sub(r'^ +',lambda m:'\t'*len(m[0]),f.read_text(),flags=re.M))
env=os.environ.copy()
for k in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:env[k]=str(p/k)
r=subprocess.run(['godot','--headless','--path',str(p),'--script','res://run.gd'],capture_output=True,text=True,env=env,timeout=240)
(p/'run.log').write_text(r.stdout+r.stderr)
print(r.stderr[:3000]);assert r.returncode==0 and 'SCRIPT ERROR' not in r.stderr and 'failed' not in r.stderr
j=json.loads(next(x for x in r.stdout.splitlines() if x.startswith('{')))
j.update(engine=next(x for x in r.stdout.splitlines() if x.startswith('Godot Engine')),baseline=a.baseline,control=a.control,short=a.short,formal_pass=False,source_sha256=hashlib.sha256((root/source).read_bytes()).hexdigest(),scope='Complete _waiting_point scan. Region, containment, safe_wait, ordering, read view and navigation are explicit adapters; no full game/geometry/AStar proof.')
(out/'result.json').write_text(json.dumps(j,indent=2));print('assertions',j['checks']);print('result',out/'result.json')
