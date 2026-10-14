# 怪好的医院 · Oddly Good Hospital

Windows独立安装、单人离线的轻松医院建造经营游戏。完整设计、内容与数值位于`docs/design`和`docs/data`；离线阅读页为`docs/product-design.html`。

当前工程交付第一阶段技术样板：两座独立验证医院、真实门诊及手术住院、五类身体、两层通行、完整提交保存与Compatibility场景。样板证明关键路径，正式空院成长和全部系统沿[四十二阶段实施路线](docs/design/12-implementation-plan.md)接入。范围、实测与未覆盖项见[第一阶段报告](docs/design/13-stage01-feasibility.md)。

## 构建

```powershell
pwsh -NoProfile -File tools/build-stage01.ps1
```

默认使用`C:/programs/godot/Godot_v4.7.2-stable_win64_console.exe`。固定导出模板、Blender、Zig和NSIS保存在`.cache/tools`并核对SHA256，不成为玩家依赖。居民、设备和道具源资产位于`art-source`，显式导出的GLB及中文字体位于`assets`。

程序输出到`.build/windows`，安装包输出到`.build/installer/oddly-good-hospital-stage01-setup.exe`。exe、同名独立pck、原生DLL及许可文件必须共同分发。试验安装器按用户安装，不覆盖已有安装；卸载保留医院资料。

## 运行与保存

运行已安装的`oddly-good-hospital.exe`。医院初始暂停，使用1×/2×/3×观察原流程；界面提供保存、切院、取消切院、切层、选择、跟随、滚轮缩放及100%/200%文字。纸巾和梦泡读取真实病例状态，视图不会推进结算或重抽结果。

医院资料位于引擎的`user://`目录，通常为`%APPDATA%/oddly-good-hospital`，以独立UUID与追加完整提交区分医院。第二进程只提示资料库占用，强制关闭后的下一次启动由Windows释放原句柄。

验收命令和隔离资料库规则见第一阶段报告。设计与数据更新后运行：

```powershell
pwsh -NoProfile -File docs/tools/export-design.ps1
```
