-- sub-style-probe-pos.lua —— v1.0.6 回归探针：\pos 定位字幕 / 灰色字幕 / 黑色主色 / 字体
-- 加载方式：mpv --script=<本文件> --sub-file=tools/sub-style-smoke-pos-gray.ass ...
-- 覆盖用户报障的四条：
--   ① 灰色对话字幕（#8B8B8B，饱和度 0）也应自动转白字黑边；
--   ② 带 \pos 的顶部字幕必须一起变色 —— force 对 explicit 事件豁免，
--      只有 sub-ass-style-overrides 改写样式表才能生效；
--   ③ 菜单点「主颜色」必须真的传参（裸 #RRGGBB 会被 mpv 当注释吞掉 → reset）；
--   ④ 菜单点「字体」后 FontName 必须写进共享样式表，\pos 字幕才换字体。
-- 颜色判据用 screenshot-raw('subtitles') 与 ('video') 差分，只看顶部字幕带 y40-110，
-- 不受左上角 OSD 报告与 uosc 顶栏干扰。
-- 输出：PROBE PASS/FAIL <用例> <细节>，最后汇总退出。

local SMOKE_DIR = os.getenv('SUBSTYLE_SMOKE_DIR') or (os.getenv('TEMP') or '.')
SMOKE_DIR = SMOKE_DIR:gsub('\\$', '')

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

local function str(name)
    return mp.get_property(name)
end

-- 菜单命令必须走 mp.command（字符串），才能复现 uosc 的 value 执行路径
local function menu(command)
    mp.command(command)
end

local function overrides()
    return mp.get_property_native('sub-ass-style-overrides') or {}
end

local function list_has(key, value)
    local want = key .. '=' .. value
    for _, e in ipairs(overrides()) do
        if e == want then return true end
    end
    return false
end

local function list_dump()
    return '[' .. table.concat(overrides(), ' | ') .. ']'
end

-- mpv 的 sub-color 形如 #AARRGGBB；取末 6 位得 RGB
local function rgb(name)
    local v = tostring(str(name) or ''):upper()
    return v:match('(%x%x%x%x%x%x)$') or v
end

-- 顶部字幕带（y40-110）的差分像素分类：灰 / 白 / 总变化量
local function top_stats()
    local ok1, a = pcall(mp.command_native, {'screenshot-raw', 'subtitles'})
    local ok2, b = pcall(mp.command_native, {'screenshot-raw', 'video'})
    if not (ok1 and ok2) or type(a) ~= 'table' or type(b) ~= 'table'
        or not a.data or not b.data or a.w ~= b.w or a.h ~= b.h then
        return nil
    end
    local gray, white, changed = 0, 0, 0
    for y = 40, math.min(110, a.h - 1) do
        for x = 0, a.w - 1 do
            local i = y * a.stride + x * 4 + 1
            local bb, gg, rr = a.data:byte(i, i + 2)
            local j = y * b.stride + x * 4 + 1
            local bb2, gg2, rr2 = b.data:byte(j, j + 2)
            if math.abs(bb - bb2) + math.abs(gg - gg2) + math.abs(rr - rr2) > 60 then
                changed = changed + 1
                local lum = (rr + gg + bb) / 3
                local sat = math.max(rr, gg, bb) - math.min(rr, gg, bb)
                if sat < 25 and lum > 90 and lum < 200 then gray = gray + 1 end
                if rr > 225 and gg > 225 and bb > 225 then white = white + 1 end
            end
        end
    end
    return {gray = gray, white = white, changed = changed}
end

local function stat_text(s)
    return s and string.format('gray=%d white=%d changed=%d', s.gray, s.white, s.changed)
        or '(no image)'
end

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.command('quit')
end

local early, late, blackened

--------------------------------------------------------------------
-- 时序：+0.8s 采样原始灰字 → +3.4s 自动预设生效后采样 → 点黑色 → 点字体
--------------------------------------------------------------------
mp.register_event('file-loaded', function()
    after(0.8, function()
        early = top_stats()
        record('pos-early-top-gray', early ~= nil and early.gray > 100
            and early.white < 50, stat_text(early))
        after(2.6, function()
            late = top_stats()
            -- 属性层：灰色字幕应被自动套用黑白预设，并写进 ASS 样式表
            record('pos-auto-primary-ass', list_has('PrimaryColour', '&H00FFFFFF'),
                list_dump())
            record('pos-auto-outline-ass', list_has('OutlineColour', '&H00000000'),
                list_dump())
            record('pos-auto-sub-color', rgb('sub-color') == 'FFFFFF',
                'sub-color=' .. tostring(str('sub-color')))
            -- 视觉层：\pos 顶部字幕由灰转白（force 做不到，只有样式表覆盖能做到）
            record('pos-top-gray-turned-white',
                late ~= nil and early ~= nil and late.white > 100
                and late.gray < early.gray * 0.3,
                stat_text(early) .. ' → ' .. stat_text(late))

            -- 复现菜单点击：value 必须是带引号的 "#000000"，否则 mpv 吞掉参数 → reset
            menu('script-message-to uosc_subtitle_style color "#000000"')
            after(1.0, function()
                record('pos-black-sub-color', rgb('sub-color') == '000000',
                    'sub-color=' .. tostring(str('sub-color')))
                record('pos-black-primary-ass', list_has('PrimaryColour', '&H00000000'),
                    list_dump())
                blackened = top_stats()
                record('pos-black-top-not-white',
                    blackened ~= nil and late ~= nil
                    and blackened.white < late.white * 0.3,
                    stat_text(late) .. ' → ' .. stat_text(blackened))

                -- 字体：菜单 value 含空格，menu_cmd 不加引号（varargs 会拼回），
                -- 但 FontName 必须进入共享列表，\pos 字幕才会换字体
                menu('script-message-to uosc_subtitle_style font "Noto Serif CJK SC"')
                after(1.0, function()
                    record('pos-font-shared-list',
                        list_has('FontName', 'Noto Serif CJK SC'), list_dump())
                    record('pos-font-sub-font',
                        tostring(str('sub-font')) == 'Noto Serif CJK SC',
                        'sub-font=' .. tostring(str('sub-font')))
                    finish()
                end)
            end)
        end)
    end)
end)

print('PROBE driver(pos/gray) loaded, smoke dir: ' .. SMOKE_DIR)
