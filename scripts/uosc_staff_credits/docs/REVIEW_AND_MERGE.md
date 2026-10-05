# uosc_staff_credits 脚本审查与合并评估报告

> 审查对象：`portable_config/scripts/uosc_staff_credits/`（约 21,800 行 / 60 个 Lua 文件）
> 审查目的：① 学习其 OSD 面板与按钮组件实现；② 检查脚本问题；③ 判断与本地 `osd-button` 组件的合并取舍
> 审查日期：2026-10-05
> 结论摘要：**不合并为一个脚本。仅吸收 3 项实现亮点，另有 6 处问题需修。**

---

## 0. 结论速览

| 维度 | 结论 |
|------|------|
| 与 `osd-button` 组件的关系 | **互补而非重复**。本项目已有 3 个通用 UI 组件（`pagination` / `overlay_manager` / `mouse_interaction`），无需引入外部按钮组件 |
| 是否合并 | **不合并**。合并会破坏其单例鼠标模型与纯函数组件约定 |
| 值得吸收 | ① 关闭按钮"绘制+命中"同源；② 位置单位与尺寸单位来源统一；③ 三态按钮配色 |
| 必须修 | 6 处（见 §3），其中 3 处已修复（见 §8） |
| 集成现状 | ✅ 已接入 —— conf / `input.conf` 绑定 / .gitignore 均已补齐（见 §5） |

---

## 1. 项目架构速览

### 1.1 分层

```
main.lua (19 行，仅引导)
  └─ app/
      ├─ bootstrap.lua        启动装配、依赖注入
      ├─ dispatcher.lua       脚本消息路由 + path_observer
      ├─ search_pipeline.lua  搜索管线（含中文标题转换）
      ├─ loading_controller.lua 加载菜单倒计时
      ├─ request_registry.lua 请求注册与取消
      └─ state.lua            全局状态
  └─ features/   业务功能（staff_credits / character_cards / cover_intro_flow /
                 subject_select / fankuhub_search / production_score_flow）
  └─ modules/    UI 与工具（4 面板 + 3 通用组件 + utils/*）
  └─ apis/       数据源适配（bangumi / fankuhub / anilist / mal / baike / dandanplay）
```

### 1.2 三种模块工厂（`modules/utils/module_loader.lua`）

| 工厂 | 返回 | 用途 |
|------|------|------|
| `make_init(name, schema)` | `(opts, deps, init)` | 普通模块，可收配置 |
| `make_feature_init(name, schema)` | `(deps, init)` | features 层，配置经 deps 间接传递 |
| `make_set_opts(initial)` | `(opts, set_opts)` | 旧式兼容 |

均带**单次初始化保护**（重复 init 仅 warn）与 **deps schema 校验**（类型不符仅 warn 不阻断）。

### 1.3 面板模块工厂（`ui_base.make_panel_module(name, target)`）

注入 7 个公共成员，是 4 个面板的统一骨架：

| 成员 | 作用 |
|------|------|
| `register_keys(key_defs)` | 批量注册（先自动 `unregister_keys()`），每项 `{key, name, fn, forced?, opts?}` |
| `unregister_keys()` | 批量移除 |
| `register_osd_observers(on_change, props, debounce_ms, is_visible)` | OSD 属性观察 + 防抖 + 可见性门控 |
| `unregister_osd()` | 注销全部 observer |
| `set_cleanup(fn)` | 注册模块私有清理回调 |
| `close()` | 通用关闭骨架：`visible=false → cleanup → unregister_keys → unregister_osd → enable_uosc` |
| `init_panel(deps, iface)` | 存 deps 并自注册到 `panel_registry` |

**面板互斥**由 `panel_registry.close_all_except(name)` 实现：先收集待关闭列表再逐个 `pcall(close)`，避免遍历中改表。

### 1.4 关键约定：`ui_scale` 与 overlay 分辨率

```lua
ui_scale = osd_w / 1920            -- 以 1920 为基准（注意是宽，不是高）
s(v) = math.floor(v * ui_scale)
overlay.res_x = osd_w              -- 必须等于 osd_w
overlay.res_y = osd_h              -- 必须等于 osd_h
```

> ⚠️ 与 `chapterskip.lua` 的差异：后者用 `scale = 高度 / 1080`，本项目用 `ui_scale = 宽 / 1920`。
> 16:9 下两者等价；**非 16:9 或非 1080p 时不等价**。这是本项目既有约定，跨项目搬代码时需换算。

---

## 2. 值得吸收的实现亮点（3 项）

### 2.1 关闭按钮：绘制与命中共用同一份坐标 ✅

```lua
-- 渲染时写入：state.close_btn = {x = close_x, y = close_y, size = close_size}
-- 命中时直接读：
if state.close_btn then
    local cb = state.close_btn
    if mx >= cb.x and mx < cb.x + cb.size
       and my >= cb.y and my < cb.y + cb.size then
        M.close()
        return
    end
end
```

**做对了什么**：命中矩形不是另算一套，而是**渲染时把矩形存进 state，命中时直接复用**。
彻底消除"绘制坐标改了、命中坐标忘了改"的漂移——这正是按钮"位置不偏"的根本保障。

> 对比 `chapterskip.lua`：那里是每次命中时用公式**重新推导** `button_x/button_y`，两处公式必须永远同步。
> 本项目"存储而非重算"更稳，值得反向吸收。

### 2.2 位置与尺寸全部源自同一组 `s()` ✅

```lua
local s = layout.s                              -- 由 osd_w 派生的缩放函数
local close_size = layout.s(28)                  -- 尺寸
local close_x = layout.start_x + layout.total_w + layout.s(12) - close_size  -- 位置
local close_y = layout.title_y                   -- 位置
```

尺寸与位置**用同一个 `s()`**，因此窗口缩放时两者同比例变化，不存在"字变大了、边距没变"的错位。
这正是 `chapterskip.lua` 中 `scale` 单一基准的同构做法，但本项目把它封装进 `layout.s` 更整洁。

### 2.3 三态按钮配色 + 九宫格布局语义 ✅

`pagination.lua` 的三态（禁用 / 默认 / 悬停）是干净的可复用设计：

| 状态 | 背景 | 文字 | 边框 | Alpha |
|------|------|------|------|-------|
| 禁用（首页/末页） | `1A1A20` | `606060` | 无 | `80` |
| 默认 | `2A2930` | `88C0FC` | 无 | `C0` |
| 悬停 | `3A3940` | `88C0FC` | `88C0FC` 2px | `D0` |

且支持 `pagination_position = top/middle/bottom`，`bottom` 特意 **上移 40px 避开 uosc 控制条**——
这是"按钮不被遮挡"的实战经验，可移入 `osd-button` 作为默认避让策略。

---

## 3. 发现的问题（6 处，按严重度排序）

### 🔴 P1-1：`state.hover_button` 未在状态表中初始化

**证据**：

```lua
-- modules/staff_grid.lua:44-55  状态表只有 hover_index，没有 hover_button
local state = {
    visible = false, items = {}, title = "", offset = 0,
    layout = nil, overlay = nil, render_version = 0,
    hover_index = 0,       -- 由 mouse_interaction 管理
    close_btn = nil,
}

-- :346  show() 里才第一次赋值
state.hover_button = nil

-- :441  清理时才赋值
state.hover_button = nil
```

**影响**：`pagination.render()` 首行执行 `local hover_button = state.hover_button`（读 nil，Lua 中合法），
渲染层不会崩；但 `state.hover_index = 0` 与 `hover_button = nil` 语义上应同时初始化。
目前靠"nil 读取合法"侥幸通过，属**隐性依赖**，一旦有人在 `pagination.render` 里写
`#state.hover_button` 或 `state.hover_button:sub(...)` 就会崩。

**修复**：在状态表初始化处补一行

```lua
hover_button = nil,    -- 由 pagination/mouse_interaction 管理（"prev"/"next"/nil）
```

---

### 🟠 P2-2：`show(new_deps, items, title)` 首参实为废弃参数，文档未同步

**证据**（修复前的原始代码）：

```lua
-- modules/staff_grid.lua:323（修复前）
function M.show(new_deps, items, title)
    -- new_deps 是签名参数（cards 模块使用闭包注入的 deps），此处忽略
```

**调用方**（修复前）：

```lua
-- features/staff_credits.lua:104 与 :222
deps.staff_grid.show(deps, items, title)
```

**影响**：传入的 `deps` 被**静默丢弃**，函数体改用 upvalue `deps`（来自 `make_init`）。
功能上正确，但签名与行为不符，极易误导后续维护者以为传参生效（例如想给某次调用传临时配置）。

**状态**：✅ 已修（2026-10-05）—— 签名改为 `show(items, title)`，两处调用同步。

**修复**（二选一）：
- **推荐**：调用方改为 `deps.staff_grid.show(items, title)`，签名同步为 `show(items, title)`
- 或：保留签名但加注释说明"首参仅为兼容旧签名，实际使用模块级 deps"

---

### 🟠 P2-3：`register_osd_observers` 每次 `show()` 都重新注册

**证据**（修复前的原始代码）：

```lua
-- modules/staff_grid.lua:375-379（修复前）
M.unregister_osd()
M.register_osd_observers(function()
    if state.visible then render() end
end, {"osd-width", "osd-height"}, 100, M.is_visible)
```

**影响**：每次打开面板都 `unobserve` + `observe` 一遍，产生无谓的属性订阅抖动；
且 `ui_base` 内部闭包 `debounce_timer` 每次重建，若上一次的防抖定时器尚未触发，
旧 `unreg_fn` 虽被调用但其闭包已与新实例解耦——存在**防抖定时器泄漏**的边界风险。

**状态**：✅ 已修（2026-10-05）—— 移至 `M.init()` 一次性注册。
`is_visible` 门控已能保证不可见时不重绘，无需在 `show()` 里重建。

---

### 🟠 P2-4：关闭按钮未纳入 `mouse_interaction` 的 `hit_test`

**证据**：

```lua
-- :143-151  on_mouse_click 里手动优先检测关闭按钮
if state.close_btn then ... M.close() ... end
pagination.on_click(...)
```

但 `hit_test`（`:379-400`）**只返回翻页按钮与单元格**，不含关闭按钮。

**影响**：鼠标移到右上角 ✕ 上**不会高亮**（`hit_test` 返回 nil → `hover_index=0`）；
用户无法从视觉上确认 ✕ 可点。功能可用（点击走 `on_mouse_click`），但交互反馈缺失。

**修复**：`hit_test` 中加入关闭按钮分支，返回标识 `"close"`，
并在 `on_hover_change` 中据此渲染 ✕ 的悬停色（`E06C75` 红色，UI.md 6.1 已定义该色但未使用）。

---

### 🟡 P3-5：ui_scale 基准（宽/1920）与 chapterskip 基准（高/1080）不统一

本项目 4 个面板统一 `ui_scale = osd_w / 1920`，`chapterskip.lua` 统一 `scale = h / 1080`。
16:9 下二者恒等，但：
- **21:9 超宽屏**：本项目 `ui_scale` 偏大 → 元素显得偏大
- **4:3 屏**：本项目 `ui_scale` 偏小 → 元素显得偏小

**不影响本项目内部一致性**（4 面板同基准），但**跨项目搬按钮组件时必须换算**，
否则会出现"照抄过来尺寸不对"的假 bug。

**修复**：无需改代码，但**必须在合并文档与组件注释中标明基准口径差异**（本报告即在此记录）。

---

### 🟡 P3-6：`osd-button` 组件尚无对应实现，仅有设计

前一轮已论证按钮自适应缩放机制（`chapterskip.lua` 的四步法）并规划 `script-modules/osd-button.lua`，
但**该文件目前并不存在**（`script-modules/` 下仅有 `file-browser-addons`）。

**结论**：因此不存在"两个按钮组件冲突需要合并"的情况。
真正要做的是**让 `osd-button` 组件吸收本项目 §2.1–2.3 的做法**，而非反向合并。

---

## 4. 合并建议

### 4.1 不合并的理由

| 理由 | 说明 |
|------|------|
| 已有等价能力 | `pagination.lua` 已覆盖按钮布局/渲染/命中/点击四接口，功能完整 |
| 破坏单例模型 | `mouse_interaction.lua` 是**模块级单例**（同一时间只有一个面板可见）。引入 `osd-button` 会使其脱离既有 `input_service` 统一鼠标订阅，产生**双订阅冲突** |
| 破坏纯函数约定 | 该组件被设计为"纯逻辑、`ass_lib` 作为参数传入"。`osd-button` 自带 overlay，会打破依赖注入边界 |
| 无收益 | 现有 3 面板（cards / cover_intro / production_score）已稳定复用，重写引入回归风险 |

### 4.2 应采取的动作：反向吸收

把本项目已验证的做法**提取为 `osd-button` 的设计规范**，用于校正 `chapterskip.lua` 的按钮实现：

| 序号 | 从本项目吸收 | 用于修正 `chapterskip.lua` 的哪一点 |
|------|------------|--------------------------------|
| 1 | 关闭按钮"渲染存矩形 → 命中读矩形"（§2.1） | 改掉"两处分别重算 `button_x/button_y`"，消除漂移隐患 |
| 2 | 位置与尺寸共用 `layout.s`（§2.2） | 已是同构做法，可对齐命名 |
| 3 | 三态配色表（§2.3） | 补齐禁用态（当前只有默认/悬停两态） |
| 4 | `bottom` 位置自动避让 40px | 作为 `osd-button` 的默认避让策略 |
| 5 | 单一 `mouse-pos` 订阅服务（`input_service`） | 替代 `chapterskip` 中直接 `observe_property("mouse-pos")` 的裸写法 |

### 4.3 若坚持合并：最低成本方案

只在 **`osd-button.lua` 内部**做接口对齐，**不动 uosc_staff_credits 任何文件**：

```lua
-- osd-button.lua 暴露与 pagination.lua 同形的四接口
-- compute_layout(parent_layout, ...) / render(parts, layout, state, ass_lib)
-- hit_test(mx, my, layout)           / on_click(mx, my, layout, ...)
```

这样两边共享同一套"布局→渲染→命中→点击"契约，**零侵入**即可互通。

### 4.4 已落地：`script-modules/osd-button.lua` ✅（2026-10-05）

§4.2 的五项吸收清单**已全部实现**为独立模块 `script-modules/osd-button.lua`（非上游脚本，
本项目自建通用件）。它把「随播放器等比缩放、不移位、不偏位」固化成四条纪律：

| 纪律 | 内容 | 对应吸收项 |
|------|------|-----------|
| 1 | **单一缩放基准**：字号/内边距/圆角/描边/行距统一乘 `layout.s`，绝不出现两个基准 | 2 |
| 2 | **贴边反推**：`x = 屏宽 - 按钮宽 - 边距`，不用绝对坐标 | 2、4 |
| 3 | **渲染存矩形 → 命中读矩形**：矩形只算一次，命中只读不重算 | 1 |
| 4 | **每次渲染重取屏幕尺寸**，不缓存，窗口缩放/全屏/换显示器即时响应 | — |

**关键设计：纪律 3 是杜绝漂移的根本。** 文字宽度只能按 `字符数 × font_size × 0.6` 估算
（ASS 无回读文字度量能力），估算本身必然有误差。若渲染和命中各估算一次，两处误差叠加
就会产生「看得见点不着」的死区。本模块让**估算只发生一次**并存入 `self._hit_rect`，
命中判定永远读同一份结果 —— 误差再大也不会自相矛盾。

**与 §4.2 吸收项 5 的偏差说明**：`input_service` 的单一订阅是 uosc_staff_credits 内部
私有服务，通用模块不应依赖它。本模块改用**进程内共享订阅**：所有 Button 实例共用
一个 `mouse-pos` observer，回调分发给实例表，最后一个实例销毁时自动 `unobserve`。
既避免「每个按钮各订阅一次」的裸写法，也不引入跨模块耦合。

**自检内置**：`M.self_test()` 含 16 条断言，覆盖缩放等比性、贴边间距恒定、
21:9 超宽屏 / 4:3 窄屏 / 极窄屏不出框、九宫格锚点、避让控制栏、布局确定性等，
可在纯 luajit（无 mpv 运行时）下运行：

```bash
../luajit.exe tools/osd-button-selftest.lua
```

实测结果：**16/16 PASS**。

### 4.5 反向落地：`chapterskip.lua` 已切换到本模块 ✅（2026-10-05）

§4.2 吸收项 1 说的「改掉两处分别重算 `button_x/button_y`」**已真正执行** ——
不是停留在建议，而是把 `chapterskip.lua` 的按钮整体换成了 `osd-button`。

**旧实现的两个根因**（比 §4.2 当时的判断更具体）：

| 层次 | 问题 |
|------|------|
| 时序 | 命中判定读 `button_state.mouse_hover`，该布尔值虽在同一次 `render` 内算出，却隐含依赖「render 一定先于判定」。鼠标事件早于 render 时（show 后立刻点击、`osd-dimensions` 未就绪）读到的就是上一帧陈旧值 |
| 度量 | 文字宽度按 `#message * font_size * 0.6` 估算，与实际字体度量不符时绘制与判定各偏一次，且**无处对账** |

**改造结果**：

- 删除 **131 行**内联几何计算（`button_x/y/width/height`、`scale`、`0.6` 估算全部消失）
- 几何计算唯一化进模块：渲染写 `self._hit_rect`，命中只读它 —— 全项目**再无第二处按钮坐标计算**
- 点击改调 `prompt_button:on_mouse_click(x, y)`
- 删除裸的 `mouse-pos` observer（原每次鼠标移动都全量 render），悬停改由模块内共享订阅驱动
- 按钮实例复用（非每次 `new`），`on_unload` 增加 `:destroy()`

**度量提升**：`chapterskip.lua` 净减约 90 行（-177/+... 见提交），代码量变化：

```
script-modules/osd-button.lua         |  78 +++++++--   (扩展进度条支持)
scripts/chapterskip.lua               | 288 ++++++++++++++--------------------
tools/osd-button-drift-regression.lua |  67 ++++++++
```

**新增回归测试 `tools/osd-button-drift-regression.lua`**：把隐患变成可复现的断言。
构造「绘制发生在 1080p、判定时屏幕已切到 4K」的场景对照：

```
[旧] 绘制矩形 x=1647.2 y=862.0   判定矩形 x=3294.4 y=1724.0
[旧] 坐标漂移 dx=1647.2 dy=862.0  ← 两者不自洽
[旧] 点在按钮中心 → 未命中           ← 应命中却漏判（看得见点不着）
[新] 判定读同一份 → 命中 ✅
```

**为进度条扩展了模块**：`set_progress(p)` + `progress_fg/progress_bg` 三态联动配色。
进度**只影响填充宽度**，不影响按钮尺寸与位置 —— 所以不会引起抖动，也无需重新布局。
六参双半径 `round_rect_cw(x0,y0,x1,y1,r,0)` 沿用原 `chapterskip.lua:462` 验证过的形式。

---

## 5. 集成现状：已接入 ✅（2026-10-05 补全）

| 检查项 | 状态 | 说明 |
|--------|------|------|
| `script-opts/uosc_staff_credits.conf` | ✅ 已补齐 | 与 `defaults.lua` 的 30+ 配置项对应 |
| `input.conf` 键位绑定 | ✅ 已补齐 | `B  script-message-to uosc_staff_credits main-menu`（工具 > Bangumi 工具箱） |
| `scripts/uosc_staff_credits/` 本体 | ✅ 已就位 | 60 个 lua 文件完整 |
| `.gitignore` | ✅ 已补齐 | 覆盖 WorkBuddy 私有目录、运行时状态文件 |

### 5.1 入口绑定（已落地）

```conf
B  script-message-to uosc_staff_credits main-menu   #menu: 工具 > Bangumi 工具箱
```

> ⚠️ **路由名必须核对**：实际注册名是 **`main-menu`**（`app/dispatcher.lua:608`），
> 而非直觉上的 `staff-credits-main`。dispatcher 实际注册的完整路由清单：

| 路由名 | 用途 |
|--------|------|
| `main-menu` | **主菜单（本入口使用）** |
| `staff-credits` | 职员表 |
| `character-intro` | 角色介绍 |
| `cover-intro` | 封面简介 |
| `staff-credits-production-score` | 制作评分 |
| `staff-credits-search` / `-select` | BGM 搜索 / 选中条目 |
| `staff-credits-fankuhub-search` / `-search-by-person` | 番库搜索 |
| `staff-credits-settings` / `-config` / `-set-config` | 设置与配置读写 |
| `staff-credits-servers` / `-servers-move` / `-servers-toggle` | 网站优先级 |
| `staff-credits-clear-cache` / `-clear-all` | 清理缓存 |
| `staff-credits-close` / `-loading-close` / `-menu-closed` | 关闭与状态回调 |
| `staff-credits-open-browser` | 打开浏览器 |

### 5.2 键位冲突核查

`B` 与既有的 `BS`（重置速度）**不冲突** —— mpv 中二者是不同键名。
已确认 `input.conf` 中无其他未注释的 `B` 开头绑定。

---

## 6. 问题清单汇总

| 编号 | 严重度 | 问题 | 位置 | 状态 |
|------|--------|------|------|------|
| P1-1 | 🔴 高 | `state.hover_button` 未初始化 | `staff_grid.lua:44-55` | ✅ 已修 |
| P2-2 | 🟠 中 | `show(new_deps,...)` 首参被忽略 | `staff_grid.lua:328` / `staff_credits.lua:104,222` | ✅ 已修 |
| P2-3 | 🟠 中 | OSD observer 每次 show 重注册 | `staff_grid.lua:438-443` | ✅ 已修 |
| P2-4 | 🟠 中 | 关闭按钮无悬停反馈 | `staff_grid.lua:384-395` | ✅ 已修 |
| P3-5 | 🟡 低 | ui_scale 基准与 chapterskip 不一致 | 全局 | 📄 已记录口径 |
| P3-6 | 🟡 低 | `osd-button.lua` 尚不存在 | `script-modules/` | ✅ 已实现 |
| — | ✅ 已解 | 无 conf、无 input 绑定 | `script-opts/` `input.conf` | ✅ 已补齐 |

---

## 7. 相关文档

- 本项目自带：`docs/UI.md`（1,291 行）、`docs/DESIGN.md`（1,307 行）、`docs/PROJECT.md`（718 行）——**质量很高，是本次审查的主要依据**
- 上一轮产出：`chapterskip.lua` 按钮自适应缩放机制分析（四步法：取基准 → 乘 scale → 贴边反推 → 写回 res_x/res_y）
- 本地差异核对：[README.md §本地脚本与上游 wiki 说明的差异核对](../../../README.md)

---

## 7.5 关键机制勘误：`script-modules/` 不在 `package.path` 上 ⚠️

**这是本次最重要的发现，因为它让「语法全过」的代码实际完全无法运行。**

上一轮我把 `chapterskip.lua` 改为 `require 'osd-button'`，指向
`script-modules/osd-button.lua`。语法检查 **185/185 全过**，但实测启动 mpv 时：

```
[chapterskip] Lua error: chapterskip.lua:354: module 'osd-button' not found:
    no field package.preload['osd-button']
    no file 'D:\...\mpv-20260831\lua\osd-button.lua'
    no file 'D:\...\mpv-20260831\lua\osd-button\init.lua'
    no file 'D:\...\mpv-20260831\osd-button.dll'
```

**实测得到的 `package.path`（在脚本内打印）**：

```
D:\...\mpv-20260831\lua\?.lua;D:\...\mpv-20260831\lua\?\init.lua
```

即：mpv 只搜索 **`<mpv 根目录>/lua/`**，`script-modules/` **根本不在搜索路径上**。
`script-modules/` 只是社区约定（mpv 官方 wiki 建议的放置位置），
**并非自动可 require**。

**正确做法**（沿用本项目 `scripts/file-browser/main.lua:16` 的既有约定）：

```lua
-- 把 ~~ 展开为 mpv 配置目录后 prepend 到 package.path
package.path = mp.command_native({"expand-path", "~~/script-modules"}) .. "/?.lua;" .. package.path
local osd_button = require 'osd-button'
```

> **教训**：`loadstring` 语法检查**无法发现模块解析失败** —— 它只解析当前文件的语法，
> 不会真的执行 `require`。这类「运行期才炸」的问题**必须靠真实启动 mpv 验证**。
> 静态检查的绿灯不等于能跑。

---

## 8. 本次已落地的修改（2026-10-05）

### 8.0 uosc 控制栏按钮修正与扩充

**发现一个静默失效的绑定**（`script-opts/uosc.conf` 的 `controls` 行）：

```conf
# 修正前（错误，且不报错、点了没反应）
<video>command:people:script-binding uosc_staff-credits/staff-credits?职员表
```

两处错误：

| 错误 | 说明 |
|------|------|
| 脚本名写错 | `uosc_staff-credits`（连字符）vs 实际目录 `uosc_staff_credits`（下划线） |
| 机制用错 | `script-binding foo/bar` 要求 `bar` 是脚本内 `register_key_binding` 注册的**按键绑定**；而本脚本的对外入口是 **`script-message` 路由**，用 `script-binding` 调不到 |

**正确做法**：本脚本自己已通过 uosc 的 `set-button` 注册了具名按钮
（`modules/menu.lua:113`），名为 **`staff_credits_main`**（图标 `menu_book`，
提示「Bangumi 工具箱」）。所以只需引用 `button:staff_credits_main`。

**uosc 的坑**：`lib/buttons.lua:14` 对未注册的按钮名**不报错**，而是返回

```lua
{icon = 'help_center', tooltip = 'Uninitialized button "' .. name .. '"'}
```

即：**名字拼错只会显示一个问号图标**，极难察觉。故必须静态比对（见 §8.4 的核验脚本）。

**扩充的业务按钮**（按业务链路新增，均实测可触发）：

| 按钮 | 引用形式 | 对应路由 |
|------|---------|---------|
| 职员表 / 主菜单 | `button:staff_credits_main` | `main-menu`（脚本自注册） |
| 角色介绍 | `command:person_search:script-message-to … character-intro` | `character-intro` |
| 封面简介 | `command:image_search:script-message-to … cover-intro` | `cover-intro` |
| 制作评分 | `command:star_rate:script-message-to … staff-credits-production-score` | `staff-credits-production-score` |

> 用 `command:…:script-message-to` 而非 `script-binding`，因为这些是 **script-message 路由**。

### 8.1 代码修复（3 处）

| 文件 | 修改 | 说明 |
|------|------|------|
| `modules/staff_grid.lua:54` | 补 `hover_button = nil` | 原仅在 `show()`/`cleanup` 里赋值，属隐性依赖 |
| `modules/staff_grid.lua:328` | `show(new_deps, items, title)` → `show(items, title)` | 首参被静默忽略，删除以免误导 |
| `feature/staff_credits.lua:104,222` | 调用同步改为 `show(items, title)` | 与签名对齐 |
| `modules/staff_grid.lua:438-443` | OSD observer 移入 `M.init()` 一次性注册 | 消除订阅抖动与防抖定时器泄漏风险 |
| `modules/staff_grid.lua:384-395` | `hit_test` 增加 `"close"` 分支 | 使 ✕ 可被识别为悬停目标 |
| `modules/staff_grid.lua:199-220` | 关闭按钮三态渲染 | 悬停时背景 `3A3940` + 边框 `88C0FC` + 文字 `E06C75` |

### 8.2 配置与集成（3 项）

| 文件 | 动作 |
|------|------|
| `script-opts/uosc_staff_credits.conf` | 补齐；另将 `debug=yes` 改为 `debug=no`（避免生产环境刷屏） |
| `input.conf:313` | 新增 `B  script-message-to uosc_staff_credits main-menu` |
| `.gitignore` | 补齐 WorkBuddy 私有目录、运行时状态文件、`file_browser_favourites.txt` 例外 |

### 8.3 验证方式

本机**无需单独安装 Lua** —— 直接复用 mpv 自带的 `luajit.exe`（在 `portable_config` 的上一级，
即 `mpv.exe` 同目录），配套检查脚本 `tools/lua-syntax-check.lua`。

```bash
cd portable_config
../luajit.exe tools/lua-syntax-check.lua
```

**实测结果：全项目 185 个 .lua 文件，语法 OK 185，FAIL 0。**

其他验证：

- 键位冲突核查：`B` 与 `BS` 不同键，无冲突
- 路由名核对：`main-menu` 已在 `app/dispatcher.lua:608` 验证存在

> ⚠️ **但语法检查有明确的能力边界**：它只解析当前文件，**不执行 `require`**，
> 因此**发现不了模块解析失败**（§7.5 就是这么踩的坑：185/185 全过，
> 实际 `chapterskip.lua` 因为 `require 'osd-button'` 失败而**完全无法运行**）。
> 结论：**语法绿灯 ≠ 能跑，必须真机启动一次**。

### 8.3.1 真机冒烟测试（重要，补语法检查之不足）

```bash
cd mpv-20260831
./mpv.exe --vo=null --ao=null --frames=1 --msg-level=all=info "av://lavfi:testsrc=d=1"
```

用 mpv 内置 lavfi 测试源（无需外部媒体文件），`--vo=null` 便于纯日志验证。
**判据：日志中不得出现 `Lua error` / `module ... not found` / `traceback`。**

实测修复前的对比：

| 阶段 | `--vo=null` 启动日志 |
|------|---------------------|
| 修复前 | `[chapterskip] Lua error: ...: module 'osd-button' not found` ← 脚本整个没加载 |
| 修复后 | 无 Lua error，chapterskip 正常加载 |

### 8.3.2 业务链路端到端测试

```bash
./mpv.exe --vo=null --ao=null --script=tools/biz-smoke.lua "av://lavfi:testsrc=d=3"
```

依次触发 4 个业务路由，确认均被 dispatcher 接收：

```
[biz] === [1/4] 触发按钮「职员表(主菜单)」→ route=main-menu
[biz] === [2/4] 触发按钮「角色介绍」→ route=character-intro
[uosc_staff_credits] [Bangumi 工具箱] 角色介绍 · 加载中...
[biz] === [3/4] 触发按钮「封面简介」→ route=cover-intro
[uosc_staff_credits] [Bangumi 工具箱] 封面简介 · 加载中...
[biz] === [4/4] 触发按钮「制作评分」→ route=staff-credits-production-score
[uosc_staff_credits] [Bangumi 工具箱] 制作评分 · 加载中...
```

四个路由全部响应，无 Lua error。（测试图案无番剧数据，故后续网络请求
自然失败 —— 这属于**预期行为**，不是缺陷。）

### 8.4 静态核验工具（防止按钮名/路由名写错）

uosc 对未注册按钮名会静默降级为 `help_center` 占位图标，故必须静态比对：

```bash
python tools/uosc-verify-buttons.py   # 核验 controls 里每个 button:NAME 是否真被注册
python tools/uosc-verify-routes.py    # 核验每个 script-message-to 路由是否真被注册
```

实测：**button 未注册 0 个，路由未注册 0 个。**
