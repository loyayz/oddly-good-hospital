extends "res://tests/acceptance/guidance_queue_entry_boundary.gd"
func run_index()->Dictionary:
 _content=HospitalContent.new()
 var x: Dictionary=_entry_fixture()
 var probe: Dictionary=_visit(x,"probe",[40,85])
 var physical: Dictionary=_visit(x,"physical",[52,81])
 _visit(x,"fixed_a",[51,74]);_visit(x,"fixed_b",[51,75])
 x.world.touch(false)
 var actor: Dictionary=x.world.facts.actors[physical.actor_id]
 var ctx: Dictionary=Entry.context(x.space,x.world,"guide")
 var checks: Dictionary={};var comparisons: Array=[]
 actor.species_id="S01";actor.erase("body_binding_id")
 var origin: Rect2=x.space._actor_rect(actor,Vector2.ZERO)
 var door: Rect2=ctx.door_bounds[0]
 var pos: Vector2=Vector2(door.get_center().x-origin.get_center().x,door.end.y+origin.size.y*0.2-origin.position.y)
 # Center is outside room/door, but its leading edge intersects door.
 pos.y=door.end.y-origin.position.y-0.1
 actor.location.cell=[pos.x,pos.y];x.world.touch(false)
 var body: Rect2=x.space.body_rectangle(actor)
 checks.large_center_outside=body.get_center().y>door.end.y
 checks.large_body_touches=Entry.is_inside(ctx,x.space,actor,pos)
 checks.large_candidate_present=Entry._physical_candidates(x.space,x.world,ctx).has(actor.id)
 _compare(x,probe,comparisons,"large_crossing",false)
 actor.species_id="S49";actor.location.cell=[60,85];x.world.touch(false)
 var tick: int=x.world.sim_tick
 _compare(x,probe,comparisons,"before_same_tick_entry",true)
 actor.location.cell=[51,76];x.space.sync_actor(x.world,actor.id)
 checks.same_tick_enter_index=Entry._physical_candidates(x.space,x.world,ctx).has(actor.id)
 _compare(x,probe,comparisons,"same_tick_inside",false)
 actor.location.cell=[60,85];x.space.sync_actor(x.world,actor.id)
 checks.same_tick_leave_index=not Entry._physical_candidates(x.space,x.world,ctx).has(actor.id)
 checks.same_tick_unchanged=x.world.sim_tick==tick
 _compare(x,probe,comparisons,"same_tick_outside",true)
 x.world.facts.floor_guidance.visits[physical.id]={"visit_id":physical.id,"phase":"working","queue_seq":1,"desk_id":"guide","guide_floor":1,"request_key":"held"}
 checks.held_outside=not Entry.is_inside(ctx,x.space,actor,Vector2(actor.location.cell[0],actor.location.cell[1]))
 _compare(x,probe,comparisons,"held_outside",false)
 x.world.facts.floor_guidance.visits.erase(physical.id)
 actor.location.cell=[44,85]
 var follower: Dictionary=_visit(x,"follower",[42,85]);x.world.touch(false)
 var request: String=x.space.request_group_move(x.world,actor.id,[actor.id,follower.actor_id],{},1,[46,85])
 checks.convoy_created=request.is_empty() and x.world.facts.moves.get(actor.id,{}).has("convoy")
 x.world.facts.actors[follower.actor_id].location.cell=[51,76];x.world.touch(false)
 checks.follower_inside=Entry.is_inside(ctx,x.space,x.world.facts.actors[follower.actor_id],Vector2(51,76))
 checks.leader_outside=not Entry.is_inside(ctx,x.space,actor,Vector2(44,85))
 checks.follower_candidate=Entry._physical_candidates(x.space,x.world,ctx).has(follower.actor_id)
 _compare(x,probe,comparisons,"convoy_member_separate",false)
 checks.all_capacity_equal=comparisons.all(func(row: Dictionary)->bool:return row.expected==row.actual and row.unchanged)
 _dispose(x)
 return {"ok":not checks.values().has(false),"request":request,"checks":checks,"comparisons":comparisons}
func _compare(x: Dictionary,probe: Dictionary,rows: Array,label: String,expected: bool)->void:
 var before: Dictionary=x.world.freeze()
 var current: bool=Entry.capacity_available(x.space,x.world,x.g,probe.actor_id,"guide")
 rows.append({"case":label,"expected":expected,"actual":current,"unchanged":before==x.world.freeze()})
