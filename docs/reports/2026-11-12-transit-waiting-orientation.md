# Transit 候位非方体朝向：stage2

## 规则与范围
真实身体、实际行走和公共安全候位仍由 design01、design11§4.1 约束。非方体的候位当前朝向不能代替召入到入口时的朝向，候位者自己到停点也会转向。仅修共同候选几何，不改变票序/真实身体/碰撞/旋转，不预约未来空间。stage1归档保持不变。

## 实际证据
initial01为合法S69旧组、同层S52后组、S49真实incoming，正式request_move。240ticks已有incoming→S69→S52运输，末段步行未完，不是死锁。
stop-body01独立合法静止S52[38,76]限制公共候选；tick1生产为S69选[37,76]，按旧facing0投影x=[37.4333,38.5667]看似不碰静止体[38.6,39.4]，实际东向停点x=[37.1667,38.8333]会重叠。tick5真实MotionResult仅protected阻挡，requested[.1599998474,0] actual0；安全碰撞阻止重叠。固定40ticks未证明永久死锁。

## 最小共同修正
_selected_entry单人候选排除合并当前实际朝向与0/90正交接近体；_stand_aside停点同样合并当前与正交朝向，覆盖后续dispatch重新规划可能改变的最后腿。只用于选点排除，第三方仍可经过，不改实际身体。该保守集合可能排除仅一种朝向能站的窄位置，不声称所有单朝向位置均可选。
最初实现预检路径末腿；审查指出正式dispatch会重算，改为正交联合后，末腿扫描冗余，最终删掉并恢复原static/dynamic/public廉价过滤后再规划。FloorNavigation邻居只有四正交，standing正反朝向同包络；不宣称任意卧姿等价。当前合法多成员必须convoy且禁旧offsets；其portal完整包络未改。helper仍依现有_move_step所有成员同facing语义计算非convoy分支。

## 验证与原始失败
final-stop01同stop-body01完整输入40ticks，选[36,77]而非已证重叠点；World/身体安全与selected朝向几何针对性检查通过。此selected例是几何资格检查，不假称原east反例发生了实际永久堵塞。
corrected-flow01同完整输入固定240ticks：S69真实到原1F[44,82]目标，S52完成运输但未完成原地面目标；reached_both仍红。获授权从完整末态独立cold恢复再至多120ticks，tail01仍红但其他全部通过；零步tail-audit01证实tick353..360每步前进，最后[48,85.96002197]，仅剩原[48,86]约.039978格，无local/待路由/阻塞。17.2格按每原路径腿ceil下界121ticks，120帽少最后落点。未把该红称新bug，也未自行追加。
final-solo01 157ticks、final-convoy01 203ticks实际目标/票序/三边界恢复/quote/安全通过，未重跑无关专题。
upgrade-parse01仅--check-only，exit0；保存run_upgrade_continuation.gd SHA3f8d8a5d4ed09e10589d78b8ca708789336c7a470f0d8f53036f9b56907dcc55。未运行升级综合窗口。

## 证据口径
旧stage2 wrapper identity.test_sha固定记录non_square测试，即waiting/parse-upgrade模式该字段不是执行脚本；真实command及source/sha256保存正确来源。tail-audit01起已修为实际executed_script/test_sha，旧记录不覆盖、不因元数据重复运行。所有host只白名单、实际project native显式hash，UID663逐SHA不变。没有stage/commit/push。

## 最终单一完整标准例
在上述40/240/120历史原始结果保留后，协调者依据真实运输阶段及逐腿离散余程批准一次400tick固定帽完整例，不是更改业务或性能门槛。full-final01从stop-body01完整preWorld恢复，输入逐字相同；362个原0.1秒movement ticks真实到达两原目标后立即停止。原request/目标每步保留、保护体每步不动、身体/扫掠/步长、World合法、实际服务顺序、选点修正、selected朝向几何和查询只读均通过。默认fresh fixture现在也包含真实protected S52，默认full帽400；本次验证明确使用原完整输入运行full流程，不声称新医院随机身份与原输入相同。原40-stop模式保留为候选定向防回退。

生产最终SHA：hospital_movement c8b025c0872fad84b71623234fb8f3bfdce9abe9f81d1f64062d7e5f4b912e78；hospital_transit 1bf9996caa46f6983b7d7e258011c0b984bb1ac16338959e8262a16080a37fc9；world_state 349e096840a646d83cafa08694eeb7b4ece56d9b2f5abb01c50332353694edeb。已无活动引擎，全部run进程reaped。最终完整例耗时见runs.json（包含引擎启动，非性能指标）。停止修改/运行，等待统一发布。

## 发布内容与下一步边界
本次包含三生产文件、选定回归与完整原始证据，原始包链接为 [waiting-orientation-stage2.zip](evidence/2026-11-12-transit-waiting-orientation/waiting-orientation-stage2.zip)。升级续接runner仅增强_phase_facts原始日志，复制完整movement与实际order worker；step、命令及业务断言未变，独立diff同目录。下一步仍是原4046完整输入单次有界续接至真实完成或7633，分别记录首次入队前接近、入队后的候位/召入、到工位及真实工作，不因本批短例通过宣称升级完成，也不恢复性能优化。
