# 保存估算的单次键名复用

`snapshot_estimate_contract.gd` 是独立计算合同用例，执行原公式对照及预算边界检查。它不推进模拟，不创建玩家医院，也不替代实际保存交接验证。

在已导入的隔离冻结工程中运行：

```powershell
& 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe' --headless `
  --path 'C:/code/loyayz/oddly-good-hospital/.cache/snapshot-prepare-20261112-key-cache-v1' `
  --script 'res://tests/acceptance/snapshot_estimate_contract.gd' -- `
  '--input=C:/code/loyayz/oddly-good-hospital/.cache/snapshot-prepare-20261112-key-cache-v1/input.bin' `
  '--output=C:/code/loyayz/oddly-good-hospital/.cache/snapshot-estimate-new-result.json'
```

输入必须使用脚本校验的完整冻结输入，原文件在仓库外保存。结果路径必须尚不存在。真实保存探针按其身份清单为每轮设置独立 APPDATA/LOCALAPPDATA；本计算用例的资源替身仅提供确定性资源状态，调用真实 `_budget` 方法。

29 项断言覆盖：

- 独立原公式与空字典、空数组、空键、嵌套、重复字段、中文、转义、NUL、多字节 Unicode、不同 Unicode 规范形式、StringName 键及标量变体的结果相同，计算输入未改变。标量变体只验证估算函数兼容性，不表示这些值都属于合法保存世界。
- 每次调用重新计算值及新增键；两个独立完整 WorldState 交替估算仍各自正确。
- 完整输入的 44642 次键访问形成 2430 个实际缓存项，每个收费均等于原 `UTF8字节数×6+4`；总估算仍为 5723348。
- 实际预算方法在物理资源 180004512 字节、磁盘 84278908 字节的精确边界通过；各减一失败、各加一通过；资源状态失败及非法数值拒绝。这里使用确定性资源状态替身，不是实机内存压力测试。
