extends SceneTree

# Calculation-boundary regression: active landing ownership is independent of
# all other cabin riders. These inputs do not assert any completed journey.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new()
	suite.content=HospitalContent.new()
	var sim: HospitalSimulation=suite._fixture()
	for id: String in ["primary","companion","other","member"]: suite._add_actor(sim,id,"S49",[40,70])
	var w: WorldState=sim.world
	w.facts.moves.primary={"actor_id":"primary","members":["primary"],"offsets":{}}
	w.facts.moves.companion={"actor_id":"companion","members":["companion","member"],"offsets":{"member":[2,0]}}
	var c: Dictionary={"phase":"alighting","from":1,"to":1,"anchor":[40,70],"riders":["primary","companion","member","other"],"primary_actor_id":"primary","lift_control_version":1,"active_group":"primary","passenger_groups":[{"actor_id":"primary","members":["primary","companion","member"],"leader_ids":["primary","companion"],"entry_cells":{"primary":[40,70],"companion":[44,70]}},{"actor_id":"other","members":["other"]}]}
	var before: Dictionary=w.freeze()
	var service: Dictionary=HospitalTransit._waiting_contact_exit(sim.space,w,c,1)
	var expected: Rect2=sim.space._actor_rect(w.facts.actors.primary,Vector2(40,70)).merge(sim.space._actor_rect(w.facts.actors.companion,Vector2(44,70))).merge(sim.space._actor_rect(w.facts.actors.member,Vector2(46,70)))
	var checks: Dictionary={"active_group_own_offsets_and_origins":service.ok and service.rect==expected,"read_only":w.freeze()==before}
	c.passenger_groups[0].leader_ids=["primary"]
	c.passenger_groups[0].members=["primary"]
	service=HospitalTransit._waiting_contact_exit(sim.space,w,c,1)
	checks.other_cabin_groups_excluded=service.ok and service.rect==sim.space._actor_rect(w.facts.actors.primary,Vector2(40,70))
	c.phase="boarding"
	checks.boarding=HospitalTransit._waiting_contact_exit(sim.space,w,c,1)==service
	checks.other_floor=HospitalTransit._waiting_contact_exit(sim.space,w,c,2)=={"ok":true,"rect":Rect2()}
	w.facts.moves.primary.convoy={"version":1}
	checks.convoy_remains_fail_closed=not HospitalTransit._waiting_contact_exit(sim.space,w,c,1).ok
	w.facts.moves.primary.erase("convoy")
	c.active_group="missing"
	checks.missing_active_fail_closed=not HospitalTransit._waiting_contact_exit(sim.space,w,c,1).ok
	c.phase="idle"
	checks.idle=HospitalTransit._waiting_contact_exit(sim.space,w,c,1)=={"ok":true,"rect":Rect2()}
	c.erase("lift_control_version");c.phase="alighting";c.riders=["primary","member"]
	w.facts.moves.primary.members=["primary","member"];w.facts.moves.primary.offsets={"member":[2,0]}
	service=HospitalTransit._waiting_contact_exit(sim.space,w,c,1)
	checks.legacy_group=service.ok and service.rect==sim.space._actor_rect(w.facts.actors.primary,Vector2(40,70)).merge(sim.space._actor_rect(w.facts.actors.member,Vector2(42,70)))
	var passed: bool=checks.values().all(func(v:bool)->bool:return v)
	var result: Dictionary={"passed":passed,"checks":checks,"scope":"Exit geometry calculation only; active group members and independent offsets, boarding/alighting, unrelated cabin groups, missing group, convoy fail-closed, legacy group; not journey completion."}
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));sim.dispose();quit(0 if passed else 1)
