extends SceneTree
const Step = preload("res://tests/acceptance/clinical_step.gd")
var content: HospitalContent
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var args=OS.get_cmdline_user_args()
 if args.size()!=4:
  push_error("Expected output.json, probe/journey/restore comma list, real transfer-start.bin, real corner.bin")
  quit(2);return
 content=HospitalContent.new()
 var rows: Array=[]
 for name: String in ["probe","journey","restore"]:
  if not name in args[1].split(","):continue
  var saved: Dictionary=FileAccess.open(args[3] if name=="probe" else args[2],FileAccess.READ).get_var()
  var row: Dictionary=probe(saved) if name=="probe" else journey(saved,name=="restore")
  row.case=name;rows.append(row);print(JSON.stringify(row))
 var ok: bool=not rows.is_empty()
 for row: Dictionary in rows:ok=ok and row.ok
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows,"engine":Engine.get_version_info().string},"  "))
 quit(0 if ok else 1)
func all(checks: Dictionary) -> bool:
 for value: bool in checks.values():
  if not value:return false
 return true
func probe(saved: Dictionary) -> Dictionary:
 var world=WorldState.new(saved.facts.duplicate(true));var sim=HospitalSimulation.new(world,content)
 var id: String=world.facts.visits[saved.visit_id].actor_id
 var m: Dictionary=world.facts.moves[id];var actor: Dictionary=world.facts.actors[id]
 var segment: Dictionary=m.path[m.cursor]
 var facts=world.freeze();var sweeps=sim.space.movement._accepted_sweeps.duplicate(true)
 var contact=sim.space.movement._convoy_turn_contact(world,actor,m,segment)
 var checks: Dictionary={"legal_corner_input":world.validate(content).is_empty() and actor.location.cell==[51.0,78.0],"detects_body_beyond_actual_step":contact!=null and contact.blocker_actor_ids==["clin_round"],"read_only":facts==world.freeze() and sweeps==sim.space.movement._accepted_sweeps,"no_reserved_permission":contact.reservation_ids.is_empty()}
 var short=sim.space.movement._convoy_turn_contact(world,actor,m,{"kind":"floor","floor_id":1,"cell":[51.0,78.2]})
 checks.no_probe_past_next_corner=short!=null and not short.blocked
 var straight=sim.space.movement._convoy_turn_contact(world,actor,m,{"kind":"floor","floor_id":1,"cell":[50.0,78.0]})
 checks.straight_leg_unchanged=straight==null
 var single: Dictionary=m.duplicate(true);single.members=[id]
 checks.single_actor_unchanged=sim.space.movement._convoy_turn_contact(world,actor,single,segment)==null
 # Independent query variants, never used to repair the real journey. Place
 # the blocker at the probe's exact outer boundary and just beyond it.
 var blocker: Dictionary=world.facts.actors.clin_round
 var rect: Rect2=sim.space.body_rectangle(blocker)
 blocker.location.cell[1]=float(blocker.location.cell[1])+80.0-rect.position.y
 sim.space.sync_actor(world,"clin_round")
 facts=world.freeze()
 var edge=sim.space.movement._convoy_turn_contact(world,actor,m,segment)
 checks.exact_edge_is_not_collision=edge!=null and not edge.blocked
 checks.edge_query_read_only=facts==world.freeze()
 blocker.location.cell[1]+=0.1;sim.space.sync_actor(world,"clin_round")
 var outside=sim.space.movement._convoy_turn_contact(world,actor,m,segment)
 checks.no_remote_body_scan=outside!=null and not outside.blocked
 sim.dispose()
 return {"ok":all(checks),"checks":checks}
func geometry(world: WorldState) -> Dictionary:
 var facilities: Dictionary={}
 for id: String in world.facts.facilities:
  var f: Dictionary=world.facts.facilities[id]
  facilities[id]=[f.get("cell"),f.get("footprint"),f.get("rotation"),f.get("floor_id"),f.get("patient_cell"),f.get("operator_cells")].duplicate(true)
 var rooms: Dictionary={}
 for id: String in world.facts.rooms:
  var room: Dictionary=world.facts.rooms[id]
  rooms[id]=[room.get("origin"),room.get("size"),room.get("floor_id"),room.get("kind")].duplicate(true)
 var floors: Dictionary=world.facts.floors.duplicate(true)
 for floor_data: Dictionary in floors.overrides.values():
  for door: Dictionary in floor_data.get("doors",[]):door.erase("used")
 return {"facilities":facilities,"rooms":rooms,"blocked":floors}
func journey(saved: Dictionary, restore: bool) -> Dictionary:
 var world=WorldState.new(saved.facts.duplicate(true));var sim=HospitalSimulation.new(world,content)
 sim.clinic.departments=null
 var patient_id: String=world.facts.visits[saved.visit_id].actor_id
 var fixed=geometry(world);var blocker=world.facts.actors.clin_round.location.duplicate(true)
 var errors: Array=[];var trace: Array=[];var restored: bool=false;var group_seen: bool=false;var saw_detour: bool=false
 var sequence: int=-1;var ticks: int=0;var arrived: bool=false;var zero_work_before_arrival: bool=true
 var checks: Dictionary={"input_valid":world.validate(content).is_empty(),"fixed_geometry":true,"blocker_never_relocated":true,"leader_step_budget":true,"one_leader_permission_per_tick":true,"same_request_goal_members":true,"all_world_boundaries_valid":true,"no_body_overlap":true}
 for index: int in 850:
  var before: Dictionary=world.facts.actors[patient_id].duplicate(true)
  var checks_before: int=int(sim.space.query_counts.get("convoy_leader_checks",0))
  var had_group: bool=world.facts.moves.get(patient_id,{}).has("convoy")
  Step.step(sim);ticks+=1
  var m: Dictionary=world.facts.moves.get(patient_id,{})
  var patient: Dictionary=world.facts.actors[patient_id]
  var stay: Dictionary=world.facts.ward_stays.values()[0]
  checks.fixed_geometry=checks.fixed_geometry and fixed==geometry(world)
  checks.blocker_never_relocated=checks.blocker_never_relocated and blocker==world.facts.actors.clin_round.location
  if had_group and patient.posture=="standing" and before.posture=="standing":
   checks.leader_step_budget=checks.leader_step_budget and ConvoyTrail.point(before.location.cell).distance_to(ConvoyTrail.point(patient.location.cell))<=sim.space.walking_speed(patient)*WorldState.TICK_SECONDS+0.001
  checks.one_leader_permission_per_tick=checks.one_leader_permission_per_tick and int(sim.space.query_counts.get("convoy_leader_checks",0))-checks_before<=1
  if m.has("convoy"):
   group_seen=true
   if sequence<0:sequence=int(m.request_sequence)
   checks.same_request_goal_members=checks.same_request_goal_members and int(m.request_sequence)==sequence and m.target_cell==[43,76] and m.members==[patient_id,"clin_cover"]
   if m.has("detour"):
    saw_detour=true
    if (trace.is_empty() or trace[-1].cursor!=m.cursor):trace.append({"tick":world.sim_tick,"head":patient.location.cell.duplicate(),"tail":world.facts.actors.clin_cover.location.cell.duplicate(),"phase":m.detour.phase,"cursor":m.cursor,"remaining":m.path.slice(m.cursor)})
   if restore and not restored and m.has("detour") and m.cursor>0:
    var frozen=world.freeze();sim.dispose();world=WorldState.new(frozen);sim=HospitalSimulation.new(world,content);sim.clinic.departments=null
    restored=world.freeze()==frozen
  var valid: String=world.validate(content)
  if not valid.is_empty():checks.all_world_boundaries_valid=false;errors.append(valid)
  var actors: Array=world.facts.actors.values()
  for a: int in actors.size():
   if actors[a].location.kind!="floor":continue
   for b: int in range(a+1,actors.size()):
    if actors[b].location.kind=="floor" and actors[a].location.floor_id==actors[b].location.floor_id and sim.space.body_rectangle(actors[a]).intersects(sim.space.body_rectangle(actors[b]),false):
     checks.no_body_overlap=false;errors.append("Body overlap: "+actors[a].id+" / "+actors[b].id)
  if stay.phase=="transfer":zero_work_before_arrival=zero_work_before_arrival and stay.remaining_ticks==1800
  if stay.phase=="recovery":arrived=true;break
  if not errors.is_empty():break
 checks.real_bed_arrival=arrived and world.facts.actors[patient_id].posture=="lying" and world.facts.actors[patient_id].support_facility_id=="clin_ward_0"
 checks.queue_and_local_detour_executed=group_seen and saw_detour
 checks.no_recovery_work_before_arrival=zero_work_before_arrival
 checks.restore_exact_in_detour=restored if restore else true
 var result: Dictionary={"ok":all(checks),"checks":checks,"ticks":ticks,"final_tick":world.sim_tick,"errors":errors,"trace":trace}
 sim.dispose();return result
