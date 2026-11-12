class_name WorldState
extends RefCounted

const TICK_SECONDS: float = 0.1
const TICKS_PER_DAY: int = 18000
const CLOCK_VERSION: String = "hospital-time-v1"

var facts: Dictionary:
	set(value):
		facts = value
		_facility_definitions.clear()
		_facility_count = -1
		_ordered_ids.clear()
		_active_visits.clear()
		_active_visit_count = -1
		_active_visit_order.clear()
		_active_visit_order_dirty = true
		_layout_projection.clear()
		_pending_ledger = null
		_ledger_owners.clear()
		_pending_sources.clear()
		_operation_sets.clear()
		_remodel_members = null
		_remodel_records = {}
		_remodel_count = -1
		_ledger_entries = {}
		_ledger_entry_count = -1
		invalidate_geometry()

# Rebuildable observation identities; none of these values enter freeze().
var geometry_revision: int = 0
var _facility_definitions: Dictionary = {}
var _facility_count: int = -1
var _ordered_ids: Dictionary = {}
var _active_visits: Dictionary = {}
var _active_visit_count: int = -1
var _active_visit_order: Array = []
var _active_visit_order_dirty: bool = true
var _layout_projection: Dictionary = {}
var _layout_revision: int = -1
var _pending_ledger: Variant = null
var _ledger_entries: Dictionary = {}
var _ledger_entry_count: int = -1
var _settled_ledger_amount: int = 0
var _pending_ledger_debits: int = 0
var _ledger_owners: Dictionary = {}
var _pending_sources: Dictionary = {}
var _operation_sets: Dictionary = {}
var _remodel_members: Variant = null
var _remodel_records: Dictionary = {}
var _remodel_count: int = -1

func _ensure_ledger_index() -> void:
	if _pending_ledger!=null and is_same(_ledger_entries,facts.ledger.entries) and _ledger_entry_count==facts.ledger.entries.size(): return
	# Ledger owns posting/settlement. Restored or replaced facts rebuild these
	# derived totals together with the existing pending set; freeze keeps facts only.
	_pending_ledger = {}
	_ledger_entries = facts.ledger.entries
	_ledger_entry_count = _ledger_entries.size()
	_settled_ledger_amount = 0
	_pending_ledger_debits = 0
	_ledger_owners.clear()
	for id: String in _ledger_entries:
		var entry: Dictionary = _ledger_entries[id]
		_index_ledger_owner(id,entry)
		if entry.settled:
			_settled_ledger_amount += int(entry.amount)
		else:
			_pending_ledger[id] = true
			_pending_ledger_debits += mini(0,int(entry.amount))

func ledger_balance() -> int:
	_ensure_ledger_index()
	return int(facts.ledger.opening_balance)+_settled_ledger_amount

func available_ledger_balance() -> int:
	_ensure_ledger_index()
	return int(facts.ledger.opening_balance)+_settled_ledger_amount+_pending_ledger_debits

func pending_ledger_ids() -> Array:
	_ensure_ledger_index()
	var result: Array = _pending_ledger.keys()
	result.sort()
	return result

func ledger_posted(id: String) -> void:
	if _pending_ledger==null: return
	if not is_same(_ledger_entries,facts.ledger.entries) or _ledger_entry_count+1!=facts.ledger.entries.size():
		_ensure_ledger_index()
		return
	_ledger_entry_count += 1
	var entry: Dictionary = facts.ledger.entries[id]
	_index_ledger_owner(id,entry)
	if entry.settled:
		_settled_ledger_amount += int(entry.amount)
	else:
		_pending_ledger[id] = true
		_pending_ledger_debits += mini(0,int(entry.amount))

func ledger_settled(id: String) -> void:
	if _pending_ledger!=null and _pending_ledger.has(id):
		var amount: int = int(facts.ledger.entries[id].amount)
		_settled_ledger_amount += amount
		_pending_ledger_debits -= mini(0,amount)
		_pending_ledger.erase(id)

func _index_ledger_owner(id: String, entry: Dictionary) -> void:
	if not _ledger_owners.has(entry.owner_id): _ledger_owners[entry.owner_id] = []
	_ledger_owners[entry.owner_id].append(id)

func ledger_owner_ids(owners: Array) -> Array:
	_ensure_ledger_index()
	var selected: Dictionary = {}
	for owner: String in owners:
		for id: String in _ledger_owners.get(owner,[]): selected[id] = true
	var result: Array = selected.keys()
	result.sort()
	return result

# Each observer owns its cursor; authoritative records and consumed identities
# remain in facts. Owner notifications also support a legal same-ID rewrite.
func _prune_fact_observers() -> void:
	for key: String in _pending_sources.keys():
		var state: Dictionary = _pending_sources[key]
		if state.has("owner") and state.owner.get_ref()==null: _pending_sources.erase(key)

func pending_fact_ids(observer: String, source: String, records: Dictionary, owner: Object = null) -> Array:
	_prune_fact_observers()
	var key: String = observer+":"+source
	var state: Dictionary = _pending_sources.get(key,{})
	if state.is_empty() or not is_same(state.records,records) or int(state.count)!=records.size():
		state = {"source":source,"records":records,"count":records.size(),"pending":{}}
		if owner!=null: state.owner = weakref(owner)
		for id: String in records: state.pending[id] = true
		_pending_sources[key] = state
	var result: Array = state.pending.keys()
	state.pending = {}
	return result

func fact_record_changed(source: String, id: String) -> void:
	_prune_fact_observers()
	for state: Dictionary in _pending_sources.values():
		if state.source!=source: continue
		var count: int = state.records.size()
		if count!=int(state.count) and count!=int(state.count)+1:
			state.count = -1
			continue
		state.count = count
		state.pending[id] = true

func completion_receipt_ids(source: String, observer: String = "staff_jobs") -> Array:
	return pending_fact_ids(observer,source+".receipts",facts.get(source,{}).get("receipts",{}))

func completion_receipt_added(source: String, id: String) -> void:
	fact_record_changed(source+".receipts",id)

# Only terminal history is omitted. Inventory/paused tasks remain eligible to
# resume. Owners invalidate on commands which can revive or replace a record.
func active_operation_ids(domain: String, collection: String, terminal: Array, ordered: bool = false, field: String = "phase") -> Array:
	var records: Dictionary = facts.get(domain,{}) if collection.is_empty() else facts.get(domain,{}).get(collection,{})
	var key: String = domain+":"+collection+":"+field+":"+JSON.stringify(terminal)
	var state: Dictionary = _operation_sets.get(key,{})
	if state.is_empty() or not is_same(state.records,records) or int(state.count)!=records.size():
		var active: Array = []
		for id: String in records:
			if not records[id].get(field,"") in terminal: active.append(id)
		state = {"records":records,"count":records.size(),"ids":active}
		_operation_sets[key] = state
	var result: Array = []
	for id: String in state.ids:
		if records.has(id) and not records[id].get(field,"") in terminal: result.append(id)
	state.ids = result
	if ordered:
		result = result.duplicate()
		result.sort()
		return result
	return result.duplicate()

func operation_records_changed(domain: String, collection: String = "") -> void:
	for key: String in _operation_sets.keys():
		if key.begins_with(domain+":"+collection+":"): _operation_sets.erase(key)
	if domain=="remodels": _remodel_members = null

func remodel_blocked(id: String) -> bool:
	var records: Dictionary = facts.get("remodels",{})
	if _remodel_members==null or not is_same(_remodel_records,records) or _remodel_count!=records.size():
		_remodel_members = {}
		_remodel_records = records
		_remodel_count = records.size()
		for order_id: String in active_operation_ids("remodels","",["applied","cancelled"],false,"state"):
			var order: Dictionary = facts.remodels[order_id]
			if order.state!="preparing": continue
			for member: String in order.member_ids: _remodel_members[member] = true
			for member: String in order.room_ids: _remodel_members[member] = true
	return _remodel_members.has(id)

var hospital_id: String:
	get:
		return facts.hospital_id
var sim_tick: int:
	get:
		return facts.sim_tick
var revision: int:
	get:
		return facts.world_revision

func _init(dto: Dictionary) -> void:
	facts = dto

func new_id(prefix: String) -> String:
	facts.entity_next += 1
	return "%s_%08d" % [prefix, int(facts.entity_next)]

func touch(geometry_changed: bool = true) -> void:
	facts.world_revision += 1
	if geometry_changed: invalidate_geometry()

func invalidate_geometry() -> void:
	geometry_revision += 1
	_facility_count = -1

func facility_ids(definition_id: String) -> Array:
	if _facility_count!=facts.facilities.size():
		_facility_definitions.clear()
		for id: String in ids("facilities"):
			var definition: String = str(facts.facilities[id].definition_id)
			if not _facility_definitions.has(definition): _facility_definitions[definition] = []
			_facility_definitions[definition].append(id)
		_facility_count = facts.facilities.size()
	return _facility_definitions.get(definition_id,[])

func freeze() -> Dictionary:
	return facts.duplicate(true)

func ids(collection: String) -> Array:
	var keys: Array = facts[collection].keys()
	var cached: Dictionary = _ordered_ids.get(collection,{})
	# Direct writes still exist in legacy owners. Compare membership rather
	# than trusting count/revision (a remove+add may keep both unchanged).
	if cached.is_empty() or cached.members!=keys:
		var ordered: Array = keys.duplicate()
		ordered.sort()
		cached = {"members":keys,"ordered":ordered}
		_ordered_ids[collection] = cached
	return cached.ordered.duplicate()

func register_visit(id: String) -> void:
	if _active_visit_count<0: return
	if not _active_visits.has(id): _active_visit_order_dirty = true
	_active_visits[id] = true
	_active_visit_count = facts.visits.size()
	_ordered_ids.erase("visits")

func active_visit_ids(ordered: bool = true) -> Array:
	if _active_visit_count!=facts.visits.size():
		_active_visits.clear()
		for id: String in facts.visits:
			var visit: Dictionary = facts.visits[id]
			if visit.phase!="departed" or not visit.get("departure_recorded",false): _active_visits[id] = true
		_active_visit_count = facts.visits.size()
		_active_visit_order_dirty = true
	if not ordered: return _active_visits.keys()
	if _active_visit_order_dirty:
		_active_visit_order = _active_visits.keys()
		_active_visit_order.sort()
		_active_visit_order_dirty = false
	# Callers own their result; a local sort/pop cannot edit the shared index.
	return _active_visit_order.duplicate()

func finish_visits() -> void:
	# All clinical, department and resident settlements have consumed departure
	# before this complete-step boundary. History itself remains untouched.
	for id: String in _active_visits.keys():
		if not facts.visits.has(id) or facts.visits[id].phase=="departed" and facts.visits[id].get("departure_recorded",false):
			_active_visits.erase(id)
			_active_visit_order_dirty = true

func capacity_layout() -> Dictionary:
	# Layout writes commit through facts replacement or geometry invalidation.
	# Values here are owned immutable input, never aliases of player facts.
	if _layout_projection.is_empty() or _layout_revision!=geometry_revision:
		_layout_projection = {}
		for field: String in ["rooms","floors","entry"]:
			if facts.has(field): _layout_projection[field] = facts[field].duplicate(true)
		_layout_revision = geometry_revision
	return _layout_projection

func draw(stream: String, modulus: int) -> int:
	var record: Dictionary = facts.rng[stream]
	var generator: RandomNumberGenerator = RandomNumberGenerator.new()
	generator.seed = str(record.seed_decimal).to_int()
	generator.state = str(record.state_decimal).to_int()
	var value: int = generator.randi_range(0,modulus-1)
	record.state_decimal = str(generator.state)
	return value

func clock_text() -> String:
	var tick: int = int(facts.sim_tick)
	var minute: int = (tick % TICKS_PER_DAY) * 1440 / TICKS_PER_DAY
	return "第%d日 · %02d:%02d" % [tick / TICKS_PER_DAY + 1, minute / 60, minute % 60]

func present_actor_count() -> int:
	var count: int = 0
	for actor: Dictionary in facts.actors.values():
		if actor.location.kind != "outside":
			count += 1
	return count

# Entry is a persisted location, never a request to relocate people. Legacy
# worlds without it retain the first-floor default until the app upgrades them.
# Validate explicit locations before admission and when restoring snapshots.
func entry_validation_error() -> String:
	if not facts.has("entry") and facts.get("gameplay_version",0)==0:
		return ""
	var entry: Variant = facts.get("entry")
	if not entry is Dictionary:
		return "医院入口结构无效"
	if not _natural(entry.get("floor_id",-1)) or int(entry.floor_id)!=1:
		return "医院入口只能位于一楼"
	if not _grid_point(entry.get("cell")) or (entry.has("exit_cell") and not _grid_point(entry.exit_cell)):
		return "医院入口坐标无效"
	return ""

func validate(content: HospitalContent) -> String:
	var required: Array = ["schema_version","hospital_id", "display_name", "mode", "sim_tick", "world_revision",
		"clock_version", "entity_next", "actors", "staff", "visits", "tickets", "sessions",
		"attempts", "preparations", "ward_stays", "facilities", "floors", "connectors", "moves",
		"ledger", "inventory", "rng", "research", "command_receipts","rooms","adaptations"]
	for field: String in required:
		if not facts.has(field):
			return "快照缺少字段：" + field
	var entry_error: String = entry_validation_error()
	if not entry_error.is_empty():
		return entry_error
	for field: String in ["actors","staff","visits","tickets","sessions","attempts","preparations","ward_stays","facilities","floors","connectors","moves","ledger","inventory","rng","command_receipts","rooms","adaptations"]:
		if not facts.get(field) is Dictionary:
			return "快照字段类型无效："+field
	for collection: String in ["actors","staff","visits","tickets","sessions","attempts","preparations","ward_stays","facilities","connectors","moves","rooms","adaptations"]:
		for id: Variant in facts[collection]:
			if not id is String or not facts[collection][id] is Dictionary:
				return "实体记录类型无效："+collection
	var shape_error: String = _validate_shapes()
	if not shape_error.is_empty():
		return shape_error
	for staff: Dictionary in facts.staff.values():
		if staff.has("clinical_release"):
			var release: Variant = staff.clinical_release
			if not release is Dictionary or not release.get("facility_id") is String or not release.get("visit_id") is String or not release.get("reason") is String or not release.get("phase") in ["seek","walking","blocked"] or not facts.facilities.has(release.facility_id) or not facts.visits.has(release.visit_id):
				return "临床安全离位义务无效"
	if facts.has("visitors"):
		if not facts.visitors is Dictionary:
			return "经营状态结构无效：visitors"
		if not facts.visitors.get("requests") is Dictionary:
			return "经营状态集合无效：visitors.requests"
		if not facts.visitors.get("stays") is Dictionary:
			return "经营状态集合无效：visitors.stays"
	if facts.has("training_jobs"):
		if not facts.training_jobs is Dictionary:
			return "经营状态结构无效：training_jobs"
	if facts.has("research_progress") or facts.has("research_jobs"):
		if not facts.get("research_progress") is Dictionary or not facts.get("research_jobs") is Dictionary:
			return "研究进度或任务结构无效"
	if facts.has("staff_schedule"):
		if not facts.staff_schedule is Dictionary:
			return "经营状态结构无效：staff_schedule"
		if not facts.staff_schedule.get("handoffs") is Dictionary:
			return "经营状态集合无效：staff_schedule.handoffs"
		if not facts.staff_schedule.get("applications") is Dictionary:
			return "经营状态集合无效：staff_schedule.applications"
	if facts.has("staff_life"):
		if not facts.staff_life is Dictionary:
			return "经营状态结构无效：staff_life"
		if not facts.staff_life.get("reservations") is Dictionary:
			return "经营状态集合无效：staff_life.reservations"
		if not facts.staff_life.get("settings") is Dictionary:
			return "经营状态集合无效：staff_life.settings"
		if not facts.staff_life.get("pressure_receipts") is Dictionary:
			return "经营状态集合无效：staff_life.pressure_receipts"
	if facts.has("waiting_life"):
		if not facts.waiting_life is Dictionary:
			return "经营状态结构无效：waiting_life"
		if not facts.waiting_life.get("seats") is Dictionary:
			return "经营状态集合无效：waiting_life.seats"
		if not facts.waiting_life.get("needs") is Dictionary:
			return "经营状态集合无效：waiting_life.needs"
		if not facts.waiting_life.get("clocks") is Dictionary:
			return "经营状态集合无效：waiting_life.clocks"
	if facts.has("environment"):
		if not facts.environment is Dictionary:
			return "经营状态结构无效：environment"
		if not facts.environment.get("dirt") is Dictionary:
			return "经营状态集合无效：environment.dirt"
		if not facts.environment.get("orders") is Dictionary:
			return "经营状态集合无效：environment.orders"
		if not facts.environment.get("surfaces") is Dictionary:
			return "经营状态集合无效：environment.surfaces"
		if not facts.environment.get("receipts") is Dictionary:
			return "经营状态集合无效：environment.receipts"
	if facts.has("maintenance"):
		if not facts.maintenance is Dictionary:
			return "经营状态结构无效：maintenance"
		if not facts.maintenance.get("jobs") is Dictionary:
			return "经营状态集合无效：maintenance.jobs"
		if not facts.maintenance.get("upgrades") is Dictionary:
			return "经营状态集合无效：maintenance.upgrades"
		if not facts.maintenance.get("receipts") is Dictionary:
			return "经营状态集合无效：maintenance.receipts"
	if facts.has("patient_experience"):
		if not facts.patient_experience is Dictionary:
			return "经营状态结构无效：patient_experience"
		if not facts.patient_experience.get("experience") is Dictionary:
			return "经营状态集合无效：patient_experience.experience"
	if facts.has("economy"):
		if not facts.economy is Dictionary:
			return "经营状态结构无效：economy"
		if not facts.economy.get("daily_accumulators") is Dictionary:
			return "经营状态集合无效：economy.daily_accumulators"
	if facts.has("recruitment"):
		if not facts.recruitment is Dictionary:
			return "经营状态结构无效：recruitment"
		if not facts.recruitment.get("standard_ordinals") is Dictionary:
			return "经营状态集合无效：recruitment.standard_ordinals"
		if not facts.recruitment.get("candidates") is Dictionary:
			return "经营状态集合无效：recruitment.candidates"
		if not facts.recruitment.get("active_search") is Dictionary:
			return "经营状态集合无效：recruitment.active_search"
		if not facts.recruitment.get("searches") is Dictionary:
			return "经营状态集合无效：recruitment.searches"
	if facts.has("arrivals"):
		if not facts.arrivals is Dictionary:
			return "经营状态结构无效：arrivals"
		if not facts.arrivals.get("plan") is Dictionary:
			return "经营状态集合无效：arrivals.plan"
		if not facts.arrivals.get("daily_stats") is Dictionary:
			return "经营状态集合无效：arrivals.daily_stats"
	if facts.inventory.has("orders") and not facts.inventory.orders is Dictionary:
		return "采购凭据集合无效"
	for staff: Dictionary in facts.staff.values():
		if staff.has("life_task") and not staff.life_task is Dictionary:
			return "员工生活任务结构无效"
	var geometry: HospitalSpace = HospitalSpace.new(content)
	if not facts.research is Array or not facts.ledger.get("entries") is Dictionary or not _natural(facts.ledger.get("opening_balance",-1)):
		return "研究或账目结构无效"
	var unit_owners: Dictionary = {}
	for order: Variant in facts.get("environment",{}).get("orders",{}).values():
		if not order is Dictionary: continue
		var units: Variant = order.get("units",[])
		if not units is Array: continue
		for unit: Variant in units:
			if unit is Dictionary and unit.get("id") is String: unit_owners[unit.id] = true
	for entry_key: String in facts.ledger.entries:
		var entry: Variant = facts.ledger.entries[entry_key]
		if not entry is Dictionary or not _fields(entry,{"owner_id":TYPE_STRING,"component":TYPE_STRING,"amount":TYPE_INT,"tick":TYPE_INT,"settled":TYPE_BOOL}).is_empty() or not _natural(entry.tick) or not is_finite(float(entry.amount)) or abs(int(entry.amount))>1000000000000:
			return "账目金额无效"
		if entry_key!=entry.owner_id+":"+entry.component or not _ledger_owner_exists(entry.owner_id,unit_owners):
			return "账目凭据所有者或组件身份无效"
	for actor: Dictionary in facts.actors.values():
		var reason: String = _fields(actor,{"id":TYPE_STRING,"name":TYPE_STRING,"species_id":TYPE_STRING,"location":TYPE_DICTIONARY,"facing":TYPE_FLOAT})
		if not reason.is_empty():
			return "身体"+reason
		if not actor.location.get("kind") is String:
			return "身体位置结构无效"
		if actor.location.kind=="floor":
			if not _natural(actor.location.get("floor_id",-1)) or not _point(actor.location.get("cell")):
				return "地面坐标无效"
		if actor.has("support_facility_id") and not facts.facilities.has(actor.support_facility_id):
			return "身体承托引用无效"
	for visit: Dictionary in facts.visits.values():
		var reason: String = _fields(visit,{"id":TYPE_STRING,"actor_id":TYPE_STRING,"disease_id":TYPE_STRING,"binding_id":TYPE_STRING,"phase":TYPE_STRING,"diagnosis":TYPE_DICTIONARY,"attempt_ids":TYPE_ARRAY,"plan_decision":TYPE_DICTIONARY,"complex":TYPE_BOOL})
		if not reason.is_empty():
			return "就诊"+reason
	for session: Dictionary in facts.sessions.values():
		var reason: String = _fields(session,{"id":TYPE_STRING,"visit_id":TYPE_STRING,"kind":TYPE_STRING,"facility_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"resources":TYPE_ARRAY,"remaining_ticks":TYPE_INT})
		if not reason.is_empty() or not facts.facilities.has(session.get("facility_id","")):
			return "执行会话结构或设施引用无效"
	for facility: Dictionary in facts.facilities.values():
		if not facility.get("definition_id") is String or not _point(facility.get("cell")) or not _point(facility.get("footprint")):
			return "设施结构无效"
		var definition_id: String = facility.definition_id
		if content.facility_definition(definition_id).is_empty():
			return "缺少核心设施定义："+definition_id
	if facts.schema_version!=1 or facts.clock_version != CLOCK_VERSION or not _natural(facts.sim_tick) or not _natural(facts.world_revision):
		return "医院时钟或版本无效"
	for command_id: Variant in facts.command_receipts:
		var receipt: Variant = facts.command_receipts[command_id]
		if not command_id is String or str(command_id).is_empty() or not receipt is Dictionary or not _fields(receipt,{"accepted":TYPE_BOOL,"reason":TYPE_STRING,"tick":TYPE_INT}).is_empty() or not _natural(receipt.tick):
			return "命令回执身份或结构无效"
		if receipt.has("new_revision") and (not _natural(receipt.new_revision) or int(receipt.new_revision)>revision):
			return "命令回执修订号无效"
		if receipt.has("code") and not receipt.code is String:
			return "命令回执结果类型无效"
		if receipt.has("changed_ids"):
			if not receipt.changed_ids is Array:
				return "命令回执对象集合无效"
			for changed_id: Variant in receipt.changed_ids:
				if not changed_id is String:
					return "命令回执对象身份无效"
		if receipt.has("command") and (not receipt.command is Dictionary or receipt.command.get("hospital_id")!=hospital_id):
			return "命令回执属于另一座医院"
	if HospitalLedger.balance(self) < 0 or not _natural(facts.inventory.units):
		return "资金或治疗包无效"
	for stream: String in facts.rng:
		var record: Variant = facts.rng[stream]
		if not record is Dictionary or not _signed_decimal(record.get("state_decimal")) or not _signed_decimal(record.get("seed_decimal")) or record.get("algorithm","")!="godot-pcg32-4.7.2":
			return "随机流无效：" + stream
	for stream: String in ["arrival","treatment","incident","personality","equipment","task_board","guidance","communication","gratitude","patience","recruitment","community_activity","registration"]:
		if not facts.rng.has(stream):
			return "必要随机流缺失："+stream
	for id: String in facts.actors:
		var actor: Dictionary = facts.actors[id]
		if actor.id != id or content.definition("species", actor.species_id).is_empty():
			return "未知居民或身份错误：" + id
		if not actor.location.kind in ["floor", "transit", "outside"]:
			return "居民位置类型无效：" + id
		if actor.location.kind == "floor" and (not actor.location.has("floor_id") or not actor.location.has("cell")):
			return "居民地面位置无效：" + id
		if actor.location.kind == "transit" and not facts.connectors.has(actor.location.connector_id):
			return "乘梯连接缺失：" + id
	for id: String in facts.staff:
		if not facts.actors.has(id):
			return "员工身体缺失：" + id
		var staff: Dictionary = facts.staff[id]
		if content.definition("staff_role_profiles","ROLE_"+str(staff.role).to_upper()).is_empty() or (staff.role=="doctor" and content.definition("doctor_titles",staff.title_id).is_empty()):
			return "员工角色或职称定义无效："+id
	var visited_actors: Dictionary = {}
	for id: String in facts.visits:
		var visit: Dictionary = facts.visits[id]
		if not facts.actors.has(visit.actor_id) or content.definition("diseases", visit.disease_id).is_empty():
			return "就诊引用无效：" + id
		if facts.actors[visit.actor_id].get("service_role","")=="mechanic":
			return "患者不能同时充当上门维修人员"
		if visited_actors.has(visit.actor_id):
			return "同一患者存在重复当前就诊"
		visited_actors[visit.actor_id] = true
		if visit.attempt_ids.size() > int(content.balance.max_treatment_attempts):
			return "治疗次数超过上限：" + id
		var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
		if binding.is_empty() or binding.disease_id!=visit.disease_id or binding.species_id!=facts.actors[visit.actor_id].species_id:
			return "病例身体绑定无效："+id
		if content.definition("patient_personalities",visit.personality_id).is_empty() or content.definition("treatment_plans",visit.requested_plan_id).is_empty():
			return "病例性格或指定方案引用无效"
		if not visit.plan_decision.is_empty() and (not visit.plan_decision.get("plan_id") is String or content.definition("treatment_plans",visit.plan_decision.plan_id).is_empty()):
			return "已会诊的方案引用无效"
		for attempt_id: String in visit.attempt_ids:
			if not facts.attempts.has(attempt_id) or facts.attempts[attempt_id].visit_id != id:
				return "治疗尝试引用无效：" + id
	var guidance_error: String = HospitalFloorGuidance.validate_state(self)
	if not guidance_error.is_empty(): return guidance_error
	var locks: Dictionary = {}
	for id: String in facts.sessions:
		var session: Dictionary = facts.sessions[id]
		if not facts.visits.has(session.visit_id) or not _natural(session.remaining_ticks):
			return "执行会话无效：" + id
		for resource_id: String in session.resources:
			if locks.has(resource_id):
				return "资源重复占用：" + resource_id
			locks[resource_id] = id
		for staff_id: String in session.staff_ids:
			if not facts.staff.has(staff_id):
				return "执行职员引用无效：" + id
	for id: String in facts.attempts:
		var attempt: Dictionary = facts.attempts[id]
		if not facts.visits.has(attempt.visit_id) or content.definition("treatment_plans", attempt.plan_id).is_empty():
			return "尝试内容引用无效：" + id
		if not attempt.result is bool or not _natural(attempt.work_ticks) or not facts.inventory.issues.has(id):
			return "尝试承诺或领包凭据缺失：" + id
		if int(facts.inventory.issues[id].units)!=int(attempt.supply_units) or int(attempt.probability_bp)<0 or int(attempt.probability_bp)>10000:
			return "尝试领包数量或概率无效"
		if attempt.has("ward_fee") and not _natural(attempt.ward_fee):
			return "尝试床位费用快照无效"
		for staff_id: String in attempt.staff_ids:
			if not facts.staff.has(staff_id):
				return "尝试人员引用缺失"
	var occupied_beds: Dictionary = {}
	for id: String in facts.ward_stays:
		var stay: Dictionary = facts.ward_stays[id]
		if not facts.visits.has(stay.get("visit_id","")) or (not stay.attempt_id.is_empty() and (not facts.attempts.has(stay.attempt_id) or facts.attempts[stay.attempt_id].visit_id!=stay.visit_id)) or not facts.facilities.has(stay.bed_id):
			return "住院引用无效：" + id
		if occupied_beds.has(stay.bed_id):
			return "床位重复占用：" + stay.bed_id
		occupied_beds[stay.bed_id] = id
	for id: String in facts.tickets:
		var ticket: Dictionary = facts.tickets[id]
		if not facts.visits.has(ticket.visit_id) or facts.visits[ticket.visit_id].ticket_id!=id:
			return "号签与当前就诊不一致："+id
	for id: String in facts.preparations:
		var preparation: Dictionary = facts.preparations[id]
		var kind: String = str(preparation.get("kind","surgery"))
		if not facts.visits.has(preparation.visit_id) or not facts.facilities.has(preparation.facility_id) or not kind in ["surgery","outpatient","gp","spectrum","resonance","consult"] or facts.visits[preparation.visit_id].phase!="wait_"+kind:
			return "临床准备的原票号或服务位不一致："+id
		if kind=="surgery" and preparation.bed_id.is_empty():
			return "手术准备缺少兼容床位承诺："+id
		if not preparation.bed_id.is_empty():
			if not facts.facilities.has(preparation.bed_id) or occupied_beds.has(preparation.bed_id) and facts.ward_stays.get(str(occupied_beds[preparation.bed_id]),{}).get("visit_id","")!=preparation.visit_id:
				return "临床准备的床位预留不一致："+id
			occupied_beds[preparation.bed_id] = id
		for staff_id: String in preparation.staff_ids:
			if not facts.staff.has(staff_id) or locks.has(staff_id):
				return "准备人员不存在或被重复占用："+staff_id
			locks[staff_id] = id
	var moving_members: Dictionary = {}
	for id: String in facts.moves:
		var movement: Dictionary = facts.moves[id]
		if not facts.actors.has(id) or movement.actor_id!=id:
			return "移动角色引用无效："+id
		var leader: Dictionary = facts.actors[id]
		if leader.location.kind=="outside":
			return "院外身体不能保留院内移动"
		for member_id: Variant in movement.get("members",[id]):
			if not member_id is String or not facts.actors.has(member_id) or moving_members.has(member_id):
				return "移动组身体不存在或重复参与"
			moving_members[member_id] = id
			if movement.has("members"):
				var member: Dictionary = facts.actors[member_id]
				if member.location.kind!=leader.location.kind:
					return "完整移动组处于不同位置阶段"
				if leader.location.kind=="transit" and member.location.connector_id!=leader.location.connector_id:
					return "完整移动组不在同一真实连接中"
		if movement.has("convoy"):
			var convoy_error: String = ConvoyTrail.validate(geometry,self,movement)
			if not convoy_error.is_empty(): return convoy_error
		var prefix_waypoint: Dictionary=movement.get("route_waypoint",{})
		if prefix_waypoint.has("prefix"):
			if not HospitalTransit._release_prefix_shape(ConvoyTrail.point(prefix_waypoint.binding.origin),prefix_waypoint.prefix,float(geometry.clearance(leader))): return "有限让位前缀局部长度或转角无效"
		var segments: Array = movement.path+movement.get("route_waypoint",{}).get("continuation",[])+movement.get("detour",{}).get("original_path",[])+movement.get("detour",{}).get("backtrack",[])
		if movement.has("local_move"): segments.append(movement.local_move.target)
		for segment: Dictionary in segments:
			if segment.kind=="connector" and not facts.connectors.has(segment.connector_id):
				return "移动使用的竖向连接不存在"
	for id: String in facts.connectors:
		var connector: Dictionary = facts.connectors[id]
		var definition: Dictionary = content.definition("vertical_connectors",connector.definition_id)
		if definition.is_empty():
			return "竖向连接定义不存在："+id
		var footprint: Array = definition.footprint.duplicate()
		if int(connector.get("rotation",0))%2==1: footprint.reverse()
		if int(connector.footprint[0])!=int(footprint[0]) or int(connector.footprint[1])!=int(footprint[1]) or connector.riders.size()>int(definition.max_group_size):
			return "竖向结构占地或乘员数量与源定义不符"
		var ends: Array = HospitalTransit.endpoints(connector)
		if definition.kind=="stairs" and (ends.size()!=2 or absi(int(ends[1])-int(ends[0]))!=1):
			return "楼梯只能连接相邻两个楼层"
		for stop: Variant in ends:
			for x: int in range(int(connector.cell[0]),int(connector.cell[0])+int(connector.footprint[0])):
				for y: int in range(int(connector.cell[1]),int(connector.cell[1])+int(connector.footprint[1])):
					if not geometry.owned(self,int(stop),Vector2i(x,y)):
						return "竖向结构超出实际取得地块"
		for actor_id: Variant in connector.riders:
			if not actor_id is String or not facts.actors.has(actor_id):
				return "竖向乘员不存在"
			var location: Dictionary = facts.actors[actor_id].location
			if location.kind!="transit" or location.connector_id!=id or connector.phase in ["idle","empty_riding"]:
				return "乘员与轿厢状态不一致"
		if not connector.riders.is_empty():
			var primary: String = connector.get("primary_actor_id",connector.riders[0])
			if not primary in connector.riders or not facts.moves.has(primary) or facts.moves[primary].get("members",[primary])!=connector.riders:
				return "真实通行组没有一致的移动拥有者"
	for id: String in facts.actors:
		var actor: Dictionary = facts.actors[id]
		if actor.location.kind=="transit" and not id in facts.connectors[actor.location.connector_id].riders:
			return "乘梯身体没有实际乘员身份"
		if actor.location.kind=="floor" and HospitalSpace.floor_plots(self,int(actor.location.floor_id)).is_empty():
			return "身体所在楼层没有实际可用地面"
		if actor.location.kind=="floor" and not geometry.owned(self,int(actor.location.floor_id),Vector2i(floori(actor.location.cell[0]),floori(actor.location.cell[1]))):
			return "身体位置不属于实际医院地块"
		if actor.has("body_binding_id") and content.definition("treatment_bindings",actor.body_binding_id).is_empty():
			return "身体引用缺少核心病例适配"
	var doors: Dictionary = {}
	for floor_key: String in facts.floors.overrides:
		for door: Dictionary in facts.floors.overrides[floor_key].doors:
			if content.definition("doors",door.definition_id).is_empty() or doors.has(door.id) or facts.facilities.has(door.id) or not str(door.room_id).is_empty() and (not facts.rooms.has(door.room_id) or int(facts.rooms[door.room_id].floor_id)!=int(floor_key)):
				return "门的定义、原墙楼层或唯一身份无效"
			doors[door.id] = door
	for id: String in facts.adaptations:
		var reservation: Dictionary = facts.adaptations[id]
		if not facts.actors.has(reservation.actor_id):
			return "展开预约身体不存在"
		if reservation.kind=="facility" and (not facts.facilities.has(reservation.facility_id) or not _reservation_owner_exists(reservation.owner_id) and not HospitalFloorGuidance.owns_reservation(self,reservation)):
			return "设施展开预约的所有者或主体不存在"
		if reservation.kind=="door":
			if not doors.has(id) or reservation.owner_id!=reservation.actor_id:
				return "门展开的实际墙段或所有者缺失"
			# Owner identity is already explicit. Historical staff lists may
			# omit that repeated identity or repeat another authorized body.
			var participants: Dictionary = {reservation.actor_id:true}
			for participant_id: Variant in reservation.staff_ids:
				if not participant_id is String or not facts.actors.has(participant_id): return "门展开参与身体不存在"
				participants[participant_id] = true
			var physical: Rect2 = geometry._door_rect(doors[id],int(reservation.span))
			var expected_region: Array = [physical.position.x,physical.position.y,physical.size.x,physical.size.y]
			if reservation.regions.size()!=1: return "门展开区域与实际墙段不一致"
			for axis: int in 4:
				# Numeric storage types do not change the exact physical region.
				if float(reservation.regions[0][axis])!=float(expected_region[axis]): return "门展开区域与实际墙段不一致"
			var subject: Dictionary = facts.actors[reservation.actor_id]
			if reservation.has("convoy_envelope"):
				var envelope: Dictionary = reservation.convoy_envelope
				for participant_id: String in participants:
					var dimensions: Dictionary = geometry.body(facts.actors[participant_id])
					if ceili(Vector2(float(dimensions.width_m),float(dimensions.depth_m)).length()/HospitalSpace.CELL_METERS)>int(envelope.size) or float(dimensions.height_m)>float(envelope.height): return "门展开队列包络不能容纳原参与身体"
				# A door retains the original queue envelope until its physical
				# reservation is released, even after the queue dissolves.
				subject = subject.duplicate(true)
				subject._convoy_size = int(envelope.size)
				subject._convoy_body = {"width_m":float(envelope.size)*HospitalSpace.CELL_METERS,"depth_m":float(envelope.size)*HospitalSpace.CELL_METERS,"height_m":float(envelope.height)}
			var quote: Dictionary = geometry.door_quote(self,subject,int(reservation.floor_id),doors[id])
			if not quote.ok or int(reservation.span)!=int(quote.span) or absf(float(reservation.clear_height_m)-float(quote.clear_height_m))>0.000001 or absf(float(reservation.clear_width_m)-float(quote.clear_width_m))>0.000001:
				return "门展开与真实身体、净高或连续墙段不一致"
		for staff_id: Variant in reservation.staff_ids:
			if not staff_id is String or not facts.actors.has(staff_id):
				return "展开岗位身体不存在"
	# All movement, connector and reservation shapes are established above.
	# Restore must re-establish the protected trail before leader-only steps
	# can rely on it; this is not an extra per-step follower permission pass.
	var convoy_ground_error: String = _validate_convoy_ground(geometry)
	if not convoy_ground_error.is_empty(): return convoy_ground_error
	if facts.has("visitors"):
		var error: String = HospitalClinic.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("training_jobs"):
		var error: String = HospitalClinicalDevelopment.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("research_progress") or facts.has("research_jobs"):
		var error: String = HospitalResearch.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("staff_schedule"):
		var error: String = HospitalShiftScheduler.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("staff_life"):
		var error: String = HospitalStaffWellbeing.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("waiting_life"):
		var error: String = HospitalWaitingLife.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.inventory.has("orders"):
		var error: String = HospitalSupplies.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("environment"):
		var error: String = HospitalEnvironment.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("maintenance"):
		var error: String = HospitalMaintenance.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("patient_experience"):
		var error: String = HospitalExperience.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("economy"):
		var error: String = FinanceService.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("recruitment"):
		var error: String = RecruitmentService.new(content,geometry).validate(self)
		if not error.is_empty():
			return error
	if facts.has("arrivals"):
		var error: String = HospitalArrivalService.validate_snapshot(facts,content)
		if not error.is_empty():
			return error
	if facts.floors.has("completed_top_floor"):
		var error: String = HospitalFloors.new(content,geometry).validate(self)
		if not error.is_empty(): return error
	if facts.has("remodels"):
		var service: HospitalRemodel = HospitalRemodel.new(content,geometry)
		service.services = {"building":BuildService.new(content,geometry)}
		var error: String = service.validate(self)
		if not error.is_empty(): return error
	if facts.has("clinical_suspensions"):
		if not facts.clinical_suspensions is Dictionary: return "临床接续集合无效"
		for id: Variant in facts.clinical_suspensions:
			var record: Variant = facts.clinical_suspensions[id]
			if not record is Dictionary or record.get("id")!=id or facts.sessions.has(id) or not facts.visits.has(record.get("visit_id","")) or not facts.tickets.has(record.get("suspended_ticket_id","")) or not _natural(record.get("remaining_ticks")) or not _natural(record.get("suspended_tick")) or not record.get("definition_id") is String: return "临床接续身份、原票号或工时无效"
			if facts.tickets[record.suspended_ticket_id].get("resume_session_id","")!=id: return "临床接续票号拥有者无效"
	return BuildService.new(content).validate(self)

# A valid saved trail is an occupied compound region, including gaps between
# member samples. Rebuild its world invariant once at the validation boundary.
func _validate_convoy_ground(geometry: HospitalSpace) -> String:
	for movement: Dictionary in facts.moves.values():
		if not movement.has("convoy"): continue
		var convoy: Dictionary = movement.convoy
		var leader: Dictionary = facts.actors[movement.actor_id]
		var regions: Array[Rect2] = ConvoyTrail.regions(convoy)
		if leader.location.kind=="transit": regions = ConvoyPortal.ground_regions(convoy,facts.connectors[leader.location.connector_id])
		if regions.is_empty(): continue
		var floor_id: int = int(convoy.floor_id)
		var proxy: Dictionary = ConvoyTrail.proxy(self,movement)
		# A fresh query only, never the navigation cache. Its unit-cell scan
		# tests exactly the clipped ground rectangles, not a whole proxy square
		# that would extend back into the cabin during boarding/alighting.
		var query: RouteClearance = RouteClearance.new(geometry,self,proxy,floor_id,[],{},false)
		query._size = 1
		query._indexed_static = false
		query._doors.clear()
		for door: Dictionary in query.source.layout.doors:
			var opening: Dictionary = facts.adaptations.get(door.id,{})
			var definition: Dictionary = geometry.content.definition("doors",door.definition_id)
			var span: int = int(opening.get("span",door.span))
			var rectangle: Rect2 = geometry._door_rect(door,span)
			var fits: bool = float(opening.get("clear_height_m",definition.clear_height_m))+0.00001>=float(convoy.height)+0.1 and float(opening.get("clear_width_m",definition.clear_width_m))+0.00001>=float(convoy.size)*HospitalSpace.CELL_METERS+0.1
			query._doors.append({"original":rectangle,"opening":rectangle,"ok":fits,"reason":"保存队列穿过尚未实际展开的门","room_id":door.room_id,"axis":door.axis})
		query._plain = query._plain_geometry()
		for region: Rect2 in regions:
			if not geometry._dynamic_clear(self,movement.actor_id,floor_id,region,movement.members,false,true): return "保存队列尾迹与外部身体或预约重叠："+str(movement.actor_id)
			for y: int in range(floori(region.position.y),ceili(region.end.y)):
				for x: int in range(floori(region.position.x),ceili(region.end.x)):
					var reason: String = query.reason(Vector2i(x,y))
					if not reason.is_empty(): return "保存队列尾迹静态空间无效："+reason
			var wall_reason: String = query._wall_reason(region)
			if not wall_reason.is_empty(): return "保存队列尾迹静态空间无效："+wall_reason
	return ""

func _reservation_owner_exists(id: String) -> bool:
	for collection: String in ["actors","tickets","preparations","sessions","attempts","ward_stays"]:
		if facts[collection].has(id):
			return true
	for staff: Dictionary in facts.staff.values():
		if staff.get("life_task",{}).get("id","")==id:
			return true
	for reservation: Variant in facts.get("staff_life",{}).get("reservations",{}).values():
		if reservation is Dictionary and reservation.get("id","")==id:
			return true
	return false

func _ledger_owner_exists(id: String, unit_owners: Dictionary) -> bool:
	if id==hospital_id:
		return true
	for collection: String in ["visits","attempts","build_transactions","staff","training_jobs","research_jobs","vertical_transactions","blueprint_transactions","remodels"]:
		if facts.get(collection,{}) is Dictionary and facts.get(collection,{}).has(id):
			return true
	if facts.get("inventory",{}).get("orders",{}) is Dictionary and facts.get("inventory",{}).get("orders",{}).has(id):
		return true
	if facts.floors.get("orders",{}) is Dictionary and facts.floors.get("orders",{}).has(id): return true
	if facts.get("environment",{}).get("orders",{}) is Dictionary and facts.get("environment",{}).get("orders",{}).has(id):
		return true
	if facts.get("maintenance",{}).get("jobs",{}) is Dictionary and facts.get("maintenance",{}).get("jobs",{}).has(id):
		return true
	if facts.get("maintenance",{}).get("upgrades",{}) is Dictionary and facts.get("maintenance",{}).get("upgrades",{}).has(id):
		return true
	if facts.get("recruitment",{}).get("searches",{}) is Dictionary and facts.get("recruitment",{}).get("searches",{}).has(id):
		return true
	return unit_owners.has(id)

func _validate_shapes() -> String:
	if not _natural(facts.get("move_request_next",0)):
		return "移动请求序号无效"
	if not facts.hospital_id is String or not facts.display_name is String or not facts.mode is String or not _natural(facts.entity_next):
		return "医院身份或实体序号类型无效"
	if not facts.inventory.get("issues") is Dictionary or not _natural(facts.inventory.get("units",-1)):
		return "耗材结构无效"
	if not facts.research is Array:
		return "研究集合无效"
	for value: Variant in facts.research:
		if not value is String:
			return "研究引用类型无效"
	if not facts.floors.get("height_intervals") is Array or not facts.floors.get("overrides") is Dictionary:
		return "稀疏楼层结构无效"
	if not facts.floors.overrides.get("1") is Dictionary or not facts.floors.overrides["1"].get("plots") is Array: return "医院缺少真实地面产权"
	var ground_plots: Dictionary = {}
	for plot: Variant in facts.floors.overrides["1"].plots:
		if not _grid_point(plot) or int(plot[0])<0 or int(plot[0])>2 or int(plot[1])<0 or int(plot[1])>2: return "地面地块坐标无效"
		var key: String = HospitalSpace.plot_key(plot)
		if ground_plots.has(key): return "地面地块重复"
		ground_plots[key] = true
	if facts.floors.has("completed_top_floor"):
		if not facts.floors.completed_top_floor is Dictionary: return "实完高度结构无效"
		for key: Variant in facts.floors.completed_top_floor:
			if not key is String or not _natural(facts.floors.completed_top_floor[key]) or int(facts.floors.completed_top_floor[key])<1: return "实完高度值无效"
	var last_floor: int = 0
	for interval: Variant in facts.floors.height_intervals:
		if not interval is Dictionary or not _natural(interval.get("first",-1)) or not _natural(interval.get("last",-1)) or not (interval.get("height_m") is float or interval.get("height_m") is int) or int(interval.first)<=last_floor or int(interval.last)<int(interval.first) or not is_finite(float(interval.height_m)) or float(interval.height_m)<=0:
			return "结构高度区间无效"
		last_floor = int(interval.last)
	for floor_key: String in facts.floors.overrides:
		if not floor_key.is_valid_int() or int(floor_key)<1 or (not facts.floors.has("completed_top_floor") and int(floor_key)>last_floor):
			return "实际楼层不在结构高度区间内"
		var layout: Variant = facts.floors.overrides[floor_key]
		if not layout is Dictionary or (not facts.floors.has("completed_top_floor") or floor_key=="1") and not layout.get("plots") is Array or not layout.get("blocked") is Array or not layout.get("doors") is Array:
			return "实际楼层布局无效"
		for field: String in ["plots","blocked"]:
			for point: Variant in layout.get(field,[]):
				if not _grid_point(point):
					return "楼层坐标类型无效"
		for door: Variant in layout.doors:
			if not door is Dictionary or not door.get("id") is String or not door.get("definition_id") is String or not _grid_point(door.get("cell")) or not _natural(door.get("span",-1)) or int(door.span)<1 or not door.get("axis") in ["x","y"] or not door.get("room_id","") is String or not str(door.room_id).is_empty() and not facts.rooms.has(door.room_id):
				return "门与原墙段的引用无效"
	var schemas: Dictionary = {
		"staff":{"id":TYPE_STRING,"role":TYPE_STRING,"title_id":TYPE_STRING,"abilities":TYPE_DICTIONARY,"energy":TYPE_FLOAT,"fatigue":TYPE_FLOAT,"stress_milli":TYPE_INT,"on_shift":TYPE_BOOL,"certificates":TYPE_ARRAY,"practice":TYPE_DICTIONARY,"completed_jobs":TYPE_DICTIONARY},
		"tickets":{"id":TYPE_STRING,"visit_id":TYPE_STRING,"kind":TYPE_STRING,"enqueued_tick":TYPE_INT},
		"attempts":{"id":TYPE_STRING,"visit_id":TYPE_STRING,"plan_id":TYPE_STRING,"result":TYPE_BOOL,"start_tick":TYPE_INT,"probability_bp":TYPE_INT,"work_ticks":TYPE_INT,"recovery_ticks":TYPE_INT,"supply_units":TYPE_INT,"cure_fee":TYPE_INT,"facility_fee":TYPE_INT,"staff_ids":TYPE_ARRAY,"effective_level":TYPE_FLOAT},
		"preparations":{"id":TYPE_STRING,"visit_id":TYPE_STRING,"bed_id":TYPE_STRING,"facility_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"deadline_tick":TYPE_INT,"setup_remaining_ticks":TYPE_INT},
		"ward_stays":{"id":TYPE_STRING,"visit_id":TYPE_STRING,"attempt_id":TYPE_STRING,"bed_id":TYPE_STRING,"phase":TYPE_STRING,"remaining_ticks":TYPE_INT,"work_credit_milli":TYPE_INT,"care_completed":TYPE_BOOL,"nurse_id":TYPE_STRING,"escort_id":TYPE_STRING},
		"facilities":{"id":TYPE_STRING,"definition_id":TYPE_STRING,"floor_id":TYPE_INT,"cell":TYPE_ARRAY,"footprint":TYPE_ARRAY,"patient_cell":TYPE_ARRAY,"operator_cells":TYPE_ARRAY,"repair_cell":TYPE_ARRAY,"grade":TYPE_INT,"condition":TYPE_FLOAT,"failed":TYPE_BOOL,"pending_failure":TYPE_BOOL,"use_receipts":TYPE_DICTIONARY},
		"rooms":{"id":TYPE_STRING,"kind":TYPE_STRING,"floor_id":TYPE_INT,"origin":TYPE_ARRAY,"size":TYPE_ARRAY},
		"connectors":{"id":TYPE_STRING,"definition_id":TYPE_STRING,"anchor":TYPE_ARRAY,"cell":TYPE_ARRAY,"footprint":TYPE_ARRAY,"floor_id":TYPE_INT,"phase":TYPE_STRING,"riders":TYPE_ARRAY,"remaining_ticks":TYPE_INT},
		"moves":{"actor_id":TYPE_STRING,"path":TYPE_ARRAY,"cursor":TYPE_INT,"travelled":TYPE_ARRAY,"blocked_since":TYPE_INT,"target_floor":TYPE_INT,"target_cell":TYPE_ARRAY},
		"adaptations":{"kind":TYPE_STRING,"owner_id":TYPE_STRING,"actor_id":TYPE_STRING,"staff_ids":TYPE_ARRAY,"floor_id":TYPE_INT,"regions":TYPE_ARRAY}}
	for collection: String in schemas:
		for id: String in facts[collection]:
			var record: Dictionary = facts[collection][id]
			var reason: String = _fields(record,schemas[collection])
			if not reason.is_empty():
				return collection+"："+reason
			for field: String in schemas[collection]:
				if int(schemas[collection][field]) in [TYPE_INT,TYPE_FLOAT] and not is_finite(float(record[field])):
					return "数值无效："+collection+"."+field
			if record.has("id") and record.id!=id:
				return "实体身份与索引不同："+collection
			for field: String in ["staff_ids","resources","riders","certificates","members"]:
				if record.has(field):
					if not record[field] is Array:
						return "身体或资格引用集合无效"
					for value: Variant in record[field]:
						if not value is String:
							return "身体或资格引用类型无效"
	for actor: Dictionary in facts.actors.values():
		if not actor.get("location") is Dictionary:
			return "身体位置类型无效"
		if not actor.location.get("kind") is String:
			return "身体位置结构无效"
		if actor.location.get("kind")=="transit" and (not actor.location.get("connector_id") is String or actor.location.has("floor_id") or actor.location.has("cell")):
			return "地面与乘梯位置不能同时存在"
		if actor.location.has("cabin_cell") and (actor.location.kind!="transit" or not _grid_point(actor.location.cabin_cell) or float(actor.location.cabin_cell[0])<0 or float(actor.location.cabin_cell[1])<0):
			return "轿厢内实际位置无效"
		if actor.location.get("kind")=="floor" and actor.location.has("connector_id"):
			return "地面身体携带了乘梯身份"
		if not actor.get("facing") is float and not actor.get("facing") is int:
			return "身体朝向类型无效"
		if not is_finite(float(actor.facing)) or not actor.get("posture","standing") in ["standing","seated","lying"]:
			return "身体朝向或姿态无效"
		if actor.location.has("height_m") and (not actor.location.height_m is float and not actor.location.height_m is int or not is_finite(float(actor.location.height_m))):
			return "身体承托高度无效"
	for staff: Dictionary in facts.staff.values():
		if float(staff.energy)<0 or float(staff.energy)>100 or float(staff.fatigue)<0 or float(staff.fatigue)>100 or not _natural(staff.stress_milli) or int(staff.stress_milli)>100000:
			return "职员生理数值超出范围"
		for track: String in ["diagnosis","treatment","care","surgery"]:
			if not _natural(staff.abilities.get(track,-1)) or int(staff.abilities[track])>5 or not _natural(staff.practice.get(track,-1)) or int(staff.practice[track])>180:
				return "临床能力或实践无效"
	for visit: Dictionary in facts.visits.values():
		var reason: String = _fields(visit,{"ticket_id":TYPE_STRING,"requested_plan_id":TYPE_STRING,"expression":TYPE_STRING,"personality_id":TYPE_STRING,"anger":TYPE_FLOAT,"final_result":TYPE_STRING,"waiting_reason":TYPE_STRING,"doctor_fee_quote":TYPE_INT})
		if not reason.is_empty():
			return "就诊："+reason
		if not visit.get("attempt_ids") is Array:
			return "尝试引用集合无效"
		for value: Variant in visit.attempt_ids:
			if not value is String:
				return "尝试引用类型无效"
		if not visit.get("diagnosis") is Dictionary: return "诊断状态结构无效"
		var diagnosis: Dictionary=visit.diagnosis
		if not diagnosis.is_empty():
			if not diagnosis.get("state","") in ["pending","working","insufficient","review_pending","diagnosed"] or not diagnosis.get("gp_completed") is bool or not diagnosis.get("exam_completed") is bool or not diagnosis.get("review_completed") is bool: return "诊断完成事实无效"
			if not diagnosis.get("exam_kind","") in ["","spectrum","resonance"] or diagnosis.exam_completed and str(diagnosis.exam_kind).is_empty(): return "检查模式或完成事实无效"
		if visit.has("continuation"):
			var plan: Variant=visit.continuation
			if not plan is Dictionary: return "原医生续诊返院计划无效"
			var pending_departure: bool=plan.get("stage","")=="leaving" and plan.get("first_day",0)==-1 and plan.get("return_day",0)==-1 and plan.get("due_tick",0)==-1
			if not pending_departure and (not _natural(plan.get("first_day",-1)) or not _natural(plan.get("return_day",-1)) or int(plan.return_day)<int(plan.first_day)+1 or int(plan.return_day)>int(plan.first_day)+2 or not _natural(plan.get("due_tick",-1)) or int(plan.due_tick)/TICKS_PER_DAY!=int(plan.return_day) or not plan.get("stage","") in ["leaving","outside","guidance","continuing","finished"]): return "原医生续诊返院计划无效"
			var periods: Variant=plan.get("outside_periods")
			if not periods is Array or periods.size()>2 or plan.stage=="outside" and periods.is_empty(): return "续诊院外区间无效"
			var previous_end: int=-1
			for index: int in periods.size():
				var period: Variant=periods[index]
				if not period is Dictionary or not _natural(period.get("left_tick")) or int(period.left_tick)>sim_tick or int(period.left_tick)<previous_end: return "续诊实际离院时刻无效"
				if period.get("returned_tick")==-1:
					if index!=periods.size()-1 or plan.stage!="outside": return "续诊院外区间尚未真实结束"
				else:
					if not _natural(period.get("returned_tick")) or int(period.returned_tick)<int(period.left_tick) or int(period.returned_tick)>sim_tick: return "续诊实际返院时刻无效"
					previous_end=int(period.returned_tick)
			if plan.stage=="outside" and periods.back().returned_tick!=-1: return "院外续诊缺少开放区间"
	for session: Dictionary in facts.sessions.values():
		if not session.get("staff_ids") is Array or not session.get("resources") is Array:
			return "执行会话资源结构无效"
		for value: Variant in session.staff_ids+session.resources:
			if not value is String:
				return "执行会话资源引用类型无效"
		if not _natural(session.get("total_ticks",-1)) or not _natural(session.get("remaining_ticks",-1)) or int(session.remaining_ticks)>int(session.total_ticks):
			return "服务工作量无效"
		if not session.get("kind") is String or not session.kind in ["gp","spectrum","resonance","consult","outpatient","surgery","wake","care"]:
			return "执行服务类型无效"
		if session.kind in ["outpatient","surgery","wake"] and not facts.attempts.has(session.get("attempt_id","")):
			return "执行会话承诺尝试缺失"
		if session.kind in ["care"] and not facts.ward_stays.has(session.get("stay_id","")):
			return "床边会话住院引用缺失"
	for issue: Variant in facts.inventory.issues.values():
		if not issue is Dictionary or not issue.get("attempt_id") is String or not _natural(issue.get("units",-1)) or not facts.attempts.has(issue.attempt_id):
			return "耗材领用凭据无效"
	for stay: Dictionary in facts.ward_stays.values():
		if not _natural(stay.remaining_ticks) or not _natural(stay.work_credit_milli) or int(stay.work_credit_milli)>=1000 or not facts.staff.has(stay.nurse_id) or not facts.staff.has(stay.escort_id):
			return "住院工作量或医护引用无效"
	for facility: Dictionary in facts.facilities.values():
		if not _grid_point(facility.cell) or not _extent(facility.footprint) or not _grid_point(facility.patient_cell) or not _grid_point(facility.repair_cell) or int(facility.grade)<0 or int(facility.grade)>2 or float(facility.condition)<0 or float(facility.condition)>100 or not facts.floors.overrides.has(str(int(facility.floor_id))):
			return "设施几何、维护或等级无效"
		for point: Variant in facility.operator_cells:
			if not _point(point):
				return "设施岗位坐标无效"
		if facility.has("room_id") and not facts.rooms.has(facility.room_id):
			return "设施所在房间不存在"
	for room: Dictionary in facts.rooms.values():
		if not _grid_point(room.origin) or not _extent(room.size) or not facts.floors.overrides.has(str(int(room.floor_id))):
			return "房间实际坐标、范围或楼层无效"
	for connector: Dictionary in facts.connectors.values():
		if connector.has("first_floor"):
			if not _natural(connector.first_floor) or not _natural(connector.get("last_floor")) or int(connector.first_floor)<1 or int(connector.last_floor)<int(connector.first_floor): return "竖向连接连续区间无效"
		elif not connector.get("stops") is Array: return "竖向连接站点结构无效"
		if not _grid_point(connector.anchor) or not _grid_point(connector.cell) or not _extent(connector.footprint) or not _natural(connector.remaining_ticks) or not connector.phase in ["idle","empty_riding","boarding","riding","alighting"]:
			return "竖向连接状态或锚点无效"
		if not connector.phase=="idle" and (not _natural(connector.get("from",-1)) or not _natural(connector.get("to",-1)) or not HospitalTransit.has_stop(connector,int(connector.from)) or not HospitalTransit.has_stop(connector,int(connector.to))):
			return "竖向连接起止楼层不在真实停靠点中"
		if HospitalTransit.endpoints(connector).is_empty() or not HospitalTransit.has_stop(connector,int(connector.floor_id)) or (connector.phase in ["idle","empty_riding"] and not connector.riders.is_empty()):
			return "竖向连接停靠点或实际乘员无效"
		if connector.phase in ["boarding","riding","alighting"] and connector.riders.is_empty():
			return "载客阶段缺少真实通行组"
		for field: String in ["primary_actor_id","assigned_actor_id"]:
			if connector.has(field) and (not connector[field] is String or not facts.actors.has(connector[field])):
				return "交通拥有者身份无效"
		if connector.has("primary_actor_id") and not connector.primary_actor_id in connector.riders:
			return "通行组领队不是实际乘员"
		if not _natural(connector.get("ticket_next",0)) or (connector.has("trip_travel_ticks") and not _natural(connector.trip_travel_ticks)):
			return "交通票序或已承诺通行时间无效"
		for field: String in ["failed","pending_failure"]:
			if connector.has(field) and not connector[field] is bool:
				return "交通运行模式无效"
		for stop: Variant in HospitalTransit.endpoints(connector):
			if not _natural(stop) or HospitalSpace.floor_plots(self,int(stop)).is_empty():
				return "竖向连接停靠点没有实际楼层"
	var request_sequences: Dictionary = {}
	var transit_sequences: Dictionary = {}
	for movement: Dictionary in facts.moves.values():
		# Saved groups have one authoritative ordered trail. Fixed offsets are
		# deliberately unsupported; accepting both creates conflicting poses.
		if movement.has("offsets"): return "旧固定偏移移动组不受支持"
		if movement.has("members")!=movement.has("convoy"): return "移动组必须保存完整队列状态"
		if movement.has("members") and (not movement.members is Array or movement.members.is_empty() or not movement.convoy is Dictionary): return "队列成员或状态结构无效"
		for member_id: Variant in movement.get("members",[]):
			if not member_id is String: return "队列成员身份类型无效"
		if not _point(movement.target_cell) or not _natural(movement.cursor) or int(movement.cursor)>movement.path.size():
			return "移动游标或目标无效"
		if movement.has("yielding") and (not movement.yielding is bool or movement.yielding) or movement.has("yield_partner"):
			return "旧优先级让行状态不受支持"
		if movement.has("local_move"):
			var local: Variant = movement.local_move
			if not local is Dictionary or not local.get("target") is Dictionary: return "局部移动目标结构无效"
			if movement.has("detour") or movement.has("convoy") or movement.has("members") or movement.get("route_pending",false) or movement.has("route_waypoint"): return "局部移动不能与其他路线拥有者并存"
			for key: Variant in local:
				if not key in ["target","origin","rejoin","retreat","corners"]: return "局部移动含未知状态"
			if not _point(local.get("origin")): return "局部移动缺少原路线离开点"
			if local.has("retreat") and (typeof(local.retreat)!=TYPE_BOOL or not local.retreat): return "局部后退标记无效"
			if local.has("corners") and (not local.corners is Array or local.corners.is_empty() or local.corners.size()>2 or not local.has("rejoin")): return "局部连续转角必须属于短回接路线"
			var local_actor: Dictionary = facts.actors.get(movement.actor_id,{})
			var local_target: Dictionary = local.target
			if local_actor.get("location",{}).get("kind")!="floor" or local_target.get("kind")!="floor" or not _point(local_target.get("cell")) or not _natural(local_target.get("floor_id",-1)) or local_target.floor_id!=local_actor.location.floor_id: return "局部移动必须保持同层有限坐标"
			var local_origin: Vector2 = ConvoyTrail.point(local_actor.location.cell)
			var local_endpoint: Vector2 = ConvoyTrail.point(local_target.cell)
			if local_origin.x!=local_endpoint.x and local_origin.y!=local_endpoint.y: return "局部移动不能斜穿格子"
			if int(movement.cursor)>=movement.path.size(): return "局部移动缺少尚未完成的原路线"
			if local.has("rejoin"):
				var link: Variant = local.rejoin
				if not link is Dictionary or link.size()!=2 or not _point(link.get("cell")) or not link.get("index") is int: return "局部移动接回结构无效"
				var local_index: int = link.index
				if local_index<int(movement.cursor) or local_index>=movement.path.size(): return "局部移动接回索引无效"
				var start: Vector2 = ConvoyTrail.point(local.origin)
				for index: int in range(int(movement.cursor),local_index+1):
					var original: Variant = movement.path[index]
					if not original is Dictionary or original.get("kind")!="floor" or original.get("floor_id")!=local_actor.location.floor_id or not _point(original.get("cell")): return "局部移动不能跳过跨层或非层内路线"
					if index<local_index: start=ConvoyTrail.point(original.cell)
				var end: Vector2 = ConvoyTrail.point(movement.path[local_index].cell)
				var rejoin: Vector2 = ConvoyTrail.point(link.cell)
				if (end-start).cross(rejoin-start)!=0.0 or (rejoin-start).dot(rejoin-end)>0.0: return "局部移动接点不在原路线段"
				if local.has("corners"):
					var corner_from: Vector2=local_origin
					var corner: Vector2=local_endpoint
					var suffix: Array=local.corners.duplicate()
					suffix.append({"kind":"floor","floor_id":local_actor.location.floor_id,"cell":link.cell})
					for next: Variant in suffix:
						if not next is Dictionary or next.get("kind")!="floor" or next.get("floor_id")!=local_actor.location.floor_id or not _point(next.get("cell")): return "局部连续转角必须保持同层有限坐标"
						var after: Vector2=ConvoyTrail.point(next.cell)
						if corner==after: return "局部连续转角不能重复坐标"
						if corner.x!=after.x and corner.y!=after.y: return "局部移动中间转角不能斜接原路线"
						if corner!=after and corner_from!=corner and (corner-corner_from).dot(after-corner)!=0.0: return "局部移动中间点必须是正交转角"
						corner_from=corner;corner=after
			else:
				var original: Variant = movement.path[int(movement.cursor)]
				if not original is Dictionary or original.get("kind")!="floor" or original.get("floor_id")!=local_actor.location.floor_id: return "局部移动原路线不在当前楼层"

		if movement.has("detour"):
			if not movement.has("convoy") and movement.get("members",[movement.actor_id]).size()==1: return "旧单人detour绕行状态不受支持"
			var detour: Variant = movement.detour
			if not detour is Dictionary or not _fields(detour,{"phase":TYPE_STRING,"original_path":TYPE_ARRAY,"direction":TYPE_ARRAY,"backtrack":TYPE_ARRAY,"back_cursor":TYPE_INT,"prefix_size":TYPE_INT,"resume_index":TYPE_INT}).is_empty(): return "局部绕行状态结构无效"
			if not detour.phase in ["aside","back","rejoin"] or detour.original_path.is_empty() or not _point(detour.direction): return "局部绕行阶段或原路线无效"
			if not ((absf(float(detour.direction[0]))==1.0 and float(detour.direction[1])==0.0) or (float(detour.direction[0])==0.0 and absf(float(detour.direction[1]))==1.0)): return "局部绕行方向无效"
			if not _natural(detour.back_cursor+1) or int(detour.back_cursor)>=detour.backtrack.size() or not _natural(detour.resume_index+1) or not _natural(detour.prefix_size) or int(detour.prefix_size)>movement.path.size() or int(movement.cursor)>int(detour.prefix_size): return "局部绕行游标无效"
			if detour.phase=="rejoin":
				if not _natural(detour.resume_index) or int(detour.resume_index)>=detour.original_path.size() or int(detour.prefix_size)<1 or movement.path.slice(int(detour.prefix_size))!=detour.original_path.slice(int(detour.resume_index)+1): return "局部绕行未接回原路线"
			elif int(detour.resume_index)!=-1 or int(detour.prefix_size)!=movement.path.size(): return "局部绕行临时前缀无效"
			if movement.get("route_pending",false) or movement.has("route_waypoint"): return "局部绕行不能重发原路线请求"
			var actor: Dictionary = facts.actors.get(movement.actor_id,{})
			var original: Variant = detour.original_path[0]
			if actor.get("location",{}).get("kind","")!="floor" or not original is Dictionary or original.get("kind")!="floor" or original.get("floor_id")!=actor.location.floor_id: return "局部绕行必须保持原受阻楼层"
			for segment: Variant in movement.path.slice(0,int(detour.prefix_size)):
				if not segment is Dictionary or segment.get("kind")!="floor" or not _point(segment.get("cell")) or segment.get("floor_id")!=actor.location.floor_id: return "局部绕行前缀必须是同层真实路径"
			if detour.phase=="rejoin":
				var endpoint: Dictionary = movement.path[int(detour.prefix_size)-1]
				var resume: Variant = detour.original_path[int(detour.resume_index)]
				if not resume is Dictionary or resume.get("kind")!="floor" or not _point(resume.get("cell")) or resume.get("floor_id")!=endpoint.floor_id or ConvoyTrail.point(endpoint.cell).distance_to(ConvoyTrail.point(resume.cell))>0.00001: return "局部重接前缀未到原路线格"
			if int(detour.prefix_size)>0 and int(movement.cursor)==int(detour.prefix_size) and ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(movement.path[int(detour.prefix_size)-1].cell))>0.001: return "局部绕行游标未实际到达前缀终点"
			for past: Variant in detour.backtrack:
				if not past is Dictionary or past.get("kind")!="floor" or not _point(past.get("cell")) or not _natural(past.get("floor_id",-1)) or past.floor_id!=actor.location.floor_id: return "局部后退历史无效"
		if not movement.get("route_pending",false) is bool:
			return "移动请求状态无效"
		if movement.has("live_floor_route"):
			if not movement.live_floor_route is bool or movement.live_floor_route!=true or not movement.get("route_pending",false) or movement.has("local_move") or movement.has("convoy") or movement.has("route_waypoint") or facts.actors[movement.actor_id].location.kind!="floor" or int(facts.actors[movement.actor_id].location.floor_id)!=int(movement.target_floor):return "实际同层重派状态无效"
		if movement.has("route_rejoin"):return "不支持旧原路线失败游标"
		if movement.has("rejoin_origin"):
			if not movement.get("live_floor_route",false) or not _point(movement.rejoin_origin) or int(movement.cursor)>=movement.path.size():return "原路线回接起点无效"
			var first: Dictionary=movement.path[int(movement.cursor)]
			if first.get("kind")!="floor" or int(first.get("floor_id",-1))!=int(facts.actors[movement.actor_id].location.floor_id):return "原路线回接不得接管连接段"
		if movement.has("request_sequence"):
			var sequence: Variant = movement.request_sequence
			if not _natural(sequence) or int(sequence)<1 or int(sequence)>int(facts.get("move_request_next",0)) or request_sequences.has(sequence):
				return "移动请求序号重复或超出原序列"
			request_sequences[sequence] = true
		elif movement.get("route_pending",false):
			return "待处理移动缺少原请求序号"
		if movement.has("route_retry_tick") and not _natural(movement.route_retry_tick):
			return "移动重查边界无效"
		if movement.has("route_waypoint"):
			var waypoint: Variant = movement.route_waypoint
			if not waypoint is Dictionary or not _natural(waypoint.get("floor_id",-1)) or not _point(waypoint.get("cell")) or not waypoint.get("continuation") is Array:
				return "临时让位路线无效"
			if waypoint.has("prefix"):
				if not movement.get("route_pending",false) or movement.has("local_move") or movement.has("detour") or movement.has("convoy") or movement.has("transit_ticket"): return "有限让位前缀拥有者无效"
				if not waypoint.prefix is Array or waypoint.prefix.is_empty() or waypoint.prefix.size()>2 or not waypoint.get("binding") is Dictionary: return "有限让位前缀结构无效"
				var binding: Dictionary=waypoint.binding
				if not _point(binding.get("origin")) or not _natural(binding.get("sequence",-1)) or not _natural(binding.get("target_floor",-1)) or not _point(binding.get("target_cell")) or not binding.get("connector_id") is String or not _natural(binding.get("trip_sequence",-1)): return "有限让位前缀绑定无效"
				for point: Variant in waypoint.prefix:
					if not point is Dictionary or point.get("kind")!="floor" or point.get("floor_id")!=waypoint.floor_id or not _point(point.get("cell")): return "有限让位前缀角点无效"
				if waypoint.prefix[-1].cell!=waypoint.cell: return "有限让位前缀终点无效"

		if movement.has("transit_wait"):
			var waiting: Variant=movement.transit_wait
			if not waiting is Dictionary or not _point(waiting.get("cell")) or waiting.get("sequence")!=movement.get("request_sequence",-1) or not movement.has("transit_ticket"): return "实际候位绑定无效"
		if movement.has("transit_ticket"):
			var ticket: Variant = movement.transit_ticket
			if not ticket is Dictionary or not _fields(ticket,{"connector_id":TYPE_STRING,"sequence":TYPE_INT,"from":TYPE_INT,"to":TYPE_INT}).is_empty() or not facts.connectors.has(ticket.get("connector_id","")):
				return "到站通行票结构或连接引用无效"
			var connection: Dictionary = facts.connectors[ticket.connector_id]
			var key: String = ticket.connector_id+":"+str(ticket.sequence)
			if not _natural(ticket.sequence) or int(ticket.sequence)<1 or int(ticket.sequence)>int(connection.get("ticket_next",0)) or transit_sequences.has(key) or not HospitalTransit.has_stop(connection,int(ticket.from)) or not HospitalTransit.has_stop(connection,int(ticket.to)):
				return "到站票序、起止站或连接身份无效"
			transit_sequences[key] = true
			for id: String in movement.get("members",[movement.actor_id]):
				var actor: Dictionary = facts.actors.get(id,{})
				if actor.is_empty() or actor.location.get("kind")!="floor" or not _natural(actor.location.get("floor_id",-1)) or int(actor.location.floor_id)!=int(ticket.from):
					return "到站通行组没有实际位于起点层"
		var segments: Array = movement.path+movement.get("route_waypoint",{}).get("continuation",[])+movement.get("detour",{}).get("original_path",[])+movement.get("detour",{}).get("backtrack",[])
		if movement.has("local_move"): segments.append(movement.local_move.target)
		for segment: Variant in segments:
			if not segment is Dictionary or not segment.get("kind") in ["floor","support_exit","connector"]:
				return "实际路线段类型无效"
			if segment.kind in ["floor","support_exit"] and (not _point(segment.get("cell")) or not _natural(segment.get("floor_id",-1))):
				return "实际层内路线段坐标无效"
			if segment.kind=="connector" and not segment.get("connector_id") is String:
				return "实际跨层路线段引用无效"
			if segment.kind=="connector" and (not _natural(segment.get("from",-1)) or not _natural(segment.get("to",-1))):
				return "实际跨层路线段楼层无效"
		for segment: Variant in movement.travelled:
			if not segment is Dictionary or segment.get("kind")!="floor" or not _point(segment.get("cell")) or not _natural(segment.get("floor_id",-1)):
				return "实际已行路线段无效"
	for reservation: Dictionary in facts.adaptations.values():
		if not reservation.kind in ["facility","door"]:
			return "实际展开类型无效"
		if not facts.floors.overrides.has(str(int(reservation.floor_id))):
			return "实际展开楼层不存在"
		if reservation.kind=="door" and (not _natural(reservation.get("span",-1)) or int(reservation.span)<1 or not (reservation.get("clear_height_m") is float or reservation.get("clear_height_m") is int) or not is_finite(float(reservation.clear_height_m)) or float(reservation.clear_height_m)<=0 or not (reservation.get("clear_width_m") is float or reservation.get("clear_width_m") is int) or not is_finite(float(reservation.clear_width_m)) or float(reservation.clear_width_m)<=0):
			return "门展开净宽净高无效"
		if reservation.has("convoy_envelope"):
			var envelope: Variant = reservation.convoy_envelope
			if reservation.kind!="door" or not envelope is Dictionary or envelope.size()!=2 or not _natural(envelope.get("size",0)) or int(envelope.get("size",0))<1 or not (envelope.get("height") is int or envelope.get("height") is float) or not is_finite(float(envelope.height)) or float(envelope.height)<=0:
				return "门展开队列包络无效"
		if reservation.kind=="facility" and (not reservation.get("facility_id") is String or not _point(reservation.get("footprint")) or not _point(reservation.get("patient_cell")) or not reservation.get("operator_cells") is Array or not _point(reservation.get("repair_cell"))):
			return "实际设施展开几何无效"
		for ordinal: int in reservation.regions.size():
			var area: Variant=reservation.regions[ordinal]
			if not area is Array or area.size()!=4:
				return "实际预约区域无效"
			var continuous_patient: bool=reservation.kind=="facility" and ordinal==1 and facts.facilities.get(str(reservation.get("facility_id","")),{}).get("definition_id","")=="SE01"
			if continuous_patient:
				for number: Variant in area:
					if not (number is int or number is float) or not is_finite(float(number)) or float(number)<0.0 or float(number)>1000000000000: return "导诊患者预约矩形数值无效"
				if float(area[2])<=0.0 or float(area[3])<=0.0 or not is_finite(float(area[0])+float(area[2])) or not is_finite(float(area[1])+float(area[3])): return "导诊患者预约矩形尺寸无效"
				continue
			for number: Variant in area:
				if not _natural(number):
					return "实际预约区域数值无效"
	return ""

static func _signed_decimal(value: Variant) -> bool:
	if not value is String or not value.is_valid_int():
		return false
	return str(value.to_int())==value

static func _grid_point(value: Variant) -> bool:
	return _point(value) and float(value[0])==floor(float(value[0])) and float(value[1])==floor(float(value[1]))

static func _extent(value: Variant) -> bool:
	return _grid_point(value) and float(value[0])>0 and float(value[1])>0

static func _fields(record: Dictionary, schema: Dictionary) -> String:
	for field: String in schema:
		if not record.has(field):
			return "缺少字段："+field
		var actual: int = typeof(record[field])
		if actual==int(schema[field]) or (int(schema[field]) in [TYPE_INT,TYPE_FLOAT] and actual in [TYPE_INT,TYPE_FLOAT]):
			continue
		return "字段类型无效："+field
	return ""

static func _point(value: Variant) -> bool:
	if not value is Array or value.size()!=2:
		return false
	for coordinate: Variant in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate))>1000000000000:
			return false
	return true

static func _natural(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value)<=1000000000000 and float(value) == floor(float(value))
