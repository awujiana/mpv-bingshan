# uosc_subtitle_style.lua 架构文档

> 版本：2026-11-05（v1.0.8：主/次分轨 + 字体选择器 + 描边 + 位置避让 +
> 灰色/`\pos` 字幕样式表覆盖 + 视频内嵌上下黑边贴合 + **所有内封字幕轨全量检查**）
> 适用范围：`scripts/uosc_subtitle_style.lua`（约 2700 行）及其配置、测试与工具链。
> 结论均标注「源码依据」或「本机实测」，未经验证的推断不写入本文件。

---

## 1. 定位与目标

`uosc_subtitle_style.lua` 是 mpv 的**字幕样式快速切换脚本**，解决「看番时临时把字幕挪位置 / 改字体字号描边」
的需求，UI 完全复用 uosc 菜单（不引入额外 UI 框架）。

三条硬约束（决定了整个架构）：

1. **主/次字幕可分别调整**（双语字幕常见：主字幕日文、次字幕中文）；
2. **改动要即时可见**（用户明确抱怨过「改了没反应」）；
3. **绝不打断字幕流**（用户明确报障过「编辑时字幕定住不跳句」）。

第 3 条是架构的分水岭：mpv 里绝大多数字幕样式参数都只能通过**重建解码器**生效，
而重建会让字幕流重新读包。因此整个应用引擎围绕「**能不动解码器就不动**」设计。

---

## 2. 文件与目录

| 路径 | 角色 |
| --- | --- |
| `scripts/uosc_subtitle_style.lua` | 主脚本（单文件，无外部依赖，纯 Lua 5.1/LuaJIT） |
| `script-opts/uosc_subtitle_style.conf` | 选项：持久化开关、默认值、字体/字号/描边候选表、预设样式 |
| `input.conf` | `ALT+Q` 打开菜单 |
| `script-opts/uosc.conf` | 工具栏按钮（`<has_sub>command:tune:script-message-to uosc_subtitle_style open-menu`） |
| `~~/uosc-subtitle-style-state.json` | 运行时状态（主/次分轨记忆，自动生成） |
| `~~/uosc-subtitle-style-preset.json` | 预设样式缓存（载入时套用的目标样式，自动生成） |
| `~~/uosc-subtitle-style-fonts.json` | 字体枚举缓存（带签名，自动生成） |
| `tools/sub-style-test.lua` | 单元测试（stub mpv 运行时 + 虚拟文件系统），133 项 |
| `tools/sub-style-e2e.py` | 真机 E2E 编排（三阶段：双轨视觉 + 字幕流连续性 + 预设样式四用例） |
| `tools/sub-style-probe.lua` | E2E 阶段一探针（双字幕轨、25 条断言） |
| `tools/sub-style-probe-stream.lua` | E2E 阶段二探针（多句 fixture，字幕流连续性） |
| `tools/sub-style-probe-preset.lua` | E2E 阶段三探针（套用/保持断言 + 前后对比截图） |
| `tools/sub-style-probe-preset-save.lua` | E2E 阶段三探针（改样式 + 存预设 + 落盘断言） |
| `tools/sub-style-smoke.ass` / `-sec.ass` / `-multi.ass` / `-colored.ass` | fixture（主轨 / 次轨 / 多句 / 彩色） |

---

## 3. 数据模型

### 3.1 状态结构

```lua
state = {
    main = { pos, scale, font, size, bold, color, outline, outline_color },
    sec  = { pos, scale, font, size, bold, color, outline, outline_color },
    target = 'main' | 'sec',   -- 当前编辑目标（样式通道的归属轨）
}

-- 预设样式（与 state 分离：state 是「当前编辑到哪」，preset 是「要套用的目标」）
preset = {
    enabled = bool,        -- 载入时自动套用总开关
    only_colored = bool,   -- 仅当检测到彩色字幕才套用
    color = '#RRGGBB', outline_color = '#RRGGBB', outline = number,
    font = string|nil, size = number|nil, bold = bool|nil,
}
```

字段语义：

| 字段 | 类型 | 含义 | `nil` 的含义 |
| --- | --- | --- | --- |
| `pos` | number 0-150 | `sub-pos`（100=原位，越大越靠上） | — |
| `pos_owned` | bool | 该轨位置是否由**本脚本**设定（见 §6.2） | — |
| `scale` | number 0.1-3 | `sub-scale`（相对缩放） | — |
| `font` | string | 字体族名（`sub-font`） | 用字幕自带字体 |
| `size` | number | 字号，**720p 等效像素**（`sub-font-size`） | 用字幕自带字号 |
| `bold` | bool | `Bold=` 列表项 | 不覆盖 |
| `outline` | number | `sub-outline-size` | 用字幕自带描边 |
| `outline_color` | string `#RRGGBB` | `sub-outline-color` | 用字幕自带描边色 |
| `color` | string `#RRGGBB` | `sub-color`（主颜色） | 用字幕自带主色 |

### 3.2 持久化格式

```json
{
  "main": {"pos": 100, "scale": 1, "font": "...", "size": 24, "outline": 2, "outline_color": "#FF0000"},
  "sec":  {"pos": 75,  "scale": 1},
  "target": "main"
}
```

- 写入时机：任何修改后立即写（`save_state`）；`persist=no` 时完全不写。
- **旧格式迁移**：早期版本是扁平结构 `{pos, scale, sec_pos, font, size, bold}`，
  `load_state` 检测到无 `main`/`sec` 键即按旧格式读入主轨、`sec_pos` 进次轨。
- 重新应用时机：`file-loaded` / `playback-restart`。原因：用户 `mpv.conf` 的
  `reset-on-next-file` 会重置 `sub-pos/sub-scale` 等，必须在每个文件加载后补回。

### 3.4 预设文件格式（`~~/uosc-subtitle-style-preset.json`）

```json
{"enabled": true, "only_colored": true, "skip_dual": true, "color": "#FFFFFF",
 "outline_color": "#000000", "outline": 2, "font": "Noto Sans CJK SC", "size": 40, "bold": false}
```

- 缺省值来自 `script-opts/uosc_subtitle_style.conf` 的 `preset_*`（`preset_font=''`/`preset_size=0`/
  `preset_bold=keep` 表示不指定）；`load_preset()` 逐字段覆盖，字段缺失保留现值。
- `skip_dual=true`：双语字幕（双轨）时保持原样、不改颜色（详见 §10）。
- 写入时机：`preset-save` / `preset-reset` / 三个开关切换。与 state 文件**分离存储**，
  互不影响（换文件不重置预设，改预设不记忆到当前编辑）。

### 3.3 基线（baseline）

脚本加载时快照 mpv 当前值（`sub-ass-override`、`sub-font`、`sub-font-size`、`sub-bold`、
`sub-outline-size`、`sub-outline-color`、`secondary-sub-ass-override`），
作为「字幕原样」的还原目标。`sub-bold` 读不到时回落 mpv 文档默认值 `no`。

---

## 4. mpv 能力矩阵（架构的物理边界）

依据 `mpv v0.41` 源码：`sub/dec_sub.c: sub_create()` 给**主/次解码器同一份**
`mp_subtitle_opts`；只有 `mp_subtitle_shared_opts` 按 order 索引（`[2]` 数组）。

| 能力 | 主/次独立 | 通道 | 依据 |
| --- | --- | --- | --- |
| 位置 | ✅ | `sub-pos` / `secondary-sub-pos` | `shared_opts->sub_pos[order]` |
| 缩放 | ✅ | `sub-scale` / `secondary-sub-scale` | `shared_opts->sub_scale[order]` |
| override 模式 | ✅ | `sub-ass-override` / `secondary-sub-ass-override` | `shared_opts->ass_style_override[order]` |
| 字体 / 字号 / 描边 | ✅（仅目标轨） | force 模式 + `sub-font` / `sub-font-size` / `sub-outline-*` | `configure_ass` 的 `mp_ass_set_style(&style, 288, opts->uosc_subtitle_style)` + libass 选择性覆盖（FONT_NAME / FONT_SIZE_FIELDS / COLORS / BORDER 位） |
| 粗体 | ❌ 共享 | `sub-ass-style-overrides` 列表 `Bold=` | force 的 flags **不含** ATTRIBUTES 位；列表是解码器级共享 |

**结论**：位置/缩放天然分轨；字体/字号/描边靠 force 的「按轨生效」特性实现分轨；
粗体在 mpv 层面无法分轨，只能共享（菜单 hint 已明示）。

**v1.0.6 补充通道（本机实测）**：`sub-ass-override=force` 的选择性覆盖只作用于
`!explicit` 事件；带 `\pos` 的顶部 signs / 定位对白是 `explicit`，字体、主色、描边色
**完全不受 force 影响**。唯一能改它们的通道是 `sub-ass-style-overrides` 列表
（改写 ASS 样式表本身）：`FontName=` / `PrimaryColour=` / `OutlineColour=`。
该列表是**解码器级共享**，主/次轨会一起变，代价由菜单「顶部/定位字幕一并改样式」
（`toggle-all`）显式暴露，用户可关掉回到纯分轨模式。颜色格式是 ASS 的
`&H00BBGGRR`（BGR 倒序），`#FF8040` → `&H004080FF`。

**v1.0.7 补充属性**：`sub-margin-y` 是**共享的 INT 属性**，且不在
`reset-on-next-file` 列表里 —— 写入非整数（如 2.4）会被 mpv **静默忽略**，
必须四舍五入；改过之后必须在关闭/让位/切文件时显式还原，否则跨文件泄漏。
`sub-use-margins` / `sub-ass-force-margins` 只处理窗口 letterbox（`osd-dimensions.mt/mb`），
对**编码进画面的黑条**（mt/mb=0）无能为力。

---

## 5. 应用引擎

### 5.1 三条应用路径

```
apply_all(dance, rebuild)
├─ separate_tracks()                  # 位置不重叠不变量（见 §6）
├─ 位置/缩放：sub-pos / secondary-sub-pos ...   # 即时生效，不碰 override
├─ apply_style_channel(cur())         # 共享样式通道 = 目标轨的样式
└─ override 决策
   ├─ dance=false（文件加载 / 位置缩放）→ 直接设 override
   └─ dance=true（样式编辑）
      ├─ 目标轨 override 需切换（进入/退出 force）→ 延迟 0.12s 设（**一次重建**）
      └─ 已是目标模式 → nudge_reconfigure()（**零重建**，见 §5.3）
```

### 5.2 为什么必须避免重建解码器

`player/sub.c: reinit_sub()` 注释明说「wait for packets … but this will have a delay」；
`player/command.c: mp_option_run_callback()` 在 UPDATE_SUB_HARD 时对**现有解码器**
调 `sub_redecode_cached_packets()` —— 但重建后的新解码器**没有缓存包**：

- **外挂字幕**：`update_subtitles` 里 `if (track->demuxer->fully_read && sub_can_preload)`
  → `demux_seek(0) + sub_preload()` 全量重载，所以重建后仍然正确（历届测试因此一直没暴露问题）；
- **内封字幕**：不满足 preload 条件，主解复用器已消费掉的当前事件包拿不到
  → 当前句丢失/滞留 = 用户看到的「字幕定住在一句」。

### 5.3 OSD 微扰：不重建也能让新样式生效

`sd_ass.c: get_bitmaps()` 中 `configure_ass()` 只在 `!ass_configured || osd_res 变化` 时重跑；
`configure_ass` 会重新读取 `--sub-*` 属性并重建 libass 的选择性覆盖样式。
**OSD 状态变化会改变字幕的 osd_res**，因此：

```lua
local function nudge_reconfigure()
    mp.commandv('show-text', ' ', 60)   -- 一个不可见的 OSD 消息
end
```

实测（`tools/` 外的临时探针，2026-10-21）：force 模式下改 `sub-font-size`，
不调用微扰时 **2s 画面都不变**；调用后 **0.2s 内画面更新**，且字幕流完全不受影响。

### 5.4 样式通道（`apply_style_channel`）

按目标轨的样式逐项写属性；未设置项回落 baseline：

```
sub-font        ← target.font or baseline.font
sub-font-size   ← target.size or baseline.size
sub-outline-size ← target.outline or baseline.outline
sub-outline-color ← target.outline_color or baseline.outline_color
sub-bold        ← target.bold 解析结果 or baseline.bold
sub-ass-style-overrides 列表 ← 读-改-写，保留用户其它条目
```

**列表写回必须「先读再写」**：`m_config_set_option_node` 对列表是**严格替换**
（`options/m_config_frontend.c`），直接写会冲掉用户 `-append` 的条目（如 `Encoding=-1`）。
因此每次先剔除本脚本管理的键再合并。

`MANAGED_OVERRIDE_KEYS` 在 v1.0.6 扩为
`FontName / Fontsize / Bold / PrimaryColour / OutlineColour / Outline`：

| 开关 | 列表里写什么 | 效果 |
| --- | --- | --- |
| `style_override_all=no` | 仅 `Bold=`（沿用旧行为，纯分轨） | 普通对白靠 force 换字体/配色；`\pos` signs 保持原样 |
| `style_override_all=yes`（默认） | 追加 `FontName=` / `PrimaryColour=` / `OutlineColour=` | 连 `\pos` signs 一起换字体/配色；两轨同变（共享列表代价） |

`hex_to_ass_color()` 把 `#RRGGBB` 转成 `&H00BBGGRR`。列表变化本身会触发一次
解码器重建 —— 这是覆盖 `\pos` 字幕必须付出的代价，用 `toggle-all` 可退回零重建路径。

---

## 6. 位置：默认值、归属权与不重叠

### 6.1 位置默认值（踩过的坑）

mpv 的原生默认是 **主字幕 `sub-pos=100`（底部）、次字幕 `secondary-sub-pos=0`（顶部）**——
这是 mpv 有意让双语字幕天然不重叠。早期版本把两轨都硬编码成 100，
导致「加载次字幕轨 → 编辑主字幕样式」时次字幕从顶部被拽到底部/中部（用户报障）。

现规则：**优先级 = 状态文件（用户设过的）> mpv 当前值（配置/默认）> 配置项默认值**
（`pos_default=100` / `sec_pos_default=0`）。脚本启动时先读当前值，而不是假设。

### 6.2 归属权（`pos_owned`）——脚本不越权

`pos_owned=false` 时脚本**只观察、不回写**该轨位置。含义：

| 场景 | 行为 |
| --- | --- |
| 用户从未用本脚本调过位置 | `pos_owned=false` ⇒ 完全不碰 `sub-pos`，mpv 配置/默认值原样保留 |
| 用户在菜单里选了位置预设 | `pos_owned=true` ⇒ 之后每个文件加载都回写该值 |
| 用户用 mpv 自己的键位（`R`/`T`）改位置 | 观察器把新值**采纳**进 state 并保存，下次编辑不会覆盖回去 |
| 用户「恢复默认」 | 两轨都按 mpv 默认值（100/0）回写并取得归属权 |
| `end-file` 时 mpv 按 `reset-on-next-file` 重置 | 窗口期内**禁止采纳**（那不是用户意图），`file-loaded` 应用完再解除 |

观察器（`adopt_external`）用 `expected_value` 记录「本脚本最后写入值」，
以此区分「自己写的」与「外部改的」；写入统一走 `write_prop`。

### 6.3 不重叠（`pos_min_gap`，默认 25）

- 实测一档（25 个 sub-pos 单位）≈ 84px（640×360 下），足够放两行字幕。
- **`push_other_away(target_pos)`**：用户设位置后若与另一轨距离 < `o.pos_min_gap`，
  把**另一轨**推到最近的不重叠位置（候选 `target±gap`，限定 0-100，同距取较小值），
  并对该轨取得归属权。目标轨位置永不被改动，OSD 提示「次字幕已避让至 75%」。
  ⚠ 实现坑：`push_other_away` 内有局部变量 `o`（= `other().pos`）遮蔽选项表，
  `local gap = o.pos_min_gap` 必须在遮蔽**之前**取出。
- **加载/复位不做强制分离**：mpv 默认本身不重叠；若用户配置把两轨设成同一位置，
  那是用户的选择，脚本不抢方向盘（早期版本在加载期强制分离，正是踩坑来源之一）。

---

## 7. 本机字体枚举（字体选择器数据源）

```
font_dirs()  →  ~~/fonts, %WINDIR%/Fonts, %LOCALAPPDATA%/Microsoft/Windows/Fonts,
                /usr/share/fonts, ~/.fonts …
   ↓ utils.readdir（返回纯字符串数组）
font_files() → 过滤 .ttf/.otf/.ttc
   ↓ 签名 = 文件数:总字节
load_font_cache() → 命中即返回（~~/uosc-subtitle-style-fonts.json）
   ↓ 未命中：逐文件区间读取
parse_font_at()  → sfnt 头(12B) → 表目录(16B×n) → name 表 → 族名
                 → cmap 表 → 是否含 U+4E2D（中文字体判定）
   ↓
{ fonts = {...}, cjk = {...}, sig = "223:753984030" }
```

关键实现约束（都是踩过的坑）：

1. **TTC 内各字体的表目录偏移是相对「文件头」的绝对偏移**，不是该字体 sfnt 基址；
2. **cmap 子表解析必须带子表偏移**（msyh 的 format 4 在 off=28，固定从表头读会全漏检）；
3. 族名取 `nameID 16`（Typographic Family）优先于 `nameID 1`；Windows/Unicode 平台优先；
4. 图标字体按族名关键字过滤（`icon/material/mdl2/uosc/modernx/wingding/webding`）；
5. 竖排变体（族名以 `@` 开头）跳过；
6. 懒加载（首次打开选择器才枚举）+ 磁盘缓存（签名变化自动重扫，也可手动「重新扫描」）。

本机实测：223 个字体文件 / 719MB，**区间读取总耗时 < 0.5s**，119 款族名、51 款含中文。

---

## 8. 菜单系统（uosc 集成）

菜单 JSON 通过 `script-message-to uosc open-menu <json>` 发送；`type` 区分两个页面：

| 页面 | type | 内容 |
| --- | --- | --- |
| 主菜单 | `uosc_subtitle_style` | 目标切换 + 位置 + 缩放 + 字体 + 字号 + 粗体 + 描边粗细 + 描边颜色 + 快捷预设 + 其它 |
| 字体选择器 | `uosc_subtitle_style_fonts` | 中文字体 / 其他字体 两组 + 恢复原样 + 重新扫描 |

菜单项结构：`{title, hint, icon, value, active, keep_open, selectable, muted}`；
`value` 一律是 `script-message-to uosc_subtitle_style <入口> <参数>`（点击即回灌到脚本）。
已打开同类型菜单时改用 `update-menu`（避免重复 open 的动画抖动）。

图标名需存在于 `fonts/MaterialIconsRound-Regular.otf`（PUA cmap + rlig 连字三角树），
否则会渲染成字面文字——新增图标前用 fontTools 校验过（本文件用到的 20+ 个已验）。

---

## 9. 消息接口（完整）

| 消息 | 参数 | 作用 |
| --- | --- | --- |
| `open-menu` | — | 打开主菜单（无 uosc 时降级为循环切换 + OSD 列表） |
| `cycle` | — | 循环切换目标轨位置预设 |
| `target` | `main`/`sec` | 切换编辑目标轨 |
| `pos` | 0-150 | 设目标轨位置（自动避让） |
| `scale` | 0.1-3 | 设目标轨缩放 |
| `nudge` | ±整数 | 位置微调 |
| `font` | 字体名 / `reset` | 字体覆盖（多词名字自动拼回） |
| `size` | 数值 / `reset` | 字号覆盖（720p 等效像素） |
| `bold` | `on`/`off`/`reset` | 粗体 |
| `outline` | 数值 / `reset` | 描边粗细 |
| `outline-color` | `#RRGGBB` / `reset` | 描边颜色 |
| `color` | `#RRGGBB` / `reset` | 主颜色（sub-color） |
| `style-preset` | `big-bold`/`original`/`sync-other` | 快捷预设 / 同步到另一轨 |
| `open-fonts` / `rescan-fonts` | — | 字体选择器 / 重新扫描 |
| `reset` | — | 恢复默认（两轨） |
| `fix-override` | — | 把目标轨 override 修成 `scale`（用户设过 `no` 时的前置条件） |
| `preset-apply` | — | 立即把预设样式套到目标轨 |
| `preset-save` | — | 把目标轨当前样式存为预设并写缓存 |
| `preset-reset` | — | 恢复出厂预设（conf 的 `preset_*` 默认值） |
| `preset-toggle-colored` | — | 开关「仅彩色字幕时套用」 |
| `preset-toggle-dual` | — | 开关「双语字幕（双轨）保持原样」 |
| `preset-toggle-enabled` | — | 开关「载入时自动套用」 |
| `inspect` | — | 重新检测字幕样式并输出左上角报告 |
| `toggle-gray` | — | v1.0.6：开关「灰色字幕也自动转黑白」 |
| `toggle-all` | — | v1.0.6：开关「顶部/定位（`\pos`）字幕一并改样式」 |
| `letterbox-toggle` | — | v1.0.7：开关「上下黑边内显示字幕」 |
| `letterbox-refresh` | — | v1.0.7：立即重新检测上下黑边 |

> ⚠ **uosc 菜单 `value` 是命令字符串**，由 uosc 用 `mp.command()` 执行；mpv 命令
> 解析器把裸 `#` 当注释起始符，所以 `color #FFFFFF` 的参数会被整段吞掉，脚本收到
> 空参数并退化成「恢复字幕原样」。所有含 `#RRGGBB` 的 value 必须用 `menu_cmd()`
> 给参数加**双引号**（`color "#FFFFFF"`），含空格的字体名同理。

## 10. 预设样式与样式检测（载入时自动）

```
file-loaded ──► apply_all(false)（恢复记忆的位置/样式）
             └─► +inspect_delay(1.2s) run_inspect()
                     ├─ inspect_style()  检测主色/描边色/字体/字号/内封字体
                     │    ① 外挂轨：parse_ass_file()（[V4+ Styles] Default + [Fonts] 段）
                     │    ② 内封轨：sample_rendered_colors()（screenshot-raw 双帧差分）
                     ├─ is_colored_hex()   饱和度 max-min(RGB) ≥ colored_threshold(40)
                     ├─ 分支一：has_secondary_track() 且 preset.skip_dual
                     │     → 双语跳过：不套用、不改颜色（报告第三行说明原因）
                     ├─ 分支二：preset.enabled 且 (非 only_colored 或 colored)
                     │     → apply_preset()
                     └─ flash_tl(preset_report())  左上角三行报告，report_ms(6s) 后消失
```

**双语（双轨）默认不改颜色**：同时存在次字幕轨（`secondary-sid`）时直接跳过套用——
两条轨往往已各有配色，强行统一反而破坏双语可读性。`preset.skip_dual` 是运行时开关
（菜单「双语字幕保持原样」/ `preset-toggle-dual` 消息，与 only_colored/enabled 同模式：
切换即落盘），conf 的 `preset_skip_dual=no` 可改出厂默认。**手动 `preset-apply` 始终可用**。
E2E 用差分证明：同一个彩色 fixture，单轨（A）套用变白、双轨（E）保持黄色。

**数据源优先级**：外挂文件解析（精确）> 像素采样（内封可用，要求 `sub-text` 非空且
当前未处于我方 force 配色——force 会把 ASS 配色扁平化，采出来全是预设色）。

**预设缓存**：`~~/uosc-subtitle-style-preset.json`（enabled/only_colored/skip_dual/color/
outline_color/outline/font/size/bold）。启动时 `load_preset()` 读取并逐字段覆盖出厂值；
`preset-save`/`preset-reset`/三个开关都会立即落盘。状态文件（`uosc-subtitle-style-state.json`）
与预设文件**分离**：前者是「当前编辑到哪了」，后者是「要套用的目标样式」。

**左上角报告的对齐安全**：`flash_tl` 临时把 `osd-align-x/y` 设为 left/top，
显示后用定时器还原（记录原值，缺省 center/bottom）——否则用户后续所有 OSD 都会跑左上角。
E2E 有还原断言。

---

## 11. 测试体系

### 11.1 单元测试（`tools/sub-style-test.lua`，259 项）

自建 stub：`mp`（全局注入，非 `package.loaded`）、`mp.msg/utils/options`、
可 `seek` 的虚拟文件系统、计时器队列（`flush_timers()` 验证延迟设置）、
合成 sfnt/TTC 字节流（验证字体解析）。

覆盖：分轨模型 / 目标切换 / 共享通道 / 列表读改写 / 状态持久化与旧格式迁移 /
菜单 JSON / 字体解析（name 表、cmap format 4+12、TTC 绝对偏移、图标过滤、缓存命中与失效）/
描边 / 位置避让 / **稳态编辑不重建** / ASS 解析与 `&HAABBGGRR→#RRGGBB` /
像素采样（合成 bgr0 帧）/ 饱和度阈值边界（39 不彩色、40 彩色）/ 预设读写缓存 /
开关与恢复出厂 / `flash_tl` 对齐还原 /
**双语跳过与开关（T34-T35）/ 避让间距可配（T36）/ 报告时长可配（T37）** /
v1.0.6 灰阶识别与共享样式表覆盖 / v1.0.7 黑边贴合（T48-T51）/
v1.0.8 全内封轨检查（T52，13 条：报告统计、切轨重检、灰色识别关闭仍套用、
标准白字 / 外挂 / 开关关闭保持旧行为）。

T48-T51 用 32×200 合成帧（上下各 12 行纯黑、中央 128 灰）走 `screenshot-raw('video')`
逐行亮度检测，覆盖：主轨 100 / 次轨 0 / 两轨限缩倍率 / `sub-margin-y` 居中且为整数 /
开关关闭还原基线 / 手动改位置缩放与外部改属性让位 / `reset` 与 `end-file` 还原 /
暗场、无黑边、黑边过薄、单侧黑边四类误判守卫 / 菜单入口。
其中 `t48-report-restored-after-osd-nudge` 验证黑边重绘的 OSD 微扰不会清掉左上角检测报告。

变异验证（2026-10-22，证明上述新用例有牙）：
双语跳过恒不生效 → 3 用例红；`pos_min_gap` 硬编码 25 → T36 红；
`report_ms` 硬编码 6000 → T37 红。

### 11.2 真机 E2E（`tools/sub-style-e2e.py`）

**阶段一（双字幕轨 + 视觉判据）**：25 条探针断言 + 截图波段分析
（主字幕带 y136-161、次字幕带 y220-244，证明分轨字体/字号互不影响）。

**阶段二（字幕流连续性回归）**：多句 fixture（每 2s 一句），
按 `playback-time` 逐句校验「显示文本 == 期望事件」，
覆盖基线 / 字号编辑后 / 字体编辑后三个窗口（实测各 15 个采样 0 失配）。

**阶段三（预设样式五用例，每次独立运行）**：

| 用例 | fixture | 预期 | 断言 |
| --- | --- | --- | --- |
| A | colored（主色 #FFFF00） | 套用出厂预设 | override=force / 粗细 2 / 白字；左上角报告出现；字幕带黄→白 |
| B | multi（白字） | 保持原样 | override=scale / 粗细 0.5；报告出现；字幕带仍白 |
| C | multi | 修改并保存 | preset.json 落盘含 #FF00FF/#00FF00/4；当前轨样式不被 save 反向覆盖 |
| D | colored + C 的缓存 | 套用缓存预设 | sub-color=#FF00FF / 粗细 4；字幕带出现洋红像素 |
| E | colored + 次轨（双语） | 双轨跳过不套用 | `dual-track-present`（防真空：确认 secondary-sid 真的加载）/ override=scale / 粗细 0.5；报告出现；字幕带**保持黄色**（与 A 同 fixture 差分） |

> ⚠ 每个用例前必须清 `uosc-subtitle-style-state.json`：persist=true 会让上一个用例退出时
> `save_state()` 写下的状态被下一个进程继承（产品设计，测试要干净起点）。
> ⚠ 视觉判据依赖 Pillow，用系统 Python（`C:\Python314\python.exe`）运行 E2E。

**阶段四（v1.0.6 回归，`sub-style-probe-pos.lua`）**：`sub-style-smoke-pos-gray.ass`
把灰色主色 `#8B8B8B` 和带 `\pos` 的顶部字幕放进同一夹具，10 条断言集中复现用户报障：
灰色自动转白、顶部 `\pos` 字幕随样式表变色、`color "#000000"` 不再被注释吞掉、
`FontName` 写进共享列表。顶部字幕像素由 `screenshot-raw` 差分统计。

**阶段五（v1.0.7 黑边贴合，`sub-style-probe-bars.lua`）**：
用 Pillow 生成 640×360、上下各 24px **编码进画面**的黑条图片当视频帧，加载双轨 SRT
（普通对白，无 `\pos`），命令行给 `--sub-margin-y=80` 让关闭贴合时字幕明显压在画面上。
探针**轮询**等自动检测落定（图片 + pause 模式 `file-loaded` 会晚到，固定延时会造成
「先关开关、timer 后到」竞态），然后对比开关前后 `screenshot-raw` 差分像素分布。
本机实测：

| 状态 | 上黑边 top | 画面区 mid | 下黑边 bottom |
| --- | --- | --- | --- |
| 关闭贴合（BASE） | 362 | **653** | 0 |
| 开启贴合（FIT，`scale=0.72`、`margin=2`） | 230 | **0** | 319 |

画面区差分归零，即字幕完全不遮挡视频内容；上下黑边各有一条字幕。
Python 侧另解析 `BARS BASE/FIT` 行做独立复核，不依赖探针自身判定。

> ⚠ 第三方 submodule（`uosc_danmaku` 等）自身的 Lua error 由 `lua_errors()` 按日志
> 标签隔离，被测脚本与探针的任何报错仍然 FAIL；PASS 明细里显式输出忽略行数。

### 11.3 配置门禁（`tools/sub-style-conf-verify.py`）

**mpv conf 不支持行尾注释**（2026-10-22 真机踩坑，冒烟测试才发现）：
`preset_enabled=yes  # 注释` 会把「yes  # 注释」整段当值——布尔/数值项报
`error converting value` 并回落到脚本默认值（**默认值恰好等于期望值时被巧合掩盖**，
E2E 全绿但配置实际没生效）；字符串项则静默把注释吃进值里（`preset_color` 变成
`"#FFFFFF  # 预设主色"`，包含匹配的断言也发现不了）。

门禁按 mpv 解析语义静态复算 conf：R1 键集合与脚本 o 表对齐 / R2 布尔项必须恰好
yes|no|true|false / R3 数值项必须能 parse / R4 字符串项值含 `#` 即报（候选列表键
除外；单色键必须恰好一个 `#RRGGBB`）。变异验证：布尔与单色字符串两类行尾注释均能被抓。
**conf 的注释一律写在独立行。**

### 11.4 尺子纪律（截图不是纯字幕画面）

- 每张截图前先 `show-text ''` 清 OSD——否则 OSD 文字带会与字幕 tiny text 差 2px 被合并
  （**预设报告的探针例外**：报告正是被测对象，用 `subtitles+osd` 一并截取）；
- uosc 底部 UI 区（y>300）与顶栏（y<40）会混入 → 用**按 y 区间找带**代替带序索引；
- 所有 lavfi 真机测试必须 `--watch-later-dir=<tmp> --save-position-on-quit=no --no-resume-playback`
  （否则 watch-later 的 resume 状态会让 file-loaded 多次触发、偶发提前 EOF）。

---

## 12. 关键实证结论（本机，mpv v0.41）

| 结论 | 影响 |
| --- | --- |
| `sub-pos` 地理：5→y9-33 贴顶 / 25→y52-77 / 50→y136-161 / 75→y220-244 / 100→y304-328；**92 一带压 OSC 进度条** | 位置预设据此标定，不做 92 档 |
| `sub-pos/sub-scale` 无 UPDATE flag 但**即时生效** | 位置/缩放不需要重建 |
| `sub-font-size` 无 UPDATE flag，**同 tick 设属性 + 触发重建会读到旧值** | override 的最终值必须延迟一个 tick |
| `configure_ass` 只在 osd_res 变化时重跑 | 用 OSD 微扰推动重配置（0.2s 生效） |
| `sub-reload` 对**内封**字幕直接失败（`cmd_track_reload` 只处理 external） | 不能作为通用重载手段 |
| 重建会打断内封字幕流（外挂靠 preload 免疫） | 架构上「能不重建就不重建」 |
| ffmpeg `ass_probe` 只读首 13 字节 | 外部 .ass 首字节必须是 `[Script Info]`，前置注释会打不开 |
| `script-message-to` 是**异步入队**派发 | 长任务（如首次冷枚举字体）会推迟目标脚本的消息处理；测试等待要覆盖最坏路径 |
| 首次字体枚举冷扫 ~~/fonts（719MB）可超过 1.5s | 探针对首次 `open-fonts` 的检查等待放到 3.5s |
| Pillow 只在系统 Python（`C:\Python314`）可用 | E2E 视觉判据须用系统 Python 跑；缺 PIL 时明确退出 |
| **mpv conf 不支持行尾注释**（`key=value  # 注释` 整段被当值） | conf 注释一律独立行；`sub-style-conf-verify.py` 门禁防回归（布尔报错回落默认值、字符串静默吃注释，都会被默认值/包含匹配巧合掩盖） |
| `mp.command('... color #FFFFFF')` 里 `#` 起注释，参数整段丢失 | uosc 菜单 value 必须 `menu_cmd()` 加双引号；实测裸值收到 `["color"]`，加引号收到 `["color","#FFFFFF"]` |
| `force` 对带 `\pos` 的 `explicit` ASS 事件完全无效 | 顶部 signs 不换字体/颜色；`strip` 会丢 `\pos`；只有 `sub-ass-style-overrides` 的 `FontName/PrimaryColour/OutlineColour` 能改（TOP 黄 1037px → 白 727px 实证） |
| `sub-margin-y` 是 INT，`set_property_native` 传 `2.4` 被静默忽略（属性停在 80），传 `5` 生效 | `compute_barfit` 的 margin 必须四舍五入；本 bug 曾让「属性看得到、画面不动」 |
| 示例视频 3840×2160 上下各 120px 黑条是**编码进画面**的，`osd-dimensions.mt/mb=0` | mpv 原生 margins 帮不上忙；只能逐行亮度扫描视频帧。实测自动贴合后 `scale=0.6`、`margin=2` |
| 灰色 `#8B8B8B` 饱和度为 0，旧「彩色」判据会当成标准白字黑边跳过 | `is_gray_hex()` + `preset_include_gray` 单独识别非纯白/纯黑灰阶 |

---

## 13. 已知边界

1. **粗体不分轨**（mpv 无分轨粗体通道），加粗会触发一次解码器重建；
2. **图形字幕（PGS/VOBSUB）** 不走 libass，位置/缩放/样式均不可调（菜单会提示）；
3. **force 模式的副带效果**：目标轨普通对白幕同时按 `--sub-*` 配色渲染；
   带 `\pos` 的 signs 因 `explicit` 豁免，不受 force 影响 —— v1.0.6 起可用
   `style_override_all=yes` 改写 `sub-ass-style-overrides` 让它们一起变（两轨同变）；
4. **首次样式编辑**必然重建一次（进入 force），此后稳态编辑零重建；
5. 字体族名以 sfnt name 表为准；若某字体族名与实际渲染名不一致，可能匹配失败；
6. **次字幕若是文本字幕（SRT）或处于 `strip` 模式**，其外观由共享的 `--sub-*` 通道决定，
   因此调主字幕的字体/字号会连带影响它的外观（位置不受影响，位置是分轨的）。
   这是 mpv 的「转换/剥离渲染」机制，非本脚本引入。
7. **像素采样的边界**：要求字幕正在显示且当前未处于我方 force 配色；
   若整段采样窗口落在同一句上（长句），采到的可能只是局部像素（已把窗口拉到 3s+ 缓解）；
8. **preset-save 与自动套用的竞态**：载入后 `inspect_delay`（1.2s）内手动改样式再存预设，
   可能被随后触发的自动套用覆盖——属极端时序，正常编辑远晚于该窗口；
9. **E2E 各用例间**：`persist=true` 会跨进程继承状态，测试每个用例前必须清
   `uosc-subtitle-style-state.json`（否则上个用例的 force/白字会被带进下个用例）。
10. **conf 行尾注释**（见 §11.3）：mpv 不支持 `key=value  # 注释`；改 conf 后
    必须跑 `python tools/sub-style-conf-verify.py` + 真机冒烟（grep `error converting`）。
11. **带 `\pos` 的 explicit ASS 事件位置不可调**：`sub-pos` / `sub-scale` /
    `sub-margin-y` 对它全部豁免（本机对示例视频做 9 组参数标定，字幕盒 y 范围恒为
    1858..2038）。黑边贴合只承诺普通 ASS 对白 / SRT / 双轨默认位置；这类 signs
    保持原位，不 strip、不重写事件（strip 会丢定位）。
12. **黑边检测的画面依赖**：靠 `screenshot-raw('video')` 逐行亮度，若画面尚未渲染
    （刚 file-loaded / 全黑淡入）会检测失败；中央亮度守卫防整帧暗场误判，
    失败时不改写任何属性，可用菜单「重新检测上下黑边」手动触发。
13. **`sub-ass-style-overrides` 列表变化会重建一次解码器**：这是覆盖 `\pos` 字幕的
    代价；不希望两轨同变或想零重建时，关掉「顶部/定位字幕一并改样式」。

---

## 14. 检测与布局增补（v1.0.3 ~ v1.0.5）

> 本节记录 §10 之后新增的三条链路：**检测重试**、**auto 标记**、**双语布局**，
> 以及彩色判定的像素阈值演进。§10 讲的是「怎么检测」，本节讲的是「检测失败之后怎么办」。

### 14.1 检测的重试链（v1.0.3）

检测原先只在 `file-loaded` + `inspect_delay`（1.2s）跑一次，字幕没就绪就**永久失败**。修后：

- `run_inspect` 在 `inspect_style` 返 `nil` 时按 `inspect_retry_delay` 重试，上限 `inspect_retries` 次；
- 观察 `sub-text`：**第一句对白由空转非空即触发检测**（对应需求「按第一句底部对话开始识别」）；
- `inspect_armed` 门：首检跑过之前观察器不触发。否则会抢在 `inspect_delay` 前就把字幕转黑白，
  E2E 用例 A/F 的早期截图会红；
- `inspect_gen` 防切文件时旧链继续跑；`inspect_done` 防每句对白重跑；`reset_style` 后重检；
  手动 inspect 强制重检（`allow_retry=false`）。

### 14.2 seek 后重新检测（2026-10-27 修复）

**症状**：片头是 OP/ED 没有底部对白时打开，然后 seek 进正片，彩色字幕**不再被替换**。

**根因**：重试额度是**每文件一次性**的。内封字幕走像素采样，字幕未渲染时 `total==0` → 返 `nil`；
片头 15s 内把额度耗尽后，seek 到正片也**无法再排重试**，一次采样失败就永久放弃。
（外挂 ASS 走文件解析、不受影响，**只有内封会**。）

**修法**：

- `seek` 事件（0.3s 去抖）在 `not inspect_done and inspect_armed` 时刷新 `inspect_attempts=0` 并 `run_inspect`；
- `sub-text` 观察器用 `sub_text_was_empty` 识别「空→非空」的新段，同样刷新额度；
- 新增 `inspect_total` + `INSPECT_TOTAL_CAP=100` 硬上限，防止无界截图；
- `reset_style` / 手动 inspect 也重置总额度。

**测试陷阱**：测「重试兜底」必须让**第一次采样失败**。把「字幕已渲染」设在 seek 之前，
首采即成功、根本走不到重试额度 ⇒ 用例无牙（第一版 T47 就这么写的）。
真实时序是 seek 落地后、字幕**下一帧**才画出来。
另：`sub-ass-override=force` 在**延迟重建定时器**里才写，断言前须再 `flush_timers()`。

### 14.3 彩色判定的像素路径（v1.0.4 修复细彩描边）

外挂 ASS 直接解析 `Default` 样式与 `[Fonts]` 段；内封只能靠 `screenshot-raw` 双帧差分成色
（要求 `sub-text` 非空且当前未处于我方 force）。

判定式：

```
is_colored_hex(主色) or is_colored_hex(真实暗描边)
  or (accent ≠ 主色 and accent 占比 ≥ colored_outline_min[默认 0.5%])
```

- **主色或描边色任一饱和即彩色**（白字 + 紫描边 `#481081` 也判为彩色 → 转黑白）；
- 细彩描边占比常 <2%：实测 `06.mkv` 粉描边 `#ED74CF` 仅 **0.87%**，
  旧的 2% 阈值把它漏判成「非彩色、保持原样」。阈值因此降到 0.5% 且可配；
- `outline_from_accent` 守卫：防止抗锯齿 fringe 被当成描边色而误判；
- 报告新增「饱和 `#xxxxxx`」一行，便于现场核对判定依据；
- **仅彩色才套用预设**，白字保持原样；**双语默认不改颜色**——
  `has_secondary_track() and preset.skip_dual` 时跳过并在报告里说明原因。
  该开关三路可达：`preset-toggle-dual` 消息 / 菜单项 / conf `preset_skip_dual`。

报告用 `flash_tl` 显示在左上角，时长 `report_ms`（6s）；实现上是临时改 `osd-align`，
**用完必须还原**。

### 14.4 `auto` 标记：防跨文件串台

轨上加 `auto` 标记，语义是「这条轨的样式是脚本自己套的」：

| 动作 | `auto` |
|---|---|
| 彩色检测自动套用 | `true` |
| 用户手动改样式 | `false` |

`file-loaded` 时先 `clear_auto_style` 清掉带 `auto` 的轨，再 `apply_all` ⇒ 新文件从**原样**起，
这也保证内封轨的像素检测能看到影片原配色。用户手动设过的样式不带 `auto`，仍跨文件持久。

### 14.5 中日双语布局 `dual_layout`（默认开）

- `compute_layout()` 识别「一条中文 + 一条日文」：内封读 `track-list.lang`；
  **外挂轨的 `lang` 恒为 `nil`**，只能从文件名猜（`.chi.` / `.jpn.` / `.sc.` / `（JP）` / `（CHS）`）；
- 布局：日轨置底（`pos=100`）并 ×`dual_layout_scale`（0.8），中轨放它上方（`100 - pos_min_gap`）；
- 结果写进 per-file 覆盖层 `layout`：**不写状态文件、不跨文件泄漏**；
  `set_pos` / `set_scale` / `adopt_external` 都把 `layout` 置 `nil`（用户一动手就退出自动布局）；
- 与颜色预设**正交**（一个管位置缩放，一个管颜色）；
- **`\pos` 注释幕对 `sub-scale` 豁免**：scale 1→0.4 时对白行高 30→11，而 `\pos` 注释行恒定 30。

### 14.6 E2E 视觉尺子军规

- 截图前先 `show-text ''`，否则 OSD 残留会污染判据；
- 按 y 区间找字幕带：排除顶栏 `y<40` 与底栏 `y>348`；
- **每个用例前删 `uosc-subtitle-style-state.json`**：`persist=true` 会跨进程继承，
  上个用例的 force/白字会被带进下个用例；
- 双语用例（E）必须加 `dual-track-present` 断言，否则「没找到第二轨」也会静默通过；
- 视觉判据用**同 fixture 差分**：单轨 A 变白 vs 双轨 E 保持黄。

### 14.7 仓库与发布

- 独立仓库 <https://github.com/awujiana/uosc_subtitle_style>（AGPL-3.0，v1.0.0 → v1.0.5；
  v1.0.5 起仓库根带 `version.json` 标准清单）。仓库 = `scripts` + `script-opts` + `docs` + `tools`。
- 安装 = 把 `scripts/uosc_subtitle_style.lua` 拖进 mpv 配置目录的 `scripts/`
  （别套成 `scripts/scripts/`），conf 放 `script-opts/`。
- **自 v1.0.5 起 Release 不打包 zip**：直接上传 `uosc_subtitle_style.lua` +
  `uosc_subtitle_style.conf` 两个文件；`version.json` 只留在仓库根，不作为 Release 资产。
- **跨仓库同步前先 diff 基线**：主项目 ↔ 独立仓库的 script/test/fixture 同源可整文件覆盖，
  但 e2e 是**仓库模式变体**（仓库版 `--config-dir=ROOT`，主项目版是用户配置模式），
  直接 `cp` 会悄悄毁掉仓库模式。做法：`git checkout HEAD -- <file>` 恢复仓库版，
  再按仓库版重打（fixture 路径用 `ROOT` 而非 `PORTABLE`），改完 `cmp` 逐个校验。

---

## 15. v1.0.6：四条报障的根因与修复链路

用户报障：点击样式没反应 / 字体切换后内封与外挂字幕都没变化 / 点主颜色左上角显示
「恢复字幕原样」/ 顶部对话字幕有时不转黑白 / 主颜色没有黑色 / 灰色字幕也要自动转黑白。

| 现象 | 实证根因 | 修复 |
| --- | --- | --- |
| 点主颜色变成「恢复原样」 | uosc 菜单 value 是命令字符串，`mp.command()` 把裸 `#FFFFFF` 当注释，参数丢失 → `set_color(nil)` | `menu_cmd()` 给含 `#`/`;` 的参数加双引号；注册器兼容无 `#` 的裸 hex |
| 字体/主色对内封 ASS 无效；顶部字幕不变 | `force` 只覆盖 `!explicit`，示例视频 `sid=3` 是带 `\pos` 的 explicit ASS；实测 force 前后差分像素不变 | `style_override_all` 打开时把 `FontName/PrimaryColour/OutlineColour` 写入 `sub-ass-style-overrides` |
| 灰色 `#8B8B8B` 不自动转黑白 | 旧判据只看饱和度，灰阶饱和度为 0 被当成「标准白字黑边」 | `is_gray_hex()` + `preset_include_gray` + `needs_preset()`，并加 `toggle-gray` |
| 点完样式菜单就关、看不到选中态 | uosc 根级 `keep_open` 未开，且改完没有刷新菜单 | 根级 `keep_open=true`；`flash()` 调 `refresh_menu()`（`update-menu` 保留滚动与搜索状态） |

同时：`colors` 候选补 `黑=#000000` 与三级灰阶（脚本内 `o.colors` 默认值同步，
避免无 conf 环境缺黑色）；新增 `toggle-all` 让用户可以退出「共享样式表」模式。

回归：`tools/sub-style-smoke-pos-gray.ass`（灰主色 + `\pos` 顶部事件）、
`tools/sub-style-probe-pos.lua`（10 条真机断言）、E2E 阶段四、
`sub-style-probe.lua` 的判据从 `font-not-leaked-to-shared-list` 改成
`font-in-shared-list-for-pos-signs` + `toggle-all-clears-shared-style`
（视觉分轨字体断言前先关共享覆盖，否则主轨像素会被共享 `FontName` 带偏）。

---

## 16. v1.0.7：视频内嵌上下黑边贴合

### 16.1 为什么必须自己检测黑边

示例视频 `Dead-End...mkv` 是 3840×2160，上下各 120px 黑条**编码在画面里**，
`osd-dimensions.mt/mb = 0`；`sub-use-margins` / `sub-ass-force-margins` 处理的是
窗口/全屏 letterbox，对这类 baked-in bars 完全无效。只有读视频帧像素才知道黑条在哪。

### 16.2 检测与布局

```
detect_bars(screenshot-raw('video'))
  逐行平均亮度 = 0.299R + 0.587G + 0.114B（列步长 letterbox_sample_step）
  守卫：中央 40%~60% 平均亮度 < dark_luma×2 ⇒ 整帧暗场/淡入淡出，返回 nil
  顶部扫前 45% 的连续暗行、底部倒扫后 45% ⇒ top_frac / bottom_frac
        ↓ compute_barfit（纯函数，可单测）
  min_bar 过滤过薄黑边；取上下较薄一侧 bar_frac
  usable_px = frame_h × bar_frac × (1 - pad)
  unit      = sub-font-size × 1.2 × (frame_h / 720)      # 实测字幕盒高估算
  scale     = clamp(usable_px / unit, 0.1, 3)，且不超过 1（黑条够宽不放大）
  margin_y  = round((frame_h×bar_frac - unit×scale) / 2 / (frame_h/720))   # 必须取整
        ↓ apply_all
  主轨 sub-pos=100 / 次轨 secondary-sub-pos=0，两轨 scale 相同
  共享 sub-margin-y = margin_y（上下对称，一条 margin 同时服务两轨）
        ↓ nudge_reconfigure()
  sub-margin-y / sub-scale 无 UPDATE flag，需 show-text ' ' 60 触发 configure_ass
```

### 16.3 生命周期（per-file 覆盖层，不落状态文件）

- `barfit` 只在当前文件有效，优先级高于 CN+JP 双语布局；
- `barfit_gen` 在 `end-file` / `file-loaded` 自增，作废上个文件遗留的检测定时器；
- 触发时机：`file-loaded` 后 `inspect_delay + letterbox_delay`；菜单
  「重新检测上下黑边」可随时手动重跑；
- **让位**：用户手动 `set_pos` / `set_scale`、`adopt_external`（r/t 键或别的脚本改属性）、
  `reset_style` 都会 `disable_barfit()`；
- **还原**：`disable_barfit()` 把共享的 `sub-margin-y` 还回 `baseline.margin_y`
  并 `nudge_reconfigure()`，否则会跨文件泄漏、且画面停在上个位置不动；
- **报告补回**：黑边重绘的 OSD 微扰会清掉左上角检测报告，
  `last_report_text` 在 `refresh_barfit()` 末尾把原报告重新 `show-text` 一遍。

### 16.4 配置（`script-opts/uosc_subtitle_style.conf`）

`letterbox_fit` / `letterbox_min_bar` / `letterbox_dark_luma` / `letterbox_pad` /
`letterbox_sample_step` / `letterbox_delay`，默认开启、菜单可关。

### 16.5 硬边界与真机结果

带 `\pos` 的 explicit ASS 事件对 `sub-pos` / `sub-scale` / `sub-margin-y` 全部豁免，
保持原位（用户确认的实现范围，不 strip、不重写事件）；窗口 letterbox 交给 mpv 原生。

| 场景 | 结果 |
| --- | --- |
| 合成 640×360 上下 24px 黑条 + 双轨 SRT | BASE 画面区 653 字幕像素 → FIT **0**；上黑边 230 / 下黑边 319（E2E 阶段五） |
| 示例视频 4K 上下 120px 黑条、内封 ASS | 自动检测 `scale=0.6` / `margin=2` / 主轨 `pos=100`，无脚本报错，播放不中断（osd mt/mb=0） |

E2E 阶段五还会校验 `sub-margin-y` 是整数 —— 这是真机踩过的坑：
`mp.set_property_native('sub-margin-y', 2.4)` 会被 mpv 静默忽略。

## 17. v1.0.8：所有的内封字幕都要被检查

### 17.1 报障与真机事实

用户截图（示例 `Dead-End...mkv`）：左上角报告
`内封字幕(像素采样)：主色 #8B8B8B · 描边 #000000 · 饱和 #001A29` /
`非彩色字幕，保持原样` —— 灰色内封字幕没有转成白字黑边。

两个独立原因叠加：

1. **截图里的文案是 v1.0.5 旧版**（新版为「非彩色字幕，保持原样（标准白字黑边）」）。
   自更新器曾把本地 v1.0.7 降级成远端 v1.0.5，用户当时 mpv 内存里跑的是旧脚本；
   该事故已由 `ae34ba8`（`@version` 版本守卫 + 禁止降级）修复，**需要重启 mpv 才加载新脚本**。
2. 即便加载新版，检测范围仍不完整：`inspect_style()` 只看**当前选中的一条轨**
   （`current_sub_path()` 取 `sid`/`secondary-sid`），成功后 `inspect_done=true`
   使本文件不再重检；套用又依赖「彩色 / 灰阶」两个窄颜色判据。

真机实测（`screenshot-raw` 探针，2026-11-05）：这支 4K MKV **有 42 条内封字幕轨**
（`id=1..42`，当前 `sid=3`）。旧逻辑只检查 1 条，其余 41 条切换过去时永远不会被检查，
也不会按规则套用样式。这是「所有的内封字幕都要被检查」的直接依据。

### 17.2 实现

| 新增 | 作用 |
| --- | --- |
| `internal_subtitle_tracks()` | 枚举 `track-list` 中 `type=sub` 且 `external=false` 的全部轨，按 id 排序 |
| `current_internal_id()` | 当前目标轨若是内封，返回 id；外挂返回 nil |
| `inspected_internal` | per-file 账本（key=轨 id），`file-loaded` 时清空 |
| `is_standard_black_white(info)` | 唯一保留原样的内封例外：非彩色 + 主色各通道 ≥ 235 |
| `sid` / `secondary-sid` 观察器 | 切到尚未检查过的内封轨 → 重置 `inspect_done`、刷新重试额度、重跑检测 |

检测报告新增一行 `内封字幕轨：共 N 条，已检查 M 条（当前 X），待检查 …`；
待检查列表**最多列 6 个 id**，其余用「等 N 条」概括 —— 42 条轨全列会把左上角 OSD 撑出屏幕。

切轨重检前必须先 `clear_auto_style(state.main/sec)` + `apply_all(false)`：
内封像素采样要求「还没被我们的 force 白字覆盖」，否则 `wants_force()` 为真会让
`inspect_style()` 直接放弃采样，看起来「检查过了」其实什么都没采到。
`clear_auto_style` 只清 `auto=true`，用户手动设过的样式不动。

### 17.3 套用判据（不破坏历史规则）

`needs_preset()` 顺序不变，只在末尾追加内封分支：

```
only_colored=false → 一律套用
info.colored       → 套用（白字+彩描边 / 薄彩描边 / 饱和阈值边界）
include_gray && is_gray_hex(color) → 套用（v1.0.6；区间放宽到亮度 [30,235]）
preset_all_internal && 当前是内封轨 && !is_standard_black_white(info) → 套用（v1.0.8）
其余 → 保持原样
```

- 外挂字幕不受 `preset_all_internal` 影响（样式来自文件解析，用户常有意保留配色）。
- 「标准白字」例外**不查描边色**：像素采样会把少量高饱和抗锯齿 fringe 记成 accent
  并派生 `outline_color`（白字 + 0.33% 粉边），拿它判「非黑描边」会误转；
  真彩描边由 `info.colored` 负责，T46b 守卫继续有效。
- `preset.skip_dual`（双语双轨保持原样）与「检查」是两件事：双轨仍会全部检查并报告，
  只是不改颜色（用户此前确认的默认行为）。

### 17.4 配置与真机结果

`script-opts/uosc_subtitle_style.conf` 新增 `inspect_all_internal=yes` /
`preset_all_internal=yes`，两项都关即回到 v1.0.7 行为（T52 有回归断言）。

真机（示例视频，`--pause=yes --start=00:12:30`，`persist=no` 隔离状态文件）：

```text
INTERNAL_TRACKS=42 IDS=1..42
SID=3  SUB_COLOR=#FFFFFFFF  ASS_OVERRIDE=force  SHARED_PRIMARY=true
```

即灰色内封字幕被检出并套用，`PrimaryColour=&H00FFFFFF` 已写入共享
`sub-ass-style-overrides`（带 `\pos` 的顶部字幕 / signs 也会变色）。
`uosc_danmaku` 的 `sites/iqiyi.lua:17` 报错是第三方 submodule 已知问题，与本次改动无关。

> ⚠ 改本脚本功能必须同步递增文件头 `-- @version: X.Y.Z`：
> `script-modules/updater.lua` 以它判定本地版本，本地 ≥ 远端时不更新、禁止降级。
> 本次 v1.0.7 → **v1.0.8**。
