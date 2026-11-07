# 怪好的医院 · Oddly Good Hospital

面向Windows与Linux x86_64的单人离线轻松医院建造经营游戏。Linux支持范围与当前验证状态见`tools/linux/README.md`。完整设计、内容与数值位于`docs/design`和`docs/data`；离线阅读页为`docs/product-design.html`。

当前工程实现至第28阶段：预设院区与空地开局、多院保存及备份、实际门诊/手术/住院、员工培养与排班生活、候诊、耗材、环境装修、设备维护升级、科室体验、财务、招聘、随机来客、研究资料、土地与楼板施工、跨层交通、安全改建及共享蓝图。操作统一进入固定步模拟，界面、报价和视图读取同一世界事实。各阶段状态见[交付记录](docs/reports/2026-10-15-stage04-stage24.md)，后续范围见[四十二阶段实施路线](docs/design/12-implementation-plan.md)。

## 构建与运行

```powershell
pwsh -NoProfile -File tools/build-game.ps1
```

默认使用`C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe`，生成`.build/stage28/product`中的Windows Release程序、独立pck、平台库、许可证和`build-identity.json`。这些文件共同构成运行单元。构建检查发布内容并封存实际源码与各产物身份，功能专项测试单独执行。

正式内容由`tools/compile-content.py`从设计数据生成，运行时使用不可变注册表。内容字节核对入口：

```powershell
python -B -X utf8 tools/compile-content.py --check
```

固定导出模板、Blender、Zig和NSIS保存在`.cache/tools`，不是玩家依赖。居民、设备和道具源资产位于`art-source`，导出的GLB及中文字体位于`assets`。`tools/build-stage01.ps1`保留试验安装器构建，正式发行安装与升级由阶段40收口。

运行`oddly-good-hospital.exe`后医院初始暂停，可用1×/2×/3×观察经营；界面支持保存、切院、切层、选择、跟随、缩放及100%/200%文字。医院资料位于引擎`user://`，通常为`%APPDATA%/oddly-good-hospital`，以独立UUID和追加完整SQLite提交区分医院。第二进程提示资料库占用，异常退出后由Windows释放句柄。

## Linux构建与验证

Linux原生实现与Windows共享业务绑定，平台边界使用条件编译；Linux不会改写Windows源文件来生成测试替身。构建入口、固定依赖及导出要求见`tools/linux/README.md`。原生库输出至`game/platform/linux/bin`，导出预设为`Linux x86_64 Release`。正式构建需要固定Godot 4.7.2和相同版本的Linux导出模板。

Linux资料目录遵循Godot的`user://`和XDG数据目录约定。独占锁使用实际文件句柄与`flock`；SQLite使用UTF-8路径。保存安全预检同时考虑宿主可用内存和可证明完整的cgroup层级限制。层级被命名空间遮蔽、不可读或格式无效时明确拒绝保存预算，不以宿主空闲内存冒充容器额度。

无窗口原生与功能测试不等于发行包、图形输出、完整性能或Windows实机验收。没有对应运行环境时必须单独列明这些缺口。

## 功能专项测试

[测试目录](tests/README.md)维护阶段1至28的需求条款、业务前提、操作和明确预期。六个专题覆盖内核与资料、临床、员工生活、运营、来客研究和空间改建。

```powershell
pwsh -NoProfile -File tests/run-acceptance.ps1 -ListCases
pwsh -NoProfile -File tests/run-acceptance.ps1 -Case 'CORE-04,CLIN-06'
```

六个专题的已注册用例均支持独立选择及跨专题组合，耗时前提按业务边界复用；完整功能库须显式使用 `-All`。回归范围和停止条件见 [AGENTS.md](AGENTS.md)。测试使用独立工程与唯一资料目录，记录实际源文件、引擎、命令、退出码及逐项结果。旧阶段验证、设计验算、基准与回放工具已移除；历史报告只保留当时构建的结果，不能作为当前代码的通过证据。

阶段28后的性能测量与优化单独进行。[第三阶段性能限制](docs/design/15-stage03-kernel-performance.md)继续保留；全量正式美术、长期经营平衡、完整性能和发行验收按后续阶段交付。

## 设计阅读页

```powershell
pwsh -NoProfile -File docs/tools/export-design.ps1
```

导出器只生成阅读页和设计数据索引，不执行功能测试或设计验算。
