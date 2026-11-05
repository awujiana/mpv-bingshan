# 脚本仓库索引

> 本文件集中收录 `mpv-bingshan` 配置中出现的**全部脚本 / 组件仓库链接**，统一用表格呈现，便于查阅、订阅与逐项核对。
> [返回 README](../README.md) ｜ 维护者：[awujiana](https://github.com/awujiana)

本配置由大量开源脚本组合而成。为避免链接散落在 README 各处，这里按「**awujiana 维护优先 → 上游 / 第三方 → 鸣谢 → 归属勘误**」四层组织。

| 目录 | 内容 |
| --- | --- |
| [一、awujiana 维护的仓库](#一awujiana-维护的仓库) | 本项目自建 / 分叉维护的脚本、模块与工具，可单独订阅 Release |
| [二、上游与第三方仓库](#二上游与第三方仓库) | 本配置直接依赖的上游项目与脚本原作 |
| [三、鸣谢](#三鸣谢) | 特别鸣谢与按目录顺序列出的脚本仓库 / 作者 |
| [四、归属勘误](#四归属勘误) | 上游 wiki 与本地源码不一致的脚本归属核对表 |

---

## 一、awujiana 维护的仓库

> 这几项均以独立公开仓库发布，可单独订阅、提 issue 或跟进 Release；下表按本配置中的重要性排序，**awujiana 仓库统一置顶**。

| 仓库 | 对应本配置路径 | 说明 | 更新方式 |
| --- | --- | --- | --- |
| [awujiana/mpv-bingshan](https://github.com/awujiana/mpv-bingshan) | 仓库根 | **本配置仓库**（`portable_config` 开箱即用发布副本） | 从本仓库 `main` 下载 zip |
| [awujiana/uosc_subtitle_style](https://github.com/awujiana/uosc_subtitle_style) | `scripts/uosc_subtitle_style.lua` | 内封字幕样式切换：主 / 次分轨、黑白预设、上下黑边贴合、ASS `Fontsize` 缩放、对外 API（当前 `v1.0.10`） | 自更新器跟 Release 最新资产，覆盖单文件 |
| [awujiana/uosc-staff-credits](https://github.com/awujiana/uosc-staff-credits) | `scripts/uosc_staff_credits/` | Bangumi 职员表 / 角色介绍 / 封面简介 / 制作评分，含对外 API | 自更新器 `git fetch` + **仅快进** |
| [awujiana/uosc_danmaku](https://github.com/awujiana/uosc_danmaku) | `scripts/uosc_danmaku/` | 弹弹play 弹幕加载、延迟与保存（submodule，由 Tony15246 原作分叉维护） | `git submodule update --init --recursive` |
| [awujiana/mpv-script-updater](https://github.com/awujiana/mpv-script-updater) | `script-modules/updater.lua` | 公共自更新模块 + 《脚本更新规范》 + 单测 / 真机 E2E / 变异测试，**唯一权威来源** | 本目录保持字节一致副本（`@version: 1.0.0`） |
| [awujiana/neve](https://github.com/awujiana/neve) | —（外部工具） | mpv 播放器管理器：液态玻璃组件库、脚本 / 皮肤 / 备份同步、uosc 预览 | 独立应用，随自身 Release 更新 |

> 带 `-- @version:` 文件头的脚本与公共更新模块由 `scripts/uosc_updater.lua` 静默检查 GitHub Release / git 上游：**同版本不更新、本地更新时禁止降级**。改动脚本功能时必须同步递增 `@version`。

### 契约与规范文档

| 文档 | 位置 | 内容 |
| --- | --- | --- |
| 字幕样式对外 API | [docs/api-uosc-subtitle-style.md](api-uosc-subtitle-style.md) | `user-data` 状态广播、请求-响应、白名单动作转发、错误码与版本承诺 |
| 字幕样式架构 | [docs/uosc-subtitle-style-architecture.md](uosc-subtitle-style-architecture.md) | 数据模型、mpv 能力矩阵、应用引擎、真机实证结论 |
| 职员表对外 API | [scripts/uosc_staff_credits/docs/EXTERNAL_API.md](../scripts/uosc_staff_credits/docs/EXTERNAL_API.md) | 职员表状态快照、动作白名单、隐私字段过滤 |
| 自更新架构 | [docs/uosc-updater.md](uosc-updater.md) | 两套更新策略、七项安全措施、排障表、测试体系 |
| 脚本更新规范 | [awujiana/mpv-script-updater · 规范/脚本更新规范.md](https://github.com/awujiana/mpv-script-updater/blob/main/%E8%A7%84%E8%8C%83/%E8%84%9A%E6%9C%AC%E6%9B%B4%E6%96%B0%E8%A7%84%E8%8C%83.md) | 版本标记、三道闸门、替换流程、门禁与责任边界 |

---

## 二、上游与第三方仓库

| 仓库 | 对应本配置路径 | 用途 |
| --- | --- | --- |
| [dyphire/mpv-config](https://github.com/dyphire/mpv-config) | 仓库根 | **本配置的上游基础**：`mpv.conf` / `input.conf` / 脚本集 / 中文 wiki / 整合包 |
| [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) | `scripts/uosc_danmaku/` | 弹幕脚本的上游原作（`awujiana/uosc_danmaku` 由此分叉维护） |
| [tomasklaen/uosc](https://github.com/tomasklaen/uosc) | `scripts/uosc/` | UI 框架，所有 uosc 菜单的宿主 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | — | 播放器本体与 `TOOLS/lua` 官方脚本 |
| [CogentRedTester/mpv-file-browser](https://github.com/CogentRedTester/mpv-file-browser) | `scripts/file-browser/` | 文件浏览器 |
| [po5/evafast](https://github.com/po5/evafast) | `scripts/evafast.lua` | 倍速快进 |
| [po5/trackselect](https://github.com/po5/trackselect) | `scripts/trackselect.lua` | 轨道自动选择 |
| [Eisa01/mpv-scripts](https://github.com/Eisa01/mpv-scripts) | `scripts/simplebookmark.lua` 等 | `simplebookmark` / `simplehistory` / `undoredo` 等 |
| [christoph-heinrich/mpv-quality-menu](https://github.com/christoph-heinrich/mpv-quality-menu) | `scripts/quality-menu.lua` | 画质菜单 |
| [tsl0922/mpv-dyn_menu](https://github.com/tsl0922/mpv_dyn_menu) | `scripts/dyn_menu.lua` | 动态右键菜单 |

### 推荐客户端与构建

| 项目 | 链接 | 说明 |
| --- | --- | --- |
| mpv 官方安装页 | [mpv.io/installation](https://mpv.io/installation) | 第三方编译版索引 |
| shinchiro 构建 | [shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake/releases) | Windows 推荐 |
| zhongfly 每日构建 | [zhongfly/mpv-winbuild](https://github.com/zhongfly/mpv-winbuild/releases) | 每日构建 |
| dyphire 修改版构建 | [dyphire/mpv-winbuild](https://github.com/dyphire/mpv-winbuild/releases) | 基于 [dyphire/mpv · patch](https://github.com/dyphire/mpv/tree/patch)，[相关说明](https://github.com/dyphire/mpv-config/discussions/7) |
| mpv.net 前端 | [mpvnet-player/mpv.net](https://github.com/mpvnet-player/mpv.net) | 成熟的 libmpv 前端，[个人配置参考](https://github.com/dyphire/mpv-config/tree/mpvnet) |
| 浏览器调用 | [akiirui/mpv-handler](https://github.com/akiirui/mpv-handler) · [play-with-mpv](https://greasyfork.org/zh-CN/scripts/416271-play-with-mpv) | 需配合油猴脚本 |
| 浏览器调用（备选） | [LuckyPuppy514/external-player](https://github.com/LuckyPuppy514/external-player) | 外部播放器扩展 |
| 单实例模式 | [zhongfly/umpv-go](https://github.com/zhongfly/umpv-go) | 复用同一窗口 |

---

## 三、鸣谢

### 特别鸣谢

| 对象 | 致谢理由 |
| --- | --- |
| [dyphire/mpv-config](https://github.com/dyphire/mpv-config) | 本配置的直接上游。`mpv.conf`、`input.conf`、脚本集、中文 wiki 与整合包发布均源自该项目；下文归属勘误也是以它的 wiki 为基准逐条核对。 |
| [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) | 弹幕扩展的原作。本配置中的 `scripts/uosc_danmaku/` 由其分叉维护，弹弹play API 接入、弹幕延迟、搜索历史等核心能力均来自该仓库。 |
| [tomasklaen/uosc](https://github.com/tomasklaen/uosc) | 整套菜单交互的宿主框架，`uosc_subtitle_style` / `uosc_staff_credits` / `uosc_danmaku` 的 UI 全部基于它。 |
| [mpv-player/mpv](https://github.com/mpv-player/mpv) | 播放器本体；同时感谢 shinchiro / zhongfly / dyphire 的 Windows 构建与分发。 |

### 脚本仓库鸣谢

按本配置 `scripts/` 中出现的顺序，作者归属见「四、归属勘误」表：

| 脚本 / 组件 | 原作者或维护者 |
| --- | --- |
| `autoload`、`dynamic-crop` | mpv 官方 `TOOLS/lua` / 社区改进版 |
| `autosubsync`、`sub-assrt`、`sub_export` | 社区脚本作者（kelciour 等） |
| `thumbfast`、`uosc` | tomasklaen |
| `quality-menu` | christoph-heinrich |
| `cycle-commands`、`playlistmanager`、`file-browser` | CogentRedTester |
| `delete-current-file` | stax76 |
| `simplebookmark`、`simplehistory`、`undoredo`、`chapterskip` | Eisa AlAwadhi（Eisa01）等 |
| `sponsorblock_minimal`、`blacklist-extensions` | 上游社区脚本 |
| `persist_properties` | d87 |
| `dyn_menu` | tsl0922（GPL-2.0-only） |
| `evafast`、`trackselect`、`chapterskip` | po5 等 |
| `inputevent` | Natural-Harmonia-Gropius |
| `mpv-torrserver`、`sub-fastwhisper`、`mpv-cropscreen`、`hdr-mode`、`pip` | dyphire 及社区作者 |
| 中文文档 | [hooke007/mpv_doc-CN](https://github.com/hooke007/mpv_doc-CN) 与 mpv 社区 |

### 参考文档

| 文档 | 链接 |
| --- | --- |
| hooke007 配置手册 | [hooke007.github.io/mpv-lazy/mpv.html](https://hooke007.github.io/mpv-lazy/mpv.html) |
| mpv 官方开发版手册（英文） | [mpv.io/manual/master](https://mpv.io/manual/master/) |
| mpv 官方手册汉化版 | [hooke007/mpv_doc-CN](https://github.com/hooke007/mpv_doc-CN) |
| 上游脚本说明 wiki | [dyphire/mpv-config · 脚本说明](https://github.com/dyphire/mpv-config/wiki/%E8%84%9A%E6%9C%AC%E8%AF%B4%E6%98%8E) |
| 上游整合包下载 | [dyphire/mpv-config · Releases](https://github.com/dyphire/mpv-config/releases) |

---

## 四、归属勘误

核对基准：上游 wiki「脚本说明」（2025-03-19 版，共 50 条脚本条目）。核对结果：**共 45 条存在差异** —— 17 条本地有脚本但 wiki 未收录、3 条 wiki 有收录但本地缺失、21 条 wiki 被误改、4 条说明本身有误。

### 4.1 wiki 未收录的本地脚本（17 个）

| 脚本 | 实际功能（据源码） |
| --- | --- |
| `fix-avsync.lua` | 切换音频输出设备时用 `frame-back-step` 修复音画不同步 |
| `hdr-mode.lua` | 根据视频内容自动切换显示器 SDR/HDR 模式，仅 Windows 10+ |
| `mpv-cropscreen.lua` | 用 ffmpeg 制作「字幕拼接长图」/ 截取字幕区域 / 自定义裁切截图 |
| `pip.lua` | 画中画模式，Windows 专用，键位 `p` |
| `uosc_danmaku/`（组） | 基于 uosc + 弹弹play API 的弹幕插件，键位 `CTRL+d` 等 |

> wiki 页脚标注「Pages 2」，但第二页实际未公开，故不排除部分脚本被列入未公开的第二页。**建议以本机源码为准**。

### 4.2 wiki 收录但本地已删除（3 个）

| wiki 条目 | 状态 |
| --- | --- |
| `command_palette.lua` | **本机不存在**；`script-modules/` 下无 `extended-menu.lua` |
| `simple-mpv-webui` | 目录存在但 `script-opts/` 下无 `webui.conf`，实际未启用 |
| `trakt-scrobble` | **本机完全不存在**（无目录、无 conf） |

### 4.3 wiki 归属被误改（21 个）

这些脚本并非 dyphire 编写，但 wiki 把源码 `AUTHORS` 字段改写成了 `dyphire`，**已丢失真实上游信息**：

| 脚本 | 真实上游（源码内可考） | wiki 现记 |
| --- | --- | --- |
| `autoload.lua` | mpv 官方 `TOOLS/lua` | 无归属 |
| `blacklist-extensions.lua` | 上游社区脚本 | 无归属 |
| `cycle-commands.lua` | CogentRedTester | 无归属 |
| `delete-current-file.lua` | stax76 | 无归属 |
| `dyn_menu.lua` | tsl0922（GPL-2.0-only） | 无归属 |
| `dynamic-crop.lua` | mpv 官方 `autocrop.lua` 改进版 | 无归属 |
| `evafast.lua` | po5 | 无归属 |
| `inputevent.lua` | Natural-Harmonia-Gropius 的 `InputEvent` | 无归属 |
| `persist_properties.lua` | d87 | 无归属 |
| `playlistmanager.lua` | CogentRedTester / dyphire 分叉 | 无归属 |
| `quality-menu.lua` | christoph-heinrich | 无归属 |
| `simplebookmark.lua` | Eisa AlAwadhi | 无归属 |
| `simplehistory.lua` | Eisa AlAwadhi | 无归属 |
| `sponsorblock_minimal.lua` | 上游社区脚本 | 无归属 |
| `sub_export.lua` | kelciour（COMMIT 2018-08-29） | 无归属 |
| `thumbfast.lua` | tomasklaen（MPL-2.0） | 无归属 |
| `trackselect.lua` | po5 | 无归属 |
| `undoredo.lua` | Eisa AlAwadhi | 无归属 |
| `chapterskip.lua` | po5、detuur、microraptor、Eisa01、allecsc（＋dyphire） | 记为 dyphire 独作 |
| `mpv-torrserver.lua` / `sub-fastwhisper.lua` | dyphire 自建 | 一致，仅版本日期不同 |

### 4.4 wiki 说明本身有误（4 个）

| 脚本 / 条目 | wiki 说法 | 实际情况 |
| --- | --- | --- |
| `chapterskip.lua` | 「可实现自动跳过指定章节」 | 主要能力是**自动跳过到下一个静音点**（`skip-to-silence`，跳 OP/ED），按章节名跳过是叠加的次要功能 |
| `simple-mpv-webui` | 「为 mpv 实现一个简单的 webui」 | 本地无对应配置且未启用 |
| `file-browser` | 面板键位描述 | 本地使用 CogentRedTester 上游版，菜单键位与 wiki 不完全一致 |
| 全局键位说明 | 「静态键位已被 `input-default-bindings=no` 屏蔽」 | 本地 `input.conf` 为大量脚本重写了中文菜单化键位 |

### 4.5 结论

- **一致**：约 22 条 wiki 条目所描述的功能与本地脚本相符（`autosubsync`、`file-browser`、`uosc`、`track-list`、`sub-assrt`、`sub-fastwhisper`、`sub_export`、`youtube-download` 等）。
- **不一致**：以上 45 条需以**本机源码为准**。wiki 最后更新于 2025-03-19，本机脚本多数更新（`chapterskip.lua` v.2026-04-30、`uosc` 5.12.0、`uosc_danmaku` 2.2.0），且有 17 个本地脚本根本不在 wiki 中。
- 后续新增 / 升级脚本时请同步更新本表。

---

> 上游 wiki 曾把部分脚本的 `AUTHORS` 误记为 `dyphire`，本表已按源码逐条还原真实归属；如有遗漏或错误，欢迎在 [Issues](https://github.com/awujiana/mpv-bingshan/issues) 指正。
