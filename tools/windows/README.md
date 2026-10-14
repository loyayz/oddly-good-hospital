# Windows第一阶段打包

`tools/prepare-stage01-tools.ps1`取得并核对固定Godot 4.7.2 Windows导出模板及NSIS 3.13 portable。已存在的ZIP/TPZ先核对SHA256再复用，不修改全局环境。原生桥接由`tools/build-platform-guard.ps1`重建。

```powershell
pwsh -NoProfile -File tools/build-stage01.ps1
```

构建等待Godot的完整`--import`完成并核对退出码，再导出Windows x86_64 Release。资源导入、导出和安装器编译日志分别位于`.cache/validation/stage01-build-import.log`、`stage01-export.log`、`stage01-installer-build.log`。编辑器提前按固定帧退出不构成完成导入；原生组件说明记录了固定引擎的冷退出文档竞态。

`.build/windows`交付`oddly-good-hospital.exe`、独立同名pck、原生DLL、`build-identity.json`及外部`licenses`目录。清单记录实际程序文件字节及SHA256；Noto OFL、字体版权说明和Godot MIT均可直接阅读。安装器只嵌入明确列出的这些文件，编译副产物、旧文件名或其他目录文件不会自动进入安装包。

试验安装包位于`.build/installer/oddly-good-hospital-stage01-setup.exe`，按用户安装至`%LOCALAPPDATA%/Programs/oddly-good-hospital`，登记到HKCU并创建当前用户的“怪好的医院”开始菜单入口。已有本产品安装或对应快捷方式时停止，目标非空时停止。完整覆盖升级、中断恢复和公开签名由既定后续阶段验收。

```powershell
Start-Process -FilePath 'C:\安装包\oddly-good-hospital-stage01-setup.exe' -ArgumentList '/S /D=C:\安装验收\怪好的医院 空格' -WindowStyle Hidden -Wait
```

NSIS的`/D=`必须是最后一个参数，路径为绝对路径且不添加引号，即使包含空格。[NSIS命令行规则](https://nsis.sourceforge.io/Docs/Chapter3.html)。静默卸载使用已安装的`Uninstall.exe /S`；实际确认文件和注册入口已清理后才判定完成，启动进程退出不代替卸载结束。

卸载确认当前目录与安装登记一致后，只删除本产品已安装的已知程序文件及快捷方式。目录中其他文件保留，目录非空时保持原目录。整个`user://`医院资料库保留；安装与卸载不访问医院世界、设置、照片或自制蓝图。
