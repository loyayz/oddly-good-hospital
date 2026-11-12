# 公共安全点排序：固定真实语料的隔离候选

## 依据与约束
[已合格热史细分](2026-11-12-waiting-hot-boundary.md)中的6次真实安全点查询，原完整公共枚举95.110ms、原sort_custom116.190ms；这些是含已明确采集扰动的诊断span，不是候选收益。其完整输入包已从03bcb4e实际下载核验后才运行本批。该候选尚未进入生产；实际生产仍1e5bb6e。

候选仅对已完整取得的点序列排序：每点仍用原Vector2.distance_squared_to，存为Vector3(distance,y,x)，使用Godot已有Array.sort原生比较后原样写回Vector2i。不改变完整候选、距离算术、y/x平局或safe_wait/can_reach；不新增缓存、库或native API，不改变期限和真实移动。

Godot4.7.2固定源码中Array.sort→Variant::OP_LESS→Vector3::<按x/y/z精确字典序，没有epsilon。Vector2距离返回与Vector3分量同为real_t，因此保存原距离函数结果不引入额外有限值精度；实际公共候选被room_use.public_point限制为0..95，y/x可精确还原。这不是泛用超大整数或NaN排序保证；没有把数值边界测试冒称合法医院输入。

## 固定计划与测量边界
6份实际points_before/origin/points_after，每份6组AB/BA交替，每arm20次，共36对、1440次排序，未按结果追加。每case另有各1次untimed完整资格/warmup。双方输入duplicate与严格全序检查都在计时外；计时包含完整排序函数返回，候选装饰、原生排序、还原、显式clear和局部生命周期均包含。完整payload/源文件不变，不创建WorldState或Simulation，不测枚举、安全、可达或实际移动。

15个额外纯正确性用例包括空/单/重复、整数与半格、binary32近等距、y/x字面平局、地块边界和正负1e12数值origin。全部通过；1440次输出均严格等于原捕获完整点顺序，6份完整事实和文件字节未改。parser通过、无修改；进程18.705秒、exit0并回收。

|720次/arm|原sort_custom|候选完整排序函数|
|---|---:|---:|
|总计|14.652447s|2.020679s|
|单次中位|19.8975ms|2.699ms|

36/36对候选更快，排序局部总计减少86.21%。这是本固定语料的纯排序结果，**不是整步或完整窗口收益**；95.110ms枚举、其他业务、以及采集残差都不在该降幅内。生产整合和真实安全撤离尚未验证，原全窗门槛与覆盖仍失败。

## 原始证据
[固定原始包](evidence/2026-11-12-floor-wait-order/micro.zip) 1460882字节、29成员，SHA256 `4969ba559b22e99628a7b5f8eceea4ba95fc93c4b9a6e92ff916f7f74ba4056a`；[member manifest](evidence/2026-11-12-floor-wait-order/micro.members.json)、[36对total/median分析](evidence/2026-11-12-floor-wait-order/micro.analysis.json)。保留1440次原始微秒、15边界、完整6语料、固定plan、原/候选脚本、引擎/host/命令及parser/进程信息。本地CRC/逐成员验证通过，未删除旧包，未修改生产。候选order.gd SHA256 `505f0195f896d086db4481beb17991b00868e652fee759b853851d9768ff3ead`。

## 排序整合：实施前范围与选例

本次只将已测排序接入 floor_waiting_point，完整枚举、公共点定义、原 Vector2 距离、y/x 平局、safe_wait && can_reach 的顺序及短路、同层返回位置全部保留；不加缓存、不改 native。实际交接是到期且当前占地不安全的 fallback_travel；原期限、票号、移动所有者、真实安全到达后80 tick 使用不变。依据公共设施规格148–156/164及医院日常§17。

选例：最终生产排序 helper 的15个纯边界与6份captured全序；同一正式 floor_waiting_point 对照原比较器，核完整序列、实际安全/可达调用轨迹、首个通过与只读World/RNG，包含冷World/facts替换/公共房间/派生上层边界；STAFF-74门及连接锚点真实撤离、存档恢复和80tick，并观察 floor_waiting_point 实际命中；只调用 safe_fallback_before_busy_waypoint 的两种所有权边界，不运行完整arrival专题。已有micro测量只在整合helper与已测候选体逐字一致时复用，不重跑micro或历史性能窗口。先parser/diffcheck，再选例；失败保留原日志。

## 生产整合定向结果

已最小接入 `_sort_floor_waiting_points`，helper实际语句与已测候选一致，仅清理注释。反向替换helper调用后，floor_waiting_point完整枚举/查询循环与整合前逐字一致。无新缓存或native改动。

通过：生产helper的15个纯计算边界及6份captured全序；6真实World查询完整候选和safe/reach调用轨迹、首个通过短路、返回位置、World/RNG未变；恢复到另一个World及同World替换facts（复用服务，不冒称全新服务冷缓存）；公共toilet→doctor_office→rest边界；STAFF-74门口和连接锚点两个变体全部原断言，包括真实撤离、完整存档恢复、80tick真实使用、到达前零工作，并实际命中floor_waiting_point两次。最终parser通过。

前提失败保留：query01/flow01使用旧waiting房型，被当前正式建房拒绝，guard终止并回收。仅新runner适配为合法toilet/rest房型；query02误用office ID，最终改为doctor_office后fixture通过。旧waypoint用例无可用卫生间时现在直接结束尝试，未进入所需fallback前提；新runner提供合法卫生间并明确原期限+451输入后真实调度到fallback_travel，未伪造到达/工作。

**独立既有缺口与未覆盖边界，分别报告：**

1. `derived_upper_without_override`：合法完整World，completed_top_floor声明第二层拥有[1,2]地块但无显式override。独立应有1024个无房间公共点；原/新在排序前均得到0候选，随后仍调用排序helper处理空数组；没有候选比较或safe/reach调用。room_use当前仅为overrides构建_plots，与floor_plots派生所有权不一致。保留失败，不把双空当正确。
2. `safe_fallback_before_busy_waypoint`：到期后本需求真实行走14步至[39.8000030517578,78]，safe_wait=true但current_area={}，原/新均仍fallback_travel、remaining_ticks=0。原比较器独立对照同失败；本需求所有权正确、无detour/convoy，但新合法房型前提在该处没有current_area成员资格，未满足当前owns_arrival的contains前提。外国owner变体正确保持移动。该观测只能证明当前适配未覆盖原预期的中途完成，不能仅凭双失败判定生产bug；保留为前提/契约解释不足，不放宽期望、不改业务，也不把STAFF-74成功解释为任意安全中途终止已通过。

最终选择性结果不是全组/全性能通过。旧失败、前提修正、最终代码、查询原始轨迹、命令/exit/log/host、实际耗时与UID原字节校验均保存；未动既有UID，未运行micro/2253历史/完整窗口。完整6语料来自已持久核验micro输入。

进程实耗（秒，含加载与退出，不是函数性能）：

- derived03: exit 1, 2.411s, reaped=True。
- fixtures03: exit 0, 3.116s, reaped=True。
- flow01: exit -15, 2.638s, reaped=True。
- flow02: exit 1, 2.810s, reaped=True。
- parse01: exit 0, 3.010s, reaped=True。
- parse02: exit 0, 2.810s, reaped=True。
- parse03: exit 0, 3.112s, reaped=True。
- parse04: exit 0, 2.809s, reaped=True。
- query01: exit -15, 16.089s, reaped=True。
- query02: exit 1, 16.416s, reaped=True。
- sequence01: exit 0, 4.823s, reaped=True。
- waypoint-reference04: exit 1, 2.809s, reaped=True。
- waypoint03: exit 1, 2.909s, reaped=True。

运行入口：`tests/acceptance/run_floor_wait_order.gd`，模式sequence/query/fixtures/flow/waypoint/waypoint_reference/derived。Linux guard及完整参数在raw包中；失败模式保持失败，不隐藏已有问题。

定向原始包：[selected.zip](evidence/2026-11-12-floor-wait-order/selected.zip)，2,965,892字节，104成员，SHA256 `ad994ae90461252562b2d0f1cc70f93948a31c50656df4053acef5e9234493fd`。[成员清单](evidence/2026-11-12-floor-wait-order/selected.members.json)及[分项状态](evidence/2026-11-12-floor-wait-order/selected.summary.json)。本地CRC/逐成员读回通过；此前micro已在a73cba9远端实际下载核验。

### 后续需求核验：中途安全撤离

排序提交后另查现行公共设施规格第150行（2026-11-10 a1dabfdd引入）：本任务真实地面行程到达任一合法安全占地即可结束移动，不必继续到预选整数终点，并不要求设施区域成员。waypoint03/reference04已证明正式本need请求、14次真实推进、合法World、单人地面段、原时钟及safe_wait=true；current_area={}却因contains门槛拒绝结束，支持独立业务缺陷结论，而非仅fixture缺区域资格。外国所有者保护仍正确；该测试未逐步累计到达前零工作，也未证明远目标是调度自然选择。旧失败原始证据保留；下一批仅分离fallback安全完成接口，不放宽一般设施区域到场。排序等价及STAFF-74既有通过范围不变。
