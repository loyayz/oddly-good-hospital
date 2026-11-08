extends RefCounted
const OLD="bench_room_1_00_1"
const ACTIVE="bench_room_1_00_0"
const PATIENT="bench_patient_0036"
const DOCTOR="bench_staff_0000"
const VISIT="visit_00000148"

func _candidate(sim: HospitalSimulation) -> Array:
 return sim.clinic.service_candidates(sim.world,sim.world.facts.visits[VISIT],"gp",false,false,{"facility_id":OLD,"staff_id":DOCTOR,"first_only":true})

func run_snapshot(facts: Dictionary, content: HospitalContent) -> Dictionary:
 var world:=WorldState.new(facts.duplicate(true))
 var sim:=HospitalSimulation.new(world,content)
 var old: Dictionary=world.facts.adaptations[OLD].duplicate(true)
 var active: Dictionary=world.facts.adaptations[ACTIVE].duplicate(true)
 var actors: Dictionary=world.facts.actors.duplicate(true)
 var reservations_before: Dictionary=world.facts.adaptations.duplicate(true)
 var before: Dictionary={"reservation":old,"candidate":_candidate(sim),"reason":sim.space.facility_reservation_reason(world,OLD,world.facts.visits[VISIT].actor_id)}
 sim.space.release_adaptations(world)
 var removed: Array=[]
 var changed: Array=[]
 for id: String in reservations_before:
  if not world.facts.adaptations.has(id):removed.append(id)
  elif world.facts.adaptations[id]!=reservations_before[id]:changed.append(id)
 var after: Dictionary={"held":world.facts.adaptations.has(OLD),"candidate":_candidate(sim),"reason":sim.space.facility_reservation_reason(world,OLD,world.facts.visits[VISIT].actor_id)}
 var builder:=BuildService.new(content,sim.space)
 var busy: String=builder._busy(world,OLD)
 var preview: Dictionary=builder.preview(world,{"kind":"build_demolish","target_id":OLD})
 var remodel:=HospitalRemodel.new(content,sim.space)
 var order: Dictionary={"room_ids":[],"member_ids":[OLD],"commands":[]}
 var affected: Dictionary=remodel._affected_view(world,order)
 var checks: Dictionary={"real_snapshot_expected_exit_owner":old.owner_id==PATIENT,"old_patient_physically_clear":not _inside(sim.space,world.facts.actors[PATIENT],old),"doctor_still_at_original_post":sim.space._at_ordinary_operator_post(world.facts.actors[DOCTOR],old),"blocked_before":before.candidate.is_empty() and not before.reason.is_empty(),"released_after":not after.held and after.reason.is_empty(),"same_doctor_candidate_after":not after.candidate.is_empty(),"only_expected_reservation_removed":removed==[OLD] and changed.is_empty(),"active_ticket_preserved":world.facts.adaptations.get(ACTIVE,{})==active,"actors_unchanged":world.facts.actors==actors,"build_busy":not busy.is_empty(),"actual_demolition_preview_blocked":not preview.ok,"remodel_operator_in_affected_area":remodel._in_affected_area(world,order,world.facts.actors[DOCTOR],affected)}
 var result: Dictionary={"scope":"actual v18 continuation snapshot, no simulation steps","tick":world.sim_tick,"before":before,"after":after,"removed":removed,"changed":changed,"build_reason":busy,"demolition_preview":preview,"checks":checks,"micro_boundaries":[]}
 sim.dispose()
 for mode: String in ["patient_inside","operator_not_at_post","extra_region","large_operator_region","changed_patient_anchor","active_ticket_owner"]:
  var micro: Dictionary=facts.duplicate(true)
  var held: Dictionary=micro.adaptations[OLD]
  match mode:
   "patient_inside":micro.actors[PATIENT].location.cell=held.patient_cell.duplicate()
   "operator_not_at_post":micro.actors[DOCTOR].location.cell=held.patient_cell.duplicate()
   "extra_region":held.regions.append([9,7,1,1])
   "large_operator_region":held.regions[-1]=[9,8,2,2]
   "changed_patient_anchor":held.patient_cell=[10,11]
   "active_ticket_owner":held.owner_id="ticket_00000063"
  var m:=HospitalSimulation.new(WorldState.new(micro),content)
  var saved: Dictionary=m.world.facts.adaptations[OLD].duplicate(true)
  m.space.release_adaptations(m.world)
  result.micro_boundaries.append({"case":mode,"scope":"constructed boundary, not actual gameplay event","preserved":m.world.facts.adaptations.get(OLD,{})==saved})
  m.dispose()
 result.ok=true
 for value: bool in checks.values():result.ok=result.ok and value
 for row: Dictionary in result.micro_boundaries:result.ok=result.ok and row.preserved
 return result

func _inside(space: HospitalSpace, actor: Dictionary, held: Dictionary) -> bool:
 if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(held.floor_id):return false
 for area: Array in held.regions:
  if space.body_rectangle(actor).intersects(Rect2(area[0],area[1],area[2],area[3]),false):return true
 return false
