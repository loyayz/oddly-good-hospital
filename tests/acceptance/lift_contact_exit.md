# 电梯当前服务组出口包络回归

依据：电梯允许多个独立同行组同舱，当前组完成下客后才服务下一组；独立组各自保有移动成员、offsets 和出口位置。

本测试针对 `HospitalTransit._waiting_contact_exit` 的计算边界，不把预设状态当作真实已完成乘梯。构造多个同舱组和当前组的多个独立 movement owner，验证：

- 只取当前 active_group，不把其他舱内组的成员套入 primary 的 offsets。
- 各 owner 使用自己的 members/offsets 和 entry_cells，完整组出口不能漏掉。
- boarding/alighting 共用同一归属；其他楼层、idle 无当前出口。
- 缺当前组或 convoy 保持原有 fail-closed 行为。
- 旧单组连接兼容，查询不修改世界。

运行：`godot --headless --path . --script res://tests/acceptance/lift_contact_exit_runner.gd -- <result.json>`。

`lift_contact_checkpoint_runner.gd` 另用于失败首轮 checkpoint 冷恢复诊断：完整恢复世界，从命令回执恢复已提交命令键，继续 200 个真实生产步。它不提供性能指标，不替代原始负载的三轮基准，也不宣称业务覆盖通过。参数为 `<checkpoint.bin> <result.json>`。
