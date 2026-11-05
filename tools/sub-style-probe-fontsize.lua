-- sub-style-probe-fontsize.lua —— v1.0.9 内封 \pos ASS 的缩放 / 字号真机探针
--
-- 加载方式（由 tools/sub-style-e2e.py 编排）：
--   mpv --script=<本文件> --vo=gpu --pause=yes --image-display-duration=inf
--       <tools/sub-style-mkv-fixture.py 生成的内封 ASS MKV>
--   SUBSTYLE_FS_MODE=plain|bars   plain = 无黑边，测手动缩放/字号；
--                                 bars  = 上下 24px 内嵌黑条，测自动缩小 + 预设缓存
--   SUBSTYLE_FS_BASE_N=<int>      bars 模式用：plain 模式的 baseline 字幕像素数
--
-- 为什么必须自己造 MKV：v1.0.9 的 Fontsize 通道只在内封 ASS 上启用。
-- --sub-file 加载的是外挂轨，测不到；真实示例 MKV 4.1GB 不适合进门禁。
-- 详见 tools/sub-style-mkv-fixture.py 的文件头。
--
-- 判据全部来自 screenshot-raw('subtitles') 与 ('video') 的逐像素差分，
-- 只统计上字幕带 y20..130（\pos(320,60) 的 explicit 事件所在处），
-- 避开底部 show-text 提示与 uosc 控件。输出 PROBE PASS/FAIL + FS 诊断行。
--
-- 这组断言同时复现用户报障的「点缩放没反应」：通道关闭时 sub-scale 确实变成
-- 1.5，但 \pos 字幕像素纹丝不动；通道开启后 Fontsize 写入才让画面变大。

local MODE = os.getenv('SUBSTYLE_FS_MODE') or 'plain'
local BASE_N = tonumber(os.getenv('SUBSTYLE_FS_BASE_N') or '0') or 0
local BASE_UNITS = 20           -- 夹具 ASS 样式表的 Default Fontsize
local SETTLE = 1.4              -- 命令后等 configure_ass / 重绘落定
local PREFIX = 'script-message-to uosc_subtitle_style '

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
local function num(name, def) return mp.get_property_number(name, def) end

local function fontsize_override()
    local ov = mp.get_property('sub-ass-style-overrides') or ''
    local v = ov:match('Fontsize=([%d%.]+)')
    return v and tonumber(v) or nil
end

local function preset_has_size()
    local path = mp.command_native({'expand-path', '~~/uosc-subtitle-style-preset.json'})
    local f = path and io.open(path, 'rb')
    if not f then return false, 'no preset file' end
    local t = f:read('*a') or ''
    f:close()
    return t:find('"size"') ~= nil, t:sub(1, 100)
end

-- 只统计上字幕带，返回像素数 / 盒高 / 上下边界与关键属性
local function stats(tag)
    local ok1, a = pcall(mp.command_native, {'screenshot-raw', 'subtitles'})
    local ok2, b = pcall(mp.command_native, {'screenshot-raw', 'video'})
    if not (ok1 and ok2) or type(a) ~= 'table' or type(b) ~= 'table'
        or not a.data or not b.data or a.w ~= b.w or a.h ~= b.h then
        print('FS ' .. tag .. ' NO_FRAME')
        return nil
    end
    local w, h = a.w, a.h
    local sa, sb, da, db = a.stride, b.stride, a.data, b.data
    local cnt, lo, hi = 0, h + 1, -1
    for y = 20, math.min(130, h - 1) do
        for x = 0, w - 1 do
            local i, j = y * sa + x * 4 + 1, y * sb + x * 4 + 1
            local bb, gg, rr = da:byte(i, i + 2)
            local b2, g2, r2 = db:byte(j, j + 2)
            if math.abs(bb - b2) + math.abs(gg - g2) + math.abs(rr - r2) > 60 then
                cnt = cnt + 1
                if y < lo then lo = y end
                if y > hi then hi = y end
            end
        end
    end
    local box_h = hi >= lo and (hi - lo + 1) or 0
    local fs = fontsize_override()
    local s = {
        n = cnt, h = box_h, y0 = lo, y1 = hi, fs = fs,
        scale = num('sub-scale', -1), fsz = num('sub-font-size', -1),
        pos = num('sub-pos', -1),
    }
    print(string.format('FS %s n=%d h=%d y0=%d y1=%d ov=%s scale=%g fsz=%g pos=%g',
        tag, cnt, box_h, lo, hi, fs and ('Fontsize=' .. tostring(fs)) or '-',
        s.scale, s.fsz, s.pos))
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

-- ---------------------------------------------------------------- plain --
if MODE == 'plain' then
    step(nil, '00-baseline', function(s)
        ctx.b = s
        local ct = mp.get_property_native('current-tracks/sub')
        local extra = mp.get_property('sub-ass-extradata') or ''
        record('fs-track-internal-ass',
            ct ~= nil and not ct.external and tostring(ct.codec) == 'ass',
            'external=' .. tostring(ct and ct.external) .. ' codec=' .. tostring(ct and ct.codec))
        record('fs-extradata-has-style',
            extra:find('PlayResY') ~= nil and extra:find('Style:') ~= nil,
            'len=' .. #extra)
        record('fs-baseline-frame-ok', s.n > 300, 'n=' .. s.n)
        record('fs-baseline-no-fontsize',
            s.fs == nil and math.abs(s.scale - 1) < 0.01,
            'ov=' .. tostring(s.fs) .. ' scale=' .. s.scale)
    end)
    step('scale 1.5', '01-scale150', function(s)
        ctx.s150 = s
        record('fs-scale-writes-ass-fontsize',
            s.fs ~= nil and math.abs(s.fs - BASE_UNITS * 1.5) < 0.6,
            'Fontsize=' .. tostring(s.fs))
        record('fs-scale-neutralizes-sub-scale', math.abs(s.scale - 1) < 0.01,
            'sub-scale=' .. s.scale)
        record('fs-scale-folds-sub-font-size',
            math.abs(s.fsz - ctx.b.fsz * 1.5) < 1.0,
            'sub-font-size ' .. ctx.b.fsz .. ' -> ' .. s.fsz)
        record('fs-scale-enlarges-pos-subtitle',
            s.n > ctx.b.n * 1.35 and s.h > ctx.b.h + 2,
            string.format('n %d -> %d, h %d -> %d', ctx.b.n, s.n, ctx.b.h, s.h))
    end)
    step('scale 1.0', '02-scale100', function(s)
        record('fs-scale-reset-restores',
            s.fs == nil and near(s.n, ctx.b.n, 0.08),
            string.format('n=%d base=%d ov=%s', s.n, ctx.b.n, tostring(s.fs)))
    end)
    step('size-step 8', '03-sizeplus8', function(s)
        ctx.splus = s
        record('fs-size-step-writes-fontsize',
            s.fs ~= nil and s.fs > BASE_UNITS + 0.5,
            'Fontsize=' .. tostring(s.fs))
        record('fs-size-step-enlarges',
            s.n > ctx.b.n * 1.08 and s.n < ctx.s150.n,
            string.format('n base=%d plus=%d scale150=%d', ctx.b.n, s.n, ctx.s150.n))
    end)
    step('size-step -8', '04-size-step-back', function(s)
        record('fs-size-step-reversible', near(s.n, ctx.b.n, 0.08),
            string.format('n=%d base=%d', s.n, ctx.b.n))
    end)
    -- \pos 字幕保持原位：先到边界 150%，再点「下移 5%」不得有任何视觉位移
    step('pos 150', '05-nudge', function(s)
        record('fs-nudge-keeps-pos-subtitle',
            near(s.n, ctx.b.n, 0.08) and math.abs(s.y1 - ctx.b.y1) <= 2,
            string.format('n %d -> %d, y1 %d -> %d', ctx.b.n, s.n, ctx.b.y1, s.y1))
        record('fs-nudge-boundary-clamps', math.abs(s.pos - 150) < 0.01,
            'sub-pos=' .. s.pos)
    end, 'nudge 5')
    step('ass-fontsize-toggle', '06-channel-off', function(s)
        record('fs-toggle-off-clears-fontsize', s.fs == nil,
            'ov=' .. tostring(s.fs))
    end)
    -- 关通道后重放用户报障：sub-scale 变成 1.5，但 \pos 字幕像素不动
    step('scale 1.5', '07-off-scale-no-visual', function(s)
        record('fs-channel-off-uses-native-sub-scale', s.scale > 1.4,
            'sub-scale=' .. s.scale)
        record('fs-channel-off-scale-ignored-by-pos',
            s.fs == nil and near(s.n, ctx.b.n, 0.10),
            string.format('n=%d base=%d', s.n, ctx.b.n))
    end)
    step('scale 1.0', '08-toggle-on', nil, 'ass-fontsize-toggle')
    step('scale 1.5', '09-toggle-on-restores', function(s)
        record('fs-toggle-on-restores',
            s.fs ~= nil and math.abs(s.fs - BASE_UNITS * 1.5) < 0.6
                and s.n > ctx.b.n * 1.35,
            string.format('Fontsize=%s n=%d base=%d', tostring(s.fs), s.n, ctx.b.n))
    end)

-- ----------------------------------------------------------------- bars --
else
    step(nil, '00-fit', function(s)
        ctx.b = s
        local ct = mp.get_property_native('current-tracks/sub')
        record('fs-bars-track-internal-ass',
            ct ~= nil and not ct.external and tostring(ct.codec) == 'ass',
            'external=' .. tostring(ct and ct.external))
        record('fs-bars-auto-detect-applied',
            s.fs ~= nil and s.fs < BASE_UNITS and math.abs(s.scale - 1) < 0.01,
            string.format('Fontsize=%s sub-scale=%g', tostring(s.fs), s.scale))
        record('fs-bars-shrinks-pos-subtitle',
            BASE_N > 0 and s.n < BASE_N * 0.95 and s.n > 100,
            string.format('n=%d plain-baseline=%d', s.n, BASE_N))
    end)
    step('size-step 8', '01-sizeplus8', function(s)
        local has, raw = preset_has_size()
        record('fs-bars-size-step-writes-fontsize',
            s.fs ~= nil and ctx.b.fs ~= nil and s.fs > ctx.b.fs + 0.5,
            string.format('Fontsize %s -> %s', tostring(ctx.b.fs), tostring(s.fs)))
        record('fs-bars-size-step-enlarges', s.n > ctx.b.n * 1.05,
            string.format('n %d -> %d', ctx.b.n, s.n))
        record('fs-bars-size-step-saves-preset', has, raw)
    end)
    step('size-step -8', '02-back', function(s)
        record('fs-bars-size-step-reversible', near(s.n, ctx.b.n, 0.10),
            string.format('n=%d fit=%d', s.n, ctx.b.n))
    end)
    step('letterbox-toggle', '03-fit-off', function(s)
        record('fs-bars-off-clears-fontsize', s.fs == nil,
            'ov=' .. tostring(s.fs))
        record('fs-bars-off-restores-visual',
            BASE_N > 0 and near(s.n, BASE_N, 0.10),
            string.format('n=%d plain-baseline=%d', s.n, BASE_N))
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
    print('FS MODE=' .. MODE .. ' BASE_N=' .. BASE_N)
    after(2.0, function() run_step(1) end)
end)
