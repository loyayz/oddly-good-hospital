extends SceneTree
class ObserveSpace extends HospitalSpace:
	var observed: Array = []
	func _init(content: HospitalContent) -> void: super(content)
	func _actor_rect(actor: Dictionary, origin: Vector2) -> Rect2:
		if actor.id=="interleave_actor": observed.append({"id":actor.id,"facing":actor.facing,"origin":origin})
		return super._actor_rect(actor,origin)
class ObserveMove extends HospitalMovement:
	var owners: Array = []
	func _init(s: HospitalSpace) -> void: super(s)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		owners.append(proof)
		return super._detour_path_clear(world,actor,movement,path,query,proof)
var checks: Dictionary = {}
func check(label: String, ok: bool) -> void:
	checks[label]=ok
	print("H5_INTERLEAVING ",label," ",ok)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var content: HospitalContent = HospitalContent.new()
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new();suite.content=content
	var fixture: RefCounted = load("res://tests/acceptance/detour_step_proof.gd").new()
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"interleave_actor","S49",[35,70]);suite._add_actor(sim,"interleave_blocker","S49",[36,70])
	var actor: Dictionary = sim.world.facts.actors.interleave_actor
	actor.facing=0.37;sim.world.touch()
	var space: ObserveSpace = ObserveSpace.new(content)
	var move: ObserveMove = ObserveMove.new(space)
	var request: Dictionary = fixture._movement(actor.id,[[36,70]])
	var origin: Vector2 = Vector2(35,70)
	var blocked_point: Dictionary = fixture._point(36,70)
	var open_point: Dictionary = fixture._point(35,71)
	var before: Dictionary = sim.world.freeze()
	check("legal_fixture",sim.world.validate(content).is_empty())
	# Owner metadata is explicit test setup, but negative proof is produced by
	# real geometry/contact execution, not injected as a collision verdict.
	var proof: Dictionary = {"sweeps":{},"segments":{},"_capture_entry":true,"_return_sample":actor.duplicate(true)}
	var clear: bool = move._detour_path_clear(sim.world,actor,request,[blocked_point],null,proof)
	var key: Array = [origin,Vector2(36,70),proof._entry.rect]
	check("real_blocked_producer",not clear and proof.segments.has(key) and proof.segments[key].is_empty())
	check("real_failure_turned_private_scratch",proof._return_sample.facing!=actor.facing)
	var stale: float = proof._return_sample.facing
	var token: int = space._actor_shapes[actor.id].token
	var prune_a: bool = move._detour_first_segment_failed(sim.world,actor,Vector2(35,71),[blocked_point],[],blocked_point,proof)
	var prune_b: bool = move._detour_first_segment_failed(sim.world,actor,origin,[],[],blocked_point,proof)
	check("consecutive_real_proof_prunes",prune_a and prune_b)
	check("prunes_restore_cache_not_scratch",space._actor_shapes[actor.id].facing==actor.facing and space._actor_shapes[actor.id].token==token and proof._return_sample.facing==stale)
	check("unknown_not_pruned",not move._detour_first_segment_failed(sim.world,actor,origin,[open_point],[],blocked_point,proof))
	space.observed.clear()
	move._detour_path_clear(sim.world,actor,request,[open_point],null,proof)
	check("unknown_full_first_rect_reset",not space.observed.is_empty() and space.observed[0].facing==actor.facing and space.observed[0].origin==origin)
	check("entry_retains_actual_origin",proof._entry.origin==origin)
	# Synthetic irrelevant integer keys only fill storage. They are not
	# reported as physical proofs; unknown exact Array key must compute.
	while proof.segments.size()<4096: proof.segments[proof.segments.size()]=[]
	while proof.sweeps.size()<4096: proof.sweeps[proof.sweeps.size()]=false
	var unknown: Dictionary = fixture._point(35,69)
	proof._return_sample.facing=1.17
	check("cap_unknown_not_pruned",not move._detour_first_segment_failed(sim.world,actor,origin,[unknown],[],blocked_point,proof))
	space.observed.clear()
	move._detour_path_clear(sim.world,actor,request,[unknown],null,proof)
	check("cap_full_reset_and_storage_only",space.observed.size()>1 and space.observed[0].facing==actor.facing and proof.segments.size()==4096 and proof.sweeps.size()==4096)
	check("world_unchanged_after_interleaving",sim.world.freeze()==before)
	var standalone: Dictionary = {}
	move._detour_path_clear(sim.world,actor,request,[open_point],null,standalone)
	check("standalone_no_private_metadata",standalone.is_empty())
	# Real owner creation across decisions, not reusing the explicit map above.
	move.owners.clear();move._detour_return_path(sim.world,actor,request,origin)
	var first_owner: Dictionary = move.owners[0]
	var first_sample: Dictionary = first_owner._return_sample
	actor.facing=0.81;actor.posture="lying";sim.world.touch()
	var changed_before: Dictionary = sim.world.freeze()
	move.owners.clear();space.observed.clear()
	move._detour_return_path(sim.world,actor,request,origin)
	var second_owner: Dictionary = move.owners[0]
	check("new_decision_private_owner",not is_same(first_owner,second_owner) and not is_same(first_sample,second_owner._return_sample) and not is_same(actor,second_owner._return_sample))
	check("new_decision_lying_and_real_pose",second_owner._return_sample.posture=="lying" and second_owner._entry.origin==origin and space.observed[0].facing==actor.facing)
	second_owner._return_sample.location.cell[0]=123
	check("nested_actor_alias_isolated",float(actor.location.cell[0])==35.0 and sim.world.freeze()==changed_before)
	var empty_request: Dictionary = fixture._movement(actor.id,[])
	move.owners.clear()
	check("empty_search_no_predicate",move._detour_return_path(sim.world,actor,empty_request,origin).is_empty() and move.owners.is_empty())
	var f: FileAccess = FileAccess.open(out,FileAccess.WRITE)
	f.store_string(JSON.stringify({"complete":true,"passed":not checks.values().has(false),"checks":checks,"scope":"real collision proof interleaving plus explicitly synthetic cap storage; no performance"},"\t"));f.close()
	sim.dispose();quit(0 if not checks.values().has(false) else 1)
