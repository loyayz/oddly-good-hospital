#!/usr/bin/env python3
"""Compare same-update actor projection reuse using extracted production GDScript.

Real projection, body dimensions, visibility bookkeeping and bounds algorithms
run unchanged. Input adapters replace world storage, content lookup, geometry
clearance, frustum decisions and resource creation. No GPU or full-game claim.
"""
import argparse, hashlib, json, os, re, subprocess, tempfile
from pathlib import Path
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--godot',default='godot')
ap.add_argument('--baseline',default='35d656dc58c4f7afac8419218a12051d3617c47b')
ap.add_argument('--output',type=Path,required=True)
a=ap.parse_args()
if a.output.exists(): ap.error('output exists')
repo=Path(__file__).resolve().parents[2]
rel='game/view/hospital_view.gd'
old=subprocess.check_output(['git','show',a.baseline+':'+rel],cwd=repo,text=True)
new=(repo/rel).read_text()
def function(s,n):
 m=re.search(r'^func '+re.escape(n)+r'\(.*?(?=^func |\Z)',s,re.M|re.S)
 if not m: raise ValueError(n)
 return m.group(0)
body=function((repo/'game/content/content_db.gd').read_text(),'actor_body')
adapter='''extends Node3D
class InputContent extends RefCounted:
	var body_calls: int = 0
	var definitions: Dictionary = {}
	func definition(kind: String, id: String) -> Dictionary:
		return definitions.get(kind,{}).get(id,{})
	func facility_definition(_id: String) -> Dictionary: return {}
BODY
class InputWorld extends RefCounted:
	var sim_tick: int = 10
	var facts: Dictionary = {"actors":{},"facilities":{},"connectors":{}}
	func ids(collection: String) -> Array:
		var result: Array = facts[collection].keys()
		result.sort()
		return result
class InputGeometry extends RefCounted:
	var content: RefCounted
	func clearance(actor: Dictionary) -> int:
		var dimensions: Dictionary = content.actor_body(actor)
		return ceili(maxf(float(dimensions.width_m),float(dimensions.depth_m))/1.5)
	func facility_layout(_world: RefCounted,_id: String) -> Dictionary: return {}
var world: InputWorld = InputWorld.new()
var content: InputContent = InputContent.new()
var _geometry: InputGeometry = InputGeometry.new()
var observed_floor: int = 1
var camera: Camera3D
var _entity_frustum: Array = []
var _actors: Dictionary = {}
var _actor_models: Dictionary = {}
var _actor_labels: Dictionary = {}
var _bindings: Dictionary = {}
var _facilities: Dictionary = {}
var work_budget: RefCounted
var hidden: bool = false
func _init() -> void:
	_geometry.content = content
func _in_view(_bounds: AABB) -> bool: return not hidden
func _remove_actor(id: String) -> void:
	_actors[id].free()
	_actors.erase(id)
	_actor_models.erase(id)
	_actor_labels.erase(id)
	_bindings.erase("actor:"+id)
func _remove_facility(_id: String) -> void: assert(false)
func _body_proxy(_dimensions: Dictionary) -> Node3D: return Node3D.new()
func _label(wrapper: Node3D, _text: String, _position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	wrapper.add_child(label)
	return label
func _bind_entity(key: String, signature: String, wrapper: Node3D, _path: String) -> void:
	_bindings[key] = {"signature":signature,"node":wrapper}
func _box(_size: Vector3,_color: Color) -> MeshInstance3D: return MeshInstance3D.new()
const Palette = {"FURNITURE":Color.WHITE}
'''
adapter=adapter.replace('BODY','\n'.join('\t'+l for l in body.strip().splitlines()))
# Count input-body invocations outside the production algorithm only.
adapter=adapter.replace('\tfunc actor_body(actor: Dictionary) -> Dictionary:\n','\tfunc actor_body(actor: Dictionary) -> Dictionary:\n\t\tbody_calls += 1\n')
runner='''extends SceneTree
const Baseline = preload("res://baseline.gd")
const Current = preload("res://current.gd")
func setup(view: Node3D, count: int) -> void:
	view.content.definitions = {"species":{"S":{"body":{"width_m":1.0,"height_m":2.0,"depth_m":1.2}}},"treatment_bindings":{"B":{"symptom_envelope":{"width_m":2.4,"height_m":3.0}}},"vertical_connectors":{"E":{"travel_seconds_per_floor":2.0,"boarding_seconds":1.0,"alighting_seconds":1.5,"clear_width_m":2.0}}}
	view.world.facts.connectors.e = {"definition_id":"E","phase":"riding","remaining_ticks":15,"from":1,"to":3,"anchor":[10,20],"cell":[10,20],"footprint":[2,3]}
	for i: int in count:
		var id: String = str(i)
		view.world.facts.actors[id] = {"id":id,"name":id,"species_id":"S","body_binding_id":"B" if i%3==0 else "","location":{"kind":"floor","floor_id":1,"cell":[i%64,20+i/64],"height_m":0.0}}
func sample(view: Node3D, changed: bool) -> Dictionary:
	var samples: Dictionary = {}
	if changed: samples = view._sync_entities()
	else: view._sync_entities()
	var positions: Dictionary = {}
	for id: String in view._actors:
		var p: Dictionary = samples[id] if changed else view._project_location(view.world.facts.actors[id])
		view._actors[id].visible = p.visible
		# Model the same arbitrary interpolated wrapper transform on both sides.
		view._actors[id].position = p.position+Vector3(0.123,0,-0.25)
		positions[id] = p
	var bounds: AABB = view._visible_body_bounds(samples) if changed else view._visible_body_bounds()
	return {"bounds":bounds,"positions":positions,"signatures":view._bindings.values().map(func(b: Dictionary)->String: return b.signature)}
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var scenarios: int = 0
	for count: int in [1,32,160,640]:
		var before = Baseline.new()
		var after = Current.new()
		setup(before,count)
		setup(after,count)
		for probe: String in ["base","cell","height","binding","transit_boarding","transit_riding","transit_alighting","other_floor","hidden","restore"]:
			for view in [before,after]:
				var actor: Dictionary = view.world.facts.actors["0"]
				match probe:
					"cell": actor.location.cell = [4,5]
					"height": actor.location.height_m = 1.3
					"binding": actor.body_binding_id = ""
					"transit_boarding", "transit_riding", "transit_alighting":
						actor.location = {"kind":"transit","connector_id":"e"}
						view.world.facts.connectors.e.phase = probe.trim_prefix("transit_")
					"other_floor": view.observed_floor = 4
					"hidden":
						view.observed_floor = 1
						view.hidden = true
					"restore": view.hidden = false
			var facts: Dictionary = before.world.facts.duplicate(true)
			var x: Dictionary = sample(before,false)
			var y: Dictionary = sample(after,true)
			for p: Dictionary in y.positions.values(): p.erase("dimensions")
			assert(x==y,probe)
			assert(before.world.facts==facts and after.world.facts==facts)
			scenarios += 1
		before.free()
		after.free()
	var before = Baseline.new()
	var after = Current.new()
	setup(before,160)
	setup(after,160)
	for repeat: int in 20:
		sample(before,false)
		sample(after,true)
	before.content.body_calls = 0
	after.content.body_calls = 0
	sample(before,false)
	sample(after,true)
	var calls: Array = [before.content.body_calls,after.content.body_calls]
	var windows: Array = []
	for label: String in ["A","B","B","A","A","B","B","A","A","B","B","A"]:
		var view = before if label=="A" else after
		var start: int = Time.get_ticks_usec()
		for repeat: int in 250: sample(view,label=="B")
		windows.append({"side":label,"iterations":250,"usec":Time.get_ticks_usec()-start})
	print("RESULT "+JSON.stringify({"scenarios":scenarios,"body_calls":calls,"windows":windows,"scope":"extracted synchronous actor projection pipeline, input adapters, headless; no GPU or full-game claim"}))
	before.free()
	after.free()
	quit()
'''
with tempfile.TemporaryDirectory(prefix='ogh-view-projection-') as tmp:
 p=Path(tmp)
 (p/'project.godot').write_text('[application]\nconfig/name="projection isolation"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
 for label,source in [('baseline',old),('current',new)]:
  code=adapter+'\n'+'\n'.join(function(source,n) for n in ['_sync_entities','_project_location','_visible_body_bounds','_cell_position'])
  (p/(label+'.gd')).write_text(code)
 (p/'run.gd').write_text(runner)
 env=dict(os.environ,XDG_DATA_HOME=str(p/'data'),XDG_CONFIG_HOME=str(p/'config'),XDG_CACHE_HOME=str(p/'cache'))
 r=subprocess.run([a.godot,'--headless','--path',str(p),'--script','res://run.gd'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 print(r.stdout)
 if r.returncode or 'SCRIPT ERROR' in r.stdout or 'ERROR:' in r.stdout: raise SystemExit('isolated run failed')
 line=next((l for l in r.stdout.splitlines() if l.startswith('RESULT ')),None)
 if line is None: raise SystemExit('missing result')
 result=json.loads(line[7:]); result.update({'baseline':a.baseline,'source_sha256':hashlib.sha256(new.encode()).hexdigest(),'baseline_sha256':hashlib.sha256(old.encode()).hexdigest(),'harness_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'engine':subprocess.check_output([a.godot,'--version'],env=env,text=True).strip()})
 a.output.write_text(json.dumps(result,indent=2)+'\n')
