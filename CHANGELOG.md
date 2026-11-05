# 更新日志

本文件记录 `冰山 MPV 配置`（`awujiana/mpv-bingshan`）的重要变更，版本号遵循语义化版本 `MAJOR.MINOR.PATCH`。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

> 脚本自身的版本以各脚本文件头 `-- @version:` 为准；本文件按**配置仓库**的变更节点记录，
> 两者不是同一套版本号。

## [未发布]

### 改进

- `tools/sub-style-e2e.py` 适配**独立公开仓库**布局：`MPV_EXE` + `--config-dir` 隔离用户全局配置、临时复制 uosc、无 `uosc_staff_credits` 时把 7 条职员表 API 断言从期望表移除（不伪造 PASS）。
- `tools/sub-style-probe-api.lua` 新增 `SUBSTYLE_STAFF_API` 开关，让 API 探针可在只装了字幕脚本的环境运行。
- `tools/lua-syntax-check.lua` 改为按相对路径读取 Lua 文件，仓库位于中文目录（如 `D:\编程\...`）时不再报「无法读取文件」；生产端仍检查全部 196 个文件。
- `docs/uosc-subtitle-style-architecture.md` §19 的姊妹 API 链接改为公开绝对 URL，同步到独立脚本仓库后不会断链。
- 同步独立公开仓库 [awujiana/uosc_subtitle_style](https://github.com/awujiana/uosc_subtitle_style) 到 **v1.0.10**（脚本 / conf / 文档 / 全套测试工具 / `version.json` / README），并发 `v1.0.10` Release，消除「仓库最新 Release 仍是 v1.0.5」的版本落差。

## [1.0.0] - 2026-11-05

按 `awujiana-readme-style` 重做对外文档，并把 `main` 定稿为开箱即用发布树。

### 新增

- `docs/script-repositories.md`：**脚本仓库索引**。把原本散落在 README 的全部脚本 / 组件仓库链接集中成表格，按「awujiana 维护优先 → 上游 / 第三方 → 鸣谢 → 归属勘误」组织，并附上游 wiki 的 45 条差异勘误表。
- `CONTRIBUTING.md`（内联完整命名规范与门禁清单）、`AGENTS.md`（五段式，写清发布树、内封 ASS 通道、自更新三道闸门等真实不变量）、`CHANGELOG.md`、`LICENSE`（AGPL-3.0 全文）。
- `scripts/update_badges.py` / `scripts/badges.config.json`：徽章与语言导航的唯一数据源，支持 `--check`。

### 改进

- `README.md` 重写：`<p align="center">` 纯 HTML 居中徽章、**双名标题**（中文名「冰山 MPV 配置」+ GitHub 仓库名 `mpv-bingshan`）、语言切换徽章 + 文档导航、AI `[!WARNING]`、稳定锚点目录、底部强制三节（关联仓库 / 作者联系方式 / 开源协议）；脚本链接改为指向索引文档。
- `main` 改为**生成出来的干净配置树**：排除 `.workbuddy-ai`、Git 元数据、视频、`.gitattributes` / `.gitignore` / `.gitmodules`、`danmaku-search-history`、日志与运行时 json；`scripts/uosc_danmaku` / `scripts/uosc_staff_credits` 两个 gitlink 展开成实体脚本文件（498 个文件，gitlink 0）。
- `tools/publish-mpv-bingshan.py`：新增 `export` / `index` / `verify` 三个子命令，从 git object DB 导出，保证 UTF-8 + LF 不被 Windows CRLF 污染。
- 新增鸣谢：特别鸣谢 [dyphire/mpv-config](https://github.com/dyphire/mpv-config) 与 [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku)。

### 脚本版本进展（随配置仓库同步）

- `uosc_subtitle_style.lua` **v1.0.10**：上下黑边双对话字幕字号自适应判据（T55）、对外 API v1.0.0（状态广播 / 请求-响应 / 白名单动作转发）、T54 20 条 API 单测、真机 5f 组 21 条双脚本 API 断言；单测 328 条。
- `uosc_subtitle_style.lua` **v1.0.9**：修复「下移 / 整体缩放对带 `\pos` 内封 ASS 无效」——缩放与字号折成 `sub-ass-style-overrides/Fontsize`；新增 ±1px 连续字号微调并自动存入全局预设；`tools/sub-style-mkv-fixture.py` 用纯 Python 直接写最小 Matroska 供 E2E 复用。
- `uosc_subtitle_style.lua` **v1.0.8**：全部内封字幕轨逐轨检查（示例 MKV 有 42 条轨）；内封非标准配色一律套用黑白预设，灰色 `#8B8B8B` 报障彻底解决。
- `uosc_subtitle_style.lua` **v1.0.7**：上下内嵌黑边贴合，主 / 次对白分别进下 / 上黑边；`sub-margin-y` 取整并显式还原。
- `uosc_subtitle_style.lua` **v1.0.6**：`sub-ass-style-overrides` 改写 ASS 样式表，带 `\pos` 的顶部字幕 / signs 也能换字体转黑白；颜色命令加引号避免裸 `#` 被当注释；黑色与灰阶候选。
- `script-modules/updater.lua` **1.0.0**：同版本不更新、本地更新禁止降级，本地版本以文件头 `@version` 为准（三道闸门 + 报告层兜底）；抽成独立公开仓库 [awujiana/mpv-script-updater](https://github.com/awujiana/mpv-script-updater) 并发布 `v1.0.0` Release。
- `uosc_staff_credits` **v2.1**：新增对外 API（状态广播 / 请求-响应 / 白名单转发），快照逐字段白名单不泄漏 token。

### 修复

- 自更新器曾把本地 v1.0.7 覆盖回远端 v1.0.5，并弹「1.0.5 已更新 1.0.5 → 1.0.5」假提示；根因是把状态文件 `tag` 当本地版本，已修复并补 72 条单测 / 四轮真机 E2E / 10 个变异用例。
- 发布 zip 里两个 submodule 目录为空（gitlink 下载后无实体文件），已通过发布树实体化解决。

### 已知限制

- 脚本更新**只落盘、下次启动 mpv 生效**；看到旧版 OSD 文案需完全退出并重启播放器。
- 带 `\pos` 的 explicit ASS 位置不可调（保持原位），只能改尺寸 / 样式；强行 `strip` 会丢定位标签。
- 粗体与 `sub-ass-style-overrides` 是解码器级共享通道，主 / 次轨无法完全独立。
- 图形字幕（PGS/VOBSUB）不走 libass，样式 / 位置不可调。
- 独立公开仓库 `awujiana/uosc_subtitle_style` 的 Release 需与配置仓库脚本版本同步发布，否则新用户从该仓库下载会拿到旧版（自更新器本身不会降级）。

## 更早的版本

本仓库直到 `2026-11-05` 才引入 `CHANGELOG.md`。更早的工作（uosc 皮肤预览、Neve 播放器管理器、v1.0.5 及以前的字幕样式与自更新改动）散落在 git 历史与上游 [dyphire/mpv-config](https://github.com/dyphire/mpv-config) 中，此处不做追溯编造。
