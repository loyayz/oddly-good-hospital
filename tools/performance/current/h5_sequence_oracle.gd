extends RefCounted
const Reference = preload("res://tools/performance/current/h5_h3_reference.gd")

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var fixture: RefCounted = load("res://tests/acceptance/detour_step_proof.gd").new()
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var actor: Dictionary = sim.world.facts.actors.walker
	var a_space: HospitalSpace = HospitalSpace.new(content)
	var b_space: HospitalSpace = HospitalSpace.new(content)
	var a: HospitalMovement = HospitalMovement.new(a_space)
	var b: HospitalMovement = Reference.new(b_space)
	var movement: Dictionary = fixture._movement("walker",[[36,70],[37,70]])
	var cases: Array = []
	# Explicit owner-level test sequence: all negative segment proofs below
	# are produced by actual original geometry, never seeded as false.
	actor.facing=0.73
	sim.world.touch()
	var facts: Dictionary = sim.world.freeze()
	var ap: Dictionary = {"sweeps":{},"segments":{},"_capture_entry":true,"_return_sample":actor.duplicate(true)}
	var bp: Dictionary = {"sweeps":{},"segments":{},"_capture_entry":true}
	# First leg genuinely turns, second leg is diagonal and rejects.
	var turning: Array = [fixture._point(35,71),fixture._point(36,72)]
	var av: bool = a._detour_path_clear(sim.world,actor,movement,turning,null,ap)
	var bv: bool = b._detour_path_clear(sim.world,actor,movement,turning,null,bp)
	cases.append({"name":"real_full_turn_then_fail","ok":not av and av==bv and float(ap._return_sample.facing)!=float(actor.facing)})
	var blocked: Array = [fixture._point(36,70)]
	av=a._detour_path_clear(sim.world,actor,movement,blocked,null,ap)
	bv=b._detour_path_clear(sim.world,actor,movement,blocked,null,bp)
	cases.append({"name":"real_first_negative_proof","ok":not av and av==bv and ap.segments==bp.segments})
	var stale: float = float(ap._return_sample.facing)
	for i: int in 3:
		var ah: bool = a._detour_first_segment_failed(sim.world,actor,Vector2(35,70),[],[Vector2(36,70)],fixture._point(36,70),ap)
		var bh: bool = b._detour_first_segment_failed(sim.world,actor,Vector2(35,70),[],[Vector2(36,70)],fixture._point(36,70),bp)
		cases.append({"name":"real_prune_"+str(i),"ok":ah and bh and float(ap._return_sample.facing)==stale and a_space._actor_shapes==b_space._actor_shapes and a_space._envelope_next==b_space._envelope_next})
	var unknown: Array = [fixture._point(35,72)]
	av=a._detour_path_clear(sim.world,actor,movement,unknown,null,ap)
	bv=b._detour_path_clear(sim.world,actor,movement,unknown,null,bp)
	cases.append({"name":"unknown_full_after_prunes","ok":av and av==bv and ap.segments==bp.segments and ap.sweeps==bp.sweeps and ap._entry==bp._entry and a_space._actor_shapes==b_space._actor_shapes and a_space._envelope_next==b_space._envelope_next})
	cases.append({"name":"facts_rng_alias","ok":facts==sim.world.freeze() and not is_same(ap._return_sample,actor) and not is_same(ap._return_sample.location,actor.location)})
	# Same tick, new owners: changed facing/posture/body dimensions and obstacle
	# placement are fixture inputs, not simulated travel or completed work.
	for posture: String in ["standing","lying"]:
		actor.posture=posture;actor.facing=0.000001
		sim.world.facts.actors.blocker.location.cell=[37,70]
		sim.world.touch()
		var before: Dictionary = sim.world.freeze()
		var selected_a: Dictionary = a._detour_return_path(sim.world,actor,movement,Vector2(35,70))
		var selected_b: Dictionary = b._detour_return_path(sim.world,actor,movement,Vector2(35,70))
		cases.append({"name":"new_owner_"+posture,"ok":selected_a==selected_b and before==sim.world.freeze() and a_space._actor_shapes==b_space._actor_shapes and a_space._envelope_next==b_space._envelope_next and a_space._actor_rect(actor,Vector2(35.125,70.25))==b_space._actor_rect(actor,Vector2(35.125,70.25))})
	var ok: bool = true
	for row: Dictionary in cases: ok=ok and row.ok
	sim.dispose()
	return {"passed":ok,"cases":cases,"scope":"Explicit legitimate owner-predicate sequence, not evidence that natural 800 search has this distribution; no seeded false proof. Original groups retain convoy/cap tests. Permission-specific owner changes delegated to independent supplement."}
