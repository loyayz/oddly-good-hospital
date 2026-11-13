extends SceneTree
var space:HospitalSpace
var nav:HospitalNavigation
func _initialize()->void:call_deferred("run")
func run()->void:
 var content:=HospitalContent.new()
 var args:=OS.get_cmdline_user_args()
 if args.size()!=1:push_error("Expected actual saved failed entrance facts");quit(2);return
 var facts:Dictionary=FileAccess.open(args[0],FileAccess.READ).get_var(false)
 var s:=HospitalSimulation.new(WorldState.new(facts),content)
 space=s.space;nav=space.navigation
 var m:Dictionary=s.world.facts.moves.max_nurse
 var c:Dictionary=s.world.facts.connectors.values()[0]
 var portal:Dictionary=ConvoyPortal.plan(space,s.world,c,m.actor_id,m.members,m.convoy)
 var actor:Dictionary=ConvoyTrail.proxy(s.world,m)
 print(nav._convoy_portal_approach(s.world,actor,1,{"cell":ConvoyTrail.point(actor.location.cell),"convoy":m.convoy},portal))
 s.dispose();quit()
