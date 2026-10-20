# 公共查询复用证据

基线：`b9bb59d59ec5db1d75f80e6db25f27f335f7fa41`。本组仅为合法160人快速诊断与相关功能回归，正式验收未执行。

| 文件 | 内容 |
| --- | --- |
| [quick-summary.json](quick-summary.json) | 三组未插桩完整步前后耗时、业务工作量、查询计数及输入/终态身份 |
| [stage-function-summary.json](stage-function-summary.json) | 同tick阶段和全实例函数耗时、调用次数、占比与探针开销；另含160步签名采集细分 |
| [movement-summary.json](movement-summary.json) | 前后完整360步派发、局部绕行、重复签名和当前终点占用观察 |
| [functional-summary.json](functional-summary.json) | 15项选例、首批SPACE-56失败与单例修复后通过、各批阶段时间 |
| [source-check.json](source-check.json) | 基线/最终439路径、验收109路径、二进制身份及25文件可逆诊断转换核对 |
| [raw-manifest.json](raw-manifest.json) | 压缩包SHA-256、237项路径/大小/摘要及逐项验证结果 |
| [raw-evidence.zip](raw-evidence.zip) | 原输入、完整结果与终态、逐步耗时、运行日志、诊断源码和身份、回归失败/通过及汇总生成脚本 |

原输入保持不变：公共 `1d83a8834528fd2f6c53dff06f6ec150c9e598eed675fc37521ab7e45fcadb10`，GP `a7cbe6d7075151f30f0935c7c802952a7dedc0b4f73a588dc1e52b793d904f27`。运营输入摘要见quick-summary。原目录结构保留在压缩包中，可按manifest逐项校验。

Headline收益仅取plain前后运行。全实例函数剖面保留原方法体，但仍有包装开销；inclusive与exclusive定义及覆盖清单在原结果中，不能加总嵌套耗时。原版本与修复版本的公共函数/移动观察分别复现各自plain终态；GP函数观察40步不能与plain80终态混比。

首批15项失败1项和后续SPACE-56通过均保留，不能只读取最后一批推断首批全通过。完整Release、渲染、容量、内存及两小时稳定性没有通过证据。
