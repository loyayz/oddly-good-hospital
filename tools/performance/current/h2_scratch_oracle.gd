extends RefCounted

# Independent comparison uses the same complete production predicate, with
# owner scratch removed only. Existing geometric proofs remain identical.
class Probe extends HospitalMovement:
	var scratch_ids: Array = []
	var calls: int = 0
	var separate_copy: bool = true
	func _init(space: HospitalSpace) -> void: super(space)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		calls += 1
		if proof.has("_return_sample"):
			var sample: Dictionary = proof._return_sample
			separate_copy = separate_copy and not is_same(sample,actor) and not is_same(sample.location,actor.location)
			var known: bool = false
			for old: Dictionary in scratch_ids: known = known or is_same(old,sample)
			if not known: scratch_ids.append(sample)
		return super._detour_path_clear(world,actor,movement,path,query,proof)

class FreshCopy extends HospitalMovement:
	func _init(space: HospitalSpace) -> void: super(space)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		var independent: Dictionary = proof.duplicate()
		independent.erase("_return_sample")
		return super._detour_path_clear(world,actor,movement,path,query,independent)

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var fixture: RefCounted = load("res://tests/acceptance/detour_step_proof.gd").new()
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var probe: Probe = Probe.new(sim.space)
	var oracle: FreshCopy = FreshCopy.new(sim.space)
	var request: Dictionary = fixture._movement("walker",[[36,70],[37,70]])
	var cases: Array = []
	for facing: float in [0.0,PI*0.5,PI,-PI*0.5]:
		sim.world.facts.actors.walker.facing = facing
		sim.world.touch()
		var before: Dictionary = sim.world.freeze()
		var prior: int = probe.scratch_ids.size()
		var calls_before: int = probe.calls
		var a: Dictionary = probe._detour_return_path(sim.world,sim.world.facts.actors.walker,request,Vector2(35,70))
		var b: Dictionary = oracle._detour_return_path(sim.world,sim.world.facts.actors.walker,request,Vector2(35,70))
		cases.append({"facing":facing,"same_original_selection":a==b and not a.is_empty(),"multiple_candidates":probe.calls-calls_before>1,"one_new_owner_scratch":probe.scratch_ids.size()==prior+1,"facts_unchanged":sim.world.freeze()==before,"private_deep_copy":probe.separate_copy})
	var direct_proof: Dictionary = {"sweeps":{},"segments":{}}
	var before: Dictionary = sim.world.freeze()
	var direct: bool = probe._detour_path_clear(sim.world,sim.world.facts.actors.walker,request,[fixture._point(35,71)],null,direct_proof)
	var direct_safe: bool = direct and not direct_proof.has("_return_sample") and before==sim.world.freeze()
	var ok: bool = direct_safe
	for row: Dictionary in cases:
		for key: String in ["same_original_selection","multiple_candidates","one_new_owner_scratch","facts_unchanged","private_deep_copy"]: ok = ok and row[key]
	sim.dispose()
	return {"passed":ok,"cases":cases,"direct_proof_not_promoted":direct_safe,"scope":"Prepared-vs-fresh actor scratch only; original predicates/proof maps retained. Other body/convoy/dynamic cases remain covered by selected original tests and independent reviewer."}
