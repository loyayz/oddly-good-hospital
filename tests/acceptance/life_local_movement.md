# 移动员工与固定使用者的局部避让

规则依据为 `docs/design/01-simulation.md` §3 及任务导航移动规格 §4。正在移动的角色没有通行优先级。真实后退遇到另一个可移动身体时，后者沿原单人地面行程检查左右、再后退；只改变临时局部意图，保留目的地、路线、请求序与业务承诺。固定岗位、坐着使用设施及同行成员保持原保护。

`_local_movable` 只读取当前实际位置、姿态及地面 Move 的所有权。安全离岗任务仍持有岗位释放义务，不能把正在履行该义务的单人地面行走判为固定岗位。一般业务繁忙判断继续保护原服务和职责，不用于否决已经存在的地面行走。

## 专项选择

| selector | 合法输入及真实交接 | 断言 |
| --- | --- | --- |
| `safe_release_collision` | 原已准备班段、远端导诊台安排；实际请求饮水，原导诊 owner 创建安全离岗与地面 Move | 实际后退碰撞使离岗者选择局部让行；选择不移动身体、不改原目标/序/路线、职责、预约及临床票；真实走出释放区域后才解锁，实际用水80步并返回原导诊台 |
| `amenity_walk` | 实际请求饮水并由生活 owner 派发设施行程 | 实际碰撞和局部让行保留原生活任务及行程，实际用水80步并返回 |
| `fixed_clinical` | 真实患者与医生走到诊桌、正式 Session 已开始 | 对受保护岗位的实际接近被拒；原身体、工作、预约保持，原诊疗正常完成并只结算一次 |
| `seated_use` | 第一名患者真实开展GP；第二名患者在合法安排队列中选公共椅，真实走到、就座、取得预约 | 固定就座身体不被选择或推动，25个实际使用步的身体、原票与预约保持；正常转诊后真实离院并释放，原GP正常结算 |
| `convoy` | 合法初始前后队列，通过正式 group request 创建原 Move | 实际后退碰撞不能单独推动成员；原组、目的地及请求序保持，完整组实际到达 |

碰撞者从已取得正式原路线的待后退临界输入开始。仅声明尚未执行的局部意图，不声明已完成移动，不伪造历史轨迹。随后每次碰撞、让行、实际离岗、设施使用、返回和同行移动都执行普通生产模拟步。只读 observer 记录真实 MotionResult 与选择结果，不替换路径、返回连接或碰撞决策。固定使用者不人为获得地面 Move；接近者初始身体必须在当前预约之外。

原专题的 `active_work`、`clinical_release`、`working_training`、`travelling_training` 等计算行仅填入最小 guard 字典，没有建立完整合法服务；它们的 `expected=false` 不能定义“有任务的移动角色不可让行”的规则。原专题还通过替换 `_local_try_return` 人为阻断生产选择。因此这些计算由上述真实业务边界替代；既有失败报告与原版本身份保留为历史证据。同目标转交清理生活 marker、同时保持移动请求的合同继续由 `movement_target_reuse.gd` 的 `optional` 选择验证。

## 执行

```powershell
godot --headless --path <共享验收工程> --script res://tests/acceptance/life_local_movement_runner.gd -- <报告.json> safe_release_collision,amenity_walk,fixed_clinical,seated_use,convoy
```

省略选择时运行五例；指定选择只构建对应必要前提。原版本先运行 `safe_release_collision`，修复后运行五例；关联回归选择 `rooms_areas_guidance` 的 `LIFE-04`、`local_only_movement.gd` 的三个真实局部场景及 `movement_target_reuse.gd` 的 `optional`。

本专项验证行为与业务交接，不构成160人性能验收。结果记录各例实际耗时、生产步数、碰撞和局部选择；中断、前提失败和工具失败分别保留，不作为通过。
