"""Run the real department sample function with no patient/environment work.
Staff/day facts and sorted staff IDs are explicit input adapters. Patient helpers
fail if called. This checks employee daily sampling, not the complete department.
"""
import argparse, hashlib, json, os, re, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default='godot');p.add_argument('--baseline',default='35d656dc58c4f7afac8419218a12051d3617c47b');p.add_argument('--output',type=Path,required=True)
a=p.parse_args();repo=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);project=out/'project';project.mkdir()
path='game/operations/department_service.gd'
sources={'current':(repo/path).read_bytes(),'baseline':subprocess.check_output(['git','show',a.baseline+':'+path],cwd=repo)}
pre='''extends RefCounted
const WorldState = preload("res://world.gd")
var environment = null
var sample_workers_enabled: bool = false
var _worker_sample_batch = null
var sample_worker_tasks: int = 4
var sample_worker_diagnostics: bool = false
var content = null
var ensure_calls: int = 0
func ensure(_world): ensure_calls += 1
func _track_phase(_a,_b,_c): assert(false)
func _environment(_a,_b,_c,_d): assert(false); return {}
func _update_cause_clocks(_a,_b,_c,_d): assert(false)
func _ticks(_a): assert(false); return 0
func _sample_anger(_a,_b,_c,_d): assert(false)
func reason_cards(_a,_b): assert(false); return []
func _detail(_a,_b,_c): assert(false)
'''
functions={}
for name,raw in sources.items():
    m=re.search(r'^func sample\(.*?(?=^func |\Z)',raw.decode(),re.M|re.S)
    if not m:raise RuntimeError('Missing sample')
    functions[name]=m.group();(project/(name+'.gd')).write_text(pre+m.group())
for name in ['game/operations/environment_service.gd','game/building/hospital_space.gd','game/operations/environment_sample_batch.gd']:
    dest=project/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text('extends RefCounted\n')
(project/'world.gd').write_text('''extends RefCounted
const TICKS_PER_DAY: int = 18000
var sim_tick: int = 0
var facts: Dictionary = {"staff":{},"departments":{"staff_days":{}}}
var ids_calls: int = 0
func active_visit_ids() -> Array: return []
func ids(kind: String) -> Array:
 assert(kind=="staff")
 ids_calls += 1
 var r: Array = facts.staff.keys()
 r.sort()
 return r
''')
h=Path(__file__).with_suffix('.gd');shutil.copyfile(h,project/'run.gd');(project/'project.godot').write_text('config_version=5\n')
env=os.environ.copy()
for k in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
    d=out/k.lower();d.mkdir();env[k]=str(d)
cmd=[a.godot,'--headless','--path',str(project),'--script','res://run.gd'];r=subprocess.run(cmd,capture_output=True,text=True,env=env,timeout=120)
(out/'run.log').write_text(r.stdout+r.stderr);r.check_returncode()
if 'SCRIPT ERROR' in r.stderr or 'ERROR:' in r.stderr:raise RuntimeError('See run.log')
result=json.loads(next(x for x in reversed(r.stdout.splitlines()) if x.startswith('{')))
result.update({'baseline':a.baseline,'source_hashes':{k:hashlib.sha256(v).hexdigest() for k,v in sources.items()},'function_hashes':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in functions.items()},'harness_sha256':hashlib.sha256(h.read_bytes()).hexdigest(),'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'command':cmd,'engine':subprocess.check_output([a.godot,'--version'],env=env,text=True).strip(),'formal_pass':False})
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
