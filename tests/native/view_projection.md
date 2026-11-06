# 同次视图更新的人物投影复用

```bash
python3 -B tests/native/view_projection.py --godot godot --baseline 35d656dc --output /tmp/view-projection-new.json
```

输出文件必须不存在。工具原样提取 `_sync_entities`、`_project_location`、`_visible_body_bounds`、`_cell_position` 和 `actor_body` 的实际算法；世界容器、内容查询、身体清距、视锥判定和资源创建使用明确输入适配器。身体计数是适配器观测，不把原生组件或 GPU 替换为假实现后宣称完整通过。

40 个读视图场景涵盖 1/32/160/640 人，及同 tick 位置、高度、身体绑定改变、乘梯上下客和行程、观察楼层切换、视锥隐藏与恢复。比较可见人物、位置、绑定签名、插值后身体包围盒，确认完整事实未修改。它们是视图输入边界，不证明业务移动或电梯流程已执行。

固定 160 人预热 20 次后执行三组 A-B-B-A，每窗 250 次完整的“同步实体→取得位置→汇总包围盒”隔离管线。所有窗口保留。该时间包含明确适配器和测试返回值整理，不能外推完整游戏帧率或 GPU 收益。

生产改动仅在一次同步 `update_facts` 调用内交接已计算的人物位置与尺寸，不跨帧、tick 或命令缓存。包围盒仍以最终插值后的 wrapper.position 计算。独立调用 `_visible_body_bounds()` 不提供采样时仍实时计算尺寸。
