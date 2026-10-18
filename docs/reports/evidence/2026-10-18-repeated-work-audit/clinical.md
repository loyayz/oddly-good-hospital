# 临床、到访、员工、研究与生活服务同类开销审计

审计日期：2026-10-18。范围为 `game/clinic`、`game/arrivals`、`game/staff`、`game/community`、`game/life` 的全部 13 个 GDScript 文件及 13 个 UID 文件。函数清单共 502 个函数入口，循环清单共 626 处 for/while；清单用于定位和筛选，不把循环总数当成缺陷数。逐文件函数与循环清单、文件 SHA-256、行数和覆盖状态见 [clinical-manifest.json](clinical-manifest.json)。审计依据为源码、设计和既有证据；未修改生产或测试代码，未运行 Godot、功能回归或性能测量。

本报告把已测得并修复的主热点、当前代码中确认存在的重复工作、必要的完整搜索和已有缓解分开。静态确认表示触发条件、调用链和重复项可由当前代码直接推出；不表示已测得该项耗时，也不表示可以跳过业务要求的候选、真实路线、到场、占用或提交复核。

## 优先级与证据边界

| 类别 | 结论 | 证据 |
| --- | --- | --- |
| 已测主热点、已修复 | 指定医生的门诊报价先枚举其他所有医生，随后才排除 | 原 GP80 嵌套计时中 `clinic.dispatch` 13.785s、`clinic.advance` 12.979s；`service_candidates` 8,966 次，26.6s 包含时间。当前 `plan_quote` 已将已知医生约束传入候选枚举，保留原最终过滤 |
| 优先静态候选 | CL-A01 同一只读报价重复枚举/计算；CL-A02 已知设施约束晚于全院查询；CL-A03 同批候选重复构建占用/归属视图；CL-A06 实际高频查询复制整个世界 | 当前源码确认，有明确最小收缩边界，尚未逐项计时 |
| 次级静态候选 | CL-A04 员工准备队列重建；CL-A05 历史完成扫描；CL-A07 容量预算重复扫描工单；CL-A08 状态栏构建完整招聘视图；CL-A09 解锁查询重复检索同一研究任务 | 当前源码确认；触发频率、对象数和现有缓解分别列出，不能凭复杂度代替测量 |
| 组合输入新增静态候选 | CL-A10 同一次休息派单在没有员工椅时重复完整茶位搜索 | 已确认当前构造与调用链；55.345s首步超时无完整相位。后续阶段跟踪在55.441s停止时，首轮茶位搜索尚未返回；不据此声称已执行第二轮或取得完整占比 |

### 已修复项 CL-FIX01：指定医生报价先应用医生约束

修复位于 `game/clinic/clinical_runtime.gd:714` 的 `plan_quote`：`options.has("doctor_id")` 时传递 `selection.staff_id`，不指定医生时仍执行完整枚举，不使用 `first_only`。当前该文件 SHA-256 为 `b7eb9407c5062b73a40a6de654a6e1994f758853d5e51f14b7cc7bcbeb513ff0`。该修复与下面十项残余候选分别统计；残余候选尚未实施，不能计入这项修复的收益。

已修复项只消除了指定医生报价中的晚过滤，以下十项仍为未修复、未逐项测量的静态候选。

下文 A=实际角色数，P=活跃就诊数，F=设施数，C=通过已有类型/路程下界的候选数，Q/N=候诊座位/生活需求，B/G=住院/亲友停留，H=保留就诊历史；session、房间和员工数量在各段单独注明。既有固定代表场景为 160 人（120 患者、32 员工、8 亲友）、64 房间、1,336 设施；这些是输入规模，不表示每个静态分支都在该窗口发生。倍率均按各自触发条件计算。

## 残余根因索引

分类表示调用触发位置，不表示每个模拟步都会满足昂贵分支。以下十项状态均为“静态确认，未实施，单项耗时与收益未测”。

| ID | 标题 | 触发分类 |
| --- | --- | --- |
| CL-A01 | 同一次只读报价重复枚举或重复医生推荐 | 每步 / 事件 / UI |
| CL-A02 | 已知设施类型或指定桌位晚过滤 | 每步 / 事件 |
| CL-A03 | 候选逐个重扫同批归属与占用事实 | 每步 / 事件 |
| CL-A04 | 共享工作基地队列重复构建排序 | 每步 |
| CL-A05 | 幂等完成结算仍每步扫描全部历史 | 每步 |
| CL-A06 | 少量假设写入触发整个世界深拷贝 | 每步 / 事件 / UI |
| CL-A07 | 容量预算逐设施重扫维修升级工单 | 容量 |
| CL-A08 | 招聘状态栏重建完整候选卡片查询 | UI |
| CL-A09 | 研究解锁按已知身份反复扫描任务历史 | 事件 / UI / 容量 |
| CL-A10 | 无员工椅时同次休息派单重复完整茶位搜索 | 每步 / 事件 |

`CL-A08` 与界面审计 `PRES-06` 共用一个根因计数，其余编号均为本分区残余根因。已修复的医生筛选独立记录，不包含在这十项中。

## CL-A01 同一次只读报价仍重复完整枚举或同一医生的推荐

**位置与调用链。** `clinical_runtime.gd:393 _dispatch_service → :749 _select_plan`。启用排班且未指定医生时，`:752` 遍历 `service_candidates(...,"consult")` 的全部设施/医生对，再在 `:753` 递归调用 `_select_plan(..., pair.staff_id)`。递归推荐不接收该对的咨询设施，只使用医生身份和同一世界。没有可执行方案或前面的医生不成功时，同一医生可因多个咨询设施重复计算全部疾病方案。完成诊断后的推荐和释放检查另有显式医生入口（`:1527`、`:1601`），不应当各自再扩大成新的全院医生搜索。

另一个同根实例在 `:2109 arrival_readiness`：`:2125–2127` 的接待/初诊存在性检查完整求出一次结构 GP 候选；`:2130` 随后为诊断阈值验证再次以相同世界、患者和参数求出 GP 候选。中间没有世界事实写入。触发入口包括 `arrival_service.gd:1206 _admission_candidates` 每次实际到访机会对候选绑定的普通/复杂检查，以及 `research_service.gd:441 reception_readiness` 的接诊缺项展示。

**倍率。** 推荐最坏为咨询设施数 × 合格医生数 × 疾病方案数 × 每份报价的完整候选工作；重复医生带来的倍数是该医生出现的设施对数。接诊检查每次 readiness 多做一次完整 GP 候选枚举。不同医生、疾病、方案、设施适配以及不同实际世界的路线仍是独立必要工作。

**现有缓解。** 已修复的医生下推消除了每份报价内部的无关医生路线；`service_candidates` 使用设施定义索引、一次调用中的临床可用性和路线查询范围。它们没有消除外层相同医生重复推荐，也没有共享两个已返回的完整 GP 数组。

**最小候选与所有权。** `_select_plan` 单次同步调用按医生 ID 去重，保留首次出现的医生顺序和原成功回退；`arrival_readiness` 单次调用复用同一个 GP 候选数组。不能跨派单写入复用，也不能限制候选数量。临床服务拥有这两个局部视图。

**规则与选例。** 推荐策略、院长指定、短缺意图、不同诊断/治疗池交接、报价只读和失败原因不变。若实施，选 `CLIN-02/06/07/11/34`，补充同一医生多咨询设施且全部方案暂不可执行的单例，以及 readiness 缺初诊/证据不足的独立断言。仅修改 readiness 复用时追加 `GROW-13/37`，不重跑完整容量矩阵。

## CL-A02 已知设施约束晚于全院查询

**员工休息选址。** `staff_wellbeing.gd:60 dispatch → :362 _select_facility`。`:372` 遍历全部设施，`:374` 先调用 `_patient_occupies`，随后 `:376–379` 才检查睡眠床/休息椅类型；员工区限制也在占用查询之后。`:751–760 _patient_occupies` 每次扫描全部角色、候诊座位和生活需求。没有失败或预约等早退的无关机器也会触发这些扫描。一次选址为 F × (A + Q + N)，其中 F 是全院设施数，而真正候选通常只是员工区目标类型的一小部分。

**课程指定桌位。** `clinical_development.gd:172 _dispatch_training_job` 在已有 `preferred_desk_id` 时，仍先于 `:181` 通过 `_desks`（`:575`）对全部设施执行 `_desk_available`，到 `:182` 才排除非指定桌。生产 `_desk_available → research_service.gd:313 desk_reason`；后者先查类型，只有真实研究桌进一步查改建/维修。不能把它描述为所有设施均进行路线计算，但所有设施的资格入口和所有研究桌的维修资格仍已执行。

**现有缓解。** `WorldState.facility_ids(definition)` 已有稳定排序的定义索引；休息选址未使用它，课程也未在指定桌时使用单元素输入。研究自身 `_find_pair:347–359` 已在桌/员工资格和路线前应用 preferred 约束，不能重复报告为相同晚过滤缺陷。

**最小候选与边界。** 休息先应用纯读的目标类型和员工区筛选，再保留原占用、适配、去返程与恢复总时长排名。课程有指定桌时仅验证该桌，无指定时读取 FUR05 定义索引；不把研究/课程队列整个阶段冻结成不更新的共享候选，后提交任务仍读取前者的真实占用。

**规则与选例。** 休息需 `STAFF-21/22/23/25/41`：实际员工区、患者席不可借、床/椅兼容、去返程、当前占用及原睡眠余量。课程需 `STAFF-06/07`、`GROW-30/32`：指定桌不可用、分桌并行、同桌互斥、改派和原冻结进度。类型过滤是纯查询顺序调整，不改变需求中的人/设施资格。

## CL-A03 每个候选重复扫描同一批归属与占用事实

**候诊座位。** `waiting_life.gd:23 dispatch → :121 seat_candidates → :245 _seat_quote_in_query → :270 _facility_quote_in_query`；`:305 _occupied` 对每个候选扫描角色支持设施、候诊座位、生活需求、临床 session，再查员工预约。`:316 _public_seat` 对每个候选扫描所有同层房间，按几何包含决定公共区。一次患者选位约 C × (A + Q + N + session 数 + 房间数)。自动选位已有定义索引和真实路程下界剪枝（`:126–135`），邻居条件已有单次调用 actor_index（`:431`），空间有路线查询范围；这些缓解不覆盖上述占用和公共区重扫。自动调度和手动提交还会复核选定座位；需求明确要求提交复核，不能直接删掉这次复核。

**亲友。** `hospital_visitors.gd:17 arrivals` 只在到期扫描，但每个活跃就诊的 `_ward_stay:260` 都扫描全部住院事实，`_present:266` 扫描全部亲友停留。失败入院请求的 `_waiting_point_in_query:208` 在每个座位 `:218` 再遍历所有停留以查等待点占用：P × B、P/Q × G 以及 Q × C × G。已有座位定义索引、稳定 ID 和路线查询范围，没有 visit→stay、waiting-cell→stay 本批视图。`_admit` 成功即结束该批后续入院尝试；失败候选只在隔离投影中增加探针，不应误称它修改真实亲友承诺。

**共享桌与员工承诺。** `clinical_development.gd:594 desk_taken` 每个桌位扫描培训任务、session、研究任务；被课程和研究 `_find_pair:351` 反复调用。`safe_busy:355` 每个员工扫描 session、preparation、转床、交接；直接热点调用包括 `shift_scheduler.gd:83–93` 每步排班边界、`simulation.gd:300–302` 每员工待岗结论和 `staff_wellbeing.gd:90`。这些谓词有各自业务含义；不能把临床 `_staff_busy` 和培训 safe_busy 当成同一契约替换。临床 `service_candidates` 已通过 `_availability:1945` 的查询视图减少其内部全扫描，排班交接 dispatch 也已有 nurses_by_ward、related_stays、nurse_busy；上述其他入口没有自动获得这些视图。

**最小候选与所有权。** 各查询/派单阶段的事实所有者分别构建一次可重建的归属投影：候诊 facility→各占用所有者及房间公共性，亲友 visit→stay 和 floor/cell→waiting owner，共享桌 desk→非终结 job/session，员工 staff→具体种类承诺。保留自己例外、当前 session 忙、床通行权限与工作预约差异、重复所有者和原遍历优先顺序。视图在真实新增/释放预约、移动、交接或 job 状态改变后更新或丢弃；不依赖未证实可靠的全局 tick/revision 缓存，不删除历史或负载。

**规则与选例。** 候诊选 `STAFF-29/30/34/35/42`；亲友选 `CLIN-30/31/32`；共享桌选 `STAFF-06/07`、`GROW-30/32`；员工承诺选 `STAFF-12/16/21/41` 和 `CLIN-23/33` 中真正受谓词影响的交接。一次改动只执行涉及的分支，不把全部列项合成默认回归包。

## CL-A04 同一共享工作基地队列多次全员构建和排序

`clinical_development.gd:453 _base_line` 遍历全部员工、对相关员工调用 safe_busy、计算承诺/queue_tick，再排序。调用者为 `_prepare_base:408`、`advance:251`、`_base_start_quote:477` 和 `_yield_prepared_base:532`。尤其 `dispatch → _prepare_base → _yield_prepared_base:519` 中每个已整理员工扫描其他员工，每个符合 travel 条件的员工又重建其基地队列；相同基地的队列可以在本段只读工作中重复。

倍率取决于 prepared 员工数、travel 员工数及队列长度；上界含 prepared 员工数 × travel 员工数次全员扫描/排序，再乘 safe_busy 的承诺遍历。不同候选 staff 的 `_base_start_quote(...,candidate_id)` 需要加入不同候选，不能把其结果误当相同数组。

现有 `queue_tick` 保证持久排序，WorldState.ids 缓存稳定 ID 排序；它们不缓存基地队列。最小候选是先按 facility 分组员工，局部复用无 candidate 的队列，或在 `_yield_prepared_base` 先排除不在同层/不相交的基地再求队首。任何真实 request_move、base_task/phase、忙碌承诺变更都截断复用；原队首、已占位优先与真实让路仍必需。选择 `STAFF-12/16/41` 和改建安全腾空涉及的 `SPACE-35/36`，新增同基地多人/异层无关基地的队列等价断言。静态候选，未测量。

## CL-A05 幂等标记防止重复效果，却没有避免每步扫描全部历史完成

`simulation.gd:342/345` 每完整步调用成长和招聘结算。`clinical_development.gd:671 _settle_cases` 遍历全部 visits 才检查 departed/cured/`development_case_settled`。`recruitment_service.gd:671 settle` 遍历全部 visits 的 registration_receipt，以及 environment/maintenance 的全部 receipts，再调用 `consume_completion:689`，后者才检查 `practice_awarded`。历史记录保留越久，该固定步工作越大，在 T 个模拟步内为 T × (H + 环境凭据数 + 维修凭据数)；有效新完成可能为零。

现有标记正确保护只结算一次，不能消除扫描；WorldState.active_visit_ids 只服务活跃就诊，不是这些循环的替代品，因为还要可靠消费刚离院结果及恢复后的尚未结算凭据。最小候选是各完成事实所有者暴露待消费完成集合或日志游标，成功消费后确认；恢复时一次从完整事实重建未消费集合，事实历史和幂等标记仍保留。不要只排除 departed 或清空 receipts。

规则为真实完成、取消不成长、治愈参与者唯一、普通岗位实践与研究余数、恢复和退款顺序。选择 `STAFF-02/08/09/10/40`，按改动来源补注册或维修完成一次/恢复的定点断言；不以整条手术流程重复证明已验证的完成接口。静态候选，未测量历史规模斜率。

## CL-A06 高频假设查询复制整个世界，写入实际只涉及少量记录

**缺包。** `simulation.gd:329 → supply_service.gd:212 advance → :186 requests → clinical_runtime.gd:2087 shortage_requests` 每步执行。存在供给不足的治疗/手术票时，`:2101` 首次使用 `WorldState.new(world.freeze())`，随后只把全部 staff 的 supply_strike 设为 false，以只读报价判断真正因缺包受阻的员工。每次 requests 至多一次整世界复制，不是每票一次；但每个相关模拟步都会复制 actors、visits、ledger、历史、布局等全部事实。请求内现有惰性 candidate 避免同次多票重复复制，没有跨查询削减复制的事实范围。

**饮水短服务将来释放。** `environment_service.gd:921 _water_usable → :925 waiting_life.call("facility_availability") → waiting_life.gd:195`。若另一使用者正在该设施的 using 段，`:200` freeze 全世界，只为了把该使用者的 projected location 置 outside、清其 need.facility_id 并移除这一设施的 adaptation（`:201–203`）。外部调用可能对多个观察者/饮水设施重复；无 using 占用时不复制。现有环境查询缓存/是否实际调用由环境所有者决定，本报告不把每个环境采样都算作 freeze，也不引用原环境耗时作为此条件分支的测量值。

**边界与最小候选。** `game/sim/world_state.gd:129 freeze` 为 facts.duplicate(true)。这两个查询需要完整读取同一真实世界且隔离投影写入，但不要求深复制所有未写入集合。可沿当前 `_route_candidate`、`_reservation_candidate` 已使用的局部所有权方式，仅复制被写入的映射与记录；饮水需要 actors、waiting_life/needs 的路径和 adaptations；缺包需要 staff 记录。必须审计报价完整调用链只读，并保留不同世界身份带来的空间缓存隔离、未改变角色/其他占用、去返程和事实/RNG只读。不能复用一个修改过的 projected world 跨独立观察者。

**规则与选例。** 缺包选 `OPS-07/11/32`、`CLIN-08/11/34` 的缺包归属与重试分支；饮水选 `STAFF-35` 和环境实际饮水可达/短段占用定点用例，新增忙饮水设施的完整事实/RNG只读断言。静态确认复制范围与调用条件，未测得单项收益。

另一个整世界 clone 在 `recruitment_service.gd:320 _search`，仅明确付费寻访命令触发，用于冻结候选/RNG后再支付。它属于同类过宽投影，但频率是人发命令，不是每步；可在独立改动中仅隔离 entity_next 和 recruitment RNG，选择 `STAFF-38` 的失败原子性。不能把它纳入缺包每步倍率或无依据排在主热点之前。

## CL-A07 一次容量预算中每个设施资源重复扫描全部维修/升级工单

`arrival_service.gd:425 capacity` 对三班构建预算，`:970 _resource_budgets → :986 _maintenance_remaining`。后者 `:999–1009` 对每个设施资源扫描全部维修和升级工单，才过滤 facility_id、终结、暂停与实际 worker rate。倍率为最多 3 × 相关设施资源数 × 全部工单数；历史终结工单也先被访问。

现有 capacity reference/classes/native role model 缓存复用结构模型，资源 budgets 的当前工作量仍重新读取；这是正确职责，重复的是按 facility 查同一批当前工单。最小候选是在单次容量请求以设施分组非终结工单：正常推进的工单合计未截断余量，再按班应用原 `_shift_remainder`；任一暂停、无工人或非正工作率仍单独标记为每个所查班次的完整班阻塞，不套用正常余量截断。保留同设施多工单相加的原契约，不缓存随工时变化的最终能力值，不启动正式容量矩阵来代替先验审计。若实施，定点选择 `GROW-03/08/39/43` 与维修暂停/实际工时用例，使用小模型独立预算预期。静态候选，完整容量与正式矩阵保持暂停。

## CL-A08 招聘状态轮询重建全部匹配简历和标准候选

跨模块调用已复核：`game/ui/recruitment_panel.gd:123 _search_status` 调用完整 `RecruitmentService.query`，然后仅读取 active_search。状态栏只使用寻访状态；招聘内部 `recruitment_service.gd:218–231 query` 每次排序全部候选、对每个匹配候选调用 `card:205`，并调用 `standard_preview:188`。card 深复制候选并核验真实入口 `_entry:600`、投影适配/天赋；standard_preview 还做确定性标准生成。刷新显式列表的 `_refresh:61` 需要完整 query，但寻访剩余时间文字不需要重新制作这些卡片。

倍率为每次可见状态刷新至少一份 standard + 匹配候选数份 card/入口查询，与当前搜索是否为空无关。query 不消耗实际随机流，但确定性不代表没有成本。最小候选是招聘服务提供 active_search 的窄只读状态投影给状态栏，保留完整 query 的公共含义和显式列表刷新。不要把候选卡 entry/价格缓存成跨录用、资金或入口变化的旧结果。选择 `STAFF-36/38/39` 的标准身份/寻访余量/每日候选，以及状态文字不构建 cards 的调用计数断言。该调用链与界面审计 `PRES-06` 是同一根因，统一以 `CL-A08` 计数，`PRES-06` 仅保留为交叉引用，不增加问题数或收益。静态候选，无 UI 性能测量。

## CL-A09 研究解锁查询按已知 research_id 反复搜索任务历史

`research_service.gd:467 disease_unlocked` 遍历已解锁 research IDs，每个 ID 内再次遍历全部 research_jobs，找该研究的 completed 冻结 rewards，找到后才查病种。调用链为 `arrival_service.gd:1260 _disease_weight`（admission/选病权重）及 `clinical_runtime.gd:2116 arrival_readiness`。研究成果必须优先使用原任务冻结 rewards；重复的是按相同已知研究身份检索任务，而不是应删除冻结快照。`rewards:461`、`active_job:296` 也按 research_id 查询任务，归为同一个研究任务归属问题。

倍率为一次解锁检查已解锁研究数 × 全部任务历史；目录研究数有限，静态优先级低于 GP 实测热点。最小候选是研究任务所有者提供保留原首次命中语义的 research→completed/active job 只读索引，在创建/终结/恢复时重建或更新；不可从当前 content 重算旧成果。当前 ensure 的 visits 扫描只在缺失 research_progress 的迁移分支执行，不能误报为每步重扫。选择 `GROW-34/35/37/38` 的冻结成果、实际解锁与恢复。尚无单项耗时证据。

## CL-A10 无员工椅时同次休息派单重复完整茶位搜索

**现场输入与来源。** 运营组合输入位于 tick 1151，输入 SHA-256 为 `de7910789ad8405de0a3f88a1613ede60653422856c42b084df09532550e0247`，来自门诊已开始边界 `f7e184d2c2ff4a5b3047f6d9bbaffe7221d1028a56156743bfd1bf0230af0ca8`。保存的 `operations-input-setup.json` 中，`setup.need_inputs` 仅把空闲接待员 `bench_staff_0024` 的能量从约 98.98 置于需求临界值 35，以及把空闲手术排班医生 `bench_staff_0008` 的 awake_ticks 从 1151 置于强制睡眠临界值 13500；未提供任务、预约、移动或完成进度。setup 同时记录 `facilities_unchanged=true`、`actor_facts_unchanged=true`，全部 160 人及 1,336 设施保留。

休息区规模由该输入的原构造及布局保留链确认：`tools/performance/fixture.gd:86–105 _build_floor` 在每层 16 个房间的索引 08、13 建造 `rest`，房间均为 8×8；四层共 8 间，分别为 `bench_room_{1,2,3,4}_{08,13}`。每间只建两个 `SE04` 床，故员工区共 16 床，没有 `_is_seat:769` 接受的休息椅。`representative_prepare.gd:65–69` 额外复建的是 room_id 为空的公共座位，不能通过 `_staff_area` 成为员工椅。这里的布局数量来自原构造、已保存输入的保留断言和现场来源链；未通过另跑引擎重新计数。

**具体调用链。** `staff_wellbeing.gd:60 dispatch` 按 awake_ticks 降序处理员工；强制睡眠医生先进入 `:88 _begin(...,"sleep")`，接待员随后因能量 35 进入 `:101–102 _begin(...,"rest")`。休息派单 `:225 _begin → :238 _dispatch_task → :251 _select_facility` 在通过原安全承诺和移动检查后执行。`_select_facility:366` 先用 `_tea_position` 取得茶位路程，作为比较座位总恢复时长的基准；`:372–404` 搜索实际员工椅。该输入没有员工椅，函数返回空设施结果，已经算出的茶位没有返回调用者。`_dispatch_task:265` 随即再次完整调用 `_tea_position`，才设置茶位移动任务。

**必要工作、重复工作与倍率。** `_tea_position:407–425` 遍历所有员工区的 BuildGeometry.cells，对通过身体、门口、设施服务点和占用检查的每个格子调用真实 `space.route`，选择最短实际路程。8 间 8×8 房间每次最多检查 512 格；设其中 C_tea 格通过检查，单次休息派单会调用相同完整搜索两次，产生 2×C_tea 次路线入口，而不是只重算最后一个格子。512 是几何格数上界，不是实测路线数，也不表示所有格子可用。第一轮要把茶位与员工椅的恢复总时长比较，候选和实际路线均有业务用途；重复的是相同员工、同一只读世界下，已得到茶位结果却在无椅分支丢弃并重算。

**已有缓解与最小边界。** `_tea_obstacles:617` 已在一次茶位搜索内构建一次局部障碍索引，`_tea_cell` 没有逐格重扫全部设施；但两次独立 `_tea_position` 仍各自构建并遍历。`_select_facility` 与调用者的 fallback 之间没有实际预约或移动提交；局部查询结果可由这一次休息派单传递到原 fallback，再在真正移动提交时保留原空间核验。最小边界是同次派单内复用已经完成的茶位选择，不持久保存分数或路线，不跨其他员工预约写入复用，不限制员工区、格子、设施或人物数量，不改变全体型可达和最近路程选择。

**睡眠、娱乐与归因边界。** 睡眠分支 `_select_facility` 不预先搜索茶位，不能套用“两次茶位搜索”的倍率。若原安全检查允许实际派单，排序在前的睡眠医生会搜索 16 床的独立适配与完整去返程，只有未取得床位时才进入茶位 fallback；这类成本可能先于接待员发生，尚未由函数阶段记录确认。`_dispatch_recreation:584` 仅检查已有娱乐预约的实际到场并开场，没有路线搜索；完整设施/路线枚举位于 `_recreation:520`。两名 need 员工分别受能量 35 和强制睡眠条件阻止娱乐，因此不能把它们的输入直接解释为新娱乐查询。单次 route 内部的公共动态前缀重复属于运营审计 `OP-A12`；本项只统计调用者重复整次多目标搜索，不把两项潜在收益相加。

**当前测量状态。** 保存的 nested 运行记录表明，tick 1151 的第 0 步只有 enter 标记，55.345s 超时后终止，没有完成任何完整步，也没有函数/相位完成结果。它证明该组合输入的首步没有在 watchdog 内完成；尚不能证明已经执行到上述接待员分支，不能把 55.345s 全部归入茶位搜索，更不能给出本项实测收益。本项为静态确认的重复查询，未实施、未作单项计时。

**规则与选例。** 若实施，选择 `STAFF-22/41` 的实际员工区、身体兼容、完整去返程和恢复总时长；补充“没有员工椅但有合法茶位”和“茶位全部不可达”的独立边界，核对完整候选得出的同一结果、事实/RNG只读、fallback 和真实移动提交，并以调用计数证明同次派单没有重复完整茶位搜索。床、人物、清洁任务及装修需求继续保留。

最新只读复核的源身份如下；运营 before 工程与工作区的员工生活服务、fixture 文件哈希一致：

| 来源 | SHA-256 |
| --- | --- |
| game/staff/staff_wellbeing.gd | `5336687e79a03dc8426e18ece5775051392cac6c7507a1c5012b9a88334de855` |
| tools/performance/fixture.gd | `f99efd9dd5cf8afa2f7ca89f221edbcc54c2e080b1d0339d4b7de80874145189` |
| operations-input-setup.json | `7a81a723e256a9110553057534d6e04da259d577f2eb7d0a2e1e0a79dc6a2cf1` |

## 全文件覆盖与未报告为问题的路径

| 文件 | 覆盖状态及结论 |
| --- | --- |
| game/clinic/clinical_runtime.gd | 全函数/循环/复制入口清单；派单、服务候选、方案报价、床/手术、临床释放、临床可用性、供给缺项、到访 readiness、reference pipeline 重点跟链。CL-A01/CL-A03/CL-A06；已修医生下推单列。手术三个互异岗位、不同身体/设施适配与真实路线是必要组合；已有 bed_quotes、workbench_reachable、reference diagnostic/component/query memo、预资格池和设施定义索引，不能一概删除全组合或“再缓存全部” |
| game/clinic/hospital_visitors.gd | 全函数/循环；到期扫描、请求/入院探针、等候点、床边/医疗让位、真实离院、恢复校验。CL-A03；只复制 actors 映射并加入探针，非整个世界深拷贝；动态空间清障停在 HospitalSpace 已定义的查询边界 |
| game/arrivals/arrival_preparation.gd | 全函数/循环；主线程 capture→封闭请求→worker→poll/commit、捕获所有权与取消/恢复。生产 seal_capacity→sealed_projection 一次封闭后复用，不因每次 poll 重建742例。公开 projection 重新读当前输入是未封闭预览接口，不能误报为生产每tick复算；_own_capture 按记录复用，去除不相关 use_receipts |
| game/arrivals/arrival_service.gd | 全函数/循环；实际机会、在院人数、到期耐心、离院/居民保护、三班模型/预算/reference缓存。CL-A01/CL-A07/CL-A09 交接。opportunity 循环每机会重读人数和额度为明确规则 GROW-12；_reference_classes 有 basis/experience/transport/weights 缓存，按疾病共享 experience；不能称三班每步都重跑 |
| game/arrivals/capacity_solver.gd | 全文件7行；封装 PlatformArrivalMath.solve，脚本无额外对象交叉扫描。native solver 不在本分区；封装简短不能证明 native 高效 |
| game/arrivals/day_plan.gd | 全函数；三班定长分配、slot_tick按当前机会计算、精确概率/拒绝采样及恢复校验。循环用于要求的精确分配、随机分布与hash稳定规则，无确认的角色交叉扫描；不能改随机流/舍入换速度 |
| game/arrivals/exact_fraction.gd | 全函数；整数格式校验与 native exact arithmetic 包装。无本分区确认的世界全扫描/多对象查询；大整数 native 算术成本未在此测量 |
| game/staff/clinical_development.gd | 全函数/循环；课程报价/共享研究桌/mentor、dispatch/advance/settle、safe_busy、基地队列/让路、实践/退款。CL-A02/CL-A03/CL-A04/CL-A05；真实先课程结课后实践的顺序和 entity队列可见性不能为批处理改变 |
| game/staff/recruitment_service.gd | 全函数/循环；标准生成/query/card/entry、每日候选、寻访/录用付款、技能/凭据/首次工作、输入校验。CL-A05/CL-A06/CL-A08；每日候选先last_passive_day守卫，寻访推进先同tick守卫，历史校验非每步执行，均不冒充高频扫描 |
| game/staff/shift_scheduler.gd | 全函数/循环；排班/休假边界、病区真实交接、suggestion/coverage、available_ticks、应用/恢复。CL-A03 safe_busy调用。dispatch已有related_stays/nurses_by_ward/candidates_by_ward/nurse_busy，且接受新交接后立即阻塞护士；不能报告为每床再次全员全病区建模。coverage的三班检查定长；_has_facility两类型扫描可用定义索引缩小，但低频建议/预览且已有明确边界，不单列热点 |
| game/staff/staff_wellbeing.gd | 全函数/循环；离岗安全、自动错峰/睡眠、座位/床/茶位、完整往返、娱乐伙伴/额度、占用/恢复。CL-A02/CL-A03/CL-A10；tea obstacles 每次茶位搜索只构建一次，_tea_cell读取局部障碍，不能误报每格重扫全院；CL-A10 是调用者同次派单重复整个茶位搜索。_adapted_candidate仅复制写入路径，不是整世界深拷贝；_relief_available/_pool_resting仍按候选扫描同岗位员工，可归入CL-A03但必须在前一员工离岗后即时更新 |
| game/community/research_service.gd | 全函数/循环；前置/资料/任务创建、共享桌/worker、推进/完成/退款、冻结rewards、接诊缺项、输入恢复。CL-A02/CL-A03/CL-A09；preferred desk/worker在资格/路线前过滤；ensure仅迁移时扫描全部visits；已完成job在阶段遍历中早退，历史active/pending可另随CL-A05所有权方案评估，不直接删记录 |
| game/life/waiting_life.gd | 全函数/循环；自动/手动选位、八条件/邻居索引、真实占位、叫号、生活需求安全段/返回、饮水将来释放、恢复校验。CL-A03/CL-A06；设施候选先按定义/路程下界，actor_index复用，环境/路径交给原服务；提交时复核有明确需求依据 |
| 全部13个 .gd.uid | 完整元数据读取并记录SHA；只包含Godot资源身份，没有执行循环，不另改动 |

覆盖是本分区的同类静态审计，不是对全部业务正确性或性能达标的证明。跨到空间、环境、供应和界面的调用追到已确认的语义边界；这些模块内部的额外计算不纳入本分区结论，跨分区的同一调用链合并计数。native arrivals/GMP、渲染、GPU、完整容量矩阵和两小时稳定性均不在本次执行范围。

## 后续测量选择

先保留已测 GP80 的固定输入、全部人口/候选与事实约束，核对主热点修复后的剩余相位；不能拿最坏静态复杂度推翻已经获得的实际排序。随后只对实际出现的 CL-A01/CL-A02/CL-A03/CL-A06 分支增加调用计数/包含时间，优先验证无方案回退、多等待候选、真实缺包或忙饮水条件。每次只实施测得且可用局部所有权解释的最小变化，同输入比较整步及业务结果；历史规模、研究/课程/预算属于其真实触发窗口，另选固定合法输入，不与未覆盖场景混称。

审计未执行后续测试、基准或源代码修改。正式矩阵、完整容量计算、GPU和长时间稳定性保持暂停。
