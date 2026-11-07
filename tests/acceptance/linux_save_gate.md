# Linux平台资源预算与真实保存边界

`linux_save_gate.gd`使用正式`PlatformSessionGuard`和`HospitalSnapshots.begin()`，不替换平台类、不注入可用内存数值。

当真实执行环境不能证明有效内存额度时，要求保存被明确拒绝、未启动工作线程、未创建医院数据库，完整世界事实保持不变。这是失败原子性证据，不是成功保存/恢复证据。

当实际额度可靠可读时，该脚本只报告拒绝分支不适用；成功路径必须另选CORE-18～29、CORE-46等真实资料库用例。跨进程锁、异常退出释放、SQLite未提交事务回滚和数值/UTF-8路径由`tests/native/run_linux_platform.py`验证。资源解析和cgroup层级边界由`tests/native/run_linux_memory_test.sh`验证。

所有测试必须使用独立HOME/XDG资料目录。Linux无窗口结果不能代表Windows路径和锁语义、发行安装、GPU绘制或完整性能。
