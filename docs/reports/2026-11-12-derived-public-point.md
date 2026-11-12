# 派生空层公共点产权修复

## 变更前规则与交接
- design/04 第157行：实完连续高度授予产权，FloorState 仅保存布局差异；空层拓扑按需派生。stage25-stage28 第27行：最多九条高度，不生成逐层格/对象/任务。floor_service._complete 更新高度并 invalidate_geometry。
- 本批只修 HospitalRoomUse._plots 查询索引，首次 public_point 访问该层时使用既有 floor_plots；不补 override、不写 World、不更改排序或安全/到场/80 tick 契约。沿用 weak World、facts 实例和 geometry_revision 失效。
- 选例：合法无 override 完工层全 1024 点与实际 safe/reach；未完层/未购相邻 plot/越界拒绝；同服务高度变化并真实 geometry invalidation、facts 替换、World 恢复；已有 override 公共/私有房间；高层只派生查询层；既有 STAFF-74 门/连接安全撤离、存取恢复与真实 0.1s 步进/80 tick。公共点直接消费者只验证许可/拒绝边界，不扩临床/导航全主题。
- 完工高度在纯查询合法边界输入中声明，不将此作为施工实际完成证据；实际移动另由流程选例执行。保存本轮完整 preWorld 原始 bin。前次 derived03 无原始 bin，不追补冒称。
- 不运行微测/历史/完整性能窗，不修改 waypoint 独立边界（其后按现行规格第150行核验为独立缺陷，留待另批修复）。

## 结果
- 生产仅 room_use.gd：去掉按 override 预建产权；public_point 在坐标界内首次访问层时懒派生。weak World / facts identity / geometry_revision 原失效条件与清理不变。无 World 写入，无新增 override，无中间层展开，排序源码未变。
- 原实现 baseline-query01 exit 1：合法层 validation 空、产权 [[1,2]]，实际 0 点；保留完整日志/断言失败和该次 preWorld。补丁 query01 exit 0：完整 1024、真实 safe→reach 均成功，返回 floor2 [38,90]；原/新排序全序和有序短路调用一致，完整 World/RNG 不变。当前修复改变产权过滤，不要求旧错误实现输出相等。
- 查询边界通过：未完层3/层0、相邻未购地块、负坐标/96边界拒绝；负缓存后高度更新并调用生产 invalidate_geometry 可见新层；facts 实例替换和恢复新 World 都失效。高度1,000,000合法，_plots仅键1000000，无补override/中间层。输入高度是合法边界声明，不是施工完工流程证据。
- 实际直接消费者：clinical_development._public_idle_point 在实完空层返回 here；guidance.return_target_valid 允许本层已购点，拒绝相邻未购点/不同层/越界，完整事实不变。未扩跑临床导航专题。
- rooms01：已有 override 中 toilet→doctor_office→rest 公共候选1024→904→1024，合法输入、完整排序/实际安全可达调用、只读性通过。
- flow01：复用正式 STAFF-74 门与连接入口两变体，原需求过期安全撤离、实际 .1s 空间推进、安全到达后才开始80 tick、保存恢复身份/原时钟、真实80 tick完成效果全通过；floor_waiting_point调用2次。此流程在已有 override 地面验证公共消费者交接，**不是在派生层上实际施工或上下楼的证明**；派生层本身由独立合法 query/实际 safe/reach 验证。未修/未运行独立 waypoint 边界，已另核规格第150行允许任一合法安全占地结束本任务移动，不要求设施区域成员，待下一独立修复。
- parse01/parse02 和 git diff --check 通过。没有工具/fixture失败；唯一预期失败为原实现 baseline-query01。第二 parser/permission 仅为补充直接消费者许可边界；先前 query/rooms/flow 方法和生产无变化，复用其通过证据。
- 本轮合法完整 preWorld 已在 query01/derived-preWorld.bin 保存 freeze() 原始 Godot variant，含全部事实/RNG；不声称前次 derived03 有此文件。基线独立构造另有原始 bin，UUID不同，不声称两次原始字节相等。
- 未运行性能微测、2253历史、长窗、全专题、施工完工流程或 GPU 验收；无安装/构建。未 stage/commit/push。

## 原始证据
目录 `derived-public-point-20261112/`，包含命令、引擎/native身份、隔离 HOME/XDG/TMP、exit/log/真实 wall time、所有失败、完整 preWorld、前后源码/补丁及 UID。耗时是功能进程墙钟，非性能结论。

- parse01: exit 0, 2.809104s, reaped=True
- baseline-query01: exit 1, 3.314072s, reaped=True
- query01: exit 0, 2.613127s, reaped=True
- rooms01: exit 0, 3.212556s, reaped=True
- flow01: exit 0, 2.608922s, reaped=True
- parse02: exit 0, 2.810387s, reaped=True
- permission01: exit 0, 2.908905s, reaped=True

生产SHA256 `3fae21448518fed43c905043ec2c24738f74b0e789906f411549e3a1f394f22e`；测试SHA256 `e8a51508136dceff6c483b5eca35114ee8962f2afbd645a493e5dea0ade6df5b`。完整 preWorld 11608 bytes，SHA256 `cd0a727611baf465763268f0d30c7d291de7419681cc2a4657d25053e76d7336`。所有 663 个既有 UID 字节不变，无新增/移除。

[原始包](evidence/2026-11-12-derived-public-point/selected.zip) 855489字节、60成员，SHA256 `7be244c6f4b3c95976ccfa53269d88d8aa4401a89c86c2c8fdd3f0cc1c38ee9e`；[成员清单](evidence/2026-11-12-derived-public-point/selected.members.json)、[结果汇总](evidence/2026-11-12-derived-public-point/selected.summary.json)。本地CRC与逐成员SHA通过。
