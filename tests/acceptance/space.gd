extends RefCounted

const ClinicalStep = preload("res://tests/acceptance/clinical_step.gd")

const CASES: Dictionary = {
	"SPACE-01":"docs/design/12-implementation-plan.md §11 8.1/8.3；合法房壳预览只读，创建与整数付款原子一致",
	"SPACE-02":"docs/design/12-implementation-plan.md §11 8.1/8.4；未购地、断格、孔洞、小房失败原子",
	"SPACE-03":"docs/design/04-technical.md §3；无关修订可提交，实质报价变化保留原世界",
	"SPACE-04":"docs/specs/26-10/2026-10-15-stage04-stage24.md 统一事实；同命令只创建扣费一次",
	"SPACE-05":"docs/design/12-implementation-plan.md §11 8.3/8.4；唯一出口与资金不足均不可部分提交",
	"SPACE-06":"docs/design/12-implementation-plan.md §11 8.3；移动保身份，未用全退/已用八折，撤销有边界",
	"SPACE-07":"docs/design/04-technical.md §6；种族与症状逐轴并集，真实宽深高分别校验",
	"SPACE-08":"docs/design/04-technical.md §13；身体、工具、伸展和真实离位共同决定设施占用",
	"SPACE-09":"docs/design/04-technical.md §6 全院请求；真实人数FIFO，替换保序，只读预览不耗额度",
	"SPACE-10":"docs/design/04-technical.md §6 局部更新；真实阻挡/层/修订及恢复不串合法路线",
	"SPACE-11":"docs/design/11-growth-arrivals-recruitment.md §3；共边地面购入仅授草地，重复/非邻接不付款",
	"SPACE-12":"docs/design/11-growth-arrivals-recruitment.md §3；选梯主锚点h+1，补块须已有实完模块",
	"SPACE-13":"docs/design/11-growth-arrivals-recruitment.md §3；正下层实际Room内格才构成建筑",
	"SPACE-14":"docs/design/11-growth-arrivals-recruitment.md §3；真实装修工/正常SE02确认唯一付费单，未完无楼面",
	"SPACE-15":"docs/data/balance.json floors.section_pricing；2/3/4/5/10F费用和标准量封顶不封层",
	"SPACE-16":"docs/design/11-growth-arrivals-recruitment.md §3；真实到场施工，完工一次交付空板",
	"SPACE-17":"docs/design/11-growth-arrivals-recruitment.md §3；主动暂停及恢复保留原单、付款、贡献和余量",
	"SPACE-18":"docs/design/11-growth-arrivals-recruitment.md §3；换人/下层Room与合法工作点变化不重付清进度",
	"SPACE-19":"docs/design/11-growth-arrivals-recruitment.md §3；冻结比例一次退款，已完结构不随下层Room撤销",
	"SPACE-20":"docs/design/11-growth-arrivals-recruitment.md §8/§9；10000层按高度区间与实际布局稀疏恢复",
	"SPACE-21":"docs/design/11-growth-arrivals-recruitment.md §4；初装电梯仅1F单站、一份主设备与空车位置",
	"SPACE-22":"docs/design/11-growth-arrivals-recruitment.md §4；第二站免费硬件须明确安装，完整井道/端口不缺板",
	"SPACE-23":"docs/design/11-growth-arrivals-recruitment.md §4；净宽高安全余量及真实舱内组合准入",
	"SPACE-24":"docs/design/11-growth-arrivals-recruitment.md §4.1；报价不取票，实际整组到齐才领当前段票",
	"SPACE-25":"docs/design/11-growth-arrivals-recruitment.md §4.1；票序公平且不因职业、视图或报价插队",
	"SPACE-26":"docs/design/11-growth-arrivals-recruitment.md §4.1；同刻max(A,P)+E+G与未知出口等待",
	"SPACE-27":"docs/design/11-growth-arrivals-recruitment.md §4.1；取消接人保留已启动空车段与恢复余量",
	"SPACE-28":"docs/design/11-growth-arrivals-recruitment.md §4.1/§8；乘梯与地面位置互斥，恢复安全离舱",
	"SPACE-29":"docs/design/11-growth-arrivals-recruitment.md §4；途中故障先安全到站，只保留每层4秒缓降",
	"SPACE-30":"docs/design/11-growth-arrivals-recruitment.md §4；困人拆改失败，正常往返和同层床条件不放宽",
	"SPACE-31":"docs/design/11-growth-arrivals-recruitment.md §5；观察只切投影，同XY异层与10000F本地高度隔离",
	"SPACE-32":"docs/design/08-hospital-life.md §10；草案只读，确认才阻止新预约，每成员一份安排",
	"SPACE-33":"docs/design/08-hospital-life.md §10；目标不预留，实际疏散终点无身体重叠，当前可用不自动应用，失败保留安排",
	"SPACE-34":"docs/design/08-hospital-life.md §10；取消只撤本安排原因，不恢复过时开放开关",
	"SPACE-35":"docs/design/08-hospital-life.md §10/§11、07-clinical-team.md §8.1；真实门诊安全转移保原票、证据、Attempt、耗材和余量，双床职责位旋转与保存后仍可达",
	"SPACE-36":"docs/design/08-hospital-life.md §11、07-clinical-team.md §8.1；改建中沿原病例完成护理、查房、唯一结算和实际释放",
	"SPACE-37":"docs/design/08-hospital-life.md §11；整组旋转跨层搬迁保原身份、状态、成本与工作引用",
	"SPACE-38":"docs/design/08-hospital-life.md §11；表面最终归属、重叠与80%替换退款只结算一次",
	"SPACE-39":"docs/design/08-hospital-life.md §12；九内置图只记录相对布局，重复或缺床链接拒绝",
	"SPACE-40":"docs/design/08-hospital-life.md §12；库存默认正常优先再稳定ID，复用原资产状态不复制",
	"SPACE-41":"docs/design/08-hospital-life.md §12；完整蓝图与相关库存报价检查，失败不部分放置付款",
	"SPACE-42":"docs/design/08-hospital-life.md §12；美化仍走真实工人工具，每单不超64，布局工单同事务",
	"SPACE-43":"docs/design/08-hospital-life.md §14；共享蓝图修订原子保存，已确认安排独立于外部蓝图",
	"SPACE-44":"docs/design/08-hospital-life.md §13/§14；部分保养与改建安排共同恢复，原任务接续且应用不重付",
	"SPACE-45":"docs/design/01-simulation.md §6；上门人员乘梯中取消未开工保养，原乘梯与读档保留，实际返1F离院",
	"SPACE-46":"docs/design/04-technical.md §6；同体型通行组换成员不继承预约豁免，变更配位与真实阻挡立即生效",
	"SPACE-47":"docs/design/08-hospital-life.md §11；整备房间按真实格形判断身体相交，不将凹角空白当房间"
}

var content: HospitalContent
var _sequence: int = 0

func run(t) -> void:
	content = HospitalContent.new()
	for case_id: String in CASES:
		if not t.wants(case_id): continue
		t.begin_case(case_id)
		if not content.error.is_empty():
			t.check(case_id,false,{"content_error":content.error})
			continue
		var result: Dictionary = call("_case_"+case_id.right(2),t)
		t.check(case_id,bool(result.get("ok",false)),result.get("details"))

func _case_01(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var draft: Dictionary = _room("room_a",[35,68])
	var before: Dictionary = sim.world.freeze()
	var quote: Dictionary = sim.services.building.preview(sim.world,draft)
	var readonly: bool = sim.world.freeze()==before
	draft.quote = quote.get("quote",{})
	var paid_before: int = HospitalLedger.balance(sim.world)
	var result: CommandResult = _command(sim,"build_room",draft)
	var room: Dictionary = sim.world.facts.rooms.get("room_a",{})
	var walls: Array = BuildGeometry.room_walls(room) if result.accepted else []
	var rectangle_walls: Array = BuildGeometry.room_walls({"origin":[35,68],"size":[4,4]})
	var expected_walls: Array = [{"axis":"x","line":68,"low":35,"high":39},{"axis":"x","line":72,"low":35,"high":39},{"axis":"y","line":35,"low":68,"high":72},{"axis":"y","line":39,"low":68,"high":72}]
	return _done(sim,readonly and quote.get("ok",false) and result.accepted and room.get("floor_id")==1 and HospitalLedger.balance(sim.world)==paid_before-int(quote.get("price",0)) and _doors(sim.world,"room_a").size()==1 and walls==expected_walls and rectangle_walls==expected_walls,{"quote":_public_quote(quote),"result":result.to_record(),"walls":walls,"rectangle_walls":rectangle_walls})

func _case_02(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var invalid: Array = [_room("unowned",[2,2]),_room("small",[35,68],[1,1]),{"kind":"build_room","id":"split","room_type_id":"gp","floor_id":1,"cells":[[35,68],[36,68],[48,78]],"door":{"definition_id":"DR01","edge":"south","offset":0}}]
	var ring: Array = []
	for y: int in range(68,74):
		for x: int in range(35,41):
			if not (x==38 and y==71): ring.append([x,y])
	invalid.append({"kind":"build_room","id":"hole","room_type_id":"gp","floor_id":1,"cells":ring,"door":{"definition_id":"DR01","edge":"south","offset":1}})
	var ok: bool = true
	var reasons: Array = []
	for draft: Dictionary in invalid:
		var before: Dictionary = sim.world.freeze()
		var quote: Dictionary = sim.services.building.preview(sim.world,draft)
		var result: CommandResult = _command(sim,"build_room",draft)
		ok = ok and not quote.get("ok",false) and not result.accepted and before==sim.world.freeze() and not result.reason.is_empty()
		reasons.append(result.reason)
	return _done(sim,ok,reasons)

func _case_03(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var draft: Dictionary = _room("stable_room",[35,68])
	var quote: Dictionary = sim.services.building.preview(sim.world,draft)
	draft.quote = quote.get("quote",{})
	var old_revision: int = sim.world.revision
	sim.step()
	var unrelated: CommandResult = _command(sim,"build_room",draft,"",old_revision)
	var changed: Dictionary = _room("changed_room",[47,68])
	var original: Dictionary = sim.services.building.preview(sim.world,changed)
	changed.quote = original.get("quote",{})
	changed.size = [5,4]
	var before: Dictionary = sim.world.freeze()
	var rejected: CommandResult = _command(sim,"build_room",changed)
	return _done(sim,unrelated.accepted and not rejected.accepted and rejected.code=="material_change" and before==sim.world.freeze(),{"unrelated":unrelated.to_record(),"changed":rejected.to_record()})

func _case_04(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var draft: Dictionary = _room("once_room",[35,68])
	var first: CommandResult = _command(sim,"build_room",draft,"space_duplicate_room")
	var after: Dictionary = sim.world.freeze()
	var second: CommandResult = _command(sim,"build_room",draft,"space_duplicate_room")
	return _done(sim,first.accepted and second.accepted and after==sim.world.freeze() and sim.world.facts.rooms.size()==1,{"first":first.to_record(),"second":second.to_record()})

func _case_05(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var built: CommandResult = _command(sim,"build_room",_room("exit_room",[35,68]))
	var door: Dictionary = _doors(sim.world,"exit_room")[0] if built.accepted else {}
	var before: Dictionary = sim.world.freeze()
	var exit_result: CommandResult = _command(sim,"build_demolish",{"target_id":door.get("id","missing")})
	var exit_atomic: bool = not exit_result.accepted and sim.world.freeze()==before
	var poor: HospitalSimulation = _fixture(false,0)
	var poor_before: Dictionary = poor.world.freeze()
	var money: CommandResult = _command(poor,"build_facility",{"definition_id":"SE02","cell":[45,75],"floor_id":1})
	var money_atomic: bool = not money.accepted and poor_before==poor.world.freeze()
	poor.dispose()
	return _done(sim,built.accepted and exit_atomic and money_atomic,{"exit":exit_result.to_record(),"money":money.to_record()})

func _case_06(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var first: CommandResult = _command(sim,"build_facility",{"id":"asset_a","definition_id":"SE02","cell":[45,75],"floor_id":1})
	var original: Dictionary = sim.world.facts.facilities.get("asset_a",{}).duplicate(true)
	var cash: int = HospitalLedger.balance(sim.world)
	var move: CommandResult = _command(sim,"build_move",{"target_id":"asset_a","cell":[48,75],"floor_id":1})
	var moved: bool = move.accepted and sim.world.facts.facilities.asset_a.id=="asset_a" and sim.world.facts.facilities.asset_a.paid_cost==original.get("paid_cost") and cash==HospitalLedger.balance(sim.world)
	var undo: CommandResult = _command(sim,"build_undo",{})
	var restored: bool = undo.accepted and sim.world.facts.facilities.get("asset_a",{})==original
	var unused_cash: int = HospitalLedger.balance(sim.world)
	var unused: CommandResult = _command(sim,"build_demolish",{"target_id":"asset_a"})
	var unused_refund: bool = unused.accepted and HospitalLedger.balance(sim.world)-unused_cash==int(original.get("paid_cost",-1))
	var used_build: CommandResult = _command(sim,"build_facility",{"id":"asset_used","definition_id":"SE02","cell":[45,75],"floor_id":1})
	if used_build.accepted: sim.world.facts.facilities.asset_used.used = true # A previously used physical asset is the fixture input.
	var used_cash: int = HospitalLedger.balance(sim.world)
	var used: CommandResult = _command(sim,"build_demolish",{"target_id":"asset_used"},"space_used_refund")
	var after: Dictionary = sim.world.freeze()
	var repeated: CommandResult = _command(sim,"build_demolish",{"target_id":"asset_used"},"space_used_refund")
	return _done(sim,first.accepted and moved and restored and unused_refund and used.accepted and HospitalLedger.balance(sim.world)-used_cash==int(original.get("paid_cost",0))*80/100 and repeated.accepted and after==sim.world.freeze(),{"move":move.to_record(),"undo":undo.to_record(),"used":used.to_record()})

func _case_07(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var built: CommandResult = _command(sim,"build_room",_room("body_room",[35,68],[8,8]))
	var door: Dictionary = _doors(sim.world,"body_room")[0] if built.accepted else {}
	var types: Array = ["S49","S21","S53","S01"]
	var ok: bool = built.accepted
	var details: Array = []
	for species_id: String in types:
		var actor: Dictionary = _actor("body_"+species_id,species_id,[48,80])
		var quote: Dictionary = sim.space.door_quote(sim.world,actor,1,door) if built.accepted else {}
		var body: Dictionary = content.definition("species",species_id).body
		ok = ok and quote.get("ok",false) and float(quote.get("clear_width_m",0))+0.0001>=maxf(float(body.width_m),float(body.depth_m))+0.10 and float(quote.get("clear_height_m",0))+0.0001>=float(body.height_m)+0.10
		details.append({"species":species_id,"quote":quote})
	var enlarged: Dictionary = _actor("symptom","S08",[48,80])
	enlarged.body_binding_id = "B_S08_D04_M04"
	var original_body: Dictionary = content.definition("species","S08").body
	var symptom: Dictionary = content.definition("treatment_bindings","B_S08_D04_M04").symptom_envelope
	var effective: Dictionary = sim.space.body(enlarged)
	for axis: String in ["width_m","depth_m","height_m"]:
		ok = ok and is_equal_approx(float(effective.get(axis,0)),maxf(float(original_body[axis]),float(symptom[axis])))
	_add_actor(sim,"tall_route","S01",[48,80])
	var high_route: Dictionary = sim.space.route(sim.world,"tall_route",1,[37,70],[],{},true)
	var low_world: WorldState = WorldState.new(sim.world.freeze())
	low_world.facts.floors.height_intervals[0].height_m = 3.0
	low_world.touch()
	var low_route: Dictionary = sim.space.route(low_world,"tall_route",1,[37,70],[],{},true)
	var high_again: Dictionary = sim.space.route(sim.world,"tall_route",1,[37,70],[],{},true)
	ok = ok and high_route.ok and not low_route.ok and high_again.ok
	sim.world.facts.floors.height_intervals[0].height_m = 3.0
	sim.world.touch()
	var tall: Dictionary = sim.space.door_quote(sim.world,_actor("tall","S01",[48,80]),1,door) if built.accepted else {}
	var human: Dictionary = sim.space.door_quote(sim.world,_actor("human","S49",[48,80]),1,door) if built.accepted else {}
	return _done(sim,ok and not tall.get("ok",true) and human.get("ok",false),{"bodies":details,"effective":effective,"tall":tall,"human":human,"high_route":high_route.ok,"low_route":low_route.ok,"high_again":high_again.ok})

func _case_08(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var made: CommandResult = _command(sim,"build_facility",{"id":"seat","definition_id":"FUR06","floor_id":1,"cell":[44,72]})
	_add_actor(sim,"user","S53",[35,82])
	_add_actor(sim,"operator","S01",[39,82])
	var before: Dictionary = sim.world.freeze()
	var quote: Dictionary = sim.space.facility_quote(sim.world,"seat","user",["operator"])
	var readonly: bool = sim.world.freeze()==before
	var blocker: CommandResult = _command(sim,"build_facility",{"id":"blocker","definition_id":"SE02","floor_id":1,"cell":[46,72]})
	var obstructed: Dictionary = sim.space.facility_quote(sim.world,"seat","user",["operator"])
	var removed: CommandResult = _command(sim,"build_demolish",{"target_id":"blocker"})
	var approached: bool = false
	if quote.get("ok",false) and quote.has("patient_cell"):
		sim.space.request_move(sim.world,"user",1,quote.patient_cell)
		approached = _wait(sim,func() -> bool: return sim.space.at(sim.world,"user",1,quote.patient_cell) and not sim.world.facts.moves.has("user"),400)
	var reserved: String = sim.space.reserve_facility(sim.world,"seat","user","user",["operator"])
	var retained: bool = false
	var released: bool = false
	if reserved.is_empty() and sim.world.facts.adaptations.has("seat"):
		sim.space.release_adaptations(sim.world)
		retained = sim.world.facts.adaptations.has("seat")
		sim.space.request_move(sim.world,"user",1,[35,82])
		_wait(sim,func() -> bool: return sim.space.at(sim.world,"user",1,[35,82]) and not sim.world.facts.moves.has("user"),500)
		sim.space.release_adaptations(sim.world)
		released = not sim.world.facts.adaptations.has("seat")
	var exit_safety: Dictionary = _facility_exit_contract()
	return _done(sim,made.accepted and readonly and quote.get("ok",false) and blocker.accepted and not obstructed.get("ok",true) and removed.accepted and approached and retained and released and exit_safety.ok,{"quote":quote,"obstructed":obstructed,"reservation":reserved,"approached":approached,"retained":retained,"released":released,"exit_safety":exit_safety})

func _facility_exit_contract() -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var made: CommandResult = _command(sim,"build_facility",{"id":"seat","definition_id":"FUR06","floor_id":1,"cell":[44,72]})
	_add_actor(sim,"user","S49",[49,82])
	_add_actor(sim,"bystander","S49",[42,73])
	# A legal one-cell passage is the bystander's only exit. The seat remains
	# its base size; its proposed patient region would close that passage.
	for y: int in range(64,96):
		if y not in [72,73]: sim.world.facts.floors.overrides["1"].blocked.append([44,y])
	sim.world.touch()
	var exit: Array = sim.space.exit_cell(sim.world,sim.world.facts.actors.bystander)
	var before_route: Dictionary = sim.space.route(sim.world,"bystander",1,exit,[],{},true)
	var before: Dictionary = sim.world.freeze()
	var trapped: Dictionary = sim.space.facility_quote(sim.world,"seat","user")
	var warm_trapped: bool = true
	for index: int in 16:
		var repeated: Dictionary = sim.space.facility_quote(sim.world,"seat","user")
		warm_trapped = warm_trapped and not repeated.get("ok",true) and str(repeated.get("reason","")).contains("安全出口")
	var readonly: bool = before==sim.world.freeze()
	sim.world.facts.floors.overrides["1"].blocked.erase([44,78])
	sim.world.touch()
	before = sim.world.freeze()
	var detour: Dictionary = sim.space.facility_quote(sim.world,"seat","user")
	var warm_detour: bool = true
	for index: int in 16: warm_detour = warm_detour and sim.space.facility_quote(sim.world,"seat","user").get("ok",false)
	readonly = readonly and before==sim.world.freeze()
	return _done(sim,made.accepted and before_route.ok and not trapped.get("ok",true) and str(trapped.get("reason","")).contains("安全出口") and detour.get("ok",false) and detour.get("footprint",[])==[2,1] and warm_trapped and warm_detour and readonly,{"before_route_ok":before_route.ok,"trapped":trapped,"detour":detour,"warm_trapped":warm_trapped,"warm_detour":warm_detour,"readonly":readonly})

func _case_09(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	for index: int in 10:
		var id: String = "fifo_%02d"%index
		_add_actor(sim,id,"S49",[33+index*2,80])
		sim.space.request_move(sim.world,id,1,[33+index*2,84])
	var sequence: int = int(sim.world.facts.moves.fifo_00.request_sequence)
	sim.space.request_move(sim.world,"fifo_00",1,[33,85])
	var before: Dictionary = sim.world.freeze()
	var preview: Dictionary = sim.services.building.preview(sim.world,_room("preview_only",[35,66]))
	var readonly: bool = before==sim.world.freeze()
	var request_count: int = int(sim.world.facts.get("move_request_next",0))
	sim.step()
	var processed: Array = []
	var pending: Array = []
	for id: String in sim.world.ids("moves"):
		if sim.world.facts.moves[id].get("route_pending",false): pending.append(id)
		else: processed.append(id)
	var expected: Array = []
	for index: int in 8: expected.append("fifo_%02d"%index)
	return _done(sim,preview.get("ok",false) and readonly and sequence==1 and request_count==10 and processed==expected and pending==["fifo_08","fifo_09"] and sim.world.facts.moves.fifo_00.request_sequence==sequence,{"processed":processed,"pending":pending,"request_count":request_count})

func _case_10(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_history_height(sim,2)
	_add_actor(sim,"walker","S49",[35,75])
	var first: Dictionary = sim.space.route(sim.world,"walker",1,[51,75])
	var first_estimates: bool = _travel_quote_contract(sim,16)
	var alternate: HospitalSimulation = HospitalSimulation.new(WorldState.new(sim.world.freeze()),content)
	var alternate_built: CommandResult = _command(alternate,"build_facility",{"id":"candidate_obstacle","definition_id":"SE02","floor_id":1,"cell":[43,75]})
	var candidate_route: Dictionary = sim.space.route(alternate.world,"walker",1,[51,75])
	var candidate_fresh: Dictionary = HospitalSpace.new(content).route(alternate.world,"walker",1,[51,75])
	var back_to_original: Dictionary = sim.space.route(sim.world,"walker",1,[51,75])
	var worlds_isolated: bool = alternate_built.accepted and candidate_route.ok and candidate_route.path==candidate_fresh.path and back_to_original.path==first.path and int(first.walking_distance)==16 and int(candidate_route.walking_distance)==18
	alternate.dispose()
	var built: CommandResult = _command(sim,"build_facility",{"id":"route_obstacle","definition_id":"SE02","floor_id":1,"cell":[43,75]})
	var changed: Dictionary = sim.space.route(sim.world,"walker",1,[51,75])
	var changed_estimates: bool = _travel_quote_contract(sim,18)
	var fresh: Dictionary = HospitalSpace.new(content).route(sim.world,"walker",1,[51,75])
	var upstairs: CommandResult = _command(sim,"build_facility",{"id":"upper_only","definition_id":"SE02","floor_id":2,"cell":[44,76]})
	var after_other: Dictionary = sim.space.route(sim.world,"walker",1,[51,75])
	sim.space.request_move(sim.world,"walker",1,[51,75])
	var restored: WorldState = WorldState.new(sim.world.freeze())
	var restored_space: HospitalSpace = HospitalSpace.new(content)
	var same_queue: bool = restored.facts.moves==sim.world.facts.moves
	var restored_route: Dictionary = restored_space.route(restored,"walker",1,[51,75])
	var dynamic: HospitalSimulation = _fixture()
	_add_actor(dynamic,"walker","S49",[35,70])
	var requested: String = dynamic.space.request_move(dynamic.world,"walker",1,[45,70])
	_movement_tick(dynamic)
	var established: bool = dynamic.world.facts.moves.has("walker") and not dynamic.world.facts.moves.walker.get("route_pending",true)
	_add_actor(dynamic,"stationary_blocker","S49",[40,70])
	var previous: Array = dynamic.world.facts.actors.walker.location.cell.duplicate()
	var travelled: float = 0.0
	var physical: bool = true
	var same_target: bool = true
	var maximum_step: float = float(content.balance.movement_speeds["1"])*WorldState.TICK_SECONDS
	for index: int in 160:
		var before_rect: Rect2 = dynamic.space.body_rectangle(dynamic.world.facts.actors.walker)
		_movement_tick(dynamic)
		var current: Array = dynamic.world.facts.actors.walker.location.cell
		var distance: float = Vector2(float(previous[0]),float(previous[1])).distance_to(Vector2(float(current[0]),float(current[1])))
		travelled += distance
		var after_rect: Rect2 = dynamic.space.body_rectangle(dynamic.world.facts.actors.walker)
		var blocker_rect: Rect2 = dynamic.space.body_rectangle(dynamic.world.facts.actors.stationary_blocker)
		physical = physical and distance<=maximum_step+0.0001 and not BodySweep.intersects(before_rect,after_rect,blocker_rect,blocker_rect) and not after_rect.intersects(blocker_rect,false)
		if dynamic.world.facts.moves.has("walker"):
			same_target = same_target and dynamic.world.facts.moves.walker.target_floor==1 and dynamic.world.facts.moves.walker.target_cell==[45,70]
		previous = current.duplicate()
	var arrived: bool = dynamic.space.at(dynamic.world,"walker",1,[45,70]) and not dynamic.world.facts.moves.has("walker")
	var blocker_kept: bool = dynamic.space.at(dynamic.world,"stationary_blocker",1,[40,70]) and not dynamic.world.facts.moves.has("stationary_blocker")
	var dynamic_details: Dictionary = {"request_reason":requested,"established_before_blocker":established,"arrived":arrived,"physical_sweeps":physical,"original_target_preserved":same_target,"blocker_stationary":blocker_kept,"travelled":travelled,"final_cell":previous}
	var dynamic_ok: bool = requested.is_empty() and established and arrived and physical and same_target and blocker_kept and travelled>10.0
	dynamic.dispose()
	var wide: HospitalSimulation = _fixture()
	_add_actor(wide,"wide_walker","S06",[35,70])
	wide.world.facts.actors.wide_walker.body_binding_id = "B_S06_D04_M04"
	wide.space.sync_actor(wide.world,"wide_walker")
	var wide_requested: String = wide.space.request_move(wide.world,"wide_walker",1,[45,70])
	_movement_tick(wide)
	var wide_established: bool = wide.world.facts.moves.has("wide_walker") and not wide.world.facts.moves.wide_walker.get("route_pending",true)
	_add_staff(wide,"wide_blocker","doctor",[40,70])
	wide.world.facts.staff.wide_blocker.on_shift = false
	var wide_previous: Array = wide.world.facts.actors.wide_walker.location.cell.duplicate()
	var wide_travelled: float = 0.0
	var wide_physical: bool = true
	var wide_same_target: bool = true
	var wide_two_cell_body: bool = wide.space.clearance(wide.world.facts.actors.wide_walker)==2
	for index: int in 160:
		var before_rect: Rect2 = wide.space.body_rectangle(wide.world.facts.actors.wide_walker)
		var blocker_before: Rect2 = wide.space.body_rectangle(wide.world.facts.actors.wide_blocker)
		_movement_tick(wide)
		var current: Array = wide.world.facts.actors.wide_walker.location.cell
		var distance: float = Vector2(float(wide_previous[0]),float(wide_previous[1])).distance_to(Vector2(float(current[0]),float(current[1])))
		wide_travelled += distance
		var after_rect: Rect2 = wide.space.body_rectangle(wide.world.facts.actors.wide_walker)
		var blocker_after: Rect2 = wide.space.body_rectangle(wide.world.facts.actors.wide_blocker)
		wide_physical = wide_physical and distance<=maximum_step+0.0001 and not BodySweep.intersects(before_rect,after_rect,blocker_before,blocker_after) and not after_rect.intersects(blocker_after,false)
		if wide.world.facts.moves.has("wide_walker"):
			wide_same_target = wide_same_target and wide.world.facts.moves.wide_walker.target_floor==1 and wide.world.facts.moves.wide_walker.target_cell==[45,70]
		wide_previous = current.duplicate()
	var wide_arrived: bool = wide.space.at(wide.world,"wide_walker",1,[45,70]) and not wide.world.facts.moves.has("wide_walker")
	var wide_blocker_yielded: bool = wide.world.facts.actors.wide_blocker.location.cell!=[40,70] or wide.world.facts.moves.has("wide_blocker")
	var wide_details: Dictionary = {"request_reason":wide_requested,"established_before_blocker":wide_established,"two_cell_body":wide_two_cell_body,"arrived":wide_arrived,"physical_sweeps":wide_physical,"original_target_preserved":wide_same_target,"idle_staff_yielded":wide_blocker_yielded,"travelled":wide_travelled,"final_cell":wide_previous}
	var wide_ok: bool = wide_requested.is_empty() and wide_established and wide_two_cell_body and wide_arrived and wide_physical and wide_same_target and wide_blocker_yielded and wide_travelled>10.0
	wide.dispose()
	var protected: HospitalSimulation = _fixture()
	_add_actor(protected,"protected_walker","S06",[35,70])
	protected.world.facts.actors.protected_walker.body_binding_id = "B_S06_D04_M04"
	protected.space.sync_actor(protected.world,"protected_walker")
	_add_staff(protected,"busy_blocker","doctor",[40,70])
	_add_staff(protected,"training_mentor","doctor",[38,70])
	protected.world.facts.training_jobs = {"training_job":{"staff_id":"trainee","mentor_id":"training_mentor","state":"working"}}
	protected.world.facts.sessions["busy_session"] = {"staff_ids":["busy_blocker"]}
	var protected_requested: String = protected.space.request_move(protected.world,"protected_walker",1,[45,70])
	_movement_tick(protected)
	var protected_established: bool = protected.world.facts.moves.has("protected_walker") and not protected.world.facts.moves.protected_walker.get("route_pending",true)
	var protected_previous: Array = protected.world.facts.actors.protected_walker.location.cell.duplicate()
	var protected_physical: bool = true
	var protected_goal_preserved: bool = true
	for index: int in 100:
		var before_rect: Rect2 = protected.space.body_rectangle(protected.world.facts.actors.protected_walker)
		_movement_tick(protected)
		var current: Array = protected.world.facts.actors.protected_walker.location.cell
		var after_rect: Rect2 = protected.space.body_rectangle(protected.world.facts.actors.protected_walker)
		var busy_rect: Rect2 = protected.space.body_rectangle(protected.world.facts.actors.busy_blocker)
		protected_physical = protected_physical and not BodySweep.intersects(before_rect,after_rect,busy_rect,busy_rect) and not after_rect.intersects(busy_rect,false)
		var current_move: Dictionary = protected.world.facts.moves.get("protected_walker",{})
		protected_goal_preserved = protected_goal_preserved and (not current_move.is_empty() and current_move.target_floor==1 and current_move.target_cell==[45,70] or current_move.is_empty() and protected.space.at(protected.world,"protected_walker",1,[45,70]))
		protected_previous = current.duplicate()
	var protected_not_pushed: bool = protected.space.at(protected.world,"busy_blocker",1,[40,70]) and not protected.world.facts.moves.has("busy_blocker")
	var mentor_not_pushed: bool = protected.space._staff_has_movement_responsibility(protected.world,"training_mentor")
	var protected_details: Dictionary = {"request_reason":protected_requested,"established":protected_established,"safe_sweeps":protected_physical,"busy_staff_not_pushed":protected_not_pushed,"training_mentor_protected":mentor_not_pushed,"patient_unchanged_goal":protected_goal_preserved,"patient_location":protected_previous}
	var protected_ok: bool = protected_requested.is_empty() and protected_established and protected_physical and protected_not_pushed and mentor_not_pushed and protected_details.patient_unchanged_goal
	protected.dispose()
	var courtesy: HospitalSimulation = _fixture()
	_add_actor(courtesy,"head_on_a","S49",[34,92])
	_add_actor(courtesy,"head_on_b","S49",[34,88])
	var first_request: String = courtesy.space.request_move(courtesy.world,"head_on_a",1,[34,86])
	var second_request: String = courtesy.space.request_move(courtesy.world,"head_on_b",1,[34,94])
	var fractional_yield: bool = false
	var safe_sweeps: bool = true
	var courtesy_targets: bool = true
	for index: int in 400:
		var before_a: Rect2 = courtesy.space.body_rectangle(courtesy.world.facts.actors.head_on_a)
		var before_b: Rect2 = courtesy.space.body_rectangle(courtesy.world.facts.actors.head_on_b)
		_movement_tick(courtesy)
		var after_a: Rect2 = courtesy.space.body_rectangle(courtesy.world.facts.actors.head_on_a)
		var after_b: Rect2 = courtesy.space.body_rectangle(courtesy.world.facts.actors.head_on_b)
		safe_sweeps = safe_sweeps and not BodySweep.intersects(before_a,after_a,before_b,after_b) and not after_a.intersects(after_b,false) and before_a.position.distance_to(after_a.position)<=maximum_step+0.0001 and before_b.position.distance_to(after_b.position)<=maximum_step+0.0001
		for actor_id: String in ["head_on_a","head_on_b"]:
			var movement: Dictionary = courtesy.world.facts.moves.get(actor_id,{})
			if movement.is_empty(): continue
			courtesy_targets = courtesy_targets and movement.target_floor==1 and movement.target_cell==([34,86] if actor_id=="head_on_a" else [34,94])
			var cell: Array = courtesy.world.facts.actors[actor_id].location.cell
			if movement.get("yielding",false) and (not is_equal_approx(float(cell[0]),roundf(float(cell[0]))) or not is_equal_approx(float(cell[1]),roundf(float(cell[1])))):
				fractional_yield = true
	var courtesy_arrived: bool = courtesy.space.at(courtesy.world,"head_on_a",1,[34,86]) and courtesy.space.at(courtesy.world,"head_on_b",1,[34,94]) and courtesy.world.facts.moves.is_empty()
	var courtesy_ok: bool = first_request.is_empty() and second_request.is_empty() and fractional_yield and safe_sweeps and courtesy_targets and courtesy_arrived
	var courtesy_details: Dictionary = {"first_request":first_request,"second_request":second_request,"fractional_yield_observed":fractional_yield,"safe_real_sweeps":safe_sweeps,"original_targets_preserved":courtesy_targets,"both_arrived":courtesy_arrived,"first_location":courtesy.world.facts.actors.head_on_a.location.duplicate(true),"second_location":courtesy.world.facts.actors.head_on_b.location.duplicate(true),"remaining_moves":courtesy.world.facts.moves.duplicate(true)}
	courtesy.dispose()
	return _done(sim,first_estimates and changed_estimates and worlds_isolated and first.get("ok",false) and built.accepted and changed.get("ok",false) and float(changed.get("walking_distance",0))>float(first.get("walking_distance",0)) and changed.get("path")==fresh.get("path") and upstairs.accepted and after_other.get("path")==changed.get("path") and same_queue and restored_route.get("path")==changed.get("path") and dynamic_ok and wide_ok and protected_ok and courtesy_ok,{"first_estimates":first_estimates,"changed_estimates":changed_estimates,"worlds_isolated":worlds_isolated,"candidate_route":_public_quote(candidate_route),"first":_public_quote(first),"changed":_public_quote(changed),"same_queue":same_queue,"stationary_obstacle":dynamic_details,"idle_staff_yield":wide_details,"protected_staff":protected_details,"fractional_head_on":courtesy_details})

func _travel_quote_contract(sim: HospitalSimulation, steps: int) -> bool:
	var speed: float = float(content.balance.movement_speeds["1"])
	var expected_ticks: int = ceili(float(steps)/speed/WorldState.TICK_SECONDS)
	var before: Dictionary = sim.world.freeze()
	var matches: bool = true
	for index: int in 16:
		var quote: Dictionary = sim.space.travel_quote(sim.world,"walker",1,[51,75])
		matches = matches and quote.ok and is_equal_approx(float(quote.walking_distance),float(steps)) and int(quote.arrival_ticks)==expected_ticks
	matches = matches and before==sim.world.freeze()
	var fractional: WorldState = WorldState.new(sim.world.freeze())
	fractional.facts.actors.walker.location.cell = [35.25,75.0]
	fractional.touch()
	before = fractional.freeze()
	for index: int in 16:
		var quote: Dictionary = sim.space.travel_quote(fractional,"walker",1,[51,75])
		matches = matches and quote.ok and is_equal_approx(float(quote.walking_distance),float(steps)+0.25) and int(quote.arrival_ticks)==expected_ticks+ceili(0.25/speed/WorldState.TICK_SECONDS)
	return matches and before==fractional.freeze()

func _case_11(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var initial: int = HospitalLedger.balance(sim.world)
	var count: int = sim.world.facts.rooms.size()+sim.world.facts.facilities.size()
	var bought: CommandResult = _command(sim,"build_land",{"plot":[2,2],"floor_id":1})
	var cash: int = HospitalLedger.balance(sim.world)
	var granted: bool = bought.accepted and initial-cash==3000 and count==sim.world.facts.rooms.size()+sim.world.facts.facilities.size() and sim.space.owned(sim.world,1,Vector2i(70,75)) and not sim.space.owned(sim.world,2,Vector2i(70,75))
	var before: Dictionary = sim.world.freeze()
	var repeated: CommandResult = _command(sim,"build_land",{"plot":[2,2],"floor_id":1})
	var distant: CommandResult = _command(sim,"build_land",{"plot":[0,0],"floor_id":1})
	return _done(sim,granted and not repeated.accepted and not distant.accepted and before==sim.world.freeze(),{"bought":bought.to_record(),"repeat":repeated.to_record(),"distant":distant.to_record()})

func _case_12(_t) -> Dictionary:
	var sim: HospitalSimulation = _floor_fixture()
	var lift: String = _connection(sim)
	var valid: Dictionary = sim.services.floors.preview(sim.world,_floor_draft(lift))
	var wrong_plot: Dictionary = sim.services.floors.preview(sim.world,{"floor_id":2,"plot":[2,2],"source":"lift","connection_id":lift})
	var no_first: Dictionary = sim.services.floors.preview(sim.world,{"floor_id":2,"plot":[1,2],"source":"same_floor"})
	var skipped: Dictionary = sim.services.floors.preview(sim.world,{"floor_id":3,"plot":[1,2],"source":"lift","connection_id":lift})
	return _done(sim,valid.get("ok",false) and not wrong_plot.get("ok",true) and not no_first.get("ok",true) and not skipped.get("ok",true),{"valid":_public_quote(valid),"wrong_plot":wrong_plot,"no_first":no_first,"skipped":skipped})

func _case_13(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var lift_result: CommandResult = _command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[48,70]})
	var lift: String = str(lift_result.changed_ids[0]) if lift_result.accepted else ""
	sim.world.facts.mode = "creative"
	var bare: Dictionary = sim.services.floors.preview(sim.world,_floor_draft(lift))
	var furniture: CommandResult = _command(sim,"build_facility",{"id":"not_building","definition_id":"SE02","floor_id":1,"cell":[42,74]})
	var not_room: Dictionary = sim.services.floors.preview(sim.world,_floor_draft(lift))
	var grass_before: Dictionary = sim.world.freeze()
	sim.services.building.preview(sim.world,_room("draft_only",[35,66]))
	var draft: Dictionary = sim.services.floors.preview(sim.world,_floor_draft(lift))
	var readonly: bool = sim.world.freeze()==grass_before
	var empty: CommandResult = _command(sim,"build_room",_room("actual_empty",[35,66]))
	var actual: Dictionary = sim.services.floors.preview(sim.world,_floor_draft(lift))
	return _done(sim,lift_result.accepted and furniture.accepted and not bare.get("ok",true) and not not_room.get("ok",true) and not draft.get("ok",true) and readonly and empty.accepted and actual.get("ok",false),{"bare":bare,"furniture":not_room,"draft":draft,"actual":_public_quote(actual)})

func _case_14(_t) -> Dictionary:
	var sim: HospitalSimulation = _floor_fixture()
	var draft: Dictionary = _floor_draft(_connection(sim))
	var worker: Dictionary = sim.world.facts.staff.decorator.duplicate(true)
	var actor: Dictionary = sim.world.facts.actors.decorator.duplicate(true)
	sim.world.facts.staff.erase("decorator")
	sim.world.facts.actors.erase("decorator")
	sim.world.touch()
	var before: Dictionary = sim.world.freeze()
	var missing_worker: CommandResult = _command(sim,"floor_purchase",draft)
	var worker_atomic: bool = not missing_worker.accepted and before==sim.world.freeze()
	sim.world.facts.staff.decorator = worker
	sim.world.facts.actors.decorator = actor
	sim.world.facts.facilities.tool.failed = true
	sim.world.touch()
	before = sim.world.freeze()
	var missing_tool: CommandResult = _command(sim,"floor_purchase",draft)
	var tool_atomic: bool = not missing_tool.accepted and before==sim.world.freeze()
	sim.world.facts.facilities.tool.failed = false
	sim.world.touch()
	var cash: int = HospitalLedger.balance(sim.world)
	var purchase: CommandResult = _command(sim,"floor_purchase",draft)
	var order: Dictionary = _order(sim)
	var before_repeat: Dictionary = sim.world.freeze()
	var repeat: CommandResult = _command(sim,"floor_purchase",draft)
	return _done(sim,worker_atomic and tool_atomic and purchase.accepted and cash-HospitalLedger.balance(sim.world)==3200 and not order.is_empty() and order.remaining_milli==order.total_milli and not sim.space.owned(sim.world,2,Vector2i(40,75)) and not repeat.accepted and before_repeat==sim.world.freeze(),{"worker":missing_worker.reason,"tool":missing_tool.reason,"purchase":purchase.to_record(),"repeat":repeat.to_record()})

func _case_15(_t) -> Dictionary:
	var details: Array = []
	var ok: bool = true
	for sample: Array in [[2,3200,90000],[3,4800,120000],[4,6400,150000],[5,8000,180000],[10,8000,180000]]:
		var sim: HospitalSimulation = _floor_fixture()
		_history_height(sim,int(sample[0])-1)
		if int(sample[0])>2:
			_command(sim,"build_room",_room("below_high",[35,66],[4,4],int(sample[0])-1))
			for floor_id: int in range(2,int(sample[0])):
				_command(sim,"connector_extend",{"connection_id":_connection(sim),"floor_id":floor_id})
			sim.world.facts.staff.decorator.work_region.floor_id = int(sample[0])-1
		var draft: Dictionary = _floor_draft(_connection(sim),int(sample[0]))
		var quote: Dictionary = sim.services.floors.preview(sim.world,draft)
		ok = ok and quote.get("ok",false) and int(quote.get("total_milli",-1))==int(sample[2]) and int(quote.get("price",-1))==int(sample[1])
		details.append({"floor":sample[0],"quote":_public_quote(quote)})
		sim.dispose()
	return {"ok":ok,"details":details}

func _case_16(_t) -> Dictionary:
	var sim: HospitalSimulation = _floor_fixture()
	var purchase: CommandResult = _command(sim,"floor_purchase",_floor_draft(_connection(sim)))
	var order: Dictionary = _order(sim)
	var start: int = int(order.get("remaining_milli",-1))
	sim.step()
	var no_remote: bool = not order.is_empty() and int(order.remaining_milli)==start and order.phase!="completed"
	var completed: bool = _wait(sim,func() -> bool: return _order(sim).get("phase")=="completed",1400)
	order = _order(sim)
	var contributions: int = 0
	for value: int in order.get("contributions",{}).values(): contributions += value
	var after: Dictionary = sim.world.facts.floors.duplicate(true)
	sim.step()
	return _done(sim,purchase.accepted and no_remote and completed and sim.space.owned(sim.world,2,Vector2i(40,75)) and int(order.get("remaining_milli",-1))==0 and contributions==90000 and sim.world.facts.rooms.size()==1 and int(sim.world.facts.connectors[_connection(sim)].last_floor)==1 and after==sim.world.facts.floors,{"purchase":purchase.to_record(),"order":order.duplicate(true),"no_remote":no_remote})

func _case_17(_t) -> Dictionary:
	var sim: HospitalSimulation = _floor_fixture()
	_command(sim,"floor_purchase",_floor_draft(_connection(sim)))
	var started: bool = _wait(sim,func() -> bool: return int(_order(sim).get("remaining_milli",90000))<89000,250)
	var order: Dictionary = _order(sim)
	var id: String = str(order.get("id",""))
	var paused: CommandResult = _command(sim,"floor_pause",{"order_id":id})
	var remaining: int = int(order.get("remaining_milli",-1))
	var contributions: Dictionary = order.get("contributions",{}).duplicate(true)
	var game: GameSession = GameSession.new(sim,"space_pause")
	game.set_speed(0)
	var before: Dictionary = sim.world.freeze()
	game.advance(0.8)
	var global_paused: bool = before==sim.world.freeze()
	for index: int in 5: sim.step()
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(sim.world.freeze()),content)
	var saved_order: Dictionary = _order(restored)
	var stable: bool = saved_order.get("paused",false) and int(saved_order.get("remaining_milli",-2))==remaining and saved_order.get("contributions",{})==contributions and int(saved_order.get("paid_cost",-1))==3200
	var resumed: CommandResult = _command(restored,"floor_resume",{"order_id":id})
	var progressed: bool = _wait(restored,func() -> bool: return int(_order(restored).get("remaining_milli",remaining))<remaining,120)
	var details: Dictionary = {"started":started,"pause":paused.to_record(),"resume":resumed.to_record(),"remaining":remaining,"restored":saved_order.duplicate(true)}
	restored.dispose()
	return _done(sim,started and paused.accepted and global_paused and stable and resumed.accepted and progressed,details)

func _case_18(_t) -> Dictionary:
	var sim: HospitalSimulation = _floor_fixture()
	_command(sim,"floor_purchase",_floor_draft(_connection(sim)))
	var started: bool = _wait(sim,func() -> bool: return int(_order(sim).get("remaining_milli",90000))<88000,250)
	var id: String = str(_order(sim).get("id",""))
	_command(sim,"floor_pause",{"order_id":id})
	var remaining: int = int(_order(sim).get("remaining_milli",-1))
	var paid: int = int(_order(sim).get("paid_cost",-1))
	var original_contribution: Dictionary = _order(sim).get("contributions",{}).duplicate(true)
	var demolished: CommandResult = _command(sim,"build_demolish",{"target_id":"below"})
	_command(sim,"floor_resume",{"order_id":id})
	sim.step()
	var stopped: bool = int(_order(sim).get("remaining_milli",-2))==remaining and str(_order(sim).get("reason","")).contains("下层")
	var rebuilt: CommandResult = _command(sim,"build_room",_room("below_again",[35,66]))
	var moved: bool = _wait(sim,func() -> bool: return int(_order(sim).get("remaining_milli",remaining))<remaining,120)
	var order: Dictionary = _order(sim)
	var same_work: bool = order.id==id and int(order.paid_cost)==paid and int(order.total_milli)==90000 and order.floor_id==2 and order.plot==[1,2] and int(order.get("work_cell",[0,0])[0])/32==1 and int(order.get("work_cell",[0,0])[1])/32==2
	for worker_id: String in original_contribution:
		same_work = same_work and int(order.contributions.get(worker_id,0))>=int(original_contribution[worker_id])
	return _done(sim,started and demolished.accepted and stopped and rebuilt.accepted and moved and same_work,{"demolished":demolished.to_record(),"stopped":stopped,"order":order.duplicate(true)})

func _case_19(_t) -> Dictionary:
	var sim: HospitalSimulation = _floor_fixture()
	var bought: CommandResult = _command(sim,"floor_purchase",_floor_draft(_connection(sim)))
	var id: String = str(_order(sim).get("id",""))
	var cash: int = HospitalLedger.balance(sim.world)
	var unstarted: CommandResult = _command(sim,"floor_cancel",{"order_id":id},"space_full_cancel")
	var full: bool = unstarted.accepted and HospitalLedger.balance(sim.world)-cash==3200 and not sim.space.owned(sim.world,2,Vector2i(40,75))
	_command(sim,"floor_purchase",_floor_draft(_connection(sim)))
	var started: bool = _wait(sim,func() -> bool: return int(_active_order(sim).get("remaining_milli",90000))<88000,250)
	var order: Dictionary = _active_order(sim)
	var expected: int = int(order.get("paid_cost",0))*int(order.get("remaining_milli",0))/maxi(1,int(order.get("total_milli",1)))
	cash = HospitalLedger.balance(sim.world)
	var partial: CommandResult = _command(sim,"floor_cancel",{"order_id":order.get("id","")},"space_partial_cancel")
	var after: Dictionary = sim.world.freeze()
	var duplicate: CommandResult = _command(sim,"floor_cancel",{"order_id":order.get("id","")},"space_partial_cancel")
	var partial_ok: bool = partial.accepted and HospitalLedger.balance(sim.world)-cash==expected and duplicate.accepted and after==sim.world.freeze()
	sim.world.facts.mode = "creative"
	var completed: CommandResult = _command(sim,"floor_purchase",_floor_draft(_connection(sim)))
	var removed: CommandResult = _command(sim,"build_demolish",{"target_id":"below"})
	return _done(sim,bought.accepted and full and started and partial_ok and completed.accepted and removed.accepted and sim.space.owned(sim.world,2,Vector2i(40,75)),{"full":full,"expected_partial":expected,"partial":partial.to_record(),"completed":completed.to_record(),"removed_below":removed.to_record()})

func _case_20(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_history_height(sim,10000)
	var floors_before: int = sim.world.facts.floors.overrides.size()
	var sparse: bool = true
	for floor_id: int in [5,10,100,1000,10000]:
		sparse = sparse and sim.space.owned(sim.world,floor_id,Vector2i(40,75)) and not sim.space.owned(sim.world,floor_id,Vector2i(70,75))
	var built: CommandResult = _command(sim,"build_room",_room("room_10000",[35,68],[4,4],10000))
	var restored: WorldState = WorldState.new(sim.world.freeze())
	var valid: String = restored.validate(content)
	var frozen: Dictionary = restored.freeze()
	var count: int = frozen.floors.get("completed_top_floor",{}).size()
	return _done(sim,sparse and built.accepted and valid.is_empty() and count==1 and floors_before==1 and frozen.floors.overrides.size()==2 and frozen.rooms.size()==1 and frozen.actors.is_empty() and frozen.floors.orders.is_empty() and restored.facts==sim.world.facts,{"validation":valid,"height_records":count,"actual_floor_overrides":frozen.floors.overrides.keys(),"actual_rooms":frozen.rooms.keys()})

func _case_21(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var cash: int = HospitalLedger.balance(sim.world)
	var made: CommandResult = _command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	var connection: Dictionary = sim.world.facts.connectors.get(_connection(sim),{})
	_add_actor(sim,"passenger","S49",[36,76])
	var before: Dictionary = sim.world.freeze()
	var route: Dictionary = sim.space.route(sim.world,"passenger",2,[36,76])
	return _done(sim,made.accepted and cash-HospitalLedger.balance(sim.world)==3200 and connection.get("first_floor")==1 and connection.get("last_floor")==1 and connection.get("floor_id")==1 and connection.get("phase")=="idle" and connection.get("riders",[]).is_empty() and int(connection.get("ticket_next",-1))==0 and sim.world.facts.connectors.size()==1 and sim.world.facts.facilities.is_empty() and not route.get("ok",true) and before==sim.world.freeze(),{"connection":connection,"route":_public_quote(route)})

func _case_22(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_history_height(sim,3)
	var made: CommandResult = _command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	var id: String = _connection(sim)
	var cash: int = HospitalLedger.balance(sim.world)
	var second: CommandResult = _command(sim,"connector_extend",{"connection_id":id,"floor_id":2})
	var included: bool = second.accepted and cash==HospitalLedger.balance(sim.world)
	if made.accepted:
		sim.world.facts.connectors[id].failed = true
		sim.world.facts.connectors[id].condition = 37.0
		sim.world.facts.connectors[id].ticket_next = 9
	cash = HospitalLedger.balance(sim.world)
	var third: CommandResult = _command(sim,"connector_extend",{"connection_id":id,"floor_id":3})
	var state_kept: bool = third.accepted and cash-HospitalLedger.balance(sim.world)==1200 and sim.world.facts.connectors[id].failed and sim.world.facts.connectors[id].condition==37.0 and sim.world.facts.connectors[id].ticket_next==9 and sim.world.facts.connectors[id].floor_id==1
	var cross: HospitalSimulation = _fixture()
	_command(cross,"build_land",{"plot":[2,2],"floor_id":1})
	_history_height(cross,2)
	var cross_made: CommandResult = _command(cross,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[62,72]})
	var before: Dictionary = cross.world.freeze()
	var missing: CommandResult = _command(cross,"connector_extend",{"connection_id":_connection(cross),"floor_id":2})
	var missing_atomic: bool = not missing.accepted and before==cross.world.freeze()
	cross.dispose()
	return _done(sim,made.accepted and included and state_kept and cross_made.accepted and missing_atomic,{"second":second.to_record(),"third":third.to_record(),"missing_plot":missing.to_record()})

func _case_23(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	_add_actor(sim,"human","S49",[45,82])
	_add_actor(sim,"tall","S01",[48,82])
	_add_actor(sim,"giant_a","S53",[52,78])
	_add_actor(sim,"giant_b","S53",[56,78])
	var lift: Dictionary = sim.world.facts.connectors[_connection(sim)]
	var human: Dictionary = HospitalTransit.fits(sim.space,sim.world,lift,"human",[])
	var tall: Dictionary = HospitalTransit.fits(sim.space,sim.world,lift,"tall",[])
	var small_pair: Dictionary = HospitalTransit.fits(sim.space,sim.world,lift,"giant_a",["giant_a","giant_b"])
	var giant_lift: Dictionary = lift.duplicate(true)
	giant_lift.definition_id = "VC03"
	var large_pair: Dictionary = HospitalTransit.fits(sim.space,sim.world,giant_lift,"giant_a",["giant_a","giant_b"])
	var stairs: Dictionary = lift.duplicate(true)
	stairs.definition_id = "VC01"
	var tall_stairs: Dictionary = HospitalTransit.fits(sim.space,sim.world,stairs,"tall",[])
	var group_stairs: Dictionary = HospitalTransit.fits(sim.space,sim.world,stairs,"human",["human","tall"])
	return _done(sim,human.get("ok",false) and not tall.get("ok",true) and not small_pair.get("ok",true) and large_pair.get("ok",false) and large_pair.get("cabin_positions",{}).get("giant_a")==[0,0] and large_pair.get("cabin_positions",{}).get("giant_b")==[3,0] and not tall_stairs.get("ok",true) and not group_stairs.get("ok",true),{"human":human,"tall":tall,"small_pair":small_pair,"large_pair":large_pair,"stairs":tall_stairs})

func _case_24(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"patient","S49",[32,78])
	_add_actor(sim,"escort","S49",[33,79])
	var before: Dictionary = sim.world.freeze()
	for index: int in 4:
		HospitalTransit.quote(sim.space,sim.world,sim.world.facts.connectors[id],"patient",1,2,60,["patient","escort"],{"patient":[0,0],"escort":[1,0]})
	var readonly: bool = before==sim.world.freeze()
	var not_ready: String = sim.space.request_group_move(sim.world,"patient",["patient","escort"],{"patient":[0,0],"escort":[1,0]},2,[44,80])
	var no_ticket: bool = not not_ready.is_empty() and int(sim.world.facts.connectors[id].ticket_next)==0 and sim.world.facts.moves.is_empty()
	sim.space.request_move(sim.world,"escort",1,[33,78])
	var aligned: bool = _wait(sim,func() -> bool: return sim.space.at(sim.world,"escort",1,[33,78]) and not sim.world.facts.moves.has("escort"),60)
	var requested: String = sim.space.request_group_move(sim.world,"patient",["patient","escort"],{"patient":[0,0],"escort":[1,0]},2,[44,80])
	var boarded: bool = _wait(sim,func() -> bool: return sim.world.facts.actors.patient.location.kind=="transit",220)
	var connection: Dictionary = sim.world.facts.connectors[id]
	return _done(sim,readonly and no_ticket and aligned and requested.is_empty() and boarded and connection.ticket_next==1 and connection.riders==["patient","escort"] and sim.world.facts.actors.escort.location.kind=="transit",{"unready":not_ready,"boarded":boarded,"connection":connection.duplicate(true)})

func _case_25(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"first","S49",[36,76])
	_add_actor(sim,"second","S49",[32,76])
	sim.space.request_move(sim.world,"first",2,[46,80])
	var first_boarded: bool = _wait(sim,func() -> bool: return sim.world.facts.actors.first.location.kind=="transit",30)
	sim.space.request_move(sim.world,"second",2,[42,82])
	var queued: bool = _wait(sim,func() -> bool: return sim.world.facts.moves.get("second",{}).has("transit_ticket"),90)
	var sequence: int = int(sim.world.facts.moves.get("second",{}).get("transit_ticket",{}).get("sequence",-1))
	var before: Dictionary = sim.world.freeze()
	HospitalTransit.quote(sim.space,sim.world,sim.world.facts.connectors[id],"second",1,2,0)
	var readonly: bool = before==sim.world.freeze()
	var arrived_first: bool = _wait(sim,func() -> bool: return sim.world.facts.actors.first.location.kind=="floor" and int(sim.world.facts.actors.first.location.floor_id)==2,100)
	var second_not_ahead: bool = sim.world.facts.actors.second.location.kind!="floor" or int(sim.world.facts.actors.second.location.floor_id)==1
	var both: bool = _wait(sim,func() -> bool: return sim.space.at(sim.world,"first",2,[46,80]) and sim.space.at(sim.world,"second",2,[42,82]),400)
	return _done(sim,first_boarded and queued and sequence==2 and readonly and arrived_first and second_not_ahead and both and int(sim.world.facts.connectors[id].ticket_next)==2,{"first_boarded":first_boarded,"queued":queued,"sequence":sequence,"both_arrived":both})

func _case_26(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"active","S49",[36,76])
	_add_actor(sim,"querying","S49",[45,84])
	sim.space.request_move(sim.world,"active",2,[46,80])
	var boarding: bool = _wait(sim,func() -> bool: return sim.world.facts.connectors[id].phase=="boarding",30)
	var connection: Dictionary = sim.world.facts.connectors[id]
	var remaining_prefix: int = int(connection.remaining_ticks)+10+15
	var expected: int = maxi(100,remaining_prefix)+10+40
	var before: Dictionary = sim.world.freeze()
	var quote: Dictionary = HospitalTransit.quote(sim.space,sim.world,connection,"querying",1,2,100)
	var readonly: bool = before==sim.world.freeze()
	_add_actor(sim,"exit_blocker","S49",[36,76],2)
	var unknown: Dictionary = HospitalTransit.quote(sim.space,sim.world,connection,"querying",1,2,100)
	return _done(sim,boarding and readonly and quote.get("ok",false) and int(quote.get("arrival_ticks",-1))==expected and int(quote.get("queue_ticks",-1))==0 and int(quote.get("empty_ticks",-1))==10 and not unknown.get("ok",true) and unknown.get("status")=="estimate_unknown" and not str(unknown.get("reason","")).is_empty(),{"quote":quote,"expected":expected,"unknown":unknown})

func _case_27(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"upstairs","S49",[36,76])
	sim.space.request_move(sim.world,"upstairs",2,[46,80])
	var delivered: bool = _wait(sim,func() -> bool: return sim.space.at(sim.world,"upstairs",2,[46,80]) and not sim.world.facts.moves.has("upstairs"),250)
	_add_actor(sim,"cancelled","S49",[36,76])
	sim.space.request_move(sim.world,"cancelled",2,[44,82])
	var empty_started: bool = _wait(sim,func() -> bool: return sim.world.facts.connectors[id].phase=="empty_riding",40)
	var connection: Dictionary = sim.world.facts.connectors[id]
	var remaining: int = int(connection.remaining_ticks)
	var floor_before: int = int(connection.floor_id)
	var ticket: Dictionary = sim.world.facts.moves.get("cancelled",{}).get("transit_ticket",{}).duplicate(true)
	if sim.world.facts.moves.has("cancelled"): HospitalTransit.cancel_waiting(sim.world,sim.world.facts.moves.cancelled)
	var preserved: bool = connection.phase=="empty_riding" and int(connection.remaining_ticks)==remaining and connection.riders.is_empty() and not connection.has("assigned_actor_id")
	var restored: WorldState = WorldState.new(sim.world.freeze())
	var restored_space: HospitalSpace = HospitalSpace.new(content)
	for index: int in remaining:
		# Advance the committed transport segment without dispatching a replacement movement demand.
		HospitalTransit.advance(restored_space,restored)
	var after: Dictionary = restored.facts.connectors[id]
	return _done(sim,delivered and empty_started and not ticket.is_empty() and floor_before==2 and preserved and after.phase=="idle" and int(after.floor_id)==1 and after.riders.is_empty() and int(after.ticket_next)==int(connection.ticket_next) and restored.facts.actors.cancelled.location.kind=="floor",{"started":empty_started,"ticket":ticket,"remaining":remaining,"preserved":preserved,"restored_connection":after})

func _case_28(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"passenger","S49",[36,76])
	sim.space.request_move(sim.world,"passenger",2,[44,80])
	var riding: bool = _wait(sim,func() -> bool: return sim.world.facts.connectors[id].phase=="riding",60)
	var actor: Dictionary = sim.world.facts.actors.passenger
	var exclusive: bool = actor.location.kind=="transit" and not actor.location.has("floor_id") and not actor.location.has("cell")
	var snapshot_path: String = "user://acceptance-space-transit-"+HospitalSnapshots.uuid()+".json"
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var encoded: bool = encoder.encode(snapshot_path,sim.world.freeze(),func(_bytes: int) -> bool: return true)
	if not encoded:
		if FileAccess.file_exists(snapshot_path): DirAccess.remove_absolute(snapshot_path)
		return _done(sim,false,{"stream_encode_error":encoder.error})
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var decoded: Dictionary = decoder.decode(snapshot_path,encoder.bytes,encoder.digest,func(_bytes: int) -> bool: return true)
	DirAccess.remove_absolute(snapshot_path)
	if not decoded.get("ok",false): return _done(sim,false,{"stream_decode_error":decoded.get("error","")})
	var restored_world: WorldState = WorldState.new(decoded.value)
	var load_validation: String = restored_world.validate(content)
	if not load_validation.is_empty(): return _done(sim,false,{"stream_snapshot_validation":load_validation})
	var restored: HospitalSimulation = HospitalSimulation.new(restored_world,content)
	var original_remaining: int = int(sim.world.facts.connectors[id].remaining_ticks)
	var same: bool = _canonical(restored.world.facts.actors.passenger)==_canonical(actor) and int(restored.world.facts.connectors[id].remaining_ticks)==original_remaining and _canonical(restored.world.facts.moves)==_canonical(sim.world.facts.moves)
	var arrived: bool = false
	for index: int in 200:
		sim.step()
		restored.step()
		if restored.space.at(restored.world,"passenger",2,[44,80]) and not restored.world.facts.moves.has("passenger") and sim.space.at(sim.world,"passenger",2,[44,80]) and not sim.world.facts.moves.has("passenger"):
			arrived = true
			break
	var final_actor: Dictionary = restored.world.facts.actors.passenger
	var validation: String = restored.world.validate(content)
	var equal_facts: bool = _canonical(restored.world.freeze())==_canonical(sim.world.freeze())
	var single_use: bool = restored.world.facts.connectors[id].use_receipts.size()==1 and sim.world.facts.connectors[id].use_receipts.size()==1 and is_equal_approx(float(restored.world.facts.connectors[id].condition),float(sim.world.facts.connectors[id].condition))
	var details: Dictionary = {"riding":riding,"same":same,"arrived":arrived,"validation":validation,"location":final_actor.location,"equal_business_facts":equal_facts,"single_wear_receipt":single_use,"use_receipts":restored.world.facts.connectors[id].use_receipts,"snapshot_bytes":encoder.bytes,"snapshot_sha256":encoder.digest}
	restored.dispose()
	return _done(sim,riding and exclusive and same and arrived and equal_facts and single_use and final_actor.id=="passenger" and final_actor.location.kind=="floor" and not final_actor.location.has("connector_id") and validation.is_empty(),details)

func _case_29(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"passenger","S49",[36,76])
	sim.space.request_move(sim.world,"passenger",2,[44,80])
	var riding: bool = _wait(sim,func() -> bool: return sim.world.facts.connectors[id].phase=="riding",60)
	sim.world.facts.connectors[id].pending_failure = true # External fault injection at an actual committed ride boundary.
	var safe: bool = _wait(sim,func() -> bool: return sim.space.at(sim.world,"passenger",2,[44,80]) and not sim.world.facts.moves.has("passenger"),240)
	var failed: bool = bool(sim.world.facts.connectors[id].failed) and not sim.world.facts.connectors[id].pending_failure
	var down: Dictionary = HospitalTransit.quote(sim.space,sim.world,sim.world.facts.connectors[id],"passenger",2,1,0)
	var up: Dictionary = HospitalTransit.quote(sim.space,sim.world,sim.world.facts.connectors[id],"passenger",1,2,0)
	sim.space.request_move(sim.world,"passenger",1,[44,80])
	var descended: bool = _wait(sim,func() -> bool: return sim.space.at(sim.world,"passenger",1,[44,80]) and not sim.world.facts.moves.has("passenger"),300)
	return _done(sim,riding and safe and failed and down.get("ok",false) and int(down.get("group_ticks",-1))==70 and not up.get("ok",true) and descended and sim.world.facts.connectors[id].failed,{"safe_arrival":safe,"down":down,"up":up,"descended":descended})

func _case_30(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var id: String = _connection(sim)
	_add_actor(sim,"resident","S49",[44,80],2)
	var before: Dictionary = sim.world.freeze()
	var remove: CommandResult = _command(sim,"connector_remove",{"connection_id":id})
	var safety: bool = not remove.accepted and before==sim.world.freeze()
	sim.world.facts.connectors[id].failed = true
	var upstairs: Dictionary = sim.space.route(sim.world,"resident",2,[46,80])
	var down: Dictionary = sim.space.route(sim.world,"resident",1,[44,80])
	return _done(sim,safety and upstairs.get("ok",false) and down.get("ok",false) and not HospitalTransit.quote(sim.space,sim.world,sim.world.facts.connectors[id],"resident",1,2,0).get("ok",true),{"remove":remove.to_record(),"down":_public_quote(down)})

func _case_31(t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_history_height(sim,10000)
	_add_actor(sim,"ground","S49",[47,80])
	_add_actor(sim,"high","S49",[47,80],10000)
	var view: HospitalView = HospitalView.new(content)
	t.root.add_child(view)
	var before: Dictionary = sim.world.freeze()
	view.bind(sim.world,1,"space_view_session")
	view.set_floor(10000)
	var projected: Dictionary = view._project_location(sim.world.facts.actors.high)
	var other: Dictionary = view._project_location(sim.world.facts.actors.ground)
	var readonly: bool = before==sim.world.freeze()
	var game: GameSession = GameSession.new(sim,"space_view_session")
	game.set_speed(0)
	game.advance(0.5)
	var paused: bool = before==sim.world.freeze()
	var ok: bool = readonly and paused and view.observed_floor==10000 and projected.get("visible",false) and not other.get("visible",true) and absf((projected.get("position",Vector3.ZERO) as Vector3).y)<8.0 and sim.world.facts.actors.size()==2
	view.free()
	return _done(sim,ok,{"readonly":readonly,"paused":paused,"high":projected,"other":other})

func _case_32(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_command(sim,"build_room",_room("remodel_room",[35,68]))
	var before: Dictionary = sim.world.freeze()
	var draft: Dictionary = sim.services.remodel.group_commands(sim.world,["remodel_room"],[],1,[45,68],0)
	var readonly: bool = before==sim.world.freeze() and sim.world.facts.remodels.is_empty()
	var cash: int = HospitalLedger.balance(sim.world)
	var prepared: CommandResult = _command(sim,"remodel_prepare",{"commands":draft.get("commands",[])})
	var id: String = str(prepared.changed_ids[0]) if prepared.accepted else ""
	var after: Dictionary = sim.world.freeze()
	var duplicate_member: CommandResult = _command(sim,"remodel_prepare",{"commands":draft.get("commands",[])})
	return _done(sim,readonly and prepared.accepted and HospitalRemodel.blocked(sim.world,"remodel_room") and HospitalLedger.balance(sim.world)==cash and not duplicate_member.accepted and after==sim.world.freeze() and sim.world.facts.remodels.get(id,{}).get("commands")==draft.get("commands"),{"prepare":prepared.to_record(),"conflict":duplicate_member.to_record()})

func _case_33(_t) -> Dictionary:
	var evacuation: Dictionary = _remodel_evacuation_contract()
	var sim: HospitalSimulation = _fixture()
	_command(sim,"build_room",_room("source",[35,68]))
	var prepared: CommandResult = _prepare(sim,["source"],1,[45,68])
	var id: String = str(prepared.changed_ids[0]) if prepared.accepted else ""
	var plan: Dictionary = sim.services.remodel.preview(sim.world,id)
	for index: int in 3: sim.step()
	var no_auto: bool = sim.world.facts.rooms.source.origin==[35,68] and sim.world.facts.remodels.get(id,{}).get("state")=="preparing"
	var target_use: CommandResult = _command(sim,"build_facility",{"id":"target_taken","definition_id":"SE02","cell":[45,68],"floor_id":1})
	var before: Dictionary = sim.world.freeze()
	var apply: CommandResult = _command(sim,"remodel_apply",{"order_id":id,"quote":_remodel_quote(plan)})
	return _done(sim,evacuation.ok and prepared.accepted and plan.get("ok",false) and no_auto and target_use.accepted and not apply.accepted and before==sim.world.freeze(),{"evacuation":evacuation,"preview":_public_quote(plan),"target_use":target_use.to_record(),"apply":apply.to_record()})

func _case_34(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_command(sim,"build_room",_room("source",[35,68]))
	var prepare: CommandResult = _prepare(sim,["source"],1,[45,68])
	var id: String = str(prepare.changed_ids[0]) if prepare.accepted else ""
	sim.world.facts.rooms.source.open_intent = false # A later, independent player operating preference.
	sim.world.touch()
	var cash: int = HospitalLedger.balance(sim.world)
	var cancelled: CommandResult = _command(sim,"remodel_cancel",{"order_id":id},"space_cancel_arrangement")
	var after: Dictionary = sim.world.freeze()
	var repeat: CommandResult = _command(sim,"remodel_cancel",{"order_id":id},"space_cancel_arrangement")
	return _done(sim,prepare.accepted and cancelled.accepted and not HospitalRemodel.blocked(sim.world,"source") and not sim.world.facts.rooms.source.open_intent and cash==HospitalLedger.balance(sim.world) and repeat.accepted and after==sim.world.freeze(),{"cancel":cancelled.to_record(),"repeat":repeat.to_record()})

func _case_35(_t) -> Dictionary:
	var bed_layouts: Dictionary = _bed_blueprint_contract()
	if not bed_layouts.ok: return {"ok":false,"details":{"prerequisite":"内置病房真实床边职责、旋转与保存","bed_layouts":bed_layouts}}
	var sim: HospitalSimulation = _fixture(true)
	sim.clinic.departments = null
	var arrival: CommandResult = _command(sim,"clinical_arrive",{"binding_id":"B_S49_D37_M37","arrival_key":"space_actual_outpatient","requested_plan_id":"P_D37_COMMON"})
	var visit_id: String = str(arrival.changed_ids[0]) if arrival.accepted else ""
	var begun: bool = _wait(sim,func() -> bool: return not _session(sim,"outpatient").is_empty(),2400)
	var session: Dictionary = _session(sim,"outpatient").duplicate(true)
	if not begun: return _done(sim,false,{"prerequisite":"实际门诊未开工","arrival":arrival.to_record(),"visit":sim.world.facts.visits.get(visit_id,{})})
	var visit: Dictionary = sim.world.facts.visits[visit_id]
	var evidence: Dictionary = visit.evidence_by_source.duplicate(true)
	var attempt_id: String = str(session.get("attempt_id",""))
	var attempt: Dictionary = sim.world.facts.attempts.get(attempt_id,{}).duplicate(true)
	var issues: Dictionary = sim.world.facts.inventory.issues.duplicate(true)
	var original_ticket: Dictionary = session.get("original_ticket",{}).duplicate(true)
	var before_use: Dictionary = sim.world.freeze()
	var active_use: Dictionary = HospitalEquipmentUse.query(sim.world,str(session.facility_id))
	var use_readonly: bool = before_use==sim.world.freeze()
	var room_id: String = str(sim.world.facts.facilities[session.facility_id].room_id)
	var prepare: CommandResult = _prepare(sim,[room_id],1,[50,66],true)
	var order_id: String = str(prepare.changed_ids[0]) if prepare.accepted else ""
	sim.step()
	var suspension: Dictionary = sim.world.facts.clinical_suspensions.get(session.id,{})
	var preserved: bool = prepare.accepted and sim.world.facts.attempts.get(attempt_id,{})==attempt and sim.world.facts.inventory.issues==issues and sim.world.facts.visits[visit_id].evidence_by_source==evidence and sim.world.facts.visits[visit_id].ticket_id==str(original_ticket.get("id","")) and int(suspension.get("remaining_ticks",-1))==int(session.remaining_ticks)
	var before_auto_plan: Dictionary = sim.world.freeze()
	var auto_plan: CommandResult = _command(sim,"clinical_auto_plan",{"visit_id":visit_id})
	var auto_plan_rejected: bool = not auto_plan.accepted and auto_plan.code=="clinical_busy" and before_auto_plan==sim.world.freeze() and sim.world.facts.attempts.get(attempt_id,{})==attempt
	var actual_before: Array = sim.world.facts.actors[visit.actor_id].location.get("cell",[]).duplicate()
	var cleared: bool = _wait(sim,func() -> bool: return sim.services.remodel.preview(sim.world,order_id).get("ok",false),500)
	var actual_after: Array = sim.world.facts.actors[visit.actor_id].location.get("cell",[]).duplicate()
	var retained: bool = sim.world.facts.attempts.get(attempt_id,{})==attempt and sim.world.facts.inventory.issues==issues
	var released_use: Dictionary = HospitalEquipmentUse.query(sim.world,str(session.facility_id))
	var equipment_handoff: bool = use_readonly and active_use.placed and active_use.occupied and not active_use.critical_commitment and released_use.placed and not released_use.occupied
	return _done(sim,begun and preserved and auto_plan_rejected and cleared and actual_after!=actual_before and retained and equipment_handoff,{"equipment_handoff":equipment_handoff,"active_use":active_use,"released_use":released_use,"bed_layouts":bed_layouts,"prepared":prepare.to_record(),"preserved":preserved,"auto_plan":auto_plan.to_record(),"auto_plan_rejected_without_mutation":auto_plan_rejected,"cleared_by_real_movement":cleared,"before":actual_before,"after":actual_after,"remaining":suspension.get("remaining_ticks"),"reason":sim.services.remodel.preview(sim.world,order_id).get("reason","")})

func _case_36(_t) -> Dictionary:
	var sim: HospitalSimulation = _surgery_fixture()
	var clinical_tick: Callable = func() -> void: ClinicalStep.step(sim,true)
	var required_staff: Array[String] = ["surgeon","anesthetist","or_nurse","ward_nurse","round_doctor","starter_doctor_a"]
	var preparation_complete: Callable = func() -> bool:
		for staff_id: String in required_staff:
			var staff: Dictionary = sim.world.facts.staff[staff_id]
			if not staff.get("on_shift",false): continue
			if not staff.get("base_prepared",false) or not staff.get("base_task",{}).is_empty() or staff.get("block_new_work",false) or sim.world.facts.moves.has(staff_id): return false
		return true
	var bases_ready: bool = _wait(sim,preparation_complete,1800,clinical_tick)
	if not bases_ready:
		var preparation_facts: Dictionary = {}
		for staff_id: String in required_staff:
			var staff: Dictionary = sim.world.facts.staff[staff_id]
			preparation_facts[staff_id] = {"on_shift":staff.get("on_shift",false),"base_prepared":staff.get("base_prepared",false),"base_task":staff.get("base_task",{}).duplicate(true),"block_new_work":staff.get("block_new_work",false),"location":sim.world.facts.actors[staff_id].location.duplicate(true),"move":sim.world.facts.moves.get(staff_id,{}).duplicate(true)}
		return _done(sim,false,{"prerequisite":"当班手术、病房及诊室医护未完成实际共享基地整理","tick":sim.world.sim_tick,"staff":preparation_facts})
	var arrival: CommandResult = _command(sim,"clinical_arrive",{"binding_id":"B_S13_D09_M09","arrival_key":"space_actual_surgery","requested_plan_id":"P_D09_SURGERY"})
	var visit_id: String = str(arrival.changed_ids[0]) if arrival.accepted else ""
	if not arrival.accepted: return _done(sim,false,{"prerequisite":"合法手术病例实际入院","arrival":arrival.to_record()})
	# Diagnosis and base preparation are saved-world inputs, outside this remodel
	# handoff. The chosen team still operates, wakes and transfers here.
	_command(sim,"clinical_visit_consent",{"visit_id":visit_id,"allow":false})
	var input_visit: Dictionary = sim.world.facts.visits[visit_id]
	var input_actor: Dictionary = sim.world.facts.actors[input_visit.actor_id]
	input_actor.location.cell = [44,76]
	sim.space.sync_actor(sim.world,input_actor.id)
	var diagnostic: Dictionary = sim.world.facts.staff.starter_doctor_a
	var profile: Dictionary = content.catalog.profiles[content.definition("diseases",input_visit.disease_id).profile]
	input_visit.evidence_by_source = {"gp":float(profile.gp_confidence)+2.0*(int(diagnostic.abilities.diagnosis)-1)}
	input_visit.doctor_fee_quote = content.doctor_fee(diagnostic.title_id)
	input_visit.clinical_participants = {diagnostic.id:true}
	sim.clinic._queue(sim.world,input_visit,"consult")
	HospitalLedger.post(sim.world,LedgerEntry.new(visit_id,"consultation",int(input_visit.doctor_fee_quote)))
	HospitalLedger.post(sim.world,LedgerEntry.new(visit_id,"gp",5))
	var history_id: String = visit_id+":given_gp"
	diagnostic.completed_jobs[history_id] = "diagnosis"
	diagnostic.practice.diagnosis += 1
	var gp: Dictionary = sim.world.facts.facilities.gp_station
	gp.used = true
	gp.use_receipts[history_id] = sim.world.sim_tick
	gp.condition -= 2.0
	sim.world.touch()
	var input_validation: String = sim.world.validate(content)
	print("CASE_INPUT SPACE-36 "+JSON.stringify({"kind":"diagnosed_waiting_for_surgery_selection","prior_diagnostics_and_base_preparation":"input","validation":input_validation}))
	if not input_validation.is_empty(): return _done(sim,false,{"prerequisite":"已诊断手术候诊输入无效","validation":input_validation})
	var bed_roles_ready: bool = true
	var bed_role_quotes: Array = []
	for facility_id: String in sim.world.ids("facilities"):
		if sim.world.facts.facilities[facility_id].definition_id!="EQ05": continue
		var fit: Dictionary = sim.space.facility_quote(sim.world,facility_id,sim.world.facts.visits[visit_id].actor_id,["ward_nurse","round_doctor"])
		var row: Dictionary = {"bed_id":facility_id,"fit":fit.get("ok",false),"reason":fit.get("reason",""),"operators":fit.get("operator_cells",[])}
		var usable: bool = fit.get("ok",false) and fit.get("operator_cells",[]).size()==2
		if usable:
			row.patient_route = sim.space.route(sim.world,sim.world.facts.visits[visit_id].actor_id,1,fit.patient_cell,[],{},true).ok
			row.nurse_route = sim.space.route(sim.world,"ward_nurse",1,fit.operator_cells[0],[],{},true).ok
			row.doctor_route = sim.space.route(sim.world,"round_doctor",1,fit.operator_cells[1],[],{},true).ok
			usable = row.patient_route and row.nurse_route and row.doctor_route and fit.operator_cells[0]==fit.operator_cells[1]
		bed_roles_ready = bed_roles_ready and usable
		bed_role_quotes.append(row)
	bed_roles_ready = bed_roles_ready and bed_role_quotes.size()==2
	var selected: CommandResult = _command(sim,"clinical_select_plan",{"visit_id":visit_id,"plan_id":"P_D09_SURGERY"})
	if selected.accepted:
		# This scenario starts immediately before the remodel command, with a
		# gathered team and one setup tick left. CLIN-18 tests the earlier full
		# gathering/setup; all surgery and recovery work below still executes.
		sim.clinic.dispatch(sim.world)
		var preparation: Dictionary = sim.world.facts.preparations.get(visit_id,{})
		if preparation.is_empty(): return _done(sim,false,{"prerequisite":"手术未取得真实准备束"})
		var table: Dictionary = sim.space.facility_layout(sim.world,preparation.facility_id)
		var positions: Dictionary = {input_visit.actor_id:table.patient_cell}
		for index: int in preparation.staff_ids.size(): positions[preparation.staff_ids[index]] = table.operator_cells[index]
		for actor_id: String in positions:
			sim.world.facts.moves.erase(actor_id)
			sim.world.facts.actors[actor_id].location = {"kind":"floor","floor_id":1,"cell":positions[actor_id].duplicate(),"height_m":0.0}
		preparation.setup_remaining_ticks = 1
		sim.world.touch()
		var ready_validation: String = sim.world.validate(content)
		print("CASE_INPUT SPACE-36 "+JSON.stringify({"kind":"gathered_surgical_team","setup_remaining_ticks":1,"prior_travel_and_setup":"input","validation":ready_validation}))
		if not ready_validation.is_empty(): return _done(sim,false,{"prerequisite":"到齐的手术准备输入无效","validation":ready_validation})
	var begun: bool = selected.accepted and _wait(sim,func() -> bool: return not _session(sim,"surgery").is_empty(),1800,clinical_tick)
	if not begun:
		var snapshot_path: String = "res://space36-plan-blocked.json"
		var encoder: HospitalJsonStream = HospitalJsonStream.new()
		var saved: bool = encoder.encode(snapshot_path,sim.world.freeze(),func(_bytes: int) -> bool: return true)
		var clinical_staff: Dictionary = {}
		for staff_id: String in sim.world.ids("staff"):
			var staff: Dictionary = sim.world.facts.staff[staff_id]
			if not staff.role in ["doctor","nurse"]: continue
			clinical_staff[staff_id] = {"role":staff.role,"ward_id":staff.get("ward_id",""),"location":sim.world.facts.actors[staff_id].location.duplicate(true),"on_shift":staff.get("on_shift",false),"scheduled_kind":staff.get("scheduled_kind",""),"abilities":staff.abilities.duplicate(true),"base_prepared":staff.get("base_prepared",false),"base_task":staff.get("base_task",{}).duplicate(true),"block_new_work":staff.get("block_new_work",false),"move":sim.world.facts.moves.get(staff_id,{}).duplicate(true)}
		var beds: Dictionary = {}
		for facility_id: String in sim.world.ids("facilities"):
			var facility: Dictionary = sim.world.facts.facilities[facility_id]
			if facility.definition_id=="EQ05": beds[facility_id] = {"bed":facility.duplicate(true),"ward":sim.world.facts.rooms.get(facility.get("room_id",""),{}).duplicate(true)}
		return _done(sim,false,{"prerequisite":"实际手术未开工","arrival":arrival.to_record(),"selected_plan":selected.to_record(),"visit":sim.world.facts.visits.get(visit_id,{}),"tick":sim.world.sim_tick,"world_path":ProjectSettings.globalize_path(snapshot_path),"world_saved":saved,"world_save_error":encoder.error,"clinical_staff":clinical_staff,"beds":beds})
	var session: Dictionary = _session(sim,"surgery").duplicate(true)
	var attempt_id: String = str(session.get("attempt_id",""))
	var attempt: Dictionary = sim.world.facts.attempts[attempt_id].duplicate(true)
	var issues: Dictionary = sim.world.facts.inventory.issues.duplicate(true)
	var bed_id: String = str(attempt.get("bed_id",""))
	var ward_id: String = str(sim.world.facts.facilities.get(bed_id,{}).get("room_id",""))
	var before_use: Dictionary = sim.world.freeze()
	var reserved_use: Dictionary = HospitalEquipmentUse.query(sim.world,bed_id)
	var equipment_handoff: bool = before_use==sim.world.freeze() and reserved_use.placed and reserved_use.occupied and reserved_use.critical_commitment
	var operating_id: String = str(sim.world.facts.facilities[session.facility_id].room_id)
	var prepared: CommandResult = _prepare(sim,[operating_id,ward_id],1,[34,66])
	var order_id: String = str(prepared.changed_ids[0]) if prepared.accepted else ""
	var blocked: Dictionary = sim.services.remodel.preview(sim.world,order_id)
	var transfer: bool = _wait(sim,func() -> bool: return not sim.world.facts.ward_stays.is_empty() and sim.world.facts.ward_stays.values()[0].get("phase")=="recovery",2600,clinical_tick)
	var still_blocked: Dictionary = sim.services.remodel.preview(sim.world,order_id)
	var stay: Dictionary = sim.world.facts.ward_stays.values()[0] if not sim.world.facts.ward_stays.is_empty() else {}
	var promise_preserved: bool = true
	var final_attempt: Dictionary = sim.world.facts.attempts.get(attempt_id,{})
	for field: String in ["id","visit_id","plan_id","result","probability_bp","work_ticks","supply_units","staff_ids","bed_id"]:
		promise_preserved = promise_preserved and _canonical(final_attempt.get(field))==_canonical(attempt.get(field))
	var protected: bool = prepared.accepted and not blocked.get("ok",true) and transfer and not still_blocked.get("ok",true) and stay.get("attempt_id")==attempt_id and stay.get("bed_id")==bed_id and promise_preserved and sim.world.facts.inventory.issues==issues and sim.world.facts.actors[sim.world.facts.visits[visit_id].actor_id].get("support_facility_id")==bed_id
	var recovery_stay: Dictionary = stay.duplicate(true)
	var recovery_use: Dictionary = HospitalEquipmentUse.query(sim.world,bed_id)
	equipment_handoff = equipment_handoff and recovery_use.occupied and recovery_use.critical_commitment
	var care_tick: int = -1
	var round_tick: int = -1
	var round_record: Dictionary = {}
	var round_work: Dictionary = {}
	var nurse_moved_after_care: bool = false
	var sequence_legal: bool = true
	if protected:
		var nurse_id: String = str(stay.nurse_id)
		var previous: Array = sim.world.facts.actors[nurse_id].location.cell.duplicate()
		for index: int in 2400:
			var current_stay: Dictionary = sim.world.facts.ward_stays.get(attempt_id,{})
			var location: Dictionary = sim.world.facts.actors[nurse_id].location
			var displacement: float = Vector2(float(previous[0]),float(previous[1])).distance_to(Vector2(float(location.cell[0]),float(location.cell[1])))
			if care_tick>=0 and current_stay.get("care_completed",false) and displacement>0.001:
				nurse_moved_after_care = true
				sequence_legal = sequence_legal and displacement<=float(content.balance.movement_speeds["1"])*WorldState.TICK_SECONDS+0.001
			previous = location.cell.duplicate()
			var layout: Dictionary = sim.space.facility_layout(sim.world,bed_id)
			for active: Dictionary in sim.world.facts.sessions.values():
				if active.get("stay_id","")!=attempt_id: continue
				if active.kind=="care":
					if care_tick<0: care_tick = sim.world.sim_tick
					sequence_legal = sequence_legal and sim.space.at(sim.world,nurse_id,1,layout.operator_cells[0])
				elif active.kind=="round":
					round_tick = sim.world.sim_tick
					round_record = active.duplicate(true)
					round_work = active
					var doctor_id: String = str(active.staff_ids[0])
					sequence_legal = sequence_legal and care_tick>=0 and current_stay.get("care_completed",false) and nurse_moved_after_care and layout.operator_cells[0]==layout.operator_cells[1] and sim.space.at(sim.world,doctor_id,1,layout.operator_cells[1]) and not sim.space.at(sim.world,nurse_id,1,layout.operator_cells[1]) and not sim.space.body_rectangle(sim.world.facts.actors[nurse_id]).intersects(sim.space.body_rectangle(sim.world.facts.actors[doctor_id]),false)
			if round_tick>=0: break
			clinical_tick.call()
	var completion: Dictionary = {"round_finished":false,"patient_departed":false,"bed_released":false,"arrangement_pending":true,"blocked_until_release":true,"no_early_settlement":true}
	if round_tick>=0:
		for index: int in 1200:
			var visit: Dictionary = sim.world.facts.visits[visit_id]
			var actor: Dictionary = sim.world.facts.actors[visit.actor_id]
			var order: Dictionary = sim.world.facts.remodels[order_id]
			completion.arrangement_pending = completion.arrangement_pending and order.state=="preparing"
			if sim.world.facts.sessions.has(str(round_record.get("id",""))):
				completion.no_early_settlement = completion.no_early_settlement and not sim.world.facts.ledger.entries.has(attempt_id+":ward") and not sim.world.facts.ledger.entries.has(visit_id+":cure")
			if sim.world.facts.ward_stays.has(attempt_id) or sim.world.facts.adaptations.has(bed_id):
				completion.blocked_until_release = completion.blocked_until_release and not sim.services.remodel._waiting(sim.world,order).is_empty()
			completion.round_finished = not sim.world.facts.sessions.has(str(round_record.get("id",""))) and int(round_work.get("remaining_ticks",-1))==0 and visit.get("final_result","")=="cured" and visit.get("result_receipt",{}).get("attempt_id","")==attempt_id
			completion.patient_departed = visit.phase=="departed" and actor.location.kind=="outside"
			completion.bed_released = not sim.world.facts.ward_stays.has(attempt_id) and not sim.world.facts.adaptations.has(bed_id) and actor.get("support_facility_id","")!=bed_id
			var current_use: Dictionary = HospitalEquipmentUse.query(sim.world,bed_id)
			if completion.round_finished:
				equipment_handoff = equipment_handoff and not current_use.critical_commitment
			if not completion.bed_released:
				equipment_handoff = equipment_handoff and current_use.occupied
			if completion.round_finished and completion.patient_departed and completion.bed_released: break
			clinical_tick.call()
	var charges: Dictionary = {"surgery":0,"ward":0,"cure":0}
	var charge_counts: Dictionary = {"surgery":0,"ward":0,"cure":0}
	var charges_settled: bool = true
	for entry: Dictionary in sim.world.facts.ledger.entries.values():
		if not str(entry.owner_id) in [attempt_id,visit_id] or not charges.has(str(entry.component)): continue
		charges[entry.component] += int(entry.amount)
		charge_counts[entry.component] += 1
		charges_settled = charges_settled and bool(entry.settled)
	var settlement: bool = charges_settled and charges=={"surgery":60,"ward":60,"cure":360} and charge_counts=={"surgery":1,"ward":1,"cure":1}
	var settled_entries: Dictionary = sim.world.facts.ledger.entries.duplicate(true)
	if completion.round_finished:
		sim.clinic._complete_service(sim.world,round_record)
		HospitalLedger.settle(sim.world)
	var unique_settlement: bool = completion.round_finished and sim.world.facts.ledger.entries==settled_entries
	for field: String in ["id","visit_id","plan_id","result","probability_bp","work_ticks","recovery_ticks","supply_units","staff_ids","bed_id","facility_fee","ward_fee","cure_fee"]:
		promise_preserved = promise_preserved and _canonical(sim.world.facts.attempts.get(attempt_id,{}).get(field))==_canonical(attempt.get(field))
	var same_case: bool = sim.world.facts.visits[visit_id].attempt_ids==[attempt_id] and sim.world.facts.inventory.issues==issues
	var arrangement_retained: bool = sim.world.facts.remodels.get(order_id,{}).get("state","")=="preparing" and completion.arrangement_pending and completion.blocked_until_release
	var validation: String = sim.world.validate(content)
	equipment_handoff = equipment_handoff and not HospitalEquipmentUse.query(sim.world,bed_id).occupied
	var passed: bool = equipment_handoff and protected and bed_roles_ready and care_tick>=0 and round_tick>care_tick and nurse_moved_after_care and sequence_legal and promise_preserved and same_case and arrangement_retained and completion.round_finished and completion.patient_departed and completion.bed_released and completion.no_early_settlement and settlement and unique_settlement and validation.is_empty()
	var final_scene: Dictionary = {}
	if not passed:
		var actual_stay: Dictionary = sim.world.facts.ward_stays.get(attempt_id,{}).duplicate(true)
		var staff_facts: Dictionary = {}
		for staff_id: String in sim.world.ids("staff"):
			var staff: Dictionary = sim.world.facts.staff[staff_id]
			if not staff.role in ["doctor","nurse"]: continue
			var record: Dictionary = staff.duplicate(true)
			record.location = sim.world.facts.actors[staff_id].location.duplicate(true)
			record.move = sim.world.facts.moves.get(staff_id,{}).duplicate(true)
			record.can_start = sim.clinic._can_start(sim.world,staff)
			record.clinically_busy = sim.clinic._staff_busy(sim.world,staff_id)
			staff_facts[staff_id] = record
		var coverage: bool = sim.clinic._ward_covering(sim.world,actual_stay) if not actual_stay.is_empty() else false
		var snapshot_path: String = "res://space36-care-blocked.json"
		var encoder: HospitalJsonStream = HospitalJsonStream.new()
		var saved: bool = encoder.encode(snapshot_path,sim.world.freeze(),func(_bytes: int) -> bool: return true)
		final_scene = {"tick":sim.world.sim_tick,"world_path":ProjectSettings.globalize_path(snapshot_path),"world_saved":saved,"world_save_error":encoder.error,"visit":sim.world.facts.visits[visit_id].duplicate(true),"stay":actual_stay,"ward_covering":coverage,"staff":staff_facts,"sessions":sim.world.facts.sessions.duplicate(true),"bed_layout":sim.space.facility_layout(sim.world,bed_id).duplicate(true),"adaptation":sim.world.facts.adaptations.get(bed_id,{}).duplicate(true)}
	return _done(sim,passed,{"equipment_handoff":equipment_handoff,"reserved_use":reserved_use,"recovery_use":recovery_use,"selected_plan":selected.to_record(),"bed_role_quotes":bed_role_quotes,"prepared":prepared.to_record(),"initial_block":blocked.get("reason"),"real_transfer":transfer,"promise_preserved":promise_preserved,"stay_at_transfer":recovery_stay,"final_block":still_blocked.get("reason"),"protected":protected,"care_tick":care_tick,"round_tick":round_tick,"nurse_moved_after_care":nurse_moved_after_care,"sequence_legal":sequence_legal,"completion":completion,"charges":charges,"charge_counts":charge_counts,"unique_settlement":unique_settlement,"same_case":same_case,"arrangement_retained":arrangement_retained,"validation":validation,"final_scene":final_scene})

func _case_37(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_history_height(sim,2)
	_command(sim,"build_room",_room("identity_room",[35,68],[6,6]))
	_command(sim,"build_facility",{"id":"identity_asset","definition_id":"M37","floor_id":1,"cell":[37,70],"room_id":"identity_room"})
	var source: Dictionary = sim.world.facts.facilities.get("identity_asset",{})
	source.grade = 1
	source.completed_upgrade_paid_cost = 125
	source.condition = 42.0
	source.failed = true
	source.used = true
	source.style = "fixture_original"
	var before: Dictionary = source.duplicate(true)
	var room_before: Dictionary = sim.world.facts.rooms.identity_room.duplicate(true)
	var cash: int = HospitalLedger.balance(sim.world)
	var prepared: CommandResult = _prepare(sim,["identity_room"],2,[45,68],false,1)
	var id: String = str(prepared.changed_ids[0]) if prepared.accepted else ""
	var plan: Dictionary = sim.services.remodel.preview(sim.world,id)
	var applied: CommandResult = _command(sim,"remodel_apply",{"order_id":id,"quote":_remodel_quote(plan)})
	var after: Dictionary = sim.world.facts.facilities.get("identity_asset",{})
	var unchanged: bool = true
	for field: String in ["id","definition_id","paid_cost","completed_upgrade_paid_cost","condition","failed","used","grade","style"]: unchanged = unchanged and before.get(field)==after.get(field)
	return _done(sim,prepared.accepted and applied.accepted and unchanged and sim.world.facts.rooms.identity_room.id==room_before.id and sim.world.facts.rooms.identity_room.floor_id==2 and after.get("floor_id")==2 and HospitalLedger.balance(sim.world)==cash and sim.world.facts.floors.completed_top_floor["1:2"]==2,{"prepared":prepared.to_record(),"applied":applied.to_record(),"before":before,"after":after})

func _case_38(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_command(sim,"build_room",_room("surface_room",[35,68],[6,6]))
	# Completed paid surfaces are historical input; the move must never reconstruct their payment or work.
	sim.world.facts.environment.surfaces["1:36:69:floor:"] = {"id":"surface_original","floor_id":1,"cell":[36,69],"surface":"floor","edge":"","material_id":"MAT01","paid_cost":25,"completed_tick":0}
	sim.world.facts.environment.surfaces["1:46:69:floor:"] = {"id":"surface_target","floor_id":1,"cell":[46,69],"surface":"floor","edge":"","material_id":"MAT02","paid_cost":35,"completed_tick":0}
	var prepared: CommandResult = _prepare(sim,["surface_room"],1,[45,68])
	var id: String = str(prepared.changed_ids[0]) if prepared.accepted else ""
	var plan: Dictionary = sim.services.remodel.preview(sim.world,id)
	var cash: int = HospitalLedger.balance(sim.world)
	var payload: Dictionary = {"order_id":id,"quote":_remodel_quote(plan)}
	var applied: CommandResult = _command(sim,"remodel_apply",payload,"space_surface_apply")
	var after: Dictionary = sim.world.freeze()
	var repeat: CommandResult = _command(sim,"remodel_apply",payload,"space_surface_apply")
	var surface: Dictionary = sim.world.facts.environment.surfaces.get("1:46:69:floor:",{})
	return _done(sim,prepared.accepted and plan.get("ok",false) and int(plan.get("refund",-1))==28 and applied.accepted and HospitalLedger.balance(sim.world)-cash==28 and surface.get("id")=="surface_original" and surface.get("paid_cost")==25 and not sim.world.facts.environment.surfaces.has("1:36:69:floor:") and repeat.accepted and after==sim.world.freeze(),{"quote":_public_quote(plan),"surface":surface,"repeat":repeat.to_record()})

func _case_39(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var valid: bool = true
	var errors: Dictionary = {}
	var count: int = 0
	for definition: Dictionary in content.catalog.blueprint_presets:
		var result: Dictionary = sim.services.blueprints.builtin(definition.id)
		var reason: String = sim.services.blueprints.validate_definition(result.get("blueprint",{}))
		valid = valid and result.get("ok",false) and reason.is_empty()
		errors[definition.id] = reason
		count += 1
	_command(sim,"build_room",_room("capture_room",[35,68]))
	_command(sim,"build_facility",{"id":"capture_asset","definition_id":"SE02","floor_id":1,"cell":[36,69],"room_id":"capture_room"})
	var before: Dictionary = sim.world.freeze()
	var captured: Dictionary = sim.services.blueprints.capture(sim.world,["capture_room"],[],"空间验收蓝图")
	var blueprint: Dictionary = captured.get("blueprint",{})
	var readonly: bool = before==sim.world.freeze()
	var prohibited: bool = false
	for field: String in ["actors","staff","visits","attempts","ledger","inventory","connectors","floors","remodels"]: prohibited = prohibited or blueprint.has(field)
	var ward: Dictionary = sim.services.blueprints.builtin("BP06").get("blueprint",{}).duplicate(true)
	var missing: Dictionary = ward.duplicate(true)
	missing.bed_links = []
	var duplicate: Dictionary = ward.duplicate(true)
	if not duplicate.get("bed_links",[]).is_empty(): duplicate.bed_links.append(duplicate.bed_links[0].duplicate(true))
	return _done(sim,count==9 and valid and captured.get("ok",false) and readonly and not prohibited and blueprint.get("rooms",[]).size()==1 and blueprint.get("objects",[]).size()==1 and blueprint.rooms[0].cells.has([0,0]) and not sim.services.blueprints.validate_definition(missing).is_empty() and not sim.services.blueprints.validate_definition(duplicate).is_empty(),{"builtins":errors,"captured":blueprint})

func _case_40(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var initial_inventory: Dictionary = sim.world.facts.inventory.build_items.duplicate(true)
	for data: Array in [["a_failed",true,false,false],["b_normal",false,false,false],["c_normal",false,false,false],["a_reserved",false,true,false],["a_borrowed",false,false,true]]:
		_command(sim,"build_facility",{"id":data[0],"definition_id":"SE02","floor_id":1,"cell":[44,72]})
		var item: Dictionary = sim.world.facts.facilities.get(str(data[0]),{})
		item.failed = data[1]
		item.reserved = data[2]
		item.borrowed = data[3]
		item.condition = 47.0
		item.used = true
		_command(sim,"build_store",{"target_id":data[0]})
	var blueprint: Dictionary = _object_blueprint("SE02")
	var payload: Dictionary = {"blueprint":blueprint,"floor_id":1,"cell":[44,78]}
	var before: Dictionary = sim.world.freeze()
	var plan: Dictionary = sim.services.blueprints.preview(sim.world,payload)
	var readonly: bool = before==sim.world.freeze()
	payload.quote = _blueprint_quote(plan)
	var cash: int = HospitalLedger.balance(sim.world)
	var original: Dictionary = sim.world.facts.inventory.build_items.get("b_normal",{}).duplicate(true)
	var placed: CommandResult = _command(sim,"blueprint_place",payload)
	var asset: Dictionary = sim.world.facts.facilities.get("b_normal",{})
	var initial_preserved: bool = true
	for inventory_id: String in initial_inventory:
		initial_preserved = initial_preserved and sim.world.facts.inventory.build_items.get(inventory_id,{})==initial_inventory[inventory_id]
	return _done(sim,readonly and plan.get("ok",false) and plan.get("inventory_choices",[{}])[0].get("inventory_id")=="b_normal" and int(plan.get("purchase_cost",-1))==0 and placed.accepted and HospitalLedger.balance(sim.world)==cash and not sim.world.facts.inventory.build_items.has("b_normal") and sim.world.facts.inventory.build_items.size()==initial_inventory.size()+4 and initial_preserved and asset.get("id")=="b_normal" and asset.get("paid_cost")==original.get("paid_cost") and asset.get("condition")==47.0 and asset.get("used")==original.get("used") and not asset.get("failed",true),{"plan":_public_quote(plan),"chosen":plan.get("inventory_choices",[]),"asset":asset,"initial_inventory_count":initial_inventory.size(),"remaining_inventory_count":sim.world.facts.inventory.build_items.size(),"initial_inventory_preserved":initial_preserved})

func _case_41(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	_command(sim,"build_facility",{"id":"preferred_stock","definition_id":"SE02","floor_id":1,"cell":[44,72]})
	_command(sim,"build_store",{"target_id":"preferred_stock"})
	var payload: Dictionary = {"blueprint":_object_blueprint("SE02"),"floor_id":1,"cell":[44,78]}
	var quote: Dictionary = sim.services.blueprints.preview(sim.world,payload)
	payload.quote = _blueprint_quote(quote)
	sim.world.facts.inventory.build_items.preferred_stock.reserved = true
	sim.world.touch()
	var before: Dictionary = sim.world.freeze()
	var changed: CommandResult = _command(sim,"blueprint_place",payload)
	var identity_atomic: bool = not changed.accepted and before==sim.world.freeze()
	var large: Dictionary = _object_blueprint("SE02")
	large.objects.clear()
	for index: int in 70: large.objects.append({"local_id":"item_%03d"%index,"definition_id":"SE02","cell":[index%10*2,index/10*2],"rotation":0,"grade":0,"style":"","room_ref":""})
	var block: CommandResult = _command(sim,"build_facility",{"id":"late_blocker","definition_id":"SE02","floor_id":1,"cell":[52,80]})
	before = sim.world.freeze()
	var late: Dictionary = sim.services.blueprints.preview(sim.world,{"blueprint":large,"cell":[34,68],"floor_id":1,"use_inventory":false})
	var unowned: Dictionary = sim.services.blueprints.preview(sim.world,{"blueprint":_object_blueprint("SE02"),"cell":[44,78],"floor_id":2})
	return _done(sim,quote.get("ok",false) and identity_atomic and block.accepted and not late.get("ok",true) and not unowned.get("ok",true) and before==sim.world.freeze(),{"changed_inventory":changed.to_record(),"late_obstacle":late.get("reason"),"unowned":unowned.get("reason")})

func _case_42(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var blueprint: Dictionary = _object_blueprint("SE02")
	blueprint.objects.clear()
	for y: int in 9:
		for x: int in 8: blueprint.surfaces.append({"cell":[x,y],"surface":"floor","edge":"","material_id":"MAT01"})
	var payload: Dictionary = {"blueprint":blueprint,"floor_id":1,"cell":[35,68],"include_surfaces":true}
	var before: Dictionary = sim.world.freeze()
	var missing: Dictionary = sim.services.blueprints.preview(sim.world,payload)
	var atomic: bool = before==sim.world.freeze() and not missing.get("ok",true)
	_add_staff(sim,"decorator","decorator",[48,80])
	var tool: CommandResult = _command(sim,"build_facility",{"id":"tool","definition_id":"SE02","floor_id":1,"cell":[47,80]})
	var plan: Dictionary = sim.services.blueprints.preview(sim.world,payload)
	payload.quote = _blueprint_quote(plan)
	var cash: int = HospitalLedger.balance(sim.world)
	var applied: CommandResult = _command(sim,"blueprint_place",payload)
	var units: int = 0
	var bounded: bool = true
	for order: Dictionary in sim.world.facts.environment.orders.values():
		units += order.units.size()
		bounded = bounded and order.units.size()<=64 and order.phase!="completed"
	return _done(sim,atomic and tool.accepted and plan.get("ok",false) and applied.accepted and units==72 and bounded and sim.world.facts.environment.orders.size()==2 and sim.world.facts.environment.surfaces.is_empty() and cash-HospitalLedger.balance(sim.world)==72*25,{"missing":missing.get("reason"),"plan":_public_quote(plan),"orders":sim.world.facts.environment.orders.keys(),"units":units})

func _case_43(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var library: HospitalBlueprintLibrary = HospitalBlueprintLibrary.new(sim.services.blueprints)
	var saved: Dictionary = library.save(_object_blueprint("SE02"),"空间验收临时蓝图","仅本专项创建")
	if not saved.get("ok",false): return _done(sim,false,{"save":saved})
	var blueprint: Dictionary = saved.blueprint
	var before: Dictionary = sim.world.freeze()
	var revised: Dictionary = library.save(blueprint,"空间验收修订","修订2")
	var old_revision: Dictionary = library.save(blueprint,"过期修订","不应覆盖")
	var loaded: Dictionary = library.load_blueprint(blueprint.id)
	var temporary_path: String = HospitalBlueprintLibrary.DIRECTORY.path_join(str(blueprint.id)+".json.tmp")
	var directory_created: Error = DirAccess.make_dir_recursive_absolute(temporary_path)
	var write_failed: Dictionary = library.save(revised.get("blueprint",blueprint),"写入失败不得覆盖","保留已保存修订")
	var preserved_file: Dictionary = library.load_blueprint(blueprint.id)
	if directory_created==OK: DirAccess.remove_absolute(temporary_path)
	var readonly: bool = before==sim.world.freeze()
	_command(sim,"build_room",_room("independent",[35,68]))
	var prepare: CommandResult = _prepare(sim,["independent"],1,[45,68],false,0,int(blueprint.revision))
	var order_id: String = str(prepare.changed_ids[0]) if prepare.accepted else ""
	var order: Dictionary = sim.world.facts.remodels.get(order_id,{}).duplicate(true)
	var removed: Dictionary = library.remove(blueprint.id)
	var restored: WorldState = WorldState.new(sim.world.freeze())
	var independent: bool = restored.facts.remodels.get(order_id,{})==order and restored.facts.remodels.get(order_id,{}).get("source_blueprint_revision")==1
	var retained: bool = revised.get("ok",false) and int(revised.get("blueprint",{}).get("revision",0))==2 and not old_revision.get("ok",true) and loaded.get("ok",false) and int(loaded.blueprint.revision)==2
	return _done(sim,retained and readonly and directory_created==OK and not write_failed.get("ok",true) and _canonical(preserved_file.get("blueprint",{}))==_canonical(loaded.get("blueprint",{})) and removed.get("ok",false) and prepare.accepted and independent and loaded.blueprint.get("content_dependencies",[]).size()==1,{"saved_id":blueprint.id,"revised":revised.get("ok"),"stale_rejected":old_revision,"write_failure":write_failed,"independent_arrangement":independent})

func _case_44(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var before_guides: Dictionary = sim.world.freeze()
	var guides: Array = content.catalog.remodel_guides
	var passive: bool = before_guides==sim.world.freeze() and guides.size()==8
	var room: CommandResult = _command(sim,"build_room",_room("resume_room",[35,68]))
	var machine: CommandResult = _command(sim,"build_facility",{"id":"resume_machine","definition_id":"M09","floor_id":1,"cell":[36,69],"room_id":"resume_room"})
	var tool: CommandResult = _command(sim,"build_facility",{"id":"resume_tool","definition_id":"SE02","floor_id":1,"cell":[43,78]})
	if not room.accepted or not machine.accepted or not tool.accepted:
		return _done(sim,false,{"prerequisite":"保养场景未建成","room":room.to_record(),"machine":machine.to_record(),"tool":tool.to_record()})
	sim.world.facts.facilities.resume_machine.condition = 45.0
	var maintenance: CommandResult = _command(sim,"maintenance_order",{"facility_id":"resume_machine"})
	var job_id: String = str(maintenance.changed_ids[0]) if maintenance.accepted else ""
	var partial: bool = maintenance.accepted and _wait(sim,func() -> bool:
		var current: Dictionary = sim.world.facts.maintenance.jobs.get(job_id,{})
		return current.get("started",false) and int(current.get("completed_milli",0))>=1000 and int(current.get("remaining_milli",0))>0,400)
	if not partial: return _done(sim,false,{"prerequisite":"原保养尚未产生实际部分进度","maintenance":maintenance.to_record(),"job":sim.world.facts.maintenance.jobs.get(job_id,{})})
	var original_job: Dictionary = sim.world.facts.maintenance.jobs[job_id].duplicate(true)
	var original_ledger: Dictionary = sim.world.facts.ledger.entries.duplicate(true)
	var original_payment: Dictionary = original_ledger.get(job_id+":maintenance_parts",{})
	var prepare: CommandResult = _prepare(sim,["resume_room"],1,[45,68])
	var order_id: String = str(prepare.changed_ids[0]) if prepare.accepted else ""
	if not prepare.accepted: return _done(sim,false,{"prepare":prepare.to_record(),"job":original_job})
	var game: GameSession = GameSession.new(sim,"space_arrangement_pause")
	game.set_speed(0)
	var saved: Dictionary = sim.world.freeze()
	for index: int in 4: game.advance(0.25)
	var paused: bool = saved==sim.world.freeze()
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(saved),content)
	var saved_job: Dictionary = restored.world.facts.maintenance.jobs.get(job_id,{})
	var preserved: bool = saved_job==original_job and int(original_job.get("total_milli",0))==20000 and int(original_job.get("paid_parts",0))==20 and original_payment.get("amount",0)==-20 and original_payment.get("settled",false) and original_job.get("contributions",{}).get(str(original_job.get("worker_id","")),0)==original_job.get("completed_milli",-1) and restored.world.facts.remodels.get(order_id,{}).get("state","")=="preparing"
	var cleared: bool = _wait(restored,func() -> bool: return restored.services.remodel.preview(restored.world,order_id).get("ok",false),400)
	var held: bool = cleared and saved_job.get("remaining_milli",-1)==original_job.remaining_milli and saved_job.get("completed_milli",-1)==original_job.completed_milli and saved_job.get("contributions",{})==original_job.contributions and restored.world.facts.ledger.entries==original_ledger and restored.world.facts.rooms.resume_room.origin==[35,68] and restored.world.facts.remodels[order_id].state=="preparing"
	var plan: Dictionary = restored.services.remodel.preview(restored.world,order_id)
	var payload: Dictionary = {"order_id":order_id,"quote":_remodel_quote(plan)}
	var applied: CommandResult = _command(restored,"remodel_apply",payload,"space_restored_apply")
	var after: Dictionary = restored.world.freeze()
	var repeated: CommandResult = _command(restored,"remodel_apply",payload,"space_restored_apply")
	var duplicate_safe: bool = repeated.accepted and after==restored.world.freeze()
	# Applying a remodel replaces world.facts; inspect the newly committed job.
	var applied_job: Dictionary = restored.world.facts.maintenance.jobs.get(job_id,{})
	var progress_at_apply: bool = applied_job.get("remaining_milli",-1)==original_job.remaining_milli and applied_job.get("completed_milli",-1)==original_job.completed_milli and applied_job.get("contributions",{})==original_job.contributions and applied_job.get("paid_parts",-1)==original_job.paid_parts and applied_job.get("frozen_class",{})==original_job.frozen_class
	var completed: bool = applied.accepted and _wait(restored,func() -> bool: return restored.world.facts.maintenance.jobs.get(job_id,{}).get("phase","")=="completed",600)
	var final_job: Dictionary = restored.world.facts.maintenance.jobs.get(job_id,{})
	var receipt_id: String = job_id+":maintenance_completed"
	var receipt: Dictionary = restored.world.facts.maintenance.receipts.get(receipt_id,{})
	var final_entries: Dictionary = restored.world.facts.ledger.entries.duplicate(true)
	var expected_entries: Dictionary = original_ledger.duplicate(true)
	expected_entries[order_id+":remodel"] = {"owner_id":order_id,"component":"remodel","amount":0,"tick":int(after.sim_tick),"settled":true}
	var completed_world: Dictionary = restored.world.freeze()
	var completed_repeat: CommandResult = _command(restored,"remodel_apply",payload,"space_restored_apply")
	var same_job: bool = final_job.get("id","")==job_id and final_job.get("facility_id","")=="resume_machine" and final_job.get("total_milli",0)==20000 and final_job.get("completed_milli",0)==20000 and final_job.get("remaining_milli",-1)==0 and final_job.get("paid_parts",0)==20 and restored.world.facts.maintenance.jobs.size()==1
	var once: bool = receipt.get("standard_work_milli",0)==20000 and receipt.get("staff_id","").is_empty() and not str(receipt.get("worker_id","")).is_empty() and restored.world.facts.maintenance.receipts.size()==1 and expected_entries==final_entries and restored.world.freeze()==completed_world
	var validation: String = restored.world.validate(content)
	var ok: bool = passive and partial and paused and preserved and held and plan.get("ok",false) and plan.get("price",-1)==0 and plan.get("refund",-1)==0 and applied.accepted and duplicate_safe and progress_at_apply and completed and same_job and once and completed_repeat.accepted and restored.world.facts.rooms.resume_room.origin==[45,68] and restored.world.facts.facilities.resume_machine.cell==[46,69] and restored.world.facts.remodels[order_id].state=="applied" and validation.is_empty()
	var details: Dictionary = {"guide_count":guides.size(),"partial_job":original_job,"paused":paused,"preserved":preserved,"held_until_apply":held,"apply":applied.to_record(),"repeat":repeated.to_record(),"progress_at_apply":progress_at_apply,"resumed_original_job":final_job.duplicate(true),"receipt":receipt,"paid_once":once,"completed_repeat":completed_repeat.to_record(),"validation":validation}
	restored.dispose()
	return _done(sim,ok,details)

func _remodel_evacuation_contract() -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var built: CommandResult = _command(sim,"build_room",_room("evacuation_source",[35,68],[6,6]))
	_add_staff(sim,"idle_a","doctor",[36,69])
	_add_staff(sim,"idle_b","doctor",[38,69])
	var prepared: CommandResult = _prepare(sim,["evacuation_source"],1,[48,68])
	if not built.accepted or not prepared.accepted:
		return _done(sim,false,{"prerequisite":"两名闲置员工所在的合法源房间与改建安排","build":built.to_record(),"prepare":prepared.to_record()})
	var order_id: String = str(prepared.changed_ids[0])
	var order: Dictionary = sim.world.facts.remodels[order_id]
	var waiting: bool = not sim.services.remodel.preview(sim.world,order_id).get("ok",true)
	sim.services.remodel.dispatch(sim.world)
	var first: Dictionary = sim.world.facts.moves.get("idle_a",{}).duplicate(true)
	var second: Dictionary = sim.world.facts.moves.get("idle_b",{}).duplicate(true)
	var assigned: bool = not first.is_empty() and not second.is_empty()
	var target_legal: bool = assigned
	if assigned:
		var first_rect: Rect2 = sim.space._actor_rect(sim.world.facts.actors.idle_a,Vector2(float(first.target_cell[0]),float(first.target_cell[1])))
		var second_rect: Rect2 = sim.space._actor_rect(sim.world.facts.actors.idle_b,Vector2(float(second.target_cell[0]),float(second.target_cell[1])))
		target_legal = first.target_cell!=second.target_cell and not first_rect.intersects(second_rect,false)
		for movement: Dictionary in [first,second]:
			var actor: Dictionary = sim.world.facts.actors[movement.actor_id]
			var point: Vector2i = Vector2i(int(movement.target_cell[0]),int(movement.target_cell[1]))
			var route: Dictionary = sim.space.route(sim.world,actor.id,1,movement.target_cell)
			target_legal = target_legal and sim.space.static_reason(sim.world,actor,1,point).is_empty() and sim.space._dynamic_clear(sim.world,actor.id,1,sim.space._actor_rect(actor,Vector2(point))) and route.get("ok",false) and route.get("status","")!="contention"
	var arrived: bool = false
	var disjoint: bool = true
	if assigned:
		for index: int in 300:
			sim.services.remodel.dispatch(sim.world)
			_movement_tick(sim)
			disjoint = disjoint and not sim.space.body_rectangle(sim.world.facts.actors.idle_a).intersects(sim.space.body_rectangle(sim.world.facts.actors.idle_b),false)
			if sim.space.at(sim.world,"idle_a",1,first.target_cell) and sim.space.at(sim.world,"idle_b",1,second.target_cell) and sim.world.facts.moves.is_empty():
				arrived = true
				break
	var clear: bool = not sim.services.remodel._in_affected_area(sim.world,order,sim.world.facts.actors.idle_a) and not sim.services.remodel._in_affected_area(sim.world,order,sim.world.facts.actors.idle_b)
	var applicable: Dictionary = sim.services.remodel.preview(sim.world,order_id)
	var not_applied: bool = order.state=="preparing" and sim.world.facts.rooms.evacuation_source.origin==[35,68]
	return _done(sim,waiting and assigned and target_legal and arrived and disjoint and clear and applicable.get("ok",false) and not_applied and sim.world.present_actor_count()==2,{"waiting":waiting,"first_move":first,"second_move":second,"target_legal":target_legal,"arrived":arrived,"bodies_disjoint":disjoint,"clear":clear,"applicable":_public_quote(applicable),"not_applied":not_applied,"tick":sim.world.sim_tick})

func _case_46(_t) -> Dictionary:
	var sim: HospitalSimulation = _fixture()
	var placed: CommandResult = _command(sim,"build_facility",{"id":"reserved_machine","definition_id":"M37","floor_id":1,"cell":[42,76]})
	if not placed.accepted: return _done(sim,false,placed.to_record())
	var point: Array = sim.space.facility_layout(sim.world,"reserved_machine").patient_cell
	_add_actor(sim,"group_leader","S49",[38,80])
	_add_actor(sim,"reserved_patient","S49",point)
	_add_actor(sim,"replacement_patient","S49",[36,80])
	var reason: String = sim.space.reserve_facility(sim.world,"reserved_machine","reserved_patient","reserved_patient")
	if not reason.is_empty(): return _done(sim,false,{"reservation":reason})
	var leader: Dictionary = sim.world.facts.actors.group_leader
	var original: Array = ["group_leader","reserved_patient"]
	var replacement: Array = ["group_leader","replacement_patient"]
	var offsets: Dictionary = {"group_leader":[0,0],"reserved_patient":[1,0],"replacement_patient":[1,0]}
	var origin: Vector2i = Vector2i(int(point[0]),int(point[1]))
	var before: Dictionary = sim.world.freeze()
	var own_clear: bool = sim.space._navigation.clearance(sim.space,sim.world,1,leader,original,offsets).reason(origin).is_empty()
	var other_blocked: bool = not sim.space._navigation.clearance(sim.space,sim.world,1,leader,replacement,offsets).reason(origin).is_empty()
	var own_again: bool = sim.space._navigation.clearance(sim.space,sim.world,1,leader,original,offsets).reason(origin).is_empty()
	var readonly: bool = before==sim.world.freeze()
	var obstacle: Array = [origin.x+3,origin.y]
	sim.world.facts.floors.overrides["1"].blocked.append(obstacle)
	sim.world.touch()
	var near_clear: bool = sim.space._navigation.clearance(sim.space,sim.world,1,leader,original,offsets).reason(origin).is_empty()
	offsets.reserved_patient = [3,0]
	var changed_offset_blocked: bool = not sim.space._navigation.clearance(sim.space,sim.world,1,leader,original,offsets).reason(origin).is_empty()
	sim.world.facts.floors.overrides["1"].blocked.erase(obstacle)
	sim.world.touch()
	var reopened: bool = sim.space._navigation.clearance(sim.space,sim.world,1,leader,original,offsets).reason(origin).is_empty()
	return _done(sim,own_clear and other_blocked and own_again and readonly and near_clear and changed_offset_blocked and reopened,{"own_reservation":own_clear,"different_patient_blocked":other_blocked,"original_group_restored":own_again,"readonly":readonly,"near_clear":near_clear,"changed_offset_blocked":changed_offset_blocked,"removed_obstacle_reopens":reopened})

func _case_47(_t) -> Dictionary:
	var rectangle: Dictionary = {"origin":[35,68],"size":[6,6]}
	var explicit: Dictionary = rectangle.duplicate(true)
	explicit.cells = BuildGeometry.cells(rectangle)
	var irregular: Dictionary = {"origin":[35,68],"size":[6,6],"cells":[]}
	for y: int in range(68,74):
		for x: int in range(35,41):
			if x<38 or y<71: irregular.cells.append([x,y])
	var inside: Rect2 = Rect2(35.5,68.5,1,1)
	var notch: Rect2 = Rect2(39,72,1,1)
	var crossing: Rect2 = Rect2(37.5,72,1,1)
	var touching: Rect2 = Rect2(41,69,1,1)
	var rectangle_ok: bool = true
	for room: Dictionary in [rectangle,explicit]:
		rectangle_ok = rectangle_ok and BuildGeometry.intersects_room(inside,room) and BuildGeometry.intersects_room(notch,room) and not BuildGeometry.intersects_room(touching,room)
	var exact_shape: bool = BuildGeometry.intersects_room(inside,irregular) and not BuildGeometry.intersects_room(notch,irregular) and BuildGeometry.intersects_room(crossing,irregular) and not BuildGeometry.intersects_room(touching,irregular)
	return {"ok":rectangle_ok and exact_shape,"details":{"rectangular_rooms":rectangle_ok,"irregular_notch_and_crossing":exact_shape}}

func _fixture(preset: bool = false, cash: int = 1000000) -> HospitalSimulation:
	_sequence += 1
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"空间专项 %04d"%_sequence,preset,content)
	return _bind_fixture(world,cash)

func _bind_fixture(world: WorldState, cash: int) -> HospitalSimulation:
	world.facts.ledger.opening_balance = cash+_opening_spend(world)
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	world.facts.arrivals.intake_open = false
	world.facts.arrivals.plan = {
		"day_index":world.sim_tick/WorldState.TICKS_PER_DAY+1,"preset":"normal","scale_numerator":3,
		"shift_capacities":[ArrivalFraction.make(),ArrivalFraction.make(),ArrivalFraction.make()],
		"opportunity_count":0,"shift_opportunity_counts":[0,0,0],"schedule_seed":null,
		"schedule_algorithm":"arrival-load-slot-v1","next_slot_index":0,
		"held_capacity_fraction":ArrivalFraction.make(),"held_scale_numerator":0
	}
	world.facts.hospital_meta.tutorial_flags.enabled = false
	world.facts.inventory.auto_restock = false
	return sim

func _opening_spend(world: WorldState) -> int:
	var result: int = 0
	for entry: Dictionary in world.facts.ledger.entries.values(): result -= int(entry.amount)
	return result

func _floor_fixture() -> HospitalSimulation:
	var sim: HospitalSimulation = _fixture()
	_command(sim,"build_room",_room("below",[35,66]))
	_command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[48,70]})
	_command(sim,"build_facility",{"id":"tool","definition_id":"SE02","floor_id":1,"cell":[40,74]})
	_add_staff(sim,"decorator","decorator",[44,76])
	sim.world.facts.staff.decorator.work_region = {"strict":true,"floor_id":1,"origin":[42,74],"size":[1,1]}
	return sim

func _case_45(_t) -> Dictionary:
	var sim: HospitalSimulation = _transit_fixture()
	var built: CommandResult = _command(sim,"build_facility",{"id":"contractor_upper_machine","definition_id":"M09","floor_id":2,"cell":[45,80]})
	if not built.accepted: return _done(sim,false,{"build":built.to_record()})
	sim.world.facts.facilities.contractor_upper_machine.condition = 45.0
	var ordered: CommandResult = _command(sim,"maintenance_order",{"facility_id":"contractor_upper_machine"})
	if not ordered.accepted: return _done(sim,false,{"order":ordered.to_record()})
	var job_id: String = str(ordered.changed_ids[0])
	var boarded: bool = _wait(sim,func() -> bool:
		var id: String = str(sim.world.facts.maintenance.jobs[job_id].worker_id)
		return not id.is_empty() and sim.world.facts.actors[id].location.kind=="transit",500)
	if not boarded: return _done(sim,false,{"job":sim.world.facts.maintenance.jobs[job_id]})
	var worker_id: String = str(sim.world.facts.maintenance.jobs[job_id].worker_id)
	var cancelled: CommandResult = _command(sim,"maintenance_cancel",{"job_id":job_id})
	var ride_retained: bool = cancelled.accepted and sim.world.facts.actors[worker_id].location.kind=="transit" and sim.world.facts.moves.has(worker_id) and sim.world.facts.connectors[_connection(sim)].riders.has(worker_id)
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(sim.world.freeze()),content)
	sim.dispose()
	sim = restored
	var restore_valid: String = sim.world.validate(content)
	var departed: bool = _wait(sim,func() -> bool: return sim.world.facts.maintenance.contractors[worker_id].phase=="departed",800)
	var job: Dictionary = sim.world.facts.maintenance.jobs[job_id]
	# The default policy can independently buy a replacement at condition 45.
	# Its incoming worker must pass the original worker returning to the exit.
	var not_charged: bool = job.paid_parts==0 and not sim.world.facts.ledger.entries.has(job_id+":maintenance_parts")
	return _done(sim,ride_retained and restore_valid.is_empty() and departed and sim.world.facts.actors[worker_id].location.kind=="outside" and sim.world.facts.staff.is_empty() and job.phase=="cancelled" and not job.started and job.completed_milli==0 and not_charged and sim.world.validate(content).is_empty(),{"ride_retained":ride_retained,"restore_validation":restore_valid,"actual_departure":departed,"cancelled_order_not_charged":not_charged,"job":job.duplicate(true),"worker":sim.world.facts.maintenance.contractors[worker_id].duplicate(true),"actor":sim.world.facts.actors[worker_id].duplicate(true),"movement":sim.world.facts.moves.get(worker_id,{}).duplicate(true),"connection":sim.world.facts.connectors[_connection(sim)].duplicate(true),"all_moves":sim.world.facts.moves.duplicate(true),"all_contractors":sim.world.facts.maintenance.contractors.duplicate(true),"all_actors":sim.world.facts.actors.duplicate(true),"validation":sim.world.validate(content)})

func _transit_fixture() -> HospitalSimulation:
	var sim: HospitalSimulation = _fixture()
	_history_height(sim,2)
	_command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	_command(sim,"connector_extend",{"connection_id":_connection(sim),"floor_id":2})
	return sim

func _bed_blueprint_contract() -> Dictionary:
	var observations: Array = []
	for variant: int in 5:
		var expanded: bool = variant==4
		var turns: int = 0 if expanded else variant
		var sim: HospitalSimulation = _fixture()
		for research: Dictionary in content.catalog.research: sim.world.facts.research.append(research.id)
		var blueprint: Dictionary = sim.services.blueprints.builtin("BP07" if expanded else "BP06").get("blueprint",{})
		var placed: CommandResult = _place_blueprint(sim,blueprint,[35,68])
		if not placed.accepted: return _done(sim,false,{"variant":variant,"placed":placed.to_record()})
		var ward_id: String = str(sim.world.ids("rooms")[0])
		var bed_ids: Array[String] = []
		for facility_id: String in sim.world.ids("facilities"):
			if sim.world.facts.facilities[facility_id].definition_id=="EQ05": bed_ids.append(facility_id)
		if turns>0:
			var rotated: CommandResult = _command(sim,"build_rotate",{"target_id":ward_id,"turns":turns})
			if not rotated.accepted: return _done(sim,false,{"variant":variant,"rotated":rotated.to_record()})
		_add_actor(sim,"bed_subject","S59" if expanded else "S49",[46,89])
		_add_staff(sim,"bed_nurse","nurse",[50,89])
		_add_staff(sim,"bed_doctor","doctor",[54,89])
		if expanded:
			sim.world.facts.actors.bed_nurse.species_id = "S59"
			sim.world.touch()
			sim.space.sync_actor(sim.world,"bed_nurse")
		var initialized: HospitalSimulation = HospitalSimulation.new(sim.world,content)
		sim.dispose()
		sim = initialized
		var ok: bool = bed_ids.size()==(1 if expanded else 2)
		var rows: Array = []
		for index: int in bed_ids.size():
			var bed: Dictionary = sim.world.facts.facilities[bed_ids[index]]
			var expected: Array = [int(bed.cell[0])-3,int(bed.cell[1])+1]
			if not expanded:
				var point: Vector2i = Vector2i(0 if index==0 else 4,2)
				match turns:
					1: point = Vector2i(7-point.y,point.x)
					2: point = Vector2i(7-point.x,7-point.y)
					3: point = Vector2i(point.y,7-point.x)
				expected = [35+point.x,68+point.y]
			var fit: Dictionary = sim.space.facility_quote(sim.world,bed.id,"bed_subject",["bed_nurse","bed_doctor"])
			var row: Dictionary = {"bed_id":bed.id,"rotation":bed.rotation,"fit":fit.get("ok",false),"reason":fit.get("reason",""),"expected_care":expected,"operators":fit.get("operator_cells",[]),"footprint":fit.get("footprint",[])}
			var usable: bool = fit.get("ok",false) and fit.get("operator_cells",[]).size()==2
			if usable:
				row.patient_route = sim.space.route(sim.world,"bed_subject",1,fit.patient_cell,[],{},true).ok
				row.nurse_route = sim.space.route(sim.world,"bed_nurse",1,fit.operator_cells[0],[],{},true).ok
				row.doctor_route = sim.space.route(sim.world,"bed_doctor",1,fit.operator_cells[1],[],{},true).ok
				usable = fit.operator_cells[0]==expected and fit.operator_cells[1]==expected and row.patient_route and row.nurse_route and row.doctor_route
				if expanded: usable = usable and fit.footprint==[3,5]
			ok = ok and usable
			rows.append(row)
		var reservation_reason: String = sim.space.reserve_facility(sim.world,bed_ids[0],"bed_subject","bed_subject",["bed_nurse","bed_doctor"]) if not bed_ids.is_empty() else "缺少病床"
		var snapshot_path: String = "user://acceptance-space-bed-"+HospitalSnapshots.uuid()+".json"
		var budget: Callable = func(_bytes: int) -> bool: return true
		var encoder: HospitalJsonStream = HospitalJsonStream.new()
		var encoded: bool = encoder.encode(snapshot_path,sim.world.freeze(),budget)
		var decoder: HospitalJsonStream = HospitalJsonStream.new()
		var decoded: Dictionary = decoder.decode(snapshot_path,encoder.bytes,encoder.digest,budget) if encoded else {"ok":false,"error":encoder.error}
		if FileAccess.file_exists(snapshot_path): DirAccess.remove_absolute(snapshot_path)
		var validation: String = str(decoded.get("error","未恢复"))
		var preserved: bool = false
		if decoded.get("ok",false):
			var restored: WorldState = WorldState.new(decoded.value)
			validation = restored.validate(content)
			preserved = _canonical(restored.facts.facilities)==_canonical(sim.world.facts.facilities) and _canonical(restored.facts.adaptations)==_canonical(sim.world.facts.adaptations)
		ok = ok and reservation_reason.is_empty() and decoded.get("ok",false) and validation.is_empty() and preserved
		observations.append({"rotation":turns,"expanded_bodies":expanded,"beds":rows,"reservation_reason":reservation_reason,"stream_decoded":decoded.get("ok",false),"validation":validation,"preserved":preserved})
		sim.dispose()
		if not ok: return {"ok":false,"cases":observations}
	return {"ok":true,"cases":observations}

func _surgery_fixture() -> HospitalSimulation:
	_sequence += 1
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"手术整备专项 %04d"%_sequence,true,content)
	# The input hospital employs only this scenario's roles. Remove template
	# hires before constructing services, schedules or any live clinical work.
	for id: String in ["starter_doctor_b","starter_doctor_c","starter_nurse","starter_cleaner"]:
		world.facts.staff.erase(id)
		world.facts.actors.erase(id)
		world.facts.ledger.entries.erase(id+":hire")
	var sim: HospitalSimulation = _bind_fixture(world,1000000)
	sim.clinic.departments = null
	for research: Dictionary in content.catalog.research: sim.world.facts.research.append(research.id)
	for id: String in sim.world.ids("staff"):
		var staff: Dictionary = sim.world.facts.staff[id]
		if staff.role=="doctor":
			staff.title_id = "DT04"
			staff.abilities = {"diagnosis":4,"treatment":4,"care":0,"surgery":0}
	var table: Dictionary = sim.services.blueprints.builtin("BP04").get("blueprint",{})
	var ward: Dictionary = sim.services.blueprints.builtin("BP06").get("blueprint",{})
	_place_blueprint(sim,table,[33,66])
	_place_blueprint(sim,ward,[45,66])
	for data: Array in [["surgeon",[34,76]],["anesthetist",[38,76]],["round_doctor",[51,76]]]:
		_add_staff(sim,str(data[0]),"doctor",data[1])
		var staff: Dictionary = sim.world.facts.staff[str(data[0])]
		staff.title_id = "DT04"
		staff.abilities = {"diagnosis":4,"treatment":4,"care":0,"surgery":0 if data[0]=="round_doctor" else 4}
		var duty: String = "round" if data[0]=="round_doctor" else "surgery"
		staff.schedule = [{"kind":duty,"pools":[],"locked":false},{"kind":duty,"pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	_add_staff(sim,"or_nurse","nurse",[42,76])
	_add_staff(sim,"ward_nurse","nurse",[45,73])
	sim.world.facts.staff.or_nurse.certificates = ["q_or","q_ward"]
	sim.world.facts.staff.or_nurse.abilities.surgery = 3
	sim.world.facts.staff.ward_nurse.certificates = ["q_ward"]
	sim.world.facts.staff.ward_nurse.abilities.care = 4
	for room: Dictionary in sim.world.facts.rooms.values():
		if room.kind=="ward": sim.world.facts.staff.ward_nurse.ward_id = room.id
	for staff: Dictionary in sim.world.facts.staff.values():
		if staff.role in ["doctor","nurse"]:
			staff.base_prepared = true
	sim.world.touch()
	return sim

func _place_blueprint(sim: HospitalSimulation, blueprint: Dictionary, cell: Array) -> CommandResult:
	var payload: Dictionary = {"blueprint":blueprint,"floor_id":1,"cell":cell,"use_inventory":false}
	var plan: Dictionary = sim.services.blueprints.preview(sim.world,payload)
	payload.quote = _blueprint_quote(plan)
	return _command(sim,"blueprint_place",payload)

func _history_height(sim: HospitalSimulation, height: int) -> void:
	# Minimal historical structure: modules were completed continuously, lower empty rooms were legally removed.
	sim.world.facts.floors.completed_top_floor["1:2"] = height
	sim.world.touch()

func _actor(id: String, species_id: String, cell: Array, floor_id: int = 1) -> Dictionary:
	return {"id":id,"name":id,"species_id":species_id,"location":{"kind":"floor","floor_id":floor_id,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}

func _add_actor(sim: HospitalSimulation, id: String, species_id: String, cell: Array, floor_id: int = 1) -> void:
	sim.world.facts.actors[id] = _actor(id,species_id,cell,floor_id)
	sim.world.touch()
	sim.space.sync_actor(sim.world,id)

func _add_staff(sim: HospitalSimulation, id: String, role: String, cell: Array) -> void:
	HospitalFactory._add_staff(sim.world,id,id,role,cell,content)
	sim.world.touch()
	sim.space.sync_actor(sim.world,id)

func _room(id: String, origin: Array, size: Array = [4,4], floor_id: int = 1) -> Dictionary:
	return {"kind":"build_room","id":id,"room_type_id":"gp","floor_id":floor_id,"origin":origin,"size":size,"door":{"definition_id":"DR01","edge":"south","offset":1}}

func _floor_draft(connection_id: String, floor_id: int = 2) -> Dictionary:
	return {"floor_id":floor_id,"plot":[1,2],"source":"lift","connection_id":connection_id}

func _connection(sim: HospitalSimulation) -> String:
	return str(sim.world.ids("connectors")[0]) if not sim.world.facts.connectors.is_empty() else ""

func _order(sim: HospitalSimulation) -> Dictionary:
	var ids: Array = sim.world.facts.floors.orders.keys()
	ids.sort()
	return sim.world.facts.floors.orders[ids[-1]] if not ids.is_empty() else {}

func _active_order(sim: HospitalSimulation) -> Dictionary:
	for order: Dictionary in sim.world.facts.floors.orders.values():
		if not HospitalFloors.terminal(order): return order
	return {}

func _doors(world: WorldState, room_id: String) -> Array:
	var result: Array = []
	for layout: Dictionary in world.facts.floors.overrides.values():
		for door: Dictionary in layout.get("doors",[]):
			if door.room_id==room_id: result.append(door)
	return result

func _command(sim: HospitalSimulation, kind: String, payload: Dictionary, command_id: String = "", expected_revision: int = -1) -> CommandResult:
	_sequence += 1
	var id: String = command_id if not command_id.is_empty() else "space_command_%08d"%_sequence
	return sim.apply(GameCommand.new(id,sim.world.hospital_id,sim.world.revision if expected_revision<0 else expected_revision,kind,BusinessPayload.new(payload)))

func _prepare(sim: HospitalSimulation, rooms: Array, floor_id: int, origin: Array, safe_transfer: bool = false, turns: int = 0, source_revision: int = 0) -> CommandResult:
	var group: Dictionary = sim.services.remodel.group_commands(sim.world,rooms,[],floor_id,origin,turns)
	return _command(sim,"remodel_prepare",{"commands":group.get("commands",[]),"safe_transfer":safe_transfer,"source_blueprint_revision":source_revision})

func _remodel_quote(plan: Dictionary) -> Dictionary:
	return {"price":plan.get("price",-1),"refund":plan.get("refund",-1),"layout":plan.get("layout",[])}

func _blueprint_quote(plan: Dictionary) -> Dictionary:
	return {"price":plan.get("price",-1),"inventory_choices":plan.get("inventory_choices",[])}

func _object_blueprint(definition_id: String) -> Dictionary:
	return {"schema_version":1,"id":"","revision":1,"name":"空间验收布局","description":"","thumbnail":"","content_dependencies":[],"rooms":[],"objects":[{"local_id":"object","definition_id":definition_id,"cell":[0,0],"rotation":0,"grade":0,"style":"","room_ref":""}],"surfaces":[],"bed_links":[]}

func _wait(sim: HospitalSimulation, condition: Callable, maximum_ticks: int, tick: Callable = Callable()) -> bool:
	if condition.call(): return true
	for index: int in maximum_ticks:
		if tick.is_valid(): tick.call()
		else: sim.step()
		if condition.call(): return true
	return false

func _movement_tick(sim: HospitalSimulation) -> void:
	sim.space.advance(sim.world,sim.world.present_actor_count())
	sim.world.facts.sim_tick += 1
	sim.world.touch()
	sim.space.finish_boundary(sim.world)

func _session(sim: HospitalSimulation, kind: String) -> Dictionary:
	for session: Dictionary in sim.world.facts.sessions.values():
		if session.kind==kind: return session
	return {}

func _public_quote(quote: Dictionary) -> Dictionary:
	var result: Dictionary = quote.duplicate()
	for field: String in ["candidate","path","draft"]: result.erase(field)
	return result

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_canonical(item))
		return result
	if value is float and is_finite(value) and floorf(value)==value and absf(value)<9007199254740992.0: return int(value)
	return value

func _done(sim: HospitalSimulation, ok: bool, details: Variant = null) -> Dictionary:
	sim.dispose()
	return {"ok":ok,"details":details}
