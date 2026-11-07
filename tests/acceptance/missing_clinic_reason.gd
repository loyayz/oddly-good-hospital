extends SceneTree
# Args: immutable evidence directory, unique output prefix. Quote-only, no steps.
var prefix: String
var checks: Array = []
func _initialize() -> void: call_deferred("run")
func save(label: String, value: Variant) -> void:
 var path: String=prefix+"-"+label+".bin"
 assert(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".json"))
 FileAccess.open(path,FileAccess.WRITE).store_var(value,true)
 FileAccess.open(path+".json",FileAccess.WRITE).store_string(JSON.stringify(value,"\t"))
func check(label: String, ok: bool, details: Variant = null) -> void:
 checks.append({"check":label,"ok":ok,"details":details})
 print("CHECK ",JSON.stringify(checks.back()))
func run() -> void:
 var args: PackedStringArray=OS.get_cmdline_user_args()
 prefix=args[1]
 var content: HospitalContent=HospitalContent.new()
 var cases: Array=[
  ["missing","item049-review-final-variants-v1-missing-input.bin",false,false,"缺少实际设施：整复台"],
  ["failed","item049-review-final-variants-v1-failed-input.bin",false,true,"治疗设备故障，等待修复：整复台"],
  ["closed","item049-review-final-variants-v1-closed-input.bin",false,true,"房间已关闭，等待原方案的房间开放"],
  ["offshift","item049-review-final-variants-v1-offshift-input.bin",false,true,"等待当前排班服务池内的治疗医生"],
  ["healthy","item049-writer-fault-green-v1-repaired-input.bin",true,true,""]]
 for row: Array in cases:
  var label: String=row[0]
  var raw: Dictionary=FileAccess.open(args[0].path_join(row[1]),FileAccess.READ).get_var(true)
  save(label+"-raw-input",raw)
  var sim: HospitalSimulation=HospitalSimulation.new(WorldState.new(raw.duplicate(true)),content)
  var world: WorldState=sim.world
  check(label+"_exact_restore",world.freeze()==raw and world.validate(content).is_empty(),world.validate(content))
  var before: Dictionary=world.freeze()
  var visit: Dictionary=world.facts.visits.visit_00000011
  var quotes: Array=sim.clinic.compare_plans(world,visit.id)
  save(label+"-quotes",quotes)
  for quote: Dictionary in quotes:
   if quote.plan_id=="P_D09_SURGERY": continue
   check(label+"_current_"+str(quote.plan_id),quote.ok==row[2] and quote.structural_ok==row[3] and quote.reason==row[4],quote)
   var structural: Dictionary=sim.clinic.plan_quote(world,visit.id,quote.plan_id,{"structural_only":true,"ignore_supplies":true})
   check(label+"_structural_"+str(quote.plan_id),structural.ok==row[3] and structural.structural_ok==row[3] and (structural.reason==row[4] if label=="missing" else structural.reason.is_empty()),structural)
  var candidates: Array=sim.clinic.service_candidates(world,visit,"outpatient")
  check(label+"_current_candidates",not candidates.is_empty() if row[2] else candidates.is_empty(),candidates)
  check(label+"_query_purity",world.freeze()==before)
  check(label+"_no_future_holds",world.facts.preparations.is_empty() and world.facts.attempts.is_empty())
  sim.dispose()
 save("checks",checks)
 var passed: bool=true
 for row: Dictionary in checks: passed=passed and row.ok
 quit(0 if passed else 1)
