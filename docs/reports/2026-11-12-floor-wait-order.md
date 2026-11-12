# 公共安全点排序：固定真实语料的隔离候选

## 依据与约束
[已合格热史细分](2026-11-12-waiting-hot-boundary.md)中的6次真实安全点查询，原完整公共枚举95.110ms、原sort_custom116.190ms；这些是含已明确采集扰动的诊断span，不是候选收益。其完整输入包已从03bcb4e实际下载核验后才运行本批。该候选尚未进入生产；实际生产仍1e5bb6e。

候选仅对已完整取得的点序列排序：每点仍用原Vector2.distance_squared_to，存为Vector3(distance,y,x)，使用Godot已有Array.sort原生比较后原样写回Vector2i。不改变完整候选、距离算术、y/x平局或safe_wait/can_reach；不新增缓存、库或native API，不改变期限和真实移动。

Godot4.7.2固定源码中Array.sort→Variant::OP_LESS→Vector3::<按x/y/z精确字典序，没有epsilon。Vector2距离返回与Vector3分量同为real_t，因此保存原距离函数结果不引入额外有限值精度；实际公共候选被room_use.public_point限制为0..95，y/x可精确还原。这不是泛用超大整数或NaN排序保证；没有把数值边界测试冒称合法医院输入。

## 固定计划与测量边界
6份实际points_before/origin/points_after，每份6组AB/BA交替，每arm20次，共36对、1440次排序，未按结果追加。每case另有各1次untimed完整资格/warmup。双方输入duplicate与严格全序检查都在计时外；计时包含完整排序函数返回，候选装饰、原生排序、还原、显式clear和局部生命周期均包含。完整payload/源文件不变，不创建WorldState或Simulation，不测枚举、安全、可达或实际移动。

15个额外纯正确性用例包括空/单/重复、整数与半格、binary32近等距、y/x字面平局、地块边界和正负1e12数值origin。全部通过；1440次输出均严格等于原捕获完整点顺序，6份完整事实和文件字节未改。parser通过、无修改；进程18.705秒、exit0并回收。

|720次/arm|原sort_custom|候选完整排序函数|
|---|---:|---:|
|总计|14.652447s|2.020679s|
|单次中位|19.8975ms|2.699ms|

36/36对候选更快，排序局部总计减少86.21%。这是本固定语料的纯排序结果，**不是整步或完整窗口收益**；95.110ms枚举、其他业务、以及采集残差都不在该降幅内。生产整合和真实安全撤离尚未验证，原全窗门槛与覆盖仍失败。

## 原始证据
[固定原始包](evidence/2026-11-12-floor-wait-order/micro.zip) 1460882字节、29成员，SHA256 `4969ba559b22e99628a7b5f8eceea4ba95fc93c4b9a6e92ff916f7f74ba4056a`；[member manifest](evidence/2026-11-12-floor-wait-order/micro.members.json)、[36对total/median分析](evidence/2026-11-12-floor-wait-order/micro.analysis.json)。保留1440次原始微秒、15边界、完整6语料、固定plan、原/候选脚本、引擎/host/命令及parser/进程信息。本地CRC/逐成员验证通过，未删除旧包，未修改生产。候选order.gd SHA256 `505f0195f896d086db4481beb17991b00868e652fee759b853851d9768ff3ead`。
