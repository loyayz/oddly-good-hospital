# 随身兜底真实安全到场

## 变更前规则、交接及选例
- public-facility-area-use:150 明确：沿本任务真实地面行程到任一合法安全占地即可结束移动，不必到预选整数终点，也不要求设施区域成员。其他任务、实际绕行、承托退出及多人行程不得借此取消。
- 仅 waiting_life fallback 私有结束逻辑去除区域 contains 门槛；保留原任务、detour/convoy/member、floor/lying、当前floor段检查，以及原 cancel_ground_move全部保护；实际完整身体 safe_wait 不变。共享 owns_arrival / try_finish_arrival 不变。
- 选本任务安全中途 current_area 空场景与 foreign owner：合法正式生活需要和本need请求，逐步到达前不工作，原时钟/票序不重置，恢复后真实到场及80tick效果。远目标是fixture明确请求，不声称自然选点。保留原失败和本轮 baseline。
- 选最小合法 guard 边界覆盖拒绝路径；选 STAFF-74 门/连接真实撤离恢复；共享区域到场仍需 contains 的直接边界。不会扩展全专题、性能或 waypoint其他问题。
- 保存完整合法原始 preWorld、日志/命令/exit/耗时和UID。施工/上下楼不是本批范围。

## 实现与主交接结果
- 生产仅 waiting_life.gd，12增2删。新增私有 _try_finish_fallback_travel，保留与原 owns_arrival 等价的 owner/detour/convoy/members/floor/lying/current segment 限制，只不调用 area contains。safe_wait 完整占地和 cancel_ground_move原保护不变。原结构无路取消分支保持原样。公共区域 owns_arrival/try_finish_arrival 一字未改。
- baseline02（原生产）合法World，真实14步到 [39.8000030517578,78]、safe=true/current_area为空，仍不结束自己移动，80tick不能开始；foreign正确拒绝。完整原失败与已有waypoint03/reference04证据不覆盖/不删除。
- flow04（补丁）同正式前提：本need在14个 .1s 生产移动步后立即在安全中途完成移动，未到显式远目标[42,90]；到达前逐步remaining0/无怒气效果/原时钟，5步存取恢复全facts精确一致，安全后remaining80，真实79+1步效果一次，合法终态。foreign owner完全不动。远目标是fixture请求，并非自然floor_waiting_point选出的目标。
- 到达时ticket全字段不变；完成后仅允许删除本 need_service pause，pause_reasons其余键值严格保持，原need ID/started_tick/visit ticket ID及票其余全部字段不变。观察唯一变化字段为pause_reasons。当前合法fixture没有额外pause键，不声称实跑了其它暂停来源的业务流程。
- 同一安全中途调用共享 try_finish_arrival(area={}) 仍拒绝并保持全World不变，证明不放宽设施区域到场门槛。
- staff74-02 两变体通过：门与交通入口，真实安全撤离、保存恢复、到场后80tick。后续只改测试观测/guard，不改该方法或生产，复用证据。
- guards02 的 OFFICIAL-CONVOY-MEMBERS-GUARD 单项通过：正式formation合法初始声明，正式request_group_move创建convoy，两成员、合法World，私有helper拒绝且完整事实不变。直接probe仅增加经验证合法的waiting_need_id标签，不把该probe称为生活需求完整流程；完整preWorld已保存。

## 保留失败、覆盖限制
- parse01 测试run与父类run签名冲突。首批shell未使用set -e导致baseline01/flow01/staff74-01也只遇到同一解析错误，均无功能结果，保留日志；改测试方法为run_safe，后续先parser且shell set -e。生产恢复finally执行，没有遗留baseline文件。
- flow02仅过严ticket全等失败：到场/恢复/真实80tick全部通过，但既有返回逻辑合法删本need_service。flow03将到场全等与完成后非pause字段全等区分，通过；flow04进一步严格断言pause字典只删除本need_service，不能忽略其它来源。保留所有版本与原失败。
- guards01复用旧support fixture时公共区域_cell_region(...).ref不存在，脚本错误/未完成，其空rows的ok输出不视为成功。新测试适配只去除本guard无关的公共区域查询。
- guards02整体exit1：旧睡眠fixture在100步内未建立sleep/lying/support_exit前提，REAL-SUPPORT-GUARD失败；不是本helper取消承托。未放宽预期，不扩跑整睡眠/上下楼。该失败及合法convoy子项原结果均保留。
- 本轮未有效实跑support_exit、lying、detour、非floor段独立拒绝；这些已有保护按源码逐项保持并在原cancel_ground_move接口停止扩范围，不冒称覆盖。单人旧detour已非法，未塞占位字典伪造合法World。
- 主真实流程/foreign/共享area/精确票暂停/STAFF74通过；guard合集不称全通过。没有尚未解释的生产失败。
- 不跑性能微测、长测或全专题；不stage/commit/push。所有UID不变。

## 原始证据与耗时
`fallback-safe-arrival-20261112/` 含源码前后及各失败测试快照、命令/隔离环境/native身份、exit/log/reaped、全部失败、完整preWorld及第5步inflight bin、UID证明。实际wall time仅功能进程耗时，不是性能验收。

- baseline01: exit=-15, guard_error=True, 0.609482s, reaped=True
- baseline02: exit=1, guard_error=False, 2.712344s, reaped=True
- flow01: exit=-15, guard_error=True, 0.509404s, reaped=True
- flow02: exit=1, guard_error=False, 2.710495s, reaped=True
- flow03: exit=0, guard_error=False, 2.708441s, reaped=True
- flow04: exit=0, guard_error=False, 3.516906s, reaped=True
- guards01: exit=-15, guard_error=True, 4.232939s, reaped=True
- guards02: exit=1, guard_error=False, 4.414239s, reaped=True
- parse01: exit=-15, guard_error=True, 0.509500s, reaped=True
- parse02: exit=0, guard_error=False, 2.608287s, reaped=True
- parse03: exit=0, guard_error=False, 2.910683s, reaped=True
- parse04: exit=0, guard_error=False, 3.713898s, reaped=True
- parse05: exit=0, guard_error=False, 3.612223s, reaped=True
- staff74-01: exit=-15, guard_error=True, 0.509604s, reaped=True
- staff74-02: exit=0, guard_error=False, 2.809418s, reaped=True

生产SHA256 `7b8ce6b2f8607f25c5328e6b63a1dad94e8acbdef8833a53eee9b9b6d7863714`；最终测试SHA256 `f2439a6906e305536c5a447bf126f757d581e0c33aadd22b76f63155579922a6`；663 UID字节全不变。完整bin逐文件SHA在summary.json。

[原始包](evidence/2026-11-12-fallback-safe-arrival/selected.zip) 1968364字节、130成员，SHA256 `da67b344d316e97a1f11a716f2a7ae5e54c9cc5224f6a9e8cfe735c7696dcc54`；[成员清单](evidence/2026-11-12-fallback-safe-arrival/selected.members.json)、[结果汇总](evidence/2026-11-12-fallback-safe-arrival/selected.summary.json)。本地CRC/逐成员SHA通过。独立只读复核无提交阻碍；覆盖限制不变。
