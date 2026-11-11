extends SceneTree
# Targeted regression from the immutable, naturally diagnosed item49 boundary.
# Args: full-facts input, unique evidence prefix. No fabricated movement/work.
var prefix: String
var checks: Array = []
func _initialize() -> void: call_deferred("run")
func check(label: String, ok: bool, details: Variant = null) -> void:
 checks.append({"check":label,"ok":ok,"details":details})
 print("CHECK ",JSON.stringify(checks.back()))
func save(label: String, value: Variant) -> void:
 var path: String = prefix+"-"+label+".bin"
 assert(not FileAccess.file_exists(path))
 FileAccess.open(path,FileAccess.WRITE).store_var(value,true)
 FileAccess.open(path+".json",FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))
func finish(sim: HospitalSimulation) -> void:
 save("checks",checks)
 var ok: bool = true
 for row: Dictionary in checks: ok = ok and bool(row.ok)
 sim.dispose()
 quit(0 if ok else 1)
func run() -> void:
 var args: PackedStringArray = OS.get_cmdline_user_args()
 prefix = args[1]
 var raw: Dictionary = FileAccess.open(args[0],FileAccess.READ).get_var(true)
 save("raw-input",raw.duplicate(true))
 var content: HospitalContent = HospitalContent.new()
 var sim: HospitalSimulation = HospitalSimulation.new(WorldState.new(raw.duplicate(true)),content)
 var world: WorldState = sim.world
 var visit: Dictionary = world.facts.visits["visit_00000011"]
 var room: Dictionary = world.facts.rooms.room_physical
 check("exact_restore",world.freeze()==raw,world.validate(content))
 check("closed_input",not room.open and visit.phase=="wait_consult")
 var before: Dictionary = world.freeze()
 var quotes: Array = sim.clinic.compare_plans(world,visit.id)
 for quote: Dictionary in quotes:
  if quote.plan_id=="P_D09_SURGERY": continue
  check("closed_current_"+str(quote.plan_id),not quote.ok and quote.structural_ok and "房间" in quote.reason and "关闭" in quote.reason and quote.availability_reason==quote.reason,quote)
  var structural: Dictionary = sim.clinic.plan_quote(world,visit.id,quote.plan_id,{"structural_only":true,"ignore_supplies":true})
  check("structural_"+str(quote.plan_id),structural.ok and structural.structural_ok,structural)
 check("closed_new_dispatch_candidates",sim.clinic.service_candidates(world,visit,"outpatient").is_empty())
 check("closed_guidance_target",sim.clinic.floor_guidance._target_ids(world,visit,"outpatient").is_empty())
 check("closed_missing_reason","房间" in sim.clinic._missing_service_reason(world,visit,"outpatient") and "关闭" in sim.clinic._missing_service_reason(world,visit,"outpatient"),sim.clinic._missing_service_reason(world,visit,"outpatient"))
 check("queries_read_only",before==world.freeze())
 # Stop the red baseline before advancing a known-invalid treatment decision.
 for row: Dictionary in checks:
  if not row.ok:
   finish(sim)
   return
 # Advance real consultation while the later treatment room remains closed.
 var consultation_ticket_id: String = visit.ticket_id
 var evidence: Dictionary = visit.evidence_by_source.duplicate(true)
 var start_tick: int = world.sim_tick
 while world.sim_tick<start_tick+1600 and visit.phase!="wait_outpatient" and visit.phase!="departed":
  sim.step()
  if world.sim_tick%100==0: await process_frame
 save("waiting",world.freeze())
 check("closed_consultation_recommends_without_future_hold",visit.phase=="wait_outpatient" and not visit.plan_decision.is_empty() and world.facts.preparations.is_empty() and world.facts.attempts.is_empty(),visit)
 check("consultation_keeps_evidence",visit.evidence_by_source==evidence)
 var ticket_id: String = visit.ticket_id
 var ticket: Dictionary = world.facts.tickets.get(ticket_id,{}).duplicate(true)
 check("new_stage_has_outpatient_ticket",ticket.get("kind","")=="outpatient" and ticket_id!=consultation_ticket_id,ticket)
 var decision: Dictionary = visit.plan_decision.duplicate(true)
 for i: int in range(10): sim.step()
 check("closed_wait_keeps_decision",visit.plan_decision==decision and visit.ticket_id==ticket_id and world.facts.attempts.is_empty())
 # Explicit legal pre-operation reopening of the existing room only. This is
 # not a construction/UI test and changes no positions, timers, work or ticket.
 room.open = true
 save("reopened-input",world.freeze())
 check("reopened_quote",sim.clinic.plan_quote(world,visit.id,str(decision.get("plan_id","P_D09_COMMON"))).ok)
 check("reopened_candidates",not sim.clinic.service_candidates(world,visit,"outpatient").is_empty())
 check("reopened_guidance",sim.clinic.floor_guidance._target_ids(world,visit,"outpatient")==["zombie_machine"])
 var resume_tick: int = world.sim_tick
 while world.sim_tick<resume_tick+1600 and world.facts.attempts.is_empty() and visit.phase!="departed":
  sim.step()
  if world.sim_tick%100==0: await process_frame
 save("active",world.freeze())
 check("real_start_after_reopen",not world.facts.attempts.is_empty() and visit.phase=="outpatient",visit)
 var active_session: Dictionary = {}
 for session: Dictionary in world.facts.sessions.values():
  if session.visit_id==visit.id and session.kind=="outpatient": active_session=session
 check("reopen_keeps_decision_evidence_ticket",visit.plan_decision==decision and visit.evidence_by_source==evidence and active_session.get("original_ticket",{}).get("id","")==ticket_id and active_session.get("original_ticket",{}).get("enqueued_tick",-1)==ticket.get("enqueued_tick",-2))
 if not world.facts.attempts.is_empty():
  var attempts: Dictionary = world.facts.attempts.duplicate(true)
  var session_ids: Array = world.ids("sessions")
  # Close to new starts, not to cancel an already committed safe service.
  room.open = false
  save("active-closed-input",world.freeze())
  sim.step()
  check("active_commitment_survives_close",world.facts.attempts==attempts and world.ids("sessions")==session_ids and visit.phase=="outpatient")
  save("active-closed-after",world.freeze())
 check("final_valid",world.validate(content).is_empty(),world.validate(content))
 multiple_candidates(raw,content)
 finish(sim)

func multiple_candidates(raw: Dictionary, content: HospitalContent) -> void:
 var sim: HospitalSimulation = HospitalSimulation.new(WorldState.new(raw.duplicate(true)),content)
 var builder: BuildService = BuildService.new(content,sim.space)
 var room_result: CommandResult = builder.execute(sim.world,"build_room",{"id":"room_alternative","room_type_id":"T01","floor_id":1,"origin":[49,76],"size":[5,6],"doors":[{"definition_id":"DR04","edge":"south","offset":1}]})
 check("alternative_room_built",room_result.accepted,room_result.reason)
 if not room_result.accepted:
  sim.dispose()
  return
 var facility_result: CommandResult = builder.execute(sim.world,"build_facility",{"id":"zz_alternative_machine","definition_id":"M09","floor_id":1,"cell":[50,77],"room_id":"room_alternative"})
 check("alternative_machine_built",facility_result.accepted,facility_result.reason)
 if not facility_result.accepted:
  sim.dispose()
  return
 # Explicit legal department-scope input: the added treatment room belongs
 # to this visit's general department, rather than an unrelated destination.
 # Initialize legitimate new-equipment defaults before freezing the fixture.
 sim.services.maintenance.ensure(sim.world)
 var input: Dictionary = sim.world.freeze()
 save("alternative-input",input)
 sim.dispose()
 sim = HospitalSimulation.new(WorldState.new(input.duplicate(true)),content)
 check("alternative_restore_exact",sim.world.freeze()==input and sim.world.validate(content).is_empty(),sim.world.validate(content))
 var visit: Dictionary = sim.world.facts.visits.visit_00000011
 var candidates: Array = sim.clinic.service_candidates(sim.world,visit,"outpatient")
 check("skip_closed_choose_later_open",not candidates.is_empty() and candidates[0].facility_id=="zz_alternative_machine",candidates)
 var quote: Dictionary = sim.clinic.plan_quote(sim.world,visit.id,"P_D09_COMMON")
 check("quote_skips_closed_choose_later_open",quote.ok and quote.get("facility_id","")=="zz_alternative_machine",quote)
 var targets: Array = sim.clinic.floor_guidance._target_ids(sim.world,visit,"outpatient")
 check("guidance_skips_closed_choose_later_open",targets==["zz_alternative_machine"],targets)
 sim.dispose()
