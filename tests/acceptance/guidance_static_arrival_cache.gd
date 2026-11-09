extends "res://tests/acceptance/floor_guidance.gd"
func run_rules(database:HospitalContent)->Dictionary:
 _content=database
 var cases:Array=[]
 for from_lift:bool in [false,true]:
  var x:Dictionary=_base(false,true)
  var start:Array=x.world.facts.connectors.lift.anchor.duplicate() if from_lift else x.world.facts.entry.cell.duplicate()
  var visit:Dictionary=_visit(x,"warm_arrival",start)
  var actor:Dictionary=x.world.facts.actors[visit.actor_id]
  var before:Dictionary=x.world.facts.duplicate(true)
  var warm:Dictionary=x.g.prepare_static_routes(x.world,1)
  var unchanged:bool=x.world.facts==before
  var point:Dictionary=x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)
  var hits:int=int(x.space.query_counts.static_path_hits)
  var builds:int=int(x.space.query_counts.static_path_builds)
  # Real exact-floor dispatch API from a legal entry/landing boundary input.
  # This tests route construction, not a simulated elevator ride or full walk.
  var route:Dictionary=x.space.navigation.exact_floor_route(x.world,actor,1,point.cell)
  var checks:Dictionary={"loading_preserves_facts":unchanged,"entry_warmed":int(warm.entry_anchors)==1,"lift_warmed":int(warm.lift_anchors)==1,"actual_snake_goal":not point.is_empty(),"route_ok":route.get("ok",false),"actual_route_cache_hit":int(x.space.query_counts.static_path_hits)>hits,"no_new_path_build":int(x.space.query_counts.static_path_builds)==builds,"no_queue_claim":not x.g.state(x.world,visit.id).has("queue_seq")}
  cases.append({"case":"lift_boundary" if from_lift else "entry_boundary","ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"warm":warm,"goal":point.cell,"service_cell":x.space.facility_layout(x.world,"guide").patient_cell,"route_reason":route.get("reason","")})
  _dispose(x)
 return {"ok":cases.all(func(c:Dictionary)->bool:return c.ok),"cases":cases,"scope":"Read-only loading and exact-floor first-leg cache reuse from entry/landing boundary inputs; no claim of whole journey completion."}
