extends SceneTree
# Geometry-selection unit: door query is explicit; real structural/body sweep
# checks stay enabled. Full-world motion/ownership is covered by the checkpoint.
class DoorSpace extends HospitalSpace:
 var doors:Array[Dictionary]=[]
 func _init(c:HospitalContent)->void:super(c)
 func movement_doors(_w:WorldState,_a:Dictionary,_s:Rect2,_m:Array=[],_f:int=0,_g:FloorStaticGeometry=null)->Array[Dictionary]:return doors
func _initialize()->void:call_deferred("run")
func run()->void:
 var content:=HospitalContent.new()
 var suite=load("res://tests/acceptance/space.gd").new();suite.content=content
 var rows:Array=[]
 for direction:float in [-1.0,1.0]:
  for adjacent:bool in [false,true]:
   var sim:HospitalSimulation=suite._fixture()
   suite._add_actor(sim,"walker","S27",[40,80])
   var space:=DoorSpace.new(content)
   var actor:Dictionary=sim.world.facts.actors.walker
   var start:Vector2=ConvoyTrail.point(actor.location.cell)
   var target:Vector2=start+Vector2(direction,0)
   space.doors=[{"cell":[target.x,target.y],"axis":"x","span":1,"id":"first"}]
   if adjacent:
    # After clearing first door, candidate would finish in this other door.
    space.doors.append({"cell":[target.x+direction,target.y],"axis":"x","span":1,"id":"adjacent"})
   var movement:Dictionary={"actor_id":"walker","cursor":0,"path":[{"kind":"floor","floor_id":1,"cell":[40,85]}],"travelled":[],"request_sequence":1,"target_floor":1,"target_cell":[40,85]}
   # Other-side body forbids that sidestep. A retreat remains an intention
   # and must pass real collision checks when executed, not at selection.
   suite._add_actor(sim,"other_side","S27",[40-direction,80])
   suite._add_actor(sim,"rear","S27",[40,80+direction])
   var before:Dictionary=actor.duplicate(true)
   var ok:bool=space.movement._local_choose(sim.world,actor,movement,Vector2(0,-direction))
   var clear:bool=false
   if ok:
    var pose:Dictionary=actor.duplicate();pose.facing=atan2(direction,0)
    var rect:Rect2=space._actor_rect(pose,ConvoyTrail.point(movement.local_move.target.cell))
    clear=true
    for door:Dictionary in space.doors:clear=clear and not rect.intersects(space._door_rect(door,1),false)
   rows.append({"direction":direction,"adjacent":adjacent,"accepted":ok,"actual_final_facing_clear":clear,"pose_unchanged":actor==before,"ok":actor==before and ((not ok or movement.local_move.target.cell[0]==40.0) if adjacent else ok and clear),"move":movement})
   sim.dispose()
 var result:Dictionary={"scope":"isolated door query geometry selection, not full application acceptance","ok":rows.all(func(r:Dictionary)->bool:return r.ok),"cases":rows}
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print(JSON.stringify(result));quit(0 if result.ok else 1)
