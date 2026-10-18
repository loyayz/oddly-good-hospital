# 完整窗口离线判定

`analyze.py <capture-directory>`读取同一运行的capture/scenario、PresentMon CSV、真实步骤/时钟/播放状态和OS内存记录，从docs/data/balance.json读取阈值及最低样本。一个运行只判一个工况，不提供跨人数/速度/窗口/比例或密集段混池入口。

## 帧与完整步

帧样本是相邻不同游戏帧的完整显示间隔，按原始起点是否处于窗口选择；尾部跨终点仍保留完整间隔。Dropped=1表示该提交未显示，不能当0毫秒帧，也不直接等同ETW丢失。重复显示终点不产生新样本。缺字段、PID不符、显示链断裂、缺完整尾部或ETW事件/缓冲丢失都不通过。

标准CSV不公开PresentMon内部lost-present计数时记录null和工具能力边界，不虚构0，也不把这个不可取得字段设为永久阻断。已有内部loss诊断非零仍失败；可选presentmon-diagnostics.json须关联同一PresentMon SHA256及带path/SHA256的原证据。ETW loss、未显示提交和内部分析loss分栏，不能互相代替。

步骤保留 started_engine_us、completed_engine_us、elapsed_us、main_elapsed_us、between_slices_wall_us和hospital_session。总现实耗时必须等于原完成时间减原开始时间；main为原执行片段的墙钟和，单列而不冒充OS CPU。完整步按原开始落窗选择，继续保留其完整elapsed；不把切片当步骤，也不从准备等待中扣除现实时间。

clock_sample实际执行native QPC→engine_us→native QPC。对历史engine端点，只用前一个样本QPC-before作为下界、后一个QPC-after作为上界；完成通知QPC可收紧完成时刻上界，不允许倒推精确开始时间。没有拟合共同rate、零漂移或中点。

夹界完整位于窗口内的样本是definite；可能跨边界的是optional。分位使用ceil(p*N)最近秩；最小值/最大值来自同一完整总体。对optional的所有可能归属，分别求各分位与最大值的上下界：固定选k条时，最大分位取k条最高optional、最小取k条最低optional，再枚举k。只有最少definite样本达到原最低量、最坏上界仍在阈值内才通过。明确违反下界则失败；其余保留boundary_uncertain/insufficient_samples，不能挑掉长边界样本。报告基础分位和metric_lower/metric_upper同时保留，判定使用完整界。

## 真实速度与暂停

速度分子是相同窗口内原完整完成步数量×0.1模拟秒，不跨医院session相减tick；逐session校验连续tick。原完成端点夹界得到确定/可能完成数，现实分母按相同窗口及选择速度积分，输出ratio_lower/ratio_upper。只有保守下界≥99%才通过；即使乐观上界仍<99%则失败，其他情况保留不确定。

仅玩家主动暂停和focus暂停可从经营分母剔除；普通保存/后台计算/未知自动停顿不剔除。暂停请求发生在已开始步骤中时，暂停边界推迟至该原步骤实际完成，准备等待继续收费。播放状态来自原同步signal；500ms heartbeat不替代状态变更。暂停时间的高帧率不能凑经营样本，帧侧使用相同暂停夹界分类。

密集模式的每个原dense_segment分别对帧、完整步和速度判定，最低量同原balance，长尾仍保留。每回调的实际frustum binding计数及90%阈值逐段核对；普通段不混入。该计数尚不能证明raster可见密度，最终可见性证据缺失时密集场景保持缺项。

## 资源与范围

OS窗口观测工作集/私有提交、实际轮询间隔、进程生命周期内核峰值分别报告。窗口后同PID的内核生命周期峰值覆盖窗口内的瞬时工作集/提交峰值，能提供上界；它不能改名为窗口局部精确峰值。生命周期峰值超目标而窗口轮询未超时，需定位峰值归属，不能直接说该窗口失败或忽略它。

图形证据不会由PID总计或payload推导。`allocation-ledger.json`的schema2区分已观测身份、完整资格、正式窗口和OS内存视图。`gpu-ledger.py`只有在原始来源、完整rawQPC、目标生命周期、全进程别名事件族、保存的schema、实际Present窗口、全部目标大小、无身份缺口、无歧义backing及未释放分配保留均成立时，才给出全局分配extent的保守上界资格。目标adapter上缺少目标alias/backing关联的PID0/PID4/未知来源global单列为未归属kernel范围，不能默认成本为0；其完整extent峰上界与目标图峰上界相加作为更保守的backend界。任一未知大小或边界缺失继续incomplete。未知flag不用于排除分配，页表同样计入；同一adapter/global/lifetime的进程/设备别名只算一次，其他global之间的物理页不声称互不重叠。该上界≤预算可证明资源在目标内；上界超过预算不能据此断言精确物理驻留超标。物理驻留值继续为null，不把分配、backing、commitment、usage、工作集相加。

`analyze.py`重新核对原ETL、decode/schema/capture哈希、进程启动身份、QPC及全部资格字段，并要求每个目标adapter/physical-adapter内存域都有同窗口连续usage视图。该OS视图按LUID、physical-adapter、memory-segment-group报告，跨GPU engine node统计，不冒充逐engine-node物理驻留。仅有commitment或另一个适配器的usage不满足该条件。旧场次没有正式窗口时继续incomplete，已知序列峰值不参与512MiB结论。

已有ETL通过[原始事件解码器](DECODING.md)读取真实Header.TimeStamp和PerfFreq，Get-WinEvent的SystemTime继续只作旁证。解码成功只证明所选记录可读取；未知模板、动态布局或文件丢失保留incomplete，不推导资源验收。所有者与共享分配仍按同场设备/全局allocation生命周期联结。

input-preview的callback完成与真实呈现、保存begin_world包围时间与纯DTO复制、切院主线程包围时间与完整载入分别保留。未取得正确最终画面的输入关联或纯复制计时，不能用较小的其他指标代替。对应操作的真实回执/不变量由运行器保存，报告只接受本工况已完成的操作证据。

## 结论与退出码

- status=failed / exit1：有明确阈值、身份、完整性或运行错误，历史失败保留。
- status=incomplete / exit2：样本不足、尾部/时钟/操作/资源等证据不足，tool_error也按未完成。
- status=passed / exit0：本运行实际承担的全部条件完成；不代表全部7组、安装、保存恢复、大世界或两小时矩阵通过。
- timing_pass单列帧/完整步/速度和采集完整性；formal_pass由实际errors/missing计算，不再硬编码false。图形资源缺项仍会阻止formal_pass。

首160完整场景的成功也不能代替临床中途、真实64/128MiB、源/候选/副本重叠、宽层/高层、密集画面、最大房间输入或长期运行证据。完整阶段验收仍由总矩阵逐项闭合。
