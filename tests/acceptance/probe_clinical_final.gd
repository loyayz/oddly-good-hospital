extends SceneTree
func _initialize()->void:
 var f:=FileAccess.open("/workspace/scratch/6962cc21ddf3/clinical-lift-r4/clinical-final.bin",FileAccess.READ);var facts:Dictionary=f.get_var(false);f.close()
 var content:=HospitalContent.new();var world:=WorldState.new(facts);var sim:=HospitalSimulation.new(world,content)
 var bed:Dictionary=sim.space.facility_layout(world,"clin_ward_0");var candidates:Array=[]
 for direction:Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
  candidates.append({"direction":[direction.x,direction.y],"result":sim.clinic._escort_formation_candidate(world,"patient_00000005","clin_or_nurse",int(bed.floor_id),bed.patient_cell,direction)})
 var formation:Dictionary=ConvoyTrail.formation(sim.space,world,"patient_00000005",["patient_00000005","clin_or_nurse"],Vector2.RIGHT)
 var pf:Dictionary=facts.duplicate(true);pf.actors.clin_or_nurse.location={"kind":"floor","floor_id":1,"cell":formation.targets.clin_or_nurse}
 var projected:=WorldState.new(pf);var created:Dictionary=ConvoyTrail.create(sim.space,projected,"patient_00000005",["patient_00000005","clin_or_nurse"])
 var move:Dictionary={"actor_id":"patient_00000005","members":["patient_00000005","clin_or_nurse"],"convoy":created.convoy}
 projected.facts.moves.patient_00000005=move
 var proxy:Dictionary=ConvoyTrail.proxy(projected,move)
 var plan:Dictionary=ConvoyPortal.plan(sim.space,projected,pf.connectors.clin_lift,"patient_00000005",move.members,move.convoy)
 var approach:Dictionary=sim.space.navigation._convoy_portal_approach(projected,proxy,1,{"cell":Vector2(35,71),"convoy":move.convoy},plan)
 var legs:Array=[]
 for target:Vector2i in [Vector2i(56,74),Vector2i(58,74),Vector2i(54,74)]:
  var pp:Dictionary=proxy.duplicate();pp._convoy_goal_direction=Vector2.UP
  var leg:Dictionary=sim.space.navigation._floor_route(projected,pp,1,Vector2i(35,71),target,[],{},true,{},true,false)
  var predict:Dictionary=sim.space.navigation._convoy_predict_floor_path(move.convoy,leg.get("path",[]),Vector2.ZERO) if leg.get("ok",false) else {}
  legs.append({"target":[target.x,target.y],"leg":leg,"predict":predict})
 var floorroute:Dictionary=sim.space.route(projected,"patient_00000005",1,[56,72],move.members,{},true)
 var out:Dictionary={"visits":facts.visits,"actors":facts.actors,"moves":facts.moves,"stays":facts.ward_stays,"legs":legs,"plan":plan,"approach":approach,"floorroute":floorroute,"body":sim.space.body(facts.actors.patient_00000005),"formation":formation,"candidates":candidates,"rooms":facts.rooms,"facilities":facts.facilities}
 FileAccess.open("/workspace/scratch/6962cc21ddf3/clinical-lift-r4/diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify(out));sim.dispose();quit()
