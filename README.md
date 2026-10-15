# 怪好的医院 · Oddly Good Hospital

Windows独立安装、单人离线的轻松医院建造经营游戏。完整设计、内容与数值位于`docs/design`和`docs/data`；离线阅读页为`docs/product-design.html`。

当前工程交付到第24阶段：预设院区与空地开局、多院保存及备份、实际门诊/手术/住院、员工培养与排班生活、候诊、耗材、环境装修、设备维护升级、科室体验、财务、招聘及随机来客。操作统一进入固定步模拟，界面、报价和视图读取同一世界事实。功能证据见[第04至24阶段交付记录](docs/reports/2026-10-15-stage04-stage24.md)，后续范围见[四十二阶段实施路线](docs/design/12-implementation-plan.md)。本批次性能检测暂时跳过，既有[第三阶段性能限制](docs/design/15-stage03-kernel-performance.md)继续保留；全量正式美术与长期经营平衡仍按后续阶段交付。

运行 `pwsh -NoProfile -File tools/build-game.ps1` 生成 Windows Release，产物位于 `.build/stage24/product`。构建检查发布内容并封存程序、内容包、平台库和源码身份，不运行性能检测。`tools/verify-functional-stage.ps1` 从 Git 暂存区创建独立工程与资料目录，用于功能验证。

## 构建

正式内容由唯一入口生成并校验。发布包、中文文本、房型与资源索引位于`content/core`，运行时使用不可变注册表，不直接读取设计数值。第四阶段及后续交付状态见[交付记录](docs/reports/2026-10-15-stage04-stage24.md)。

```powershell
python -B -X utf8 tools/compile-content.py --check
```

```powershell
pwsh -NoProfile -File tools/build-stage03.ps1
```

默认使用`C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe`。固定导出模板、Blender、Zig和NSIS保存在`.cache/tools`并核对SHA256，不成为玩家依赖。居民、设备和道具源资产位于`art-source`，显式导出的GLB及中文字体位于`assets`。

程序输出到`.build/stage03/product`。exe、同名独立pck、原生DLL及许可文件必须共同分发。`tools/build-stage01.ps1`保留第一阶段试验安装器构建入口，输出`.build/windows`及`.build/installer/oddly-good-hospital-stage01-setup.exe`；安装器按用户安装，不覆盖已有安装，卸载保留医院资料。第三阶段未重新执行安装器验收。

## 基准与回放

第二阶段生成72组未测量的显示计划；准备Release基准不会启动性能检测：

```powershell
pwsh -NoProfile -File tools/prepare-performance-plan.ps1
pwsh -NoProfile -File tools/prepare-kernel-benchmark.ps1
```

第三阶段按160→320→640人逐档验证，当前人数的1×/3×均通过才进入下一档，每档失败后最多三轮优化、提交与正式复测。160人阶段门禁已通过；最终构建320人完成三轮优化后，1×P95为10.135ms，仍高于10ms预算，3×通过，640人及其通过后的六组完整基准未执行。38项规则检查通过，最终结果与限制见[第三阶段报告](docs/design/15-stage03-kernel-performance.md)。完整步预算为P95≤10ms、P99≤15ms、普通最大≤30ms，实际速度≥99%。每组预热60秒、采样600秒；两组约22分钟，完整六组约66分钟。原始数据位于`.cache/validation/stage03/<RunName>`，基准使用独立资料目录。

```powershell
pwsh -NoProfile -File tools/measure-kernel.ps1 -Actors 160 -RunName local-kernel
python -X utf8 tools/report-kernel.py --input .cache/validation/stage03/local-kernel --actors 160 --output .cache/validation/stage03/local-kernel/report.json
```

真实测量结果、构建身份、目标判定及缺失成本见第三阶段报告。无窗口结果只覆盖模拟内核。独立回放入口为`tools/replay-simulation.gd`，输入为初始世界、带tick的命令记录和目标tick，输出规范化事实及随机流末态；完整参数格式见[实施规格](docs/specs/26-10/2026-10-14-stage02-stage03-simulation-kernel.md)。

## 运行与保存

运行已安装的`oddly-good-hospital.exe`。医院初始暂停，使用1×/2×/3×观察原流程；界面提供保存、切院、取消切院、切层、选择、跟随、滚轮缩放及100%/200%文字。纸巾和梦泡读取真实病例状态，视图不会推进结算或重抽结果。

医院资料位于引擎的`user://`目录，通常为`%APPDATA%/oddly-good-hospital`，以独立UUID与追加完整提交区分医院。第二进程只提示资料库占用，强制关闭后的下一次启动由Windows释放原句柄。

验收命令和隔离资料库规则见第一阶段报告。设计与数据更新后运行：

```powershell
pwsh -NoProfile -File docs/tools/export-design.ps1
```
