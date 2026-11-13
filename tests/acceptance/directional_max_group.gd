extends SceneTree
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
var lift_cell:Array=[36,32]
var wide_input:bool=false
func _initialize()->void:call_deferred("run")
func prepare(species:String="S63")->Dictionary:
 suite.content=HospitalContent.new()
 var s:HospitalSimulation=suite._fixture()
 # Explicit independent historical wide/high landing. No in-flight person,
 # previous clinical obligation, species or movement is rewritten.
 s.world.facts.floors.overrides["1"].plots.append([1,1])
 s.world.facts.floors.completed_top_floor["1:1"]=2
 s.world.facts.floors.completed_top_floor["1:2"]=2
 s.world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":8.0}]
 if wide_input:
  for x:int in range(3):
   for y:int in range(3):
    if not [x,y] in s.world.facts.floors.overrides["1"].plots:s.world.facts.floors.overrides["1"].plots.append([x,y])
    s.world.facts.floors.completed_top_floor[str(x)+":"+str(y)]=2
 s.world.touch()
 var built:CommandResult=suite._command(s,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":lift_cell})
 if not built.accepted:return {"ok":false,"error":built.reason,"sim":s}
 var id:String=str(built.changed_ids[0])
 var extended:CommandResult=suite._command(s,"connector_extend",{"connection_id":id,"floor_id":2})
 if not extended.accepted:return {"ok":false,"error":extended.reason,"sim":s}
 suite._add_actor(s,"max_nurse","S49",[50,50]);suite._add_actor(s,"max_patient",species,[39,49])
 var members:Array=["max_nurse","max_patient"]
 var form:Dictionary=ConvoyTrail.formation(s.space,s.world,members[0],members,Vector2.UP)
 for who:String in members:s.world.facts.actors[who].location.cell=form.targets[who].duplicate();s.space.sync_actor(s.world,who)
 var created:Dictionary=ConvoyTrail.create(s.space,s.world,members[0],members)
 if not created.ok:return {"ok":false,"error":created.reason,"sim":s}
 var plan:Dictionary=ConvoyPortal.plan(s.space,s.world,s.world.facts.connectors[id],members[0],members,created.convoy)
 if not plan.ok:return {"ok":false,"error":plan.reason,"sim":s}
 # Declared pre-move initial formation at the real local-handoff entry.
 for who:String in members:
  s.world.facts.actors[who].location.cell=plan.initial_poses[who].cell.duplicate()
  s.world.facts.actors[who].facing=plan.initial_poses[who].facing
  s.space.sync_actor(s.world,who)
 created=ConvoyTrail.create(s.space,s.world,members[0],members)
 s.world.facts.move_request_next=int(s.world.facts.get("move_request_next",0))+1
 var move:Dictionary={"actor_id":members[0],"members":members,"convoy":created.convoy,"path":[{"kind":"connector","connector_id":id,"from":1,"to":2}],"cursor":0,"travelled":[s.space.movement._checkpoint(s.world.facts.actors[members[0]])],"blocked_since":-1,"yielding":false,"target_floor":2,"target_cell":plan.egress.duplicate(),"request_sequence":s.world.facts.move_request_next}
 s.world.facts.moves[members[0]]=move;s.world.touch();s.space._sync_convoys(s.world)
 return {"ok":true,"sim":s,"connector_id":id,"leader":members[0],"members":members,"target":plan.egress,"plan":plan}
func step(c:Dictionary)->void:suite._movement_tick(c.sim)
func complete(c:Dictionary)->bool:return c.sim.space.at(c.sim.world,c.leader,2,c.target) and not c.sim.world.facts.moves.has(c.leader)
func run()->void:
 var args:=OS.get_cmdline_user_args();var c:Dictionary=prepare(args[1] if args.size()>1 else "S63")
 var errors:Array=[];var seen:Array=[];var trace:Array=[];var done:bool=false
 if not c.ok:errors.append(c.error)
 var s:HospitalSimulation=c.sim
 var initial:String=s.world.validate(suite.content)
 if not initial.is_empty():errors.append(initial)
 FileAccess.open(args[0]+".input.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 for i:int in 2400:
  if not errors.is_empty():break
  step(c)
  var error:String=s.world.validate(suite.content)
  if not error.is_empty():errors.append({"tick":s.world.sim_tick,"error":error});break
  var lift:Dictionary=s.world.facts.connectors[c.connector_id]
  if not lift.phase in seen:seen.append(lift.phase)
  if i%25==0:trace.append({"tick":s.world.sim_tick,"lift":lift.duplicate(true),"moves":s.world.facts.moves.duplicate(true)})
  if complete(c):done=true;break
  if i%100==99:print("MAX_PORTAL_PROGRESS ",s.world.sim_tick," ",lift.phase);await process_frame
 var result:Dictionary={"ok":done and errors.is_empty(),"done":done,"errors":errors,"seen":seen,"tick":s.world.sim_tick,"scope":"Independent legal maximal nursing two-body transport; not yet three-body clinical or performance acceptance","moves":s.world.facts.moves}
 FileAccess.open(args[0]+".final.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 FileAccess.open(args[0]+".trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace))
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 s.dispose();print(JSON.stringify(result));quit(0 if result.ok else 1)
