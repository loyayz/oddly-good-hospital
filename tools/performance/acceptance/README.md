# Release 性能验收

验收依据为 `docs/design/04-technical.md` 第9节、发布数据的 `performance_targets` 和 `docs/specs/26-10/2026-10-16-performance-validation.md`。固定负载的诊断短测、功能回归、Release 构建及正式性能采集分别记录，互不代替。

## 运行边界

1. 完成受影响功能回归，提交生产实现和工具源文件，再用 `tools/build-game.ps1 -Output <新发行目录>` 导出 Windows x64 Release。保存该目录的 `build-identity.json`，同一次结论的工况使用同一 EXE、PCK 和 DLL。
2. 按 [fixtures](fixtures/README.md) 生成并校验只读输入。输入必须保留实际工作、移动、预约、随机流和完整业务所有者；未通过的前提不进入采样。
3. 在独立发行副本旁用引擎内置的override.cfg选择外部probe.tscn，并在启动前设置全新的独立profile，执行probe.gd探针，核验Release标签、原业务脚本、信号、计时字段和原生QPC。探针不打开玩家存档。
4. 按 [工况矩阵](DENSE_MATRIX.md) 配置独立 JSON，使用 `capture.ps1` 启动可见发行进程及所属采集会话。运行入口和时钟边界见 [RUNNER.md](RUNNER.md)，实际操作与前提见 [OPERATIONS.md](OPERATIONS.md)。
5. 用 `analyze.py` 分析原始采集，保留缺失项、超标项、超时和先前失败。采集接口见 [CAPTURE.md](CAPTURE.md)，判定口径见 [REPORTING.md](REPORTING.md)。

示例命令在仓库根目录的 PowerShell 7 中运行，所有占位路径均替换为实际绝对路径：

```powershell
pwsh -NoProfile -File tools/performance/acceptance/capture.ps1 -Exe '<发行目录>/oddly-good-hospital.exe' -Pack '<发行目录>/oddly-good-hospital.pck' -Scenario '<工况JSON>' -Output '<新采集目录>'
python tools/performance/acceptance/analyze.py --help
```

标准4.7.2发行模板禁用CLI路径覆写：--main-pack会拒绝，--script会被忽略。正式工具使用仍启用的独立项目设置override能力，在本次发行副本旁设置外部Node主场景；原EXE、PCK、DLL不变，不新增游戏中的测试入口。override、外部场景和脚本均记录哈希，启动后核对原生和user://目录，之后才取得医院锁。

## 证据与完成条件

每场保留源与工具哈希、命令行、退出码、脚本错误、原始呈现 CSV、原始步记录、QPC 对齐、实际设置、负载与密度、操作收据、采集开销及进程/图形资源证据。采集目录不可覆盖。运行数据存放在忽略目录，提交的报告包含足以复核结论的汇总和证据身份。

每个适用帧/步分位数至少取得1000个真实完整样本，采用最近秩。模拟等待和窗口末端已开始区间的完整尾部保留；模拟速度使用原窗口，不能用尾部扩大分母。密集负载独立统计。主线程片段耗时、完整步现实耗时、引擎帧回调和实际呈现帧各有不同含义。

只有全部适用责任具备有效通过证据才记为完整通过。语法检查成功、短跑完成、模型返回、零值或不可用监视器、缺失图形证据、尚未执行的操作均不能填为通过。超标后按相同负载定位、修复和复验，未变化且仍有效的证据继续复用。
