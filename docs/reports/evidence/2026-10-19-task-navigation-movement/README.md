# 暂停交付证据

此目录归档已存在的结果。没有为交付重新运行引擎、构建、内容编译、功能测试或性能测量。

- `quick-summary.json`：重写前完整300步基线、两个未完成的新版本窗口、诊断及未完成项。最新版本完成93/300步，不是完整性能通过。
- `functional-summary.json`：71项通过批次及后续6项、19项相关复测；保留早期失败，计数不可相加。
- `prior-quick-summary.json`：重写前4个本地提交组合的既有对照，不能代表重写后的收益。
- `final-source-identity.json`、`delivery-source-match.json`：最终测量工程逐文件SHA及与交付生产源码的匹配记录。身份中的`head`为冻结时HEAD，源码当时未提交。
- `evidence-manifest.json`：ZIP和每项证据的SHA、大小及未归档的大型早期调用树说明。
- `raw-evidence.zip`：`rewrite/`为本次重写，`acceptance/`为原始相关功能结果和失败快照，`original-inputs/`为原输入，`prior-decision-ledger/`为前置阶段证据。

ZIP中的命令文件保留历史执行方法，不是要求自动执行的交付步骤。绝对路径可能指向原本地缓存；归档内部使用相对路径。正式性能验收继续暂停，所有插桩数据仅用于诊断。
