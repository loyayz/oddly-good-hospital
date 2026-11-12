extends RefCounted

class CountingNavigation:
 extends HospitalNavigation
 var acquisitions: int = 0
 var geometries: Array[RouteClearance] = []
 func structural_clearance(world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
  acquisitions += 1
  var result: RouteClearance = super.structural_clearance(world,actor,floor_id,members,offsets)
  geometries.append(result)
  return result

# A local-return decision boundary, not a replacement for actual movement tests.
# Every original candidate cell initially has a stationary body, so no local
# link may reach it; a return intention must retain collision checks.
func run(suite: RefCounted) -> Dictionary:
 var sim: HospitalSimulation = suite._fixture()
 suite._add_actor(sim,"walker","S49",[35,70])
 var path: Array = []
 for x: int in range(36,46):
  suite._add_actor(sim,"blocker_"+str(x),"S49",[x,70])
  path.append({"kind":"floor","floor_id":1,"cell":[x,70]})
 var movement: Dictionary = {"actor_id":"walker","detour":{"original_path":path}}
 var navigation: CountingNavigation = CountingNavigation.new(sim.space)
 sim.space.navigation = navigation
 var actor: Dictionary = sim.world.facts.actors.walker
 var original: Dictionary = sim.world.freeze()
 var blocked: Dictionary = sim.space.movement._detour_return_path(sim.world,actor,movement,Vector2(35,70))
 var checks: Dictionary = {"all_occupied_targets_rejected":blocked.is_empty(),"one_geometry_for_many_candidates":navigation.acquisitions==1,"no_graph_build":sim.space._navigation._entries.is_empty(),"decision_readonly":sim.world.freeze()==original}
 var blocked_acquisitions: int = navigation.acquisitions
 # Each call reacquires current static proof; dynamic body/path results are not cached.
 for x: int in range(36,46): sim.world.facts.actors.erase("blocker_"+str(x))
 sim.world.touch()
 var before: int = navigation.acquisitions
 original = sim.world.freeze()
 var released: Dictionary = sim.space.movement._detour_return_path(sim.world,actor,movement,Vector2(35,70))
 checks.released_actor_uses_first_original_cell = released.get("index",-1)==0
 checks.new_call_acquires_again = navigation.acquisitions==before+1
 checks.release_decision_readonly = sim.world.freeze()==original
 # A new static obstacle blocks the common first leg. The return helper
 # must reject it; actual side movement belongs to the movement state machine.
 sim.world.facts.floors.overrides["1"].blocked.append([36,70])
 sim.world.touch()
 before = navigation.acquisitions
 original = sim.world.freeze()
 var edited: Dictionary = sim.space.movement._detour_return_path(sim.world,actor,movement,Vector2(35,70))
 checks.static_edit_rejects_blocked_first_leg = edited.is_empty()
 var flow: Dictionary = _edited_real_flow(suite)
 checks.static_edit_real_side_and_nearest_rejoin = flow.ok
 checks.static_edit_reacquired = navigation.acquisitions==before+1
 checks.static_edit_readonly = sim.world.freeze()==original
 # A body change likewise belongs to the next proof, even with unchanged XY.
 actor.species_id = "S08"
 sim.world.touch()
 before = navigation.acquisitions
 var fresh: HospitalSpace = HospitalSpace.new(suite.content)
 var expected: Dictionary = fresh.movement._detour_return_path(sim.world,actor,movement,Vector2(35,70))
 var changed_body: Dictionary = sim.space.movement._detour_return_path(sim.world,actor,movement,Vector2(35,70))
 checks.changed_body_cold_equal = changed_body==expected and navigation.geometries.back()._size==sim.space.clearance(actor)
 checks.changed_body_reacquired_once = navigation.acquisitions==before+1
 var restored: WorldState = WorldState.new(sim.world.freeze())
 before = navigation.acquisitions
 original = restored.freeze()
 var restored_result: Dictionary = sim.space.movement._detour_return_path(restored,restored.facts.actors.walker,movement,Vector2(35,70))
 checks.restored_world_fresh_readonly = restored_result==expected and restored.freeze()==original
 checks.restored_world_reacquired_once = navigation.acquisitions==before+1
 before = navigation.acquisitions
 var empty: Dictionary = sim.space.movement._detour_return_path(sim.world,actor,{"actor_id":"walker","detour":{"original_path":[]}},Vector2(35,70))
 checks.empty_suffix_allocates_nothing = empty.is_empty() and navigation.acquisitions==before
 var ok: bool = true
 for passed: bool in checks.values(): ok = ok and passed
 var report: Dictionary = {"case":"query_local_detour_geometry","ok":ok,"checks":checks,"blocked_geometry_acquisitions":blocked_acquisitions,"original_candidates":path.size(),"released_index":released.get("index",-1),"edited_index":edited.get("index",-1),"edited_real_flow":flow}
 sim.dispose()
 return report

func _edited_real_flow(suite: RefCounted) -> Dictionary:
 var sim:HospitalSimulation=suite._fixture();suite._add_actor(sim,"walker","S49",[35,70])
 var w:WorldState=sim.world;var s:HospitalSpace=sim.space;var a:Dictionary=w.facts.actors.walker
 var reason:String=s.request_move(w,"walker",1,[45,70]);s.movement._dispatch_routes(w,1)
 var m:Dictionary=w.facts.moves.walker;m.cursor=s.movement._initial_route_cursor(a,m.path,w)
 var original:Array=m.path.slice(int(m.cursor)).duplicate(true)
 w.facts.floors.overrides["1"].blocked.append([36,70]);w.touch()
 var rejected:bool=s.movement._detour_return_path(w,a,{"actor_id":"walker","detour":{"original_path":original}},Vector2(35,70)).is_empty()
 s.movement._start_detour(w,a,m)
 var trace:Array=[];var safe:bool=true;var side_seen:bool=false;var first_rejoin:Array=[]
 for i:int in 200:
  var previous:Vector2=ConvoyTrail.point(a.location.cell)
  s.advance(w);w.facts.sim_tick+=1;w.touch(false)
  var now:Vector2=ConvoyTrail.point(a.location.cell)
  var geometry:RouteClearance=s.navigation.structural_clearance(w,a,1)
  safe=safe and geometry.sweep_reason(previous,now).is_empty()
  side_seen=side_seen or absf(now.y-70.0)>0.01
  var current:Dictionary=w.facts.moves.get("walker",{})
  if first_rejoin.is_empty() and side_seen and absf(now.y-70.0)<0.0001:first_rejoin=[now.x,now.y]
  trace.append({"tick":i,"cell":a.location.cell.duplicate(),"local_move":current.get("local_move",{}).duplicate(true)})
  if not w.facts.moves.has("walker"):break
 var result:Dictionary={"request":reason,"initial_return_rejects_wall":rejected,"side_seen":side_seen,"first_rejoin":first_rejoin,"safe_sweeps":safe,"arrived":s.at(w,"walker",1,[45,70]),"trace":trace,"validation":w.validate(suite.content)}
 result.ok=reason.is_empty() and rejected and side_seen and first_rejoin.size()==2 and ConvoyTrail.point(first_rejoin).distance_to(Vector2(37,70))<0.0001 and safe and result.arrived and result.validation.is_empty()
 sim.dispose()
 return result
