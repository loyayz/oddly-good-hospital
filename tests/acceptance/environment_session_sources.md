# 环境临床会话来源专项

## 需求与范围

依据 `docs/design/08-hospital-life.md` §4、`docs/design/07-clinical-team.md` §8、§14 及内容中的环境规则。优化只改变来源获取与观察边界的派生索引，不改变噪声、临床承诺、费用、工时、暂停或移动。

- 只有 M09、M37、M17、EQ01 的 outpatient/surgery/operate 会话，设备未 failed 时产生 10 分机器噪声。
- 噪声从设备实际 footprint 出发，沿真实可传播格边至四步。wake、care、gp 及其他设备不产生机器噪声。
- 全局暂停仍显示已有噪声；正在工作但 pending_failure 的设备不提前消音。
- 正式临床插入/删除维护所有 session 成员，包括不发噪声的成员。正常查询不重新枚举 session，也不重新逐机器格计算观察 bounds。
- 存档、同数量集合替换、跨世界重新绑定必须正确冷建；failed 等可变值在局部查询时读取。
- identity/count 不是任意原始改写探测器。同ID的来源位置或kind改写，以及未观察到空集合的等数量原地删除新增，仍须发布所有者通知或替换集合。若查询已经观察到权威空集合，则会丢弃过期的非空来源。

本专项检查五处实际所有者交接：`_start`、`_complete_service`、`_pause_bed_sessions`、`suspend_outpatient`、`_dispatch_suspended`。分段前提使用现有临床 fixture，不扩展至全量临床、导诊或移动专题。

## 选择用例

| 编号 | 执行边界与独立断言 |
| --- | --- |
| ENV-SESSION-CLINICAL | OPS18 合法已诊断未治疗输入，先暖空索引，再实际导诊、走路、到场及开工；噪声 0→10，正式全局暂停事实不变，pending_failure 仍10；继续全部剩余299个实际工作 tick 完成后0，无来源重建。 |
| ENV-SESSION-RESUME | 从完整合法开工事实复制，加不阻塞既有岗位的同类备用房间；正式 remodel_prepare、安全暂停及实际撤离后，原 session ID/Attempt 到另一台 M37 真实到场恢复。记录最大移动步长、噪声消失和重新出现、索引构建数不变。 |
| ENV-SESSION-SURGERY | gp_started、surgery_started、ward_care 分段状态；明确声明最后工作 tick 为输入，正式 advance 完成服务；手术删除和 wake 插入发生在同一 tick、集合大小不变但噪声10→0。GP/care不发噪声且删除仍准确计数；调用病床暂停所有者检查 care 成员删除。 |
| ENV-SESSION-INDEX | 原始来源计算边界：四种指定设备×六种kind、非指定设备、同设施双成员、排除成员增删、同ID替换、failed/repair/pending实时（含同scope）、footprint第四/第五步、最后来源清空、64位格key与保守bounds。不是合法临床过程或吞吐样例。 |
| ENV-SESSION-LAYOUT | 原始运行session配合真实 S59 reserve_facility 通知。FF03/FF04 的正式规则保持机器底座尺寸，不把身体或岗位误当噪声底座。另以显式原始3×3适配输入检查局部footprint更新和外沿四步。 |
| ENV-SESSION-FLOORS | 原始1/2/40/400层来源，只请求1层时floor_checks只+1且只产生1层bounds；同scope重复无需工作，请求2层仅+1，先前只读快照保持不变。不是合法400层医院。 |
| ENV-SESSION-EMPTY | 非空暖来源直接raw清空，观察权威空集合后必须丢弃旧索引；同数量新ID在另一设备冷建，原位置不残留。正常通知清空后保留暖owner，20次空观察不访问sources，下一次正式写入无需冷建。 |
| ENV-SESSION-RESTORE | 同数量session集合替换、正式流式JSON encode/decode、全事实相等、恢复服务冷绑定、同数值身份的不同world、异世界读取不污染父scope、同world完整facts替换。 |
| ENV-SESSION-WORKERS | 同一真实门诊事实，failed false/true/false；真实线程池分别运行1/4个SampleJob，再经正式consume完成水等串行权限。与串行sample及独立raw完整字段一致，事实和随机流只读、只借用来源、不自建索引。另对真实visit执行生产batch.prepare→consume；仅一个visit时请求4任务按生产规则缩为1，单独如实记录。 |
| ENV-SESSION-MEASURE | 20条发噪声及60条排除session的原始固定查询输入；1000次暖查询，session visits/builds/layout updates均不增加，每次只检查所请求楼层。耗时只作固定操作诊断，不能称为临床吞吐或游戏帧率。 |

`environment_direct_reference.gd` 是逐条当前事实的原始观察路径；完整解释记录只忽略无业务承诺的排列顺序，不省略字段、数值、来源记录、噪声或只读检查。

## 运行与证据

在已完成资源导入及相同原生库准备的隔离工程中运行。必须显式列出用例，不默认执行全部专题：

```sh
godot --headless --path . \
  --script res://tests/acceptance/environment_session_sources_runner.gd -- \
  /path/to/evidence/session-results.json \
  ENV-SESSION-CLINICAL ENV-SESSION-RESUME ENV-SESSION-SURGERY
```

计算、恢复和线程用例可独立选择。新进程选择需要真实门诊输入的用例时只生成一次，后续用例各自复制完整事实并正式绑定服务。临床分段前提仅按所选边界准备，同批复用现有 checkpoint 内存缓存；没有保存运行时服务缓存。

运行器以输出JSON所在目录作为可选证据目录；首次生成真实开工状态时，可导出 `real-outpatient-started.bin`（Godot `var_to_bytes`，只含完整事实），已有同名文件不覆盖。不同实现的性能对照必须固定同一文件字节、验证完整世界并记录哈希；前提生成不计入查询计时。

每例输出 `ok/checks/elapsed_us` 与相关计数、原始对照或线程号；总 `ok` 要求全部所选用例有结果并通过。完整一批通过还必须核对实际进程退出0及日志无脚本/引擎ERROR。中断、缺少结果、环境准备错误不是通过。

若某独立用例已完整通过且无脚本错误、相关实现与输入未变化，可以依 `AGENTS.md` 只复用该项证据，不能把它所在的失败整批称为通过。例如 `boundary-v2` 的 LAYOUT、MEASURE 各项通过可复用；该批因旧 RESUME 前提失败而退出1，整批仍不算通过。RESUME 以修正后 `owner-final` 的通过结果替代。

初轮错误分为测试前提和工具：机器FF03实际不扩底座、旧式floor输入没有canonical bounds字段、worker原始返回需consume、备用房间不能挡既有导诊岗位，以及XDG资料目录须处于隔离可写目录。修正后只复跑受影响的选例。专项通过不代表完整临床、完整移动、发行回归或性能收益；性能需另做固定输入独立进程对照。
