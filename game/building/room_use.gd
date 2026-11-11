class_name HospitalRoomUse
extends RefCounted

var content: HospitalContent
var _world: WeakRef
var _facts: Dictionary = {}
var _revision: int = -1
var _facilities: Dictionary = {}
var _rooms_by_kind: Dictionary = {}
var _room_cells: Dictionary = {}
var _by_cell: Dictionary = {}
var _plots: Dictionary = {}
var _waiting_cells: Dictionary = {}
var treatment_definitions: Array = []

func _init(database: HospitalContent) -> void:
	content=database
	for routine: Dictionary in content.catalog.treatment_routines:
		if not routine.equipment_id in treatment_definitions: treatment_definitions.append(routine.equipment_id)

func _ensure(world: WorldState) -> void:
	if _world!=null and _world.get_ref()==world and _revision==world.geometry_revision and is_same(_facts,world.facts): return
	_world=weakref(world); _facts=world.facts; _revision=world.geometry_revision
	_facilities.clear(); _rooms_by_kind.clear(); _room_cells.clear(); _by_cell.clear(); _plots.clear(); _waiting_cells.clear()
	for floor_key: String in world.facts.floors.overrides:
		var owned: Dictionary={}
		for plot: Array in HospitalSpace.floor_plots(world,int(floor_key)): owned[Vector2i(int(plot[0]),int(plot[1]))]=true
		_plots[int(floor_key)]=owned
	for id: String in world.ids("rooms"):
		var room: Dictionary=world.facts.rooms[id]
		if room.get("structure_valid",true):
			_rooms_by_kind.get_or_add(str(room.get("kind","")),[]).append(id)
			_room_cells[id]=BuildGeometry.cells(room)
			for cell: Array in _room_cells[id]: _by_cell.get_or_add(int(room.floor_id),{})[Vector2i(int(cell[0]),int(cell[1]))]=id
	for id: String in world.ids("facilities"):
		var facility: Dictionary=world.facts.facilities[id]
		if facility.get("stored",false): continue
		_facilities.get_or_add(str(facility.get("room_id","")),{}).get_or_add(str(facility.definition_id),[]).append(id)

func rooms(world: WorldState, kind: String) -> Array:
	_ensure(world)
	return _rooms_by_kind.get(kind,[])

func standing_cells(world: WorldState, room_id: String) -> Array:
	_ensure(world)
	return _room_cells.get(room_id,[])

func room_at(world: WorldState, floor_id: int, point: Vector2i) -> String:
	_ensure(world)
	return str(_by_cell.get(floor_id,{}).get(point,""))

func public_point(world: WorldState, floor_id: int, point: Vector2i) -> bool:
	_ensure(world)
	if point.x<0 or point.y<0 or point.x>=96 or point.y>=96 or not _plots.get(floor_id,{}).has(Vector2i(point.x/32,point.y/32)): return false
	var room: Dictionary=world.facts.rooms.get(_by_cell.get(floor_id,{}).get(point,""),{})
	return room.is_empty() or room.get("kind","") in ["rest","toilet"]

func waiting_cells(world: WorldState, room_id: String) -> Array:
	_ensure(world)
	if _waiting_cells.has(room_id): return _waiting_cells[room_id]
	var room: Dictionary=world.facts.rooms.get(room_id,{})
	if room.is_empty(): return []
	var found: Dictionary={}
	for door: Dictionary in HospitalSpace.floor_layout(world,int(room.floor_id)).doors:
		if door.get("room_id","")!=room_id: continue
		var horizontal: bool=door.axis=="x"
		var left: int=int(door.cell[0]); var top: int=int(door.cell[1])
		var right: int=left+(int(door.span) if horizontal else 0)
		var bottom: int=top+(0 if horizontal else int(door.span))
		for x: int in range(left-6,right+7):
			for y: int in range(top-6,bottom+7):
				var point:=Vector2i(x,y)
				var dx: int=maxi(0,maxi(left-x,x-right))
				var dy: int=maxi(0,maxi(top-y,y-bottom))
				if dx+dy>6 or _by_cell.get(int(room.floor_id),{}).get(point,"")==room_id or not public_point(world,int(room.floor_id),point): continue
				found[point]=true
	var result: Array=found.keys()
	result.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return a.y<b.y if a.y!=b.y else a.x<b.x)
	_waiting_cells[room_id]=result
	return result

func facilities(world: WorldState, room_id: String, definitions: Array) -> Array:
	_ensure(world)
	var result: Array=[]
	for definition: String in definitions: result.append_array(_facilities.get(room_id,{}).get(definition,[]))
	result.sort()
	return result

func reason(world: WorldState, room_id: String) -> String:
	_ensure(world)
	var room: Dictionary=world.facts.rooms.get(room_id,{})
	if room.is_empty() or not room.get("structure_valid",true): return "缺少合法房间结构"
	if not room.get("open_intent",room.get("open",true)): return "房间已关闭"
	var kind: String=str(room.get("kind",""))
	var required: Array=[]
	match kind:
		"gp": required=["FUR02"]
		"treatment": required=treatment_definitions
		"operating_room": required=["EQ01"]
		"ward": required=["EQ05"]
		"doctor_office": required=["SE05"]
		"research": required=["FUR05"]
		"dormitory": required=["SE04"]
		"toilet": required=["FUR07","AE03"]
		"rest":
			# Tea uses an actual safe standing position without dedicated furniture.
			# Each seated-rest/recreation task still checks its own real equipment.
			return ""
		_: return "空房间尚未选择用途"
	var ids: Array=facilities(world,room_id,required)
	if ids.is_empty(): return "缺少房间用途所需设施"
	if kind=="operating_room" and ids.size()!=1: return "手术室只能有一张手术台"
	return ""

func facility_reason(world: WorldState, facility: Dictionary) -> String:
	var room_id: String=str(facility.get("room_id",""))
	var blocked: String=reason(world,room_id)
	if not blocked.is_empty(): return blocked
	var kind: String=str(world.facts.rooms[room_id].kind)
	var definition: String=str(facility.definition_id)
	if definition=="FUR02": return "诊断桌不适合当前房间用途" if not kind in ["gp","treatment"] else ""
	if definition in treatment_definitions: return "治疗设备不适合当前房间用途" if not kind in ["gp","treatment"] else ""
	var usages: Dictionary={"EQ01":"operating_room","EQ05":"ward","SE05":"doctor_office","FUR05":"research","SE04":"dormitory","FUR07":"toilet","AE03":"toilet"}
	if usages.has(definition) and kind!=usages[definition]: return "设施不适合当前房间用途"
	return ""
