extends "res://tools/performance/current/plain_v4.gd"
func _run() -> void:
	var input: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if input.is_empty() or output.is_empty() or FileAccess.file_exists(output): quit(2);return
	var f: FileAccess=FileAccess.open(input,FileAccess.READ);var saved: Dictionary=f.get_var(false);f.close()
	var world: WorldState=WorldState.new(saved.facts)
	var original: Dictionary=population_current(world)
	var id: String="maintenance_contractor_00000168"
	var checks: Dictionary={"owned_mechanic":original.other_owned_present.size()==1 and original.other_owned_present[0].actor_id==id and original.unclassified_actor_ids.is_empty()}
	world.facts.actors[id].service_role="not_mechanic"
	checks.wrong_role_rejected=id in population_current(world).unclassified_actor_ids
	world.facts.actors[id].service_role="mechanic"
	world.facts.maintenance.contractors[id].phase="departed"
	checks.inconsistent_phase_location_rejected=id in population_current(world).unclassified_actor_ids
	world.facts.maintenance.contractors[id].phase="assigned"
	checks.wrong_assigned_job_owner_rejected=id in population_current(world).unclassified_actor_ids
	world.facts.maintenance.contractors[id].phase="leaving"
	world.facts.maintenance.contractors[id].job_id="missing"
	checks.missing_job_rejected=id in population_current(world).unclassified_actor_ids
	var ok: bool=true
	for value: bool in checks.values(): ok=ok and value
	write_json(output,{"ok":ok,"checks":checks,"original_population":original,"scope":"Read binary and classify owners, with independent invalid record mutations only in test-owned copies; no simulation steps or source changes"});quit(0 if ok else 1)
