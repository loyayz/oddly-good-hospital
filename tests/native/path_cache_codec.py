"""Exercise exact production cached_floor_path with explicit input adapters.

The real Dictionary/PackedInt32 cache implementation is extracted unchanged.
World, graph result, graph key, source and trimming are explicit adapters. No
search, permission, eviction policy or complete navigation is claimed tested.
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
a = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
project = out / 'project'
project.mkdir()
source_path = 'game/building/navigation_cache.gd'
current = (repo / source_path).read_bytes()
baseline = subprocess.run(['git', 'show', f'{a.baseline}:{source_path}'], cwd=repo, check=True, capture_output=True).stdout

def function(source, name):
    lines = source.decode().splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if re.match(r'^func ' + re.escape(name) + r'\(', line))
    end = start + 1
    while end < len(lines) and (not lines[end].strip() or lines[end].startswith('\t')):
        end += 1
    return ''.join(lines[start:end]).rstrip() + '\n'

adapters = '''extends RefCounted
const WorldState = preload("res://world.gd")
const HospitalSpace = preload("res://space.gd")
const FloorNavigation = preload("res://floor.gd")
const RouteClearance = preload("res://query.gd")
var _entries: Dictionary = {}
var _query_charged: int = 0
func _graph_key(_a,_b,_c,_d,_e,_f,_g): return "graph"
func floor_source(_a,_b,_c): return {}
func _trim(_a,_b): pass
'''
for name, source in [('baseline', baseline), ('current', current)]:
    (project / (name + '.gd')).write_text(adapters + function(source, 'cached_floor_path'))
(project / 'world.gd').write_text('extends RefCounted\n')
(project / 'query.gd').write_text('extends RefCounted\n')
(project / 'space.gd').write_text('extends RefCounted\nvar query_counts: Dictionary = {"static_path_hits":0,"static_path_builds":0}\nvar content: Dictionary = {"balance":{"pathfinding":{"graph_cache_target_bytes":134217728}}}\n')
(project / 'floor.gd').write_text('''extends RefCounted
const SIDE: int = 96
var geometry = preload("res://query.gd").new()
var result: Dictionary = {}
var builds: int = 0
static func _id(cell: Vector2i)->int: return cell.y*SIDE+cell.x
static func _cell(id: int)->Vector2i: return Vector2i(id%SIDE,id/SIDE)
func find_path(_a,_b,_c,_d,_e,_f,_g,_h,cost_only):
 builds += 1
 var out=result.duplicate(true)
 if cost_only: out.erase("cells")
 return out
''')
harness = Path(__file__).with_suffix('.gd')
shutil.copyfile(harness, project / 'run.gd')
(project / 'project.godot').write_text('config_version=5\n')
env = os.environ.copy()
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    path = out / key.lower()
    path.mkdir()
    env[key] = str(path)
command = [a.godot, '--headless', '--path', str(project), '--script', 'res://run.gd']
run = subprocess.run(command, text=True, capture_output=True, env=env, timeout=120)
(out / 'run.log').write_text(run.stdout + run.stderr)
run.check_returncode()
if 'ERROR' in run.stderr: raise RuntimeError('Godot error; see run.log')
result = json.loads(next(line for line in reversed(run.stdout.splitlines()) if line.startswith('{')))
means = []
for length in [0, 32, 192]:
    for hit in [True, False]:
        before = [w['us'] for w in result['windows'] if w['length'] == length and w['hit'] == hit and w['old']]
        after = [w['us'] for w in result['windows'] if w['length'] == length and w['hit'] == hit and not w['old']]
        assert len(before) == len(after) == 6
        means.append({'length': length, 'hit': hit, 'baseline_us': sum(before)/6, 'current_us': sum(after)/6, 'local_reduction_percent': (1-sum(after)/sum(before))*100})
result.update({'means': means, 'engine': subprocess.run([a.godot, '--version'], text=True, capture_output=True, env=env, check=True).stdout.strip(), 'baseline': a.baseline, 'baseline_sha256': hashlib.sha256(baseline).hexdigest(), 'source_sha256': hashlib.sha256(current).hexdigest(), 'harness_sha256': hashlib.sha256(harness.read_bytes()).hexdigest(), 'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'command': command, 'scope': __doc__, 'formal_pass': False})
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
