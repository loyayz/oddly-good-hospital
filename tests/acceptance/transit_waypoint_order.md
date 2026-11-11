# 交通临时让位的移动请求序

## 合同与交接

[移动设计§3](../../docs/design/01-simulation.md#3-移动队列与服务预约)和[导航规格§4](../../docs/specs/26-10/2026-10-19-task-navigation-movement.md#4-移动执行)要求临时让位保留原目的地、原路线和移动请求序。电梯口侧移及走完临时点后重接原连接段属于同一次移动。

移动请求序与交通票分别归属原行程和当前实际候梯段。[A41](transit_presence.md)仍要求实际离开候位时取消交通票、解除未登舱指派，回站后领取新票；已经开始的空车和载客安全段继续完成。

`queue_waypoint`及重新接近同一连接入口的派路保留已有`request_sequence`。合法的非待派路边界允许没有该字段，这类输入首次派路仍领取一个新序号。其他新移动和改目标的原派路规则保持。

## 可选用例

| Selector | 真实前提与被测交接 |
| --- | --- |
| `waypoint_solo` | 单人实际到站取票、空车实际接人；提交临时地面点并真实走离、回站、重新取票和到达原目标。 |
| `waypoint_convoy` | 同一过程使用完整两人尾迹和原步长，核对真实步幅及完整世界合法性。 |
| `aside_solo` | 来车实际开始驶向等候者所在层，由生产`HospitalTransit.begin`自动触发`_stand_aside`及`queue_waypoint`。 |
| `aside_convoy` | 完整同行队列在来车期间自动侧移，随后完成原跨层行程。 |

前置边界只声明真实楼板、连接和已对齐的起始身体，不预置完成位移、登离舱或已完成票据。原移动由`request_move`或`request_group_move`创建；所有被测位移均由生产阶段⑤按0.1秒执行。

四例均验证：提交临时点不重发移动序、不改变最终目标、临床票集合及当时交通票；真实`GameSession`暂停不推进任何世界事实；待派路和实际离位后分别从完整`world.freeze()`事实创建新`WorldState`及新运行时继续。恢复覆盖事实和运行时重建，不覆盖保存管理界面或磁盘快照协议。

## 运行

准备独立工程并完成Godot导入后执行：

```powershell
& 'C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path '.cache/transit-waypoint-order-20261112/fixed' --script 'res://tests/acceptance/transit_waypoint_order.gd' -- 'C:/code/loyayz/oddly-good-hospital/.cache/transit-waypoint-order-20261112/fixed/local-order.json' 'waypoint_solo,waypoint_convoy,aside_solo,aside_convoy'
```

相关回归使用`transit_presence.gd`的`leave_solo,leave_convoy,order_solo,order_convoy,repeated`，覆盖离位取消、回站新票、仍在位者按票序登舱，以及三轮真实双向运输。

## 证据与边界

旧实现四例均在原请求序断言失败，目标、真实移动、交通票归属和实际到达断言通过。修复后四例及五项相关回归通过，无脚本错误。结果、实际耗时、完整命令及冻结源身份见[专项证据](../../docs/reports/evidence/2026-11-12-clinical-performance/transit-waypoint-order.json)；原失败保留于`.cache/transit-waypoint-order-20261112/baseline`。

这些用例验证临时行程保序及相关交通交接，不证明任意密度的无饥饿性、堵出口角色的局部让行正确性，或160人性能达标。电梯busy分支、容量、真实身体和离舱保护均未改变。
