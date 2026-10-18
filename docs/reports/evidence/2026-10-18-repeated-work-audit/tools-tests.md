# 工具与验证代码重复工作排查

范围为 tools、tests 和 addons/source_assets 下的自有代码。文件清单逐文件初筛循环、全集合访问、完整拷贝、序列化和调用点；重点语义核对验收驱动、检查点、采样控制器、离线统计与新增逐步测量。以下均为静态结论，没有运行正式捕获或长稳。

## 确认的重复模式

| ID | 代码与触发 | 重复工作与现有边界 | 最小安全方向 | 状态 |
| --- | --- | --- | --- | --- |
| T01 | tests/run-acceptance.ps1:84；checkpoints.gd:26–35 | 前置状态身份包含全部 game、content、assets 以及整个 builder 文件哈希。只改 UI/可视资源或同 builder 中无关边界，也会改变所有相关检查点目录并重新真实生成。不是每个 case 默认重跑全套：runner.wants 和专题入口已先选择。 | 先显式定义各命名边界真实依赖；仅排除证明不会参与 headless 生成的 UI/展示资源，保留全部业务、内容、随机流、运行时身份和祖先生成依赖。不能仅按目录粗暴删哈希字段。 | 静态工具候选；没有测量本轮由无关变更引起的重建成本。 |
| T02 | tools/performance/acceptance/analyze.py:37–57 | bounded_distribution 对每个可选样本数 k 重新拼接全部 definite 并排序两次；即 optional=0 也重复排序相同总体。成本 O((Q+1)(D+Q)log(D+Q))，还保留两份全部候选统计数组。 | definite/optional 各排序一次，使用精确次序统计/归并及前缀和计算所有 k 的原上下界。保留每一个 k、nearest-rank、完整总体和不确定性，不能挑有利边界或截样本。 | 静态离线候选；不属于本轮 Simulation.step 耗时。 |
| T03 | analyze.py:508–522、step_population:227–235 | 每个密集片段都从 all_frames、steps、telemetry 全量筛选，再调用 speed_window；step_population 自己又对同一 steps 重复 membership。成本随片段数乘完整记录数增长。 | 一次建立按原 QPC/原始顺序查询的索引，逐片段取准确区间；保持各片段独立统计、边界不确定性和暂停归属，不能把片段合并冒充连续场景。 | 静态离线候选；没有正式密集采样或两小时结果。 |
| T04 | tools/performance/acceptance/capture.ps1:224–232，frameStarts 在129追加 | 当操作/步数条件已满足而最小实时时长或帧数尚未满足时，每100ms再次扫描所有累计展示帧起点计数，再检查时长。帧总体随时间增长。当前两小时计划的最后操作在7200秒后，不能据此声称该计划必然全程反复扫描。 | 对固定 windowStart 使用追加游标，每个新增 frameStart 做一次相同判断；保留原选链、去重、边界和完整 CSV，不依赖帧起点天然有序，不删原始证据。 | 静态采集器候选；未实际测量对被测进程的扰动。 |

## 已核对而不作为生产优化问题

- runner.gd 在专题加载和专题内部均先用 wants 选择，缺结果按失败，未发现先跑全部断言再过滤的路径；每批只有一次工程准备。
- checkpoints.gd 的每次独立 clone、完整 facts/RNG 校验与校验和属于输入隔离和恢复契约，不能删除来获取测试速度。_states 已在同进程复用命名边界。
- fixture.gd 的每房间扫描小型 layout 定义、初始静态/身体合法性检查属于一次性前置构造，未进入普通完整步；没有把它们当成实测经营热点。
- 新 representative 驱动的完整观察、事件展开、逐步证据落盘和最终 freeze 均在 .step 计时外；前后相同测量规则。插桩本身开销另外计量，无插桩窗口负责收益结论。
- step_profile 的逐调用记录只在内存，根阶段互斥；嵌套包含时间不相加。每步样本副本用于保留独立证据，没有在生产路径引入全世界拷贝。
- decode-etl.cs 按 event id/version 建 schema 字典再解码当前 payload，source_assets 导出插件也先建路径字典；未发现每事件或每导出文件重扫全部 schema/manifest。
- solver_oracle.py 的完整组合/精确消元是独立小规模正确性 oracle；不能裁掉组合来冒充验证优化。构建/导出脚本的完整输入身份检查属于一次发行边界，不冒充逐帧成本。

以上候选不自动成为本轮采纳项。正式工具和发行验收继续暂停；没有改变阈值、统计总体或验证要求。
