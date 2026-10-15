"""Validate original kernel capture records and report each population separately."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[math.ceil(len(ordered) * fraction) - 1] if ordered else None


def meets_targets(summary, targets):
    return bool(summary["formal_capture"]
                and summary["step"].get("p95_ms", math.inf) <= targets["sim_step_p95_ms"]
                and summary["step"].get("p99_ms", math.inf) <= targets.get("sim_step_p99_ms", math.inf)
                and summary["step"].get("max_ms", math.inf) <= targets.get("sim_step_ordinary_max_ms", math.inf)
                and summary["speed_ratio"] >= targets["sim_speed_ratio_min"])


def validate_group(path: Path):
    summary = read(path / "summary.json")
    validation = read(path / "validation.json")
    execution = read(path / "execution.json")
    steps, commands, processes = [], [], []
    errors = []
    for line in (path / "raw.ndjson").read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row["kind"] == "step":
            steps.append(row)
        elif row["kind"] == "command":
            commands.append(row)
        else:
            errors.append("unknown_raw_record_kind")
    for line in (path / "process.ndjson").read_text(encoding="utf-8").splitlines():
        processes.append(json.loads(line))
    if not validation["valid"]:
        errors.append("runtime_script_errors")
    if len(steps) != summary["executed_ticks"] or len(steps) != summary["step"]["count"]:
        errors.append("raw_tick_count_differs")
    if [row["sim_tick"] for row in steps] != list(range(summary["first_tick"] + 1, summary["last_tick"] + 1)):
        errors.append("ticks_missing_or_duplicated")
    if not steps or percentile([row["duration_usec"] for row in steps], .95) / 1000 != summary["step"]["p95_ms"]:
        errors.append("raw_percentile_differs")
    if steps:
        durations = [row["duration_usec"] for row in steps]
        if percentile(durations, .99) / 1000 != summary["step"]["p99_ms"] or max(durations) / 1000 != summary["step"]["max_ms"]:
            errors.append("raw_tail_statistics_differ")
        if not math.isclose(sum(durations) / len(durations) / 1000, summary["step"]["mean_ms"], rel_tol=1e-12):
            errors.append("raw_mean_differs")
        if summary["fixture"]["fixture"] == "kernel-mobile-and-surgery-v2":
            for field, key in (("walking_bodies", "walking_bodies_per_step"), ("pending_routes", "pending_routes_per_step")):
                values = [row.get(field) for row in steps]
                if any(not isinstance(value, int) or value < 0 for value in values):
                    errors.append(f"{field}_samples_missing")
                    continue
                expected = {"count": len(values), "min": min(values), "max": max(values),
                            "p05": percentile(values, .05), "p50": percentile(values, .5),
                            "p95": percentile(values, .95), "mean": sum(values) / len(values)}
                if any(not math.isclose(expected[name], summary.get(key, {}).get(name, math.inf), rel_tol=1e-12)
                       for name in expected):
                    errors.append(f"{field}_summary_differs")
            if any(row.get("walking_bodies", math.inf) > row["present_actors"] or row.get("pending_routes", math.inf) > row["moves"] for row in steps):
                errors.append("movement_population_inconsistent")
    if not commands or len(commands) != summary["command_boundary"]["count"]:
        errors.append("command_samples_missing")
    elif percentile([row["duration_usec"] for row in commands], .95) / 1000 != summary["command_boundary"]["p95_ms"]:
        errors.append("raw_command_percentile_differs")
    if not processes:
        errors.append("OS_resource_samples_missing")
    if any(row["path_refused"] for row in steps):
        errors.append("fixture_path_refused")
    if any(not row["result"]["accepted"] for row in commands) or summary["rejected_commands"]:
        errors.append("fixture_command_rejected")
    if summary["formal_capture"] and (summary["debug_build"] or summary["warmup_real_seconds"] < 60 or summary["sample_real_seconds"] < 600):
        errors.append("formal_conditions_missing")
    calculated_ratio = summary["executed_ticks"] / (summary["sample_real_seconds"] * 10 * summary["speed"])
    if not math.isclose(calculated_ratio, summary["speed_ratio"], rel_tol=1e-12):
        errors.append("raw_speed_ratio_differs")
    threshold_passed = meets_targets(summary, summary["targets"])
    if threshold_passed != summary["passed"]:
        errors.append("reported_threshold_result_differs")
    if execution["exit_code"] != (0 if not summary["formal_capture"] or threshold_passed else 1):
        errors.append("unexpected_execution_exit_code")
    if any(row["present_actors"] != summary["actors"] for row in steps):
        # Departure is physical in phase 4; its replacement arrives at the next boundary.
        if any(row["present_actors"] not in (summary["actors"], summary["actors"] - 1) for row in steps):
            errors.append("unexpected_actual_population")
    summary["evidence_valid"] = not errors
    summary["evidence_errors"] = errors
    summary["exit_code"] = execution["exit_code"]
    summary["OS_resources"] = {
        "observed_peak_working_set_bytes": max((r["working_set_bytes"] for r in processes), default=None),
        "observed_peak_private_commit_bytes": max((r["private_commit_bytes"] for r in processes), default=None),
        "lifetime_peak_working_set_bytes": max((r["lifetime_peak_working_set_bytes"] for r in processes), default=None),
        "cadence_seconds": 1,
        "includes_warmup": True,
        "graphics": None,
    }
    summary["raw_sha256"] = hashlib.sha256((path / "raw.ndjson").read_bytes()).hexdigest()
    summary["evidence_sha256"] = {name: hashlib.sha256((path / name).read_bytes()).hexdigest()
                                  for name in ("capture-start.json", "summary.json", "validation.json", "execution.json",
                                               "process.ndjson", "final-world.json", "stdout.log", "stderr.log")}
    summary["raw_path"] = str(path / "raw.ndjson")
    summary["passed"] = bool(summary["passed"] and summary["evidence_valid"])
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--actors", type=int, nargs="+", choices=(160, 320, 640), default=[160, 320, 640])
    parser.add_argument("--targets", type=Path, help="Re-evaluate captured data against current balance.json without changing capture results.")
    args = parser.parse_args()
    requested_actors = sorted(set(args.actors))
    groups = [validate_group(path.parent) for path in sorted(args.input.glob("actors-*/summary.json"))
              if read(path)["actors"] in requested_actors]
    evaluation = read(args.targets)["performance_targets"] if args.targets else None
    for row in groups:
        row["evaluation_targets"] = evaluation["metrics"] if evaluation else row["targets"]
        row["evaluation_passed"] = row["evidence_valid"] and meets_targets(row, row["evaluation_targets"])
    models = []
    for speed in (1, 3):
        rows = {r["actors"]: r for r in groups if r["speed"] == speed and r["formal_capture"] and r["evidence_valid"]}
        if not {160, 320, 640} <= rows.keys():
            continue
        slope = (rows[320]["step"]["mean_ms"] - rows[160]["step"]["mean_ms"]) / 160
        intercept = rows[160]["step"]["mean_ms"] - 160 * slope
        predicted = intercept + 640 * slope
        measured = rows[640]["step"]["mean_ms"]
        models.append({"speed": speed, "cost": "mean_complete_step_ms", "calibration_actors": [160, 320],
                       "intercept_ms": intercept, "ms_per_actor": slope, "holdout_actors": 640,
                       "predicted_640_ms": predicted, "measured_640_ms": measured,
                       "holdout_relative_error": (predicted - measured) / measured,
                       "valid_range": [160, 640], "scope": "same mobile-and-surgery fixture only; no percentile prediction"})
    formal_keys = {(r["actors"], r["speed"]) for r in groups if r["formal_capture"] and r["evidence_valid"]}
    complete = formal_keys == {(count, speed) for count in requested_actors for speed in (1, 3)}
    full_matrix_complete = formal_keys == {(count, speed) for count in (160, 320, 640) for speed in (1, 3)}
    report = {"schema_version": 1, "stage02_status": "performance_measurement_skipped", "stage03_groups": groups,
              "requested_actors": requested_actors, "deferred_actors": sorted({160, 320, 640} - set(requested_actors)),
              "requested_matrix_complete": complete, "formal_matrix_complete": full_matrix_complete,
              "performance_passed": complete and all(r["evaluation_passed"] for r in groups),
              "evaluation_budget": evaluation.get("simulation_budget") if evaluation else None,
              "evaluation_source_sha256": hashlib.sha256(args.targets.read_bytes()).hexdigest() if args.targets else None,
              "cost_model_status": "calibrated" if models else "insufficient_measured_populations",
              "cost_models": models, "build_identity": read(args.input / "build-identity.json"),
              "environment": read(args.input / "environment.json"),
              "missing": ["presented_frames", "GPU", "graphics_resources", "save_restore", "full_daily_systems", "multiple_clinical_stations", "isolated_log_serialization_cost"]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown:
        population_label = "/".join(str(count) for count in requested_actors)
        result_label = "通过" if report["performance_passed"] else "未达标"
        lines = [f"# 第三阶段：{population_label}人内核Release实测", "", f"第二阶段性能检测未执行。第三阶段本次测量范围为{population_label}人、1×/3×正式内核，采集有效性与性能达标分别判定；本次性能结果：**{result_label}**。", "",
                 "## 实测条件", "", f"原始证据目录：`{args.input.as_posix()}`。构建与源文件哈希、设备、电源和后台进程记录保存在同目录。每组独立预热60现实秒、采样600现实秒；步耗时采用单调时钟和最近秩分位。", "",
                 f"夹具保持{population_label}名实际在院身体，使用四份96×96合法移动楼层和原手术布局，保留10000层稀疏结构。额外居民沿真实路线持续移动，一个D23病例执行原接待、诊断、手术、护理和结算流程；患者实际离院后的下一边界补入一名移动居民。单个病例完成后不持续生成新病例，本次结果不能代表多站点临床满载。逻辑记录数与实际在院数分别记录。", "",
                 "夹具协议为kernel-mobile-and-surgery-v2：分散场景额外居民沿32格路线往返，密集诊断沿8格路线往返。夹具在步前只提出移动目标，路径搜索由正式step中的全院FIFO队列派发；临床派发、实际移动和安全检查均在完整step内。与旧版1格往返夹具的结果不能直接作为同负载优化对比。", "",
                 "每步分别记录实际地面位置发生变化的身体数及待寻路请求数，移动记录数包含等待中的请求。人数观察、原始日志和OS观察计入实际推进速度；人数观察与计时探针另记开销，日志序列化和写入开销尚未独立量化。无窗口采集没有呈现帧或GPU指标。", "",
                 f"## {len(groups)}组正式结果", "", "| 在院身体 | 速度 | step P95 / P99（ms） | step最大（ms） | 实际tick | 速度比例 | 命令P95（ms） | 工作集峰值（MiB） | 私有提交峰值（MiB） | 结果 |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for row in groups:
            result = "通过" if row["evaluation_passed"] else ("未达标" if row["formal_capture"] and row["evidence_valid"] else "证据无效/诊断")
            memory = row["OS_resources"]["observed_peak_working_set_bytes"]
            command_p95 = row["command_boundary"].get("p95_ms")
            command_text = f"{command_p95:.3f}" if command_p95 is not None else "缺失"
            memory_text = f"{memory / 1048576:.1f}" if memory is not None else "缺失"
            private = row["OS_resources"]["observed_peak_private_commit_bytes"]
            private_text = f"{private / 1048576:.1f}" if private is not None else "缺失"
            lines.append(f'| {row["actors"]} | {row["speed"]}× | {row["step"]["p95_ms"]:.3f} / {row["step"]["p99_ms"]:.3f} | {row["step"]["max_ms"]:.3f} | {row["executed_ticks"]} | {row["speed_ratio"]:.5f} | {command_text} | {memory_text} | {private_text} | {result} |')
        metrics = groups[0]["evaluation_targets"] if groups else {}
        budget_text = f'完整步目标P95≤{metrics.get("sim_step_p95_ms", "缺失")}ms'
        if "sim_step_p99_ms" in metrics:
            budget_text += f'、P99≤{metrics["sim_step_p99_ms"]}ms、普通最大≤{metrics["sim_step_ordinary_max_ms"]}ms'
        lines += ["", budget_text+"；实际速度至少达到所选速度的99%。捕获时目标和退出码保持原值，当前评估另列。表内所有原始step连续、无跳tick且命令样本存在才视为有效证据。未达标组不以实际速度通过代替步耗时通过。工作集和私有提交为每秒OS观察峰值，包含预热与采样；进程生命周期工作集峰值另存结构化报告。", "",
                  "## 实际工作量与工具开销", "", "| 身体 / 速度 | 步样本 | 命令样本 | 路径请求 | 移动记录峰值 | 实际行走均值 / P05 | 待寻路均值 / 峰值 | 同时临床服务峰值 | 治疗尝试数 | 结束病例阶段 | 夹具准备P95（ms） | 人数观察P95（ms） |", "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for row in groups:
            walking = row.get("walking_bodies_per_step", {})
            pending = row.get("pending_routes_per_step", {})
            walking_text = f'{walking["mean"]:.1f} / {walking["p05"]}' if "mean" in walking else "未测"
            pending_text = f'{pending["mean"]:.1f} / {pending["max"]}' if "mean" in pending else "未测"
            observer = row.get("population_observer", {}).get("p95_ms")
            observer_text = f"{observer:.3f}" if observer is not None else "未测"
            lines.append(f'| {row["actors"]} / {row["speed"]}× | {row["step"]["count"]} | {row["command_boundary"]["count"]} | {row["path_requests"]} | {row["peak_moves"]} | {walking_text} | {pending_text} | {row["peak_clinical_sessions"]} | {row["actual_attempts"]} | {row["clinical_phase"]} | {row["fixture_dispatch"]["p95_ms"]:.3f} | {observer_text} |')
        lines += ["", "命令表记录实际执行边界的成本，输入到画面反馈的响应时间保持未测。夹具准备分位不与完整step分位相加；它与采集开销均包含在实际速度判定中。计时探针采用微秒分辨率，0表示未分辨出差值，不代表零开销。", "",
                  "## 成本模型与缺失项", ""]
        if models:
            lines += ["模型以160/320的完整步均值校准，640作为独立外推检验；只用于相同夹具和160至640范围，不预测P95，不将模块分位相加。截距是线性拟合参数，不代表另行测量的固定开销。", "",
                      "| 速度 | 拟合截距（ms） | 每身体成本（ms） | 640预测均值（ms） | 640实测均值（ms） | 相对误差 |", "| --- | --- | --- | --- | --- | --- |"]
        else:
            lines += ["当前只有已列人数的有效采样，未形成160/320校准及640外推检验的成本模型。模型系数和未测人数预测保持缺失。", ""]
        for model in models:
            lines.append(f'| {model["speed"]}× | {model["intercept_ms"]:.4f} | {model["ms_per_actor"]:.6f} | {model["predicted_640_ms"]:.3f} | {model["measured_640_ms"]:.3f} | {model["holdout_relative_error"]:.1%} |')
        lines += ["", "到访容量、候诊离院、环境脏区、互动候选、多临床站点和全部正式资源尚未接入本夹具。绘制/姿态、图形分配、保存恢复的大世界峰值及完整游戏性能保持缺失；最晚接入阶段由`tools/benchmarks/cost-coverage.json`记录。", "",
                  "## 运行与收尾", "", "第二阶段提供基准准备、72组显示计划、原始记录、OS资源采集、报表和成本接入清单；性能检测跳过。第三阶段提供类型化世界/命令/结果/事实事件、稳定十阶段、会话播放控制、命令原子失败、账目幂等、独立回放及规则运行器。", "",
                  "空间优化以完整身体包络建立分桶索引，同步真实移动、承托、乘梯和离院。采集工具拒绝有Godot运行错误的记录；完整事实及随机流的一致性由独立规则验证记录。", "",
                  "性能采集和规则验证分别记录。本采集工具核对Release性能数据；医院规则、保存、安装与绘制证据由相应验证入口记录。", ""]
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"groups": len(groups), "requested_matrix_complete": complete, "formal_matrix_complete": full_matrix_complete,
                      "performance_passed": report["performance_passed"], "report": str(args.output)}, ensure_ascii=False))
    return 0 if complete and all(r["evidence_valid"] for r in groups) and groups else 2


if __name__ == "__main__":
    raise SystemExit(main())
