extends SceneTree
class ExtensionSpace extends HospitalSpace:
 pass
func _initialize()->void:call_deferred("run")
func run()->void:
 var suite=preload("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
 var sim:HospitalSimulation=suite._transit_fixture();suite._add_actor(sim,"proof_actor","S06",[44.25,80])
 var w:WorldState=sim.world;var s:HospitalSpace=sim.space;var a:Dictionary=w.facts.actors.proof_actor
 var q:Dictionary=s.navigation.exact_floor_route(w,a,1,[49.75,84],[],{})
 if not q.get("ok",false):print(q);sim.dispose();quit(1);return
 var m:Dictionary={"actor_id":a.id,"target_floor":1,"target_cell":[49.75,84],"request_sequence":123,"path":q.path.duplicate(true),"cursor":0,"members":[a.id],"offsets":{}}
 var checks:Dictionary={}
 var cold:RouteClearance=RouteClearance.new(s,w,a,1,[],{},false)
 var previous:Vector2=Vector2(a.location.cell[0],a.location.cell[1]);var all_clear:bool=true
 for segment:Dictionary in m.path:
  var target:Vector2=Vector2(segment.cell[0],segment.cell[1]);all_clear=all_clear and cold.sweep_reason(previous,target).is_empty();previous=target
 checks.planner_path_matches_independent_full_sweep=all_clear
 var extension:HospitalSpace=ExtensionSpace.new(suite.content)
 var extension_quote:Dictionary=extension.navigation.exact_floor_route(w,a,1,[49.75,84],[],{})
 checks.extension_keeps_cold_validation=extension_quote.ok and not extension_quote.has("static_proof")
 checks.accept=s.movement._accept_static_proof(w,a,m,q.static_proof)
 var before:int=int(s.query_counts.route_revalidations)
 checks.handoff_does_not_repeat_full_sweep=s.movement._active_route_clear(w,a,m,{}) and int(s.query_counts.route_revalidations)==before
 var other:WorldState=WorldState.new(w.freeze())
 checks.reject_other_world=not s.movement._accept_static_proof(other,other.facts.actors[a.id],m,q.static_proof)
 var changed:Dictionary=m.duplicate(true);changed.path[0].cell=[40,80]
 checks.reject_changed_path=not s.movement._accept_static_proof(w,a,changed,q.static_proof)
 a.body_binding_id="B_S06_D04_M04";w.touch()
 checks.reject_changed_body=not s.movement._accept_static_proof(w,a,m,q.static_proof)
 a.erase("body_binding_id");a.posture="lying";w.touch()
 checks.reject_changed_posture=not s.movement._accept_static_proof(w,a,m,q.static_proof)
 a.posture="standing";w.touch()
 w.facts.floors.overrides["1"].blocked.append([49,84]);w.touch()
 checks.reject_changed_geometry=not s.movement._accept_static_proof(w,a,m,q.static_proof)
 checks.active_route_rechecks_changed_geometry=not s.movement._active_route_clear(w,a,m,{}) and int(s.query_counts.route_revalidations)>before
 w.facts.floors.overrides["1"].blocked.erase([49,84]);w.touch()
 var restored:HospitalSpace=HospitalSpace.new(suite.content)
 var old_count:int=int(restored.query_counts.route_revalidations)
 checks.cold_restore_full_validation=restored.movement._active_route_clear(w,a,m,{}) and int(restored.query_counts.route_revalidations)>old_count
 var fresh:Dictionary=s.navigation.exact_floor_route(w,a,1,[49.75,84],[],{})
 s._navigation._trim(0,s.query_counts)
 checks.eviction_not_false_permission=s.movement._accept_static_proof(w,a,m,fresh.static_proof)
 var detour:Dictionary=m.duplicate(true);detour.detour={"phase":"aside"}
 checks.detour_not_unconditionally_proven=not s.movement._accept_static_proof(w,a,detour,fresh.static_proof)
 var retarget:Dictionary=m.duplicate(true);retarget.target_cell=[48,85]
 checks.retarget_rejects_old_proof=not s.movement._accept_static_proof(w,a,retarget,fresh.static_proof)
 var group:Dictionary=m.duplicate(true);group.members.append("other")
 checks.members_reject_old_proof=not s.movement._accept_static_proof(w,a,group,fresh.static_proof)
 var shifted:Dictionary=m.duplicate(true);shifted.offsets[a.id]=[1,0]
 checks.offset_rejects_old_proof=not s.movement._accept_static_proof(w,a,shifted,fresh.static_proof)
 var convoy:Dictionary=m.duplicate(true);convoy.convoy={}
 checks.convoy_rejects_single_proof=not s.movement._accept_static_proof(w,a,convoy,fresh.static_proof)
 var other_floor:Dictionary=m.duplicate(true);other_floor.target_floor=2
 checks.cross_floor_rejects_single_proof=not s.movement._accept_static_proof(w,a,other_floor,fresh.static_proof)
 var live:HospitalSimulation=suite._fixture();suite._add_actor(live,"live_proof","S49",[44.25,80])
 var reason:String=live.space.request_floor_move(live.world,"live_proof",1,[49.75,84])
 for step:int in 120:
  suite._movement_tick(live)
  if not live.world.facts.moves.has("live_proof"):break
 checks.real_dispatch_handoff=int(live.space.query_counts.get("route_proof_handoffs",0))>0
 checks.real_dispatch_arrival=reason.is_empty() and live.space.at(live.world,"live_proof",1,[49.75,84]) and not live.world.facts.moves.has("live_proof")
 live.dispose()
 var ordinary:Dictionary=door_handoff(suite.content,false)
 var expanded:Dictionary=door_handoff(suite.content,true)
 checks.real_dispatch_ordinary_door=ordinary.ok
 checks.real_dispatch_expanded_door_release=expanded.ok
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"checks":checks,"door_ordinary":ordinary,"door_expanded":expanded}));sim.dispose();quit(0 if ok else 1)

func door_handoff(content:HospitalContent,expanded:bool)->Dictionary:
 var helper=preload("res://tests/acceptance/ordinary_door_passage.gd").new();helper.suite.content=content
 var setup:Dictionary=helper._setup(false);var sim:HospitalSimulation=setup.sim
 if setup.door.is_empty():sim.dispose();return {"ok":false,"reason":"no door"}
 var door:Dictionary=setup.door;var xx:float=float(door.cell[0]);var yy:float=float(door.cell[1])
 helper.suite._add_actor(sim,"door_proof","S01" if expanded else "S49",[xx,yy+3])
 var reason:String=sim.space.request_floor_move(sim.world,"door_proof",1,[xx,yy-4])
 var held:bool=false
 for step:int in 240:
  helper.suite._movement_tick(sim)
  held=held or sim.world.facts.adaptations.has(door.id)
  if not sim.world.facts.moves.has("door_proof"):break
 helper.suite._movement_tick(sim)
 var arrived:bool=sim.space.at(sim.world,"door_proof",1,[xx,yy-4]) and not sim.world.facts.moves.has("door_proof")
 var handoffs:int=int(sim.space.query_counts.get("route_proof_handoffs",0))
 var released:bool=not sim.world.facts.adaptations.has(door.id)
 var used:bool=bool(door.get("used",false))
 var result:Dictionary={"ok":reason.is_empty() and arrived and handoffs>0 and released and used and (held if expanded else not held),"request":reason,"arrived":arrived,"handoffs":handoffs,"held_seen":held,"released":released,"used":used}
 sim.dispose();return result
