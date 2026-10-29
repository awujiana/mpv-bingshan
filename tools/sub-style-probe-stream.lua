-- sub-style-probe-stream.lua —— 字幕流连续性回归探针
-- 背景（2026-10-21 用户报障）：编辑样式时字幕「定住在一句」不再跳句。
-- 根因：override 切换 / sub-reload 会让字幕解码器重建，重建后新解码器拿不到
-- 已消费的包（外挂字幕靠 sub_preload 侥幸无恙，内封字幕必然中招）。
-- 本探针用**多句 fixture** 逐句校验：编辑前后「实际显示文本」是否始终与
-- playback-time 对应的期望事件一致。单句贯穿全片的 fixture 覆盖不到此分支。
--
-- 用法：mpv --script=<本文件> --sub-file=sub-style-smoke-multi.ass ...
-- 输出：PROBE PASS/FAIL ... 与 PROBE SUMMARY（E2E 侧解析）

local EVENTS = {
    {0, 2, 'ONE'}, {2, 4, 'TWO'}, {4, 6, 'THREE'}, {6, 8, 'FOUR'},
    {8, 10, 'FIVE'}, {10, 12, 'SIX'}, {12, 14, 'SEVEN'}, {14, 16, 'EIGHT'},
}

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

local function expected(pt)
    for _, e in ipairs(EVENTS) do
        if pt >= e[1] and pt < e[2] then return e[3] end
    end
    return nil
end

-- 采样窗口：收集 (playback-time, 期望, 实际)
local function sample_window(seconds, label)
    local samples = {}
    local timer
    timer = mp.add_periodic_timer(0.25, function()
        local pt = mp.get_property_number('playback-time', -1)
        local txt = mp.get_property('sub-text') or ''
        local got = txt:match('(%u+)$')
        if pt >= 0 then samples[#samples + 1] = {pt = pt, exp = expected(pt), got = got} end
    end)
    return function()
        timer:kill()
        local mism, seen, checked = 0, {}, 0
        for _, s in ipairs(samples) do
            if s.exp then
                checked = checked + 1
                if s.got ~= s.exp then mism = mism + 1 end
                seen[s.got or '-'] = true
            end
        end
        local distinct = 0
        for _ in pairs(seen) do distinct = distinct + 1 end
        return checked, mism, distinct
    end
end

local step_size, step_font, step_done

step_size = function()
    -- 基线窗口（未编辑）→ 必须先证明字幕本来就会跳句。
    -- 窗口取 3.2s：事件每 2s 一句，窗口必须**必然**跨过至少一个句界，
    -- 否则窗口整段落在同一句内会让 distinct=1（曾因 2.0s 窗口偶发失败）。
    local finish_base = sample_window(3.2)
    mp.add_timeout(3.2, function()
        local checked, mism, distinct = finish_base()
        record('baseline-advances', checked >= 5 and mism <= 1 and distinct >= 2,
            string.format('checked=%d mism=%d distinct=%d', checked, mism, distinct))
        -- 编辑：改字号（首次进入 force，必然重建一次）
        local finish_edit = sample_window(4.0)
        mp.commandv('script-message-to', 'uosc_subtitle_style', 'size', '24')
        mp.add_timeout(4.0, function()
            local c2, m2, d2 = finish_edit()
            record('after-size-edit-advances', c2 >= 8 and m2 <= 2 and d2 >= 2,
                string.format('checked=%d mism=%d distinct=%d', c2, m2, d2))
            step_font()
        end)
    end)
end

step_font = function()
    -- 稳态编辑（已 force）：改字体不应再重建，字幕应继续正常跳句
    local finish = sample_window(4.0)
    mp.commandv('script-message-to', 'uosc_subtitle_style', 'font', 'Noto', 'Serif', 'CJK', 'SC')
    mp.add_timeout(4.0, function()
        local c, m, d = finish()
        record('after-font-edit-advances', c >= 8 and m <= 2 and d >= 2,
            string.format('checked=%d mism=%d distinct=%d', c, m, d))
        record('no-lua-errors-marker', true)
        step_done()
    end)
end

step_done = function()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.command('quit')
end

mp.register_event('file-loaded', function()
    mp.add_timeout(1.0, function()
        step_size()
    end)
end)

print('PROBE stream driver loaded')
