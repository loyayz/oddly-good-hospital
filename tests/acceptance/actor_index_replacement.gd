extends RefCounted

var observations: Array = []
var capture: Callable
func _save(name: String, value: Variant) -> void:
 if capture.is_valid(): capture.call(name,value)

func _query(label: String, world: WorldState, space: HospitalSpace, database: HospitalContent) -> bool:
 var before: Dictionary = world.freeze()
 _save(label+"-input",before)
 var validation: String = world.validate(database)
 space._ensure_actor_index(world)
 var probes: Array[Rect2] = [Rect2(43,79,3,3),Rect2(49,87,3,3),Rect2(0,0,96,96)]
 var rows: Array = []
 var ok: bool = validation.is_empty()
 # Independent literal standing S49 geometry: width/depth 0.7m, cell1.5m.
 # Every fixture actor is S49, standing, facing zero; no convoy in this matrix.
 for floor_id: int in [1,2,10000]:
  for rect: Rect2 in probes:
   var expected: Array[String] = []
   for id: String in world.facts.actors:
    var actor: Dictionary = world.facts.actors[id]
    if actor.location.kind!="floor" or int(actor.location.floor_id)!=floor_id: continue
    var origin: Vector2 = Vector2(actor.location.cell[0],actor.location.cell[1])
    var body: Rect2 = Rect2(origin+Vector2.ONE*(1.0-0.7/1.5)*0.5,Vector2.ONE*(0.7/1.5))
    if rect.intersects(body,false): expected.append(id)
   expected.sort()
   var actual: Array[String] = space._actor_index.candidates(floor_id,rect)
   rows.append({"floor":floor_id,"rect":rect,"expected":expected,"actual":actual})
   ok = ok and actual==expected
 ok = ok and before==world.freeze()
 observations.append({"label":label,"ok":ok,"validation":validation,"pure":before==world.freeze(),"rows":rows,"builds":space.query_counts.actor_index_builds})
 return ok

func run_case(suite: RefCounted, recorder: Callable = Callable()) -> Dictionary:
 capture=recorder
 var sim: HospitalSimulation = suite._fixture()
 suite._add_actor(sim,"index_subject","S49",[44,80])
 suite._add_actor(sim,"index_other","S49",[42,86])
 var w: WorldState=sim.world
 var original: Dictionary=w.freeze()
 var checks: Dictionary={}
 checks.initial=_query("initial",w,sim.space,suite.content)
 var builds: int=sim.space.query_counts.actor_index_builds
 checks.unchanged=_query("unchanged",w,sim.space,suite.content) and sim.space.query_counts.actor_index_builds==builds
 # Legal independent calculation boundary, not claimed as executed movement.
 var replacement: Dictionary=original.duplicate(true)
 replacement.actors.index_subject.location.cell=[50,88]
 replacement.actors.erase("index_other")
 replacement.actors["index_added"]=original.actors.index_other.duplicate(true)
 replacement.actors.index_added.id="index_added"
 w.facts=replacement
 checks.replacement_same_revision=w.revision==int(original.world_revision)
 checks.replacement=_query("replacement",w,sim.space,suite.content) and sim.space.query_counts.actor_index_builds==builds+1
 sim.space.begin_route_query(w)
 sim.space._ensure_actor_index(w)
 w.facts=original.duplicate(true)
 checks.restore_inside_new_scope=_query("restore_scope",w,sim.space,suite.content) and sim.space.query_counts.actor_index_builds==builds+2
 sim.space.end_route_query()
 var copied: WorldState=WorldState.new(original.duplicate(true))
 checks.copied_owner=_query("copied",copied,sim.space,suite.content)
 checks.return_owner=_query("return",w,sim.space,suite.content) and w.freeze()==original
 # sync_actor must rebuild all current actors, not only the requested identity.
 var sync_facts: Dictionary=original.duplicate(true)
 sync_facts.actors.index_subject.location.cell=[50,88]
 sync_facts.actors.index_other.location.cell=[44,80]
 w.facts=sync_facts
 sim.space.sync_actor(w,"index_subject")
 checks.sync_actor_rebuilds_entire_collection=_query("sync_replacement",w,sim.space,suite.content)
 # Replacing either side invalidates an exclusion capability captured earlier.
 for side: String in ["source","projection"]:
  w.facts=original.duplicate(true)
  var projected_facts: Dictionary=w.facts.duplicate()
  projected_facts.actors=w.facts.actors.duplicate()
  projected_facts.actors.index_other=w.facts.actors.index_other.duplicate(true)
  projected_facts.actors.index_other.location={"kind":"outside"}
  var projected: WorldState=WorldState.new(projected_facts)
  sim.space.begin_actor_exclusion_query(w,projected,["index_other"])
  sim.space._ensure_actor_index(projected)
  checks[side+"_borrow_initial"]=not sim.space._actor_exclusion_scope(projected).is_empty()
  if side=="source":
   w.facts=w.freeze()
   sim.space._ensure_actor_index(w)
  else:
   projected.facts=original.duplicate(true)
  _save(side+"-source-facts",w.freeze())
  checks[side+"_replacement_revokes_borrow"]=sim.space._actor_exclusion_scope(projected).is_empty()
  checks[side+"_replacement_query"]=_query(side+"_exclusion",projected,sim.space,suite.content)
  sim.space.end_route_query()
 # Old indexed world now exposes different actor storage. A new projection
 # sharing that new storage must not reuse the old indexed bodies.
 w.facts=original.duplicate(true)
 sim.space.begin_route_query(w)
 sim.space._ensure_actor_index(w)
 builds=sim.space.query_counts.actor_index_builds
 w.facts=sync_facts.duplicate(true)
 var shared: WorldState=WorldState.new(w.facts.duplicate())
 checks.stale_owner_shared_actors=_query("stale_shared_owner",shared,sim.space,suite.content) and sim.space.query_counts.actor_index_builds==builds+1
 sim.space.end_route_query()
 w.facts=original.duplicate(true)
 sim.space._ensure_actor_index(w)
 _save("pure-observations",observations)
 # Real move: preserve a genuinely progressed boundary, replace full facts with
 # that exact saved state at identical revision, then continue ordinary ticks.
 var request: String=sim.space.request_move(w,"index_subject",1,[46,80])
 suite._movement_tick(sim)
 var frozen: Dictionary=w.freeze()
 _save("moving-before-replacement",frozen)
 var position: Array=w.facts.actors.index_subject.location.cell.duplicate()
 var sequence: int=w.facts.moves.index_subject.request_sequence
 checks.real_progress=request.is_empty() and float(position[0])>44.0 and float(position[0])<46.0
 builds=sim.space.query_counts.actor_index_builds
 w.facts=frozen.duplicate(true)
 checks.full_replacement_exact=w.freeze()==frozen
 sim.space._ensure_actor_index(w)
 checks.moving_rebuilt=sim.space.query_counts.actor_index_builds==builds+1
 var trace: Array=[]
 var valid: bool=true
 for tick: int in 40:
  if not w.facts.moves.has("index_subject"): break
  valid=valid and int(w.facts.moves.index_subject.request_sequence)==sequence
  suite._movement_tick(sim)
  trace.append({"tick":w.sim_tick,"actors":w.facts.actors.duplicate(true),"moves":w.facts.moves.duplicate(true),"empty_sweeps":not sim.space.movement._sweep_index._has_current_records})
  valid=valid and not sim.space.movement._sweep_index._has_current_records
 checks.real_arrival=valid and not w.facts.moves.has("index_subject") and sim.space.at(w,"index_subject",1,[46,80]) and w.validate(suite.content).is_empty()
 _save("moving-trace",trace);_save("moving-final",w.freeze())
 sim.dispose()
 return {"ok":not checks.values().has(false),"checks":checks,"queries":observations,"actual_ticks_after_replacement":trace.size()}
