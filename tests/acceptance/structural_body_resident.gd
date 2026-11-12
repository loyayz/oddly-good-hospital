extends RefCounted
class TinyCache extends NavigationCache:
 func _trim(_target: int, counts: Dictionary={}) -> void:super._trim(1,counts)
func _total_ok(c: NavigationCache, target: int=134217728) -> bool:
 var body: int=0;var graph: int=0;var query: int=0;var floor_charge: int=0;var source: int=0
 for e: Dictionary in c._body_entries.values():body+=int(e.charge)
 for e: Dictionary in c._entries.values():graph+=int(e.charge);query+=int(e.get("query_charge",0))
 for e: Dictionary in c._floor_geometries.values():floor_charge+=int(e.charge)
 for e: Dictionary in c._sources.values():source+=int(e.charge)
 return body==c._body_charged and graph==c._charged and query==c._query_charged and floor_charge==c._floor_charged and source==c._source_charged and c.total_charge()<=target and mini(mini(body,graph),mini(query,mini(floor_charge,source)))>=0
func _cold(content: HospitalContent,w: WorldState,a: Dictionary) -> RouteClearance:
 var s: HospitalSpace=HospitalSpace.new(content)
 return RouteClearance.new(s,w,a,1,[],{},false,s._navigation.floor_source(s,w,1))
func _equivalent(a: RouteClearance,b: RouteClearance) -> bool:
 if a._size!=b._size or a._height_m!=b._height_m or a._doors!=b._doors:return false
 for y: int in range(65,90):
  for x: int in range(33,60):
   if a.reason(Vector2i(x,y))!=b.reason(Vector2i(x,y)):return false
 return true
func _temporary(c: NavigationCache,s: HospitalSpace,facts: Dictionary) -> WeakRef:
 var w: WorldState=WorldState.new(facts.duplicate(true))
 c.static_body(s,w,1,w.facts.actors.body_actor)
 return weakref(w)
func _lru(content: HospitalContent,w: WorldState,a: Dictionary,body_first: bool) -> Dictionary:
 var s: HospitalSpace=HospitalSpace.new(content);var c: NavigationCache=s._navigation
 var proxy: Dictionary=a.duplicate(true);proxy._convoy_size=2
 if body_first:
  s.navigation.structural_clearance(w,a,1);c.graph(s,w,1,proxy,[],{})
 else:
  c.graph(s,w,1,proxy,[],{});s.navigation.structural_clearance(w,a,1)
 var body_charge: int=c._body_charged;var graph_charge: int=c._charged+c._query_charged
 var target: int=c._floor_charged+c._source_charged+maxi(body_charge,graph_charge)
 var both: bool=not c._body_entries.is_empty() and not c._entries.is_empty()
 c._trim(target)
 var correct: bool=c._body_entries.is_empty() and not c._entries.is_empty() if body_first else c._entries.is_empty() and not c._body_entries.is_empty()
 var sums: bool=_total_ok(c,target);c._trim(0)
 return {"both_before":both,"oldest_evicted":correct,"accounted":sums,"zero_trim":c.total_charge()==0 and c._entries.is_empty() and c._body_entries.is_empty() and c._sources.is_empty() and c._floor_geometries.is_empty(),"target":target,"body_charge":body_charge,"graph_charge":graph_charge}
func run(suite: RefCounted) -> Dictionary:
 var sim: HospitalSimulation=suite._fixture();suite._add_actor(sim,"body_actor","S49",[35,70]);suite._add_actor(sim,"body_other","S49",[40,80])
 var w: WorldState=sim.world;var a: Dictionary=w.facts.actors.body_actor;var s: HospitalSpace=HospitalSpace.new(suite.content);var c: NavigationCache=s._navigation;var checks: Dictionary={"initial_world_valid":w.validate(suite.content).is_empty()};var before: Dictionary=w.freeze()
 var q: RouteClearance=s.navigation.structural_clearance(w,a,1);var again: RouteClearance=s.navigation.structural_clearance(w,a,1)
 checks.no_graph_resident_hit=c._entries.is_empty() and c._body_entries.size()==1 and q==again and c.body_stats.builds==1 and c.body_stats.hits==1
 checks.static_cold_equal=_equivalent(q,_cold(suite.content,w,a)) and not q.source.has("occupancy") and q._reservations.is_empty() and before==w.freeze()
 var proxy: Dictionary=a.duplicate(true);proxy._convoy_body=s.body(a).duplicate(true);proxy._convoy_body.width_m=float(proxy._convoy_body.width_m)+0.01
 var full: RouteClearance=s.navigation.structural_clearance(w,proxy,1)
 checks.same_id_full_body_separate=full!=q and _equivalent(full,_cold(suite.content,w,proxy))
 proxy=a.duplicate(true);proxy._convoy_size=s.clearance(a)
 var explicit: RouteClearance=s.navigation.structural_clearance(w,proxy,1)
 checks.field_presence_separate=explicit!=q and _equivalent(explicit,q)
 proxy._convoy_size=s.clearance(a)+1
 var wide: RouteClearance=s.navigation.structural_clearance(w,proxy,1)
 checks.proxy_size_separate=wide._size==s.clearance(a)+1 and wide!=explicit and _equivalent(wide,_cold(suite.content,w,proxy))
 proxy=a.duplicate(true);proxy.posture="lying"
 var lying: RouteClearance=s.navigation.structural_clearance(w,proxy,1)
 checks.posture_separate=lying!=q and _equivalent(lying,_cold(suite.content,w,proxy))
 var entries: int=c._body_entries.size()
 var group: RouteClearance=s.navigation.structural_clearance(w,a,1,[a.id,"body_other"],{"body_other":[1,0]})
 var offset: RouteClearance=s.navigation.structural_clearance(w,a,1,[],{"unused":[0,0]})
 checks.group_offset_fallback=c._body_entries.size()==entries and group._members.size()==1 and offset!=q
 var restored: WorldState=WorldState.new(w.freeze());var restored_actor: Dictionary=restored.facts.actors.body_actor
 checks.equal_cross_world=s.navigation.structural_clearance(restored,restored_actor,1)==q
 restored.facts.floors.overrides["1"].blocked.append([36,70]);restored.touch()
 var edited: RouteClearance=s.navigation.structural_clearance(restored,restored_actor,1)
 checks.static_replace=edited!=q and not edited.reason(Vector2i(36,70)).is_empty() and q.reason(Vector2i(36,70)).is_empty() and _total_ok(c)
 var matching: WorldState=WorldState.new(w.freeze())
 var matching_query: RouteClearance=s.navigation.structural_clearance(matching,matching.facts.actors.body_actor,1)
 var different: WorldState=WorldState.new(w.freeze());different.facts.floors.overrides["1"].blocked.append([37,70])
 checks.same_revision_different_world=different.geometry_revision==matching.geometry_revision and matching_query.reason(Vector2i(37,70)).is_empty() and not s.navigation.structural_clearance(different,different.facts.actors.body_actor,1).reason(Vector2i(37,70)).is_empty()
 var back: RouteClearance=s.navigation.structural_clearance(w,a,1)
 checks.return_original_source=_equivalent(back,q) and _total_ok(c)
 # Permission test uses the real reservation owner API, not cached metadata.
 var built: CommandResult=suite._command(sim,"build_facility",{"id":"body_machine","definition_id":"M37","floor_id":1,"cell":[46,76]})
 var reserve: String=sim.space.reserve_facility(w,"body_machine","body_other","body_other") if built.accepted else "build failed"
 var permission_space: HospitalSpace=HospitalSpace.new(suite.content)
 var static_before: RouteClearance=permission_space.navigation.structural_clearance(w,a,1)
 var denied: Array=RouteClearance.capture_reservation_regions(w,a.id,1)
 var live_before: RouteClearance=permission_space._navigation.clearance(permission_space,w,1,a)
 permission_space.grant_facility_access(w,"body_machine",a.id)
 var live_after: RouteClearance=permission_space._navigation.clearance(permission_space,w,1,a)
 var allowed: Array=RouteClearance.capture_reservation_regions(w,a.id,1)
 checks.live_permission_not_cached=built.accepted and reserve.is_empty() and denied.size()>allowed.size() and live_before._reservations.size()>live_after._reservations.size() and _equivalent(static_before,permission_space.navigation.structural_clearance(w,a,1))
 var held: RouteClearance=s.navigation.structural_clearance(w,a,1);var charged: int=c._body_charged
 c._trim_source_payloads(0)
 checks.source_only_eviction=c._sources.is_empty() and c._source_charged==0 and c._body_charged==charged and _total_ok(c)
 # Retire only the raw floor owner, just as the existing floor-static pressure case.
 c._floor_geometries.clear();c._floor_charged=0
 checks.floor_owner_released_body_still_accounted=c._body_charged==charged and _total_ok(c) and _equivalent(held,_cold(suite.content,w,a))
 var weak: WeakRef=_temporary(c,s,w.freeze());c._prune_sources()
 checks.no_strong_world=weak.get_ref()==null and _total_ok(c)
 var first: Dictionary=_lru(suite.content,w,a,true);var second: Dictionary=_lru(suite.content,w,a,false)
 checks.joint_lru_graph_newer=first.both_before and first.oldest_evicted and first.accounted and first.zero_trim
 checks.joint_lru_body_newer=second.both_before and second.oldest_evicted and second.accounted and second.zero_trim
 var tiny: HospitalSpace=HospitalSpace.new(suite.content);tiny._navigation=TinyCache.new()
 var borrowed: RouteClearance=tiny.navigation.structural_clearance(w,a,1)
 checks.overbudget_complete_unretained=_equivalent(borrowed,_cold(suite.content,w,a)) and tiny._navigation._body_entries.is_empty() and tiny._navigation.total_charge()==0 and _total_ok(tiny._navigation,1)
 c._trim(0);checks.zero_trim=c.total_charge()==0 and _total_ok(c,0)
 checks.final_world_valid=w.validate(suite.content).is_empty()
 var result: Dictionary={"ok":not checks.values().has(false),"checks":checks,"lru_graph_newer":first,"lru_body_newer":second,"validation":w.validate(suite.content)}
 sim.dispose();return result
