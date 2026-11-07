extends RefCounted
class Probe extends HospitalMovement:
	var pruned: int = 0
	var predicates: int = 0
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _detour_first_segment_failed(world: WorldState, actor: Dictionary, origin: Vector2, prefix: Array, link: Array, fallback: Dictionary, proof: Dictionary) -> bool:
		var rejected: bool = super._detour_first_segment_failed(world,actor,origin,prefix,link,fallback,proof)
		if rejected: pruned+=1
		return rejected
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		predicates+=1
		return super._detour_path_clear(world,actor,movement,path,query,proof)
class CompleteSearch extends Probe:
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _detour_first_segment_failed(_world: WorldState, _actor: Dictionary, _origin: Vector2, _prefix: Array, _link: Array, _fallback: Dictionary, _proof: Dictionary) -> bool: return false

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new();suite.content=content
	var fixture: RefCounted = load("res://tests/acceptance/detour_step_proof.gd").new()
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70]);suite._add_actor(sim,"blocker","S49",[36,70])
	var cases: Array = []
	var total_pruned: int = 0
	for nonempty_prefix: bool in [false,true]:
		for facing: float in [0.0,PI*0.5,PI,-PI*0.5]:
			sim.world.facts.actors.walker.facing=facing;sim.world.touch()
			var a_space: HospitalSpace = HospitalSpace.new(content)
			var b_space: HospitalSpace = HospitalSpace.new(content)
			var a: Probe = Probe.new(a_space);var b: CompleteSearch = CompleteSearch.new(b_space)
			var request: Dictionary = fixture._movement("walker",[[36,70],[37,70]])
			var prefix: Array = [fixture._point(36,70)] if nonempty_prefix else []
			var origin: Vector2 = Vector2(36,70) if nonempty_prefix else Vector2(35,70)
			var before: Dictionary = sim.world.freeze()
			var chosen: Dictionary = a._detour_return_path(sim.world,sim.world.facts.actors.walker,request,origin,prefix)
			var original: Dictionary = b._detour_return_path(sim.world,sim.world.facts.actors.walker,request,origin,prefix)
			var same_cache: bool = a_space._actor_shapes==b_space._actor_shapes and a_space._envelope_next==b_space._envelope_next
			var subsequent: bool = a_space._actor_rect(sim.world.facts.actors.walker,Vector2(39.125,72.25))==b_space._actor_rect(sim.world.facts.actors.walker,Vector2(39.125,72.25))
			var checks: Dictionary = {"same_ordered_selection":chosen==original,"facts_readonly":before==sim.world.freeze(),"shape_and_token_exact":same_cache,"subsequent_rectangle_exact":subsequent,"original_predicate_calls_accounted":a.predicates+a.pruned==b.predicates,"reference_never_prunes":b.pruned==0}
			if nonempty_prefix: checks.blocked_real_prefix_rejected=chosen.is_empty()
			total_pruned+=a.pruned
			cases.append({"prefix_nonempty":nonempty_prefix,"facing":facing,"checks":checks,"pruned":a.pruned,"candidate_predicates":a.predicates,"complete_predicates":b.predicates,"selected":chosen})
	var ok: bool = total_pruned>0
	for row: Dictionary in cases:
		for value: bool in row.checks.values(): ok=ok and value
	sim.dispose()
	return {"passed":ok,"total_pruned":total_pruned,"cases":cases,"scope":"Complete original search comparator disables only early helper; real predicates/proofs retained. Shape/token equality and subsequent rectangle observed, not only world facts."}
