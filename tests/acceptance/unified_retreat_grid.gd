extends RefCounted
# Local geometry/intent contract, not evidence of a natural journey completing.
func run(content:HospitalContent)->Dictionary:
 var suite:RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[]
 for species:String in ["S49","S11"]:
  for fractional:bool in [false,true]:
   for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
    rows.append(_case(suite,species,fractional,direction,false))
    rows.append(_case(suite,species,fractional,direction,true))
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 return {"ok":ok,"scope":"Local geometry only; supplied travelled checkpoint is input history, not a newly simulated trip.","cases":rows}

func _case(suite:RefCounted,species:String,fractional:bool,back:Vector2,history:bool)->Dictionary:
 var sim:HospitalSimulation=suite._fixture()
 var start:Vector2=Vector2(40,70)+(Vector2(0.25,0.25) if fractional else Vector2.ZERO)
 suite._add_actor(sim,"walker",species,[start.x,start.y])
 var actor:Dictionary=sim.world.facts.actors.walker
 actor.facing=atan2(-back.x,-back.y)
 sim.space.sync_actor(sim.world,"walker")
 var span:int=sim.space.clearance(actor)
 # A corridor whose side walls reject both full neighbouring footprints,
 # while its axial direction stays open. No body begins inside a wall.
 var low:int=int(floorf(start.y if back.x!=0 else start.x))-1
 var high:int=int(ceilf((start.y if back.x!=0 else start.x)+span))
 for coordinate:int in range(30,85):
  for side:int in [low,high]:
   var cell:Array=[coordinate,side] if back.x!=0 else [side,coordinate]
   HospitalFactory._put_cell(sim.world.facts.floors.overrides["1"].blocked,cell)
 sim.world.touch()
 var expected:Vector2=start
 if back.x>0:expected.x=floorf(start.x)+span
 elif back.x<0:expected.x=ceilf(start.x)-span
 elif back.y>0:expected.y=floorf(start.y)+span
 else:expected.y=ceilf(start.y)-span
 var travelled:Array=[]
 if history:
  expected=start+back*(span+0.5)
  travelled=[{"kind":"floor","floor_id":1,"cell":[expected.x,expected.y]},{"kind":"floor","floor_id":1,"cell":[start.x,start.y]}]
 var forward_target:Vector2=start-back*span
 var movement:Dictionary={"actor_id":"walker","members":["walker"],"cursor":0,"path":[{"kind":"floor","floor_id":1,"cell":[forward_target.x,forward_target.y]}],"travelled":travelled.duplicate(true)}
 var before_actor:Dictionary=actor.duplicate(true)
 var before_history:Array=movement.travelled.duplicate(true)
 var query:RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
 var lateral:Vector2=Vector2(-back.y,back.x)*span
 var valid_start:bool=query.sweep_reason(start,start).is_empty()
 var sides_blocked:bool=not query.sweep_reason(start,start+lateral).is_empty() and not query.sweep_reason(start,start-lateral).is_empty()
 var picked:bool=sim.space.movement._local_choose(sim.world,actor,movement,-back)
 var local:Dictionary=movement.get("local_move",{})
 var actual:Vector2=ConvoyTrail.point(local.get("target",{}).get("cell",[0,0]))
 var validation:String=sim.world.validate(suite.content)
 var checks:Dictionary={"legal_world_and_body":validation.is_empty() and valid_start,"two_static_sides_blocked":sides_blocked,"correct_real_span":span==1 if species=="S49" else span>1,"retreat_selected":picked and local.get("retreat",false),"exact_expected_target":actual==expected,"nonmoving_axis_exact":actual.y==start.y if back.x!=0 else actual.x==start.x,"no_body_move_or_fact_change":actor==before_actor,"history_not_written":movement.travelled==before_history,"declared_target_static_clear":query.sweep_reason(start,actual).is_empty()}
 var ok:bool=true
 for value:bool in checks.values():ok=ok and value
 var result:Dictionary={"ok":ok,"species":species,"span":span,"fractional":fractional,"back":[back.x,back.y],"checkpoint_input":history,"start":[start.x,start.y],"expected":[expected.x,expected.y],"local":local,"checks":checks,"validation":validation}
 sim.dispose();return result
