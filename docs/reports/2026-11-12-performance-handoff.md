# 160 人 CPU 性能工作交接

当前状态为暂停。临床流程与住院家属需求已经实现、独立评审并修复，后续工作集中在固定 160 人负载的正确性、覆盖和 CPU 性能。本次结束于末态检查、局部验证与推送，不启动新的长采样。完整 Release 矩阵、实机渲染/GPU 与两小时稳定性验收仍暂停。

仓库为 `C:\code\loyayz\oddly-good-hospital`，分支为 `dot/next-stage-20261107`，origin 为 `https://github.com/loyayz/oddly-good-hospital.git`。源码与工具提交 [`9abf7b5`](https://github.com/loyayz/oddly-good-hospital/commit/9abf7b5679e5398939ea0f201baef8d0b6359870) 已推送；此前三次完整 CPU 测量和证据已推送为 [`580ed2d`](https://github.com/loyayz/oddly-good-hospital/commit/580ed2d)。需求依据是[临床流程与住院家属规格](../specs/26-11/2026-11-11-clinical-flow-and-inpatient-family.md)、其引用设计及设计数据，现有快照不定义业务正确答案。功能实现与评审修复分别在 `4c5e2e4`、`dc5cbf5`，无需重新实施需求。

`9abf7b5` 只减少重复计算：已有候诊时钟直接保留；导航尺寸描述复用一次身体读取并保留同行组尺寸覆盖；`BodyIndex` 通过新增 `query_rect` 传递完整 Rect2，保留原 Boost 查询、Dictionary 结果、错误、严格接触过滤、候选顺序和当前代际。没有调整价格、资格、工时、随机流、负载、搜索范围或玩法。

本批已完成的验证如下，详细原始记录见[局部结果报告](2026-11-12-query-bridge-and-initialization.md)。

- `PERF-11/12`、`SPACE-53/57/61` 五例通过。共享准备 15.126 s、导入 24.196 s、测试阶段 8.382 s、总计 47.716 s。PERF-11 包含 27 项边界；PERF-12 包含全部 80 species、488 bindings 的 91600 次尺寸对照及图键、权限、零预算驱逐交接。
- 候诊时钟：完整 mixed 终态保留 184 Actor、166 在院、127 活跃 Visit，每侧 1000 次完整 ensure；三对耗时合计从 324584 µs 降为 98895 µs，减少 69.53%。独立计数的住院查询从 127000 次降为 0；这仅适用于本边界所有活跃 Visit 都已有时钟的事实。
- 导航尺寸：原 mixed 完整 160 Actor × 实际四层，共 640 个请求，每对每侧 163840 次；三对合计 1591465→1014842 µs，减少 36.23%。独立计数 body 读取 1280→640，尺寸及 JSON 字节相同。
- 原生查询：从完整终态执行构造与一个真实步，完整捕获 25 个索引、1904 次更新、30352 次查询，其中 30349 次跨原生桥。按原操作顺序回放，每段重复 100 次、三对 AB/BA/AB，合计 12449434→10026576 µs，减少 19.46%；全部有序 IDs 相同。该语料包含冷构造，不能当作稳态整窗或完整验收。
- 只读末态检查及离线契约通过，完整事实和 RNG 不变。业务历史诊断工具的 0＋2 真实步检查通过，完整终态文件 SHA 为 `21aff2546935022312333b67605680c491292575aaa845b07733db993a415a51`；离线契约退出 0。两步业务覆盖不足保留；完整 7000 步历史诊断没有运行。

新版本的整体性能尚未测量，不能保证整窗收益或据此宣布性能达标。最近完整三轮 B03 使用旧源码 `9368fc6`、旧原生 `89d4e1db…` 和固定 mixed 输入：P95 为 98.014/90.693/90.625 ms，P99 为 120.599/116.717/109.410 ms，最大值为 291.635/300.453/288.649 ms，采样墙时为 459.906960/437.005125/432.071632 s。三轮 1×速度通过，完整 6000 密集样本均保留 165～171 人；但延迟标准 10/15/30 ms 及五项覆盖均未通过，合格重复数为 0。详见[B03 性能报告](2026-11-12-clinical-flow-performance.md)和[B03 摘要](evidence/2026-11-12-clinical-performance/mixed-b03-summary.json)。

五项未覆盖为检查工作、完成检查、维护、升级、有效探视。tick7633 的只读事实已经缩小范围：

- 十二例检查患者都处于 `leaving/abandoned`。0048、0049、0051 已完成检查，其余九例未完成。当前四名原医生空闲且队列为空，不能反推弃候前的实际资格、路线或等待历史。
- 维护 `maintenance_00000233`、升级 `upgrade_00000234` 尚在 travelling，工时均为 0；工人 238/239 仍在 1F，下一段乘 `benchmark_lift` 到 2F，尚无正式乘梯票。升降机此刻在 trip37 向 1F 下客，乘客为患者0018。已付款不代表开工，单帧也不能证明持续死锁或具体阻挡者。
- 两名留存家属都是 companion，正在真实离院；关联患者已治愈。WardStays、探视请求和每日探视意向已经清理，末态无法证明 30% 未命中，也无法恢复全部历史原因。

下一任务可先用完整末态的一实际步对照定位工人238/239、trip37、患者0018与下客/落点/Move 的具体交接及 blocker。冷恢复的一步只解释该边界，不能替代过去6000步的历史证据。检查及有效探视的历史原因需要在明确恢复长诊断后，用新工具捕获真实 owner 变化；不搬设备、不调护士岗位、不重抽随机或删合法负载来补覆盖。

可直接复用的本地证据与输入：

- `.cache/query-rect-acceptance01/summary.json`，对应隔离工程 `.cache/acceptance/abdd41108f8b4b3b90d309a8e798fa9e`。
- `.cache/hotpath-local-batch01/summary.json`、`inspect/result.json`、`clock/result.json`、`shape-counts/result.json`、`shape-timing/result.json`、`spatial-replay/result.json`。
- `.cache/hotpath-local-batch01/spatial-capture/requests.bin`，SHA `f612cd6deabc6eb75d24e28a3caee13246d2d09c7f6ca232ed234973be9352db`。完整流只保留在本地；Git 证据记录其身份及重建入口。
- `.cache/business-fact-smoke01/summary.json` 和 `offline-contract.json`。
- 原 mixed 输入 `.cache/performance160-mixed-20261112-toolqualification01/mixed-input01/mixed160.input.bin`，SHA `75f5e1d922f39f12382c0ceb74806bda0293251189f68a1ac158842f65fa78ca`。
- 原完整终态 `.cache/performance160-clinical-family-20261112-mixed-candidate01/qualification-r1/r1.json.final.bin`，SHA `0daf82b82da618af8818aed962d5ef2bf9bad1b00be01c4f5a7ce71efb52662e`。缓存缺失时按 B03 摘要的已归档成员恢复并校验，不重新生成较轻输入。
- 长窗协议保留 1000 真实前缀＋6000 采样、0.1 s 固定步、app 主线程策略、4 环境任务、`OMP_NUM_THREADS=1`。原 v3 输入 `752924c5…` 与 mixed 是独立行，不能跨行计算优化收益。

本机新原生 DLL 为 `ab025d4367b7a13264f8a33cfefa5c177e19f591cc62cf36c1ca01d0e805249b`，由 Godot4.7.2/Zig0.15.2 构建，四份依赖未变。DLL 不入 Git；另一环境在运行新 `BodyIndex` 前必须构建或核对该库。默认沙箱连相同极小 C++ 探针都报 Unexpected，正常执行方式的同源探针 135 ms 通过，随后完整构建 156.296 s 通过；失败日志与原 DLL 均保留，不属于业务失败。引擎 console SHA 为 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`，实际 EXE SHA 为 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`。

恢复后的优化判断继续分别报告局部收益、整体影响与正确性。可靠局部收益可保留，不要求整窗必须提高固定百分比；整体变慢时拆开定位。相同含义、代码、内容及执行环境的既有证据可复用，局部结果不当完整性能验收，旧内核输出也不替代规格。当前不追加长采样。
