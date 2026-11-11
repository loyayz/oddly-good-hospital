# 公共区域真实入区与安全停留

入区入口只表示结构可通行，不表示可站立、已经入用或持有设施。完整身体真实进入目标区域后，才可由原任务改去本区设施；只有当前安全占地才能停步等待。候诊椅按真实入用位置先到先坐，生活需求保留原450 tick期限及80 tick兜底工作。

按独立交接选择运行，不以本组代替全量验收：

- `run_public_area_arrival_integration.gd <json>`：患者真实去程、临时入口拥堵、无椅、安全站立、当前保存恢复、剩余45秒预算拒绝及外来移动所有权，共6项。
- `run_arrival_boundaries.gd <json>`：分数起点、完整身体、不同体型、紧凑3×3/4×4房间、无房间大堂、跨层真实乘梯及保存、卧姿退出、实际安全80 tick、门/连接器范围和结构变化。
- `run_need_budget_gate.gd <json>`：入口行程加在用设施剩余服务时间的估计，在剩余额度少1、相等、多1 tick边界上分别兜底、允许出发、允许出发。保留原45秒预判，不刷新需求时钟，允许出发者执行真实有界移动且不提前占用设施。
- `run_arrival_deadline.gd <prefix>`：先真实走到设施入用前边界，再生成449/450/451合法临界输入，执行原11项期限验收。到区域不等于到设施，不伪造此前449 tick历史。
- `arrival_ownership_staff_visitors.gd <json>`：员工/访客真实入口、当前保存恢复、自动/手动双人娱乐及所有权交接，共35项。拥堵输入按全部安全点放置合法身体，直到确实没有候选，再释放一个邻近身体并真实走动恢复；不以任意40个身体假定满员。
- `run_prepared_waiting_failure.gd <json>`：显式准备的两种原生失败原子性、完整A*退路及事实只读。已退役的普通如厕公共区域分派与预热对照不再执行。
- `runner.gd space --case=SPACE-51`：安全驻足查询仍与完整参考求解一致，显式距离场、越界、权限、失效与驱逐契约。测试的全集投影在读取cells前显式准备，不要求普通入口查询提前展开。
- `visitor_seat_competition_runner.gd <prefix> --case=VISITOR-SEAT-LOST`：真实到椅子的竞争与输者安全停步。
- `run_guidance_need_return.gd <json> [case...]`（6项，含饮水中拆除最后导诊台与诊室设备，真实走到安全点后才恢复原票据）与 `waiting_adoption_runner.gd <json> --case=A30 --case=A35`：生活需求返回、临床叫号、第三方移动及结构变化的实际交接。

运行方式为指定Godot的 `--headless --path <project> --script res://tests/acceptance/<runner> -- <arguments>`。流程使用原0.1秒步长，临界输入、声明占用边界和真实执行段分别记录。完整安全候选搜索、导航静态冷建及A*最坏整层访问仍是独立未消除的边界，不由入口零全序次数宣称已经解决。选例通过不表示完整回归或性能达标。

阶段核验记录见 [公共区域入口阶段报告](../../docs/reports/public-area-arrival-stage.md)。A30/A35中的两个基线前提失败单独列出，不能把该组标为全通过。
