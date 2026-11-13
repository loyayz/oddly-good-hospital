extends "res://tests/acceptance/directional_elevator_contract.gd"
func run()->void:
 var args:=OS.get_cmdline_user_args();var queued:bool=args.size()>1 and args[1]=="queued"
 suite.content=HospitalContent.new();var s:=fixture();var id:String=suite._connection(s);var c:Dictionary=s.world.facts.connectors[id]
 suite._add_actor(s,"person","S49",[42,80],1)
 var reason:String=s.space.request_move(s.world,"person",2,[45,82]);var found:bool=false
 for i:int in 600:
  suite._movement_tick(s)
  var has_queue:bool=c.get("landing_queues",{}).values().any(func(line:Array)->bool:return not line.is_empty())
  if c.phase=="idle" and (has_queue and c.riders.is_empty() if queued else not c.riders.is_empty()):found=true;break
 var before:Dictionary=s.world.freeze()
 if not args.is_empty():FileAccess.open(args[0]+".input.bin",FileAccess.WRITE).store_var(before,true)
 var result:Dictionary={"ok":false,"actual_boundary":found,"boundary_kind":"arrived_queue_idle" if queued else "loaded_idle","request_reason":reason}
 if found:
  var r:CommandResult=suite._command(s,"connector_remove",{"connection_id":id})
  result.command=r.to_record();result.rejected=not r.accepted
  result.original_connector_preserved=s.world.facts.connectors==before.connectors
  result.original_people_preserved=s.world.facts.actors==before.actors and s.world.facts.moves==before.moves
  result.ledger_preserved=s.world.facts.ledger==before.ledger
  result.validation=s.world.validate(suite.content)
  result.ok=result.rejected and result.original_connector_preserved and result.original_people_preserved and result.ledger_preserved and result.validation.is_empty()
 if not args.is_empty():
  FileAccess.open(args[0]+".final.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
  FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 s.dispose();print(JSON.stringify(result));quit(0 if result.ok else 1)
