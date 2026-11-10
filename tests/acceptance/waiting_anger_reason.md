# 自然平静的座位理由读取

本专项只优化 `HospitalDepartments._sample_anger` 自然平静分支对候诊摘要的消费。该分支原本只检查 `seat.phase == seated` 且 `reasons` 非空；不消费场景、完整分数、理由文字、排名或种族偏好标记。原生候诊服务改为读取这个布尔投影，保留完整设施报价与动态有效性，再先判断无需邻居的条件；不能证明有正权重理由时才使用原邻居规则。自定义候诊服务仍调用其原 `patient_summary`。

这不是玩法修正。`docs/design/08-hospital-life.md` §2 写的是“坐上满足偏好的兼容座位额外减0.5”，当前实现实际用性格理由，而非物种 `_preferred`。两者不等价。本次有意保留既有消费结果；该差异须另按设计处理，不能用本次兼容性断言替代设计依据。

| 选择器 | 覆盖与边界 |
| --- | --- |
| ANGER-SEAT-MATRIX | 10 种性格 × 11 条件：八项理由各自正反、全部否、安抚椅低于阈值及已领取。使用既有 SeatObservations 隔离条件算术，合法已坐边界、真实报价和邻居计算不替换；从配置权重独立推导预期。比较完整原摘要判断，以及两种调用路径的怒气和来源累计。 |
| ANGER-SEAT-BOUNDARIES | 无就诊、无座、未坐、生活需求、设施删除、非公共设施、改建阻挡；失效标记保持原公共椅报价结果。删除/失效所有权等诊断输入明确不声称是合法流程。 |
| ANGER-SEAT-LIVE | 原生环境/空间/候诊服务，真实派工、移动和开工产生噪声，真实暂停后恢复；安静→施工→暂停→恢复存档的布尔值为 true/false/true/true，噪声 0/15/0/0，环境值 43/28/43/43。已坐输入只用于观察，不宣称覆盖入座到场。 |
| ANGER-SEAT-FRIENDS | 朋友闲等、实际独行、实际同行队列（从者没有独立 moves）、实际乘梯，以及活动中恢复；原邻居资格不变，观察不改世界。 |

`ANGER-SEAT-MATRIX-CHAIRS` 及 `ANGER-SEAT-FRIENDS-OWNERS` 只选择相应前置输入修复后需重跑的子组。记录各次结果并按明确子组复用通过证据，不把失败的整组报告描述为通过。

相关旧回归只选 STAFF-30（完整选座分数/顺序）、STAFF-32（噪声怒气分量）和 STAFF-42（完整邻居报价、真实占座变化及饮水）。它们不证明全院、渲染或实机性能。

入口：`--headless --path <repo> --script res://tests/acceptance/waiting_anger_reason_runner.gd -- <output.json> ANGER-SEAT-MATRIX ANGER-SEAT-BOUNDARIES ANGER-SEAT-LIVE ANGER-SEAT-FRIENDS`。运行时须与证据身份一致；本轮是 Godot 4.7.2，不能默认为系统 Godot 4.6.3。

局部性能固定为 160 人、100 次已坐静音罩椅的布尔读取，只测完整摘要与布尔 API，不是完整 tick 或座位选择。仍需邻居才能决定的输入会使用原查询，不宣称消除所有全员扫描，也不建立新动态索引。
