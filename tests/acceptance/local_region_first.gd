extends "res://tests/acceptance/staff_fixtures.gd"
# Selection-policy unit adapters only. Travel/arrival is not simulated here;
# real full-world evidence is recorded separately by the 160-person screen.
class Probe extends HospitalPublicAreas:
	var areas: Array=[]
	var costs: Dictionary={}
	var waits: Dictionary={}
	func _ensure(_world: WorldState, _floor: int=0) -> void: pass
	func _candidate_regions(_definitions: Array) -> Array: return areas
	func facilities(_world: WorldState, _reference: Dictionary, _definitions: Array) -> Array: return ["toilet"]
	func contains(world: WorldState, reference: Dictionary, actor_id: String) -> bool: return int(world.facts.actors[actor_id].location.floor_id)==int(reference.floor_id)
	func _wait_estimate(_world: WorldState, reference: Dictionary, _facilities: Array, _purpose: String) -> int: return int(waits.get(reference.id,0))
	func waiting_point(_world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int=9223372036854775807) -> Dictionary:
		var cost: int=int(costs[actor_id][reference.id])
		if cost<0 or cost>maximum_travel_ticks: return {}
		return {"floor_id":reference.floor_id,"cell":[1,1],"travel_ticks":cost}
class Original extends Probe:
	func select(world: WorldState, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, members: Array = [], maximum_travel_ticks: int = 9223372036854775807, selected_entries: Dictionary = {}, current_floor_only: bool = false) -> Dictionary:
		# Furniture-free standing areas remain valid for rest/return-to-waiting.
		# Other purposes cannot select a region without a requested definition.
		if not purpose in ["rest","waiting"]:
			var present: bool = false
			for facility: Dictionary in world.facts.facilities.values():
				if facility.definition_id in definitions: present = true; break
			if not present: return {}
		_ensure(world)
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor.location.kind!="floor": return {}
		var best: Dictionary = {}
		var best_entries: Dictionary = {}
		var travellers: Array = [actor_id] if members.is_empty() else members
		var body_key: String = ""
		# Rest and return-to-waiting also permit a safe standing region without furniture.
		var candidates: Array = _regions if purpose in ["rest","waiting"] else _candidate_regions(definitions)
		space.query_counts["public_select_regions_total"] = int(space.query_counts.get("public_select_regions_total",0))+_regions.size()
		space.query_counts["public_select_regions_visited"] = int(space.query_counts.get("public_select_regions_visited",0))+candidates.size()
		# The caller may already own this unchanged, real-body enumeration. Its
		# actor index is reusable; this child still gets independent query views.
		space.begin_dynamic_route_query(world,not space.in_dynamic_route_query(world))
		for area: Dictionary in candidates:
			if current_floor_only and int(area.ref.floor_id)!=int(actor.location.floor_id): continue
			var room: Dictionary = world.facts.rooms.get(area.ref.room_id,{})
			if not room.is_empty() and (not str(room.get("kind",room.get("type",""))) in room_kinds or HospitalRemodel.blocked(world,area.ref.room_id)): continue
			if room.is_empty() and not "" in room_kinds: continue
			var local: Array = facilities(world,area.ref,definitions)
			if not local.is_empty() and body_key.is_empty(): body_key = _body_key(world,travellers)
			local = local.filter(func(id: String)->bool:
				if _geometry_fits.get(id,{}).get(body_key,true)==false: return false
				if maximum_travel_ticks<9223372036854775807 and space.facility_travel_lower_bound_ticks(world,id,actor_id)>maximum_travel_ticks: return false
				var definition: Dictionary = space.content.facility_definition(world.facts.facilities[id].definition_id)
				var capacity: Dictionary = definition.get("adapter_capacity",definition)
				for member: String in travellers:
					var body: Dictionary = world.facts.actors[member]
					if space.clearance(body)>int(capacity.get("max_clearance_cells",96)) or float(space.body(body).height_m)>float(capacity.get("max_height_m",INF)): return false
				return true)
			if local.is_empty() and not purpose in ["rest","waiting"]: continue
			var inside: bool = contains(world,area.ref,actor_id)
			var waiting: int = _wait_estimate(world,area.ref,local,purpose)
			var travel_limit: int = maximum_travel_ticks
			if not best.is_empty():
				if purpose in ["water","toilet"]:
					if waiting>int(best.start_ticks): continue
					travel_limit = mini(travel_limit,int(best.start_ticks)-waiting)
				else:
					if best.inside and not inside: continue
					if inside==bool(best.inside): travel_limit = mini(travel_limit,int(best.travel_ticks))
			# Equal bounds remain candidates: the original stable area tie-break
			# and the slowest member's actual journey still decide the winner.
			var point: Dictionary = waiting_point(world,actor_id,area.ref,travel_limit)
			if point.is_empty(): continue
			var entries: Dictionary = {actor_id:point.duplicate(true)}
			var all_reachable: bool = true
			for member: String in travellers:
				if member==actor_id: continue
				var entry: Dictionary = waiting_point(world,member,area.ref,travel_limit)
				if entry.is_empty(): all_reachable = false; break
				entries[member] = entry
				point.travel_ticks = maxi(int(point.travel_ticks),int(entry.travel_ticks))
			if not all_reachable: continue
			point.area = area.ref.duplicate(true)
			point.inside = inside
			point.start_ticks = int(point.travel_ticks)+waiting
			if best.is_empty() or _earlier(point,best,purpose):
				best = point
				best_entries = entries
		space.end_route_query()
		selected_entries.merge(best_entries,true)
		return best

func run_focused(content: HospitalContent) -> Dictionary:
	_content=content
	var x: Dictionary=_fixture()
	_facility(x,"toilet","FUR07",[39,68],"")
	var v1: Dictionary=_visit(x,"probe_one",[34,82])
	var v2: Dictionary=_visit(x,"probe_two",[42,82])
	var actor: String=str(v1.actor_id)
	var follower: String=str(v2.actor_id)
	var original:=Original.new(x.space)
	var actual:=Probe.new(x.space)
	var cases: Array=[]
	var scenarios: Array=[
		{"name":"cross_floor_shorter_queue_wins","head":{"a":8,"z":1},"tail":{"a":8,"z":1},"waits":{"a":0,"z":100},"group":false,"limit":999,"winner":"a"},
		{"name":"slow_follower_changes_winner","head":{"a":8,"z":1},"tail":{"a":8,"z":20},"waits":{},"group":true,"limit":999,"winner":"a"},
		{"name":"stable_key_tie_still_wins","swap_floors":true,"head":{"a":8,"z":8},"tail":{"a":8,"z":8},"waits":{},"group":false,"limit":999,"winner":"a"},
		{"name":"local_unreachable","head":{"a":8,"z":-1},"tail":{"a":8,"z":-1},"waits":{},"group":false,"limit":999,"winner":"a"},
		{"name":"budget_rejects_both","head":{"a":8,"z":9},"tail":{"a":8,"z":9},"waits":{},"group":false,"limit":7,"winner":""}]
	for scenario: Dictionary in scenarios:
		var swap: bool=bool(scenario.get("swap_floors",false))
		x.world.facts.actors[actor].location.floor_id=2 if swap else 1
		x.world.facts.actors[follower].location.floor_id=2 if swap else 1
		for p: Probe in [actual,original]:
			p.areas=[{"ref":{"id":"a","floor_id":1 if swap else 2,"room_id":""}},{"ref":{"id":"z","floor_id":2 if swap else 1,"room_id":""}}]
			p.costs={actor:scenario.head,follower:scenario.tail};p.waits=scenario.waits
		var members: Array=[actor,follower] if scenario.group else []
		var entries: Dictionary={};var reference: Dictionary={}
		var before: Dictionary=x.world.freeze()
		var a: Dictionary=actual.select(x.world,actor,["FUR07"],[""],"toilet",members,int(scenario.limit),entries)
		var b: Dictionary=original.select(x.world,actor,["FUR07"],[""],"toilet",members,int(scenario.limit),reference)
		var winner: String=str(a.get("area",{}).get("id",""))
		cases.append({"name":scenario.name,"passed":a==b and entries==reference and winner==scenario.winner and before==x.world.freeze() and x.space._route_queries.is_empty(),"winner":winner,"entries":entries})
	x.a.dispose();x.p.waiting_life=null;x.p.environment=null;x.l.environment=null;x.l.visitors=null;x.e.waiting_life=null;x.c.recruitment=null
	return {"passed":cases.all(func(row: Dictionary)->bool:return row.passed),"cases":cases,"scope":"Policy-only exact-cost adapter tests; not cross-floor movement acceptance."}
