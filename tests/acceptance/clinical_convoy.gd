extends SceneTree
var builder = preload("res://tests/acceptance/clinical_fixtures.gd").new()
var content: HospitalContent
func _initialize(): call_deferred("run")
func run() -> void:
 var begun: int = Time.get_ticks_usec()
 content = HospitalContent.new()
 builder._content = content
 builder._cache = preload("res://tests/acceptance/checkpoints.gd").new(content,"res://tests/acceptance/clinical_fixtures.gd",weakref(builder))
 var ready: bool = await builder._ensure_boundary(self,"surgery_transfer")
 var out: Dictionary = {"source":"Fresh standard surgery_transfer boundary; fixture surgery/wake last-work inputs are explicit. No transfer actor teleport, clock skip, or nudge.","preparation_us":Time.get_ticks_usec()-begun,"fixture_ready":ready,"fixtures":builder._cache.observations.duplicate(true)}
 if ready:
  var initial: Dictionary = builder._snapshots.surgery_transfer.duplicate(true)
  out.baseline = _continue(initial,false)
  out.restored = _continue(initial,true)
  out.same_final_facts = out.baseline.final_facts==out.restored.final_facts
  out.ok = out.baseline.ok and out.restored.ok and out.restored.save_restored and out.same_final_facts
 else:
  out.ok = false
  out.fixture_failures = builder._fixture_failures
 out.elapsed_us = Time.get_ticks_usec()-begun
 var output: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://clinical-convoy-results.json"
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(out,"  "))
 print(JSON.stringify({"ok":out.ok,"fixture_ready":ready,"elapsed_us":out.elapsed_us}))
 builder._dispose_simulations()
 quit(0 if out.ok else 1)
func _continue(initial: Dictionary, save_mid: bool) -> Dictionary:
 var begun: int = Time.get_ticks_usec()
 var world: WorldState = WorldState.new(initial.facts.duplicate(true))
 var sim: HospitalSimulation = HospitalSimulation.new(world,content)
 sim.clinic.experience = null
 var visit_id: String = initial.visit_id
 var stay_id: String = ""
 for stay: Dictionary in world.facts.ward_stays.values():
  if world.facts.attempts[stay.attempt_id].visit_id==visit_id: stay_id=stay.id
 var commitments: Dictionary = builder._commitments(world.facts.attempts)
 var original_stay: Dictionary = world.facts.ward_stays[stay_id].duplicate(true)
 var original_remaining: int = int(original_stay.get("remaining_ticks",-1))
 var quote: Dictionary = _quote_check(sim,world.facts.visits[visit_id],world.facts.ward_stays[stay_id])
 var errors: Array = []
 if not quote.ok: errors.append("Read-only transfer quote must include the final bedside walk")
 var group_seen: bool = false
 var saved: bool = false
 var handoff_seen: bool = false
 var handoff_witness: Dictionary = {}
 var restore_checks: Dictionary = {}
 var terminal_quote: Dictionary = {}
 var mid_quote: Dictionary = {}
 var trace: Array = []
 var last_phase: String = ""
 var steps: int = 0
 for i: int in 1200:
  steps=i+1
  var visit: Dictionary = world.facts.visits[visit_id]
  var stay: Dictionary = world.facts.ward_stays[stay_id]
  var patient_id: String = visit.actor_id
  var escort_id: String = stay.escort_id
  var before_bed: Dictionary = sim.space.facility_layout(world,stay.bed_id)
  if stay.phase=="transfer" and sim.space.at(world,patient_id,int(before_bed.floor_id),before_bed.patient_cell) and not world.facts.moves.has(patient_id):
   if terminal_quote.is_empty(): terminal_quote=_quote_check(sim,visit,stay)
   if sim.space.at(world,escort_id,int(before_bed.floor_id),before_bed.operator_cells[0]) and not world.facts.moves.has(escort_id):
    handoff_witness={"tick":world.sim_tick,"patient":world.facts.actors[patient_id].location.duplicate(true),"escort":world.facts.actors[escort_id].location.duplicate(true),"operator_cell":before_bed.operator_cells[0].duplicate()}
  sim.clinic.dispatch(world)
  if stay.phase=="recovery" and handoff_witness.is_empty(): errors.append("Recovery started without actual bedside handoff witness")
  var movement: Dictionary = world.facts.moves.get(patient_id,{})
  if movement.has("convoy"):
   group_seen=true
   if restore_checks.is_empty(): restore_checks=_restore_checks(world,patient_id)
   if mid_quote.is_empty():
    mid_quote=_quote_check(sim,visit,stay)
    if not mid_quote.ok or int(mid_quote.gathering_ticks)!=0: errors.append("Active convoy quote incorrectly re-gathers its escort")
   if not restore_checks.ok: errors.append("Invalid convoy save accepted or valid save rejected")
  var bed: Dictionary = sim.space.facility_layout(world,stay.bed_id)
  if stay.phase=="transfer" and sim.space.at(world,patient_id,int(bed.floor_id),bed.patient_cell) and not world.facts.moves.has(patient_id):
   handoff_seen=true
   if not sim.space.at(world,escort_id,int(bed.floor_id),bed.operator_cells[0]) and world.facts.actors[patient_id].get("posture","")=="lying": errors.append("Patient supported before escort bedside arrival")
  _movement_tick(sim)
  var problem: String = world.validate(content)
  if not problem.is_empty(): errors.append(problem)
  var floor_actors: Array = []
  for actor: Dictionary in world.facts.actors.values():
   if actor.location.kind=="floor": floor_actors.append(actor)
  for a: int in floor_actors.size():
   for b: int in range(a+1,floor_actors.size()):
    if floor_actors[a].location.floor_id==floor_actors[b].location.floor_id and sim.space.body_rectangle(floor_actors[a]).intersects(sim.space.body_rectangle(floor_actors[b]),false): errors.append("Endpoint bodies overlap: "+floor_actors[a].id+"/"+floor_actors[b].id)
  if i%100==0 or stay.phase!=last_phase:
   trace.append({"step":i,"phase":stay.phase,"patient":world.facts.actors[patient_id].location.duplicate(true),"escort":world.facts.actors[escort_id].location.duplicate(true),"waiting":visit.get("waiting_reason",""),"movement":world.facts.moves.get(patient_id,{}).duplicate(true)})
  last_phase=stay.phase
  if save_mid and not saved and movement.has("convoy") and movement.convoy.points.size()>1:
   var encoder: HospitalJsonStream = HospitalJsonStream.new()
   var path: String = "user://convoy-clinical-current.json"
   if not encoder.encode(path,world.freeze(),func(_bytes:int)->bool:return true): errors.append(encoder.error);break
   var decoder: HospitalJsonStream = HospitalJsonStream.new()
   var decoded: Dictionary = decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true)
   if not decoded.ok: errors.append(decoder.error);break
   var restored: WorldState = WorldState.new(decoded.value)
   var restore_error: String = restored.validate(content)
   if not restore_error.is_empty(): errors.append(restore_error);break
   if restored.freeze()!=world.freeze(): errors.append("Current-format JSON stream changed saved facts");break
   sim.dispose()
   world=restored
   sim=HospitalSimulation.new(world,content)
   sim.clinic.experience=null
   saved=true
  if not errors.is_empty() or stay.phase=="recovery": break
 var stay: Dictionary = world.facts.ward_stays[stay_id]
 var preserved: bool = commitments==builder._commitments(world.facts.attempts) and stay.bed_id==original_stay.bed_id and stay.attempt_id==original_stay.attempt_id
 var result: Dictionary = {"ok":errors.is_empty() and group_seen and handoff_seen and not handoff_witness.is_empty() and stay.phase=="recovery" and preserved and int(stay.remaining_ticks)==original_remaining and quote.ok and mid_quote.get("ok",false) and terminal_quote.get("ok",false),"group_seen":group_seen,"handoff_seen":handoff_seen,"handoff_witness":handoff_witness,"quote":quote,"terminal_quote":terminal_quote,"mid_quote":mid_quote,"restore_validation":restore_checks,"recovery":stay.phase=="recovery","save_restored":saved,"commitments_preserved":preserved,"initial_recovery_remaining":original_remaining,"final_recovery_remaining":stay.get("remaining_ticks",-1),"steps":steps,"runtime_us":Time.get_ticks_usec()-begun,"errors":errors,"trace":trace,"final_facts":world.freeze()}
 sim.dispose()
 return result

# Quotes observe legal boundaries only. They cannot gather staff, grant real
# access, consume RNG, or omit the final independent bedside walk.
func _quote_check(sim: HospitalSimulation, visit: Dictionary, stay: Dictionary) -> Dictionary:
 var world: WorldState=sim.world
 var before: Dictionary=world.freeze()
 var source: Dictionary=world.facts.attempts[stay.attempt_id]
 var quote: Dictionary=sim.clinic._bed_transport(world,visit,source,stay,true)
 var bed: Dictionary=sim.space.facility_layout(world,stay.bed_id)
 var terminal: bool=sim.space.at(world,visit.actor_id,int(bed.floor_id),bed.patient_cell)
 var handoff_ticks: int=int(quote.get("handoff",{}).get("travel_ticks",-1))
 var components: int=handoff_ticks if terminal else int(quote.get("gathering",{}).get("travel_ticks",-1))+int(quote.get("transfer",{}).get("travel_ticks",-1))+handoff_ticks
 var exit_ticks: int=0
 if not terminal and world.facts.actors[visit.actor_id].get("posture","")=="lying":
  var support: Dictionary=sim.space.facility_layout(world,world.facts.actors[visit.actor_id].support_facility_id)
  exit_ticks=sim.space.support_exit_ticks(world.facts.actors[visit.actor_id],support)
 var readonly: bool=world.freeze()==before
 return {"ok":quote.get("ok",false) and readonly and handoff_ticks>=0 and int(quote.get("ticks",-1))==components+exit_ticks,"readonly":readonly,"terminal":terminal,"handoff_ticks":handoff_ticks,"gathering_ticks":quote.get("gathering",{}).get("travel_ticks",0),"transfer_ticks":quote.get("transfer",{}).get("travel_ticks",0),"support_exit_ticks":exit_ticks,"total_ticks":quote.get("ticks",-1),"failure":quote if not quote.get("ok",false) else {}}

func _restore_checks(world: WorldState, primary: String) -> Dictionary:
 var original: Dictionary=world.freeze()
 var outcomes: Dictionary={}
 var valid_error: String=WorldState.new(original.duplicate(true)).validate(content)
 var passed: bool=valid_error.is_empty()
 for probe: String in ["legacy_offsets","missing_trail","missing_members","malformed_members","malformed_identity","malformed_convoy","wrong_leader","duplicate_member","wrong_floor","broken_tail","insufficient_spacing","nonfinite_spacing","extra_center"]:
  var altered: WorldState=WorldState.new(original.duplicate(true))
  var movement: Dictionary=altered.facts.moves[primary]
  match probe:
   "legacy_offsets": movement.offsets={}
   "missing_trail": movement.erase("convoy")
   "missing_members": movement.erase("members")
   "malformed_members": movement.members="not an array"
   "malformed_identity": movement.members[1]=42
   "malformed_convoy": movement.convoy=[]
   "wrong_leader": movement.members.reverse()
   "duplicate_member": movement.members[1]=primary
   "wrong_floor": movement.convoy.floor_id+=1
   "broken_tail": movement.convoy.points[0][0]+=0.25
   "insufficient_spacing": movement.convoy.spacing=float(movement.convoy.size)
   "nonfinite_spacing": movement.convoy.spacing=INF
   "extra_center": movement.convoy.centers["missing"]=[0,0]
  var error: String=altered.validate(content)
  outcomes[probe]=error
  passed=passed and not error.is_empty()
 # The door envelope schema is checked before geometry is reconstructed.
 # A fabricated malformed envelope must not crash restore, irrespective of
 # whether this particular mid-route frame has reached an expanded door.
 for probe: Variant in [[],{}, {"size":1}, {"size":1,"height":0}, {"size":1.5,"height":2}, {"size":1,"height":INF}, {"size":1,"height":2,"extra":true}]:
  var altered: WorldState=WorldState.new(original.duplicate(true))
  altered.facts.adaptations["invalid_convoy_door"]={"kind":"door","owner_id":primary,"actor_id":primary,"floor_id":1,"staff_ids":[],"regions":[],"span":1,"clear_height_m":2.0,"clear_width_m":1.5,"convoy_envelope":probe}
  var error: String=altered._validate_shapes()
  outcomes["door_"+str(outcomes.size())]=error
  passed=passed and error=="门展开队列包络无效"
 return {"ok":passed,"valid_save_error":valid_error,"rejected":outcomes}

func _movement_tick(sim: HospitalSimulation) -> void:
 sim.space.advance(sim.world,sim.world.present_actor_count())
 sim.world.facts.sim_tick+=1
 sim.world.touch()
 sim.space.finish_boundary(sim.world)
