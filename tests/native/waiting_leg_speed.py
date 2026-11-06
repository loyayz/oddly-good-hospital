from pathlib import Path
import re,subprocess,os,json,hashlib,argparse,shutil
parser=argparse.ArgumentParser(description="Actual waiting quote wrapper; route output and subject are explicit adapters, not full navigation validation.")
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--baseline',default='35d656dc58c4f7afac8419218a12051d3617c47b')
parser.add_argument('--control',action='store_true')
a=parser.parse_args()
root=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(exist_ok=False);p=out/'project';p.mkdir()

def fun(path,name,baseline=False):
 s=subprocess.run(["git","show",f"{a.baseline}:{path}"],cwd=root,check=True,capture_output=True,text=True).stdout if baseline else (root/path).read_text();m=re.search(r'^(?:static )?func '+name+r'\(',s,re.M);e=re.search(r'^\S',s[s.index('\n',m.start())+1:],re.M);return s[m.start():s.index('\n',m.start())+1+e.start() if e else len(s)].rstrip()+'\n'
nav='game/building/hospital_navigation.gd'; space='game/building/hospital_space.gd';trans='game/building/hospital_transit.gd'
base=fun(nav,'waiting_travel_ticks',not a.control);new=fun(nav,'waiting_travel_ticks')
prefix='''extends RefCounted
const WorldState=preload("res://world.gd")
const HospitalTransit=preload("res://transit.gd")
var space=preload("res://space.gd").new()
var leg:Dictionary={"ok":true,"walking_distance":12}
var calls:int=0
func _floor_route(_a,_b,_c,_d,_e,_f,_g,_h,_i,_j,_k):
 calls+=1
 return leg
func _prepare_route_subject(_world,actor,_members,_offsets):
 return {"floor_id":actor.location.floor_id,"start":Vector2i(1,1),"initial_ticks":actor.get("prefix",2),"reason":""}
'''
for name,src in [('baseline',base),('current',new)]: (p/(name+'.gd')).write_text(prefix+fun(nav,'_waiting_cost_basis')+src)
(p/'world.gd').write_text('extends RefCounted\nconst TICK_SECONDS:float=0.1\nvar facts:Dictionary={"connectors":{},"actors":{}}\n')
(p/'space.gd').write_text('''extends RefCounted
const CELL_METERS:float=1.5
var _bodies:Dictionary={"s:":{"width_m":1.0,"depth_m":0.8}}
var content=preload("res://content.gd").new()
var query_counts:Dictionary={}
var views:Dictionary={}
var scoped:bool=true
func in_dynamic_route_query(_world):return scoped
func read_view(_world,name,build):
 if not views.has(name):views[name]=build.call()
 return views[name]
'''+fun(space,'body')+fun(space,'clearance')+fun(space,'walking_speed'))
(p/'content.gd').write_text('''extends RefCounted
var balance:Dictionary={"movement_speeds":{"1":1.3,"2":0.7}}
func definition(_table,_id):return {"kind":"lift"}
func actor_body(_actor):return {"width_m":2.0,"depth_m":1.0}
''')
(p/'transit.gd').write_text('extends RefCounted\nconst HospitalSpace=preload("res://space.gd")\nconst WorldState=preload("res://world.gd")\nconst MAX_TICK:int=9223372036854775807\n'+fun(trans,'walking_ticks')+fun(trans,'_add'))
(p/'project.godot').write_text('config_version=5\n')
for g in p.glob('*.gd'):
 if g.name!='run.gd': g.write_text(re.sub(r'^ ', '\t', g.read_text(),flags=re.M))
shutil.copyfile(Path(__file__).with_suffix('.gd'),p/'run.gd')
env=os.environ.copy()
for k in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
 d=out/k;d.mkdir(exist_ok=True);env[k]=str(d)
r=subprocess.run(['godot','--headless','--path',str(p),'--script','res://run.gd'],capture_output=True,text=True,env=env,timeout=120)
(out/'run.log').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);assert r.returncode==0 and 'SCRIPT ERROR' not in r.stderr and 'ERROR:' not in r.stderr
j=json.loads(next(l for l in r.stdout.splitlines() if l.startswith('{')));j['engine']=next(line for line in r.stdout.splitlines() if line.startswith('Godot Engine'));j['window_iterations']=20000;j['control']=a.control;j['baseline']=a.baseline;j['formal_pass']=False;j['source_sha256']=hashlib.sha256((root/nav).read_bytes()).hexdigest();j['scope']='Exact waiting_travel_ticks and _waiting_cost_basis, walking_ticks, body and clearance. Floor route/subject/world/content are explicit adapters. Measures quote wrapper only, not AStar or full game.';(out/'result.json').write_text(json.dumps(j,indent=2))
