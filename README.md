## MPV config ([English branch](https://github.com/dyphire/mpv-config/tree/eng))

### 项目介绍

本项目为 windows 下 [mpv](https://github.com/mpv-player/mpv) 播放器的配置文件，应放入`mpv.exe`所在目录的`portable_config`文件夹内，

或 mpv 配置默认路径`%APPDATA%/mpv/`下，这种方式全局生效。

使用`portable_config`时会覆盖全局配置方案。

PS：自行编辑配置文件时，注意编码格式应为 UTF-8，换行符为 Unix，否则 MPV 可能无法识别

**mpv 整合包下载**：[Releases](https://github.com/dyphire/mpv-config/releases)

### mpv 客户端

- 目前 mpv 没有官方发布的客户端，官网上有放一些推荐的第三方编译版：[https://mpv.io/installation](https://mpv.io/installation)
  - windows 上推荐使用 shinchiro 版： [shinchiro_mpv](https://github.com/shinchiro/mpv-winbuild-cmake/releases) ![releases](https://img.shields.io/github/v/release/shinchiro/mpv-winbuild-cmake)
  - 每日构建版：[zhongfly_mpv](https://github.com/zhongfly/mpv-winbuild) [![releases](https://img.shields.io/github/v/release/zhongfly/mpv-winbuild)](https://github.com/zhongfly/mpv-winbuild/releases)
  - 基于个人修改版 [mpv](https://github.com/dyphire/mpv/tree/patch) 构建版：[dyphire_mpv](https://github.com/dyphire/mpv-winbuild) [![releases](https://img.shields.io/github/v/release/dyphire/mpv-winbuild)](https://github.com/dyphire/mpv-winbuild/releases)
    - [修改版 mpv 相关说明](https://github.com/dyphire/mpv-config/discussions/7)
- 目前比较成熟的 mpv/libmpv 前端推荐： [mpv.net](https://github.com/mpvnet-player/mpv.net) [![mpv.net](https://flat.badgen.net/github/last-commit/mpvnet-player/mpv.net?scale=1.0&cache=1800)](https://github.com/mpvnet-player/mpv.net) [![releases](https://img.shields.io/github/v/release/mpvnet-player/mpv.net)](https://github.com/mpvnet-player/mpv.net/releases)
  - 个人 mpv.net 配置文件参考：https://github.com/dyphire/mpv-config/tree/mpvnet
- 浏览器调用 mpv 播放的方法推荐
  - [mpv-handler](https://github.com/akiirui/mpv-handler) 配合脚本 [play-with-mpv](https://greasyfork.org/zh-CN/scripts/416271-play-with-mpv)
  - [external-player](https://github.com/LuckyPuppy514/external-player)
- 单实例模式：[umpv](https://github.com/zhongfly/umpv-go)

### 脚本着色器说明

本项目使用的 mpv 脚本及功能介绍详见 wiki 内容： [脚本说明-wiki](https://github.com/dyphire/mpv-config/wiki/脚本说明)

本项目涉及的着色器见 mpv.conf 中相关内容

### 本地脚本与上游 wiki 说明的差异核对

核对基准：上游 wiki「脚本说明」（2025-03-19 版，共 50 条脚本条目）。
核对结果：**共 45 条存在差异** —— 17 条本地有脚本但 wiki 未收录，3 条 wiki 有收录但本地缺失，
21 条 wiki 被误改（上游原作者记录被替换为 `dyphire`），4 条说明本身有误。逐条列示如下。

#### 一、wiki 未收录的本地脚本（本地新增 17 个）

以下脚本存在于本机 `scripts/` 目录，但上游 wiki 完全没有条目，**无法从 wiki 得到其功能说明**：

| 脚本 | 实际功能（据源码） |
| --- | --- |
| `fix-avsync.lua` | 切换音频输出设备时用 `frame-back-step` 修复音画不同步（dyphire 自建，wiki 无条目） |
| `hdr-mode.lua` | 根据视频内容自动切换显示器 SDR/HDR 模式，仅 Windows 10+；依赖 `mpv-display-plugin` 与 `display-info.dll` |
| `mpv-cropscreen.lua` | 用 ffmpeg 制作「字幕拼接长图」/截取字幕区域/自定义裁切截图（选项 `screenshot_dir=~~/files/screenshots`） |
| `pip.lua` | 画中画（Picture-in-Picture）模式，Windows 专用；键位 `p` |
| `uosc_danmaku/`（组） | 基于 uosc + 弹弹play API 的弹幕插件，加载弹幕/弹幕延迟/保存弹幕；键位 `CTRL+d` 等 |

> 备注：wiki 页脚标注「Pages 2」，但第二页实际未公开（`_history` 无第二页正文），
> 故不排除上述部分脚本被列入未公开的第二页。**建议以本机源码为准**。

#### 二、wiki 有收录但本地已删除（3 个）

| wiki 条目 | 状态 |
| --- | --- |
| `command_palette.lua`（命令面板，依赖 `extended-menu.lua`） | **本机不存在**；`script-modules/` 下仅有 `file-browser-addons`，无 `extended-menu.lua` |
| `simple-mpv-webui`（依赖 luasocket） | 目录存在，但 `script-opts/` 下**无 `webui.conf`**，实际未启用 |
| `trakt-scrobble`（trakt 观看记录跟踪） | **本机完全不存在**（无目录、无 `trakt_scrobble.conf`） |

#### 三、wiki 条目被误改（21 个）—— 最需要留意的一类

这些脚本并非 dyphire 编写，但 wiki 把源码 `AUTHORS` 字段改写成了 `dyphire`，**已丢失真实上游信息**：

| 脚本 | 真实上游（源码内可考） | wiki 现记 |
| --- | --- | --- |
| `autoload.lua` | mpv 官方 `TOOLS/lua` | 无归属（记为项目自带） |
| `blacklist-extensions.lua` | 上游社区脚本 | 无归属 |
| `cycle-commands.lua` | CogentRedTester | 无归属 |
| `delete-current-file.lua` | stax76 | 无归属 |
| `dyn_menu.lua` | tsl0922（GPL-2.0-only） | 无归属 |
| `dynamic-crop.lua` | mpv 官方 `autocrop.lua` 改进版 | 无归属 |
| `evafast.lua` | po5（`manager.json` 可证） | 无归属 |
| `inputevent.lua` | Natural-Harmonia-Gropius 的 `InputEvent` | 无归属 |
| `persist_properties.lua` | d87 | 无归属 |
| `playlistmanager.lua` | CogentRedTester / dyphire 分叉（branch `dev`） | 无归属 |
| `quality-menu.lua` | christoph-heinrich | 无归属 |
| `simplebookmark.lua` | Eisa AlAwadhi | 无归属 |
| `simplehistory.lua` | Eisa AlAwadhi | 无归属 |
| `sponsorblock_minimal.lua` | 上游社区脚本 | 无归属 |
| `sub_export.lua` | kelciour（COMMIT 2018-08-29） | 无归属 |
| `thumbfast.lua` | tomasklaen（MPL-2.0） | 无归属 |
| `trackselect.lua` | po5 | 无归属 |
| `undoredo.lua` | Eisa AlAwadhi | 无归属 |
| `chapterskip.lua` | po5, detuur, microraptor, Eisa01, allecsc（＋dyphire） | 记为 dyphire 独作 |
| `mpv-torrserver.lua` / `sub-fastwhisper.lua` | dyphire 自建 | 一致，仅版本日期不同 |

#### 四、wiki 说明本身有误（4 个）

| 脚本 | wiki 说法 | 实际情况 |
| --- | --- | --- |
| `chapterskip.lua` | 「可实现自动跳过指定章节」 | 主要能力是**自动跳过到下一个静音点**（`skip-to-silence`，用于跳 OP/ED），选项为 `silence_audio_level` / `silence_duration`；「按章节名跳过」是叠加的次要功能 |
| `simple-mpv-webui` | 「为 mpv 实现一个简单的 webui」 | 本地**无对应配置且未启用**，见第二节 |
| `file-browser` | 面板键位描述 | 本地使用 CogentRedTester 上游版，**菜单键位与 wiki 描述不完全一致** |
| 全局键位说明 | 「所有脚本预绑定的静态键位已被 `input-default-bindings=no` 屏蔽」 | 本地 `input.conf` 为大量脚本**重新写了中文菜单化键位**，不能按 wiki 的默认键位使用 |

#### 五、结论

- **一致**：约 22 条 wiki 条目所描述的功能本身与本地脚本相符（如 `autosubsync`、`file-browser`、
  `uosc`、`track-list`、`sub-assrt`、`sub-fastwhisper`、`sub_export`、`youtube-download` 等）。
- **不一致**：以上 45 条需以**本机源码为准**。wiki 最后更新于 2025-03-19，本机脚本版本多数更新
  （如 `chapterskip.lua` v.2026-04-30、`hdr-mode.lua` 2025 版、`uosc` 5.12.0、`uosc_danmaku` 2.2.0），
  且有 17 个本地脚本根本不在 wiki 中。
- **本 README 的核对内容即为差异清单**，后续新增/升级脚本时请同步更新本节。

### 预览

 ![image-20231103224421000](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224421000.png)

![image-20231103224540075](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224540075.png)

![image-20231103224557019](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224557019.png)

| 拼音搜索（支持首字母）                                                                                    | 字幕下载                                                                                           |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| ![image](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224614449.png) | ![image](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224721066.png) |

### 参考

* [hooke007 配置手册](https://hooke007.github.io/mpv-lazy/mpv.html)
* [mpv 原版官方的开发版手册（英文）](https://mpv.io/manual/master/)
* [mpv 官方文档的汉化版-hooke007](https://github.com/hooke007/mpv_doc-CN)
