extends "res://tests/acceptance/floor_guidance.gd"

func run_exit_cases(database: HospitalContent) -> Dictionary:
 _content=database
 var rows: Array=[]
 for mode: String in ["normal","rejoin","support_exit","group_follower"]:rows.append(_exit_boundary(mode))
 var ok: bool=true
 for row: Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"scope":"Explicit leaving-at-exit boundary, not a complete consultation. Normal/rejoin execute a subsequent full simulation step; support/group are cancellation refusal boundaries only."}

func _departures(events: Array) -> int:
 var count: int=0
 for event: SimEvent in events:
  if event.kind=="patient_departed":count+=1
 return count

func _exit_boundary(mode: String) -> Dictionary:
 var x: Dictionary=_base()
 var visit: Dictionary=_visit(x,"exit_"+mode,[40,88])
 var actor: Dictionary=x.world.facts.actors[visit.actor_id]
 var exit: Array=x.space.exit_cell(x.world,actor)
 # Legal initial boundary placement, before any advancement in this fixture.
 actor.location.cell=exit.duplicate();x.world.touch();x.space.sync_actor(x.world,actor.id)
 var departure_accepted: bool=x.c.depart_visit(x.world,visit.id,"referred")
 x.c.take_events()
 var request: String=""
 if mode!="normal":
  request=x.space.request_move(x.world,actor.id,1,[float(exit[0])+1.0,float(exit[1])])
  var move: Dictionary=x.world.facts.moves[actor.id]
  move.path=[{"kind":"floor","floor_id":1,"cell":exit.duplicate()}];move.cursor=0;move.route_pending=false
  if mode=="rejoin":
   move.detour={"phase":"rejoin","prefix_size":1,"resume_index":0,"original_path":move.path.duplicate(true),"direction":[1,0],"backtrack":[],"back_cursor":-1}
   x.space.movement._route_checks[actor.id]={"boundary_probe":true}
   x.space.movement._route_failures[actor.id]={"boundary_probe":true}
  elif mode=="support_exit":
   move.path[0].kind="support_exit"
  else:
   # Ownership boundary only: the partial convoy is never advanced.
   var owner: String="guide_nurse"
   x.world.facts.moves.erase(actor.id)
   move.actor_id=owner;move.members=[owner,actor.id];move.convoy={}
   x.world.facts.moves[owner]=move
   x.space.movement._register_members(move)
 var before_moves: Dictionary=x.world.facts.moves.duplicate(true)
 x.c.dispatch(x.world)
 var event_count: int=_departures(x.c.take_events())
 var should_depart: bool=mode in ["normal","rejoin"]
 var cleaned: bool=not x.world.facts.moves.has(actor.id) and not x.space.movement._pending_routes.has(actor.id) and not x.space.movement._route_checks.has(actor.id) and not x.space.movement._route_failures.has(actor.id)
 var phase: String=visit.phase
 var location: Dictionary=actor.location.duplicate(true)
 var refusal_preserved: bool=x.world.facts.moves==before_moves and actor.location.kind=="floor" and visit.phase=="leaving"
 var world: WorldState=x.world
 _dispose(x)
 var full_step_done: bool=false
 if should_depart:
  var sim:=HospitalSimulation.new(world,_content)
  var tick_result: TickResult=sim.step()
  event_count+=_departures(tick_result.facts)
  event_count+=_departures(sim.clinic.take_events())
  sim.clinic.dispatch(world)
  event_count+=_departures(sim.clinic.take_events())
  full_step_done=true
  sim.dispose()
 var ok: bool=departure_accepted and request.is_empty()
 if should_depart:ok=ok and phase=="departed" and location.kind=="outside" and cleaned and event_count==1 and full_step_done
 else:ok=ok and refusal_preserved and event_count==0
 return {"case":mode,"ok":ok,"departure_accepted":departure_accepted,"request_error":request,"phase":phase,"location":location,"move_and_runtime_routes_cleared":cleaned,"refusal_preserved":refusal_preserved,"departure_events":event_count,"subsequent_full_step":full_step_done}
