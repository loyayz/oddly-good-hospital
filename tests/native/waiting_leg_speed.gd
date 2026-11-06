extends SceneTree
const Before=preload("res://baseline.gd")
const After=preload("res://current.gd")
const World=preload("res://world.gd")
var checks:int=0
func check(ok:bool):
 checks+=1
 if not ok:push_error("failed "+str(checks));quit(1)
func run(s,world,bounds):return s.waiting_travel_ticks(world,"actor",1,Vector2i(8,8),bounds)
func _initialize():
 var w=World.new()
 w.facts.actors.actor={"id":"actor","species_id":"s","location":{"floor_id":1}}
 var bounds={"landings":[],"unknown":false}
 var a=Before.new();var b=After.new()
 for species in ["s","large"]:
  w.facts.actors.actor.species_id=species
  for speed in [0.01,0.7,1.3,100.0]:
   for s in [a,b]:
    s.space.views.clear()
    s.space.content.balance.movement_speeds={"1":speed,"2":speed}
   for distance in [0.0,0.00001,0.1,1.0,12.0,95.0,9216.0,1e17]:
    for s in [a,b]:s.leg={"ok":true,"walking_distance":distance}
    check(run(a,w,bounds)==run(b,w,bounds))
   for s in [a,b]:s.leg={"ok":false}
   check(run(a,w,bounds)==run(b,w,bounds))
   check(a.calls==b.calls)
   check(a.space.query_counts==b.space.query_counts)
 # Same-prefix overflow and body changes occur only after ending the sealed scope.
 for prefix in [0,9223372036854775807]:
  w.facts.actors.actor.prefix=prefix
  for s in [a,b]:
   s.space.views.clear();s.leg={"ok":true,"walking_distance":12}
  check(run(a,w,bounds)==run(b,w,bounds))
  check(run(b,w,bounds).travel_ticks==-1 if prefix>0 else run(b,w,bounds).travel_ticks==2)
 w.facts.actors.actor.erase("prefix")
 # Actual cross-floor basis validation: good lift proof, bad quote, unknown bounds.
 w.facts.actors.actor.location.floor_id=2
 w.facts.connectors={"lift":{"definition_id":"lift","anchor":[1,1]}}
 for valid in [true,false]:
  for unknown in [true,false]:
   var cross={"landings":[{"cell":Vector2(1,1),"ticks":13}],"unknown":unknown}
   for s in [a,b]:
    s.space.views={"point_journeys":{"subjects":{"actor":{"floor_id":2,"start":Vector2i(1,1),"initial_ticks":2,"reason":"","journeys":{JSON.stringify([1,[1,1],true],"",true,true):{"ok":true,"travel_ticks":13 if valid else 14}}}}}}
   check(run(a,w,cross)==run(b,w,cross))
   check(run(b,w,cross).is_empty()==(not valid or unknown))
 w.facts.actors.actor.location.floor_id=1
 w.facts.connectors={}
 var windows=[]
 for mode in ["success","cold","failure","unscoped","complex"]:
  for s in [a,b]:
   s.space.views.clear();s.space.scoped=mode!="unscoped"
   s.leg={"ok":mode!="failure","walking_distance":12}
  w.facts.connectors={"a":{},"b":{}} if mode=="complex" else {}
  check(run(a,w,bounds)==run(b,w,bounds))
  for old in [true,false,false,true,true,false,false,true,true,false,false,true]:
   var s=a if old else b
   var sum:int=0
   var start=Time.get_ticks_usec()
   for i in 20000:
    if mode=="cold":s.space.views.clear()
    var r=run(s,w,bounds)
    sum+=int(r.get("travel_ticks",-2))
   windows.append({"mode":mode,"old":old,"us":Time.get_ticks_usec()-start,"sum":sum})
 print(JSON.stringify({"checks":checks,"windows":windows}))
 quit()
