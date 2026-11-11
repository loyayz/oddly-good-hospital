# 本地脚本累计性能诊断

Godot 4.7.2 的本地 `scripts` profiler 在关闭时向 stdout 输出累计函数调用数、总耗时和自身耗时。诊断使用现有完整输入、真实生产模拟步和业务观察器；不改变合法负载、步长、窗口或性能标准。它用于选择优化方向，不构成 plain 性能验收。

`prepare_builtin_script_profile.py prepare` 只复制明确冻结的工程及其五个 DLL，并局部修改副本的 `plain_v4.gd`。原主目录的生产代码和共享 driver 不变。准备时校验权威 source identity、完整清单、已验证生产源、输入、引擎两级可执行文件与 DLL；清单中的其他文件逐字节保持。manifest 保存全部替换文本，逆序去除后必须恢复原 driver 的 SHA256 和原字节。

原长 `_run` 调用帧在预热结束后直接调用 `EngineDebugger.profiler_enable("scripts",true)`，完整采样后直接关闭。不开启启动即采集的 `--profiling`。关闭及累计表打印在 `window_end` 之后；预热不启用 profiler。跨启停边界的 `_run` 控制帧不用于热点解释。纯 marker 每个采样步调用一次，前缀 marker 仅在预热调用；两者无世界、随机流或资源副作用，三种模式执行相同 marker。

短资格串行执行同一完整输入的 `plain`、`debug-off`、`scripts` 三个新进程，全部为 0+2 步。后两者使用 `--debug --ignore-error-breaks`；`debug-off` 不启用 profiler。分别核对实际 `has_profiler/is_profiling`、启动和停止 tick、marker calls=2、前缀 calls=0、耗时健康、表容量、无脚本错误、完整 World 与有序 events 的相同最终 envelope SHA256。首次两步沿用既有完整事实见证，不以观察摘要替代事实比较。

准备示例（不启动引擎）：

```powershell
python -X utf8 tools/performance/current/prepare_builtin_script_profile.py prepare `
  --base-project .cache/resident-mask-source-hybrid01 `
  --authority .cache/resident-mask-final-identity.json `
  --input .cache/performance160-clinical-family-20261112-v3-prep01/input01/comprehensive160.input.bin `
  --input-sha256 752924c562f275804cee40cbd2a8760f8f0780cab3276a04330db63a2866e780 `
  --short-expected-final-sha256 f332ee5b20de51ece182f79866f5780d4792652bdb8169e0b3d9900e5af091d7 `
  --output .cache/builtin-script-profile-20261112-qualification01/project
```

获得独占引擎槽后才执行短资格；`--import-project` 仅在副本确需重新导入时添加：

```powershell
python -X utf8 tools/performance/current/prepare_builtin_script_profile.py qualify `
  --project .cache/builtin-script-profile-20261112-qualification01/project `
  --output .cache/builtin-script-profile-20261112-qualification01/qualification `
  --profile-stages
```

完整诊断使用 `run --project ... --output ... --outcome-reference <同输入plain的r1.json> --profile-stages`，固定 1000+6000 步。每次升级生产源都从新的明确冻结工程重新 prepare，不能把旧源与最新 DLL 或共享工具混合。执行器为每个进程隔离 APPDATA、LOCALAPPDATA、TEMP/TMP，记录命令、引擎、源、DLL、线程策略和 worker 配置。超时或脚本错误只终止当前 Popen 拥有的进程树，使用 `.NET Process.Kill(true)` 和有界等待；失败日志和未完成结果保留，不覆盖成通过。

每个模式保存完整 `.final.bin`、原 driver 结果、`.builtin-profile.json` 和 engine.log。脚本模式另保存 `functions.json/csv`；解析器仅接受显式括起的最终 `ACCUMULATED` 表，忽略周期 FRAME 表。函数表达到 32768 项标为可能截断，不能声称完整。只读离线转换也可独立执行 `parse_builtin_script_profile.py --log ... --output ... --csv ...`。

现有 root-only StageTimer 覆盖全部采样步，`nested=false`；不启用高频手工调用栈 wrapper。标准 profiler 是跨线程、跨调用者的平面累计表，包含观察器及工具，工具函数单列；被工具和生产共享的 callee 无法据此拆成纯 step CPU。总耗时包含后代，不能相加；自身耗时仍可能包含未拆开的原生调用、等待与诊断扰动，也不能相加为主线程 wall。

`--debug` 本身增加逐行断点检查和调试轮询；标准 profiler 也增加原生计时与计数。短资格记录三种模式的实际差值，但两步结果不能估计完整窗口扰动或宣称更快。正式诊断继续报告相同输入的 plain 与诊断耗时、stdout 量和停止打印耗时。完整事实见证相同只证明本次观察未改变业务结果，不证明零扰动。

接口依据为 [本地 profiler](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/debugger/local_debugger.cpp)、[命令行开关](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/main/main.cpp)和 [GDScript VM 计时边界](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/gdscript/gdscript_vm.cpp)。`ScriptLanguageExtension` 的 profiling 虚方法是语言实现接口，不能作为现有 GDScript 的读取接口；该工具使用原生本地 profiler 的标准日志出口。

2026-11-12 短资格的三种模式各完成原完整输入的 2 步（tick 633→635），36 项检查通过，完整 World 和有序 events 的 envelope SHA256 均为 `f332ee5b20de51ece182f79866f5780d4792652bdb8169e0b3d9900e5af091d7`。复用已验证导入缓存，无新增全局脚本类，无重新导入。

| 模式 | 新进程墙时 | 两个 step 合计 | 包含观察的采样窗口 |
| --- | ---: | ---: | ---: |
| plain | 5.224510 s | 356.903 ms | 366.735 ms |
| debug-off | 5.430432 s | 359.783 ms | 369.040 ms |
| scripts | 6.839223 s | 420.242 ms | 432.449 ms |

脚本模式输出 1959 项，其中 641 项有调用，未达到容量；marker calls=2、total=self=1 µs，前缀 marker calls=0，实际启停状态及 root 阶段分区通过。关闭和累计打印为 1.150894 s，发生在采样结束之后；周期 FRAME 表为 0。以上差值是两步冷启动观测，不能外推完整窗口开销或推断当前游戏热点。可追溯摘录见 `docs/reports/evidence/2026-11-12-clinical-performance/builtin-script-profiler-qualification.json`，原始日志保留在 `.cache/builtin-script-profile-20261112-qualification01/qualification`。
