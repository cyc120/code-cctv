# show your shit

一个 Codex 本地插件，用中文 `AI_WORKLOG.md` 把 AI 辅助编程过程摊开给人看。

它会记录：

- 实时进度和流程图
- 涉及文件
- 函数定位和代码片段说明
- 决策记录
- 验证结果
- 初学者核对清单
- 风险与最终总结

## 安装

把仓库放到本机插件目录：

```bash
mkdir -p ~/plugins
git clone https://github.com/YOUR_NAME/show-your-shit.git ~/plugins/show-your-shit
```

在个人插件市场文件 `~/.agents/plugins/marketplace.json` 中加入：

```json
{
  "name": "show-your-shit",
  "source": {
    "source": "local",
    "path": "./plugins/show-your-shit"
  },
  "policy": {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL"
  },
  "category": "Productivity"
}
```

然后安装插件：

```bash
codex plugin add show-your-shit@personal
```

新开 Codex 线程后使用：

```text
Use $show-your-shit，用中文记录本次改代码过程，并解释函数、代码片段和初学者核对步骤。
```

## 脚本

更新工作日志：

```bash
python3 scripts/update_worklog.py --workspace "$PWD" --language zh --status "侦察中" --focus "正在阅读项目上下文"
```

扫描 Python/JavaScript/TypeScript 函数位置：

```bash
python3 scripts/scan_code_map.py src tests
```

扫描脚本只生成行号骨架。真正给初学者看的解释，应该由 Codex 结合上下文补全。
