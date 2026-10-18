# Windows Release 外部采集

`capture.ps1` 启动并持有本次唯一游戏进程、PresentMon 和可选 GPU/ETW 采集进程。每次使用新输出目录、运行 UUID 和 ETW session 名；只停止本次 session 和 owned PID，不按程序名查杀。采集退出0只表示生命周期、操作门闩与尾帧完成，性能结论由离线报告给出。

## 首160场景

需要最终 Windows x86_64 Release、匹配的独立 PCK/原生 DLL、PresentMon2.3.1 和已验证的 `160four.input.bin`。先用最终导出包做兼容性探针；正式采样使用实际安装的最终 Release。导出探针与安装/启动验收分别报告，不能由探针通过推定游戏流程通过。

最小探针使用同原EXE/PCK/DLL的隔离副本和标准启动场景override，参数路径全部取绝对路径：

```powershell
$repo = 'C:/code/loyayz/oddly-good-hospital'
$product = "$env:LOCALAPPDATA/Programs/oddly-good-hospital"
$probeUnit = "$repo/.cache/formal-probe-"+[Guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Path $probeUnit | Out-Null
Get-ChildItem -LiteralPath $product | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $probeUnit -Recurse }
$probeScene = "$repo/tools/performance/acceptance/probe.tscn"
$profile = 'OddlyGoodHospital Formal probe-'+[Guid]::NewGuid().ToString('N')
"[application]`nrun/main_scene=`"$probeScene`"`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$profile`"" | Set-Content -LiteralPath "$probeUnit/override.cfg" -Encoding utf8NoBOM
Push-Location $probeUnit
try { & "$probeUnit/oddly-good-hospital.exe" -- "--output=$probeUnit/probe.json" } finally { Pop-Location }
```

探针报告须 `valid=true` 且进程exit0。标准Release通过原exe旁override.cfg的application.run/main_scene进入外部Node主场景，不能依赖被Release忽略/拒绝的--main-pack/--script入口。禁止以editor/debug executable、headless、固定帧模拟或开发工程path替代最终产品。探针不挂载医院；外部继承、Fixture、资料目录隔离和实际经营还需场景本身成功。

`fixtures/Expand-Scenarios.ps1` 提供共用矩阵与实际输入绑定；`scenario.example.json` 是首160配置示例，须将 input_path 改为实际已验证输入的绝对路径。示例同一窗口采180现实秒以覆盖原自动保存周期，达到帧/步最低样本且操作完成后才允许结束。20步边界余量只延长收集，不冒充最终归属样本。普通场景不统一固定600秒；两小时场景另将 minimum_capture_real_seconds=7200，watchdog同时延长。

```powershell
pwsh -NoProfile -File "$repo/tools/performance/acceptance/capture.ps1" `
  -Exe "$product/oddly-good-hospital.exe" -Pack "$product/oddly-good-hospital.pck" `
  -Scenario "$repo/.cache/formal-scenarios/B1.json" `
  -Output "$repo/.cache/formal-capture/B1-new-run" -TimeoutSeconds 900
python -B "$repo/tools/performance/acceptance/analyze.py" "$repo/.cache/formal-capture/B1-new-run"
```

输出目录必须不存在且不能嵌在源发行目录。采集器重写本次run_id/output_dir，复制最终scenario与完整发行单元到output/product，逐文件核对源复制前/后与副本SHA256，再只在副本写本次override.cfg。标准startup custom profile在引擎启动前生效；原产品override和玩家资料不修改。product-copy.json及capture.json记录身份。一个目录仅对应一个实际工况；不能复用输出目录覆盖失败证据。NoGpuCounters仅关闭PID聚合旁证，不使图形资源验收自动通过。

## 时钟、停止与完整区间

PresentMon固定 `--v1_metrics --qpc_time --process_id <owned PID> --output_stdout --session_name <UUID>`。QPCTime是原始QPC ticks；MsUntilDisplayed/MsBetweenDisplayChange是毫秒。显示终点为 `QPCTime + MsUntilDisplayed*frequency/1000`，起点再减完整显示间隔。不得把 CPUStartQPCTime 当成该 Present 时刻。

采集器先等 CSV schema，再 armed；运行器完成实际预热后 prepared。start/stop ACK必须具有相同generation、owned PID和QPC frequency，原生ACK采样须落在命令发布到外部读回之间。报告窗口从started ACK之后第一个真实不同显示帧边界开始，终点为完整业务边界的stopped ACK。收到stop请求时的原在途步骤等待仍属于原窗口，不能以请求时间截断。

stop前同时要求真实帧数量、运行器步骤门闩、操作完成和场景最小时长。最终有效步数量仍由原始 started/completed_engine_us 的时钟夹界判定，门闩数量不能代替它。持续采集到终点之后第一个不同显示帧，才发送tail_ack；正常退出还要等待原退出checkpoint、writer、dispose及guard释放。TailTimeoutSeconds只约束显示尾，ExitTimeoutSeconds另约束正常退出（默认300秒）。超时/强杀/非零退出完整保留，不能称完成。

进程内存通过Windows GetProcessMemoryInfo读取，工作集和私有提交分别记录，内核生命周期峰值另列。窗口轮询最大值不是未观测时段上界；窗口后采得的内核生命周期峰值可作为该窗口上界，但不是窗口局部精确峰值。采集器与各helper的CPU、观测工作集及轮询耗时独立记录，不从游戏样本扣除。

## 真正Windows输入

运行器的 input-request.json 使用 `{id,status:'armed',pid,fields:[{name,client_point:[x,y],text}]}`。client_point为控件 `viewport_transform * global_transform` 所得的物理客户区坐标，包含根窗口content stretch。不能使用在嵌入子窗口模式下省略根stretch的 `get_screen_transform()`。采集器编译 input-driver.cs，在DPI感知作用域内逐字段核验owned前台窗口和物理client边界，调用Windows `ClientToScreen`后执行原SendInput：真实点击、Ctrl+A、UTF-16 Unicode键入、Enter。不强抢前台，不发窗口消息，不调用Godot伪输入。

input-ack.json保留send_begin_qpc/send_end_qpc/frequency、实际client/screen坐标及失败原因。前台不符或坐标错误时本次操作失败，不能转用脚本赋值代填。运行器的预览完成callback仍不是已显示画面的精确时刻；报告区分真实输入、完整结果callback和外部显示候选，缺少正确画面关联时保留对应缺项。

## Arc资源探针

在上述命令加 `-AllocationTrace`：采集器先启动owned DxgKrnl session并等allocation.ready.json，之后才创建游戏进程，把真实PID/start_utc_ticks绑定给trace watchdog。该顺序覆盖本次启动后的资源生命周期，不能把晚附加称启动前覆盖。已存在的共享分配仍可能需要rundown，其缺失会保留unknown。该trace是另一个需记录开销的系统级旁证，不仅过滤目标PID，因跨进程别名去重需要相关事件。

```powershell
pwsh -NoProfile -File "$repo/tools/performance/acceptance/decode-dxgkrnl.ps1" `
  -Etl "$repo/.cache/formal-capture/B1-new-run/allocation/dxgkrnl.etl" `
  -Output "$repo/.cache/formal-capture/B1-new-run/allocation/events.ndjson"
python -B "$repo/tools/performance/acceptance/gpu-ledger.py" `
  --events "$repo/.cache/formal-capture/B1-new-run/allocation/events.ndjson" `
  --trace "$repo/.cache/formal-capture/B1-new-run/allocation/trace.json" `
  --schema "$repo/.cache/formal-capture/B1-new-run/allocation/provider-schema.json" `
  --output "$repo/.cache/formal-capture/B1-new-run/allocation/ledger.json"
```

decode保留事件版本、opcode、header PID、命名data及ordered data_fields；payload PID才用于资源归属，不能拿系统工作线程header PID替代。Get-WinEvent只给转换后的SystemTime，qpc_ticks明确null；不能据此直接联成精确采样窗口驻留账本。GPUProcessMemory CIM 是PID/adapter聚合，不能提供allocation identity/shared dedup。实际分配、Arc适配器、生命周期代次、共享别名、未释放资源、原资源所有者和驻留口径尚须实际事件与后端证据闭环。任何未知都不填0，不把Godot payload计为OS驻留。

## 离线工具检查

```powershell
python -B tools/performance/acceptance/self_check.py
pwsh -NoProfile -Command "Add-Type -Path tools/performance/acceptance/trace-status.cs; Add-Type -Path tools/performance/acceptance/input-driver.cs"
```

合成自检、PS AST和C#编译仅验证工具，不是游戏运行、ETW事件可用性或性能通过证据。
