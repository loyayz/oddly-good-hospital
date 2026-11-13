extends "res://tests/acceptance/simple_transit.gd"
# Unchanged legal legacy convoy input; records actual terminal facts on failure.
func _run()->void:
 suite.content=HospitalContent.new()
 var sim:HospitalSimulation=suite._transit_fixture()
 var input:Dictionary=_start(sim,true)
 var initial_validation:String=sim.world.validate(suite.content)
 var args:=OS.get_cmdline_user_args()
 if not args.is_empty():FileAccess.open(args[0]+".input.bin",FileAccess.WRITE).store_var(sim.world.freeze(),true)
 var result:Dictionary=_drive(sim,input.target) if input.ok else {"ok":false,"input":input}
 result.input=input;result.initial_validation=initial_validation;result.ok=result.ok and initial_validation.is_empty()
 result.connector=sim.world.facts.connectors.duplicate(true)
 result.moves=sim.world.facts.moves.duplicate(true)
 result.actors=sim.world.facts.actors.duplicate(true)
 if not args.is_empty():
  FileAccess.open(args[0]+".final.bin",FileAccess.WRITE).store_var(sim.world.freeze(),true)
  FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 sim.dispose();print(JSON.stringify(result));quit(0 if result.ok else 1)
