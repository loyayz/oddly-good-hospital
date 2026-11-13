extends SceneTree
# Legal construction and historical floor input, followed by actual physical
# queueing, boarding and alighting. No direct relocation after the input.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func travel(turns:int,species:String,definition:String,stem:String)->Dictionary:
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
 var built:CommandResult=suite._command(s,"connector_build",{"definition_id":definition,"floor_id":1,"cell":[44,76],"rotation":turns})
 if not built.accepted:
  var r:Dictionary={"ok":false,"turns":turns,"species":species,"build":built.to_record(),"kind":"input_rejected"};s.dispose();return r
 var cid:String=suite._connection(s);var extended:CommandResult=suite._command(s,"connector_extend",{"connection_id":cid,"floor_id":2})
 suite._add_actor(s,"rider",species,[55,90],1)
 var initial:String=s.world.validate(suite.content);var req:String=s.space.request_move(s.world,"rider",2,[55,90]);var c:Dictionary=s.world.facts.connectors[cid]
 var errors:Array=[];var entries:Array=[];var boarded:bool=false;var landed:bool=false;var done:bool=false;var steps:int=0
 if not initial.is_empty():errors.append(initial)
 if not stem.is_empty():FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
 for i:int in 1600:
  if not errors.is_empty():break
  suite._movement_tick(s);steps=i+1
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  for line:Array in c.get("landing_queues",{}).values():
   for e:Dictionary in line:
    var point:Array=e.cell
    if not point in entries:entries.append(point.duplicate())
  var a:Dictionary=s.world.facts.actors.rider
  boarded=boarded or a.location.kind=="transit"
  landed=landed or (boarded and a.location.kind=="floor" and int(a.location.floor_id)==2)
  done=s.space.at(s.world,"rider",2,[55,90]) and not s.world.facts.moves.has("rider")
  if done:break
 var result:Dictionary={"ok":extended.accepted and req.is_empty() and not entries.is_empty() and boarded and landed and done and errors.is_empty(),"turns":turns,"species":species,"definition":definition,"clearance":s.space.clearance(s.world.facts.actors.rider),"build":built.to_record(),"extend":extended.to_record(),"request":req,"queue_positions":entries,"actual_boarding":boarded,"actual_alighting":landed,"arrived":done,"steps":steps,"errors":errors,"final_connector":c.duplicate(true),"final_moves":s.world.facts.moves.duplicate(true),"final_actor":s.world.facts.actors.rider.duplicate(true)}
 if not stem.is_empty():FileAccess.open(stem+"-after.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
 s.dispose();return result
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var stem:String=args[0] if not args.is_empty() else "";var rows:Array=[]
 for turns:int in [1,2,3]:
  for item:Array in [["S49","VC02"],["S11","VC02"],["S53","VC03"]]:
   rows.append(travel(turns,item[0],item[1],stem+"-r%d-%s"%[turns,item[0]] if not stem.is_empty() else ""))
 var report:Dictionary={"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows,"scope":"90/180/270 degree doors with 1/2/3-cell bodies; actual empty-floor lawful journeys, not congestion or capacity proof"}
 if not stem.is_empty():FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));quit(0 if report.ok else 1)
