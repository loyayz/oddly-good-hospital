# 科室环境批处理中无来源的观察

实际链为 Department.sample → EnvironmentSampleBatch.prepare/consume。原生环境的现有 sample_at 在规范楼层、已拥有位置、正负来源范围之外且没有脚下材质时，结果仅由环境基础分与洁净加分构成。本改动在批准备中证明同一条件，完整生成该主体的观察，保留原消费顺序；其余请求仍交现有 worker。没有抽样、降低频率、跳过患者、修改水权限或生成新索引。

边界：

- 只启用原生 batch、environment、space，要求同一当前 query 和规范楼层。自定义 batch 的执行/失败钩子仍接收全部请求。
- 复用现有 observation bounds 与已准备的 owned 集合；没有相应集合时用原 owned 查询。非规范/未知边界、院外点、地材、任一潜在来源仍走原 worker。
- 动态灯具、污渍、噪声、水的来源界限由原 owner 和查询生命周期提供，作用半径及 R15 保持原规则。不保留新的跨查询状态。
- 每个主体得到独立观察字典及 sources 数组。完整空观察只共享不可变的空覆盖映射，消费方不向该映射写入。主线程产生的观察与 worker 结果一起按原 visit 顺序消费；部分 worker 失败时清空整批结果，Department.sample 仍完整串行回退。
- 批统计 processed/consumed 仍覆盖全部请求，jobs 只报告实际执行的 worker。main_empty_observations 单独计数主线程生成的观察；失败批次的此计数不代表已消费。
- 来源准备、覆盖值、缓存合并与释放保持原语义。worker 只按实际请求数创建；没有 worker 的批次不复制历史覆盖种子。移动、导诊、空间、环境来源和饮水判断均未修改。

选择器：

- ENV-EMPTY-MATRIX：合法世界的纯空、混合灯具、地面材质、污渍、小数坐标、上层、旧楼层、定制 batch、关闭体验和不在楼面的患者。完整观察与原生 sample_at 相等，世界只读，作用分支有计数证据。
- ENV-EMPTY-GUARDS：合法世界上的显式院外/越界观察坐标、未知边界、异世界和缺少楼层边界。只是保守性计算检查，不将患者伪造到院外。
- ENV-EMPTY-RANGE：普通半径之外一格及 R15 扩大半径后的精确来源变化。
- ENV-EMPTY-LIVE：同一 batch 重用，新增灯具、失效、移除、完整事实替换和新 WorldState 后正确变化。
- ENV-EMPTY-DEPARTMENT：真实 sample 入口，混合直接/worker 结果及原生 batch 中 worker 坏结果的整批回退。比较完整经验、怒气、票号、随机流、员工日记录和其他事实。
- ENV-EMPTY-PREPARATION：同一批对象经历空、混合、再次空和再次混合；完整观察与原生读取相同，观察和来源数组逐主体独立，只有空覆盖映射为共享只读值。全空首批不构造 worker，混合批只构造实际任务所需的 worker，后续重用。
- GROW-75：保留原有 worker 水权限、嵌套、覆盖预算和插入顺序、无水数值、旧楼层、自定义覆盖和坏结果回退；执行统计改为分别验证实际 worker 与直接观察。

这些是观察和采样业务边界，不证明移动、施工或临床全流程。局部计时使用固定合法存档的同状态 prepare/consume，交错比较原全部 worker 路径与新路径。不是完整 Simulation.step、整院性能或渲染基准。

运行：environment_empty_batch_runner.gd 后依次传输出 JSON 路径及上述 ENV-EMPTY 选择器；GROW-75 通过原 acceptance runner 显式选例。使用记录中的 Godot 4.7.2 与可写 XDG 目录。

`tools/performance/prepare_experience_sample_probe.py --project <冻结工程> --baseline-source <原批处理源码>` 准备可逐字节还原的局部 A/B 变体；不启动引擎。工程导入后，`experience_sample_probe.gd -- --input=<原160人输入> --output=<新JSON> --warmup=10 --iterations=200` 在三个独立服务对中交错比较 prepare，使用原四任务及完整观察。初始输入必须为真实 comprehensive160，事实不推进、不修改；同状态重复读取自然预热运行时缓存。结果逐次比较完整观察及工作数，前后核对完整事实和随机流。

计数变体另行执行，保留本次实际 seed 并在计时外按对象身份统计独立容器和条目。该数值覆盖结果与 seed 的可达容器，不是进程分配次数、内存占用或 GC 时间；局部耗时也不代替完整模拟步的性能验收。
