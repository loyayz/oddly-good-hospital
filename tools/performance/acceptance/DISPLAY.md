# 实际显示与三维附件尺寸

`capture-display.ps1`对同源Windows Release的独立副本采集显示边界。外部主场景复用原AppRoot控件和HospitalView，在合法预设医院上显示；不创建GameSession，不承担160人经营、速度、帧时间、图形预算或稳定性职责。原EXE、同名PCK及DLL保持相同字节，独立profile和override另记身份。

```powershell
pwsh -NoProfile -File tools/performance/acceptance/capture-display.ps1 `
  -Exe C:/release/oddly-good-hospital.exe `
  -Output C:/evidence/display-boundaries `
  -RenderDoc C:/tools/RenderDoc/qrenderdoc.exe
```

RenderDoc使用[官方发行包](https://renderdoc.org/builds)，本机验证接口为1.46。默认条件为2560×1440/2880×1920、100%/200%界面和100%/75%/约67%三维比例，共12个显示边界；可用`-Conditions <JSON数组>`选择独立诊断范围。每个条件保留真实窗口、控件viewport transform映射的物理范围、输出纹理、原生二维模式、实际Release特征、根PNG原图及RDC原件。根光栅尺寸使用实际Image读回值；ViewportTexture声明尺寸单列，不能代替真实附件。

Python脚本通过RenderDoc target control在原条件已显示后抓一帧。回放读取真实draw的color/depth附件和viewport尺寸，报告与该控件输出对应的三维depth draw及根光栅输出；没有对应的实际draw不会用请求尺寸补值。二维逻辑尺寸与物理尺寸不必相同，canvas_items与实际光栅纹理共同核对。每个条件必须使用实际请求窗口/UI和Release特征，退出或缺附件按未完成处理。

采集与回放注入会改变CPU、GPU和内存开销，此工具的任何耗时、帧或资源数都不进入正式性能总体。正式资源预算继续使用无注入Release、原始DxgKrnl分配与同窗口OS视图；RDC只补实际显示/后端尺寸证据。首次工具analytics提示在调用期间关闭，调用结束恢复原UI.config字节，不修改游戏偏好。

RenderDoc无法推进时，可用[官方apitrace14.0](https://github.com/apitrace/apitrace/releases/tag/14.0)的Windows x64 portable包采集同一OpenGL后端：

```powershell
pwsh -NoProfile -File tools/performance/acceptance/capture-apitrace-display.ps1 `
  -Exe C:/release/oddly-good-hospital.exe `
  -Output C:/evidence/gl-display-boundaries `
  -ApiTrace C:/tools/apitrace/bin/apitrace.exe
python tools/performance/acceptance/apitrace_display.py C:/evidence/gl-display-boundaries
```

采集副本额外放置官方opengl32追踪wrapper，并单列其哈希；原EXE/PCK/DLL不改，拒绝已有wrapper或能力覆盖配置。完整`.trace`保留，`gl-calls.txt`包含线程、上下文、真实纹理/渲染缓冲分配、FBO附件与完整性检查、viewport、draw、swap和读回。分析器按上下文和实际对象生命周期重建当前绘制状态，将真实根PNG读回关联到该帧实际root绘制与带depth的三维绘制。缺少成功FBO检查、对象大小、实际draw或可靠读回关联时保持未完成；不由请求百分比补出实际附件。采集成功先记`captured_pending_backend_analysis`，只有原始trace/dump/PNG/owned进程身份及实际附件均核对后才判显示证据通过。

`gl-render-target-evidence.json`的status同时核对原始GL附件关联和最近偶数规格；`nearest_even_3d_policy_pixels`和`nearest_even_3d_policy_satisfied`保留独立结果，不能由关联时允许的整数差推定合格。内部实际尺寸和原生二维都由同一条件的真实draw/读回证明；该独立显示取证不代表正式经营、资源预算或整个发行矩阵已通过。

Godot4.7.2把输出extent×原scaling_3d_scale的float32乘积截断为内部整数。生产视口先从控件实际物理extent求最近偶数内部尺寸E，再选择邻近整数输出extent n使float32的floor(n×scale)=E；n与控件物理区域最多相差数像素，TextureRect仍覆盖原区域，原pick/pan使用实际n。该取整不增加显示档位、不改原生二维或世界事实，最终必须由实际GL附件重新确认。r3单条件原始trace已实测1263×773，对应原最近偶数1262×772，旧policy=false保留为该版本未满足的证据。
