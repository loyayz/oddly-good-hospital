class_name HospitalView
extends Node3D

const Palette = preload("res://game/view/hospital_palette.gd")
const SharedResources = preload("res://game/view/view_resources.gd")

var world: WorldState
var content: HospitalContent
var observed_floor: int = 1
var low_motion: bool = false
var camera: Camera3D
var _actors: Dictionary = {}
var _actor_models: Dictionary = {}
var _facilities: Dictionary = {}
var _decorations: Node3D
var _selected: String = "patient"
var _geometry: HospitalSpace
var _skin_batches: Array[SkinnedPoseBatch] = []
var bind_error: String = ""
var follow_actor: String = ""
var _case_props: Dictionary = {}
var _machine_props: Dictionary = {}
var _wall_nodes: Dictionary = {}
var _door_frames: Dictionary = {}
var _extension_nodes: Dictionary = {}
var _labels: Array[Label3D] = []
var _actor_labels: Dictionary = {}
var hospital_session: String = ""
var view_generation: int = 0
var walls_cut: bool = false
var _resources: RefCounted = SharedResources.new()
var _bindings: Dictionary = {}
var _binding_next: int = 0
var _pending_resources: Array[Dictionary] = []
var _geometry_signature: String = ""
var _camera_target: Vector3 = Vector3(24,0,24)
var _retiring: Array[WeakRef] = []
var _selection_outline: Node3D
var _environment_marks: Node3D
var _environment_marks_signature: String = ""
var _environment_heatmap: MultiMeshInstance3D
var _heatmap_stamp: String = ""
var _heatmap_subjects: Array[String] = []
var _equipment_marks: Dictionary = {}

func _init(database: HospitalContent) -> void:
	content = database
	_geometry = HospitalSpace.new(database)

func bind(state: WorldState, floor_id: int = 1, session_id: String = "") -> void:
	bind_error = ""
	view_generation += 1
	hospital_session = session_id if not session_id.is_empty() else str(state.get_instance_id())+":"+str(view_generation)
	world = state
	observed_floor = floor_id
	_pending_resources.clear()
	_clear_batches()
	for child: Node in get_children():
		_retire(child)
	_actors.clear()
	_actor_models.clear()
	_facilities.clear()
	_skin_batches.clear()
	_case_props.clear()
	_machine_props.clear()
	_wall_nodes.clear()
	_door_frames.clear()
	_extension_nodes.clear()
	_labels.clear()
	_actor_labels.clear()
	_bindings.clear()
	_geometry_signature = ""
	_environment_marks_signature = ""
	_environment_heatmap = null
	_heatmap_stamp = ""
	_heatmap_subjects.clear()
	_equipment_marks.clear()
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Palette.BACKDROP
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("f0f2f7")
	environment.environment.ambient_light_energy = 0.32
	add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-32,0)
	light.light_color = Color("fff9f1")
	light.light_energy = 0.38
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = float(content.balance.camera_view.default_size_m)
	camera.position = Vector3(74.0,50.0,74.0)
	camera.look_at_from_position(camera.position,Vector3(24,0,24))
	camera.far = 180.0
	add_child(camera)
	_decorations = Node3D.new()
	add_child(_decorations)
	_selection_outline = Node3D.new()
	add_child(_selection_outline)
	_environment_marks = Node3D.new()
	add_child(_environment_marks)
	update_facts()

func set_floor(floor_id: int) -> void:
	if world!=null and floor_id!=observed_floor:
		bind(world,floor_id,hospital_session)

func _sync_geometry() -> void:
	var rooms: Array = []
	for room: Dictionary in world.facts.get("rooms",{}).values():
		if int(room.floor_id)==observed_floor:
			rooms.append(room)
	var connectors: Array = []
	for connector: Dictionary in world.facts.connectors.values():
		if HospitalTransit.has_stop(connector,observed_floor):
			connectors.append({"definition_id":connector.definition_id,"cell":connector.cell,"anchor":connector.anchor,"footprint":connector.footprint,"stops":connector.get("stops",[])})
	var door_shapes: Array = []
	for door: Dictionary in world.facts.floors.overrides.get(str(observed_floor),{}).get("doors",[]):
		var adapted: Dictionary = world.facts.adaptations.get(door.id,{})
		door_shapes.append([door.id,adapted.get("span",door.span),adapted.get("clear_height_m",0)])
	var layout: Dictionary = world.facts.floors.overrides.get(str(observed_floor),{})
	var signature: String = JSON.stringify([layout.get("plots",[]),layout.get("blocked",[]),layout.get("doors",[]),rooms,connectors,door_shapes],"",true,true)
	if signature==_geometry_signature:
		return
	_geometry_signature = signature
	for child: Node in _decorations.get_children():
		_retire(child)
	_wall_nodes.clear()
	_door_frames.clear()
	for plot: Array in world.facts.floors.overrides.get(str(observed_floor),{}).get("plots",[]):
		var floor_mesh: MeshInstance3D = _box(Vector3(48,0.15,48),Palette.FLOOR)
		floor_mesh.position = _cell_position([int(plot[0])*32,int(plot[1])*32],24)+Vector3(0,-0.075,0)
		_decorations.add_child(floor_mesh)
	for obstacle: Array in world.facts.floors.overrides.get(str(observed_floor),{}).get("blocked",[]):
		var wall: MeshInstance3D = _box(Vector3(1.5,0.7,1.5),Palette.WALL)
		wall.position = _cell_position(obstacle,0.75)+Vector3(0,0.35,0)
		_decorations.add_child(wall)
		_wall_nodes[Vector2i(int(obstacle[0]),int(obstacle[1]))] = wall
	for door: Dictionary in world.facts.floors.overrides.get(str(observed_floor),{}).get("doors",[]):
		var frame: Node3D = Node3D.new()
		frame.position = _cell_position(door.cell,0)
		if door.axis=="y":
			frame.rotation.y = -PI/2
		_decorations.add_child(frame)
		for index: int in 3:
			frame.add_child(_box(Vector3.ONE,Palette.OAK))
		_door_frames[door.id] = frame
	for room: Dictionary in rooms:
		if room.has("cells"):
			for cell: Array in room.cells:
				var tile: MeshInstance3D = _box(Vector3(1.5,0.02,1.5),Palette.WARD_FLOOR if room.kind=="ward" else Palette.SURGERY_FLOOR)
				tile.position = _cell_position(cell,0.75)+Vector3.UP*0.03
				_decorations.add_child(tile)
		else:
			var floor: MeshInstance3D = _box(Vector3(float(room.size[0])*1.5,0.02,float(room.size[1])*1.5),Palette.WARD_FLOOR if room.kind=="ward" else Palette.SURGERY_FLOOR)
			floor.position = _cell_position(room.origin,0)+Vector3(float(room.size[0])*0.75,0.03,float(room.size[1])*0.75)
			_decorations.add_child(floor)
		for edge: Dictionary in room.get("wall_edges",[]):
			for along: int in range(int(edge.low),int(edge.high)):
				var opening: bool = false
				for door: Dictionary in layout.get("doors",[]):
					var coordinate: int = int(door.cell[0] if door.axis=="x" else door.cell[1])
					var line: int = int(door.cell[1] if door.axis=="x" else door.cell[0])
					var span: int = int(world.facts.adaptations.get(door.id,{}).get("span",door.span))
					if door.axis==edge.axis and line==int(edge.line) and along>=coordinate and along<coordinate+span:
						opening = true
				if opening:
					continue
				var wall: MeshInstance3D = _box(Vector3(1.5,0.7,0.12) if edge.axis=="x" else Vector3(0.12,0.7,1.5),Palette.WALL)
				wall.position = _cell_position([along,edge.line] if edge.axis=="x" else [edge.line,along],0)+(Vector3(0.75,0.35,0) if edge.axis=="x" else Vector3(0,0.35,0.75))
				wall.set_meta("wall_edge",edge)
				_decorations.add_child(wall)
	for connector: Dictionary in world.facts.connectors.values():
		if HospitalTransit.has_stop(connector,observed_floor):
			var definition: Dictionary = content.definition("vertical_connectors",connector.definition_id)
			var base: Vector3 = _cell_position(connector.cell,0)
			var w: float = float(connector.footprint[0])*HospitalSpace.CELL_METERS
			var d: float = float(connector.footprint[1])*HospitalSpace.CELL_METERS
			var platform: MeshInstance3D = _box(Vector3(w,0.16,d),Palette.PLATFORM)
			platform.position = base+Vector3(w*0.5,0.08,d*0.5)
			_decorations.add_child(platform)
			var opening: Vector3 = _cell_position(connector.anchor,0)+Vector3(0.75,0,0)
			var net_width: float = float(definition.clear_width_m)
			var net_height: float = float(definition.clear_height_m)
			for side: float in [-0.1,net_width+0.1]:
				var post: MeshInstance3D = _box(Vector3(0.2,net_height,0.2),Palette.STRUCTURE)
				post.position = opening+Vector3(side,net_height*0.5,0)
				_decorations.add_child(post)
			var header: MeshInstance3D = _box(Vector3(net_width+0.4,0.2,0.2),Palette.STRUCTURE)
			header.position = opening+Vector3(net_width*0.5,net_height+0.1,0)
			_decorations.add_child(header)
			_label(header,str(definition.name),Vector3(0,0.5,0))

func update_facts(interpolation_alpha: float = 1.0) -> void:
	if world == null:
		return
	_sync_geometry()
	_sync_entities()
	_sync_environment_marks()
	_complete_resources()
	_labels = _labels.filter(func(label: Variant) -> bool: return is_instance_valid(label) and not label.is_queued_for_deletion())
	_retiring = _retiring.filter(func(reference: WeakRef) -> bool: return reference.get_ref()!=null)
	for actor_id: String in _actors:
		var actor: Dictionary = world.facts.actors[actor_id]
		var wrapper: Node3D = _actors[actor_id]
		var projected: Dictionary = _project_location(actor)
		wrapper.visible = projected.visible
		if not wrapper.visible:
			continue
		var binding: Dictionary = _bindings["actor:"+actor_id]
		var current: Vector3 = projected.position
		if binding.sample_tick!=world.sim_tick or not (binding.sample_position as Vector3).is_equal_approx(current):
			var previous: Vector3 = binding.sample_position
			var delta: Vector3 = current-previous
			# Interpolate only one observed cardinal step. A skipped boundary may
			# contain a turn or transit handoff and must not cut through its wall.
			var cardinal: bool = is_zero_approx(delta.x) or is_zero_approx(delta.z)
			binding.previous_position = previous if world.sim_tick-int(binding.sample_tick)==1 and cardinal else current
			binding.sample_position = current
			binding.sample_tick = world.sim_tick
		wrapper.position = (binding.previous_position as Vector3).lerp(current,clampf(interpolation_alpha,0,1))
		var model: Node3D = _actor_models[actor_id]
		model.rotation = Vector3(-PI/2 if actor.get("posture","standing")=="lying" else 0.0,float(actor.facing),0)
		var pose: Dictionary = _pose(actor_id)
		wrapper.set_meta("business_pose",pose.name)
		if world.facts.staff.has(actor_id):
			var staff_status: Dictionary = _staff_status(actor_id)
			(_actor_labels[actor_id] as Label3D).text = str(actor.name)+"\n"+str(staff_status.text)
			wrapper.set_meta("life_attention",staff_status.attention)
		var player: AnimationPlayer = _animation_player(model)
		if player != null:
			var animation_name: StringName = _animation_name(player,pose.name)
			if animation_name.is_empty() and pose.name in ["sleep","rest","recreation"]:
				animation_name = _animation_name(player,"sit" if pose.name=="rest" else "pause")
			if not animation_name.is_empty():
				if player.current_animation != animation_name:
					player.play(animation_name)
				player.seek(float(pose.time),true)
		if _case_props.has(actor_id):
			if not world.facts.visits.has(_case_props[actor_id].visit_id):
				_retire(_case_props[actor_id].node)
				_case_props.erase(actor_id)
		if not _case_props.has(actor_id) and not bool(wrapper.get_meta("resource_proxy",true)):
			_bind_case_props(actor_id)
		if _case_props.has(actor_id):
			_update_case_props(actor_id)
	for facility_id: String in _facilities:
		(_facilities[facility_id] as Node3D).position = _cell_position(world.facts.facilities[facility_id].cell,0)
		_update_equipment_mark(facility_id)
		var player: AnimationPlayer = _animation_player(_facilities[facility_id])
		if player == null:
			continue
		var requested: String = "idle"
		var local_time: float = 0.0
		for session: Dictionary in world.facts.sessions.values():
			if session.facility_id!=facility_id:
				continue
			if session.kind in ["outpatient","surgery"]:
				var completed: int = int(session.total_ticks)-int(session.remaining_ticks)
				var cumulative: int = 0
				var previous: int = 0
				var names: Array[String] = ["prepare","process","climax","safe_finish"]
				for index: int in 4:
					cumulative += int(content.balance.treatment_presentation.beat_basis_points[index])
					var boundary: int = ceili(float(session.total_ticks)*cumulative/10000.0)
					if completed<boundary:
						requested = names[index]
						local_time = float(completed-previous)/maxi(1,boundary-previous)*2.0
						break
					previous = boundary
			else:
				requested = "work"
				local_time = fmod(float(world.facts.sim_tick)*0.1,2.0)
		if world.facts.facilities[facility_id].get("failed",false):
			requested = "pause"
			local_time = 0.5
		if low_motion:
			requested = "low_motion"
			local_time = 0.5
		var animation_name: StringName = _animation_name(player,requested)
		if not animation_name.is_empty():
			if player.current_animation!=animation_name:
				player.play(animation_name)
			player.seek(local_time,true)
		if _machine_props.has(facility_id):
			_seek_prop(_machine_props[facility_id],"low_motion" if low_motion else ("paused" if requested in ["idle","pause"] else "work"),local_time)
	_update_space_geometry()
	if not follow_actor.is_empty() and _actors.has(follow_actor) and (_actors[follow_actor] as Node3D).visible:
		var target: Vector3 = (_actors[follow_actor] as Node3D).position+Vector3.UP*1.5
		camera.look_at_from_position(target+Vector3(50,50,50),target)
	var viewport_height: float = maxf(1.0,get_viewport().get_visible_rect().size.y)
	for label: Label3D in _labels:
		label.pixel_size = camera.size*18.0/(float(label.font_size)*viewport_height)
		var logical_id: String = str(label.get_parent().get_meta("logical_entity_id",""))
		if logical_id.begins_with("facility:"):
			var facility_id: String = logical_id.trim_prefix("facility:")
			label.visible = facility_id==_selected or bool(world.facts.facilities.get(facility_id,{}).get("failed",false))
	for actor_id: String in _actor_labels:
		(_actor_labels[actor_id] as Label3D).visible = actor_id==_selected or actor_id==follow_actor or bool(_actors[actor_id].get_meta("life_attention",false))
	_update_selection()
	for batch: SkinnedPoseBatch in _skin_batches:
		batch.publish(_visible_body_bounds())

func _sync_entities() -> void:
	var visible_actors: Dictionary = {}
	for actor_id: String in world.ids("actors"):
		var actor: Dictionary = world.facts.actors[actor_id]
		var projection: Dictionary = _project_location(actor)
		if not projection.visible:
			continue
		var dimensions: Dictionary = content.actor_body(actor)
		var bounds: AABB = AABB(projection.position-Vector3(float(dimensions.width_m)*0.5,0,float(dimensions.depth_m)*0.5),Vector3(float(dimensions.width_m),float(dimensions.height_m),float(dimensions.depth_m)))
		if not _in_view(bounds):
			continue
		visible_actors[actor_id] = true
		var signature: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))+":"+JSON.stringify(dimensions,"",true,true)
		var key: String = "actor:"+actor_id
		if _bindings.has(key) and _bindings[key].signature!=signature:
			_remove_actor(actor_id)
		if not _actors.has(actor_id):
			var wrapper: Node3D = Node3D.new()
			wrapper.position = projection.position
			add_child(wrapper)
			_actors[actor_id] = wrapper
			var model: Node3D = _body_proxy(dimensions)
			wrapper.add_child(model)
			_actor_models[actor_id] = model
			_actor_labels[actor_id] = _label(wrapper,str(actor.name),Vector3(0,float(dimensions.height_m)+0.35,0))
			_bind_entity(key,signature,wrapper,"res://assets/models/core_"+str(actor.species_id).to_lower()+"_body.glb")
	for actor_id: String in _actors.keys():
		if not visible_actors.has(actor_id):
			_remove_actor(actor_id)
	var visible_facilities: Dictionary = {}
	for facility_id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[facility_id]
		if int(facility.floor_id)!=observed_floor:
			continue
		var layout: Dictionary = _geometry.facility_layout(world,facility_id)
		var size: Vector3 = Vector3(float(layout.footprint[0])*1.5,3.0,float(layout.footprint[1])*1.5)
		if not _in_view(AABB(_cell_position(facility.cell,0),size)):
			continue
		visible_facilities[facility_id] = true
		var key: String = "facility:"+facility_id
		var signature: String = str(facility.definition_id)+":"+JSON.stringify(facility.footprint)+":"+str(facility.get("rotation",0))
		if _bindings.has(key) and _bindings[key].signature!=signature:
			_remove_facility(facility_id)
		if not _facilities.has(facility_id):
			var wrapper: Node3D = Node3D.new()
			wrapper.position = _cell_position(facility.cell,0)
			_facilities[facility_id] = wrapper
			add_child(wrapper)
			var proxy: MeshInstance3D = _box(Vector3(float(facility.footprint[0])*1.5,1.0,float(facility.footprint[1])*1.5),Palette.FURNITURE)
			proxy.position = Vector3(float(facility.footprint[0])*0.75,0.5,float(facility.footprint[1])*0.75)
			proxy.name = "ResourceProxy"
			wrapper.add_child(proxy)
			_label(wrapper,str(content.facility_definition(facility.definition_id).get("name",facility.definition_id)),Vector3(1.5,3.0,1.5))
			_bind_entity(key,signature,wrapper,"res://assets/models/core_"+str(facility.definition_id).to_lower()+"_machine.glb")
	for facility_id: String in _facilities.keys():
		if not visible_facilities.has(facility_id):
			_remove_facility(facility_id)

func _bind_entity(key: String, signature: String, wrapper: Node3D, path: String) -> void:
	_binding_next += 1
	_bindings[key] = {"generation":_binding_next,"signature":signature,"node":wrapper,"path":path,"sample_tick":world.sim_tick,"sample_position":wrapper.position,"previous_position":wrapper.position}
	wrapper.set_meta("logical_entity_id",key)
	wrapper.set_meta("part_role","body" if key.begins_with("actor:") else "facility")
	wrapper.set_meta("binding_generation",_binding_next)
	wrapper.set_meta("resource_proxy",true)
	if ResourceLoader.exists(path):
		_pending_resources.append(resource_ticket(key))

func resource_ticket(key: String) -> Dictionary:
	if not _bindings.has(key):
		return {}
	return {"hospital_session":hospital_session,"hospital_id":world.hospital_id,"world_instance":world.get_instance_id(),"content_fingerprint":content.content_fingerprint,"view_id":get_instance_id(),"view_generation":view_generation,"floor_id":observed_floor,"entity_key":key,"generation":_bindings[key].generation,"path":_bindings[key].path}

func accepts_resource(ticket: Dictionary) -> bool:
	var key: String = str(ticket.get("entity_key",""))
	if world==null or ticket.get("hospital_session")!=hospital_session or ticket.get("hospital_id")!=world.hospital_id or ticket.get("world_instance")!=world.get_instance_id() or ticket.get("content_fingerprint")!=content.content_fingerprint or ticket.get("view_id")!=get_instance_id() or ticket.get("view_generation")!=view_generation or ticket.get("floor_id")!=observed_floor or not _bindings.has(key) or ticket.get("generation")!=_bindings[key].generation or ticket.get("path")!=_bindings[key].path:
		return false
	var id: String = key.substr(key.find(":")+1)
	if key.begins_with("actor:"):
		if not world.facts.actors.has(id):
			return false
		var actor: Dictionary = world.facts.actors[id]
		var current: Dictionary = _project_location(actor)
		var body: Dictionary = content.actor_body(actor)
		var signature: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))+":"+JSON.stringify(body,"",true,true)
		return current.visible and signature==_bindings[key].signature and _in_view(AABB(current.position-Vector3(float(body.width_m)*0.5,0,float(body.depth_m)*0.5),Vector3(float(body.width_m),float(body.height_m),float(body.depth_m))))
	if not world.facts.facilities.has(id):
		return false
	var facility: Dictionary = world.facts.facilities[id]
	var signature: String = str(facility.definition_id)+":"+JSON.stringify(facility.footprint)+":"+str(facility.get("rotation",0))
	return int(facility.floor_id)==observed_floor and signature==_bindings[key].signature and _in_view(AABB(_cell_position(facility.cell,0),Vector3(float(facility.footprint[0])*1.5,3,float(facility.footprint[1])*1.5)))

func _complete_resources() -> void:
	var started: int = Time.get_ticks_usec()
	var count: int = 0
	var budget: int = int(content.balance.spatial_view.view_build_budget_ms_per_frame)*1000
	var limit: int = int(content.balance.spatial_view.view_chunk_starts_per_frame)
	while not _pending_resources.is_empty() and count<limit and Time.get_ticks_usec()-started<budget:
		var ticket: Dictionary = _pending_resources.pop_front()
		if not accepts_resource(ticket):
			continue
		var model: Node3D = _resources.acquire(ticket.path)
		if model!=null:
			publish_resource(ticket,model)
		count += 1

func publish_resource(ticket: Dictionary, model: Node3D) -> bool:
	if not accepts_resource(ticket):
		_resources.release_tree(model)
		model.queue_free()
		return false
	var key: String = ticket.entity_key
	var id: String = key.substr(key.find(":")+1)
	var wrapper: Node3D = _bindings[key].node
	_clear_batches()
	if key.begins_with("actor:"):
		_retire(_actor_models[id])
		wrapper.add_child(model)
		_actor_models[id] = model
		(_actor_labels[id] as Label3D).text = str(world.facts.actors[id].name)
		_bind_case_props(id)
	else:
		var proxy: Node = wrapper.get_node_or_null("ResourceProxy")
		if proxy!=null:
			_retire(proxy)
		wrapper.add_child(model)
		_orient_facility_part(model,world.facts.facilities[id])
		for child: Node in wrapper.get_children():
			if child is Label3D:
				child.text = str(content.facility_definition(world.facts.facilities[id].definition_id).get("name",world.facts.facilities[id].definition_id))
		if world.facts.facilities[id].definition_id=="M37":
			var props: Node3D = _load_scene("res://assets/gags/device_m37_filter.glb")
			if props!=null:
				props.position = Vector3(1.5,1.3,1.5)
				_orient_facility_part(props,world.facts.facilities[id])
				wrapper.add_child(props)
				_machine_props[id] = props
	wrapper.set_meta("resource_proxy",false)
	_bind_skin_batches()
	return true

func _orient_facility_part(node: Node3D, facility: Dictionary) -> void:
	var turns: int = posmod(int(facility.get("rotation",0)),4)
	var definition: Dictionary = content.facility_definition(facility.definition_id)
	var size: Array = definition.get("footprint",facility.footprint)
	var offset: Vector3 = Vector3.ZERO
	match turns:
		1: offset.x = float(size[1])*1.5
		2: offset = Vector3(float(size[0])*1.5,0,float(size[1])*1.5)
		3: offset.z = float(size[0])*1.5
	var basis: Basis = Basis(Vector3.UP,-float(turns)*PI*0.5)
	node.position = offset+basis*node.position
	node.rotation.y = -float(turns)*PI*0.5

func _bind_case_props(actor_id: String) -> void:
	var model: Node3D = _actor_models[actor_id]
	for visit: Dictionary in world.facts.visits.values():
		if visit.actor_id!=actor_id:
			continue
		var filename: String = {"B_S49_D37_M37":"case_d37_tissue.glb","B_S49_D23_M23":"case_d23_dream.glb"}.get(visit.binding_id,"")
		if filename.is_empty():
			continue
		var skeleton: Skeleton3D = _skeleton(model)
		var slot: String = "hand_l" if visit.binding_id=="B_S49_D37_M37" else "head"
		if skeleton==null or skeleton.find_bone(slot)<0:
			continue
		var props: Node3D = _load_scene("res://assets/gags/"+filename)
		if props!=null:
			_actors[actor_id].add_child(props)
			_case_props[actor_id] = {"node":props,"visit_id":visit.id,"slot":slot}

func _remove_actor(id: String) -> void:
	_clear_batches()
	_retire(_actors[id])
	_actors.erase(id)
	_actor_models.erase(id)
	_actor_labels.erase(id)
	_case_props.erase(id)
	_bindings.erase("actor:"+id)
	if _selected==id:
		_selected = ""
	if follow_actor==id:
		follow_actor = ""

func _remove_facility(id: String) -> void:
	_equipment_marks.erase(id)
	_retire(_facilities[id])
	_facilities.erase(id)
	_extension_nodes.erase(id)
	_machine_props.erase(id)
	_bindings.erase("facility:"+id)

func _clear_batches() -> void:
	for batch: SkinnedPoseBatch in _skin_batches:
		batch.clear_sources()
		_retire(batch)
	_skin_batches.clear()

func _retire(node: Node) -> void:
	_resources.release_tree(node)
	if node.get_parent()!=null:
		node.get_parent().remove_child(node)
	_retiring.append(weakref(node))
	node.queue_free()

func resource_usage() -> Dictionary:
	var result: Dictionary = _resources.usage()
	result.pending_bindings = _pending_resources.size()
	result.active_bindings = _bindings.size()
	result.retiring_nodes = _retiring.size()
	return result

func _body_proxy(dimensions: Dictionary) -> Node3D:
	var model: Node3D = Node3D.new()
	var size: Vector3 = Vector3(float(dimensions.width_m),float(dimensions.height_m),float(dimensions.depth_m))
	var box: MeshInstance3D = _box(size,Palette.ACTION)
	box.position.y = size.y*0.5
	model.add_child(box)
	return model

func _in_view(bounds: AABB) -> bool:
	if camera==null or not is_inside_tree():
		return true
	var center: Vector3 = bounds.get_center()
	var half: Vector3 = bounds.size*0.5
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(center)>absf(plane.normal.x)*half.x+absf(plane.normal.y)*half.y+absf(plane.normal.z)*half.z:
			return false
	return true

func _visible_body_bounds() -> AABB:
	var combined: AABB = AABB()
	var first: bool = true
	for actor_id: String in _actors:
		var wrapper: Node3D = _actors[actor_id]
		if not wrapper.visible:
			continue
		var actor: Dictionary = world.facts.actors[actor_id]
		var dimensions: Dictionary = content.actor_body(actor)
		var bounds: AABB = AABB(wrapper.position-Vector3(float(dimensions.width_m)*0.5,0,float(dimensions.depth_m)*0.5),Vector3(float(dimensions.width_m),float(dimensions.height_m),float(dimensions.depth_m)))
		combined = bounds if first else combined.merge(bounds)
		first = false
	return combined.grow(0.05)

func _project_location(actor: Dictionary) -> Dictionary:
	var k: int = _geometry.clearance(actor)
	if actor.location.kind=="floor":
		var position: Vector3 = _cell_position(actor.location.cell,float(k)*0.75)
		position.y = float(actor.location.get("height_m",0))
		return {"visible":int(actor.location.floor_id)==observed_floor,"position":position}
	if actor.location.kind=="transit" and world.facts.connectors.has(actor.location.connector_id):
		var connector: Dictionary = world.facts.connectors[actor.location.connector_id]
		var definition: Dictionary = content.definition("vertical_connectors",connector.definition_id)
		var progress: float = 0.0
		if connector.phase in ["riding","alighting"]:
			progress = 1.0 if connector.phase=="alighting" else 1.0-float(connector.remaining_ticks)/maxf(1.0,abs(int(connector.to)-int(connector.from))*float(definition.travel_seconds_per_floor)*10)
		var floor_position: float = lerpf(float(connector.from),float(connector.to),progress)
		var position: Vector3 = _cell_position(connector.anchor,float(k)*0.75)
		var entry: Vector3 = position
		var inside: Vector3 = _cell_position(connector.cell,0)+Vector3(0.75+float(definition.clear_width_m)*0.5,0,float(connector.footprint[1])*0.75)
		if connector.phase=="boarding":
			var boarding: float = 1.0-float(connector.remaining_ticks)/maxf(1.0,float(definition.boarding_seconds)*10)
			position = entry.lerp(inside,boarding)
		elif connector.phase=="alighting":
			var alighting: float = 1.0-float(connector.remaining_ticks)/maxf(1.0,float(definition.alighting_seconds)*10)
			position = inside.lerp(entry,alighting)
		else:
			position = inside
		position.y = (floor_position-float(observed_floor))*7.5
		return {"visible":observed_floor in [int(connector.from),int(connector.to)],"position":position}
	return {"visible":false,"position":Vector3.ZERO}

func pick(screen: Vector2) -> String:
	if camera==null:
		return ""
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var nearest: float = INF
	var selected: String = ""
	for actor_id: String in _actors:
		var wrapper: Node3D = _actors[actor_id]
		if not wrapper.visible:
			continue
		var hit: Variant = _actor_pick_bounds(actor_id).intersects_ray(origin,direction)
		if hit is Vector3:
			var distance: float = origin.distance_to(hit)
			if distance < nearest:
				nearest = distance
				selected = actor_id
	_selected = selected
	return selected

func _actor_pick_bounds(id: String) -> AABB:
	var actor: Dictionary = world.facts.actors[id]
	var body: Dictionary = content.actor_body(actor)
	var position: Vector3 = _project_location(actor).position
	var box: AABB = AABB(position-Vector3(float(body.width_m)*0.5,0,float(body.depth_m)*0.5),Vector3(float(body.width_m),float(body.height_m),float(body.depth_m)))
	if actor.location.kind=="floor":
		var rect: Rect2 = _geometry.body_rectangle(actor)
		var lying: bool = actor.get("posture","standing")=="lying"
		box = AABB(Vector3((rect.position.x-32)*1.5,position.y-(float(body.depth_m)*0.5 if lying else 0.0),(rect.position.y-64)*1.5),Vector3(rect.size.x*1.5,float(body.depth_m) if lying else float(body.height_m),rect.size.y*1.5))
	return box

func pick_entity(screen: Vector2) -> Dictionary:
	if camera==null:
		return {}
	var actor_id: String = pick(screen)
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var nearest: float = INF
	var selected: Dictionary = {"kind":"actor","id":actor_id} if not actor_id.is_empty() else {}
	if not actor_id.is_empty():
		var hit: Variant = _actor_pick_bounds(actor_id).intersects_ray(origin,direction)
		if hit is Vector3:
			nearest = origin.distance_to(hit)
	for id: String in _facilities:
		var facility: Dictionary = _geometry.facility_layout(world,id)
		var bounds: AABB = AABB(_cell_position(facility.cell,0),Vector3(float(facility.footprint[0])*1.5,3,float(facility.footprint[1])*1.5))
		var hit: Variant = bounds.intersects_ray(origin,direction)
		if hit is Vector3 and origin.distance_to(hit)<nearest:
			nearest = origin.distance_to(hit)
			selected = {"kind":"facility","id":id}
	_selected = str(selected.get("id",""))
	return selected

func cell_at_screen(screen: Vector2) -> Array:
	if camera==null:
		return []
	var hit: Variant = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	if not hit is Vector3:
		return []
	return [floori(hit.x/1.5)+32,floori(hit.z/1.5)+64]

func pan_camera(pixels: Vector2) -> void:
	if camera==null:
		return
	follow_actor = ""
	var scale: float = camera.size/maxf(1,get_viewport().get_visible_rect().size.y)
	var offset: Vector3 = -camera.basis.x*pixels.x*scale+camera.basis.y*pixels.y*scale
	offset.y = 0
	camera.position += offset
	_camera_target += offset

func focus_cell(cell: Array) -> void:
	if camera==null or cell.size()!=2:
		return
	follow_actor = ""
	var target: Vector3 = Vector3((float(cell[0])+0.5-32.0)*1.5,0,(float(cell[1])+0.5-64.0)*1.5)
	camera.position += target-_camera_target
	_camera_target = target

func zoom_camera(factor: float) -> void:
	if camera!=null and factor>0 and is_finite(factor):
		camera.size = clampf(camera.size*factor,float(content.balance.camera_view.minimum_size_m),maxf(float(content.balance.camera_view.original_max_size_m),_overview_size()))

func overview() -> void:
	if camera==null:
		return
	var bounds: AABB = _floor_bounds()
	if bounds.size==Vector3.ZERO:
		return
	follow_actor = ""
	_camera_target = bounds.get_center()
	camera.look_at_from_position(_camera_target+Vector3(50,50,50),_camera_target)
	camera.size = _overview_size()

func _floor_bounds() -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for plot: Array in world.facts.floors.overrides.get(str(observed_floor),{}).get("plots",[]):
		var tile: AABB = AABB(_cell_position([int(plot[0])*32,int(plot[1])*32],0),Vector3(48,0,48))
		bounds = tile if first else bounds.merge(tile)
		first = false
	for actor: Dictionary in world.facts.actors.values():
		var projected: Dictionary = _project_location(actor)
		if not projected.visible:
			continue
		var body: Dictionary = content.actor_body(actor)
		var box: AABB = AABB(projected.position-Vector3(float(body.width_m)*0.5,0,float(body.depth_m)*0.5),Vector3(float(body.width_m),float(body.height_m),float(body.depth_m)))
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _overview_size() -> float:
	var bounds: AABB = _floor_bounds()
	if bounds.size==Vector3.ZERO:
		return float(content.balance.camera_view.default_size_m)
	var width: float = 0
	var height: float = 0
	var low: Vector2 = Vector2(INF,INF)
	var high: Vector2 = Vector2(-INF,-INF)
	for index: int in 8:
		var corner: Vector3 = bounds.get_endpoint(index)
		var point: Vector2 = Vector2(camera.basis.x.dot(corner),camera.basis.y.dot(corner))
		low = low.min(point)
		high = high.max(point)
	width = high.x-low.x
	height = high.y-low.y
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = maxf(0.01,viewport_size.x/maxf(1,viewport_size.y))
	return maxf(float(content.balance.camera_view.minimum_size_m),float(content.balance.camera_view.overview_padding_bp)/10000.0*maxf(width/aspect,height))

func _update_selection() -> void:
	var target: Node3D = _actors.get(_selected,_facilities.get(_selected))
	_selection_outline.visible = target!=null
	if target==null:
		return
	while _selection_outline.get_child_count()<4:
		_selection_outline.add_child(_box(Vector3.ONE,Palette.ACTION))
	var size: Vector2 = Vector2.ONE*1.5
	var center: Vector3 = target.position
	if _actors.has(_selected):
		var body: Dictionary = content.actor_body(world.facts.actors[_selected])
		size = Vector2(float(body.width_m),float(body.depth_m))
	else:
		var facility: Dictionary = _geometry.facility_layout(world,_selected)
		size = Vector2(float(facility.footprint[0])*1.5,float(facility.footprint[1])*1.5)
		center += Vector3(size.x*0.5,0,size.y*0.5)
	_selection_outline.position = center+Vector3.UP*0.04
	for index: int in 2:
		var side: float = -1.0 if index==0 else 1.0
		var horizontal: MeshInstance3D = _selection_outline.get_child(index*2)
		(horizontal.mesh as BoxMesh).size = Vector3(size.x+0.12,0.03,0.06)
		horizontal.position.z = side*(size.y*0.5+0.03)
		var vertical: MeshInstance3D = _selection_outline.get_child(index*2+1)
		(vertical.mesh as BoxMesh).size = Vector3(0.06,0.03,size.y+0.12)
		vertical.position.x = side*(size.x*0.5+0.03)

func _pose(actor_id: String) -> Dictionary:
	if low_motion:
		return {"name":"low_motion","time":0.5}
	if world.facts.moves.has(actor_id):
		return {"name":"walk","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for movement: Dictionary in world.facts.moves.values():
		if actor_id in movement.get("members",[]):
			return {"name":"walk","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for session: Dictionary in world.facts.sessions.values():
		if (actor_id==world.facts.visits.get(session.get("visit_id",""),{}).get("actor_id","") or actor_id in session.get("staff_ids",[])) and world.facts.facilities.get(session.get("facility_id",""),{}).get("failed",false) and session.kind!="wake":
			return {"name":"pause","time":0.5}
	if world.facts.staff.has(actor_id):
		var phase: String = str(world.facts.staff[actor_id].get("life_task",{}).get("phase","idle"))
		if phase in ["sleep","rest","recreation"]:
			return {"name":phase,"time":0.5 if phase!="recreation" else fmod(float(world.sim_tick)*0.1,1.0)}
	if world.facts.actors[actor_id].get("posture","standing") == "seated":
		return {"name":"sit","time":0.5}
	for visit: Dictionary in world.facts.visits.values():
		if visit.actor_id != actor_id:
			continue
		if visit.final_result == "cured":
			return {"name":"recover","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
		if visit.phase in ["outpatient","surgery"]:
			return {"name":"work","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
		if visit.phase in ["wake","transfer","recovery","round_wait","round"]:
			return {"name":"pause","time":0.5}
		return {"name":"symptom","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for session: Dictionary in world.facts.sessions.values():
		if actor_id in session.staff_ids:
			return {"name":"work","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for patch: Dictionary in world.facts.get("environment",{}).get("dirt",{}).values():
		if patch.get("worker_id","")==actor_id and patch.get("phase","")=="working":
			return {"name":"work","time":fmod(float(world.sim_tick)*0.1,1.0)}
	for order: Dictionary in world.facts.get("environment",{}).get("orders",{}).values():
		for unit: Dictionary in order.units:
			if unit.get("worker_id","")==actor_id and unit.phase=="working":
				return {"name":"work","time":fmod(float(world.sim_tick)*0.1,1.0)}
	for collection: String in ["jobs","upgrades"]:
		for job: Dictionary in world.facts.get("maintenance",{}).get(collection,{}).values():
			if job.get("worker_id","")==actor_id and job.phase=="working":
				return {"name":"work","time":fmod(float(world.sim_tick)*0.1,1.0)}
	return {"name":"idle","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}

func _sync_environment_marks() -> void:
	var facts: Dictionary = world.facts.get("environment",{})
	var dirt: Array = []
	var surfaces: Array = []
	var units: Array = []
	for patch: Dictionary in facts.get("dirt",{}).values():
		if int(patch.floor_id)==observed_floor:
			dirt.append([patch.id,patch.cell,patch.source_kind,patch.bin_id,patch.phase])
	for surface: Dictionary in facts.get("surfaces",{}).values():
		if int(surface.floor_id)==observed_floor:
			surfaces.append([surface.cell,surface.surface,surface.edge,surface.material_id])
	for order: Dictionary in facts.get("orders",{}).values():
		if int(order.floor_id)!=observed_floor:
			continue
		for unit: Dictionary in order.units:
			if unit.phase not in ["completed","cancelled"]:
				units.append([unit.cell,order.surface,unit.edge,unit.phase,unit.started,order.paused])
	var signature: String = JSON.stringify([observed_floor,dirt,surfaces,units],"",true,true)
	if signature!=_environment_marks_signature:
		_environment_marks_signature = signature
		for child: Node in _environment_marks.get_children():
			_retire(child)
		for surface: Array in surfaces:
			var mark: MeshInstance3D = _surface_mark(surface[0],str(surface[1]),str(surface[2]),_finish_color(str(surface[3])))
			mark.set_meta("completed_material_id",surface[3])
			_environment_marks.add_child(mark)
		for patch: Array in dirt:
			var mark: Node3D = Node3D.new()
			mark.position = _cell_position(patch[1],0.75)+Vector3.UP*(0.9 if not str(patch[3]).is_empty() else 0.07)
			mark.set_meta("dirt_id",patch[0])
			var color: Color = Palette.ACTION if str(patch[4])=="working" else Palette.OAK
			var scrap: MeshInstance3D = _box(Vector3(0.65,0.025,0.43),color if patch[2]!="CL03" else Palette.FURNITURE)
			scrap.rotation.y = 0.28
			mark.add_child(scrap)
			var fold: MeshInstance3D = _box(Vector3(0.22,0.11,0.18),Palette.SURFACE)
			fold.position = Vector3(0.19,0.04,-0.08)
			mark.add_child(fold)
			_environment_marks.add_child(mark)
			if str(patch[4])=="working":
				_label(mark,"清扫中",Vector3(0,0.65,0))
		for unit: Array in units:
			var working: bool = str(unit[3])=="working" and not bool(unit[5])
			var mark: MeshInstance3D = _surface_mark(unit[0],str(unit[1]),str(unit[2]),Palette.ACTION if working else Palette.STRUCTURE)
			mark.scale *= 0.82
			mark.set_meta("construction_state","working" if working else "waiting")
			_environment_marks.add_child(mark)
			_label(mark,"施工中" if working else ("施工暂停" if unit[5] else "待施工"),Vector3(0,0.8,0))
	if _environment_heatmap!=null and is_instance_valid(_environment_heatmap) and _heatmap_stamp!=_environment_read_stamp():
		_environment_heatmap.visible = false

func _surface_mark(cell: Array, surface: String, edge: String, color: Color) -> MeshInstance3D:
	var mark: MeshInstance3D
	var origin: Vector3 = _cell_position(cell,0)
	if surface=="wall":
		mark = _box(Vector3(1.48,0.61,0.035) if edge in ["north","south"] else Vector3(0.035,0.61,1.48),color)
		mark.position = origin+Vector3(0.75 if edge in ["north","south"] else (0.02 if edge=="west" else 1.48),0.36,0.75 if edge in ["west","east"] else (0.02 if edge=="north" else 1.48))
	else:
		mark = _box(Vector3(1.48,0.025,1.48),color)
		mark.position = origin+Vector3(0.75,0.065,0.75)
	return mark

func _finish_color(material_id: String) -> Color:
	return {"MAT01":Palette.SURFACE.lerp(Palette.OAK,0.24),"MAT02":Palette.FLOOR.lerp(Palette.FURNITURE,0.35),
		"MAT03":Color("aabdad"),"MAT04":Palette.WARD_FLOOR,"MAT05":Palette.SURFACE,
		"MAT06":Color("b4c9b7"),"MAT07":Palette.STRUCTURE,"MAT08":Palette.FURNITURE}.get(material_id,Palette.WALL)

func show_environment_heatmap(heatmap: Array) -> void:
	if _environment_heatmap!=null and is_instance_valid(_environment_heatmap):
		_retire(_environment_heatmap)
	_environment_heatmap = null
	_heatmap_subjects.clear()
	if world==null or heatmap.is_empty():
		_heatmap_stamp = ""
		return
	var samples: Array = []
	for raw: Variant in heatmap:
		if not raw is Dictionary or not raw.get("environment") is Dictionary:
			continue
		if raw.get("cell") is Array and raw.cell.size()==2 and int(raw.get("floor_id",observed_floor))==observed_floor and raw.environment.get("status","")=="current":
			samples.append(raw)
	if samples.is_empty():
		_heatmap_stamp = ""
		return
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.42,0.015,1.42)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1,1,1,0.65)
	mesh.material = material
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = mesh
	instances.instance_count = samples.size()
	for index: int in samples.size():
		var sample: Dictionary = samples[index]
		var observation: Dictionary = sample.get("environment",{})
		var value: float = clampf(float(observation.get("value",0))/100.0,0,1)
		var color: Color = Palette.OAK.lerp(Palette.SURFACE,value/0.6) if value<0.6 else Palette.SURFACE.lerp(Palette.SUCCESS,(value-0.6)/0.4)
		instances.set_instance_transform(index,Transform3D(Basis.IDENTITY,_cell_position(sample.cell,0.75)+Vector3.UP*0.11))
		instances.set_instance_color(index,color)
		var subject: String = str(observation.get("subject_id",""))
		if not subject.is_empty() and not subject in _heatmap_subjects:
			_heatmap_subjects.append(subject)
	_environment_heatmap = MultiMeshInstance3D.new()
	_environment_heatmap.multimesh = instances
	_environment_heatmap.set_meta("observed_floor",observed_floor)
	add_child(_environment_heatmap)
	_heatmap_stamp = _environment_read_stamp()

func _environment_read_stamp() -> String:
	var active: Array = []
	for session: Dictionary in world.facts.sessions.values():
		active.append([session.facility_id,session.kind])
	for item: Dictionary in world.facts.get("maintenance",{}).get("upgrades",{}).values():
		active.append([item.facility_id,item.phase])
	var bodies: Array = []
	if not _heatmap_subjects.is_empty():
		for actor: Dictionary in world.facts.actors.values():
			bodies.append([actor.id,actor.location,actor.get("posture","standing"),actor.get("body_binding_id","")])
	var facilities: Array = []
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)==observed_floor:
			facilities.append([facility.id,facility.cell,facility.get("rotation",0),facility.get("failed",false)])
	return JSON.stringify([_geometry_signature,_environment_marks_signature,active,bodies,facilities,world.facts.research],"",true,true)

func _update_equipment_mark(facility_id: String) -> void:
	var item: Dictionary = world.facts.facilities[facility_id]
	if not item.definition_id in content.balance.equipment.maintained_definition_ids:
		return
	var wrapper: Node3D = _facilities[facility_id]
	var grade: int = int(item.get("upgrade_level",item.get("grade",0)))
	var upgradable: bool = false
	for profile: Dictionary in content.catalog.get("medical_equipment_profiles",[]):
		if profile.definition_id==item.definition_id:
			upgradable = true
	var state: String = "可用"
	var accent: Color = Palette.SUCCESS
	if item.get("upgrading_block",false):
		state = "已付材料，等待升级"
		accent = Palette.ACTION
		for order: Dictionary in world.facts.get("maintenance",{}).get("upgrades",{}).values():
			if order.facility_id==facility_id and order.phase not in ["completed","cancelled"]:
				state = "升级施工中" if order.phase=="working" else ("升级暂停" if order.paused else "等待升级施工")
	if item.get("maintenance_block",false):
		state = "维护暂停"
		accent = Palette.ACTION
	var job: Dictionary = world.facts.get("maintenance",{}).get("jobs",{}).get(str(item.get("maintenance_order_id","")),{})
	if not job.is_empty() and job.phase=="working":
		state = "维修中" if job.kind=="repair" else "保养中"
		accent = Palette.ACTION
	elif item.get("failed",false):
		state = "设备故障，等待维修"
		accent = Palette.OAK
	elif item.get("pending_failure",false):
		state = "安全完成当前服务后停机"
		accent = Palette.OAK
	elif float(item.get("condition",100))<=float(content.balance.equipment.stop_new_service_threshold):
		state = "状态过低，暂停新预约"
		accent = Palette.OAK
	var title: String = str(content.facility_definition(item.definition_id).get("name",item.definition_id))
	var tier: String = str(["基础型","精修型","奇想型"][clampi(grade,0,2)]) if upgradable else ""
	for child: Node in wrapper.get_children():
		if child is Label3D:
			child.text = title+(" · "+tier if not tier.is_empty() else "")+"\n"+state+" · 状态%d" % roundi(float(item.get("condition",100)))
	wrapper.set_meta("completed_upgrade_level",grade)
	wrapper.set_meta("equipment_status",state)
	var signature: String = str(grade)+":"+accent.to_html()
	if not _equipment_marks.has(facility_id) or _equipment_marks[facility_id].signature!=signature:
		if _equipment_marks.has(facility_id):
			_retire(_equipment_marks[facility_id].node)
		var marks: Node3D = Node3D.new()
		var w: float = float(item.footprint[0])*HospitalSpace.CELL_METERS
		var d: float = float(item.footprint[1])*HospitalSpace.CELL_METERS
		var rail: MeshInstance3D = _box(Vector3(maxf(0.25,w-0.35),0.055,0.12),Palette.STRUCTURE)
		rail.position = Vector3(w*0.5,0.22,d*0.5)
		marks.add_child(rail)
		var condition: MeshInstance3D = _box(Vector3(maxf(0.25,w-0.35),0.07,0.13),accent)
		condition.position = rail.position+Vector3.UP*0.015
		marks.add_child(condition)
		if upgradable and grade>=1:
			for z: float in [0.14,d-0.14]:
				var trim: MeshInstance3D = _box(Vector3(maxf(0.2,w-0.28),0.09,0.09),Palette.SURFACE)
				trim.position = Vector3(w*0.5,1.12,z)
				marks.add_child(trim)
			for x: float in [0.14,w-0.14]:
				var trim: MeshInstance3D = _box(Vector3(0.09,0.09,maxf(0.2,d-0.28)),Palette.SURFACE)
				trim.position = Vector3(x,1.12,d*0.5)
				marks.add_child(trim)
		if upgradable and grade>=2:
			for side: float in [-1.0,1.0]:
				var calibration: MeshInstance3D = _box(Vector3(0.13,0.42,0.13),Palette.FURNITURE)
				calibration.position = Vector3(w*0.5+side*minf(0.5,w*0.2),1.42,d*0.5)
				marks.add_child(calibration)
		wrapper.add_child(marks)
		_equipment_marks[facility_id] = {"node":marks,"condition":condition,"signature":signature}
	var meter: MeshInstance3D = _equipment_marks[facility_id].condition
	meter.scale.x = maxf(0.01,clampf(float(item.get("condition",100))/100.0,0,1))

func _staff_status(actor_id: String) -> Dictionary:
	var staff: Dictionary = world.facts.staff[actor_id]
	var task: Dictionary = staff.get("life_task",{})
	var phase: String = str(task.get("phase","idle"))
	var status: String = str({"sleep":"睡眠中","rest":"休息中","recreation":"放松中","wait_bed":"等可用睡眠床",
		"wait_safe":"等安全交接后休息","travel":"前往休息点","exiting":"前往院外休整","offsite":"院外休整",
		"returning":"返回岗位","release":"离开休息设施"}.get(phase,"当班" if staff.get("on_shift",false) else "休班"))
	var attention: bool = phase not in ["idle","offsite"]
	var need: String = ""
	if int(staff.get("sleep_remaining_ticks",0))>0 or int(staff.get("awake_ticks",0))>=ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS):
		need = "需要睡眠" if phase!="sleep" else "保留睡眠余量"
	elif float(staff.get("energy",100))<=float(content.balance.wellbeing.recreation_max_energy_priority):
		need = "需要休息"
	elif staff.get("rest_obligation",false) or int(staff.get("rest_debt_ticks",0))>0:
		need = "需要补休"
	if not need.is_empty():
		attention = true
	return {"text":"%s · 能量%d%s" % [status,roundi(float(staff.get("energy",100)))," · "+need if not need.is_empty() else ""],"attention":attention}

func _cell_position(cell: Array, center: float) -> Vector3:
	return Vector3((float(cell[0])-32)*1.5+center,0,(float(cell[1])-64)*1.5+center)

func _load_model(filename: String) -> Node3D:
	var path: String = "res://assets/models/"+filename
	return _load_scene(path)

func _load_scene(path: String) -> Node3D:
	return _resources.acquire(path)

func _update_case_props(actor_id: String) -> void:
	var binding: Dictionary = _case_props[actor_id]
	var props: Node3D = binding.node
	var skeleton: Skeleton3D = _skeleton(_actor_models[actor_id])
	if skeleton==null:
		return
	var bone: int = skeleton.find_bone(binding.slot)
	if bone<0:
		return
	var attachment: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(bone)
	if binding.slot=="head":
		var toward_camera: Vector3 = camera.global_basis.z
		toward_camera.y = 0.0
		props.global_transform = Transform3D(Basis.looking_at(toward_camera.normalized(),Vector3.UP,true),attachment.origin)
	else:
		props.global_transform = attachment
	var visit: Dictionary = world.facts.visits[binding.visit_id]
	var pose: String = "symptom"
	var time: float = fmod(float(world.facts.sim_tick)*0.1,2.0)
	if visit.final_result=="cured":
		pose = "recovery_hold"
		time = 0.5
	elif visit.phase in ["wake","transfer","recovery","round_wait","round"]:
		pose = "awaiting_result" if visit.binding_id=="B_S49_D23_M23" else "paused"
	elif visit.phase in ["outpatient","surgery"]:
		pose = "work"
		for session: Dictionary in world.facts.sessions.values():
			if session.visit_id==visit.id:
				time = float(session.total_ticks-session.remaining_ticks)/maxi(1,int(session.total_ticks))*2.0
				if world.facts.facilities[session.facility_id].failed:
					pose = "paused"
	if low_motion:
		pose = "low_motion_recovery" if visit.final_result=="cured" else ("low_motion_work" if visit.phase in ["outpatient","surgery"] else "low_motion")
		var player: AnimationPlayer = _animation_player(props)
		if player==null or _animation_name(player,pose).is_empty():
			pose = "recovery_hold" if visit.final_result=="cured" else "low_motion"
		time = 0.5
	_seek_prop(props,pose,time)

func _seek_prop(node: Node, name: String, time: float) -> void:
	var player: AnimationPlayer = _animation_player(node)
	if player==null:
		return
	var animation: StringName = _animation_name(player,name)
	if not animation.is_empty():
		if player.current_animation!=animation:
			player.play(animation)
		player.seek(time,true)

func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _skeleton(child)
		if found!=null:
			return found
	return null

func _update_space_geometry() -> void:
	for cell: Vector2i in _wall_nodes:
		(_wall_nodes[cell] as Node3D).visible = not walls_cut
	for child: Node in _decorations.get_children():
		if child is Node3D and child.has_meta("wall_edge"):
			child.visible = not walls_cut
	for door: Dictionary in world.facts.floors.overrides.get(str(observed_floor),{}).get("doors",[]):
		var reservation: Dictionary = world.facts.adaptations.get(door.id,{})
		var definition: Dictionary = content.definition("doors",door.definition_id)
		var span: int = int(reservation.get("span",door.span))
		var width: float = float(reservation.get("clear_width_m",definition.clear_width_m))
		var height: float = float(reservation.get("clear_height_m",definition.clear_height_m))
		var frame: Node3D = _door_frames[door.id]
		frame.visible = not walls_cut
		var margin: float = (float(span)*1.5-width)*0.5
		for index: int in 2:
			var post: MeshInstance3D = frame.get_child(index) as MeshInstance3D
			(post.mesh as BoxMesh).size = Vector3(0.12,height,0.15)
			post.position = Vector3(margin if index==0 else margin+width,height*0.5,0.75)
		var lintel: MeshInstance3D = frame.get_child(2) as MeshInstance3D
		(lintel.mesh as BoxMesh).size = Vector3(width+0.12,0.12,0.15)
		lintel.position = Vector3(float(span)*0.75,height+0.06,0.75)
		for offset: int in span:
			var cell: Vector2i = Vector2i(int(door.cell[0]),int(door.cell[1]))+(Vector2i(offset,0) if door.axis=="x" else Vector2i(0,offset))
			if _wall_nodes.has(cell):
				(_wall_nodes[cell] as Node3D).visible = false
	for id: String in _extension_nodes:
		(_extension_nodes[id] as Node3D).visible = world.facts.adaptations.has(id)
	for id: String in world.facts.adaptations:
		var reservation: Dictionary = world.facts.adaptations[id]
		if reservation.kind!="facility" or int(reservation.floor_id)!=observed_floor or not _facilities.has(id) or not world.facts.actors.has(reservation.actor_id):
			continue
		var facility: Dictionary = world.facts.facilities[id]
		if not _extension_nodes.has(id):
			var pad: MeshInstance3D = _box(Vector3.ONE,Palette.SUPPORT)
			_facilities[id].add_child(pad)
			_extension_nodes[id] = pad
		var pad: MeshInstance3D = _extension_nodes[id]
		var dimensions: Dictionary = content.actor_body(world.facts.actors[reservation.actor_id])
		var reclined: bool = facility.definition_id in ["EQ01","EQ05"]
		(pad.mesh as BoxMesh).size = Vector3(float(dimensions.width_m),0.16,maxf(float(dimensions.depth_m),float(dimensions.height_m)) if reclined else float(dimensions.depth_m))
		pad.position = _geometry.support_anchor(world,id)-Vector3.UP*0.08
		pad.visible = true

func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		(node as AnimationPlayer).callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _animation_player(child)
		if found != null:
			return found
	return null

func _bind_skin_batches() -> void:
	var groups: Dictionary = {}
	for actor_id: String in _actor_models:
		if not world.facts.staff.has(actor_id) or not (_actors[actor_id] as Node3D).visible:
			continue
		var mesh: MeshInstance3D = _mesh_instance(_actor_models[actor_id])
		if mesh==null or mesh.skin==null:
			continue
		var skeleton: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton==null:
			continue
		var key: String = str(mesh.mesh.get_instance_id())+":"+str(mesh.get_active_material(0).get_instance_id())
		if not groups.has(key):
			groups[key] = {"meshes":[],"skeletons":[]}
		groups[key].meshes.append(mesh)
		groups[key].skeletons.append(skeleton)
	for group: Dictionary in groups.values():
		if group.meshes.size()<2:
			continue
		var meshes: Array[MeshInstance3D] = []
		var skeletons: Array[Skeleton3D] = []
		meshes.assign(group.meshes)
		skeletons.assign(group.skeletons)
		var batch: SkinnedPoseBatch = SkinnedPoseBatch.new()
		add_child(batch)
		var reason: String = batch.bind_sources(meshes,skeletons)
		if reason.is_empty():
			_skin_batches.append(batch)
		else:
			remove_child(batch)
			batch.free()

func _mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _mesh_instance(child)
		if found!=null:
			return found
	return null

func _animation_name(player: AnimationPlayer, requested: String) -> StringName:
	for name: StringName in player.get_animation_list():
		if str(name) == requested or str(name).ends_with("/"+requested):
			return name
	return &""

func _label(parent: Node3D, text: String, position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.position = position
	label.font = load("res://assets/fonts/NotoSansCJKsc-Medium.otf")
	label.font_size = 48
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Palette.INK
	label.outline_modulate = Palette.SURFACE
	label.outline_size = 3
	parent.add_child(label)
	_labels.append(label)
	return label

static func _box(dimensions: Vector3, color: Color) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	instance.mesh = mesh
	return instance
