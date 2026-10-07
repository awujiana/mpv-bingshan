-- tools/danmaku-layout-test.lua —— modules/parse.lua 排版引擎回归测试
--
-- 用法（任意 cwd 均可 —— 路径基准由脚本自身位置推导）：
--   ./luajit.exe portable_config/tools/danmaku-layout-test.lua
--
-- 为什么需要它（2026-10-07）：
--   提交 972d27f 把 modules/parse.lua 的排版算法**整体重写**了：
--   旧的「按行数组」（set_time_length / get_time / get_length / is_empty）
--   换成按时间递增的碰撞检测（rolling_danmaku_collides / find_y_from_top）。
--   当时的验证是一次性的（合成弹幕喂进去、手工看违例计数），**没有留存**，
--   于是重写后的引擎处于零回归保护状态 —— 之后再动一次谁也不知道有没有坏。
--
--   uosc_danmaku 共 19 个源文件（11 模块 + 6 站点解析 + 2 API），此前**零测试**。
--   本文件是它的第一个。
--
-- ⚠️ 判据设计（这决定了测试有没有牙）：
--   不去复刻「算法应该怎么算」，而是**从真正被渲染的产物反推**：
--   调 convert_danmaku_to_ass_events() 拿到 ASS 事件，再用每个事件的
--   \move / \pos 坐标**独立复算**两条弹幕在时间轴上是否真的会重叠。
--   复刻算法 = 在测「我对它的理解」；查产物 = 在测「它实际画了什么」。
--   前者在算法被改错时会跟着一起错，后者不会。
--
-- ⚠️ 用**真实**的 modules/utils.lua 与 modules/parse.lua，只桩 mp.* 与几个全局。
--   桩越真、分辨力越高；把 get_str_width 之类也桩掉就等于自己写了一遍算法。

-- ---- 路径基准：从脚本自身位置反推，使本测试与 cwd 无关 ----
local _src = debug.getinfo(1, "S").source or "@."
local _tools_dir = _src:match("^@(.*)[/\\][^/\\]*$") or "."
local _pc = _tools_dir:match("^(.*)[/\\][^/\\]*$") or "."
local _danmaku_dir = _pc .. "/scripts/uosc_danmaku"

-- ---- 计数器 ----
local pass, fail = 0, 0
local function check(desc, got, want)
    if got == want then
        pass = pass + 1
        print(string.format("  [PASS] %s", desc))
    else
        fail = fail + 1
        print(string.format("  [FAIL] %s\n         期望: %s\n         实际: %s",
            desc, tostring(want), tostring(got)))
    end
end
local function check_true(desc, cond, detail)
    if cond then
        pass = pass + 1
        print(string.format("  [PASS] %s", desc))
    else
        fail = fail + 1
        print(string.format("  [FAIL] %s\n         %s", desc, tostring(detail or "")))
    end
end
local function section(t)
    print("")
    print(string.rep("-", 76))
    print(t)
    print(string.rep("-", 76))
end

-- ============================================================================
-- §0 环境搭建：桩 mp.*，装填全局，加载真实模块
-- ============================================================================
section("§0 环境自检（桩 + 真实模块加载）")

local msg_log = { info = 0, verbose = 0, warn = 0, error = 0, debug = 0 }
local fake_msg = {}
for level in pairs(msg_log) do
    fake_msg[level] = function() msg_log[level] = msg_log[level] + 1 end
end
fake_msg.log = fake_msg.info

local fake_utils = {
    parse_json = function() return nil end,
    format_json = function() return "{}" end,
    join_path = function(a, b) return a .. "/" .. b end,
    read_file = function() return nil, "not found" end,
    write_file = function() return nil, "not writable" end,
    get_env_list = function() return {} end,
    split_path = function(p) return p, ".", "" end,
    file_info = function() return nil end,
}

package.loaded["mp.msg"] = fake_msg
package.loaded["mp.utils"] = fake_utils

-- parse.lua 在**模块级**就调用 mp.command_native({"expand-path", options.blacklist_path})
-- 并读取全局 options —— 所以 options 必须在 require 之前存在。
-- （这正是本项目 MEMORY.md 记的「uosc_danmaku 隐性全局共享」风格。）
local expand_calls = 0
_G.mp = _G.mp or {}
_G.mp.command_native = function(args)
    if type(args) == "table" and args[1] == "expand-path" then
        expand_calls = expand_calls + 1
        return args[2]
    end
    return nil
end
_G.mp.set_property_native = function() end
_G.mp.commandv = function() end

-- 全局 options：只放 parse.lua 真正读的键
_G.options = {
    blacklist_path = "",
    chConvert = 0,
    displayarea = 1.0,
    fixtime = 5,
    fontsize = 30,
    max_screen_danmaku = 0,
    merge_fontsize_growth = 8,
    merge_fontsize_max = 100,
    merge_tolerance = -1,
    merge_without_style = false,
    scrolltime = 15,
    title_replace = "[]",
}

_G.show_message = function() end
_G.DANMAKU = { sources = {} }
_G.COMMENTS = nil

-- 让 require 能找到 dicts/s2t_chars 等
package.path = _danmaku_dir .. "/?.lua;" .. package.path

local ok_utils, utils_mod = pcall(require, "modules.utils")
check_true("modules/utils.lua 加载成功", ok_utils, ok_utils and "" or tostring(utils_mod))

local ok_parse, parse_mod = pcall(require, "modules.parse")
check_true("modules/parse.lua 加载成功", ok_parse, ok_parse and "" or tostring(parse_mod))

if not ok_parse then
    print("")
    print("模块加载失败，后续断言无法进行。")
    os.exit(1)
end

check_true("parse.lua 模块级读取了 options.blacklist_path（隐性全局契约）",
    expand_calls >= 1, "expand-path 调用次数=" .. expand_calls)

-- convert_danmaku_to_ass_events 是全局函数（parse.lua 未 return 表）
check("convert_danmaku_to_ass_events 已导出为全局",
    type(_G.convert_danmaku_to_ass_events), "function")

-- ============================================================================
-- §1 get_merged_font_size：单调不减、有上界、入参强制为正整数
-- ============================================================================
section("§1 合并字号映射（对数增长 + 上界）")

local D = _G.DanmakuArray
if not D then
    -- parse.lua 里 DanmakuArray 是 local，但 convert 会用到；
    -- 这里通过一次真实调用反推它是否可用
    print("  [INFO] DanmakuArray 是 local，改用端到端产物验证（见 §3~§5）")
end

-- ============================================================================
-- §2 合成数据生成器
-- ============================================================================
section("§2 生成合成弹幕（确定性随机，可复现）")

-- 线性同余伪随机：不用 math.random，保证跨平台/跨次运行完全一致
local seed = 20261007
local function rnd()
    seed = (1103515245 * seed + 12345) % 2147483648
    return seed / 2147483648
end

local function make_source(n, span, types)
    local data = {}
    for i = 1, n do
        local t = rnd() * span
        local ty = types[math.floor(rnd() * #types) + 1]
        data[i] = {
            time = t,
            type = ty,
            color = 0xFFFFFF,
            size = 25,
            -- 文本长度差异大，覆盖「短弹幕挤得下 / 长弹幕挤不下」两种情形
            text = string.rep("弹", math.floor(rnd() * 30) + 1) .. tostring(i),
        }
    end
    return data
end

local function run_convert(n, span)
    _G.DANMAKU = { sources = { ["test://src"] = { blocked = false, data = make_source(n, span, {1,1,1,4,5}) } } }
    _G.options.merge_tolerance = -1
    _G.options.max_screen_danmaku = 0
    _G.COMMENTS = nil
    _G.convert_danmaku_to_ass_events(true)
    return _G.COMMENTS or {}
end

-- ============================================================================
-- §3 ★ 核心不变量：同一 y 带的滚动弹幕，两两在时间轴上不重叠
-- ============================================================================
section("§3 ★ 滚动弹幕不碰撞（从 ASS \\move 产物独立复算）")

-- y 带相交判定：直接复用被测算法的契约（top + height 区间重叠）
local function y_intersects(y1, h1, y2, h2)
    return y1 < y2 + h2 and y2 < y1 + h1
end

-- 独立复算：两条滚动弹幕的文本框在时间轴上是否真的重叠
--   ASS \move(x1,y,x2,y) 的锚点是**文本中心**（parse.lua 按 center 计算：
--   x1 = res_x + tl/2，x2 = -tl/2 ⇒ 起手时左边缘恰在 res_x，结束时右边缘恰在 0）
--   center(t) = x1 + (x2-x1) * (t - start) / duration
--   half_width = 文本宽度 / 2
--
-- ⚠️ 这里踩过一次：半宽不能写成 (x1 - x2)/2。
--    因为锚点是中心，x1 - x2 = res_x + text_length，直接除 2 会把半宽
--    多算 res_x/2 = 960px ⇒ 判据阈值虚高近 2000px ⇒ **100% 假报重叠**
--    （当时三档密度整齐地 111/111、876/876、4836/4836 全灭，
--      这种「整齐的失败率」本身就是判据错了的信号，不是引擎坏了）。
--    正解：文本宽度用被测模块同一套 get_str_width 重新量（它是纯文本度量，
--    不属于碰撞逻辑，用真的反而比自写更可信）。
local get_str_width = _G.get_str_width
check_true("get_str_width 可用（用于独立量文本宽度）",
    type(get_str_width) == "function", type(get_str_width))

local function rolling_pair_overlaps(a, b)
    local t0 = math.max(a.start_time, b.start_time)
    local t1 = math.min(a.end_time, b.end_time)
    if t0 >= t1 then return false end

    local ax1, ax2 = a.move[1], a.move[3]
    local bx1, bx2 = b.move[1], b.move[3]
    local a_hw = get_str_width(a.clean_text, a.font_size) / 2
    local b_hw = get_str_width(b.clean_text, b.font_size) / 2
    local thr = a_hw + b_hw
    local dur_a = a.end_time - a.start_time
    local dur_b = b.end_time - b.start_time

    local function diff(t)
        local ca = ax1 + (ax2 - ax1) * (t - a.start_time) / dur_a
        local cb = bx1 + (bx2 - bx1) * (t - b.start_time) / dur_b
        return ca - cb
    end

    -- 采样点：两个端点 + 线性差函数的零点
    local d0, d1 = diff(t0), diff(t1)
    local pts = { t0, t1 }
    if d1 ~= d0 then
        local tz = t0 + (t1 - t0) * (-d0) / (d1 - d0)
        if tz > t0 and tz < t1 then pts[#pts + 1] = tz end
    end
    for _, t in ipairs(pts) do
        if math.abs(diff(t)) < thr then return true end
    end
    return false
end

-- 三条密度档位：弹幕越密，越容易撞
local DENSITIES = {
    { name = "稀疏", n = 200,  span = 600 },
    { name = "中等", n = 800,  span = 600 },
    { name = "密集", n = 3000, span = 600 },
}

local density_report = {}
for _, dens in ipairs(DENSITIES) do
    local events = run_convert(dens.n, dens.span)
    local r2l, top, btm = {}, {}, {}
    for _, e in ipairs(events) do
        if e.style == "R2L" and e.move then r2l[#r2l + 1] = e
        elseif e.style == "TOP" and e.pos then top[#top + 1] = e
        elseif e.style == "BTM" and e.pos then btm[#btm + 1] = e end
    end

    local violations, same_band_pairs = 0, 0
    local sample = nil

    -- 自检：验证「锚点是文本中心」这个前提。若成立，
    -- (x1 - x2) - 文本宽度 应恒等于屏幕宽度 res_x（parse.lua 里写死 1920）。
    -- 这条不过，后面的重叠判定就没有意义 —— 先证明尺子是对的，再量东西。
    local res_seen, res_ok = nil, true
    for _, e in ipairs(r2l) do
        local r = (e.move[1] - e.move[3]) - get_str_width(e.clean_text, e.font_size)
        if res_seen == nil then res_seen = r end
        if math.abs(r - res_seen) > 0.5 then res_ok = false end
    end
    check_true(string.format("[%s] 坐标系自检：(x1-x2)-文本宽 恒为 %.0f（= res_x）",
        dens.name, res_seen or -1),
        res_ok and res_seen ~= nil and math.abs(res_seen - 1920) < 1,
        "得到 " .. tostring(res_seen))

    for i = 1, #r2l do
        for j = i + 1, #r2l do
            local a, b = r2l[i], r2l[j]
            -- 只在时间上可能相遇时才有必要查 y
            if a.start_time < b.end_time and b.start_time < a.end_time then
                if y_intersects(a.move[2], a.font_size, b.move[2], b.font_size) then
                    same_band_pairs = same_band_pairs + 1
                    if rolling_pair_overlaps(a, b) then
                        violations = violations + 1
                        if not sample then
                            sample = string.format(
                                "i=%d(t=%.2f,len=%.0f,y=%d) vs j=%d(t=%.2f,len=%.0f,y=%d)",
                                i, a.start_time, a.move[1] - a.move[3], a.move[2],
                                j, b.start_time, b.move[1] - b.move[3], b.move[2])
                        end
                    end
                end
            end
        end
    end

    density_report[#density_report + 1] = {
        name = dens.name, n = dens.n, total = #events, r2l = #r2l,
        pairs = same_band_pairs, bad = violations,
    }
    check_true(string.format("[%s] n=%d：同 y 带且时间相交的弹幕对 %d 组，实际重叠 0 组",
        dens.name, dens.n, same_band_pairs),
        violations == 0,
        violations .. " 组重叠，例：" .. tostring(sample))
    check_true(string.format("[%s] 确实产生了足够多的同带对（证明上一条不是空跑）", dens.name),
        same_band_pairs > 50, "仅 " .. same_band_pairs .. " 组")
end

-- ============================================================================
-- §4 固定弹幕：同一 y 带 + 时间相交 ⇒ 必须重叠为 0
-- ============================================================================
section("§4 固定弹幕不重叠（顶部/底部共用一个 y 空间）")

for _, dens in ipairs(DENSITIES) do
    local events = run_convert(dens.n, dens.span)
    local fixed = {}
    for _, e in ipairs(events) do
        if (e.style == "TOP" or e.style == "BTM") and e.pos then fixed[#fixed + 1] = e end
    end

    local bad, pairs = 0, 0
    local sample = nil
    for i = 1, #fixed do
        for j = i + 1, #fixed do
            local a, b = fixed[i], fixed[j]
            -- 时间相交才需要不同 y
            if a.start_time < b.end_time and b.start_time < a.end_time then
                if y_intersects(a.pos[2], a.font_size, b.pos[2], b.font_size) then
                    bad = bad + 1
                    if not sample then
                        sample = string.format("i=%d(y=%d,fs=%d) vs j=%d(y=%d,fs=%d)",
                            i, a.pos[2], a.font_size, j, b.pos[2], b.font_size)
                    end
                end
            end
            pairs = pairs + 1
        end
    end
    check_true(string.format("[%s] 固定弹幕 %d 条，时间相交且 y 带重叠 0 组",
        dens.name, #fixed), bad == 0,
        bad .. " 组，例：" .. tostring(sample))
end

-- ============================================================================
-- §5 端到端产物完整性
-- ============================================================================
section("§5 端到端产物完整性")

local ev = run_convert(500, 300)
check_true("产出了事件（非空）", #ev > 0, "#events=" .. #ev)

local fields_ok, bad_field = true, nil
for idx, e in ipairs(ev) do
    for _, k in ipairs({ "orig_time", "start_time", "end_time", "style",
                         "text", "clean_text", "layer", "font_size", "merge_count" }) do
        if e[k] == nil then
            fields_ok = false; bad_field = string.format("第%d条缺字段 %s", idx, k); break
        end
    end
    if not fields_ok then break end
    if e.style == "R2L" and not e.move then
        fields_ok = false; bad_field = string.format("第%d条 R2L 无 move", idx); break
    end
    if (e.style == "TOP" or e.style == "BTM") and not e.pos then
        fields_ok = false; bad_field = string.format("第%d条 %s 无 pos", idx, e.style); break
    end
end
check_true("每条事件字段完整且定位信息齐备", fields_ok, tostring(bad_field))

local layer_ok = true
for _, e in ipairs(ev) do
    if e.style == "R2L" and e.layer ~= 0 then layer_ok = false end
    if e.style ~= "R2L" and e.layer ~= 1 then layer_ok = false end
end
check_true("layer 约定成立（滚动=0，固定=1）", layer_ok, "存在违例")

local time_ok = true
for _, e in ipairs(ev) do
    if not (e.end_time > e.start_time) then time_ok = false end
end
check_true("end_time 严格大于 start_time", time_ok, "存在违例")

-- 字号上界：任何事件都不该超过 merge_fontsize_max
local size_ok, max_seen = true, 0
for _, e in ipairs(ev) do
    if e.font_size > _G.options.merge_fontsize_max then size_ok = false end
    if e.font_size > max_seen then max_seen = e.font_size end
end
check_true(string.format("字号不超过 merge_fontsize_max=%d（实测最大 %d）",
    _G.options.merge_fontsize_max, max_seen), size_ok, "存在超界")

-- 文本转义：ASS 的 {} 必须被转义，否则会被当成样式覆盖指令
_G.DANMAKU = { sources = { ["x"] = { blocked = false, data = {
    { time = 1, type = 1, color = 0xFFFFFF, size = 25, text = "a{b}c\\d" },
} } } }
_G.options.merge_tolerance = -1
_G.options.max_screen_danmaku = 0
_G.COMMENTS = nil
_G.convert_danmaku_to_ass_events(true)
local esc = (_G.COMMENTS or {})[1]
check_true("ASS 特殊字符被转义（{ } \\ 不再裸奔）",
    esc and esc.text:find("\\{", 1, true) ~= nil
        and esc.text:find("\\}", 1, true) ~= nil
        and esc.text:find("\\\\", 1, true) ~= nil,
    esc and esc.text or "(无事件)")

-- 颜色：0xRRGGBB 十进制 → ASS 的 &HBBGGRR&
_G.DANMAKU = { sources = { ["x"] = { blocked = false, data = {
    { time = 1, type = 1, color = 0xFF0000, size = 25, text = "red" },
} } } }
_G.COMMENTS = nil
_G.convert_danmaku_to_ass_events(true)
local cev = (_G.COMMENTS or {})[1]
check_true("红色 0xFF0000 转成 ASS 的 &H0000FF&（BGR 序）",
    cev and cev.text:find("&H0000FF&", 1, true) ~= nil,
    cev and cev.text or "(无事件)")

-- 黑名单：命中词的弹幕不应进入产物
_G.options.blacklist_path = ""
_G.DANMAKU = { sources = { ["x"] = { blocked = false, data = {
    { time = 1, type = 1, color = 0xFFFFFF, size = 25, text = "正常" },
    { time = 1, type = 1, color = 0xFFFFFF, size = 25, text = "正常" },
} } } }
_G.COMMENTS = nil
_G.convert_danmaku_to_ass_events(true)
check_true("无黑名单时弹幕全部保留（2 条）",
    #(_G.COMMENTS or {}) == 2, "#=" .. #(_G.COMMENTS or {}))

-- blocked 源必须被完全忽略
_G.DANMAKU = { sources = {
    ["a"] = { blocked = false, data = { { time = 1, type = 1, color = 0xFFFFFF, size = 25, text = "A" } } },
    ["b"] = { blocked = true,  data = { { time = 1, type = 1, color = 0xFFFFFF, size = 25, text = "B" } } },
} }
_G.COMMENTS = nil
_G.convert_danmaku_to_ass_events(true)
local blocked_ok = true
for _, e in ipairs(_G.COMMENTS or {}) do
    if e.clean_text == "B" then blocked_ok = false end
end
check_true("blocked=true 的源不参与渲染", blocked_ok, "仍出现被屏蔽源的弹幕")

-- ============================================================================
-- §6 多源合并：不同源的弹幕要按时间归并成一条有序流
-- ============================================================================
section("§6 多源归并（最小堆）按时间递增")

_G.DANMAKU = { sources = {
    ["s1"] = { blocked = false, data = {
        { time = 5, type = 1, color = 0xFFFFFF, size = 25, text = "s1-5" },
        { time = 1, type = 1, color = 0xFFFFFF, size = 25, text = "s1-1" },
        { time = 9, type = 1, color = 0xFFFFFF, size = 25, text = "s1-9" },
    } },
    ["s2"] = { blocked = false, data = {
        { time = 3, type = 1, color = 0xFFFFFF, size = 25, text = "s2-3" },
        { time = 7, type = 1, color = 0xFFFFFF, size = 25, text = "s2-7" },
    } },
} }
_G.options.merge_tolerance = -1
_G.options.max_screen_danmaku = 0
_G.COMMENTS = nil
_G.convert_danmaku_to_ass_events(true)

local times = {}
for _, e in ipairs(_G.COMMENTS or {}) do times[#times + 1] = e.start_time end
local sorted_ok = true
for i = 2, #times do
    if times[i] < times[i - 1] then sorted_ok = false end
end
check_true("归并后事件按 start_time 单调不减（多源合并正确）", sorted_ok,
    table.concat(times, ","))
check("5 条弹幕全部保留", #(_G.COMMENTS or {}), 5)

-- ============================================================================
-- §7 空数据 / 边界输入不得崩溃
-- ============================================================================
section("§7 边界输入健壮性")

_G.DANMAKU = { sources = {} }
_G.COMMENTS = nil
local ok_empty = pcall(_G.convert_danmaku_to_ass_events, true)
check_true("无任何数据源时不抛异常", ok_empty, "抛了异常")
check("无数据时 COMMENTS 置空表", type(_G.COMMENTS), "table")
check("无数据时 COMMENTS 长度为 0", #_G.COMMENTS, 0)

_G.DANMAKU = { sources = { ["x"] = { blocked = false, data = {} } } }
local ok_emptylist = pcall(_G.convert_danmaku_to_ass_events, true)
check_true("数据源存在但 data 为空时不抛异常", ok_emptylist, "抛了异常")

_G.DANMAKU = { sources = { ["x"] = { blocked = false, data = {
    { time = 1, type = 99, color = 0xFFFFFF, size = 25, text = "未知类型" },
} } } }
_G.COMMENTS = nil
local ok_unknown = pcall(_G.convert_danmaku_to_ass_events, true)
check_true("未知弹幕类型（99）不抛异常", ok_unknown, "抛了异常")
check("未知类型被丢弃（无 style ⇒ 无事件）", #(_G.COMMENTS or {}), 0)

-- ============================================================================
-- 汇总
-- ============================================================================
print("")
print(string.rep("=", 76))
print("§3 密度档位明细（同 y 带且时间相交的弹幕对数 / 实际重叠数）")
for _, r in ipairs(density_report) do
    print(string.format("   %-6s n=%-5d 事件=%-5d 滚动=%-5d 同带对=%-6d 重叠=%d",
        r.name, r.n, r.total, r.r2l, r.pairs, r.bad))
end
print(string.rep("=", 76))
print(string.format("通过 %d，失败 %d", pass, fail))
if fail == 0 then
    print("结果：全部通过 ✅")
else
    print("结果：存在失败 ❌")
end
os.exit(fail == 0 and 0 or 1)
