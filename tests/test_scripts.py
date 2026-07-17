from __future__ import annotations

import tempfile
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import update_worklog  # noqa: E402


class WorklogTests(unittest.TestCase):
    def test_escaped_pipe_and_backslash_round_trip(self) -> None:
        value = r"C:\temp|source.py"
        encoded = update_worklog.escape_cell(value)
        self.assertEqual(update_worklog.split_escaped_values(encoded), [value])

    def test_table_parser_preserves_escaped_cell(self) -> None:
        lines = [
            "## 模块图谱",
            "",
            "| 模块 | 相关代码 | 职责 | 依赖 | 风险 | 怎么核对 |",
            "| --- | --- | --- | --- | --- | --- |",
            r"| 模块 | C:\temp\|src.py | 读取代码 | 暂无 | 暂无 | 打开文件 |",
            "",
            "## 流程图",
        ]
        rows = update_worklog.parse_table(lines, ["模块图谱"], 6)
        self.assertEqual(rows[0][1], r"C:\temp|src.py")

    def test_atomic_write_replaces_content_and_cleans_temp(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "AI_WORKLOG.md"
            path.write_text("旧内容", encoding="utf-8")
            update_worklog.atomic_write_text(path, "新内容")
            self.assertEqual(path.read_text(encoding="utf-8"), "新内容")
            self.assertEqual(list(path.parent.glob(".AI_WORKLOG.md.*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
