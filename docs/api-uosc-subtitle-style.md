# uosc_subtitle_style 对外 API

> 适用版本：`uosc_subtitle_style.lua` ≥ **1.0.10**，API 版本 `1.0.0`。
> 面向「别的 mpv 脚本 / 自定义按键 / 外部工具」读取本脚本状态、触发其动作。
> 架构背景见 [uosc-subtitle-style-architecture.md](uosc-subtitle-style-architecture.md)。
> v1.0.11 起快照新增 `ass_pos_shift_active` / `ass_y_ratio` / `barfit.y_ratio` /
> `barfit.anchor_target` / `runtime.{ass_pos_shift,show_report,report_shown}` 与两个白名单动作；
> v1.0.13 起新增 `internal_tracks`（字段表里已逐项标注）；这些都是**可选附加字段**，
> 旧调用方无需改动。
>
> v1.0.13 起左上角 OSD 检测报告**不再**输出「内封字幕轨：共 N 条，已检查 M 条」——
> 切轨已改为一律重新检测，按轨账本不再参与放行，该文案会让人误以为漏检。
> 同一份进度信息改由 `state.internal_tracks` 结构化输出；**不新增 message、不改 API 版本**。

## 1. 设计边界

| 项目 | 约定 |
|---|---|
| 脚本名（`script-message-to` 目标） | `uosc_subtitle_style` |
| API 版本 | `1.0.0`（独立于脚本版本；只读字段增加不升版本，字段语义/删除才升 MINOR/MAJOR） |
| 传输 | mpv `script-message` + `user-data` 属性；**不依赖 uosc**，无 uosc 时全部可用 |
| 方向 | ① 主动订阅（状态广播）② 请求-响应（查询）③ 白名单动作转发 |
| 兼容性 | 纯附加；所有 v1.0.9 及更早的 `script-message` 入口**原样保留**，参数与副作用不变 |
| 失败策略 | 任何参数校验失败/编码失败只写日志或回 `ok=false`，**不抛错、不影响字幕主流程** |

API 只提供**只读状态快照**和对既有入口的**白名单转发**，不新增任何字幕属性写入路径，
因此不会触发解码器重建，也不会打断字幕流。

## 2. 通道一：`user-data` 状态广播（推荐订阅）

脚本加载完成、以及每次 `apply_all()` / `flash()`（即任何菜单动作、自动预设、黑边重算）
都会刷新下面两个属性：

| 属性 | 类型 | 说明 |
|---|---|---|
| `user-data/uosc_subtitle_style/version` | string | API 版本，如 `1.0.0`；脚本加载后写一次 |
| `user-data/uosc_subtitle_style/state` | string | **JSON 字符串**，见 §3 字段表；状态变化时覆盖 |

订阅示例（另一个脚本）：

```lua
local mp, utils = require('mp'), require('mp.utils')
mp.observe_property('user-data/uosc_subtitle_style/state', 'native', function(_, raw)
    if type(raw) ~= 'string' then return end
    local ok, st = pcall(utils.parse_json, raw)
    if ok and st and st.barfit_active then
        mp.msg.info(('黑边贴合中：上 %.3f 下 %.3f 倍率 %.3f')
            :format(st.barfit.top, st.barfit.bottom, st.barfit.scale))
    end
end)
-- 晚加载的脚本直接读一次，不依赖「变化事件」
local raw = mp.get_property_native('user-data/uosc_subtitle_style/state')
```

> ⚠ **必须用 `native`**：`user-data` 是 mpv 的 node 属性，`mp.get_property()`
> 与 `observe_property(..., 'string')` 拿到的是**带引号、二次转义的 JSON 文本表示**
> （`version` 会变成 `"1.0.0"`，`state` 无法直接 `parse_json`）。真机实测见
> `tools/sub-style-probe-api.lua` 的 `api-userdata-version-is-native-string` /
> `api-subscribe-native-observer` 断言。
>
> 旧版 mpv 不支持写 `user-data` 时脚本用 `pcall` 兜住，广播通道静默失效，
> 但通道二（请求-响应）仍可用。

## 3. `state` 字段表

值为 JSON 对象。**值为 `nil` 的字段会被 `utils.format_json` 省略**（例如未设字体时没有 `main.font`、
未检出黑边时没有 `barfit`），取值前请判空。

| 字段 | 类型 | 说明 |
|---|---|---|
| `api_version` | string | 固定 `1.0.0` |
| `script_name` | string | 固定 `uosc_subtitle_style` |
| `target` | string | 当前编辑目标轨：`main` / `sec` |
| `main` / `sec` | object | 两轨各自样式，子字段见下 |
| `main.pos` / `sec.pos` | number | 位置百分比，0=顶部 100=底部 |
| `main.scale` / `sec.scale` | number | 缩放倍率（相对字幕原始大小） |
| `main.size` / `sec.size` | number? | 字号 px；省略表示「字幕原样」 |
| `main.font` / `sec.font` | string? | 字体名；省略表示原样 |
| `main.bold` / `sec.bold` | boolean? | 粗体 |
| `main.color` / `sec.color` | string? | 主色 `#RRGGBB` |
| `main.outline` / `sec.outline` | number? | 描边宽度 |
| `main.outline_color` / `sec.outline_color` | string? | 描边色 |
| `main.pos_owned` / `sec.pos_owned` | boolean | 位置是否由本脚本设定（否则脚本只观察不回写） |
| `main.auto` / `sec.auto` | boolean | 当前样式是否由彩色检测自动套用的预设写入 |
| `barfit_active` | boolean | 上下黑边贴合是否生效 |
| `barfit` | object? | 生效时存在：`top` / `bottom`（占帧高比例）、`scale`（限缩倍率）、`margin_y`（整数 px）、`y_ratio` / `anchor_target`（v1.0.11，内封 `\pos` 位移用，仅内封 ASS 时存在） |
| `ass_fontsize_active` | boolean | 内封定位 ASS 的 `Fontsize` 通道是否激活（v1.0.9） |
| `ass_pos_shift_active` | boolean | 内封定位 ASS 的 `PlayResY` 垂直位移通道是否激活（v1.0.11） |
| `ass_y_ratio` | number | 当前应施加的 Y 坐标系放大倍率（1 = 不位移）；由黑边贴合或 1% 微调反解，见架构文档 §20.3 |
| `internal_tracks` | object | **v1.0.13**：内封轨检查进度；OSD 不再显示该文案，改由此字段输出 |
| `internal_tracks.total` | number | 当前文件的内封字幕轨总数（不含外挂） |
| `internal_tracks.checked` | number | 本文件内已成功检出过的内封轨数；v1.0.13 起**只作记录**，不影响切轨是否重检 |
| `internal_tracks.current_id` | number? | 当前目标轨是内封时的轨 id；当前是外挂轨时省略 |
| `internal_tracks.current_is_internal` | boolean | 当前目标轨是否为内封轨 |
| `internal_tracks.pending` | string[] | 本文件尚未检出过的内封轨 id（字符串），例 `["2","5"]` |
| `runtime.override_all` | boolean | 运行时开关：样式覆盖所有轨 |
| `runtime.include_gray` | boolean | 灰阶字幕是否纳入黑白预设 |
| `runtime.bar_fit` | boolean | 黑边贴合开关 |
| `runtime.ass_fontsize` | boolean | ASS 字号通道开关 |
| `runtime.ass_pos_shift` | boolean | 内封定位 ASS 位移通道开关（v1.0.11） |
| `runtime.show_report` | boolean | 左上角检测报告 OSD 开关（v1.0.11）；只关显示，不关检测/预设/黑边贴合 |
| `runtime.report_shown` | number | 实际输出过几次左上角消息（v1.0.11）；供门禁验证开关是否生效 |
| `preset.enabled` | boolean | 载入时自动套用预设 |
| `preset.only_colored` | boolean | 仅彩色/灰色字幕套用 |
| `preset.skip_dual` | boolean | 双语双轨跳过 |
| `preset.color` / `outline_color` | string | 预设主色 / 描边色 |
| `preset.outline` / `size` | number? | 预设描边 / 字号 |
| `preset.font` | string? | 预设字体 |
| `preset.bold` | boolean? | 预设粗体 |

## 4. 通道二：请求-响应

### 调用格式

```text
script-message-to uosc_subtitle_style api <reply_to> <request_id> <action> [args...]
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `reply_to` | ✅ | 接收回复的**脚本名**（`mp.get_script_name()`）；只允许 `[A-Za-z0-9_.-]`，≤128 字符 |
| `request_id` | ✅ | 调用方自定义关联 id，原样回填；字符集同上 |
| `action` | ✅ | `get-state` / `get` / `list-actions` / `call` |

回复通过 `mp.command_native` 数组形式发出（JSON 里的空格/引号不会被命令解析器拆开）：

```text
script-message-to <reply_to> uosc_subtitle_style-api-response <request_id> <json>
```

接收方注册：

```lua
mp.register_script_message('uosc_subtitle_style-api-response', function(request_id, json)
    local ok, res = pcall(utils.parse_json, json)
    if ok and res.ok then -- ...
    end
end)
```

所有成功响应都含 `ok=true` 与 `request_id`；失败响应含 `ok=false`、`error`。

### action 一览

| action | 额外参数 | 成功响应 |
|---|---|---|
| `get-state` | 无 | `{ok, request_id, data=<§3 快照>}` |
| `get` | `<dotted.key>` | `{ok, request_id, key, value}`；点号路径如 `main.pos`、`barfit.scale`、`runtime.bar_fit` |
| `list-actions` | 无 | `{ok, request_id, actions=[...]}`；可被 `call` 转发的白名单动作名 |
| `call` | `<action_name> [args...]` | `{ok, request_id, dispatched, async=true}` |

### `call` 语义与白名单

`call` 把请求**转发给本脚本已注册的原生入口**，复用既有参数处理与副作用：

```text
script-message-to uosc_subtitle_style api my_script c1 call nudge -5
→ script-message-to uosc_subtitle_style nudge -5          # 内部转发
→ script-message-to my_script uosc_subtitle_style-api-response c1 {"ok":true,...}
```

- **`async=true`**：先回复「已派发」，动作随后执行。要观察结果请订阅 §2 的 `state` 广播，
  不要在收到回复时假设属性已经变化。
- 白名单含 30 个入口（菜单/位置/缩放/字号/颜色/预设/黑边/检测等，v1.0.11 新增
  `ass-pos-shift-toggle` 与 `report-toggle`），完整列表用 `list-actions` 动态获取；
  **刻意不含 `api` 与 `uosc-version`**，防止外部脚本递归进入 API 通道或伪造 uosc 可用性。
- 参数原样转发，校验由原生入口负责。

### 错误码

| `error` | 触发条件 | 是否回复 |
|---|---|---|
| `bad_key` | `get` 缺 key / key 含非法字符 | ✅ |
| `unknown_key` | `get` 路径不存在或值为 nil | ✅ |
| `unknown_action` | `action` 不在四个受支持值里 | ✅ |
| `bad_action_name` | `call` 缺动作名 / 非法字符 | ✅ |
| `action_not_allowed` | `call` 的动作不在白名单 | ✅ |
| `dispatch_failed` | 内部转发抛错 | ✅ |
| `encode_failed` | JSON 编码失败（回复体退化为固定错误串） | ✅ |
| — | `reply_to` / `request_id` 非法 | ❌ 只写 `warn` 日志，不向未知目标发消息 |

## 5. 完整调用示例

```lua
local mp, utils = require('mp'), require('mp.utils')
local SELF = mp.get_script_name() or 'my_script'
local pending = {}

mp.register_script_message('uosc_subtitle_style-api-response', function(rid, json)
    local ok, res = pcall(utils.parse_json, json)
    if not ok or not res then return end
    local cb = pending[rid]
    if cb then pending[rid] = nil; cb(res) end
end)

local function request(action, ...)
    local rid = tostring(math.random(100000, 999999))
    mp.command_native({'script-message-to', 'uosc_subtitle_style',
                       'api', SELF, rid, action, ...})
    return rid
end

-- 查询当前主字幕位置
request('get', 'main.pos')

-- 读取完整状态
request('get-state')

-- 触发「上移 1%（微调）」（v1.0.11 起菜单步长 1%，nudge 入口接受任意 ±%）
request('call', 'nudge', '-1')

-- 触发黑边重算
request('call', 'letterbox-refresh')

-- 关闭左上角检测报告（v1.0.11）；conf 用 show_report=no 可永久关闭
request('call', 'report-toggle')
```

`input.conf` 里也可以直接用（无需写脚本，但拿不到回复）：

```conf
# 查询状态（回复需要有脚本注册 uosc_subtitle_style-api-response 才有意义）
F9 script-message-to uosc_subtitle_style api my_script k1 get-state
```

## 6. 门禁覆盖

| 层 | 位置 | 判据 |
|---|---|---|
| 单测 | `tools/sub-style-test.lua` **T54**（20 条） | 注册/初始广播、`get-state` 形状与 id 回填、`get` 命中与未命中、非法 token 不回复、未知 action、白名单不含 `api`、`call` 转发参数、拒绝递归、状态变更自动刷新、原生入口不被覆盖 |
| 单测 | `tools/sub-style-test.lua` **T55**（18 条） | 上下黑边双对白自适应：`get-state` 的 `barfit.scale/top/bottom` 必须与真实 `sub-scale` / 黑边比例一致 |
| 单测 | `tools/sub-style-test.lua` **T56**（v1.0.11） | `get-state` 快照含 `ass_pos_shift_active` / `ass_y_ratio` / `barfit.y_ratio` / `barfit.anchor_target` |
| 单测 | `tools/sub-style-test.lua` **T57**（v1.0.11） | `runtime.show_report` / `report_shown` 在快照内、`report-toggle` 在白名单可转发 |
| 真机 E2E | `tools/sub-style-probe-api.lua` + `tools/sub-style-e2e.py` 第 5f 组 | 真实 mpv 下 `user-data` 可读、请求-响应可达、`call` 真正改变位置并刷新广播；两个脚本共 21 条断言 |
| 真机 E2E | `tools/sub-style-e2e.py` 第 5h 组（v1.0.11） | `show_report=yes\|no` 两轮对照下用 `report_shown` 验证 API 状态与 `report-toggle` 双向生效 |
| 单测 | `tools/sub-style-test.lua` **T52**（v1.0.13） | OSD 报告不再含「内封字幕轨：…」；`internal_tracks.{total,checked,current_id,current_is_internal,pending}` 随切轨记账 |
| 真机 E2E | `tools/sub-style-probe-reinspect.lua` + 第 5k 组（v1.0.13） | 真实 mpv 下 `internal_tracks` 可读、`total=1`，且切到外挂轨时 `current_is_internal=false` |
| 语法/配置 | `lua-syntax-check.lua` / `sub-style-conf-verify.py` | 全量 Lua 语法、conf 键集合对齐 |

## 7. 版本与兼容承诺

- API 版本 `1.0.0` 起：§3 已列出的字段**只增不删**；新增可选字段不升 MINOR。
- 删除字段、改变字段类型/单位、改变 `error` 值语义 → 升 MINOR；改变调用格式或回复消息名 → 升 MAJOR。
- 脚本自身版本号（`-- @version:`）与 API 版本**相互独立**：脚本任何功能改动都必须按
  `script-modules/updater.lua` 的规范递增 `@version`，否则自更新器会误判本地版本。
