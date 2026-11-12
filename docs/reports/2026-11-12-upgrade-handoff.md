# M09 升级真实交接补齐

## 规则、前提、选例（执行前）
- design08 §21 与 OPS26/27：使用中的机器须原安全改建停止新预约并实际安全交接；Attempt冻结方案/领料/承诺不回算；420一次材料、30000标准毫秒、真实外部人员到场才工作，完成才升一级。未开工可退、已开工不退款/存取不清工时，原接口不变不重复整套库存专题。
- 当前comprehensive_observer只要求upgrade实际工时≥1ms；保留该指标但本例必须证明目标机器真正完成唯一升级，不能把刚开工算补齐。暂不修改综合benchmark动作脚本，待探视方案统一版本化。
- 固定原目标bench_room_2_15_0（M09），从完整活跃服务World边界开始；直接machine_upgrade拒绝必须现金/等级/订单原子性。不得换目标、清预约、瞬移、减负载或重抽随机。
- 正式命令remodel_prepare：同设备同层原位置build_move，safe_transfer=true；实际.1s推进至最新preview可应用；同一次drain_commands顺序remodel_apply完整quote再machine_upgrade，避免中间新预约。后续真实派工/到场/30000标准毫秒，保存准备中与部分施工，原病例接续和后续病例设备等级按必要选例验证。
- 保存完整preWorld/RNG/身份/账目、命令/结果/事件/耗时、所有失败与UID；仅功能补例，不性能测量。host采集源头只读CPU/内存/affinity/配额统计，node仅hash，绝不读取mount/cgroup内部映射；进程环境记录白名单。

## 第一轮有界结果与阻碍（未补齐）
- 原档成员SHA及archiveSHA验证；仅提取decision-1633目标bin，不复制旧host/Windows元数据。before完整事实在当前代码validate为空，Simulation初始化后freeze精确等于输入；163 present，原session207/Attempt206，remaining148。仅作为合法业务边界，不声称当前实现从历史重新生成此轨迹。
- inspect01调用了不存在的upgrade_preview，纯测试API错误；改为正式upgrade_quote后inspect02通过，保留原日志。
- upgrade01：直接machine_upgrade拒绝、现金/等级/订单/原Attempt和领料原子性通过；remodel_prepare正式接受，准备中完整冷恢复全事实通过。600个真实.1s步骤后preview仍拒“等待承托对象实际离开”，未进行apply/付款/施工，exit1，83.776422秒。此轮不是性能窗。完整preWorld/preparing/safe-transfer-boundary/final及事件/trace保存。
- 实际阻碍是bench_patient_0085：旧before已standing、height0、2F[79,49.1999969]而仍support_facility_id=目标M09；当前600步终态standing、height0、2F[86,45.3999977]仍保留引用。build_service._busy无条件按此字段拒绝；不能清旧引用、换目标或删actor来通过。
- 只读生命周期调查：clinical_runtime._support对seated也记录support；_settle改seated→standing却不清引用；导航仅lying才有support_exit，movement只有真实support_exit完成清引用；release_adaptations按完整身体退出释放预约但不清standing引用。临床busy读support时同时要求实际overlaps，改建_unused却仅看引用。这是需要单独确认规则/修复的真实阻碍，不把validate通过等同语义一致。
- 原0109在tick1821已cured并leaving。_dispatch_suspended允许另一台同definition设备继续原Attempt/余量，不能要求升级准备期间永远suspended148。首版frozen_safe_release断言混入OPS26单机fixture假设，需按真实暂停/接续分支修正并保留原失败，不能据此宣称生产冻结被破坏。
- upgrade01和inspect-terminal01进程都已回收；engine槽已交家属选例，后续只读，无继续重放或生产修改。

## 承托生命周期最小修复（执行前增补）
- 已独立审查：_settle的seated→standing原转换应清support引用，按现有suspend_outpatient同样同步；不释放adaptation、不改身体位置、不放宽build._busy。
- 历史兼容落在正式clinical dispatch既有active_visit循环，不读档全actor猜测改事实。要求已结算result_receipt与原visit/Attempt/同设备/outpatient协议关联；standing+floor+height0；无活跃session/住院/preparation/生活need/seat/本actor设备预约/current support_exit；完整body离开设备与patient/operator/repair岗位和现有预约区域。只清该引用并sync，条件不足保留，幂等。
- 补实际完整负载座式结算场景：真实成功/可观察失败分支，刚起身原预约/身体仍阻止改建，实际离位才解除；旧before恢复后正式协调清85引用，真实seated/lying/当前support_exit（输入若有）拒绝且其它事实不变。不重写Attempt结果以造失败。
- 原升级用例改为观察暂停与同Attempt真实接续，允许同型替代设备完成；只在暂停期间余量冻结，实际工作才减少。升级原目标不变。

## 生命周期修复与选择性验证阶段1
- 当前生产仅clinical_runtime.gd：正式_settle中seated→standing清support字段；已有active_visit循环中的历史兼容按上述窄条件执行。不改任何位置、预约、账目、Attempt、步长、排序或benchmark动作。
- 原实现settle-baseline01：完整原1633前提实际推进，1650病例0065 cured、1657病例0063 retry、1781病例0109 cured；三例起身仍残留ref。补丁settle-patched01同三例全部清ref。目标109刚起身仍实际在[72,74]，原adaptation全保留，build._busy仍以真实预约拒绝，不能立即搬机器。
- settle两轮整体exit1中的额外失败是测试把既有一次plan_experience_awarded从缺省到true也当成冻结承诺。保留原runner/失败。settle-audit02从已存真实结果只读核验，三例唯一变化字段均为该flag且值必须true，其余Attempt键/值严格全等，ref均清、真实在位仍拒改建，exit0；没有重抽结果、修改旧事实或为测试补造失败分支。最终断言只允许缺省→true，不忽略任意flag差异。
- compat01 exit0：0085真实leaving/cured且仍在active_visit_ids；原result_receipt→attempt183→visit85→同M09→outpatient证据来自原事实。直接兼容调用仅删该actor的ref，完整World其它事实/RNG精确不变，第二次幂等。真实seated109与lying0004全不变。原baseline实际生成的standing仍在岗位/持预约1781边界也不清。当前support_exit独立负例未造假构造，仅保持明确代码拒绝；不声称本轮实跑所有保护组合。
- 新生成与历史兼容均已通过关键选例。失败原始前提/结果/bin保留。准备中读档仍全事实等于保存边界，不在读档初始化泛扫清引用。

## 原固定目标升级02（仍未补齐）
- 相同完整before，直接升级拒绝原子性仍PASS；正式remodel_prepare接受、准备中cold restore全等。5个真实.1s安全交接步骤后可应用，tick1638同一次drain_commands按remodel_apply最新price/refund/layout后machine_upgrade，两条都接受，创建唯一upgrade225，420只支付一次。真实dispatch已处理85历史ref，未改输入。
- 后续2400个真实步骤至4038，原负载没有删减。原session/Attempt身份保持；暂停连续阶段remaining精确不变；若减少只能发生有实际工作session的步骤且每步至多1tick。允许同型替代设备接续；原Attempt仅允许已述一次结算flag，原领料不变。
- 目标升级订单仍travelling，维修员226在1F[83,43.6000023]，目标2F[73,71]；remaining30000、started=false、work0、grade0、无完成凭据。未到场前零工时保护PASS，部分付费施工恢复没有触发，后续新病例读取等级也未验证。现行coverage≥1ms也未满足，不能称升级已补齐。
- 只读inspect-worker02：request634/cursor84仍原1→2F路线；floor点[86,44]后为电梯段，无领票。local rejoin index84；travelled累计265点，末段83–84/43–45反复侧让。旧trace未记每步worker位置，累计运动不能证明最近连续进展，不能从2400上限自动断言死锁。电梯trip24 alighting，患者0003，from4/to3、remaining1。已存完整4038World，不继续盲跑，待短观察方案批准。
- 所有进程已reaped、engine槽空闲；未stage/commit/push。本阶段只封不可覆盖备份，升级还未完成。

## 阶段身份、隐私及耗时
host采集新wrapper只读取CPU/内存/affinity/固定配额统计；node仅SHA256；进程环境输出固定allowlist。没有导入旧host函数，没有读取/proc/mounts、/proc/self/mountinfo、/proc/self/cgroup或旧Windows host记录。旧archive仅抽取已校验的业务bin。以下时间为功能进程wall time，不作性能优化结论。

- compat01: exit 0, guard_error False, 4.215139s, reaped True
- inspect-terminal01: exit 0, guard_error False, 3.212488s, reaped True
- inspect-worker02: exit 0, guard_error False, 4.024684s, reaped True
- inspect01: exit -15, guard_error True, 3.027308s, reaped True
- inspect02: exit 0, guard_error False, 3.219852s, reaped True
- parse01: exit 0, guard_error False, 2.509151s, reaped True
- parse02: exit 0, guard_error False, 2.408269s, reaped True
- parse03: exit 0, guard_error False, 2.308588s, reaped True
- parse04: exit 0, guard_error False, 2.610600s, reaped True
- parse05: exit 0, guard_error False, 2.508451s, reaped True
- settle-audit02: exit 0, guard_error False, 3.317293s, reaped True
- settle-baseline01: exit 1, guard_error False, 14.049139s, reaped True
- settle-patched01: exit 1, guard_error False, 13.356937s, reaped True
- upgrade01: exit 1, guard_error False, 83.776422s, reaped True
- upgrade02: exit 1, guard_error False, 133.287371s, reaped True

阶段HEAD `9491f15ad9060a1b2381ecd48abfd1a01d9d295d`；生产SHA256 `ccd4751e5110f959d2b78fa670fda88acc0cc092cc85ec4d9838bee8a49f0ca1`；最终runnerSHA256 `9a3bab1968fc70102f6b975a0c3da3851425ec0cebd8cbb5392b244e836afe6c`。全部663个UID字节不变，无新增/移除。

## 批准的8步冷恢复诊断（停止于4046）
- 仅从完整4038终态独立冷恢复，freeze与输入全等。未重复命令、未额外调用业务/寻路/安全查询，仅正式全World .1s step与直接事实快照。保存起终完整World/RNG、每tick有序事件及9帧actor/move/tickets/lift/出口邻近身体事实。不是原连续热史或性能测量。
- 226在8/8步均移动，累计约1.6格，从[83,43.6000023]经[83,44]到[84.1999817,44]；原request634与rejoin84保持，未取得电梯票。该短窗不是226零位移卡死，不能由2400上限自动判业务故障。
- lift trip24保持alighting/remaining1，患者0003仍transit4→3；3F出口真实多身体，0025在[85.6000061,44.2000008]等身体8步未动。没有调用contact/safe判断，不宣称唯一阻挡或死锁根因，不据此偷偷改交通规则。
- 观察只证明该冷分支8步事实，不证明后续电梯一定释放或升级一定完成。升级仍未补齐，未续跑至7633。
- parser06与observe8-01均exit0，进程reaped。最终runner相对stage1仅新增两个直接观察函数与一个mode分支，逆变换后旧方法逐字相同；未改变此前升级/settle/compat逻辑。生产SHA不变，全部663 UID不变。stage1.zip未覆盖；增量完整包包含该不可变阶段备份及本次原始结果。

[完整阶段包](evidence/2026-11-12-upgrade-handoff/stage2-observation.zip)：7688595字节，175项，SHA256 `48120f3a97d4f35d2f06b66cc0262f6435235e61d886ad9779bf278a257ea9fb`；[清单](evidence/2026-11-12-upgrade-handoff/stage2.members.json)、[阶段1汇总](evidence/2026-11-12-upgrade-handoff/stage1.summary.json)、[8步汇总](evidence/2026-11-12-upgrade-handoff/observe8.summary.json)。内含不可变stage1.zip（SHA927eff463edb0325eac7a2a27c28ed7a2581389e9bc9d8ff2d802c3d4c971313）。最新runner SHA256 `440540b3b325ff51098005cfffa9e8e302963b4f5c9d29adcf62190c5c0cfe59`。本地CRC/逐成员SHA通过；生产修复独立只读复核无提交阻碍，升级未完成边界不变。
