# 实际显示与三维附件尺寸

`capture-display.ps1`对同源Windows Release的独立副本采集显示边界。外部主场景复用原AppRoot控件和HospitalView，在合法预设医院上显示；不创建GameSession，不承担160人经营、速度、帧时间、图形预算或稳定性职责。原EXE、同名PCK及DLL保持相同字节，独立profile和override另记身份。

```powershell
pwsh -NoProfile -File tools/performance/acceptance/capture-display.ps1 `
  -Exe C:/release/oddly-good-hospital.exe `
  -Output C:/evidence/display-boundaries `
  -RenderDoc C:/tools/RenderDoc/qrenderdoc.exe
```

RenderDoc使用[官方发行包](https://renderdoc.org/builds)，本机验证接口为1.46。默认条件为2560×1440/2880×1920、100%/200%界面和100%/75%/约67%三维比例，共12个显示边界；可用`-Conditions <JSON数组>`选择独立诊断范围。每个条件保留真实窗口、控件screen transform映射的物理范围、输出纹理、原生二维模式、实际Release特征及RDC原件。

Python脚本通过RenderDoc target control在原条件已显示后抓一帧。回放读取真实draw的color/depth附件和viewport尺寸，报告与该控件输出对应的三维depth draw及根光栅输出；没有对应的实际draw不会用请求尺寸补值。二维逻辑尺寸与物理尺寸不必相同，canvas_items与实际光栅纹理共同核对。每个条件必须使用实际请求窗口/UI和Release特征，退出或缺附件按未完成处理。

采集与回放注入会改变CPU、GPU和内存开销，此工具的任何耗时、帧或资源数都不进入正式性能总体。正式资源预算继续使用无注入Release、原始DxgKrnl分配与同窗口OS视图；RDC只补实际显示/后端尺寸证据。首次工具analytics提示在调用期间关闭，调用结束恢复原UI.config字节，不修改游戏偏好。
