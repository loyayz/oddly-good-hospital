extends RefCounted

# Authored single-contact boundary, not an end-to-end life trip. Suppress
# the retreating subject's return so this tests the actual blocker's contract.
class ContactOnlyMovement extends HospitalMovement:
 func _init(s:HospitalSpace)->void:super(s)
 func _local_try_return(_w:WorldState,_a:Dictionary,_m:Dictionary,_attempt:bool=false)->bool:return false

func _p(cell:Array)->Dictionary:return {"kind":"floor","floor_id":1,"cell":cell.duplicate()}
func _journey(id:String,start:Array,goal:Array)->Dictionary:
 return {"actor_id":id,"path":[_p(goal)],"cursor":0,"travelled":[_p(start)],"blocked_since":-1,"target_floor":1,"target_cell":goal.duplicate(),"request_sequence":101}

func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[]
 for mode:String in ["area_travel","local_travel","returning","release","exiting","stale_marker","missing_marker","active_work","clinical_release","working_training","travelling_training","rest","same_target_transfer"]:
  var sim:HospitalSimulation=suite._fixture()
  suite._add_actor(sim,"a","S49",[40,70])
  suite._add_actor(sim,"front","S49",[40.6,70])
  suite._add_staff(sim,"b","nurse",[39.4,70])
  sim.services.finance.ensure(sim.world)
  sim.services.recruitment.ensure(sim.world)
  sim.services.development.ensure(sim.world)
  sim.services.scheduler.ensure(sim.world)
  sim.services.wellbeing.ensure(sim.world)
  var initial_validation:String=sim.world.validate(content)
  sim.space.movement=ContactOnlyMovement.new(sim.space)
  var a:Dictionary=_journey("a",[40,70],[45,70])
  a.path=[_p([41,70]),_p([45,70])]
  a.local_move={"origin":[40,70],"target":_p([39,70]),"retreat":true}
  var b:Dictionary=_journey("b",[39.4,70],[39.4,75])
  var phase:String=mode if mode in ["area_travel","local_travel","returning","release","exiting","rest"] else "local_travel"
  # Minimal task input for the eligibility boundary. Active-work and training
  # rows deliberately supply guard facts, not fabricated working sessions.
  var life:Dictionary={"id":"life_b_contract","kind":"rest","phase":phase,"floor_id":1,"cell":[39.4,75],"facility_id":"","public_purpose":"rest"}
  sim.world.facts.staff.b.life_task=life
  b.waiting_seat_id=life.id
  if mode=="stale_marker":b.waiting_seat_id="life_b_previous"
  if mode=="missing_marker":b.erase("waiting_seat_id")
  if mode=="active_work":sim.world.facts.staff.b.active_job_id="contract:active_work"
  if mode=="clinical_release":sim.world.facts.staff.b.clinical_release={"phase":"walking"}
  if mode in ["working_training","travelling_training"]:
   sim.world.facts.staff.b.training_job_id="contract_training"
   sim.world.facts.training_jobs.contract_training={"state":"working" if mode=="working_training" else "travelling"}
  sim.world.facts.moves.a=a;sim.world.facts.moves.b=b
  var retarget_reason:String=""
  if mode=="same_target_transfer":retarget_reason=sim.space.request_move(sim.world,"b",1,b.target_cell.duplicate())
  var before:Dictionary=sim.world.freeze()
  var eligible:bool=sim.space.movement._local_movable(sim.world,sim.world.facts.actors.b,b)
  var contact:=HospitalMovement.MotionResult.new()
  contact.requested_motion=Vector2(-0.2,0);contact.blocker_actor_ids.append("b")
  var actual_contact:bool=BodySweep.intersects(sim.space.body_rectangle(sim.world.facts.actors.a),sim.space._actor_rect(sim.world.facts.actors.a,Vector2(39.8,70)),sim.space.body_rectangle(sim.world.facts.actors.b),sim.space.body_rectangle(sim.world.facts.actors.b))
  sim.space.movement._local_collision(sim.world,sim.world.facts.actors.a,a,contact)
  var after:Dictionary=sim.world.freeze()
  var expected:bool=mode in ["area_travel","local_travel","returning","release","exiting"]
  var before_without_local:Dictionary=before.duplicate(true)
  var after_without_local:Dictionary=after.duplicate(true)
  before_without_local.moves.b.erase("local_move");after_without_local.moves.b.erase("local_move")
  var checks:Dictionary={"base_fixture_valid":initial_validation.is_empty(),"actual_current_body_contact":actual_contact,"expected_eligibility":eligible==expected,"expected_local_intention":b.has("local_move")==expected,"no_displacement":before.actors==after.actors,"only_blocker_local_intention_may_change":before_without_local==after_without_local,"life_task_preserved":before.staff.b.life_task==after.staff.b.life_task,"goal_sequence_cursor_route_preserved":before.moves.b.target_cell==b.target_cell and before.moves.b.request_sequence==b.request_sequence and before.moves.b.cursor==b.cursor and before.moves.b.path==b.path,"same_target_transfer_clears_marker":mode!="same_target_transfer" or retarget_reason.is_empty() and not b.has("waiting_seat_id")}
  var ok:bool=true
  for value:bool in checks.values():ok=ok and value
  rows.append({"case":mode,"ok":ok,"checks":checks,"initial_validation":initial_validation,"eligible":eligible,"movement":b.duplicate(true),"retarget_reason":retarget_reason})
  sim.dispose()
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"cases":rows,"scope":"Direct eligibility and one authored real-body contact only. Does not execute or complete a life journey; actual offshift travel is covered by CLIN-27. Minimal active-work/training guard inputs are not claimed as valid full work sessions."}
