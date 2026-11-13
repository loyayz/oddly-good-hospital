extends SceneTree
func _initialize()->void:
 var c:=HospitalContent.new()
 var f:=FileAccess.open("/tmp/ogh-mixed-visit-b87545e/r10-owner-fix.json.final.bin",FileAccess.READ);var e:Dictionary=f.get_var(false);f.close()
 var w:=WorldState.new(e.facts);var before:Dictionary=w.freeze();var rows:Dictionary={"legacy_validation":w.validate(c),"migration":w.migrate_legacy_transit(c)}
 rows.legacy_unchanged=(before==w.freeze())
 # Empty shape-only declarations exercise storage contract without making a
 # synthetic transport completion or moving a real actor.
 var lift:Dictionary=w.facts.connectors.benchmark_lift.duplicate(true)
 lift.lift_control_version=1;lift.direction=0;lift.landing_queues={};lift.passenger_groups=[];lift.riders=[];lift.phase="idle";lift.erase("primary_actor_id");lift.erase("active_group")
 rows.valid_idle=w._validate_lift_shape(lift)
 lift.direction=2;rows.bad_direction=w._validate_lift_shape(lift);lift.direction=0
 lift.landing_queues={"3:0":[]};rows.bad_queue_direction=w._validate_lift_shape(lift)
 f=FileAccess.open("/workspace/scratch/6962cc21ddf3/lift-schema-probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(rows,"\t"));f.close()
 quit(0 if rows.legacy_validation.is_empty() and rows.migration.is_empty() and rows.legacy_unchanged and rows.valid_idle.is_empty() and not rows.bad_direction.is_empty() and not rows.bad_queue_direction.is_empty() else 1)
