# 入口、人物索引与冷启动证据

基线为`284efc9c339d23fe1299f901b1f7f738c2239876`。仅为固定合法160人的快速诊断与相关回归，正式性能验收继续暂停。

| 文件 | 内容 |
| --- | --- |
| [quick-summary.json](quick-summary.json) | 初始基线、中间A/B/B/A、最终完整步及运营交错结果；输入、工作量、计数和完整终态 |
| [operations-investigation.json](operations-investigation.json) | 上一轮P95变化的旧/新/新/旧复核、真实出舱与清扫完成触发链及归因局限 |
| [stage-function-summary.json](stage-function-summary.json) | 执行阶段、全实例函数、调用数/占比；入口、重建原因和区域冷建细分 |
| [functional-summary.json](functional-summary.json) | 17项不同选例，16项/6项/1项三个批次、复用范围及各阶段耗时 |
| [source-check.json](source-check.json) | Git基线、最终测量及验收源码匹配、二进制身份和可逆诊断转换 |
| [raw-manifest.json](raw-manifest.json) | 原始归档SHA-256及每个压缩条目的大小/摘要和验证数量 |
| [raw-evidence.zip](raw-evidence.zip) | 原始三份输入、所有测量与终态、逐步日志、源码身份、诊断转换及回归原件 |

完整步收益仅使用plain。函数探针保留原方法体，仍有观察和包装开销；inclusive不与子调用叠加，新增helper会改变exclusive归属。每个选定步的真实index按样本tick映射，不能将六条剖面记录的数组下标当成原360步index。细探针的tick是执行中world.sim_tick，完成结果的tick为下一tick。

中间修复、初始慢窗口及无收益结果全部保留，不覆盖成最终结果。每窗P95是各自短窗的统计，不能将两个窗口P95的均值当作合并正式分位数。完整步结果不含正式容量、渲染、内存或两小时稳定性验收。
