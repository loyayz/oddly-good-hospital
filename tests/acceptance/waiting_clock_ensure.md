# 候诊时钟初始化

`PERF-11` 位于 `tests/acceptance/performance_contracts.gd::CASES`，由该专题的 `_case_11` 调用 `waiting_clock_ensure.gd`。`tests/run-acceptance.ps1` 从各专题的 CASES 生成目录并按 PERF 编号选择该专题，`tests/acceptance/runner.gd` 已包含 `performance_contracts`；不增加独立路由或共享控制器。

```powershell
pwsh -File tests/run-acceptance.ps1 -Case PERF-11
```

规则和范围：`HospitalWaitingLife.ensure` 只为缺失 clock 且没有实际 `admitted_tick` 的活跃 Visit 补齐时钟。仅有 `admitting` 的床位承诺仍需要普通时钟。已有 clock 保留 sequence、purpose、deadline 和原 Dictionary 身份，不因后来的住院事实而重置。新到达输入使用生命周期中的 `arrived_tick=900`，首次需求独立按到达时间加 `first_need_seconds` 换算；本项优化不确立历史字段之间的额外时间规则，也不改变生产初始化公式。

计算输入直接声明合法的普通候诊、待入床、已实际住院边界；病床和占用使用真实内容、布局及预约。World 校验分别检查输入、初始化结果、恢复和空医院。被测操作不执行模拟步，不证明患者曾真实到院、行走或入床。

待入床边界包含完整 Stay、已叫号票及正式 `request_move` 产生的行程意图；已入床边界使用原承托、使用收据和家属评估 owner 补齐声明历史。家属随机评估属于前置准备，测试在准备完成后冻结完整 RNG，再验证 ensure 不改变它；不运行整段临床前缀。

覆盖包括：

- 缺 clock 的新到达普通患者、仅 admitting 患者、带 `admitted_tick` 患者；新到达的首次需求间隔。历史 admitting 边界验证补齐及记录结构，不将旧字段差异定义为业务规则。
- 原时钟值、waiting_life／clocks／各时钟 Dictionary 身份不变；重复 ensure 完整世界与随机流保持。
- 同一步注册新活跃 Visit 只补新 clock；完成结算的 departed Visit 不重新获得 clock。
- 新 World 恢复后的活跃索引重建、所有暖 clock 保留，以及恢复输入单个缺失 clock 的补齐。
- 空医院第一次创建候诊及厕所队列集合，后续重复不变。

测试中的 `_admitted` 重载只计调用数，并调用原查询；不进入性能计时。三个缺 clock 输入各查一次；三个已有 clock 连续 ensure 五次合计零次；注册或恢复单个缺失 clock 时仅查一次。实际住院但始终缺 clock 的患者仍每次查原住院事实，其他 dispatch 路径和全部活跃 Visit 的遍历不变。

后续局部性能验证使用真实 mixed 完整终态 `0daf82b8…` 和全部 Actor／Visit／WardStay，不改事实或随机流。先核一次 ensure 的完整结果及输入只读边界；若出现合法初始化，先记录差异，不能删患者或伪造 clock 凑只读。原 ensure 从优化前固定 Git 方法体逐字节取得，仅该方法参与 A/B，其他源、内容、DLL 和引擎相同。独立计数运行后，再在主线程用普通 HospitalWaitingLife 做三对交替 A/B，每对每侧固定 1000 次完整 ensure；保留所有原访问，记录原 World/RNG、结果相同及每组时间。该局部操作不代替 160 人整步性能验收。

独立入口为 `tools/performance/current/waiting_clock_probe.gd`，沿用局部 probe 的 `--input`、`--expected-sha`、`--output`、`--iterations=1000` 参数。输入固定完整 `0daf82b8…`；原 ensure 来自 `9368fc6` 的 Git blob `c99ef187…`，去除工具子类的一层缩进后逐字节匹配，运行时重新核方法及整文件逆替换摘要。计数预期来自实际活跃全集和已有 clock，不写死活跃人数或零查询结论。每侧计数运行也执行 1000 次，三对普通计时不带计数重载。

当前仅准备实现和用例；引擎导入、`PERF-11` 及局部计时等待统一执行窗口，尚未运行。
