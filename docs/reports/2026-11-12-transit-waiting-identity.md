# Transit 实体候位与召入：首轮实现和短边界验证

本文记录 stage1 原始候选与该阶段范围，不是最终非方体结论。后续共同选点修复及完整到达证据见 [stage2 报告](2026-11-12-transit-waiting-orientation.md)；stage1 原包已在 b9c6661 发布并完成逐字读回。

## 规则与交接
依据 design/11-growth-arrivals-recruitment.md §4.1，必要让位保留已真实到站的队列身份；实际公共候位才能按票召入，完整身体实际对齐入口才能登舱。A41历史助手方案不是用户业务要求。本批不改变首次远处接近、不恢复226旧票、不改变职业优先级、负载或0.1秒步长。

transit_wait仅保存原request_sequence和Transit候位cell；原票唯一拥有connector/from/to/sequence，原movement唯一拥有目标/path。实际到点及assigned推导交接，不持久化三套phase。一般waypoint默认结束该身份，仅Transit内部显式保留。非头入口组由Transit选择实际公共候位，无合法点则不强推。选头取已实际候位的组而非只取anchor-ready，selected召入使用既有Movement真实碰撞/扫掠。convoy复用既有portal approach的层内规划与完整尾部对齐，不重选全局连接或任务。

明确临时路径unreachable解除本次assigned，保票并回原候位目标走原retry预算；不把该失败缓存成原最终任务无路。动态接触/暂时无侧路不是失败，不增加超时。正式retarget/cancel、外部普通waypoint或无效原连接身份结束候位。空载已开始后取消只清引用，真实余量继续。报价对本组/前方不可估计候位步行返回unknown，后票不污染前缀。

## 选例及结果
- baseline01：221 movement ticks，合法World、身体安全、最终到达、原request/目标通过；原票2丢失，order incoming→later→leader，两项需求断言红。这是正式request_move+真实必要清退，不是超时。
- solo-final03：精确重用baseline完整preWorld（SHA c2981b2e8cdea2186a4b04d3245217d994d7ed3ea4ac69d80e1dd524056aa4a4），157 ticks，票2保留，incoming→leader→later，实际最终到达。
- convoy-final01：精确重用convoy01完整preWorld，203 ticks，完整组实际对齐/登舱/到达、票序、身体安全、World合法通过。
- 两正例均在必要清退途中、实体候位、已召入边界独立冷恢复，后续完整World持续相等；检查后票不进入本组quote前缀，查询前后完整facts/RNG不变。
- edges02：真实assigned存档恢复，正式临时waypoint API请求已有shaft结构禁入点，真实planner失败而World合法；释放assigned、保票/候位、回原候位目标、无最终goal失败缓存。此为声明的不可达临时目标，不是模拟建墙。正式request_move retarget与普通外部waypoint均取消身份。原cancel_ground_move空载例10 ticks精确到原站，无虚构乘客/磨损。
- regression01：source_boarding_solo/convoy与普通waypoint_solo/convoy四项通过。必要清退的旧A41撤票/后票先行断言不作为当前标准，也未删成绿。
- chain-exact01：发布stage8c完整preWorld，4 ticks，constructor完全等价、两级实际contact、trip清除且incoming真实落2F、保护体每步不变、真实步长/身体安全通过。
- chain-fresh02：修正默认测试输入生成，正常staff初始化发生在冻结独立preWorld之前；保留生成前原始bin，再独立构造并验证coldrestore；默认4tick全部通过。这是fixture修正，不是生产/性能输入变动。

## 原始失败与限制
- convoy01：240上限，票/恢复/安全通过但未完成；头到入口而尾折弯，普通local route只到坐标，反复零距离waypoint。改复用既有完整portal approach后convoy02及final通过。
- chain01：实际contact/释放通过但constructor_exact红；零步比对仅staff缺默认字段。失败及差异保留，未放宽断言。
- solo-final02：Array[int]/Array[float]测试比较漏记实际waiting恢复点，其余断言通过；改用Vector2实际坐标比较后final03通过。生产未因该失败改变。
- 一次convoy文本拼接工具请求因潜在尾部截断风险被拒、未执行。只读核范围后仅一次唯一上下文替换重试获准。没有绕过拒绝。
- 不承诺任意永久动态堵塞必达；局部等待点也不可达时沿原retry等待、不作为已实际候位再次选头。不声称已解决此前2083状态首次接近慢，未跑原综合长窗，升级完成尚未验证。
- 非方体selected入口完整包络代码已复核，但本批未另加不同尺寸混组新正例。结构失效覆盖真实planner边界，不声称已覆盖所有正式几何编辑。

## 可恢复原始证据
每run保存真实command、exit、wall_seconds、reaped、白名单host、实际project native SHA、当时三生产源与runner。所有原始失败不覆盖。runs.json记录实测耗时（含引擎启动，不是性能指标）。final-source保存最后版本；最后仅两条陈旧注释修正不改变执行语句。UID与此前663份逐SHA完全相等。未stage/commit/push；停止engine等待审核。
