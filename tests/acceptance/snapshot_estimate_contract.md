# 保存估算的单次键名复用

`snapshot_estimate_contract.gd` 是独立计算合同用例，执行原公式对照、预算边界和固定完整输入的三对局部计时。它不推进模拟，不创建玩家医院，也不替代实际保存交接验证。

在已导入的隔离冻结工程中运行：

```powershell
& 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe' --headless `
  --path 'C:/code/loyayz/oddly-good-hospital/.cache/snapshot-prepare-20261112-key-cache-v1' `
  --script 'res://tests/acceptance/snapshot_estimate_contract.gd' -- `
  '--input=C:/code/loyayz/oddly-good-hospital/.cache/snapshot-prepare-20261112-key-cache-v1/input.bin' `
  '--output=C:/code/loyayz/oddly-good-hospital/.cache/snapshot-estimate-new-result.json'
```

固定输入 SHA-256 为 `752924c562f275804cee40cbd2a8760f8f0780cab3276a04330db63a2866e780`，可从[保存诊断证据](../../docs/reports/evidence/2026-11-12-snapshot-preparation/probe-evidence.zip)的 `input.bin` 还原。结果路径必须尚不存在。真实保存探针按其身份清单为每轮设置独立 APPDATA/LOCALAPPDATA；本计算用例的资源替身仅提供确定性资源状态，调用真实 `_budget` 方法。

29 项断言覆盖：

- 独立原公式与空字典、空数组、空键、嵌套、重复字段、中文、转义、NUL、多字节 Unicode、不同 Unicode 规范形式、StringName 键及标量变体的结果相同，计算输入未改变。标量变体只验证估算函数兼容性，不表示这些值都属于合法保存世界。
- 每次调用重新计算值及新增键；两个独立完整 WorldState 交替估算仍各自正确。
- 完整输入的 44642 次键访问形成 2430 个实际缓存项，每个收费均等于原 `UTF8字节数×6+4`；总估算仍为 5723348。
- 实际预算方法在物理资源 180004512 字节、磁盘 84278908 字节的精确边界通过；各减一失败、各加一通过；资源状态失败及非法数值拒绝。这里使用确定性资源状态替身，不是实机内存压力测试。
- 同一完整输入交替执行三次原公式和三次候选估算，逐次核对金额和完整源事实；不改变输入规模或合法负载。

实际 `begin → wait_for_idle → load_commit` 的代表性交接另以三个全新测试资料库执行，每轮 13 项完整事实、冻结副本、真实锁、回执、会话及清单归属检查均通过；三项立即失败检查保持。结果见[保存分段报告](../../docs/reports/2026-11-12-snapshot-preparation-performance.md)。
