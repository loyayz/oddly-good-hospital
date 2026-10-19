extends RefCounted

class WarmView extends HospitalView:
	var builds: Dictionary = {}
	var heatmap_reads: int = 0
	func _same_visual_sources(name: String, inputs: Array) -> bool:
		var same: bool = super._same_visual_sources(name,inputs)
		if not same: builds[name] = int(builds.get(name,0))+1
		return same
	func _environment_read_stamp() -> String:
		heatmap_reads += 1
		return super._environment_read_stamp()

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
	var decorations: Dictionary = _geometry_dependencies(t,content)
	var marks: Dictionary = _environment_dependencies(t,content)
	var floors: Dictionary = _room_floor_batches(t,content)
	t.check(case_id,reused and geometry and environment and heatmap and validation.is_empty() and decorations.passed and marks.passed and floors.passed,{"unchanged_projection_reused":reused,"same_revision_geometry":geometry,"direct_dirt_change":environment,"heatmap_current_inputs":heatmap,"decoration_dependencies":decorations,"environment_dependencies":marks,"room_floor_batches":floors,"validation":validation,"scope":"exact dependency reuse, per-cell static geometry and live direct writes; no GPU timing claim"})
	simulation.dispose()
	warm.queue_free()
	cold.queue_free()
	await t.process_frame

func _environment_dependencies(t, content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"环境标记读集",false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var ordered: CommandResult = simulation.services.environment.execute(world,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]}],"allow_waiting":true})
	var dirt: String = simulation.services.environment.spawn_dirt(world,"CL01","mark-probe","mark-probe:scatter",1,[44,80])
	if not ordered.accepted or dirt.is_empty():
		simulation.dispose()
		return {"passed":false,"order":ordered.to_record(),"dirt":dirt}
	var baseline: Dictionary = world.freeze()
	var warm: WarmView = WarmView.new(content)
	var cold: ColdView = ColdView.new(content)
	for view: HospitalView in [warm,cold]:
		t.root.add_child(view)
		view.bind(world,1)
	var order_id: String = str(ordered.changed_ids[0])
	var observations: Array = []
	var passed: bool = world.validate(content).is_empty()
	for probe: String in ["remaining","contributions","other_floor","unit_phase","unit_paused","unit_cell","dirt_phase","dirt_cell"]:
		world.facts = baseline.duplicate(true)
		warm._sync_environment_marks()
		var builds: int = int(warm.builds.environment)
		var before_nodes: Array = warm._environment_marks.get_children().map(func(node: Node) -> int: return node.get_instance_id())
		match probe:
			"remaining": world.facts.environment.orders[order_id].units[0].remaining_milli -= 1
			"contributions": world.facts.environment.orders[order_id].units[0].contributions.extra = 1
			"other_floor":
				var other: Dictionary = world.facts.environment.dirt[dirt].duplicate(true)
				other.floor_id = 2
				other.id = "other_floor_dirt"
				world.facts.environment.dirt[other.id] = other
			"unit_phase": world.facts.environment.orders[order_id].units[0].phase = "working"
			"unit_paused": world.facts.environment.orders[order_id].paused = true
			"unit_cell": world.facts.environment.orders[order_id].units[0].cell = [43,80]
			"dirt_phase": world.facts.environment.dirt[dirt].phase = "working"
			"dirt_cell": world.facts.environment.dirt[dirt].cell = [45,80]
		var before: Dictionary = world.freeze()
		warm._sync_environment_marks()
		cold._sync_environment_marks()
		var ignored: bool = probe in ["remaining","contributions","other_floor"]
		var same_nodes: bool = warm._environment_marks.get_children().map(func(node: Node) -> int: return node.get_instance_id())==before_nodes
		var ok: bool = int(warm.builds.environment)-builds==(0 if ignored else 1) and same_nodes==ignored and warm._environment_marks_signature==cold._environment_marks_signature and world.freeze()==before
		passed = passed and ok
		observations.append({"probe":probe,"passed":ok,"source_changes":int(warm.builds.environment)-builds,"same_nodes":same_nodes})
	world.facts = baseline.duplicate(true)
	warm._sync_environment_marks()
	var sample: Array = [{"floor_id":1,"cell":[42,80],"environment":{"status":"current","value":50}}]
	warm.show_environment_heatmap(sample)
	var published: MultiMeshInstance3D = warm._environment_heatmap
	world.facts.research.append(content.catalog.research[0].id)
	warm._sync_environment_marks()
	var invalidated: bool = published!=null and not published.visible and warm._heatmap_stamp.is_empty()
	var reads: int = warm.heatmap_reads
	for repeat: int in 3: warm._sync_environment_marks()
	var stopped: bool = warm.heatmap_reads==reads and not published.visible
	# Returning to old facts cannot silently restore a previously invalid color.
	world.facts = baseline.duplicate(true)
	warm._sync_environment_marks()
	stopped = stopped and warm.heatmap_reads==reads and not published.visible
	warm.show_environment_heatmap(sample)
	var republished: bool = warm._environment_heatmap!=published and warm._environment_heatmap.visible and not warm._heatmap_stamp.is_empty()
	warm.set_floor(2)
	var floor_clear: bool = warm._environment_heatmap==null and warm._heatmap_stamp.is_empty()
	warm.bind(HospitalFactory.create(HospitalSnapshots.uuid(),"另一环境视图",false,content),1)
	var hospital_clear: bool = warm._environment_heatmap==null and warm._heatmap_stamp.is_empty()
	var validation: String = world.validate(content)
	warm.queue_free()
	cold.queue_free()
	simulation.dispose()
	return {"passed":passed and invalidated and stopped and republished and floor_clear and hospital_clear and validation.is_empty(),"observations":observations,"invalidated_hidden":invalidated,"invalidated_stamp_reads_stopped":stopped,"explicit_republication":republished,"floor_clear":floor_clear,"hospital_clear":hospital_clear,"validation":validation}

func _room_floor_batches(t, content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"逐格地板批次",true,content)
	var baseline: Dictionary = world.freeze()
	# Direct presentation probes preserve ordered cells, L-shapes and holes;
	# construction legality remains the responsibility of SPACE-06/52.
	world.facts.rooms.room_gp.cells = [[36,86],[37,86],[36,87]]
	var other: Dictionary = world.facts.rooms.room_gp.duplicate(true)
	other.id = "other_floor_probe"
	other.floor_id = 2
	other.kind = "ward"
	other.cells = [[35,70],[36,70],[37,70],[35,71],[37,71],[35,72],[36,72],[37,72]]
	world.facts.rooms[other.id] = other
	var before: Dictionary = world.freeze()
	var view: HospitalView = HospitalView.new(content)
	t.root.add_child(view)
	view.bind(world,1)
	var observations: Array = []
	var passed: bool = true
	for floor_id: int in [1,2,1]:
		view.set_floor(floor_id)
		var expected: Array = []
		for room: Dictionary in world.facts.rooms.values():
			if int(room.floor_id)!=floor_id or not room.has("cells"): continue
			for cell: Array in room.cells:
				expected.append({"transform":Transform3D(Basis.IDENTITY,Vector3((float(cell[0])-32)*1.5+0.75,0.03,(float(cell[1])-64)*1.5+0.75)),"size":Vector3(1.5,0.02,1.5),"color":HospitalView.Palette.WARD_FLOOR if room.kind=="ward" else HospitalView.Palette.SURGERY_FLOOR,"roughness":0.9})
		var actual: Array = []
		var batches: int = 0
		var complete_buffers: bool = true
		var backend_transform: String = "none"
		for node: Node in view._decorations.get_children():
			if not node is MultiMeshInstance3D: continue
			batches += 1
			var mesh: BoxMesh = node.multimesh.mesh
			var material: StandardMaterial3D = mesh.material
			var buffer: PackedFloat32Array = node.multimesh.buffer
			complete_buffers = complete_buffers and buffer.size()==node.multimesh.instance_count*12
			if buffer.size()!=node.multimesh.instance_count*12: continue
			if node.multimesh.instance_count>0: backend_transform = var_to_str(node.multimesh.get_instance_transform(0))
			for index: int in node.multimesh.instance_count:
				# Decode the actual submitted renderer buffer. Dummy rendering does
				# retain this buffer but its per-instance getter returns identity.
				var at: int = index*12
				var transform: Transform3D = Transform3D(Basis(Vector3(buffer[at],buffer[at+4],buffer[at+8]),Vector3(buffer[at+1],buffer[at+5],buffer[at+9]),Vector3(buffer[at+2],buffer[at+6],buffer[at+10])),Vector3(buffer[at+3],buffer[at+7],buffer[at+11]))
				actual.append({"transform":node.global_transform*transform,"size":mesh.size,"color":material.albedo_color,"roughness":material.roughness})
		var same: bool = complete_buffers and actual.size()==expected.size()
		for index: int in mini(actual.size(),expected.size()):
			same = same and (actual[index].transform as Transform3D).is_equal_approx(expected[index].transform) and (actual[index].size as Vector3).is_equal_approx(expected[index].size) and (actual[index].color as Color).is_equal_approx(expected[index].color) and is_equal_approx(float(actual[index].roughness),float(expected[index].roughness))
		view.walls_cut = true
		view._update_space_geometry()
		var visible: bool = true
		for node: Node in view._decorations.get_children():
			if node is MultiMeshInstance3D: visible = visible and node.visible
		passed = passed and same and visible
		observations.append({"floor_id":floor_id,"cells":expected.size(),"instances":actual.size(),"batches":batches,"complete_uploaded_buffers":complete_buffers,"complete_geometry_materials":same,"visible_after_wall_cut":visible,"first_expected":var_to_str(expected[0]) if not expected.is_empty() else "empty","first_actual":var_to_str(actual[0]) if not actual.is_empty() else "empty","backend_first_transform":backend_transform})
	var old_decorations: Node3D = view._decorations
	view.bind(HospitalFactory.create(HospitalSnapshots.uuid(),"清空院区",false,content),1)
	var cleared: bool = old_decorations.get_parent()==null and not old_decorations in view.get_children()
	passed = passed and cleared and world.freeze()==before
	world.facts = baseline
	var validation: String = world.validate(content)
	view.queue_free()
	return {"passed":passed and validation.is_empty(),"observations":observations,"old_hospital_retired":cleared,"validation":validation,"scope":"decode actual complete submitted transform buffers plus box dimensions/materials, not GPU readback or occlusion performance"}

func _geometry_dependencies(t, content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"装饰几何读集",true,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var made: CommandResult = simulation.services.connectors.execute(world,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	if not made.accepted:
		simulation.dispose()
		return {"passed":false,"connector_build":made.to_record()}
	var baseline: Dictionary = world.freeze()
	var initial_validation: String = world.validate(content)
	var connector_id: String = made.changed_ids[0]
	var warm: WarmView = WarmView.new(content)
	var cold: ColdView = ColdView.new(content)
	for view: HospitalView in [warm,cold]:
		t.root.add_child(view)
		view.world = world
		view._decorations = Node3D.new()
		view.add_child(view._decorations)
		view._sync_geometry()
	var original_signature: String = warm._geometry_signature
	var original_nodes: Array = warm._decorations.get_children().map(func(node: Node) -> int: return node.get_instance_id())
	var observations: Array = []
	var passed: bool = initial_validation.is_empty()
	# These are direct-write read-view probes, each restored from the same legal
	# world. They do not stand in for transport, construction or clinical flows.
	for probe: String in ["used","transport_clock","other_floor","room_origin","room_size","room_cells","cell_order","wall_edges","blocked","door_cell","door_span","connector_cell","connector_anchor","connector_footprint","connector_stop","plots","top_floor"]:
		world.facts = baseline.duplicate(true)
		if probe=="cell_order": world.facts.rooms.room_gp.cells = [[36,86],[37,86],[36,87]]
		warm.observed_floor = 1
		cold.observed_floor = 1
		warm._sync_geometry()
		var before_builds: int = int(warm.builds.geometry)
		var before_nodes: Array = warm._decorations.get_children().map(func(node: Node) -> int: return node.get_instance_id())
		match probe:
			"used": world.facts.rooms.room_gp.used = true
			"transport_clock": world.facts.connectors[connector_id].remaining_ticks = 17
			"other_floor":
				world.facts.floors.overrides["2"] = {"blocked":[[40,75]],"doors":[]}
				var upper: Dictionary = world.facts.rooms.room_gp.duplicate(true)
				upper.id = "upper_probe"
				upper.floor_id = 2
				world.facts.rooms.upper_probe = upper
			"room_origin": world.facts.rooms.room_gp.origin[0] += 1
			"room_size": world.facts.rooms.room_gp.size[0] += 1
			"room_cells": world.facts.rooms.room_gp.cells = [[36,86],[37,86],[36,87]]
			"cell_order": world.facts.rooms.room_gp.cells = [[36,87],[37,86],[36,86]]
			"wall_edges": world.facts.rooms.room_gp.wall_edges = [{"axis":"x","line":86,"low":36,"high":40}]
			"blocked": world.facts.floors.overrides["1"].blocked.append([60,70])
			"door_cell": world.facts.floors.overrides["1"].doors[0].cell[0] += 1
			"door_span":
				var door: Dictionary = world.facts.floors.overrides["1"].doors[0]
				world.facts.adaptations[door.id] = {"span":int(door.span)+1}
			"connector_cell": world.facts.connectors[connector_id].cell[0] += 1
			"connector_anchor": world.facts.connectors[connector_id].anchor[0] += 1
			"connector_footprint": world.facts.connectors[connector_id].footprint[0] += 1
			"connector_stop":
				world.facts.connectors[connector_id].first_floor = 2
				world.facts.connectors[connector_id].last_floor = 2
			"plots": world.facts.floors.overrides["1"].plots.append([2,2])
			"top_floor":
				warm.observed_floor = 2
				cold.observed_floor = 2
				world.facts.floors.completed_top_floor = {"1:2":2}
		var revision: int = world.revision
		var before: Dictionary = world.freeze()
		warm._sync_geometry()
		cold._geometry_signature = ""
		cold._sync_geometry()
		var ignored: bool = probe in ["used","transport_clock","other_floor"]
		var nodes: Array = warm._decorations.get_children().map(func(node: Node) -> int: return node.get_instance_id())
		var rebuilt: bool = int(warm.builds.geometry)==before_builds+1 and nodes!=before_nodes
		var untouched: bool = int(warm.builds.geometry)==before_builds and nodes==before_nodes and warm._geometry_signature==original_signature and nodes==original_nodes
		var equal: bool = warm._geometry_signature==cold._geometry_signature
		var readonly: bool = world.freeze()==before and world.revision==revision
		var ok: bool = equal and readonly and (untouched if ignored else rebuilt)
		passed = passed and ok
		observations.append({"probe":probe,"passed":ok,"projection_runs":int(warm.builds.geometry)-before_builds,"rebuilt":rebuilt,"matches_cold":equal,"readonly":readonly})
	world.facts = baseline.duplicate(true)
	var restored_validation: String = world.validate(content)
	warm.queue_free()
	cold.queue_free()
	simulation.dispose()
	return {"passed":passed and restored_validation.is_empty(),"initial_validation":initial_validation,"restored_validation":restored_validation,"observations":observations,"scope":"direct-write geometry dependencies and node reuse; no frame or GPU claim"}

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
