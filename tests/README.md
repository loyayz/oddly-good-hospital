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

自然入院和随机需求改造另见 [自然入院专项](acceptance/natural-admission.md) 与 [随机需求专项](acceptance/random-arrival-demand.md)，均有独立无头入口及逐项结果。

候诊椅实际占用、手动预览与安全离位另见 [候诊椅占用查询专项](acceptance/seat_owner_lookup.md)，按独立交接选择用例。

公共选区复用既有类型索引、缺类提前返回及布局/事实替换后的恢复见 [公共选区类型查询](acceptance/public_select_type_index.md)。

环境覆盖复用、实际扩门恢复与9×9热图批次另见 [环境观察专项](acceptance/environment_cache_scope.md)。

环境墙段、真实门洞、共墙归属与实时扩门的局部查询另见 [环境真实墙边专项](acceptance/environment_wall_lookup.md)。

回归范围、前置状态使用边界和停止条件见 [AGENTS.md](../AGENTS.md)。六个专题的已注册用例组成需求覆盖库，每次执行选择实际受影响的用例；不带范围的命令会拒绝执行。

查询用例清单，不启动 Godot：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -ListCases
```

六个专题的全部用例均支持单例选择。省略 `-Suite` 时按编号推导专题，逗号分隔编号可以跨专题共享一次工程准备：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -Case 'CORE-04,CLIN-06,STAFF-08,GROW-23'
```

显式选择整个专题或完整功能库：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -Suite operations
pwsh -NoProfile -File tests/run-acceptance.ps1 -All
```

选择编号只执行相应用例及必要前提，不执行其他用例再过滤结果。未知、重复或不属于显式所选专题的编号，在复制工程之前拒绝。定点执行只记录指定用例，不能称为整组通过。

临床使用 `clinical.gd` 的 `PREREQUISITES` 声明所需边界，按需准备初诊开始、门诊候治疗/开始、C档诊断完成、手术候诊/准备/开始/苏醒/转床、入床/护理/护理完成/待查房/查房/结算、陪护进入和探视到床。缺失节点只准备对应前提，同一次执行和后续进程均可复用。局部用例的工厂可以声明团队已到齐、既有准备进度、最后一个工作或恢复 tick，先检查完整快照，再调用正式服务完成剩余步骤；`FIXTURE_INPUT` 明确记录这些输入，不把此前完整流程计为已执行。门诊贯通、完整手术到齐及四段、15秒苏醒和陪同转床分别由 CLIN-02、18、19、20 实推。研究复用真实初诊开放后的状态，课程复用实际完成 540 或 1079 tick 的进度。被测的移动、工作、收费和交接实际执行。

前置状态保存在 `.cache/acceptance-checkpoints`，每次使用都独立复制完整事实和标量观察记录，并重新绑定服务；不保存服务缓存、编辑器状态或玩家医院。读取时检查节点/生成器身份、数据摘要和 `WorldState.validate`，不匹配或损坏时重新生成。预期值仍由专题用例中的需求依据定义。

缓存身份包含实际参与整步生成的游戏源码、内容、资产、工程配置、引擎和原生库，以及对应 `*_fixtures.gd` 的字节摘要和缓存格式版本；另记录写入器字节摘要。读取诊断修复不改变同一生成器产生的事实，编码规则变化须更新格式版本。真实整步会执行所有模拟服务，因此生产代码变化保守失效这些节点；文档、其他专题或本专题断言变化不会因此失效。前置生成与用例断言分文件保存，避免只修改断言时重复生成前提。

修改前置过程本身时，应选从该过程之前开始的用例。需要完整重新生成选定用例的前提时使用：

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -Case CLIN-23 -RebuildFixtures
```

强制重建跳过旧磁盘状态，同一批中已经新建的节点仍可复用。`FIXTURE` 日志和结果中的 `fixtures` 记录节点身份、来源（`built`、`memory`、`disk`）与耗时；递归节点的生成耗时含子节点，不可逐项相加。每例 `elapsed_ms` 为总耗时，`setup_ms` 记录显式分段前提准备，`body_ms` 为余下用例操作耗时，包含该例自己的短小输入准备。

临床金额、预留和截止规则分别从合法的开工前、可叫号和截止前输入执行被测操作，CLIN-02、18保留真实贯通。CLIN-13、15、16、17的内部阶段计时位于结果的 `details.timing.stages_us`；CLIN-17的 `inclusive_calls` 进一步记录真实临床与空间方法的调用次数和耗时，嵌套调用的累计时间不能相加。各段含义见[临床用例说明](acceptance/clinical.md)。

运行器复制实际工作区源文件至`.cache/acceptance/<唯一ID>`，使用唯一的引擎资料目录，复用已导入的不可变资产，不复制编辑器状态或玩家医院。失败先判断是业务实现、场景前提还是工具问题，再按需求修复并复验受影响用例。已通过用例仅在相关实现、内容、用例或执行环境变化后复测。选定范围通过且无未解决相关问题即结束，不自动扩大到完整游戏。用例必须全部产生结果，脚本中断留下的用例按未完成失败处理。

`source-identity.json`记录复制源文件的字节哈希、引擎和原生库身份、完整命令及运行环境。隔离工程的`project.godot`将`config/custom_user_dir_name`替换为该次记录的唯一`profile`；该资料目录替换与源文件哈希共同标识执行工程。`execution-status.json`记录实际退出码及引擎错误；`acceptance-results.json`记录每项需求、实际结果、用例和专题耗时；`timing-summary.json`记录工程准备、导入、测试进程及整批执行耗时。整批计时从脚本开始到测试进程结束，不含之后的日志展示和报告整理。整次执行通过须全部声明用例完成并通过、进程退出0、日志无脚本错误；单项结果与整次执行状态分别记录。

功能用例的计时用于定位耗时，不能直接代替固定负载性能比较。CLIN-17记录调度前完整输入的SHA-256，可在独立进程中核对相同输入与引擎/原生库后比较模拟步；沿用冻结输入的测量和新源码生成前提的功能回归分别记录。原始结果、计时和执行身份保存在该次隔离工程，不另生成优化过程报告。

这些测试不默认执行历史长时间回放矩阵、阶段29以后的功能或完整发行验收。正式美术质量、Compatibility实机画面、安装中断和长期性能不能由无窗口功能结果推导。

随机来客需求另有[独立专项](acceptance/random-arrival-demand.md)。原精确容量与后台准备的25例已从growth注册表及默认运行移除；相应历史函数不代表现行产品要求。

## 班表只读预览专项

运行 `godot --headless --path . --script res://tests/acceptance/schedule_preview.gd`，输出逐项 checks 与 INPUT_VALIDATION。覆盖医生建议/手动草案、三班六岗位与护士资格、当日覆盖/休假边界、离职后草案失效、当前实际状态和换选员工清空。正式输入先检查完整世界、排班和生活验证器。护理有能力但无 q_ward 是合法原始资格计算边界，不声称正常培养会生成该组合；离职边界通过正式工资结清生成，不代表执行了辞退及真实离院流程。睡眠状态由合法睡前输入经真实移动、床位预约及入睡产生，只验证预览，不重复完整睡眠周期。

地污生成对有效预约的独立边界与恢复专项见 [地污生成与有效预约](acceptance/dirt_spawn_reservations.md)。

地污来源、合法格与地块预算的局部查询及实际清完更新专项见 [地污当前态索引](acceptance/dirt_spawn_indices.md)。

个人床候选区域变化与真实预约释放的定点专项见 [个人床局部机会观察](acceptance/personal_bed_dependencies.md)。

招聘与员工返院的入口身体局部查询、多人实际入院及队列跨层边界见 [入口真实身体查询](acceptance/entry_body_lookup.md)。

EQ05 空岗位可通行而使用权仍独占、真实床体/身体/扫掠安全、局部重接及跨层落地、护理查房与维修恢复的显式专项见 [护理床岗位通行](acceptance/bed_passage.md)。分段输入和真实执行范围分别标明，不替代原有完整临床链结果。

连续局部转弯、已有生活旅程所有权，以及从候手术到真实离院的完整工时与冷恢复专项见 [真实临床连续交接](acceptance/clinical_full_chain.md)。
