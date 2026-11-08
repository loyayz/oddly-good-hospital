extends RefCounted
class Probe extends HospitalMovement:
	var trials: Array = []
	var records: Array = []
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		for point: Dictionary in path:
			var known: bool=false
			for old: Dictionary in records: known=known or is_same(point,old)
			if not known: records.append(point)
		var before: Array = path.duplicate(true)
		var clear: bool = super._detour_path_clear(world,actor,movement,path,query,proof)
		trials.append({"path":before,"clear":clear,"unchanged":before==path})
		return clear

# Exact published pre-buffer owner. Geometry and all proof logic are shared.
class FreshPaths extends Probe:
	func _detour_return_path(world: WorldState, actor: Dictionary, movement: Dictionary, origin: Vector2, prefix: Array = []) -> Dictionary:
		# Candidate links read one unchanged actor, geometry, reservations and
		# accepted sweeps. Exact single-body proofs live only in this synchronous
		# search; the next attempt rebuilds. Convoys retain their full trail proof.
		var proof: Dictionary = {"sweeps":{},"segments":{},"_capture_entry":true,"_return_sample":actor.duplicate(true),"_cache_contacts":true} if not movement.has("convoy") else {}
		var query: RouteClearance = null
		for index: int in movement.detour.original_path.size():
			var segment: Dictionary = movement.detour.original_path[index]
			if segment.kind!="floor" or int(segment.floor_id)!=int(actor.location.floor_id): break
			if query==null:
				var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
				query = space.navigation.structural_clearance(world,proxy,int(actor.location.floor_id))
			var target: Vector2 = ConvoyTrail.point(segment.cell)
			# Try the original blocked cell first, then its original successors.
			# Check fixed orthogonal local links, never a global route.
			var links: Array = [[Vector2(target.x,origin.y),target],[Vector2(origin.x,target.y),target]]
			# Four fixed outside links handle a nearby corner/passing pocket.
			# A queue's margin also clears its own tail before returning.
			var margin: float = float(movement.convoy.spacing) if movement.has("convoy") else float(space.clearance(actor))
			var outside_x: Array = [maxf(origin.x,target.x)+margin,minf(origin.x,target.x)-margin]
			var outside_y: Array = [maxf(origin.y,target.y)+margin,minf(origin.y,target.y)-margin]
			for x: float in outside_x: links.append([Vector2(x,origin.y),Vector2(x,target.y),target])
			for y: float in outside_y: links.append([Vector2(origin.x,y),Vector2(target.x,y),target])
			# A pocket beside furniture may need one outside bend on each axis
			# to reach the side of a doorway. Try these fixed links for this
			# original cell before considering a farther one; never redispatch.
			for x: float in outside_x:
				for y: float in outside_y:
					links.append([Vector2(x,origin.y),Vector2(x,y),Vector2(target.x,y),target])
					links.append([Vector2(origin.x,y),Vector2(x,y),Vector2(x,target.y),target])
			for link: Array in links:
				if _detour_first_segment_failed(world,actor,origin,prefix,link,segment,proof): continue
				var path: Array = prefix.duplicate(true)
				var previous: Vector2 = origin
				for point: Vector2 in link:
					if previous.distance_to(point)>0.001: path.append(_floor_point(actor,point))
					previous = point
				if path.is_empty(): path.append(segment.duplicate(true))
				if _detour_path_clear(world,actor,movement,path,query,proof): return {"path":path,"index":index}
		return {}

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new();suite.content=content
	var fixture: RefCounted = load("res://tests/acceptance/detour_step_proof.gd").new()
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70]);suite._add_actor(sim,"blocker","S49",[36,70])
	var probe: Probe = Probe.new(sim.space)
	var reference: FreshPaths = FreshPaths.new(sim.space)
	var rows: Array = []
	var retained: Array = []
	var allocation_reduced: bool=false
	var metadata_seen: bool=false
	var fallback_seen: bool=false
	var mutation_checked: bool=false
	for cells: Array in [[[36,70],[37,70]],[[35,70]],[[36,70]],[[35.0008,70.0008]]]:
		for prefix: Array in [[],[{"kind":"floor","floor_id":1,"cell":[35.0,71.0],"meta":{"chain":[{"label":"prefix"}]}}]]:
			for facing: float in [0.0,PI*0.5]:
				sim.world.facts.actors.walker.facing=facing;sim.world.touch()
				var request: Dictionary=fixture._movement("walker",cells)
				request.detour.original_path[0].meta={"chain":[{"label":"fallback"}]}
				var link_origin: Vector2=Vector2(35.0004,70.0004) if cells[0][0]==35.0008 else Vector2(35,70)
				var before: Dictionary=sim.world.freeze();var old_prefix: Array=prefix.duplicate(true);var old_request: Dictionary=request.duplicate(true)
				probe.trials.clear();reference.trials.clear();probe.records.clear();reference.records.clear()
				var a: Dictionary=probe._detour_return_path(sim.world,sim.world.facts.actors.walker,request,link_origin,prefix)
				var b: Dictionary=reference._detour_return_path(sim.world,sim.world.facts.actors.walker,request,link_origin,prefix)
				var unchanged: bool=true
				for saved: Dictionary in retained: unchanged=unchanged and saved.result==saved.copy
				rows.append({"same_result":a==b,"same_ordered_trials":probe.trials==reference.trials,"caller_unchanged":before==sim.world.freeze() and prefix==old_prefix and request==old_request,"prior_result_unchanged":unchanged,"record_allocation_not_greater":probe.records.size()<=reference.records.size()})
				if not a.is_empty():
					if a.path[0].has("meta"):
						metadata_seen=metadata_seen or a.path[0].meta.chain[0].label=="prefix"
						fallback_seen=fallback_seen or a.path[0].meta.chain[0].label=="fallback"
						a.path[0].meta.chain[0].label="result-only"
					a.path[0].cell[0]+=10.0
					mutation_checked=true
					rows.back().result_mutation_isolated=prefix==old_prefix and request==old_request and before==sim.world.freeze()
				allocation_reduced=allocation_reduced or probe.records.size()<reference.records.size()
				retained.append({"result":a,"copy":a.duplicate(true)})
	var ok: bool=allocation_reduced and metadata_seen and fallback_seen and mutation_checked
	for row: Dictionary in rows:
		for value: bool in row.values():ok=ok and value
	sim.dispose();return {"passed":ok,"rows":rows,"allocation_reduced":allocation_reduced,"metadata_seen":metadata_seen,"fallback_seen":fallback_seen,"mutation_checked":mutation_checked,"scope":"Exact owner oracle; candidate history/order, caller isolation, escaped path lifetime. Actual workload separate."}
