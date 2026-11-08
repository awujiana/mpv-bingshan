# AGENTS.md

> 本文件供 **AI 编码 / 写作 agent**（如 WorkBuddy、Copilot、Claude）阅读，用于了解本仓库的结构、约定与禁忌，从而在自动改动时保持风格一致。
> 人类贡献者请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)（含完整命名规范）。

## 项目概述

- **名称**：冰山 MPV 配置（中文名）
- **GitHub 仓库名（英文名）**：`mpv-bingshan`
- **类型**：代码仓库（AGPL-3.0；第三方脚本 / 着色器保留各自协议）
- **维护者**：awujian（GitHub `awujiana`）
- **一句话**：一套基于 [dyphire/mpv-config](https://github.com/dyphire/mpv-config) 的 Windows mpv 开箱即用配置，核心自研能力是内封字幕分轨样式 / 上下黑边贴合、双脚本对外 API，以及「同版本不更新、绝不降级」的静默自更新。

## 仓库结构

| 路径 | 用途 | 是否发布 |
| --- | --- | --- |
| `mpv.conf` / `input.conf` / `menu.conf` / `manager.json` | 播放器主配置与中文菜单化键位 | ✅ |
| `scripts/` | mpv Lua 脚本目录（含两个 submodule 展开后的实体文件） | ✅ |
| `scripts/uosc_subtitle_style.lua` | **核心自研脚本**，文件头 `-- @version: 1.0.15` 是本地版本依据 | ✅ |
| `scripts/uosc_updater.lua` | 自更新驱动；只做调度与 OSD，核心逻辑在 `script-modules/updater.lua` | ✅ |
| `scripts/uosc_danmaku/` / `scripts/uosc_staff_credits/` | 两个 submodule（开发态是 gitlink，发布态展开为实体文件） | ✅ 实体文件 |
| `script-modules/updater.lua` | 公共自更新模块副本，与 `awujiana/mpv-script-updater` **字节一致** | ✅ |
| `script-opts/` | 各脚本 conf（mpv **不支持行尾注释**） | ✅ |
| `docs/` | 架构、API 契约、**脚本仓库索引**（`script-repositories.md`） | ✅ |
| `tools/` | 单测、真机 E2E、探针、夹具、门禁、`publish-mpv-bingshan.py` | ✅ |
| `scripts/update_badges.py` / `scripts/badges.config.json` | 徽章与语言导航唯一数据源（mpv 不加载 `.py` / `.json`） | ✅ |
| `README.md` / `CONTRIBUTING.md` / `AGENTS.md` / `CHANGELOG.md` / `LICENSE` | 对外说明、贡献、AI 约定、更新日志、AGPL-3.0 全文 | ✅ |
| `LICENSE.MD` | 上游对第三方脚本 / 着色器协议的说明（**不是**协议全文） | ✅ |
| `.workbuddy-ai/` / `.gitattributes` / `.gitignore` / `.gitmodules` / 视频 / 日志 / 运行时 json | 开发态文件，发布树刻意排除 | ❌ |

> `main` 分支是**生成出来的发布树**：由 `tools/publish-mpv-bingshan.py` 按排除清单重写 Git 索引产生，磁盘上的开发态文件用 `.git/info/exclude` 隐藏。改动发布内容后必须 `verify`，不要直接把开发态文件加进索引。

## 必须遵守的约定

1. **命名规范（不缩写）**：项目 `kebab-case`、文件 / 函数 / 组件全拼无缩写、名称不重复、Lua 脚本 `snake_case.lua`、`script-message` 入口 `kebab-case`。详见 `CONTRIBUTING.md`。
2. **项目核心不变量 —— 版本只认 `@version`**：`version_from_text()` 只接受文件头 8 KB 内**行首独立成行**的 `-- @version: X.Y.Z`；`uosc-updater-state.json` 的 `tag` 只表示「上次从远端装了什么」。历史上把它当本地版本导致 2026-11-05「1.0.5 已更新 1.0.5 → 1.0.5」假提示与「本地 v1.0.7 被远端 v1.0.5 降级」两次事故，禁止复现。
3. **项目核心不变量 —— 自更新三道闸门**：检查前 `local_ver >= remote_ver` 不下载；旧脚本无标记且状态同 tag（**必须本地文件存在**）不重装；安装前 `from_ver >= remote_ver` 丢弃下载物。改 `script-modules/updater.lua` 必须同步公共仓库 `awujiana/mpv-script-updater` 并保持两端字节一致。
4. **项目核心不变量 —— 内封 ASS 通道**：带 `\pos` 的 explicit ASS 事件对 `sub-pos` / `sub-scale` / `sub-font-size` / `sub-margin-y` **全部豁免**；样式只能写 `sub-ass-style-overrides` 的 `FontName` / `PrimaryColour` / `OutlineColour` / `Fontsize`（颜色 `&H00BBGGRR`），缩放与字号折成 `Fontsize` 并把两轨 `sub-scale` 归 1 防双叠加。**禁止**用 `ScaleX/ScaleY` 做倍率（125% 起字幕消失），**禁止**用 `strip` 重写事件（会丢 `\pos`）。
5. **技术禁令**：绝不轻易重建字幕解码器（会打断内封字幕包流，表现为「字幕定住一句」）；稳态编辑只写属性 + `show-text ' ' 60` 触发 `configure_ass`；`sub-margin-y` 是 INT 且不在 `reset-on-next-file`，贴合结束必须显式还原；`user-data` 是 node 属性，读取必须 `native`；`script-message-to` 参数含 `#RRGGBB` 必须加引号；`script-opts/*.conf` 禁止行尾注释；禁止 `load-script` 热重载；禁止对脏工作区 `reset --hard`；禁止保留 `.bak`。
6. **对外 API 边界**：`uosc_subtitle_style` 与 `uosc_staff_credits` 的 API 版本均为 `1.0.0`，只做只读状态快照 + 白名单动作转发，`api` 自身不得进入 `call` 白名单；`user-data` 快照不得泄漏 `bangumi_token` / 原始 opts / 原始 API 响应 / 缓存正文；旧 `script-message` 入口参数与副作用必须原样保留。
7. **README 风格**：顶部 shields.io 徽章（`<p align="center">` 纯 HTML 居中）→ **双名标题**（中文 `<h1>`「冰山 MPV 配置」+ `<h2>` `mpv-bingshan`）→ 语言切换徽章 + 文档导航 → `[!WARNING]` AI 声明 → 目录 → 正文 → 底部三节（关联仓库 / 作者联系方式 / 开源协议）。
8. **脚本链接集中**：所有脚本 / 组件仓库链接一律写进 `docs/script-repositories.md` 的表格，awujiana 维护仓库排在上游 / 第三方之前；README 只留该文档的入口链接，不要把仓库表格散落回 README。
9. **协议**：代码仓库 AGPL-3.0，`LICENSE` 全文不许改；第三方脚本 / 着色器保留各自协议，见 `LICENSE.MD`，不得宣称本仓库对上游重新授权。
10. **文档索引**：README「文档」节只列操作 / 契约文档；测试脚本默认只在「测试与门禁」节一句话带过。
11. **提交信息**：说明「做了什么 / 为什么」；发布树提交用 `chore(release):` 前缀并说明排除清单。
12. **提交身份**：`git config user.name=awujian`、`user.email=bingshanlengtie@qq.com`。旧邮箱一旦进入提交元数据，「改文件」和 `force push` 都清不掉——普通仓库要删库重建，fork 只能请 GitHub Support 做 GC。
13. **徽章由脚本生成**：`<!-- badges:start -->` / `<!-- badges:end -->`、`<!-- language-nav:start -->` / `<!-- language-nav:end -->` 之间禁止手改；改配置后跑 `python scripts/update_badges.py`，提交前 `--check` 必须通过。
14. **维护**：每次改动同步 `CHANGELOG.md`；改脚本功能同步文件头 `@version` + 独立公开仓库 `awujiana/uosc_subtitle_style` 的 `version.json` / Release；改发布内容同步本地镜像 `D:/Software/PlayerSoftware/MPV/mpv-Bingshan`（`master`）。

## 改动前检查

- **改 Lua 脚本**：`../luajit.exe tools/lua-syntax-check.lua`（222 个文件、`FAIL 0`），再跑 `../luajit.exe tools/sub-style-test.lua`（`pass=446 fail=0 ALL_OK`）。
- **改 conf**：`python tools/sub-style-conf-verify.py`（`SUMMARY sub-style-conf-verify PASS fail=0`）。
- **改样式 / 黑边 / API**：加跑 `/c/Python314/python.exe tools/sub-style-e2e.py`（`SUMMARY sub-style-e2e PASS fail=0`、325 条 PASS，含 5m 画面边界守护两轮各 18 项）；新增行为必须同时新增单测与真机断言。
- **改自更新**：`../luajit.exe tools/updater-test.lua`（`PASS=72 FAIL=0`）、`/c/Python314/python.exe tools/updater-e2e.py`、`/c/Python314/python.exe tools/updater-mutation-test.py`（`ALL_KILLED` 且源文件按字节还原）。
- **改 README / 文档**：对照技能 `awujiana-readme-style`，核对徽章、双名标题、锚点、底部三节；跑 `python scripts/update_badges.py --check`。
- **改发布内容**：`/c/Python314/python.exe tools/publish-mpv-bingshan.py verify` → `VERIFY excluded_in_index=0 gitlinks=0`、`VERIFY OK`。
- **提交**：`git status` 确认不含视频、`*.log`、运行时 json、`danmaku-search-history.json`、`.workbuddy-ai/`、`.gitmodules`、submodule 内 Git 元数据与变异残留。

## 不要做的事

- 不要手写 `⚠️ Warning` 代替 GitHub 警示块 `> [!WARNING]`。
- 不要把 `uosc-updater-state.json` 的 `tag` 当本地版本，不要弱化三道闸门中的任何一道，不要弹「X 已更新 X → X」。
- 不要用缩写命名、同名文件（含仅大小写不同）或数字后缀解决冲突。
- 不要在标题用 VS16 变体 emoji（`⚠️` / `🖼️`），会破坏自动锚点。
- 不要把脚本仓库链接表格写回 README；它们只属于 `docs/script-repositories.md`。
- 不要把排除清单里的开发态文件、视频、日志、运行时 json 提交进 `main` 发布树，也不要把 submodule 的 gitlink 推上发布树。
- 不要手改徽章生成区块，也不要绕过脚本直接改徽章链接。
- 不要删除 `AGENTS.md` / `CONTRIBUTING.md` / `CHANGELOG.md`；它们承载协作与 AI 约定。
- 不要在 `script-opts/*.conf` 值后面写注释，不要用 `sub-reload` 重建解码器来「刷新」样式。
- 不要改已发布 Release tag 的资产；撤回发布应发更高版本。
