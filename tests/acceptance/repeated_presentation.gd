extends RefCounted

class WarmView extends HospitalView:
	var builds: Dictionary = {}
	func _same_visual_sources(name: String, inputs: Array) -> bool:
		var same: bool = super._same_visual_sources(name,inputs)
		if not same: builds[name] = int(builds.get(name,0))+1
		return same

class ColdView extends HospitalView:
	func _same_visual_sources(_name: String, _inputs: Array) -> bool:
		return false

class SampleBatch extends SkinnedPoseBatch:
	var published: Array = []
	func publish(bounds: AABB) -> bool:
		published.append(bounds)
		return true

class BoundsView extends HospitalView:
	var bounds_calls: int = 0
	func _sync_geometry() -> void: pass
	func _sync_entities() -> void: pass
	func _sync_environment_marks() -> void: pass
	func _complete_resources(_visits: Variant = null) -> void: pass
	func _update_space_geometry() -> void: pass
	func _update_selection() -> void: pass
	func _visible_body_bounds() -> AABB:
		bounds_calls += 1
		return AABB(Vector3(1,2,3),Vector3(4,5,6))

class Resources extends RefCounted:
	var acquired: int = 0
	func acquire(_path: String) -> Node3D:
		acquired += 1
		return Node3D.new()
	func release_tree(_node: Node) -> void: pass

class ResourceView extends HospitalView:
	var rebinds: int = 0
	func _in_view(_bounds: AABB) -> bool: return true
	func _bind_skin_batches() -> void: rebinds += 1
	func _bind_case_props(_actor_id: String, _visits: Array) -> void: pass

class QuoteClinic extends HospitalClinic:
	var comparisons: int = 0
	var submissions: int = 0
	func compare_plans(world: WorldState, visit_id: String) -> Array:
		comparisons += 1
		var rows: Array = []
		for plan: Dictionary in content.catalog.treatment_plans:
			if plan.disease_id==world.facts.visits[visit_id].disease_id:
				rows.append({"plan_id":plan.id,"ok":false,"reason":"controlled unavailable quote"})
		return rows
	func plan_quote(_world: WorldState, _visit_id: String, _plan_id: String, _options: Dictionary = {}) -> Dictionary:
		submissions += 1
		return {"ok":false}

class SearchStatus extends RefCounted:
	var status_calls: int = 0
	var query_calls: int = 0
	func search_status(_world: WorldState) -> Dictionary:
		status_calls += 1
		return {"remaining_ticks":10}
	func query(_world: WorldState, _filter: Dictionary) -> Dictionary:
		query_calls += 1
		return {"active_search":{}}

func run_projection(t, content: HospitalContent, case_id: String = "CORE-51") -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"精确视图依赖",false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var warm: WarmView = WarmView.new(content)
	var cold: ColdView = ColdView.new(content)
	t.root.add_child(warm)
	t.root.add_child(cold)
	warm.bind(world,1,"warm")
	cold.bind(world,1,"cold")
	var before: Dictionary = world.freeze()
	for repeat: int in 3:
		warm.update_facts()
		cold.update_facts()
	var reused: bool = int(warm.builds.geometry)==1 and int(warm.builds.environment)==1 and world.freeze()==before
	world.facts.floors.overrides["1"].blocked.append([36,90])
	var unchanged_revision: int = world.revision
	warm.update_facts()
	cold.update_facts()
	var geometry: bool = int(warm.builds.geometry)==2 and warm._geometry_signature==cold._geometry_signature and world.revision==unchanged_revision
	var dirt: String = simulation.services.environment.spawn_dirt(world,"CL01","projection-probe","projection-probe:scatter",1,[39,90])
	warm.update_facts()
	cold.update_facts()
	var environment: bool = not dirt.is_empty() and warm._environment_marks_signature==cold._environment_marks_signature
	if not dirt.is_empty():
		world.facts.environment.dirt[dirt].cell = [40,90]
		unchanged_revision = world.revision
		before = world.freeze()
		warm.update_facts()
		cold.update_facts()
		environment = environment and warm._environment_marks_signature==cold._environment_marks_signature and world.freeze()==before and world.revision==unchanged_revision
	var first_stamp: String = warm._environment_read_stamp()
	var heatmap: bool = first_stamp==cold._environment_read_stamp() and first_stamp==warm._environment_read_stamp() and int(warm.builds.heatmap)==1
	world.facts.research.append(content.catalog.research[0].id)
	before = world.freeze()
	var changed_stamp: String = warm._environment_read_stamp()
	heatmap = heatmap and changed_stamp!=first_stamp and changed_stamp==cold._environment_read_stamp() and world.freeze()==before
	var validation: String = world.validate(content)
	t.check(case_id,reused and geometry and environment and heatmap and validation.is_empty(),{"unchanged_projection_reused":reused,"same_revision_geometry":geometry,"direct_dirt_change":environment,"heatmap_current_inputs":heatmap,"validation":validation,"scope":"exact dependency reuse and live direct writes; no GPU timing claim"})
	simulation.dispose()
	warm.queue_free()
	cold.queue_free()
	await t.process_frame

func run_resources(t, content: HospitalContent, case_id: String = "CORE-52") -> void:
	var bounds: BoundsView = BoundsView.new(content)
	bounds.world = HospitalFactory.create(HospitalSnapshots.uuid(),"批次局部投影",false,content)
	bounds.camera = Camera3D.new()
	bounds.add_child(bounds.camera)
	t.root.add_child(bounds)
	var batches: Array = [SampleBatch.new(),SampleBatch.new()]
	for batch: SampleBatch in batches:
		bounds.add_child(batch)
		bounds._skin_batches.append(batch)
	bounds.update_facts()
	var one_bounds: bool = bounds.bounds_calls==1 and batches[0].published==batches[1].published and batches[0].published.size()==1
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"资源发布交接",true,content)
	var view: ResourceView = ResourceView.new(content)
	view.world = world
	view.hospital_session = "resource-probe"
	view._resources = Resources.new()
	t.root.add_child(view)
	var actor_ids: Array = world.ids("actors").slice(0,2)
	for id: String in actor_ids:
		var actor: Dictionary = world.facts.actors[id]
		var wrapper: Node3D = Node3D.new()
		var proxy: Node3D = Node3D.new()
		wrapper.add_child(proxy)
		view.add_child(wrapper)
		view._actors[id] = wrapper
		view._actor_models[id] = proxy
		var label: Label3D = Label3D.new()
		wrapper.add_child(label)
		view._actor_labels[id] = label
		var signature: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))+":"+JSON.stringify(content.actor_body(actor),"",true,true)
		view._bind_entity("actor:"+id,signature,wrapper,"res://assets/models/core_"+str(actor.species_id).to_lower()+"_body.glb")
	var before: Dictionary = world.freeze()
	view._complete_resources()
	var coalesced: bool = actor_ids.size()==2 and view._pending_resources.is_empty() and view.rebinds==1 and not view._publishing_resources
	var ticket: Dictionary = view.resource_ticket("actor:"+str(actor_ids[0]))
	var independent: bool = view.publish_resource(ticket,Node3D.new()) and view.rebinds==2
	var stale: Dictionary = ticket.duplicate()
	stale.generation = -1
	var rejected: bool = not view.publish_resource(stale,Node3D.new()) and view.rebinds==2
	var facility_only: bool = false
	for id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[id]
		if facility.definition_id!="FUR01": continue
		var wrapper: Node3D = Node3D.new()
		view.add_child(wrapper)
		view._facilities[id] = wrapper
		var signature: String = str(facility.definition_id)+":"+JSON.stringify(facility.footprint)+":"+str(facility.get("rotation",0))
		view._bind_entity("facility:"+id,signature,wrapper,"res://assets/models/core_fur01_machine.glb")
		# Cache the proxy's missing player, then publish the replacement.
		view._animation_player(wrapper)
		facility_only = view.publish_resource(view.resource_ticket("facility:"+id),Node3D.new()) and view.rebinds==2 and not wrapper.has_meta("_hospital_animation_player")
		break
	var lookups: Dictionary = _model_lookups(view)
	t.check(case_id,one_bounds and coalesced and independent and rejected and facility_only and lookups.ok and world.freeze()==before,{"one_bounds_per_update":one_bounds,"two_publications_one_rebind":coalesced,"standalone_publication":independent,"stale_ticket_rejected":rejected,"facility_preserves_staff_batches":facility_only,"model_lookup_results":lookups.ok,"model_lookup_details":lookups,"scope":"publication orchestration with a resource double; source hashes/material/bones remain CORE-33"})
	bounds.queue_free()
	view.queue_free()
	await t.process_frame

func _model_lookups(view: HospitalView) -> Dictionary:
	var model: Node3D = Node3D.new()
	var player: AnimationPlayer = AnimationPlayer.new()
	var skeleton: Skeleton3D = Skeleton3D.new()
	model.add_child(player)
	model.add_child(skeleton)
	skeleton.add_bone("head")
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation("walk",Animation.new())
	player.add_animation_library("library",library)
	var checks: Dictionary = {}
	checks.player_identity = view._animation_player(model)==player
	checks.player_cached = view._animation_player(model)==player
	checks.skeleton_identity = view._skeleton(model)==skeleton
	checks.skeleton_cached = view._skeleton(model)==skeleton
	var bone_before: int = view._bone_index(skeleton,"head")
	var expected_before: int = skeleton.find_bone("head")
	checks.bone_identity = bone_before==expected_before
	checks.bone_cached = view._bone_index(skeleton,"head")==expected_before
	checks.missing_bone_cached = view._bone_index(skeleton,"renamed")==-1
	var animations: Array = []
	for requested: String in ["walk","library/walk","missing"]:
		var actual: StringName = view._animation_name(player,requested)
		var expected: StringName = _original_animation(player,requested)
		checks["animation_"+requested] = actual==expected
		animations.append({"requested":requested,"actual":str(actual),"expected":str(expected)})
	library.add_animation("new_clip",Animation.new())
	var new_clip: StringName = view._animation_name(player,"new_clip")
	var expected_clip: StringName = _original_animation(player,"new_clip")
	checks.animation_added = new_clip==expected_clip
	animations.append({"requested":"new_clip","actual":str(new_clip),"expected":str(expected_clip)})
	var version_before: int = skeleton.get_version()
	skeleton.set_bone_name(0,"renamed")
	var version_after: int = skeleton.get_version()
	var old_index: int = view._bone_index(skeleton,"head")
	var new_index: int = view._bone_index(skeleton,"renamed")
	var expected_old: int = skeleton.find_bone("head")
	var expected_new: int = skeleton.find_bone("renamed")
	checks.bone_version_changed = version_after!=version_before
	checks.bone_renamed_old = old_index==expected_old and old_index==-1
	checks.bone_renamed_new = new_index==expected_new and new_index==0
	model.free()
	return {"ok":not checks.values().has(false),"checks":checks,"animations":animations,"bones":{"version_before":version_before,"version_after":version_after,"before":bone_before,"expected_before":expected_before,"old_after":old_index,"expected_old_after":expected_old,"new_after":new_index,"expected_new_after":expected_new}}

func _original_animation(player: AnimationPlayer, requested: String) -> StringName:
	for name: StringName in player.get_animation_list():
		if str(name)==requested or str(name).ends_with("/"+requested): return name
	return &""

func run_ui(t, content: HospitalContent, case_id: String = "CORE-53") -> void:
	var c: Dictionary = load("res://tests/acceptance/clinical_gathering.gd").new()._context(content,"gp")
	var simulation: HospitalSimulation = HospitalSimulation.new(c.world,content)
	var original: HospitalClinic = simulation.clinic
	var clinic: QuoteClinic = QuoteClinic.new(content,simulation.space)
	simulation.clinic = clinic
	var panel: HospitalPlansPanel = HospitalPlansPanel.new()
	panel.simulation = simulation
	panel.build_controls()
	var expected: Array = []
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id==c.world.facts.visits[panel._visit_id].disease_id: expected.append(plan.id)
	var actual: Array = []
	for index: int in panel._plans.item_count: actual.append(panel._plans.get_item_metadata(index))
	var once: bool = clinic.comparisons==1 and actual==expected
	panel._submit()
	var submit_rechecks: bool = clinic.submissions==1
	var search: SearchStatus = SearchStatus.new()
	var recruitment: RefCounted = simulation.services.recruitment
	simulation.services.recruitment = search
	var recruitment_panel: HospitalRecruitmentPanel = HospitalRecruitmentPanel.new()
	recruitment_panel.simulation = simulation
	recruitment_panel._search_status()
	var narrow: bool = search.status_calls==1 and search.query_calls==0
	simulation.services.recruitment = recruitment
	var build: HospitalBuildPanel = HospitalBuildPanel.new()
	t.root.add_child(build)
	var overlay: HospitalBuildOverlay = HospitalBuildOverlay.new()
	var publications: Array = []
	build.preview_changed.connect(func(draft: Dictionary, result: Dictionary) -> void:
		publications.append([draft.duplicate(true),result.duplicate(true)])
		overlay.show_preview(draft,result,1)
		draft.consumer_change = true)
	build._draft = {"kind":"build_room","cells":[[34,66],[35,66]]}
	build._result = {"ready":false,"generation":1}
	build._publish_preview()
	build._publish_preview()
	var duplicate_suppressed: bool = publications.size()==1 and not build._published_draft.has("consumer_change")
	build._result.ready = true
	build._publish_preview()
	duplicate_suppressed = duplicate_suppressed and publications.size()==2
	var before_hide: int = publications.size()
	build.hide()
	overlay.show_preview({},{},1)
	var cleared: bool = overlay.mesh==null
	build.show()
	build._publish_preview()
	var restored: bool = cleared and publications.size()==before_hide+1 and overlay.mesh!=null
	build._publish_preview()
	restored = restored and publications.size()==before_hide+1
	t.check(case_id,once and submit_rechecks and narrow and duplicate_suppressed and restored,{"initial_plan_compare_once":once,"option_order":actual,"submit_rechecks":submit_rechecks,"narrow_search_status":narrow,"unchanged_preview_not_republished":duplicate_suppressed,"preview_restored_after_reshow":restored,"preview_publications_before_hide":before_hide,"preview_publications_after_reshow":publications.size()})
	simulation.clinic = original
	simulation.dispose()
	panel.free()
	recruitment_panel.free()
	build.free()
	overlay.free()

func run_import_overlay(t, content: HospitalContent, case_id: String = "CORE-54") -> void:
	var library: HospitalLibrary = HospitalLibrary.new(content,null)
	var old: String = "00000000-0000-4000-8000-000000005400"
	var next: String = "00000000-0000-4000-8000-000000005401"
	var staff: Array = [old+":a",old+":a:b",old+":prefix/worker", "external:worker"]
	var facts: Dictionary = {"hospital_id":old,"staff":{},"departments":{"staff_consumed":{}}}
	for id: String in staff: facts.staff[id] = {"id":id}
	for id: String in staff:
		for source: String in [old+":course",old+"_job",old+"/receipt","external:source",""]:
			facts.departments.staff_consumed[id+":"+source] = true
	facts.departments.staff_consumed["unmatched:key"] = true
	var before: Dictionary = facts.duplicate(true)
	var control: Dictionary = _original_remap(library,facts,old,next)
	var imported: Dictionary = library._remap_hospital(facts,old,next)
	var mapping: bool = imported==control and facts==before
	var overlay: HospitalBuildOverlay = HospitalBuildOverlay.new()
	var cells: Array = [[34,66],[35,66],[34,66],[36,66]]
	var blocked: Array = [[35,66],[35,66],[40,90]]
	overlay.show_preview({"cells":cells},{"ready":true,"ok":true,"blocked_cells":blocked},1)
	var arrays: Array = overlay.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var geometry: bool = colors.size()==cells.size()*8
	for index: int in cells.size():
		var expected: Color = Color("b85550") if cells[index] in blocked else Color("4d719d")
		for vertex: int in 8: geometry = geometry and colors[index*8+vertex].is_equal_approx(expected)
	t.check(case_id,mapping and geometry,{"longest_staff_prefix_and_definition_rules":mapping,"irregular_blocked_colors":geometry,"scope":"pure identity rewrite and generated mesh arrays; durable import remains CORE-26/27"})
	overlay.free()

func _original_remap(library: HospitalLibrary, value: Dictionary, old: String, next: String) -> Dictionary:
	var ids: Dictionary = {old:next}
	library._collect_instance_ids(value,old,next,ids)
	var rewritten: Dictionary = library._rewrite_ids(value,"",old,next,ids)
	var staff: Array = value.staff.keys()
	staff.sort_custom(func(a: String,b: String) -> bool: return a.length()>b.length())
	var consumed: Dictionary = {}
	for key: String in value.departments.staff_consumed:
		var mapped: String = key
		for id: String in staff:
			if key.begins_with(id+":"):
				var source: String = key.substr(id.length()+1)
				var mapped_source: String = next+source.substr(old.length()) if library._hospital_prefix(source,old) else source
				mapped = str(ids.get(id,id))+":"+mapped_source
				break
		consumed[mapped] = value.departments.staff_consumed[key]
	rewritten.departments.staff_consumed = consumed
	return rewritten
