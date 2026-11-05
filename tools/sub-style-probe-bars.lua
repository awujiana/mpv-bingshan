-- sub-style-probe-bars.lua —— v1.0.7 上下黑边贴合真机探针
-- 加载方式：mpv --script=<本文件> --sub-file=...bars-main.srt
--          --sub-file=...bars-sec.srt --secondary-sid=2 --sub-margin-y=80
--          <带内嵌黑条的 640x360 图片>（由 sub-style-e2e.py 用 Pillow 生成）
--
-- 为什么用 SRT：普通文本对白完全受 sub-pos / sub-scale / sub-margin-y 控制，
-- 不像带 \pos 的 explicit ASS 事件对位置豁免；正好覆盖用户要的「对话字幕」。
-- 为什么把 --sub-margin-y 设成 80（360p 帧 ⇒ 40px）：让「关闭贴合」时
-- 主轨字幕压在画面中部；打开贴合后两轨应分别缩进 24px 的下/上黑边，
-- 画面中部差分像素归零。
--
-- 判据全部来自 screenshot-raw('subtitles') 与 ('video') 的逐像素差分，
-- 与 OSD 报告、uosc 顶栏无关。输出 PROBE PASS/FAIL + BARS 诊断行，最后 quit。

local BAR_FRAC = 24 / 360      -- 夹具黑条厚度占帧高比例，按比例换算防缩放
local BASE_MARGIN = 80         -- 由命令行 --sub-margin-y=80 给出

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

local function after(sec, fn)
    mp.add_timeout(sec, function() fn() end)
end

local function num(name, def)
    return mp.get_property_number(name, def)
end

local function menu(command)
    mp.command(command)   -- 复现 uosc 菜单 value 的执行路径
end

local function props_text()
    return string.format('pos=%s secpos=%s scale=%s secscale=%s margin=%s fontsize=%s',
        tostring(num('sub-pos', -1)), tostring(num('secondary-sub-pos', -1)),
        tostring(num('sub-scale', -1)), tostring(num('secondary-sub-scale', -1)),
        tostring(num('sub-margin-y', -1)), tostring(num('sub-font-size', -1)))
end

-- 差分统计：字幕像素落在上黑边 / 画面区 / 下黑边各多少
local function diff_stats(tag)
    local ok1, a = pcall(mp.command_native, {'screenshot-raw', 'subtitles'})
    local ok2, b = pcall(mp.command_native, {'screenshot-raw', 'video'})
    if not (ok1 and ok2) or type(a) ~= 'table' or type(b) ~= 'table'
        or not a.data or not b.data or a.w ~= b.w or a.h ~= b.h then
        print('BARS ' .. tag .. ' NO_FRAME')
        return nil
    end
    local w, h, sa, sb, da, db = a.w, a.h, a.stride, b.stride, a.data, b.data
    local bar = math.max(1, math.floor(h * BAR_FRAC + 0.5))
    local top, mid, bottom = 0, 0, 0
    for y = 0, h - 1 do
        for x = 0, w - 1, 2 do
            local i = y * sa + x * 4 + 1
            local j = y * sb + x * 4 + 1
            local bb, gg, rr = da:byte(i, i + 2)
            local bb2, gg2, rr2 = db:byte(j, j + 2)
            if math.abs(bb - bb2) + math.abs(gg - gg2) + math.abs(rr - rr2) > 60 then
                if y < bar then top = top + 1
                elseif y >= h - bar then bottom = bottom + 1
                else mid = mid + 1 end
            end
        end
    end
    print(string.format('BARS %s w=%d h=%d bar=%d top=%d mid=%d bottom=%d | %s',
        tag, w, h, bar, top, mid, bottom, props_text()))
    return {top = top, mid = mid, bottom = bottom, h = h, bar = bar}
end

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.commandv('quit')
end

local on_auto_ready

-- 自动检测在 file-loaded + inspect_delay + letterbox_delay 之后跑；图片 + pause
-- 模式下 file-loaded 可能晚到 1s 以上，固定 3s 延时会造成「探针先关开关、
-- timer 后到」的竞态。这里轮询等自动贴合真正落定，顺便把它作为一条断言。
local function wait_auto(tries)
    local margin = num('sub-margin-y', -1)
    local scale = num('sub-scale', -1)
    if math.abs(margin - BASE_MARGIN) > 1 and scale > 0 and scale < 1 then
        record('bars-auto-detect-applied', true,
            string.format('margin=%s scale=%s', tostring(margin), tostring(scale)))
        after(0.3, on_auto_ready)
        return
    end
    if tries >= 60 then
        record('bars-auto-detect-applied', false,
            string.format('timeout margin=%s scale=%s', tostring(margin), tostring(scale)))
        finish()
        return
    end
    after(0.2, function() wait_auto(tries + 1) end)
end

on_auto_ready = function()
    local fit_scale = num('sub-scale', -1)
    local fit_margin = num('sub-margin-y', -1)
    local fit_sec_scale = num('secondary-sub-scale', -1)
    print('BARS FITPROPS ' .. props_text())
    record('bars-fit-main-pos-bottom', math.abs(num('sub-pos', -1) - 100) < 0.01,
        tostring(num('sub-pos', -1)))
    record('bars-fit-sec-pos-top', math.abs(num('secondary-sub-pos', -1) - 0) < 0.01,
        tostring(num('secondary-sub-pos', -1)))
    record('bars-fit-scale-limited', fit_scale > 0 and fit_scale < 1,
        tostring(fit_scale))
    record('bars-fit-sec-scale-same', math.abs(fit_sec_scale - fit_scale) < 0.001,
        tostring(fit_sec_scale))
    record('bars-fit-margin-overrides-baseline', math.abs(fit_margin - BASE_MARGIN) > 1,
        tostring(fit_margin))
    record('bars-fit-margin-is-integer', fit_margin == math.floor(fit_margin),
        tostring(fit_margin))

    -- 关掉贴合拿基线（disable_barfit 会还原 sub-margin-y 并 nudge 重绘）
    menu('script-message-to uosc_subtitle_style letterbox-toggle')
    after(0.8, function()
        local base = diff_stats('BASE')
        local off_margin = num('sub-margin-y', -1)
        record('bars-off-restores-margin', math.abs(off_margin - BASE_MARGIN) < 0.01,
            tostring(off_margin))
        record('bars-base-frame-ok', base ~= nil)
        record('bars-base-dialogue-over-picture', base ~= nil and base.mid > 150,
            base and tostring(base.mid) or 'no frame')

        -- 再打开贴合，立即重检
        menu('script-message-to uosc_subtitle_style letterbox-toggle')
        after(0.8, function()
            local fit = diff_stats('FIT')
            record('bars-fit-frame-ok', fit ~= nil)
            record('bars-fit-bottom-dialogue-in-lower-bar',
                fit ~= nil and fit.bottom > 80,
                fit and tostring(fit.bottom) or 'no frame')
            record('bars-fit-top-dialogue-in-upper-bar',
                fit ~= nil and fit.top > 80,
                fit and tostring(fit.top) or 'no frame')
            record('bars-fit-no-dialogue-over-picture',
                fit ~= nil and base ~= nil and fit.mid < base.mid * 0.25,
                fit and base and (tostring(fit.mid) .. ' vs base ' .. tostring(base.mid))
                    or 'no frame')
            record('bars-fit-both-bars-populated',
                fit ~= nil and fit.top > 0 and fit.bottom > 0,
                fit and (tostring(fit.top) .. '/' .. tostring(fit.bottom)) or 'no frame')
            finish()
        end)
    end)
end

after(0.5, function() wait_auto(0) end)
