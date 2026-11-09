extends "res://tests/acceptance/floor_guidance.gd"
class ObserveGuidance extends HospitalFloorGuidance:
 var lookups:int=0
 func _queue_point(world:WorldState, actor_id:String,desk_id:String,visit_id:String="")->Dictionary:
  lookups+=1
  return super._queue_point(world,actor_id,desk_id,visit_id)
func run_rules(database:HospitalContent)->Dictionary:
 _content=database
 var x:Dictionary=_base()
 var old:HospitalFloorGuidance=x.g
 x.g=ObserveGuidance.new(_content,x.space);x.g.clinic=x.c;x.g.waiting=x.l
 x.c.floor_guidance=x.g;x.l.floor_guidance=x.g
 var visit:Dictionary=_visit(x,"frozen_tail",[35,94])
 var checked:int=0;var changed:bool=false;var arrived:bool=false;var early_number:bool=false
 for tick:int in 700:
  var before:Dictionary=x.world.facts.moves.get(visit.actor_id,{}).duplicate(true)
  var lookups:int=x.g.lookups
  var current:Dictionary=x.g.state(x.world,visit.id)
  if not before.is_empty() and before.get("floor_guidance_key","")==current.get("request_key","") and current.get("phase","")=="seek":
   x.g.prepare(x.world,visit,x.world.facts.tickets[visit.ticket_id])
   checked+=1
   var after:Dictionary=x.world.facts.moves.get(visit.actor_id,{})
   changed=changed or x.g.lookups!=lookups or after.get("target_cell",[])!=before.target_cell
   early_number=early_number or current.has("queue_seq")
  _step(x)
  if not x.g.state(x.world,visit.id).get("receipts",[]).is_empty():arrived=true;break
 var checks:Dictionary={"natural_trip_observed":checked>0,"no_tail_lookup_or_retarget_while_travelling":not changed,"no_remote_queue_number":not early_number,"real_service_completed":arrived,"valid":x.world.validate(_content).is_empty()}
 var result:Dictionary={"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"observed_steps":checked,"validation":x.world.validate(_content),"state":x.g.state(x.world,visit.id).duplicate(true)}
 _dispose(x)
 return result
