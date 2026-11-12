# 无图结构几何缓存：实现与定向验证

## 规则、交接与选择理由（修改前记录）
业务规则、路径预算/重试/顺序、碰撞、门预约及原 134217728 字节 allowance 不变。仅在 structural_clearance 已有 graph lookup miss 后，复用无成员无 offset 的完整静态 body geometry。static-query acquisition 是交接边界；动态身体、预约及真实移动仍由原 owner 判断。

沿用已独立 micro 验证的 candidate：完整 body/proxy/姿态与字段存在性 key；weak World/revision 和当前完整 static source 校验；source/floor/graph/query/body 共用预算，graph/body 同 LRU。source 的 occupancy 元数据不进入静态 resident，不缓存 live permission。allowance 非实际 RAM。已测 cold 更贵，重复 missing-envelope API 更快，不声称整窗收益。

选择新增 body/proxy/来源/权限/weak owner/联合 LRU/超预算边界；navigation_source_lifecycle 直接子例、SPACE-58 floor_static_loading、PERF-08、detour_geometry_reuse 直接子例、run_local_return_geometry。它们分别覆盖源生命周期、floor 共享/驱逐、原预算和投影、动态释放/静态编辑、真实移动。不同对象身份不是业务契约；每次重新 acquisition 与实际阻挡/释放仍须验证。仅同步 GUI operation_driver 的计账报告，不运行 GUI 验收。

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
