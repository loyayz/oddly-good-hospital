"""Actual entry scan + safety tail with explicit dependency adapters, not game acceptance."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--baseline-source', type=Path, help='Optional complete pre-change public_areas.gd; otherwise reverse only this optimization.')
parser.add_argument('--control', action='store_true')
parser.add_argument('--targeted', action='store_true')
parser.add_argument('--check-only', action='store_true')
parser.add_argument('--prepare-only', action='store_true', help='Generate and check source identities without starting Godot.')
a = parser.parse_args()
if a.targeted and (a.control or a.check_only):
    parser.error("--targeted already includes A/B and current/current timing; run correctness separately")
root = Path(__file__).resolve().parents[2]
out = a.output.resolve()
out.mkdir(exist_ok=False)
p = out / 'project'
p.mkdir()
s = (root / 'game/life/public_areas.gd').read_text()

def extract(text, name):
    match = re.search(r'^func ' + re.escape(name) + r'\(.*?(?=^func |\Z)', text, re.M | re.S)
    assert match, name
    lines = match[0].rstrip().splitlines()
    while lines and (not lines[-1].strip() or lines[-1].startswith('#')):
        lines.pop()
    return '\n'.join(lines) + '\n\n'

scan = extract(s, '_waiting_point')
safe = extract(s, 'safe_wait')
helper = extract(s, '_safe_wait_at')
tail = safe[safe.index('\tif not geometry.points.has(origin):'):]
assert helper.split('\n', 1)[1] == tail, 'Private/public safety tails diverged; review permission and dynamic checks.'
assert '_safe_wait_at(' not in safe, 'Public fractional entry must not gain helper-call overhead.'
call = '\t\tif not _safe_wait_at(world,actor_id,floor_id,point,Vector2(point),actor,geometry): continue'
assert scan.count(call) == 1, 'Test must exercise the actual private candidate path.'
# Counterfactual removes only this optimization, retaining all unrelated current
# improvements. --baseline-source can independently verify an archived source.
bscan = scan.replace(call, '\t\tvar cell: Array = [point.x,point.y]\n\t\tif not safe_wait(world,actor_id,floor_id,cell,geometry): continue')
bscan = bscan.replace('space.travel_quote(world,actor_id,floor_id,[point.x,point.y])', 'space.travel_quote(world,actor_id,floor_id,cell)')
bscan = bscan.replace('best = {"floor_id":floor_id,"cell":[point.x,point.y],"travel_ticks":travel_ticks}', 'best = {"floor_id":floor_id,"cell":cell,"travel_ticks":travel_ticks}')
if a.baseline_source:
    archived = a.baseline_source.read_text()
    assert bscan == extract(archived, '_waiting_point'), 'Archived scan differs beyond this optimization.'
    assert safe == extract(archived, 'safe_wait'), 'Public safe_wait changed.'
reference = scan + safe + helper if a.control else bscan + safe
current = scan + safe + helper
prefix='''extends RefCounted
const WorldState=preload("res://world.gd")
const FloorNavigation=preload("res://floor.gd")
const HospitalTransit=preload("res://transit.gd")
const RouteClearance=preload("res://clearance.gd")
const ENTRY_GRID_WIDTH:int=96
const ENTRY_CELL_COUNT:int=9216
var space=preload("res://space.gd").new()
var ordered:Dictionary={}
var safe:bool=false
var inside:bool=false
var exists:bool=true
var geometry:Dictionary={}
var logging:bool=false
var trace:Array=[]
func region(_w,_r):return {"exists":true} if exists else {}
func contains(_w,_r,_a):return inside
func _ensure(_w,_f):pass
func _cell_region(_f,_p):return {"exists":true} if exists else {}
func _entry_landings(_w,_a,_f):return {}
func _entry_geometry_view(_w,_a,_r):return geometry
func _entry_order(_a,_o,_b,_g,_m):return ordered
func _safe_wait_geometry(_w,_a,_f,o,_g,_d):
 if logging:trace.append(["static",o])
 return safe
'''
for name, source in [('baseline', reference), ('current', current)]:
    (p / (name + '.gd')).write_text(prefix + source)
(p/'world.gd').write_text('extends RefCounted\nconst TICK_SECONDS:float=0.1\nvar facts:Dictionary={"actors":{"a":{"id":"a","location":{"floor_id":1,"cell":[0,0]}}}}\n')
(p/'floor.gd').write_text('extends RefCounted\nstatic func _id(p):return p.y*96+p.x\n')
(p/'transit.gd').write_text('extends RefCounted\nstatic func _add(a,b):return a+b\n')
(p/'clearance.gd').write_text('''extends RefCounted
var space
func _init(s=null,_w=null,_a=null,_f=0,_m=[],_o={},_i=true,_src={},_static=null):
 space=s
 if space!=null:space.constructs+=1
func reservation_reason(point):
 if space.logging:space.trace.append(["reservation",point])
 return "blocked" if space.reserved else ""
''')
(p/'space.gd').write_text('''extends RefCounted
var navigation=preload("res://nav.gd").new()
var _navigation=preload("res://nav.gd").new()
var query_counts:Dictionary={}
var bounds:Dictionary={"landings":[],"unknown":false}
var views:Dictionary={}
var reserved:bool=false
var dynamic:bool=true
var constructs:int=0
var logging:bool=false
var trace:Array=[]
var quote:Dictionary={"ok":false}
func read_view(_w,n,c):
 if n.begins_with("public_entry_landings:"):return bounds
 if not views.has(n):views[n]=c.call()
 return views[n]
func travel_quote(_w,_a,_f,cell):
 if logging:trace.append(["quote",cell])
 return quote
func _actor_rect(_a,origin):return Rect2(origin,Vector2.ONE)
func _dynamic_clear(_w,_a,_f,rect):
 if logging:trace.append(["dynamic",rect])
 return dynamic
''')
(p/'nav.gd').write_text('''extends RefCounted
var field:Dictionary={}
var leg:Dictionary={}
var calls:int=0
func ready_waiting_cost_field(_w,_a,_f,_b):
 calls+=1
 return field
func waiting_travel_ticks(_w,_a,_f,_p,_b):return leg
func floor_source(_s,_w,_f):return {}
''')
(p/'project.godot').write_text('config_version=5\n')

shutil.copyfile(Path(__file__).with_suffix('.gd'), p / 'run.gd')
for file in p.glob('*.gd'):
    file.write_text(re.sub(r'^ +', lambda match: '\t' * len(match[0]), file.read_text(), flags=re.M))
metadata = {
    'source_sha256': hashlib.sha256(s.encode()).hexdigest(),
    'baseline_sha256': hashlib.sha256(reference.encode()).hexdigest(),
    'current_extracted_sha256': hashlib.sha256(current.encode()).hexdigest(),
    'reference': str(a.baseline_source) if a.baseline_source else 'current source with only private entry optimization reversed',
    'control': a.control,
    'targeted': a.targeted,
    'formal_pass': False,
    'scope': 'Actual _waiting_point, public safe_wait and private safety tail. Region, static geometry, reservation query, dynamic bodies and navigation are explicit adapters; not complete game or geometry acceptance.',
}
(out / 'identity.json').write_text(json.dumps(metadata, indent=2))
if a.prepare_only:
    print('Private path and safety-tail identity guards passed; generated', p)
    raise SystemExit(0)
env = os.environ.copy()
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    env[key] = str(p / key)
args = ['godot', '--headless', '--path', str(p), '--script', 'res://run.gd', '--']
if a.control: args.append('--control')
if a.targeted: args.append('--targeted')
if a.check_only: args.append('--check-only')
result = subprocess.run(args, capture_output=True, text=True, env=env, timeout=300)
(p / 'run.log').write_text(result.stdout + result.stderr)
assert result.returncode == 0 and 'SCRIPT ERROR' not in result.stderr and 'ERROR:' not in result.stderr and 'failed' not in result.stderr, result.stderr[:4000]
data = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{')))
data.update(metadata)
data['engine'] = next(line for line in result.stdout.splitlines() if line.startswith('Godot Engine'))
(out / 'result.json').write_text(json.dumps(data, indent=2))
print('assertions', data['checks'], 'result', out / 'result.json')
