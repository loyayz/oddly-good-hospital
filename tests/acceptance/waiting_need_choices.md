# 生活设施候选共用本次调度的首次身体刷新

实际链：`HospitalSimulation` 的 waiting dispatch → `_dispatch_need` → `_dispatch_public_need` → `_public_need_choices`。既有区域选择使用本地 `need_scan.refreshed`，两个设施候选入口此前没有传递此标记，每次都以默认参数强制重建原空间身体索引。本次只补传同一字典；不改变选区、FIFO、候选全集、排序、45秒预算或真实使用条件。

契约：

- 每次 waiting dispatch 新建标记，第一次实际选区或设施候选仍强制吸收上游/raw 身体变化。
- 后续候选只取消无条件强刷，仍调用原 `_ensure_actor_index`，世界、完整 facts 所有者及 revision 改变仍正常失效。
- 每次候选有独立只读 scope，提交移动/预约前关闭；不共享 fit、路线或占用结果跨越事实修改。
- 既有 `sync_actor`、同行结束同步及 `reservation_changed` 继续生效。没有改动移动、导诊、空间索引或预约接口，没有新索引或持久缓存。
- 独立调用使用空字典默认值，仍每次强刷。没有承诺支持同一内部 dispatch 中未通知、未 touch 的任意 raw 写入；这也不是既有批处理的契约。完整 facts 替换另行验证。

| 选择器 | 覆盖 |
| --- | --- |
| NEED-CHOICES-READ | 四次只读报价，首次前 raw 身体变化、两次间 sync_actor、同 revision 完整 facts 替换、新 WorldState、独立 raw 调用、新预约。报价完整相等，事实/RNG只读，scope关闭，世界合法。首次之外需要失效时仍重建。 |
| NEED-CHOICES-DISPATCH | 六个合法已到区、尚未选择生活设施的需求，原生 dispatch 与仅强制每次刷新的参考比较完整世界、身份、票号、RNG和移动意图；不提前预约。重建6→1、人物访问42→7。只验证选择交接，不冒充真实走到设施。 |
| NEED-CHOICES-POSTURE | 已坐边界经原 `_release_seat` 真实释放，站姿与身体形状同步，后续报价与强刷相同。 |

相关旧用例：STAFF-35、STAFF-47（真实移动、服务、安全退出与期限），以及 `run_waiting_need_scan.gd` 的普通/raw+同步两变体（既有选区首次刷新契约）。不运行未变的完整专题或整院性能基准。

局部计时：固定160人、50组每组六次候选读取，比较300次强刷与50次首刷。计时检查候选总数相等与事实只读，完整报价数组相等由 READ 专项另行证明。只证明此 helper 的局部开销；不是整院、完整tick或渲染性能。实际 Linux诊断来源为46001aa3，当前实现基于较新的dbaf7065，两者不混称同一轮完整基准。

入口：`--headless --path <repo> --script res://tests/acceptance/waiting_need_choices_runner.gd -- <output.json> NEED-CHOICES-READ NEED-CHOICES-DISPATCH NEED-CHOICES-POSTURE`。使用证据记录的Godot 4.7.2和正确XDG路径。
