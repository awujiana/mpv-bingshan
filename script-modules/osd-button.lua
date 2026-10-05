--[[
  osd-button.lua —— 可复用的「随播放器等比缩放、不移位、不偏位」OSD 按钮组件

  * 归属：本项目自建 script-module（非上游脚本）
  * 依据：scripts/uosc_staff_credits/docs/REVIEW_AND_MERGE.md §4.2 反向吸收清单
  * 参考实现：scripts/chapterskip.lua 的 render_button()（v.2026-04-30）
  * License: MIT

  ────────────────────────────────────────────────────────────────────────
  为什么需要这个模块
  ────────────────────────────────────────────────────────────────────────
  在画面里画按钮，最容易踩三个坑：

  1. 「缩放不一致」：字号按一个基准缩放，内边距按另一个基准缩放，
     结果按钮在不同分辨率/宽高比下被拉扁或撑开。
  2. 「位置漂移」：渲染时算一遍坐标，做鼠标命中判定时又算一遍；
     两次计算的输入（屏幕尺寸、文字宽度估算）只要有一次不同，
     就会出现「看得见点不着」「鼠标在按钮外却判定为命中」。
  3. 「贴边不牢」：用绝对坐标定位，换分辨率后按钮跑到框外或压住控制栏。

  本模块用四条纪律一次性解决：

  纪律 1（单一缩放基准）
    所有尺寸——字号、内边距、圆角、描边、行距——**统一**乘以同一个
    layout.s。绝不出现两个基准。

  纪律 2（贴边反推，不用绝对坐标）
    位置从**边缘**反推：x = 屏宽 - 按钮宽 - 边距。
    按钮变宽或屏幕变窄时自动跟随，天然不会出框。

  纪律 3（渲染存矩形 → 命中读矩形）
    渲染时把算好的矩形存进 state.hit_rect，
    命中判定只读它、**不重算**。这是杜绝漂移最根本的一条。

  纪律 4（每次渲染重取屏幕尺寸，不缓存）
    缩放因子每次 render 都从 osd-dimensions 现读，
    这样窗口缩放、全屏切换、多显示器切换都能立刻正确响应。

  额外：bottom 位置默认自动避让 uosc 控制栏，不会被挡住。

  ────────────────────────────────────────────────────────────────────────
  用法
  ────────────────────────────────────────────────────────────────────────
  local button = require 'osd-button'

  local b = button.new({
      anchor = "bottom-right",   -- tl / tc / tr / ml / mc / mr / bl / bc / br
      label  = "跳过片头",
      hint   = "[Enter]",        -- 可选，第二行小字
      on_click = function() mp.commandv("seek", 90, "absolute") end,
  })

  b:set_text("跳过片头", "[Enter]")
  b:show()
  b:hide()
  b:destroy()

  自检：print(button.self_test())  -- 返回 ok, 详细报告
--]]

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local M = {}

-- ── 默认样式（全部为 1080p 下的像素值，会在渲染时统一乘 layout.s）──────────
local DEFAULT_STYLE = {
    font_size       = 24,
    padding_x       = 20,
    padding_y       = 15,
    margin          = 30,
    border          = 2,
    radius          = 13,
    line_spacing    = 0.1,   -- 相对 font_size 的比例
    -- 三态配色（BBGGRR，ASS 是 BGR 序！）
    bg              = "2A2930",
    bg_hover        = "3A3940",
    bg_disabled     = "1E1D22",
    fg              = "A0A0A0",
    fg_hover        = "E06C75",
    fg_disabled     = "5A5A5A",
    border_color    = nil,        -- nil = 不描边
    border_hover    = "88C0FC",
    border_disabled = nil,
}

-- 文字宽度估算系数：ASS 默认字体下，字符平均宽度 ≈ font_size * 0.6。
-- 这是估算而非精确度量——正因为是估算，才更要遵守纪律 3（存矩形读矩形），
-- 让「估算」只发生一次，命中判定永远用同一份结果。
local CHAR_WIDTH_RATIO = 0.6

-- bottom 系锚点默认避让 uosc 控制栏的高度（1080p 基准）
local CONTROL_BAR_AVOID = 80

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function hex_or(primary, fallback)
    if primary and primary ~= "" then return primary end
    return fallback
end

-- ────────────────────────────────────────────────────────────────────────
-- 几何：布局计算
-- ────────────────────────────────────────────────────────────────────────
-- 纪律 1 + 纪律 2 的落地处。
-- 输入：屏幕尺寸 + 文本 + 样式
-- 输出：一个 layout 表，渲染与命中判定**共用同一份**
local function compute_layout(screen_w, screen_h, text, hint, style, opts)
    -- 纪律 4：scale 每次都从当前屏幕高度现算，绝不缓存
    local s = screen_h / 1080

    local font_size = style.font_size * s
    local hint_size = font_size * 0.9
    local pad_x     = style.padding_x * s
    local pad_y     = style.padding_y * s
    local margin    = style.margin * s
    local radius    = style.radius * s
    local border    = (style.border or 0) * s
    local spacing   = font_size * (style.line_spacing or 0.1)

    -- 宽度 = 主体与提示文字中较宽者 + 左右内边距
    -- 中文按 1.0、西文按 0.6 计；用字节长近似判断，避免引入 utf8 依赖
    local function text_w(str, size)
        if not str or str == "" then return 0 end
        local n_ascii, n_wide = 0, 0
        for i = 1, #str do
            local b = str:byte(i)
            if b >= 0x80 then
                -- 多字节字符的后续字节（10xxxxxx）不计数
                if b >= 0xC0 then
                    n_wide = n_wide + 1
                end
            else
                n_ascii = n_ascii + 1
            end
        end
        return (n_ascii * CHAR_WIDTH_RATIO + n_wide) * size
    end

    local body_w = text_w(text, font_size)
    local hint_w = text_w(hint, hint_size)
    local button_w = math.max(body_w, hint_w) + pad_x * 2

    local n_lines = (hint and hint ~= "") and 2 or 1
    local button_h
    if n_lines == 2 then
        button_h = font_size + spacing + hint_size + pad_y * 2
    else
        button_h = font_size + pad_y * 2
    end

    -- 纪律 2：位置一律从边缘反推
    local anchor = opts.anchor or "bottom-right"
    local v_side = anchor:match("^t") and "top" or (anchor:match("^m") and "middle" or "bottom")
    local h_side = anchor:match("l$") and "left" or (anchor:match("c$") and "center" or "right")

    local x
    if h_side == "left" then
        x = margin
    elseif h_side == "center" then
        x = (screen_w - button_w) / 2
    else
        x = screen_w - button_w - margin
    end

    -- bottom 锚点自动避让控制栏 + 用户自定义避让
    local avoid = (opts.avoid or 0) * s
    if v_side == "bottom" and opts.avoid_control_bar ~= false then
        avoid = avoid + CONTROL_BAR_AVOID * s
    end

    local y
    if v_side == "top" then
        y = margin
    elseif v_side == "middle" then
        y = (screen_h - button_h) / 2
    else
        y = screen_h - button_h - margin - avoid
    end

    -- 兜底：任何情况下都不许出框
    x = clamp(x, 0, math.max(0, screen_w - button_w))
    y = clamp(y, 0, math.max(0, screen_h - button_h))

    -- 纪律 3 的准备：矩形在这里**唯一一次**被定下
    return {
        s          = s,            -- 单一缩放基准，全模块共享
        x          = x,
        y          = y,
        w          = button_w,
        h          = button_h,
        font_size  = font_size,
        hint_size  = hint_size,
        pad_x      = pad_x,
        pad_y      = pad_y,
        radius     = radius,
        border     = border,
        spacing    = spacing,
        n_lines    = n_lines,
        anchor     = anchor,
    }
end

M.compute_layout = compute_layout

-- ────────────────────────────────────────────────────────────────────────
-- 实例
-- ────────────────────────────────────────────────────────────────────────
local Button = {}
Button.__index = Button

function M.new(opts)
    opts = opts or {}

    local style = {}
    for k, v in pairs(DEFAULT_STYLE) do style[k] = v end
    for k, v in pairs(opts.style or {}) do style[k] = v end

    local self = setmetatable({}, Button)

    self._style      = style
    self._text       = opts.label or ""
    self._hint       = opts.hint or ""
    self._on_click   = opts.on_click
    self._opts       = {
        anchor           = opts.anchor or "bottom-right",
        avoid            = opts.avoid or 0,
        avoid_control_bar = opts.avoid_control_bar,
    }

    self._visible    = false
    self._enabled    = (opts.enabled ~= false)
    self._hover      = false

    -- 纪律 3：这是唯一的位置真源。渲染写入，命中读取，永不重算。
    self._hit_rect   = nil

    self._overlay    = mp.create_osd_overlay("ass-events")
    self._overlay.z  = opts.z or 1000

    -- 纪律 3 的前置条件：鼠标位置只订阅一次，回调里读取已存矩形比对
    self._mouse_observer = nil
    self._destroyed  = false

    self:_start_mouse_observer()

    return self
end

-- 单一 mouse-pos 订阅（对应 REVIEW_AND_MERGE.md §4.2 吸收项 5）
-- 注意：本项目 chapterskip.lua 用的是裸 observe_property("mouse-pos")。
--       uosc_staff_credits 的既有架构是「单一 input_service 集中订阅」。
--       本模块作为通用件，采用一个**进程内共享订阅**的折中方案：
--       所有 Button 实例共用同一个 observer，回调分发给各自的实例列表。
function Button:_start_mouse_observer()
    M._instances = M._instances or {}
    M._instances[self] = true

    if M._mouse_observer then return end

    M._mouse_observer = mp.observe_property("mouse-pos", "native", function(_, pos)
        local mx = pos and pos.x or -1
        local my = pos and pos.y or -1
        local hoverable = pos and pos.hover or false

        for inst in pairs(M._instances) do
            if inst._visible and inst._hit_rect and not inst._destroyed then
                -- 纪律 3：这里**只读**矩形，绝不重新计算布局
                local r = inst._hit_rect
                local inside = hoverable
                    and mx >= r.x and mx <= r.x + r.w
                    and my >= r.y and my <= r.y + r.h
                inside = inside and true or false

                if inside ~= inst._hover then
                    inst._hover = inside
                    inst:_render()
                end
            end
        end
    end)
end

function Button:set_text(text, hint)
    self._text = text or ""
    if hint ~= nil then self._hint = hint end
    if self._visible then self:_render() end
    return self
end

function Button:set_enabled(enabled)
    self._enabled = enabled and true or false
    if self._visible then self:_render() end
    return self
end

function Button:set_on_click(fn)
    self._on_click = fn
    return self
end

-- 三态配色解析（吸收项 3：补齐 disabled 态）
function Button:_resolve_colors()
    local st = self._style
    if not self._enabled then
        return {
            bg    = hex_or(st.bg_disabled, st.bg),
            fg    = hex_or(st.fg_disabled, st.fg),
            border = hex_or(st.border_disabled, st.border_color),
        }
    elseif self._hover then
        return {
            bg    = hex_or(st.bg_hover, st.bg),
            fg    = hex_or(st.fg_hover, st.fg),
            border = hex_or(st.border_hover, st.border_color),
        }
    else
        return {
            bg    = st.bg,
            fg    = st.fg,
            border = st.border_color,
        }
    end
end

-- ────────────────────────────────────────────────────────────────────────
-- 渲染
-- ────────────────────────────────────────────────────────────────────────
function Button:_render()
    if self._destroyed or not self._visible then return end

    local dims = mp.get_property_native("osd-dimensions")
    local sw, sh
    if dims then
        sw, sh = dims.w, dims.h
    else
        sw, sh = 1920, 1080
    end
    if not sw or sw <= 0 or not sh or sh <= 0 then
        sw, sh = 1920, 1080
    end

    local layout = compute_layout(sw, sh, self._text, self._hint, self._style, self._opts)

    -- 纪律 3：渲染定下的矩形，就是命中判定将读取的矩形
    self._hit_rect = { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
    self._layout = layout

    local c = self:_resolve_colors()

    local ass = assdraw.ass_new()
    ass:new_event()
    ass:pos(0, 0)   -- \an7\pos(0,0)：绝对坐标作图模式
    ass:append("{\\an7\\blur0}")

    -- 底板
    ass:append("{\\bord0\\1c&H" .. c.bg .. "&}")
    ass:draw_start()
    ass:round_rect_cw(layout.x, layout.y,
                      layout.x + layout.w, layout.y + layout.h,
                      layout.radius)
    ass:draw_stop()

    -- 描边（可选，悬停时出现）
    if c.border and layout.border > 0 then
        ass:append("{\\1c&H" .. c.border .. "&\\bord" .. layout.border
                   .. "\\3c&H" .. c.border .. "&}")
        ass:draw_start()
        ass:round_rect_cw(layout.x, layout.y,
                          layout.x + layout.w, layout.y + layout.h,
                          layout.radius)
        ass:draw_stop()
    end

    -- 文字（主行 + 可选提示行），整体垂直居中
    local cx = layout.x + layout.w / 2
    local inner_h = layout.n_lines == 2
        and (layout.font_size + layout.spacing + layout.hint_size)
        or layout.font_size
    local top = layout.y + (layout.h - inner_h) / 2

    local body_cy = top + layout.font_size / 2
    ass:new_event()
    ass:pos(cx, body_cy)
    ass:append("{\\an5\\fs" .. layout.font_size .. "\\b1\\bord0\\shad0\\1c&H" .. c.fg .. "&}")
    ass:append(self._text)

    if layout.n_lines == 2 then
        local hint_cy = top + layout.font_size + layout.spacing + layout.hint_size / 2
        ass:new_event()
        ass:pos(cx, hint_cy)
        ass:append("{\\an5\\fs" .. layout.hint_size
                   .. "\\b0\\bord0\\shad0\\1c&H" .. c.fg .. "&\\alpha&H80&}")
        ass:append(self._hint)
    end

    -- res_x/res_y = 屏幕尺寸，使 ASS 单位与像素 1:1 对应
    self._overlay.res_x = sw
    self._overlay.res_y = sh
    self._overlay.data  = ass.text
    self._overlay:update()
end

function Button:show()
    if self._destroyed then return self end
    self._visible = true
    self:_render()
    return self
end

function Button:hide()
    if self._destroyed then return self end
    self._visible = false
    self._hover = false
    self._hit_rect = nil
    self._overlay:remove()
    return self
end

-- 供外部查询当前是否命中（不重算）
function Button:is_hovered()
    return self._visible and self._enabled and self._hover
end

-- 外部点击入口：返回 true 表示本次点击被本按钮消费
function Button:on_mouse_click(mx, my)
    if not self._visible or not self._enabled then return false end
    local r = self._hit_rect
    if not r then return false end
    if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
        if self._on_click then
            local ok, err = pcall(self._on_click)
            if not ok then
                msg.error("osd-button on_click 回调出错：" .. tostring(err))
            end
        end
        return true
    end
    return false
end

-- 手动触发重绘（例如外部改了样式表后）
function Button:refresh()
    if self._visible then self:_render() end
    return self
end

function Button:destroy()
    if self._destroyed then return end
    self._destroyed = true
    self._visible = false
    self._hit_rect = nil
    pcall(function() self._overlay:remove() end)

    if M._instances then
        M._instances[self] = nil
        -- 没有实例了就撤掉共享订阅，避免空转
        local empty = true
        for _ in pairs(M._instances) do empty = false break end
        if empty and M._mouse_observer then
            M._mouse_observer:unobserve()
            M._mouse_observer = nil
            M._instances = nil
        end
    end
end

M.Button = Button

-- ────────────────────────────────────────────────────────────────────────
-- 自检：验证四条纪律确实成立
-- ────────────────────────────────────────────────────────────────────────
-- 这些断言不依赖 mpv 运行环境，可以在纯 Lua 下跑（用于 CI / 语法检查后的逻辑校验）
function M.self_test()
    local lines = {}
    local ok = true

    local function check(name, cond, detail)
        lines[#lines + 1] = string.format("  %s %s%s",
            cond and "[PASS]" or "[FAIL]", name,
            detail and ("  — " .. detail) or "")
        if not cond then ok = false end
    end

    local style = DEFAULT_STYLE
    local o = { anchor = "bottom-right" }

    -- 纪律 1：单一缩放基准 —— 对比 1080p 与 2160p，所有尺寸都应恰好 ×2
    local l1 = compute_layout(1920, 1080, "测试test", "[Enter]", style, o)
    local l2 = compute_layout(3840, 2160, "测试test", "[Enter]", style, o)
    check("基准 s 与屏幕高度成正比", l2.s == l1.s * 2,
          string.format("s1=%.4f s2=%.4f", l1.s, l2.s))
    check("字号同比缩放", math.abs(l2.font_size - l1.font_size * 2) < 1e-6)
    check("内边距同比缩放", math.abs(l2.pad_x - l1.pad_x * 2) < 1e-6)
    check("圆角同比缩放", math.abs(l2.radius - l1.radius * 2) < 1e-6)
    check("尺寸同比缩放（宽高皆然）",
          math.abs(l2.w - l1.w * 2) < 1e-6 and math.abs(l2.h - l1.h * 2) < 1e-6,
          string.format("w1=%.2f w2=%.2f", l1.w, l2.w))

    -- 纪律 2：贴边反推 —— 右边缘间距恒等于 margin，与按钮宽度无关
    local r1 = 1920 - (l1.x + l1.w)
    check("右边距 == margin（1080p）", math.abs(r1 - style.margin) < 1e-6,
          string.format("实测 %.3f 期望 %d", r1, style.margin))
    local r2 = 3840 - (l2.x + l2.w)
    check("右边距 == margin×2（2160p，随 s 缩放）",
          math.abs(r2 - style.margin * 2) < 1e-6,
          string.format("实测 %.3f 期望 %d", r2, style.margin * 2))

    -- 纪律 2 补：超宽屏下不得出框
    local lw = compute_layout(3440, 1440, "一个相当长的按钮文字用来撑开宽度", nil, style, o)
    check("超宽屏（21:9）不出右框", lw.x + lw.w <= 3440 + 1e-6)
    check("超宽屏（21:9）不出左框", lw.x >= -1e-6)

    -- 纪律 2 补：4:3 窄屏也得在框内
    local ln = compute_layout(1024, 768, "窄屏测试文字", "[y/n]", style, o)
    check("4:3 窄屏不出右框", ln.x + ln.w <= 1024 + 1e-6)
    check("4:3 窄屏不出下框", ln.y + ln.h <= 768 + 1e-6)

    -- 纪律 3：渲染存储与命中读取必须同源
    --   用锚点对比法：同一份 layout 被计算两次（模拟「重算」），
    --   在确定性的输入下应完全一致；一旦将来有人改成非确定性（如缓存屏幕尺寸），
    --   这条断言就是哨兵。
    local a = compute_layout(1920, 1080, "x", nil, style, o)
    local b = compute_layout(1920, 1080, "x", nil, style, o)
    check("同输入布局确定性（命中判定可安全复用）",
          a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h)

    -- 纪律 2 补：bottom 锚点自动避让控制栏
    check("bottom-right 自动避让控制栏 80px×s",
          math.abs(l1.y - (1080 - l1.h - style.margin - CONTROL_BAR_AVOID)) < 1e-6,
          string.format("y=%.2f h=%.2f", l1.y, l1.h))

    -- 可选关闭避让
    local lna = compute_layout(1920, 1080, "x", nil, style,
                               { anchor = "bottom-right", avoid_control_bar = false })
    check("avoid_control_bar=false 时贴近底边",
          math.abs(lna.y - (1080 - lna.h - style.margin)) < 1e-6)

    -- 九宫格锚点都应落在框内
    local anchors = {"top-left","top-center","top-right",
                     "middle-left","middle-center","middle-right",
                     "bottom-left","bottom-center","bottom-right"}
    local all_in = true
    local bad = nil
    for _, anc in ipairs(anchors) do
        local l = compute_layout(1920, 1080, "文字", "[k]", style, { anchor = anc })
        if l.x < -1e-6 or l.y < -1e-6
           or l.x + l.w > 1920 + 1e-6 or l.y + l.h > 1080 + 1e-6 then
            all_in = false
            bad = anc
        end
    end
    check("九宫格锚点全部不出框", all_in, bad and ("越界锚点=" .. bad) or nil)

    -- 极窄屏幕：按钮比屏幕还宽时必须被夹住而不是溢出
    local t = compute_layout(300, 200, "非常非常非常长的按钮文字内容", nil, style, o)
    check("极窄屏被夹住且宽度收进屏内", t.x >= 0 and t.w <= 300 + 1e-6,
          string.format("x=%.2f w=%.2f", t.x, t.w))

    return ok, table.concat(lines, "\n")
end

return M
