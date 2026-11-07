extends "res://tests/acceptance/floor_guidance.gd"

# Named immutable predecessors are supplied by the runner. Each case restores
# independently. Aging is declared input history, never elapsed simulation.
func run_deadline_cases(database: HospitalContent, fixtures: String, output: String) -> Dictionary:
	_content = database
	var rows: Array = []
	for kind: String in ["outside","inside"]:
		for age: int in [449,450,451]:
			rows.append(_boundary(fixtures,output,kind,age))
	for kind: String in ["fractional_edge","fractional_inside","inside_not_ready","invalid_area","unavailable"]:
		rows.append(_boundary(fixtures,output,kind,450))
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows,"tick_seconds":WorldState.TICK_SECONDS,"scope":"Supplied seek-age boundaries; actual physical motion only where recorded. No 450-tick seek-duration claim."}

func _deadline_restore(path: String) -> Dictionary:
	return _guide_bind(WorldState.new(FileAccess.open(path,FileAccess.READ).get_var(true)))

func _boundary(fixtures: String, output: String, kind: String, age: int) -> Dictionary:
	var source: String = "inside" if kind in ["inside","invalid_area","unavailable"] else "outside"
	var x: Dictionary = _deadline_restore(fixtures+"-"+source+"-predecessor.bin")
	var v: Dictionary = x.world.facts.visits.life_patient
	var n: Dictionary = x.world.facts.waiting_life.needs[v.id]
	var actor: Dictionary = x.world.facts.actors[v.actor_id]
	var steps: int = 0
	var found: bool = not kind.begins_with("fractional") and kind!="inside_not_ready"
	# Advance the real initial facility route, stopping on an observed boundary.
	# No actor location, route cursor, or service work is edited.
	if not found:
		for i: int in 150:
			x.space.advance(x.world)
			x.world.facts.sim_tick += 1
			x.world.touch(false)
			steps += 1
			var contained: bool = x.space.public_areas.contains(x.world,n.area,v.actor_id)
			var current: bool = x.space.public_areas.current_area(x.world,v.actor_id)==n.area
			var fractional: bool = absf(float(actor.location.cell[0])-roundf(actor.location.cell[0]))>0.001 or absf(float(actor.location.cell[1])-roundf(actor.location.cell[1]))>0.001
			if (kind=="fractional_edge" and current and not contained and fractional) or (kind=="fractional_inside" and contained and fractional) or (kind=="inside_not_ready" and contained and not x.world.facts.moves.has(v.actor_id)):
				found=true;break
	if kind=="invalid_area": n.area={}
	if kind=="unavailable": x.world.facts.facilities.life_toilet.failed=true
	var predecessor_tick: int = x.world.sim_tick
	var stem: String = output+"-"+kind+"-"+str(age)
	FileAccess.open(stem+"-predecessor.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	x.world.facts.sim_tick = int(n.started_tick)+age
	x.world.touch(false)
	var before: Dictionary = x.world.freeze()
	var input_validation: String = x.world.validate(_content)
	var contains: bool = x.space.public_areas.contains(x.world,n.area,v.actor_id)
	var current_area: Dictionary = x.space.public_areas.current_area(x.world,v.actor_id)
	var initial_cell: Array = actor.location.cell.duplicate()
	var initial_request: int = int(x.world.facts.get("move_request_next",0))
	FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(before,true)
	x.l._dispatch_need(x.world,v,n)
	var expected_use: bool = kind=="inside" and age<=450
	var expected_seek: bool = kind=="outside" and age==449
	var fallback: bool = n.phase in ["fallback","fallback_travel"]
	var checks: Dictionary = {"boundary_found":found,"input_valid":input_validation.is_empty(),"output_valid":x.world.validate(_content).is_empty(),"body_unchanged":actor.location.cell==initial_cell,"tick_unchanged":x.world.sim_tick==before.sim_tick,"expected_outcome":(n.phase=="using" and n.remaining_ticks==80) if expected_use else ((n.phase=="area_travel") if expected_seek else fallback)}
	if kind=="outside" and age>=450: checks.no_renewed_request=int(x.world.facts.get("move_request_next",0))==initial_request and not x.world.facts.moves.has(v.actor_id)
	if kind=="fractional_edge": checks.rounded_region_not_full_body=current_area==n.area and not contains
	if kind in ["fractional_inside","inside_not_ready"]: checks.inside_without_use=contains and not expected_use
	FileAccess.open(stem+"-after.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	var row: Dictionary = {"case":kind+"_"+str(age),"ok":checks.values().all(func(z:Variant)->bool:return bool(z)),"checks":checks,"input_validation":input_validation,"output_validation":x.world.validate(_content),"actual_motion_steps":steps,"predecessor_tick":predecessor_tick,"declared_input_age":age,"input_tick":before.sim_tick,"initial_cell":initial_cell,"contains":contains,"current_area":current_area,"need":n.duplicate(true),"movement":x.world.facts.moves.get(v.actor_id,{}).duplicate(true)}
	_dispose(x)
	return row
