# 相遇时只让一人绕开

依据 `docs/design/01-simulation.md` 的实际相撞与单人局部动作规则。没有个人优先权、让行承诺或未来连接的动态预检查。

```powershell
godot --headless --path . --script res://tests/acceptance/run_one_local_avoider.gd -- OUTPUT.json
```

`LOCAL-ONE-AVOIDER` 从合法行程中途开始：walker 在 `[40,70]`，原目标 `[43,70]`，已经打算回接 `[41,70]`；leaver 在 `[40.6,70]`，正向 `[40.6,71]` 侧移，原目标 `[45,70]`。只提供前置事实，两人的后续身体接触、行走和到达均由生产移动实现执行。

walker 的实际前进一步会碰到 leaver，leaver 自己的当前一步畅通。此时保留 walker 的原回接意图，不让它另起侧移；当前通路安全后立即继续，不要求 leaver 先完成整次临时动作。两人必须在 180 步上限内分别到达原目标，原路线、请求序和任务目标保持，逐步检查真实身体和已接受扫掠的安全。

首次接触后通过生产 HospitalJsonStream 写盘、摘要校验、解码并冷建，核对完整事实及下一真实步一致，拒绝已有非法局部状态。正常分支继续至两人到达；冷恢复检查在本例覆盖下一步，完整冷恢复到达另由 WIDE/LOST 与 CLIN-37 覆盖。
