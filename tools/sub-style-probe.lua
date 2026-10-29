-- sub-style-probe.lua —— uosc_subtitle_style.lua 真机探针（不参与日常运行，仅测试用）
-- 加载方式：mpv --script=<本文件> ...（独立 VM，经 script-message 驱动 uosc_subtitle_style）
-- 输出：PROBE PASS/FAIL <用例> <细节> 逐条打印，最后汇总并退出。
-- 依赖环境变量 SUBSTYLE_SMOKE_DIR 指定截图输出目录（缺省用 TEMP）。

local SMOKE_DIR = os.getenv('SUBSTYLE_SMOKE_DIR') or (os.getenv('TEMP') or '.')
SMOKE_DIR = SMOKE_DIR:gsub('\\$', '')

local phase = 0
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

-- SKIP：运行环境不满足前置条件（而非被测代码缺陷）。独立仓库默认不带 uosc，
-- 字体选择器断言无法验证；E2E 以 SUBSTYLE_UOSC=1 声明「uosc 已加载」时，
-- 收不到 uosc-version 即为 FAIL（uosc 加载失败），不再容忍 SKIP。
local uosc_expected = os.getenv('SUBSTYLE_UOSC') == '1'
local uosc_seen = false
mp.register_script_message('uosc-version', function() uosc_seen = true end)

local function record_skip(name, detail)
    print(string.format('PROBE SKIP %s%s', name,
        detail and (' | ' .. tostring(detail)) or ''))
end

local function send(...)
    mp.commandv('script-message-to', 'uosc_subtitle_style', ...)
end

local function num(name)
    return mp.get_property_number(name, -1e9)
end

local function str(name)
    return mp.get_property(name)
end

local function after(sec, fn)
    mp.add_timeout(sec, function() fn() end)
end

-- 截图：每张前切换 screenshot-template（模板名别带 .png，mpv 会自动追加），
-- 并先清掉 show-text 的 OSD 提示——否则 flash 文字会与次字幕带混在一起
-- （实测 OSD 带 y56-78 与次字幕 tiny text y76-80 只差 2px，被波段分组合并）。
local function shoot(tag)
    mp.commandv('show-text', '')
    mp.set_property_native('screenshot-template', tag)
    mp.commandv('screenshot', 'subtitles+osd')
end

local function shot_saved(tag)
    local f = io.open(SMOKE_DIR .. '/' .. tag .. '.png', 'rb')
    local ok = f ~= nil
    if f then f:close() end
    return ok
end

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.command('quit')
end

--------------------------------------------------------------------
-- 流程：主/次分轨位置 → 分轨字体 → 分轨字号（含及时反馈计时）→ 状态 → 重置
--------------------------------------------------------------------

-- 前向声明（Lua 局部量作用域从声明之后才开始）
local step_main_pos, step_sec_pos, step_sec_font, step_sec_size, step_state, step_reset,
      step_overlap, step_outline

step_main_pos = function()
    send('pos', '50')
    after(0.6, function()
        record('main-pos-50', math.abs(num('sub-pos') - 50) < 0.01, 'sub-pos=' .. tostring(num('sub-pos')))
        shoot('main50')
        after(0.5, function()
            record('main50-shot', shot_saved('main50'))
            step_sec_pos()
        end)
    end)
end

step_sec_pos = function()
    send('target', 'sec')
    send('pos', '75')
    after(0.6, function()
        record('sec-target-switched', str('secondary-sub-pos') ~= nil)
        record('sec-pos-75', math.abs(num('secondary-sub-pos') - 75) < 0.01,
            'secondary-sub-pos=' .. tostring(num('secondary-sub-pos')))
        -- 分轨关键断言：主字幕位置不受次字幕操作影响
        record('main-pos-untouched', math.abs(num('sub-pos') - 50) < 0.01,
            'sub-pos=' .. tostring(num('sub-pos')))
        shoot('sec10')
        after(0.5, function()
            record('sec10-shot', shot_saved('sec10'))
            step_sec_font()
        end)
    end)
end

step_sec_font = function()
    -- 模拟在字体选择器里点选（多词字体名走 vararg 拼接）
    send('font', 'Noto', 'Serif', 'CJK', 'SC')
    after(0.6, function()
        record('sec-font-set', str('sub-font') == 'Noto Serif CJK SC',
            'sub-font=' .. tostring(str('sub-font')))
        -- 字体走 force ⇒ 次轨 override 变 force，主轨回基线 scale
        record('sec-override-force', str('secondary-sub-ass-override') == 'force',
            'secondary-sub-ass-override=' .. tostring(str('secondary-sub-ass-override')))
        record('main-override-baseline', str('sub-ass-override') == 'scale',
            'sub-ass-override=' .. tostring(str('sub-ass-override')))
        -- 列表不写 FontName（分轨关键）：只可有 Bold 管理键
        local v = mp.get_property_native('sub-ass-style-overrides') or {}
        local leaked
        for _, e in ipairs(v) do
            if e:match('^FontName=') then leaked = true end
        end
        record('font-not-leaked-to-shared-list', leaked == nil,
            'list=[' .. table.concat(v, ' | ') .. ']')
        shoot('secfont')
        after(0.5, function()
            record('secfont-shot', shot_saved('secfont'))
            step_sec_size()
        end)
    end)
end

step_sec_size = function()
    send('size', '24')
    -- 及时反馈标定：属性即时生效；画面的解码器重建有延迟，
    -- 在 +0.3s 与 +1.0s 各截一张，E2E 用后者做视觉断言（实测重建 <1s）。
    after(0.3, function()
        record('sec-size-24-prop', math.abs(num('sub-font-size') - 24) < 0.01,
            'sub-font-size=' .. tostring(num('sub-font-size')))
        shoot('secsize03')
        after(0.7, function()
            record('secsize03-shot', shot_saved('secsize03'))
            shoot('secsize')
            after(0.5, function()
                record('secsize-shot', shot_saved('secsize'))
                step_overlap()
            end)
        end)
    end)
end

-- 位置避让：目标轨设到与另一轨相同位置时，另一轨必须让位
step_overlap = function()
    send('target', 'main')
    send('pos', '75')     -- 次字幕此时也在 75
    after(0.6, function()
        local m, s = num('sub-pos'), num('secondary-sub-pos')
        record('overlap-target-kept', math.abs(m - 75) < 0.01, 'main=' .. tostring(m))
        record('overlap-other-pushed', math.abs(m - s) >= 25,
            string.format('main=%s sec=%s', tostring(m), tostring(s)))
        step_outline()
    end)
end

-- 描边粗细/颜色（作用于次字幕）
step_outline = function()
    send('target', 'sec')
    send('outline', '2')
    send('outline-color', '#FF0000')
    after(0.6, function()
        record('outline-size-set', math.abs(num('sub-outline-size') - 2) < 0.01,
            'sub-outline-size=' .. tostring(num('sub-outline-size')))
        local c = tostring(str('sub-outline-color') or ''):lower()
        record('outline-color-set', c:find('ff0000', 1, true) ~= nil,
            'sub-outline-color=' .. tostring(str('sub-outline-color')))
        step_state()
    end)
end

step_state = function()
    local path = mp.command_native({'expand-path', '~~/uosc-subtitle-style-state.json'})
    local f = path and io.open(path, 'rb')
    local content = f and f:read('*a')
    if f then f:close() end
    local ok = content ~= nil and content:find('"sec"', 1, true) ~= nil
        and content:find('"target"', 1, true) ~= nil
        and content:find('Noto Serif CJK SC', 1, true) ~= nil
        and content:find('outline', 1, true) ~= nil
    record('state-file-written', ok, content or '(nil)')
    step_reset()
end

step_reset = function()
    send('reset')
    after(0.8, function()
        -- 复位后主字幕 100（底部）、次字幕 0（顶部，mpv 原生默认）
        record('reset-restores-defaults',
            math.abs(num('sub-pos') - 100) < 0.01
            and math.abs(num('secondary-sub-pos') - 0) < 0.01
            and math.abs(num('sub-scale') - 1) < 0.001,
            'sub-pos=' .. tostring(num('sub-pos'))
            .. ' secondary-sub-pos=' .. tostring(num('secondary-sub-pos')))
        step_font_picker()
    end)
end

-- 字体选择器真机检查：懒加载枚举（含缓存）+ 菜单打开 + 重新扫描
-- ⚠ 首次 open-fonts 含**冷枚举**（扫 ~~/fonts 全部 sfnt/TTC，阻塞主线程），
-- 且 mpv 的 script-message-to 是异步入队派发：枚举超过 1.5s 时，探针的检查
-- 定时器会抢在 uosc 的 open-menu 消息之前触发，读到 menu/type=nil（误报）。
-- 因此首次等待放到 3.5s（覆盖冷枚举）；rescan 有热缓存，保持 1.5s。
-- 无 uosc 环境：三项断言整体 SKIP（菜单/枚举都走 uosc 路径），由 E2E 的
-- SUBSTYLE_UOSC=1 区分「允许跳过」与「必须通过」。
step_font_picker = function()
    local t0 = mp.get_time()
    -- uosc 应生效 = 探针收到广播 或 E2E 声明已加载；此时菜单/枚举未发生 = FAIL
    local uosc_on = uosc_seen or uosc_expected
    send('open-fonts')
    after(3.5, function()
        local mt = mp.get_property_native('user-data/uosc/menu/type')
        if mt ~= nil then
            record('font-picker-opens', tostring(mt) == 'uosc_subtitle_style_fonts',
                'menu/type=' .. tostring(mt) .. ' (+' .. string.format('%.2f', mp.get_time() - t0) .. 's)')
        elseif uosc_on then
            record('font-picker-opens', false,
                'uosc 已加载但菜单未打开（open-menu 路由断裂或 uosc 初始化失败）')
        else
            record_skip('font-picker-opens', '未检测到 uosc：设 UOSC_MAIN 环境变量可启用')
        end
        -- 从枚举结果里挑一款中文字体验证（读缓存文件）
        local path = mp.command_native({'expand-path', '~~/uosc-subtitle-style-fonts.json'})
        local f = path and io.open(path, 'rb')
        local content = f and f:read('*a')
        if f then f:close() end
        if uosc_on then
            record('font-cache-enumerated', content ~= nil
                and content:find('"cjk"', 1, true) ~= nil
                and content:find('Noto', 1, true) ~= nil,
                content and ('len=' .. #content) or '(nil)')
        else
            record_skip('font-cache-enumerated',
                content and ('len=' .. #content) or '(nil)：枚举由 uosc 菜单触发，无 uosc 不执行')
        end
        send('rescan-fonts')
        after(1.5, function()
            local mt2 = mp.get_property_native('user-data/uosc/menu/type')
            if mt2 ~= nil then
                record('font-picker-rescan', tostring(mt2) == 'uosc_subtitle_style_fonts',
                    'menu/type=' .. tostring(mt2))
            elseif uosc_on then
                record('font-picker-rescan', false, 'uosc 已加载但重扫菜单未打开')
            else
                record_skip('font-picker-rescan', '未检测到 uosc')
            end
            finish()
        end)
    end)
end

--------------------------------------------------------------------
-- 入口：等第一个文件加载完成
--------------------------------------------------------------------

mp.register_event('file-loaded', function()
    if phase == 0 then
        phase = 1
        after(1.0, function()
            shoot('base')
            after(0.5, function()
                record('base-shot', shot_saved('base'))
                -- 基线：保留 mpv 自己的默认——主 100（底部）、次 0（顶部）。
                -- 脚本绝不能把次字幕从顶部拽走（用户报障的正是这一点）。
                record('baseline-keeps-mpv-defaults',
                    math.abs(num('sub-pos') - 100) < 0.01
                    and math.abs(num('secondary-sub-pos') - 0) < 0.01,
                    'sub-pos=' .. tostring(num('sub-pos'))
                    .. ' secondary-sub-pos=' .. tostring(num('secondary-sub-pos')))
                step_main_pos()
            end)
        end)
    end
end)

print('PROBE driver loaded, smoke dir: ' .. SMOKE_DIR)
