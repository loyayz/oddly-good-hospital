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
