# 完整性能验收：Release启动预检

生产提交ddc9aea已在隔离工作树导出Windows x64 Release。实际发行程序的外部只读探针通过，正式业务负载、帧/步/速度、图形资源、操作和稳定性验收尚未完成。该预检不构成性能通过。

## 发行身份与启动路径

发行单元为`.build/formal-ddc9aea/product/`，原始build-identity与探针结果保存在同名evidence.json。构建源为ddc9aea；导入生成的两个未跟踪UID在build-identity逐项记录，受跟踪工作树与该提交一致。原生DLL沿用第五轮版本，14,875,648 bytes，SHA256为02fbe7c7be685ba3115d277904ff5333d9b07a2f3d43f38b02adfd2b1ea19e0b。

实际启动先后保留三次结果：

1. --main-pack被标准发行模板拒绝，明确返回未编译路径覆写支持。
2. 仅--script没有执行探针；30秒内只有正常引擎/渲染器banner，无探针结果，所属PID看门狗终止。该次未完成。
3. 在独立发行副本旁设置引擎内置override.cfg，启动前指定全新独立profile和外部Node主场景。原EXE、PCK、DLL不变，实际执行外部探针并以0退出，valid=true。

Godot将CLI路径覆写与项目设置override作为独立能力；无CLI路径支持时会清空script/main_loop参数，但原PCK载入后仍可读取启用的override.cfg。依据为[Godot main.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7-stable/main/main.cpp)与[项目设置载入实现](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/config/project_settings.cpp)。本机第三次结果已验证该路径，不依赖重新编译引擎或添加游戏测试入口。

探针确认template/release=true、editor/debug=false，Windows显示服务、Arc OpenGL Compatibility，原6个业务资源、79个global class、三个原生接口、GameSession.tick_completed及TickResult四个原始计时字段可用。实际QPC频率为10,000,000，连续读取单调。

正式观察器改为Node外部主场景，原AppRoot、GameSession、模拟和保存仍执行原实现。每场复制发行单元，校验源/副本哈希，设置独立启动profile，原产品目录不写override；采集脚本、场景与override哈希纳入工具身份。初始可见资源和实际工作缓存就绪后开始采样，未来日容量后台准备保留在普通经营负载，不以其完成作为暖机前置条件。

8个正式核心/操作观察脚本的Godot4.7.2语法检查全部通过，记录位于`.cache/performance/formal-tool-check-r2/`。这不替代实际运行。

## 负载准备缺口

旧Fixture中的8个访客只有Actor，没有原访客业务所有者，不能作为完整160人合法负载。正式输入保留120患者、32员工、8真实访客，补齐合法公共座位并执行原访客准入、路线和完整步，不用站桩或患者替换访客。

首个生成尝试在168.590秒后因工具前提缺陷中断：座位候选反复执行完整全院建造安全检查，而且该阶段没有原准备watchdog与进度。引擎CPU163.344秒，stderr为空，无输入或manifest。该结果为incomplete_tool_preparation，不是游戏性能超时判定。所属父子PID及启动身份核对后停止；未终止其他进程。完整记录见`.cache/native-math/formal-inputs-ddc9aea-r1/`。

第二次生成在10.515秒内完成，但改写了来源中已经形成的陪诊意图，因此保留为工具前提失败，不能作为正式输入。

第三次生成保留原陪诊意图、随机流和全部待到场请求，按原顺序消费8个既有合法请求。新增初始公共座位通过拥有地、实际占地与等候位检查，实际准入、完整路线和21个原0.1秒步均由原所有者执行。世界校验通过，tick25时实际120患者、32员工、8家属；64间房、1200件FUR18及原128个服务对象全部保留，另加8张公椅，实际设施总数1336。待到场请求从38变为30，后续仍按正常业务处理，不锁定人数。

合法输入SHA256为6595dda287f5a82cf725ce3b1cd77b8da8d73bc242da7f2c13aa97e0b5ea822e，内部准备10.775秒，位于`.cache/performance/formal-inputs-ddc9aea-r3/160four.input.bin`。输入生成通过仅证明该命名初始边界可用；完整帧/步/操作与资源结果继续由实际Release采集判定。

正式工具保留产品原帧上限及同步设置，不把fps_target目标值设置为额外帧上限。最后的两个观察脚本再次语法检查通过，记录位于`.cache/performance/formal-tool-check-r3/`。
