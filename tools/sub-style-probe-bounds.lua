-- sub-style-probe-bounds.lua —— v1.0.15「字幕不得越过画面边界」真机探针
--
-- 用户截图：底部对白「我们那只是在比腕力而已」字形下半截被画面下边缘切掉
-- （960×540 截图里白字从 y518 一直延伸到 y539，末行仍有 177 个白像素），
-- 顶部两条 signs 却完整。真机复现（640×360 最小 Matroska 夹具）：
--   pos=100 → ratio 1.000 → BOT y319..336（无黑边）/ y342..354（24px 黑边）
--   pos=110 → ratio 1.106 → BOT y355..359，只剩 5 行像素（部分在视频外）
--   pos=120 → ratio 1.213 → BOT 无像素，整条对白消失在视频外
-- 根因：ass_y_ratio() 的手动位移分支旧版 clamp 到 2.0，没有画面边界守护。
-- v1.0.15 起统一钳到 ass_pos_shift_max（默认 1.06），本探针就是该不变量的
-- 回归门禁：无论怎么点下移，底部 \pos 对白都必须「盒高不缩水 + 完整在帧内」。
--
-- 由 tools/sub-style-e2e.py 的 5m 组编排，分别用 bars=24 / bars=0 两个夹具
-- 起两轮（SUBSTYLE_BOUNDS_KIND 只用于日志区分）。像素判据沿用
-- screenshot-raw('subtitles') 与 ('video') 的逐像素差分，两个波段：
--   TOP y0..150（顶部 signs）、BOT y200..h-1（底部对白）。
-- 探针自行 quit；不要在生产配置里常驻加载。

local KIND = os.getenv('SUBSTYLE_BOUNDS_KIND') or 'bars'
local SETTLE = 1.2
local PREFIX = 'script-message-to uosc_subtitle_style '
local BASE_PRY = 360      -- 夹具 ASS PlayResY
local LIMIT = 1.06        -- conf ass_pos_shift_max 默认值

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
local function ov_num(key)
    local ov = mp.get_property('sub-ass-style-overrides') or ''
    local v = ov:match(key .. '=([%d%.]+)')
    return v and tonumber(v) or nil
end
local function api_limit()
    local ok, v = pcall(mp.get_property_native,
        'user-data/uosc_subtitle_style/state')
    if not ok then return nil end
    if type(v) == 'table' then return tonumber(v.ass_y_limit) end
    if type(v) == 'string' then
        return tonumber(v:match('"ass_y_limit"%s*:%s*([%d%.]+)'))
    end
    return nil
end

local function stats(tag)
    local ok1, a = pcall(mp.command_native, {'screenshot-raw', 'subtitles'})
    local ok2, b = pcall(mp.command_native, {'screenshot-raw', 'video'})
    if not (ok1 and ok2) or type(a) ~= 'table' or type(b) ~= 'table'
        or not a.data or not b.data or a.w ~= b.w or a.h ~= b.h then
        print('BND ' .. tag .. ' NO_FRAME')
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
        pry = ov_num('PlayResY'), fs = ov_num('Fontsize'),
        pos = mp.get_property_number('sub-pos', -1),
    }
    print(string.format(
        'BND %-16s TOP[n=%d y=%d..%d] BOT[n=%d y=%d..%d] h=%d PlayResY=%s Fontsize=%s pos=%g',
        tag, s.top.n, s.top.y0, s.top.y1, s.bot.n, s.bot.y0, s.bot.y1, h,
        s.pry and tostring(s.pry) or '-', s.fs and tostring(s.fs) or '-', s.pos))
    return s
end

local ctx = {}
local sequence = {}
local function step(command, tag, check)
    sequence[#sequence + 1] = {command = command, tag = tag, check = check}
end

-- 通用「这一帧的对白必须完整、不得越过画面下边缘」判据。
-- 盒高与基线相比不能缩水：被裁掉下半截时 y1 会卡在 h-1 而盒高骤减，
-- 单看 y1 <= h-1 会漏判（修复前 pos=110 正是这种「贴边只剩 5 行」）。
local function dialogue_intact(s)
    local b = ctx.base and ctx.base.bot
    if not b or b.y1 < 0 then return false, 'no baseline' end
    local base_h = b.y1 - b.y0 + 1
    local h = s.bot.y1 - s.bot.y0 + 1
    local ok = s.bot.n > 100
        and s.bot.n >= b.n * 0.75
        and s.bot.y0 >= 0
        and s.bot.y1 <= s.h - 1
        and h >= base_h - 2
    return ok, string.format('bot n=%d y=%d..%d box=%d base_n=%d base_box=%d h=%d',
        s.bot.n, s.bot.y0, s.bot.y1, h, b.n, base_h, s.h)
end

local function step_checks(tag, s)
    local intact, detail = dialogue_intact(s)
    record('bnd-' .. tag .. '-dialogue-not-clipped', intact, detail)
    local ratio = s.pry and (BASE_PRY / s.pry) or nil
    record('bnd-' .. tag .. '-playres-bounded',
        ratio ~= nil and ratio <= LIMIT + 0.001,
        string.format('PlayResY=%s ratio=%s limit=%g',
            tostring(s.pry), ratio and string.format('%.4f', ratio) or '-', LIMIT))
    record('bnd-' .. tag .. '-top-sign-visible', s.top.n > 100,
        'top n=' .. s.top.n)
end

step(nil, '00-fit', function(s)
    ctx.base = s
    record('bnd-baseline-dialogue-in-frame',
        s.bot.n > 100 and s.bot.y0 >= 0 and s.bot.y1 <= s.h - 1,
        string.format('bot n=%d y=%d..%d h=%d', s.bot.n, s.bot.y0, s.bot.y1, s.h))
    record('bnd-baseline-top-sign-visible', s.top.n > 100, 'top n=' .. s.top.n)
end)
-- 110 是修复前「只剩 5 行像素」的临界点；120/150 是「整条消失」的点；
-- 中间插两次 nudge +1 覆盖用户连续点「下移 1%」的真实操作路径。
step('pos 110', '01-pos110', function(s)
    ctx.p110 = s
    step_checks('pos110', s)
end)
step('nudge 1', '02-nudge1', function(s) step_checks('nudge1', s) end)
step('nudge 1', '03-nudge2', function(s) step_checks('nudge2', s) end)
step('pos 150', '04-pos150', function(s)
    ctx.p150 = s
    step_checks('pos150', s)
end)
step('pos 100', '05-reset', function(s)
    record('bnd-reset-clears-playres', s.pry == nil,
        'PlayResY=' .. tostring(s.pry))
    record('bnd-reset-dialogue-in-frame',
        s.bot.n > 100 and s.bot.y1 <= s.h - 1,
        string.format('bot n=%d y=%d..%d h=%d', s.bot.n, s.bot.y0, s.bot.y1, s.h))
end)

local function finish()
    local a, b = ctx.p110, ctx.p150
    record('bnd-ratio-clamped-at-limit',
        a ~= nil and b ~= nil and a.pry ~= nil and b.pry ~= nil
        and math.abs(a.pry - b.pry) < 0.01
        and BASE_PRY / b.pry <= LIMIT + 0.001,
        string.format('pos110 PlayResY=%s pos150 PlayResY=%s',
            a and tostring(a.pry) or '-', b and tostring(b.pry) or '-'))
    local lim = api_limit()
    record('bnd-api-limit-exposed', lim ~= nil and math.abs(lim - LIMIT) < 0.001,
        'state.ass_y_limit=' .. tostring(lim))
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.commandv('quit')
end

local function run_step(i)
    if i > #sequence then finish() return end
    local item = sequence[i]
    if item.command then cmd(item.command) end
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
    print('BND MODE=' .. KIND)
    after(4.5, function() run_step(1) end)
end)
