<div align="center">

<!-- badges:start -->
<p align="center">
  <a href="LICENSE"><img alt="协议 AGPL-3.0" src="https://img.shields.io/badge/%E5%8D%8F%E8%AE%AE-AGPL--3.0-blue?style=flat"></a>
  <a href="https://github.com/awujiana/mpv-bingshan"><img alt="平台 Lua" src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Lua-black?style=flat&logo=lua&logoColor=white"></a>
  <a href="https://github.com/awujiana"><img alt="作者 awujiana" src="https://img.shields.io/badge/%E4%BD%9C%E8%80%85-awujiana-orange?style=flat"></a>
  <a href="https://github.com/awujiana/mpv-bingshan"><img alt="状态 维护中" src="https://img.shields.io/badge/%E7%8A%B6%E6%80%81-%E7%BB%B4%E6%8A%A4%E4%B8%AD-green?style=flat"></a>
  <a href="https://github.com/awujiana/mpv-bingshan"><img alt="AI辅助生成 是" src="https://img.shields.io/badge/AI%E8%BE%85%E5%8A%A9%E7%94%9F%E6%88%90-%E6%98%AF-orange?style=flat"></a>
</p>

<p align="center">
  <a href="https://github.com/awujiana/mpv-bingshan/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/awujiana/mpv-bingshan?style=flat"></a>
  <a href="https://github.com/awujiana/mpv-bingshan/issues"><img alt="Issues" src="https://img.shields.io/github/issues/awujiana/mpv-bingshan?style=flat"></a>
</p>
<!-- badges:end -->

<h1>冰山 MPV 配置</h1>
<h2>mpv-bingshan</h2>

<strong>一套开箱即用的 Windows mpv 配置：uosc 菜单、双语字幕分轨样式、弹幕与职员表、静默自更新</strong>

<!-- language-nav:start -->
<p align="center">
  <a href="README.md"><img alt="简体中文 当前" src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%BD%93%E5%89%8D-2ea44f?style=flat"></a>
  <img alt="繁體中文 待补" src="https://img.shields.io/badge/%E7%B9%81%E9%AB%94%E4%B8%AD%E6%96%87-%E5%BE%85%E8%A1%A5-lightgrey?style=flat">
  <img alt="English 待补" src="https://img.shields.io/badge/English-%E5%BE%85%E8%A1%A5-lightgrey?style=flat">
</p>

<p align="center">
  <sub>文档 / Docs：<a href="#sec-11">文档索引</a> · <a href="CONTRIBUTING.md">贡献指南</a> · <a href="CHANGELOG.md">更新日志</a> · <a href="#sec-12">多语言支持</a></sub>
</p>
<!-- language-nav:end -->

</div>

---

> [!WARNING]
> 本项目的相当一部分代码由 AI 辅助生成，并经过持续的人工作业、联调和重构，但它仍然可能存在遗漏、边界情况处理不足或行为与预期不完全一致的问题。如果你在使用过程中发现 Bug、兼容性问题、异常行为或文档缺失，欢迎积极提交 Issue。最好附上复现步骤、日志、截图和系统版本信息，这会非常有帮助。

<a id="sec-toc"></a>
## 📚 目录

- [🚀 项目简介](#sec-1)
- [✨ 核心特色](#sec-2)
- [📷 展示图](#sec-3)
- [📦 安装 / 快速开始](#sec-4)
- [🎮 使用说明](#sec-5)
- [🔗 脚本仓库索引](#sec-6)
- [🖋 内封字幕样式切换](#sec-7)
- [🔄 脚本自更新](#sec-8)
- [🧪 测试与门禁](#sec-9)
- [⚠ 注意事项](#sec-10)
- [📖 文档](#sec-11)
- [🌐 多语言支持](#sec-12)
- [💬 反馈建议](#sec-13)
- [🙏 参考与致谢](#sec-14)
- [🔗 关联仓库](#sec-15)
- [📮 作者联系方式](#sec-16)
- [📄 开源协议](#sec-17)

---

<a id="sec-1"></a>
## 🚀 项目简介

**冰山 MPV 配置**（`awujiana/mpv-bingshan`）是一套面向 Windows 的 [mpv](https://mpv.io) 播放器配置，由 **awujiana** 维护，建立在 [dyphire/mpv-config](https://github.com/dyphire/mpv-config) 的上游基础之上。

把本仓库内容放进 `mpv.exe` 同目录的 `portable_config/` 文件夹即可生效；也可以放到 mpv 默认配置路径 `%APPDATA%/mpv/` 下全局生效。使用 `portable_config` 时会覆盖全局配置方案。

本项目要解决的三件事：

1. **开箱即用**。GitHub `main` 分支是生成出来的**干净配置树**：不含 Git 元数据、视频、日志与运行时 json，两个 submodule 已展开成实体脚本文件，下载 zip 解压即可用（早期版本 zip 里这两个目录是空的）。
2. **内封字幕能改样式**。mpv 对带 `\pos` 的内封 ASS 字幕豁免大部分样式属性；本项目用 `sub-ass-style-overrides` 改写 ASS 样式表，配合主 / 次分轨模型、黑白预设与上下黑边贴合，做到真正可见、可微调、可持久化。
3. **脚本能自己更新，且绝不降级**。公共自更新模块以文件头 `-- @version:` 为本地版本依据，同版本不更新、本地更新时禁止降级，绝不覆盖本地改动。

<a id="sec-2"></a>
## ✨ 核心特色

| 能力 | 说明 |
| --- | --- |
| uosc 中文菜单 | 控制栏 / 右键菜单全部中文化，脚本功能统一由 `script-message-to` 暴露 |
| 内封字幕样式切换 | 位置、缩放、字体、字号 ±1px、粗体、主色、描边；主 / 次字幕**分轨独立**、自动避让不重叠 |
| 字幕自动黑白预设 | 彩色 / 灰色 / 内封非标准配色自动套用；**全部内封字幕轨**逐轨检查；双语双轨默认保持原样 |
| 上下黑边贴合 | 检测视频**内嵌**黑条，把主 / 次对白分别放进下 / 上黑边，按较薄一侧自适应字号，不遮挡画面 |
| 对外 API | 字幕样式与职员表脚本都提供 `user-data` 状态广播 + 请求-响应 + 白名单动作转发 |
| 弹幕与职员表 | 弹弹play 弹幕、Bangumi 职员表 / 角色介绍 / 封面简介 / 制作评分 |
| 静默自更新 | 单文件跟 Release、目录走 git 仅快进；异步不阻塞播放，失败自动回滚，不留 `.bak` |
| 完整门禁 | 194+ Lua 文件语法检查、328 项字幕脚本单测、conf 静态门禁、真机 E2E + 变异测试 |

<a id="sec-3"></a>
## 📷 展示图

![主界面](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224421000.png)

![菜单](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224540075.png)

![字幕与菜单](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224557019.png)

| 拼音搜索（支持首字母） | 字幕下载 |
| --- | --- |
| ![拼音搜索](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224614449.png) | ![字幕下载](https://cdn.jsdelivr.net/gh/dyphire/PicGo/img/2023/11/03/image-20231103224721066.png) |

<a id="sec-4"></a>
## 📦 安装 / 快速开始

1. 从 [Releases / 仓库 main](https://github.com/awujiana/mpv-bingshan) 下载 zip 并解压。
2. 把解压得到的 `portable_config/` 放到 `mpv.exe` 同目录（或把内容放进 `%APPDATA%/mpv/`）。
3. 启动 mpv。`ALT+Q` 呼出字幕样式菜单，控制栏「字幕样式」按钮等价。

> [!IMPORTANT]
> 自行编辑配置文件时，**编码必须为 UTF-8、换行符必须为 Unix LF**，否则 mpv 可能无法识别。
> `mpv.conf` 的 `script-opts` 配置**不支持行尾注释**：`key=value  # 注释` 会把整段当值，
> 注释必须独立成行（仓库里有静态门禁复算这一点）。

**开箱即用发布副本**由 `tools/publish-mpv-bingshan.py` 生成与校验，文件内容直接从 git object DB 读取，与仓库 blob 字节一致（UTF-8 + LF），不会被 Windows CRLF 污染：

```bash
/c/Python314/python.exe tools/publish-mpv-bingshan.py export <目标目录>  # 纯文件副本
/c/Python314/python.exe tools/publish-mpv-bingshan.py index              # 重写索引为发布树
/c/Python314/python.exe tools/publish-mpv-bingshan.py verify             # 校验无排除项/无 gitlink
```

排除清单：`.gitattributes` / `.gitignore` / `.gitmodules` / `.workbuddy-ai` / 视频文件 / 日志 / `danmaku-search-history` / 运行时 json；`scripts/uosc_danmaku` 与 `scripts/uosc_staff_credits` 两个 gitlink 展开成实体文件。

<a id="sec-5"></a>
## 🎮 使用说明

### mpv 客户端

mpv 没有官方发布的客户端，官网列有推荐的第三方编译版：[mpv.io/installation](https://mpv.io/installation)。Windows 上推荐 [shinchiro 版](https://github.com/shinchiro/mpv-winbuild-cmake/releases)、[zhongfly 每日构建](https://github.com/zhongfly/mpv-winbuild/releases) 或 [dyphire 修改版构建](https://github.com/dyphire/mpv-winbuild/releases)；成熟前端可选 [mpv.net](https://github.com/mpvnet-player/mpv.net)。浏览器调用可用 [mpv-handler](https://github.com/akiirui/mpv-handler) 配合 [play-with-mpv](https://greasyfork.org/zh-CN/scripts/416271-play-with-mpv)，单实例用 [umpv-go](https://github.com/zhongfly/umpv-go)。完整链接表见[脚本仓库索引](docs/script-repositories.md#二上游与第三方仓库)。

> [!NOTE]
> 全局键位说明：上游 wiki 称「静态键位已被 `input-default-bindings=no` 屏蔽」，但本地 `input.conf`
> 为大量脚本**重写了中文菜单化键位**，不能按 wiki 的默认键位使用。逐条差异见
> [脚本仓库索引 · 归属勘误](docs/script-repositories.md#四归属勘误)。

### 着色器与脚本

本配置涉及的着色器见 `mpv.conf` 中相关段落；脚本功能与真实作者归属见
[脚本仓库索引](docs/script-repositories.md)（含上游 wiki 的 45 条差异勘误）。

### 在 uosc 控制栏加按钮

uosc 的控制栏 `controls=` 定义在 `script-opts/uosc.conf`（不是本脚本的 conf）。所有脚本功能都通过 `script-message-to` 暴露，加一个 `command:` 按钮即可：

```conf
<has_sub>command:tune:script-message-to uosc_subtitle_style open-menu?字幕样式
```

拼进现有 `controls=` 长行即可；改完需**重启 mpv**（uosc 不热加载 `controls`）。图标名用 Material Symbols，写错只会渲染成文字，不影响功能。

<a id="sec-6"></a>
## 🔗 脚本仓库索引

**所有脚本 / 组件仓库链接已集中到独立文档，统一用表格呈现，方便查看：**

> 📋 **[docs/script-repositories.md](docs/script-repositories.md)** —— 按「**awujiana 维护优先 → 上游 / 第三方 → 鸣谢 → 归属勘误**」组织，含契约文档、推荐客户端、特别鸣谢与上游 wiki 逐条勘误表。

其中由 awujiana 维护的六个仓库（本配置仓库、`uosc_subtitle_style`、`uosc-staff-credits`、`uosc_danmaku`、`mpv-script-updater`、`neve`）均排在上游 / 第三方之前，可单独订阅 Release。

<a id="sec-7"></a>
## 🖋 内封字幕样式切换

`scripts/uosc_subtitle_style.lua`（**v1.0.11**）：把字幕在 **原位 / 中下 / 中部 / 中上 / 顶部** 之间切换，可整体缩放、改字体、字号、粗体、描边粗细与描边颜色；**主字幕（sid）与次字幕（secondary-sid）分轨独立调整**，两轨位置自动避让、**永不重叠**。载入时自动检测字幕样式并在左上角输出报告（可用 conf `show_report=no` 关闭显示，功能照常），可对**彩色字幕与灰色字幕**自动套用可修改、可缓存的预设样式；**双语字幕（双轨）默认不改颜色**。界面直接用 uosc 菜单。

### 版本要点

- **v1.0.6**：字体 / 主色 / 描边色同步改写 ASS 样式表，因此**带 `\pos` 的顶部对话字幕、signs 也能换字体、转黑白**；主颜色候选补入**黑色**与灰阶；菜单点击后保持打开并刷新选中态。
- **v1.0.7**：检测到**视频内嵌上下黑条**时，默认把主字幕放进下黑边、次字幕放进上黑边，**不遮挡画面内容**；菜单「其它 → 上下黑边内显示字幕」可关闭。
- **v1.0.8**：**所有的内封字幕都要被检查**。旧检测只看当前选中的一条轨，真机示例 MKV 有 **42 条内封字幕轨**，切换过去时其余 41 条从未被检查。现在报告列出「内封字幕轨：共 N 条，已检查 M 条」，切换 `sid`/`secondary-sid` 到未检查过的内封轨会自动重新检测；内封字幕除「标准白字黑边」外一律套用黑白预设，不再只靠「是否彩色 / 是否灰阶」这种窄颜色判据（灰色 `#8B8B8B` 报障的彻底解决）。conf 的 `inspect_all_internal` / `preset_all_internal` 可分别关闭。
- **v1.0.9**：修好「点下移 / 整体缩放都没反应，只有换字体有效」。真机查证带 `\pos` 的**内封** ASS 对 `sub-pos` / `sub-scale` / `sub-font-size` **全部豁免**，只有改写 ASS 样式表才有效。现在这类字幕的**缩放与字号折成 `sub-ass-style-overrides/Fontsize`**（基准字号优先从 `sub-ass-extradata` 的 `Style:` / `PlayResY` 读取），并把两轨 `sub-scale` 归 1 防止双叠加；`ScaleX/ScaleY` 实测在 125%/150% 会让字幕消失，故不用作倍率通道。
  - **新增字号 ±1px 连续微调**（菜单「字号 −1px / +1px」，`size-step ±1`），解决「整体缩放不能精准放大字号」；到 `size_min/size_max` 边界给明确提示。
  - **上下黑边视频**：限缩倍率同样并入 `Fontsize`，内封 `\pos` 字幕自动缩小到匹配黑边的单行大小；嫌小点「字号 +1px」，黑边贴合时**自动存进全局预设缓存**（`size_step_saves_preset`）。（v1.0.10 时位置仍保持原位，v1.0.11 起由 `PlayResY` 通道一并送进黑边。）
  - **位置微调到边界不再静默失效**：`nudge` 到 `0%`/`150%` 明确提示；（v1.0.11 起带 `\pos` 的定位字幕改为同步位移，不再保持原位。）
  - 「其它 → 内封定位字幕可缩放/改字号」(`ass-fontsize-toggle`) 可一键退回原生通道；关闭时真机能复现原报障。
- **v1.0.10**：① **上下黑边双对话字幕字号自适应判据**——横向比较 `12/12`、`6/6`、`18/6`、`30/30` 四种黑边，证明限缩倍率由**较薄一侧**决定、上下两条对白用**同一倍率**且字幕盒都不溢出黑边，宽黑边只居中不放大；结果同步进对外 API 快照。② **对外输出 API**（`1.0.0`）：`user-data` 状态广播 + 请求-响应 + 白名单动作转发。
- **v1.0.11**：① 修复「**内封字幕点下移没反应，只有外挂有反应**」与「**对话轨道字幕没在黑边内输出**」——真机逐通道实测确认 `\pos` explicit ASS 对 `sub-pos` / `sub-scale` / `sub-margin-y` 全豁免，唯一能改 Y 的是覆盖 ASS `[Script Info]` 的 `PlayResY`；据此把「上移/下移」与「上下黑边贴合」折成 `ratio` 写进 `PlayResY`，并用 `Fontsize` 反向补偿保持物理字号。对话轨道本身是 `\pos` 对白时也能整条推进下黑边。② 菜单步长 **上移/下移 5% → 1%**，便于一点点推进黑边；新增「其它 → 内封定位字幕可下移」(`ass-pos-shift-toggle`)，可关回「保持原位」。③ **左上角报告可关闭**：conf `show_report=no` 永久关闭显示（检测 / 黑白预设 / 全内封轨检查 / 黑边贴合照常执行），菜单「显示左上角检测报告」与 `report-toggle` 可运行时切换。④ 对外 API 快照新增 `ass_pos_shift_active` / `ass_y_ratio` / `barfit.y_ratio` / `barfit.anchor_target` / `runtime.{ass_pos_shift,show_report,report_shown}`，白名单新增 `ass-pos-shift-toggle` / `report-toggle`。架构文档新增 [§20](docs/uosc-subtitle-style-architecture.md) 说明位移公式与黑边反解。
- **v1.0.14**：「保持原样」（标准白字黑边 / 双语不改色 / 灰度识别关闭等未套用预设的情形）的左上角检测报告**默认不再弹出**——常用片源多为标准白字黑边，每次切轨都刷「非彩色字幕，保持原样」很干扰观看。conf 新增 `show_keep_original=no`（设 `yes` 恢复显示），与总开关 `show_report` 是「与」关系（`show_report=no` 仍彻底关闭一切左上角输出）；套用了预设（「已套用预设样式」）仍照常显示。详见架构文档 [§20.7](docs/uosc-subtitle-style-architecture.md)。

> 若 mpv 仍显示旧的「非彩色字幕，保持原样」文案，说明内存里跑的还是被自更新器降级过的 v1.0.5 —— **完全退出并重启播放器**即可加载 v1.0.11。

### 对外 API

两个自研脚本都提供同名契约，供其它 mpv 脚本 / `input.conf` / 外部工具集成，**不依赖 uosc**：

| 脚本 | 目标名 | 契约文档 |
| --- | --- | --- |
| `uosc_subtitle_style` | `uosc_subtitle_style` | [`docs/api-uosc-subtitle-style.md`](docs/api-uosc-subtitle-style.md) |
| `uosc_staff_credits` | `uosc_staff_credits` | [`scripts/uosc_staff_credits/docs/EXTERNAL_API.md`](scripts/uosc_staff_credits/docs/EXTERNAL_API.md) |

```text
# 订阅（node 属性必须 native）
mp.observe_property('user-data/uosc_subtitle_style/state', 'native', fn)
# 请求-响应
script-message-to uosc_subtitle_style api <reply_to> <request_id> get-state
script-message-to uosc_subtitle_style api <reply_to> <request_id> get barfit.scale
script-message-to uosc_subtitle_style api <reply_to> <request_id> call nudge -5
```

- 回复消息名 `<脚本名>-api-response`，`get-state` / `get` / `list-actions` / `call` 四类 action；
- `call` 只转发白名单内的**既有入口**（字幕脚本 28 项、职员表 16 项），**不含 `api` 自身**，防递归；
- 纯附加：v1.0.9 及更早的所有 `script-message` 入口参数与副作用**原样保留**；
- 只读快照 + 转发，**不新增任何字幕属性写入路径**，不会触发解码器重建；
- `user-data` 是 mpv node 属性，必须用 `get_property_native()` / `'native'`，否则拿到的是带引号二次转义的文本；
- 职员表快照逐字段白名单，**不输出 token / api key / 原始响应 / 缓存正文**。

### 入口

- uosc 工具栏：字幕按钮左侧的「字幕样式」按钮（`controls=` 里的 `command:tune:...open-menu`）
- 键盘：`ALT+Q`（`input.conf` 字幕区）
- 消息：`open-menu | cycle | target <main|sec> | pos <0-150> | scale <倍率> |
  nudge <±%> | font <字体名|reset> | size <像素值|reset> | bold <on|off|reset> |
  outline <粗细|reset> | outline-color <#RRGGBB|reset> | color <#RRGGBB|reset> |
  style-preset <big-bold|original|sync-other> | open-fonts | rescan-fonts | reset | fix-override |
  preset-apply | preset-save | preset-reset | preset-toggle-colored | preset-toggle-dual |
  preset-toggle-enabled | inspect | toggle-gray | toggle-all |
  size-step <±px> | ass-fontsize-toggle | letterbox-toggle | letterbox-refresh`

> ⚠ uosc 菜单项的 `value` 由 `mp.command()` 解析，裸 `#RRGGBB` 会被当成注释起始符吞掉参数（表现为点黑色后提示「恢复字幕原样」）。脚本生成的颜色命令一律写成 `"#RRGGBB"`。

### 编辑目标制与分轨能力矩阵

菜单顶部切换「主字幕 / 次字幕」，位置 / 缩放 / 字体 / 字号只对**当前目标轨**生效；另一轨恢复字幕原样（其预设仍被记忆，切回即恢复）。两轨样式值相同时一起生效。无次字幕轨时目标固定为主字幕，切换项置灰。

| 项目 | 主/次独立 | 实现通道 |
| --- | --- | --- |
| 位置 / 缩放 | ✅ 完全独立 | `sub-pos/scale` 与 `secondary-sub-pos/scale`；两轨自动避让不重叠 |
| 字体 / 字号 / 描边（对白幕） | ✅ 仅目标轨 | `sub-ass-override=force` + `sub-font` / `sub-font-size` / `sub-outline-*` |
| 字体 / 主色 / 描边色（`\pos` 字幕） | ⚠ 共享 | `sub-ass-style-overrides` 的 `FontName` / `PrimaryColour` / `OutlineColour`，改写 ASS 样式表本身；`force` 对带 `\pos` 的 explicit 事件**完全无效** |
| 缩放 / 字号（内封 `\pos` 字幕，v1.0.9） | ⚠ 共享 | `sub-ass-style-overrides/Fontsize`；倍率同时折进 `sub-font-size`，两轨 `sub-scale` 归 1 防双叠加 |
| 粗体 | ⚠ 共享 | `sub-ass-style-overrides` 列表 `Bold=`（mpv 无分轨粗体通道） |
| 上下黑边内的边距 | ⚠ 共享 | `sub-margin-y` 为 INT 且全局共享，贴合时写入、关闭/切文件时还原基准值 |

- **`\pos` 覆盖通道**：Netflix 等内封 ASS 每行都带 `\pos`，只改 `force` / `sub-font` 时字体与主色完全无反应。开启 `style_override_all=yes`（默认）后把 `FontName` / `PrimaryColour` / `OutlineColour` 写进 `sub-ass-style-overrides`（ASS 颜色格式 `&H00BBGGRR`，BGR 倒序），顶部字幕与 signs 才会一起变。代价：该列表解码器级共享、主 / 次轨同变，改动会触发一次重建；菜单「全部字幕统一样式」(`toggle-all`) 可临时关掉。
- **位置默认与不重叠**：沿用 mpv 原生默认（主 100 底部 / 次 0 顶部，天然不重叠），脚本启动时读当前值而非硬编码；只有你通过菜单设过位置才回写（归属权模型）。设目标轨位置时若与另一轨过近，另一轨自动让位一档。用 mpv 自己的 `R`/`T` 键改过位置也会被脚本采纳。
- 位置实测表（640×360）：`pos=5`→贴顶 y9-33 / `25`→中上 y52-77 / `50`→中部 y136-161 / `75`→中下 y220-244 / `100`→原位 y304-328。
- 字号单位是「720p 等效像素」（与 `--sub-font-size` 同语义）。图形字幕（PGS/VOBSUB）不走 libass，位置 / 缩放 / 样式均不可调，菜单与 OSD 会提示。

### 字体选择器与「不打断字幕流」

- 菜单「字体 → 选择本机字体…」：中文字体与其他字体分组，支持菜单内搜索；枚举为**纯 Lua 实现**（sfnt/TTC 读取 name 表 + cmap 检测 U+4E2D），懒加载，缓存于 `~~/uosc-subtitle-style-fonts.json`（以字体文件数 + 总字节为签名）。
- 位置 / 缩放改动**即时生效**；字体 / 字号 / 描边**稳态编辑零重建**——写属性后发一次 OSD 微扰让 `configure_ass` 重跑，实测 **0.2s 内**画面更新（旧实现靠重建解码器，会打断内封字幕包流，表现为「字幕定住在一句」）。
- 只有「进入/退出 force 模式」与改粗体需要一次重建。所有修改自动保存到 `~~/uosc-subtitle-style-state.json`（`{main,sec,target}` 分轨记忆）。

### 内封字体检查与预设样式

- **检测**：外挂字幕解析 ASS 文件（`[V4+ Styles]` 的 Default 样式 + `[Fonts]` 段内封字体）；内封字幕用 `screenshot-raw` 双帧差分做像素采样。结果以**三行报告显示在左上角**，6s 后消失（黑边检测的重绘微扰会清掉报告，脚本会缓存文案再补回）。
- **预设样式**：主色 / 描边色 / 描边粗细 / 字体 / 字号 / 粗体可存为预设，缓存于 `~~/uosc-subtitle-style-preset.json`，重启后仍生效；「恢复出厂预设」回到 conf 默认值。
- **彩色 / 灰色才套用**：彩色阈值是主色饱和度 `max-min(RGB) ≥ colored_threshold`（默认 40）；v1.0.6 起额外识别**灰阶**（如 `#8B8B8B`）；v1.0.8 起内封字幕除标准白字黑边外一律套用。只有**标准白字黑边**保持原样。
- **双语字幕（双轨）默认不改颜色**：检测到 `secondary-sid` 时直接跳过套用；菜单开关或 `preset_skip_dual=no` 可改回。
- **配置文件**：`script-opts/uosc_subtitle_style.conf` 带中文注释，覆盖全部行为。已知边界：像素采样要求字幕正在显示且未处于我方 force 配色；带 `\pos` 的 signs 不参与采样；样式表覆盖是共享通道，需严格分轨时用 `toggle-all` 关闭。

### 上下黑边内显示字幕（v1.0.7，默认开启）

- **适用场景**：视频**文件内嵌**的上下黑条（示例 `3840×2160` 上下各 `120px`，约 5.6%）。黑条是编码进画面的，`osd-dimensions.mt/mb = 0`；mpv 原生 `sub-use-margins` / `sub-ass-force-margins` 只管窗口 / 全屏 letterbox，对它无能为力。
- **检测**：`file-loaded` 后用 `screenshot-raw('video')` 逐行采样平均亮度，从上 / 下各扫 45% 找连续暗行；中央区域亮度守卫防止暗场误判。
- **布局**：按 `sub-font-size × 1.2 × frame_h/720` 估算字幕盒，限缩 `sub-scale` 让它塞进黑条，再用共享 `sub-margin-y` 居中；主轨 `sub-pos=100`（下黑边）、次轨 `secondary-sub-pos=0`（上黑边），两轨同倍率。优先级高于中日双语自动布局。
- **让位与还原**：菜单改位置 / 缩放、外部 `R`/`T` 键改位置、`reset`、`end-file` 都会立即退出本次贴合并还原 `sub-margin-y`。`sub-margin-y` 是 **INT 属性**（传小数会被静默忽略）且不在 `reset-on-next-file` 列表里，必须显式还原；改完还要发一次 `show-text ' ' 60` 触发 `configure_ass`。
- **硬边界（v1.0.11 更新）**：带 `\pos` 的 explicit ASS 事件对 `sub-pos` / `sub-scale` / `sub-margin-y` 全部豁免；强行 `strip` 会丢定位标签并使 style-overrides 整体失效，脚本不重写事件。v1.0.9 起限缩倍率写进 ASS `Fontsize`（尺寸跟着缩小）；**v1.0.11 起改由覆盖 `[Script Info]` 的 `PlayResY` 做整体比例位移**，`\pos` 对白可整条送进下黑边、点下移 1% 即时生效，`Fontsize` 同比反向补偿保持物理字号。该通道解码器级共享、以画面顶部为原点，次轨 `\pos` 无法同时进上黑边；`ass-pos-shift-toggle` 可关回「保持原位」。
- 真机 E2E：贴合前画面区字幕差分 `mid=653`，贴合后 `mid=0`，上 / 下黑边分别 `230` / `319`，画面主体完全不遮挡。

<a id="sec-8"></a>
## 🔄 脚本自更新

`uosc_subtitle_style` 与 `uosc_staff_credits` 会自动检查各自的 GitHub 上游，**仅当远端版本更高**才静默下载替换，下次启动 mpv 生效——不用手动下载、不用解压覆盖。

| 组件 | 形态 | 上游 | 更新方式 |
| --- | --- | --- | --- |
| `uosc_subtitle_style` | 单文件 `scripts/uosc_subtitle_style.lua` | `awujiana/uosc_subtitle_style` | 跟 Release 最新资产，覆盖单文件 |
| `uosc_staff_credits` | 目录 `scripts/uosc_staff_credits/`（git 工作副本） | `awujiana/uosc-staff-credits` | `git fetch` + **仅快进** |

> 架构与安全设计见 [`docs/uosc-updater.md`](docs/uosc-updater.md)。公共更新模块 `script-modules/updater.lua` 已抽成独立公开仓库
> [awujiana/mpv-script-updater](https://github.com/awujiana/mpv-script-updater)：版本标记、《脚本更新规范》、发布流程、单测 / E2E / 变异测试都在那里；本目录保持字节一致副本（当前 `@version: 1.0.0`）。`scripts/uosc_updater.lua` 只是接入驱动。

**行为要点**

- 启动后 30 秒首查，之后每 6 小时一次；网络与 git 调用全部异步，**不阻塞播放**。
- **不保留 `.bak` 备份**，不留临时文件；替换失败自动回滚，原文件完好。
- git 组件**只做快进**：工作区有未提交改动或本地有额外提交时一律跳过。
- 更新落盘后**下次启动 mpv 生效**——mpv 没有卸载 / 热重载脚本的能力，强行加载第二份会造成重复注册。
- **同版本不更新、本地更新时禁止降级**：版本判定以脚本文件头**独立成行**的 `-- @version: X.Y.Z` 为准（必须行首，行内举例不会误读），不用状态文件里的 `tag` 冒充本地版本——避免「1.0.5 已更新 1.0.5 → 1.0.5」这类假提示，也避免上游旧版覆盖本地开发版。同版本 / 禁止降级只写日志，不弹 OSD。
- `uosc_danmaku` 与 `uosc_staff_credits` 以 **git submodule** 形式纳入本仓库：克隆请用 `git clone --recursive`，已克隆过的补 `git submodule update --init --recursive`。

**配置**（`script-opts/uosc_updater.conf`）：`enabled` / `startup_delay` / `interval_hours` / `notify` / `update_subtitle_style` / `update_staff_credits` / `git_path` / `api_base`，默认全部开启。

**手动触发**：`script-message uosc-updater-check`（立即检查并 OSD 汇总）、`script-message uosc-updater-status`（显示上次检查时间与记录版本，不联网）。

<a id="sec-9"></a>
## 🧪 测试与门禁

```bash
../luajit.exe tools/lua-syntax-check.lua               # 全仓 Lua 语法检查（194 文件）
../luajit.exe tools/sub-style-test.lua                 # 字幕脚本 328 项单测
python tools/sub-style-conf-verify.py                  # conf 静态门禁
/c/Python314/python.exe tools/sub-style-e2e.py         # 字幕脚本真机 E2E（含 21 条 API 断言）
../luajit.exe tools/updater-test.lua                   # 自更新单测 72 条
/c/Python314/python.exe tools/updater-e2e.py           # 自更新真机 E2E 25 条 / 四轮
/c/Python314/python.exe tools/updater-mutation-test.py # 10 个变异，须 ALL_KILLED
```

- **单测**覆盖字体解析器合成 sfnt/TTC、位置避让、稳态编辑不重建、ASS 解析 / 像素采样、灰阶识别与 `\pos` 样式表覆盖、预设读写、双语跳过、菜单项；T48–T51 上下黑边、T52 全内封轨、T53 `Fontsize` 通道与 ±1px 微调、T54 对外 API、T55 双对话字幕黑边自适应、**T56 v1.0.11 位移 / T57 报告开关 / T27d·T27e v1.0.14 保持原样默认静音**（共 412 条）。
- **conf 门禁**按 mpv 解析语义复算键集合与脚本 `o` 表对齐、布尔 / 数值 / 颜色格式、行尾注释检测。
- **真机 E2E** 共 10 组：① 双轨探针 + 视觉波段 ② 字幕流连续性 ③ 预设五用例 ④ v1.0.6 灰色 / `\pos` 报障回归 ⑤ v1.0.7 黑边贴合 ⑥ v1.0.8 42 轨示例视频复现 ⑦ v1.0.9 内封 `\pos` ASS 缩放 / 字号（`sub-style-mkv-fixture.py` **纯 Python 直接写最小 Matroska**，不依赖 ffmpeg） ⑧ v1.0.10 双脚本 API ⑨ **5g v1.0.11 `\pos` 对白进黑边 / 1% 下移** ⑩ **5h `show_report=yes|no` 两轮对照**。
- E2E 会按日志标签隔离 `uosc_danmaku` / `uosc_staff_credits` / `dynamic_crop` 等第三方插件的无关 Lua error；被测脚本与探针自身的报错仍判 FAIL。
- ⚠ E2E 视觉判据依赖 Pillow：请用系统 Python（`C:\Python314\python.exe`）运行；缺 PIL 时脚本会明确退出而非崩溃。

<a id="sec-10"></a>
## ⚠ 注意事项

- **mpv ≥ 0.41**：依赖 `secondary-sub-pos` / `secondary-sub-scale` 等分轨属性。
- **配置文件编码 UTF-8 + LF**；mpv conf **不支持行尾注释**。
- **图形字幕（PGS/VOBSUB）**不走 libass，位置 / 缩放 / 样式均不可调。
- **粗体 / 样式表覆盖是解码器级共享**：mpv 无分轨粗体通道，带 `\pos` 的字幕无法分轨改样式；需要严格分轨时用 `toggle-all` 临时关闭。
- **自更新改动功能必须递增 `@version`**，否则会被判定为同版本或旧版本。
- **重启播放器**：脚本更新落盘后、或看到旧版 OSD 文案时，需完全退出并重启 mpv。
- 字体选择器首次打开会有一次全盘字体冷枚举（约 1–3 秒），之后走签名缓存。
- Linux / macOS 的字体枚举路径已内置，但主要验证环境为 Windows。

<a id="sec-11"></a>
## 📖 文档

仅列操作与契约文档；测试脚本见 `tools/` 目录，不单独索引。

| 文档 | 内容 |
| --- | --- |
| [脚本仓库索引](docs/script-repositories.md) | **全部脚本仓库链接（表格）**、鸣谢与归属勘误 |
| [字幕样式对外 API](docs/api-uosc-subtitle-style.md) | 字段表、错误码、调用示例、版本兼容承诺 |
| [字幕样式架构](docs/uosc-subtitle-style-architecture.md) | 数据模型、mpv 能力矩阵、应用引擎、真机实证 |
| [职员表对外 API](scripts/uosc_staff_credits/docs/EXTERNAL_API.md) | 状态快照、动作白名单、隐私字段过滤 |
| [自更新架构](docs/uosc-updater.md) | 两套更新策略、安全措施、排障表 |
| [贡献指南](CONTRIBUTING.md) | 门禁清单、命名规范、代码与文档约定 |
| [更新日志](CHANGELOG.md) | 版本变更记录 |
| [AI 协作约定](AGENTS.md) | 给 AI 编码 / 写作 agent 的仓库约定 |

<a id="sec-12"></a>
## 🌐 多语言支持

| 语言 | 文档 | 状态 |
| --- | --- | --- |
| 简体中文 | [README.md](README.md) | ✅ 当前 |
| 繁體中文 | `README.zh-TW.md` | 待补 |
| English | `README.en.md` | 待补 |

欢迎协助翻译；新增译文后运行 `python scripts/update_badges.py`，语言徽章会自动从「待补」升级为可点击切换。

<a id="sec-13"></a>
## 💬 反馈建议

提交 [Issue](https://github.com/awujiana/mpv-bingshan/issues) 时建议附上：

- 系统 / 运行环境版本（mpv 版本、操作系统、uosc 版本）
- 复现步骤
- 相关日志（可用 `--msg-level=all=info`）
- 截图或录屏
- 出问题的具体对象（字幕文件 / 轨道 / 配置项）

问题反馈：[Issues](https://github.com/awujiana/mpv-bingshan/issues) ｜ [Discussions](https://github.com/awujiana/mpv-bingshan/discussions)

<a id="sec-14"></a>
## 🙏 参考与致谢

本配置建立在大量开源项目之上。特别鸣谢 [dyphire/mpv-config](https://github.com/dyphire/mpv-config)（直接上游）、[Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku)（弹幕扩展原作）、[tomasklaen/uosc](https://github.com/tomasklaen/uosc)（菜单框架）与 [mpv-player/mpv](https://github.com/mpv-player/mpv)。

**全部脚本仓库链接、脚本仓库鸣谢与逐条归属勘误请见 [脚本仓库索引](docs/script-repositories.md)**；参考文档（hooke007 配置手册、mpv 官方手册等）也集中在同一份表格里。

<a id="sec-15"></a>
## 🔗 关联仓库

- [脚本仓库索引](docs/script-repositories.md) —— awujiana 维护仓库 + 上游 / 第三方，表格速查
- [awujiana/mpv-script-updater](https://github.com/awujiana/mpv-script-updater) —— 公共自更新模块与《脚本更新规范》
- [awujiana/neve](https://github.com/awujiana/neve) —— mpv 播放器管理器（外部工具）
- [dyphire/mpv-config](https://github.com/dyphire/mpv-config) —— 本配置的上游基础

<a id="sec-16"></a>
## 📮 作者联系方式

- GitHub：[@awujiana](https://github.com/awujiana)
- 邮箱：[bingshanlengtie@qq.com](mailto:bingshanlengtie@qq.com)
- 问题反馈：[Issues](https://github.com/awujiana/mpv-bingshan/issues)

<a id="sec-17"></a>
## 📄 开源协议

本项目由 awujiana 维护的配置、文档与自研脚本基于 [AGPL-3.0](LICENSE) 开源。以网络服务器形式向用户提供交互服务时，必须同样以 AGPL-3.0 公开其完整对应源代码。

> 第三方脚本与着色器**保留各自原有协议**（通常已写在文件内部，见 [`LICENSE.MD`](LICENSE.MD)）；本仓库不对上游组件重新授权。
