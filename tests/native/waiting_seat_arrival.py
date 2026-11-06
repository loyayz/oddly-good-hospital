"""Exact-method contract checks, not gameplay/pathfinding acceptance."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--godot', default='godot')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
project = out / 'project'
project.mkdir()

def method(path, name):
    source = (root / path).read_text()
    match = re.search(r'^(?:static )?func ' + name + r'\(', source, re.M)
    assert match, (path, name)
    end = source.find('\nfunc ', match.end())
    static_end = source.find('\nstatic func ', match.end())
    ends = [x for x in [end, static_end] if x >= 0]
    return source[match.start():min(ends) if ends else len(source)].rstrip() + '\n'

waiting = 'game/life/waiting_life.gd'
areas = 'game/life/public_areas.gd'
departments = 'game/operations/department_service.gd'
(project / 'waiting.gd').write_text('''extends RefCounted
const WorldState = preload("res://world.gd")
const HospitalRemodel = preload("res://remodel.gd")
const PUBLIC_SEAT_DEFINITIONS = ["FUR09"]
var content = preload("res://content.gd").new()
var space = preload("res://space.gd").new()
var visitors = null
var candidates: Array = []
var searches: int = 0
var safe_waits: int = 0
func _public_seat(_world, _facility): return true
func _occupied(world, facility_id, actor_id):
    return world.owner != "" and world.owner != actor_id
func _seat_target_valid(_world, _id): return true
func _seat_target_quote(_world, _visit, _id): return {"ok":false}
func _manual_seat_quote(_world, _visit, _id): return {"ok":false}
func _release_seat(world, visit_id): world.facts.waiting_life.seats.erase(visit_id)
func seat_candidates(_world, _visit_id):
    searches += 1
    return candidates
func _wait_safely(_world, _visit, _intent): safe_waits += 1
''' + '\n'.join(method(waiting, name) for name in ['_dispatch_public_seat', '_claim_seat', 'is_seated', '_ticks']))
(project / 'areas.gd').write_text('''extends RefCounted
const WorldState = preload("res://world.gd")
var queue: Array = []
var queries: int = 0
func _facility_queue(_world, _purpose, _id):
    queries += 1
    return queue
func _queue_fit(_world, _id, _ids): return {"ok":true}
func changed(_world): pass
func region(_world, _reference): return {"id":"area"}
func area_valid(_world, _area, _kinds): return true
func facilities(_world, _area, _definitions): return ["chair"]
func compatible_geometry(_world, _area, _definitions, _actors): return true
func contains(_world, _area, _actor): return true
''' + method(areas, 'turn'))
(project / 'space.gd').write_text('''extends RefCounted
var public_areas = preload("res://areas.gd").new()
var reserve_result: String = ""
var move_result: String = ""
var reserves: int = 0
var requests: int = 0
func at(world, actor_id, floor_id, cell):
    return world.facts.actors[actor_id].location.floor_id == floor_id and world.facts.actors[actor_id].location.cell == cell
func facility_layout(_world, _id): return {"floor_id":1,"patient_cell":[2,2]}
func reserve_facility(world, _facility, actor_id, _owner):
    reserves += 1
    if reserve_result.is_empty(): world.owner = actor_id
    return reserve_result
func sync_actor(_world, _actor): pass
func request_move(world, actor, floor_id, cell):
    requests += 1
    if move_result.is_empty(): world.facts.moves[actor] = {"floor_id":floor_id,"cell":cell}
    return move_result
func movement_failure(_world, _actor): return ""
func cancel_ground_move(world, actor):
    world.facts.moves.erase(actor)
    return true
''')
(project / 'world.gd').write_text('''extends RefCounted
const TICK_SECONDS: float = 0.1
var sim_tick: int = 51
var owner: String = ""
var facts: Dictionary = {"facilities":{"chair":{"id":"chair","definition_id":"FUR09"}},"actors":{"patient":{"id":"patient","location":{"kind":"floor","floor_id":1,"cell":[1,1]},"posture":"standing"}},"moves":{},"visits":{"visit":{"actor_id":"patient"}},"waiting_life":{"seats":{},"needs":{}},"tickets":{"ticket":{"kind":"gp","waited_ticks":0,"pause_reasons":{}}},"departments":{"guidance":{}}}
''')
(project / 'remodel.gd').write_text('extends RefCounted\nstatic func blocked(_world, _id): return false\n')
shutil.copyfile(root / 'docs/data/balance.json', project / 'balance.json')
(project / 'content.gd').write_text('''extends RefCounted
var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://balance.json"))
func definition(_name, _id): return {"anger_growth_multiplier":1.0,"anger_decay_multiplier":1.0}
''')
(project / 'departments.gd').write_text('''extends RefCounted
const WorldState = preload("res://world.gd")
const HospitalWaitingLife = preload("res://waiting.gd")
var content = preload("res://content.gd").new()
var waiting_life = null
func _environment(_world, _actor, _floor, _cell): return {}
''' + '\n'.join(method(departments, name) for name in ['_sample_anger', '_update_cause_clocks', '_clock', '_cause', '_anger_change', '_ticks']))
(project / 'project.godot').write_text('config_version=5\n')
# All adapters use tabs like the exact production methods appended to them.
for file in project.glob('*.gd'):
    file.write_text(re.sub(r'^( +)', lambda m: '\t' * (len(m[1]) // 4), file.read_text(), flags=re.M))
shutil.copyfile(Path(__file__).with_suffix('.gd'), project / 'run.gd')
env = os.environ.copy()
for key in ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    directory = out / key
    directory.mkdir()
    env[key] = str(directory)
result = subprocess.run([args.godot, '--headless', '--path', str(project), '--script', 'res://run.gd'], capture_output=True, text=True, env=env, timeout=120)
(out / 'run.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
assert result.returncode == 0 and 'SCRIPT ERROR' not in result.stderr
report = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{')))
report['engine'] = next(line for line in result.stdout.splitlines() if line.startswith('Godot Engine'))
report['scope'] = 'Exact production seat dispatch, claim, is_seated, public turn, anger sampling and cause clocks. World, geometry, reservation, movement and content lookup are explicit adapters. No real pathfinding, gameplay or performance acceptance.'
report['formal_pass'] = False
report['sources'] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in [waiting, areas, departments, 'docs/data/balance.json']}
(out / 'result.json').write_text(json.dumps(report, indent=2))
assert report['failed'] == 0
