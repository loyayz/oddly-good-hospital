class_name HospitalToiletQueue
extends RefCounted

var space: HospitalSpace
var _intents: Dictionary = {}

func _init(geometry: HospitalSpace) -> void:
	space=geometry

func ensure(world: WorldState) -> void:
	if not world.facts.waiting_life.has("toilet_queues"): world.facts.waiting_life.toilet_queues={}

func observe(world: WorldState) -> void:
	_intents.clear()
	for need: Dictionary in world.facts.waiting_life.needs.values(): register(need)
	for staff: Dictionary in world.facts.staff.values(): register(staff.get("life_task",{}))

func register(intent: Dictionary) -> void:
	if intent.get("public_purpose","")=="toilet": _intents[str(intent.actor_id)]=intent

func choose(world: WorldState, actor_id: String, excluded: Array) -> String:
	var ids: Array=[]
	for room_id: String in space.room_use.rooms(world,"toilet"):
		if room_id in excluded or not space.room_use.reason(world,room_id).is_empty(): continue
		for id: String in space.room_use.facilities(world,room_id,["FUR07","AE03"]):
			var facility: Dictionary=world.facts.facilities[id]
			if facility.get("failed",false) or HospitalRemodel.blocked(world,id): continue
			if space.facility_geometry_quote(world,id,actor_id).ok:
				ids.append(room_id); break
	return str(ids[world.draw("guidance",ids.size())]) if not ids.is_empty() else ""

func leave(world: WorldState, actor_id: String) -> void:
	ensure(world)
	for queue: Dictionary in world.facts.waiting_life.toilet_queues.values(): queue.actor_ids.erase(actor_id)

func members(world: WorldState, room_id: String) -> Array:
	ensure(world)
	return world.facts.waiting_life.toilet_queues.get_or_add(room_id,{"actor_ids":[]}).actor_ids

func point(world: WorldState, room_id: String, actor_id: String) -> Dictionary:
	var room: Dictionary=world.facts.rooms.get(room_id,{})
	if room.is_empty(): return {}
	var door: Dictionary={}
	for candidate: Dictionary in HospitalSpace.floor_layout(world,int(room.floor_id)).doors:
		if candidate.get("room_id","")==room_id: door=candidate; break
	if door.is_empty(): return {}
	var outward:=Vector2(0.0,-float(door.get("interior_side",1))) if door.axis=="x" else Vector2(-float(door.get("interior_side",1)),0.0)
	var edge:=Vector2(float(door.cell[0])+float(door.span)*0.5,float(door.cell[1])) if door.axis=="x" else Vector2(float(door.cell[0]),float(door.cell[1])+float(door.span)*0.5)
	if door.axis=="x" and outward.y>0: edge.y+=1.0
	elif door.axis=="y" and outward.x>0: edge.x+=1.0
	var ids: Array=members(world,room_id).duplicate()
	if not actor_id in ids: ids.append(actor_id)
	var previous: Rect2
	for id: String in ids:
		var actor: Dictionary=world.facts.actors[id]
		var local: Rect2=space._actor_rect(actor,Vector2.ZERO)
		var center: Vector2=edge+outward*(1.0+(local.size.y if door.axis=="x" else local.size.x)*0.5)
		if previous.has_area():
			center=previous.get_center()+outward*((previous.size.y+local.size.y)*0.5+0.05 if door.axis=="x" else (previous.size.x+local.size.x)*0.5+0.05)
		var anchor: Vector2=center-local.get_center()
		previous=Rect2(anchor+local.position,local.size)
		if id==actor_id:
			var cell: Array=[anchor.x,anchor.y]
			if not actor_id in members(world,room_id) and not space.public_areas.safe_wait(world,id,int(room.floor_id),cell): return {}
			return {"floor_id":int(room.floor_id),"cell":cell}
	return {}

func join(world: WorldState, room_id: String, actor_id: String) -> void:
	var queue: Array=members(world,room_id)
	if not actor_id in queue: queue.append(actor_id)

func turn(world: WorldState, room_id: String, actor_id: String, facility_id: String) -> bool:
	for id: String in members(world,room_id):
		if id==actor_id: return true
		var intent: Dictionary=_intents.get(id,{})
		if intent.get("phase","")=="local_travel" and not str(intent.get("facility_id","")).is_empty() and intent.facility_id!=facility_id: continue
		if space.facility_geometry_quote(world,facility_id,id).ok: return false
	return false

func validate(world: WorldState) -> String:
	if not world.facts.waiting_life.get("toilet_queues",{}) is Dictionary: return "卫生间队列集合无效"
	var seen: Dictionary={}
	for room_id: String in world.facts.waiting_life.get("toilet_queues",{}):
		var queue: Variant=world.facts.waiting_life.toilet_queues[room_id]
		if not queue is Dictionary or not queue.get("actor_ids") is Array: return "卫生间队列顺序无效"
		for id: Variant in queue.actor_ids:
			if not id is String or not world.facts.actors.has(id) or seen.has(id): return "卫生间重复入队或人物缺失"
			seen[id]=true
	return ""
