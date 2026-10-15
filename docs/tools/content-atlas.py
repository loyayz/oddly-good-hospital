"""Render the source content catalogue for the offline design book."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / "data/content-catalog.json").read_text(encoding="utf-8"))
lines = ["# 完整内容索引", "", "本章直接列出设计数据中的内容定义。", ""]
for collection, rows in catalog.items():
    if isinstance(rows, dict) and rows and all(isinstance(row, dict) for row in rows.values()):
        rows = [{"id":identity, **row} for identity, row in rows.items()]
    if not isinstance(rows, list) or not rows or not isinstance(rows[0], dict):
        continue
    lines += [f"## {collection}", "", "| ID | 名称 | 定义 |", "| --- | --- | --- |"]
    for row in rows:
        identity = str(row.get("id", ""))
        name = str(row.get("name", row.get("title", "")))
        definition = json.dumps(row, ensure_ascii=False, separators=(",", ":"))
        cells = [identity, name, definition]
        lines.append("| " + " | ".join(cell.replace("|", "&#124;").replace("\n", "<br>") for cell in cells) + " |")
    lines.append("")
status = """# 设计数据与验收状态

内容索引由设计数据直接生成。功能专项用例按需求条款维护于tests/acceptance，执行入口为tests/run-acceptance.ps1；运行结果保留实际源码、引擎、隔离资料目录、退出码和逐项结论。

旧设计验算、历史阶段验证和性能基准脚本已移除。历史报告仅记录当时构建的观察，不代表当前版本通过；当前功能结果与性能、正式资产和发行验收分别记录。
"""
print(json.dumps({"atlas": "\n".join(lines), "report": status}, ensure_ascii=False))
