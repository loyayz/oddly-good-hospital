# 第一阶段病例道具

三个 GLB 使用 Blender 4.5.14 LTS 的自制网格、顶点色与普通节点动画，单位为米，引擎局部 +Y 向上。根变换为零且不参与动画。

| 成品 | 实际绑定 | 外部锚点 | 主要节点 |
| --- | --- | --- | --- |
| `case_d37_tissue.glb` | B_S49_D37_M37 | hand_l，根始终留在原手插槽 | sail、paper_body、grip |
| `device_m37_filter.glb` | B_S49_D37_M37 / M37 | 设备局部 (1.5, 1.3, 1.5) | fan、cloud_bag、cloud、filter_seal |
| `case_d23_dream.glb` | B_S49_D23_M23 | head | bubble、sheep、sheep_2、sheep_pillow、dream_fence、closed_seam |

纸巾的折角被气流吹成小帆，实际治愈后收拢；纸巾与握持根不会离手。滤袋道具位于既有 M37 基座内，风车与棉花云只表现原治疗气流。三只羊和末羊的小枕头属于同一梦泡投影，返回沿原梦栅栏发生，不创建居民或可收集物。

共同动作包括 `symptom`、`work`、`paused`、`recovery`、`recovery_hold`、`low_motion`、`short_loop`。暂停优先保留当前实际进度对应的姿态，静态 paused 只作可读回退。主过程按真实进度定位；短循环只供次要表现，不以播放完成推进治疗、结算或资源释放。

D23 的 `awaiting_result` 保持梦泡完整且不暗示结果，`recovery` 仅在真实治愈后合拢；`low_motion_work` 和 `low_motion_recovery` 分别保留工作与合拢构图。M37 的 `safe_finish` 停转风车、收拢滤袋，适用于真实完成的尝试，不表示已经治愈。

从仓库根目录导出：

```powershell
pwsh -NoProfile -File tools/export-stage01-gags.ps1 -RenderSourcePreview -VerifyGodotImport
```

成品与精简 metadata 位于 `assets/gags`。源文件及联系图位于本目录；预览从实际 GLB 导入，以 Cycles CPU 渲染，用于美术检查。游戏内 Compatibility 的可读性、实际锚点绑定与临床状态映射由运行验收记录。道具不携带世界逻辑、临床计时器、随机选择或模拟实体。

三个 `.glb.import` 复用项目的顶点色导入脚本，保留实际 COLOR，并关闭不可变动画轨道删除与名称后缀转换，让静态姿态及动作名完整保留。Godot 检查读取实际 PackedScene 的材质、颜色流、无 Skin 路径及动作列表；headless 导入检查不宣告 GPU 呈色或游戏性能通过。`short_loop` 首尾相接，表现采样按既有次要演出周期定位，不通过片段结束回调推进临床。
