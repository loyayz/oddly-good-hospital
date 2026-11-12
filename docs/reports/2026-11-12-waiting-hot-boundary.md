# Waiting dispatch 热史长尾边界

## 选择依据与范围
原、身体缓存后完整plain的最大步均为index2250/输出tick2884：319.280/319.587ms。此前已合格root-stage原始记录该步waiting256.752ms、整步289.788ms，邻步waiting8.574/6.636ms。该旧阶段记录没有nested调用，不能归因到某个患者、设施或路径查询，也不是本轮新分项计时。自动无意图扫座要求world tick%50==0；输出2884所对应world2883不满足，不能笼统归因为周期扫座。

实际链为Simulation→HospitalWaitingLife.dispatch（game/life/waiting_life.gd）→need/seat/clinic-wait/安全等待生命周期及其真实空间查询。只调查该确定长尾，保留连续前史形成的热缓存，不以末态恢复8步替代。所有业务、人员、命令、RNG、.1步长、4 workers与观察层1保持。

## 无插桩边界基线
HEAD `2220eb7a2f5c826aac89bb1ff7b9348b8dafe786`，生产缓存源码仍1e5bb6e。前一完整包已从2c06e5d实际下载核验后才执行本轮。原75f5e1d输入、原plain_v4、prefix仍为1000，sample仅截到1253，共2253步到2886。没有把prefix改到热点前从而移动运营命令，原命令仍在tick1633。请求app策略，Linux实际platform_default；原引擎/桥接/内容保持，新独立进程与profile。

2253连续完成记录齐全，与已完成完整plain相同前缀的index/tick/在场数/会话/移动数逐项相等。旧完整运行没有该中间点二进制，不宣称其完整World相等；本轮终态`53af4f26c2b95307ba9357c33b44b02951544b86629deb32d76735e569d1de1f`将供观察版独立核对完整World/RNG/有序事件。tick2884本轮296.258ms，前后整步67.747/44.017ms。不是waiting分项，不由三步给出验收分位数或优化收益。

进程163.366秒、exit1；截断覆盖22/31，原升级拒绝仍在tick1633。保留require-coverage及失败结果，明确诊断截断，不是完整性能资格窗；没有降低门槛。结束封包并停止，实际持久读回后才允许同边界观察版。

[原始plain包](evidence/2026-11-12-waiting-hot-boundary/plain.zip) 804876字节、24成员，SHA256 `a5f482d04e0ad9ac1bf73901ec4696d127a49f16fb55145bd3a5bcac36901650`；[逐成员manifest](evidence/2026-11-12-waiting-hot-boundary/plain.members.json)和[前缀对比](evidence/2026-11-12-waiting-hot-boundary/plain.comparison.json)。本地CRC/成员长度/SHA均通过。包为既有合成游戏benchmark的运行事实、输入/终态及工程诊断，不含真实患者材料或账号凭据。此前所有原始包保留。

## 同热史限定观察与已证触发

plain包已从3c3da32实际下载核验24成员后，运行唯一观察版。隔离副本4文件32个wrapper，原函数体/参数默认值/早返通过机械逆变换逐字验证；原返回只执行一次。仅world2881..2885的waiting根启用；窗口外直通但仍有轻量wrapper开销。两次parse-only均通过，第二次只是执行前补短坐标数组摘要，旧helper/manifest与parser日志保留。没有额外业务查询或World快照。

实际2253步的完整World/RNG/有序事件、business/prefix/sample/errors以及逐步非计时状态与plain相等，final仍53af4f26…de1f。1238调用记录、5根span和parent/stack/计时算式通过。进程164.569秒，仍覆盖22/31与exit1，未宣称性能验收通过。

输出2884的waiting raw297.909ms，已测后代handler37.140ms，扣除后估计260.769ms。57次_start_fallback的exclusive共223.735ms；其中真实患者0003/0026/0011/0012/0027/0059这6条调用占222.908ms。六人的如厕need原started_tick=2433，seek_seconds=45，因此同在world2883到期；实际phase从area_travel转fallback_travel，当前safe_wait=false、current_area为空，随后真实安全点移动请求返回空错误串。没有把意图当成实际到达。邻近4步fallback调用均0，waiting扣已测handler后的估计为9.020/8.644/8.729/8.087ms。

这是生活期限同刻到期后的安全撤离，不是周期扫座。尚未给floor_waiting_point、room_use.public_point、can_reach、toilets.leave单独计时；它们在未包裹残差中。源码虽在floor_waiting_point完整枚举拥有公共地块并按当前身体origin距离/y/x排序，然后safe_wait/can_reach，但不能把222.908ms直接全算作排序或A*。下一界限是这些内部真实工作，而不是修改期限、分散提交或降低安全规则。

计时exclusive=body_raw−直接child已测wrapper，仅用于本次观测分区，不是净生产CPU。门控、传播/返回等未测观察开销仍在残差。5次root flush分别20.131/18.085/33.838/18.404/17.219ms，全部留在真实outer step内，不能删除长帧或直接用该观察版做性能比较；inclusive不可相加。

[观察原始包](evidence/2026-11-12-waiting-hot-boundary/observer.zip) 1562701字节、56成员，SHA256 `f83106189f981ba8f23c165cdd7c367a268a73bc5abfd39632f4c97148846df3`；[成员清单](evidence/2026-11-12-waiting-hot-boundary/observer.members.json)、[资格对比](evidence/2026-11-12-waiting-hot-boundary/observer.comparison.json)、[5根span与6owner分析](evidence/2026-11-12-waiting-hot-boundary/observer.analysis.json)。本地CRC/每成员字节及SHA核验通过。所有实际trace、源变换、helper、准备/校验控制器、parser输出与进程身份均保留；overlay已还原并停止，没有生产修改、第二次重放或全窗重复。
