# 接触查询单侧候选复用

`BodyIndex.candidates()` 返回同层、严格包络相交、排除原成员后的完整排序身份数组。当前身体或本步已接受扫掠的一侧为空时，接触查询直接使用另一侧数组；两侧都有候选时保留原字典去重及完整排序。原预约查询、精确扫掠、复合队形、权限、首个真实接触语义和计数不变。区域缓存分支继续完整严格重筛。改动只位于 `HospitalMovement._movement_contacts`，不改变局部避让、查询频率、模拟预算或跨步缓存。

## 正确性用例

| selector | 输入与断言 |
| --- | --- |
| `current_only` | 完整当前身体单侧命中；全部身份及次序保持 |
| `accepted_only` | 当前身体已离开探针，合法0.2格已接受扫掠仍相交；不能漏掉历史扫掠 |
| `both_duplicate_distinct` | 当前身体与扫掠同时含同一身份，另有不同身体；必须完整去重且保留不同身份 |
| `empty_with_reservation` | 两侧身体都空，正式设施预约仍阻挡；不能以空身体集合跳过预约 |
| `order_first_contact` | 完整收集、首接触、普通与缓存查询返回同源的稳定次序，首接触仍准备全部候选 |
| `compound_gap` | 合法三人转弯队列临界输入；外包框内的真实空隙不阻挡，全部实体区域仍阻挡 |
| `strict_edge` | 精确贴边不相撞，0.0001格相交保留真实身份；区域缓存不能把外框命中当精确命中 |

每个新例分别比较 `full`、`first`、`cached_full`、`cached_first`，检查完整 typed MotionResult、完整候选计数及世界只读。`movement_contacts_oracle.gd` 从所有 Actor/同行事实、显式接受扫掠和全部预约独立枚举，不使用空间索引、生产接触函数或旧输出定义期待。身体、同行和 `BodySweep` 继续使用未改变的几何接口；此处验证候选合并，不另写物理算法。

接受扫掠及转弯队伍是计算测试的合法临界输入，不构成此前实际行走的证据。贴边和预约探针也是接触计算，不声称角色已到达该处。相关旧用例只选 `detour_first_contact` 和 `detour_contact_regions` 的 `exact_candidates`、`permissions`；不运行其他专题。

```powershell
godot --headless --path <共享工程> --script res://tests/acceptance/movement_contacts_candidates_runner.gd -- <结果.json> current_only,accepted_only,both_duplicate_distinct,empty_with_reservation,order_first_contact,compound_gap,strict_edge,first_contact,regions_exact,regions_permissions
```

## 只读局部查询性能

输入使用当前9e3a1e0真实7000步完成边界的完整 `.final.bin`，保留全部179个 Actor 及所有世界事实，其中169人在院。遍历所有已经发出路线的地面 Move，保留原 `goal/local/current_body` 三类完整 owner 输入；旧终态的317是历史数量，不固定或裁剪当前数量。每类 owner 身份另与全部原 Move 独立枚举核对。不能截取最近角色、裁剪查询或删去旧事实。原 local target 和 corners 的首步转向及后续直线全部保留，展开后的接触调用数另行报告；零距离原目标是静态接触计算，不声称新增实际移动。

每个进程先在计时外比较完整独立 oracle、typed 输出及世界事实，再测量同一完整语料。完整边界没有本步历史扫掠，性能输入不会伪造接受扫掠；该分支由功能 selector 验证。测量只包括接触查询与 MotionResult 创建，不包含 oracle、散列和文件写入。普通完整收集与原首接触模式分别报告。

`prepare_movement_contacts_probe.py prepare` 生成 A/B 与独立 counted 源。A 来自明确提交，B 仅移植工作区的该函数；反向替换必须逐字节恢复 A。`install` 验证其他全部运行时 Git blobs、原生库和完整输入后，才写入独立共享工程。只准备小型 overlay，不复制工程、不启动引擎。

```powershell
python tools/performance/current/prepare_movement_contacts_probe.py prepare --baseline 9e3a1e0 --output .cache/contact-candidates-overlay02 --input .cache/performance160-clinical-family-20261112-v3-candidate01/qualification-r1/r1.json.final.bin --reference .cache/performance160-clinical-family-20261112-v3-candidate01/qualification-r1 --expected-actors=179
python tools/performance/current/prepare_movement_contacts_probe.py install --overlay .cache/contact-candidates-overlay02 --project <隔离纯基线工程> --variant b --record <安装记录.json>
godot --headless --path <隔离纯基线工程> --script res://tools/performance/current/movement_contacts_probe.gd -- --input=<完整final.bin> --output=<结果.json> --mode=plain --iterations=1000 --expected-actors=179
```

共享工程只 import 一次。先分别执行 A/B 功能选例；独立计数进程使用 `a_counted/b_counted`、`--mode=counted --iterations=1`，不报告性能耗时。随后用无计数钩子的源，按 `A/B、B/A、A/B` 执行三对普通查询。`verify` 接收上述顺序的八个微测结果，核对完整事实、语料、typed 输出、源码和三对耗时，不设最小收益比例。

结果仅说明这个只读接触子查询的成本，不能替代160人整步、功能覆盖、渲染或稳定性验收。功能错误、前提/工具失败和真实业务阻挡分别报告。

## 2026-11-12 验证

A/B七个新计算边界及三个关联选例通过，独立微测核对81项通过。当前完整终态保留179条 Actor、169人在院、152个 Move；151个 ready ground Move 产生439个三类 owner 输入，完整展开为每模式568个接触查询。独立计数时 A/B 均执行1136次查询、1842个完整候选、1136次预约查询；该完整边界没有本步历史扫掠，B避免了A各1136次的字典和排序。

三对无计数钩子的完整查询分别为 A/B：19.209097/18.728900秒、19.156121/18.561592秒、19.340506/19.138380秒，整组减少2.500%、3.104%、1.045%。第三对 `current_body.first` 的B耗时更高，原因未测，不能称各类查询均提速。首轮工具解析错误和一次 StringName Move 键前提错误保留，未记为业务通过。证据见 `docs/reports/evidence/2026-11-12-clinical-performance/movement-contacts-candidates.json`。本改动尚未做160人完整模拟步性能复验。
