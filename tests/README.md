# 功能专项测试

测试范围为阶段1至28已经接入游戏的功能。每个专题先以需求文档形成用例，再将前提和操作映射到实际代码入口。预期金额、时长、资格、状态和失败边界来自需求及设计数据；现有实现不定义正确答案。

| 专题 | 已完成阶段 | 用例与预期 |
| --- | --- | --- |
| 内核、内容、保存、多院、界面投影 | 1、3至7及共同会话边界 | [core](acceptance/core.md) |
| 门诊、方案、手术、住院 | 10至13 | [clinical](acceptance/clinical.md) |
| 培养、排班、员工与候诊生活、招聘 | 14至17、23 | [staff](acceptance/staff.md) |
| 耗材、环境、维护、科室、财务 | 18至22 | [operations](acceptance/operations.md) |
| 来客、居民回访、研究 | 24、25 | [growth](acceptance/growth.md) |
| 建造、导航、土地、楼层、交通、改建蓝图 | 8、9、26至28 | [space](acceptance/space.md) |

完整专题执行：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1
```

修复后只执行受影响专题，例如：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -Suite core
```

运营与空间的各例输入相互独立，可按明确用例补测：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -Suite operations -Case OPS-10
```

定点执行只记录指定用例，不能称为整组通过；完整执行的失败与后续修复记录分别保留。临床仅开放 `clinical.gd` 的 `SELECTABLE_CASES` 所列用例，并重新走完各自所需的真实前提；其余临床用例执行完整专题。

运行器复制实际工作区源文件至`.cache/acceptance/<唯一ID>`，使用唯一的引擎资料目录，复用已导入的不可变资产，不复制编辑器状态或玩家医院。首次执行全部专题一次；失败先判断是业务实现、场景前提还是工具问题，再按需求修复并复验受影响用例。已通过用例仅在相关实现、内容或执行环境变化后复测。用例必须全部产生结果，脚本中断留下的用例按未完成失败处理。

`source-identity.json`记录复制源文件的字节哈希、引擎和原生库身份、完整命令及运行环境。隔离工程的`project.godot`将`config/custom_user_dir_name`替换为该次记录的唯一`profile`；该资料目录替换与源文件哈希共同标识执行工程。`execution-status.json`记录实际退出码及引擎错误；`acceptance-results.json`记录每项需求、实际结果和错误。整次执行通过须全部声明用例完成并通过、进程退出0、日志无脚本错误；单项结果与整次执行状态分别记录。

这些测试不执行性能采样、历史长时间回放矩阵、阶段29以后的功能或完整发行验收。正式美术质量、Compatibility实机画面、安装中断和长期性能不能由无窗口功能结果推导。
