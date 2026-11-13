extends SceneTree
const Cases=preload("res://tests/acceptance/space.gd")
func _initialize()->void:
 var suite=Cases.new();suite.content=HospitalContent.new();var results:Array=[]
 for species:String in ["S53","S59","S63"]:
  for rotation:int in 4:
   var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
   suite._command(s,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":[36,72],"rotation":rotation})
   suite._command(s,"connector_extend",{"connection_id":suite._connection(s),"floor_id":2})
   suite._add_actor(s,"nurse","S49",[45,85]);suite._add_actor(s,"patient",species,[45,70])
   var members:Array=["nurse","patient"];var form:Dictionary=ConvoyTrail.formation(s.space,s.world,"nurse",members)
   var c:Dictionary=s.world.facts.connectors[suite._connection(s)];LiftController.ensure(c)
   var p:Dictionary=ConvoyPortal.plan(s.space,s.world,c,"nurse",members,form)
   if not p.ok:results.append({"plan_error":p.reason});continue
   var trail:Dictionary={"version":1,"size":form.size,"spacing":form.spacing,"shift":form.shift,"centers":form.centers,"height":form.height,"floor_id":1,"points":p.initial_ground_points.duplicate(true),"portal":{"plan":p,"cursor":0,"stage":"boarding"}}
   var m:Dictionary={"actor_id":"nurse","members":members,"convoy":trail}
   s.world.facts.moves.nurse=m
   c.riders=members.duplicate();c.active_group="nurse";c.primary_actor_id="nurse";c.from=1;c.to=2
   c.passenger_groups=[{"actor_id":"nurse","leader_ids":["nurse"],"members":members,"from":1,"to":2,"receipt":"probe","cabin_positions":p.cabin_positions.duplicate(true)}]
   for mode:String in ["boarding_start","boarding_mid","riding","idle","alighting_start","alighting_mid","alighting_end"]:
    var stage:String="alighting" if mode.begins_with("alighting") else "boarding"
    c.phase=mode if mode in ["riding","idle"] else stage
    c.floor_id=2 if stage=="alighting" else 1
    trail.floor_id=2 if stage=="alighting" else 1
    trail.portal.stage=stage
    trail.portal.cursor=0 if mode.ends_with("start") else int(p[stage].size()/2) if mode.ends_with("mid") else p[stage].size()
    var poses:Dictionary=ConvoyTrail.positions(trail,members)
    for id:String in members:
     s.world.facts.actors[id].location={"kind":"transit","connector_id":c.id,"from":1,"to":2,"queue_cell":poses[id].cell,"cabin_cell":p.cabin_positions[id]}
     s.world.facts.actors[id].facing=poses[id].facing
    var row:Dictionary={"species":species,"rotation":rotation,"mode":mode,"error":ConvoyTrail.validate(s.space,s.world,m),"manifest_error":s.world._validate_lift_manifest(c,suite.content.definition("vertical_connectors",c.definition_id),s.space)}
    var restored:WorldState=WorldState.new(s.world.freeze())
    var cold:HospitalSimulation=HospitalSimulation.new(restored,suite.content)
    row.cold_error=ConvoyTrail.validate(cold.space,restored,restored.facts.moves.nurse)
    cold.dispose()
    trail.portal.cursor+=p[stage].size()+1;row.bad_cursor=ConvoyTrail.validate(s.space,s.world,m);trail.portal.cursor-=p[stage].size()+1
    var heading:float=s.world.facts.actors.nurse.facing
    s.world.facts.actors.nurse.facing=heading+0.5
    row.bad_facing=ConvoyTrail.validate(s.space,s.world,m);s.world.facts.actors.nurse.facing=heading
    trail.portal.stage="alighting" if stage=="boarding" else "boarding"
    row.bad_stage=ConvoyTrail.validate(s.space,s.world,m);trail.portal.stage=stage
    trail.portal.plan=p.duplicate(true);trail.portal.plan.entry[0]+=1
    row.bad_plan=ConvoyTrail.validate(s.space,s.world,m);trail.portal.plan=p
    var point:Array=c.passenger_groups[0].cabin_positions.nurse.duplicate()
    c.passenger_groups[0].cabin_positions.nurse=[point[0]+1,point[1]]
    row.bad_cabin=s.world._validate_lift_manifest(c,suite.content.definition("vertical_connectors",c.definition_id),s.space)
    c.passenger_groups[0].cabin_positions.nurse=point
    results.append(row)
   s.dispose()
 FileAccess.open("/workspace/scratch/6962cc21ddf3/articulated-schema-probe.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
 quit(0 if results.size()==84 and results.all(func(r:Dictionary)->bool:return r.get("error","bad").is_empty() and r.get("manifest_error","bad").is_empty() and r.get("cold_error","bad").is_empty() and not r.bad_cursor.is_empty() and not r.bad_facing.is_empty() and not r.bad_stage.is_empty() and not r.bad_plan.is_empty() and not r.bad_cabin.is_empty()) else 1)
