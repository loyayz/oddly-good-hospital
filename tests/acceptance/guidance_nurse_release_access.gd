extends "res://tests/acceptance/floor_guidance.gd"

# Position mutations below are explicit boundary fixtures, not natural walking evidence.
func run_rules(database:HospitalContent)->Dictionary:
 _content=database
 var x:Dictionary=_base()
 var visit:Dictionary=_visit(x,"release_access",[50,85])
 for tick:int in 600:
  _step(x)
  if x.world.facts.adaptations.has("guide") and x.g.state(x.world,visit.id).get("phase","")=="to_counter":break
 var current:Dictionary=x.g.state(x.world,visit.id)
 if not x.world.facts.adaptations.has("guide"):
  _dispose(x);return {"ok":false,"error":"natural counter reservation not established"}
 var template:Dictionary=x.world.facts.adaptations.guide.duplicate(true)
 var nurse:Dictionary=x.world.facts.actors.guide_nurse
 var nurse_location:Dictionary=nurse.location.duplicate(true)
 var patient:Dictionary=x.world.facts.actors[visit.actor_id]
 var checks:Dictionary={"natural_counter_hold":current.phase=="to_counter"}
 # Ordinary completion clears the fixed on-duty nurse from the patient's hold.
 x.g._release_counter(x.world,visit,current)
 checks.normal_fixed_nurse_not_retained=x.world.facts.staff.guide_nurse.active_job_id=="floor_desk:guide" and not "guide_nurse" in x.world.facts.adaptations.get("guide",{}).get("staff_ids",[])
 var held:Dictionary=template.duplicate(true)
 held.owner_id=visit.actor_id;held.staff_ids=[]
 x.world.facts.adaptations.guide=held
 x.world.facts.staff.guide_nurse.active_job_id="floor_desk_release:guide"
 var was_allowed:bool=RouteClearance.reservation_allows(held,"guide_nurse")
 x.g._retain_departing_nurse_access(x.world,"guide","guide_nurse")
 checks.departing_inside_gains_exit_permission=not was_allowed and RouteClearance.reservation_allows(held,"guide_nurse")
 x.g._retain_departing_nurse_access(x.world,"guide","guide_nurse")
 checks.idempotent_staff_identity=held.staff_ids==["guide_nurse"]
 # Patient outside, departing nurse inside: hold still protects that real body.
 patient.location.cell=[35,94]
 x.world.facts.moves.clear()
 x.space.release_adaptations(x.world)
 checks.hold_retained_until_nurse_outside=x.world.facts.adaptations.has("guide")
 nurse.location.cell=[54,92]
 x.space.release_adaptations(x.world)
 checks.hold_removed_after_both_outside=not x.world.facts.adaptations.has("guide")
 # A new reservation has its own participant array. Finishing the previous
 # departure must not transfer the old nurse identity to this newer service.
 var newer:Dictionary=template.duplicate(true)
 newer.owner_id="later_service_owner";newer.staff_ids=[]
 x.world.facts.adaptations.guide=newer
 x.world.facts.floor_guidance.releases.guide_nurse={"desk_id":"guide","floor_id":1,"cell":nurse_location.cell.duplicate(),"clearance":x.space.clearance(nurse)}
 x.g._release_nurses(x.world)
 checks.later_hold_does_not_inherit_old_identity=newer.staff_ids.is_empty() and not RouteClearance.reservation_allows(newer,"guide_nurse")
 # Negative scopes do not grant identities or create missing holds.
 held=template.duplicate(true);held.owner_id=visit.actor_id;held.staff_ids=[]
 x.world.facts.adaptations.guide=held
 x.g._retain_departing_nurse_access(x.world,"guide","guide_nurse")
 checks.outside_not_added=held.staff_ids.is_empty()
 nurse.location=nurse_location.duplicate(true);nurse.location.floor_id=2
 x.g._retain_departing_nurse_access(x.world,"guide","guide_nurse")
 checks.other_floor_not_added=held.staff_ids.is_empty()
 nurse.location=nurse_location.duplicate(true)
 x.world.facts.adaptations.erase("guide")
 x.g._retain_departing_nurse_access(x.world,"guide","guide_nurse")
 checks.missing_hold_not_created=not x.world.facts.adaptations.has("guide")
 var out:Dictionary={"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"scope":"natural counter hold; explicit boundary locations for permission and cleanup, not natural exit-motion proof"}
 _dispose(x);return out
