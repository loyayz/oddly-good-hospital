# 混合场景业务事实诊断

独立入口继承 `plain_v4.gd` 的快照与统计方法，复用原观察器、原运营脚本和生产 `sim.step`。原 plain 驱动、覆盖门槛、输入、随机流、人员、候选和请求保持不变。原驱动没有逐步扩展点，因此独立入口只重写执行循环，不对 plain 或生产源插钩。

优先读取原完整末态，不推进模拟：

```powershell
<Godot> --headless --path <隔离工程> --script res://tools/performance/current/business_fact_probe.gd -- --inspect --input=<原0daf末态.bin> --output=<新inspect.json>
python -X utf8 -B tools/performance/current/business_fact_contract.py --inspect-report <新inspect.json>
```

末态模式直接恢复完整 World，执行 `World.validate`，读取十二例检查、原两设备工单、实际人员/Move/connector、病房/家属和保留账目，并比较读取前后的完整事实与 RNG。它不创建 Simulation、不执行命令或业务查询。已删除的住院、意向和请求无法由末态重建；保留的 `relative_of` 身份不证明曾有效探视。

需要历史交接时，固定原混合输入 `75f5e1d9…`，执行真实 1000 前缀＋6000 采样：

```powershell
<Godot> --headless --path <隔离工程> --script res://tools/performance/current/business_fact_probe.gd -- --input=<原mixed160.input.bin> --output=<新result.json>
python -X utf8 -B tools/performance/current/business_fact_contract.py --result <新result.json>
```

独立进程采用 app 主线程策略、4 个环境工作任务和 `OMP_NUM_THREADS=1`。启动应复用 `prepare_builtin_script_profile.run_process` 的独占进程、限时和错误守护；本入口不负责额外进程管理。`--smoke` 明确切换为 0＋2 步，只验证入口；完整诊断不接受自定义短窗口。

`.business.ndjson` 按实体字段变化记录输入、前缀和采样；包含实际状态、所有权、路径/局部目标/请求序、排队与生活阶段、工单余量和贡献、日探视意向及家属剩余时间。原始字段差异可按序重建，路径不因游标变化整条重复输出，静止位置不逐步刷日志。相关演员的真实身体/位置、成员和 convoy 作为变化时的上下文保留。已观察对象继续追踪，不能把离开观察范围误报为事实删除。

原始余量增减不直接归类为有效工作；终结清零、取消、重置均保留原值和阶段。没有保存在 owner 的瞬时拒绝原因不能由边界事实补造。完整有序事件和全部世界事实继续保存在 `.final.bin`，必须与原 plain `0daf82b8…` 严格相同；两步入口对应 `21aff254…`。覆盖不足原样保留，不将诊断计为资格通过。

```powershell
python -X utf8 -B tools/performance/current/business_fact_contract.py --self-test
```

离线契约覆盖字段链、创建/删除/重建、999→1000 分窗、终结清零、错输入/窗口/余量、重复/截断和错误时刻。它不运行游戏，也不替代 Godot 导入、入口、末态只读或完整重放验证。记录、序列化和 IO 有额外耗时；本工具不提供 plain CPU 收益结论。capture 包含变化行的写入，write 另含 header，两者均不含 footer 写入；计时重叠，不能相减当纯 CPU。
