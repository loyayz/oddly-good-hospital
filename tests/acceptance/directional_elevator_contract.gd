extends SceneTree
# Requirement-derived physical integration tests. Historical structure is legal
# input; queue arrival, boarding, each floor segment and alighting run for real.
const Cases = preload("res://tests/acceptance/space.gd")
var suite = Cases.new()
func _initialize()->void:call_deferred("run")
func fixture()->HospitalSimulation:
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,4)
 suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
 for floor:int in [2,3,4]:suite._command(s,"connector_extend",{"connection_id":suite._connection(s),"floor_id":floor})
 return s
func tokens(w:WorldState)->bool:
 for c:Dictionary in w.facts.connectors.values():
  for key:String in ["ticket_next","assigned_actor_id","trip_sequence"]:
   if c.has(key):return true
 for m:Dictionary in w.facts.moves.values():
  if m.has("transit_ticket") or m.has("transit_wait"):return true
 return false
func idle()->Dictionary:
 var s:=fixture();var c:Dictionary=s.world.facts.connectors[suite._connection(s)];c.floor_id=2
 var errors:Array=[]
 for i:int in 50:
  suite._movement_tick(s)
  if int(c.floor_id)!=2 or not c.riders.is_empty():errors.append("No-demand lift moved")
 var v:String=s.world.validate(suite.content)
 if not v.is_empty():errors.append(v)
 var r:Dictionary={"case":"no_demand_stays","ok":errors.is_empty() and not tokens(s.world),"errors":errors};s.dispose();return r
func journey(name:String, inputs:Array, initial_floor:int, targets:Dictionary, max_steps:int=2400)->Dictionary:
 var s:=fixture();var c:Dictionary=s.world.facts.connectors[suite._connection(s)];c.floor_id=initial_floor
 var errors:Array=[];var events:Array=[];var last:Dictionary={};var boarded:Dictionary={};var landed:Dictionary={};var max_riders:int=0;var actual_arrivals:Dictionary={}
 for input:Dictionary in inputs:
  input.destination_cell=[45+2*inputs.find(input),82]
  suite._add_actor(s,input.id,"S49",input.cell,input.floor)
  var reason:String=s.space.request_move(s.world,input.id,int(targets[input.id]),input.destination_cell)
  if not reason.is_empty():errors.append({"request":input.id,"reason":reason})
 var initial_validation:String=s.world.validate(suite.content)
 if not initial_validation.is_empty():errors.append({"input":initial_validation})
 var complete:bool=false;var steps:int=0
 for i:int in max_steps:
  suite._movement_tick(s);steps=i+1;max_riders=maxi(max_riders,c.riders.size())
  for line:Array in c.get("landing_queues",{}).values():
   for entry:Dictionary in line:
    if not actual_arrivals.has(entry.actor_id):actual_arrivals[entry.actor_id]=entry.arrived_tick
  for input:Dictionary in inputs:
   var id:String=input.id;var a:Dictionary=s.world.facts.actors[id];var loc:Dictionary=a.location
   if loc.kind!=last.get(id,""):
    events.append({"tick":s.world.sim_tick,"actor":id,"location":loc.duplicate(true),"lift_floor":c.floor_id,"phase":c.phase})
    if loc.kind=="transit" and not boarded.has(id):boarded[id]=s.world.sim_tick
    if last.get(id,"")=="transit" and loc.kind=="floor":landed[id]={"tick":s.world.sim_tick,"floor":loc.floor_id}
    last[id]=loc.kind
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append({"tick":s.world.sim_tick,"reason":v});break
  if tokens(s.world):errors.append("Removed elevator token returned");break
  complete=inputs.all(func(input:Dictionary)->bool:return s.space.at(s.world,input.id,int(targets[input.id]),input.destination_cell) and not s.world.facts.moves.has(input.id))
  if complete:break
 var checks:Dictionary={"all_arrived":complete,"real_boarding":boarded.size()==inputs.size(),"correct_landings":landed.size()==inputs.size(),"valid":errors.is_empty()}
 for id:String in landed:checks.correct_landings=checks.correct_landings and int(landed[id].floor)==int(targets[id])
 if name=="multi_destination":checks.shared_cabin=max_riders>=2;checks.ascending_drop_order=landed.has("near") and landed.has("far") and int(landed.near.tick)<int(landed.far.tick)
 if name=="opposite_calls_extreme":checks.farthest_then_reverse_pickup=boarded.has("upper") and boarded.has("middle") and int(boarded.upper)<int(boarded.middle)
 if name=="drop_before_pickup":checks.first_out_then_in=landed.has("drop") and boarded.has("pickup") and int(landed.drop.tick)<int(boarded.pickup);checks.through_rider_preserved=landed.has("through") and int(landed.through.floor)==3
 if name=="cabin_capacity":checks.physical_capacity_respected=max_riders<=9;checks.multiple_trips=boarded.size()==10 and max_riders<10
 if name=="arrival_fifo":
  checks.actual_arrival_not_request=actual_arrivals.has("late_request") and actual_arrivals.has("early_request") and int(actual_arrivals.late_request)<int(actual_arrivals.early_request)
  checks.boarding_fifo=boarded.has("late_request") and boarded.has("early_request") and int(boarded.late_request)<int(boarded.early_request)
 var ok:bool=checks.values().all(func(v:bool)->bool:return v)
 var r:Dictionary={"case":name,"ok":ok,"checks":checks,"errors":errors,"steps":steps,"events":events,"actual_arrivals":actual_arrivals,"max_riders":max_riders,"final_connector":c.duplicate(true),"final_moves":s.world.facts.moves.duplicate(true),"final_actors":s.world.facts.actors.duplicate(true),"source":"Legal historical floor/input positions; all queueing and journeys are real movement"};s.dispose();return r
func directions()->Dictionary:
 var c:Dictionary={"floor_id":3,"direction":0,"passenger_groups":[],"landing_queues":{"1:1":[{"actor_id":"lower"}],"4:-1":[{"actor_id":"upper"}]},"unavailable_heads":{}}
 var checks:Dictionary={"nearest_up":LiftController.choose_direction(c)==1}
 c.landing_queues={"2:1":[{"actor_id":"lower"}],"4:-1":[{"actor_id":"upper"}]}
 checks.equal_distance_fixed_up=LiftController.choose_direction(c)==1
 c.direction=1;c.passenger_groups=[{"to":5}]
 checks.keep_current_direction=LiftController.choose_direction(c)==1
 c.floor_id=5;c.passenger_groups=[];c.landing_queues={"5:-1":[{"actor_id":"reverse"}],"2:1":[{"actor_id":"behind"}]}
 checks.reverse_at_extreme=LiftController.choose_direction(c)==-1
 c.floor_id=1;c.direction=1;c.landing_queues={"3:-1":[{"actor_id":"three"}],"4:-1":[{"actor_id":"four"}]}
 checks.empty_to_farthest_opposing_call=LiftController.next_stop(c)==4
 return {"case":"direction_calculation","ok":checks.values().all(func(v:bool)->bool:return v),"checks":checks,"scope":"Pure legal demand boundaries; separate physical journey tests verify actual motion"}
func cold_groups()->Dictionary:
 var s:=fixture();var id:String=suite._connection(s);var c:Dictionary=s.world.facts.connectors[id];c.floor_id=4
 var specs:Array=[{"id":"near","cell":[42,80],"to":2,"goal":[45,82]},{"id":"far","cell":[44,82],"to":3,"goal":[47,82]}]
 var errors:Array=[];var snapshots:Dictionary={};var details:Array=[];var final_reference:Dictionary={}
 for a:Dictionary in specs:
  suite._add_actor(s,a.id,"S49",a.cell,1)
  var reason:String=s.space.request_move(s.world,a.id,a.to,a.goal)
  if not reason.is_empty():errors.append(reason)
 for i:int in 600:
  suite._movement_tick(s)
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  if c.passenger_groups.size()>=2 and c.phase in ["boarding","riding","alighting","idle"] and not snapshots.has(c.phase):snapshots[c.phase]=s.world.freeze()
  if snapshots.size()==4:break
 s.dispose()
 for phase:String in snapshots:
  var source:Dictionary=snapshots[phase]
  var args:=OS.get_cmdline_user_args()
  if not args.is_empty():FileAccess.open(args[0]+"."+phase+".bin",FileAccess.WRITE).store_var(source,true)
  var world:=WorldState.new(source.duplicate(true))
  var exact:bool=world.freeze()==source
  var restored:=HospitalSimulation.new(world,suite.content);var complete:bool=false;var reason:String=world.validate(suite.content);var steps:int=0
  for i:int in 2400:
   if not reason.is_empty():break
   suite._movement_tick(restored);steps=i+1;reason=world.validate(suite.content)
   complete=specs.all(func(a:Dictionary)->bool:return restored.space.at(world,a.id,a.to,a.goal) and not world.facts.moves.has(a.id))
   if complete:break
  if final_reference.is_empty():final_reference=world.freeze()
  var same_final:bool=final_reference==world.freeze()
  details.append({"phase":phase,"same_complete_final_state":same_final,"exact_facts_rng_events":exact,"initial_tick":source.get("sim_tick",-1),"complete":complete,"validation":reason,"steps":steps,"no_tokens":not tokens(world)})
  restored.dispose()
 var ok:bool=errors.is_empty() and snapshots.size()==4 and details.all(func(d:Dictionary)->bool:return d.same_complete_final_state and d.exact_facts_rng_events and d.complete and d.validation.is_empty() and d.no_tokens)
 return {"case":"multi_group_cold_phases","ok":ok,"errors":errors,"actual_phases":snapshots.keys(),"details":details}
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var rows:Array=[]
 rows.append(idle());rows.append(directions());rows.append(cold_groups())
 rows.append(journey("far_down_only",[{"id":"upper","floor":4,"cell":[44,82]}],1,{"upper":1}))
 rows.append(journey("opposite_calls_extreme",[{"id":"upper","floor":4,"cell":[42,80]},{"id":"middle","floor":3,"cell":[44,82]}],1,{"upper":1,"middle":1}))
 rows.append(journey("multi_destination",[{"id":"near","floor":1,"cell":[42,80]},{"id":"far","floor":1,"cell":[44,82]}],4,{"near":2,"far":3}))
 rows.append(journey("arrival_fifo",[{"id":"early_request","floor":1,"cell":[60,92]},{"id":"late_request","floor":1,"cell":[41,77]}],4,{"early_request":2,"late_request":2}))
 rows.append(journey("drop_before_pickup",[{"id":"drop","floor":1,"cell":[42,80]},{"id":"through","floor":1,"cell":[44,82]},{"id":"pickup","floor":2,"cell":[46,82]}],4,{"drop":2,"through":3,"pickup":3}))
 var crowd:Array=[];var goals:Dictionary={}
 for i:int in 10:
  var actor_id:String="capacity_%02d"%i;crowd.append({"id":actor_id,"floor":1,"cell":[42+2*(i%5),80+2*(i/5)]});goals[actor_id]=2
 rows.append(journey("cabin_capacity",crowd,4,goals))
 var report:Dictionary={"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows,"scope":"Selected directional lift physical boundaries; not full functional coverage or performance evidence"}
 if not args.is_empty():var f:=FileAccess.open(args[0],FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
 print(JSON.stringify(report));quit(0 if report.ok else 1)
