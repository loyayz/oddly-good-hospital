# 护理床停点索引

依据房间规格§3.2、§9及护理床通行/使用权分离：床体和真实身体仍参与碰撞，空岗位只限制外人的停点。每份EQ05预约无论包含多少患者、医护、维修区域，只贡献一项所在楼层计数。

```powershell
godot --headless --path . --script res://tests/acceptance/bed_destination_index_runner.gd -- <新结果.json> BED-INDEX-COUNT BED-INDEX-LIFECYCLE BED-INDEX-OWNER BED-INDEX-ORACLE BED-INDEX-STOPS
```

只执行显式选择项。共享前提复用既有已建双层与真实交通设施输入，通过正式床预约创建两层三床的完整预约；每个用例从独立事实复制开始，运行时索引不复制。输入与恢复后均校验世界。

- `BED-INDEX-COUNT`：一床多区域只计一次，同层多床及不同层共存，重复callback不累计。
- `BED-INDEX-LIFECYCLE`：正式授权、授权事实撤销、移除至零、重新加入，稀疏楼层摘要及查询立即生效。撤销和释放是明确的计算边界，不新增玩家命令。
- `BED-INDEX-OWNER`：独立冷世界、同修订完整facts替换与恢复、geometry revision重建；不同所有者的派生视图不串用。
- `BED-INDEX-ORACLE`：全量读取预约事实，独立判断EQ05、软区域、主人/医护/成员权限、严格相交和确定性首阻挡者；不使用生产摘要、BodyIndex或生产权限函数生成期望值。
- `BED-INDEX-STOPS`：目标层或原局部路径所在层没有床停点占用时精确早退；相关层有占用时保留原结果，只同步借一次活视图。计数子类只验证查询次数，不提供耗时收益。

这些计算合同不证明患者实际入院或完整转床。相关真实流程选择`ROOM-14`及`BED-CLAIM/LOCAL/GROUP/TRANSIT/FACING/RESTORE`，不默认扩展至SPACE全专题。局部纯查询基准另外保留完整160人来源事实或完整R1终态的所有角色、设施、预约与随机流，只对合法地面角色及其原Move执行查询，不将outside角色改作移动输入。纯耗时与带计数版本分别运行，不能以计数探针的耗时宣称优化收益。
