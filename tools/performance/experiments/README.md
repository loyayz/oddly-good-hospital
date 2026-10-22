# Worker 环境采样试验

部门环境采样默认启用 `WorkerThreadPool.add_group_task`，最多4个连续分片，诊断计时默认关闭。真实环境或空间服务存在自定义脚本注入时继续走原串行路径。本工具保留串行控制与固定完整负载的可复验对照，功能回归和短窗诊断不表示正式性能验收通过。

性能对照沿用同一合法160人输入和原公共360步、GP80步、运营40步窗口，保留原步长、随机流、规则、阈值与轮询间隔。plain完整步、root阶段和Worker计时分别报告。

`worker_sample_experiment.py` 只变换已准备好的 Godot 工程副本，不复制工程、不导入、不启动引擎，也不预热 Worker。当前仓库本身不能作为目标。

```powershell
python tools/performance/experiments/worker_sample_experiment.py --project="C:\path\prepared-copy"
```

副本必须已经包含生产 `game/operations/environment_sample_batch.gd`。工具只读核对该文件身份，从原 `representative.gd` 生成 `representative_worker.gd`，不修改生产采样源码或验收用例。所有片段和逆变换先完成检查；片段不匹配时不写文件。已经安装过的副本不能重复覆盖，应保留原证据并使用另一份副本。

副本根目录的 `worker-sample-source-proof.json` 记录生产helper身份、原/生成 SHA256及每个可逆替换。

运行副本时使用 `res://tools/performance/representative_worker.gd`，保留原 runner 的输入、输出、完整步数和 `--profile` 参数，并添加以下参数：

| 参数 | 默认 | 含义 |
| --- | --- | --- |
| `--workers=on` / `--workers=off` | `on` | 启用 Worker，或显式切换到原串行控制 |
| `--worker-tasks=1` 至 `--worker-tasks=4` | `4` | 完整请求的连续分片数，负载不减少 |
| `--worker-diagnostics=true` / `false` | `false` | 附加准备、派发、等待、合并、串行水许可和应用计时 |
| `--worker-records=true` / `false` | `false` | 每步计时结束后读取 `_last`，保留实际分片记录 |

Worker 服务在首个真实采样步内懒建。每个分片使用独立服务、查询与缓存容器；主线程在 barrier 后先完整校验结果，再按原 visit 顺序合入覆盖项、核验水许可及结算。`sample_worker_report()` 保留真实线程和完整处理数量。分片耗时是可能重叠的现实区间，不是线程 CPU；应用总时间包含串行水许可和覆盖合并，不能相加。

正常 GROW-75 已包含真实Worker回归：默认启用与4任务、自定义环境和CustomSpace串行交接、串行控制、缺结果回退、嵌套查询与缓存顺序、主体水许可及 unclamped 数值完成。检查预加载同一生产helper，无需通过性能工具安装。跨层和域外 Worker 请求仍未由该有限 helper 验证。工具不增加Worker算法或其他调度入口。
