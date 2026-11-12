# 无图结构几何缓存：实现与定向验证

## 规则、交接与选择理由（修改前记录）
业务规则、路径预算/重试/顺序、碰撞、门预约及原 134217728 字节 allowance 不变。仅在 structural_clearance 已有 graph lookup miss 后，复用无成员无 offset 的完整静态 body geometry。static-query acquisition 是交接边界；动态身体、预约及真实移动仍由原 owner 判断。

沿用已独立 micro 验证的 candidate：完整 body/proxy/姿态与字段存在性 key；weak World/revision 和当前完整 static source 校验；source/floor/graph/query/body 共用预算，graph/body 同 LRU。source 的 occupancy 元数据不进入静态 resident，不缓存 live permission。allowance 非实际 RAM。已测 cold 更贵，重复 missing-envelope API 更快，不声称整窗收益。

选择新增 body/proxy/来源/权限/weak owner/联合 LRU/超预算边界；navigation_source_lifecycle 直接子例、SPACE-58 floor_static_loading、PERF-08、detour_geometry_reuse 直接子例、run_local_return_geometry。它们分别覆盖源生命周期、floor 共享/驱逐、原预算和投影、动态释放/静态编辑、真实移动。不同对象身份不是业务契约；每次重新 acquisition 与实际阻挡/释放仍须验证。仅同步 GUI operation_driver 的计账报告，不运行 GUI 验收。

## 与原先结构预加载约定的关系

原预加载不是缺失或被撤销。`52adb6e`（2026-11-07）的设计16§5已规定：激活/恢复时完整加载当前观察层基础几何，实际切层加载对应整层；同一段明确基础不依赖身体，不预建全部身体、姿态和楼层的通行图笛卡尔积。`8e5bffd`（2026-11-08）再增加选中层入口/电梯到真实体型空队首和服务位的静态路径预热，`e6d126f`调整真实队列目标。设计04中仍明确未命中时正常寻路。

实际链路是 AppRoot 激活/恢复/成功切层 → Simulation.prepare_floor_static → NavigationCache.prepare_floor，另调用公共到达及导诊路径准备。plain_v4 同样在模拟前准备 observed_floor，本轮固定为1；后台层按需进入同一 floor_geometry 缓存。

须区分四项：FloorStaticGeometry 保存不依赖身体的整层墙门/设施/连接器及索引；RouteClearance 借用这些容器，再计算某个完整身体的门宽/净高及门格索引；FloorNavigation 另建96×96节点/边；导诊预热仅准备规定固定起终点路径。旧 structural_clearance 能借 resident graph 的几何，但缺图时每次 new RouteClearance，结束后不留存它。实测2/3/4层三个稳定键共318次fallback是身体适配层重复构造，并非318次重新加载基础楼层，也不是预加载承诺未兑现的证据。

这次新增的是预算内的轻量身体静态投影复用，不用强建寻路图来消除重复，也不扩大整层预加载范围；预约权限、动态占用仍实时判断。仅凭该短段不能判断完整窗口内所有基础层驱逐/重建次数，亦不能推出整窗收益。

## 验证状态
Godot parse-only 与 git diff --check 通过。新增 body 最终 21 检查通过；source lifecycle 14、SPACE-58 floor 13、PERF-08 13、detour 16 检查通过。真实 local-return 正序/反序身份两例均 91 ticks 到达，保留原目标/请求序列和固定旁人，binary32轴检查通过。

body-01 唯一失败是测试前提：恢复 World 的 runtime geometry_revision 重置为0，而原 live World 已递增。改为两个真正恢复的同revision World，各自首次查询前具有不同静态内容；只重跑 body-02，通过。生产算法未为通过而改变，失败raw保留。

缓存测试覆盖缺图复用、完整body同ID差异、proxy size/存在位、姿态、group/offset原fallback、静态替换/跨World同revision、真实预约grant后live权限变化、weakWorld释放、source单独驱逐、floor owner独立退休后body仍完整计费、graph/body两向联合LRU、超预算完整borrower不resident和zero trim非负计账。floor单独退休用既有pressure用例同样的直接owner清理模拟，并非声称自然工作负载已触发该驱逐。

总额消费者改用 total_charge()，graph类别计数不泛化；operation_driver只有导航总清空报告包含body，未运行GUI验收。验证阶段没有新完整性能窗、没有重跑micro；实现与证据由同工作分支一并发布。该轮为选定功能验证，不是全量验收。

### 原始进程记录

|运行|状态|进程wall秒|
|---|---|---:|
|parse-01|pass|3.711661|
|body-01|测试前提失败|3.512045|
|body-02|pass|4.216638|
|source-01|pass|4.118171|
|floor-01|pass|3.419716|
|perf08-01|pass|3.612541|
|detour-01|pass|3.516621|
|local-01|pass|3.711690|

现有663个UID文件逐字节未改，包含既有导入旁文件。下方 raw 保留每次独立命令、输出、日志、host、源码清单和失败记录。计账allowance不是RAM。

### 审查追加合法性断言

新增body用例将初始/最终World.validate为空纳入checks（不只记录）。仅body-03-validity重跑：21检查全通过，wall 3.811679秒。原selected.zip不覆盖，新增结果独立validity-correction.zip。整数reason/door等价helper不单独证明fractional sweep；本轮真实移动由detour/local选例承担。

## 持久证据与限制

- [选例完整原始包](evidence/2026-11-12-structural-body-cache/selected.zip)：2294610 字节，102 个原始成员及 [manifest](evidence/2026-11-12-structural-body-cache/selected.members.json)，SHA256 `684cb73fc12a2530ca89130a51cd620a54fb01c94c4a1db648727e5472cd7ba2`。
- [最终合法性断言补包](evidence/2026-11-12-structural-body-cache/validity-correction.zip)：274723 字节，12 个原始成员及 [manifest](evidence/2026-11-12-structural-body-cache/validity-correction.members.json)，SHA256 `0cf155c1d443b118b82ad8d539840510deda68694c784249728df55d8144b684`。

两包已独立核对 CRC、精确成员集合、每个文件长度及 SHA；最终测试源码与补包一致。独立源码审查未发现来源、预约或预算方面的阻断。旧失败包未覆盖，所有更早性能原始文件及三轮完整诊断窗口继续保留。

[隔离固定微基准](2026-11-12-structural-cache-micro.md) 只证明三条真实 missing-envelope 的重复 API 收益，并保留了更贵的 cold 构造。其 44 成员原始包已从 `acac8277f21f4f6298706b864fa520e183f899df` 实际下载验证。当前实现的整步、整窗收益尚未测得；原延迟门槛及两个未覆盖业务 gate 未因此通过，GUI/GPU/audio/发行验收均未运行。

最终 `game/building/navigation_cache.gd` SHA256：`f67bebbc9a78dbb79089902010b68ccda2d793c17f39d0176a282c87535b033f`。

最终 `game/building/hospital_navigation.gd` SHA256：`48f3b469753f3c5b557f0420e84953dc08fc3fce41011eedb635366239c6cbb2`。

## 发布版实际8步整合验证

源码提交 `1e5bb6e3c0883836275aeab74e64847255fd8a06`，复用原终态输入 SHA256 `41928476a199dbf3e35b3ff74cd54a52fd0801feb92c5b1d1a5d6fe035258a68`，原 plain_v4 无插桩驱动、0 prefix/8 steps、0.1模拟步、4 workers、observed floor 1，原内容/引擎/原生库未变。新独立进程与HOME/XDG/TMP；请求app策略，Linux实际platform_default。进程5.418秒、exit0；完整World/RNG/有序事件与业务结果等于之前独立plain8，最终文件SHA256 `6ecee78b194a7925938549383dc9fb87f222a3843d901d790fe83ac7aeaeb93d`。仅为限定边界整合验证，不由8个样本声称性能通过。

[原始包](evidence/2026-11-12-structural-body-cache/plain8.zip) 1183484字节、24成员，SHA256 `687a50dcf912ac8cd8bd0ce28166ec490a229285ad24b4ca93ac84d57baea59c`；[逐成员清单](evidence/2026-11-12-structural-body-cache/plain8.members.json)及[对比结果](evidence/2026-11-12-structural-body-cache/plain8.comparison.json)。本地CRC及全部成员字节/SHA已核验；持久发布后实际下载读回，之后才开始下一完整窗口。此前功能selected与validity-correction两包已从1e5bb6e实际下载校验，分别102和12成员均匹配。
