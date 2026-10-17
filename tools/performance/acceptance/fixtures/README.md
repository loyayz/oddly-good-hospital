# 正式性能输入

本目录只准备输入和展开场景配置，不判定性能通过。准备进程与 Release 采集进程分开；准备耗时、输入身份和失败日志保留在输出目录。原始输入只读，每次采集恢复独立世界。

`inputs.json` 记录输入契约及各自 `manifest_file`，`scenarios.json` 记录七组联合矩阵和额外职责。基础manifest为 `<id>.manifest.json`，命名临床/日界边界为 `<id>.input.bin.manifest.json`，双医院和历史输入使用各自汇总报告。二进制使用原 `Fixture.store_input` 信封：`content_fingerprint`、`facts`、`floors`、`visitor_ids`。消费端仍须独立校验世界、内容指纹、实际人数及楼层。

## 基础输入

| 输入 | 患者 / 员工 / 家属 | 活动楼层 | 布局 |
| --- | --- | --- | --- |
| `160four` | 120 / 32 / 8 | 1、2、3、4 | `four_floors` |
| `320four` | 240 / 64 / 16 | 1、2、3、4 | `four_floors` |
| `640wide` | 480 / 128 / 32 | 1 | `wide` |
| `wide160` | 120 / 32 / 8 | 1 | `wide` |
| `tall640` | 480 / 128 / 32 | 1、10、1000、10000 | `tall` |

原 `tools/performance/fixture.gd` 的 64 间房、128 个服务对象和 1200 件 FUR18 道具全部保留。高楼保留从 1 到 10000 的连续结构和原电梯，仅表中四层布置活动内容。准备器使用同一原 `HospitalFactory._add_facility`，在初始合法已建布局边界为家属增加 8 / 16 / 32 个公共 FUR09 座位。候选仅限1楼下方 `y=90` 公共走廊的39个间隔位置，入口附近留空。原 `BuildService._facility_position` 独立校验定义、研究、公共归属、拥有地、实际身体、设施、连接器、适配预约、垃圾及门口；等候格另验公共归属和实际占地，原到场所有者再验完整路线。此输入不用于证明建造提交或全院建造安全流程，不能删除原道具腾位置。

原诊断 Fixture 的 `bench_visitor_*` 没有到访记录和业务所有者，不能计为正式访客。准备器只移除确认无员工、就诊、家属、移动及 VisitorStay 所有者的这些占位 Actor，保留患者和员工数量，以需求中的家属档案补足原 5% 组成。家属属于原 `HospitalVisitors` 的 `companion` profile：必须关联实际 Visit，`relative_of` 指向患者，物种与患者一致，一次就诊最多一名，真实入口有空间，实际公共等候位和路线可达。复用真实步骤来源时，所有原陪诊意图、RNG和待到场请求均保留，仅按原 `(request_tick, id)` 顺序将既有合法请求交给 `_admit`，实际到场达到目标即停。剩余请求保留为后续正常经营负载，manifest记录待到场请求前后数量；不能取消请求锁定人数。原请求不足时拒绝该来源，重新使用尚未执行原步骤的新Fixture初始边界；只有该新边界可指定已知陪诊意图并由原 `_request` 建立请求。原 `_admit` 创建Actor、抽取人格并建立VisitorStay，原流程执行移动、等候和离院。脚本不写VisitorStay，不把家属伪称普通探访者，也不证明随机陪诊概率或扫描周期。

入口被占用时只推进完整生产步骤，不瞬移、不停住患者、不改模拟时钟、不缩短工时。输出边界要求实际75%患者、20%员工、5%家属及零无主在院Actor。自然离院、入口或座位失败、求解失败、看门狗耗尽都判为准备未完成，不能降人数输出。正式经营中的自然到场、离院和组成变化继续执行；160、320、640是起点实际负载，不是静态锁定人口。

基础准备在复用来源入口实查 `rooms.size()==64`、FUR18 数量1200及其他设施数量128；输出再次实查其他设施数量为 `128 + added_public_seat_ids.size()`，并核对所有原房间ID、设施ID和设施定义仍在。manifest同时记录 `actual_layout_before`、`actual_layout_after` 和对象保留结果，不能只凭 `original_*` 合同声明认定负载。

## 最短准备命令

使用已准备好脚本索引和 Windows 平台组件的隔离工具工程。下列命令不执行导出或构建。`Godot` 是工具引擎绝对路径，`Project` 是该隔离工程绝对路径；输出目录使用新目录。引擎运行须由统一主流程串行调度。

```powershell
# 五种基础输入；每种负载独立构造。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Inputs.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -OutputDirectory C:/evidence/formal-inputs -Mode Base

# 首个160可复用同内容、同布局、同人数且已有真实当天冻结计划的来源。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Inputs.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -OutputDirectory C:/evidence/first-160 -Mode Base -CaseId 160four `
  -SourceInput C:/evidence/native/steps.json.after.bin

# 依赖已成功的160four和320four；仅推进真实临床/日界前提，并保留两个原医院。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Inputs.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -OutputDirectory C:/evidence/formal-inputs -Mode Boundaries

# 64/128MiB离线合法历史，单独安排内存、磁盘和时间预算。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Inputs.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -OutputDirectory C:/evidence/formal-inputs -Mode History

# 仅展开配置，不启动游戏；输入和成功manifest缺失或哈希改变即失败。
pwsh -File tools/performance/acceptance/fixtures/Expand-Scenarios.ps1 `
  -InputDirectory C:/evidence/formal-inputs `
  -ScenarioDirectory C:/evidence/formal-scenarios `
  -EvidenceDirectory C:/evidence/formal-captures
```

`Prepare-Inputs.ps1 -Plan` 只打印引擎参数；仍检查引擎和工程路径。基础脚本默认最多 4000 个完整步骤，单次准备最多 3600 真实秒，可用 `-MaximumRealSeconds` 指定。`--source-input` 只属于一个选定工况，不能改标签复用为其他人数或布局。来源没有当日真实冻结计划时拒绝，不注入零机会计划。新建 Fixture 则由原步骤计算首日计划。`-Mode All` 等同依次 Base、Boundaries、History，适合 `-CaseId all`；单独生成一种基础输入后不满足双医院依赖。

直接调用首个基础脚本的最短入口如下；独立工具工程可使用该入口进行语法检查和首次生成：

```powershell
& C:/tools/Godot.exe --headless --path C:/prepared/tool-project `
  --script res://tools/performance/acceptance/fixtures/prepare_inputs.gd -- `
  --case=160four --source-input=C:/evidence/native/steps.json.after.bin `
  --output-dir=C:/evidence/first-160 --maximum-steps=4000 --maximum-real-seconds=1800
```

现有目标文件和日志不覆盖。基础准备保留逐输入 `.manifest.json`、`base-preparation-*.json` 和日志；失败不得把残留文件当作成功输入。`ACCEPTANCE_PREPARATION_PROGRESS` 记录来源载入、真实计划检查、每张初始座位、每名家属到场以及每32个完整步骤的阶段和墙钟耗时。

## 七组联合矩阵

| 组 | 输入 / 速度 | 窗口像素 | 场景缩放 / UI | 主要职责 |
| --- | --- | --- | --- | --- |
| B1 | `160four` / 1× | 2560×1440 | 75% / 100% | 默认主目标、面板与镜头、手动保存及原180秒自动保存 |
| B3 | `160four` / 3× | 2560×1440 | 75% / 100% | 同一只读输入的3× |
| D1 | `640wide` / 1× | 2560×1440 | 75% / 100% | 640宽院区；密集条件另行实测 |
| D3 | `640wide` / 3× | 2560×1440 | 75% / 100% | 同上3× |
| C320 | `320four` / 3× | 2880×1920 | 100% / 200% | 320成长负载、高像素和UI200 |
| W160 | `wide160` / 1× | 2880×1920 | 66.67% / 200% | 宽院区、场景67%和UI200 |
| T640 | `tall640` / 3× | 2880×1920 | 75% / 100% | 1/10/1000/10000活动层切换及区间保存 |

默认初始楼层为1，T640操作显式切换四个活动层。每组最少帧样本及完整步骤样本从当前 `docs/data/balance.json` 读取；每个场景生成新 `run_id`、绝对输入路径和独立输出目录，收集器可在正式运行时创建新的运行身份。B1至少采集190真实秒，但自动保存仍须原回执与截止时刻证据，不能只凭时长宣告覆盖。

D1/D3只有同屏真实绑定人物至少576且该独立密集段样本充分时，才联合承担640密集职责；W160对应至少144。配置人数不定义密度，普通组 `dense_target_actors=0` 禁用密集判定。自然离院造成密度不足时保留结果并追加合法独立密集工况，不能冻结离院、降低分母或拼接轻载片段。七组不是分辨率、缩放、人数和速度的笛卡尔积。

## 命名边界和大输入

- `clinical_midstep` 从160基础输入推进至原门诊或手术 Session 的 `64 <= remaining_ticks < total_ticks`，完整步骤结束后保存。manifest保留Session身份和冻结承诺见证。操作开始时必须仍为同一未完成Session；人口以实际生成结果为准，不能沿用160标签。没有满足条件的Session时保留 `.blocked.json`，需检查真实员工/设施/排队前提，不能重写进度。
- `day_boundary_before` 实际推进至下一个日界执行tick之前64步；首日通常为17936。日界业务在源tick18000执行，对应完成结果tick18001，manifest分别记录 `target_executed_tick=18000`、`target_completed_tick=18001`、`target_day_index=2`。默认暖机32个实际步骤后仍须处于边界前，否则本次采集无效。原当天计划、随机流及后台求解生命周期全部保留。
- `dual_a`、`dual_b` 分别按字节复制已验证的160和320输入，保持两座原厂医院不同UUID及全部引用；不改ID。`dual-plan.json` 只记录来源。正式切换前还须通过原 `HospitalLibrary.create` 和 `HospitalSnapshots` 在隔离资料库写入两院，按原检查点、载入和返回流程操作；两个准备信封不等于已有双医院快照。
- `history_64mib`、`history_128mib` 保留160基础输入的所有活动事实、原身份、账目、承诺、进度和RNG，仅新增合法已离院 Visit、在院外 Actor 与 `arrival_receipts`。模板必须无住院居民、无支持设施、无尝试/证据/方案/收费承诺/家属；不满足时明确失败，可用 `--template-visit` 指定已有合格原Visit。每次验证原事实逐项还原相等、原活动Visit序列及实际在院人数不变，再由原 `HospitalJsonStream` 输出至少64/128MiB的规范世界JSON，并单独记录二进制长度及两个哈希。增加的是合法历史输入，不是声称真实发生过的模拟历史；不添加未定义字段或padding，不把历史人物计为活跃负载。离线编码预算不证明游戏保存准入或内存余量，正式验收仍须真实快照保存/恢复、额外峰值和事实/RNG核对。

## 尚需实际建立的操作前提

现有满64房布局并不证明“最大成功房间预览”或“载入中改建”。仍需在选定合法世界给出可成功的最大房间请求和替代布局，核实几何、资金、原资源所有者及当前精确报价，再执行原整备、真实撤离、等待和显式应用。未建立该命令与布局前，此职责保持未完成。

两小时稳定性还需一个连续7200真实秒的实际操作计划和运行，包含八次房间变更、四次原医院切换及对应回执、尾部资源。七组短采集、边界输入和两院信封不能替代此证据。工具源文件、静态检查、前置状态生成、正式Release测量分别记录；没有运行结果的输入保持“待生成”。
