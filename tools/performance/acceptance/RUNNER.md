# Release 可见运行器

运行器使用最终 Windows Release 的原 EXE、同名 PCK 和 DLL，在独立发行单元中通过 Godot 的标准 `override.cfg` 加载外部主场景。`launch.tscn` 中的 Node 使用现有 SceneTree；它从原 PCK 实例化真实 AppRoot、HospitalView、HospitalSimulation 和 GameSession。模拟由原 AppRoot 的真实现实时间驱动，不停用到院准备，不改变步长、工时或业务服务。

## 启动与身份

标准 Godot 4.7.2 模板默认禁用 CLI 路径覆盖。`--main-pack` 会报错；即使接受了 `--script` 参数，启动代码也会清空脚本并运行原主场景。正式入口使用独立复制发行单元旁的 `override.cfg`，不修改原发行目录或 PCK：

```ini
[application]
run/main_scene="C:/absolute/tools/performance/acceptance/launch.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="OddlyGoodHospital Formal RUN_ID"
```

进程参数只有用户配置，例如 `-- --config=C:/absolute/capture/scenario.json`。RUN_ID 必须等于采集器写入该配置的 `run_id`。启动前的独立配置保证渲染器也使用独立用户目录。运行器校验 ProjectSettings、`OS.get_user_data_dir()` 和 `user://` 的实际解析结果，拒绝已有医院资料库。引擎自己产生的启动缓存不构成玩家资料。采集器负责新运行身份、初始目录检查、复制发行单元和启动配置；参见 [CAPTURE.md](CAPTURE.md)。

`probe.tscn` 是相同方式加载的轻量探针，参数为 `-- --output=C:/absolute/probe.json`。它检查真实 `template && release && !editor && !debug` 特征、原 PCK 资源、三个原生类、真实 QPC、GameSession 信号和 TickResult 四个计时字段。探针不会创建医院或打开玩家资料库。探针成功只证明入口及这些依赖可用，不能代替实际界面、保存或性能验收。

原 EXE/PCK/DLL 哈希由采集器保留，`boot` 另记录外部脚本、两个外部场景、`override.cfg`、输入二进制及内容指纹。实际观测目标仍是相同发行代码和资源；外部启动配置属于采集工具身份。标准设置覆盖与 CLI 路径覆盖是不同开关，依据 [Godot ProjectSettings 启动源](https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp#L690-L703)、[CLI 脚本清空逻辑](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L4018-L4029)和[特征标签](https://docs.godotengine.org/en/4.7/tutorials/export/feature_tags.html)。

## 输入与实际配置

`input_path` 指向已有合法 Fixture 的绝对二进制路径，保持原 `store_var()` 信封：

```text
{content_fingerprint:String, facts:Dictionary, floors:Array, visitor_ids:Array}
```

运行器使用 `get_var(false)` 禁止对象反序列化，独立检查当前内容指纹、`WorldState.validate()`、生产 gameplay_version 和实际 `present_actor_count()`。四层、宽层、高层分别核对 `[1,2,3,4]`、`[1]`、`[1,10,1000,10000]`。人数不会由信封标签或可见绑定数替代。`workload_kind=reference` 使用 160/320/640 档；命名 `boundary/history` 输入仍按其真实正人口核对，不将这些恢复状态伪称原始人口组。

场景必须包含 `run_id/output_dir/input_path/actors/layout/floor_id/window_pixels/scene_scale_bp/ui_scale_percent/speed/minimum_frame_samples/minimum_step_samples`。可选字段和七组代表矩阵见 [fixtures](fixtures/README.md)、[DENSE_MATRIX.md](DENSE_MATRIX.md)及采集器场景示例。帧/步最低样本必须与原 balance 合同一致，当前各为 1000；速度只用真实 1×/3×，场景比例使用 10000/7500/6667，UI 使用 100/200。

运行器设置原视口三维比例和原 UI 方法，记录实际窗口像素、逻辑视口、canvas 变换、SubViewport 尺寸、UI 倍率、渲染方法/驱动、GPU、刷新率、vsync 和帧上限；实际设置与请求不符会失败。实际后端分配尺寸和完整图形驻留仍由外部证据确认，不能用标称比例乘像素代填。若产品现有 canvas stretch 使逻辑 UI 范围与物理窗口不同，保留原行为并写 `coverage_gap`，不通过采集工具另改界面来制造原生 UI 结论。

## 预热、门闩与退出

初始预热要求至少 32 个真实完整步、真实工作量曾减少、当前显示绑定完成且无资源错误，以及原完整业务边界。正在运行的未来日准备任务不阻止预热结束：它属于普通经营成本，继续留在正式窗口中。若当前日所需准备尚未就绪，原完整步自然无法满足门槛；运行器不额外等待未来任务 `jobs>0`，也不轮询替代推进。

预热截图 `prepared.png` 保存后发出 `warmup_complete` 和 `prepared` ACK。截图来自实际根视口读回，属于图像佐证，不能充当已显示帧或 OS 输入可见终点。采集器通过下列固定文件握手：

| 文件 / 类型 | 字段与含义 |
| --- | --- |
| `control.json` | `{phase,generation,qpc_before_write,qpc_frequency}`；phase 为 armed/start/stop/tail_ack |
| `ready.json`、`capture_ready.json` | 相同 `{phase,generation,engine_us,qpc_ticks,qpc_frequency,completed_steps,operations_complete}`；phase 为 prepared/started/operations_complete/stopped |
| `telemetry.ndjson` | 原步骤、播放、操作、资源、时钟和结束记录；引擎 callback 单列诊断，不计已显示帧 |

控制器发布时采用原子文件替换；ACK 的双文件顺序写入允许读方遇到不完整 JSON 后重试。`start/stop` 等待原完整步、保存与载入作业边界，已经开始的准备等待不能被截断。`stop` 还需满足实际完整步最低数、所有配置操作完成和 `minimum_capture_real_seconds`。帧最低数及完整尾帧由 PresentMon 采集器负责，不能从引擎 callback 数推算。

`capture_end` 固定该次采样边界；真实游戏继续运行，等待采集器取得下一不同显示帧后发 `tail_ack`。此后保存 `after-tail.png`，再调用原 `_request_quit()`。原退出检查点的真实回执、原 simulation.dispose 和 guard 释放完成后，才写 `scenario_complete`、`exit` 并关闭遥测。末尾继续运行产生的 tick 不扩张原速度分子/分母。退出检查点和线程收尾可能需要真实等待，不能用较短的尾帧看门狗误杀正常保存。

超时、准备错误、保存失败、未完成原操作、提前关闭或缺少尾帧均为未完成。`performance_pass` 保持 null；运行器成功退出只说明采集生命周期完整，最终阈值、采样与证据缺口由 [REPORTING.md](REPORTING.md)定义的报告判定。

## 步与 QPC

每个原 `tick_completed` 信号只记录它自己的真实结果。`started_engine_us/completed_engine_us` 直接来自原 kernel 起止；`elapsed_us` 包含步内各轮询之间的真实等待，`main_elapsed_us` 是原 `step_nonblocking()` 执行片段墙钟耗时之和，均不是 OS CPU 时间。两者差值命名为 `between_slices_wall_us`。这些计时属于观测结果，不进入 facts 或存档。

回调第一步采样原生 `PlatformArrivalMath.monotonic_clock()`。返回的 `qpc_ticks/qpc_frequency` 与 PresentMon raw QPC 同域；`completion_qpc_ticks` 只表示稍后的通知观测，不能替代之前的原完成时间，更不能倒减 elapsed 伪造原开始。每行保留 `qpc_role`，区分原引擎时间与现在的观测。

`clock_sample` 在启动、500ms周期和采集起止边界执行 QPC-before / engine-us / QPC-after。历史 engine 端点按前后实际单调样本保守夹界，保留宽度；不默认零漂移、不取中点当精确锚点。边界归属不确定的步骤保留缺项。速度只使用同医院/会话和真实播放分段的完成步，不能减不同医院的 tick。暂停意图发生在已开始准备等待期间时，原完整步继续属于此前分段。

## 操作与证据责任

`panel/floor/overview/pan/zoom/save` 使用原回调。`operation_driver.gd` 还提供原 view rebind、navigation trim、自动保存等待、换班/日界、第二院创建/切换、真实改建、业务命令及外部真实预览输入；具体参数和合法前提见 [OPERATIONS.md](OPERATIONS.md)。操作按 `after_real_seconds` 顺序执行，一次只保留一个未完成操作。原失败回执不被改成成功，也不自动重试过期报价。

每个回调可记录逻辑 frustum 绑定密度；`dense_target_actors=0` 明确不申请密集责任。正值密集区间仍需实际可见 ID/画面和足够独立完整样本佐证，不能拼接稀疏片段。资源计量保留实际所有者口径；Release 不可用监视器的 0 值不能当真实零占用。

首 160 场景、最大预览合法成功前提、加载中实际改建、两小时周期表、64/128MiB恢复以及完整 GPU 分配/驻留分别保留其真实结果和缺项。代码支持某项操作不等于该项已取得实机证据。JSON、写盘、截图、观察回调和外部采集开销均须记录，不能静默扣除普通帧中的监视成本。
