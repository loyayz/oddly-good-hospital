"""Compare the complete door-candidate function with explicit query inputs.

The floor/version, clearance and broadphase results are input adapters. This does
not test Boost, door permissions or the complete movement integration.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='godot')
parser.add_argument('--baseline', default='35d656dc58c4f7afac8419218a12051d3617c47b')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
project = output / 'project'
project.mkdir()
path = 'game/building/hospital_space.gd'
sources = {
    'baseline': subprocess.check_output(['git', 'show', f'{args.baseline}:{path}'], cwd=repo),
    'current': (repo / path).read_bytes(),
}
prelude = '''extends RefCounted
const WorldState = preload("res://world.gd")
const BodyIndex = preload("res://index.gd")
var _navigation = preload("res://nav.gd").new()
var _door_views: Dictionary = {}
var query_counts: Dictionary = {"door_candidates":0}
var regions: Array = []
var region_calls: int = 0
var clearance_calls: int = 0
func clearance(actor):
 clearance_calls += 1
 return actor.width
func _door_rect(door,span): return Rect2(door.x,door.y,span,1)
func _reservation_regions(_w,_f,_r):
 region_calls += 1
 return regions
'''
functions = {}
for name, raw in sources.items():
    match = re.search(r'^func movement_doors\(.*?(?=^func |\Z)', raw.decode(), re.M | re.S)
    if not match:
        raise RuntimeError('Door-candidate function missing')
    functions[name] = match.group()
    (project / f'{name}.gd').write_text(prelude.replace('\n ', '\n\t') + match.group())
(project / 'world.gd').write_text('extends RefCounted\nvar facts: Dictionary = {}\n')
(project / 'nav.gd').write_text('extends RefCounted\nvar version: int = 1\nfunc floor_version(_s,_w,_f): return version\n')
(project / 'index.gd').write_text('''extends RefCounted
var selected: Array[String] = []
var calls: int = 0
func update(_id,_f,_r): pass
func candidates(_f,_r) -> Array[String]:
 calls += 1
 return selected.duplicate()
''')
harness = Path(__file__).with_suffix('.gd')
shutil.copyfile(harness, project / 'run.gd')
(project / 'project.godot').write_text('config_version=5\n')
environment = os.environ.copy()
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    location = output / key.lower()
    location.mkdir()
    environment[key] = str(location)
command = [args.godot, '--headless', '--path', str(project), '--script', 'res://run.gd']
run = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=120)
(output / 'run.log').write_text(run.stdout + run.stderr)
run.check_returncode()
if 'SCRIPT ERROR' in run.stderr or 'ERROR:' in run.stderr:
    raise RuntimeError('Godot error, see run.log')
result = json.loads(next(line for line in reversed(run.stdout.splitlines()) if line.startswith('{')))
result.update({
    'baseline': args.baseline,
    'source_hashes': {k: hashlib.sha256(v).hexdigest() for k, v in sources.items()},
    'function_hashes': {k: hashlib.sha256(v.encode()).hexdigest() for k, v in functions.items()},
    'harness_sha256': hashlib.sha256(harness.read_bytes()).hexdigest(),
    'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'engine': subprocess.check_output([args.godot, '--version'], env=environment, text=True).strip(),
    'command': command,
    'formal_pass': False,
})
(output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
