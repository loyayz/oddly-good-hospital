# 游戏内路线消费者审查

审查范围为 `game/` 中全部直接 `.route(...)` 和 `_floor_route(...)` 调用，不包含函数声明。共核对 52 个调用点：37 个完整旅程调用改用 `route_cost` 或 `can_reach`，2 个原本忽略人员的层内计算改用 `cost_only=true`；其余 13 个保留执行路径、动态绕行检查或成本模式传递职责。

`route_cost` 与原 `route` 使用同一个结构旅程算法、完整身体与同行配位、预约权限、连接方向、整数时长及失败原因。差别仅为不构造未被消费的脚本 `path/cells`。只需布尔值的调用使用 `can_reach`，保留原有传参。直接层内调用只有原 `ignore_people=true` 的计算可以转为成本模式；真实移动中需要人员争用与绕行的调用保留完整模式。

下表路径均相对 `game/`；行号记录成本接口接入时的位置，函数及调用角色为审查定位依据。

## 采纳：37 个完整旅程计算

| 文件 | 函数／调用角色 | 消费字段 | 处理与理由 |
| --- | --- | --- | --- |
| `life/waiting_life.gd:419` | `_facility_quote_in_query` 去程 | `ok`、`reason`、`travel_ticks` | `route_cost`；座位／公共设施报价没有读取执行路径。 |
| `life/waiting_life.gd:428` | `_facility_quote_in_query` 返程 | `ok`、`reason` | `route_cost`；保留实际投影及返回失败解释。 |
| `staff/staff_wellbeing.gd:311` | `_dispatch_task` 原目标失效检查 | `ok`、`status` | `route_cost`；仅判断原目标是否不可达，真实走路仍由 `request_move` 发起。 |
| `staff/staff_wellbeing.gd:372` | `_reserve` 到达前校验 | `ok`、`reason` | `route_cost`；预约与任务设置顺序保持。 |
| `staff/staff_wellbeing.gd:429` | `_select_facility` 候选去程 | `ok`、`travel_ticks` | `route_cost`；评分按原精确行程，不读取路径。成功旅程具备 `travel_ticks`，不需要 `_route_ticks` 的旧路径长度兜底。 |
| `staff/staff_wellbeing.gd:434` | `_select_facility` 候选返程 | `ok` | `route_cost`；保持独立适配投影与原身体位置修改。 |
| `staff/staff_wellbeing.gd:669` | `_recreation_choice` 各成员到场资格 | `ok` | `can_reach`；保留每名成员、实际目的点及容量条件。 |
| `clinic/clinical_runtime.gd:729` | `_missing_service_reason` 患者路线 | `ok`、`reason` | `route_cost`；失败解释不变，不生成诊断说明不会使用的路径。 |
| `clinic/clinical_runtime.gd:733` | `_missing_service_reason` 工作人员路线 | `ok`、`reason` | `route_cost`；工作人员资格和操作位检查不变。 |
| `clinic/clinical_runtime.gd:1496` | `_bed_transport` 同行转床估算 | `ok`、`travel_ticks`，失败诊断字典 | `route_cost`；保留患者、陪同者及 `[-1,0]` 配位。调用者只读取总时长、离床时长和成功标志，未读取失败诊断中的 `transfer.path`。实际转床另建移动请求。 |
| `clinic/clinical_runtime.gd:1775` | `_dispatch_clinical_releases` 候选离位点 | `ok` | `can_reach`；原身体、预约区域和局部动态终点检查均保留。 |
| `clinic/clinical_runtime.gd:1820` | `_release_ward_operator` 病房离位资格 | `ok`、`status` | `route_cost`；候选排序、床边通路排除和真实 `request_move` 保持。 |
| `clinic/clinical_runtime.gd:2020` | `_round_candidate` 查房人员到场资格 | `ok`、`status` | `route_cost`；仅在原独立预约投影通过后授予实际通行权。 |
| `clinic/hospital_visitors.gd:339` | `_bedside_in_query` 床边探视点 | `ok` | `can_reach`；原床旁身体与操作区相交检查保持。 |
| `operations/environment_service.gd:512` | `_arrive` 清洁／装修出发检查 | `ok`、`reason` | `route_cost`；真实到场、施工和已有移动不重复报价规则保持。 |
| `operations/environment_service.gd:547` | `_work_position` 工作点比较 | `ok`、`walking_distance` | `route_cost`；保留原距离下界及严格优先比较。变量原名为 `path`，实际未读取路径。 |
| `operations/environment_service.gd:966` | `_water_usable` 无候诊服务时的饮水可用性 | `ok` | `can_reach`；设施适配检查保持。 |
| `operations/maintenance_service.gd:474` | `_arrived` 维修到场前检查 | `ok`、`reason` | `route_cost`；原任务、移动所有者与实际到场检查保持。 |
| `operations/maintenance_service.gd:517` | `_position` 维修工作点比较 | `ok`、`walking_distance` | `route_cost`；维修点、人员和原距离排序不变。 |
| `operations/department_service.gd:284` | `readiness` 科室入口路线 | `ok`、`reason` | `route_cost`；入口资格和临床准备状态检查保持。 |
| `operations/department_service.gd:652` | `_has_guide_screen` 导引屏可达性 | `ok` | `can_reach`；原邻近半径过滤保持。 |
| `operations/department_service.gd:692` | `_guide_position` 护士导引站位 | `ok` | `can_reach`；原站位枚举顺序及身体尺寸保持。 |
| `community/research_service.gd:393` | `_find_pair` 研究人与桌配对 | `ok` | `can_reach`；区域、资格、独占和候选顺序保持。 |
| `building/floor_service.gd:107` | `_crew` 工具可达性 | `ok` | `can_reach`；不生成施工资格不消费的路径。 |
| `building/floor_service.gd:115` | `_work_point` 继续使用原工作点 | `ok` | `can_reach`；保留原区域和静态落点检查。 |
| `building/floor_service.gd:120` | `_work_point` 新工作点枚举 | `ok` | `can_reach`；保持逐格首次合法点顺序。 |
| `building/floor_service.gd:150` | `dispatch` 更换工具 | `ok` | `can_reach`；工具故障、改建限制和既有进度不变。 |
| `building/build_service.gd:774` | `actor_safety` 已承诺移动目的地保护 | `ok` | `route_cost`；同行成员与配位原样传入，只证明目标仍可达；不会读取或替换真实移动路径。 |
| `building/remodel_service.gd:324` | `_evacuation` 安全疏散落点 | `ok`、`status` | `route_cost`；原动态落点占用、已承诺目标和房间排除保持；实际疏散另发移动。 |
| `sim/simulation.gd:252` | `_execute` 玩家移动命令前置校验 | `ok`、`reason` | `route_cost`；失败仍保留原原因，成功继续由 `request_move` 管理真实路线。 |
| `staff/clinical_development.gd:202` | `_dispatch_training_job` 培训桌选择 | `ok` | `route_cost`；原桌位独占及工作窗口保持。 |
| `staff/clinical_development.gd:221` | `_dispatch_training_job` 导师相邻站位 | `ok` | `can_reach`；导师仍实际移动到指定站位后工作。 |
| `staff/clinical_development.gd:245` | `advance` 导师到场资格 | `ok` | `can_reach`；保留 `space.at` 真实到场条件。 |
| `staff/clinical_development.gd:557` | `_base_start_quote` 前序基地使用者到达时间 | `ok`、`travel_ticks` | `route_cost`；FIFO 及前序工作剩余量累积保持。 |
| `staff/clinical_development.gd:583` | `_select_base` 基地候选比较 | `ok`、`status`、`travel_ticks` | `route_cost`；原预计开始时刻、可用性及 ID 平局顺序保持。 |
| `staff/clinical_development.gd:642` | `_yield_prepared_base` 当前人员让位点资格 | `ok`、`status` | `route_cost`；进入者的完整路线见证仍保留，当前人员只需证明让位点合法。 |
| `staff/shift_scheduler.gd:171` | `dispatch` 护理交接候选到场资格 | `ok` | `can_reach`；原独立预约投影、相关床位通行授权和实际交接保持。 |

## 采纳：2 个直接层内计算

| 文件 | 函数／调用角色 | 消费字段 | 处理与理由 |
| --- | --- | --- | --- |
| `life/waiting_life.gd:671` | `_conditions` 座位邻居／朋友路径半径 | `ok`、`walking_distance` | 原 `ignore_people=true`，追加 `cost_only=true`；精确路径距离、朋友条件和原访问顺序保持。 |
| `building/build_service.gd:737` | `_public_door` 公共出口存在性 | `ok` | 原 `ignore_people=true`，追加 `cost_only=true`；不改变合法房门和公共空间证明。 |

## 保留：13 个执行、见证与模式传递调用

| 文件 | 函数／调用角色 | 实际消费／职责 | 保留原因 |
| --- | --- | --- | --- |
| `staff/clinical_development.gd:623` | `_yield_prepared_base` 进入者路线 | `ok`、`path` | 路径格用于构造进入者占用区域，当前员工须避开这些区域；成本字典不能提供见证。 |
| `building/hospital_movement.gd` | `_dispatch_routes` 完整旅程 | `ok`、`reason`、`status`、`path` | 路径被正式移动对象执行。 |
| `building/hospital_movement.gd` | `_dispatch_routes` 局部层内重规划 | `ok`、`status`、`path` | 真实遇阻后的动态绕行路径，不能跳过人员检查。 |
| `building/hospital_movement.gd` | `_yield` 已行走历史上的退让点 | `ok`，动态层内可达性 | 虽未保存本次返回的路径，但完整模式执行人员争用和动态绕行；当前成本模式会跳过该检查，不能等价替换。 |
| `building/hospital_movement.gd` | `_yield` 无历史时的局部退让点 | `ok`、`status`，动态层内可达性 | 同上，真实让行资格必须保留动态绕行结果。 |
| `building/hospital_movement.gd` | `_yield_idle_staff` 空闲员工让行候选 | `ok`、`status`、`walking_distance`，动态层内可达性 | 候选距离来自实际动态绕行，不能换成忽略人员后的成本距离。 |
| `building/hospital_transit.gd:354` | `_stand_aside` 电梯出口让位 | `ok`，动态层内可达性 | 真实离舱出口让位保留人员争用和动态绕行；成功后仅排入 waypoint 不等于本次检查可省略。 |
| `building/hospital_space.gd` | `_floor_route` 转交导航实现 | 完整参数及 `cost_only` | 是统一层内契约，不是业务读者；保持模式参数原样传递。 |
| `building/hospital_space.gd` | `_facility_exit_quote` 候选展开后的出口 | `ok` | 已使用成本模式，保留现有候选预约／几何 overlay；没有遗漏的脚本物化。 |
| `building/hospital_space.gd` | `_exit_witness` 冷路径兜底 | `ok`、`path` | 逐段构造出口 swept 区域，后续展开安全证明需要这些几何见证。 |
| `building/hospital_navigation.gd` | `_point_route` 同层直接旅程 | 完整结果或成本结果 | 已传递 `distance_only`；执行请求保留路径，成本请求无需路径。 |
| `building/hospital_navigation.gd` | `_point_edges` 最后楼层到终点 | 路程、耗时，执行模式下的 `path` | 已传递 `distance_only`，Boost 惰性展开所需业务边事实按模式生成。 |
| `building/hospital_navigation.gd` | `_point_edges` 当前锚点到连接入口 | 路程、耗时，执行模式下的 `path` | 同上；执行路径须包含层内走路段，不能统一强制成本模式。 |

## R2 补充：纯成本投影不构建动态人物索引

完整路径物化移除后，三个纯成本投影仍显式同步身体或开启动态查询。`sync_actor` 在新投影上会先经 `_ensure_actor_index` 遍历全体人物，再单独更新目标人物；后续动态入口还会执行一次索引检查。切回原世界进行下一次真实设施适配时，也可能再次重建原世界索引。

| 文件／函数 | 原行为 | 修复 | 保留的实际检查 |
| --- | --- | --- | --- |
| `life/waiting_life.gd::_facility_quote_in_query` 返程 | `sync_actor(reverse)` 后开启 `begin_dynamic_route_query(reverse,false)` | 删除同步，使用 `begin_route_query(reverse,{},false)` | 原世界的设施占用、完整身体、设施适配及安全出口预检保持；候选适配与独立返回世界保持。 |
| `building/hospital_space.gd::facility_trip_quote` 去返程 | 去程动态入口强制构建全部人物索引；修改返回位置后再次同步并开动态入口 | 两段均使用独立普通查询，删除中间同步 | 设施真实适配在创建纯成本投影之前执行；两段之间仍清空路线和观察视图，不继承外层 nominal 结果。 |
| `staff/staff_wellbeing.gd::_select_facility` 返程 | 候选空间为每个新世界同步人物索引 | 删除候选同步 | 员工区域、个人床归属、实际占用、身体适配、去返程结构可达性和原评分保持。 |

安全依据：`_route_result` 的位置取自传入世界事实；fractional stub 使用 `structural_clearance`。`_point_route/_point_edges` 的层内边始终 `ignore_people=true` 且 `structural_only=true`；连接只读取身体兼容和固定通行时长。`RouteClearance` 和门报价读取静态布局、独立门索引及适配权限，不读取人物索引。原世界的实际设施预检、外层动态候选批次、移动碰撞、动态绕行和安全出口见证没有删除。

新增游戏计数：

- `actor_index_builds`：仅 `_ensure_actor_index` 确实执行完整重建时增加 1；缓存命中、同一批次共享和单人同步不增加。
- `actor_index_actor_visits`：仅上述完整重建循环每访问一名人物时增加 1；记录实际重建扫描量，不把一次单人位置同步当作全体扫描。

旧测量没有这两个字段，必须标记“未记录”，不能视为 0，也不能用新字段臆测旧版本的实测值。计数归属各 `HospitalSpace` 实例；模拟主空间计数不等于所有临时独立空间的全局总和。

独立回归在原入口追加：CountingSpace 按世界记录实际 `_sync_actor`，要求候诊椅和 `facility_trip_quote` 的纯成本投影为零，原世界适配预检仍实际建立索引；真实另一个身体仍阻挡 `_dynamic_clear`。员工选址内部创建独立空间，CountingWorld 因此直接记录候选输入的 `ids("actors")` 遍历，要求去返程不枚举全体人物，并用独立完整路线验证同一个人床来回合法。所有原字段、字面时长、事实只读及零脚本路径格断言继续保留。新增索引子项随最终 SPACE-55 执行通过，来源为隔离工程 `99f26c6554cd49f384fd371aec855ac4`；同一批 STAFF-41、42、52 通过，游戏文件与最终普通整步冻结来源逐项一致。

## 验证边界

独立入口：`tests/acceptance/route_cost_consumers.gd::run(suite)`。

- 直线 4 格／20 tick、原地 0 格／0 tick 使用字面答案；比较成本与完整旅程的全部业务字段（只排除 `path/cells`），并检查事实只读和成本调用零脚本路径格。
- 两人同行跨层字面答案为 32 格／240 tick：两层各 16 格，以 1.6 格／秒步行，再加 VC02 的 15+10+15 tick 固定通行。成员与配位完整传入。巨型身体不适配、目标阻塞和院外人物验证失败状态与原因一致。
- 实际候诊椅报价覆盖去程、返程和朋友邻居路径条件；字面答案为 3 格／15 tick，重复报价相同、事实只读、查询栈闭合，且报价阶段 `materialized_floor_cells` 增量必须为 0。

最终实现为 `f83011330adff6d7347b2369e67dcdbbcffcaf23`。同一合法160人输入下，公共300步均值979.52→828.12ms，GP80步1071.32→574.43ms，运营40步79.22→151.03ms。公共最大单步11.62→20.83s，长尾仍未解决；不把本次组合修改的整步收益归给单一调用点。主Space最终记录3900次人物索引重建、624000次人物访问，旧版本未计数，不能作同比。

给定人物的空座报价子测量两次未满足实际适配前提，均保留失败，没有调整负载补出加速结论。性能结论以完整快速窗口为依据；脚本格子物化减少不能单独宣称整步性能验收通过。

代表性交接建议：SPACE-55 运行新契约；STAFF-41/42 覆盖休息去返程、护理交接及选座邻居；OPS-44 覆盖运营动态路线批次，OPS-21 覆盖真实维修到场；GROW-30 覆盖研究与课程桌位竞争；SPACE-18 覆盖楼层工作点与工具变化；CLIN-24 覆盖护理、查房及实际离院。若同一批已含相同且未变的断言，可复用对应通过证据。固定合法 160 人快速测量继续覆盖实际临床、选座和高成本阶段；完整性能验收保持暂停。
