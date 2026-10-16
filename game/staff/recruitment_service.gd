class_name RecruitmentService
extends RefCounted

const ROLES: Array[String] = ["receptionist","doctor","nurse","cleaner","researcher","decorator"]
const ORDINARY_ROLES: Array[String] = ["receptionist","cleaner","researcher","decorator"]
var content: HospitalContent
var space: HospitalSpace

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func validate(world: WorldState) -> String:
	var facts: Dictionary = world.facts
	if not facts.get("staff") is Dictionary or not facts.get("actors") is Dictionary or not facts.get("ledger") is Dictionary or not facts.ledger.get("entries") is Dictionary:
		return "招聘员工、身体或账本集合无效"
	var state: Dictionary = {}
	if facts.has("recruitment"):
		if not facts.recruitment is Dictionary:
			return "招聘事实必须是对象"
		state = facts.recruitment
		for field: String in ["standard_ordinals","candidates","active_search","searches"]:
			if not state.get(field) is Dictionary:
				return "招聘集合类型无效："+field
		var today: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
		for field: String in ["last_passive_day","last_notice_day"]:
			if not _saved_integer(state.get(field),0,today):
				return "招聘批次日期无效"
		if state.has("notice") and not state.notice is String:
			return "招聘通知文本无效"
		for key: Variant in state.standard_ordinals:
			if not key is String or not _saved_integer(state.standard_ordinals[key]):
				return "标准候选序号无效"
			var parts: PackedStringArray = key.split("|")
			if parts.size()!=3 or not parts[0] in ROLES:
				return "标准候选筛选键无效"
			if parts[0]=="doctor":
				if content.definition("doctor_titles",parts[1]).is_empty() or not parts[2] in ["diagnosis","treatment","surgery"]:
					return "标准医生键引用无效"
			elif not parts[1].is_empty() or not parts[2].is_empty():
				return "普通岗位的标准键带有医生资格"
		var identities: Dictionary = {}
		for id: Variant in state.candidates:
			var candidate: Variant = state.candidates[id]
			if not id is String or not candidate is Dictionary or candidate.get("id")!=id:
				return "简历身份与索引不同"
			var invalid: String = _validate_saved_candidate(candidate,today)
			if not invalid.is_empty():
				return invalid
			identities[id] = true
		var active: Dictionary = state.active_search
		if not active.is_empty():
			if not active.get("id") is String or not state.searches.has(active.id) or not active.get("filter") is Dictionary or not active.get("candidates") is Array:
				return "活动寻访身份、筛选或候选结构无效"
			var filter_error: String = _validate_saved_filter(active.filter)
			if not filter_error.is_empty():
				return filter_error
			if not _saved_integer(active.get("remaining_ticks"),1,roundi(float(content.balance.recruitment.search_seconds)*10)) or not _saved_integer(active.get("last_advanced_tick"),-1,world.sim_tick):
				return "寻访剩余工时或推进时点无效"
			if active.candidates.size()!=int(content.balance.recruitment.search_result_count):
				return "寻访冻结候选数不完整"
			for candidate: Variant in active.candidates:
				if not candidate is Dictionary:
					return "寻访候选必须是对象"
				var invalid: String = _validate_saved_candidate(candidate,today)
				if not invalid.is_empty():
					return invalid
				if candidate.source!="targeted" or candidate.pool!="targeted" or identities.has(candidate.id):
					return "寻访候选来源或唯一身份无效"
				identities[candidate.id] = true
		for id: Variant in state.searches:
			var search: Variant = state.searches[id]
			if not id is String or not search is Dictionary or search.get("id")!=id or not search.get("status") in ["searching","completed","cancelled"] or not _saved_integer(search.get("cost")) or not _saved_integer(search.get("started_tick"),0,world.sim_tick):
				return "寻访历史身份、状态或费用无效"
			var payment: Variant = facts.ledger.entries.get(id+":search")
			if not payment is Dictionary or payment.get("owner_id")!=id or payment.get("component")!="search" or payment.get("amount")!=-int(search.cost) or payment.get("tick")!=search.started_tick or payment.get("settled")!=true:
				return "寻访缺少同一身份的原付款凭据"
			if (search.status=="searching")!=(not active.is_empty() and active.id==id):
				return "寻访活动状态与历史所有者不一致"
			if not active.is_empty() and active.id==id and int(active.last_advanced_tick)<int(search.started_tick)-1:
				return "寻访推进时点早于原开工"
	var hired_candidates: Dictionary = {}
	for id: Variant in facts.staff:
		var staff: Variant = facts.staff[id]
		if not id is String or not staff is Dictionary or staff.get("id")!=id or not staff.get("role") in ROLES or not facts.actors.has(id):
			return "招聘员工身份、岗位或实际身体无效"
		if staff.has("candidate_id"):
			var candidate_id: Variant = staff.candidate_id
			if not candidate_id is String or candidate_id.is_empty() or id!="staff_"+candidate_id or hired_candidates.has(candidate_id) or state.get("candidates",{}).has(candidate_id):
				return "录用候选重复或与员工身份不同"
			hired_candidates[candidate_id] = true
			var payment: Variant = facts.ledger.entries.get(id+":recruitment")
			if not payment is Dictionary or payment.get("owner_id")!=id or payment.get("component")!="recruitment" or payment.get("tick")!=staff.get("hired_tick") or payment.get("settled")!=true:
				return "已录用员工缺少原录用付款凭据"
		if staff.has("first_job_tick") or staff.has("research_practice_ticks"):
			if not _saved_integer(staff.get("first_job_tick"),-1,world.sim_tick) or not _saved_integer(staff.get("research_practice_ticks"),0,roundi(float(content.balance.staff_practice.research_active_seconds)*10)-1):
				return "首次工作或研究实践余量无效"
			if int(staff.first_job_tick)>=0:
				for field: String in ["first_job_source","first_job_scene","first_job_low_motion"]:
					if not staff.get(field) is String or staff[field].is_empty():
						return "首次工作缺少原完成来源或表现"
		if staff.role in ORDINARY_ROLES and (staff.has("skill") or staff.has("job_practice")):
			if not _saved_integer(staff.get("skill"),1,int(content.balance.staff_practice.max_level)) or not _saved_integer(staff.get("job_practice")):
				return "普通岗位技能或实践值无效"
			if int(staff.job_practice)>(int(content.balance.staff_practice.max_level)-int(staff.skill))*int(content.balance.staff_practice.units_per_level):
				return "岗位实践超过可累计的合法余量"
	for entry: Variant in facts.ledger.entries.values():
		if not entry is Dictionary:
			return "招聘付款凭据结构无效"
		if entry.get("component")=="search" and not state.get("searches",{}).has(entry.get("owner_id","")):
			return "寻访付款引用不存在的原寻访"
		if entry.get("component")=="recruitment" and (not facts.staff.has(entry.get("owner_id","")) or not facts.staff.get(entry.get("owner_id",""),{}).has("candidate_id")):
			return "录用付款引用不存在的原候选员工"
	return ""

func _validate_saved_filter(filter: Dictionary) -> String:
	if filter.has("role") and (not filter.role is String or not filter.role in ROLES):
		return "寻访岗位筛选无效"
	for pair: Array in [["species_id","species"],["title_id","doctor_titles"],["social_personality_id","patient_personalities"],["biography_id","staff_biographies"]]:
		if filter.has(pair[0]) and (not filter[pair[0]] is String or (not filter[pair[0]].is_empty() and content.definition(pair[1],filter[pair[0]]).is_empty())):
			return "寻访筛选内容引用无效"
	if filter.has("primary_track") and (not filter.primary_track is String or not filter.primary_track in ["diagnosis","treatment","surgery"]):
		return "寻访医生主方向无效"
	if filter.has("ability") and (not filter.ability is String or not filter.ability in ["diagnosis","treatment","care","surgery","skill"]):
		return "寻访能力筛选无效"
	if filter.has("min_ability") and not _saved_integer(filter.min_ability,1,5):
		return "寻访最低能力必须是合法整数"
	return ""

func _validate_saved_candidate(candidate: Dictionary, today: int) -> String:
	for field: String in ["id","name","role","species_id","title_id","primary_track","social_personality_id","work_style_id","biography_id","personality_id","source","pool"]:
		if not candidate.get(field) is String:
			return "简历字符串字段无效："+field
	if candidate.id.is_empty() or candidate.name.is_empty() or not candidate.role in ROLES or not candidate.source in ["passive","referral","targeted"] or not candidate.pool in ["passive","targeted","bookmarked"]:
		return "简历身份、岗位或来源无效"
	if candidate.pool=="bookmarked" and not candidate.get("original_pool") in ["passive","targeted"]:
		return "关注简历缺少原候选池"
	if candidate.has("referral_summary") and not candidate.referral_summary is String:
		return "推荐简历摘要无效"
	for field: String in ["hire","wage_day"]:
		if not _saved_integer(candidate.get(field)):
			return "简历冻结报价无效"
	if not _saved_integer(candidate.get("created_day"),1,today) or not _saved_integer(candidate.get("expires_day"),int(candidate.get("created_day",0))+1):
		return "简历生成或到期日无效"
	for pair: Array in [["species_id","species"],["social_personality_id","patient_personalities"],["work_style_id","staff_work_styles"],["biography_id","staff_biographies"]]:
		if content.definition(pair[1],candidate[pair[0]]).is_empty():
			return "简历内容引用不存在："+str(pair[0])
	if not candidate.get("abilities") is Dictionary or candidate.abilities.size()!=4:
		return "简历四能力结构无效"
	for ability: String in ["diagnosis","treatment","care","surgery"]:
		if not _saved_integer(candidate.abilities.get(ability),0,5):
			return "简历能力等级无效"
	if not _saved_integer(candidate.get("skill"),0,3):
		return "简历岗位技能无效"
	if candidate.role=="doctor":
		if content.definition("doctor_titles",candidate.title_id).is_empty() or content.definition("doctor_personalities",candidate.personality_id).is_empty() or not candidate.primary_track in ["diagnosis","treatment","surgery"] or int(candidate.skill)!=0 or int(candidate.abilities.care)!=0:
			return "医生简历资格或主方向无效"
	elif not candidate.title_id.is_empty() or not candidate.personality_id.is_empty():
		return "普通职员简历带有医生资格"
	elif candidate.role=="nurse":
		if candidate.primary_track!="care" or int(candidate.skill)!=0 or int(candidate.abilities.treatment)!=0 or int(candidate.abilities.surgery)!=0:
			return "新护士简历资格无效"
	elif int(candidate.skill)<1 or not candidate.primary_track.is_empty():
		return "普通岗位简历技能或方向无效"
	return ""

func _saved_integer(value: Variant, minimum: int = 0, maximum: int = 1000000000000) -> bool:
	return value is int and int(value)>=minimum and int(value)<=maximum

func ensure(world: WorldState) -> void:
	if not world.facts.has("recruitment"):
		world.facts.recruitment = {"standard_ordinals":{},"candidates":{},"active_search":{},"searches":{},"last_passive_day":0,"last_notice_day":0}
	for staff: Dictionary in world.facts.staff.values():
		if staff.role in ORDINARY_ROLES:
			if not staff.has("skill"):
				staff.skill = 1
			if not staff.has("job_practice"):
				staff.job_practice = 0
		if not staff.has("research_practice_ticks"):
			staff.research_practice_ticks = 0
		if not staff.has("first_job_tick"):
			staff.first_job_tick = -1

func standard_key(filter: Dictionary) -> String:
	var role: String = str(filter.get("role","receptionist"))
	return "%s|%s|%s"%[role,str(filter.get("title_id","DT01")) if role=="doctor" else "",str(filter.get("primary_track","treatment")) if role=="doctor" else ""]

func standard_preview(world: WorldState, filter: Dictionary = {}) -> Dictionary:
	var normalized: Dictionary = filter.duplicate(true)
	normalized.species_id = str(content.balance.staff_species.standard_species_id)
	var invalid: String = _filter_error(world,normalized,false)
	if not invalid.is_empty():
		return {"ok":false,"reason":invalid}
	var key: String = standard_key(normalized)
	var ordinal: int = int(world.facts.get("recruitment",{}).get("standard_ordinals",{}).get(key,0))
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	var identity: String = world.hospital_id+"|"+str(world.facts.rng.recruitment.seed_decimal)+"|"+str(day)+"|"+key+"|"+str(ordinal)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = identity.hash()
	var candidate: Dictionary = _generate(world,normalized,"standard",day,identity.sha256_text().substr(0,24),random)
	candidate.standard_key = key
	candidate.ordinal = ordinal
	return card(world,candidate)

func card(world: WorldState, candidate: Dictionary) -> Dictionary:
	var result: Dictionary = candidate.duplicate(true)
	result.ok = true
	result.quote_hash = _quote_hash(candidate)
	result.cash_sufficient = HospitalLedger.balance(world)>=int(candidate.hire)
	result.entry = _entry(world,candidate)
	result.assignment_reason = "从1F实际入口入院；等待原岗位调度，当前目标岗位与休息点仍按身体核验"
	result.remaining_days = maxi(0,int(candidate.expires_day)-(world.sim_tick/WorldState.TICKS_PER_DAY+1))
	result.talent = talent(str(candidate.species_id)).duplicate(true)
	result.rig_adapter = adapter(str(candidate.species_id)).duplicate(true)
	result.asset_status = "岗位骨架合同已接入；全种族正式资产在阶段35逐项交付"
	return result

func query(world: WorldState, filter: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	var saved: Dictionary = world.facts.get("recruitment",{}).get("candidates",{})
	var keys: Array = saved.keys()
	keys.sort()
	for id: String in keys:
		var candidate: Dictionary = saved[id]
		if not filter.get("role","").is_empty() and candidate.role!=filter.role:
			continue
		if not filter.get("species_id","").is_empty() and candidate.species_id!=filter.species_id:
			continue
		candidates.append(card(world,candidate))
	return {"standard":standard_preview(world,filter),"candidates":candidates,"active_search":world.facts.get("recruitment",{}).get("active_search",{}).duplicate(true),
		"roles":ROLES.duplicate(),"species_count":content.catalog.species.size(),"asset_status":"阶段35全量正式资源待验收"}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if payload.has("filter") and not payload.filter is Dictionary:
		return _result(world,false,"invalid_filter","筛选条件结构无效")
	if kind=="recruitment_bookmark" and payload.has("enabled") and not payload.enabled is bool:
		return _result(world,false,"invalid_payload","关注开关无效")
	match kind:
		"recruitment_search":
			return _search(world,payload.get("filter",{}))
		"recruitment_cancel_search":
			return _cancel_search(world)
		"recruitment_hire":
			return _hire(world,payload)
		"recruitment_bookmark":
			return _bookmark(world,str(payload.get("candidate_id","")),bool(payload.get("enabled",true)))
		"recruitment_dismiss":
			var id: String = str(payload.get("candidate_id",""))
			if not world.facts.recruitment.candidates.has(id):
				return _result(world,false,"candidate_missing","简历已归档或录用")
			world.facts.recruitment.candidates.erase(id)
			world.touch()
			return _result(world,true,"applied","")
	return _result(world,false,"unknown_command","未知招聘命令")

func boundaries(world: WorldState) -> void:
	ensure(world)
	var state: Dictionary = world.facts.recruitment
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	if day<=int(state.last_passive_day):
		return
	var expired: int = 0
	for id: String in state.candidates.keys():
		var candidate: Dictionary = state.candidates[id]
		if candidate.pool!="bookmarked" and day>=int(candidate.expires_day):
			state.candidates.erase(id)
			expired += 1
	var staff_ids: Array = []
	for id: String in world.ids("staff"):
		if not world.facts.staff[id].get("departed",false):
			staff_ids.append(id)
	var referral_index: int = -1
	if not staff_ids.is_empty() and world.draw("recruitment",10000)<roundi(float(content.balance.recruitment.daily_referral_probability)*10000.0):
		referral_index = world.draw("recruitment",ROLES.size())
	for index: int in ROLES.size():
		var id: String = world.new_id("candidate")
		var candidate: Dictionary = _generate(world,{"role":ROLES[index]},"passive",day,id)
		if index==referral_index:
			var referrer: String = staff_ids[world.draw("recruitment",staff_ids.size())]
			candidate.source = "referral"
			candidate.referral_summary = str(world.facts.actors[referrer].name)+"推荐：愿意一起把本职工作做好。"
		state.candidates[id] = candidate
	state.last_passive_day = day
	if expired>0:
		state.last_notice_day = day
		state.notice = "%d份过期简历已归档"%expired

func advance(world: WorldState) -> void:
	ensure(world)
	var search: Dictionary = world.facts.recruitment.active_search
	if search.is_empty():
		return
	if int(search.last_advanced_tick)>=world.sim_tick:
		return
	search.last_advanced_tick = world.sim_tick
	search.remaining_ticks = maxi(0,int(search.remaining_ticks)-1)
	if int(search.remaining_ticks)>0:
		return
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	for candidate: Dictionary in search.candidates:
		candidate.created_day = day
		candidate.expires_day = day+int(content.balance.recruitment.result_days_retained)
		world.facts.recruitment.candidates[candidate.id] = candidate
	world.facts.recruitment.searches[search.id].status = "completed"
	world.facts.recruitment.active_search = {}

func _search(world: WorldState, filter: Dictionary) -> CommandResult:
	var state: Dictionary = world.facts.recruitment
	var invalid: String = _filter_error(world,filter,true)
	if not invalid.is_empty():
		return _result(world,false,"invalid_filter",invalid)
	if not state.active_search.is_empty():
		return _result(world,false,"search_active","先完成或取消当前寻访")
	if _pool_count(world,"targeted")+int(content.balance.recruitment.search_result_count)>int(content.balance.recruitment.max_targeted_results):
		return _result(world,false,"candidate_capacity","寻访需要3个空简历位")
	var cost: int = int(content.balance.recruitment.search_fee)
	if HospitalLedger.balance(world)<cost:
		return _result(world,false,"insufficient_funds","资金不足，寻访未开始")
	var clone: WorldState = WorldState.new(world.freeze())
	var id: String = clone.new_id("search")
	var candidates: Array = []
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	for index: int in range(int(content.balance.recruitment.search_result_count)):
		candidates.append(_generate(clone,filter,"targeted",day,clone.new_id("candidate")))
	var payment: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"search",-cost))
	if not payment.accepted:
		return payment
	world.facts.entity_next = clone.facts.entity_next
	world.facts.rng.recruitment = clone.facts.rng.recruitment
	state.active_search = {"id":id,"filter":filter.duplicate(true),"remaining_ticks":roundi(float(content.balance.recruitment.search_seconds)*10),"last_advanced_tick":world.sim_tick-1,"candidates":candidates}
	state.searches[id] = {"id":id,"cost":cost,"started_tick":world.sim_tick,"status":"searching"}
	return _result(world,true,"applied","")

func _cancel_search(world: WorldState) -> CommandResult:
	var state: Dictionary = world.facts.recruitment
	if state.active_search.is_empty():
		return _result(world,false,"search_missing","当前没有寻访")
	state.searches[state.active_search.id].status = "cancelled"
	state.active_search = {}
	world.touch()
	return _result(world,true,"applied","")

func _hire(world: WorldState, payload: Dictionary) -> CommandResult:
	var state: Dictionary = world.facts.recruitment
	var candidate_id: String = str(payload.get("candidate_id",""))
	var standard: bool = not str(payload.get("standard_key","")).is_empty()
	if (candidate_id.is_empty() and not standard) or (not candidate_id.is_empty() and standard):
		return _result(world,false,"invalid_selection","请只指定一份简历，或一个标准键与序号")
	var candidate: Dictionary
	if standard:
		var preview: Dictionary = standard_preview(world,payload.get("filter",{}))
		if not preview.ok or preview.standard_key!=payload.standard_key or int(preview.ordinal)!=int(payload.get("ordinal",-1)):
			return _result(world,false,"material_change","标准候选已改变，请刷新")
		candidate = _candidate_from_card(preview)
	else:
		if not state.candidates.has(candidate_id):
			return _result(world,false,"candidate_missing","简历已过期、关闭或录用")
		candidate = state.candidates[candidate_id]
		if not candidate.role in ROLES:
			return _result(world,false,"external_service","维修通过设备工单购买上门服务")
		if candidate.pool!="bookmarked" and world.sim_tick/WorldState.TICKS_PER_DAY+1>=int(candidate.expires_day):
			return _result(world,false,"candidate_expired","简历已到期")
	if str(payload.get("quote_hash",""))!=_quote_hash(candidate):
		return _result(world,false,"material_change","候选能力或报价已改变，请刷新")
	if adapter(str(candidate.species_id)).is_empty() or not candidate.role in adapter(str(candidate.species_id)).roles:
		return _result(world,false,"unknown_adapter","该身体缺少岗位操作适配")
	var entry: Dictionary = _entry(world,candidate)
	if not entry.ok:
		return _result(world,false,"entry_blocked",entry.reason)
	var cost: int = int(candidate.hire)
	var paid: int = cost
	if HospitalLedger.balance(world)<paid:
		return _result(world,false,"insufficient_funds","资金不足，简历保留")
	var id: String = "staff_"+str(candidate.id)
	if world.facts.staff.has(id):
		return _result(world,false,"already_hired","该候选已录用")
	var payment: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"recruitment",-paid))
	if not payment.accepted:
		return payment
	var ledger: Dictionary = world.facts.ledger.entries[id+":recruitment"]
	ledger.cost = cost
	ledger.hospital_paid = paid
	ledger.direct_paid = cost-paid
	ledger.funding_source = "community_aid"
	ledger.summary = candidate.name
	world.facts.actors[id] = {"id":id,"name":candidate.name,"species_id":candidate.species_id,"location":{"kind":"floor","floor_id":1,"cell":entry.cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	world.facts.staff[id] = {"id":id,"candidate_id":candidate.id,"role":candidate.role,"title_id":candidate.title_id,
		"abilities":candidate.abilities.duplicate(true),"certificates":_certificates(candidate),"practice":{"diagnosis":0,"treatment":0,"care":0,"surgery":0},"completed_jobs":{},
		"energy":float(content.balance.recruitment.initial_energy),"fatigue":float(content.balance.recruitment.initial_doctor_fatigue) if candidate.role=="doctor" else 0.0,
		"stress_milli":roundi(float(content.balance.recruitment.initial_stress)*1000.0),"on_shift":true,"hired_tick":world.sim_tick,
		"wage_numerator":0,"wage_accrued_tick":world.sim_tick-1,"social_personality_id":candidate.social_personality_id,"work_style_id":candidate.work_style_id,
		"biography_id":candidate.biography_id,"personality_id":candidate.personality_id,"growth_direction":candidate.primary_track,"primary_track":candidate.primary_track,"arrival_status":"waiting_for_assignment","arrival_tick":world.sim_tick,
		"research_practice_ticks":0,"first_job_tick":-1}
	if candidate.role in ORDINARY_ROLES:
		world.facts.staff[id].skill = candidate.skill
		world.facts.staff[id].job_practice = 0
	if standard:
		state.standard_ordinals[candidate.standard_key] = int(candidate.ordinal)+1
	else:
		state.candidates.erase(candidate_id)
	space.sync_actor(world,id)
	world.touch()
	return CommandResult.new(true,"applied","",[id],world.revision)

func _bookmark(world: WorldState, id: String, enabled: bool) -> CommandResult:
	var candidates: Dictionary = world.facts.recruitment.candidates
	if not candidates.has(id):
		return _result(world,false,"candidate_missing","简历不存在")
	var candidate: Dictionary = candidates[id]
	if enabled and candidate.pool!="bookmarked":
		if _pool_count(world,"bookmarked")>=int(content.balance.recruitment.max_bookmarked):
			return _result(world,false,"bookmark_capacity","最多关注4份简历")
		candidate.original_pool = candidate.pool
		candidate.pool = "bookmarked"
	elif not enabled and candidate.pool=="bookmarked":
		if world.sim_tick/WorldState.TICKS_PER_DAY+1>=int(candidate.expires_day):
			candidates.erase(id)
		elif _pool_count(world,candidate.original_pool)>=(int(content.balance.recruitment.max_passive) if candidate.original_pool=="passive" else int(content.balance.recruitment.max_targeted_results)):
			return _result(world,false,"candidate_capacity","原简历池已满，先关闭其他简历")
		else:
			candidate.pool = candidate.original_pool
	world.touch()
	return _result(world,true,"applied","")

func _filter_error(world: WorldState, filter: Dictionary, targeted: bool) -> String:
	var role: String = str(filter.get("role","receptionist"))
	if not role in ROLES:
		return "岗位不存在"
	var species_id: String = str(filter.get("species_id",""))
	if not species_id.is_empty() and content.definition("species",species_id).is_empty():
		return "种族定义不存在"
	var title: String = str(filter.get("title_id","DT01"))
	if role=="doctor" and not title in _titles(world):
		return "该医生职称尚未开放"
	var track: String = str(filter.get("primary_track","treatment"))
	if role=="doctor" and (not track in ["diagnosis","treatment","surgery"] or (track=="surgery" and not "R34" in world.facts.research)):
		return "该医生主方向尚未开放"
	if targeted and filter.has("min_ability"):
		var ability: String = str(filter.get("ability",track if role=="doctor" else "care" if role=="nurse" else "skill"))
		var level: int = int(filter.min_ability)
		if level<1 or level>5 or (level>1 and not "R11" in world.facts.research):
			return "能力等级超出当前合法范围"
		if role=="nurse" and (not ability in ["diagnosis","care"] or level>3):
			return "新护士不能通过寻访获得手术资格"
		if role in ORDINARY_ROLES and (ability!="skill" or level>3):
			return "当前新职员技能范围为1至3"
		if role=="doctor" and (not ability in ["diagnosis","treatment","surgery"] or (ability=="surgery" and ((filter.has("primary_track") and track!="surgery") or not "R34" in world.facts.research))):
			return "该方向不能生成要求的能力"
		if role=="doctor" and _doctor_choices(world,filter).is_empty():
			return "该职称和主方向没有满足等级的候选"
	return ""

func _titles(world: WorldState) -> Array:
	var result: Array = []
	for title: Dictionary in content.catalog.doctor_titles:
		var available: bool = true
		for research: String in title.recruitment.requires_research:
			available = available and research in world.facts.research
		if title.recruitment.requires_promoted_chief:
			available = false
			for staff: Dictionary in world.facts.staff.values():
				if staff.role=="doctor" and staff.get("title_id","")==title.id and staff.get("promoted_title",false):
					available = true
		if available:
			result.append(title.id)
	return result

func _generate(world: WorldState, filter: Dictionary, pool: String, day: int, id: String, random: RandomNumberGenerator = null) -> Dictionary:
	var role: String = str(filter.get("role","receptionist"))
	var species_id: String = str(filter.get("species_id",""))
	if species_id.is_empty():
		species_id = str(content.catalog.species[_draw(world,content.catalog.species.size(),random)].id)
	var title_id: String = ""
	var track: String = "care" if role=="nurse" else ""
	var abilities: Dictionary = {"diagnosis":0,"treatment":0,"care":0,"surgery":0}
	var skill: int = 0
	if role=="doctor":
		if pool=="targeted":
			var choices: Array = _doctor_choices(world,filter)
			var choice: Dictionary = choices[_draw(world,choices.size(),random)]
			title_id = choice.title_id
			track = choice.primary_track
		else:
			var titles: Array = _titles(world)
			title_id = str(filter.get("title_id",titles[_draw(world,titles.size(),random)] if pool!="standard" else "DT01"))
			var tracks: Array = ["diagnosis","treatment"]+(["surgery"] if "R34" in world.facts.research else [])
			track = str(filter.get("primary_track",tracks[_draw(world,tracks.size(),random)] if pool!="standard" else "treatment"))
		var rank: int = int(content.definition("doctor_titles",title_id).rank)
		abilities.diagnosis = maxi(1,rank)
		abilities.treatment = 1
		abilities[track] = rank+1
		if pool!="standard" and "R11" in world.facts.research and _draw(world,10000,random)<roundi(float(content.balance.recruitment.secondary_ability_probability)*10000.0):
			var learned: Array = []
			for ability: String in ["diagnosis","treatment","surgery"]:
				if ability!=track and int(abilities[ability])>0 and int(abilities[ability])<4:
					learned.append(ability)
			if not learned.is_empty():
				abilities[learned[_draw(world,learned.size(),random)]] += 1
	elif role=="nurse":
		abilities.diagnosis = 1+(_draw(world,3,random) if pool!="standard" and "R11" in world.facts.research else 0)
		abilities.care = 1+(_draw(world,3,random) if pool!="standard" and "R11" in world.facts.research else 0)
	else:
		skill = 1+(_draw(world,3,random) if pool!="standard" and "R11" in world.facts.research else 0)
	if pool=="targeted" and filter.has("min_ability"):
		var required: String = str(filter.get("ability",track if role=="doctor" else "care" if role=="nurse" else "skill"))
		if required=="skill":
			skill = int(filter.min_ability)+_draw(world,(3 if "R11" in world.facts.research else 1)-int(filter.min_ability)+1,random)
		elif role=="nurse":
			abilities[required] = int(filter.min_ability)+_draw(world,(3 if "R11" in world.facts.research else 1)-int(filter.min_ability)+1,random)
		else:
			abilities[required] = maxi(int(abilities[required]),int(filter.min_ability))
	var pay: Dictionary = _pay(role,title_id)
	var biography: String = _preference(world,"staff_biographies",str(filter.get("biography_id","")),random)
	var social: String = _preference(world,"patient_personalities",str(filter.get("social_personality_id","")),random)
	var name: String = ["林","周","叶","云","范","星","方","岑"][_draw(world,8,random)]+["小舟","禾","青","晓","舒","予","知","宁"][_draw(world,8,random)]
	return {"id":id,"name":name,"role":role,"species_id":species_id,"title_id":title_id,"primary_track":track,"abilities":abilities,"skill":skill,
		"social_personality_id":social,"work_style_id":_preference(world,"staff_work_styles","",random),"biography_id":biography,
		"personality_id":_preference(world,"doctor_personalities","",random) if role=="doctor" else "","hire":int(pay.hire),"wage_day":int(pay.wage_day),
		"source":pool,"pool":pool,"created_day":day,"expires_day":day+int(content.balance.recruitment.passive_days_retained)}

func _doctor_maximum(title: String, primary: String, ability: String) -> int:
	var rank: int = int(content.definition("doctor_titles",title).rank)
	if ability==primary:
		return rank+1
	if ability=="surgery":
		return 0
	return mini(4,(maxi(1,rank) if ability=="diagnosis" else 1)+1)

func _doctor_choices(world: WorldState, filter: Dictionary) -> Array:
	var titles: Array = [str(filter.title_id)] if filter.has("title_id") else _titles(world)
	var tracks: Array = [str(filter.primary_track)] if filter.has("primary_track") else ["diagnosis","treatment"]+(["surgery"] if "R34" in world.facts.research else [])
	var choices: Array = []
	for title: String in titles:
		for track: String in tracks:
			var ability: String = str(filter.get("ability",track))
			if not filter.has("min_ability") or int(filter.min_ability)<=_doctor_maximum(title,track,ability):
				choices.append({"title_id":title,"primary_track":track})
	return choices

func _pay(role: String, title: String) -> Dictionary:
	for row: Dictionary in (content.balance.doctor_pay if role=="doctor" else content.balance.staff):
		if (role=="doctor" and row.title_id==title) or (role!="doctor" and row.role==role):
			return row
	return {"hire":0,"wage_day":0}

func _draw(world: WorldState, maximum: int, random: RandomNumberGenerator) -> int:
	return random.randi_range(0,maximum-1) if random!=null else world.draw("recruitment",maximum)

func _preference(world: WorldState, collection: String, preference: String, random: RandomNumberGenerator) -> String:
	var choices: Array = content.catalog[collection]
	var extra: int = 1 if not preference.is_empty() and not content.definition(collection,preference).is_empty() else 0
	var index: int = _draw(world,choices.size()+extra,random)
	return preference if index>=choices.size() else str(choices[index].id)

func _quote_hash(candidate: Dictionary) -> String:
	var terms: Dictionary = {}
	for field: String in ["id","name","role","species_id","title_id","primary_track","abilities","skill","social_personality_id","work_style_id","biography_id","personality_id","hire","wage_day","source","standard_key","ordinal"]:
		if candidate.has(field):
			terms[field] = candidate[field]
	return JSON.stringify(_ordered(terms)).sha256_text()

func _ordered(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			result[key] = _ordered(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_ordered(item))
		return result
	return value

func _candidate_from_card(card_value: Dictionary) -> Dictionary:
	var candidate: Dictionary = card_value.duplicate(true)
	for field: String in ["ok","quote_hash","cash_sufficient","entry","assignment_reason","remaining_days","talent","rig_adapter","asset_status"]:
		candidate.erase(field)
	return candidate

func _pool_count(world: WorldState, pool: String) -> int:
	var count: int = 0
	if pool=="targeted":
		count += world.facts.recruitment.active_search.get("candidates",[]).size()
	for candidate: Dictionary in world.facts.recruitment.candidates.values():
		if candidate.pool==pool:
			count += 1
	return count

func _staff_count(world: WorldState, role: String) -> int:
	var count: int = 0
	for staff: Dictionary in world.facts.staff.values():
		if staff.role==role and not staff.get("departed",false):
			count += 1
	return count

func _entry(world: WorldState, candidate: Dictionary) -> Dictionary:
	var entry: Dictionary = world.facts.get("entry",{"anchor":[47,93],"size":[3,3]})
	var anchor: Array = entry.get("cell",entry.get("anchor",[47,93]))
	var size: Array = entry.get("size",[3,3])
	var actor: Dictionary = {"id":"candidate_preview","species_id":candidate.species_id,"facing":0.0,"location":{"kind":"floor","floor_id":1,"cell":anchor.duplicate()}}
	for y: int in range(int(anchor[1]),int(anchor[1])+int(size[1])):
		for x: int in range(int(anchor[0]),int(anchor[0])+int(size[0])):
			var cell: Vector2i = Vector2i(x,y)
			if not space.static_reason(world,actor,1,cell).is_empty():
				continue
			actor.location.cell = [x,y]
			var rectangle: Rect2 = space.body_rectangle(actor)
			var occupied: bool = false
			for present: Dictionary in world.facts.actors.values():
				if present.location.kind=="floor" and int(present.location.floor_id)==1 and rectangle.intersects(space.body_rectangle(present)):
					occupied = true
					break
			if not occupied:
				return {"ok":true,"floor_id":1,"cell":[x,y]}
	return {"ok":false,"reason":"1F入口缺少支持该真实身体的合法空位"}

func _certificates(candidate: Dictionary) -> Array:
	if candidate.role=="nurse":
		return ["q_ward"] if int(candidate.abilities.care)>0 else []
	return ["q_research"] if candidate.role=="researcher" else []

func adapter(species_id: String) -> Dictionary:
	var species: Dictionary = content.definition("species",species_id)
	return content.definition("staff_rig_adapters","SRA_"+str(species.get("rig","")))

func talent(species_id: String) -> Dictionary:
	for definition: Dictionary in content.catalog.staff_talents:
		if definition.species_id==species_id:
			return definition
	return {}

func talent_effect(world: WorldState, staff_id: String, action: String, patient_id: String = "", specialty: String = "") -> Dictionary:
	if not world.facts.staff.has(staff_id) or world.facts.staff[staff_id].get("departed",false):
		return {}
	var effect: Dictionary = talent(world.facts.actors[staff_id].species_id)
	if effect.is_empty() or effect.action!=action:
		return {}
	var condition: String = str(effect.condition)
	var applicable: bool = condition=="always" or (condition=="late_shift" and world.sim_tick%WorldState.TICKS_PER_DAY>=12000) or condition==specialty
	if world.facts.actors.has(patient_id):
		var patient: Dictionary = world.facts.actors[patient_id]
		var body: Dictionary = space.body(patient)
		applicable = applicable or (condition=="tall_patient" and float(body.height_m)>2.4) or (condition=="large_patient" and space.clearance(patient)==3) or (condition=="micro_patient" and content.definition("species",patient.species_id).rig=="micro")
	return effect.duplicate(true) if applicable else {}

func work_rate(world: WorldState, staff_id: String, action: String, patient_id: String = "", specialty: String = "") -> float:
	var staff: Dictionary = world.facts.staff[staff_id]
	var rate: float = 1.0+float(content.balance.staff_practice.speed_per_extra_level)*(int(staff.get("skill",1))-1) if staff.role in ORDINARY_ROLES else 1.0
	var effect: Dictionary = talent_effect(world,staff_id,action,patient_id,specialty)
	if effect.get("handler_id","")=="work_speed":
		rate *= 1.0+float(effect.value)
	return rate

func service_mood(world: WorldState, staff_id: String, action: String, visit_id: String, receipt: Dictionary) -> int:
	if receipt.get("talent_mood_applied",false) or not world.facts.visits.has(visit_id):
		return 0
	var visit: Dictionary = world.facts.visits[visit_id]
	var effect: Dictionary = talent_effect(world,staff_id,action,visit.actor_id)
	if effect.get("handler_id","")!="service_mood":
		return 0
	var amount: int = mini(int(effect.value),maxi(0,int(content.balance.staff_species.talent_mood_cap_per_visit)-int(visit.get("staff_talent_mood",0))))
	visit.staff_talent_mood = int(visit.get("staff_talent_mood",0))+amount
	visit.anger = maxf(0.0,float(visit.anger)-amount)
	receipt.talent_mood_applied = true
	return amount

func settle(world: WorldState) -> void:
	ensure(world)
	for visit: Dictionary in world.facts.visits.values():
		var receipt: Dictionary = visit.get("registration_receipt",{})
		if not receipt.is_empty():
			consume_completion(world,"registration_completed",receipt)
	for collection: String in ["environment","maintenance"]:
		var receipts: Dictionary = world.facts.get(collection,{}).get("receipts",{})
		for receipt: Dictionary in receipts.values():
			var kind: String = str(receipt.kind)
			var source: String = {"repair_completed":"maintenance_order_completed","maintenance_completed":"maintenance_order_completed","upgrade_completed":"machine_upgrade_completed","renovation_completed":"surface_unit_completed"}.get(kind,kind)
			consume_completion(world,source,receipt)
	for staff: Dictionary in world.facts.staff.values():
		if staff.role=="nurse" and int(staff.first_job_tick)<0 and not staff.get("completed_jobs",{}).is_empty():
			_first_job(world,staff,"clinical_completed")
		if staff.role in ORDINARY_ROLES and "R11" in world.facts.research:
			_convert_practice(staff)

func consume_completion(world: WorldState, source: String, receipt: Dictionary) -> bool:
	if receipt.get("practice_awarded",false) or int(receipt.get("standard_work_milli",0))<=0:
		return false
	var staff_id: String = str(receipt.get("staff_id",""))
	if not world.facts.staff.has(staff_id) or world.facts.staff[staff_id].get("departed",false):
		receipt.practice_awarded = true
		return false
	var staff: Dictionary = world.facts.staff[staff_id]
	var profile: Dictionary = _practice_profile(staff.role)
	if profile.is_empty() or not source in profile.sources or staff.role=="researcher":
		return false
	receipt.practice_awarded = true
	if staff.role in ORDINARY_ROLES:
		_award_practice(world,staff,1)
	_first_job(world,staff,str(receipt.get("id",source)))
	return true

func research_work(world: WorldState, staff_id: String, ticks: int, receipt: Dictionary) -> bool:
	if ticks<=0 or receipt.get("practice_time_consumed",false) or not world.facts.staff.has(staff_id):
		return false
	var staff: Dictionary = world.facts.staff[staff_id]
	if staff.role!="researcher" or staff.get("departed",false) or not receipt.get("qualified_active_research",false):
		return false
	receipt.practice_time_consumed = true
	staff.research_practice_ticks += ticks
	var period: int = roundi(float(content.balance.staff_practice.research_active_seconds)*10.0)
	var units: int = int(staff.research_practice_ticks)/period
	staff.research_practice_ticks = int(staff.research_practice_ticks)%period
	if units>0:
		_award_practice(world,staff,units)
		_first_job(world,staff,str(receipt.get("id","research")))
	return true

func _award_practice(world: WorldState, staff: Dictionary, units: int) -> void:
	var cap: int = (int(content.balance.staff_practice.max_level)-int(staff.skill))*int(content.balance.staff_practice.units_per_level)
	staff.job_practice = mini(cap,int(staff.job_practice)+units)
	if "R11" in world.facts.research:
		_convert_practice(staff)

func _convert_practice(staff: Dictionary) -> void:
	var required: int = int(content.balance.staff_practice.units_per_level)
	while int(staff.skill)<int(content.balance.staff_practice.max_level) and int(staff.job_practice)>=required:
		staff.skill += 1
		staff.job_practice -= required

func _practice_profile(role: String) -> Dictionary:
	for profile: Dictionary in content.catalog.staff_practice_profiles:
		if profile.role==role:
			return profile
	return {}

func _first_job(world: WorldState, staff: Dictionary, source: String) -> void:
	if int(staff.get("first_job_tick",-1))>=0:
		return
	staff.first_job_tick = world.sim_tick
	staff.first_job_source = source
	var profile: Dictionary = _practice_profile(staff.role)
	staff.first_job_scene = str(profile.get("first_job_scene",""))
	staff.first_job_low_motion = str(profile.get("low_motion_first_job_scene",""))

func _result(world: WorldState, ok: bool, code: String, reason: String) -> CommandResult:
	return CommandResult.new(ok,code,reason,[],world.revision)
