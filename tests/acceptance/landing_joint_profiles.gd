extends "res://tests/acceptance/directional_elevator_contract.gd"
func run()->void:
 suite.content=HospitalContent.new()
 var s:=fixture()
 for x:int in range(32,70):
  s.world.facts.floors.overrides["1"].blocked.append([x,75])
  s.world.facts.floors.overrides["1"].blocked.append([x,84])
 s.world.touch()
 suite._add_actor(s,"nurse","S49",[55,78]);suite._add_actor(s,"patient","S49",[55,80]);suite._add_actor(s,"family","S49",[60,83])
 var request:String=s.space.movement.request_group_move(s.world,"nurse",["nurse","patient"],{},1,[48,78])
 var nursing:Dictionary=s.world.facts.moves.get("nurse",{})
 var report:Dictionary={"scope":"Composite nursing convoy and family waiting envelopes; geometry proof only, no claimed actual elevator arrival","request":request,"ok":false}
 if nursing.has("convoy"):
  var family:Dictionary={"actor_id":"family","members":["family"]}
  var a:Rect2=LiftLandingQueue._body(s.space,s.world,nursing,[45,78])
  var b:Rect2=LiftLandingQueue._body(s.space,s.world,family,[45,83])
  report.nursing=LiftLandingQueue._rect_key(a);report.family=LiftLandingQueue._rect_key(b)
  report.old_publication=LiftLandingQueue._publication_clear(s.space,s.world,1,[a,b],[])
  report.old_joint=LiftLandingQueue._preserves_passage(s.space,s.world,1,a,[]) and LiftLandingQueue._preserves_passage(s.space,s.world,1,b,[a])
  suite._add_actor(s,"large","S53",[60,76])
  report.large_legal=s.space.static_reason(s.world,s.world.facts.actors.large,1,Vector2i(60,76))
  report.single_nursing=LiftLandingQueue._preserves_passage(s.space,s.world,1,a,[])
  report.single_family=LiftLandingQueue._preserves_passage(s.space,s.world,1,b,[])
  report.new_publication=LiftLandingQueue._publication_clear(s.space,s.world,1,[a,b],[])
  report.occupancy_signature_order_independent=LiftLandingQueue._occupied_signature([a,b])==LiftLandingQueue._occupied_signature([b,a])
  report.occupancy_signature_movement_changes=LiftLandingQueue._occupied_signature([a])!=LiftLandingQueue._occupied_signature([Rect2(a.position+Vector2.RIGHT,a.size)])
  report.new_joint=LiftLandingQueue._preserves_passage(s.space,s.world,1,b,[a])
  report.validation=s.world.validate(suite.content)
  report.ok=report.old_publication and not report.new_publication and report.occupancy_signature_order_independent and report.occupancy_signature_movement_changes and request.is_empty() and report.old_joint and report.single_nursing and report.single_family and not report.new_joint and report.large_legal.is_empty() and report.validation.is_empty()
 var args:=OS.get_cmdline_user_args()
 if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));s.dispose();quit(0 if report.ok else 1)
