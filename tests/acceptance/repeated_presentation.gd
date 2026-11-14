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
	func _sync_entities() -> Dictionary: return {}
	func _sync_environment_marks() -> void: pass
	func _complete_resources(_visits: Variant = null) -> void: pass
	func _update_space_geometry() -> void: pass
	func _update_selection() -> void: pass
	func _visible_body_bounds(_actor_samples: Dictionary = {}) -> AABB:
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
	var floors: Dictionary = _surface_finishes(t,content)
	t.check(case_id,reused and geometry and environment and heatmap and validation.is_empty() and decorations.passed and marks.passed and floors.passed,{"unchanged_projection_reused":reused,"same_revision_geometry":geometry,"direct_dirt_change":environment,"heatmap_current_inputs":heatmap,"decoration_dependencies":decorations,"environment_dependencies":marks,"surface_finishes":floors,"validation":validation,"scope":"exact dependency reuse, per-cell static geometry and live direct writes; no GPU timing claim"})
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

func _surface_finishes(t, content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"逐格付费饰面",true,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var view: HospitalView = HospitalView.new(content)
	t.root.add_child(view)
	view.bind(world,1)
	# A furnished room is not a purchase of surface finishes.
	var implicit_tiles: bool = not world.facts.rooms.is_empty() and world.facts.environment.surfaces.is_empty() and _drawn_finishes(view).is_empty()
	for node: Node in view._decorations.get_children():
		if node is MultiMeshInstance3D: implicit_tiles = false
		if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.is_equal_approx(Vector3(1.5,0.02,1.5)): implicit_tiles = false
	# Independent already-paid legal history for mark geometry. The upper
	# floor's hole and the lower L must not become a rectangular fill.
	world.facts.floors.completed_top_floor["1:2"]=2
	world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":float(content.balance.floors.clear_height_m)}]
	world.facts.floors.overrides["2"]={"plots":[[1,2]],"blocked":[],"walls":[],"doors":[],"paths":[]}
	var lower: Array=[[36,86],[37,86],[36,87]]
	var upper: Array=[[35,70],[36,70],[37,70],[35,71],[37,71],[35,72],[36,72],[37,72]]
	var cash: int=HospitalLedger.balance(world)
	var expected_payment: int=0
	var paid: bool=true
	for floor_id: int in [1,2]:
		var material: String="MAT01" if floor_id==1 else "MAT04"
		var cells: Array=lower if floor_id==1 else upper
		var price: int=int(content.definition("renovation_materials",material).unit_price)
		var units: Array=cells.map(func(cell: Array)->Dictionary: return {"cell":cell})
		var payment: CommandResult=simulation.services.environment.execute(world,"renovation_order",{"material_id":material,"floor_id":floor_id,"units":units,"allow_waiting":true})
		paid = paid and payment.accepted
		expected_payment += price*cells.size()
		if not payment.accepted:
			view.queue_free()
			simulation.dispose()
			return {"passed":false,"floor_id":floor_id,"order":payment.to_record()}
		# This projection fixture starts from installed tiles. The actual order
		# owns the production material debit and every installed unit.
		var order: Dictionary=world.facts.environment.orders[payment.changed_ids[0]]
		for unit: Dictionary in order.units:
			unit.phase="completed"
			unit.started=true
			unit.remaining_milli=0
			world.facts.environment.surfaces[unit.key]={"floor_id":floor_id,"cell":unit.cell.duplicate(),"surface":order.surface,"edge":unit.edge,"material_id":order.material_id,"paid_cost":unit.paid_cost,"order_id":order.id}
		order.phase="completed"
	world.touch()
	var validation: String=world.validate(content)
	var before: Dictionary=world.freeze()
	var observations: Array=[]
	var passed: bool=implicit_tiles and paid and HospitalLedger.balance(world)==cash-expected_payment and validation.is_empty()
	for floor_id: int in [1,2,1]:
		view.set_floor(floor_id)
		view.update_facts()
		var actual: Array=_drawn_finishes(view)
		var cells: Array=lower if floor_id==1 else upper
		var material: String="MAT01" if floor_id==1 else "MAT04"
		var expected_color: Color=HospitalView.Palette.SURFACE.lerp(HospitalView.Palette.OAK,0.24) if floor_id==1 else HospitalView.Palette.WARD_FLOOR
		var exact: bool=actual.size()==cells.size()
		for index: int in mini(actual.size(),cells.size()):
			var cell: Array=cells[index]
			var expected_position:=Vector3((float(cell[0])-32)*1.5+0.75,0.065,(float(cell[1])-64)*1.5+0.75)
			var mark: MeshInstance3D=actual[index]
			var box: BoxMesh=mark.mesh
			var surface: StandardMaterial3D=box.material
			exact=exact and mark.get_meta("completed_material_id")==material and mark.position.is_equal_approx(expected_position) and box.size.is_equal_approx(Vector3(1.48,0.025,1.48)) and surface.albedo_color.is_equal_approx(expected_color) and is_equal_approx(surface.roughness,0.9)
		view.walls_cut=true
		view._update_space_geometry()
		var visible: bool=actual.all(func(mark: MeshInstance3D)->bool:return mark.visible)
		passed=passed and exact and visible
		observations.append({"floor_id":floor_id,"expected":cells.size(),"actual":actual.size(),"geometry_and_material":exact,"visible_after_wall_cut":visible})
	var old_marks: Node3D=view._environment_marks
	view.bind(HospitalFactory.create(HospitalSnapshots.uuid(),"清空院区",false,content),1)
	var cleared: bool=old_marks.get_parent()==null and _drawn_finishes(view).is_empty()
	passed=passed and cleared and world.freeze()==before
	view.queue_free()
	simulation.dispose()
	return {"passed":passed,"no_implicit_tiles":implicit_tiles,"payment_conserved":paid and HospitalLedger.balance(world)==cash-expected_payment,"observations":observations,"old_hospital_retired":cleared,"validation":validation,"scope":"Exact paid visible per-cell presentation, no GPU or timing claim"}

func _drawn_finishes(view: HospitalView) -> Array:
	return view._environment_marks.get_children().filter(func(node: Node)->bool:return node is MeshInstance3D and node.has_meta("completed_material_id"))

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
	for probe: String in ["used","transport_clock","other_floor","room_origin","room_size","legacy_origin","legacy_size","room_cells","cell_order","wall_edges","blocked","door_cell","door_span","connector_cell","connector_anchor","connector_footprint","connector_stop","plots","top_floor"]:
		world.facts = baseline.duplicate(true)
		if probe=="cell_order": world.facts.rooms.room_gp.cells = [[36,86],[37,86],[36,87]]
		if probe in ["legacy_origin","legacy_size"]: world.facts.rooms.room_gp.erase("cells")
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
			"room_origin", "legacy_origin": world.facts.rooms.room_gp.origin[0] += 1
			"room_size", "legacy_size": world.facts.rooms.room_gp.size[0] += 1
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
		var ignored: bool = probe in ["used","transport_clock","other_floor","room_origin","room_size"]
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
		if facility.definition_id!="SE01": continue
		var wrapper: Node3D = Node3D.new()
		view.add_child(wrapper)
		view._facilities[id] = wrapper
		var signature: String = str(facility.definition_id)+":"+JSON.stringify(facility.footprint)+":"+str(facility.get("rotation",0))
		view._bind_entity("facility:"+id,signature,wrapper,"res://assets/models/core_se01_machine.glb")
		# Cache the proxy's missing player, then publish the replacement.
		view._animation_player(wrapper)
		facility_only = view.publish_resource(view.resource_ticket("facility:"+id),Node3D.new()) and view.rebinds==2 and not wrapper.has_meta("_hospital_animation_player")
		break
	var lookups: Dictionary = _model_lookups(view)
	view._skin_actor_ids[str(actor_ids[0])] = true
	view._remove_actor(str(actor_ids[0]))
	view._remove_actor(str(actor_ids[1]))
	var removal_pending: bool = view._skin_bindings_dirty and view.rebinds==2
	view._complete_resources()
	var removal_rebound: bool = removal_pending and view.rebinds==3 and not view._skin_bindings_dirty
	view._complete_resources()
	removal_rebound = removal_rebound and view.rebinds==3
	var paging: Dictionary = _skin_batch_pages(t,content)

	t.check(case_id,one_bounds and coalesced and independent and rejected and facility_only and lookups.ok and removal_rebound and paging.ok and world.freeze()==before,{"one_bounds_per_update":one_bounds,"two_publications_one_rebind":coalesced,"standalone_publication":independent,"stale_ticket_rejected":rejected,"facility_preserves_staff_batches":facility_only,"model_lookup_results":lookups.ok,"model_lookup_details":lookups,"removals_one_rebind_without_publication":removal_rebound,"skin_pages":paging,"scope":"publication orchestration with a resource double; source hashes/material/bones remain CORE-33"})
	bounds.queue_free()
	view.queue_free()
	await t.process_frame

func _skin_batch_pages(t, content: HospitalContent) -> Dictionary:
	# Rendering-only synthetic sources: one compatible bone/triangle, shared
	# material and mesh. These do not stand in for hospital business actors.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,StandardMaterial3D.new())
	var skin: Skin = Skin.new()
	skin.add_bind(0,Transform3D.IDENTITY)
	var observations: Array = []
	var ok: bool = true
	for count: int in [1,2,63,64,65,128,129]:
		var view: HospitalView = HospitalView.new(content)
		view.world = WorldState.new({"staff":{}})
		t.root.add_child(view)
		for index: int in count:
			var id: String = "render_source_"+str(index)
			var wrapper: Node3D = Node3D.new()
			var skeleton: Skeleton3D = Skeleton3D.new()
			skeleton.name = "Skeleton"
			skeleton.add_bone("root")
			var source: MeshInstance3D = MeshInstance3D.new()
			source.mesh = mesh
			source.skin = skin
			source.skeleton = NodePath("../Skeleton")
			wrapper.add_child(skeleton)
			wrapper.add_child(source)
			view.add_child(wrapper)
			view._actors[id] = wrapper
			view._actor_models[id] = wrapper
			view.world.facts.staff[id] = {}
		view._bind_skin_batches()
		var members: int = 0
		var capacities: bool = true
		for batch: SkinnedPoseBatch in view._skin_batches:
			var rows: int = int(batch.resource_usage().members)
			members += rows
			capacities = capacities and rows>0 and rows<=64
		var expected_pages: int = 0 if count==1 else ceili(float(count)/64.0)
		var expected_members: int = 0 if count==1 else count
		var passed: bool = capacities and view._skin_batches.size()==expected_pages and members==expected_members and view._skin_actor_ids.size()==expected_members
		ok = ok and passed
		observations.append({"sources":count,"pages":view._skin_batches.size(),"members":members,"passed":passed})
		view._clear_batches()
		view.free()
	return {"ok":ok,"observations":observations}

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
	var pending: HospitalPlansPanel = HospitalPlansPanel.new()
	pending.simulation = simulation
	pending.build_controls()
	var hidden: bool = pending._plans.item_count==0 and clinic.comparisons==0 and pending._apply.disabled and pending._auto.disabled
	var visit: Dictionary=c.world.facts.visits[pending._visit_id]
	var visit_id: String=pending._visit_id
	pending.free()
	# Comparison starts from a lawful completed diagnosis with its original
	# operator and desk identity; the earlier GP session is not under test.
	visit.diagnosis=preload("res://tests/acceptance/clinical_input.gd").diagnosed("gather_worker","gather_facility_0")
	visit.phase="wait_plan"
	c.world.facts.tickets[visit.ticket_id].kind="plan"
	c.world.touch()
	var valid: bool=c.world.validate(content).is_empty()
	var panel: HospitalPlansPanel = HospitalPlansPanel.new()
	panel.simulation = simulation
	panel._visit_id=visit_id
	panel.build_controls()
	var expected: Array = []
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id==c.world.facts.visits[panel._visit_id].disease_id: expected.append(plan.id)
	var actual: Array = []
	for index: int in panel._plans.item_count: actual.append(panel._plans.get_item_metadata(index))
	var once: bool = clinic.comparisons==1 and not expected.is_empty() and actual==expected
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
	t.check(case_id,hidden and valid and once and submit_rechecks and narrow and duplicate_suppressed and restored,{"hidden_until_confirmed_diagnosis":hidden,"diagnosed_boundary_valid":valid,"initial_plan_compare_once":once,"option_order":actual,"submit_rechecks":submit_rechecks,"narrow_search_status":narrow,"unchanged_preview_not_republished":duplicate_suppressed,"preview_restored_after_reshow":restored,"preview_publications_before_hide":before_hide,"preview_publications_after_reshow":publications.size()})
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
	var facts: Dictionary = {"hospital_id":old,"staff":{},"patient_experience":{"staff_consumed":{}}}
	for id: String in staff: facts.staff[id] = {"id":id}
	for id: String in staff:
		for source: String in [old+":course",old+"_job",old+"/receipt","external:source",""]:
			facts.patient_experience.staff_consumed[id+":"+source] = true
	facts.patient_experience.staff_consumed["unmatched:key"] = true
	var before: Dictionary = facts.duplicate(true)
	var control: Dictionary = _original_remap(library,facts,old,next)
	var imported: Dictionary = library._remap_hospital(facts,old,next)
	var mapping: bool = imported==control and facts==before
	var family: Dictionary={"hospital_id":old,"actors":{old+":patient":{"id":old+":patient"},old+":companion":{"id":old+":companion","relative_of":old+":patient","name":old+":patient"}},"visitors":{"stays":{old+":family":{"id":old+":family","actor_id":old+":companion","visit_id":old+":visit"}}}}
	var family_before: Dictionary=family.duplicate(true)
	var family_copy: Dictionary=library._remap_hospital(family,old,next)
	var family_mapped: bool=family_copy.actors[next+":companion"].relative_of==next+":patient" and family_copy.visitors.stays[next+":family"].actor_id==next+":companion" and family_copy.actors[next+":companion"].name==old+":patient" and family==family_before
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
	t.check(case_id,mapping and family_mapped and geometry,{"longest_staff_prefix_and_definition_rules":mapping,"family_patient_identity":family_mapped,"irregular_blocked_colors":geometry,"scope":"pure identity rewrite and generated mesh arrays; durable import remains CORE-26/27"})
	overlay.free()

func _original_remap(library: HospitalLibrary, value: Dictionary, old: String, next: String) -> Dictionary:
	var ids: Dictionary = {old:next}
	library._collect_instance_ids(value,old,next,ids)
	var rewritten: Dictionary = library._rewrite_ids(value,"",old,next,ids)
	var staff: Array = value.staff.keys()
	staff.sort_custom(func(a: String,b: String) -> bool: return a.length()>b.length())
	var consumed: Dictionary = {}
	for key: String in value.patient_experience.staff_consumed:
		var mapped: String = key
		for id: String in staff:
			if key.begins_with(id+":"):
				var source: String = key.substr(id.length()+1)
				var mapped_source: String = next+source.substr(old.length()) if library._hospital_prefix(source,old) else source
				mapped = str(ids.get(id,id))+":"+mapped_source
				break
		consumed[mapped] = value.patient_experience.staff_consumed[key]
	rewritten.patient_experience.staff_consumed = consumed
	return rewritten
