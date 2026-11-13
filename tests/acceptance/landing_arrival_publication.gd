extends "res://tests/acceptance/directional_elevator_contract.gd"
# Draft: run only after copying into the repository at an approved freeze boundary.
# No location/queue fabrication: the small actor walks using production advance.
func run()->void:
 suite.content=HospitalContent.new()
 var rows:Array=[boundary(false),boundary(true)]
 var ok:bool=true
 for row:Dictionary in rows:ok=ok and row.ok
 var report:Dictionary={"ok":ok,"rows":rows}
 var args:=OS.get_cmdline_user_args()
 if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));quit(0 if ok else 1)
func boundary(at_endpoint:bool)->Dictionary:
 var s:=fixture();var c:Dictionary=s.world.facts.connectors[suite._connection(s)];c.floor_id=4
 for x:int in range(32,65):
  s.world.facts.floors.overrides["1"].blocked.append([x,75])
  s.world.facts.floors.overrides["1"].blocked.append([x,79])
 s.world.touch();suite._add_actor(s,"small","S49",[48,77])
 var reason:String=s.space.request_move(s.world,"small",2,[45,82])
 var found:bool=false;var target:Dictionary={};var errors:Array=[]
 for tick:int in 500:
  suite._movement_tick(s)
  var m:Dictionary=s.world.facts.moves.get("small",{})
  target=m.get("lift_queue_target",{}).duplicate(true)
  if not target.is_empty() and LiftLandingQueue.head(c,1,1).is_empty():
   var arrived:bool=LiftLandingQueue._arrived(s.space,s.world,m,target)
   if arrived==at_endpoint and float(s.world.facts.actors.small.location.cell[0])<44.0:found=true;break
 var report:Dictionary={"case":"endpoint_before_publication" if at_endpoint else "old_target_walking","request":reason,"boundary_found":found,"old_target":target,"errors":errors,"ok":false}
 if found:
  suite._add_actor(s,"large","S53",[48,76])
  report.large_legal=s.space.static_reason(s.world,s.world.facts.actors.large,1,Vector2i(48,76))
  report.initial_no_overlap=not s.space.body_rectangle(s.world.facts.actors.small).intersects(s.space.body_rectangle(s.world.facts.actors.large),false)
  report.old_target_unsafe=not LiftLandingQueue._preserves_passage(s.space,s.world,1,LiftLandingQueue._body(s.space,s.world,s.world.facts.moves.small,target.cell),[])
  report.signature_changed=target.get("passage_profiles",[])!=s.space.passage_profile_signature(s.world,1)
  var before:Dictionary=s.world.facts.actors.duplicate(true)
  LiftLandingQueue.sync(s.space,s.world,c)
  report.no_teleport=before==s.world.facts.actors
  report.no_false_entry=LiftLandingQueue.head(c,1,1).is_empty()
  report.no_invitation=not s.world.facts.moves.small.has("lift_boarding_call")
  report.standby=s.world.facts.moves.small.get("lift_queue_standby",{}).duplicate(true)
  report.validation=s.world.validate(suite.content)
  # Observe real safe follow-on motion; the large actor is an actual obstacle.
  for tick:int in 160:
   suite._movement_tick(s)
   var error:String=s.world.validate(suite.content)
   if not error.is_empty():errors.append(error)
   if s.space.body_rectangle(s.world.facts.actors.small).intersects(s.space.body_rectangle(s.world.facts.actors.large),false):errors.append("Bodies overlapped")
   var entry:Dictionary=LiftLandingQueue.head(c,1,1)
   if not entry.is_empty() and entry.has("owner_cells"):
    var b:Rect2=LiftLandingQueue._body(s.space,s.world,s.world.facts.moves.small,entry.cell)
    if not LiftLandingQueue._preserves_passage(s.space,s.world,1,b,[]):errors.append("Unsafe queue published")
  report.final_location=s.world.facts.actors.small.location.duplicate(true)
  report.ok=reason.is_empty() and report.large_legal.is_empty() and report.initial_no_overlap and report.old_target_unsafe and report.signature_changed and report.no_teleport and report.no_false_entry and report.no_invitation and report.validation.is_empty() and errors.is_empty()
 s.dispose();return report
