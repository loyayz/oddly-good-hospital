# 驻留静态图的矩形查询

依据现有整数通行谓词：保持身体包络、floor/ceil 包含末格、原点 y→x 顺序、原 `reason` 首错、净高、成员、预约和最后墙边检查。优化只借用已完整构建且来源/身体匹配的既有图；冷缓存、淘汰、修复中、身份改变及不匹配输入完整回退，不主动建图。

独立选例入口：

```powershell
godot --headless --path . --script res://tests/acceptance/resident_static_rectangle_runner.gd -- C:/absolute/new-result.json MASK-NATIVE MASK-LIFETIME MASK-BOUNDARIES MASK-FIRST-REASON
```

- `MASK-NATIVE`：完整 96×96 掩码、逐行首零、最后一行/列、单点、矩形外障碍排除、非法长度/边界/扫描值拒绝、输入只读。统一错误对象须有 `error` 且没有 `blocked_id`。
- `MASK-LIFETIME`：冷查询不建图、匹配完整图复用、小矩形完整回退、clone 尺寸/身体高度/楼层净高不匹配回退、身体改变、零预算清空、合法在用借用、弱引用不持有淘汰图、来源变化、旧几何失效和局部修复中禁用。
- `MASK-BOUNDARIES`：单格与大身体、整数/分数/近整数、96 边界、越界、真实墙门及净高，逐项与完整原谓词比较原因及完整源事实。
- `MASK-FIRST-REASON`：查询局部预约及成员投影的较早失败不得被后面的静态禁用点掩盖；原墙边检查保持。实际交接另验证四个 `RETURN-*`、两个 `LOCAL-CORNER-*` 和门通行专项。
