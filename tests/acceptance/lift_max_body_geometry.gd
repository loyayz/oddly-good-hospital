extends SceneTree
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 suite.content=HospitalContent.new()
 var results:Array=[]
 for species:String in ["S53","S59","S63"]:
  var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
  var build= suite._command(s,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":[36,72]})
  var id:String=suite._connection(s)
  suite._command(s,"connector_extend",{"connection_id":id,"floor_id":2})
  suite._add_actor(s,"nurse","S49",[52,84],1)
  suite._add_actor(s,"patient",species,[41,83],1)
  suite._add_actor(s,"family",species,[60,84],1)
  var formation:Dictionary=ConvoyTrail.formation(s.space,s.world,"nurse",["nurse","patient"])
  # This is a declared legal static formation boundary, not a claim of a
  # completed clinical journey. Both actual species dimensions are retained.
  s.world.facts.actors.patient.location.cell=formation.targets.patient.duplicate()
  s.world.touch();s.space.sync_actor(s.world,"patient")
  var initial_error:String=s.world.validate(suite.content)
  var formed:Dictionary=ConvoyTrail.create(s.space,s.world,"nurse",["nurse","patient"])
  var plan:Dictionary={}
  if formed.ok:plan=ConvoyPortal.plan(s.space,s.world,s.world.facts.connectors[id],"nurse",["nurse","patient"],formed.convoy)
  results.append({"species":species,"initial_validation":initial_error,"formation":formation,"created":formed,"portal":plan,"actual_body":suite.content.definition("species",species).body,"scope":"Geometry boundary only; no clinical journey completion or performance claim"})
  s.dispose()
 var args:=OS.get_cmdline_user_args()
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
 print(JSON.stringify(results));quit(0)
