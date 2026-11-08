# 更新日志

本文件记录 `冰山 MPV 配置`（`awujiana/mpv-bingshan`）的重要变更，版本号遵循语义化版本 `MAJOR.MINOR.PATCH`。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

> 脚本自身的版本以各脚本文件头 `-- @version:` 为准；本文件按**配置仓库**的变更节点记录，
> 两者不是同一套版本号。

## [未发布]

### 修复（v1.0.15）：对话字幕不得越过画面边界

- `uosc_subtitle_style.lua` **v1.0.14 → v1.0.15**。用户截图报障「对话字幕有一部分在视频外了」：960×540 截图里底部对白从 `y=518` 延伸到 `y=539`，末两行仍有 177~182 个近白像素，字形下半截被画面下边缘直接截断，顶部 signs 完整。这不是「没进黑边」，而是 `\pos` 对白盒底越过了视频帧。
- 用纯 Python Matroska 夹具（`\pos(320,60)` / `\pos(320,338)`、上下 24px 黑条 / 无黑条两种）在 640×360 真机复现：
  | `sub-pos` | 旧 `ratio` | 底部对白像素 |
  | --- | --- | --- |
  | 100 | 1.000 | `y342..354`，完整 |
  | 110 | 1.106 | `y357..359`，只剩 5 行（截图里的「部分在视频外」） |
  | 120 | 1.213 | 无像素，整条对白消失在视频外 |
  | 150 | 1.532 | 无像素 |
  根因是 v1.0.11 引入的 `PlayResY` 位移通道：`\pos` 的 Y 是 ASS 盒底对齐点（默认 `\an2`），盒底 ≈ `ass_anchor_ratio × 帧高 × ratio`，而手动分支的 `clamp(..., 0.5, 2.0)` 等于放任把字幕推到帧外，黑边贴合反解也有同样隐患。
- 新增 conf **`ass_pos_shift_max=1.06`**（`1.0~1.5` 可配，越界 / 非数字回退 1.06）。`y_ratio_limit()` 统一钳住 `ass_y_ratio()` 的三条来源：手动「上移/下移 1%」、pos 预设、黑边贴合反解；`Fontsize` 补偿与 `PlayResY` 覆盖仍取同一个 ratio，物理字号不变。默认 1.06 ≈ `1/0.94` 减描边余量，容得下黑边贴合反解实测的 1.057。到达上限后继续点下移会明确提示「⚠ 已到画面边界：再下移会让字幕落到视频外，位移已停在上限」，不静默吞掉点击。
- 修复后真机（两种夹具一致）：`pos=110/120/150` 底部对白都停在 `y342..355`（24px 黑边）/ `y340..357`（无黑边），`PlayResY=339.623`（ratio 1.060），盒高与像素数不再缩水；`pos=100` 复位时覆盖项清空。
- 对外 API 快照新增只读字段 **`ass_y_limit`**（默认 1.06），API 版本仍为 `1.0.0`，不新增 message、不改动作白名单。
- **纳入正式测试流程**：新增 `tools/sub-style-probe-bounds.lua` 真机探针（`screenshot-raw('subtitles')` 与 `('video')` 逐像素差分，TOP / BOT 双波段），判据同时检查像素数 ≥ 基线 75%、盒高不缩水、`y0 >= 0`、`y1 <= h-1` —— 只看 `y1` 会漏判「贴边裁切」。`tools/sub-style-e2e.py` 新增第 **5m** 组（`bars=24` / `bars=0` 两夹具，连续 pos 110 → nudge ×2 → pos 150 → pos 100）；`tools/sub-style-test.lua` 新增 **T60**（conf / 脚本默认值、API、手动与连续微调钳位、非法配置回退、黑边反解、边界提示），单测 412 → **446 条全绿**；全仓 Lua 语法 222 个文件 FAIL 0；`sub-style-conf-verify.py` PASS（52 项）。全套真机 E2E `SUMMARY sub-style-e2e PASS fail=0`、**325 条 PASS**（独立公开仓库 318 条，5m 两轮各 18 项）。
- ⚠ v1.0.14「保持原样」默认静音后，依赖左上角 OSD 像素 / `report_shown` 的旧 E2E 轮次（B/E 预设、5k 切轨）显式加 `--script-opts=uosc_subtitle_style-show_keep_original=yes`；默认静音由 T27d / T27e 守。`sub-style-probe-fontsize.lua` / `sub-style-probe-shift.lua` 里期待 ratio `>1.4` 的旧断言同步改为「钳在 1.06、完整在帧内」。

### 新增（v1.0.11）

- `uosc_subtitle_style.lua` **v1.0.11**：新增「内封定位字幕可下移」通道。真机逐通道实测确认带 `\pos` 的 explicit ASS 事件对 `sub-pos` / `sub-scale` / `sub-font-size` 全部豁免、`sub-margin-y` 在 ASS 下是死通道，唯一能改 Y 的是覆盖 ASS `[Script Info]` 的 `PlayResY`；据此把「上移/下移」与「上下黑边贴合」折成 `ratio` 写进 `PlayResY`，并用 `Fontsize` 除以 `ratio` 补回物理字号。对话轨道本身是 `\pos` 对白时也能整条推进下黑边、点下移即时生效。
- 菜单步长 **上移/下移 5% → 1%**（`nudge` 默认 1），便于把 `\pos` 内封字幕一点点推进黑边；新增菜单项「内封定位字幕可下移」及消息 `ass-pos-shift-toggle`（默认开，可关回「保持原位」）。
- **左上角报告可关闭**（用户新需求）：conf 新增 `show_report=yes`（设 `no` 永久关闭）、运行时菜单「显示左上角检测报告」及消息 `report-toggle`。`flash_tl()` 成为左上角 `show-text` 唯一出口，关闭时不输出、也不临时改 `osd-align-*`；检测/黑白预设/全内封轨检查/黑边贴合/位置字号通道全部照常执行。`runtime.report_shown` 计数供 API 与门禁验证。
- 对外 API 快照新增 `ass_pos_shift_active` / `ass_y_ratio` / `barfit.y_ratio` / `barfit.anchor_target` / `runtime.ass_pos_shift` / `runtime.show_report` / `runtime.report_shown`；白名单新增 `ass-pos-shift-toggle` / `report-toggle`（共 30 个）。API 版本仍为 `1.0.0`（只增可选字段）。
- `tools/sub-style-probe-shift.lua` + `tools/sub-style-e2e.py` 第 **5g**（`\pos` 对白进黑边 / 点下移生效 / 关通道复现原报障，15 条）与第 **5h**（`show_report=yes|no` 两轮对照、关闭零输出、`report-toggle` 双向生效，各 11 条）真机门禁；`tools/sub-style-test.lua` 新增 **T56**（1% 步长 / PlayResY / Fontsize 补偿 / 黑边反解 / API）与 **T57**（报告开关），单测 360 → **373 条全绿**。

### 新增（v1.0.14）

- `uosc_subtitle_style.lua` **v1.0.14**：「保持原样」（标准白字黑边 / 双语不改色 / 灰度识别关闭等**未套用预设**的情形）的左上角 OSD 报告**默认不再弹出**——常用片源多为标准白字黑边，每次切轨都刷「非彩色字幕，保持原样」很干扰观看。conf 新增 `show_keep_original=no`（设 `yes` 恢复显示），与总开关 `show_report` 是**「与」关系**（`show_report=no` 仍彻底关闭一切左上角输出）；套用了预设（「已套用预设样式」）仍照常显示。`runtime.last_report_show` 记录本次 `run_inspect` 是否真的弹了左上角报告，供 API 与门禁验证；`api_snapshot()` 暴露 `runtime.show_keep_original` / `runtime.last_report_show`。`refresh_barfit()` 的「OSD 微扰后补回报告」路径同样受此约束。
- `tools/sub-style-test.lua` 新增 **T27d**（默认静音：保持原样不弹 OSD、套用预设仍显示）/ **T27e**（开启后显示），并修正 T32/T37/T48/T59b/T59c 在保持原样场景下需显式打开开关才能验证报告路径；单测 373 → **412 条全绿**。

### 改进

- conf 新增 `ass_pos_shift=yes` / `ass_anchor_ratio=0.94` / `show_report=yes`，`nudge=1`；`sub-style-conf-verify.py` 校验全部键的类型。架构文档新增 **§20**、API 文档与脚本头说明同步。
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
- 带 `\pos` 的 explicit ASS 仍不能用 `sub-pos` / `sub-margin-y` 移动；v1.0.11 起改由 `PlayResY` 覆盖实现整体比例位移（见架构文档 §20）。这是解码器级共享、以画面顶部为原点的比例位移，因此次轨 `\pos` 字幕无法同时进上黑边；`ass_pos_shift=no` 时回到「保持原位」。⚠ 强行 `strip` 会丢定位标签并使 style-overrides 整体失效，禁止使用。
- 粗体与 `sub-ass-style-overrides` 是解码器级共享通道，主 / 次轨无法完全独立。
- 图形字幕（PGS/VOBSUB）不走 libass，样式 / 位置不可调。
- 独立公开仓库 `awujiana/uosc_subtitle_style` 的 Release 需与配置仓库脚本版本同步发布，否则新用户从该仓库下载会拿到旧版（自更新器本身不会降级）。

## 更早的版本

本仓库直到 `2026-11-05` 才引入 `CHANGELOG.md`。更早的工作（uosc 皮肤预览、Neve 播放器管理器、v1.0.5 及以前的字幕样式与自更新改动）散落在 git 历史与上游 [dyphire/mpv-config](https://github.com/dyphire/mpv-config) 中，此处不做追溯编造。
