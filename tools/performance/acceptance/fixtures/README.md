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

## 稳定性与最大预览的操作前提

`prepare_operations.gd` 的两个模式均从成功的原四层输入开始，不删原负载、交通或历史，不改随机流、时间和工时。`Prepare-Operations.ps1` 检查来源manifest与哈希，保留失败日志；`--maximum-steps`和`--maximum-real-seconds`限制实际准备过程。源文件已提供，生成、预检及正式采集仍分别记录，未运行不能标为通过。

### 稳定性两院

`stability_a`读取160基础，`stability_b`读取320基础，保持各自原厂不同UUID和75/20/5组成。原建房报价与命令真实支付2700，增加 `formal_stability_room`：1F `[15,81]`、8×8空GP、`formal_stability_door`为DR04南门offset1。原64间房及全部设施保留，稳定性明确为65房；空房是需求允许的真实房壳，不生成假服务或演员。

来源通过实际身体、拥有地、门口、原预约及全院安全出口检查才提交；原实体、临床事实和RNG须保持。两个布局同一占地，原 `build_rotate turns=2` 将门从南侧 `[16,89]` 移到北侧 `[20,81]`，再转回南侧。准备器在独立克隆上执行两次完整原 `remodel_prepare`、真实0.1秒腾空步骤、当前完整报价和显式 `remodel_apply`，核验门坐标、原身份、零金额唯一凭据及世界。发布输入仍在第一次旋转之前，克隆预检步骤单列，不能冒充已在发布医院旋转。

`extra_scenarios.json` 的STABILITY先真实保存A，再通过原 `Library.create` 写入B并等待回执。捕获保持原180秒自动保存，不改周期；900、1800秒修改A，切B；2700、3600秒修改B，切A；4500、5400秒修改A，切B；6300、7200秒修改B，切回A并保存。八次操作均由原改建安排执行，四次切院均走源检查点、原载入、暂停及显式恢复1×。返回使用最新已提交保存点，不重新加载初始种子。7200秒后的末次操作和显示尾部仍须完整结束，10800秒只是独立停止保护。逾期操作串行保留实际延迟，不删除或伪称完成。

空壳旋转不证明临床占用安全交接。真实中途Session的身份、剩余工时、原Attempt/票号/耗材与安全交接另用对应命名输入和SPACE-35等实际流程；载入中改建还须实测当时确有待绑定资源。运行中阻碍或报价失败保留原安排，不自动重新报价成成功。

### 最大成功与完整失败

- `PREVIEW85`保留原tall640完整世界，初始1F经原切层观察2F，真实外部输入85×95 GP/DR01矩形，origin `[0,0]`。8075格报价323050；右侧保留 `[85,40]` 4×4区间井道及公共空间、底行95为门外公共区。这是当前世界及原南门UI约束下的最大成功矩形，不能称为全输入域上限。
- `PREVIEW96FAIL`在同一未修改来源的2F输入96×95，等待原完整失败结果；阻碍为原真实井道，不把此失败当最大成功证据。两个配置是独立场景，实际完整请求不足时不能从帧样本数推导预览P95通过。
- `preflight_maximum_tall.gd`在独立准备进程对同一来源的两个克隆执行原同步完整报价，要求85×95成功且价323050、96×95因真实井道失败、两个完整世界事实及RNG不变。报告为 `maximum_tall.preflight.json`；展开器核对报告来源哈希。同步报价是正确性预检，不能冒充真实外部输入、原分片UI计算或显示延迟，也不会把预检进程缓存带进正式采集。
- `maximum_upper`从原160四层世界，通过原标准装修工简历及精确招聘报价录用一名真实员工，在4F购买SE02工具台；首块沿原电梯主锚点地块 `[2,1]` 购买5F，其余八块在该层实际有完工模块后按原 `floor_purchase` 逐块购买。原装修工实际到工具台、乘梯到4F、走到各地块正下方工作点并完成原冻结工时。九份原工单、真实贡献、付款、完成tick和实际总步骤均保留；不足前提、缺人/工具/路线、故障或看门狗耗尽都输出未完成，不能写 `completed_top_floor` 或工单剩余量补齐。
- 5F完成后仍保留原电梯的1…4F范围，不扩站、不删交通；5F没有井道、房屋、设施或演员。原64房及全部原实体的身份、布局和交通范围保持，正常经营期间人口、账目、随机和工作自然推进，实际生成后人数写manifest，不能继续硬标160。准备器通过原完整只读报价核验5F的96×95矩形成功、报价364850，且世界不变。`PREVIEW96UPPER`再通过原切5F和真实SpinBox输入测量该9120格最大矩形。

当前普通采集门仍要求实际正人口、32完整步骤、真实有进度的Session、绑定就绪和实际速度。5F施工可能跨日；若完工输入没有实际Session，输入可合法生成，但普通采集无法进入捕获。必须保留这一证据缺口。独立预览门需原AppRoot/视图/建造面板启动、内容和世界验证、原拥有楼层选择、真实完整边界及绑定就绪、外部OS输入与原完整结果/实际显示端点，不应伪造 `warmup_work_seen` 或Session。本目录没有修改其他工具以绕过该门。

四组预览各展开21个独立 `preview_input`：最大成功、最大完整失败、第五层最大成功和 `PREVIEWNORMAL` 的8×8普通尺寸。普通尺寸沿原tall640空2F和相同原UI操作，保留全院640人来源；其100ms目标来自`performance_targets.metrics.input_preview_p95_ms`，最大房间的200ms目标来自`room_preview_p95_ms`，不混用。

每次先由原控件准备其他字段，将被测height置4，再等待外部Windows真实输入将它改为目标8或95；原完整反馈及匹配ACK返回后执行原cancel。重复值不是未发生编辑，控件的实际初值与目标必须不同。每次拥有独立operation ID、OS输入QPC、原草案generation及完整结果，不能把同一结果逐帧重复计数。外部实际显示端点、完整请求数量和最近秩统计仍须由采集产物证明，配置中21不等于21个成功样本。

`BuildPreview.cancel()`确实清除pending/current/result/job及完整边界token，因此所有这些请求都是新的冷job；它不清除原空间几何、导航、内容和图形的全部进程缓存。首个进程内被测请求单独标为`first_process_request`，后20个为`later_process_reuse_job_cold`。原driver在OS编辑之前已准备初始尺寸的预览，因此首个被测请求也不能称为“从未执行过预览代码的进程冷启动”。报告分别保留首个请求原始延迟、后续20个请求和全部冷job；首个请求超标不能由后续较快请求稀释，单个首请求不构成进程首次请求的P95分布。如需该分布，使用独立进程窗口，不拼接成一个伪冷样本集。

## 额外正式场景

`extra_scenarios.json`与`Expand-Extra-Scenarios.ps1`只使用原可执行操作接口，不写世界事实。每组仍取得原`capture.minimum_frame_samples`与`minimum_step_samples`，当前分别为1000帧和1000个真实完整步；预览、载入或日界配置不降低正常经营暖机门，也不把暂停切片或pending轮询当作完整步。

| 组 | 原始来源 | 操作与证据责任 |
| --- | --- | --- |
| STABILITY | operation / stability_a、stability_b | 连续两现实小时、八次原房间旋转、四次原切院及原180秒自动保存。返回使用最新原检查点，不固定回初始seed。 |
| PREVIEW85、PREVIEW96FAIL | base / tall640 | 分别完成85×95成功和96×95真实井道失败，逐次真实OS输入、取消及显示端点。 |
| PREVIEW96UPPER | operation / maximum_upper | 九份原施工订单形成的空5F，完成96×95成功；实际生成人口和正常暖机门单独核验。 |
| PREVIEWNORMAL | base / tall640 | 原空2F的8×8普通尺寸输入，单独适用100ms目标。 |
| HISTORY64、HISTORY128 | history / 对应history输出 | 暂停于原完整边界，真实保存、原Library.create独立320医院、原switch载入并返回前次手动保存的明确snapshot_id，再按原接口恢复速度。记录额外副本、候选/旧世界重叠、工作集与实际分配峰值。 |
| CLINICALSAVE | boundary / clinical_midstep | 暖机后确认同一个真实未完成Session，暂停、保存、切至原320医院，再按该保存回执的snapshot_id返回并继续原工作。核验命名Session、Visit、全部Attempt、票及资源承诺。 |
| DAYBOUNDARY | boundary / day_boundary_before | 在manifest指明的真实执行tick观察唯一原日计划提交及完整步；等待时间留在原步中。 |
| DAYPAUSE、DAYSAVE | boundary / day_boundary_before的独立恢复 | 分别只在实际step_in_progress时发原暂停/保存意图。没有真实pending即失败，不能把普通日界完成当等待覆盖。 |
| RESOURCES160 | base / 160four | 原view.bind重建、原navigation._trim(0)、实际32步后继业务和冷暖观察。原退场代、加载代、实际显示及到达/收费/预约所有权核验另有证据。 |

临床输入的manifest.witness填入组根及save的`required_session`，指定源身份而非冻结预热前剩余工时；保存前须仍为同一id/visit/facility且真实in-progress。原观察器在保存时读取当前完整边界的冻结承诺，以实际snapshot_id记录，原loader成功后、新Simulation建立前核验。跨院时仅对所属原医院应用命名Session条件，不借同名ID串用另一医院事实。`verify_snapshot_witness:true`要求真实载入快照存在来源见证且相等，字段本身不是通过证明。

大历史和临床返回操作的`snapshot_operation_id`引用本场已完成的手动save操作ID，由driver从其真实成功保存receipt提取明确snapshot_id；展开器不伪造该运行时身份。稳定性没有该字段，沿最新原检查点返回。源快照的规范JSON完整hash验证继续由原loader执行，完整facts/RNG往返相等由另一次已暂停完整边界正确性对照验证；低成本tick/RNG/命名承诺见证不冒充全世界逐字段比较。定时保存、切院及观察器成本仍进入帧和资源采集。

三个日界场景使用同一合法命名输入的独立进程恢复。展开器读取原manifest的`target_executed_tick`、`target_completed_tick`、`target_day_index`及64tick预留，保留32真实步暖机要求；如果实际暖机越过目标，运行必须失败。`require_pending:true`只接受原等待事实，不能为得到暂停或保存样本关闭后台任务、插入延迟、清空计划、改时钟或伪造pending。日计划提交、暂停和保存三项责任分别记录，不以其中一项代替另外两项。

RESOURCES160使用原view_rebind进行完整当前视图重建，不能称为不存在的“窄范围驱逐仍被引用的活动模型”。navigation_evict只调用原_trim(0)，不清活动路线、事实预约、版本或请求队列。32后继完整步只证明真实继续推进，实际路线到达、安全交接、收费及承诺不变仍须对应观察或独立正确性断言；缓存allowance记账不是分配或驻留证据。冷重建成本保留在普通捕获窗口，不重新标为暖机。

### 原报告格式与目录

展开器按`source_kind`选择目录，不根据文件名猜测另一种manifest：

| source_kind | 默认目录 | 原报告格式与身份校验 |
| --- | --- | --- |
| base | BaseInputDirectory，缺省InputDirectory | `<id>.manifest.json`；ok、完整原对象保留、实际人口/布局、hospital_id、content_fingerprint和input_sha256。 |
| operation | InputDirectory | `<id>.manifest.json`；另验证原base源hash、UUID和内容相同，以及真实旋转预检或九份施工订单/完整最大报价。 |
| boundary | BoundaryInputDirectory，缺省base目录 | `<id>.input.bin.manifest.json`；不是base格式，按mode、原source_sha256、实际population、Session witness或日界目标读取；layout由已核同源base契约取得，运行仍独立验证二进制完整事实。 |
| history | HistoryInputDirectory，缺省base目录 | 直接读取原`history-generation.json.outputs`中唯一对应target_mib成功项；该原格式没有ok、input_sha256或hospital_id，不能伪造同名manifest替代。 |

历史校验同时核对原report.source_sha256与成功160four源、相同内容指纹、original_facts_and_rng_preserved、空validation、活动及在院计数。逐文件核对原binary SHA/长度、规范world JSON SHA/实际长度及至少64/128MiB；原UUID和患者/员工/家属组成来自已验证且原事实未变的base manifest，出处写入配置。历史Actor/Visit不计为在院负载。原始报告路径和entry保留为证据，输出的配置归一化字段不是新的准备成功manifest。正式消费者仍独立校验UUID、内容和完整世界，不能仅信配置人口。

```powershell
# 在PowerShell 7会话执行；各目录可不同，只选择当前已生成并成功核验的正式组。
& ./tools/performance/acceptance/fixtures/Expand-Extra-Scenarios.ps1 `
  -InputDirectory C:/evidence/operation-inputs `
  -BaseInputDirectory C:/evidence/formal-inputs `
  -BoundaryInputDirectory C:/evidence/named-boundaries `
  -HistoryInputDirectory C:/evidence/legal-history `
  -ScenarioDirectory C:/evidence/extra-scenarios-new `
  -EvidenceDirectory C:/evidence/formal-captures `
  -GroupId @('HISTORY64','HISTORY128','CLINICALSAVE','DAYBOUNDARY','DAYPAUSE','DAYSAVE','RESOURCES160')
```

从现有PowerShell会话调用脚本时，`-GroupId`使用数组；通过`pwsh -File`启动时只传一个组，或省略该参数展开全部12组，避免原生参数传递把逗号字面量当一个ID。展开成功只表示原输入与配置引用通过静态/哈希校验；不运行游戏、构建或采集。目标配置与extra-index已存在时拒绝覆盖；所有选定来源先验证完成再输出，不把残留或缺报告输入当作可执行成功场景。完整Release同源身份、实际运行结果、样本、显示端点、冻结承诺、资源和阈值判定仍分别记录。

### 最短操作命令

```powershell
# 首个稳定性前提；b对应320four，仍须独立合法来源。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Operations.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -InputDirectory C:/evidence/formal-inputs -OutputDirectory C:/evidence/operation-inputs `
  -CaseId stability_a

# 原九块5F施工，可能跨日；不在脚本中缩短任何工时。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Operations.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -InputDirectory C:/evidence/formal-inputs -OutputDirectory C:/evidence/operation-inputs `
  -CaseId maximum_upper -MaximumSteps 40000 -MaximumRealSeconds 3600

# 原tall640两个最大矩形的独立完整正确性预检，不采集性能。
pwsh -File tools/performance/acceptance/fixtures/Prepare-Operations.ps1 `
  -Godot C:/tools/Godot.exe -Project C:/prepared/tool-project `
  -InputDirectory C:/evidence/formal-inputs -OutputDirectory C:/evidence/operation-inputs `
  -CaseId preview_tall

# 展开某一当前可用场景；STABILITY另需已成功生成的stability_b。
pwsh -File tools/performance/acceptance/fixtures/Expand-Extra-Scenarios.ps1 `
  -InputDirectory C:/evidence/operation-inputs -BaseInputDirectory C:/evidence/formal-inputs `
  -ScenarioDirectory C:/evidence/extra-scenarios -EvidenceDirectory C:/evidence/formal-captures `
  -GroupId STABILITY
```

`Prepare-Operations.ps1 -CaseId all`依次生成三个输入并执行tall完整预检，`-Plan`仅打印启动参数。展开器从成功manifest取得实际人口、原UUID及哈希，填入原操作驱动的 `input_path`、`hospital_id`、`resume_speed`、`commands`、`safe_transfer`和预览参数，不改世界或原种子。`expected_door_cell`是明确的外部核验预期，当前驱动若未验证门结果，不得仅凭配置宣称通过。SPACE-01/32/33/37及CORE-09/18/19/30/31覆盖相应建造、改建、身份、保存与观看交接；临床占用、维护接续和失败原子性按实际责任追加选例。
