---
name: show-your-shit
description: 定位你的ai编程。Maintain a Chinese-first live Markdown monitor for AI-assisted programming work, especially when exposing progress through shit mountain code or messy legacy code. Use when the user wants to understand what Codex is doing, asks for a Chinese template, real-time visibility, progress monitoring, function locations, code-section explanations, beginner-friendly verification steps, an AI worklog, a flowchart, a decision log, a summary of coding work, or explicitly asks to use $show-your-shit while implementing, debugging, reviewing, testing, refactoring, or planning code changes.
---

# show your shit

Use this skill to make programming work observable. Keep a Markdown file named `AI_WORKLOG.md` in the current workspace root unless the user names another file. Prefer the Chinese template by default.

## Required behavior

1. At the start of the task, create or refresh `AI_WORKLOG.md` with the current goal, status, and a Mermaid flowchart.
2. During work, update the file after meaningful state changes:
   - starting context discovery
   - identifying the likely implementation path
   - editing files
   - running validation
   - finding a blocker, risk, or changed assumption
   - finishing the task
3. Keep the monitor factual and compact. Prefer specific files, commands, decisions, and evidence over broad narration.
4. For code changes or code explanation tasks, fill the function and code-section tables with file paths and line numbers. Explain what each function/section does in beginner-friendly Chinese.
5. Add beginner verification checks that tell the user exactly what to inspect, how to inspect it, and what result to expect.
6. Preserve visibility even when no code changes are made. Record analysis-only work, reviewed files, and conclusions.
7. End every monitored task by writing a final summary section with what changed, verification, residual risks, and next suggested action when useful.

## Markdown structure

Use these Chinese sections in this order:

````markdown
# show your shit

最后更新：YYYY-MM-DD HH:MM:SS CST
状态：侦察中 | 制定方案 | 修改中 | 验证中 | 阻塞 | 完成
当前关注：一句话说明我现在正在处理什么。

## 流程图

```mermaid
flowchart TD
    A["收到目标"] --> B["阅读上下文"]
    B --> C["制定改动方案"]
    C --> D["编辑文件"]
    D --> E["验证"]
    E --> F["总结"]
```

## 实时记录

| 时间 | 阶段 | 发生了什么 | 证据 |
| --- | --- | --- | --- |

## 涉及文件

| 文件 | 用途 | 状态 |
| --- | --- | --- |

## 函数定位

| 位置 | 函数 | 作用 | 怎么核对 |
| --- | --- | --- | --- |

## 代码片段说明

| 位置 | 代码片段 | 这段在做什么 | 初学者核对点 |
| --- | --- | --- | --- |

## 决策记录

| 决策 | 原因 | 取舍 |
| --- | --- | --- |

## 验证结果

| 检查 | 结果 | 备注 |
| --- | --- | --- |

## 初学者核对清单

| 要核对什么 | 怎么核对 | 预期结果 |
| --- | --- | --- |

## 风险与待确认

- 暂无。

## 最终总结

待完成。
````

Keep the Mermaid graph valid. Use quoted node labels and simple ASCII identifiers. Update the graph when the workflow branches, blocks, or skips a phase.

A reusable Chinese template is bundled at `assets/worklog-template.zh-CN.md`.

## Script

Use the bundled script when helpful:

```bash
python3 scripts/update_worklog.py --workspace "$PWD" --status "侦察中" --focus "正在阅读项目上下文" --note "已建立工作日志" --phase "开始" --evidence "用户要求监控"
```

Use `--language zh` explicitly when the user asks for Chinese, though Chinese is the script default:

```bash
python3 scripts/update_worklog.py --workspace "$PWD" --language zh --status "侦察中" --focus "正在阅读项目上下文" --phase "开始" --note "已建立中文监控文件" --evidence "用户要求中文模板"
```

The script is deterministic and can initialize the file, append live notes, record touched files, decisions, validation results, risks, and final summaries. It rewrites the monitored sections between stable markers, so it is safer than ad hoc Markdown editing for repeated updates. It can also parse old English headings and then re-render the monitor in Chinese.

Add beginner-facing code maps with:

```bash
python3 scripts/update_worklog.py --workspace "$PWD" --language zh --function "src/app.py:42|load_config|读取配置文件并返回字典|打开该行，确认调用处传入的路径存在，并运行相关测试" --segment "src/app.py:40-58|配置加载逻辑|把 JSON 文件读入内存，缺失时给默认值|改一个临时配置值，确认程序读取结果变化"
```

For Python, JavaScript, and TypeScript projects, generate a first-pass function skeleton with:

```bash
python3 scripts/scan_code_map.py src tests
```

Treat scanner output as a locator scaffold only. Replace the placeholder purpose and verification text with context-aware Chinese explanations before finalizing the worklog.

Before using the script, inspect `scripts/update_worklog.py` if behavior changes are needed. Otherwise it can be executed directly.

## Cadence

Update the monitor before user-visible tool work begins when feasible. For longer tasks, update it at least every few tool batches or whenever a user would otherwise be left guessing what is happening.

Do not claim that the monitor is automatic background telemetry. It is an explicit work protocol maintained by Codex during the task.
