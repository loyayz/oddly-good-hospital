extends "res://tests/acceptance/public_environment_view.gd"

const OriginalSignature = preload("res://tests/acceptance/public_wait_dependency_queries.gd")

class ProbeAreas extends HospitalPublicAreas:
	var index_queries: int = 0
	func _environment_sample_indices(samples: Array, indices: Dictionary, floor_id: int, points: Array) -> Array:
		index_queries += 1
		return super._environment_sample_indices(samples,indices,floor_id,points)

# Keep the old full layout reads and full signature, but obtain its environment
# rows independently from original facts, without either production index.
class FullReference extends OriginalSignature.ReferenceAreas:
	var observed_world: WorldState
	var literal: WeakRef
	func _init(geometry: HospitalSpace, reference: RefCounted) -> void:
		super(geometry)
		literal = weakref(reference)
	func _decision_signature(world: WorldState, intent: Dictionary, definitions: Array, members: Array, extra: Dictionary, route_floors: Array = []) -> Array:
		observed_world = world
		return super._decision_signature(world,intent,definitions,members,extra,route_floors)
	func _environment_samples(_view: Dictionary, floor_id: int, points: Array) -> Array:
		return literal.get_ref()._literal_samples(observed_world,floor_id,points)

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _areas()
	x.probe = ProbeAreas.new(x.space)
	x.reference = FullReference.new(x.space,self)
	x.space.public_areas = x.probe
	x.subject = _visit(x,"environment_match_subject",[40,75])
	x.peer = _visit(x,"environment_match_peer",[42,75])
	# Inside the patient place's strict broadphase union, beyond the actual
	# chair/repair places and separate from the other two real bodies.
	x.nearby = _visit(x,"environment_match_nearby",[40,74])
	var checks: Dictionary = {"legal_input":x.world.validate(database).is_empty()}
	var anchor: Array = x.world.facts.facilities.west_chair.cell.duplicate()
	var other: Array = x.world.facts.facilities.east_chair.cell.duplicate()
	var patch: String = x.e.spawn_dirt(x.world,"CL01","environment_match_source","environment_match_source:1",1,[42,76])
	x.probe.changed(x.world)
	var rows: Array = []
	var first: Dictionary = _sample(x,[anchor])
	rows.append(_sample_row("first_point_set",first))
	var second: Dictionary = _sample(x,[other])
	rows.append(_sample_row("second_point_set",second))
	var first_again: Dictionary = _sample(x,[anchor.duplicate()])
	rows.append(_sample_row("return_to_equal_first_set",first_again))
	var second_again: Dictionary = _sample(x,[other.duplicate()])
	rows.append(_sample_row("return_to_equal_second_set",second_again))
	checks.alternating_complete_equal_point_sets_skip_both_queries = first.index_queries==2 and second.index_queries==2 and first_again.index_queries==0 and second_again.index_queries==0
	var combined: Dictionary = _sample(x,[anchor,other])
	rows.append(_sample_row("combined_set",combined))
	var reverse: Dictionary = _sample(x,[other,anchor])
	rows.append(_sample_row("reverse_point_order",reverse))
	var repeated: Dictionary = _sample(x,[anchor,anchor,other])
	rows.append(_sample_row("duplicate_points",repeated))
	checks.order_and_duplicates_keep_original_source_order = combined.actual==reverse.actual and reverse.actual==repeated.actual and combined.index_queries==2 and reverse.index_queries==2 and repeated.index_queries==2
	var empty: Dictionary = _sample(x,[])
	rows.append(_sample_row("empty_point_set",empty))
	checks.empty_points_do_not_query_or_enter_recent_sets = empty.actual.is_empty() and empty.index_queries==0 and empty.view.environment_matches[1].size()==2
	var mutable_points: Array = [anchor.duplicate()]
	var frozen: Dictionary = _sample(x,mutable_points)
	mutable_points[0][0] += 1
	var mutated: Dictionary = _sample(x,mutable_points)
	var original_again: Dictionary = _sample(x,[anchor.duplicate()])
	rows.append(_sample_row("mutated_caller_points",mutated))
	rows.append(_sample_row("original_points_after_caller_mutation",original_again))
	checks.retained_complete_points_are_frozen_and_history_is_bounded = frozen.index_queries==2 and mutated.index_queries==2 and original_again.index_queries==0 and original_again.view.environment_matches[1].size()==2
	var retained_view: Dictionary = original_again.view
	var facility: Dictionary = x.world.facts.facilities.west_chair
	facility.level = 2
	facility.failed = true
	var live: Dictionary = _sample(x,[anchor])
	rows.append(_sample_row("same_view_live_facility_values",live))
	checks.matched_indices_do_not_cache_current_level_or_failure = live.index_queries==0 and is_same(live.view,retained_view) and live.actual.has([anchor,"facility",[facility.id,facility.definition_id,2,true]])
	facility.level = 1
	facility.failed = false
	x.world.facts.sim_tick += 1
	x.world.touch(false)
	var next_tick: Dictionary = _sample(x,[anchor])
	rows.append(_sample_row("next_tick",next_tick))
	checks.next_tick_replaces_matches_but_keeps_static_index = next_tick.index_queries==2 and not is_same(next_tick.view,retained_view) and is_same(next_tick.view.facility_environment,retained_view.facility_environment)
	x.probe.changed(x.world)
	var changed: Dictionary = _sample(x,[anchor])
	rows.append(_sample_row("changed_same_tick",changed))
	checks.changed_replaces_matches = changed.index_queries==2 and not is_same(changed.view,next_tick.view)
	if not patch.is_empty():
		x.world.facts.environment.dirt.erase(patch)
		x.probe.changed(x.world)
	var removed: Dictionary = _sample(x,[[42,76]])
	rows.append(_sample_row("real_dynamic_source_removed",removed))
	checks.dynamic_source_removal_uses_new_closed_view = not patch.is_empty() and removed.actual.filter(func(row: Array)->bool:return row[1]=="dirt").is_empty()
	var explicit: Dictionary = removed.view.duplicate()
	explicit.erase("environment_matches")
	var explicit_source: Dictionary = x.world.freeze()
	var explicit_samples: Array = x.probe._environment_samples(explicit,1,[anchor])
	checks.explicit_legacy_view_lazily_owns_discardable_matches = explicit_samples==_literal_samples(x.world,1,[anchor]) and explicit.has("environment_matches") and explicit_source==x.world.freeze()
	var index_count: int = removed.view.facility_environment.indices.size()
	var empty_floor: Dictionary = _sample(x,[anchor],2)
	rows.append(_sample_row("empty_floor",empty_floor))
	checks.empty_floor_does_not_build_an_index = empty_floor.actual.is_empty() and empty_floor.view.facility_environment.indices.size()==index_count and not empty_floor.view.environment_indices.has(2)
	var original_world: WorldState = x.world
	x.world = WorldState.new(original_world.freeze())
	var different_world: Dictionary = _sample(x,[anchor])
	rows.append(_sample_row("different_world",different_world))
	checks.other_world_does_not_reuse_prior_point_matches = different_world.index_queries==2 and not is_same(different_world.view,removed.view) and not is_same(different_world.view.facility_environment,removed.view.facility_environment)
	x.world = original_world
	var input: Dictionary = {"id":"environment_match_task","actor_id":x.subject.actor_id,"public_purpose":"seat","mode":"auto","area":x.probe.for_facility(x.world,"west_chair"),"phase":"area_travel","facility_id":"","arrived_tick":-1,"started_tick":x.world.sim_tick}
	var signatures: Array = []
	var initial: Dictionary = _signature(x,input)
	signatures.append(_signature_row("complete_original_signature",initial))
	var again: Dictionary = _signature(x,input)
	signatures.append(_signature_row("unchanged_complete_signature",again))
	checks.equal_signature_skips_both_environment_index_queries = initial.signature==again.signature and again.index_queries==0
	checks.actor_change_input_is_an_actual_observed_dependency = again.signature.any(func(row: Variant)->bool:return row is Array and row.size()==7 and row[0]==x.nearby.actor_id)
	# Facing and live dependency facts can change without replacing the public
	# observation. The match owns sample membership only, never actor state.
	x.world.facts.actors[x.nearby.actor_id].facing = 0.375
	var actor_change: Dictionary = _signature(x,input)
	signatures.append(_signature_row("current_actor_fact_without_changed",actor_change))
	checks.same_view_actor_fact_remains_live = actor_change.signature!=again.signature and actor_change.index_queries==0
	var reservation: String = x.space.reserve_facility(x.world,"west_chair",x.subject.actor_id,x.subject.actor_id)
	var reserved: Dictionary = _signature(x,input)
	signatures.append(_signature_row("real_facility_reservation",reserved))
	checks.real_reservation_keeps_original_full_layout_semantics = reservation.is_empty() and x.world.facts.adaptations.has("west_chair") and reserved.signature!=actor_change.signature
	x.space.grant_facility_access(x.world,"west_chair",x.peer.actor_id)
	var permission: Dictionary = _signature(x,input)
	signatures.append(_signature_row("real_access_grant_without_public_changed",permission))
	checks.current_permission_is_not_memoized = x.world.facts.adaptations.get("west_chair",{}).get("staff_ids",[]).has(x.peer.actor_id) and permission.signature!=reserved.signature and permission.index_queries==0
	# Both participants leave the reservation's actual places before the real
	# owner releases it. This is a calculation boundary, not simulated travel.
	_position(x,x.subject.actor_id,[40,75])
	_position(x,x.peer.actor_id,[42,75])
	x.space.release_adaptations(x.world)
	var released: Dictionary = _signature(x,input)
	signatures.append(_signature_row("real_ownership_release",released))
	checks.real_owner_release_restores_unreserved_signature = not x.world.facts.adaptations.has("west_chair") and released.signature==actor_change.signature
	var result: Dictionary = {"ok":not checks.values().has(false) and rows.all(func(row: Dictionary)->bool:return row.ok) and signatures.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"samples":rows,"signatures":signatures,"reservation_reason":reservation,"match_builds":x.space.query_counts.get("public_wait_environment_match_builds",0),"match_hits":x.space.query_counts.get("public_wait_environment_match_hits",0),"scope":"Exact observer calculations, current sample values and real ownership changes; full waiting, movement and use remain STAFF-69 through STAFF-72."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

func _sample(x: Dictionary, points: Array, floor_id: int = 1) -> Dictionary:
	var queries: int = x.probe.index_queries
	var result: Dictionary = _observe(x,points,floor_id)
	result.index_queries = x.probe.index_queries-queries
	return result

func _sample_row(label: String, observed: Dictionary) -> Dictionary:
	return {"boundary":label,"ok":observed.ok,"readonly":observed.readonly,"index_queries":observed.index_queries,"row_count":observed.actual.size()}

func _signature(x: Dictionary, intent: Dictionary) -> Dictionary:
	var source: Dictionary = x.world.freeze()
	var queries: int = x.probe.index_queries
	# The reference always starts from current original ownership facts.
	x.reference.changed(x.world)
	var actual: Array = x.probe._decision_signature(x.world,intent,["FUR09"],[],{},[1])
	var expected: Array = x.reference._decision_signature(x.world,intent,["FUR09"],[],{},[1])
	return {"ok":actual==expected and source==x.world.freeze(),"signature":actual.duplicate(true),"full_original_signature_equal":actual==expected,"readonly":source==x.world.freeze(),"index_queries":x.probe.index_queries-queries}

func _signature_row(label: String, observed: Dictionary) -> Dictionary:
	var row: Dictionary = observed.duplicate()
	row.erase("signature")
	row.boundary = label
	return row
