# 调度重复准备修复证据

- `quick-summary.json`：最终 `ga/gb/gc/gd` A/B/B/A完整快速窗口、此前全部中间窗口、资格、工作量、当前查询计数及终态摘要。
- `function-summary.json`：基线、首次三处修复、补齐冷来源后的最终版本，在相同选定完整步的阶段及函数耗时。新增准备函数包括在内；插桩时间不用于宣称整步加速。
- `functional-summary.json`：首批16项中的1项失败、随后4项补验通过；完整用例结果及前提、准备与执行耗时。
- `source-check.json`：基线439个游戏/内容/性能脚本路径与Git `0f6a9099b5de2d17db08cd60ceb53620012b7c86` 核对，最终冻结源码与提交工作树核对，测试源码及引擎/原生库/运行库身份核对。
- `raw-manifest.json`、`raw-evidence.zip`：原始输入、全部结果与逐步流、终态、运行日志、失败和补验、测量脚本、插桩转换及原方法体，各条目SHA256核对。

基线从既有同源工程克隆，逐路径与当前基线Git内容及克隆文件核对；其来源和身份保留在 `before-project/source-identity.json`。`after-project` 为最早修改版，`final-project` 尚缺无图冷来源修复，`fixed-project` 才是最终源码；没有用中间版的测量冒充最终代码。

固定合法160人输入均来自原场景，原始二进制一并归档。功能回归、冻结工程导入、静态检查、快速诊断分别报告；未导出Release、未运行正式矩阵或两小时稳定性。原阈值不变，`formal_pass=false`。
