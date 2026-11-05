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

### 内封字幕样式切换（scripts/uosc_subtitle_style.lua，主/次字幕分轨，v1.0.8）

把字幕在 **原位 / 中下 / 中部 / 中上 / 顶部** 之间切换，可整体缩放、改字体、字号、粗体、
**描边粗细与描边颜色**；**主字幕（sid）与次字幕（secondary-sid）分轨独立调整**，
且两轨位置自动避让、**永不重叠**。载入时自动**检测字幕样式**（主色/描边色/字体/内封字体），
在**左上角输出报告**，并可对**彩色字幕与灰色字幕**自动套用可修改、可缓存的预设样式；
**双语字幕（双轨）默认不改颜色**。界面直接用 uosc 的菜单。

- **v1.0.6**：字体 / 主色 / 描边色会同步改写 ASS 样式表，因此**带 `\pos` 的顶部对话字幕、
  signs 也能换字体、转黑白**；主颜色候选补入**黑色**与灰阶；菜单点击后保持打开并刷新选中态。
- **v1.0.7**：检测到**视频内嵌上下黑条**时，默认把主字幕放进下黑边、次字幕放进上黑边，
  **不遮挡画面内容**；菜单「其它 → 上下黑边内显示字幕」可关闭。
- **v1.0.8**：**所有的内封字幕都要被检查**。旧检测只看当前选中的一条轨，一个文件成功检测
  一次后就不再重检——真机示例 MKV 有 **42 条内封字幕轨**，切换过去时其余 41 条从未被检查。
  现在报告列出「内封字幕轨：共 N 条，已检查 M 条」，切换 `sid`/`secondary-sid` 到未检查过的
  内封轨会自动重新检测；内封字幕除「标准白字黑边」外一律套用黑白预设，不再只靠
  「是否彩色 / 是否灰阶」这种窄颜色判据（灰色 `#8B8B8B` 报障的彻底解决）。
  外挂字幕、标准白字、双语双轨保持原样的既有规则不变；conf 的
  `inspect_all_internal` / `preset_all_internal` 可分别关闭。
  > 若你的 mpv 仍显示旧的「非彩色字幕，保持原样」文案，说明内存里跑的还是被自更新器
  > 降级过的 v1.0.5 —— **重启播放器**即可加载 v1.0.8。

> 架构细节（数据模型、mpv 能力矩阵、应用引擎、字体枚举、测试体系）见
> [`docs/uosc-subtitle-style-architecture.md`](docs/uosc-subtitle-style-architecture.md)。

**入口**
- uosc 工具栏：字幕按钮左侧的「字幕样式」按钮（`script-opts/uosc.conf` 的 `controls=`，
  `<has_sub>command:tune:script-message-to uosc_subtitle_style open-menu?字幕样式`）
- 键盘：`ALT+Q`（input.conf 字幕区）
- 消息：`open-menu | cycle | target <main|sec> | pos <0-150> | scale <倍率> |
  nudge <±%> | font <字体名|reset> | size <像素值|reset> | bold <on|off|reset> |
  outline <粗细|reset> | outline-color <#RRGGBB|reset> | color <#RRGGBB|reset> |
  style-preset <big-bold|original|sync-other> | open-fonts | rescan-fonts | reset | fix-override |
  preset-apply | preset-save | preset-reset | preset-toggle-colored | preset-toggle-dual |
  preset-toggle-enabled | inspect | toggle-gray | toggle-all |
  letterbox-toggle | letterbox-refresh`

> ⚠ uosc 菜单项的 `value` 由 `mp.command()` 解析，裸 `#RRGGBB` 会被当成注释起始符吞掉参数
> （表现为点黑色后提示「恢复字幕原样」）。脚本生成的颜色命令一律写成 `"#RRGGBB"`。

**编辑目标制**：菜单顶部切换「主字幕 / 次字幕」，位置/缩放/字体/字号只对**当前目标轨**生效；
另一轨恢复字幕原样（其预设仍被记忆，切回即恢复）。两轨样式值相同时一起生效。
无次字幕轨时目标固定为主字幕，切换项置灰。

**分轨能力矩阵**（ASS 内封字幕，mpv v0.41 源码 + 本机实测）

| 项目 | 主/次独立 | 实现通道 |
| --- | --- | --- |
| 位置 / 缩放 | ✅ 完全独立 | `sub-pos/scale` 与 `secondary-sub-pos/scale`；两轨自动避让不重叠 |
| 字体 / 字号 / 描边（对白幕） | ✅ 仅目标轨 | `sub-ass-override=force` + `sub-font`/`sub-font-size`/`sub-outline-size`/`sub-outline-color`（force 的选择性覆盖位只作用于该轨） |
| 字体 / 主色 / 描边色（`\pos` 字幕） | ⚠ 共享 | `sub-ass-style-overrides` 的 `FontName` / `PrimaryColour` / `OutlineColour`，改写 ASS 样式表本身；`force` 对带 `\pos` 的 explicit 事件**完全无效** |
| 粗体 | ⚠ 共享 | `sub-ass-style-overrides` 列表 `Bold=`（列表是解码器级共享，mpv 无分轨粗体通道） |
| 上下黑边内的边距 | ⚠ 共享 | `sub-margin-y` 为 INT 且全局共享，贴合时写入、关闭/切文件时还原基准值 |

- **`\pos` 覆盖通道**：Netflix 等内封 ASS 每行都带 `\pos`，实测只改 `force` / `sub-font` 时
  字体与主色完全无反应。开启 `style_override_all=yes`（默认）后，脚本把 `FontName` /
  `PrimaryColour` / `OutlineColour` 写进 `sub-ass-style-overrides`（ASS 颜色格式
  `&H00BBGGRR`，BGR 倒序），顶部字幕与 signs 才会一起变。代价：该列表解码器级共享、
  主/次轨同变，改动会触发一次重建；菜单「全部字幕统一样式」(`toggle-all`) 可临时关掉，
  回到纯分轨模式。

- **位置默认与不重叠**：沿用 mpv 原生默认（主 100 底部 / 次 0 顶部，天然不重叠），
  脚本启动时读当前值而非硬编码；只有你通过菜单设过位置才回写（归属权模型）。
  设目标轨位置时若与另一轨过近，另一轨自动让位一档（OSD 提示「次字幕已避让至 X%」）。
  用 mpv 自己的 `R`/`T` 键改过位置也会被脚本采纳，不会被下次编辑覆盖。

- 位置实测表（640x360）：`pos=5`→贴顶 y9-33 / `25`→中上 y52-77 / `50`→中部 y136-161 /
  `75`→中下 y220-244 / `100`→原位 y304-328。带 `\pos` 的 signs/特效幕不随 sub-pos 移动。
- 字体/字号走 force 的副带效果：该轨**对白幕**同时按 `--sub-*` 配色渲染（force 下 signs 因
  explicit 豁免；开启 `style_override_all` 后 signs 由样式表覆盖一并生效）。
- 字号单位是「720p 等效像素」（与 `--sub-font-size` 同语义），mpv 会按字幕脚本的 PlayResY 换算。
- 图形字幕（PGS/VOBSUB）不走 libass，位置/缩放/样式均不可调，菜单与 OSD 会提示。

**本机字体选择器**
- 菜单「字体 → 选择本机字体…」打开选择器：中文字体（含「中」字字形）与其他字体分组，
  支持菜单内搜索；选中即对目标轨生效。字体目录增减后点「重新扫描本机字体」。
- 枚举为本项目**纯 Lua 实现**（sfnt/TTC 区间读取 name 表族名 + cmap 检测 U+4E2D），
  懒加载，结果缓存于 `~~/uosc-subtitle-style-fonts.json`（以字体文件数+总字节为签名，变化自动重扫）。
- 已知边界：TTC 内各字体的表目录偏移是相对**文件头**的绝对偏移（不是字体基址）；
  cmap 子表解析必须带子表偏移（msyh 的 format 4 子表在 off=28）。

**及时反馈与「不打断字幕流」**
- 位置/缩放改动**即时生效**（mpv 默认键位同路径，无重建）。
- 字体/字号/描边：**稳态编辑零重建**——写属性后发一次 OSD 微扰让 `configure_ass` 重跑，
  实测 **0.2s 内**画面更新（旧实现靠重建解码器，会打断内封字幕的包流，
  表现为「字幕定住在一句」，已修复并加了回归测试）。
- 只有「进入/退出 force 模式」（每个文件首次改样式）需要一次重建；粗体因 mpv 无实时
  粗体通道，改粗体时也会重建一次。
- 所有修改自动保存到 `~~/uosc-subtitle-style-state.json`（{main,sec,target} 分轨记忆），
  每个文件加载后自动重新应用（`mpv.conf` 的 `reset-on-next-file` 会重置这些属性）。

**内封字体检查与预设样式**（载入时自动，也可手动「重新检测」）
- **检测**：外挂字幕直接解析 ASS 文件（[V4+ Styles] 的 Default 样式 + [Fonts] 段内封字体）；
  内封字幕用 `screenshot-raw` 双帧差分做像素采样（取最多亮色为主色、最多暗色为描边色）。
  结果以**三行报告显示在左上角**：`来源：主色 #RRGGBB · 描边 #RRGGBB` / `字体 · 字号 · 内封字体 N 个` /
  `已套用预设样式（…）` 或 `非彩色字幕，保持原样（标准白字黑边）`。报告用 `show-text` 临时置于左上角，
  6s 后自动消失（黑边检测的重绘微扰会清掉报告，脚本会缓存文案再补回）。
- **预设样式**：`color`（主色）/`outline-color`（描边色）/`outline`（粗细）/字体/字号/粗体
  可存为预设（「把当前样式存为预设」或 `preset-save` 消息），缓存于 `~~/uosc-subtitle-style-preset.json`，
  重启后仍生效；「恢复出厂预设」回到 `script-opts/uosc_subtitle_style.conf` 的 `preset_*` 默认值。
- **彩色 / 灰色才套用**：彩色阈值是主色饱和度 `max-min(RGB) ≥ colored_threshold`（默认 40）；
  v1.0.6 起额外识别**灰阶**（如 Netflix 内封 ASS 的 `#8B8B8B`）——饱和度为 0，但既不是纯白
  也不是纯黑，同样自动套用白字黑边预设（开关「灰色字幕也自动转黑白」/ `preset_include_gray`）。
  只有**标准白字黑边**保持原样；不想自动套用可关「载入时自动套用」开关（只报告不修改）。
- **黑色主色**：`colors` 候选含 `黑=#000000` 与 `深灰 / 灰 / 浅灰`，用于浅色画面或还原被
  自动识别成「非标准黑白」的灰色字幕。
- **双语字幕（双轨）默认不改颜色**：检测到次字幕轨（`secondary-sid`）时直接跳过套用——
  两条轨往往已各有配色，强行统一反而破坏双语可读性（报告第三行会说明
  `双语字幕（双轨），保持原样不改颜色`）。菜单「双语字幕保持原样」开关或 conf 的
  `preset_skip_dual=no` 可改回「双语也套用」；手动 `preset-apply`/「套用预设样式」始终可用。
- **配置文件**：`script-opts/uosc_subtitle_style.conf` 带中文注释，覆盖上述全部行为
  （阈值 `colored_threshold`、检测时机 `inspect_delay`、报告时长 `report_ms`、
  避让间距 `pos_min_gap`、force 重建延迟 `rebuild_delay`、预设各项 `preset_*`；
  v1.0.6 的 `style_override_all` / `preset_include_gray`；v1.0.7 的 `letterbox_*` 六项；
  v1.0.8 的 `inspect_all_internal` / `preset_all_internal`）。
- 已知边界：像素采样要求字幕正在显示且未处于我方 force 配色；带 `\pos` 的 signs 不参与采样；
  样式表覆盖是共享通道，需要严格分轨时用 `toggle-all` 关闭。

**上下黑边内显示字幕（v1.0.7，默认开启）**

- **适用场景**：视频**文件内嵌**的上下黑条（示例 `3840×2160` 上下各 `120px`，约 5.6%）。
  黑条是编码进画面的，`osd-dimensions.mt/mb = 0`；mpv 原生 `sub-use-margins` /
  `sub-ass-force-margins` 只管播放窗口/全屏 letterbox，对它无能为力。
- **检测**：`file-loaded` 后 `inspect_delay + letterbox_delay`，用 `screenshot-raw('video')`
  逐行采样平均亮度（列步长 `letterbox_sample_step`），从上/下各扫 45% 找连续暗行；
  中央区域亮度守卫防止暗场/淡入淡出误判，黑条占比需 ≥ `letterbox_min_bar`。
- **布局**：按 `sub-font-size × 1.2 × frame_h/720` 估算字幕盒，限缩 `sub-scale` 让它塞进黑条
  （留 `letterbox_pad` 余量），再用共享 `sub-margin-y` 居中；主轨 `sub-pos=100`（下黑边）、
  次轨 `secondary-sub-pos=0`（上黑边），两轨同倍率。优先级高于中日双语自动布局。
- **让位与还原**：菜单改位置/缩放、外部（mpv `R`/`T` 键）改位置、`reset`、`end-file` 都会
  立即退出本次贴合并还原 `sub-margin-y` 基准值。`sub-margin-y` 是 **INT 属性**（真机实测传
  小数会被 mpv 静默忽略）且不在 `reset-on-next-file` 列表里，必须显式还原，否则跨文件泄漏；
  改完还要发一次 `show-text ' ' 60` 触发 `configure_ass`，否则「属性值变了、画面不动」。
- **菜单**：「其它 → 上下黑边内显示字幕」(`letterbox-toggle`)、「重新检测上下黑边」
  (`letterbox-refresh`)；conf 里 `letterbox_fit=no` 可默认关闭。
- **硬边界**：带 `\pos` 的 explicit ASS 事件对 `sub-pos` / `sub-scale` / `sub-margin-y` 全部豁免，
  **保持原位**；强行 `strip` 会丢定位标签，脚本不重写事件。窗口 letterbox 仍由 mpv 原生处理。
  真机 E2E 用双轨 SRT 夹具验证：贴合前画面区字幕差分 `mid=653`，贴合后 `mid=0`，
  上/下黑边分别 `230` / `319`，即画面主体完全不被遮挡。

**测试**
- `../luajit.exe tools/sub-style-test.lua` —— **259 项单测**（含字体解析器合成 sfnt/TTC 字节流、
  位置避让、稳态编辑不重建、ASS 解析/像素采样/饱和度阈值、灰阶识别与 `\pos` 样式表覆盖、
  预设读写与开关、双语跳过与开关、避让间距/报告时长可配、菜单项、
  T48–T51 上下黑边检测/布局/让位/菜单、
  T52 全内封轨检查：报告统计 / 切轨重检 / 灰色识别关闭仍套用 / 白字·外挂·关开关保持旧行为）
- `python tools/sub-style-conf-verify.py` —— conf 静态门禁：按 mpv 解析语义复算
  `script-opts/uosc_subtitle_style.conf`（键集合与脚本 o 表对齐、布尔/数值/颜色格式、
  **行尾注释检测**——mpv 不支持 `key=value  # 注释`，会被整段吃进值里）
- `/c/Python314/python.exe tools/sub-style-e2e.py` —— 真机 E2E 五组判据：
  ① 双字幕轨探针 + 视觉波段判据（分轨位置/字体/字号互不影响，含 `FontName` 写入共享
     样式表与 `toggle-all` 清除覆盖）；
  ② 字幕流连续性回归（多句 fixture，编辑后逐句校验仍正常跳句）；
  ③ 预设样式五用例：A 彩色→套用 / B 白色→保持原样 / C 修改并保存缓存 /
     D 重启读缓存 / E 双语双轨→不套用（与 A 同 fixture 差分），
     含左上角报告出现与字幕变色的像素判据；
  ④ v1.0.6 报障回归：灰色 `#8B8B8B` 转白、带 `\pos` 的顶部字幕变色、
     菜单点黑色 `"#000000"` 不被注释吞掉、字体写入样式表；
  ⑤ v1.0.7 上下黑边贴合：双轨 SRT + 合成 `640×360` 上下各 `24px` 黑条，探针 15 断言 +
     Python 侧独立复核 `BASE mid=653 → FIT mid=0`，上下黑边各出现一条字幕；
  ⑥ v1.0.8 示例视频真机复现（`--pause=yes --start=00:12:30`，`persist=no` 隔离状态）：
     `INTERNAL_TRACKS=42`、`SID=3`、`SUB_COLOR=#FFFFFFFF`、`ASS_OVERRIDE=force`、
     `SHARED_PRIMARY=true` —— 灰色内封字幕与带 `\pos` 的顶部字幕一并转黑白
- 探针 `tools/sub-style-probe.lua` / `sub-style-probe-stream.lua` /
  `sub-style-probe-preset.lua` / `sub-style-probe-preset-save.lua` /
  `sub-style-probe-pos.lua` / `sub-style-probe-bars.lua`；
  fixture `tools/sub-style-smoke{,-sec,-multi,-colored}.ass` /
  `sub-style-smoke-pos-gray.ass` / `sub-style-smoke-bars-{main,sec}.srt`
- E2E 会按日志标签隔离 `uosc_danmaku` / `uosc_staff_credits` / `dynamic_crop` 等第三方插件的
  无关 Lua error；被测脚本与探针自身的报错仍判 FAIL。
- ⚠ E2E 视觉判据依赖 Pillow：PATH 里的 managed python 未装，请用系统 Python
  （`C:\Python314\python.exe`，已装 Pillow）运行；缺 PIL 时脚本会明确退出而非崩溃。

### 脚本自更新（scripts/uosc_updater.lua）

`uosc_subtitle_style` 与 `uosc_staff_credits` 会自动检查各自的 GitHub 上游，
**仅当远端版本更高**才静默下载替换，下次启动 mpv 生效——不用手动下载、不用解压覆盖。

| 组件 | 形态 | 上游 | 更新方式 |
| --- | --- | --- | --- |
| `uosc_subtitle_style` | 单文件 `scripts/uosc_subtitle_style.lua` | `awujiana/uosc_subtitle_style` | 跟 Release 最新资产，下载后覆盖单文件 |
| `uosc_staff_credits` | 目录 `scripts/uosc_staff_credits/`（git 工作副本） | `awujiana/uosc-staff-credits` | `git fetch` + **仅快进** |

> 架构与安全设计（为什么必须做成独立脚本、两套更新策略、七项安全措施、
> 故障排查表、测试体系）见 [`docs/uosc-updater.md`](docs/uosc-updater.md)。
>
> 公共更新模块 `script-modules/updater.lua` 已抽成独立公开仓库
> [awujiana/mpv-script-updater](https://github.com/awujiana/mpv-script-updater)：版本标记、
> 《脚本更新规范》、发布流程、单测 / 真机 E2E / 变异测试都在那里；本目录保持同步副本
> （当前 `@version: 1.0.0`）。本表里的两个组件**不含**这个模块自身，`scripts/uosc_updater.lua`
> 只是接入驱动。

**行为要点**
- 启动后 30 秒首查，之后每 6 小时一次；网络与 git 调用全部异步，**不阻塞播放**。
- **不保留 `.bak` 备份**，也不留任何临时文件；替换失败自动回滚，原文件完好。
- git 组件**只做快进**：工作区有未提交改动、或本地有额外提交时一律跳过，不会冲掉你的改动。
- 更新落盘后**下次启动 mpv 生效**——mpv 没有卸载/热重载脚本的能力，强行加载第二份会造成重复注册。
- 状态记录命中时**不重复下载**那 100 KB 的脚本。
- **同版本不更新、本地更新时禁止降级**：版本判定以脚本文件头**独立成行**的
  `-- @version: X.Y.Z` 为准（必须行首，行内举例不会误读），不用状态文件里的 `tag`
  冒充本地版本——避免「1.0.5 已更新 1.0.5 → 1.0.5」
  这类假提示，也避免上游旧版覆盖本地开发版。同版本/禁止降级只写日志（`保持本地版本 …`），
  不弹 OSD。改动脚本功能时请同步递增 `@version`。
- `uosc_danmaku` 与 `uosc_staff_credits` 以 **git submodule** 形式纳入本仓库（见 `.gitmodules`）：
  克隆请用 `git clone --recursive`，已克隆过的补 `git submodule update --init --recursive`。
  自更新推进子模块后父仓库会显示 submodule 变更，需在父仓库提交一次指向。

**配置**（`script-opts/uosc_updater.conf`）：`enabled` / `startup_delay` / `interval_hours` /
`notify` / `update_subtitle_style` / `update_staff_credits` / `git_path` / `api_base`。
默认全部开启，无需配置。

**手动触发**
- `script-message uosc-updater-check` —— 立即检查并用 OSD 汇总结果
- `script-message uosc-updater-status` —— 显示上次检查时间与记录的版本（不联网）；
  本地版本高于远端时额外显示「远端 X（本地 Y，不降级）」。

**测试**
```bash
../luajit.exe tools/updater-test.lua                    # 单测 72 条
/c/Python314/python.exe tools/updater-e2e.py            # 真机 E2E 25 条 / 四轮（隔离 config-dir）
/c/Python314/python.exe tools/updater-mutation-test.py  # 10 个变异，须 ALL_KILLED
```

E2E 第三轮复现「状态已记录同版本、本地文件被外部改动」→ 不下载、不覆盖、不弹更新；
第四轮验证「本地 `@version: 10.0.0`、远端 `9.9.9`」→ 禁止降级。

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
