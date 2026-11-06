# Linux 原生空间索引核心检查

此工具从当前 `platform_spatial_index.h` 提取真实 `SpatialInstance` 和 update/query/query_many 分支。树、删除、更新和查询算法不替换；仅将 Godot Variant 输入/输出改接标准 C++ 类型。独立穷举矩形相交 oracle 验证跨层、更新同一身份、删除、清空、重复查询区域、边缘接触和零面积框。

要求 g++（C++17）和与仓库相同的 Boost 1.92.0 头文件。可以将 `tools/build-arrival-math.ps1` 固定的 MSYS2 包解压到独立目录，无需系统安装：

- 包：`mingw-w64-ucrt-x86_64-boost-1.92.0-4-any.pkg.tar.zst`
- SHA256：`2f9935335e17f9930cba7e93a8db95bf699df2dd1c250cffe6dce89c7ea70154`
- 文件来自 MSYS2 官方镜像列表；校验摘要后只解压 `ucrt64/include/boost` 与许可证。

```sh
python3 -B tests/native/spatial_index_core.py \
  --boost-include /absolute/path/ucrt64/include \
  --output /absolute/path/new-result-directory
```

输出源/翻译单元哈希、编译器、完整命令、日志和结果。输出目录必须不存在。20,000次确定随机操作及精确边界样本共40,015次查询对照；这是实际 Boost R-tree，不是模拟索引。Broadphase 包含边缘接触符合当前原生实现，严格接触由上层 `BodyIndex` 过滤。

不覆盖 Godot ABI、Variant 类型转换、错误处理、动态库注册、BodyIndex/Godot 整体调用或完整医院。没有性能收益声明，也不能将本检查当作 SPACE-55 或正式性能验收通过。
