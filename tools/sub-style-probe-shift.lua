-- sub-style-probe-shift.lua —— v1.0.11 真机探针
--
-- 覆盖两件用户报障的收口验证，都由 tools/sub-style-e2e.py 编排：
--   MODE=bars   内封 ASS（两条都是 \\pos explicit 事件，底部对白 \\pos(320,338)）
--               + 上下 24px 内嵌黑条。验证黑边贴合把「对话轨道字幕」整条推进
--               下黑边、PlayResY/Fontsize 成对出现、开关与位移通道可逆，
--               并复现「关掉位移通道后点下移没反应」的原报障。
--   MODE=report 同一夹具，用 --script-opts=uosc_subtitle_style-show_report=yes|no
--               启动两次互为对照组。验证 conf 开关被读到、左上角 OSD 完全不输出、
--               osd-align-* 不被临时改动，而黑边贴合（检测链）照常执行；
--               再用 report-toggle 反转运行时开关做双向验证。
--               ⚠ 夹具是 MJPEG 单帧 + 内封 ASS，mpv 对图片型字幕不暴露 sub-text
--                 （真机实测恒为 nil），自动检测链走不到 flash_tl。因此正对照
--                 用 preset-save——它是另一条必然调用 flash_tl 的路径，能纯粹
--                 验证「开关是否管住左上角输出」，不掺入检测链能否触发的变量。
--
-- 为什么底部对白也用 \\pos：用户截图里的对白「这到底是…」点下移毫无反应，
-- 说明它是 explicit 定位事件（普通对白 sub-pos 是有效的）。夹具必须同构。
-- 像素判据来自 screenshot-raw('subtitles') 与 ('video') 的逐像素差分。
--
-- 用法见 tools/sub-style-e2e.py 的 5g / 5h 阶段；探针自行 quit。

local MODE = os.getenv('SUBSTYLE_SHIFT_MODE') or 'bars'
-- report 模式下由编排器声明本次期望（yes=默认显示 / no=conf 关闭），
-- 两个真机运行互为对照组，避免「本来就没有 OSD」的假阳性。
local EXPECT = os.getenv('SUBSTYLE_SHIFT_EXPECT') or 'no'
local SETTLE = 1.4
local PREFIX = 'script-message-to uosc_subtitle_style '
local BASE_UNITS = 20     -- 夹具 ASS Default Fontsize
local BASE_PRY = 360      -- 夹具 ASS PlayResY
local BAR_PX = 24         -- 上下内嵌黑条厚度

local pass, fail = 0, 0
local failures = {}

local function record(name, ok, detail)
    if ok then pass = pass + 1 else
        fail = fail + 1
        failures[#failures + 1] = name
    end
    print(string.format('PROBE %s %s%s', ok and 'PASS' or 'FAIL', name,
        detail and (' | ' .. tostring(detail)) or ''))
end

local function after(sec, fn) mp.add_timeout(sec, fn) end
local function cmd(c) mp.command(PREFIX .. c) end
local function num(n, d) return mp.get_property_number(n, d) end
local function ov_num(key)
    local ov = mp.get_property('sub-ass-style-overrides') or ''
    local v = ov:match(key .. '=([%d%.]+)')
    return v and tonumber(v) or nil
end
local function api_state()
    local ok, v = pcall(mp.get_property_native,
        'user-data/uosc_subtitle_style/state')
    if ok and type(v) == 'string' then
        -- 有的 mpv 版本对 user-data 子属性仍返回 JSON 文本；这里不解析，
        -- 只把原始值交给需要它的断言（bars 模式用不到）。
        return nil, v
    end
    return (ok and type(v) == 'table') and v or nil, nil
end

-- 两个独立波段：TOP y0..150 (\pos 顶部注释)、BOT y200..h-1 (底部对白)。
-- 返回 {top={n,y0,y1}, bot={n,y0,y1}, fs, pry, pos, scale}
local function stats(tag)
    local ok1, a = pcall(mp.command_native, {'screenshot-raw', 'subtitles'})
    local ok2, b = pcall(mp.command_native, {'screenshot-raw', 'video'})
    if not (ok1 and ok2) or type(a) ~= 'table' or type(b) ~= 'table'
        or not a.data or not b.data or a.w ~= b.w or a.h ~= b.h then
        print('SH ' .. tag .. ' NO_FRAME')
        return nil
    end
    local w, h = a.w, a.h
    local sa, sb, da, db = a.stride, b.stride, a.data, b.data
    local bands = {{0, math.min(150, h - 1)}, {200, h - 1}}
    local boxes = {}
    for _, bd in ipairs(bands) do
        local cnt, y0, y1 = 0, h + 1, -1
        for y = bd[1], bd[2] do
            for x = 0, w - 1 do
                local i, j = y * sa + x * 4 + 1, y * sb + x * 4 + 1
                local bb, gg, rr = da:byte(i, i + 2)
                local b2, g2, r2 = db:byte(j, j + 2)
                if math.abs(bb - b2) + math.abs(gg - g2) + math.abs(rr - r2) > 60 then
                    cnt = cnt + 1
                    if y < y0 then y0 = y end
                    if y > y1 then y1 = y end
                end
            end
        end
        if y1 < y0 then y0, y1 = -1, -1 end
        boxes[#boxes + 1] = {n = cnt, y0 = y0, y1 = y1}
    end
    local s = {
        top = boxes[1], bot = boxes[2], h = h,
        fs = ov_num('Fontsize'), pry = ov_num('PlayResY'),
        pos = num('sub-pos', -1), scale = num('sub-scale', -1),
        fsz = num('sub-font-size', -1),
    }
    print(string.format(
        'SH %-24s TOP[n=%d y=%d..%d] BOT[n=%d y=%d..%d] | PlayResY=%s Fontsize=%s pos=%g scale=%g fsz=%g',
        tag, s.top.n, s.top.y0, s.top.y1, s.bot.n, s.bot.y0, s.bot.y1,
        s.pry and tostring(s.pry) or '-', s.fs and tostring(s.fs) or '-',
        s.pos, s.scale, s.fsz))
    return s
end

local function near(a, b, frac)
    return math.abs(a - b) <= math.max(1, b * frac)
end

local ctx = {}
local sequence = {}
local function step(command, tag, check, command2)
    sequence[#sequence + 1] = {
        command = command, command2 = command2, tag = tag, check = check,
    }
end

if MODE == 'bars' then
    -- 文件载入后 inspect_delay(1.2) + letterbox_delay(0.6) 才跑自动贴合，
    -- 编排器会先等 4.5s，这里第一步直接采「贴合已落定」的画面。
    step(nil, '00-fit', function(s)
        ctx.fit = s
        local bar_top = s.h - BAR_PX
        record('sh-barfit-writes-playres',
            s.pry ~= nil and s.pry < BASE_PRY and BASE_PRY / s.pry > 1,
            'PlayResY=' .. tostring(s.pry))
        record('sh-barfit-shrinks-fontsize',
            s.fs ~= nil and s.fs < BASE_UNITS,
            'Fontsize=' .. tostring(s.fs))
        -- 核心：对话轨道字幕整条都在下黑边里，不再压在画面内容上
        record('sh-dialogue-fully-inside-bottom-bar',
            s.bot.n > 100 and s.bot.y0 >= bar_top and s.bot.y1 <= s.h - 1,
            string.format('bot y=%d..%d bar_top=%d h=%d',
                s.bot.y0, s.bot.y1, bar_top, s.h))
        record('sh-top-sign-still-rendered', s.top.n > 100,
            'top n=' .. s.top.n)
    end)
    -- 关贴合：PlayResY / Fontsize 都必须清空，对白退回压画面的位置
    step('letterbox-toggle', '01-fit-off', function(s)
        ctx.off = s
        local bar_top = s.h - BAR_PX
        record('sh-fit-off-clears-playres', s.pry == nil,
            'PlayResY=' .. tostring(s.pry))
        record('sh-fit-off-clears-fontsize', s.fs == nil,
            'Fontsize=' .. tostring(s.fs))
        record('sh-fit-off-dialogue-leaves-bar',
            s.bot.n > 100 and s.bot.y0 < bar_top,
            string.format('bot y0=%d bar_top=%d', s.bot.y0, bar_top))
    end)
    -- 位移通道开启：点「下移」必须真的推动 \pos 对白（复现原报障的反向验证）
    -- v1.0.15：旧判据期待 ratio>1.4 / 位移≥20px，那正是把底部对白推到视频外
    --   的越界行为（用户截图「对话字幕有一部分在视频外了」）。现在 pos=150
    --   钳到 ass_pos_shift_max=1.06，仍要求确实动了（~4px）、顶部 signs 仍在
    --   帧内，且 PlayResY / Fontsize 都停在上限；更严格的像素级不变量由
    --   tools/sub-style-probe-bounds.lua（E2E 5m）负责。
    step('pos 150', '02-pos150-shift', function(s)
        local ratio = s.pry and (BASE_PRY / s.pry) or 0
        record('sh-pos150-writes-playres',
            s.pry ~= nil and ratio > 1.0 and ratio <= 1.061,
            string.format('PlayResY=%s ratio=%.4f limit=1.06',
                tostring(s.pry), ratio))
        record('sh-pos150-moves-positioned-subtitle',
            s.top.y1 - ctx.off.top.y1 >= 2
            and s.top.y1 - ctx.off.top.y1 <= 8
            and s.top.y1 <= s.h - 1,
            string.format('top y1 %d -> %d h=%d', ctx.off.top.y1, s.top.y1, s.h))
        record('sh-pos150-compensates-fontsize',
            s.fs ~= nil and s.fs < BASE_UNITS
            and s.fs >= BASE_UNITS / 1.06 - 0.1,
            'Fontsize=' .. tostring(s.fs))
        record('sh-pos150-ratio-at-limit', math.abs(ratio - 1.06) < 0.005,
            string.format('ratio=%.4f', ratio))
    end)
    -- 关通道后重放用户报障：sub-pos 变了，但 \pos 字幕像素纹丝不动
    step('ass-pos-shift-toggle', '03-channel-off', nil)
    step('pos 100', '04-off-reset', nil)
    step('pos 150', '05-off-no-visual', function(s)
        record('sh-channel-off-no-playres', s.pry == nil,
            'PlayResY=' .. tostring(s.pry))
        record('sh-channel-off-keeps-pos-subtitle',
            near(s.top.n, ctx.off.top.n, 0.10)
            and math.abs(s.top.y1 - ctx.off.top.y1) <= 2,
            string.format('n %d -> %d, y1 %d -> %d',
                ctx.off.top.n, s.top.n, ctx.off.top.y1, s.top.y1))
        record('sh-channel-off-sub-pos-changed', math.abs(s.pos - 150) < 0.01,
            'sub-pos=' .. s.pos)
    end)
    -- 打开通道 + 重新打开贴合：letterbox-refresh 在 bar_fit 关闭时是空操作，
    -- 必须先用 letterbox-toggle 把开关打开（它内部会立即 refresh 一次）。
    step('ass-pos-shift-toggle', '06-channel-on', nil, 'letterbox-toggle')
    step('letterbox-refresh', '07-back-to-bar', function(s)
        local bar_top = s.h - BAR_PX
        record('sh-refresh-restores-playres', s.pry ~= nil,
            'PlayResY=' .. tostring(s.pry))
        record('sh-refresh-dialogue-back-in-bar',
            s.bot.n > 100 and s.bot.y0 >= bar_top,
            string.format('bot y=%d..%d bar_top=%d',
                s.bot.y0, s.bot.y1, bar_top))
    end)
else
    -- report 模式：命令行 --script-opts=uosc_subtitle_style-show_report=yes|no
    -- 起两次，EXPECT 声明本次期望。只判「配置被读到 / 左上角输出计数 /
    -- OSD 对齐没被临时改 / 检测链照跑」，不判像素位置的绝对值。
    local start_ax = mp.get_property('osd-align-x') or 'center'
    local start_ay = mp.get_property('osd-align-y') or 'bottom'
    local expect_on = EXPECT == 'yes'

    -- 两个 getter 都必须避开 `cond and false or ...`：Lua 里 false 会让 or
    -- 继续求值，把「明确读到 false」误判成「没读到」。
    local function report_enabled()
        local st, raw = api_state()
        local v
        if st and type(st) == 'table' and type(st.runtime) == 'table' then
            v = st.runtime.show_report
        end
        if v == nil and type(raw) == 'string' then
            if raw:find('"show_report"%s*:%s*false') then v = false
            elseif raw:find('"show_report"%s*:%s*true') then v = true end
        end
        return v
    end
    local function report_count()
        local st, raw = api_state()
        local v
        if st and type(st) == 'table' and type(st.runtime) == 'table' then
            v = st.runtime.report_shown
        end
        if v == nil and type(raw) == 'string' then
            v = tonumber(raw:match('"report_shown"%s*:%s*(%d+)'))
        end
        return v
    end
    local function align_unchanged()
        return (mp.get_property('osd-align-x') or 'center') == start_ax
            and (mp.get_property('osd-align-y') or 'bottom') == start_ay
    end
    local function count_ok(before, want_show)
        local after = report_count()
        if type(after) ~= 'number' or type(before) ~= 'number' then
            return false, 'report_shown=' .. tostring(after)
        end
        local d = after - before
        local ok = want_show and d >= 1 or d == 0
        return ok, string.format('before=%d after=%d delta=%d want_show=%s',
            before, after, d, tostring(want_show))
    end

    step(nil, '00-report-config', function(s)
        local on, shown = report_enabled(), report_count()
        ctx.base_shown = shown
        record(expect_on and 'sh-report-config-read-as-on'
            or 'sh-report-config-read-as-off',
            on == expect_on,
            'runtime.show_report=' .. tostring(on)
            .. ' expect=' .. tostring(expect_on))
        record('sh-report-counter-readable', type(shown) == 'number',
            'report_shown=' .. tostring(shown))
        record('sh-report-no-osd-align-change', align_unchanged(),
            string.format('start=%s/%s now=%s/%s', start_ax, start_ay,
                mp.get_property('osd-align-x') or '?',
                mp.get_property('osd-align-y') or '?'))
        -- 关掉报告不等于关掉功能：黑边贴合仍写入了 PlayResY / Fontsize
        record('sh-report-detection-still-runs',
            s.pry ~= nil and s.fs ~= nil,
            string.format('PlayResY=%s Fontsize=%s',
                tostring(s.pry), tostring(s.fs)))
        record('sh-report-dialogue-still-in-bar',
            s.bot.n > 100 and s.bot.y0 >= s.h - BAR_PX,
            string.format('bot y=%d..%d bar_top=%d',
                s.bot.y0, s.bot.y1, s.h - BAR_PX))
    end)
    -- preset-save 是除 run_inspect 之外唯一会调 flash_tl 的入口，且不依赖
    -- sub-text / 像素采样，正好用来做「开关是否管住左上角输出」的纯净对照。
    step('preset-save', '01-save-conf', function()
        local ok, detail = count_ok(ctx.base_shown, expect_on)
        record(expect_on and 'sh-report-on-actually-shows'
            or 'sh-report-off-no-osd-output', ok, detail)
        -- 关闭时即便被显式调用，也不许临时改 osd-align-*
        record('sh-report-off-keeps-osd-align',
            expect_on or align_unchanged(),
            string.format('now=%s/%s', mp.get_property('osd-align-x') or '?',
                mp.get_property('osd-align-y') or '?'))
        ctx.shown1 = report_count()
    end)
    step('report-toggle', '02-toggle', function()
        record('sh-report-toggle-flips-runtime-state',
            report_enabled() == (not expect_on),
            'runtime.show_report=' .. tostring(report_enabled()))
    end)
    step('preset-save', '03-save-toggled', function()
        local ok, detail = count_ok(ctx.shown1, not expect_on)
        record('sh-report-toggle-takes-effect', ok, detail)
        ctx.shown2 = report_count()
    end)
    step('report-toggle', '04-toggle-back', function()
        record('sh-report-toggle-restores-conf-value',
            report_enabled() == expect_on,
            'runtime.show_report=' .. tostring(report_enabled()))
    end)
    step('preset-save', '05-save-restored', function()
        local ok, detail = count_ok(ctx.shown2, expect_on)
        record('sh-report-restore-takes-effect', ok, detail)
    end)
end

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.commandv('quit')
end

local function run_step(i)
    if i > #sequence then finish() return end
    local item = sequence[i]
    if item.command then cmd(item.command) end
    if item.command2 then
        after(0.45, function() cmd(item.command2) end)
    end
    after(SETTLE, function()
        local s = stats(item.tag)
        if item.check then
            if s then item.check(s) else
                record(item.tag .. '-frame-ok', false, 'NO_FRAME')
            end
        end
        run_step(i + 1)
    end)
end

mp.register_event('file-loaded', function()
    print('SH MODE=' .. MODE)
    -- 自动黑边贴合在 inspect_delay+letterbox_delay 之后才落定，先等足 4.5s
    after(4.5, function() run_step(1) end)
end)
