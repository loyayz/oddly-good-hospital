extends SceneTree

var _failures: Array[String] = []
var _checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage07-view",false,content)
	for collection: String in ["actors","staff","visits","tickets","sessions","moves","facilities","connectors","rooms","adaptations"]:
		world.facts[collection].clear()
	var view: HospitalView = HospitalView.new(content)
	root.add_child(view)
	view.bind(world,1,"view-session-a")
	await process_frame
	_check("empty_hospital_projects_without_actors_or_facilities",view._actors.is_empty() and view._facilities.is_empty() and view.bind_error.is_empty())
	for species: Dictionary in content.catalog.species:
		world.facts.actors[species.id] = {"id":species.id,"name":str(species.name),"species_id":species.id,"location":{"kind":"floor","floor_id":1,"cell":[44,78]},"facing":0.0}
	world.touch()
	var original: String = _canonical(world)
	view.update_facts()
	_check("binding_all_species_is_read_only",original==_canonical(world))
	_check("all_species_keep_real_visible_bodies",view._actors.size()==content.catalog.species.size())
	_check("unproduced_assets_are_marked_proxies",view._actors.has("S01") and view._actors.S01.get_meta("resource_proxy",false))
	var micro: Dictionary = content.actor_body(world.facts.actors.S21)
	var micro_mesh: MeshInstance3D = view._actor_models.S21.get_child(0) if view._actors.S21.get_meta("resource_proxy",false) else null
	_check("proxy_keeps_actual_envelope",micro_mesh==null or (micro_mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(float(micro.width_m),float(micro.height_m),float(micro.depth_m))))
	var old_ticket: Dictionary = view.resource_ticket("actor:S01")
	world.facts.actors.erase("S01")
	world.touch()
	view.update_facts()
	_check("departed_actor_releases_binding",not view._actors.has("S01") and not view.accepts_resource(old_ticket))
	world.facts.actors.S01 = {"id":"S01","name":"新居民","species_id":"S01","location":{"kind":"floor","floor_id":1,"cell":[44,78]},"facing":0.0}
	world.touch()
	view.update_facts()
	_check("reused_entity_id_has_new_generation",not view.accepts_resource(old_ticket) and view.resource_ticket("actor:S01").generation!=old_ticket.generation)
	var floor_ticket: Dictionary = view.resource_ticket("actor:S01")
	view.set_floor(2)
	_check("floor_change_retires_old_actor_instances",view._actors.is_empty() and not view.accepts_resource(floor_ticket))
	view.set_floor(1)
	var hospital_ticket: Dictionary = view.resource_ticket("actor:S01")
	var restored: WorldState = WorldState.new(world.freeze())
	view.bind(restored,1,"view-session-b")
	_check("restoring_same_hospital_rejects_old_load",not view.accepts_resource(hospital_ticket))
	var stale_node: Node3D = Node3D.new()
	_check("late_result_is_not_published",not view.publish_resource(hospital_ticket,stale_node))
	for id: String in restored.facts.actors.keys():
		if id!="S49":
			restored.facts.actors.erase(id)
	restored.facts.actors.S49.location.cell = [44,78]
	restored.facts.actors["second"] = restored.facts.actors.S49.duplicate(true)
	restored.facts.actors.second.id = "second"
	restored.facts.actors.second.location.cell = [46,78]
	restored.touch()
	for index: int in 12:
		view.update_facts()
		await process_frame
	var first: MeshInstance3D = view._mesh_instance(view._actor_models.S49)
	var second: MeshInstance3D = view._mesh_instance(view._actor_models.second)
	_check("shared_model_resources_keep_independent_nodes",first!=null and second!=null and first!=second and first.mesh==second.mesh)
	_check("manifest_import_contract_has_no_errors",view.resource_usage().errors.is_empty())
	var screen: Vector2 = view.camera.unproject_position(view._actors.S49.position+Vector3.UP*0.5)
	_check("picking_uses_current_true_body",view.pick(screen)=="S49")
	_check("screen_to_cell_matches_world_projection",view.cell_at_screen(view.camera.unproject_position(Vector3(18.75,0,21.75)))==[44,78])
	restored.facts.facilities["new_desk"] = {"id":"new_desk","definition_id":"FUR01","floor_id":1,"cell":[43,77],"footprint":[1,1],"patient_cell":[43,78],"operator_cells":[[44,77]],"repair_cell":[42,77],"failed":false}
	restored.touch()
	view.update_facts()
	_check("new_construction_appears_dynamically",view._facilities.has("new_desk"))
	restored.facts.facilities.erase("new_desk")
	restored.facts.floors.overrides["1"].blocked.append([40,77])
	restored.touch()
	view.update_facts()
	_check("removed_facility_retires_and_wall_change_projects",not view._facilities.has("new_desk") and view._wall_nodes.has(Vector2i(40,77)))
	view.walls_cut = true
	view.low_motion = true
	view.zoom_camera(1.2)
	view.pan_camera(Vector2(5,10))
	view.overview()
	view.update_facts()
	_check("wall_cut_only_changes_projection",not view._wall_nodes[Vector2i(40,77)].visible)
	_check("view_never_advances_original_world",int(world.sim_tick)==0)
	var before: String = _canonical(restored)
	view.set_floor(2)
	await process_frame
	view.update_facts()
	_check("retired_resource_references_converge",int(view.resource_usage().instance_users)==0 and int(view.resource_usage().shared_scenes)==0)
	_check("floor_camera_and_retirement_are_read_only",before==_canonical(restored))
	view.queue_free()
	await process_frame
	print(JSON.stringify({"ok":_failures.is_empty(),"checks":_checks,"failures":_failures,"performance":"skipped_by_request","formal_asset_completion":"stage35_pending"},"\t"))
	quit(0 if _failures.is_empty() else 1)

func _canonical(world: WorldState) -> String:
	return JSON.stringify(world.facts,"",true,true)

func _check(name: String, passed: bool) -> void:
	_checks[name] = passed
	if not passed:
		_failures.append(name)
