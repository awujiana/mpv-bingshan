# AGENTS.md

> 本文件供 **AI 编码 / 写作 agent** 阅读，用于了解本仓库的结构、约定与禁忌，从而在自动改动时保持风格一致。
> 人类贡献者请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 项目概述

- **名称**：uosc 弹幕（中文名）
- **GitHub 仓库名（英文名）**：uosc_danmaku
- **类型**：代码仓库（mpv Lua 脚本，MIT，**fork** 自 Tony15246/uosc_danmaku）
- **维护者**：awujiana（本 fork）；上游：Tony15246
- **一句话**：在 MPV 中基于 uosc UI 框架与弹弹play API 加载弹幕的扩展插件。

## 仓库结构

| 路径 | 用途 | 是否发布 |
| --- | --- | --- |
| `main.lua` | 入口：加载脚本、注册消息与菜单 | ✅ |
| `modules/` | 解析、渲染、哈希、菜单、配置、更新等模块 | ✅ |
| `apis/` | 弹幕源 API（`dandanplay.lua`、`extra.lua`） | ✅ |
| `sites/` | 站点适配（bilibili / bahamut / iqiyi / mgtv / tencentvideo / youku） | ✅ |
| `dicts/` | 简繁转换字表 | ✅ |
| `README.md` / `CONTRIBUTING.md` / `AGENTS.md` / `CHANGELOG.md` | 文档 | ✅ |
| `LICENSE` | MIT | ✅ |

## 必须遵守的约定

1. **命名规范（不缩写）**：Lua 模块 / 函数 `snake_case`、常量 `UPPER_SNAKE_CASE`，全拼无缩写、名称不重复。
2. **项目核心不变量**：
   - **加载顺序**：mpv 按脚本名顺序加载，本脚本早于大部分消费方；对外广播同时走**消息**与 **user-data** 两条（user-data 为持久状态，解决首次广播漏读）。
   - **换片清场**：`file-loaded` 时先 `clear_anime_info()` 再广播，避免外部读到上一部片的信息。
   - **path 校验**：广播消息带 `path`，接收方比对 `mp.get_property("path")`，防止异步时序误用陈旧数据。
   - **uosc 可选**：未安装 uosc 时通过 `mp.input`（mpv ≥ 0.39.0）渲染菜单。
   - **哈希匹配限制**：需 LuaJIT 或 Lua 5.2，**不支持 Lua 5.1**。
   - **API 代理**：默认走项目维护的代理，勿用于批量抓取。
3. **技术禁令**：不得破坏上游模块边界（本仓库为 fork，便于同步）；不得移除 `path` 校验；不得假设 uosc 一定存在。
4. **README 风格**：居中徽章 → 双名标题（中文 `<h1>` 在上、英文 `<h2>` 在下）→ 目录 → 正文 → 关联标签 → 底部三节。
5. **协议**：MIT（沿用上游；`LICENSE` 不许改动）。
6. **提交信息**：说明「做了什么 / 为什么」。
7. **提交身份**：`git config user.name` 必须是 `awujiana`，`user.email` 必须是 `bingshanlengtie@qq.com`。
8. **维护**：每次改动同步 `CHANGELOG.md`。

## 改动前检查

- `luac -p main.lua` 或 `luajit -bl main.lua > /dev/null` 做语法检查（无 luac 时至少用 mpv 加载验证）。
- 改渲染 / 菜单：在 mpv 中实际播放并触发弹幕搜索、开关、样式菜单验证。
- 改站点适配：确认对应站点的 URL 匹配与 API 返回仍可用。
- 改文档：同步 `CHANGELOG.md`。

## 不要做的事

- 不要移除对外广播的 `path` 校验与 `file-loaded` 清场。
- 不要假设 uosc 一定存在（必须保留 `mp.input` 回退）。
- 不要缩写命名、不要同名文件。
- 不要改动 `LICENSE`（MIT，上游版权）。
- 不要删除 `AGENTS.md` / `CONTRIBUTING.md` / `CHANGELOG.md`。
