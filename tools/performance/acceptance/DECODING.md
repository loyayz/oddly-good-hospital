# DxgKrnl 离线解码

`decode-raw-etl.ps1`读取已经结束的ETL，不创建session、不启用provider，也不启动游戏。输入使用该场次保存的`provider-schema.json`；保留原文件及哈希，不能换用另一台机器或Windows版本的模板。`decode-dxgkrnl.ps1`继续提供Get-WinEvent/TDH转换结果及可选XML旁证，其SystemTime不是原始QPC，不能据此伪造窗口归属。

## 命令

在仓库根目录的PowerShell 7 x64中运行，每次使用新的输出路径和fresh pwsh进程：

```powershell
pwsh -NoProfile -File tools/performance/acceptance/self-check-raw-etl.ps1
pwsh -NoProfile -File tools/performance/acceptance/decode-raw-etl.ps1 -Etl '<场次>/allocation/dxgkrnl.etl' -Schema '<场次>/allocation/provider-schema.json' -Output '<新目录>/raw-events.ndjson'
```

大型trace可只展开需要的事件ID，减少JSON体积；C#仍读完该ETL并保留所有DxgKrnl回调的原序号，筛选不会重编号：

```powershell
pwsh -NoProfile -File tools/performance/acceptance/decode-raw-etl.ps1 -Etl '<场次>/allocation/dxgkrnl.etl' -Schema '<场次>/allocation/provider-schema.json' -EventIds '27,28,29,33,34,35,36,37,38,39,78,110,320,321,367,371,373,374' -Output '<新目录>/allocation-events.ndjson'
```

EventIds为逗号分隔的十进制ID字符串；缺省时输出所有DxgKrnl记录。输出目录必须已存在，NDJSON及`.meta.json`均不可覆盖。自检只编译C#和处理合成字节；可用`-Output '<新文件>.json'`保存自检结果，默认不向工具目录写文件。

## 时钟、来源与字段

reader使用`OpenTraceW`和`ProcessTrace(EVENT_RECORD|RAW_TIMESTAMP)`，保留原`EVENT_HEADER.TimeStamp`，不经过SystemTime转换。只有TraceHeader.ReservedFlags=1且PerfFreq>0时，`qpc_ticks`才等于该原整数，`clock_domain=windows_qpc`；其他时钟保留`raw_timestamp`，但QPC字段为null。PerfFreq来自原ETL文件头，不用本次解码机器的Stopwatch频率替换。FILETIME格式的StartTime/EndTime仍单列，不能改名QPC。[EVENT_TRACE_LOGFILEW](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/ns-evntrace-event_trace_logfilew)、[TRACE_LOGFILE_HEADER](https://learn.microsoft.com/en-us/windows/win32/api/evntrace/ns-evntrace-trace_logfile_header)

每条输出保留Provider GUID、ID、Version、Task、Opcode、PID/TID、Flags、原UserData base64及处理序号。header_pid与payload中的hProcessId含义不同，解码器不推断资源所有者。整数和handle的data值为精确十进制/十六进制字符串；raw_timestamp/qpc_ticks为JSON整数，读取端必须保留64位精度，不能经double往返。

schema以精确ID+Version匹配，已知Task/Opcode必须一致。字段按ETW packed顺序读取，不套C结构对齐；指针优先使用事件32/64位标记，无标记时才使用文件头PointerSize，矛盾标记失败。支持固定整数、HexInt32/64、Pointer、4-byte Boolean、GUID、Float/Double、固定长度Binary和有界NUL终止UTF16。110:v1的ConfigSpace使用前置UInt32字段给定长度的UInt8数组，保留为base64，data_fields另含count、count_from、encoding与原offset/bytes。数组长度受原USHORT payload长度约束，不根据PCI猜字段或跳过字节。

重复或匿名字段名、未知类型、其他动态数组/结构、截断、尾随字节和descriptor不符均标`decode_status=incomplete`。完整raw payload继续保留；data清空，data_fields中的已读前缀仅供诊断，不能作为完整成功输入。

`.meta.json`保留原ETL、provider-schema、C# reader、PS wrapper和输出哈希，读取前后核对ETL/schema/C#来源稳定；另含文件头、API返回码、原始时钟判断、读取/筛选/解码计数与各类失败。`sequence`始终是包含被过滤记录在内的全部DxgKrnl记录的1起始序号。`FirstRawTimestamp/LastRawTimestamp`覆盖整个provider读取范围，不是筛选结果的测量窗口；过滤条件另列selected_event_ids。

## 失败与结论

- exit0 / status=decoded：文件处理完成、QPC文件头有效、文件已结束、文件loss为0、CloseTrace成功、至少输出一条记录，且全部**输出**记录完整解码。带EventIds时只证明选择的记录可解码，不证明其他ID不存在或全部事件可解码。
- exit2 / status=incomplete：未知模板/动态字段、错误时钟、文件loss、读/关闭错误、来源变化或无输出等。原始证据保留，不将未知值填0，不把partial data送入成功账目。
- 参数、schema格式或编译错误可能在创建输出前终止；缺少最终meta同样按未完成处理，不能仅凭已有NDJSON判成功。

原始QPC可与同一捕获、同boot的原生QPC联结，仍须核对该场次PID/启动身份、频率、窗口、提前armed和完整tail。27/29提供设备映射，28/39为生命周期线索；解码器仅提供原字段。33的creator、36/37的hProcessId或header_pid都不能自动替代设备所属进程；39也不能替代34释放全局bytes。实际所有权、共享去重、代次、rundown及驻留由ledger另行核对。

真实B1-r3故障trace已用该接口有界验证27/28/29/39/110共1615条全部解码，文件读取/关闭成功、clock=1、PerfFreq=10000000、文件loss为0。该场未进入正式窗口，此验证只证明解码接口，不构成图形预算或正式性能通过。最初的完整raw reader还完成了短probe与该实际ETL的全文件读取；未知事件保持incomplete。
