# 候诊环境数值读取专项

依据：`docs/design/08-hospital-life.md` §17.2–17.4、`docs/design/06-validation.md` V341、V375。

业务规则不变。候诊选座、单椅报价和患者摘要只消费环境数值及偏好字段；拥挤与朋友仍由候诊生活服务的真实可达邻域计算。公开环境观察与热图继续提供来源和附近人数。

| 选择器 | 边界与断言 |
| --- | --- |
| WAIT-ENV-CONSUMERS | 7 种合法输入：朋友、隔墙、移动朋友、大身体、3 格距离、小数桶边界、拥挤朋友。使用原生环境服务和 canonical floors；与旧调用比较完整候选顺序和单椅报价，确认真实 observation bounds 已准备、事实/RNG 只读、环境人口桶构建为零。 |
| WAIT-ENV-LIVE | 实际可用水点、灯故障、污物删除和恢复。独立断言水/光/清洁与数值变化，并比较公开详细环境与原始事实参考的全部字段、来源和人数。 |
| WAIT-ENV-SUMMARY | 从合法已占罩椅边界开始，真实派工与移动使装修进入工作，再暂停。摘要在无噪声/施工噪声/暂停间切换场景；独立断言噪声 0/15/0、环境 43/28/43 和完整摘要等值。 |

执行：Godot 4.7.2 `--headless --path <project> --script res://tests/acceptance/waiting_environment_sample_runner.gd -- <result.json> <selectors...>`。

现有关联回归：STAFF-30、STAFF-32、STAFF-42。STAFF-30/32 的注入观察对象无 `sample_at`，验证兼容后备及既有规则，不能代替本专项的原生路径。

本专项不修改导诊、移动、索引所有权或 worker 协议；不宣称消除了候诊拥挤判定或公开热图的其他全量读取，也不代表整院性能结果。
