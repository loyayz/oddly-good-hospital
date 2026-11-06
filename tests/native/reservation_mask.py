"""Compare complete production reservation mask helper on Linux Godot.
Inputs are explicit reservation rectangles; exact engine geometry executes unchanged.
This does not cover authorization, full navigation or game timing.
"""
import argparse, hashlib, json, os, re, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',default='godot')
p.add_argument('--baseline',default='35d656dc58c4f7afac8419218a12051d3617c47b')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();repo=Path(__file__).resolve().parents[2];out=a.output.resolve()
out.mkdir(parents=True,exist_ok=False);project=out/'project';project.mkdir()
path='game/building/route_clearance.gd'
sources={'current':(repo/path).read_bytes(),'baseline':subprocess.check_output(['git','show',a.baseline+':'+path],cwd=repo)}
functions={}
for name,raw in sources.items():
    source=raw.decode();parts=[]
    for method in ['_mark_reservation_mask']:
        m=re.search(r'^func '+method+r'\(.*?(?=^func |\Z)',source,re.M|re.S)
        if not m: raise RuntimeError('Missing '+method)
        parts.append(m.group())
    functions[name]='\n'.join(parts)
    (project/(name+'.gd')).write_text('extends RefCounted\nconst FloorNavigation = preload("res://floor.gd")\nvar _size: int = 1\nvar _reservations: Array = []\n'+functions[name])
(project/'floor.gd').write_text('extends RefCounted\nconst SIDE = 96\nstatic func _id(cell: Vector2i) -> int:\n\treturn cell.y*SIDE+cell.x\n')
h=Path(__file__).with_suffix('.gd');shutil.copyfile(h,project/'run.gd')
(project/'project.godot').write_text('config_version=5\n')
env=os.environ.copy()
for k in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
    d=out/k.lower();d.mkdir();env[k]=str(d)
cmd=[a.godot,'--headless','--path',str(project),'--script','res://run.gd']
r=subprocess.run(cmd,capture_output=True,text=True,env=env,timeout=120)
(out/'run.log').write_text(r.stdout+r.stderr);r.check_returncode()
if 'SCRIPT ERROR' in r.stderr or 'ERROR:' in r.stderr:raise RuntimeError('See run.log')
result=json.loads(next(x for x in reversed(r.stdout.splitlines()) if x.startswith('{')))
result.update({'baseline':a.baseline,'source_hashes':{k:hashlib.sha256(v).hexdigest() for k,v in sources.items()},'function_hashes':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in functions.items()},'harness_sha256':hashlib.sha256(h.read_bytes()).hexdigest(),'command':cmd,'engine':subprocess.check_output([a.godot,'--version'],env=env,text=True).strip(),'formal_pass':False})
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
