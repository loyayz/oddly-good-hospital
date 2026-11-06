#!/usr/bin/env python3
"""Run isolated production wait-capture comparison in Godot on any host.

The capture function and value readers are extracted unchanged. Explicit input
adapters supply spatial-query results, environment samples and content geometry;
this is NOT STAFF-69, a spatial-index test or a full-game performance benchmark.
No repository inputs or runtime caches are modified. Timings cover this isolated
capture with adapters only; do not extrapolate them to whole-step performance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default='godot')
parser.add_argument('--baseline', default='35d656dc58c4f7afac8419218a12051d3617c47b')
parser.add_argument('--iterations', type=int, default=2000)
parser.add_argument('--rounds', type=int, default=4)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
if args.iterations < 1 or args.rounds < 1:
    parser.error('iterations and rounds must be positive')
if args.output and args.output.exists():
    parser.error('output already exists; choose a new evidence file')
repo = Path(__file__).resolve().parents[2]
workspace = tempfile.TemporaryDirectory(prefix='ogh-wait-capture-')
p = Path(workspace.name)
(p/'project.godot').write_text('[application]\nconfig/name="wait-capture-isolation"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="ogh-wait-isolation"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
(p/'world.gd').write_text('extends RefCounted\nvar facts: Dictionary = {}\n')
(p/'remodel.gd').write_text('extends RefCounted\nstatic func blocked(world: RefCounted, id: String) -> bool:\n\treturn world.facts.get("blocked",{}).has(id)\n')
import subprocess,re
names=['_capture_wait_signature','_watch_wait','_wait_actor_value','_wait_area_value','_wait_facility_value','_wait_queue_value']
adapters='''extends RefCounted
const WorldState = preload("res://world.gd")
const HospitalRemodel = preload("res://remodel.gd")
class InputSpace extends RefCounted:
	var navigation: RefCounted
	var _navigation: RefCounted
	var body_calls: int = 0
	var connection_calls: int = 0
	var routing_calls: int = 0
	func body(actor: Dictionary) -> Dictionary:
		body_calls += 1
		return actor.body.duplicate()
	func clearance(actor: Dictionary) -> int: return int(actor.body.width)
	func _ensure_actor_index(_world: RefCounted) -> void: pass
	func connection_basis(world: RefCounted) -> Array:
		connection_calls += 1
		return world.facts.connections.duplicate(true)
	func routing_floor_basis(world: RefCounted) -> Array:
		routing_calls += 1
		return world.facts.floors.duplicate()
	func floor_static_version(_space: RefCounted, world: RefCounted, floor_id: int) -> int:
		return int(world.facts.floor_versions[floor_id])
var space: InputSpace = InputSpace.new()
func _init() -> void:
	space.navigation = space
	space._navigation = space
var input_view: Dictionary = {}
var input_area: Dictionary = {}
func _decision_view(_world: RefCounted) -> Dictionary: return input_view
func region(_world: RefCounted, _reference: Dictionary) -> Dictionary: return input_area
func _facility_members(area: Dictionary, definitions: Array) -> Array:
	var out: Array = []
	for i: int in area.facilities.size():
		if area.definitions[i] in definitions: out.append(i)
	return out
func _add_dynamic_dependencies(world: RefCounted, _floor: int, _bounds: Array[Rect2], members: Array, actors: Dictionary, reservations: Dictionary) -> void:
	# Explicit spatial-query input: all declared nearby actors and reservations.
	# This test validates capture consumption, not the spatial query implementation.
	for id: String in world.facts.nearby:
		if not id in members: actors[id] = true
	for id: String in world.facts.nearby_reservations:
		var r: Dictionary = world.facts.nearby_reservations[id]
		reservations[id] = [id,r.actor_id,r.staff_ids,r.regions]
func _environment_samples(view: Dictionary, floor_id: int, points: Array) -> Array:
	return [floor_id,points.duplicate(true),view.environment.duplicate(true)]
'''
for mode,source in [('baseline',subprocess.check_output(['git','show',args.baseline+':game/life/public_areas.gd'],cwd=repo,text=True)),('candidate',(repo/'game/life/public_areas.gd').read_text())]:
 out=adapters
 for name in names:
  m=re.search(r'^func '+name+r'\(.*?(?=^func |\Z)',source,re.M|re.S);assert m,name
  out+='\n'+m.group(0)
 (p/(mode+'.gd')).write_text(out)

RUN_SCRIPT = r'''
extends SceneTree
const World = preload("res://world.gd")
const Before = preload("res://baseline.gd")
const After = preload("res://candidate.gd")
var failed: bool = false
func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)
func fixture(count: int, mode: String) -> Dictionary:
	var world: RefCounted = World.new()
	var area: Dictionary = {"floor_id":1,"room_id":"room"}
	var intent: Dictionary = {"id":"waiting_a","actor_id":"a","area":area,"public_purpose":"rest" if mode=="rest" else "seat","arrived_tick":1,"phase":"local_wait"}
	if mode=="visitor": intent.ticket_id = "ticket"
	if mode=="manual":
		intent.mode = "manual"
		intent.manual_facility_id = "chair"
	var queue: Array = [intent]
	var actors: Dictionary = {"a":{"id":"a","location":{"floor_id":1,"cell":[1,1]},"body":{"width":2,"height":1},"posture":"standing","facing":0.0}}
	var nearby: Array = []
	for i: int in count:
		var id: String = "q%d" % i
		actors[id] = {"id":id,"location":{"floor_id":1,"cell":[3+i,3]},"body":{"width":1+i%3,"height":1},"posture":"sitting" if i%2==0 else "standing","facing":float(i%4)}
		nearby.append(id)
		queue.append({"id":"w"+id,"actor_id":id,"staff_ids":[id],"arrived_tick":i-1,"phase":["local_wait","local_travel","manual_wait","ended"][i%4],"facility_id":"","mode":"auto"})
	var facility: Dictionary = {"id":"chair","definition_id":"FUR09","cell":[5,5],"footprint":[1,1],"patient_cell":[5,6],"operator_cells":[[5,6],[6,5]],"repair_cell":[6,5],"failed":mode=="failed"}
	var reservation: Dictionary = {"id":"reserved","staff_ids":["someone"]} if mode=="reserved" else {}
	world.facts = {"actors":actors,"rooms":{"room":{"kind":"public","origin":[0,0],"size":[32,32],"wall_edges":[]}},"research":{"R15":true},"facilities":{"chair":facility},"adaptations":{},"staff_life":{"reservations":{"chair":reservation} if not reservation.is_empty() else {}},"moves":{},"relationships":{"a:q0":{"kind":"friend"}},"connections":[[1,2,"lift"]],"floors":[1,2],"floor_versions":{1:7,2:9},"nearby":nearby,"nearby_reservations":{"r":{"actor_id":"q0","staff_ids":[],"regions":[{"floor_id":1,"rect":[4,4,2,2]}]}},"blocked":{"chair":true} if mode=="blocked" else {},"rng":{"state":"unchanged"}}
	if mode=="adapted": world.facts.adaptations.chair = {"actor_id":"a","staff_ids":["a"],"regions":[],"patient_cell":[7,7],"operator_cells":[[7,8]],"repair_cell":[8,7]}
	var view: Dictionary = {"users":{"chair":["other"]} if mode in ["occupied","visitor"] else {},"visitor_seats":{"chair":true} if mode=="visitor" else {},"queues":{JSON.stringify([intent.public_purpose,area],"",true,true):queue},"environment":[["cleanliness",7]]}
	var region: Dictionary = {"geometry":"v1","facilities":["chair"],"definitions":["FUR09"],"bounds":Rect2(0,0,32,32)}
	return {"world":world,"intent":intent,"view":view,"area":region,"definitions":[] if mode=="empty" else ["FUR09"]}
func execute(f: Dictionary, kind: String) -> Dictionary:
	var probe: RefCounted = Before.new() if kind=="baseline" else After.new()
	probe.input_view = f.view
	probe.input_area = f.area
	var observed: Dictionary = {"resources":{},"bounds":[]}
	var signature: Array
	if kind=="optimized": signature = probe._capture_wait_signature(f.world,f.intent,f.definitions,[],{"extra":"yes"},[1,2],observed,false)
	else: signature = probe._capture_wait_signature(f.world,f.intent,f.definitions,[],{"extra":"yes"},[1,2],observed)
	probe.space.navigation = null
	probe.space._navigation = null
	return {"observed":observed,"signature":signature,"calls":{"body":probe.space.body_calls,"connection":probe.space.connection_calls,"routing":probe.space.routing_calls}}
func _initialize() -> void:
	var cases: int = 0
	for count: int in [0,1,8,32]:
		for mode: String in ["vacant","occupied","reserved","visitor","manual","rest","empty","failed","blocked","adapted"]:
			var f: Dictionary = fixture(count,mode)
			var frozen: PackedByteArray = var_to_bytes(f.world.facts)
			var a: Dictionary = execute(f,"baseline")
			var b: Dictionary = execute(f,"candidate")
			var c: Dictionary = execute(f,"optimized")
			check(a==b,"diagnostic compatibility %s/%d" % [mode,count])
			check(a.observed==c.observed,"subscription parity %s/%d" % [mode,count])
			check(c.signature.is_empty(),"no unused signature")
			check(c.observed.resources.has("actor:a") and c.observed.resources.has("control:") and (mode=="empty" or c.observed.resources.has("facility:chair")),"required dependency sources")
			check(var_to_bytes(f.world.facts)==frozen,"facts/rng unchanged")
			check(c.calls.body <= a.calls.body and c.calls.connection < a.calls.connection,"removed duplicate work")
			cases += 1
	var f: Dictionary = fixture(32,"vacant")
	var measurements: Array = []
	for round_number: int in 4:
		for kind: String in (["baseline","optimized"] if round_number%2==0 else ["optimized","baseline"]):
			var t: int = Time.get_ticks_usec()
			for i: int in 2000: execute(f,kind)
			measurements.append({"round":round_number,"kind":kind,"calls":2000,"elapsed_us":Time.get_ticks_usec()-t})
	print(JSON.stringify({"ok":not failed,"cases":cases,"sample_before":execute(f,"baseline").calls,"sample_after":execute(f,"optimized").calls,"benchmark_scope":"isolated capture with explicit input adapters; not full game","measurements":measurements}))
	quit(1 if failed else 0)
'''
(p/'run.gd').write_text(RUN_SCRIPT.replace('in 4:', f'in {args.rounds}:').replace('in 2000:', f'in {args.iterations}:').replace('"calls":2000', f'"calls":{args.iterations}'))
env = os.environ.copy()
env['XDG_DATA_HOME'] = str(p/'data')
env['XDG_CACHE_HOME'] = str(p/'cache')
command = [args.godot, '--headless', '--path', str(p), '--script', 'res://run.gd']
completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=180)
print(completed.stdout, end='')
print(completed.stderr, end='')
rows = [line for line in completed.stdout.splitlines() if line.startswith('{')]
result = json.loads(rows[-1]) if rows else {'ok':False}
result['exit_code'] = completed.returncode
result['baseline_commit'] = subprocess.check_output(['git','rev-parse',args.baseline],cwd=repo,text=True).strip()
result['source_sha256'] = hashlib.sha256((repo/'game/life/public_areas.gd').read_bytes()).hexdigest()
result['harness_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
result['engine_version'] = subprocess.check_output([args.godot,'--version'],env=env,text=True).strip()
result['command'] = command
result['stderr'] = completed.stderr
result['scope'] = 'isolated capture equivalence and microbenchmark; input adapters; not complete game'
if args.output:
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
raise SystemExit(0 if completed.returncode == 0 and result.get('ok') and 'SCRIPT ERROR:' not in completed.stderr and 'ERROR:' not in completed.stderr else 1)
