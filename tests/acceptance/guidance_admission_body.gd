extends "res://tests/acceptance/floor_guidance.gd"
func run_rules(database:HospitalContent)->Dictionary:
 _content=database
 var x:Dictionary=_base()
 var visit:Dictionary=_visit(x,"actual_admission",[35,94])
 var actor:Dictionary=x.world.facts.actors[visit.actor_id]
 var point:=Vector2(35,94)
 var body:Rect2=x.space._actor_rect(actor,point)
 var envelope:=Rect2(point,Vector2.ONE*x.space.clearance(actor))
 var margin:float=body.position.x-envelope.position.x
 var region:=Rect2(point,Vector2(margin*0.5,envelope.size.y))
 var reservation:Dictionary={"kind":"facility","floor_id":1,"actor_id":"other","staff_ids":[],"facility_id":"probe","regions":[[region.position.x,region.position.y,region.size.x,region.size.y]]}
 x.world.facts.adaptations["admission_probe"]=reservation
 var checks:Dictionary={"fixture_envelope_only":margin>0.0 and envelope.intersects(region,false) and not body.intersects(region,false)}
 checks.exact_body_admitted=x.g._queue_admission_clear(x.world,visit.actor_id,1,[35,94],actor.facing)
 reservation.regions=[[body.position.x,body.position.y,body.size.x,body.size.y]]
 x.world.touch()
 checks.real_overlap_rejected=not x.g._queue_admission_clear(x.world,visit.actor_id,1,[35,94],actor.facing)
 reservation.actor_id=visit.actor_id
 x.world.touch()
 checks.own_reservation_allowed=x.g._queue_admission_clear(x.world,visit.actor_id,1,[35,94],actor.facing)
 var result:Dictionary={"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"body":str(body),"envelope":str(envelope),"scope":"admission boundary only, not route proof"}
 _dispose(x)
 return result
