extends SceneTree
const Before=preload("res://baseline.gd")
const After=preload("res://current.gd")
const Floor=preload("res://floor.gd")
const Space=preload("res://space.gd")
const World=preload("res://world.gd")
var checks: int = 0
func make_state(script: Script,length: int)->Dictionary:
 var state={"cache":script.new(),"graph":Floor.new(),"space":Space.new(),"world":World.new(),"actor":{"id":"actor"}}
 var cells:Array=[]
 for i:int in length: cells.append([i%96,i/96])
 state.graph.result={"ok":true,"status":"complete","walking_distance":length,"cells":cells}
 state.cache._entries={"graph":{"graph":state.graph,"charge":0}}
 return state
func run(state:Dictionary,cost_only:bool=false)->Dictionary:
 return state.cache.cached_floor_path(state.space,state.world,1,state.actor,state.graph,state.graph.geometry,Vector2i(0,0),Vector2i(95,95),cost_only)
func check(value:bool)->void:
 checks+=1
 if not value: push_error("check failed "+str(checks)); quit(1)
func _initialize()->void:
 for length:int in [0,1,32,192,1024,9216]:
  var old=make_state(Before,length)
  var new=make_state(After,length)
  for cost_only:bool in [true,true,false,false,true,false]:
   var a=run(old,cost_only)
   var b=run(new,cost_only)
   check(a==b)
   check(old.cache._query_charged==new.cache._query_charged)
   check(old.space.query_counts==new.space.query_counts)
   if b.has("cells"):
    check(b.cells==new.graph.result.cells)
    b.cells.append([-1,-1])
    check(run(new).cells==new.graph.result.cells)
    run(old)
  check(old.graph.builds==new.graph.builds)
  var saved:Dictionary=new.cache._entries.graph.structural_paths.paths[Vector4i(0,0,95,95)]
  check(saved.cells is PackedInt32Array)
  check(saved.cells.size()==length)
  for i:int in length: check(saved.cells[i]==i)
  check(not saved.value.has("cells"))
 for failed:bool in [true,false]:
  for fallback:bool in [true,false]:
   var old=make_state(Before,32)
   var new=make_state(After,32)
   if failed:
    old.graph.result={"ok":false,"status":"unreachable","reason":"explicit failure"}
    new.graph.result=old.graph.result.duplicate(true)
   if fallback:
    old.cache._entries.clear()
    new.cache._entries.clear()
   for i:int in 3:
    check(run(old)==run(new))
    check(old.cache._query_charged==new.cache._query_charged)
    check(old.space.query_counts==new.space.query_counts)
   check(new.graph.builds==(3 if fallback else 1))
 var windows:Array=[]
 for length:int in [0,32,192]:
  for hit:bool in [true,false]:
   var a=make_state(Before,length)
   var b=make_state(After,length)
   run(a);run(b)
   for old:bool in [true,false,false,true,true,false,false,true,true,false,false,true]:
    var s:Dictionary=a if old else b
    var start=Time.get_ticks_usec()
    var sum:int=0
    for i:int in 1000:
     if not hit:
      s.cache._entries.graph.erase("structural_paths")
      s.cache._entries.graph.query_charge=0
      s.cache._query_charged=0
     sum+=run(s).cells.size()
    windows.append({"length":length,"hit":hit,"old":old,"us":Time.get_ticks_usec()-start,"sum":sum})
 print(JSON.stringify({"checks":checks,"windows":windows}))
 quit()
