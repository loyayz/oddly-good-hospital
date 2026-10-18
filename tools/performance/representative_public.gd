extends RefCounted

# Observations run outside the complete-step timer and never edit facts.
var starts: Dictionary = {}
var completions: Dictionary = {}
var fallbacks: Dictionary = {}
var queued_actors: Dictionary = {}
var last_owner: Dictionary = {}
var previous: Dictionary = {}
var trace: Array = []
var errors: Array = []
var queue_peak: int = 0
var use_ticks: int = 0
var handoffs: int = 0
var initial_queries: Dictionary = {}
var area_arrivals: Dictionary = {}
var queue_ticks: int = 0
var seated_users: Dictionary = {}

func _init(space: HospitalSpace) -> void:
	initial_queries = space.query_counts.duplicate()

func observe(world: WorldState, space: HospitalSpace) -> void:
	var current: Dictionary = {}
	var queued: int = 0
	for need: Dictionary in world.facts.waiting_life.needs.values():
		var actor_id: String = str(world.facts.visits[need.visit_id].actor_id)
		current[need.id] = need.duplicate(true)
		var prior: Dictionary = previous.get(need.id,{})
		if int(need.get("arrived_tick",-1))>=0 and not area_arrivals.has(need.id): area_arrivals[need.id] = {"tick":int(need.arrived_tick),"actor_id":actor_id,"area":need.get("area",{})}
		if need.phase in ["local_wait","manual_wait"] and int(need.get("arrived_tick",-1))>=0:
			queued += 1
			queued_actors[actor_id] = true
			queue_ticks += 1
		if need.phase=="using":
			if not starts.has(need.id):
				starts[need.id] = {"tick":world.sim_tick,"actor_id":actor_id,"facility_id":need.facility_id,"area":need.get("area",{}).duplicate(true)}
				if last_owner.has(need.facility_id) and last_owner[need.facility_id].actor_id!=actor_id:
					if not _previous_body_clear(world,space,last_owner[need.facility_id]): errors.append("New public use began before the previous body left: "+need.facility_id)
					else: handoffs += 1
				var adapter: Dictionary = world.facts.adaptations.get(need.facility_id,{})
				last_owner[need.facility_id] = {"actor_id":actor_id,"floor_id":adapter.get("floor_id",-1),"regions":adapter.get("regions",[]).duplicate(true)}
				trace.append({"kind":"actual_use_start","id":need.id,"data":starts[need.id]})
				var total: int = 0
				for service: Dictionary in space.content.catalog.amenity_services:
					if service.purpose==need.purpose: total = ceili(float(service.ordinary_seconds)/WorldState.TICK_SECONDS)
				use_ticks += total-int(need.remaining_ticks)
			else: use_ticks += maxi(0,int(prior.get("remaining_ticks",need.remaining_ticks))-int(need.remaining_ticks))
			var layout: Dictionary = space.facility_layout(world,need.facility_id)
			if not space.at(world,actor_id,int(layout.floor_id),layout.patient_cell) or world.facts.moves.has(actor_id): errors.append("Public service ran without real arrival: "+need.id)
		if need.phase=="fallback" and not fallbacks.has(need.id):
			fallbacks[need.id] = world.sim_tick
			trace.append({"kind":"fallback_start","id":need.id,"tick":world.sim_tick})
		if need.phase=="returning" and prior.get("phase","")=="using":
			use_ticks += int(prior.remaining_ticks)
			completions[need.id] = world.sim_tick
			trace.append({"kind":"actual_use_complete","id":need.id,"tick":world.sim_tick})
	queue_peak = maxi(queue_peak,queued)
	for id: String in previous:
		if current.has(id) or previous[id].phase!="using": continue
		if int(previous[id].remaining_ticks)==1:
			use_ticks += 1
			completions[id] = world.sim_tick
			trace.append({"kind":"actual_use_complete","id":id,"tick":world.sim_tick})
		else: errors.append("Actual use disappeared before its final work tick: "+id)
	for actor: Dictionary in world.facts.actors.values():
		if actor.get("posture","")=="seated" and not str(actor.get("support_facility_id","")).is_empty(): seated_users[actor.id] = actor.support_facility_id
	previous = current

func _previous_body_clear(world: WorldState, space: HospitalSpace, prior: Dictionary) -> bool:
	var actor: Dictionary = world.facts.actors[prior.actor_id]
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(prior.floor_id): return true
	var body: Rect2 = space.body_rectangle(actor)
	for region: Array in prior.regions:
		if body.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),false): return false
	return true

func report(space: HospitalSpace) -> Dictionary:
	var queries: Dictionary = {}
	for key: String in space.query_counts: queries[key] = int(space.query_counts[key])-int(initial_queries.get(key,0))
	var regions: Array = []
	for use: Dictionary in starts.values():
		if not use.area.is_empty() and not use.area in regions: regions.append(use.area)
	return {"actual_use_starts":starts,"actual_use_completions":completions,"actual_use_ticks":use_ticks,"used_regions":regions,"fallback_starts":fallbacks,"actual_queued_actors":queued_actors.keys(),"queue_peak":queue_peak,"queue_actor_ticks":queue_ticks,"area_arrivals":area_arrivals,"actual_seated_users":seated_users,"actual_exit_then_reuse_count":handoffs,"query_counts":queries,"trace":trace,"errors":errors}
