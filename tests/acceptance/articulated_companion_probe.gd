extends SceneTree
# Boundary test only: constructs a legally seated nursing pair. Does not
# substitute for the complete live floor-to-floor journey or clinical load.
const Cases=preload("res://tests/acceptance/space.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var suite=Cases.new();suite.content=HospitalContent.new();var results:Array=[]
 for species:String in ["S53","S59","S63"]:
  for rotation:int in 4:
   var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
   # Declared wide clear geometry fixture, not a change to an active journey.
   s.world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":8.0}]
   for x:int in range(3):
    for y:int in range(3):
     if not [x,y] in s.world.facts.floors.overrides["1"].plots:s.world.facts.floors.overrides["1"].plots.append([x,y])
     s.world.facts.floors.completed_top_floor[str(x)+":"+str(y)]=2
   s.world.touch()
   suite._command(s,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":[48,48],"rotation":rotation})
   var c:Dictionary=s.world.facts.connectors[suite._connection(s)]
   suite._command(s,"connector_extend",{"connection_id":c.id,"floor_id":2});c=s.world.facts.connectors[suite._connection(s)];LiftController.ensure(c)
   suite._add_actor(s,"nurse","S49",[45,85]);suite._add_actor(s,"patient",species,[45,70]);suite._add_actor(s,"family",species,[75,85])
   var members:Array=["nurse","patient"]
   var form:Dictionary=ConvoyTrail.formation(s.space,s.world,"nurse",members)
   var nursing:Dictionary=ConvoyPortal.plan(s.space,s.world,c,"nurse",members,form)
   if not nursing.ok:results.append({"species":species,"rotation":rotation,"error":nursing.reason});s.dispose();continue
   var target:Vector2=LiftLandingQueue.companion_entry(s.space,s.world.facts.actors.family,nursing,s.space.clearance(s.world.facts.actors.nurse))
   var plan:Dictionary={};var def:Dictionary=suite.content.definition("vertical_connectors",c.definition_id)
   var size:int=s.space.clearance(s.world.facts.actors.family)
   for y:int in range(int(def.cabin_size[1])-size+1):
    if plan.get("ok",false):break
    for x:int in range(int(def.cabin_size[0])-size+1):
     plan=ArticulatedLiftPortal.companion_plan(s.space,s.world,c,nursing,"family",[target.x,target.y],[x,y],0.37)
     if plan.get("ok",false):break
   if not plan.get("ok",false):results.append({"species":species,"rotation":rotation,"error":plan.get("reason","no candidate")});s.dispose();continue
   var trail:Dictionary=form.duplicate(true);trail.floor_id=1;trail.points=nursing.initial_ground_points.duplicate(true);trail.portal={"plan":nursing,"cursor":nursing.boarding.size(),"stage":"boarding"}
   s.world.facts.moves.nurse={"actor_id":"nurse","members":members,"convoy":trail}
   s.world.facts.moves.family={"actor_id":"family","lift_pending_boarding":{"connector_id":c.id,"group_leader":"nurse"}}
   var g:Dictionary={"actor_id":"nurse","leader_ids":["nurse"],"members":members.duplicate(),"from":1,"to":2,"receipt":"companion-probe","cabin_positions":nursing.cabin_positions.duplicate(true),"entry_cells":{"family":[target.x,target.y]},"pending_boarding":[{"actor_id":"family","members":["family"],"entry_cell":[target.x,target.y],"cabin_positions":{"family":plan.cabin_position}}],"companion_portals":{"family":{"plan":plan,"cursor":0,"stage":"boarding"}}}
   c.passenger_groups=[g];c.riders=members.duplicate();c.phase="boarding";c.active_group="nurse";c.primary_actor_id="nurse"
   for id:String in members:
    var pose:Dictionary=nursing.boarding[-1].poses[id]
    s.world.facts.actors[id].location={"kind":"transit","connector_id":c.id,"from":1,"to":2,"queue_cell":pose.cell,"cabin_cell":nursing.cabin_positions[id]};s.world.facts.actors[id].facing=pose.facing
   s.world.facts.actors.family.location={"kind":"floor","floor_id":1,"cell":plan.initial_pose.cell.duplicate()};s.world.facts.actors.family.facing=plan.initial_pose.facing
   s.world.touch();s.space._ensure_actor_index(s.world)
   var errors:Array=[];var samples:Array=[]
   for stage:String in ["boarding","alighting"]:
    var portal:Dictionary=g.companion_portals.family
    if stage=="alighting":
     g.erase("pending_boarding");s.world.facts.moves.family.erase("lift_pending_boarding")
     g.members.append("family");g.leader_ids.append("family");g.cabin_positions.family=plan.cabin_position;c.riders=g.members.duplicate()
     s.world.facts.actors.family.location={"kind":"transit","connector_id":c.id,"from":1,"to":2,"cabin_cell":plan.cabin_position,"queue_cell":plan.seated_pose.cell}
     c.floor_id=2;c.phase="alighting";g.exit_stage="companions";portal.stage=stage;portal.cursor=0
     s.space._sync_actor(s.world,"family")
    for i:int in plan[stage].size():
     var before:int=int(portal.cursor)
     LiftController._companion_step(s.space,s.world,c,g,"family",int(c.floor_id))
     if int(portal.cursor)!=before+1:errors.append({"stage":stage,"cursor":before,"blocked":c.get("waiting_reason","")});break
     var error:String=s.world._validate_lift_manifest(c,def,s.space)
     if not error.is_empty():errors.append({"stage":stage,"cursor":portal.cursor,"error":error});break
     if i==int(plan[stage].size()/2):
      var cold:=HospitalSimulation.new(WorldState.new(s.world.freeze()),suite.content)
      var cold_c:Dictionary=cold.world.facts.connectors[c.id]
      var cold_error:String=cold.world._validate_lift_manifest(cold_c,def,cold.space)
      cold.space._ensure_actor_index(cold.world)
      var indexed:bool=cold.space._actor_index._records.has("family")
      var altered:Dictionary=cold_c.passenger_groups[0].companion_portals.family
      altered.cursor=plan[stage].size()+1
      var rejected:bool=not cold.world._validate_lift_manifest(cold_c,def,cold.space).is_empty()
      samples.append({"stage":stage,"cold_error":cold_error,"indexed":indexed,"bad_cursor_rejected":rejected})
      cold.dispose()
   results.append({"species":species,"rotation":rotation,"errors":errors,"samples":samples,"boarding_frames":plan.boarding.size(),"alighting_frames":plan.alighting.size()});s.dispose()
 var args:=OS.get_cmdline_user_args()
 if args.size()>0:FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
 print(JSON.stringify(results))
 quit(0 if results.size()==12 and results.all(func(r:Dictionary)->bool:return r.has("errors") and r.errors.is_empty() and r.samples.size()==2 and r.samples.all(func(p:Dictionary)->bool:return p.cold_error.is_empty() and p.indexed and p.bad_cursor_rejected)) else 1)
