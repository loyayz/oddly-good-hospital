extends RefCounted
class ObserveMovement extends HospitalMovement:
 var target:Array=[]
 var evidence:Dictionary={}
 func _move_step(world:WorldState,actor:Dictionary,journey:Dictionary,segment:Dictionary)->HospitalMovement.MotionResult:
  var result:HospitalMovement.MotionResult=super._move_step(world,actor,journey,segment)
  if actor.id=="a_sweeper" and evidence.is_empty() and result.actual_motion!=Vector2.ZERO:
   var other:Dictionary=world.facts.actors.z_walker
   var endpoint:Rect2=space._actor_rect(other,ConvoyTrail.point(target))
   var historical:BodyIndex.Record=_accepted_sweeps.get("a_sweeper")
   var projection:Dictionary=space._dynamic_route_query(world,other,1,[],{})
   var quote:Dictionary={"ok":_local_path_clear(world,other,[{"kind":"floor","floor_id":1,"cell":target}])}
   quote.erase("static_proof")
   var actual_step:HospitalMovement.MotionResult=super._move_step(world,other,world.facts.moves.z_walker,{"kind":"floor","floor_id":1,"cell":target})
   evidence={"real_accepted_sweep":historical!=null,"projection_bbox_hits":projection.index.intersects(1,endpoint,""),"current_body_clear":not space._actor_index.intersects(1,endpoint,"z_walker",["z_walker"]),"stationary_endpoint_narrow_clear":not BodySweep.intersects(endpoint,endpoint,historical.sweep_from,historical.sweep_to),"quote":quote,"actual_walker_step":str(actual_step.actual_motion),"actual_walker_blocked":actual_step.blocked,"blockers":actual_step.blocker_actor_ids}
  return result
func run(content:HospitalContent)->Dictionary:
 var helper:RefCounted=load("res://tests/acceptance/space.gd").new();helper.content=content
 var sim:HospitalSimulation=helper._fixture()
 helper._add_actor(sim,"a_sweeper","S49",[40,74]);helper._add_actor(sim,"z_walker","S49",[35,80])
 var a:Dictionary=sim.world.facts.actors.a_sweeper;var b:Dictionary=sim.world.facts.actors.z_walker
 var found:bool=false;var target:Array=[];var input:Dictionary={}
 for binding:Dictionary in content.catalog.treatment_bindings:
  var sample:Dictionary=a.duplicate();sample.species_id=binding.species_id;sample.body_binding_id=binding.id;sample.facing=0.0
  if sim.space.clearance(sample)>2 or float(sim.space.body(sample).height_m)>6.5:continue
  var end_actor:Dictionary=sample.duplicate();end_actor.facing=PI*0.5
  var end:Vector2=sim.space.movement._step_toward(Vector2(40,74),Vector2(41,74),sim.space.walking_speed(sample)*WorldState.TICK_SECONDS)
  var from_rect:Rect2=sim.space._actor_rect(sample,Vector2(40,74));var to_rect:Rect2=sim.space._actor_rect(end_actor,end)
  for ix:int in range(760,860):
   for iy:int in range(1420,1560):
    var p:=Vector2(float(ix)/20.0,float(iy)/20.0);var endpoint:Rect2=sim.space._actor_rect(b,p)
    if not endpoint.intersects(from_rect.merge(to_rect),false) or endpoint.intersects(to_rect,false) or BodySweep.intersects(endpoint,endpoint,from_rect,to_rect):continue
    for offset:Vector2 in [Vector2(-0.1,0),Vector2(0.1,0),Vector2(0,-0.1),Vector2(0,0.1)]:
     var start:=p+offset;var initial:Rect2=sim.space._actor_rect(b,start)
     if initial.intersects(from_rect,false) or initial.intersects(to_rect,false) or BodySweep.intersects(initial,endpoint,from_rect,to_rect):continue
     a.species_id=binding.species_id;a.body_binding_id=binding.id;a.facing=0.0;b.location.cell=[start.x,start.y];b.facing=atan2(-offset.x,-offset.y)
     target=[p.x,p.y];input={"binding":binding.id,"walker_start":b.location.cell.duplicate(),"walker_target":target,"sweeper_before":str(from_rect),"sweeper_after":str(to_rect)};found=true;break
    if found:break
   if found:break
  if found:break
 if not found:sim.dispose();return {"ok":false,"reason":"No legal real-sweep witness found; not covered."}
 sim.world.touch(false);sim.space.sync_actor(sim.world,"a_sweeper");sim.space.sync_actor(sim.world,"z_walker")
 var observed:ObserveMovement=ObserveMovement.new(sim.space);observed.target=target;sim.space.movement=observed
 var r1:String=sim.space.request_move(sim.world,"a_sweeper",1,[41,74]);var r2:String=sim.space.request_move(sim.world,"z_walker",1,target)
 # Ordinary advance creates the accepted sweep. The hook only observes at
 # that real phase boundary and performs the walker's real collision attempt.
 sim.space.advance(sim.world)
 var evidence:Dictionary=observed.evidence
 var checks:bool=not evidence.is_empty()
 if checks:checks=evidence.real_accepted_sweep and evidence.projection_bbox_hits and evidence.current_body_clear and evidence.stationary_endpoint_narrow_clear and evidence.quote.get("ok",false) and not evidence.actual_walker_blocked and sim.space.at(sim.world,"z_walker",1,target)
 var result:Dictionary={"ok":r1.is_empty() and r2.is_empty() and checks and sim.world.validate(content).is_empty(),"requests":[r1,r2],"input":input,"evidence":evidence,"validation":sim.world.validate(content),"scope":"Real advance-produced accepted sweep; mid-phase instrumentation, real walker _move_step. No handcrafted sweep records. Current-body endpoint occupancy is checked separately from historical sweep bbox."}
 sim.dispose();return result
