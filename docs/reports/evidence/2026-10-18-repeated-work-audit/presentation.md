# 表现、应用、内容与持久化重复工作静态审计

审计日期：2026-10-18。对象为清单 recorded_at 时刻的工作区代码，源码身份和逐文件清单见 [presentation-manifest.json](presentation-manifest.json)。证据仅包括静态调用链、循环规模和复用边界；未运行 Godot、测试、界面、GPU 或性能窗口，没有耗时、占比、帧率或收益结论。它不替代固定负载下 `Simulation.step` 的实测归因。

范围为 `game/app`、`game/ui`、`game/view`（含 shader）、`game/platform`、`game/content`、`game/persistence`、`addons/source_assets`，以及范围枚举额外发现的 `assets/models/import_vertex_colours.gd` 和 `art-source` 四个自有 Python 脚本。其余生产服务由临床、运营分区审计；`tools`、`tests`、`docs/tools` 由工具分区审计。模型、纹理、内容 JSON、UID、场景和插件配置只作为输入或绑定核对，不作为可执行循环审计；预编译库及第三方实现不进入自有源码审计。不存在单独的 `game/render`、`game/presentation`、`game/resource`、`game/save`、`game/storage` 或根 `source_assets` 目录。

符号约定：A 为当前视图绑定角色数，F 为绑定设施数，V 为全部 Visit 数，B 为蒙皮批次数，K 为一次资源完成批次的发布数，U 为升级单数，P 为当前病例可比较方案数，C 为不规则草案格数，D 为阻挡格数。全部规模来自代码的集合关系，不表示实测运行规模。当前基础内容包含 6 个 medical_equipment_profiles、4 个员工娱乐设备定义、8 条设施收费和 4 条医生收费；扩展内容不能默认保持这些数量。

## 候选编号与触发分类

PRES-01～PRES-11 为本分区的 11 条记录。PRES-06 与 CL-A08 共用招聘根因，汇总只计一次；CAP-01 单列为容量候选。类别表示触发路径，不表示耗时排序。

| ID | 标题 | 分类 |
| --- | --- | --- |
| PRES-01 | 每个蒙皮批次重新计算全局包围盒 | 每帧 |
| PRES-02 | 每个资源发布重建全部员工蒙皮批次并扫描 Visit | 每帧（资源完成时） |
| PRES-03 | 稳定模型播放器、骨骼与剪辑反复解析 | 每帧 |
| PRES-04 | 每个维护设施重复扫描目录与升级单 | 每帧 |
| PRES-05 | 方案面板首次建立重复完整比较 | UI |
| PRES-06 | 寻访倒计时重建完整招聘卡片（同 CL-A08） | UI |
| PRES-07 | 几何和环境签名输入重复投影 | 每帧 |
| PRES-08 | 已缓存预览仍重复深复制发布 | 每帧（可见草案 UI） |
| PRES-09 | 不规则预览格逐个扫描阻挡格 | 冷（预览 basis 变化） |
| PRES-10 | 导入评级去重键逐个扫描员工前缀 | 冷（导入） |
| PRES-11 | 娱乐设施选项逐项扫描小目录 | UI（构建/显式刷新） |
| CAP-01 | 岗位约束变化逐节点检查全部锁定角色 | 容量 |

## 可直接缩小到一次调用或一次更新的重复

### PRES-01：每个蒙皮批次重新计算同一个全局包围盒

- 调用链：`game/app/app_root.gd:620` 每个非 pending 帧调用 `HospitalView.update_facts`；`game/view/hospital_view.gd:308` 对每个 `_skin_batches` 调用 `batch.publish(_visible_body_bounds())`；`:552` 的辅助函数遍历全部 `_actors`、读取 wrapper.visible/position、查询 actor_body，并合并 AABB。复杂度为 O(B×A)，B=1 时没有乘法收益。
- 必要部分：每个批次仍须发布当前骨矩阵、验证来源并更新自己的可见性。重复部分：这些调用之间 `batch.publish` 不改变角色 wrapper 的位置或 visible，故所有批次得到同一 AABB。
- 现有复用：没有此更新内的包围盒复用；内容定义有索引，但每次 actor_body 仍构造尺寸值。
- 最小候选：仅在批次非空时计算一次当前包围盒，再传给所有批次。结果只在本次 update 内存活，不引入跨帧失效问题。
- 验证边界：CORE-31、32、33、48；另检查多个实际批次、无可见角色、切层/切院、移出视锥及低动态模式。AABB 和原始逐批计算一致，业务事实/RNG 不变。状态：静态确认重复，收益未测。

### PRES-02：每完成一个资源就拆除并重建所有员工蒙皮批次

- `hospital_view.gd:409` 的 `_complete_resources` 在当前 2ms/最多 2 次开始预算内发布资源；`publish_resource:425` 先校验资源票，`:432` 无条件 `_clear_batches()`，`:457` 无条件 `_bind_skin_batches()`；后者从 `:1163` 遍历全部绑定 actor models、递归找 mesh/skeleton，再重新创建全部合法组。设施模型完成也执行这套员工批次工作。一次完成批次为 O(K×A)，还包含重复验证、页分配和解绑。
- 同一函数 `:439` 为每个完成的角色资源 `world.facts.visits.values().filter(actor_id)`，单个完成批次最多执行 K 次完整 Visit 扫描。`_presentation_index:750` 已经有 visits_by_actor，但在资源完成之后才构建，不能偷用上一帧索引。
- 必要部分：迟到票拒绝、代理替换、资源所有权和每个实际 actor 新来源验证。现有帧预算限制开始次数，没有合并同一批次内的全体重新绑定；资源缓存只复用 PackedScene 与资产验证，不复用这些批次。
- 最小候选：员工来源和成员未变的纯设施发布不重建员工批次；actor 来源变化时先安全解除旧批次，当前完成批次结束后统一重建一次。若同时处理多个角色，在该批次内按当前完整事实构建一次 Visits 分组。保持外部单次 publish_resource 的独立可用语义，不能仅删除其重建。
- 验证：CORE-32、33、48，加入设施单独发布、同帧两个 actor 发布、混合设施/actor、旧票拒绝、移除/重绑、校验失败；结束后的来源、分组和恢复可见性等价。状态：静态确认重复，收益未测。

### PRES-03：稳定模型的播放器、骨骼、骨索引和剪辑名每帧重新解析

- `hospital_view.gd:239` 每个可见角色、`:259` 每个设施调用递归 `_animation_player:1153`；随后 `_animation_name:1204` 重新遍历 `get_animation_list()`。病例道具 `_update_case_props:1052` 每次递归 `_skeleton` 并 `find_bone`；低动态分支又查播放器/剪辑，随后 `_seek_prop:1090` 再查一次。机器道具也经 `_seek_prop`。
- 规模为每帧 O(各绑定实例层级节点数 + 各请求剪辑列表长度)，低动态病例道具存在同一帧重复查找。实际动画 seek、骨姿态读取和当前业务 pose 计算必要，模型内这些解析结果在资源替换前稳定。
- 现有缓存只缓存资源加载/验证，不缓存每个已实例化来源的解析句柄。最小候选：在资源或道具绑定时存播放器、骨骼、slot bone index 和按原顺序解析的剪辑映射；替换、移除、重绑定同步清理。保留首个匹配/后缀匹配顺序、缺剪辑回退和 manual callback 设置，不能缓存动态骨矩阵。
- 验证：CORE-33、48，特别是命名空间剪辑、缺剪辑、低动态回退、替换后不引用旧 Node。状态：静态候选，实例层级和真实成本未测。

### PRES-04：每个维护设施每帧扫描设备目录与全部升级单

- `hospital_view.gd:258` 对每个绑定设施调用 `_update_equipment_mark:950`。维护设备在 `:957` 扫描整个 medical_equipment_profiles 判断是否可升级；upgrading_block 的设施在 `:965` 扫全部 maintenance.upgrades。基础目录为 6 条，但 U 随保存事实变化；复杂度为 O(F维护×6 + F升级×U)。装饰 signature 在扫描之后才判定，只阻止装饰重建。
- 必要部分：当前故障、工作、暂停和等级文字必须跟随事实。最小候选：内容 fingerprint 生命周期内建立可升级 definition membership；每次 update 按当前升级单建立一次 facility→状态投影，保留原遍历下最后一个匹配非终态订单覆盖的语义。不能因预期单设施一单而静默丢弃合法输入顺序。
- 验证：CORE-48 和受影响 OPS-21～27 中实际设备状态交接，覆盖故障/待安全停机、升级等待/工作/暂停/取消、同 tick 命令及重新绑定。状态：静态候选，收益未测。

### PRES-05：治疗方案面板建立时连续执行两次完整 compare_plans

- `game/ui/plans_panel.gd:31` 调用 `_populate_plans:37`，其 `:39` 的完整比较只用于取得 plan_id 与名称；`:35` 调用基类 report，`game/ui/action_panel.gd:128` 立即调用 `_details`，后者在 `plans_panel.gd:61` 再执行同一病例完整比较。每个完整比较还会枚举其合法医生/设施等候选，不能将 P 次报价看成常数文本格式化。
- `action_panel.gd:42` 还会对可见面板每 500ms 调用 `_details`，即使暂停且事实未变。这个周期复核有当前可开工状态用途；其缓存失效必须严谨，不能按 sim_tick 一项缓存。`:47` 提交时再次 plan_quote 是必要复核，应保留。公开 compare_plans 必须保持全医生比较，不能套用自动调度的指定医生过滤。
- 最小候选：选项从病例对应的方案定义取得，或让一次当前刷新完整报价同时提供选项与详情。跨刷新复用是另一项有条件改动：需包含世界身份、会话/病例、相关修订和选择，命令在同 tick 改事实应立即失效。
- 验证：CLIN-06、13、34，CORE-30、34；另外检查首次打开仅一个完整比较、改变病例、暂停后库存/班表/故障变动、选择与完整失败原因、提交复核。状态：静态确认首次重复，周期复用收益和失效方案未测。

### PRES-06：寻访倒计时投影重建全部招聘卡片

- `game/ui/recruitment_panel.gd:123` 的 `_search_status` 被可见面板每 500ms 调用，却调用完整 `RecruitmentService.query(world,filter)` 只读取 active_search；`:61` 的显式 `_refresh` 已经调用同一完整查询以建立卡片。
- 服务分区已核对 `game/staff/recruitment_service.gd:218`：排序保存候选 ID、`:229` 对匹配者 card（复制简历及物理入职门槛等），返回时 `:230` 又做 standard_preview。规模为每个倒计时更新 O(候选排序 + 匹配候选投影 + 标准预览)，与只需一个当前搜索记录不匹配。
- 最小候选：由招聘服务提供只读 active_search/status 投影，完整 query 继续服务显式列表刷新。不得在 UI 自建另一份寻访事实或跳过当前筛选定义。
- 验证：受影响招聘用例、CORE-30、34；寻访开始、实际倒计时、取消/完成、过滤条件变化和切院。状态：跨分区静态确认，PRES-06 与临床分区 CL-A08 属于同一根因，跨分区汇总只计一次。

## 其他存在乘法或重复投影、但应先量化的路径

| 编号 | 当前代码、触发与规模 | 现有控制、最小边界与验证 |
| --- | --- | --- |
| PRES-07 | `hospital_view.gd:114` 每个 update 收集房间/连接/门、floor_layout，再 JSON.stringify 后才比较 geometry signature。`:816` 每帧收集 dirt/surfaces/装修单元再计算环境 signature；热图存在时 `:934` 还收集活动医疗/设备、身体、设施等 stamp。这是同一事实在多个显示帧的重复投影，不是每 actor 全院扫描。 | signature 已避免重建网格，尚未避免造签名输入。候选为相关几何/材质提交的精确标识与世界身份/楼层绑定；没有证明生产标识完整覆盖前不能跨帧跳过。tick 不足以覆盖暂停命令；世界 revision 也可能被无关命令频繁改变。CORE-31、33、48，加同 tick 改建、门适配、脏污/材质/热图变更。未测，不列为当前 step 瓶颈。 |
| PRES-08 | `game/ui/build_panel.gd:200` 每个可见有草案帧调用有缓存的 preview.update，`:213` 仍深复制 draft 与 result 并 emit。接收的 `game/view/build_overlay.gd:7` 才比较 basis。就绪且输入未变时仍重复复制/信号传递。 | 现有 preview 缓存与 overlay equality 已挡住计算及网格重建，不能报为每帧重跑完整预览。候选是预览发布身份/内容未变时不再次复制发布；须保留进行中结果变更、选择/楼层/新事实失效、切院清草案。CORE-30、36、SPACE-52。未测。 |
| PRES-09 | `build_overlay.gd:45` 不规则 cells 分支对每格做 `cell in blocked_cells`，O(C×D)，仅 basis 改变后执行。矩形分支已经按行列绘线并单独遍历阻挡格。 | 此处局部建立阻挡格键集合即可 O(C+D)，保留精确格相等与颜色。不得重写已经线性的矩形路径。SPACE-52，加不规则/重复/边界阻挡格及原几何输出比较。冷重建路径，未测。 |
| PRES-10 | `game/persistence/hospital_library.gd:324` 导入改院身份；`:333` 每个 departments.staff_consumed 复合键遍历按长度倒序的全部 staff_ids 寻找前缀，O(历史消费键×员工数)。 | 最长前缀用于正确处理身份中的分隔符，必要；全世界两遍 collect/rewrite 用于建立完整映射和重写引用，也必要。候选只缩小复合键前缀查找，可用本次导入局部前缀索引，保留最长匹配和 definition 字符串保护，不能简单 split(':')。CORE-26、27，加共享前缀/含冒号身份及去重键恢复。只在导入触发，未测。 |
| PRES-11 | `game/ui/staff_life_panel.gd:10` 构建娱乐设施选项时，每个设施遍历 staff_recreation_equipment（当前 4 条）；O(F×4)。 | 仅面板实际创建/显式刷新，非 500ms 摘要；已有 ContentRegistry.definition/legacy_definition 按集合索引。可直接按 definition ID 查询该集合，无需再造全局缓存；保留未知定义过滤与原设施顺序。CORE-34 和相关娱乐用例。规模小，未测，低优先级。 |

改建摘要属于跨分区共同调用链：`game/ui/remodel_panel.gd` 的可见摘要每 500ms 对每个 preparing order 调用服务 `_waiting`；`game/building/remodel_service.gd:145` 会分别扫描会话、病房住院、准备、装修 orders/units、适配和 actors。服务分区负责完整事实生命周期、源几何与真实身体检查的审计，此处不另计一个 UI 根因或声称已测成本。

## CAP-01：岗位约束变化时重复检查无关角色

分类：容量分析条件候选。`game/platform/windows/platform_arrivals.cpp:1261` 的 `Model.update_roles` 在岗位约束确实变化时，对每节点×每 locked_role×节点局部 resource term 检查 coverage/staff 互斥。同值 `next==locked_roles` 已立即返回；当前未测节点数、角色数、term 数或触发次数。

岗位互斥以及按子节点结果传播 enabled 是精确模型的必要语义。可量化的候选仅是在完整模型生命周期内派生资源/角色关联索引，以跳过无关角色；应保留原约束顺序与精确结果，不按字符串冒号随意拆 staff ID，也不复用已失效的求解状态。受影响验证为容量专题的岗位互斥、约束不变/变化、预算变化和证书复用边界；未执行这些验证。

该路径属于暂停的容量分析范围，与普通临床 `Simulation.step` 的现有实测瓶颈分开记录，没有耗时占比或收益结论。

## 已检查而未形成剩余优化结论的区域

### 应用、全部管理面板

- `app_root._update_details:923` 已经一次建立 sessions_by_visit，再顺序处理完整 Visit 历史和所属会话；未发现旧式 Visit×全部 Session 扫描。隐藏正文直接结束，时钟余额仍更新。其历史正文每 100ms 的线性重建不应伪装成尚未修复的同类二次扫描。
- `GameSession.advance:82` 限制一次返回最多 8 个完整固定步，pending 步先完成，等待不积累补跑。每步实际推进有不同业务输入，不能合并成一次或跳过；暂停/保存边界和命令排空语义不是缓存候选。
- 基类 ActionPanel 只构建实际可见且 pending rebuild 的控件，已建页面重开不重建，500ms 摘要仅可见时执行。未发现 20 面板全部每帧刷新。
- arrivals：初始居民选择后按 16 展示；day_stats 的内部由临床分区负责。clinical：一次顺序统计 Visit 并显示选中项。departments：一次服务 summary 后组装行，内部由运营分区负责。finance：一次 query 后显示 12 行与少量预测。maintenance：设施选择按 16 展示，只对选中设施报价，非每行全量报价。supplies：选中报价/预算与摘要，无逐列表行全院查询。
- hospital_library：每页 12 张卡，槽位显示最多 28 条，显式翻页/刷新；非每帧解码所有医院。environment：热图为显式操作，不能算每 500ms 或每帧完整 heatmap；普通状态为单点。expansion：connector/order 多个线性列表投影但无逐行完整服务报价，暂不凭小重复遍历扩展优化。
- research：每帧 opened/解锁小状态检查；完整 readiness 是显式按钮。schedule：选中员工、固定 3 班×6 选项，覆盖计算手动触发。training：选中员工预览及提交，非全员报价。waiting：显式一次 seat_candidates 后展示结果。ward：选中病例的票/会话/准备/住院等分别一次线性过滤，没有每床重跑完整集合。remodel 的蓝图列表仅构建/显式操作读取，非周期摘要反复读库。

### 视图、共享资源、shader

- `_presentation_index:750` 已按一次 update 建立 moves、visits_by_actor、sessions_by_facility/visit 和人员工作状态索引；`_pose` 与设施动画只读所属桶。不跨更新缓存旧事实，同 tick 命令可见。此处不列剩余 A×V 或 A×S。
- `_sync_entities:311` 为视锥/楼层成员重新扫描 actor/facility，当前观察范围不是完整世界实例化；摄像机移动时仍需当前几何判断。pick 只在输入触发扫描候选；overview 只对楼面包围盒的固定 8 个角投影，未发现 8 次全院扫描。
- `view_resources.gd` 目录先索引；同路径 PackedScene、源哈希和首次场景验证在资源使用期缓存。首次剪辑/骨序/材质交叉核对是发布源验证，非每实例每帧执行。最后使用者释放是资源所有权规则，不能无限保留资产来宣称消除冷加载。
- `skinned_pose_batch.gd` 按至多 64 行/40 骨分页面，publish 的行×骨矩阵上传确实随当前姿态变化；不能把必要的动态矩阵和来源检查当作同值重算。`compatibility_skin_input.gd` 的深数组一致性在准备/绑定等验证入口，未发现普通 publish 每顶点重比较整份几何。
- `view_work_budget.gd` 缓存当前帧 ID 与剩余预算，常数访问；palette 为常量。7 个自有 shader/include 已检查：正式蒙皮读取四权重骨矩阵，readback 为诊断通道并有固定 24 次颜色反解；没有 CPU 全目录循环。GPU实际成本及视觉正确性均未测。

### 内容与自有资源生成

- `content_registry.gd` 在装包时建立 definition、species/disease binding 和兼容目录索引，并冻结；definition、resolve_bindings、effective_case_body 不扫描全部目录。facility_definition 查固定 8 个集合的字典成员，不遍历全部设施定义；当前不为这个固定上限另建缓存。
- `content_db.gd` 的 facility_fee/doctor_fee 仍线性扫描 8/4 条收费；这是明确的重复小表查找，但当前规模有界、无运行证据，不提出独立优化。actor_body 的定义查找已索引，复制三维尺寸是返回值所有权。
- `content_loader.gd` 与 `content_pipeline.py` 仅装包/内容构建触发；疾病方案先分组再引用，引用查验与依赖图有索引/完成集合。角色×种族校验是完整内容合法性，当前没有业务帧内全目录查询。`content_load_result.gd` 为结果容器，schema100 为规则数据。
- `addons/source_assets/plugin.gd` 导出开始时建立 path→record map，每导出文件按 map 命中核验该源文件哈希；非每文件扫描完整 manifest。`assets/models/import_vertex_colours.gd` 每次导入递归一次，且相同原 mesh 的 SkinInput.prepare_mesh 有本次导入字典复用。
- `art-source/build_stage01.py` 离线为固定 5 个身体、4 台设备逐个选目录记录；四个脚本的 mesh/骨架/逐关键帧及预览枚举属于资源生成。仅 `next(row for catalog if id)` 是小固定导出数×目录的冷扫描，未发现产品运行路径；不运行 Blender 或调整资产。

### 持久化与自有原生实现

- `snapshot_store._begin_world:169` 资源估算后冻结完整世界交给异步写入；冻结隔离活世界后续修改，是 CORE-19 契约。`_write:344` 事务内全读校验、封存提交、重新打开验证，以及 `_cleanup:460` 对旧保存点完整校验再保留/删除，属于不同持久化边界；CORE-46 明确禁止用清单元数据代替完整校验。不能仅因多次遍历相同 DTO 就删除这些门槛。当前保留配置自动 5、手动 20、检查点 3；坏点不能占有效回退配额。
- `hospital_library.scan_page:34` 按 generation 缓存已排序医院列表，卡片取 sealed manifest 元数据；slots/list_commits 分页上限 256，不全解码世界。仅选择医院、恢复、导入/导出时验证目标世界。导出克隆、私有 staging 验证、ZIP SHA/CRC、导入映射、保存回读是各自边界，未提出跳过其校验。
- `blueprint_library.gd` 枚举文件名后只读取页内最多 30 个合法蓝图，非列表每行重新读取所有蓝图；没有常规帧触发。`json_stream.gd` 按 32768 字节块读写，已具有块级 byte fast path，规范排序和 UTF-8/数值完整校验必须保留。`backup_zip.gd` 最多 3 个条目、块式解压/写出、表驱动 CRC，Adler 已每块归约；未发现随累计世界长度反复重拼完整缓冲的路径。
- `platform_session_guard.c` 独占句柄、路径及磁盘/内存资源检查，数字解析 locale 在初始化创建复用；没有每实体重复枚举进程/目录。`platform_sqlite.h:195` SQL chunk read/write 语句按连接缓存，reset/clear_bindings 后复用；世界块按复合主键 cursor 单块读取，非每块扫描所有历史块。元数据行上限 256、单 chunk 32768 字节。
- `platform_arrivals.cpp` 自有模型装配、结构证书与精确求解适配已检查；SCIP/SoPlex/GMP/Boost 等第三方内部未审计。结构 flat 有因子/组合去重，超过 4096 选择后用 implicit graph；graph intern、group memo、支配证明 memo、证书和当前模型复用已存在。`Model.price:1294` 一次 DAG 动态规划价格化所有节点；LP 的逐轮重新 price 输入对偶价格不同，是算法必要工作。`solve:1598` 非 dirty 直接 summary，预算/岗位变化才重新求解，原生精确证书/岗位 MIP 也有复用。

逐文件清单包括每个自有代码文件的 SHA-256、行数和审计入口；非代码只列举身份/用途。文件枚举与哈希是源码核对，不是运行性能测量。没有运行任何候选的验证用例，以上用例均为落地改动时的受影响边界建议。

## 自有代码逐文件覆盖表

覆盖 55 个自有代码文件、12422 行；清单另列 229 个非代码文件。行数为源文本统计，不是执行量。

| 文件 | 行数 | 检查入口/结论定位 |
| --- | ---: | --- |
| `addons/source_assets/plugin.gd` | 43 | manifest indexed once/export matched source hash once |
| `art-source/build_stage01.py` | 543 | offline geometry/bone/keyframe build/fixed nine asset catalog lookup |
| `art-source/gags/build_gags.py` | 295 | offline fixed three prop assets/keyframes/export |
| `art-source/gags/preview_gags.py` | 74 | offline fixed prop/clip preview list |
| `art-source/preview_stage01.py` | 76 | offline fixed body/machine preview list |
| `assets/models/import_vertex_colours.gd` | 31 | import tree traversal/original mesh preparation map |
| `game/app/app_root.gd` | 1007 | frame advance/view refresh/details grouping/save-switch publication boundaries |
| `game/app/game_session.gd` | 120 | pending resume/fixed-step loop cap/paused command boundary |
| `game/content/content_db.gd` | 84 | indexed definitions/body values/8 facility and 4 doctor fee rows |
| `game/content/content_load_result.gd` | 9 | load result container |
| `game/content/content_loader.gd` | 544 | pack load dependency/reference loops and grouped protocols; cold path |
| `game/content/content_pipeline.py` | 552 | offline pack validate/build/grouping/index loops |
| `game/content/content_registry.gd` | 123 | immutable per-collection and pair indexes/fixed 8 collection facility membership |
| `game/persistence/backup_zip.gd` | 439 | max three entries/bounded streaming/hash CRC Adler |
| `game/persistence/blueprint_library.gd` | 88 | filename enumeration and bounded validated page |
| `game/persistence/hospital_library.gd` | 526 | manifest page cache/import-export boundaries/identity remap nested prefix scan |
| `game/persistence/json_stream.gd` | 292 | canonical keys/chunk fast paths/UTF-8 and numeric decode |
| `game/persistence/snapshot_store.gd` | 562 | freeze/encode/full durable validation/cleanup/chunk paging |
| `game/platform/windows/platform_arrivals.cpp` | 1910 | own graph assembly/intern memo/structural proof/LP-MIP exact reuse/role loop; vendor internals excluded |
| `game/platform/windows/platform_session_guard.c` | 603 | handle/path/resource checks/decimal locale lifetime/extension bindings |
| `game/platform/windows/platform_sqlite.h` | 376 | connection ownership/cached chunk statements/bounded parameter and row loops |
| `game/ui/action_panel.gd` | 142 | visible-only deferred build/500ms summaries/selection helpers |
| `game/ui/arrivals_panel.gd` | 40 | resident pages/day statistics caller/explicit scale controls |
| `game/ui/build_panel.gd` | 268 | cached preview caller/deep copied per-frame signal |
| `game/ui/clinical_panel.gd` | 70 | linear visit summary and selected action |
| `game/ui/departments_panel.gd` | 48 | one service summary/list builders; service owner operations |
| `game/ui/environment_panel.gd` | 68 | single-cell status/explicit heatmap/material controls |
| `game/ui/expansion_panel.gd` | 129 | connector/order list projections/selected quote |
| `game/ui/finance_panel.gd` | 46 | one explicit model query/12 rows/bounded forecasts |
| `game/ui/hospital_library_panel.gd` | 152 | 12 cards/28 slot UI/explicit paging-refresh |
| `game/ui/maintenance_panel.gd` | 50 | 16 facility page/selected quotes/status |
| `game/ui/plans_panel.gd` | 70 | duplicate initial compare/500ms details/submit recheck |
| `game/ui/recruitment_panel.gd` | 125 | full list query reused for status-only timer; shared clinical finding |
| `game/ui/remodel_panel.gd` | 401 | 500ms per-preparing-order wait query; shared operations finding/explicit blueprint list |
| `game/ui/research_panel.gd` | 219 | opened frame predicate/selected preview/explicit readiness |
| `game/ui/schedule_panel.gd` | 82 | staff list/fixed 3x6 slots/explicit coverage |
| `game/ui/staff_life_panel.gd` | 28 | facility x four recreation definitions at build/selected status |
| `game/ui/supplies_panel.gd` | 33 | selected purchase/budget/status |
| `game/ui/training_panel.gd` | 70 | selected worker/course preview and submit |
| `game/ui/waiting_panel.gd` | 41 | explicit once candidate model/no per-row requery |
| `game/ui/ward_panel.gd` | 134 | selected visit sequential ticket/session/stay/preparation scans |
| `game/view/build_overlay.gd` | 59 | basis equality/linear rectangle/irregular cell x blocked membership |
| `game/view/compatibility_skin_input.gd` | 87 | once prepare and bind identity validation/no full-array per publish compare |
| `game/view/hospital_palette.gd` | 31 | constant palette |
| `game/view/hospital_view.gd` | 1235 | full update pipeline/root callers/signature builds/one-update indexes/resource publication/pose/tree lookup/batches/pick and overview |
| `game/view/shaders/skin_readback.gdshader` | 14 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/shaders/skin_readback_original.gdshader` | 15 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/shaders/skin_readback_output.gdshaderinc` | 48 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/shaders/skinned_pose.gdshader` | 4 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/shaders/skinned_pose.gdshaderinc` | 16 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/shaders/skinned_pose_double_sided.gdshader` | 4 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/shaders/skinned_pose_surface.gdshaderinc` | 23 | own shader/include: formal four-weight skin or diagnostic readback fixed work; no runtime/GPU measurement |
| `game/view/skinned_pose_batch.gd` | 209 | source validation/64 row 40 bone pages/actual current matrices |
| `game/view/view_resources.gd` | 136 | manifest index/shared PackedScene/hash and first path validation lifetime |
| `game/view/view_work_budget.gd` | 28 | frame ID and remaining work budget constant access |
