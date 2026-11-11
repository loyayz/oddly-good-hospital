extends RefCounted

const Structure = preload("res://game/building/room_structure.gd")

# Complete pre-view enumeration. Only the unused batch argument is new; this
# reference keeps the original entry, object, stop, region and error ordering.
class FullChecks extends BuildService:
	func _wall_crossing(world: WorldState, floor_id: int, edge: Dictionary, _view: Dictionary) -> String:
		if floor_id==1:
			var entry: Array=world.facts.entry.cell
			var protected_entry: Rect2=Rect2(float(entry[0]),float(entry[1]),3,3)
			if _edge_crosses(edge,protected_entry) or edge.axis=="x" and int(edge.line)==int(entry[1])+3 and int(edge.low)<int(entry[0])+3 and int(edge.high)>int(entry[0]): return "医院入口缓冲区和通向外界的边界不能阻断"
		for collection: String in ["facilities","connectors"]:
			for record: Dictionary in world.facts[collection].values():
				if collection=="connectors":
					if not HospitalTransit.has_stop(record,floor_id): continue
				elif int(record.floor_id)!=floor_id: continue
				var rect: Rect2=BuildGeometry.rectangle(record)
				if _edge_crosses(edge,rect): return "墙不能穿过实际设备或交通设施："+str(record.id)
		for reservation: Dictionary in world.facts.adaptations.values():
			if int(reservation.floor_id)!=floor_id: continue
			for region: Array in reservation.regions:
				if _edge_crosses(edge,Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))): return "墙不能穿过正在使用或安全交接的真实预约"
		return ""

class ViewProbe extends BuildService:
	var crossing_calls: int=0
	var view_builds: int=0
	var enumerated_records: int=0
	var object_rectangles: int=0
	var reservation_rectangles: int=0
	func _wall_crossing(world: WorldState, floor_id: int, edge: Dictionary, view: Dictionary) -> String:
		crossing_calls+=1
		return super._wall_crossing(world,floor_id,edge,view)
	func _wall_crossing_view(world: WorldState, floor_id: int) -> Dictionary:
		view_builds+=1
		# The helper completes one enumeration of each of these collections.
		enumerated_records+=world.facts.facilities.size()+world.facts.connectors.size()+world.facts.adaptations.size()
		var view: Dictionary=super._wall_crossing_view(world,floor_id)
		object_rectangles+=view.objects.size()
		reservation_rectangles+=view.reservations.size()
		return view

func _actor(world: WorldState, id: String, species_id: String, cell: Array) -> void:
	world.facts.actors[id]={"id":id,"name":id,"species_id":species_id,"location":{"kind":"floor","floor_id":1,"cell":cell},"facing":0.0,"posture":"standing"}
	world.touch()

func run_case(content: HospitalContent) -> Dictionary:
	var world: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"墙边局部视图",false,content)
	# Completed-floor input; the real connector owner buys and extends the lift.
	world.facts.floors.height_intervals=[{"first":1,"last":3,"height_m":float(content.balance.floors.clear_height_m)}]
	world.facts.floors.completed_top_floor={HospitalSpace.plot_key([1,2]):3}
	for floor_id: int in [2,3]: world.facts.floors.overrides[str(floor_id)]={"plots":[[1,2]],"blocked":[],"wall_edges":[],"doors":[],"paths":[]}
	world.touch()
	var actual: ViewProbe=ViewProbe.new(content)
	var original: FullChecks=FullChecks.new(content)
	var connector: HospitalConnectors=HospitalConnectors.new(content,actual.space)
	var bought: CommandResult=connector.execute(world,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[50,70]})
	var checks: Dictionary={"connector_bought":bought.accepted}
	if not bought.accepted: return {"checks":checks,"setup":bought.to_record()}
	var connector_id: String=str(bought.changed_ids[0])
	for floor_id: int in [2,3]: checks["extended_"+str(floor_id)]=connector.execute(world,"connector_extend",{"connection_id":connector_id,"floor_id":floor_id}).accepted
	var seat: CommandResult=actual.execute(world,"build_facility",{"id":"wall_seat","definition_id":"FUR06","floor_id":1,"cell":[44,80]})
	checks.seat_bought=seat.accepted
	_actor(world,"wall_user","S53",[35,86])
	_actor(world,"wall_operator","S01",[39,86])
	var reserved: String=actual.space.reserve_facility(world,"wall_seat","wall_user","wall_user",["wall_operator"]) if seat.accepted else "缺少设施"
	checks.real_reservation=reserved.is_empty() and world.facts.adaptations.has("wall_seat")
	var validation: String=world.validate(content)
	checks.legal_input=validation.is_empty()
	if not checks.real_reservation or not checks.legal_input: return {"checks":checks,"validation":validation,"reservation_error":reserved}
	var before: Dictionary=world.freeze()
	var difference: Dictionary={}
	var reservation_rejections: int=0
	var tested_edges: int=0
	for floor_id: int in [1,2,3]:
		var view: Dictionary={}
		for axis: String in ["x","y"]:
			var line_start: int=64 if axis=="x" else 32
			var along_start: int=32 if axis=="x" else 64
			for line: int in range(line_start,line_start+33):
				for along: int in range(along_start,along_start+32):
					var edge: Dictionary={"axis":axis,"line":line,"low":along,"high":along+1}
					var observed: String=actual._wall_crossing(world,floor_id,edge,view)
					var expected: String=original._wall_crossing(world,floor_id,edge,{})
					tested_edges+=1
					if observed!=expected and difference.is_empty(): difference={"floor_id":floor_id,"edge":edge,"actual":observed,"expected":expected}
					if observed=="墙不能穿过正在使用或安全交接的真实预约": reservation_rejections+=1
	checks.complete_owned_plot_first_errors=difference.is_empty()
	checks.reservation_only_edges_covered=reservation_rejections>0
	checks.queries_readonly=world.freeze()==before
	checks.facility_precedes_its_reservation=actual._wall_crossing(world,1,{"axis":"y","line":45,"low":80,"high":81},{})=="墙不能穿过实际设备或交通设施：wall_seat"
	checks.entry_precedes_other_claims=actual._wall_crossing(world,1,{"axis":"x","line":94,"low":47,"high":50},{})=="医院入口缓冲区和通向外界的边界不能阻断"
	for floor_id: int in [1,2,3]: checks["connector_stop_"+str(floor_id)]=actual._wall_crossing(world,floor_id,{"axis":"x","line":72,"low":50,"high":54},{})=="墙不能穿过实际设备或交通设施："+connector_id
	var rect: Rect2=Rect2(44,80,2,1)
	checks.strict_geometry_boundaries=not actual._edge_crosses({"axis":"y","line":44,"low":80,"high":81},rect) and not actual._edge_crosses({"axis":"y","line":46,"low":80,"high":81},rect) and not actual._edge_crosses({"axis":"y","line":45,"low":79,"high":80},rect) and not actual._edge_crosses({"axis":"y","line":45,"low":81,"high":82},rect) and actual._edge_crosses({"axis":"y","line":45,"low":80,"high":81},rect)
	var request: Dictionary={"kind":"build_wall","floor_id":2,"edges":[{"axis":"x","line":80,"low":50,"high":54}]}
	actual.crossing_calls=0
	actual.view_builds=0
	var quote: Dictionary=actual.preview(world,request)
	var reference_quote: Dictionary=original.preview(world,request)
	checks.one_complete_view_for_four_edges=quote.get("ok",false) and quote==reference_quote and actual.crossing_calls==4 and actual.view_builds==1 and before==world.freeze()
	var built: CommandResult=actual.execute(world,"build_wall",request)
	checks.wall_applied=built.accepted
	actual.view_builds=0
	actual.crossing_calls=0
	var repeated: Dictionary=actual.preview(world,request)
	checks.existing_wall_needs_no_view=repeated.get("ok",false) and int(repeated.price)==0 and actual.view_builds==0 and actual.crossing_calls==0
	var removal: Dictionary=request.duplicate(true)
	removal.kind="build_remove_wall"
	var removed: Dictionary=actual.preview(world,removal)
	checks.removal_needs_no_view=removed.get("ok",false) and actual.view_builds==0 and actual.crossing_calls==0
	var collision: Dictionary={"floor_id":3,"edges":[{"axis":"x","line":72,"low":50,"high":54}]}
	before=world.freeze()
	var rejected: CommandResult=actual.execute(world,"build_wall",collision)
	checks.failed_batch_atomic=not rejected.accepted and rejected.reason=="墙不能穿过实际设备或交通设施："+connector_id and before==world.freeze()
	# A fresh synchronous request must observe newly placed facts immediately.
	var fresh: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"墙边新请求",false,content)
	var builder: ViewProbe=ViewProbe.new(content)
	var later: Dictionary={"kind":"build_wall","floor_id":1,"edges":[{"axis":"y","line":41,"low":84,"high":85}]}
	var clear: Dictionary=builder.preview(fresh,later)
	var placed: CommandResult=builder.execute(fresh,"build_facility",{"id":"later_seat","definition_id":"FUR06","floor_id":1,"cell":[40,84]})
	var blocked: Dictionary=builder.preview(fresh,later)
	checks.next_request_reads_new_objects=clear.get("ok",false) and placed.accepted and not blocked.get("ok",true) and blocked.reason=="墙不能穿过实际设备或交通设施：later_seat"
	return {"checks":checks,"validation":validation,"tested_edges":tested_edges,"reservation_only_rejections":reservation_rejections,"first_difference":difference}

func measure(content: HospitalContent, facts: Dictionary, floor_id: int, width: int, height: int, repeats: int=3) -> Dictionary:
	var request: Dictionary={"floor_id":floor_id,"edges":BuildGeometry.room_walls({"origin":[0,0],"size":[width,height]})}
	var rows: Array=[]
	var equal: bool=true
	for repeat: int in repeats:
		var outputs: Dictionary={}
		for variant: String in (["full","view"] if repeat%2==0 else ["view","full"]):
			# Identical complete input. Copying, construction, equality checks and
			# evidence serialization stay outside the measured operation.
			var world: WorldState=WorldState.new(facts.duplicate(true))
			var builder: BuildService=FullChecks.new(content) if variant=="full" else BuildService.new(content)
			var started: int=Time.get_ticks_usec()
			var result: Dictionary=builder._change_walls(world,request,false)
			var elapsed: int=Time.get_ticks_usec()-started
			outputs[variant]={"result":result,"facts":world.freeze()}
			rows.append({"repeat":repeat+1,"variant":variant,"elapsed_usec":elapsed,"accepted":result.ok,"reason":result.get("reason",""),"wall_price":result.get("price",-1),"actors":world.present_actor_count(),"facilities":world.facts.facilities.size()})
		equal=equal and outputs.full==outputs.view
	# Work evidence is a separate untimed pass; the timer above has no counters.
	var counted: ViewProbe=ViewProbe.new(content)
	var world: WorldState=WorldState.new(facts.duplicate(true))
	var result: Dictionary=counted._change_walls(world,request,false)
	var records: int=facts.facilities.size()+facts.connectors.size()+facts.adaptations.size()
	return {"ok":equal,"identical_results_and_complete_candidate_facts":equal,"floor_id":floor_id,"width":width,"height":height,"samples":rows,"work":{"successful_batch":result.ok,"crossing_calls":counted.crossing_calls,"view_builds":counted.view_builds,"view_enumerated_records":counted.enumerated_records,"full_enumerated_records":counted.crossing_calls*records if result.ok else -1,"view_object_rectangles":counted.object_rectangles,"view_reservation_rectangles":counted.reservation_rectangles,"full_rectangles":counted.crossing_calls*(counted.object_rectangles+counted.reservation_rectangles) if result.ok else -1},"scope":"Synchronous wall planning on complete unchanged hospital input; includes original request/seed/layout work, excludes cloning and observation. This is not a simulation-step or displayed-frame result."}
