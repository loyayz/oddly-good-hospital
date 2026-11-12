# Waiting dispatch 热史长尾边界

## 选择依据与范围
原、身体缓存后完整plain的最大步均为index2250/输出tick2884：319.280/319.587ms。此前已合格root-stage原始记录该步waiting256.752ms、整步289.788ms，邻步waiting8.574/6.636ms。该旧阶段记录没有nested调用，不能归因到某个患者、设施或路径查询，也不是本轮新分项计时。自动无意图扫座要求world tick%50==0；输出2884所对应world2883不满足，不能笼统归因为周期扫座。

实际链为Simulation→HospitalWaitingLife.dispatch（game/life/waiting_life.gd）→need/seat/clinic-wait/安全等待生命周期及其真实空间查询。只调查该确定长尾，保留连续前史形成的热缓存，不以末态恢复8步替代。所有业务、人员、命令、RNG、.1步长、4 workers与观察层1保持。

## 无插桩边界基线
HEAD `2220eb7a2f5c826aac89bb1ff7b9348b8dafe786`，生产缓存源码仍1e5bb6e。前一完整包已从2c06e5d实际下载核验后才执行本轮。原75f5e1d输入、原plain_v4、prefix仍为1000，sample仅截到1253，共2253步到2886。没有把prefix改到热点前从而移动运营命令，原命令仍在tick1633。请求app策略，Linux实际platform_default；原引擎/桥接/内容保持，新独立进程与profile。

2253连续完成记录齐全，与已完成完整plain相同前缀的index/tick/在场数/会话/移动数逐项相等。旧完整运行没有该中间点二进制，不宣称其完整World相等；本轮终态`53af4f26c2b95307ba9357c33b44b02951544b86629deb32d76735e569d1de1f`将供观察版独立核对完整World/RNG/有序事件。tick2884本轮296.258ms，前后整步67.747/44.017ms。不是waiting分项，不由三步给出验收分位数或优化收益。

进程163.366秒、exit1；截断覆盖22/31，原升级拒绝仍在tick1633。保留require-coverage及失败结果，明确诊断截断，不是完整性能资格窗；没有降低门槛。结束封包并停止，实际持久读回后才允许同边界观察版。

[原始plain包](evidence/2026-11-12-waiting-hot-boundary/plain.zip) 804876字节、24成员，SHA256 `a5f482d04e0ad9ac1bf73901ec4696d127a49f16fb55145bd3a5bcac36901650`；[逐成员manifest](evidence/2026-11-12-waiting-hot-boundary/plain.members.json)和[前缀对比](evidence/2026-11-12-waiting-hot-boundary/plain.comparison.json)。本地CRC/成员长度/SHA均通过。包为既有合成游戏benchmark的运行事实、输入/终态及工程诊断，不含真实患者材料或账号凭据。此前所有原始包保留。
