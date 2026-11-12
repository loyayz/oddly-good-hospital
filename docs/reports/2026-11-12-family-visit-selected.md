# 有效家属探视专项：执行前计划

计划编写时状态：仅准备，未解析、未启动引擎、未生成新输入或运行选例。实际执行结果见后节。基于 HEAD 85a69488d0a693f0ccabc2d34eab743c9128af6a，生产73fd376。原 mixed160 输入及benchmark不变。

## 规则与本次范围

`effective_ward_visit`是短时家属探视，不是医护care查房，也不是companion陪同入房。design08的病房探视条目与统一临床家属规格§5规定：每日白天独立30%意向，最多一名独立探视者；实际双方完整身体同在病房才累计300个0.1秒有效tick，医疗/转运/让位期间不计，之后真实离院，不转为陪同、不产生生活任务。

正式入口为HospitalVisitors.arrivals：合法实际住院→每日意向→同意→内部_request→真实入口/等候点可用才_admit。clinical_visit_consent只管理同意，不生成意向；禁止用它或直接写visitor_intent伪造命中。原mixed v1和旧未覆盖结果完整保留。

## 精确选例与前提

新增独立runner `tests/acceptance/run_family_visit_selected.gd`，仅可选择FAMILY-06、FAMILY-12，调用现有inpatient_family.run与原用例，不复制或改写其业务断言。

- FAMILY-06：companion和ward_visit两人正式到场，实际不同身份、完整身体不重叠，非必须床边，入房已经产生有效计时。
- FAMILY-12：无companion变体，实际300有效tick，期间不转换角色或产生生活任务，真实离院及空间身份清理。
- 两项共享现有before_admission生产命名前提；不同的companion概率条件分别复制完整World，不能混用不同意向输入。相同条件的真实入房前提仍由原_named_sources共享。
- 复用既有明确功能RNG边界：入院陪同7999/8000、探视2999，由原正式抽签执行，不直接写意向/请求/访客/路径/完成。完整记录被声明的stream旧/新值，以及该声明前后两份完整World事实。这是专用功能输入，绝非当前mixed自然轨迹或概率统计，不允许偷偷移植回原160输入。
- 原fixture通过正式build_room_open命令暂停手术，专门留出无医疗占用的探视区间；不暂停真实行走/时间。实际推进使用原ClinicalStep，不宣称本次为综合Simulation性能测量。

## 输入保存与失败边界

没有找到已核验当前来源、内容及版本身份的独立“请求前”缓存；不把旧Windows意向false的事实改成true。首次获引擎槽后，按原_surgery_queue生成一次before_admission并共享。子类只保存：原before_admission、每次专用RNG声明之后但正式daily scan之前的完整facts/RNG、实际入房后的原命名边界。文件使用新输出目录、存在即拒绝覆盖，保存SHA/长度/content/engine/validation。恢复或独立重用之前仍须检查内容、源文件与执行身份及World.validate；保存成功不是前提验证成功。

实际抽签、请求、接纳、行走、入房和300tick都来自现有正式所有者；未手填家属、路径或倒计时完成。若原前提生成失败，保留精确阶段/验证/日志，不无限延长、不换seed挑选综合性能结果。原用例已经有有限步数上限，宿主另加owned-process超时并回收。

本轮不声称覆盖医疗中断恢复、跨夜、实际转运暂停的所有边界。先用06/12证明所缺场景主链；只有观察到这些接口影响本轮结果才选择相应11/10等，不默认跑全家属专题。后续版本化固定场景是独立决定，不能将功能输入结果冒称旧31覆盖已补齐。

## 执行方案与实际结果

父线程释放引擎槽后已执行：先独立parser，再同一进程选择`FAMILY-06,FAMILY-12`（若只选一个，不先跑其它编号）。预备命令：

```
Godot_v4.7.2-stable_linux.x86_64 --headless --path <current repository> --script res://tests/acceptance/run_family_visit_selected.gd -- <fresh output/result.json> FAMILY-06,FAMILY-12
```

复用已验证Linux库与owned-process guard，工程使用当前工作仓库，隔离的是HOME/XDG/TMP，OMP1。宿主记录仅白名单CPU/内存/affinity/cgroup配额与用量；不读挂载布局、cgroup身份映射，主机node仅hash，process仅显式环境允许列表。本批执行阶段未暂存、提交或推送。

## 本轮已执行证据

parser exit 0；selected01 exit 0，FAMILY-06/12 共 12 项断言全部通过。功能用例本体合计 10.642 秒，受控进程总耗时 13.181 秒，before_admission 只生成一次 5.116 秒（嵌套耗时不重复相加）。两类家属实际入房边界 tick 1269；无陪同探视者实际入房 tick 1219。入房前的 daily intent 声明均在 tick 1032，住院前输入 tick 1031。声明完整前后 World 与 RNG、实际入房完整 World 共 7 个文件，均 SHA 校验通过。

FAMILY-06 验证不同身份、非床位点、完整身体无重叠、入房计时和 World/临床身份合法。FAMILY-12 验证 300 有效 tick、院内清理拒绝、无生活/转换、真实离院和空间身份释放。请求和接纳经过正式生产调用，但本轮没有逐 tick 请求事件流水；离院结果由原断言证明，没有另存离院末态 World，不能声称这些未采集附件存在。无需为补附件重复已通过原用例。

原始证据：`family-visit-selected-20261112/selected01/result.json`、7 个 `.bin`、parser/run 日志与 process.json、summary.json、源码副本及 selected.zip。原生产源码未修改，UID 前后逐字一致；全部拥有的引擎已回收，无临时生产 hook，无 stage/commit/push。引擎槽已释放。旧 mixed160 未覆盖结论保持不变，后续版本化综合输入仍需单独设计与验证。

[原始包](evidence/2026-11-12-family-visit-selected/selected.zip) 248022字节、28项（27数据成员及清单），SHA256 `79ff400ed9b2f13cca37845bc1c433d19a58d4f2d65f88b1d44eaa4af32d3d2c`；[成员清单](evidence/2026-11-12-family-visit-selected/selected.members.json)、[汇总](evidence/2026-11-12-family-visit-selected/selected.summary.json)。本地CRC/逐成员SHA通过。
