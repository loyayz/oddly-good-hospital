extends SceneTree
# Read-only quotes and one actual dispatch boundary; no simulated time changes.
# Args: failed diagnosed input, legal alternative input, outpatient wait input, prefix.
var prefix: String
var checks: Array = []
var content: HospitalContent
func _initialize() -> void: call_deferred("run")
func check(label: String, ok: bool, details: Variant = null) -> void:
 checks.append({"check":label,"ok":ok,"details":details})
 print("CHECK ",JSON.stringify(checks.back()))
func save(label: String, value: Variant) -> void:
 var path: String = prefix+"-"+label+".bin"
 assert(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".json"))
 FileAccess.open(path,FileAccess.WRITE).store_var(value,true)
 FileAccess.open(path+".json",FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))
func read(path: String) -> Dictionary:
 return FileAccess.open(path,FileAccess.READ).get_var(true)
func bind(label: String, raw: Dictionary) -> HospitalSimulation:
 save(label+"-input",raw)
 var sim: HospitalSimulation = HospitalSimulation.new(WorldState.new(raw.duplicate(true)),content)
 check(label+"_exact_restore",sim.world.freeze()==raw and sim.world.validate(content).is_empty(),sim.world.validate(content))
 return sim
func query(sim: HospitalSimulation, label: String, executable: bool, reason: String, facility_id: String = "zombie_machine") -> void:
 var before: Dictionary = sim.world.freeze()
 var visit: Dictionary = sim.world.facts.visits.visit_00000011
 var quotes: Array = sim.clinic.compare_plans(sim.world,visit.id)
 save(label+"-quotes",quotes)
 for quote: Dictionary in quotes:
  if quote.plan_id=="P_D09_SURGERY": continue
  check(label+"_current_"+str(quote.plan_id),quote.ok==executable and quote.structural_ok and (quote.get("facility_id","")==facility_id if executable else reason in quote.reason and quote.availability_reason==quote.reason),quote)
  var structural: Dictionary = sim.clinic.plan_quote(sim.world,visit.id,quote.plan_id,{"structural_only":true,"ignore_supplies":true})
  check(label+"_structural_"+str(quote.plan_id),structural.ok and structural.structural_ok,structural)
 var candidates: Array = sim.clinic.service_candidates(sim.world,visit,"outpatient")
 check(label+"_new_start_candidates",not candidates.is_empty() and candidates[0].facility_id==facility_id if executable else candidates.is_empty(),candidates)
 var targets: Array = sim.clinic.floor_guidance._target_ids(sim.world,visit,"outpatient")
 check(label+"_guidance",targets==[facility_id] if executable else targets.is_empty(),targets)
 check(label+"_all_queries_pure",sim.world.freeze()==before)
func run() -> void:
 var args: PackedStringArray = OS.get_cmdline_user_args()
 prefix=args[3]
 content=HospitalContent.new()
 var raw: Dictionary = read(args[0])
 var sim: HospitalSimulation = bind("failed",raw)
 check("exact_failed_boundary",sim.world.facts.facilities.zombie_machine.failed and sim.world.facts.rooms.room_physical.open)
 query(sim,"failed",false,"故障")
 sim.dispose()
 var repaired: Dictionary = raw.duplicate(true)
 repaired.facilities.zombie_machine.failed=false
 sim=bind("repaired",repaired)
 query(sim,"repaired",true,"")
 sim.dispose()
 var closed: Dictionary = repaired.duplicate(true)
 closed.rooms.room_physical.open=false
 sim=bind("closed",closed)
 query(sim,"closed",false,"房间已关闭")
 sim.dispose()
 # Reuse the validated actual-build alternative fixture. Only primary fault/
 # room flags change before binding; positions and maintenance defaults do not.
 var alternative: Dictionary = read(args[1])
 save("alternative-raw",alternative)
 alternative.rooms.room_physical.open=true
 alternative.facilities.zombie_machine.failed=true
 sim=bind("alternative",alternative)
 query(sim,"alternative",true,"","zz_alternative_machine")
 sim.dispose()
 # Original recommended outpatient-stage boundary: fault remains a wait for
 # this same decision, not a new consultation or future resource reservation.
 var waiting: Dictionary = read(args[2])
 save("waiting-raw",waiting)
 waiting.rooms.room_physical.open=true
 waiting.facilities.zombie_machine.failed=true
 sim=bind("waiting",waiting)
 var world: WorldState=sim.world
 var visit: Dictionary=world.facts.visits.visit_00000011
 var ticket: Dictionary=world.facts.tickets[visit.ticket_id].duplicate(true)
 var decision: Dictionary=visit.plan_decision.duplicate(true)
 var evidence: Dictionary=visit.evidence_by_source.duplicate(true)
 var tick: int=world.sim_tick
 sim.clinic._dispatch_service(world,visit,world.facts.tickets[visit.ticket_id])
 check("fault_dispatch_keeps_original_wait",visit.phase=="wait_outpatient" and visit.ticket_id==ticket.id and world.facts.tickets[ticket.id].enqueued_tick==ticket.enqueued_tick and visit.plan_decision==decision and visit.evidence_by_source==evidence,visit)
 check("fault_dispatch_no_start_or_reservation",world.facts.attempts.is_empty() and world.facts.preparations.is_empty() and world.sim_tick==tick)
 save("waiting-after-dispatch",world.freeze())
 check("waiting_final_valid",world.validate(content).is_empty(),world.validate(content))
 sim.dispose()
 save("checks",checks)
 var ok: bool=true
 for row: Dictionary in checks: ok=ok and row.ok
 quit(0 if ok else 1)
