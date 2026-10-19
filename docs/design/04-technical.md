# 技术架构、数据与保存

## 1. 固定技术基线

项目内部标识统一为 `oddly-good-hospital`，产品名为《怪好的医院》（Oddly Good Hospital）。安装目录、用户数据目录、可执行文件与发行元数据均使用该标识，快照格式为 `oddly-good-hospital.snapshot`，导出扩展名为 `.oghbackup`。当前尚未发布游戏或产品存档，不建立旧工程名的兼容目录或自动迁移入口；首次交付从本标识与 snapshot schema1 开始。

| 项目 | 选型与责任 |
| --- | --- |
| 引擎 | Godot 4.7.2 标准版，编辑器和导出模板同版本，带类型 GDScript |
| 画面 | Compatibility，OpenGL 3.3 路径；3D正交镜头，Godot Control界面 |
| 建造和移动 | 二维逻辑网格与四邻显式图；AStar2D只负责层内搜索，图适配层维护真实包络、合法边与确定性；跨层按到站时刻报价搜索，Movement负责实际扫掠和礼让，见完整导航选型 |
| 内容 | 版本化UTF-8 JSON及CSV本地化；发布前校验后装入不可变注册表 |
| 美术 | Blender 4.5.14 LTS源资产，显式导出glTF 2.0二进制GLB；不要求玩家安装Blender |
| 声音 | WAV源文件、Ogg Vorbis成品；AudioStreamPlayer与位置音源 |
| 保存 | 每医院独立SQLite 3.54.0数据库、事务追加保存点、分段世界DTO及SHA-256校验；导出为受限ZIP格式 |
| Windows原生桥接 | 随包x86_64 GDExtension封装Win32资料库独占句柄、精确数值解码及SQLite；主线程业务规则与事实提交使用GDScript，纯计算后端沿下述依赖边界选型 |
| 测试 | 引擎无窗口模式、项目内SceneTree断言运行器；不引入外部运行时测试框架 |
| 安装 | NSIS 3.13，按用户安装；Windows x86_64 exe与独立pck资源包 |

以上版本于2026-10-11按官方资料核验：[Godot Windows](https://godotengine.org/download/windows/)、[Blender 4.5 LTS](https://www.blender.org/releases/4-5/)、[NSIS](https://nsis.sourceforge.io/Download)。Godot提供Windows导出和3D导入机制，实际项目仍需完整验证资源打包与运行。[Windows导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)、[3D导入](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html)。

SQLite嵌入原生桥接，无数据库服务、账户或后台进程，玩家不另装SQLite。基础内容随安装包携带，启动及日常操作不联网。SQLite使用固定官方源码与构建身份，不自动追随新版本。[SQLite官方源码](https://sqlite.org/download.html)。引擎升级是明确的工程变更，需重跑存档、内容和性能验证，不自动追随stable标签。

### 引擎能力、第三方依赖与业务适配

Godot的[Asset Library](https://docs.godotengine.org/en/4.7/community/asset_library/what_is_assetlib.html)提供社区插件、脚本、工具和资源；可复用依赖也包括直接嵌入的原生库。资源库可下载不等于已适用于固定引擎、Windows发行包或本项目的业务与性能合同。采用具体版本时核对接口覆盖、维护状态、许可证及传递依赖、离线打包、完整错误语义与实际成本，记录来源和构建身份；不在玩家运行时联网下载。

| 能力 | 复用与项目边界 |
| --- | --- |
| 并发任务 | 优先使用Godot已有Thread或WorkerThreadPool，业务只定义只读输入、结果身份、失效和提交顺序，不另写通用线程池。 |
| 路径搜索 | 已有AStar2D承担层内搜索；项目适配真实身体、预约通行、确定性和跨层时刻。搜索库不拥有服务预约或移动事实。 |
| 数据库事务 | 已有SQLite承担存储事务；项目桥接负责固定平台接口，保存协议负责医院身份、冻结边界和完整提交。 |
| 容量数值求解 | SoPlex精确有理数模式承担连续优化，GMP统一承担任意精度整数与分数运算；项目拥有医院资源/岗位/病例模型、隐式资源选择的完整定价、K和精确结果合同。通用离散搜索采用SCIP精确模式。选型本身不构成本机达标结论。 |
| 流式编解码 | RapidJSON承担JSON通用编解码，minizip-ng/zlib承担ZIP通用结构与CRC；项目继续拥有世界类型、范围、保存边界、哈希及受限归档策略。按实际替换责任接入，不改变文件协议。 |

[SoPlex](https://soplex.zib.de/)提供稀疏修正单纯形与热启动；其[精确求解模式](https://soplex.zib.de/doc/html/EXACT.php)使用GMP并显式启用精确输入、同步和校验。求解与完整最优性检查按批次在原生计算中完成，不逐标量跨语言调用。浮点容差解不能替代精确容量及日计划分数，也不能因库支持LP便省略护士岗位选择与结构规模搜索。分数仍使用规范十进制分子/分母，取整方向和既有随机源保持；依赖或求解失败返回明确错误，不冻结伪零计划。依赖按实际接入记录固定来源、构建身份、许可证及离线发行文件，未接入和未验证责任单独记录。

医院时间遵循模拟规格§1.1及hospital_clock；0.1模拟秒固定步、1800模拟秒一日和24小时钟面均由hospital-time-v1定义。WorldState.sim_tick仍是唯一推进事实，钟面、日内班次及人类可读剩余量为精确比的投影，不保存clock_hour或第二套分钟进度。工资使用18,000tick日分母、运营使用20×18,000＝360,000分母；原真实tick费率分子、逐人持余、当前费率生效边界及日结凭据保持。日界、到访窗口和假期从同一当前基准派生，内容扩展不能换基准重建旧医院日期。自动保存、资源显示采样、帧率、输入与文件保留继续使用明确现实时间；同一参数不能在UI与模拟侧分别猜单位。

## 2. 工程目录与事实所有权

```text
project.godot                 项目和输入设置
export_presets.cfg            Windows导出
game/app/                    启动、医院切换、命令入口、设置
game/platform/windows/       资料库独占句柄的原生桥接与导出配置
game/content/                定义、包加载、索引、内容验证
game/sim/                    固定步长世界及业务系统
game/building/               建造校验、事务、蓝图与路线图
game/clinic/                 就诊、方案、手术、床位、队列、医生能力与排班
game/community/              事件、关系、故事、任务和研究
game/economy/                账目、工资、定期补助、奖励、援助、购买
game/persistence/            快照编解码、提交、恢复、导入迁移
game/view/                   场景投影、角色、机器、镜头和特效
game/ui/                     Control场景、面板和输入焦点
content/core/                基础包数据、文本、资源引用
assets/models/               GLB、材质与导入设置
assets/audio/                声音成品
assets/ui/                   图标、字体、界面素材
art-source/                  原始blend、音频工程与导出记录
tests/unit/                  纯规则场景测试
tests/integration/           状态恢复、流程、内容扩展测试
tests/fixtures/              小医院、满载医院、旧版和损坏保存点
tools/                       内容校验、打包、验证命令
installer/                   NSIS脚本和发行元数据
```

WorldState是唯一模拟事实，不保存到场景节点里。建筑系统拥有格子/墙/物件，临床系统拥有Visit、治疗尝试、SurgerySession与WardStay，员工系统拥有DoctorProfile、NurseProfile、排班、培训与员工任务，事件系统拥有Incident，成长系统拥有解锁、故事和任务实例；设备系统拥有故障与工单；建筑系统拥有土地和门；账目系统独占所有资金变化。系统通过同一世界内的明确命令和事实事件协作，不双向复制患者列表、资金或队列。

显示层只持实体ID、表现资源和插值缓存，不能加钱、判断治疗成功或自行结束冻结。面板从只读投影取数；同一个诊断原因同时供患者卡和接诊检查使用，避免两份判断不一致。世界对象不直接持Node、Texture、AnimationPlayer、文件句柄或委托。

## 3. 公共类型与模块接口

以下为需要实现的GDScript class_name和签名，类型文件位于所属模块的types目录。ID使用StringName运行、String保存；错误返回具有code、message_key、args、entity_ids，禁止用空数组同时表示“没有候选”和“查找失败”。

| 类型/入口 | 精确接口 | 责任 |
| --- | --- | --- |
| ContentLoader | load_packs(paths: PackedStringArray) -> ContentLoadResult | 返回registry或完整验证错误；全有或全无 |
| ContentRegistry | resolve_bindings(species_id: StringName, disease_id: StringName) -> Array[TreatmentBinding] | 以独立适配索引查询合法机器，不根据ID序号猜测 |
| GameSession | submit(command: GameCommand) -> CommandResult | 验证医院、世界修订号与命令ID，排队或立即执行暂停命令 |
| Simulation | step(world: WorldState, commands: Array[GameCommand]) -> TickResult | 完整执行一个0.1秒步长，返回发生的事实事件 |
| BuildService | preview(world: WorldState, draft: BuildDraft) -> BuildPreview | 只读、含价钱/错误格/影响范围/可撤销状态 |
| BuildService | commit(world: WorldState, draft: BuildDraft, expected_revision: int) -> CommandResult | 重新验证并原子提交，不相信旧预览 |
| NavigationService | request_path(actor_id: StringName, goal: CellRef, envelope: TraversalEnvelope) -> void | 按§6的人数额度处理全院FIFO移动队列，保存请求顺序，不因帧数或缓存改变结果 |
| ArrivalService / WaitDepartureService | plan_day(world: WorldState, day_index: int) -> void；evaluate(world: WorldState, visit_id: StringName) -> void | 当日随机机会计划、候诊离院抽签与唯一评估点 |
| FloorService | preview(world: WorldState, draft: FloorDraft) -> FloorPreview；commit(world: WorldState, draft: FloorDraft, expected_revision: int) -> CommandResult | 选梯所属地块/本层补块来源、当前下层Room、唯一模块单及原人员工具费用；完工原子交付，取消按冻结实付/标准工作量退款 |
| TransitService | quote(world: WorldState, actor_ids: Array[StringName], target: CellRef) -> TransitQuote；reserve(world: WorldState, actor_ids: Array[StringName], target: CellRef, connection_id: StringName, expected_revision: int) -> CommandResult；advance(world: WorldState) -> void | 报价只读；实际到齐的本组按明确输入复核站点/舱位/设备后入队，创建唯一TransitSession，不依赖界面报价缓存ID |
| RecruitmentService | list(world: WorldState, filter: RecruitmentFilter) -> RecruitmentList；search(world: WorldState, filter: RecruitmentFilter, expected_revision: int) -> CommandResult；hire(world: WorldState, source: CandidateSelection, expected_revision: int) -> CommandResult | 简历ID或标准筛选键+序号二选一，原子录用，工资从录用tick起算 |
| QueueService | enqueue(world: WorldState, visit_id: StringName, service_key: StringName) -> QueueTicket | 分配票号、幂等，当前服务仅一张票 |
| ClinicService | try_start(world: WorldState, ticket_id: StringName) -> ServiceStartResult | 原子占患者/员工/站点，承诺随机结果和费用 |
| HospitalEquipmentUse | query(world: WorldState, equipment_id: String) -> Dictionary | 只读返回placed、occupied、critical_commitment；从设备使用方与实际空间占用合并，不保存第二份预约或占用状态 |
| DepartmentService | assign_rooms(world, department_id: StringName, room_ids: Array[StringName]) -> CommandResult；change_focus(world, department_id: StringName, specialty_id: StringName) -> CommandResult | 区域归属、共享资源、专长冷却与报价 |
| ExperienceSystem | update(world: WorldState, facts: Array[SimEvent]) -> void | 怒气/等待原因、体验累计与有限评分窗口 |
| GuidanceService | correct_route(world, visit_id: StringName, guide_id: StringName) -> CommandResult | 按真实接诊范围/设备筛选错误候选并保存一次选择；纠正前重查等效目的地，需转科时保留票号与收费 |
| RenovationService | preview(world, draft: RenovationDraft) -> RenovationQuote；commit(world, quote: RenovationQuote) -> CommandResult | 付材料费、创建分格工单、取消退款、完工环境脏标记 |
| GratitudeService | evaluate(world, visit_id: StringName) -> void | 一次意向、名额、礼物与能力效果原子兑现 |
| WellbeingService | schedule_leave(world, staff_id: StringName, day: int, duration_days: int) -> CommandResult | 劳累压力、带薪休假、覆盖投影与安全释放 |
| PlanService | evaluate(world: WorldState, visit_id: StringName, doctor_id: StringName) -> Array[PlanQuote]；choose(world, quote_id: StringName) -> CommandResult | 过滤资格/路线/团队/床位，确定性评分；界面复用同一报价 |
| ScheduleService | preview(world, changes: Array[ShiftAssignment]) -> SchedulePreview；commit(world, preview_revision: int, changes: Array[ShiftAssignment]) -> CommandResult | 校验跨日休息、任务能力与覆盖，保留安全任务和补休 |
| DoctorDevelopment | train(world, staff_id: StringName, track_id: StringName) -> CommandResult；promote(world, staff_id: StringName) -> CommandResult | 条件、付费、独占研究桌；完成后原子更改能力/职称 |
| SurgeryService | try_start(world: WorldState, ticket_id: StringName) -> ServiceStartResult | 一次占用互异医护、设备、床位与窗口，复核方案并承诺结果 |
| WardService | admit(world, attempt_id: StringName, bed_id: StringName) -> CommandResult；transfer(world, stay_id: StringName, target_bed_id: StringName) -> CommandResult | 床位关联、护理覆盖、恢复工时、查房与最终结算事实 |
| IncidentService | evaluate(world: WorldState, facts: Array[SimEvent]) -> void | 条件过滤、名额与冷静期、创建或推进事件 |
| ResearchService | start(world: WorldState, research_id: StringName, desk_id: StringName, community: bool, allow_waiting: bool = false) -> CommandResult | desk_id为空表示自动选桌；检查前置/资料/费用及唯一任务，缺桌/人时只有allow_waiting明确为true才保留已付待办，普通计划排序不调用开始 |
| LandService | purchase(world: WorldState, plot_id: StringName, expected_revision: int) -> CommandResult | 邻接、价格和余额一次验证，原子取得土地 |
| EquipmentService | scan(world: WorldState) -> void | 固定tick抽故障、创建唯一工单，不能直接改医疗会话结算 |
| TaskService | accept(world: WorldState, definition_id: StringName) -> CommandResult；claim(world: WorldState, instance_id: StringName) -> CommandResult | 记录接取基线，消费一次性事实，领取通过Ledger |
| SubsidyService | settle(world: WorldState, completed_day: int) -> void | 以周期ID发放，不以读档或系统时间推算 |
| Ledger | post(world: WorldState, entry: LedgerEntry) -> CommandResult | 使用稳定entry_id幂等记账，不允许未覆盖负余额 |
| SnapshotCodec | encode_to(snapshot: WorldState, sink: ByteSink) -> CodecResult | 分段序列化只读DTO为UTF-8 JSON，写入SQLite BLOB分段，返回实际字节数和哈希 |
| SnapshotCodec | decode_from(source: ByteSource, registry: ContentRegistry) -> DecodeResult | 增量验型和资源检查，全部引用通过后重建世界，不推进时间 |
| SnapshotStore | write(request: SaveRequest, snapshot: WorldState) -> SaveResult | 调用流式编码、提交SQLite事务并返回可恢复的snapshot_id |
| SnapshotStore | recover(hospital_id: StringName) -> RecoveryResult | 扫描有效提交，列出最近候选及失败原因 |
| ReadModel | inspect(world: WorldState, entity_id: StringName) -> ObjectView | 单一解释模型，生成显示字段与可用动作 |

WorldState、GameCommand、SimEvent等为RefCounted数据类，业务实例不使用Godot场景序列化。GameCommand包含id、hospital_id、expected_revision、kind和typed_payload；TickResult包含sim_tick、revision和facts。CommandResult包含accepted、code、changed_ids、new_revision。服务失败必须保留原状态并返回可读原因。

expected_revision表示预览读取过的世界，不是“每过一个模拟步都拒绝操作”的锁。命令边界始终重新验证实际目标、价款、库存、资格、占地、可达性与安全承诺：若命令指定的对象、数量、已确认方案、费用/退款和被修改字段的原值仍一致，且当前仍可合法执行，则即使全局revision改变也可原子提交。别层患者走路、现金变化但仍够支付、无关工单完成或预计排队秒数变化，不要求玩家反复确认。费用改变、候选身份/库存复用对象变化、同一字段已被另一操作改写、已选内容失效或安全条件不再满足时，保持原草稿和世界不变，返回具体差异供原面板刷新；不自动替换更贵设施、不同候选或另一组排班。

各服务从既有定义和真实实例生成自己负责的预览依据；依据只是本次命令的已确认值，不是第二份可修改的世界。建造检查实际草案与付款，采购检查同一品项/数量/单价和当前容量，招聘检查原候选身份/能力/费率，排班检查受影响员工的原班次、建议差异与安全覆盖。自动排班建议若这些依据或已展示的覆盖缺口发生实质变化，就重新生成差异供应用；没有相关变化时不因时间走了一步而拒绝。临床自动选站与方案重评仍使用各自调度规则，不套玩家确认框。

### 大面积建造预览的计算与发布

preview_computation服务既有建造、搬移、蓝图与“试试看”的原活动预览会话。最多一个当前计算任务及一个可替换的最新请求，不积累鼠标轨迹上的所有旧草案；新请求先替换待办，旧计算在下一个安全切片停止并释放原引用。草案格/方向、实际对象绑定、主体/体型或检查选项等语义变化才增加draft_generation，同格鼠标像素微移、无关世界tick和其他层经营不反复重启。原当前轮廓/定位先显示，完整检查前不保留旧可建/可开诊/路径通过状态；只有同一当前草案的完整结果才可以就绪。

请求逐项绑定医院加载会话、view_id及代次、实际观察层、原预览会话、草案ID/代次、按原稳定楼层顺序规范化的源楼层集合、目标楼层、内容指纹、查询类型、主体身份、实际TraversalEnvelope和完整query_options。未选居民的标注示例与真实患者/职员身份不同，不能凭同种族/同身体拿另一人的资格或预约结果。切层后的草案仍属原层，视图绑定改变就撤旧显示；结果不能贴在同XY的另层、新医院、已取消草案或新布局，恢复旧保存点沿原新会话规则。只读结果及任务不进WorldState。

仅镜头/视图绑定变化时，完备且当前相干依据仍有效的原语义结果可重绑到当前投影，不因此再次检查整层业务；显示发布必须使用当前视图身份。地图叠加只在实际观察层等于原草案目标层时绘制，看别层保留原草案栏中的源/目标层说明，不能把1F物件画到10000F。重绑不修改目标层、原草案或已确认清单，当前结果与原任务/请求/退场值一起计资源。

每个原查询处理器提供完整的相关语义依据：原草案/对象值、报价/库存复用、实际楼板/几何、完整身体与操作/伸展范围、准入/资格/预约及原安全/可达要求。判定当前是否仍够付款读取同一固定报价的相关条件，不能因现金改变但仍足额、无关工单或另一层走动便要求重复确认；预计余额等显示仍读原当前经营来源。依赖关注完整查询作用域，包括开始为空而后来进入的真实身体、新阻挡/预留和可能改变出口/连通的几何，不能只订阅旧命中对象或旧路径。要求全层/跨层出口及安全可达时必须沿原完整查询域检查，局部脏桶只能筛选重算，不能凭草案邻格无阻碍宣布整院安全。

分片检查在主线程读取所需原只读值和已验证派生查询，记录同一套完整相关依据；切片之间发现相关原事实变化，撤就绪并重取当前原查询。不能混拼不同修订的墙/床/演员而产生世界中从未存在的“安全布局”。后台不得读取活跃WorldState、场景树或共享可变AStar图，不为每次拖动复制整个医院。处理器不能证明依赖完备或不能取得一致只读上下文时，沿原完整主线程查询；不能用部分结果/未知索引输出许可，也不省略安全检查来满足帧预算。

查询、切片、当前轮廓/叠加上传、取消和退场共用原每帧2ms新增显示工作目标，和角色绑定/热图相互计账，不另藏一份预算。可分片的范围、节点和部件继续细分；无法分片的一次调用也记录实际越界与普通帧成本，不把整层阻塞查询当免费原子操作。路径缓存/近邻只沿原完整身份与当前修订使用，不向全院Actor移动FIFO放虚假请求、占其额度或预约试用身体。任务临时值、最新请求和未释放旧引用全部计原工作集/显示资源，没有全院深副本、角色对矩阵或空层预览任务。

发布时整份结果必须完整，并逐项匹配当前请求及已验证的完整相关依据；不拼接上一草案的绿格/费用与新草案的部分路径。相关语义事实相同可继续使用，不绑定全局revision或显示tick。必要依据变化先撤就绪，显示原草案的检查/具体阻碍；完整检查本身不付款、占位、停诊或开始装修。原明确确认仍在命令边界原子复核当下目标、报价、库存和安全；计算未完不排自动确认，结果就绪也不会自行应用。实际差异沿原material_change保留草案供刷新，不新增第二套确认或静默替换。

原输入/预览P95≤100ms、房间预览≤200ms及普通帧目标继续采用原输入到当前反馈/完整结果的证据，分别记录挂起时长、被替换/取消次数和单次越界。不能把只画轮廓、一直取消、仅从最后静止或任务开始计时当完整预览已经通过。原96×96同层160/640、宽高联合样例测试持续拖动/旋转、大蓝图、完整多房搬移、角色进入草案区域、门/楼板相关变化及切层/恢复；比较原完整检查与分片结果，现阶段没有真实查询延迟或帧率证明。

提交入口同时核对当前医院和加载会话，切医院或恢复旧保存点后丢弃旧会话尚未入队的输入。已入队命令遵循保存前排空规则；同一命令ID只产生一次效果与回执，重按按钮不重复采购、录用或付费。加载会话标识只约束运行时输入与回执，不混入模拟随机流或保存的经营状态。

暂停命令和正常模拟共用验证逻辑，不另建“编辑器世界”。SceneTree负责输入与帧循环；Simulation负责固定步长。界面刷新最多10次/秒，数值变化由事件标记脏数据，镜头与角色插值按渲染帧更新。

三日财务展望按模拟经营规格§8.2的真实依赖失效，使用原可取消只读查询与同一当前边界的财务来源。10次/秒是普通显示发布上限，不是每100毫秒重新求整份预测的定时器；原输入与命令回执不等待预测。仅纯tick变化且固定期末金额已证明不变时复用原显示结果，不能冻结面板内的实时累计与日期。关闭该页停止它的预测工作，重新打开读取当前来源；迟到结果校验原hospital_session、panel和query_generation，旧医院、已关页或旧请求不得发布。账目与采购继续原固定阶段，不由面板开启状态驱动。既有聚合可用时读取它，否则沿原所有者查询；不预设已有全员工资聚合接口或宣称查询必为常数时间。

本次医院会话的播放控制唯一持有玩家requested_speed（0/1/2/3）、最近主动选择的运行速度、由当前窗口/退出操作持有的临时暂停令牌集合，以及既有观看会话的可选1×覆盖。玩家意图为0或有任一暂停令牌时实际速度为0；否则有仍有效的观看覆盖则为1，没有覆盖则取玩家意图。每个来源只添加/释放自己的令牌，重复关闭幂等，不维护“关窗便弹出旧速度”的多层恢复栈。手动改速撤销观看覆盖；取消退出先把意图置0再移除退出令牌，载入新医院清除旧会话并以0开始。旧会话窗口回调不得操作新集合。这些属于视图控制，不保存进WorldState、不改变随机流；全局暂停时也不能用现实累计补推进模拟步。

## 4. 运行数据模型

| 实体 | 必需字段与约束 |
| --- | --- |
| HospitalMeta | hospital_id(UUID)、display_name、seed_decimal、mode、created_utc、play_ticks、tutorial_flags(各步骤完成/跳过与至多两个事实标记、未发教学请求/消耗凭据、本院开关、情境已读/停用/延后日及提示冷却)；mode只在命令边界改变 |
| ArrivalPlan | intake_open、disease_intake_weights、current/next_day_preset_id、day_index、frozen_scale_numerator、scale_mode、held_scale_numerator、held_capacity_fraction；当日frozen_capacity_by_shift[3]、opportunity_count、shift_opportunity_counts[3]、schedule_seed、schedule_algorithm、next_slot_index。容量用约分非负分子/正分母十进制，班数和为N；冻结值归日计划，不成为可修改真实容量/人数。开关权重只筛新Visit。 |
| CellRef / FloorStructure / FloorState | CellRef包含floor_id与xy:Vector2i；FloorStructure拥有每个地面已购plot真正完工并取得的连续最高层，不能证明当前存在房间；FloorState只保存实际布局差异；1F面取LandState，上层面须地面已购且显式高度覆盖，空层拓扑按需派生 |
| FloorDraft / 模块购买施工单 | 草案拥有入口、目标floor/期望plot，选梯入口另含connection_id，提交从真实主锚点核对；原订单唯一拥有目标floor/plot、冻结paid_cost/标准总量、remaining_work、当前worker_id/正下层工作点、主动暂停、贡献与付款/退款/完成凭据；来源梯不作为已付单的强引用 |
| ArrivalDayPlan视图 / WaitDepartureState | 前者为ArrivalPlan只读当日视图，不另存日时刻数组/计数；后者拥有当前票号下一有效等候阈值与离院决定，沿原等待时钟。 |
| VerticalConnection / LiftTransportState / TransitSession | 各层端口引用唯一主设备；连接拥有叫梯序号，主设备拥有空载余量与指派组，实际组拥有登舱/通行/离舱余量；Actor实际位置互斥，完整字段归随机来客、多层与招聘章 |
| RecruitmentState / Candidate | 有界简历池、关注、寻访进度、标准招聘种子/录用序号；员工内容引用与冻结候选能力 |
| WorldState | schema_version、sim_tick、revision、next_entity_sequence、rng_streams、content_fingerprint、实体集合、系统进度；actor/pair/zone冷静期映射、装修与社区效果、评分窗口和休假、next_global_incident_tick、到访/故障扫描时钟、任务板刷新期必须保存 |
| Resident | id、species_id、appearance_id、profession_id、social_personality_id、quirk_id、name、regular、story_role_ids、last_departure_tick、pending_release；患者与访客共用身份，实际离院更新回访间隔 |
| VisitorStay | id、resident_id、arrived_tick、left_tick(实际未离院为空)、purpose(companion/ward_visit/activity)、related_visit_id或activity_instance_id、探视起止tick/原陪诊理由、major_event_participated；同居民不能同时拥有Visit和访客停留，普通访客关联另一位患者的Visit；陪诊随关联就诊结束离院，探视在床边30秒结束后离开或回陪诊等候，活动由散场驱动，不套固定停留钟 |
| Actor | id、resident_id或staff_id、location_kind(floor/transit)、cell:CellRef或transit_session_id（二者互斥）、edge_to、edge_progress(0…1023)、route_cells、route_index、navigation_request、goal、pose_state；可在两格之间保存 |
| Visit | id、resident_id、disease_id、stage、evidence_by_source、attempts、affect_id、experience_id、communication_state、consultation_behavior_id、preparation_cues(所选来源、原工作引用、完成事实，不复制工时)、need_state、current_ticket_id、session_id、interruption、outburst_consumed、major_event_participated、initial_consultation_charge_id、arrived_tick、complexity(normal/complex)、plan_decision_id、participating_doctor_ids、final_settlement_id |
| Staff | id、species_id、appearance_id、role、social_personality_id、work_style_id、biography_id、五非医护岗位的job_skill/job_experience、research_practice_remainder_ticks、practice_fact_cursor、first_job_shown、doctor_profile_id或nurse_profile_id、energy_milli、stress_milli、awake_ticks、sleep_remaining_ticks、sleep_phase、sleep_bed_ref、offsite_rest_started_tick、offsite_sleep_satisfied、work_block_id、base_preparation_remaining_ticks、base_preparation_done、休闲/分配/任务与工资字段；医护不再保存通用岗位等级或资格集合，天赋由种族引用派生 |
| DoctorProfile | staff_id唯一、title_id/title_changed_tick、diagnosis_level、treatment_level、surgery_level、primary_track、personality_id、三能力practice_by_track、completed_courses、cured_case_count、completed_attempts_by_plan、training_id、growth_goal、occurred_growth_moment_ids、fatigue_milli、leave_plan_id；无科室/麻醉子能力或重复资格 |
| NurseProfile | staff_id唯一、diagnosis_level、care_level、surgery_level、三能力practice_by_track、training_id、growth_goal、occurred_growth_moment_ids；只有适用岗位的有界成长标记，研究和岗位共同派生检查/护理/手术协助资格 |
| ScheduleState | staff_id、daily_template、today_overrides、rest_debt_ticks、rest_target_energy；过往班次不无限保存 |
| ShiftAssignment | shift_index(0…2)、kind、pool_or_room_ids、locked_by_player；每班唯一，跨日最多连续两个工作班，建议不改手动锁定班次 |
| DevelopmentJob | id、staff_id、kind(course/promotion)、track_or_title_id、target_level、paid_fee、work_total_ticks、work_remaining_ticks、desk_id、mentor_id、completed_fact_id |
| PlanDecision | id、visit_id、plan_id、binding_or_adapter_id、consultant_id、expected_staff_ids、quote_revision、expected_probability_bp、reason_components、decided_tick、selection_source(automatic/manual)、pending_review_reason、handled_quote_revision；只保存当前决定，报价不是资源锁 |
| 教学病例保护 | 未发教学请求归HospitalMeta.tutorial_flags；入院后一次保护归对应Visit，首个实际TreatmentAttempt消耗并冻结结果；离院不退回请求，帮助不拥有或重置病例 |
| TreatmentAttempt | id、visit_id、plan_id、binding_or_adapter_id、attempt_index、source_rules_version、committed_success、probability_bp、work_total_ticks、recovery_total_ticks、冻结操作者能力与主体设备等级/effective_upgrade、supply_units_consumed、supply_consumption_id、cure_fee_snapshot、procedure_fee_quote、ward_fee_quote、分项charge_ids、applied_wear_subject_ids(仅本次实际使用主体)、settlement_id；本次领用/治疗收费/结果唯一所有者 |
| SurgerySession | id、attempt_id、room_id、surgeon_id、anesthetist_id、nurse_id、observer_id、equipment_ids、bed_reservation_id、phase、work_remaining_ticks、wake_remaining_ticks；三位必需员工互异 |
| ClinicalPreparation | id、visit_id、plan_decision_id、resource_ids、supply_units_reserved、adaptation_ids、expires_tick、器械核对总量/余量；资源和治疗包原子预留，开工才领用，不提前增加尝试或结算实践 |
| BedReservation | id、preparation_id、attempt_id(开术前为空)、bed_id、expires_tick、committed；开始前30秒过期，开术后到转床/转诊才释放 |
| BedSlot | bed_object_id、ward_room_id；床内监护和照护卡由同一设备定义提供，无外部组件实例或第二份等级/状态 |
| WardStay | id、attempt_id、bed_id、标准恢复余量（定点工作量）、当前覆盖段冻结的护士/床等级/工作率与不足一工作tick余数、主动护理唯一任务与贡献、nursing_visit_done、discharge_round_done、assigned_nurse_id、no_progress_since_tick；不复制总量/效果/收费 |
| 陪诊/探视请求 | 关联Visit、目的、创建tick、窗口、Visit持有的当前探视日/早中窗口评估与消耗位、已抽意向、暂不接待、已绑定亲友引用或临时模板；每活跃Visit至多一份院外请求，Actor实际入院才创建，患者终结取消请求但不删除在途家属 |
| CareDepartment | id、name、room_ids、public_area_cells、intake_anchor、focus_specialty_id、pending_focus_id、focus_ready_tick、shared_facility_ids；room_ids归属独占，评分为投影 |
| RegistrationRoute | visit_id、chosen_department_id、correct_department_id、error_rolled、corrected、guidance_task_id、original_ticket_sequence、可选wrong_entry_fact_id与发生时department_id；corrected表示路线解决，真实到错入口才影响评分/怒气，职员成绩只取本人完成工作，不复制Visit诊断 |
| InteractionContext | id、predicate_id、producer_id、source_fact_sequence、actor_ids、target_ids、created_tick、expires_tick、consumed；最多160条，10秒过期，无物种即触发规则 |
| ComedyState | scan_cursor_actor_id、recent_scene_starts≤144、major_starts≤7、last_consumed_fact_sequence；冷却与最近三场只读派生，见熟客记忆规格 |
| CommunityMemory | resident_id、memory_id、callback_id、source_fact_sequence、source_visit_id或source_stay_id、counterpart_kind/id由已提交来源事实冻结、created_day、consumed、started_tick、source_summary；熟客每人≤3，全院≤600 |
| 当前社区活动 | 每医院至多一个未结束实例；名单、配位、阶段、预留容量的派生、故事关联和收尾凭据遵循社区活动规格§12；故事角色模板到Resident的稳定绑定归原故事进度保存；报名理由及已核验最小来源摘要只随当前活动保留，不成为永久病史或新治愈事实 |
| LifeNeed | visit_id、need_sequence、purpose、next_due_tick、started_tick、actual_queue_ticks(当前连续排队，离开排队即清零)、phase、facility_id、scene_id；每Visit最多一个需求，使用余量归ServiceSession；完成后仅保留最新序号和下次类型/时间，兜底不满按当前序号幂等 |
| PatientAffect | visit_id、anger_milli、cause_clocks、applied_impulse_keys、last_help_tick、high_anger_no_progress_ticks；mood派生，主队列有效等待由QueueTicket拥有，cause_clocks不再复制同一计时 |
| VisitExperience | visit_id、queue_excess_ticks、environment_value_tick_sum、observed_ticks、care_facts、attributed_department_id(无实际治疗为空)、finalized；评价按公式生成 |
| RenovationOrder | id、material_id、unit_targets、paid_material_cost、completed_units、active_unit_work、worker_ids、tool_id、stop_after_active_units、refund_entry_id；首次开工领料，取消退未开工部分，单元不重复领料 |
| SurfaceFinish | owner(room/public)、surface_key(局部格或带朝向墙边；公共表面为CellRef)、material_id、paid_cost、completed_tick；共墙两侧独立，搬房保留成本，实际表面唯一，环境缓存从定义重建 |
| RatingWindow | owner_type、owner_id、last_fact_sequence、bounded_samples、daily_aggregates；总分不另存到实体 |
| GratitudeReceipt | visit_id、kind、definition_id、credited_staff_ids、state、committed_fact_id、可选applied_work_ref(kind、id)；每Visit唯一，工作帮助只记原任务归属，不持有其余量或完成状态 |
| GratitudeState | gift_collection_by_definition、current_day_count、regular_next_eligible_day；重复卡计数不生成无限物件 |
| TemporaryCommunityEffect | id、definition_id、source_visit_id、anchor:CellRef、remaining_ticks；仅三类有时限的区域效果，范围由当前公共区域与墙体派生，不复制覆盖格集合，不强引用已离院Actor。即时工作帮助归GratitudeReceipt |
| LeavePlan | id、staff_id、kind(planned/overfatigue)、requested_day、actual_start_tick、end_tick(自动长休为空)、status；主动假期安全结束后才开始，自动长休须恢复至55才结束 |
| RecreationSession | id、equipment_id、staff_ids、remaining_ticks；次数/冷却在Staff中有界保存 |
| Room | id、floor_id、room_type_id、inner_cells、wall_edges、door_edges、admission_intent、last_focus_specialty_id、focus_ready_tick；实例即原子提交完毕的基础壳体，缺设备仍可存在；建筑存在从当前inner_cells与地块相交派生，不存历史建成标记；开放意愿为事实，实际可预约状态派生；改建归属从安排参与集索引，运营科室归属从CareDepartment房间集索引查询 |
| 改建安排 | id、参与实体ID集、冻结目标布局、来源蓝图ID/修订、创建序号；每实体至多一个安排，就绪与阻碍实时派生；不复制各工作任务进度 |
| 空间蓝图 | schema_version、id、revision、名称/说明/缩略图、依赖、相对布局/材料意图；共享资料库独立原子写，医院内已确认安排保存布局值而不依赖外部文件 |
| PlacedObject | id、definition_id、anchor:CellRef、rotation、room_id、paid_cost、ever_used、borrowed、upgrade_level、仅维护集合实例具有condition_milli、wear_remainder、equipment_state、pending_failure、last_fault_roll_tick、repair_grace_until、maintenance_order_id；库存用location=inventory而非复制一件 |
| QueueTicket | id、visit_id、service_key、ticket_sequence、waited_ticks、priority、suspension_reasons(各来源独立撤销，suspended只读派生)、assigned_station_id、seat_id；waited_ticks是主队列有效候诊时长唯一事实，供怒气/评分/离院查询，院内序列单调递增 |
| ServiceSession | id、visit_id、staff_id、station_id、service_kind、attempt_id(非治疗服务为空)、work_remaining_ticks、phase、非治疗服务的doctor_fee_quote/facility_fee_quote与charge_ids、非治疗医疗服务medical_wear_applied；治疗结果、总量、治疗报价与主体使用去重只由TreatmentAttempt拥有，治疗Session仅引用它 |
| 岗位工作贡献 | 原服务/维修单/施工单元按实际有贡献的在职员工稀疏保存标准工作量，不预分配全员数组、不以旧32人样本截断；另存一份最高离职贡献摘要(非Staff外键)；完成后选最大贡献者，只在其仍在职时归并一次实践，再释放临时贡献；研究按Staff实际工作时间余数累计 |
| StaffTask | id、kind、actor_id、target_ids、work_remaining_ticks、priority、reservation_ids；任务取消统一释放预约 |
| DirtPatch / 清洁累计 | 污渍拥有source_kind、来源实体显示摘要/完成序号、地面CellRef或垃圾桶引用、生成tick（无到期）、冻结清扫总量/余量、贡献和任务引用；StaffTask仅引用污渍工作，不复制余量。日常设备保存用途累计余数和完成游标，搬动不重置；按实际floor_id+plot_index各最多64份活跃污渍，新生成检查当地预算；旧污渍永不因超额删除 |
| Incident | id、definition_id、actor_ids、zone_id、phase、elapsed_ticks、deadline_tick、care_task_id、effects_applied、cleanup_ids、followup_played、resume_handles；日常演出引用required_object_instance_id及其使用锁，沿用演员锁和空间预约，不复制家具状态 |
| Relationship | ordered_identity_refs(各为resident/staff类型与稳定ID，按类型及ID排序)、kind、mediations、last_interaction_tick、positive_days(0…3)、last_positive_day；无反向重复记录，同一天不重复累计友好天数；员工关系按实际合作稀疏记录，不预分配32人矩阵或固定496条容量，随原关系集合流式保存 |
| LandState | 只拥有1F的owned_plot_ids、purchase_sequence、paid_cost_by_plot；起始地块免费且固定，其他地面交易幂等，价序/补助/owned_plots均只取此来源；不复制上层权属 |
| DoorInstance（只读视图） | 从definition_id引用DoorDef的PlacedObject投影，墙边锚点由anchor/rotation查询；不另存购买、耐久、故障或维修状态。收起尺寸从DoorDef查询，实际展开尺寸和墙边占用来自AdaptationReservation；门不持有故障状态 |
| MaintenanceOrder | id、equipment_id、kind(repair/preventive)、staff_id、completed_work_ticks、frozen_class_terms、charged_parts、parts_entry_ids、queued_tick、scene_id、status；余量派生，每设备最多一张有效工单，未完成维护留在原单，不另复制到设备 |
| UpgradeOrder | id、equipment_id、目标等级、逐级冻结规则/材料价/工作量/完成量/贡献、支付与退款凭据、当前阶段、排队tick、status；每设备至多一单，升级等级仅由完成阶段推进，设备paid_cost只计已完成材料；StaffTask不重复拥有升级余量 |
| 研究进度 | 按research_id持有资料凭据/来源摘要、唯一简报到期tick、待办排序与唯一有效任务；任务冻结方式、实际付款、工作总量/余量、解锁快照、桌位偏好与终态凭据；界面兴趣路线不复制进度 |
| 就诊历史 | 活跃Visit的最近32条明细/采样游标及早期阶段时长汇总；最近100张离院小票冻结显示事实、结局、分项和来源凭据；只读投影不驱动病例、评分或账目 |
| TaskInstance | id、definition_id、accepted_fact_sequence、target_snapshot、reward_snapshot、rules_version、progress、last_consumed_fact_sequence(暂停恢复推进至命令边界)、unique_count_keys、status、completed_tick、claimed_ledger_id、period_index；数值冻结为接取版本，计数键仅保留至目标阈值，完成后压缩为凭据 |
| 财务展示 | FinanceNote仅存文字/目标金额；账页与三日展望查询原Ledger及现状，流水成本/实付/资助关联同一费用凭据；不持有预测余额、重复工资或资助批准 |
| TaskBoardState | next_refresh_day、offer_ids、last_offered_period_by_template、active_instance_ids(含暂停，不含待领)、last_completed_day_by_template、abandon_cooldowns、milestone_claims；当前与待领奖励不因刷新丢失 |
| GrowthState | known_diseases、research_unlocks、research_tasks、mail_jobs、story_states、seen_species、seen_scene_ids、cured_diseases、used_machines、claimed_reward_ids |
| EconomyState | cash、daily_accumulators（其中operating_numerator持有未结运营分子及跨日余数）、recent_ledger、aid_total、subsidy_next_day、last_subsidy_period、creative_fund_total、last_daily_settlement_tick、settled_entry_ids；运营整数费用与余数按原日结凭据原子消费，不随日期整体清零；已完结条目按日聚合，唯一会话结算标记保留在病例摘要 |
| HistoryState | entries≤500、pinned≤50、source_fact_cursor、highest_floor_recorded、daily_summaries≤30、earlier_summary；置顶卡可含photo_id，照片元数据与文件在独立本机库，医院快照不复制库索引 |

原日常会话冻结所选scene_id、原绑定的A/B及response_variant_id或空值，工作进度和完成凭据仍由该会话唯一拥有。变体定义与普通/静态姿态归ContentRegistry；社会性格、关系仍各归原居民和关系事实，不复制到展示对象。编译索引按已选基础场景查询其合法回应，不建立全院演员×全部结尾矩阵；低动态、切层、存读档和关系变化不会重选。ComedyState与GrowthState继续只按基础scene_id记录开始、冷却和已见，36种结尾不是36份完成收益或图鉴奖励。

所有集合主键唯一，外键必须存在或有明确已离院摘要。实例ID由医院UUID与单调实体序列生成，内容定义ID使用命名空间，两者不可混用。清理临时居民时先清除Actor、Visit活动引用及预约，再留下必要院史摘要。

设施摆放从受支持的内容定义和原PlacedObject锚点/旋转恢复，基座、局部原点与门墙基准遵循内容规格§10的发布兼容规则。原服务预约继续持有其真实伸展与身体资源；加载验证不能为通过新版几何检查而重定位设施或提前释放这些占用。内容兼容比较不增加逐物件几何副本，也不进入每tick查询。

运行预算：sim_tick、实体序号、金币绝对值均≤10^12，JSON解码后明确转整数并做范围检查；超过预算返回错误而不溢出。随机数发生器state/seed为64位十进制字符串，不能经过JSON浮点数往返。普通访客停留记录也保存major_event_participated，与Visit同样在进入前兆时写入；不写到Resident形成永久禁演。熟客记忆、喜剧预算、社区活动与排班建议遵循[熟客与社区活动规格](10-community-comedy.md)。至少分别保存arrival、treatment、incident、personality、equipment、task_board、registration、communication、gratitude、patience、recruitment、community_activity十二条随机流；视觉粒子使用独立非业务随机，不影响游戏结果。

同一游戏与内容版本下，无窗口与有窗口模拟在同种子、命令序列和步数下业务状态一致。跨引擎版本不承诺位级随机一致；引擎升级需迁移策略或保留旧算法。Godot随机数支持state与seed，但算法兼容不能从种子本身推断。[RandomNumberGenerator](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html)。

diagnostic_work_styles由内容注册表建立主体/医生DP性格复合索引。当前诊断服务拥有服务类型、工作阶段、实际患者与医生、采集余量和证据；视图仅读这一来源，工作段绑定变更时丢弃旧操作端。姿态从原已保存阶段与当前进度恢复，不另存表演开始tick、表演进度或全院候选动作表，不补演跳过阶段。只为可见当前工作绑定查询专用定义，取不到专用定义则按同一名额使用相应medical_progress_cues的通用工作反应，当前FUR02对应MP01；名额不足或次要资源未就绪只保留主操作。不得为表演创建诊断服务、预约或临时Actor。仅替换同一医疗次要插槽，与门诊小戏共用3组名额，不新增并行声源；原主操作和全部后台医疗继续运行。

医患文字卡由当前对象详情唯一持有，绑定医院加载会话、聚焦病例、实际回应来源与视图代次；正文和至少4现实秒的阅读窗仅为可丢弃的UI状态。同一真实回应来源不重复重置阅读窗。当前原医疗任务拥有回应、工时、医护和完成事实，文字不生产沟通、收费、安抚或结果。界面只查询聚焦病例，阅读窗到期后取此刻实际沟通，不保存全院发言列表、待补播队列或第二份病例状态。切焦点、退出或换医院释放旧卡，迟到的旧来源不能贴给同名新角色。近景复用同一份信息，不建立第二个文字槽；医患文字开关与叫号图示、必要原因、当前工作状态相互独立。

## 5. 内容定义的类型约束

SpeciesDef拥有原身体、骨架、家族与外观，StaffTalent通过species_id唯一绑定，StaffRigAdapter按rig覆盖六岗位。ClinicalAbilityDef仅诊断/治疗/手术/护理，ClinicalPracticeSource引用实际工作事实。TreatmentRoutine拥有equipment_id、specialty_id、service_ticks和四段表现；TreatmentBinding引用species_id、disease_id、routine_id、骨架与三种身体表现，并可拥有symptom_envelope；设备从routine派生。MachineDef仅有三类门诊主体的价、占地、适配与状态类别；诊断台、手术台、护理床各有唯一定义，MedicalEquipmentProfile索引六类主体的操作规则，UpgradePresentation提供每主体两级外观。内置检查、麻醉、监护和器械功能不是独立设备实体。

DiseaseDef继续拥有病名、症状、临床档位、治愈费与症状资源；DoorDef拥有收起跨度/净宽高、价与自动适配策略。TaskDef拥有kind、metric、target、filter、eligibility_rule及奖励；能力团队指标的metric_parameters拥有所需能力项数和等级，说明文字不执行规则。ResearchDef独占解锁列表，初始病症由initial_disease_ids声明；疾病不另存unlock_id，界面反向索引由注册表派生。TreatmentProtocol拥有方案参数，TreatmentPlan引用病症、协议、额外研究与独特演出；SurgicalAdapter引用binding_id、plan_id、patient_pose、target_description与required_anchors，种族和病症由绑定派生。DoctorTitleDef拥有职称顺序和晋级条件，DoctorPayDef拥有同title_id的工资、招聘费和评估费；BillingPolicy独占各职称初诊诊费及各equipment_id/service_kind的设施单价和收费节点，DoctorPersonalityDef拥有六种评分权重。ClinicalEquipmentDef和ClinicalRoomTypeDef保留临床主体价、尺寸、研究及房间需求；模式资格额外读取DiagnosticMode，不用诊断台通用资格放行护士初诊。

表现层的姿态权威是原模拟阶段与FacilityReservation登记的包络：treatment_presentation.pose_authority声明这一来源，result_writes_from_animation固定为false。动画回调不结算治愈、诊断、耗材、费用、清洁或睡眠；这些效果先由各业务拥有者提交，再驱动表现。纯次要小戏缺失时按missing_secondary省略它并保留主流程，主姿态缺资源时沿现有代理模型规则标明，保持原身体占位与阶段，不凭空替换骨架或改变速度。

设计目录JSON中的中文name/symptom/机器beats由内容导入工具一次规范化为本地化键和演出资源清单；构建产物禁止同时修改导入前后两套数值。临床档位为内容配置profile，不允许在分散代码中重复费率与时长。UI不硬编码T01…T10为十个按钮，而从部门定义构建目录。

身体能力标签和偏好必须在包的tag字典中声明。普通标签只能用于筛选；带模拟意义的标签必须绑定已注册能力handler。数值参数拒绝NaN、无穷、负时长、超过地图尺寸的占地。文本只用于显示，不参与ID查找。

### 表现资源的共享与切层

内容定义和已验证资源清单可以常驻，模型、纹理、动画片段与只读材质按内容指纹和资源ID共享引用。患者与职员实例只保存自身姿态、插槽绑定和外观参数；染色、徽章或一套症状不复制整份纹理/骨架资源，改变一个人的材质参数不能改变同种族的其他人。已完成机器等级按同一主体附加配件，不载入84台重复主体。

FloorView只为当前观察层视锥相交的显示块和玩家明确打开的预览建立显示实例。预取只准备有界块数据与共享资源，不在预取圈建立显示实例。其他楼层继续保存和运行原模拟事实，不保留整层动画树、音源和粒子节点。切层先释放旧视图绑定，尚被新视图使用的共享资源继续持有；未被使用资源可进入按真实字节计账的LRU缓存，缓存、当前资产与加载临时副本全部计入原工作集/显存目标，不另给缓存一份隐藏预算。回收缓存不删除定义或世界实体，重建只读姿态即可再次观看。空楼层不预建模型节点。

资源读取按当前可见主体、症状/安全状态、当前实际需要的配件排序，再考虑次要小戏和未使用资源的预取。场景实例化与绑定遵循现有主线程规则，分帧完成显示工作；加载速度、缓存命中和实例化批次不推进业务、阻止已合法临床任务或消费模拟随机数。尚未就绪时用清楚标记的原尺寸轮廓和当前状态说明保留选择/定位，不能把患者画成已离院或已缩回。纯表现资源真的缺失仍遵循内容包代理规则，正式发行资产门槛不因此降低。

每次显示请求绑定医院加载会话、view_id、实体ID与该实体的视图绑定代次；代次仅在该显示绑定或所需资源身份改变时递增，不跟着每个模拟tick变化。迟到结果只可绑定仍匹配的目标，否则释放临时引用或留作合法缓存，不能贴到新医院、已离院演员或复用节点上。资源就绪后读取当前真实工作阶段与预约包络，直接建立此刻姿态，不重播已经错过的高潮、完成音效或回馈。显示句柄、缓存和未完成读取不进快照。 动态实体绑定还须核验其当前楼层与显示包络仍属于目标视图范围；块索引仅给出候选ID，即使实体锚点块不在视锥内，也按该实体自身句柄建立唯一实例。

FUR24普通窗面读取其原互动/活动已绑定且仍在现场的微观居民；没有会话时只展示同层同一可连通公共空间内、到窗演出侧合法路径不超过3格的真实微观居民，按距离和ID稳定选取，不派人过来。此选择是只读观察，可复用原邻域与空间查询；不能占演出锁、清票号或产生设施使用事实。放大近景全视图至多一份，显示同一实际名单和当前阶段；原活动所需的每人泊位及随机人数不因此减少。空窗不造演员，S24的多名外形成员仍是同一Actor。切窗、切层、关闭、对象被收纳或切医院时解除近景绑定并回收不用的显示资源，迟到结果遵循同一代次校验。近景不另起声音源，复用原现场非语言音效与状态图示；光点、收尾和静音的变化不回写业务。

门诊方案表现从本次Attempt引用的方案、协议及本档内容版本解析presentation_mode，新的PlanDecision仅影响后续治疗。病例身体/主目标仍由原绑定与预约包络约束；standard使用原专业次要动作，gentle按protocol_variants当前四段替代同一槽。四段边界直接由唯一冻结总工作量累计向上取整，表现不拥有四个独立服务时钟。模式、姿态缓存与状态文字不写PatientAffect、护士任务、耗材或结果；加载只重建当前姿态，不重领包或重演已过前奏。暂停与结果优先沿已有held_scene和临床结果投影，阶段高潮定格次要道具，共享3台可见动态预算保持。

### 当前层的视野切块与远景

spatial_view拥有显示块、镜头细节与分帧绑定合同，不拥有医院实体。当前基础地图96×96格按16×16划为最多36个楼板显示块；实际只请求当前视锥相交区域及一圈低优先级预取。1F真实自然地面取LandState，上层须地面已购且completed_top_floor覆盖本层；静态墙地只读本层真实Room与布局差异。在建订单只有信息轮廓和实际施工表现，预览不提供可走面、出舱点、楼板碰撞或虚构阴影承托面。明确预览使用自己的身份和同一资源预算，不为10000个空层生成块、修订数组或场景树。

可见性按当前完整显示包络与视锥相交判定，包括真实身体、仍生效的症状和实际伸展部件，不只看锚点或格子中心。跨块家具、长颈鹿或医疗主体可被多个块索引引用，同一逻辑实体在一个视图只绑定一个实例。静态墙地可拆成不重叠的绘制片段，片段仍回指原对象；不能将其算成多件家具、重复维护或新预约。动态显示包络伸到楼板边缘之外仍可被查询，不为这些纯显示范围制造可建格子。

静态块只因相关几何或材料真实提交而失效，取变化前后范围并集；人员走动、医疗进度、表情和交接更新自己的当前姿态，不重新烘焙整块墙地。远处地块继续向上施工时，只有对当前查询层的有效覆盖真的改变才重建，不能因completed_top_floor数值变化就清空所有已观察层。局部显示修订按实际请求保存于派生缓存，随字节预算回收，不成为另一套世界事实或存档字段。

细节读取camera_view.native_projected_cell_metric：由实际相机投影把地格的X/Z两条边映到原生输出，取两条长度中较短者作为每格像素，不用低比例三维纹理自身像素或格子包围框宽度。每格达到24像素进入细节层，下降到20像素退出；中间区间保留本视图此前层级，首次绑定使用24像素门槛。远景共用简化几何与材质，仍保留实际物件位置、身体尺寸和必要医疗/安全状态；当前选中且可见的对象保留完整表现。选中院外或其他层对象不会因此常驻整层模型。低动态与必要状态继续按原设置，镜头缩远不生成对白或改写临床结局。

鼠标选择、拖动、试摆和建造合法性始终查询逻辑空间索引及真实实体包络，不能拿远景合并网格或尚未就绪的显示碰撞体作事实。主要轮廓、当前必要状态与选择反馈优先，次要小戏沿原3组预算。加载中的代理只描绘当前真实对象与尺寸；过时墙段或已离院演员立即退出本视图选择，不拿旧模型继续接受操作。

主线程的实例化、绑定、几何上传和退场共用每帧2ms的新增显示工作目标，每帧最多启动2个块任务。一个块内部按对象或小网格片段继续分帧，不能把整块或巨型旧楼层当成不可分割的免费操作；单步越界须记录真实耗时。切层先解绑旧视图和选择范围，销毁与资源释放也计账、分帧进行；尚未释放资源仍占原工作集和图形预算。优先完成可见/选中对象，再预取；镜头离开后的纯预取直接丢弃，不排成跨层历史待办。

显示请求包含hospital_session、view_id、view_generation、floor_id、chunk、local_visual_revision、content_fingerprint与lod。代次只随对应绑定或需求身份变化，不能每模拟tick递增。返回时逐项核对当前请求，迟到旧块不绑定到新楼层、另一个预览、另一医院、旧布局或错误细节层；只读基础资产仍可在合法字节预算内共享缓存。绑定动态对象时再取当前真实姿态，不补演加载期间已经结束的工作。

块大小、细节层、显示队列和缓存冷热均不参与寻路、碰撞、实际照护、收入、工资、怒气、关系或随机机会。所有已有实体继续完整模拟；显示块及显示名额不是医院的面积、楼层、家具、患者或接诊上限。

### 大面积当前层的概览镜头

camera_view拥有观察层的正交镜头规则；默认yaw45°、俯角35.264°，旋转仍为90°四方向，最小纵向尺寸18米、默认42米。纵向尺寸使用KEEP_HEIGHT，与[Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)的正交size/纵向锁定定义对应。缩远边界为max(90米,当前层概览所需size)，当前层已完成面积增加或窗口变窄不会被固定90米阻止。镜头与渲染设置属于本地视图，不写世界状态或临床位置。

“全层概览”先从地块高度取得本层合法楼板角点，再从当前层逻辑空间记录取得真实当前显示包络的角点，包括仍生效症状、伸展部件和高身体；按实际相机right/up基投影为二维米范围。分别投影各包络再取并集，不只投影地面或某个角色锚点，也不先把整个医院包进包含其他层高度的巨盒。此只读查询不实例化模型、演员、视图块或其他楼层场景。第10000层与第1层使用同一本层重定位高度原点，不以楼层号乘层高求概览。

安全矩形使用原生场景输出中真正未被当前固定界面遮挡的矩形，扣除顶/底栏、当前目录和侧栏；其中心为概览对齐目标。令投影宽高为Pw/Ph，原生输出宽高为Ow/Oh、安全宽高为Sw/Sh，实际三维视口宽高比为Ar。采用纵向锁定时，概览size=max(18,1.1×max(Pw×Ow/(Ar×Sw),Ph×Oh/Sh))米；1.1给总宽高10%余量。Pw/Ph中心通过同一相机矩阵平移到安全矩形中心，不能只把楼板中点放到被侧栏遮住的整窗中心。实际Ar取已分配的三维视口，包含75%/约67%偶数尺寸取整；原生与低比例坐标通过同一显示变换转换，不能用整窗比例代替实际投影。

九地块96×96格的空楼板宽深各144米；默认方向投影约203.647×117.574米。16:9纯画面矩形下至少需要约117.574米纵向尺寸才能不裁边，按10%余量概览约129.332米，未计实际高物件与固定UI。高物件位于外缘或侧栏压缩安全区域时，按实际包络/矩形进一步增加；该算例解释几何，不作为帧率或拾取实测。18米最小值与42米常用视角继续保留，概览尺度不是建造面积或居民体型限制。

Home或明确“全层”按钮只改变当前镜头并退出跟随，保留选中对象、草案、暂停/速度和真实服务。普通走动、日夜、工作推进或打开对象卡不自动反复全层适配；界面布局/窗口变化更新下一次主动概览/缩放的范围，原手动构图可以保留。缓存的当前size暂时大于新边界时也不每帧回夹；下一次主动缩放按当前边界处理。原每层镜头偏好32项LRU继续是本地偏好容量，不常驻整层表现或限制医院层数。

没有合法楼板的层返回明确施工/定位状态，不拿未来楼板建立医院；安全矩形宽高为0、窗口最小化或投影无有效范围时保留当前镜头，恢复后只处理仍匹配当前医院/层/操作的请求，不除零或取无限size。鼠标选择与建造沿当前真实投影转换及原逻辑空间查询，不从概览模型/远景包围框推断占地。全层概览可能请求本层更多显示块，仍遵循原每帧2ms/2块启动、共享资源与完整模拟目标，不为迅速看到全层排除冷绑定和普通长帧。

### 可见部件合批与实例身份

visual_batching只合并当前视图真实可见的兼容部件，不合并业务实体。完整显示包络/视野查询先产生候选ID并去重，再从当前原表现绑定取得部件。组键由内容指纹、真实网格资源、完整Surface材质布局、LOD、渲染状态和已验证准备姿态资源组成；同种族、同家族或相同颜色都不能代替资源相容性。每个部件仍以原逻辑实体ID与注册part_role唯一标识，一个实体在本视图仍只有一份逻辑表现句柄。

render_state覆盖透明/裁切/投影等实际管线与适用光照配置，完整材质布局保留Surface次序。局部光照或材质接口无法在同批正确表达时，分为真实相容组或沿原管线，不能仅凭主材质相同把照明不同的部件强合。光照表现沿原一盏方向光/最多8盏可见装饰光与真实环境规则，分组不创建新光源、提高环境分或改变昼夜。

兼容opaque/cutout且只有刚体变换的家具、建筑片段、机器部件可共用实例绘制；已经验证与原身体/症状及当前阶段一致的无骨骼远景姿态也可使用。近景骨骼默认沿原每实体姿态管线，只有满足skin_pose_instancing的正式适配与后端验收后才可用专用独立骨矩阵路径；顶点形态变形及alpha_blend沿原当前管线/逐对象深度排序。资产没有兼容准备姿态或材质不支持实例参数时，保留原当前主表现。不能为合批把患者变成通用球、冻结主要医疗动作或提前画成治愈，也不以缺少合批能力拒绝合法扩展种族/病症。最终能力须在Compatibility与正式资产上验证，不能从相同资源ID推断骨骼可以共同播放。

[MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)按整批可见性绘制，缺少逐实例视锥剔除。因此本项目显式维护当前可见成员，只将本视图需要的部件写入连续可见前缀；引擎批包围盒只作整批粗剔除，不替代原逻辑空间与逐实体包络。没有为预取圈、其他层或全部医院预分配活跃演员槽。新增/移出成员时压实当前名单，同一部件不能同时在旧批与新批/原管线绘制；选择转近景、LOD或绑定变化先解除旧绘制身份再建立当前表现，必要原尺寸轮廓沿原规则保留。

批槽绑定hospital_session、view_id、batch_key、batch_generation、slot_index、logical_entity_id、part_role与slot_generation。压实、复用或迁移槽位时更新映射/代次，迟到变换、颜色、姿态或资产结果必须逐项匹配当前绑定；槽号不是实体身份、预约ID或保存引用。原角色已离院、物件被移动到别层、所选对象进入原管线后，旧结果不得附给恰好占同一槽的新对象。同一实体移到另一槽时，即使两槽代次数值相等也因slot_index不同拒绝旧绑定。鼠标选择、试摆和建造继续读逻辑空间索引及真实包络，不用批包围盒当家具或碰撞体。

变换、染色和允许的表现参数来自当前原主体/阶段，按实例更新；共享网格和材质仍只读，改变一把薄荷椅或一位医生不能改变同批其他人。正常位移只更新现有参数，不销毁重造整个资源。相容性、可见性或姿态绑定变化才调整组成员；连续参数更新合并当前值，绑定/上传前在身份核验后重新读取当前原姿态，不能让请求发起时的旧位置覆盖较新的同槽人物。返回视野直接显示当前阶段，不重播错过的工作/高潮/结果音效，不消费业务随机或提交临床事实。

组创建、名单压实、映射调整、参数写入/上传、绑定和回收计入原每帧2ms新增显示工作；单批也可按小段处理，不把巨型批上传当免费原子操作。缓冲实际分配容量、当前/空闲/暂存副本、上传临时数据及尚未回收旧批都计原工作集和512MiB图形目标，不能只按visible_instance_count计字节；集显共享分配沿原规则标注，同一实际分配不重复相加，也不遗漏容量。容量按实际需要与真实资源准入增长，不设固定批数或医院实体上限；缓存释放不删除世界。批成员/映射/槽位/待更新记录不进快照。

400绘制调用与1.5M可见三角仍为原画面目标，核验使用真实引擎统计及必要主/阴影等通道的成本记录。批数、逻辑人数、模型数及纸面“合为一组”不能当实际调用数，多Surface、独立透明与回退都须计账。超目标时继续保留所有当前主体、症状与安全状态，记录相容性/材质/姿态/提交瓶颈并优化，不能截取前400人或隐藏失败分组。96×96同层160/640人与宽高联合样例增加合批开/关、冷暖/回收、选中切管线和槽位复用的同业务重放；静态分组算例不证明本机帧率。

### 密集近景的独立骨矩阵实例绘制

skin_pose_instancing为密集可见骨骼提供专用绘制路线，启用条件是实际Compatibility/本机后端与该正式资产适配都已验证；当前capability_validation_available和runtime_measurement_available均为false。验收依据绑定实际引擎版本、渲染器、设备/驱动、内容/skin适配、shader指纹、页格式及实例参数布局，任一改变便沿原管线直到对应依据重新成立。内容包的一个verified标记不能替代引擎/资产验收证据。普通MultiMesh不能自动共享不同居民的骨架状态，30/15Hz采样也不自动减少绘制提交。未验证、未知或不支持的资产沿原当前逐实体骨骼表现，合法种族/病症仍可使用；不能用纸面合批声称原400调用或60fps已经通过。

专用路线复用pose_sampling对同一原身体/阶段的唯一评估结果，取得模型局部skin矩阵（原当前骨全局变换乘原inverse_bind），不再次运行AnimationMixer或建立动画进度。准备网格保留原rest顶点、合法骨索引/权重、UV和完整Surface材质布局，不附带另一份自动Skeleton变形；shader只在模型空间变形一次，再使用原实例世界变换。首个适配范围为已验证opaque/cutout、最多40骨/每顶点4权重、刚性骨变换；非均匀骨缩放、形态变形、更多权重、透明排序或未知属性继续原管线。40/4是该绘制适配容量，不拒绝需要原管线的合法扩展身体。

骨矩阵页使用[Image.FORMAT_RGBAF](https://docs.godotengine.org/en/stable/classes/class_image.html)的四通道32位浮点数据；每骨连续3个RGBA texel存行优先3×4仿射矩阵。宽为不小于3×实际骨数的最小2次幂，每行属于当前唯一实体部件；每页实际成员最多64，页高取容纳当前成员的最小2次幂。禁止sRGB/颜色转换、有损压缩、mip及线性过滤，采样读取本骨本行，未使用列/行不能引用旧人的矩阵。更多可见成员分更多页，64不是医院人数或每帧处理人数上限。

[MultiMesh自定义数据](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)在Compatibility以16位存储，因此INSTANCE_CUSTOM.x只承载0…63的局部行号，必须在实际导入/上传/shader中逐值往返验证，不把ActorID、tick、页代次或高楼层号塞进这个通道。原染色/症状参数与行号通道由已验证适配声明各自位置，不相互覆盖。页资源按实际组绑定，不用半精度编码全局页身份。[空间shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)提供骨索引/权重和实例自定义输入，但这些接口存在不构成本机独立变形能力证明。

组键沿原真实网格/完整材质布局/LOD/渲染状态，另含skin适配（含inverse_bind）、已验证shader与矩阵页。相同网格但绑定空间、法线处理或材料接口不同不能混组，同种族也不共享业务阶段。每个当前可见部件沿原唯一身份/密集前缀，行拥有医院会话、视图/代次、实际楼层、页/代次、行索引/代次、实体/部件、skin适配、原姿态来源及采样代次、内容指纹。多个Surface可读相同已绑定行，其他部件只有真实同源相容才复用原评估结果，额外GPU页副本仍计字节。正常位移继续原每帧合法根变换，不修改真实碰撞或治疗占位。

页面使用完整暂存页与当前页；发布前核验当前绑定并合并最新原采样结果，整份页与行映射就绪才切换。行复用、离院、换体形/阶段、切层或选择切管线先撤旧绘制，迟到旧行/页拒绝；暂存不完整或原来源已变时保留原当前骨骼表现/真实尺寸轮廓，不能读另一人的行、同时画两份身体或用旧膨胀/治愈状态补位。主画面和必要阴影等通道使用同一当前矩阵，原灯光/透明/轮廓规则保持。变形后可见包络与选择仍读原真实逻辑空间，不使用rest网格小AABB剔除伸出的脖子、症状或治疗姿态。

[ImageTexture.update](https://docs.godotengine.org/en/stable/classes/class_imagetexture.html)更新同尺寸/格式/配置的整张纹理；没有经过实际API验证的行级上传就按实际整个分配页计传输，不把改一行报成只传一行。页生成/绑定/上传/回收计原2ms新增显示工作及完整帧成本，原骨求值继续计全帧；当前/暂存/尚未回收旧页、CPU原姿态和上传临时值计原工作集/512MiB图形目标，同一集显分配沿原规则不重复相加。40骨×640成员同一相容组示意为10页128×64，页总原始1310720字节、双份2621440字节；假设全部页每呈现帧更新且60Hz，原始传输78643200字节/现实秒，未含驱动/同步/副本。不能按每人30Hz或dirty行数把全页带宽减半，这些只为算例，未测CPU/GPU与帧率。

正式适配验证覆盖原九骨架、四向、实际症状/承托/操作、近远与低动态、暂停/恢复、独立不同进度/性格、行压实/复用及全部必要渲染通道。与原近景管线逐顶点/法线/切线及实际包络对照：位置误差≤0.005米，法线/切线方向误差≤1°，插槽仍满足原0.05米门槛；没有可证明的测量就保持未验证并走原管线，不用截图相似替代数值/状态/裁切验收。记录真实Surface/页调用、实际顶点/上传/求值成本及原本机尾部帧。密集近景增加合法真实可见640成员的独立姿态样例，并与原大平层/宽高联合世界同命令重放；不能通过隐藏第65人、缩小身体、同步所有动作或减少医疗保性能。矩阵页、行索引和采样/绘制缓存不进世界快照，不决定结果、收入、怒气或随机。

### 可见角色的姿态采样

pose_sampling只管理当前可见角色骨架/已验证姿态绑定及明确预览的表现采样；原模拟阶段、工作进度和预约包络仍是姿态事实。近处30Hz、远处15Hz按本次医院视图会话的单调现实时间计算，细节档沿spatial_view的原24入20出及选中可见对象规则。3×推进原业务进度，不把骨架频率乘成90/45Hz；暂停也不靠现实采样推进工作。根位置与镜头继续每渲染帧使用原合法移动插值，骨架采样不是位置、安全离位、碰撞或跨层通行的时钟。

同一绑定只有采样器一个骨架评估入口，不能让AnimationPlayer/AnimationTree默认逐帧推进再叠加到期采样。[AnimationMixer](https://docs.godotengine.org/en/stable/classes/class_animationmixer.html)的manual处理模式用于关闭自动推进；实际采样映射原当前阶段/进度，不把累计advance或animation_finished当成第二份工作/结果时钟。正式动画不得通过方法/声音轨道补发业务、高潮或错过的音效，必要声音继续原已发生事实与并发规则。

连续姿态只为当前可见绑定维护稀疏到期项，不为全部医院或10000空层排动画任务。每个实体的相位由hospital_session与logical_entity_id的UTF-8字节确定：每字段先写8字节无符号大端字节长度，再写字段字节，拼接后取SHA256前8字节为无符号大端整数，对1024取模。此散列只属于显示身份，不抽取任何业务随机。相位箱是错开连续采样的时间位置，不是角色容量；散列碰撞可以同时到期，不保证640人每帧平均分配，也不丢弃后面的角色。

令p=相位箱/1024、频率f为30或15、t为会话现实秒，到期点为(k+p)/f，k为非负整数。正常采样后下一到期取(floor(t×f−p)+1+p)/f，严格晚于t，使用整数单调时间及有理数换算避免累加截断漂移。首次可见/改变正式绑定先取当前原姿态，再加入当前频率的相位格；近远切换只更改显示采样，旧频率到期项失效。帧晚了多个周期也只读当前一次，并跳到下一相位格，不连做数次旧骨骼评估、排高潮/音效补播或把错过采样转换成临床工作。

阶段切换、实际身体/有效症状、故障、冻结、占用姿态或原资源绑定等离散变化在绘制前使旧姿态失效，并读当前原来源，不等待普通15Hz周期继续画旧身体。同一渲染帧的连续到期与多个离散源变化合为每个当前绑定一次最新原姿态评估；业务固定步与所有完成事实照常提交，只合并显示需求，不按中间事件逐次算旧骨架。资产/正规姿态未就绪时沿原真实包络轮廓与必要当前状态规则，不能提前治愈、保持已经解除的冰冻或用任意通用身体冒充正式适配。治疗结束到离位、转床和上下车仍各由业务安全边界拥有，动画不提前释放物理位置。迟到评估/上传沿原会话/视图/实体/绑定代次检查，核验后再取当前原姿态，旧阶段不能覆盖较新的同一个人。

暂停且原姿态无变化、低动态的已授权静态姿态或明确静态的角色不反复骨架评估；相关原姿态/已注册镜头输入改变才更新。正常连续工作/行走即使两帧之间没有新WorldState修订，仍按原合法展示插值与连续姿态需要采样，不能把“世界tick未变”误判为静止。恢复、重新进视野或切回楼层直接取当前姿态，不恢复另一份表演进度，也不补演屏外已经结束的动作。

相同实体在主视图与微观近景只有hospital_session、logical_entity_id、骨架资源、原姿态来源/绑定、模式和已注册镜头输入全部相容时才可复用同一次评估结果；原来源键包含当前原阶段/姿态依据，camera_pose_key只有明确与镜头无关时才为空。近景需要30Hz时按最高当前需要提供，远景不强迫近景降为15Hz。摄像机相关看向、不同身体资源/模式分别计算，不凭相同种族或同一动画名共享不同人的相位/状态。复用的是只读结果，不创建第二Actor、患者、临床服务或微观成员。准备姿态与无骨骼远景仍须满足visual_batching的原正式资产验证，不声称一个骨架结果可自动实例化独立骨骼动画。

连续骨架求值、变换上传、插值与真实渲染全部计入原普通帧目标；新建/切换/回收绑定继续共用每帧2ms新增显示工作。没有以30/15Hz设每帧演员截断数，也不以频率算术声称帧率通过。640个连续近处绑定理论每现实秒19200次采样、全远处9600次，均未计必要离散刷新、镜头相关输入、首次绑定或真实资产成本；相位可能碰撞和帧错过，正式测量实际次数/耗时/延迟及原尾部帧。到期项、相位、评估结果与插值缓存不进世界快照，显示采样不改收入、怒气、关系、随机或真实医院增长。

### 透明覆盖与叠加成本

transparency_view拥有原20%透明覆盖目标的计量口径。每个实际三维视图分别以其真实渲染宽高作分母，不用整窗原生UI、安全矩形或其他层面积稀释。主画面与明确微观近景等预览分别记录；全部视图的提交、耗时与分配仍进入原普通帧/图形资源总目标，预览不是免费画面。透明分类来自已导入材质的实际管线，不能因为名字叫玻璃/幽灵就猜测成本。

覆盖率取本视图进入实际透明片元处理的像素并集/本视图像素数，目标仍为2000bp。另记录进入片元处理的采样总次数/(宽×高×该视图实际每像素采样数)，表示叠加负载；同一位置多次绘制逐次计数，不把比例夹到100%。混合、加色、减色、乘色、预乘、折射、粒子与软影只要走实际透明管线就计入；最后alpha为0或被材质丢弃不抹掉已经发生的片元入口工作。opaque/cutout的真实提交/着色成本仍在原帧统计中，不因未归透明而视作免费。诊断入口数据的采样阶段与多重采样方式须记录，不能把合成后非零颜色、最终截图或模型包围矩形当成准确的管线计数。

例如100像素的静态示意中，10像素区域叠12层：并集10%，叠加负载120%。并集低于20%仍不证明GPU流畅；没有给叠加负载另造患者/层数上限，它是定位成本的证据，是否达标继续由原本机帧目标判定。大面积医院的透明罩、幽灵、设备光图与粒子相互重叠，以及低画质软影贴片，必须检查实际密集段，不只数24个发射器或看整层空楼板。

准确入口/覆盖捕获须在实际Compatibility、材质、采样与当前视图上验证工具能力。无法得到准确数据时标为未测/不可用，包围框或投影面积只能另列估计，不能填0或宣称20%目标通过。诊断捕获与正式计时分开，绑定同一世界版本、原当前姿态、镜头、渲染比例、UI布局与画质；正常游戏不持续生成逐像素叠加地图。诊断本身的额外通道、读取与资源单独记录，正式帧样本关闭诊断地图；普通经营、冷绑定、切层及原自动保存的卡顿仍进入原规定样本。

正式资产优先以不透明轮廓、实体框架或已验证cutout表达可等价的原身体/当前状态，只有材质与剪影验收通过才可采用。[BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)区分不透明、alpha混合和裁切等模式，不能从裁切较便宜推断透明角色可以无条件替换。幽灵等必要透明主体沿原当前排序与已验证材料；不支持低成本方案时保留原主表现并记录成本。只按原LOD/粒子优先级简化已有可选次要细节，种子轨迹、冰壳/医生眨眼/护士热风、症状、故障、伸展边界和叫号状态继续可辨，不隐藏主体、提前治愈或改写环境效果。

画质/三维比例仍由玩家明确设置，不因某帧成本突然把透明身体变成实心或消失。材料切换、当前参数与旧绑定释放沿原visual_batching/表现资源身份合同，共用原显示工作与内存目标；不会产生治疗、临时Actor、声音/对白或每居民测量任务。诊断记录和透明显示缓存不进世界快照，显示策略不改变原模拟与随机流。

### 声源池与解码资源

audio_resources只具体化audio_presentation原设施6、角色非语言反应6、UI2和音乐2的并发与资源合同，预算仍来自原字段。计量实际同时播放/解码的音流，包括复合子流、淡出和尚未停止的旧播放，不用播放器Node数、设备数或共享资源数代替。场景池槽最多一个实际音流；同设备当前阶段的多个音层在产线预混为一个片段，不给内部零件、循环与高潮偷偷各开一条。角色反应槽不被用来隐藏设备子流，声音类别与原实际来源一致。

[AudioStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html)支持复音，[AudioStreamSynchronized](https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html)可同步播放子流；因此一个节点/资源不意味着只有一份播放成本。本项目原有界池显式约束场景槽的max_polyphony=1，并禁止未计入预算的并行复合子流。真实设备仍可全部工作，落选的次要音效沿原优先/距离规则省略，不给机器或患者设置接诊上限。

淡出中的旧流仍占原类别预算，实际播放停止才释放播放名额；发出stop请求但后端仍在播放/解码时仍计原名额，已停而尚未释放的缓冲继续计字节。音乐原15秒交叉淡入淡出的两条轨道已经计入2路，没有第三条隐藏过渡流。场景满额时不能额外开启“暂时不算”的新流，不等播完再让临床完成，也不靠骤然增大音量补偿。槽复用先停止旧实际播放、撤旧绑定，再绑定当前来源；停止和退出也主动清理，不能等待finished信号才释放，因为显式stop不保证发出该信号。旧完成/资源回调只能作用于原绑定，不得停止或播放复用槽里的另一个对象。

场景槽绑定医院加载会话、view_id/代次、当前楼层、原池类别、槽索引/代次、真实源实体、原工作/反应来源键、音片段资源和内容指纹。来源键包含原已发生事实/当前阶段，正常播放游标不是业务进度；同槽新阶段、角色离院、切层/切医院或换片段均撤旧绑定。迟到短音省略，不排重播；仍需要的循环在匹配绑定后重新读取当前原阶段才接续，不能依据加载发起时的旧治疗或故障。微观近景复用原现场声音，没有第二音池或重复播放同一居民。

对应现场类别音量为零时停止其实际解码与新播放投放，清除纯显示短音待办；只把音量调零而持续全部播放不能称为静音性能完成。其他类别继续各自原设置；重新打开现场声音只接原当前合法循环，不重播错过的启动/高潮/治愈/反应，不保留一份全院暂停的播放树。全局暂停沿原现场工作声静下规则，UI与音乐按设置继续。stop、音频游标、静音、绑定选择与解码失败均不结束医疗、不增加诊断证据、不释放预约、不改变真实经营噪声/怒气或业务随机。

编码片段按内容指纹和资源ID共享只读；实际播放游标、音量/位置参数和解码缓冲属于各池槽，不能改共享音频资源来影响另一个人。共享压缩片段不意味着六份播放共享一份解码缓冲，真实编码/解码/缓冲、空闲缓存、读取临时值及未释放旧播放全部计原医院工作集；PCM不计GPU图形512MiB而重复相加，没有额外每层音频预算。池与资源准入按实际原名额/字节管理，不为640角色、1200物件或10000层创建播放器/解码器。

格式、采样率、声道、编码文件字节、运行时缓冲/解码CPU和切换峰值由正式导入与播放测量记录，不能只用Ogg文件小证明低成本。静态PCM16示意：44.1kHz单声道1秒为88200字节，48kHz双声道6秒为1152000字节；这不是Ogg实际驻留或引擎分配。原密集同层/宽高样例测所有音量开/现场静音/恢复、6路满额/退场、快速切层、唯一微观预览和原1×/3×，记录实际子流、池占用、解码/内存与普通帧尾部。声音池/游标/缓存不进世界快照，当前没有实机音频性能或听感验收。

## 6. 路线与规模控制

[完整游戏的导航与空间选型](16-navigation-space-selection.md)确定职责：AStar2D用于层内四邻显式图，跨层采用读取原TransitService报价的FIFO时间依赖最早到达搜索，Movement与原预约执行实际许可。导航网格、Agent避让、物理形状查询和额外搜索结构经过完整玩法适配比较后，不作为业务通行权威；通用搜索复用引擎，项目保留真实空间和时间规则。正式规则及性能仍须按实施阶段验收，选型不构成已实现或实测通过证明。

AStar2D的确定性不能只靠冷建时排序。每次局部修补均将受影响源节点的全部合法出边按目标ID规范化；删点同时处理全部入边源节点。相同世界在冷建、局部修补、驱逐重建和恢复后必须返回相同完整/部分路径。查询级预约例外不修改共享图，搜索回调只读一致的已验证投影，不复制世界或逐边扫描全院。原生邻接顺序的小图专项结果与完整规则、性能的未验证范围见选型文档。

跨层逐段传递同一quoted_tick下的预计到站时刻A；有限电梯报价沿原max(A,P)+E+G推进，不能将真实队列等待当成与到站时刻无关的固定边权。原生AStar2D成本回调不暴露累计到站时刻，因此跨层报价搜索独立实现，层内行走段仍复用同一合法图及其真实步行时长。搜索保持先到可等候的FIFO条件，未知报价不填0、不伪装几何无路；原连接和票序仍由TransitService拥有。

试摆是Readiness与适配几何在未提交草案上的只读投影，输入身体/姿态、实际或明确标注的示例团队、草案修订与世界修订。结果不创建Actor、AdaptationReservation或第二套可开诊状态；提交和实际接单仍使用当前规则重新查询。一次只计算所选组合与其路线，关闭后丢弃投影，示例不进入快照。

TraversalEnvelope由种族原身体和关联Visit的种族/病症身份派生；内容合并校验先证明该pair所有routine绑定的有效E一致，症状包络仍由原绑定定义持有。查询不以当前选中routine、计划列表顺序或最近Attempt挑选另一副身体。Visit的真实治愈结局决定使用未治愈E或原身体，不另存一份可修改的角色宽高或症状计时器。转诊、失败、离院中仍保留未治愈症状。治愈缩回在安全完成边界更新空间修订和后续路线；已经占用的设备按原离位规则释放。保存恢复先按同一已验证内容中的病例和结局重建包络，再恢复移动与设备预约，不能先用健康尺寸行走一帧；当前身体变小而旧大预约仍等实际离位是合法状态。

Movement拥有当前行进/退让意图、受阻开始tick、让行对象与实际路径；临时会车不改变Visit票号、Attempt或临床承诺。空间可达性、动态适配占用和行人短时争用分别返回原因，不能用关闭碰撞恢复通行。活跃退让意图随角色保存，读档先恢复真实位置与设施占地，再按同一优先序继续；意图失效时从当前位置重寻路，不移动角色来修复。已承诺的陪同转床始终作为一组。

按(floor_id, TraversalEnvelope签名)懒加载层内AStar2D图，签名保留真实格宽和宽高；图及相关派生数据共用128MiB目标做LRU回收，不再用全院16份图限制活跃楼层；实际大小按分配统计，同等最近使用按键排序。单份临时图超过缓存目标时可在本次计算后释放，仍须满足实际内存准入；缓存不是通路存在与否的事实。层内节点ID=y×96+x，跨层用CellRef。k格移动检查k×(k+1)或(k+1)×k扫掠区。门边查询先求实际伸展尺寸、连续墙段及两侧可用空间；既有适配预留与展开占地进入动态阻挡并递增本层occupancy_revision。查询结果持有相关修订号，真正移动/过门/开工前再原子检查，不在旧缓存上穿过伸出的床尾。物件几何、体积/高度和可达性使用同一适配查询，动画不能自行扩大碰撞体。

建筑、门、土地及对查询层生效的楼板几何提交，以及清扫、活动、冲突的真实软绕行范围启停、范围或实际代价变化，增加本层nav_revision；适配预留与真实展开/收拢更新本层occupancy_revision。软成本变化不以同时发生硬占地变化为前提。竖向连接与运行模式由原连接索引及交通修订核验。局部变化在下一次相关查询前修补依赖点边；不能只按收起的3格忽略5格床尾。所有点边按ID排序，四邻、无斜向和部分路径返回。门没有故障状态；适配预留和收拢改变实际墙边及动态占用，安全出口检查与当前伸展尺寸一致。层内[AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html)图负责明确节点与连接，项目负责实际几何与适配预检；服务可达检查复用同一图与包络，不在UI再算一份。

通行组的结构通行检查复用当前楼层与完整包络的不可变几何；几何、身体、姿态或配位改变时更新。短时预约与成员身份的实际许可由移动在当前扫掠处复核；同体型替换者不继承他人的使用权。结构路线不因普通行人或未知队列变为无路。

### 行人争用的局部完整候选

movement_queries沿pathfinding.local_updates原8×8格逻辑桶，按floor_id稀疏登记当前实际身体和原Movement单位的完整包络。真实位置从Actor互斥的地面/设施/轿厢/跨层状态读取；实际位于本层的患者、员工、普通访客与等候者都可成为相关身体候选，不能只索引正在走路的人。乘梯中不在地面伪留另一位患者，登舱/离舱以原交通真实提交切换；同XY不同层互不进入层内候选。完整陪同组沿原组身份和包络处理，成员不另造重叠的新移动Actor，也不因索引拆队。

移动单位键复用原单人Actor或现存组拥有者的稳定身份；原组没有独立ID时，按原唯一任务/转移拥有者ID派生带类型键，不生成新世界实体。当前成员从原组记录读取，历史扫掠使用原提交参与者作精确依据。组成员变化后，不能仅因单位键变化漏掉本人/自有身体排除，也不能把已经离组的他人继续当成自有预约例外；精确检查始终按该次原当前位置与原参与者解释。

身体及拟走路径按实际包络/分段扫掠覆盖所有相交逻辑桶，边界接触保守入桶；用当前真实位置和精度，不把小数位移粗取整或只索引锚点。跨桶长身体和展开后的症状仍被找到，原组包络不能缩为领队点。多个合法分段分别登记，不用起终点的大矩形代替原实际路径。只保守多报，查到同一桶不意味着身体相撞；查询取全部相交桶，按原Movement单位键去重，再按原稳定实体顺序处理，无最近N人/每桶人数截断。

阶段⑤内已经接受的原移动提交保留其实际本步扫掠依据并入局部候选，直到本次⑤结束才释放；它是历史扫掠依据，不是另一份当前Actor位置或预约。拟走扫掠也查询这些记录，避免前一个人移到新点后漏掉刚经过的区域。最终许可仍检查原当前身体、原扫掠/同行时序、预约和礼让规则，不能把粗矩形相交直接判成碰撞、把整条扫掠硬占满一tick，或阻止原本能并行的宽路。设施、门、展开预留与建筑仍由原静态图/适配占用拥有，索引不是绕过它们的第二条路径。

每次真实位置、有效身体/症状、原组成员或实际位置种类提交，先核验原事实，再原子移除旧桶引用并登记当前完整新范围；下一次相关查询读取已提交结果，不能拖到视图或低频动画更新。普通迈步仅改变行人位置时，只更新少量实际引用，不增加nav_revision或重建全部身体图。⑤开始时本步扫掠集合为空，每项来自已经接受的原提交，本阶段使用期间固定保留；源事实晚于该次查询的变化按原阶段顺序影响后续查询，不回溯已完成的医疗。

完整性取本医院加载会话、对应原位置/身体/组身份以及当前模拟阶段，不能从缓存存在或一次空桶推断已经完整。派生索引失效时，在下一次相关查询前从原当前事实重建所需层，或沿原完整同层查询并同时检查仍保留的本步扫掠；使用期间的扫掠依据不能因LRU回收丢掉。索引没有就不声称通道空闲，也不把未知当永久无路/重置票号。真正无路仍忽略可移动行人查询原建筑/设施/身体几何；临时争用、3秒退让、5秒重查及30/60秒选站/转诊保持原区分与优先序。

索引和临时候选只按实际单位/所交桶/本步扫掠分配，计原医院工作集及模拟步/输入响应目标，不建立全院Actor²矩阵、每层满格数组或10000份空索引。原全院移动请求FIFO与max(8,ceil(A/20))额度、速度、队列/候诊/怒气及业务随机完全保持。读档先恢复真实身体/位置/原Movement，再在启动模拟前重建所需索引；本步临时扫掠、桶引用和候选不入快照。原96×96同层160/640与宽高联合样例分别测分散/密集/会车/转床，记录访问桶、候选、精确检查、更新引用和真实时间峰值；局部候选算例不证明实时避让或本机性能。

### 局部通行图更新与查询结果

pathfinding.local_updates使用同层8×8格的逻辑分桶索引真实几何与软代价依赖，与16×16显示块独立。96×96层面最多有144个逻辑桶，实际缓存只为已请求楼层及真实包络建立。桶用于筛选受影响的节点和边；整条路线仍可跨越任意数量的桶、房间及合法连接。缓存冷热和镜头视野不改变节点、通路或业务请求顺序。

建筑和设施系统提交真实变化前后占地，分别扩展当前图包络的最大扫掠范围，查相交桶，再精确检查节点身体足迹和四邻边扫掠依赖。移动物件的两端范围分别取并集，不用包住两端的巨型矩形使中间走廊全部失效。索引允许保守多报，不能漏掉门两侧、净宽高变化或伸展尾部；包络来自实际身体和当前症状，不把外扩固定成1格或3格。连续提交在下一次相关查询前合并脏范围，查询必须完成所需修补后才读取图，不能先返回旧通路再后台补正。

清扫工作、活动与冲突仍由各自原状态拥有软绕行范围及生效条件，真实变化在原模拟阶段提交前后范围和代价影响。沿同一分桶/实际包络依赖修补受影响的原边权，并使后续新查询读取当前nav_revision；不另存软成本修订、逐人绕行矩阵或第二套区域状态。开始演出时硬预约可能已经取得，结束演出时人物也可能尚未离位，软范围启停仍独立生效；实体身体、工具与预约继续按真实占地检查。重叠范围只撤掉本次结束来源，受影响边从当前仍有效的原来源重新求值，不能把另一场仍有效的软代价一并清零。普通行人迈步本身不改变这些软范围；纯动画、字幕、静音、低动态和镜头操作也不提交软代价变化。

软绕行保持原正代价和不硬封唯一出口的规则，不改移动速度或新增权重。即使可达性与occupancy_revision均未变，新查询的最优路线及实际步行距离仍可能改变，不能复用旧结果或只检查上次走廊。已派Movement不因成本高低改变而追逐另一条较便宜路线，仍按原剩余扫掠、真实阻断和连接规则安全接续。冷缓存、缺脏历史或恢复加载时从当前几何、占地和仍生效的原软范围一起重建；不以软区已不可见或旧图被回收视为结束。范围索引、边权与修补共用原缓存/工作集预算，空层不预建记录，所有实际成本计入原帧、模拟步和输入验收。

门和护理病床的真实主体变化进入结构几何；固定设施主体不因使用者变大。设施实际使用区域及权限是移动执行的动态阻挡，在当前扫掠处检查。普通点路线忽略临时身体与操作预约，不提前推演其解除时间。建筑拥有墙地/门/楼板，设施管理拥有使用权，Movement拥有行程与真实交通票，HospitalNavigation只持可丢弃的图、依赖和路线结果。显示、材质、低动态和切层不产生导航修订。

结构路线缓存区分实际起终点、完整身体与同行组、楼层和当前结构几何；本次同步查询结果只在事实不变的边界共享。允许绕经其他层的同层起终点仍属于跨层查询。局部避让与设施使用检查另按当前预约权限隔离，不能把他人的实际使用许可写入公共结构图。新捷径、新门或真实主体尺寸变化后重新查询；旧结果按原预算回收，不积累每次改建历史。

跨层点到点查询由HospitalNavigation根据当前合法连接与基准通行成本搜索，不推演电梯队列；可移动身体及短时操作预约不否定结构通路。HospitalMovement持有真实行程、票和扫掠，在实际遇到处检查占用并处理队列、局部绕行和安全段。HospitalTransit.quote只提供独立只读估时，未知不作为无路。实际身体位置、业务资源承诺与交通事实保持唯一，详见[任务、寻路与移动规格](../specs/26-10/2026-10-19-task-navigation-movement.md)。

已经派发的活动路线拥有原Movement意图；相关变化先核验尚未走过的身体扫掠和实际所用连接，变化只在已走路段或无关走廊时继续原路线。剩余路线被阻断、身体改变、目标失效或所用连接变化时，按原规则从当前位置重查；已经处理后失败的重试排到全院队尾。角色不会为追逐新捷径每次装修便中断照护或重置等待。每次实际移动边、过门、预约和开工仍以当前世界原子核验，依赖索引不是穿过障碍的许可。

图、几何依赖索引、合并脏记录和查询结果共同计入原128MiB目标及医院真实工作集，不给每类缓存另分一份128MiB。脏记录只覆盖实际缓存所需的近期变化；缓存释放后不保留该图的长程历史，不为10000层建修订数组。导航修订属于本次加载会话内由真实提交驱动的派生有效性标记，不进快照；读档从同一世界重建。每层派生修订记录与仍引用它的图/结果同寿命，释放该层最后的缓存记录时一并丢弃层内查询结果；新记录不能拾回旧结果而造成修订号重新命中。活动路段随原Movement保存，依赖索引在模拟启动前重建，不相信上次会话的修订号。脏历史因回收不完整时，只从当前世界重建所请求的层/包络，不能把旧图标为有效，也不能以“缓存还在更新”认定无路或取消预约。所有修补与重建计入原模拟步、输入响应和内存采样，尚未实测性能。

### 全院请求与只读查询

阶段⑤每步处理的Actor移动路径请求额度为max(8,ceil(A/20))，A取本步开始时真实在院的唯一Actor数，包含乘梯者，不包含院外休假或未生成的来客；全部楼层共用一个按请求序号的FIFO队列。160人额度8，320人16，640人32；人数增长增加计算额度，不改变走路速度、体型或通行权。即使缓存命中也占额度，避免硬件与缓存改变业务顺序。每个Actor最多一项待处理移动请求，目标改变时原位替换内容、保留序号；已经处理但因占地修订失效的重试重新排到尾部，不能无限占住队首。消失或结束需求的请求按原事实取消。

建造预览、诊疗Readiness和规模投影使用只读的拓扑/适配可达查询，不向Actor移动队列插入虚假人物，也不消耗其业务序号。相同相关修订可复用只读结果，真实预约前仍原子复核。查看哪层、打开多少卡片或缓存冷热不改变移动请求处理次序；算力不够时沿统一模拟降速，不能丢弃角色、跳过候诊计时或用穿墙路线“赶上进度”。保存中的活动路线与请求队列可恢复；共享寻路缓存、空间邻域索引和环境覆盖缓存不保存，载入阶段重建后再启动模拟。社区活动集合预算仅在整组转集合时按同刻原路线和相关连接完整前缀求值，按连接聚合起终层极值；仅遍历实际路线段与队列，不生成空层数组、未来票或持久预算副本，保存仍使用原活动截止tick。已保存路线如因内容迁移失效，从当前合法格重算并明确返回修复摘要，不跳过诊疗。

### 到访机会的先决排除

原阶段③使用arrivals.admission_evaluation确定求值顺序。先读当下intake_open，关闭时仅按原计划消费机会；开门才查询实际门诊在院人数与原当天冻结额度，已满时同样仅消费。排除分支不建立完整病例候选、不求资格/身体/团队/床/路线，也不消耗本次患者抽签。正常通过才使用原完整Readiness与真实入口核验。人数与床承诺来自原事实查询，代价计入完整步；日计划人数/种子抽签仍在原日界，不因关诊优化换序。

同tick按机会序逐次读取，前一次实际入院提交后立即影响下一机会；失败不虚增人数，不批量复制第一条允许结果。阶段②已释放床承诺及原提交状态可见，⑤实际离院到下一③才释放额度。算法不复制世界、不增快照人数、不给空层生成逐层检查；原只读原因卡和临床准备队列继续自身查询，早排除不能替代其完整原因。性能采样同时对照机会游标、实际患者、原随机状态与准备结果，记录完整病例查询次数和原取数成本；没有运行数据时不报告帧率收益。

### 未开工临床队列的条件重查

clinical_readiness_queries只优化已有临床QueueTicket的准备查询。Readiness拥有完整资格/设备/空间/人员/库存/床位核验；QueueService拥有票序、优先公平与当前预约。一次完整查询失败后，可为当前票保存至多一份派生“必要条件仍为假”的依据，包含当前病例/服务目标身份、一个确实阻断开工的条件、它的全部相关依赖及最早原时间边界。依据不拥有第二套患者、方案或可开诊状态，不缓存“允许开工”。只要该必要条件能够证明仍为假，就可省去同一准备查询；缺依据、依赖不完整或条件随时间变化而无法确定边界时，执行原完整查询。

ReadinessFailureProof的运行字段为hospital_session、current_ticket_id、case_query_signature、handler_id、dependencies_complete、dependency_stamps和next_original_tick。case_query_signature为当前病例/阶段、服务目标、方案/模式及其所需包数、实际包络/目标姿态、准入参数和完整query_options的稳定值元组；忽略治疗包或使用自有预约例外的查询不能共用同一身份。dependency_stamps为完整资源作用域键到当前修订/身份值的映射。next_original_tick为原条件的最早时间复核点，无时间依赖才可为空；未声明、类型错误或过期都使依据失效。dependencies_complete仅由经过完整依赖校验的处理器产出；布尔标记本身不能代替依赖证明。初始字段全部来自完整失败查询，后续只允许下述原缺包处理器更新库存stamp，不允许界面或内容文字自行造依据。

当前可提供依据的基础类别为治疗包不足、必要设施不存在、合格团队缺失和兼容床暂忙。库存依赖读取真实实存/预留及当前方案用量；设施/团队/床依赖覆盖该服务所有合法替代来源。没有候选时按设备定义、岗位/能力、作用域及相关拓扑关注新增实例、招聘、能力提升、研究完成与新路线，不能只订阅上次不存在的某个实例ID。实际可用性和目标姿态、身体、方案/资格变化都使对应依据失效。扩展条件可注册完整依赖处理；无法声明完整依赖的处理器继续原查询，不为优化限制新种族、病症、设备或流程。

库存修订变化后，原supply_shortage处理器可在下一合法④续证，但仅限本人没有任何有效治疗包预留的同一未开工准备票。必须保持同一医院会话、票/病例与完整查询身份、处理器和依赖作用域，完整依赖中所有非库存stamp不变，原next_original_tick尚未到达。读取同一已提交边界的实存S及全部有效预留R，以A=S−R重验A小于当前原方案所需量；仍不足时只更新本份Proof现存库存stamp的值，其余字段及原期限不动。stamp表示原来源修订而非A的数值；A由5升至6但仍少于12，同样可以证明不能准备。相关变化先标脏，未完成这次复核前不能沿用旧stamp。

本人准备取得、释放、过期或改变目标时撤掉旧依据并沿原完整准备校验，即使当前又恰好没有预留也不能续回旧依据。S=12、本人有效预留12、A=0时，原准备可以使用自己的承诺，不属于这种无预留缺包证明；部分或异常承诺也交原不变量检查。其他人的领用与预留释放必须在原原子事务或既定阶段真正完成后读取，不能提前扣除未来将到期的R。新增/缺失依赖键、处理器声明变化、其他依赖变化、原期限到达、缓存缺失或A已足够时均回到完整查询；原依赖若包含人员、设备、床位、适配占用或相关跨层路线，也不能借续证丢掉它们。无需额外订阅与这一必要条件无关的全院路径。

续证只回答同一准备查询仍被缺包阻断，不回答哪一原因最重要或是否已经就绪。方案重评、忽略包数的缺货关闭查询、采购报价、实际受阻计时与复工仍读各自原规则。若400张无本人预留的票各需12包，当前S=17/R=12/A=5；另一位已预留者真实开工后S=5/R=0/A=5，可以逐票复核同一缺包谓词而不重求其余准备条件。后来仅到6包仍可续证，到12包则恢复完整公平查询；首票取得预留后，后续票读取新的R，不能共享一份可开工许可。400只是条件算例，不限制票数、不免除逐票处理，也不保证库存查询为常数时间或已经测得提速。

依赖索引使用稀疏资源键到原票ID的反向引用，并按当前真实目标作用域关联；不构造“所有患者×所有人员×所有设备”矩阵。一次相关变化只将当前票标脏一次，多项变化合并；无关楼层的普通走动、镜头切换、列表开关或另一专业的非关联设施变化不唤醒本票。路线阻碍须关注全部可能恢复可达性的相关拓扑，不能只看旧失败路径走廊；跨层连接恢复按原空间查询重新判定。依赖记录的病例阶段、身体、方案与当前票身份必须匹配，已开始、离院、取消或真实改派后解除旧引用，不让旧通知复活结束请求。

唤醒只是下一次合法④调度的查询候选。①真实采购完成或②岗位/拓扑变化，可在本步④检查；⑤真实到位、⑥服务完成释放或⑨研究解锁，影响下一步④。④中尚未越过原调度位置的后续对象可合并当前唤醒并读取当前资源，已越过位置的对象被新事实标脏时留到下一边界，不逆序再次插入。候选按原票号、优先照顾的两优先后最早普通规则及既有稳定实体顺序处理，不能按事件到达顺序、显示楼层或缓存命中排队；无固定唤醒人数上限。

时间依赖直接引用原模拟时钟及条件阈值，不另建从最后一次检查重新开始的等待钟。硬无路的5秒重查、30秒重选、60秒转诊，手术准备30秒到齐、床位预留的距离开始≤30秒，以及各流程120/300秒提示/转诊边界仍在原时点执行。连续可用窗口、能量/预测效果或其他随时间变化的条件，必须有可靠的原阈值/状态变化来源才可静待；不能证明时保留原查询。定时依据只决定复核机会，不延长限期、暂停候诊或创建新的服务机会。

节省准备查询期间，方案有效性/原重评处理、员工准备、队列优先计数与期限事件继续各自原规则，不因某项必要缺失而省略这些独立检查。实际医疗/护理工作、⑦有效候诊/怒气/需求采样、弃候评估和其随机流照常运行。条件恢复后仍完整核验目标、团队、适配、库存与床位；两票同刻醒来争最后一包或同一床时，只有原顺序中原子取得资源者可开工。面板使用原ReadModel查询当前原因，不能把缓存中的旧缺项当作现场真相；打开卡片可只读查当前条件，不清脏标记、加优先或提前派单。现场叫号仍是原票号/头像/站点图示，无语言。

失败依据、反向索引、合并标记和到期候选均为本会话可丢弃的派生缓存，按实际分配计入原工作集，不进世界快照；所有业务票号、原时钟和预约仍照常保存。缓存回收或载入重建后，在下一原调度机会完整查询，不能把没有依据当作永久不就绪，也不补发错过的期限/抽签。空层没有票、依赖表或轮询任务。大平层与多楼层640人密集样例中同时覆盖缺货/缺岗/床满、同刻恢复与强制回收，记录完整/复用查询次数、实际字节和原帧/步目标；静态依据算例不证明真实查询性能。

### 患者耐心的到期索引

patience_schedule依据随机来客§2的唯一行为规则，只索引原弃候流程的当前活动QueueTicket；不把全体Actor、全部楼层或临床准备请求再复制成定时任务。每票最多一项当前到期记录，键包括医院加载会话、原Actor、当前票身份与原next_check_wait_ticks。当前等待量、暂停原因、怒气、性格和概率输入仍读取各自原所有者；索引只持身份、可证明的下次模拟tick与定位当前项所需的句柄。

在阶段⑦原有效候诊积分完成后的同一边界，对确定正在按每tick增加一有效等待tick的票，派生due_tick=current_sim_tick+max(0,next_check_wait_ticks−current_waited_ticks)。距本阶段尚未积分的tick不能重复算入；本步早阶段新建/暂停/恢复或替换的票先标记其当前项，⑦读已积分的真实量后重算，达到阈值者就在本步既有离院判定位置处理。对暂停票不安排未来抽签；状态变化、有效时钟是否推进、当前票/阈值或医院会话改变，必须原位改期或移除旧项，不能只追加失效墓碑让内存随医院运行时间增长。不能证明推进速率或完整变化来源时，对该受影响原票执行原检查，不用猜测日期。

到期处理先服从原真实服务/安全和确定性退出次序，再以原Actor ID及当前票ID稳定顺序处理概率候选；这保持全院原稳定角色顺序，不使用入堆顺序或观察楼层。概率只在实际评估边界读当前怒气/环境/性格，沿原万分取整与patience随机流。原WaitDepartureState先在同一消费提交推进该门槛，再抽一次并提交其决定；同tick多个旧通知不能重复推进。随后按新原阈值重算，结束票解除索引。所有真实同刻到期项均在原步处理，不借路径FIFO额度、固定每帧人数或延迟一tick改变经营。

阶段④叫号、⑤移动状态与⑥工作完成可在本步⑦改变资格；⑦内真实退出也即时撤掉对应条目。其他原时钟的怒气退出、无进展转诊、生活需求、实际候诊累计、环境采样和临床准备全部继续，不能因为这张票没有概率到期就跳过独立规则。概率输入变化本身不提前抽签，也不把每10秒环境采样改为每30秒。接受叫号后等待电梯是否仍累计，完全读取原票状态，不把“Actor正在走动”一概当成暂停。

载入在验证原实体、票、时钟及临床状态后、下一⑦执行前重建当前活动索引；缓存丢失同样从受影响原所有者恢复。重建不抽签、不补发已经消费门槛、不更改原有效量。条目、定位句柄与重建临时副本的实际字节计入原工作集；空层不建立定时槽或角色记录，数量随实际活动票增长而非楼层高度。它是派生索引，不进入世界快照，也不另保存due_tick或概率。

静态时钟算例：同一固定票连续有效等待到180秒，只有120/150/180秒三个概率门槛。640张均未终结的固定票在1,800tick内有1,152,000次逐tick“是否到期”检查机会，而门槛通知为三批各640次、合计1,920次；这只比较尚未到期的调度机会，没有运行概率退出、计算原积分成本或测得提速。真实患者可更早进入服务或离院，索引维护、每批同刻640个通知、内存及其他模拟工作仍要付费。正式160/320/640人分散/同刻到期、生活暂离、叫号、确定性退出、冷热重建与跨层场景须对照原逐票评估的事实序列和patience流末态，记录查询次数、维护次数、实际字节与原帧/步目标；无实机测量结论。

### 空间邻域与环境

事件近邻使用(floor_id,8×8分区)稀疏索引，不跨层扫描或传播环境；每5秒按社区喜剧章的内容选择器索引与邻近桶规则逐组查询，包含距离范围相交的相邻分桶，不构造全院角色对矩阵。缓存重建与显示层不改变原轮询顺序或随机消耗。每种族动画LOD根据投影像素大小调整，模拟始终保留全部角色。屏幕外治疗照常结算，切回来时直接映射当前进度，不从头播。

环境查询先复用与身体无关的局部覆盖：已完工墙地、装饰类别、照明、污物/洁净、实际噪声和临时回馈，再按请求身体核验饮水可用性并生成最终0…100分。共享覆盖键包含CellRef、相关局部内容/几何/工作状态修订和正向范围版本；饮水查询另含真实TraversalEnvelope与相关占用修订，不能只按格子缓存一个全体型结果。座位偏好、静音罩对怒气分量的倍率和舒适等级仍由各自原规则组合，不塞进公共环境缓存。

材料完工、物件搬动、污物真正清除、工作段启停、屏风/墙边和实际伸展变化只使相关同层范围失效；取变化前后占地并集向外扩最大适用半径，噪声仍执行自身4步规则。R15改变正向范围版本，相关查询按需重建，不遍历10000个空层填热图。缓存只保存近期实际查询并按字节回收，替换旧修订而不积累每一tick的历史。患者情绪/评分采样前必须得到当前有效结果，不能以“热图还没刷新”为由使用过时的饮水或噪声分。关闭热图、切层、暂停和冷热缓存不改变世界结果。

### 当前层环境热图

environment.heatmap_view使用spatial_view原16×16显示块，只为当前层视野内合法楼板采样；最大96×96层面的原始颜色/状态共9216格、最多36块。块以共享颜色和有效状态掩码批量绘制，不为每格建立Node、Control、文字、3D碰撞体或独立环境更新器。空层结构仍从地块高度派生，打开热图不预先生成10000份格子场。原环境共享覆盖与身体饮水可用性查询是数值唯一来源，显示层不另写一套美观度或舒适公式。

热图主体取当前实际选中居民的TraversalEnvelope及准入查询参数，或原明确标注的体型示例，不创建测试Actor、移动请求或饮水预约。绘制的格子表示该身体在这里的环境查询，不代表居民实际走到这些位置。固定几何/真实展开占地无法容纳身体时显示body_no_fit；未购地或本层未完工显示outside_owned_floor，均无环境分。普通路过者与正常饮水排队沿原可用性规则，不因有人排队把合格饮水源判成失效。患者卡和体验采样仍查询本人实际位置，不从热图读分。

显示刷新最多每200现实毫秒受理当前最新需求，最多5Hz；节流归本次医院视图会话，切层、换身体或反复关闭/打开不能重置门槛。连续变化合并，不排历史帧。颜色/状态生成、绑定、上传和释放与原新增显示工作共用每帧2ms及最多启动2块任务，不能另给热图追加2ms或两份启动额度。单块内部逐格或小批完成，原主体轮廓/安全状态与选中、稳定悬停单格的当前查询优先，再处理可见块。200ms是刷新频率门槛，不承诺一次算完整层；未完成块保持明确更新状态，输入和业务沿原响应/模拟目标继续。

相关真实环境变化先撤销受影响块的当前标记，绘制时以块状态遮为updating，再按原范围和身体核验重算；遮掉旧值不等待200ms刷新门槛，也不要求先重算或上传整张颜色场，状态变更的实际显示成本仍计原预算。不让施工噪声开始、纸屑清除或床尾展开之后的旧颜色继续冒充当前值。每块完整取得同一请求的有效结果才发布，environment_query_stamp必须覆盖原查询的全部相关材料/几何/工作/占用等修订，range_version读取原正向范围版本。该标记来自完整相关局部查询依赖，不拿WorldState.revision或sim_tick作统一失效键；依赖无法可靠细分时执行原完整查询，不能为了减少刷新漏报实际阻碍。异步或分帧期间再次变化就丢弃旧块结果，不把不同主体、范围或世界修订的单格拼成一份当前块；其他未失效块可继续显示。

请求身份逐项包含hospital_session、view_id、view_generation、floor_id、chunk、subject_identity、traversal_envelope、query_options、environment_query_stamp、range_version与content_fingerprint。切层、换身体、症状缩回、准入参数变化、关闭热图或换医院时撤销旧绑定；迟到结果须全部匹配才可发布。只有相关需求变化增加视图代次，模拟每tick变化不是统一重建理由。预取圈不计算环境色场，不为镜头曾经经过的楼层保留历史更新队列。

状态掩码区分current、updating、body_no_fit及outside_owned_floor。只有current可显示0…100值；真实0分与尚未采样、身体放不下分别可辨。图例采用原环境怒气缓冲60/80、舒适70及0/100端点，结合颜色、明度、纹理和单一文字说明，不把色带当成保证舒适等级2。单格详情由原当前查询显示分项及身体/位置来源，不能从颜色纹理反推旧分或用近似远景值付款/结算。分数是否有效与低动态、静音或显示分辨率无关。

每格原始颜色4字节、状态1字节，一块16×16共1280字节，最大平层原始负载46080字节；若每块同时有一份当前与一份待发布负载，原始数据为92160字节。此算术不含容器、纹理行对齐、上传临时副本、网格和其他显示资源，不作为实测内存。每个活动块请求至多一份待发布负载，旧请求撤销即解绑并按原预算回收，仍未释放的字节继续计账。全部原始/暂存/图形资源计原工作集与512MiB图形目标；热图缓存和显示身份不进快照，不回写Environment、PatientAffect、评分或任何随机/业务时钟。

主模拟、场景树与资源实例化留在主线程。保存时主线程调用WorldState.snapshot_copy() -> WorldState建立只读深副本，工作线程只编码该副本和写字节，不访问活跃场景节点或世界。SnapshotStore.write为需要await的异步入口，成功回执回到主线程；界面不能同步等待磁盘写入。Godot并非所有API均可安全跨线程；遵循其[线程安全说明](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)，不为未验证的并行化增加共享状态。

候诊选位由原临床队列发起，按[公共设施规格](../specs/26-10/2026-10-18-public-facility-area-use.md)区分自动区域意图与手动指定设施，实际到场后复核当前身体/权限、空位、空间和路线。原任务拥有意图与区域等待，SeatSession/FacilityReservation只拥有实际入用及安全离位占用；选择器不另存座位分数、朋友位置或候诊时钟。临床叫号优先；候诊卡打开与否不决定选位顺序，八项条件不消耗随机流。入座表现由实际坐姿和当前条件投影，不靠动画结束开启椅子效果。

候选从已有座位与空间索引按需查询，借真实路程下界排除超过自动窗口或最近路程带的区域；只有可证明超出才剪枝。跨层必须包含同一交通代价，不能拿平面直线距离当最终路程。没有固定候选数量、楼层数或朋友数上限，也不每5秒为所有已坐患者遍历全院。无座请求在相关座位释放、空间/路线变化或原候诊调度机会重查；当前合法座位不因邻域缓存失效重选。邻居、污物、装饰和小戏复用相交的同层桶与环境覆盖，关系只查实际邻近居民，不能构造全院角色对。缓存键含相关几何/交通/占用和查询身体，当前关系与角色阶段仍即时读取；冷热缓存、切层与载入重建不改变排序。密集附近座位与640人并发请求仍计入本机模拟步和帧目标，算例不证明性能达标。

### 管理列表与只读查询

患者、员工、房间、设备、楼层、目录和历史列表只为可见范围加上下各一屏缓冲创建行控件；以当前字号、缩放和真实行高计算范围，不将屏外条目隐藏后仍保留一整套控件。行只持稳定对象ID与轻量显示字段，头像复用共享静态缩略图，不给每行加载骨架、治疗机器或独立3D视口。选中详情按需读取原实体，关闭面板即解除绑定；医院规模不受行池或头像缓存数量限制。

筛选、计数和排序使用对应领域的派生索引及合并后的变更，不每渲染帧全量排序或读取所有病例历史。索引只保存必要键与ID，可重建且不进快照；完整对象和金额仍由原世界拥有。未查询的诊疗路线、所有候选方案与跨层可达性不为了显示一行姓名而提前求解。列表总数取完整条件匹配，不把目前绘制的行数、取样数量或未结束查询的0当实际人数。

重排保留选中对象ID与首个可见对象及其行内偏移；文本输入/输入法组合、拖动和按键确认进行中暂缓行序重排，单行状态仍可标明已变化。行复用前解除旧对象的处理器、提示和异步头像绑定。一次输入从按下到确认捕获同一对象ID，不能按确认时的行号重新找人；对象离院、离职、被售出或不再符合条件时明确说明，不能将命令转给补进这一行的新对象。

查询结果带hospital_session、panel_generation与query_generation；切医院、关面板或连续换筛选时撤销旧查询，迟到结果不覆盖当前选择。初次重查询显示正在更新而非空医院，已有结果可标明上次完成的投影并继续浏览；付款、招聘、排班等命令仍在原事务中重查当前实体、资格和价格。可取消的查询分批执行，不能为了画列表暂停模拟、占治疗资源或消耗随机流。实际UI耗时与缓冲内存纳入本章性能目标。

### 原生界面的文字与字体资源

文字投影沿用原事件脏标、普通数值最多10次/秒和可见行范围。只有相关显示字段改变才重新格式化，不因世界tick、远处演员移动或当前卡片无关的事实重做整页文案。格式化后的字符串仍相同时，复用控件已有文本及引擎已有的相同文本短路；不在外部再保存一份全院姓名、病例文字或“上次文本”字典。引擎已经避免的排版工作不能计作新增优化收益，实际格式化、文本提交和排版分别测量。

文字未变不等于布局未变。字体及回退资源的实际内容指纹、实际字号与UI缩放、可用宽度与换行规则、语言方向及字形排列选项变化时，原控件须重新处理相应布局；同一名称或资源路径不能证明字体相同。颜色、选中、进度条、图标、提示全文与当前来源仍按各自原属性更新，文字相等不能跳过整个控件。已有排版结果由控件和引擎拥有，不增加一套可修改布局事实或全局排版缓存。

行复用、病例切换和医院切换先执行原完整来源解绑与重绑，即使两位居民同名、两位医生说同一句话也一样。操作目标仍是实际对象ID；医患卡的实际回应来源、阅读窗、焦点和迟到结果仍按原合同处理，不能因字符串相等沿用上一位对象的操作或来源。10Hz只约束原普通数值投影；输入法预编辑、候选确认、文本光标、焦点、按键反馈及命令结果沿原即时输入处理，不等待下一次数值刷新。未确认输入不执行医院命令。

Noto Sans CJK SC及随包回退字体按内容指纹与资源ID共享只读字体资源，字形与排版优先使用所选引擎后端已有能力。各控件的字号、颜色及布局是各自属性，不能通过修改共享字体让其他控件跟着变化；不为每行、每位居民、每座医院复制字体或字库。仅按实际可见文本需要生成字形，不遍历全院名字或整个Unicode范围预热。新增罕见字不成为拒绝合法名称、删字、截断金额或把UI降为75%分辨率的理由；离线回退仍缺字时保留原Unicode文本、显示可辨缺字符号，并允许在原全文/编辑入口查看和复制原文，不联网取字、不悄悄替换保存的名字。

字体文件大小只表示编码资产。实际字形纹理页、相关GPU缓冲、加载中副本和仍驻留的旧字号资源计入原512MiB图形预算；字体面、字形排列结果、排版暂存和后端实际额外分配计入原2GiB工作集口径。同一实际分配按既有集显规则识别，不能把共享引用数当副本数，也不能漏掉后台仍持有的页。只释放后端确实支持且已无使用引用的资源；没有逐页回收能力时按实际常驻量计数，不声明一个不存在的LRU已释放内存。派生字体资源不进医院快照，切院不复制字库，也不要求为了清缓存重新载入医院。

冷字形生成、UI缩放和必要排版的不可分调用计入发生时的真实普通帧；不把它们视为零成本，或假定引擎调用能自动分片到原视图预算。原预算和输入目标保持，未知字形页格式、实际驻留或排版耗时时标记未测。1024×1024单通道8位页为1,048,576字节、同尺寸RGBA8页为4,194,304字节，仅为无mip原始字节示意；实际后端格式、页尺寸、额外层级、暂存与驱动分配另测，不能据此宣称本机通过。

变更面为原生UI文字的按需处理、字体共享与实际资源计量。世界状态、名单、病例、收费、评分、随机流、输入目标和已有文本内容保持原归属。原160/640角色、96×96大平层与10000层联合样例分别测试冷暖缓存、密集列表滚动、长名称/罕见字、中文输入、五档UI缩放往返与切院；记录格式化、文本提交、实际排版、字形未命中、实际页/字节、UI耗时和普通帧尾部，沿原1×/3×帧、响应和内存目标验收。诊断采集额外开销单列，业务同源重放须一致；定义与字节算术不构成真实加速证据。

## 7. 本地保存布局与协议

启用use_custom_user_dir，custom_user_dir_name=oddly-good-hospital。Windows路径为 %APPDATA%/oddly-good-hospital。通过user://和系统路径转换访问，不从可执行文件目录猜测可写位置。[Godot数据路径](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)。

```text
user://.session.guard
user://settings.json
user://blueprints/<uuid>.json
user://hospitals/<hospital_uuid>/hospital.sqlite3
user://hospitals/<hospital_uuid>/hospital.sqlite3-journal  # SQLite事务期间及中断恢复时
user://hospitals/<hospital_uuid>/thumbnails/<snapshot_uuid>.png
user://trash/<hospital_uuid>-<deleted_utc>/...
user://migration-backups/<hospital_uuid>/<snapshot_uuid>/...
user://photos/<hospital_uuid>/...
user://logs/...
```

### 同一资料库的进程所有权

同一实际user://资料库同时只允许一个游戏进程载入并操作，主菜单、暂停及多座医院切换都处于同一次占用中。原串行写入器仍负责进程内保存顺序；只有它不能阻止第二个进程从同一旧sequence分叉保存、轮换同一日志或清理另一个进程的提交。所有权属于AppRoot的进程生命周期，不属于某座WorldState，也不进入快照、蓝图或三条目备份包。

PlatformSessionGuard通过OS.get_user_data_dir()取得实际目录，首次启动仅先创建根目录与固定`.session.guard`入口，然后用CreateFileW以读写访问、dwShareMode=0、OPEN_ALWAYS及不可继承句柄尝试打开该文件。打开成功的句柄是唯一占用凭据；文件内容、存在与否、PID或进程名都不是凭据。已有空文件可以直接重新取得，不删除它来“解锁”，不同快捷方式、安装路径或同一目录的路径别名不能产生第二份所有权。Windows共享模式在句柄关闭前拒绝冲突打开，进程异常终止后由系统关闭该进程的句柄；实际崩溃恢复仍按原提交协议核验。[CreateFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)、[文件句柄关闭](https://learn.microsoft.com/en-us/windows/win32/fileio/closing-and-deleting-files)。

资料库占用与SQLite原生桥接随标准引擎导出打包，使用匹配固定引擎版本的接口、`.gdextension`声明和Windows x86_64动态库，不要求玩家另装工具、启动脚本或后台服务。PlatformSessionGuard仅返回取得、被占用或具体平台错误，提供只读占用状态并持有、最终关闭句柄；固定操作实际user://目录，不接收任意路径或向脚本暴露原始HANDLE/文件API，不编码医院、账目或保存协议。OPEN_ALWAYS返回有效句柄且附带ERROR_ALREADY_EXISTS仍是成功；只有失败的ERROR_SHARING_VIOLATION归类为被占用，其他失败分别报告。缺失、位数错误或加载失败时停留启动错误页，不回退到文件存在检测。GDExtension提供加载原生共享库的机制，具体打包和句柄生命周期仍需发行包验收。[GDExtension](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html)。

取得所有权之前不读取医院、玩家设置、蓝图或照片，不扫描/迁移/清理提交、垃圾箱与备份，也不创建产品日志。共享冲突显示“医院资料正在被占用，请回到已打开的游戏或稍后重试”，只提供手动重试与退出，不载入只读医院、不强制关闭已有进程；权限、磁盘或桥接错误显示对应启动原因，不误报医院损坏或创建空医院。静态启动界面从安装资源读取，重试取得后才进入原主菜单流程。

发行配置在引擎启动前显式关闭debug/file_logging/enable_file_logging及其.pc覆盖值，避免AppRoot运行前就写入或轮换默认user://日志；取得所有权后才启用原产品日志的5份×2MiB轮换，退出时随其他资料IO一起停止。引擎可重建缓存与上述持久资料分开，不能混放到医院、设置、蓝图、照片或产品日志路径；缓存访问不代表已取得资料库，不承诺引擎启动前零磁盘访问，也不为多开保护关闭原着色器缓存。默认桌面文件日志行为见[Godot日志设置](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-debug-file-logging-enable-file-logging-pc)。

正常退出先停止接收新资料操作，按原规则处理保存与放弃未保存进展，等待已经启动的保存、照片、清理及日志IO实际停止后，才关闭所有权句柄。取消退出、保存超时提示、切院失败或释放旧世界均不释放它；迟到任务仍可能写盘时不能把资料库交给新进程。异常退出后新进程取得句柄，再走原完整提交恢复；遗留空guard不会阻止启动。空guard与原生资源只属于运行协调，不能作为医院列表条目或存档完整性证据。

独占句柄锁住guard入口，由遵守同一协议的程序保护资料，不是整个目录的访问权限控制；外部手工修改仍由原哈希、引用核验和恢复规则处理。安装器/卸载器可通过NSIS自带System插件调用同一Win32协议，不把游戏x86_64 GDExtension库当成NSIS插件。安装程序完成自己持锁的资料操作并释放后，才启动游戏。

### 快照提交与恢复

数据库使用SQLite application_id=0x4F474853及user_version=1；数据库结构版本与世界snapshot schema1独立。hospital表唯一持有数据库所属hospital_id，snapshots表持有snapshot_id、唯一递增sequence、清单原始UTF-8字节、清单SHA-256及sealed提交状态；world_chunks表按(snapshot_id, chunk_index)主键保存≤32KiB的BLOB分段，并以外键关联保存点。索引只加速持久资料读取，不拥有第二份经营事实。SQLite连接只在资料库guard取得后打开，每次后台保存独占自己的连接，连接不跨线程共用；实时模拟只访问WorldState。

清单必须包含format="oddly-good-hospital.snapshot"、schema_version=1、game_version、hospital_id、snapshot_id、sequence、slot_kind(manual/auto/checkpoint)、slot_key、created_utc、sim_tick、content_packs及world_bytes、world_sha256、display_summary。display_summary包含同一冻结DTO的display_name、mode与present_actor_count；人数按实际在院Actor去重，包含楼层内和乘梯者，不含未到院名单或院外休整职员。院龄从该保存sim_tick与已锁定规则推导。摘要只用于列表展示，完整载入时必须与世界核对，不成为第二套医院状态。清单仍≤64KiB，世界大小随实际医院事实增长，不设32MiB固定上限。world_bytes必须为合法非负整数，实际分段字节总数与哈希必须相符，不能只信声明。世界DTO继续增量编码为UTF-8 JSON并存入数据库分段，不形成院外world.json文件，不将JSON配置目录改为SQL业务状态。64位整数、浮点完整精度、随机流和原深度/字符串限制保持；模拟快照仍取同一完整步边界。

连接固定使用journal_mode=DELETE、synchronous=EXTRA、foreign_keys=ON、4MiB页缓存目标与文件暂存。SQLite承担回滚日志和原子事务；恢复不手工删除hospital.sqlite3-journal，不复制正在写的数据库主文件充当备份。[SQLite原子提交](https://sqlite.org/atomiccommit.html)、[同步策略](https://sqlite.org/pragma.html#pragma_synchronous)。

保存步骤：

1. 先按实际世界规模预检副本所需资源；在一个完整模拟步结束后冻结DTO副本，暂停时在全部已确认命令完成后取副本。复制分配失败即保留当前世界并返回可行动错误，不进入提交。生成新snapshot UUID、递增sequence，世界继续运行。
2. 在同医院数据库开启BEGIN IMMEDIATE事务，在事务内取得下一sequence，以新snapshot UUID追加未sealed记录，再分段写世界和清单；过程中继续检查资源，失败回滚，不改旧保存点。
3. 从同一事务分段回读，验证连续chunk_index、实际大小、世界和清单哈希、DTO与业务不变量；全部通过才sealed并COMMIT。任何错误保留当前医院，关闭连接时回滚尚未提交的事务。
4. 重新打开并验证本次已提交保存点，返回携带冻结revision的成功回执。界面此时才显示“已保存”，最近医院索引作为可重建缓存更新。
5. 清理过期记录在成功之后另开事务执行，以外键级联删除分段。保留各手动槽最新、最近5个自动槽、最近3个检查点，以及全医院额外最近2个有效历史提交。损坏记录不充当有效历史；清理失败只增加磁盘占用，不撤销成功保存。日常保存不执行全库VACUUM，空闲页由SQLite复用。

医院列表分页查询sealed保存点的有界清单；先核对数据库身份、清单大小、格式、保存点身份及清单哈希，再按sequence而非系统时钟列出每槽最新提交。浏览列表不读取全部世界分段，不将“清单可读”称为世界已完整通过校验。当前选中的载入/恢复才分段核对完整世界大小、哈希、DTO及全部业务不变量；失败时标记该记录需要恢复并列出此前提交，选择后同样完整校验，不把损坏世界部分加载。同医院的历史保存点是独立逻辑版本，整个数据库损坏时保留原文件并提供外部备份恢复，不用空数据库替换；启动扫描继续查找其他健康医院。

已有工程验证目录commits中的完整JSON保存点仅作为一次性导入来源。首次建立SQLite时按原manifest/world/COMMITTED身份、哈希和业务校验筛选完整保存点，在同一事务导入并保留原hospital_id、snapshot_id、sequence及全部事实；不导入.pending。来源目录不删除、不双写。数据库已经完成首个事务后，它是唯一当前持久化来源；导入失败保持来源，初次事务中断留下的无表数据库可重试，不能覆盖已存在的未知版本或损坏数据库。

最近医院索引按hospital_id、snapshot_id与sequence缓存清单摘要，属于可丢弃的应用侧缓存；删除、恢复、新提交或外部目录变化后按清单重建。全库扫描允许取消并逐页给出已读取结果，搜索尚未完成时不将未扫描部分说成不存在；不能为了排序名称或人数而先载入每座医院。迟到扫描与缩略图结果使用原界面代次检查，关闭列表、切换医院后不附到别的卡片。医院卡片沿管理列表规则按视口复用，不为全部保存点建立图片节点。

医院缩略图为可选PNG，沿用256KiB编码大小上限，解码前检查宽≤640、高≤360及有效像素尺寸，解码与纹理分配按真实字节纳入缓存预算；不依据小文件大小推断解码内存。它只提供保存附近已呈现的本院场景预览，不负责证明患者数量、层数或业务状态。异步捕获携带医院/保存点身份，不能将后来打开医院的画面写进旧卡片。缺失、不能解码或超出缩略图尺寸时使用默认占位图，不尝试从完整世界渲染一遍补图，也不把仅缺图片的有效医院判为损坏；保存成功回执只取完整校验后的SQLite事务。备份容器与世界仍遵守既有格式、字节和资源校验。

自动保存每180现实秒触发，只有模拟或已确认命令造成revision改变才写，最多一项保存作业；未完成时合并为一个待保存请求，不堆积文件。手动20槽，Ctrl+S固定“快速保存”占一个手动槽。自动、手动与退出保存共用同一串行写入器。

SaveRequest与成功回执共同携带hospital_id、加载会话标识、request_id、snapshot_id、冻结的world_revision及sim_tick；加载会话标识属于本次打开医院的运行时，不写成世界身份。回执只确认该副本，较新的模拟或命令不会被它标成已保存。界面显示“已保存至第N日·时刻”，若当前revision更高则保留“此后还有进展”。迟到回执可更新对应医院的有效提交索引，不能改变另一医院或另一次加载会话的界面、暂停状态和退出动作。

退出、切换和恢复各有一个当前操作标识：先停止接收新的经营命令，排空此前已接收命令后冻结目标revision，再经串行写入器写本次检查点。正在写的较早自动/手动保存仍正常完成，但其回执不能替代本次检查点。仅匹配当前操作、医院、加载会话与目标revision的成功回执允许离开。取消退出立即撤销离开意图并保留原医院暂停；此后完成的检查点仍是有效保存，不再触发关闭。重试只替换失败请求，不同时启动第二个写入器；15秒是提供取消与导出的界面阈值，不是将未知结果判成失败或成功的存储超时。

未提交的房间、摆放、改建和排班草稿属于当前医院的编辑会话；Ctrl+S只保存已确认世界，不把草稿转成付款、工单或排班。普通切层与收起面板仍保留草稿。离开医院时若有草稿，在原退出流程中一次显示“保存已确认进展并舍弃草稿／返回编辑”，不能先保存后才悄悄舍弃；选择保存不会执行草稿。保存失败、取消退出或目标医院载入失败时，原世界与草稿均保留。成功离开才释放草稿，重新载入只恢复已确认事实；已经确认的待改建安排属于世界，正常随检查点保存。

退出游戏先暂停、排空已接收命令并写本次检查点，匹配成功后关闭当前世界。切换到另一座医院时，同样先完成原医院检查点，但继续保留暂停的原WorldState与编辑会话；保存成功只满足离开的前提，不代表目标已能接管。

目标从所选完整保存点建立独立候选，完成内容/格式、哈希、全部实体引用与业务不变量校验，并恢复原必要索引、身体及临床占用，准备好初始可操作视图，才具备切换条件。所需场景资源沿原按需加载规则，不预载全部楼层；尚未就绪的候选不接受经营命令、不推进模拟tick、日结、自动采购或任何随机流。原医院仍是当前会话，界面显示正在切换与真实进度，不把目标的部分场景当作已进入的医院。

就绪后再次核对原当前离开操作与来源医院会话，在同一主线程发布边界切换活跃WorldState、新加载会话、输入目标和视图绑定。目标默认暂停；成功发布后才释放原世界与已确认舍弃的草稿。失败或发布前取消只丢弃候选并结束本次切换，原医院保留原tick、已确认事实与草稿且保持暂停，可沿原入口继续经营。旧保存回执仍只更新对应提交索引；已取消操作的迟到加载或资源结果只回收自身引用，不能激活旧候选、清掉当前草稿或恢复另一医院的速度。

切换期间按原资源规则计算所有仍活跃的原世界、候选、索引、保存冻结副本、解码暂存及新旧显示资源；原检查点副本只有在串行写入器确认不再使用后才释放，实际未释放的字节仍计峰值。目标分配过程中资源不足时安全停止候选加载，保留原医院，不能先销毁来源来假装满足预算。失败后的候选引用也要实际退出后台工作及显示绑定后才停止计量。原快照格式、提交/回执和资源准入公式保持，切换操作与加载会话不保存为医院事实。

恢复旧保存点先保存当前世界为检查点，再载入目标并以新的sequence写一次恢复后检查点，使下次“继续”指向恢复后的世界；任一步失败保留原会话，不自动退出。

保存失败仅允许重试、继续当前医院、导出到其他目录；退出仍未保存时需明确“放弃未保存进展”确认。文件被占用、磁盘满、权限拒绝、目录失踪都需映射可行动文案。

## 8. 备份、迁移与删除

.oghbackup为ZIP，允许且只允许manifest.json、hospital.sqlite3和可选thumbnail.png，文件数≤3；manifest≤64KiB、缩略图≤256KiB。导出的独立SQLite只含所选完整保存点，通过SQLite连接读取和事务写入临时数据库，完整校验并关闭全部连接后再打包，不包含活跃回滚日志。备份清单另持有database_bytes与database_sha256，内部世界清单继续验证world_bytes与world_sha256；数据库与压缩包不设32/64MiB固定总量门槛，按真实资源预算准入。拒绝重复条目、绝对路径、..、反斜线逃逸、符号链接、加密条目及单条解压比例>200:1。原生导出遇到压缩率超过该校验边界的合法数据时，对该条目采用存储模式，不生成自己无法导入的备份。

先读取有界manifest与ZIP元数据并检查白名单、实际包大小、条目声明及数据库/世界字节数，再分段解压到应用生成的唯一pending文件；不使用包内路径创建文件，不一次把整个包载入内存。每段累计真实解压字节、哈希和实际资源使用，超过声明大小、资源预算或比例保护立即拒绝，未完成临时数据不能成为提交。解压后先核对独立数据库实际大小、SHA-256、结构版本和所选保存点身份，再按分段解码完整世界。世界DTO的JSON增量解析限制嵌套深度64、单字符串UTF-8最多64KiB，字段仍按快照schema逐一验型；无界医院表现为更多合法实体记录，不是更深的对象套娃或巨型单字段。实体引用、随机流与所有临床/资金不变量全部验证后才建立候选世界，不能用看得见的楼层代替全世界校验。

资源预算以world_bytes为输入，初始估算额外内存=4×world_bytes+64MiB，须不超过操作开始时实际可用内存的一半；一般保存暂存磁盘需求=3×world_bytes+64MiB，备份导入/导出以max(world_bytes, database_bytes)替代该磁盘公式的world_bytes，目标卷需有对应可用空间。这是待实现压测校准的保守估算，不是内存安全证明；读写和实例化过程中继续按实际分配检查并保留取消入口。资源状态变化时安全结束本次未提交作业，不删除实体、降低数据精度或覆盖旧记录。一般保存与备份导出同样先检查自己的实际副本与暂存需求，不能只在导入端允许大医院、保存端继续卡32MiB。

导入通过后生成新hospital UUID，只重映射类型为实例ID的字段中的旧医院前缀，禁止全文件字符串替换；定义ID、角色关系与实例引用的相对序号保持一致。跨页引用校验在全部实体可识别后完成，临床收费、工资余数与睡眠时钟原样保留。玩家只看到真实进度、所需空间与可行动错误；不会为增加楼层而被要求切换存档格式。

导入作为新医院，与原医院同名也不覆盖；成功提交新世界后才显示医院卡片。导入期间任何失败清理新pending目录，原始备份和既有医院不动。

schema_version由快照结构拥有，content版本由内容包拥有，两者分别比较。未来格式直接拒绝并说明需要更高游戏版本；旧格式只沿显式的vN_to_vN1纯数据迁移链升级。迁移前通过关闭的独立数据库副本保留完整原提交到migration-backups，迁移结果验证与提交完成前不改变旧医院。首次游戏交付snapshot schema1；设计目录和数值表schema100不是已发布存档schema100，起始布局schema9、临床布局schema5、共享蓝图schema1分别拥有结构版本，版本空间独立。保留schema0测试夹具验证迁移框架，但不声称支持未知历史产品格式。

迁移必须检查病症/机器/资格/故事ID的别名与退休定义、事件handler版本、余额与引用不变量。新增字段的迁移必须明确土地所有权、旧门类型、工资余数、设备工单/扫描时间、任务奖励与补助周期的缺省；不存在旧字段时以旧sim_tick推导下一个未来补助周期，不补发历史钱。迁移也须处理医生职称/能力/课程、排班休息债务、病例方案、手术与床位关联；新增社会性格、患者怒气、评分窗口、已付装修、导诊纠正、谢礼凭据和医护休假须显式迁移；不能把原有付费疗程丢成新候诊，或给所有医生凭空最高外科资格。已进行的治疗使用保存参数；迁移不能重新抽随机结果、重放奖励或按现实离线时长推进。

删除医院为同卷移动到trash并记录删除时间；30天后在下次启动提示可清理，不启动隐藏后台定时服务。恢复放回新唯一目录，名称冲突不覆盖。卸载默认保留整个user://目录；用户主动勾选删除数据时，卸载器也必须先以同一Win32协议取得该实际目录的guard，再删除该目录中的产品资料。被占用时只提示关闭游戏后重试，不部分删除；删除期间一直持有句柄，保留空guard及根目录，不先解锁再递归删除根目录。清理中断或权限失败显示实际未删除项，不把部分删除冒充成功；可重建缓存可清理，失败或随后重生不构成医院资料恢复。

## 9. 性能、显示与安装验收目标

首要性能基准为2026-10-13读取的本机：Intel Core Ultra 5 125H（14核/18逻辑处理器）、Intel Arc Graphics、32GiB安装内存、NVMe SSD、Windows 11 x64，图形驱动31.0.101.5382；Arc当前报告2880×1920显示模式；原2560×1440保留为独立对照窗口。硬件事实只是一份参考记录，不等于游戏已通过性能验收。数值与采样条件由balance.performance_targets拥有，负载由performance_reference拥有；以下表格是该合同的阅读表示。

Oray与MuMu虚拟显示设备不是本机验收显卡；实测须记录游戏实际使用的渲染适配器。WMI报告的128MiB AdapterRAM不代表集显全部可用图形内存，不拿它当显存上限。主要验收在交流供电下记录真实电源模式与后台负载，不修改系统电源计划或以关闭所有日常应用制造通过；驱动、显示模式或硬件更换后更新记录并重测。

| 档位 | 目标设备与设置 | 通过标准 |
| --- | --- | --- |
| 本机主要目标 | 上述Ultra 5 125H/Arc/32GiB/NVMe；2560×1440界面、标准画质、三维75%（1920×1080）；160角色四层共同负载 | 1×和3×按本节样本与操作覆盖规则采集；P95帧≤16.7ms、P99≤25ms、普通帧最大≤50ms；模拟步P95≤10ms、P99≤15ms、普通最大≤30ms；真实模拟速度达到所选档位的99%以上 |

模拟步预算采用`sim-frame-budget-v2`：主线程完整步占帧目标的60%，其余40%预留给界面、场景投影、渲染提交和其他工作。按整毫秒向下取整，16.7×60%得到P95预算10ms，25×60%得到P99预算15ms，50×60%得到普通最大预算30ms。60%属于本项目的工程分配策略，来自明确余量假设，不是社区通用比例或实测通过证明；完整step的各指标分别验证，完整实际呈现帧另行采集，不把模块分位相加。原4ms缺少这一分配依据，历史采样保留原阈值和原结论，新标准只能作为另一次显式评估。

容量提前准备不要求把此前已经完成的后台累计CPU时间重复加到日界某一步，但准备期间的全部呈现帧、CPU竞争、资源和推进速度仍计入经营负载。完整步从开始执行到真正完成，以单调现实时间计时；发生跨帧续接时，日界补算、校验、提交和待结果间隔都包含在同一步内，另列主线程实际执行时间。等待不是主动暂停或载入，不能从原速度分母或完整步样本删除；即使窗口保持流畅，步耗时或速度超标仍判未通过。既有数值上限不变。
| 原生清晰度追加样例 | 同机、同负载、三维100%（2560×1440），UI100%及200% | 独立记录帧耗时、图形资源和症状可读性；不以此结果替代默认75%档验收，也不宣称尚未测得的60fps |
| 最低兼容参考 | Windows10/11 x64、i5-8250U级、8GiB、UHD620级OpenGL3.3、SSD | 1280×720低画质、160角色、1×/3×，P95帧≤33.3ms；属于另行验证的兼容性目标，不代替本机主要目标 |
| 响应 | 本机、主要目标设置 | 点击至预览更新P95≤100ms；最大院区房间预览P95≤200ms；正常选择、文字输入与切页保持响应 |
| 保存恢复 | 本机、160角色基线世界 | DTO复制主线程P95≤25ms，保存总时长≤2秒，载入≤5秒；连续自动保存无跨秒卡顿 |
| 内存/包体 | 本机、160角色基线世界 | 工作集目标≤2GiB；共享图形资源目标≤512MiB，合计可见/空闲/加载副本及渲染目标；安装体积目标≤2GiB、上限4GiB |

320/640角色和10000空结构楼层是递增负载样例，帧耗时与真实模拟速度仍以本机主要目标为优化目标，不能把更大医院自动降为只需静止画面。各样例保留实际临床、排班、护理、装修、活动与跨层任务，记录达成情况及主要成本；未达标时优化查询、共享、LOD和实际显示预算，再按同负载复测。至少64MiB/128MiB实际世界文件另测保存耗时、复制峰值与导入资源，不用基线2秒/2GiB目标拒绝大医院。超资源只阻止本次无法完成的操作并保留世界，目标数字不是人数或楼层硬上限。

三维比例只有100%、75%和约67%三个明确选项，按窗口实际像素缩放并取最近偶数尺寸。界面文字、按钮、头像、选中轮廓与必要状态按原生窗口分辨率绘制；世界拾取用实际镜头与视口坐标转换，不因缩放点错一格。默认75%在参考窗口得到1920×1080三维画面，约67%为1706×960；1280×720窗口仍保持原界面可读性规则。比例是本地显示偏好，不进医院模拟哈希，不改变身体、路径、症状、治疗结果和时间；不会在游戏中悄悄跳档或因帧率低删去病人。

P95/P99使用实际呈现帧间隔，CPU、GPU与模拟工作的各自耗时作为成本记录，不能把并行CPU/GPU耗时相加伪造成实际帧长；平均fps也不能替代尾部帧。实际刷新率、帧率限制与垂直同步一并记录，WMI的整数刷新率标签不当作精确采样结果。稳态同时测真实模拟tick，速度比=窗口内实际完成tick×0.1÷（有效现实秒数×所选速度），要求≥99%；玩家主动暂停及系统休眠分段标记，不拿暂停时的高帧率凑样本。正常自动保存、互动高潮与施工仍包含在负载采样；首次启动/载入的明确加载阶段另外测，不能剔除普通经营卡顿。医院已经运行后的平移、变焦、切层、冷资源绑定和旧视图退场均计入普通帧，不因界面显示资源准备中就排除卡顿。无证据的设备相当关系与硬件参数不证明帧率；只在完整游戏与正式资产上确认通过。

责任与容量边界：本地设置拥有显示选择，表现系统使用真实视口与共享资产实现相同现场，WorldState及临床/经济规则继续拥有医院。512MiB和2GiB用于成本核验与缓存/LOD调校，不作为合法演员、病症或楼层的准入额度；真实资源不足仍按原操作失败与世界保留规则处理。额外成本为独立三维渲染目标和显示切换，必须计入资源及响应采样。本机正式资产下的长帧、图形分配、集显带宽、热机状态、输入拾取与3×实际速度尚未验证，硬件记录与静态算术不能替代这些证据。

Godot官方系统要求只是简单项目基线，不能替代本游戏压测。[引擎系统要求](https://docs.godotengine.org/en/stable/about/system_requirements.html)。低画质减少影子、粒子、动画更新频率和纹理LOD，不减少模拟病人、不跳过事件或改变经济。

固定导出Windows x86_64 Release，独立pck避免大型exe内嵌资源限制。安装到%LOCALAPPDATA%/Programs/oddly-good-hospital，主程序oddly-good-hospital.exe，默认无需管理员权限，开始菜单快捷方式和卸载入口显示“怪好的医院”。升级要求旧进程关闭，替换程序资源，首次打开时再按保存协议迁移；不直接在安装器里编辑world.json。

exe、pck、原生扩展声明及其Windows x86_64库构成同一发行版本的完整安装单元。安装器先将新版完整暂存并核验随包版本、文件清单和完整性，暂存核验成功前不替换旧安装；开始替换后保留已确认的完整旧版，直到目标单元和快捷方式、卸载信息均核验成功。此后才报告安装完成、提供启动并清理本次旧版副本。暂存或替换失败须显示具体失败及恢复结果，不能把部分复制当作成功；医院、设置、照片和自制蓝图不进入程序替换或回滚范围。

普通失败沿本次安装记录恢复完整旧版；恢复仍失败时保留完整副本和修复入口，不启动半套程序。强制结束或断电后的受支持恢复入口是重新运行同一离线安装包：先按原占用协议确认旧游戏已退出，再核验本次暂存、旧版副本和目标状态，恢复完整旧版或完成完整新版后才报告成功。首次安装没有旧版可回退，失败保持未完成，重新运行安装包继续完成。安装进度只属于安装器，不进入医院快照；反复修复不迁移或清除医院，不累计永久历史版本。该规则约束发行结果，不假定多文件替换具备整体原子性；安装中断及恢复能力仍须在实际发行包上验证。

内部验收包可未签名；面向公开分发的exe与安装器须使用发行主体的代码签名证书并验证签名，证书采购与保管属于发行准备，不阻碍本地实现。应用不自动下载更新，版本页显示当前版本和发行说明入口；主动打开外部链接前显示其用途。

安装验收覆盖中文用户名、含空格路径、非管理员账户、离线启动、覆盖升级、卸载后重装恢复医院；在首次解包、资源包复制、原生库替换和安装入口更新阶段分别注入普通失败及强制中断，重跑同一安装包后只能确认完整旧版或完整新版，保留原医院资料。崩溃日志仅本地轮换5份、每份2MiB；诊断导出由玩家主动触发，不后台上传医院名称或存档。

### 基于本机配置的负载可行性判断

本机具备承载完整产品的合理硬件条件：160角色、四层医院、默认75%三维有可行性，实际帧率尚未验证；640角色密集近景属于高风险工况，不能承诺稳定60FPS。这一判断来自当前硬件与现有负载预算，不来自验收目标本身。balance_reference.machine_feasibility拥有说明算例，统一阅读页从原模型预算、目录数量和本机记录生成几何、提交、姿态、纹理及保存容量表；它不参与游戏调度、不添加人数/楼层限制，也不把估计结果写入世界。

Ultra5 125H的14核由4个性能核、8个能效核和2个低功耗能效核构成，Arc为7个Xe核；官方最高CPU/GPU频率不是本机持续负载频率。现有模拟和许多显示准备仍在主线程，不能把14核当14倍模拟性能。SMBIOS本次报告8条各4GiB内存记录，Speed7467、ConfiguredClockSpeed6400、DataWidth64；它们不证明512位总线、实际通道带宽或GPU可用显存。核对时OS可用物理内存约16.26GiB，这是一时快照，实际保存/加载继续检查当时资源。[Intel125H官方规格](https://www.intel.com/content/www/us/en/products/sku/236848/intel-core-ultra-5-processor-125h-18m-cache-up-to-4-50-ghz/specifications.html)。

CPU数量级：原0.1秒固定步下，3×的每次全演员遍历分别为160人4,800次/现实秒、640人19,200次/现实秒；这只是一轮访问量，不是全部工作指令或耗时。把10ms步预算全部均摊，160/640人每演员分别只有62.5/15.625微秒，真正可用量还要扣资源调度、查询、结算和日界工作。路径额度在3×下分别最多240/960次请求/现实秒；假设每次触达整个96×96层面，节点触达算例约221万/885万次/秒，尚未计边、回调、图修补和跨层搜索。缓存命中与稀疏相关重查因此决定CPU成本，不能因只看1F就省掉其他层医疗。三班名义容量涉及原完整资源/岗位优化模型，其生产求解成本仍未证明，是独立的主要风险。

GPU数量级：假设160人、128服务位、1,200道具均分四层，当前层按常用模型上界为396,000三角面；把全部160人和同一批设备/道具集中到一层为1,584,000，640人常用/近景分别2,304,000/3,648,000，均未包含墙体、楼板、附属效果或阴影重复提交。它们是把对象全部当可见且达到该档预算的说明上界，不是实际场景面数。原单视图1.5M目标在分布医院中有空间余量，密集院区必须依靠已有视野裁剪、真实LOD及资产复用，不靠减病人或改医疗结果。

提交成本比单看三角面更敏感。只有在每种常用材质恰一Surface、每道具一Surface、没有合批和额外pass的假设下，四层均分当前层基础提交为476次，同层160/640为1,904/2,864次。材质数量不等于Surface数量，阴影、透明与附件可能继续增加，实际重复网格合批又可降低；这些不是实测draw calls。原400调用目标要求正式资产和现有合批路线真正生效，不能只把角色做成低模就认为Arc会流畅。

显示与姿态成本分别估算：2880×1920默认75%得到2160×1440三维，按60个目标帧/现实秒，三维输出位置数合计约1.87亿/秒，不等于实际片元调用；空背景、提前深测与清屏优化可减少真实工作，透明叠加、材质计算和读带宽另计。假设一份RGBA8颜色、32位深度及原生RGBA8输出，原始目标数据量约44.82MiB；若每帧各完整写一次，约2.82GB/秒，这只是部分写入量，不能当真实总带宽或FPS。640个40骨近处绑定每现实秒19,200次姿态采样，远处9,600次；同一相容组的原完整骨矩阵页按60次/秒全页上传算约78.64MB/秒，双份页约2.5MiB；真实多组各自的页宽/尾页与副本需另算，CPU求值、顶点读取、缓存与同步仍未知。矩阵原始量本身不是内存大头，密集求值和驱动提交更值得优先优化。

内存与保存容量：假设每个家族一张1024RGBA8完整mip图、六医疗主体各一张常用图、八装修材料各一张同尺寸图，原始纹理量约144MiB；六主体全部使用2048特写图时约240MiB。再加上述显示目标和640骨页双份，说明量约191/287MiB，未计网格、字体、阴影、其他贴图、实际对齐及副本。在原512MiB目标下有合理安排空间；若80种族各自常驻独立1024图且六主体全部特写，单这些纹理已约597MiB，原目标就不成立。现有共享图集、按需绑定和缓存回收必须落实，80种居民及其外观仍完整保留。

64/128MiB世界文件按原保存估算需要320/576MiB额外内存及256/448MiB暂存磁盘；相对于本次约16.26GiB可用内存，没有明显容量门槛，但这不保证2秒保存或25ms复制。NVMe只说明设备类型，JSON对象构造、主线程一致快照、编码、哈希与最后提交仍可能成为耗时主因；双医院切换的源世界、候选与正在退场资源继续同时计入。空高层仍采用原稀疏高度/实际对象表示，10000空结构层不是10000份常驻地图或模型。

变更面仅为本机事实补充和同源负载测算。结论为基础规模硬件可行、共享/裁剪/合批与查询复用是必要条件、密集近景和完整容量求解有高风险；CPU毫秒、真实GPU帧率、散热功耗、具体资产与保存耗时保留未验证。没有凭配置生成虚构FPS，没有降低原目标或缩减完整游戏功能。

### 正式Release的资源验收口径

performance_targets.resource_measurement只拥有验收资料的度量来源与解释，2GiB工作集、512MiB共享图形资源以及原缓存目标继续有效。正式采样使用实际安装的Windows x86_64 Release目标进程；编辑器、调试包和采样工具进程分开记录。Godot部分内存监视器在Release不可用，其0值不表示游戏占用为0，也不能用节点数或安装包大小代替驻留。[Godot Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html)。

进程工作集通过Windows进程内存计量或等价OS工具取得，WorkingSetSize与PrivateUsage分栏：前者是当前工作集，后者是私有内存提交量，不能互换名称或只取更小值。记录同一采样工况的实际观测峰值与采样间隔，以及进程生命周期峰值；后者不自动等于本次采样窗口的峰值。轮询可能遗漏短暂分配，不能把已观测最大值写成未观测时段的严格上界。保存复制、冷绑定、切层和旧资源退场等已有短时工作须补充其实际分配/峰值证据，证据不完整时保留缺项。[Windows进程内存](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex)、[GetProcessMemoryInfo](https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-getprocessmemoryinfo)。

资源明细沿已有资产、缓存和视图的实际所有者归集，区分payload_bytes原始数据量、allocated_bytes已确认完整分配、engine_estimate引擎估计与os_residency操作系统驻留视图。字节依据、实际资源/分配身份、共享引用及仍未释放副本一并说明；必要原生分配、对齐或后端驻留不可取得时写明未核实，不填0，也不把算例字节当作完整测量。报告可读取原资源元数据和采样工具证据，不建立另一份参与游戏的资源账本、缓存或内存准入状态。

共享只读资源按实际分配ID计一次，六个角色引用同一张纹理仍是一份分配；相同内容指纹若实际生成三份纹理必须计三份。可见、空闲、加载暂存及尚未释放的旧实例/纹理/骨矩阵页全部沿原预算计入，隐藏节点或解除显示绑定不证明已经释放。原生UI/字体、渲染目标、角色和设备资源及上传暂存继续各取原真实口径；音频PCM只计原CPU工作集。OS与引擎对同一集显分配的重叠视图并列，不直接相加成总内存，也不因无法逐项匹配就宣称全不重叠。

RGBA8纹理的设计算例说明数据量与分配身份：1024×1024单层原始量4,194,304字节，11级完整mip的原始量5,592,404；实际后端格式、对齐与额外副本另计。六引用同一完整mip数据仍为5,592,404，三份实际数据副本为16,777,212，不能分别按引用数放大或按同指纹合并。这些原始数据量不证明真实GPU驻留、图形目标或工作集已通过。

变更面只覆盖正式包资源验收和离线算例，不增加游戏功能、世界状态、实体上限或运行时镜像账本。现有所有者的完整分配证据、Arc集显驻留、瞬时峰值与采样开销仍须正式资源和实际发行包验证；硬件容量、调试统计或静态格式计算不能代替这一结果。

### 真实帧间隔与统一统计口径

performance_targets.capture拥有采样完成条件，其statistics拥有统计合同，性能阈值保持。帧样本取目标游戏进程实际显示的相邻不同游戏帧之间的单调现实时间间隔；显示器重复刷新同一帧不计新帧，未显示的提交不能变成一条零时长帧。CPU/GPU阶段耗时和引擎帧回调另作定位成本，不能冒充显示变化。Godot的TIME_FPS按一秒统计已渲染帧数，不提供尾部间隔；Windows采样可用经实际后端核验的PresentMon呈现追踪或等价工具，记录工具版本、实际进程/渲染器、字段含义及丢失情况。[Godot Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html)、[PresentMon](https://github.com/GameTechDev/PresentMon)。

预热用于完成首次加载、显示绑定和实际业务缓存准备，不为每个参数组合固定等待60秒。准备完成须有实际资源状态、已执行工作与连续帧/步记录支持，并记录预热耗时；同一运行单元的热机状态可以复用，冷启动另测。运行中的冷绑定、驱逐重建、切层与切院仍是被测操作，不能重新标为预热以删除长帧。

正式帧分位数至少采集minimum_frame_samples个有效完整间隔，模拟步分位数至少采集minimum_step_samples个实际完整步，当前均为1000；P99因此至少保留约10个尾部样本用于观察，这不是独立样本或统计置信保证。1×采满1000步约需100现实秒，3×约需33.3秒，实际耗时以真实完成记录为准。每个工况还须完成其对应操作覆盖，不能只凑帧数。只验证显示边界时不重复独立模拟分位验收，但仍记录全部真实步、速度及资源，样本不足的指标不宣称通过。

采样在满足相应样本量和操作覆盖后结束，不统一固定为600秒。结果接近阈值、分段趋势或重复结果不稳定时，追加独立窗口并分别列出结果及延长依据；存在未解释差异时保持未完成。已发现的失败保留，不能靠延长窗口或混入轻负载稀释。诊断中已复现超标即可停止该次定位采集，优化后重验受影响工况；诊断短测不作为正式通过证据。样本量、操作周期和真实波动共同决定耗时，不通过加速模拟或跳过业务压缩现实时间。

正式覆盖按默认经营、增长后的模拟查询、最大人数密集现场、宽层/高层、显示与文字边界、资源切换、保存恢复组织，不取窗口×人数×比例×速度的笛卡尔积。160人默认四层的1×/3×和640人密集现场的1×/3×分别验收；320人用于成本校准，宽层160/640与高层640覆盖实际几何差异。相同场景已经提供对应人数、密度、速度和资源证据时复用一次采集。不同工况只复用其确有证据的共同责任，不由像素量大小推定另一个组合必然通过；出现非单调成本或参数交互时追加相关组合。

自动保存、施工、换班/日界、切层、切院、冷暖与驱逐、输入/最大房间预览和64MiB/128MiB保存恢复按对应操作覆盖取证，不要求在每个显示组合重复等待。可以从合法的操作前边界开始，被测工作真实执行；实际发生的普通长帧仍保留在该工况帧总体中，另列操作耗时与峰值。长时泄漏、持续热机与经营稳定性独立执行验收规格的两现实小时场景，不乘到各参数组合。

同一工况中的完整普通间隔按毫秒升序排列。N为实际有效间隔数，P95取第ceil(0.95×N)个，P99取第ceil(0.99×N)个，序号从1开始；最大普通帧取同一总体最大值，仅表示该窗口已观察的最大值。平均FPS如需报告，用1000×N/完整间隔毫秒总和，不能对逐帧FPS取平均。平均FPS、P95、P99和最大值并列，任一原门槛不满足仍未通过；不删尾部、不取平均百分位，也不以目标FPS乘预定时间代替真实样本数。

采样窗口在预热完成后的实际帧边界开始，记录满足完成条件时的窗口结束点，纳入起点在该窗口内的普通间隔。末尾已开始但尚未结束的间隔继续捕获到下一实际不同帧，保留完整长度；没有下一帧或呈现证据缺失时记录证据不足，不能当0、截到窗口末尾或直接丢弃。真实模拟步数仍只计已记录窗口内完成的tick，继续捕获末尾不扩张速度分母。主动暂停、休眠及原明确载入阶段按真实起止分段；已经开始的日界准备等待按上一段保留，不能因等待期间收到暂停或保存请求便提前截断。日界求解、自动保存、普通切层和资源准备仍是经营负载，不能事后因帧慢改标成加载。

医院负载、窗口/实际三维尺寸、UI比例、速度、电源/后台与采样条件不同就分别成组。每组保留起止、有效帧数、完整区间、原模拟进度、峰值资源、预热完成依据、操作覆盖、停止或延长原因、超标及缺失原因；密集区间单独应用同一统计规则，不与轻负载片段混算以掩盖尾部。各指标样本不足或工具字段不可用时保留缺失，不能由其他进程、监视器刷新率或引擎平均FPS补造。

三个设计算例说明统计的后果：990个16ms加10个80ms间隔，平均约60.10FPS且P95/P99均16ms，但最大80ms超过原50ms；989个16ms加11个40ms，P99为40ms而失败；9,900个16ms与另一工况100个30ms混算可以使P95/P99变成16ms，30ms工况独立统计仍失败。这些只验证算术，不代表已取得游戏样本。

变更面仅为本地验收资料和离线统计算例；WorldState、模拟随机、保存、资源预算及患者/员工规模没有新增状态或上限。实际追踪对Arc/OpenGL显示路径的字段可用性、采样丢失、工具自身开销及正式游戏长帧尚未验证，实际证据不足时保留未通过，不能由静态脚本代填结果。

### 本机当前显示尺寸与实际渲染目标

performance_targets.display_workload_samples同时引用原2560×1440对照窗口与hardware_reference当前报告的2880×1920，三维比例复用原三个选项，界面分别使用100%与200%。默认负载和最大人数密集现场先验证主目标；追加实际两窗口、三比例及两UI档的边界覆盖，包含最高像素下200%界面、约67%拾取与文字/列表布局。各选项均取得实际证据，但不与所有人数和速度相乘；性能、资源或可见范围出现独立差异时追加相关组合并分组判定。沿用原帧、真实模拟速度、响应与资源目标。WMI模式不是实际窗口、渲染目标或已通过证据；采样记录实际输出像素、三维分配尺寸与UI比例，不能把Windows逻辑尺寸、DPI百分比或虚拟显示模式直接当作渲染分辨率。某模式不能实际创建时保留该项证据缺口，不用较小窗口的结果代填。

按原最近偶数尺寸规则，2880×1920的100%/75%/约67%三维算例分别为2880×1920、2160×1440、1920×1280；原对照分别为2560×1440、1920×1080、1706×960。75%样例的三维像素从2,073,600增至3,110,400，恰为1.5倍；这不是总内存、总帧耗时或帧率比例。长宽比、可见实例、UI布局、阴影、骨架与CPU工作可能各自变化，必须分别测量，不把降低像素视作提高临床吞吐。

Godot4.7提供Viewport.scaling_3d_scale与所有渲染器可用的双线性三维缩放，原生Control界面继续独立绘制；Compatibility不依赖Forward+专属FSR、TAA或纹理偏置能力。使用已选引擎的实际分配和显示变换核验三种选项，内部对齐与额外附件不由算表冒充。世界拾取、概览安全矩形和原生选中轮廓仍从实际视口与镜头转换；缩放、调整窗口和切UI比例不生成另一份医院镜头或模拟位置。[Godot4.7三维缩放](https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html)、[Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html)。

渲染资源按每个仍存活目标的实际宽×高×每样本字节×样本数逐项归集，包含颜色、深度、解析、显示合成、暂存与尚未释放旧目标；纹理对齐、驱动开销和后台缓冲另按实际记录。只有用于说明的单色RGBA8加单份32位深度算例采用8字节/像素，75%时两窗口分别16,588,800与24,883,200字节；它不包含原生UI、MSAA或其他目标，不能当作游戏全部图形内存。所有真实分配仍计原512MiB目标及工作集；同一集显共享分配沿原归集规则避免重复相加。

变更面为本机验收样例、硬件参考记录和离线像素算表；默认画质、三维选项、实体数量、医院保存与医疗经济规则保持原合同。正式资产下的缩放质量、实际目标分配、调整窗口瞬时峰值、输入一致性及高分辨率长帧尚待实测；API可用与算术自洽不证明流畅运行。

### 大面积与高层的联合采样

performance_targets.spatial_samples增加完整同层面积与高层组合。宽层样例使用九个已购地块的96×96实际面积，把64房间、128服务位、1200道具放在同一层，分别以实际160与640角色采样；布局须具备真实通路、门/伸展/身体适配和合法岗位，不能用子网格、装饰分片或虚拟角色凑数。高层组合以10000层连续结构、实际640角色和第1/10/1000/10000活动层验证切层、同XY隔离与按区间保存，实际业务对象合理分布，其他空层不展开。

在原交流供电、标准画质、75%三维与原生UI下，按本节代表场景和采样完成条件验证；已经覆盖的密集现场不重复采集。轨迹包含近景工作区、全层远景、双轴平移、反复跨越细节门槛、活动层跳转及加载中局部改建，分别记录冷缓存、热缓存与主动回收。逻辑实体数、可见实体ID、显示实例/片段、请求与淘汰、实际主线程绑定/释放耗时和资源峰值分别记录，不能把低绘制调用数冒充医院人数减少。

密集区间须达到目标人数90%以上，即160档至少144人、640档至少576人，帧和步的相应分位验收复用capture中的最低样本要求；分离区间独立统计，不拼接时钟制造跨段帧。缺少对应样本即该指标证据不足，不能用后半段空院平均替代；患者照常治愈或离院，不为测试强行锁住角色。缓存/细节/镜头序列变化时对照相同种子、命令和步数的世界摘要、预约与医疗结算，主世界事实必须一致。当前只有合同与静态算术，未取得实机帧率或资源测量证据。

## 10. 临床资源事务与确定性

患者性格、怒气与表达决定当前服务工作量，劳累决定员工速度，运营科室专长可减5%操作工时；所有倍率在Readiness预计与实际开单时使用同一规则对象，不能UI少算住院或休假覆盖。

候选方案用同一Readiness查询返回研究、人员、空间、设备、床位与治疗包原因；报价带world_revision，不占资源。开始准备按票号和准备ID原子锁互异人员、患者、设备、床位、护理名额、适配区域及本次治疗包数量。失败全部回滚；30秒准备过期释放全部未承诺资源。到齐并通过最终检查才创建TreatmentAttempt、扣实物和抽一次结果；此时没有第二笔耗材现金支出。恢复、转床、安全接续引用同一Attempt，不能再次领包。

概率以整数基点保存、工时以tick保存，方案费用乘数向上取整。医生性格评分使用有界定点数，按得分、效果、总时长、方案ID排序。预计团队用同一组实际资格计算概率，不把不同人的能力最大值分别拼合。新增方案只参加下一次会诊，当前TreatmentAttempt保留参数。

ClinicService负责门诊执行、SurgeryService负责手术与苏醒、WardService负责恢复与查房，它们均引用同一TreatmentAttempt；没有第二份承诺随机结果和待收费用。设施使用费在实际服务完成时以owner_id+component唯一键入账；治愈费无住院时在成功治疗完成后、住院时在成功查房后结算。只有一个final_settlement_id可提交治愈事实、治愈费账目和医生病例累计，不能阻止失败尝试已完成设施的独立收费。失败尝试先恢复再重选或转诊，不能同时有两个活动尝试。

员工任务锁优先于排班意图。排班修改先落模板，正在安全任务中不释放员工；结束后算越过可用窗口的时间形成补休债务。日工资逐tick查询当时职称费率，晋级不重写既往累计分子。每床最多一个活动住院或开术预留、一个护士不能同时承担手术锁与病区覆盖、每个员工最多一个执行任务，加载和每次资源提交后均检查这些不变量。

手术区的外部移动与内部演出分开：患者先真实走到适配候位，再按已验证承托姿态进入术台；术中不会把台面变成普通可穿越地块。四套临床布局作为几何夹具，不能用面积合格代替人员和器械位置可达。


## 11. 多层、到访与招聘的状态合同

[随机来客、多层与招聘](11-growth-arrivals-recruitment.md)拥有新增状态的完整字段与边界。楼层数不设上限，每层最多96×96格，按地块高度和稀疏布局记录，实际实体随已建设施、人员和就诊需求增长，不设全院固定数目上限。路径在层内平面图之间经显式连接边行进，连接边的方向、身体净宽高、舱内组合和服务时间由TransitService提供；AStar2D仍以明确节点ID查找，不能按相同XY匹配其他层。

FloorView只显示一层，其他层只保留模拟事实。图缓存和移动请求额度统一遵循本章§6与balance.pathfinding：按实际内存回收缓存，按真实在院人数分配全院FIFO处理额度。跨层段按竖向设施区间查询，不能预建整院稠密图；当前查看楼层不改变预算或队列。任务行程采用基准通行成本；当前队列估时独立且可以未知，实际到齐不能由预计替代。手术/需住院治疗与其床位必须同层，界面和接单都用Readiness验证。

无楼层上限的区间保存、按需图和高层验证遵循新增经营规格§9。初始与临床布局夹具明确floor_id=floor:1；旧夹具迁移时只补地面所属，不复制任何角色。保存包括所有层、乘梯中唯一Actor位置、候诊评估阈值、日计划、简历/寻访、当前活动及12条随机流；切层不重新初始化任何业务模块。

交通报价是只读值，包含quoted_tick、相关修订、当前组/目标/连接、可达与可估计状态、分段预计及条件说明。业务命令保存实际组、目标、连接和预期修订，处理时复核；quote_id或界面缓存不成为恢复/重放输入。读报价不生成实体序号或叫梯票。连接队列前缀按实际入队/撤销、指派、阶段、站点与工作模式修订重建，当前实际余量直接组合，不每tick全量重建长队。前缀保留实际起终层与累加成本，不生成任意两站矩阵；无固定截断数，空层没有虚构票。身体、通路与出口复核仍取原空间事实，渲染帧不完成通行。

## 12. 医护成长与主体设备的一致性

错峰短休由原Staff任务调度拥有：保存休息原因、关联工作池和最近实际休息结束tick；同池提前休人数从当前休息员工派生，不另存可修改计数。原能量阈值、补休、长休与病房交接各保留唯一事实源。资格、实际位置与班次变化后重新检查可接替者，不把推荐替手写成已经完成的覆盖。非医生待岗娱乐复用阶段④原调度的无可派工作结论，按诊室互动规格§6复核资格后进入原RecreationSession；不新存闲置计时、娱乐来源或90能量目标。娱乐期间与恢复后的原休息义务仍取Staff、ScheduleState和LeavePlan，不能从当前能量反推。

AbilityService只消费实际完成事实，按role+工作种类映射到本人三能力之一；同原始工作、同执行岗位只结算一次。DevelopmentJob固定目标能力与等级，阶段⑨按“真实课程完成/主动取消→实践门槛→仍未完成而已实操掌握的课程终结”归并，实践上限180，课程不阻止自然升级。自动终结引用原任务的剩余量、实付学费和唯一退款凭据，reason为practice_mastered，不发course_completed；任务只拥有一个终态。Readiness与预测/真正开工共用EquipmentOperation查询，先验证角色、能力、研究与实际操作位，再计算效果；同类设备升级不改变资格门槛。

天赋只调用五种有版本处理器：工作率、门诊成功率、实际服务心情、课程工作量、解冻照护工作量。条件与目标动作有注册表，不能执行任意脚本或按种族写工作分支。课程天赋报名时冻结，工作率每段冻结，成功率Attempt开始冻结，心情原服务完成时幂等结算；Visit只保留天赋已获心情0…5及原事实游标，不新增无限触发历史。

设计目录、数值、布局与快照各自拥有结构版本，当前归属与迁移边界见本章§8。当前数据直接使用六类主体与四能力，不同时保留旧机器目录或旧医护技能字段。发挥率用万分整数，团队平均保留分子/人数，最后概率向下取整至万分点、工时向上取整至tick，阶段内不反复舍入；病房按定点速率积累未满一工作tick余数并保存。

## 13. 实际库存、清洁和伸缩占地的事实归属

| 所有者 | 保存事实与唯一职责 |
| --- | --- |
| SupplyStock | 当前医院SUP01实存整数、自动补货开关、援助采购日及当日使用次数；可用量由实存减有效准备预留计算，不另存一份可修改可用数；SupplyUsage仅拥有当日领用累计、上一结算日用量及轮换日号，C/R/T/B从设备与财务派生 |
| PurchaseOrder / Ledger | 稳定采购命令ID、数量、冻结单价、医院实付/直接代付及成交时的代付来源、入库完成凭据；扣款、入库、订单完成同一事务 |
| ClinicalPreparation | 本次方案冻结所需包数和未消费的预留；取消/超时只释放，不能同时在Stock另存一份预留清单 |
| TreatmentAttempt | 已领用数量、唯一领用凭据及原结果/时长/收费；开始的原子事务同时扣实存，后续执行者只引用它 |
| SupplyShortage | 本院缺货事件序号、实际受阻请求及各参与医护累计tick、已结算阈值；活动请求来自调度，结束后归并最近原因 |
| Staff | 罢工请求/安全交接状态、关联缺货事件ID、复工截止tick；压力仍只存原stress_milli，已解决标记不重复拥有库存 |
| DirtPatch | 地面CellRef或垃圾桶引用、生成tick、来源凭据、冻结工时、剩余量、贡献、预约；没有expiry，唯一删除原因是清洁员完成 |
| AdaptationReservation | 目标设施、使用者/会话引用、冻结身体与姿态、旋转、展开包络/占用格、岗位锚点、阶段及释放条件；门开口也由此恢复 |

阶段①执行已授权采购与自动补货，②释放过期准备并更新拓扑，④原子准备/适配，⑤按实时占用移动，⑥开工领包或实际清洁完成，⑦按实际缺货受阻时间更新压力和抗议，⑨提交统计。用户暂停时的采购仍可在命令边界完成，等待、清扫和复工不推进；离线不补货、不刷新援助、不清垃圾。

恢复先加载库存、有效准备、已开工Attempt与适配占地，再重建派工和寻路。拒绝负库存、预留总数大于实存、重复领用、占地互撞、超墙段、缺失使用者和仍有人却已收缩等不一致；不通过自动补库存或删除障碍修复坏档。展示暂停或切层不释放伸缩资源，临床结束须先真实离位再收缩。基础布局文件只保存收起尺寸与示例引用，不能把示例预留当成已建世界。

功能物件的equipment_class仍描述既有设备类别；是否产生磨损、随机故障、事件磨损或保养，唯一取equipment.maintained_definition_ids。集合外物件不建立condition和维修工单，不能因统一class查表又给椅子抽故障。新增包定义须显式加入维护集合才能参与；维护范围和伸缩能力相互独立。

员工公共设施意图、区域等待沿Staff原任务保存，原空间占用事实登记到场后的真实使用。个人员工床的自动固定分配与唯一长期归属执行[个人床规格§6](../specs/26-10/2026-10-18-public-facility-area-use.md#6-员工床固定归属与自动分配)，与本次睡眠预约分离，其他员工不能借用；专用工作位继续沿其预约职责，不被公共队列分配。起始布局的staff_work_areas只定义公共区域中的员工工作角，不生成新房型或隐形墙。建造与选位排除患者等候、活动配位和临床操作冲突，行走仍读取实际物件与展开占地。员工专用房间的进入权限属于Room，任何权限变更不得困住现有角色。

WardHandoff沿既有员工任务保存接班者、可选离班者、同病房本组床位引用、剩余5秒和完成凭据；完成时原子转移仍有效的覆盖。原工作段准备凭据不能代替它，独自核对原记录不产生两人合作事实。当前人员、床位和任务是唯一来源，不另存病房“虚拟可用护士数”。

ArrivalPlan保存真正冻结的三班名义能力、N、三个班机会数、时刻算法/种子与消费游标；新日arrival-load-slot-v1从已保存班数派生时刻，arrival-slot-v1继续读取其原整日冻结计划。UI、编码、恢复不推进arrival，不从当前排班重分活跃日。ArrivalCapacityProjection为资源工时/病例比例只读结果，参考分配不写Staff、准备、库存或预约；一次物理资源时钟只给一次预算，现有负荷从原所有者读取。求解器/索引/冷热缓存不保存，相关输入不完整不能输出伪容量。公式与完整资源约束归随机来客规格§1.1.1/§1.2，首次快照仍schema1。

### 容量准备任务与跨帧续接

容量生命周期和未就绪时的业务行为归随机来客规格§1.1.2。主线程继续按原固定阶段唯一写入WorldState、消费模拟随机流和提交日计划。工作线程只接收依赖一致的不可变输入，维护只读资源图、需求系数和求解候选，返回带医院会话、目标日及输入依据的结果。源数据仍归原业务所有者，派生值可从事实重建；提取和复制输入同样受主线程时间与总内存预算约束，不为启动后台任务深拷贝整个医院，不维护第二份预约或预算账本。

运行控制维护当前固定步或命令边界的续接位置、已封闭容量输入及候选身份；它们只用于完成已经开始的边界，不成为新的医院时间或保存字段。封闭后只允许原边界按原顺序续接，不开放并行经营写入。正常只读查询和渲染读取最近完整边界已经发布的结果，不能在等待期间遍历半步WorldState；尚无已发布投影的新查询保持待更新。日计划提交与当前步结束是两个原有阶段，只有全部剩余阶段完成才发布新的完整步、处理后续命令或取保存副本。暂停中的保持模式命令完成后只发布该命令边界，不借容量准备推进tick。

优先复用[WorkerThreadPool](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)或可复用的[Thread](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html)。独立班次或只读子问题可以并行，同一求解基与可变图由一个任务独占。活跃场景树、共享可变Resource及同一个AStar对象不能作为多线程共享工作区，遵循[Godot线程安全边界](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)。医疗、库存和财务的事实提交仍按固定阶段完成，不按每个业务模块分配一个任意写世界的线程。

准备任务合并相关变更，在安全切片检查失效与取消；实际有用的输入版本才触发更新，普通工作递减复用已有结构和求解基。日界前过时候选不发布，封闭输入后的补算只服务该输入。主线程通过完成通知或状态查询消费结果，不能在界面帧内等待未完成任务或持有覆盖整次求解的锁。完成、取消、失败及会话退出均须回收任务；已撤销但尚未实际停止的任务及其输入继续计入资源峰值，迟到结果只能释放，不能提交到其他日期或会话。

任务未就绪时让出主线程，按§1.1.2保持当前步待续接；等待时间不进入快进累计器，不生成补算步。实际失败与同输入重试保持续接身份，不重复前置命令、故障扫描或日计划抽签。暂停及保存请求以当前步的下一完整边界生效，保存副本不包含运行控制或中间世界；不保存退出按原放弃流程销毁会话并停止接收其结果。

SE04主体固定，access_anchor_policy从实际床边求上下床区，operation_anchor仅为基座示意；SE05/SE06的operator_pose选择骨架姿态，不改变有效身体包络。已求出的岗位坐标仍只归AdaptationReservation，不在Staff或PlacedObject另存一套可修改锚点。实际几何未通过就不能开工或入睡。

采购建议复用原缺货候选和临床Readiness的实际就绪排序，不建立一份预先承诺的“下一位患者”。正常接单资格包括原罢工/整理/休息条件；若没有合法首候选且本事件有罢工参与者，才复用原缺货关闭查询的逐请求最大需要量。候选与门槛只读派生，库存/预留变更重算当前缺量，只有现金或容量改变时重算成交可行性；设备放置、临床、人员和占用变化仍按原Readiness范围使相关首候选失效。不能每帧重做全院候选×方案查询，提交采购仍只拥有医院ID、固定数量和单价。

普通采购与创作基金付款使用原采购订单和Ledger事务：实际成本等于医院实付加直接代付，库存增加与付款凭据同一次提交；资助不进入可花现金，普通购买不消费社区援助次数。报价、目标说明、当前C/R/T/B与纸箱姿态不进世界快照，不持有患者、病例或医护的第二份状态。UI纸箱不改变Stock或SupplyUsage，库存下发后原准备资源束再次按同一公平顺序复核。当前卡片打开、缓存冷热、切层与保存恢复不改变订单或医疗顺序。

自动补货的求值顺序由医院日常§22.1与supplies.auto_evaluation拥有：只用本命令边界的原事实排除数学上确定的零订单，再按需读容量与普通经营保留预算。临床准备继续拥有有效预留，SupplyUsage拥有真实日用量，财务投影拥有应付上界；不另外保存可用量、U或采购资格。跳过订单计算不跳过真实缺货原因查询，原事务仍核验当前值。静态等价校验与真实设备/财务访问次数、主线程耗时分别报告。

## 14. 临床结果投影与大医院

诊断ServiceSession的实际完成及Visit证据、TreatmentAttempt的操作/必要恢复/结算、WardStay的实际照护和查房是结果提示的唯一来源。result_scenes按主体与临床团队§15的键查不可变映射，不能从动画末帧、疗程百分比或开工时承诺但尚未揭晓的结果反推可见结局。awaiting_recovery只读取已经完成的操作和仍未完成的恢复链，不分成功/失败材质；揭晓由原结算事实触发。CB15的消费键为原Attempt及failure_feedback阶段，原沟通进度只保留当前实际反馈；没有第二套治疗结果、重试队列或待演结果表。

保存保持原Attempt承诺参数、实际阶段、已结算凭据、Visit当前方案来源/修订以及沟通消费边界。恢复先重建身体、床位和安全占用，再直接投影当前已知状态；未完成的实际反馈按余量继续，已经完成的失败不重加怒、不重抽事件、不回收后再次领包。静态结果文字可查看，短动作不因恢复、切层或重新打开卡片重播。内容更新的表现可换资源，当前已开始Attempt的效果、费用和恢复承诺仍冻结。

结果发生时按事实中的Visit、Attempt、设备ID直接更新对应投影与已打开详情；不新增每tick遍历所有患者、所有病例绑定或所有空楼层的结果查询。只给当前可见主体绑定小道具，使用原共享资产、音频和最多3台次要医疗道具动态预算；未观察层只保留原业务事实。一次结果小动作替代相应工作收尾，高潮、必要照护与患者主体优先；没有名额就保留稳定姿态及必要文字，不延迟结算、释放或新接诊。

结果投影绑定事实中的原设备与Attempt；新工作绑定具有更高的当前阶段优先级，旧结果仅保留历史文字。短动作被新任务、安全离位或视图回收替代时直接结束，不建立待补播记录；异步资源仍按原医院会话/实体/视觉代号拒绝迟到绑定。省略动作、未执行CB15和已实际完成解释分别按原沟通消费边界判定，表现结束不生成help_completed或照护加分。

方案比较只为当前选中Visit投影现有推荐及至多一个合法备选，数量和缺项读取原临床查询；无推荐时显示原待齐原因，不创建占位方案。其余实际方案及缺资源说明在玩家展开时使用原列表分页。数据中的四个解析样例在文档核验时计算，不随患者生成或画面刷新批量计算。临床、账目、评分、关系、任务和院史依旧各消费原完成事实；结果卡没有额外事实广播、世界快照副本或无界保留列表。160/320/640人及稀疏高层场景须比较关闭/开启结果表现的模拟哈希、资源峰值和原帧耗时目标；缓存或表现名额不得成为玩法容量。
