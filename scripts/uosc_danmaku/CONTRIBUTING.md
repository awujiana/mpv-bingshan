<div align="center">

<p align="center">
  <a href="LICENSE"><img alt="协议 MIT" src="https://img.shields.io/badge/协议-MIT-green?style=flat"></a>
  <a href="CONTRIBUTING.md"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat"></a>
</p>

<h1>贡献指南</h1>

<strong>欢迎参与「uosc 弹幕」的共建</strong>

</div>

---

感谢你关注 **uosc_danmaku** 并愿意贡献。本项目是 [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) 的 fork，上游采用 MIT 协议；本 fork 只做增量修改。

> 本 fork 维护者：awujiana ｜ 上游作者：Tony15246 ｜ 协议：MIT

## 📚 目录

- [我能如何参与](#我能如何参与)
- [提交 Issue 前](#提交-issue-前)
- [提交 Pull Request 前](#提交-pull-request-前)
- [命名规范（不缩写）](#命名规范不缩写)
- [代码约定](#代码约定)
- [行为准则](#行为准则)
- [许可证](#许可证)

## 🤝 我能如何参与

- **提交 Issue**：反馈本 fork 新增功能的 Bug、上游兼容性问题或文档错误。
- **完善文档**：改进 README 与配置项说明。
- **改进插件**：优化弹幕解析、渲染与菜单交互。
- **向上游反馈**：属于上游的问题请优先提到上游仓库。

## 🐞 提交 Issue 前

1. 先搜索确认问题未被重复提出。
2. 说明 mpv 版本（`mpv --version`）、是否安装 uosc、操作系统。
3. 说明弹幕源（弹弹play / 巴哈姆特 / bilibili 等）与复现步骤。
4. 附上控制台日志（`mpv --msg-level=all=v` 或脚本 `log`）。

## 🔀 提交 Pull Request 前

1. 从 `main` 切出特性分支，命名如 `fix/render-overlap` 或 `docs/config`。
2. 遵循本仓库的 README 输出规范：居中徽章、双名标题、底部三节。
3. 命名一律全拼、禁止缩写、名称不重复。
4. 提交信息清晰说明「做了什么 / 为什么」。

## 📝 命名规范（不缩写）

### 总则

- **一律全拼，禁止缩写**：`cfg`→`config`、`msg`→`message`、`err`→`error`、`idx`→`index`。
- **名称不重复**：同目录文件名唯一（大小写不敏感）；同模块符号唯一。
- **名称即语义**：禁止 `utils`、`common`、`misc`、`temp` 等泛化名。

### 文件命名

| 类型 | 规则 | 示例 |
| --- | --- | --- |
| Lua 模块 | `snake_case.lua` | `main.lua`、`render.lua` |
| 站点适配 | `snake_case.lua`（站点名） | `bilibili.lua`、`bahamut.lua` |
| 文档 | `kebab-case.md` | `readme.md` |

### 函数命名

- **Lua 函数 / 变量**：`snake_case`，动词开头，全拼，如 `load_danmaku`、`render_comment`。
- **常量**：`UPPER_SNAKE_CASE`。
- 同一模块内不得出现同名函数；不同模块同名须加限定词。

## 📋 代码约定

- 正文以简体中文为主，专有名词（uosc / JSONL / LuaJIT）保留英文原文。
- 代码片段使用围栏代码块并标注语言。
- **兼容性**：哈希匹配功能需 mpv 基于 LuaJIT 或 Lua 5.2 构建，不支持 Lua 5.1。
- **不破坏上游结构**：本 fork 的增量修改应与上游模块边界保持一致，便于后续同步。

## 🤗 行为准则

请保持友善、专业、就事论事。尊重不同经验水平的贡献者，不人身攻击、不贬低他人工作。

## 📄 许可证

本项目基于 **MIT** 协议（沿用上游）。向本仓库提交贡献，即表示你同意以 MIT 协议发布你的贡献。详见 [LICENSE](LICENSE)。

[![MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
