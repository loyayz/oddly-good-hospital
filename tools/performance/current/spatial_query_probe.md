# 原生空间查询 Rect2 入口

`PlatformSpatialIndex.query_rect(floor_id, Rect2)` 与原 `query(floor_id, Array)` 返回相同 Dictionary，使用同一 Boost R-tree、闭区间候选和原迭代顺序。四个 binary32 分量先提升为 double 再计算端点。原 Array 接口、批量查询、更新、删除及错误 Dictionary 保留；不存在的楼层仍不解析矩形。

SPACE53 的 `spatial_rect_query` 计算边界对照静态原生调用与 `Variant.call`，包含负坐标、非整数、零面积、接触边缘、非有限分量、负尺寸、楼层变更和删除。BodyIndex 继续负责严格相交、ignored、compound regions 与当前代际，原生宽相交不替代这些规则。

## 实际请求捕获

先在新编译原生库的共享隔离工程完成一次 import。捕获工具只修改 `.cache` 中指定工程的 BodyIndex，保存原字节和逆序还原断言，不复制整份工程、不替换 DLL、不启动引擎。原生查询在诊断副本内仍调用原 Array API。

```powershell
python -B tools/performance/current/prepare_spatial_query_capture.py install --project <隔离工程> --record <新记录.json> --expected-body-sha <未插桩BodyIndex的SHA256>
godot --headless --path <隔离工程> --script res://tools/performance/current/spatial_query_probe.gd -- --mode=capture --input=<完整mixed边界.bin> --expected-sha=<输入SHA256> --output=<新请求流.bin>
python -B tools/performance/current/prepare_spatial_query_capture.py restore --project <隔离工程> --record <记录.json>
```

捕获从完整输入真实执行一个固定模拟步，在 Simulation 构造前启用，记录每个 BodyIndex 的创建、全部实际 native clear/update/remove，以及每次原 `_query` 的楼层、原 Rect2、空代际标识和完整有序 IDs。保留完整初始世界、源身份、真实步的事件及终态哈希。相同矩形更新虽可能激活代际，但不修改原生树；空代际请求单独记录为 skip。所有原生树变更仍按原执行顺序保留，未截取最近若干角色、记录或请求。

诊断流不是普通性能结果。中断、未登记索引和不完整 footer 均不能用于计时。没有真实请求流时，工具不以重复单矩形代替实际负载。

## 三对局部测量

```powershell
godot --headless --path <已还原的同一隔离工程> --script res://tools/performance/current/spatial_query_probe.gd -- --mode=replay --input=<请求流.bin> --expected-sha=<请求流SHA256> --output=<新局部结果.json> --iterations=100
```

计时入口拒绝仍有捕获 hooks 的 BodyIndex。A/B 在同一候选 DLL 中分别调用原 Array API 与新 Rect2 API，两棵树按完整原操作流同步构建。每段无树变更的实际查询先完整预热并逐项比较原捕获 IDs、A IDs 与 B IDs，再按 AB/BA/AB 测三对；树更新、比较及哈希均在计时外。空代际保持原 skip，查询矩形、角色、候选、顺序与权限均不删减。

输出保留每段累计普通耗时、完整请求数、实际跨桥查询数、源世界与请求流身份。重复次数是局部只读查询循环，不是模拟步数；减少的 Array 封装次数可由实际跨桥次数推导，不能称为 allocator 次数或完整160人模拟步收益。整体收益仍由独立完整160人测量判断。
