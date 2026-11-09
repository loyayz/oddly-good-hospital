extends "res://tests/acceptance/guidance_queue_entry_boundary.gd"

# Explicitly tests the new actual-tail admission rule. Physical fixtures below
# are not claims of completed movement; integration runners cover real travel.
func run_tail_body_checks(content: HospitalContent) -> Dictionary:
	_content=content
	var x: Dictionary=_entry_fixture()
	var entrant: Dictionary=_visit(x,"tail_entrant",[52,81])
	var point: Dictionary=x.g._queue_point(x.world,entrant.actor_id,"guide",entrant.id)
	var checks: Dictionary={"real_tail_exists":not point.is_empty()}
	if point.is_empty():
		_dispose(x)
		return {"ok":false,"checks":checks}
	checks.initial_tail_clear=Entry.capacity_available(x.space,x.world,x.g,entrant.actor_id,"guide")
	var leaving: Dictionary=_visit(x,"departing_body",point.cell.duplicate())
	leaving.phase="leaving"
	x.world.touch(false)
	checks.departing_body_blocks_actual_tail=not Entry.capacity_available(x.space,x.world,x.g,entrant.actor_id,"guide")
	checks.physical_body_does_not_join=x.g._desk_queue(x.world,"guide").is_empty()
	var ctx: Dictionary=Entry.context(x.space,x.world,"guide")
	var actor: Dictionary=x.world.facts.actors[leaving.actor_id]
	var moved: bool=false
	# Find a genuine in-room body position which does not cover the tail.
	# The exact room membership predicate, not center containment, is used.
	for candidate: Array in [[54,76],[55,76],[50,76],[54,75],[55,75]]:
		actor.location.cell=candidate
		x.world.touch(false)
		if Entry.is_inside(ctx,x.space,actor,Vector2(candidate[0],candidate[1])) and x.g._queue_admission_clear(x.world,entrant.actor_id,int(point.floor_id),point.cell):
			moved=true
			break
	checks.non_tail_body_still_in_room=moved
	checks.unheld_room_body_does_not_consume_virtual_number=moved and Entry.capacity_available(x.space,x.world,x.g,entrant.actor_id,"guide") and x.g._desk_queue(x.world,"guide").is_empty()
	checks.same_tail_after_body_moves=x.g._queue_point(x.world,entrant.actor_id,"guide",entrant.id)==point
	actor.location.cell=point.cell.duplicate()
	x.world.touch(false)
	checks.same_tick_reentry_blocks_tail_again=not Entry.capacity_available(x.space,x.world,x.g,entrant.actor_id,"guide")
	var result: Dictionary={"ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"tail":point,"scope":"new actual-tail body admission, not old virtual room packing equivalence"}
	_dispose(x)
	return result
