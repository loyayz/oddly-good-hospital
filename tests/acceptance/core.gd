extends RefCounted

const CASES: Dictionary = {
	"CORE-01":"模拟规格§8：空院24800、60包、单地块且无员工房间",
	"CORE-02":"模拟规格§8：预设10780、6员工及合法初始布局",
	"CORE-03":"阶段02至03规格§2：冻结副本与世界/会话事实分离",
	"CORE-04":"阶段02至03规格§4：初始暂停及0.1秒固定步",
	"CORE-05":"阶段02至03规格§4：独立来源暂停令牌",
	"CORE-06":"阶段02至03规格§4：观看覆盖与手动速度",
	"CORE-07":"阶段02至03规格§4：停机不补算，正常积压不删步",
	"CORE-08":"阶段02至03规格§3：医院和会话身份拒绝原子",
	"CORE-09":"阶段02至03规格§3：暂停命令和恢复后幂等",
	"CORE-10":"阶段02至03规格§3：同ID不同内容拒绝",
	"CORE-11":"阶段02至03规格§3：无关修订不锁定，非法目标原子",
	"CORE-12":"阶段02至03规格§3：运行命令在保存边界排空",
	"CORE-13":"阶段02至03规格§3：账目幂等及负余额拒绝",
	"CORE-14":"技术规格§4：十二独立随机流",
	"CORE-15":"实施路线4.2至4.4：完整基础内容和引用",
	"CORE-16":"实施路线4.3：注册表不可变",
	"CORE-17":"实施路线4.4：加载失败保留有效注册表",
	"CORE-18":"技术规格§5、路线5.1至5.3：真实SQLite保存回读",
	"CORE-19":"同上：回执属于冻结修订",
	"CORE-20":"同上：追加序列和旧提交保留",
	"CORE-21":"路线4.1、5.4：完整内容身份、坏世界不部分载入及旧有效提交恢复",
	"CORE-22":"路线5.4：事务中断不封存半成品",
	"CORE-23":"技术规格资料所有权：真实独占与释放",
	"CORE-24":"路线6.1：清单分页不冒充世界已校验",
	"CORE-25":"路线6.1：取消旧扫描",
	"CORE-26":"路线6.3：实际ZIP备份新身份导入",
	"CORE-27":"技术规格受限ZIP：路径与未知条目拒绝",
	"CORE-28":"路线6.4：回收和恢复保留身份",
	"CORE-29":"路线6.4：当前医院不可回收",
	"CORE-30":"路线6.2：新医院会话暂停且拒绝旧输入",
	"CORE-31":"路线7.1、7.4：观看高层不改变世界",
	"CORE-32":"路线7.4：资源票旧身份拒绝",
	"CORE-33":"路线7.2、7.3：基础资源可加载且观看不造实体",
	"CORE-34":"阶段04至28规格：18个实际服务面板只读绑定",
	"CORE-35":"体验规格及路线7.4：200%文字和小窗口可操作",
	"CORE-36":"路线6.2及阶段25至28规格：取消离开保留草稿",
	"CORE-37":"路线4.4：新种族复用已有病症与主体",
	"CORE-38":"路线4.4：新病症复用已有种族与主体",
	"CORE-39":"路线4.2：重复、错类型与未知内容拒绝",
	"CORE-40":"路线4.2：缺依赖与依赖环拒绝",
	"CORE-41":"技术规格账目结算：待结索引、幂等、原子失败、恢复及医院隔离",
	"CORE-42":"技术规格分段SQLite：固定语句复用、空结果、错误恢复与回滚原子性",
	"CORE-43":"性能规格显示边界：实际物理3D视口、原生2D、比例切换和原坐标拾取",
	"CORE-44":"技术规格§5规范JSON：String/StringName文本键统一排序，完整值与冷热回读保持",
	"CORE-45":"技术规格账本：余额与待付负债同源，提交、结算、替换和恢复精确保持",
	"CORE-46":"技术规格保存保留：完整旧保存点校验、坏档拒绝及有效回退保留",
	"CORE-47":"技术规格详情投影：原会话顺序、完整文字和余额显示保持",
	"CORE-48":"技术规格表现投影：局部只读索引保留姿态优先级与当前事实",
	"CORE-49":"技术规格流式编解码：跨块UTF-8、64位、坏输入及精确校验和",
	"CORE-50":"命名前提：生成recipe与祖先依赖、环境失效、无关修改复用、完整事实独立复制及坏缓存拒绝",
	"CORE-51":"表现签名：当前精确依赖、同修订直接修改和冷热投影一致",
	"CORE-52":"资源发布：同批一次包围盒、独立及批量绑定、迟到票与当前模型句柄",
	"CORE-53":"管理界面：方案完整比较、提交复核、窄招聘状态与预览发布",
	"CORE-54":"导入与预览：复合员工身份最长前缀及不规则阻挡颜色保持"
}

func run(t) -> void:
	for case_id: String in CASES:
		if not t.wants(case_id): continue
		t.begin_case(case_id)
		await call("_case_"+case_id.right(2),t,HospitalContent.new())

func _case_43(t, content: HospitalContent) -> void:
	await preload("res://tests/acceptance/scene_pixels.gd").new().run(t,content)

func _case_44(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/canonical_json.gd").new().run(t,content)

func _case_45(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/ledger_observation.gd").new().run(t,content)

func _case_46(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/snapshot_cleanup.gd").new().run(t,content)

func _case_47(t, content: HospitalContent) -> void:
	await preload("res://tests/acceptance/details_projection.gd").new().run(t,content)

func _case_48(t, content: HospitalContent) -> void:
	await preload("res://tests/acceptance/view_projection.gd").new().run(t,content)

func _case_49(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/stream_boundaries.gd").new().run(t,content)

func _case_50(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/checkpoint_dependencies.gd").new().run(t,content)

func _case_51(t, content: HospitalContent) -> void:
	await preload("res://tests/acceptance/repeated_presentation.gd").new().run_projection(t,content,"CORE-51")

func _case_52(t, content: HospitalContent) -> void:
	await preload("res://tests/acceptance/repeated_presentation.gd").new().run_resources(t,content,"CORE-52")

func _case_53(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/repeated_presentation.gd").new().run_ui(t,content,"CORE-53")

func _case_54(t, content: HospitalContent) -> void:
	preload("res://tests/acceptance/repeated_presentation.gd").new().run_import_overlay(t,content,"CORE-54")

func _case_01(t, content: HospitalContent) -> void:
	var empty: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"空地",false,content)
	t.check("CORE-01",HospitalLedger.balance(empty)==24800 and int(empty.facts.inventory.units)==60 and empty.facts.rooms.is_empty() and empty.facts.staff.is_empty() and HospitalSpace.floor_plots(empty,1)==[[1,2]])

func _case_02(t, content: HospitalContent) -> void:
	var preset: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"预设",true,content)
	var initial_space: HospitalSpace = HospitalSpace.new(content)
	var office: Dictionary = initial_space.facility_layout(preset,"doctor_office_desk")
	var office_route: Dictionary = initial_space.route(preset,"starter_doctor_a",1,office.operator_cells[0])
	t.check("CORE-02",HospitalLedger.balance(preset)==10780 and preset.facts.staff.size()==6 and preset.validate(content).is_empty() and office_route.ok,{"validation":preset.validate(content),"office_route":office_route})

func _case_03(t, content: HospitalContent) -> void:
	var empty: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"空地",false,content)
	var frozen: Dictionary = empty.freeze()
	frozen.display_name = "副本"
	t.check("CORE-03",empty.facts.display_name=="空地" and not empty.facts.has("requested_speed") and not empty.facts.has("scene"))

func _case_04(t, content: HospitalContent) -> void:
	var rates: bool = true
	for speed: int in [1,2,3]:
		var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"时钟",false,content)
		var sim: HospitalSimulation = HospitalSimulation.new(world,content)
		var session: GameSession = GameSession.new(sim,"clock")
		rates = rates and session.actual_speed()==0
		session.set_speed(speed)
		session.advance(0.2)
		rates = rates and world.sim_tick==[2,4,6][speed-1]
		sim.dispose()
	t.check("CORE-04",rates)

func _case_05(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"暂停",false,content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(sim,"pause")
	session.set_speed(3)
	session.pause("focus")
	session.pause("dialog")
	session.resume("focus")
	session.advance(0.2)
	var held: bool = session.actual_speed()==0 and world.sim_tick==0
	session.resume("dialog")
	t.check("CORE-05",held and session.actual_speed()==3)
	sim.dispose()

func _case_06(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"观看",false,content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(sim,"watch")
	session.set_speed(3)
	session.set_watching(true)
	var watching: bool = session.actual_speed()==1
	session.set_speed(2)
	t.check("CORE-06",watching and session.actual_speed()==2)
	sim.dispose()

func _case_07(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"停机",false,content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(sim,"backlog")
	session.set_speed(1)
	session.advance(0.0)
	session.advance(2.0)
	var suspended: bool = world.sim_tick==0
	session.advance(0.9)
	var bounded: bool = world.sim_tick==8 and session.running_slow
	session.advance(0.0)
	t.check("CORE-07",suspended and bounded and world.sim_tick==9)
	sim.dispose()

func _case_08(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"命令",false,content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(sim,"current")
	var payload: Dictionary = {"floor_id":1,"room_type_id":"gp","origin":[34,66],"size":[4,4]}
	var before: Dictionary = world.freeze()
	var old: CommandResult = session.submit(GameCommand.new("old",world.hospital_id,world.revision,"build_room",BusinessPayload.new(payload),"previous"))
	var other: CommandResult = session.submit(GameCommand.new("other","other-hospital",world.revision,"build_room",BusinessPayload.new(payload),"current"))
	t.check("CORE-08",not old.accepted and not other.accepted and world.freeze()==before)
	sim.dispose()

func _case_09(t, content: HospitalContent) -> void:
	var x: Dictionary = _command_fixture(content)
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var session: GameSession = x.session
	var payload: Dictionary = x.payload
	var command: GameCommand = GameCommand.new("room",world.hospital_id,world.revision,"build_room",BusinessPayload.new(payload),"current")
	var built: CommandResult = session.submit(command)
	var after: Dictionary = world.freeze()
	var duplicate: CommandResult = session.submit(command)
	var restored: WorldState = WorldState.new(world.freeze())
	var second: HospitalSimulation = HospitalSimulation.new(restored,content)
	var resumed: CommandResult = second.apply(command)
	t.check("CORE-09",built.accepted and duplicate.accepted and resumed.accepted and world.sim_tick==0 and world.freeze()==after and restored.freeze()==after,built.reason)
	sim.dispose()
	second.dispose()

func _case_10(t, content: HospitalContent) -> void:
	var x: Dictionary = _command_fixture(content,true)
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var session: GameSession = x.session
	var payload: Dictionary = x.payload
	var after: Dictionary = world.freeze()
	var changed: Dictionary = payload.duplicate(true)
	changed.origin = [44,66]
	var conflict: CommandResult = session.submit(GameCommand.new("room",world.hospital_id,world.revision,"build_room",BusinessPayload.new(changed),"current"))
	t.check("CORE-10",not conflict.accepted and world.freeze()==after)
	sim.dispose()

func _case_11(t, content: HospitalContent) -> void:
	var x: Dictionary = _command_fixture(content,true)
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var session: GameSession = x.session
	var changed: Dictionary = x.payload.duplicate(true)
	changed.origin = [44,66]
	var quoted_revision: int = world.revision
	world.touch()
	var unrelated: CommandResult = session.submit(GameCommand.new("second_room",world.hospital_id,quoted_revision,"build_room",BusinessPayload.new(changed),"current"))
	var before: Dictionary = world.freeze()
	changed.origin = [0,0]
	var invalid: CommandResult = session.submit(GameCommand.new("invalid",world.hospital_id,world.revision,"build_room",BusinessPayload.new(changed),"current"))
	t.check("CORE-11",unrelated.accepted and not invalid.accepted and world.freeze()==before,unrelated.reason)
	sim.dispose()

func _case_12(t, content: HospitalContent) -> void:
	var x: Dictionary = _command_fixture(content)
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var session: GameSession = x.session
	session.set_speed(1)
	var queued: CommandResult = session.submit(GameCommand.new("floor_note",world.hospital_id,world.revision,"finance_note",BusinessPayload.new({"text":"保存边界","target_amount":6000}),"current"))
	var revision: int = world.revision
	session.drain_commands()
	t.check("CORE-12",queued.accepted and queued.code=="queued" and world.facts.command_receipts.has("floor_note") and world.revision>revision and world.sim_tick==0)
	sim.dispose()

func _case_13(t, content: HospitalContent) -> void:
	var x: Dictionary = _command_fixture(content)
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var balance: int = HospitalLedger.balance(world)
	var entry: LedgerEntry = LedgerEntry.new(world.hospital_id,"acceptance_payment",-10)
	var paid: CommandResult = HospitalLedger.post(world,entry)
	HospitalLedger.post(world,entry)
	var before: Dictionary = world.freeze()
	var excessive: CommandResult = HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"excessive",-1000000))
	t.check("CORE-13",paid.accepted and HospitalLedger.balance(world)==balance-10 and not excessive.accepted and world.freeze()==before)
	sim.dispose()

func _case_41(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"账目索引",false,content)
	var original: Dictionary = world.freeze()
	var empty: bool = HospitalLedger.settle(world).is_empty() and world.freeze()==original
	var z: LedgerEntry = LedgerEntry.new(world.hospital_id,"z_pending",25)
	var a: LedgerEntry = LedgerEntry.new(world.hospital_id,"a_pending",-10)
	var posted: bool = HospitalLedger.post(world,z,false).accepted and HospitalLedger.post(world,a,false).accepted
	var pending: Dictionary = world.freeze()
	var duplicate: CommandResult = HospitalLedger.post(world,z,true)
	var conflict: CommandResult = HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"z_pending",26),false)
	var funds: CommandResult = HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"fail_pending",-1000000),false)
	var atomic: bool = duplicate.accepted and duplicate.code=="duplicate" and not conflict.accepted and not funds.accepted and world.freeze()==pending and HospitalLedger.balance(world)==24800
	var restored: WorldState = WorldState.new(pending.duplicate(true))
	var events: Array[SimEvent] = HospitalLedger.settle(world)
	var event_ids: Array = []
	for event: SimEvent in events: event_ids.append_array(event.changed_ids)
	var ordered: bool = event_ids==[a.entry_id,z.entry_id] and HospitalLedger.balance(world)==24815 and HospitalLedger.settle(world).is_empty()
	var other: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"另一医院",false,content)
	var other_entry: LedgerEntry = LedgerEntry.new(other.hospital_id,"pending",7)
	HospitalLedger.post(other,other_entry,false)
	var replacement: Dictionary = other.freeze()
	world.facts = replacement.duplicate(true)
	var replacement_events: Array[SimEvent] = HospitalLedger.settle(world)
	var rebuilt: bool = replacement_events.size()==1 and replacement_events[0].changed_ids==[other_entry.entry_id] and HospitalLedger.balance(world)==24807 and not other.facts.ledger.entries[other_entry.entry_id].settled
	var recovered_events: Array[SimEvent] = HospitalLedger.settle(restored)
	var recovered: bool = recovered_events.size()==2 and HospitalLedger.balance(restored)==24815
	var instant: bool = HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"instant_payment",-1),true).accepted and HospitalLedger.settle(world).is_empty() and HospitalLedger.balance(world)==24806
	var validation: String = world.validate(content)+restored.validate(content)+other.validate(content)
	t.check("CORE-41",empty and posted and atomic and ordered and rebuilt and recovered and instant and validation.is_empty(),{"empty_readonly":empty,"atomic":atomic,"event_order":event_ids,"replacement_rebuilt":rebuilt,"restored":recovered,"instant":instant,"validation":validation})

func _case_14(t, content: HospitalContent) -> void:
	var empty: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"空地",false,content)
	var original_rng: Dictionary = empty.facts.rng.duplicate(true)
	empty.draw("treatment",10000)
	var independent: bool = empty.facts.rng.size()==12 and original_rng.treatment!=empty.facts.rng.treatment
	for stream: String in original_rng:
		if stream!="treatment" and original_rng[stream]!=empty.facts.rng[stream]: independent = false
	t.check("CORE-14",independent)

func _case_15(t, content: HospitalContent) -> void:
	t.check("CORE-15",content.error.is_empty() and content.catalog.species.size()==80 and content.catalog.diseases.size()==154 and content.catalog.research.size()==38 and content.catalog.build_room_types.size()==17,content.error)

func _case_16(t, content: HospitalContent) -> void:
	var species: Dictionary = content.definition("species","S49")
	var original_name: String = species.name
	var immutable: bool = species.is_read_only() and species.body.is_read_only()
	if not species.is_read_only(): species.name = "查询副本"
	if not species.body.is_read_only(): species.body.width_m = 999.0
	var facilities_readonly: bool = true
	for collection: String in ContentRegistry.FACILITY_COLLECTIONS:
		for definition: Dictionary in content.registry.collection(collection):
			var identifier: String = str(definition.get("id",definition.get("definition_id","")))
			var facility: Dictionary = content.facility_definition(identifier)
			facilities_readonly = facilities_readonly and facility.is_read_only() and is_same(facility,content.registry.legacy_definition(collection,identifier)) and is_same(facility,content.facility_definition(ContentRegistry.legacy_id(identifier)))
	facilities_readonly = facilities_readonly and content.facility_definition("absent:FACILITY").is_empty()
	t.check("CORE-16",facilities_readonly and (immutable or content.definition("species","S49").name==original_name and float(content.definition("species","S49").body.width_m)<999.0),{"facility_views_readonly_and_canonical_aliases":facilities_readonly})

func _case_17(t, content: HospitalContent) -> void:
	var original_name: String = content.definition("species","S49").name
	var fingerprint: String = content.content_fingerprint
	var invalid: bool = content.load_packs(PackedStringArray(["res://acceptance-missing-pack"]))
	t.check("CORE-17",not invalid and content.content_fingerprint==fingerprint and content.definition("species","S49").name==original_name)

func _case_18(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var world: WorldState = x.world
	var original: Dictionary = x.original
	var loaded: Dictionary = x.loaded
	t.check("CORE-18",loaded.ok and _same(loaded.world.freeze(),original),loaded.get("error",""))
	_close_storage(x)

func _case_42(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var opened: Dictionary = x.store._connect(x.world.hospital_id)
	if not opened.ok:
		t.check("CORE-42",false,opened)
		_close_storage(x)
		return
	var database: RefCounted = opened.database
	var sql: String = "SELECT chunk_index,CASE WHEN length(data)<=32768 THEN data END AS data FROM world_chunks WHERE snapshot_id=? AND chunk_index>=? ORDER BY chunk_index LIMIT 1"
	var source: Dictionary = database.call("execute",sql,[x.first_id,0])
	var correct: bool = source.ok and source.rows.size()==1
	if not correct:
		database.call("close")
		t.check("CORE-42",false,source)
		_close_storage(x)
		return
	for index: int in 3:
		var repeated: Dictionary = database.call("execute",sql,[x.first_id,0])
		correct = correct and repeated.ok and repeated.rows==source.rows
	var empty: Dictionary = database.call("execute",sql,[HospitalSnapshots.uuid(),0])
	var bad_read: Dictionary = database.call("execute",sql,[x.first_id])
	var recovered: Dictionary = database.call("execute",sql,[x.first_id,0])
	var begin: Dictionary = database.call("execute","BEGIN IMMEDIATE",[])
	var bad_write: Dictionary = database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[x.first_id,0])
	var duplicate: Dictionary = database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[x.first_id,0,source.rows[0].data])
	var inserted: Dictionary = database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[x.first_id,999999,source.rows[0].data])
	var rollback: Dictionary = database.call("execute","ROLLBACK",[])
	database.call("close")
	var restored: Dictionary = x.store.load_commit(x.world.hospital_id,x.first_id)
	correct = correct and empty.ok and empty.rows.is_empty() and not bad_read.ok and recovered.ok and recovered.rows==source.rows and begin.ok and not bad_write.ok and not duplicate.ok and inserted.ok and rollback.ok and restored.ok and restored.world.freeze()==x.original
	t.check("CORE-42",correct,{"repeated_and_recovered":recovered.ok and recovered.rows==source.rows,"empty_result":empty.ok and empty.rows.is_empty(),"bad_read_rejected":not bad_read.ok,"bad_write_rejected":not bad_write.ok,"duplicate_rejected":not duplicate.ok,"rollback":rollback.ok,"restored":restored.ok})
	_close_storage(x)

func _case_19(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var world: WorldState = x.world
	var original: Dictionary = x.original
	var receipt: Dictionary = x.receipt
	t.check("CORE-19",receipt.ok and int(receipt.world_revision)==int(original.world_revision) and int(world.revision)>int(receipt.world_revision),receipt)
	_close_storage(x)

func _case_20(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var guard: RefCounted = x.guard
	var store: HospitalSnapshots = x.store
	var receipt: Dictionary = x.receipt
	var loaded: Dictionary = x.loaded
	if not loaded.ok: sim.dispose(); guard.call("release"); return
	var first_id: String = receipt.snapshot_id
	var begin: Dictionary = store.begin(world,"storage-session")
	var second: Dictionary = store.wait_for_idle() if begin.ok else begin
	t.check("CORE-20",second.ok and int(second.sequence)>int(receipt.sequence) and store.load_commit(world.hospital_id,first_id).ok,second)
	_close_storage(x)

func _case_21(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var begin: Dictionary = x.store.begin(x.world,"storage-session")
	var second: Dictionary = x.store.wait_for_idle() if begin.ok else begin
	var world: WorldState = x.world
	var sim: HospitalSimulation = x.sim
	var guard: RefCounted = x.guard
	var store: HospitalSnapshots = x.store
	var loaded: Dictionary = x.loaded
	var first_id: String = x.first_id
	var opened: Dictionary = store._connect(world.hospital_id)
	if not opened.ok: sim.dispose(); guard.call("release"); return
	var database: RefCounted = opened.database
	var corrupted: Dictionary = database.call("execute","UPDATE world_chunks SET data=? WHERE snapshot_id=? AND chunk_index=0",["broken".to_utf8_buffer(),second.snapshot_id])
	database.call("close")
	var bad: Dictionary = store.load_commit(world.hospital_id,second.snapshot_id)
	var recovered: Dictionary = store.recover_latest(world.hospital_id)
	var manifest: Dictionary = loaded.manifest.duplicate(true)
	var valid_manifest: Dictionary = store._parse_manifest(JSON.stringify(manifest).to_utf8_buffer(),world.hospital_id,first_id)
	manifest.content_packs = [{"id":"core","version":str(content.catalog.content_version)}]
	var incomplete_identity: Dictionary = store._parse_manifest(JSON.stringify(manifest).to_utf8_buffer(),world.hospital_id,first_id)
	t.check("CORE-21",corrupted.ok and not bad.ok and recovered.ok and recovered.manifest.snapshot_id==first_id and valid_manifest.ok and not incomplete_identity.ok and str(incomplete_identity.get("error","")).contains("核心内容版本"),{"bad_world":bad.get("error",""),"incomplete_content_identity":incomplete_identity})
	_close_storage(x)

func _case_22(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var world: WorldState = x.world
	var store: HospitalSnapshots = x.store
	var opened: Dictionary = store._connect(world.hospital_id)
	var database: RefCounted = opened.database
	var unsealed_id: String = HospitalSnapshots.uuid()
	database.call("execute","BEGIN IMMEDIATE",[])
	var unsealed: Dictionary = database.call("execute","INSERT INTO snapshots VALUES(?,?,?,?,0)",[unsealed_id,99,"{}".to_utf8_buffer(),"0".repeat(64)])
	database.call("close")
	opened = store._connect(world.hospital_id)
	database = opened.database
	var count: Dictionary = database.call("execute","SELECT count(*) AS count FROM snapshots WHERE snapshot_id=?",[unsealed_id])
	database.call("close")
	t.check("CORE-22",unsealed.ok and count.ok and int(count.rows[0].count)==0)
	_close_storage(x)

func _case_23(t, content: HospitalContent) -> void:
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	var acquired: Dictionary = guard.call("acquire")
	var contender: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	var denied: Dictionary = contender.call("acquire")
	var exclusive: bool = acquired.ok and not denied.ok and denied.busy
	guard.call("release")
	var retry: Dictionary = contender.call("acquire")
	t.check("CORE-23",exclusive and retry.ok)
	contender.call("release")

func _case_24(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var store: HospitalSnapshots = x.store
	var library: HospitalLibrary = x.library
	var another: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"另一座测试院",false,content)
	var begin: Dictionary = library.create(another,"library-session")
	var created: Dictionary = store.wait_for_idle() if begin.ok else begin
	var page: Dictionary = library.scan_page({},1)
	t.check("CORE-24",created.ok and page.ok and page.records.size()==1 and not page.records[0].world_verified and not page.done,page)
	_close_storage(x)

func _case_25(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var another: WorldState = _another_hospital(x,content)
	var page: Dictionary = x.library.scan_page({},1)
	var library: HospitalLibrary = x.library
	library.cancel_scan()
	var cancelled: Dictionary = library.scan_page(page.cursor,1)
	t.check("CORE-25",not cancelled.ok and cancelled.get("cancelled",false))
	_close_storage(x)

func _case_26(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var world: WorldState = x.world
	var store: HospitalSnapshots = x.store
	var library: HospitalLibrary = x.library
	var original: Dictionary = x.original
	var first_id: String = x.first_id
	var backup_path: String = "user://acceptance.oghbackup"
	var exported: Dictionary = library.export_backup(world.hospital_id,first_id,backup_path)
	var imported: Dictionary = library.import_backup(backup_path) if exported.ok else exported
	t.check("CORE-26",imported.ok and imported.world.hospital_id!=world.hospital_id and imported.world.facts.display_name==original.display_name and HospitalLedger.balance(imported.world)==24800 and _same(imported.world.facts.rng,original.rng) and store.load_commit(world.hospital_id,first_id).ok,imported.get("error",""))
	_close_storage(x)

func _case_27(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var backup_path: String = "user://acceptance.oghbackup"
	x.library.export_backup(x.world.hospital_id,x.first_id,backup_path)
	var rejected: bool = true
	var source_zip: ZIPReader = ZIPReader.new()
	var zip_readable: bool = source_zip.open(backup_path)==OK
	for name: String in ["../outside.txt","unknown.txt"]:
		var zip: ZIPPacker = ZIPPacker.new()
		var path: String = "user://rejected.oghbackup"
		zip.open(path)
		if zip_readable:
			for allowed_name: String in source_zip.get_files():
				zip.start_file(allowed_name)
				zip.write_file(source_zip.read_file(allowed_name))
				zip.close_file()
		zip.start_file(name)
		zip.write_file("outside".to_utf8_buffer())
		zip.close_file()
		zip.close()
		var inspected: Dictionary = HospitalBackupZip.new().inspect(path)
		rejected = rejected and not inspected.ok
	source_zip.close()
	t.check("CORE-27",zip_readable and rejected and not FileAccess.file_exists("user://outside.txt"))
	_close_storage(x)

func _case_28(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var another: WorldState = _another_hospital(x,content)
	var world: WorldState = x.world
	var library: HospitalLibrary = x.library
	var trashed: Dictionary = library.trash_hospital(another.hospital_id,world.hospital_id)
	var restored: Dictionary = library.restore_hospital(another.hospital_id) if trashed.ok else trashed
	var continued: Dictionary = library.continue_hospital(another.hospital_id) if restored.ok else restored
	t.check("CORE-28",continued.ok and continued.world.hospital_id==another.hospital_id and _same(continued.world.freeze(),another.freeze()),continued.get("error",""))
	_close_storage(x)

func _case_29(t, content: HospitalContent) -> void:
	var x: Dictionary = _storage_fixture(content)
	if x.is_empty(): return
	var world: WorldState = x.world
	var store: HospitalSnapshots = x.store
	var library: HospitalLibrary = x.library
	var first_id: String = x.first_id
	var protected: Dictionary = library.trash_hospital(world.hospital_id,world.hospital_id)
	t.check("CORE-29",not protected.ok and store.load_commit(world.hospital_id,first_id).ok)
	_close_storage(x)

func _case_30(t, content: HospitalContent) -> void:
	var previous: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"原医院",false,content)
	var previous_simulation: HospitalSimulation = HospitalSimulation.new(previous,content)
	var previous_session: GameSession = GameSession.new(previous_simulation,"previous-session")
	var command: GameCommand = GameCommand.new("old-input",previous.hospital_id,previous.revision,"finance_note",BusinessPayload.new({"text":"旧输入","target_amount":1}),"previous-session")
	var new_session: GameSession = GameSession.new(HospitalSimulation.new(HospitalFactory.create(HospitalSnapshots.uuid(),"另一院",false,content),content),"new-session")
	var before: Dictionary = new_session.simulation.world.freeze()
	var panels_rebound: bool = true
	for panel: HospitalActionPanel in [HospitalExpansionPanel.new(),HospitalRemodelPanel.new()]:
		panel.hide()
		panel.attach(previous_simulation,previous_session)
		t.root.add_child(panel)
		panel.set("_draft",{"editing":true})
		panel.attach(new_session.simulation,new_session)
		panels_rebound = panels_rebound and panel.get_child_count()==0 and panel.get("_draft").is_empty() and panel.simulation==new_session.simulation and panel.session==new_session
		panel.show()
		if panel.get_child_count()==0:
			panels_rebound = false
		else:
			var first_control: int = panel.get_child(0).get_instance_id()
			panel.attach(previous_simulation,previous_session)
			panels_rebound = panels_rebound and panel.get_child_count()>0 and panel.get_child(0).get_instance_id()!=first_control and panel.session==previous_session
		panel.queue_free()
	t.check("CORE-30",panels_rebound and new_session.actual_speed()==0 and not new_session.submit(command).accepted and new_session.simulation.world.freeze()==before)
	previous_simulation.dispose()
	new_session.simulation.dispose()
	await t.process_frame

func _case_31(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"视图",true,content)
	var view: HospitalView = HospitalView.new(content)
	t.root.add_child(view)
	var before: Dictionary = world.freeze()
	view.bind(world,1,"view-a")
	view.overview()
	view.update_facts()
	var ticket: Dictionary = view.resource_ticket("actor:starter_doctor_1")
	if ticket.is_empty():
		for id: String in world.ids("actors"):
			ticket = view.resource_ticket("actor:"+id)
			if not ticket.is_empty(): break
	view.set_floor(10000)
	view.zoom_camera(1.2)
	view.overview()
	view.update_facts()
	t.check("CORE-31",world.freeze()==before and view.observed_floor==10000)
	view.queue_free()
	await t.process_frame

func _case_32(t, content: HospitalContent) -> void:
	var x: Dictionary = _view_fixture(t,content)
	var world: WorldState = x.world
	var view: HospitalView = x.view
	var ticket: Dictionary = x.ticket
	view.bind(HospitalFactory.create(HospitalSnapshots.uuid(),"新视图",true,content),1,"view-b")
	t.check("CORE-32",not ticket.is_empty() and not view.accepts_resource(ticket))
	view.queue_free()
	await t.process_frame

func _case_33(t, content: HospitalContent) -> void:
	var x: Dictionary = _view_fixture(t,content)
	var world: WorldState = x.world
	var view: HospitalView = x.view
	var before: Dictionary = x.before
	var resources_ready: bool = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")!=null
	var owner = load("res://game/view/view_resources.gd").new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(owner.MANIFEST))
	var observations: Array = []
	for record: Dictionary in manifest.assets:
		var path: String = "res://"+str(record.asset_path)
		var node: Node3D = owner.acquire(path)
		var valid: bool = node!=null and FileAccess.get_sha256(path)==record.asset_sha256 and FileAccess.get_file_as_bytes(path).size()==int(record.bytes)
		observations.append({"path":path,"source_and_scene_valid":valid})
		resources_ready = resources_ready and valid
		if node!=null:
			owner.release_tree(node)
			node.free()
	var released: Dictionary = owner.usage()
	var first: String = "res://"+str(manifest.assets[0].asset_path)
	var invalid_hash = load("res://game/view/view_resources.gd").new()
	invalid_hash._definitions[first].asset_sha256 = "0".repeat(64)
	var bad_hash: Node3D = invalid_hash.acquire(first)
	var rejected_hash: bool = bad_hash==null and invalid_hash._entries.is_empty() and invalid_hash.usage().instance_users==0 and invalid_hash.errors.size()==1
	if bad_hash!=null:
		invalid_hash.release_tree(bad_hash)
		bad_hash.free()
	var invalid_scene = load("res://game/view/view_resources.gd").new()
	invalid_scene._definitions[first].surface_count += 1
	var bad_scene: Node3D = invalid_scene.acquire(first)
	var rejected_scene: bool = bad_scene==null and invalid_scene._entries.is_empty() and invalid_scene.usage().instance_users==0 and invalid_scene.errors.size()==1
	if bad_scene!=null:
		invalid_scene.release_tree(bad_scene)
		bad_scene.free()
	t.check("CORE-33",resources_ready and not observations.is_empty() and owner.errors.is_empty() and released.shared_scenes==0 and released.instance_users==0 and rejected_hash and rejected_scene and view.bind_error.is_empty() and world.freeze()==before,{"resources":observations,"released":released,"hash_rejection_atomic":rejected_hash,"scene_rejection_atomic":rejected_scene,"bind_error":view.bind_error})
	view.queue_free()
	await t.process_frame

func _case_34(t, content: HospitalContent) -> void:
	var app: Control = await _app_fixture(t)
	if app==null: return
	var panels_ready: bool = app._management_panels.get_child_count()==18
	for panel: Node in app._management_panels.get_children():
		if panel is HospitalActionPanel:
			panels_ready = panels_ready and panel.get_child_count()==0 and panel.simulation==app._simulation and panel.session==app._session
	var environment: HospitalActionPanel = app._management_panels.get_node("environment")
	environment.rebuild()
	panels_ready = panels_ready and environment.get_child_count()==0
	app._submit_business("finance_note",{"text":"首次打开前的便签","target_amount":1})
	app._show_panel("finance")
	await t.process_frame
	var finance: HospitalActionPanel = app._management_panels.get_node("finance")
	var memo: TextEdit = finance.find_children("*","TextEdit",true,false)[0]
	var picker: OptionButton = finance.find_children("*","OptionButton",true,false)[0]
	var current_on_first_open: bool = memo.text=="首次打开前的便签"
	memo.text = "尚未保存的编辑"
	picker.select(picker.item_count-1)
	var selected_id: String = finance.selected(picker)
	app._management_scroll.scroll_vertical = int(app._management_scroll.get_v_scroll_bar().max_value)
	await t.process_frame
	var scroll_position: int = app._management_scroll.scroll_vertical
	app._show_panel("details")
	await t.process_frame
	app._show_panel("finance")
	await t.process_frame
	var retained: bool = is_instance_valid(memo) and is_instance_valid(picker) and memo.text=="尚未保存的编辑" and finance.selected(picker)==selected_id and scroll_position>0 and app._management_scroll.scroll_vertical==scroll_position
	app._show_panel("details")
	app._submit_business("finance_note",{"text":"显式刷新后的便签","target_amount":1})
	finance.rebuild()
	var deferred_refresh: bool = is_instance_valid(memo) and memo.is_inside_tree()
	app._show_panel("finance")
	var refreshed_memo: TextEdit = finance.find_children("*","TextEdit",true,false)[0]
	deferred_refresh = deferred_refresh and refreshed_memo!=memo and refreshed_memo.text=="显式刷新后的便签"
	var before: Dictionary = app._simulation.world.freeze()
	for panel: Node in app._management_panels.get_children():
		app._show_panel(str(panel.name))
		if panel.has_method("rebuild"): panel.call("rebuild")
		panels_ready = panels_ready and panel.get_child_count()>0
	t.check("CORE-34",panels_ready and current_on_first_open and retained and deferred_refresh and app._simulation.world.freeze()==before,{"hidden_bindings":panels_ready,"first_open_current":current_on_first_open,"editing_and_scroll_retained":retained,"hidden_refresh_deferred":deferred_refresh,"scroll_position":scroll_position})
	await _close_app(t,app)

func _case_35(t, content: HospitalContent) -> void:
	var app: Control = await _app_fixture(t)
	if app==null: return
	var before: Dictionary = app._simulation.world.freeze()
	app.size = Vector2(1280,720)
	app._set_ui_scale(2)
	app._show_panel("research")
	await t.process_frame
	t.check("CORE-35",app._ui_scale==2 and app.theme.default_font_size==36 and app._management_scroll.visible and app._management_scroll.get_child_count()>0 and app._simulation.world.freeze()==before)
	await _close_app(t,app)

func _case_36(t, content: HospitalContent) -> void:
	var app: Control = await _app_fixture(t)
	if app==null: return
	var before: Dictionary = app._simulation.world.freeze()
	app._show_panel("expansion")
	app._expansion_panel._preview("build_land",{"floor_id":1,"plot":[0,2]})
	var panel_draft: Dictionary = app._expansion_panel._draft.duplicate(true)
	var preview_label: Label = app._expansion_panel._result
	var original_drafts: Dictionary = app._drafts.duplicate(true)
	app._show_panel("details")
	await t.process_frame
	app._show_panel("expansion")
	var prompted: bool = app._confirm_draft_leave(Callable())
	if prompted:
		app._draft_confirmation.canceled.emit()
		app._draft_confirmation.hide()
	t.check("CORE-36",prompted and not panel_draft.is_empty() and is_instance_valid(preview_label) and app._expansion_panel._result==preview_label and app._expansion_panel._draft==panel_draft and app._drafts==original_drafts and app._simulation.world.freeze()==before and app._leave_operation.is_empty())
	await _close_app(t,app)

func _case_37(t, content: HospitalContent) -> void:
	var species: Dictionary = content.registry.definition("species","S49").duplicate(true)
	species.id = "acceptance.species:SAMPLE"
	var binding: Dictionary = content.registry.definition("treatment_bindings","B_S49_D37_M37").duplicate(true)
	binding.id = "acceptance.species:B_SAMPLE"
	binding.species_id = species.id
	var talent: Dictionary = {}
	for candidate: Dictionary in content.registry.collection("staff_talents"):
		if candidate.species_id!="core:S49": continue
		talent = candidate.duplicate(true)
		talent.id = "acceptance.species:T_SAMPLE"
		talent.species_id = species.id
		break
	var path: String = _pack("acceptance.species",{"species.json":[species],"staff_talents.json":[talent],"treatment_bindings.json":[binding]})
	var loaded: ContentLoadResult = ContentLoader.new().load_packs(PackedStringArray(["res://content/core",path]))
	t.check("CORE-37",loaded.accepted and not loaded.registry.resolve_bindings(species.id,"D37").is_empty(),loaded.errors)

func _case_38(t, content: HospitalContent) -> void:
	var disease: Dictionary = content.registry.definition("diseases","D37").duplicate(true)
	disease.id = "acceptance.disease:CASE"
	var binding: Dictionary = content.registry.definition("treatment_bindings","B_S49_D37_M37").duplicate(true)
	binding.id = "acceptance.disease:B_CASE"
	binding.disease_id = disease.id
	var plans: Array = []
	for plan: Dictionary in content.registry.collection("treatment_plans"):
		if plan.disease_id!="core:D37": continue
		var copy: Dictionary = plan.duplicate(true)
		copy.id = "acceptance.disease:"+str(plan.id).trim_prefix("core:")
		copy.disease_id = disease.id
		plans.append(copy)
	var unlock: Dictionary = content.registry.definition("research","R01").duplicate(true)
	unlock.id = "acceptance.disease:R_CASE"
	unlock.requires = []
	unlock.disease_ids = [disease.id]
	var path: String = _pack("acceptance.disease",{"diseases.json":[disease],"treatment_bindings.json":[binding],"treatment_plans.json":plans,"research.json":[unlock]})
	var loaded: ContentLoadResult = ContentLoader.new().load_packs(PackedStringArray(["res://content/core",path]))
	t.check("CORE-38",loaded.accepted and not loaded.registry.resolve_bindings("S49",disease.id).is_empty() and not loaded.registry.resolve_bindings("S49","D37").is_empty(),loaded.errors)

func _case_39(t, content: HospitalContent) -> void:
	var species: Dictionary = content.registry.definition("species","S49").duplicate(true)
	var all_rejected: bool = not ContentLoader.new().load_packs(PackedStringArray(["res://content/core","res://content/core"])).accepted
	species.id = "acceptance.duplicate:SAMPLE"
	var duplicate_path: String = _pack("acceptance.duplicate",{"species.json":[species,species.duplicate(true)]})
	var wrong_type: String = _pack("acceptance.wrongtype",{"species.json":{}})
	var unknown: String = _pack("acceptance.unknownfile",{"unregistered.json":[]})
	var reasons: Dictionary = {}
	for invalid_path: String in [duplicate_path,wrong_type,unknown]:
		var invalid: ContentLoadResult = ContentLoader.new().load_packs(PackedStringArray(["res://content/core",invalid_path]))
		all_rejected = all_rejected and not invalid.accepted
		reasons[invalid_path] = invalid.errors
	all_rejected = all_rejected and str(reasons[duplicate_path]).contains("重复") and str(reasons[wrong_type]).contains("数组") and str(reasons[unknown]).contains("未注册")
	t.check("CORE-39",all_rejected,reasons)

func _case_40(t, content: HospitalContent) -> void:
	var missing: String = _pack("acceptance.missingdep",{},[{"pack_id":"core","version_range":"*"},{"pack_id":"acceptance.absent","version_range":"*"}])
	var cycle_a: String = _pack("acceptance.cyclea",{},[{"pack_id":"core","version_range":"*"},{"pack_id":"acceptance.cycleb","version_range":"*"}])
	var cycle_b: String = _pack("acceptance.cycleb",{},[{"pack_id":"core","version_range":"*"},{"pack_id":"acceptance.cyclea","version_range":"*"}])
	var missing_result: ContentLoadResult = ContentLoader.new().load_packs(PackedStringArray(["res://content/core",missing]))
	var cycle_result: ContentLoadResult = ContentLoader.new().load_packs(PackedStringArray(["res://content/core",cycle_a,cycle_b]))
	t.check("CORE-40",not missing_result.accepted and not cycle_result.accepted and str(missing_result.errors).contains("缺少依赖") and str(cycle_result.errors).contains("环"),{"missing":missing_result.errors,"cycle":cycle_result.errors})

func _command_fixture(content: HospitalContent, built: bool = false) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"命令输入",false,content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(sim,"current")
	var payload: Dictionary = {"floor_id":1,"room_type_id":"gp","origin":[34,66],"size":[4,4]}
	var command: GameCommand = GameCommand.new("room",world.hospital_id,world.revision,"build_room",BusinessPayload.new(payload),"current")
	if built: session.submit(command)
	return {"world":world,"sim":sim,"session":session,"payload":payload}

func _storage_fixture(content: HospitalContent) -> Dictionary:
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	if not guard.call("acquire").ok:
		push_error("Isolated acceptance profile unavailable")
		return {}
	var store: HospitalSnapshots = HospitalSnapshots.new(content,guard)
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"事务医院",false,content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	var original: Dictionary = world.freeze()
	var begin: Dictionary = store.begin(sim,"storage-session")
	world.facts.display_name = "保存后更名"
	world.touch()
	var receipt: Dictionary = store.wait_for_idle() if begin.ok else begin
	var loaded: Dictionary = store.load_commit(world.hospital_id,receipt.snapshot_id) if receipt.ok else receipt
	if not loaded.ok:
		push_error("Cannot prepare SQLite input: "+JSON.stringify(loaded))
		sim.dispose()
		guard.call("release")
		return {}
	return {"world":world,"sim":sim,"guard":guard,"store":store,"library":HospitalLibrary.new(content,store),"original":original,"receipt":receipt,"loaded":loaded,"first_id":receipt.snapshot_id}

func _another_hospital(x: Dictionary, content: HospitalContent) -> WorldState:
	var another: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"另一座测试院",false,content)
	var begin: Dictionary = x.library.create(another,"library-session")
	if begin.ok: x.store.wait_for_idle()
	return another

func _close_storage(x: Dictionary) -> void:
	x.sim.dispose()
	x.guard.call("release")

func _view_fixture(t, content: HospitalContent) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"视图输入",true,content)
	var view: HospitalView = HospitalView.new(content)
	t.root.add_child(view)
	var before: Dictionary = world.freeze()
	view.bind(world,1,"view-a")
	view.update_facts()
	var ticket: Dictionary = {}
	for id: String in world.ids("actors"):
		ticket = view.resource_ticket("actor:"+id)
		if not ticket.is_empty(): break
	return {"world":world,"view":view,"before":before,"ticket":ticket}

func _app_fixture(t) -> Control:
	var app: Control = load("res://game/app/main.tscn").instantiate()
	t.root.add_child(app)
	app.set_process(false)
	await t.process_frame
	if app._simulation!=null: return app
	push_error("Actual application did not activate an isolated hospital")
	app.queue_free()
	return null

func _close_app(t, app: Control) -> void:
	if app._snapshots.busy(): app._snapshots.wait_for_idle()
	app._guard.call("release")
	app.queue_free()
	await t.process_frame

func _same(first: Variant, second: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(first,"",true,true))==JSON.parse_string(JSON.stringify(second,"",true,true))

func _pack(identity: String, collections: Dictionary, dependencies: Array = [{"pack_id":"core","version_range":"*"}]) -> String:
	var directory: String = "user://case-packs/"+identity
	DirAccess.make_dir_recursive_absolute(directory)
	var files: Array = []
	for filename: String in collections:
		var file: FileAccess = FileAccess.open(directory.path_join(filename),FileAccess.WRITE)
		file.store_string(JSON.stringify(collections[filename],"",true,true))
		file.close()
		files.append({"path":filename,"sha256":FileAccess.get_sha256(directory.path_join(filename))})
	var manifest: FileAccess = FileAccess.open(directory.path_join("manifest.json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"pack_id":identity,"version":"1.0.0","schema_version":100,"min_game_version":"1.0.0","requires":dependencies,"files":files}))
	manifest.close()
	return directory
