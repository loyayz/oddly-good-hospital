"""Run the exact environment end_query function against ordered-cache expectations.

Only the owning service's unrelated declarations are omitted. Real Godot
Dictionaries perform every merge, insertion-order eviction, and nested-scope step.
This is not a complete environment observation or whole-game benchmark.
"""
import argparse, hashlib, json, os, re, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default='godot')
p.add_argument('--baseline',default='35d656dc58c4f7afac8419218a12051d3617c47b')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args(); repo=Path(__file__).resolve().parents[2]; out=a.output.resolve()
out.mkdir(parents=True,exist_ok=False); project=out/'project'; project.mkdir()
path='game/operations/environment_service.gd'
sources={'current':(repo/path).read_bytes(),'baseline':subprocess.check_output(['git','show',a.baseline+':'+path],cwd=repo)}
functions={}
for name,raw in sources.items():
    source=raw.decode(); match=re.search(r'^func end_query\(.*?(?=^func |\Z)',source,re.M|re.S)
    if not match: raise RuntimeError('end_query missing')
    functions[name]=match.group()
    (project/(name+'.gd')).write_text('extends RefCounted\nvar _query_depth: int = 0\nvar _coverage_cache: Dictionary = {}\nvar _query: Dictionary = {}\n'+match.group())
h=Path(__file__).with_suffix('.gd'); shutil.copyfile(h,project/'run.gd')
(project/'project.godot').write_text('config_version=5\n')
env=os.environ.copy()
for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
    d=out/key.lower();d.mkdir();env[key]=str(d)
cmd=[a.godot,'--headless','--path',str(project),'--script','res://run.gd']
r=subprocess.run(cmd,capture_output=True,text=True,env=env,timeout=120)
(out/'run.log').write_text(r.stdout+r.stderr);r.check_returncode()
if 'SCRIPT ERROR' in r.stderr or 'ERROR:' in r.stderr: raise RuntimeError('See run.log')
result=json.loads(next(line for line in reversed(r.stdout.splitlines()) if line.startswith('{')))
result.update({'baseline':a.baseline,'source_hashes':{k:hashlib.sha256(v).hexdigest() for k,v in sources.items()},'function_hashes':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in functions.items()},'harness_sha256':hashlib.sha256(h.read_bytes()).hexdigest(),'command':cmd,'engine':subprocess.check_output([a.godot,'--version'],env=env,text=True).strip(),'formal_pass':False})
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
