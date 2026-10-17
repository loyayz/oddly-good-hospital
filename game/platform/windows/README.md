# Windows资料库与SQLite桥接

`PlatformSessionGuard`继承`RefCounted`，由AppRoot持有并管理进程生命周期。桥接使用固定Godot 4.7.2标准版的C ABI；源码不依赖godot-cpp。构建从同一引擎生成接口头文件、内置类型尺寸和方法哈希，使用校验SHA256的Zig 0.15.2 portable生成Windows x86_64 DLL。

`PlatformSQLite`在同一DLL中静态链接SQLite 3.54.0官方amalgamation。源码包SHA256为`68e913b0fe8ec6b4e5f391c594a28872884e80d6cd042a1e50c957be46b5aa4d`，与官方SHA3-256下载记录核对。构建启用线程安全、禁用动态扩展加载及双引号字符串兼容；玩家不安装数据库程序或后台服务。源码地址与公有领域说明随包写入第三方说明。

SQLite连接取得资料库guard后才能打开，只接受规范医院UUID，固定操作实际`user://hospitals/<uuid>/hospital.sqlite3`，不接受任意文件路径。参数使用预编译绑定，整数为64位、浮点为double、世界分段为BLOB；查询结果每批至多256行，由资料层分页读取。每个连接固定于创建线程，关闭连接回滚未完成事务。世界DTO、保存点清单、业务校验及保留策略由GDScript资料层拥有；SQLite负责本地存储与事务。

```powershell
pwsh -NoProfile -File tools/build-platform-guard.ps1
```

DLL位于`game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll`，属于可重建产物。`.gdextension`声明相同的Windows调试与发行库及GMP、MPFR、libgcc、winpthreads动态依赖，Godot发行导出携带五个DLL。C++标准库静态编入桥接，MPFR经libgcc使用winpthreads；实际导入链在隔离工程加载前检查。UCRT是项目既定Windows10/11的系统组件，无需另装编译器或后台服务。[Microsoft UCRT部署说明](https://learn.microsoft.com/en-us/cpp/windows/universal-crt-deployment)。

## 精确容量与大整数

纯计算后端使用SoPlex 8.1.0、GMP 6.3.0和Boost.Multiprecision 1.92.0的GMP头文件后端。SoPlex固定提交为`a00610534e044f35aa298059eb963312336c4c9c`；GMP与Boost使用固定MSYS2 UCRT64包。构建脚本校验源码/包SHA256，使用同一Zig 0.15.2的C++17编译；不依赖godot-cpp、.NET、外部求解进程或玩家联网下载。GMP保持独立动态链接，随包保留许可证、对应源码、补丁与构建脚本。

`PlatformArrivalMath`提供批量`solve(cases,budgets)`及分数/整数运算。Godot数组与字典在调用边界转换为原生稀疏模型；求解、共享AND/OR选择图的完整精确定价及原始/对偶校验都在同一调用内完成，不逐次矩阵消元跨语言。连续LP使用精确有理数同步、零最终容差和精确校验；只有覆盖全部隐式合法组合且预算、病例比例、非负分配与原始/对偶目标一致时才返回容量。失败保留明确错误，不能当作0能力生成日计划。

`PlatformArrivalCapacity`由单个任务独占，`prepare(cases,budgets)`准备模型、已生成列及求解基；`solve(budgets)`更新预算并热启动，变化后重新证明完整可行性和最优性，输入未变时复用已验证结果。该接口只返回容量、瓶颈和模型计数，不为医院创建假想Visit分配对象；完整分配接口仍由静态`solve`提供。对象析构释放这些可重建资源，不保存进医院快照，不持有医院事实、随机流或资源承诺。并发任务不同时操作同一实例。

仅预算右端项变化时，使用SoPlex提供的精确求解基及逆列计算新基本解。所有基本变量非负、实际病例比例与资源约束成立，且新原始目标等于仍覆盖全部隐式资源选择的旧对偶界时，直接接受已证明的新最优值；任一条件不成立则回到SoPlex精确求解与完整定价。复用不执行自研矩阵消元，不以预算比例近似容量。

存在护理覆盖时，容量投影使用SCIP精确混合整数流模型。同一隐式AND/OR资源图保留全部合法选择，病例根流严格按原概率分配；岗位二元变量约束同一护士只覆盖一个病房，覆盖岗位与其他主动工作互斥，原自身护理仍使用同一份实际工时预算。流量上界由全部资源预算及完整资源束的最小总需求精确推导，不设置任意候选或Visit上限。返回前复核原始有理数约束、变量边界与岗位整数性；没有护理岗位的模型继续使用SoPlex路径。该容量最大值与下面的结构K分别求得。

结构规模使用SCIP 10.1.0精确整数模式，依赖启用GMP、MPFR和精确SoPlex接口。`structure(cases,blocked,reception,bed_limit)`对完整初诊/终点组合建立二元配置，约束主动操作者和设施互异、每名覆盖护士只服务一个实际病房、同房最多8床以及接待配对上限。相同资源而覆盖者或病房不同的组合分别保留。仅在精确最优状态及原约束的整数解复核通过后返回K；错误不能返回假零值。医院模型提供真实资格、开放状态和组合，SCIP不定义业务规则。

GMP从十进制字符串赋值后显式约分；返回分数始终为互素分子/正分母，0为0/1。整数除法取向0截断，非负divmod、负分数floor/ceil及原随机拒绝采样语义由既有适配接口保持。真实岗位、班次、PlanScore、已有负荷、护士互斥与K的业务规则仍由医院模型拥有，数值库不替代这些规则。

依赖来源和全部许可证见`tools/windows/THIRD-PARTY-NOTICES.txt`；构建生成的独立许可文本与GMP对应源码位于`bin/licenses`，正式构建复制到发行目录的`licenses`。源码/头文件及构建中间对象不进入游戏资源包。构建和数学/功能验证不构成完整模拟步或画面性能通过证据。

## 接口

| 方法 | 返回 | 责任 |
| --- | --- | --- |
| `acquire()` | `{ok: bool, busy: bool, error: int, message: String}` | 固定读取`OS.get_user_data_dir()`，创建实际资料库根目录并以不可继承的Win32文件句柄独占`.session.guard`。已持有时重复调用返回成功。只有`ERROR_SHARING_VIOLATION`返回`busy=true`，其他错误保留Windows错误码与具体原因。 |
| `release()` | 无 | 关闭本实例实际持有的句柄，可重复调用。实例最终析构同样释放句柄。 |
| `is_held()` | `bool` | 只读查询本实例是否实际持有句柄。 |
| `get_resource_status()` | `{ok: bool, error: int, message: String, available_physical_bytes: int, available_disk_bytes: int}` | 持锁后查询实际可用物理内存与同一`user://`目录所在卷对当前调用者可用的磁盘字节。失败保留具体错误；未取得资料库时返回`ERROR_INVALID_HANDLE`。 |

桥接不接收路径，不暴露HANDLE、PID或通用文件操作，不读取医院内容，也不持有保存事实。空guard文件不会阻止获取。独占判断只依赖`CreateFileW(GENERIC_READ | GENERIC_WRITE, shareMode=0, OPEN_ALWAYS)`返回的实际句柄；异常结束由Windows释放。中文、空格和长路径使用UTF-16 Win32扩展路径处理。

AppRoot在读取玩家资料及启动产品日志前获取资料库。发行工程预先关闭`debug/file_logging/enable_file_logging`及`.pc`覆盖。退出等待全部保存、照片、清理与日志IO结束后才调用`release()`；切院不释放。桥接缺失或加载失败必须显示启动错误，不降级为文件存在检测。

所有权及生命周期操作由AppRoot主线程执行。资源查询只反映查询时刻的系统余量，不能代替世界副本、编码缓冲和实际资源峰值的保存预算核算。

## 精确JSON数值解码

同一桥接另登记抽象静态类`PlatformJsonNumbers`。`decode_decimal(source: String)`返回`{ok, value}`或具体错误，最多接受128字节有限数值标量。世界JSON解析器先检查JSON语法，再调用Windows系统UCRT的`_strtod_l`；私有C数值locale只用于十进制解码，不改变进程或系统locale，不接受资料库路径，也不读取世界文件。整数溢出由JSON解析器拒绝，随机种子和状态仍按原规则使用64位十进制字符串。

Godot 4.7.2内置JSON解码的实际对照曾把`99.52000000000027`改变一个最低有效位。当前解码读回的64位字节完全一致，所有代表中途保存及恢复对照通过。该适配维持标准JSON快照格式；资料库占用和数值转换分别由两个类拥有。

当前SQLite桥接DLL的实际字节数与SHA256由[第一阶段验收数据](../../../docs/data/stage01-feasibility.json)的`build.files`记录，与`.build/windows/build-identity.json`及随包文件核对。本版本完整导入、编译、双进程error32、数据库/日志占用及提交前后强制结束后的恢复，以及实际发行包随包加载均有对应[第一阶段报告](../../../docs/design/13-stage01-feasibility.md)。

## 原生验收记录

Godot `4.7.2.stable.official.ed1daf0bf`、Zig `0.15.2`、Windows11 x64普通权限下的独立验收资料库使用中文及空格目录。下表是数值解码加入前的guard基线：DLL为28,160字节，SHA256为`279fbf9746b88bfb21ee636e3e0f43efb145c78d2a88db46981cd66c813322ea`。当前版本追加的实际验收范围见上文；原guard的句柄、错误分类和生命周期代码保持原实现。

| 范围 | 实际结果 | 原始证据 |
| --- | --- | --- |
| 编译及ABI | 对应引擎生成接口，严格警告编译成功，PE为x86_64且导出唯一初始化入口 | `.cache/validation/stage01-platform-build.log`、`stage01-platform-pe.json` |
| 正常生命周期 | 重复获取成功，另一实例实际竞争失败，正常释放后重新获取，未持锁资源查询失败，资源余量查询成功 | `.cache/validation/stage01-platform-runtime-diagnostic.log` |
| 双进程及强制结束 | 第二进程实际返回error32/busy；强制结束持锁者后新进程成功，原空guard文件保留 | `.cache/validation/stage01-platform-lifecycle.json`及同名场景日志 |
| 实例析构 | 最后一个RefCounted引用释放后另一实例成功获取 | `.cache/validation/stage01-platform-free.log` |
| 具体平台错误 | 独立guard文件设为只读时返回error5/busy=false | `.cache/validation/stage01-platform-access-denied.log` |
| 动态接口调用 | `Object.call()`与带类型GDScript调用均返回正确事实，动态释放后只读状态为false | `.cache/validation/stage01-platform-dynamic.log` |

上述验证使用真实Win32句柄和Godot原生扩展；headless不构成GPU表现证据。资料库与产品医院分开，未读取产品医院、玩家设置或启用产品日志。

### 编辑器冷启动与提前退出

Godot 4.7.2的全新工程首次发现扩展后立即退出会触发已确认的[编辑器扩展文档生成竞态#111048](https://github.com/godotengine/godot/issues/111048)。本机使用相同512个Resource、没有脚本及任何guard实例的独立冷工程对照取得以下结果；固定帧数延后没有修复此边界。

| 对照 | 退出码 | 证据 |
| --- | --- | --- |
| 当前桥接，`--quit-after 1`和12 | 两者均为`-1073741819` | `.cache/validation/stage01-cancellation-controls.json` |
| 无扩展，同样1帧和12帧及扫描取消 | 两者均为0 | 同一对照记录 |
| 扩展只注册空RefCounted类，不注册方法 | `-1073741819` | `.cache/validation/stage01-registration-controls.json` |
| 同一扩展初始化但不注册类 | 0 | 同一注册对照记录 |
| 当前桥接，`--headless --editor --import`完成扫描后退出 | 0 | `.cache/validation/stage01-platform-complete-import.json` |

诊断库的回调轨迹只进入初始化、类及方法注册，没有调用实例create/free、业务method或任何deinitialize回调。Windows异常发生在引擎本体偏移`0x53fd042`，实际访问地址为`0x8`；记录位于`.cache/validation/stage01-cancellation-exception.log`。没有引擎调试符号，栈内函数名不作为本机直接测得事实。

固定引擎提交`ed1daf0bf`的源路径与已确认问题吻合：[文档线程将扩展文档生成放入延迟队列](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp#L3041)，[生成函数直接使用doc](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp#L3083)，[EditorNode析构释放文档](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/editor_node.cpp#L9640)，[cleanup_doc将doc设为空](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp#L3365)。上述本机对照、异常地址和源路径支持将其归于同一引擎文档竞态。扩展注册时的[PropertyInfo深复制](https://github.com/godotengine/godot/blob/ed1daf0bf/core/extension/gdextension.cpp#L195)与[已初始化的返回值](https://github.com/godotengine/godot/blob/ed1daf0bf/core/extension/gdextension.cpp#L108)符合当前C ABI处理，没有用修改Variant生命周期掩盖故障。

将`is_exposed`设为false能跳过编辑器文档，但实际运行的`ClassDB.can_instantiate("PlatformSessionGuard")`变为false，`ClassDB.instantiate`返回null并报告“isn't exposed”；这违反固定桥接入口。[ClassDB暴露检查](https://github.com/godotengine/godot/blob/ed1daf0bf/core/object/class_db.cpp#L595)及实际反例位于`.cache/validation/stage01-hidden-class-control.json`。生产类保持`is_exposed=1`，C源码、DLL及运行接口不因编辑器诊断改变。

开发导入使用完整扫描命令并核对实际退出码。`--import`在本机独立工程已通过，已确认引擎问题仍可能受文档线程时序影响；一次通过不代表竞态已被修复。

完整游戏发行exe/pck中的随包加载、安装路径及安装/卸载生命周期继续由第一阶段整包验收验证。Windows10目标及超过260字符的完整资料库路径尚未取得独立实机证据。
