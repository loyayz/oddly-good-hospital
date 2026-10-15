class_name HospitalView
extends Node3D

const Palette = preload("res://game/view/hospital_palette.gd")

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

func _init(database: HospitalContent) -> void:
	content = database
	_geometry = HospitalSpace.new(database)

func bind(state: WorldState, floor_id: int = 1) -> void:
	bind_error = ""
	world = state
	observed_floor = floor_id
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
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
	camera.size = 42.0
	camera.position = Vector3(74.0,50.0,74.0)
	camera.look_at_from_position(camera.position,Vector3(24,0,24))
	camera.far = 180.0
	add_child(camera)
	_decorations = Node3D.new()
	add_child(_decorations)
	var floor_mesh: MeshInstance3D = _box(Vector3(48,0.15,48),Palette.FLOOR)
	floor_mesh.position = Vector3(24,-0.075,24)
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
	for room: Dictionary in world.facts.get("rooms",{}).values():
		if int(room.floor_id) != observed_floor:
			continue
		var floor: MeshInstance3D = _box(Vector3(float(room.size[0])*1.5,0.02,float(room.size[1])*1.5),Palette.WARD_FLOOR if room.kind=="ward" else Palette.SURGERY_FLOOR)
		floor.position = _cell_position(room.origin,0)+Vector3(float(room.size[0])*0.75,0.03,float(room.size[1])*0.75)
		_decorations.add_child(floor)
	for facility_id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[facility_id]
		if int(facility.floor_id) != observed_floor:
			continue
		var wrapper: Node3D = Node3D.new()
		wrapper.position = _cell_position(facility.cell,0)
		var model: Node3D = _load_model("core_"+str(facility.definition_id).to_lower()+"_machine.glb")
		if model == null:
			if facility.definition_id in ["M37","M17","EQ01","EQ05"]:
				bind_error = "缺少医疗主体资源："+str(facility.definition_id)
				wrapper.free()
				return
			model = _box(Vector3(float(facility.footprint[0])*1.5,1.0,float(facility.footprint[1])*1.5),Palette.FURNITURE)
			model.position = Vector3(float(facility.footprint[0])*0.75,0.5,float(facility.footprint[1])*0.75)
		wrapper.add_child(model)
		_facilities[facility_id] = wrapper
		add_child(wrapper)
		var name: String = str(content.facility_definition(facility.definition_id).get("name",{"FUR01":"接待台","FUR02":"诊断台"}.get(facility.definition_id,"服务位")))
		_label(wrapper,name,Vector3(1.5,3.0,1.5))
		if facility.definition_id=="M37":
			var props: Node3D = _load_scene("res://assets/gags/device_m37_filter.glb")
			if props==null:
				bind_error = "调理舱的风车与滤袋资源缺失"
				return
			props.position = Vector3(1.5,1.3,1.5)
			wrapper.add_child(props)
			_machine_props[facility_id] = props
	for connector: Dictionary in world.facts.connectors.values():
		if HospitalTransit.has_stop(connector,observed_floor):
			var definition: Dictionary = content.definition("vertical_connectors",connector.definition_id)
			var base: Vector3 = _cell_position(connector.cell,0)
			var w: float = float(connector.footprint[0])*HospitalSpace.CELL_METERS
			var d: float = float(connector.footprint[1])*HospitalSpace.CELL_METERS
			var platform: MeshInstance3D = _box(Vector3(w,0.16,d),Palette.PLATFORM)
			platform.position = base+Vector3(w*0.5,0.08,d*0.5)
			add_child(platform)
			var opening: Vector3 = _cell_position(connector.anchor,0)+Vector3(0.75,0,0)
			var net_width: float = float(definition.clear_width_m)
			var net_height: float = float(definition.clear_height_m)
			for side: float in [-0.1,net_width+0.1]:
				var post: MeshInstance3D = _box(Vector3(0.2,net_height,0.2),Palette.STRUCTURE)
				post.position = opening+Vector3(side,net_height*0.5,0)
				add_child(post)
			var header: MeshInstance3D = _box(Vector3(net_width+0.4,0.2,0.2),Palette.STRUCTURE)
			header.position = opening+Vector3(net_width*0.5,net_height+0.1,0)
			add_child(header)
			_label(header,str(definition.name),Vector3(0,0.5,0))
	for actor_id: String in world.ids("actors"):
		var actor: Dictionary = world.facts.actors[actor_id]
		var wrapper: Node3D = Node3D.new()
		var model: Node3D = _load_model("core_"+str(actor.species_id).to_lower()+"_body.glb")
		if model == null:
			bind_error = "缺少当前医院身体资源："+str(actor.species_id)
			wrapper.free()
			return
		wrapper.add_child(model)
		_actor_models[actor_id] = model
		_actors[actor_id] = wrapper
		add_child(wrapper)
		var dimensions: Dictionary = content.actor_body(actor)
		_actor_labels[actor_id] = _label(wrapper,actor.name,Vector3(0,float(dimensions.height_m)+0.35,0))
		for visit: Dictionary in world.facts.visits.values():
			if visit.actor_id!=actor_id:
				continue
			var filename: String = {"B_S49_D37_M37":"case_d37_tissue.glb","B_S49_D23_M23":"case_d23_dream.glb"}.get(visit.binding_id,"")
			if not filename.is_empty():
				var props: Node3D = _load_scene("res://assets/gags/"+filename)
				if props==null:
					bind_error = "病例的症状与康复资源缺失"
					return
				var skeleton: Skeleton3D = _skeleton(model)
				var slot: String = "hand_l" if visit.binding_id=="B_S49_D37_M37" else "head"
				if skeleton==null or skeleton.find_bone(slot)<0:
					bind_error = "病例必要的身体插槽缺失："+slot
					props.free()
					return
				wrapper.add_child(props)
				_case_props[actor_id] = {"node":props,"visit_id":visit.id,"slot":slot}
	update_facts()
	_bind_skin_batches()

func update_facts() -> void:
	if world == null:
		return
	for actor_id: String in _actors:
		var actor: Dictionary = world.facts.actors[actor_id]
		var wrapper: Node3D = _actors[actor_id]
		var projected: Dictionary = _project_location(actor)
		wrapper.visible = projected.visible
		if not wrapper.visible:
			continue
		wrapper.position = projected.position
		var model: Node3D = _actor_models[actor_id]
		model.rotation = Vector3(-PI/2 if actor.get("posture","standing")=="lying" else 0.0,float(actor.facing),0)
		var pose: Dictionary = _pose(actor_id)
		var player: AnimationPlayer = _animation_player(model)
		if player != null:
			var animation_name: StringName = _animation_name(player,pose.name)
			if not animation_name.is_empty():
				if player.current_animation != animation_name:
					player.play(animation_name)
				player.seek(float(pose.time),true)
		if _case_props.has(actor_id):
			_update_case_props(actor_id)
	for facility_id: String in _facilities:
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
		if world.facts.facilities[facility_id].failed:
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
	for actor_id: String in _actor_labels:
		(_actor_labels[actor_id] as Label3D).visible = actor_id==_selected or actor_id==follow_actor
	for batch: SkinnedPoseBatch in _skin_batches:
		batch.publish(_visible_body_bounds())

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
	if actor.location.kind=="transit":
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
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var nearest: float = INF
	var selected: String = ""
	for actor_id: String in _actors:
		var wrapper: Node3D = _actors[actor_id]
		if not wrapper.visible:
			continue
		var dimensions: Dictionary = content.actor_body(world.facts.actors[actor_id])
		var extents: Vector3 = Vector3(float(dimensions.width_m),float(dimensions.height_m),float(dimensions.depth_m))
		var box: AABB = AABB(wrapper.position-Vector3(extents.x*0.5,0,extents.z*0.5),extents)
		if world.facts.actors[actor_id].location.kind=="floor":
			var rect: Rect2 = _geometry.body_rectangle(world.facts.actors[actor_id])
			box = AABB(Vector3((rect.position.x-32)*1.5,wrapper.position.y,(rect.position.y-64)*1.5),Vector3(rect.size.x*1.5,extents.y,rect.size.y*1.5))
		if world.facts.actors[actor_id].get("posture","standing")=="lying":
			box = AABB(wrapper.position-Vector3(extents.x*0.5,extents.z*0.5,extents.y),Vector3(extents.x,extents.z,extents.y))
		var hit: Variant = box.intersects_ray(origin,direction)
		if hit is Vector3:
			var distance: float = origin.distance_to(hit)
			if distance < nearest:
				nearest = distance
				selected = actor_id
	_selected = selected
	return selected

func _pose(actor_id: String) -> Dictionary:
	if low_motion:
		return {"name":"low_motion","time":0.5}
	if world.facts.moves.has(actor_id):
		return {"name":"walk","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for movement: Dictionary in world.facts.moves.values():
		if actor_id in movement.get("members",[]):
			return {"name":"walk","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}
	for session: Dictionary in world.facts.sessions.values():
		if (actor_id==world.facts.visits[session.visit_id].actor_id or actor_id in session.staff_ids) and world.facts.facilities[session.facility_id].failed and session.kind!="wake":
			return {"name":"pause","time":0.5}
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
	return {"name":"idle","time":fmod(float(world.facts.sim_tick)*0.1,1.0)}

func _cell_position(cell: Array, center: float) -> Vector3:
	return Vector3((float(cell[0])-32)*1.5+center,0,(float(cell[1])-64)*1.5+center)

func _load_model(filename: String) -> Node3D:
	var path: String = "res://assets/models/"+filename
	return _load_scene(path)

func _load_scene(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	return scene.instantiate() as Node3D

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
		(_wall_nodes[cell] as Node3D).visible = true
	for door: Dictionary in world.facts.floors.overrides.get(str(observed_floor),{}).get("doors",[]):
		var reservation: Dictionary = world.facts.adaptations.get(door.id,{})
		var definition: Dictionary = content.definition("doors",door.definition_id)
		var span: int = int(reservation.get("span",door.span))
		var width: float = float(reservation.get("clear_width_m",definition.clear_width_m))
		var height: float = float(reservation.get("clear_height_m",definition.clear_height_m))
		var frame: Node3D = _door_frames[door.id]
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
		if reservation.kind!="facility" or int(reservation.floor_id)!=observed_floor:
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
