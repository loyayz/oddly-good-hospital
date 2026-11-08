extends "res://tests/acceptance/convoy_door_lifecycle.gd"
func run()->void:
 ROOT=OS.get_cmdline_user_args()[0]
 suite.content=HospitalContent.new()
 for label: String in ["normal_three_straight","normal_three_corner","cancel_then_new_singleton","cancel_then_follower_exit","cancel_restart_same_group"]:
  journey(label,false,label=="normal_three_corner",label.begins_with("cancel"))
 authorized_regroup_tail()
 _subsequent_real_user()
 var ordinary: Dictionary=preload("res://tests/acceptance/ordinary_door_passage.gd").new().run_passage(suite.content)
 rows.append({"case":"ordinary_door_four","ok":ordinary.passed,"details":ordinary})
 save(".trace",trace)
 var ok: bool=not rows.any(func(row: Dictionary)->bool:return not row.ok)
 save(".result",{"ok":ok,"rows":rows,"scope":"v18 real convoy tail/cancellation/regroup/reuse and ordinary door regressions"})
 quit(0 if ok else 1)
func _subsequent_real_user()->void:
 var sim: HospitalSimulation=suite._fixture();var w: WorldState=sim.world
 var build: CommandResult=suite._command(sim,"build_room",suite._room("reuse_room",[35,68],[8,8]))
 var door: Dictionary=suite._doors(w,"reuse_room")[0]
 var members: Array=["leader","middle","tail"]
 suite._add_actor(sim,"leader","S49",[36,73]);suite._add_actor(sim,"middle","S49",[36,71]);suite._add_actor(sim,"tail","S49",[36,69])
 var request: String=sim.space.request_group_move(w,"leader",members,{},1,[36,84])
 var acquired: bool=false;var head_clear_tail_held: bool=false;var safety: bool=true
 for tick: int in 200:
  var before: Dictionary=w.freeze()
  suite._movement_tick(sim)
  safety=safety and motion_errors(sim,before,members).is_empty()
  if w.facts.adaptations.has(door.id):
   acquired=true
   var aperture: Rect2=sim.space._door_rect(door,int(w.facts.adaptations[door.id].span))
   head_clear_tail_held=head_clear_tail_held or (not sim.space.body_rectangle(w.facts.actors.leader).intersects(aperture,false) and not overlaps_members(sim,members,aperture,true).is_empty())
  if not w.facts.moves.has("leader"):break
 var finished: bool=sim.space.at(w,"leader",1,[36,84]) and not w.facts.moves.has("leader")
 var released: bool=not w.facts.adaptations.has(door.id)
 suite._add_actor(sim,"next_user","S49",[38,78])
 var next_request: String=sim.space.request_move(w,"next_user",1,[36,70])
 var entered: bool=false
 for tick: int in 240:
  suite._movement_tick(sim)
  var body: Rect2=sim.space.body_rectangle(w.facts.actors.next_user)
  entered=entered or body.intersects(sim.space._door_rect(door,int(door.span)),false)
  for id: String in members:safety=safety and not body.intersects(sim.space.body_rectangle(w.facts.actors[id]),false)
  if not w.facts.moves.has("next_user"):break
 var arrived: bool=sim.space.at(w,"next_user",1,[36,70]) and not w.facts.moves.has("next_user")
 rows.append({"case":"new_actual_user_after_convoy_tail_release","ok":build.accepted and request.is_empty() and acquired and head_clear_tail_held and finished and released and next_request.is_empty() and entered and arrived and safety and w.validate(suite.content).is_empty(),"acquired":acquired,"head_clear_tail_still_held":head_clear_tail_held,"group_arrived":finished,"released_after_group":released,"new_request":next_request,"new_body_entered_door":entered,"new_user_arrived":arrived,"no_overlap_or_teleport":safety,"validation":w.validate(suite.content)})
 sim.dispose()
