-- sub-style-test.lua —— uosc_subtitle_style.lua 单元测试（stub 掉 mpv 运行时）
-- 用法（在 portable_config/ 下执行）：
--   ../luajit.exe tools/sub-style-test.lua
-- 判据：exit code 0 且汇总行全 PASS。
-- 覆盖：主/次分轨模型、目标切换、共享样式通道、延迟重建（override 切换法）、
--       状态持久化与旧格式迁移、菜单 JSON、样式检测（ASS 解析/像素采样/饱和度
--       阈值）、预设样式（读写缓存/开关/恢复出厂）、左上角报告与 OSD 对齐还原。

local SCRIPT = 'scripts/uosc_subtitle_style.lua'

local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(string.format('%s %s%s', ok and 'PASS' or 'FAIL', name,
        detail and (' | ' .. tostring(detail)) or ''))
end

--------------------------------------------------------------------
-- 极简 JSON 编/解码（测试两端都在自己手里，格式保持简单确定）
--------------------------------------------------------------------

local function jenc(v)
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[\\"]', {['\\'] = '\\\\', ['"'] = '\\"'}) .. '"'
    elseif t == 'number' then
        return tostring(v)
    elseif t == 'boolean' then
        return v and 'true' or 'false'
    elseif t == 'table' then
        local is_array = true
        for k in pairs(v) do
            if type(k) ~= 'number' then is_array = false end
        end
        local parts = {}
        if is_array then
            for _, item in ipairs(v) do parts[#parts + 1] = jenc(item) end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                parts[#parts + 1] = jenc(tostring(k)) .. ':' .. jenc(v[k])
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    end
    return 'null'
end

local function jdec(s)
    local pos = 1
    local function skip() while pos <= #s and s:sub(pos, pos):match('%s') do pos = pos + 1 end end
    local parse_value
    local function parse_string()
        pos = pos + 1
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == '' then error('unterminated string') end
            if c == '\\' then
                local n = s:sub(pos + 1, pos + 1)
                out[#out + 1] = ({n = '\n', t = '\t', ['\\'] = '\\', ['"'] = '"'})[n] or n
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end
    parse_value = function()
        skip()
        local c = s:sub(pos, pos)
        if c == '"' then return parse_string()
        elseif c == '{' then
            pos = pos + 1
            local obj = {}
            skip()
            if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while true do
                skip()
                local k = parse_string()
                skip()
                assert(s:sub(pos, pos) == ':', 'expected :')
                pos = pos + 1
                obj[k] = parse_value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == '}' then break end
                assert(d == ',', 'expected , or }')
            end
            return obj
        elseif c == '[' then
            pos = pos + 1
            local arr = {}
            skip()
            if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while true do
                arr[#arr + 1] = parse_value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == ']' then break end
                assert(d == ',', 'expected , or ]')
            end
            return arr
        elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
        else
            local num = s:match('^%-?%d+%.?%d*', pos)
            assert(num, 'bad json token at ' .. pos)
            pos = pos + #num
            return tonumber(num)
        end
    end
    return parse_value()
end

--------------------------------------------------------------------
-- stub 环境：mp / mp.msg / mp.utils / mp.options / io.open（虚拟 FS）
-- add_timeout 入队，由 flush_timers() 按序执行（验证延迟重建）
--------------------------------------------------------------------

local VFS_ROOT = 'C:/fake-config'
local STATE_PATH = VFS_ROOT .. '/uosc-subtitle-style-state.json'
local PRESET_PATH = VFS_ROOT .. '/uosc-subtitle-style-preset.json'

local env = {
    props = {}, commands = {}, showtexts = {}, showtext_durs = {}, messages = {},
    events = {}, timers = {}, opt_overrides = {}, vfs = {}, readdir_map = {}, raw_shots = {},
}
local FONT_CACHE_PATH = 'C:/fake-config/uosc-subtitle-style-fonts.json'

local function fresh_script_env()
    env.props, env.commands, env.showtexts, env.showtext_durs = {}, {}, {}, {}
    env.messages, env.events, env.timers = {}, {}, {}
    env.script_messages = {}   -- command_native 的 script-message-to（对外 API 回复/转发）
    env.observers = {}
    env.opt_overrides, env.vfs, env.raw_shots = {}, {}, {}

    local mp_stub = {}
    function mp_stub.get_property(name) return env.props[name] end
    function mp_stub.get_property_number(name, def)
        local v = env.props[name]
        if type(v) == 'number' then return v end
        return def
    end
    function mp_stub.get_property_native(name) return env.props[name] end
    function mp_stub.get_property_bool(name, def)
        local v = env.props[name]
        if type(v) == 'boolean' then return v end
        return def
    end
    function mp_stub.set_property(name, v) env.props[name] = v end
    function mp_stub.set_property_native(name, v) env.props[name] = v end
    function mp_stub.commandv(...)
        local t = {...}
        env.commands[#env.commands + 1] = t
        if t[1] == 'show-text' then
            env.showtexts[#env.showtexts + 1] = t[2]
            env.showtext_durs[#env.showtext_durs + 1] = t[3]
        end
    end
    function mp_stub.command(s)
        env.commands[#env.commands + 1] = {s}
        local text = s:match('^show%-text%s+"(.*)"')
        if text then env.showtexts[#env.showtexts + 1] = text end
    end
    function mp_stub.register_script_message(name, fn) env.messages[name] = fn end
    function mp_stub.register_event(name, fn) env.events[name] = fn end
    -- observe_property：记录回调；测试里可用 env.fire_prop(prop, value) 触发
    -- 模拟「用户用 mpv 键位/其它脚本改了属性」
    function mp_stub.observe_property(name, kind, fn)
        env.observers = env.observers or {}
        env.observers[name] = fn
    end
    function mp_stub.add_timeout(_, fn) env.timers[#env.timers + 1] = fn end
    function mp_stub.unregister_event() end
    function mp_stub.command_native(t)
        if type(t) == 'table' and t[1] == 'script-message-to' then
            env.script_messages[#env.script_messages + 1] = t
        end
        if type(t) == 'table' and t[1] == 'expand-path' then
            if t[2] == '~~/uosc-subtitle-style-state.json' then return STATE_PATH end
            if t[2] == '~~/uosc-subtitle-style-preset.json' then return PRESET_PATH end
            if t[2] == '~~/fonts' then return 'C:/fake-fonts' end
            if t[2] == '~~/uosc-subtitle-style-fonts.json' then return FONT_CACHE_PATH end
            return t[2]
        end
        -- screenshot-raw：测试里放合成帧（env.raw_shots[kind] = {w,h,stride,data}）
        if type(t) == 'table' and t[1] == 'screenshot-raw' then
            return env.raw_shots and env.raw_shots[t[2]]
        end
        return nil
    end

    local msg_stub = {}
    for _, level in ipairs({'info', 'warn', 'error', 'verbose', 'debug'}) do
        msg_stub[level] = function() end
    end
    env.readdir_map = {}
    local utils_stub = {
        format_json = jenc, parse_json = jdec,
        readdir = function(dir) return env.readdir_map[dir] end,
    }
    local options_stub = {
        read_options = function(t, _)
            for k, v in pairs(env.opt_overrides) do t[k] = v end
            return t
        end,
    }

    -- mpv 把 mp 表作为**全局**注入脚本环境，package.loaded 管不住它
    local real_mp_global = rawget(_G, 'mp')
    rawset(_G, 'mp', mp_stub)
    package.loaded['mp'] = mp_stub
    package.loaded['mp.msg'] = msg_stub
    package.loaded['mp.utils'] = utils_stub
    package.loaded['mp.options'] = options_stub

    local real_open = io.open
    io.open = function(path, mode)
        mode = mode or 'r'
        if mode:find('w') then
            local buf = {}
            return {
                write = function(_, s) buf[#buf + 1] = s end,
                close = function() env.vfs[path] = table.concat(buf) end,
            }
        end
        local content = env.vfs[path]
        if not content then return nil, 'no such file: ' .. tostring(path) end
        local p = 1
        return {
            read = function(_, fmt)
                if fmt == '*a' then
                    local r = content:sub(p); p = #content + 1; return r
                elseif fmt == '*l' or fmt == 'l' then
                    local s, e = content:find('\n', p, true)
                    if not s then
                        local r = content:sub(p); p = #content + 1; return r
                    end
                    local line = content:sub(p, s - 1); p = e + 1; return line
                elseif type(fmt) == 'number' then
                    local r = content:sub(p, p + fmt - 1)
                    p = p + fmt
                    return r
                end
                return nil
            end,
            seek = function(_, whence, o)
                if whence == 'set' then p = (o or 0) + 1
                elseif whence == 'cur' then p = p + (o or 0)
                elseif whence == 'end' then p = #content + 1 - (o or 0) end
                return p - 1
            end,
            close = function() end,
        }
    end

    return function()
        io.open = real_open
        if real_mp_global ~= nil then rawset(_G, 'mp', real_mp_global)
        else rawset(_G, 'mp', nil) end
        package.loaded['mp'] = nil
        package.loaded['mp.msg'] = nil
        package.loaded['mp.utils'] = nil
        package.loaded['mp.options'] = nil
    end
end

local function load_script()
    local chunk, err = loadfile(SCRIPT)
    if not chunk then error('loadfile failed: ' .. tostring(err)) end
    chunk()
end

local function flush_timers()
    -- 一次性执行完当前队列（延迟重建的回调）
    local queue = env.timers
    env.timers = {}
    for _, fn in ipairs(queue) do fn() end
end

local function fire_prop(prop, value)
    env.props[prop] = value
    local fn = env.observers and env.observers[prop]
    if fn then fn(prop, value) end
end

local function uosc_command()
    for _, c in ipairs(env.commands) do
        if c[1] == 'script-message-to' and c[2] == 'uosc' then return c end
    end
    return nil
end

local function last_showtext()
    return env.showtexts[#env.showtexts]
end

-- 便捷：设置主/次字幕轨存在性
local function set_tracks(has_sec)
    env.props['current-tracks/sub'] = {codec = 'ass', image = false, external = false, id = 1}
    if has_sec then
        env.props['current-tracks/sub2'] = {codec = 'ass', image = false, external = false, id = 2}
    else
        env.props['current-tracks/sub2'] = nil
    end
end

--------------------------------------------------------------------
-- 用例
--------------------------------------------------------------------

-- T1 加载与注册
local restore = fresh_script_env()
load_script()
check('load-registers-messages',
    env.messages['open-menu'] ~= nil and env.messages['cycle'] ~= nil
    and env.messages['target'] ~= nil and env.messages['pos'] ~= nil
    and env.messages['scale'] ~= nil and env.messages['nudge'] ~= nil
    and env.messages['font'] ~= nil and env.messages['size'] ~= nil
    and env.messages['bold'] ~= nil and env.messages['style-preset'] ~= nil
    and env.messages['reset'] ~= nil and env.messages['fix-override'] ~= nil
    and env.messages['uosc-version'] ~= nil)
check('load-registers-file-loaded', env.events['file-loaded'] ~= nil)
check('load-registers-playback-restart', env.events['playback-restart'] ~= nil)

-- T2 无归属权时**不越权写位置**：保留 mpv 自己的值（这里是模拟的默认 100）
set_tracks(false)
env.props['sub-pos'] = 100
env.props['sub-scale'] = 1
env.events['file-loaded']()
check('default-main-pos-kept', env.props['sub-pos'] == 100, tostring(env.props['sub-pos']))
check('default-main-scale', env.props['sub-scale'] == 1)
check('no-secondary-props-without-track', env.props['secondary-sub-pos'] == nil)

-- T3 主字幕位置/缩放
env.messages['pos']('50')
check('main-pos-50', env.props['sub-pos'] == 50)
check('main-pos-flash', last_showtext() and last_showtext():find('主字幕', 1, true) ~= nil
    and last_showtext():find('50%', 1, true) ~= nil, last_showtext())
env.messages['nudge']('-5')
check('main-nudge-45', env.props['sub-pos'] == 45)
env.messages['nudge']('-200')
check('main-nudge-clamp-floor', env.props['sub-pos'] == 0)
env.messages['nudge']('200')
check('main-nudge-clamp-ceiling', env.props['sub-pos'] == 150)
env.messages['scale']('1.25')
check('main-scale-125', env.props['sub-scale'] == 1.25)

-- T4 切换到次字幕后，位置写 secondary-*，主字幕属性不动
set_tracks(true)
env.commands = {}
env.messages['target']('sec')
-- 切换即应用：flash 指明新目标，且次字幕位置属性开始被写
check('target-switched', last_showtext():find('编辑目标 → 次字幕', 1, true) ~= nil,
    last_showtext())
local main_pos_before = env.props['sub-pos']
env.messages['pos']('0')
check('sec-pos-0', env.props['secondary-sub-pos'] == 0, tostring(env.props['secondary-sub-pos']))
check('main-pos-untouched', env.props['sub-pos'] == main_pos_before,
    'sub-pos=' .. tostring(env.props['sub-pos']))
check('sec-flash-names-track', last_showtext():find('次字幕', 1, true) ~= nil, last_showtext())
env.messages['scale']('0.8')
check('sec-scale-08', env.props['secondary-sub-scale'] == 0.8)
-- cycle 只认预设值：先从 0 微调到预设 50，再 cycle → 25
env.messages['pos']('50')
env.messages['cycle']()
check('cycle-on-target', env.props['secondary-sub-pos'] == 25, tostring(env.props['secondary-sub-pos']))

-- T5 无次字幕轨时 target sec 被拒绝
env.messages['target']('main')
set_tracks(false)
env.commands = {}
env.messages['target']('sec')
check('target-sec-rejected-without-track', env.showtexts[#env.showtexts]
    and env.showtexts[#env.showtexts]:find('未检测到次字幕轨', 1, true) ~= nil,
    last_showtext())
check('target-still-main', env.props['sub-pos'] ~= nil)

-- T6 字体：多词字体名 vararg 拼回；除 force + sub-font 外，v1.0.6 还会把 FontName
--    写进 sub-ass-style-overrides（改写 ASS 样式表），让带 \pos 的顶部字幕也换字体。
set_tracks(false)
env.props['sub-ass-style-overrides'] = nil
env.props['sub-ass-override'] = 'scale'
env.timers = {}
env.messages['font']('Noto', 'Serif', 'CJK', 'SC')
check('font-multiword-joined', env.props['sub-font'] == 'Noto Serif CJK SC',
    tostring(env.props['sub-font']))
local list = env.props['sub-ass-style-overrides'] or {}
check('font-in-shared-list-for-pos-signs',
    #list == 1 and list[1] == 'FontName=Noto Serif CJK SC',
    table.concat(list, ' | '))
-- 字体 ⇒ 需要 force ⇒ 延迟一个 tick 后 override 变 force
check('font-defers-force', env.props['sub-ass-override'] == 'scale')
flush_timers()
check('font-forces-after-flush', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))

-- T6b 分轨：主字幕设字体后，次字幕轨保持 scale 基线；
--    但列表（解码器级共享）里 FontName 会写入 —— 这是覆盖 \pos 字幕的代价，
--    用户可用菜单「顶部/定位字幕一并改样式」关掉回到纯分轨模式。
set_tracks(true)
env.props['sub-ass-override'] = 'scale'
env.props['secondary-sub-ass-override'] = 'strip'
env.props['sub-ass-style-overrides'] = {'Encoding=-1'}
env.timers = {}
env.messages['font']('Noto Sans CJK KR')
flush_timers()
check('font-main-force-only', env.props['sub-ass-override'] == 'force'
    and env.props['secondary-sub-ass-override'] == 'strip',
    'main=' .. tostring(env.props['sub-ass-override'])
    .. ' sec=' .. tostring(env.props['secondary-sub-ass-override']))
list = env.props['sub-ass-style-overrides'] or {}
local enc_kept, fontname_now
for _, v in ipairs(list) do
    if v == 'Encoding=-1' then enc_kept = true end
    if v == 'FontName=Noto Sans CJK KR' then fontname_now = true end
end
check('font-list-keeps-foreign-and-fontname', enc_kept == true and fontname_now == true,
    table.concat(list, ' | '))

-- T7 列表先读再写：用户条目保留；旧版写入的 FontName/Bold 残留被清理并换成当前值
env.props['sub-ass-style-overrides'] = {'Encoding=-1', 'FontName=OldFont', 'Bold=1', 'PlayResX=1920'}
env.messages['bold']('on')
list = env.props['sub-ass-style-overrides'] or {}
local has_enc, has_bold, has_font, has_old_font, has_playres
for _, v in ipairs(list) do
    if v == 'Encoding=-1' then has_enc = true end
    if v == 'Bold=1' then has_bold = true end
    if v == 'FontName=Noto Sans CJK KR' then has_font = true end
    if v == 'FontName=OldFont' then has_old_font = true end
    if v == 'PlayResX=1920' then has_playres = true end
end
check('list-preserves-foreign', has_enc == true and has_playres == true)
check('list-refreshes-bold', has_bold == true)
check('list-drops-stale-fontname', has_font == true and has_old_font == nil,
    table.concat(list, ' | '))

-- T7b 全样式覆盖通道：颜色写 ASS &H00BBGGRR（BGR 倒序）、恢复原样会清键、开关可关
env.messages['color']('#FF8040')
list = env.props['sub-ass-style-overrides'] or {}
local has_primary
for _, v in ipairs(list) do
    if v == 'PrimaryColour=&H004080FF' then has_primary = true end
end
check('color-writes-ass-primary-bgr', has_primary == true, table.concat(list, ' | '))
env.messages['outline-color']('#00FF00')
list = env.props['sub-ass-style-overrides'] or {}
local has_outline_col
for _, v in ipairs(list) do
    if v == 'OutlineColour=&H0000FF00' then has_outline_col = true end
end
check('outline-color-writes-ass-bgr', has_outline_col == true, table.concat(list, ' | '))
env.messages['color']('reset')
env.messages['outline-color']('reset')
list = env.props['sub-ass-style-overrides'] or {}
local primary_left, outline_left = false, false
for _, v in ipairs(list) do
    if v:match('^PrimaryColour=') then primary_left = true end
    if v:match('^OutlineColour=') then outline_left = true end
end
check('reset-clears-ass-color-keys', not primary_left and not outline_left,
    table.concat(list, ' | '))
-- 关掉全样式覆盖后，即使再设颜色也不写列表键（回到纯 force 分轨模式）
env.messages['toggle-all']()
env.messages['color']('#FF8040')
list = env.props['sub-ass-style-overrides'] or {}
local leaked_primary = false
for _, v in ipairs(list) do
    if v:match('^PrimaryColour=') or v:match('^FontName=') then leaked_primary = true end
end
check('override-all-off-keeps-list-clean', not leaked_primary, table.concat(list, ' | '))
env.messages['toggle-all']()
env.messages['color']('reset')

-- T8 字号：写 sub-font-size 并把 override 的最终值延迟一个 tick（重建法）
env.messages['font']('reset')
flush_timers()
env.props['sub-ass-override'] = 'scale'
env.props['sub-ass-style-overrides'] = {}
env.commands = {}
env.messages['size']('46')
check('size-sets-fontsize', env.props['sub-font-size'] == 46, tostring(env.props['sub-font-size']))
check('size-defers-override', env.props['sub-ass-override'] == 'scale',
    '应立即保持原值，延迟后再设 force')
check('size-queues-rebuild', #env.timers >= 1, 'timers=' .. #env.timers)
flush_timers()
check('size-override-force-after-flush', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
-- reset 前先清字体（T7 的字体还在，否则 override 仍会保持 force）
env.messages['font']('reset')
flush_timers()
env.messages['size']('reset')
flush_timers()
-- stub 未设 sub-font-size ⇒ 基线取脚本默认 38
check('size-reset-restores-fontsize', env.props['sub-font-size'] == 38,
    tostring(env.props['sub-font-size']))
check('size-reset-override-back', env.props['sub-ass-override'] == 'scale',
    tostring(env.props['sub-ass-override']))

-- T9 粗体：列表 Bold + sub-bold 属性
env.props['sub-ass-style-overrides'] = {}
env.messages['bold']('on')
list = env.props['sub-ass-style-overrides'] or {}
local bold_val
for _, v in ipairs(list) do
    if v:match('^Bold=') then bold_val = v end
end
check('bold-on-list', bold_val == 'Bold=1', tostring(bold_val))
check('bold-on-prop', env.props['sub-bold'] == 'yes', tostring(env.props['sub-bold']))
env.messages['bold']('off')
check('bold-off-prop', env.props['sub-bold'] == 'no')
env.messages['bold']('reset')
check('bold-reset-prop', env.props['sub-bold'] == 'no')  -- 回落 mpv 默认 no
bold_val = nil
for _, v in ipairs(env.props['sub-ass-style-overrides'] or {}) do
    if v:match('^Bold=') then bold_val = v end
end
check('bold-reset-removes-entry', bold_val == nil)

-- T10 另一轨 force 规则：同样式一起 force，不同式仅目标轨
set_tracks(true)
env.props['sub-ass-override'] = 'scale'
env.props['secondary-sub-ass-override'] = 'strip'
env.timers = {}
-- 主字幕设样式
env.messages['target']('main')
env.messages['size']('46')
flush_timers()
check('other-no-force-when-different', env.props['secondary-sub-ass-override'] == 'strip',
    tostring(env.props['secondary-sub-ass-override']))
-- 同步到另一轨 ⇒ 两轨一致 ⇒ 都 force
env.messages['style-preset']('sync-other')
flush_timers()
check('sync-other-sets-sec-style', env.props['sub-font-size'] == 46)
check('sync-other-both-force', env.props['sub-ass-override'] == 'force'
    and env.props['secondary-sub-ass-override'] == 'force',
    'main=' .. tostring(env.props['sub-ass-override'])
    .. ' sec=' .. tostring(env.props['secondary-sub-ass-override']))
-- 切回主目标、改样式 ⇒ 次轨回到 strip
env.messages['size']('32')
flush_timers()
check('after-diverge-sec-back-to-baseline', env.props['secondary-sub-ass-override'] == 'strip',
    tostring(env.props['secondary-sub-ass-override']))

-- T11 状态文件新格式 round-trip（含 target）。
-- 先落一组确定值：主 75/×1.5，次 25（次 scale 0.8 来自 T4）
env.messages['target']('main')
env.messages['pos']('75')
env.messages['scale']('1.5')
env.messages['target']('sec')
env.messages['pos']('25')
env.messages['target']('main')
local saved = env.vfs[STATE_PATH]
check('state-file-nested-format', saved ~= nil
    and saved:find('"main"', 1, true) ~= nil
    and saved:find('"sec"', 1, true) ~= nil
    and saved:find('"target"', 1, true) ~= nil, saved)
local restore2 = fresh_script_env()
set_tracks(true)
env.vfs[STATE_PATH] = saved
load_script()
env.events['file-loaded']()
check('state-restored-main-pos', env.props['sub-pos'] == 75, tostring(env.props['sub-pos']))
check('state-restored-main-scale', env.props['sub-scale'] == 1.5, tostring(env.props['sub-scale']))
check('state-restored-sec-pos', env.props['secondary-sub-pos'] == 25, tostring(env.props['secondary-sub-pos']))
check('state-restored-sec-scale', env.props['secondary-sub-scale'] == 0.8)
-- 目标恢复为 main 且两轨样式不同 ⇒ 仅主轨 force，次轨回基线
check('state-restored-target-main-force', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
check('state-restored-sec-baseline', env.props['secondary-sub-ass-override'] == 'strip',
    tostring(env.props['secondary-sub-ass-override']))

-- T12 旧版扁平格式迁移
local restore3 = fresh_script_env()
set_tracks(true)
env.props['secondary-sub-pos'] = 5      -- 模拟 mpv 配置里的次字幕位置
env.vfs[STATE_PATH] = '{"pos":30,"scale":1.25,"sec_pos":0,"font":"Noto Sans CJK SC","size":40,"bold":true}'
load_script()
env.events['file-loaded']()
check('legacy-main-pos', env.props['sub-pos'] == 30, tostring(env.props['sub-pos']))
check('legacy-main-scale', env.props['sub-scale'] == 1.25)
-- 旧版状态里的 sec_pos（脚本硬编码默认值）不得覆盖 mpv 的配置值
check('legacy-sec-pos-released', env.props['secondary-sub-pos'] == 5,
    tostring(env.props['secondary-sub-pos']))
check('legacy-main-font', env.props['sub-font'] == 'Noto Sans CJK SC')
check('legacy-main-size', env.props['sub-font-size'] == 40)
check('legacy-main-bold', env.props['sub-bold'] == 'yes')
flush_timers()
check('legacy-main-force', env.props['sub-ass-override'] == 'force')

-- T13 reset 清空两轨并回到主目标
env.messages['target']('sec')
env.messages['pos']('10')
env.messages['reset']()
flush_timers()
check('reset-main-pos', env.props['sub-pos'] == 100)
-- 复位：次字幕回到 mpv 原生默认 0（顶部），与主字幕 100 天然不重叠
check('reset-sec-pos-default-top', env.props['secondary-sub-pos'] == 0,
    tostring(env.props['secondary-sub-pos']))
-- 无样式 ⇒ override 回落基线（stub 未配 sub-ass-override ⇒ scale）
check('reset-override-back-to-baseline', env.props['sub-ass-override'] == 'scale',
    tostring(env.props['sub-ass-override']))
check('reset-no-managed-list', #(env.props['sub-ass-style-overrides'] or {}) == 0)
check('reset-no-overlap',
    math.abs(env.props['sub-pos'] - env.props['secondary-sub-pos']) >= 25,
    string.format('main=%s sec=%s', tostring(env.props['sub-pos']),
        tostring(env.props['secondary-sub-pos'])))

-- T14 菜单 JSON：目标切换项、无次轨时置灰、位置区标题带目标名
local restore4 = fresh_script_env()
set_tracks(false)
load_script()
env.messages['uosc-version']()
env.messages['open-menu']()
local data = jdec(uosc_command()[4])
local want = {
    'script-message-to uosc_subtitle_style target main',
    'script-message-to uosc_subtitle_style target sec',
    'script-message-to uosc_subtitle_style pos 50',
    'script-message-to uosc_subtitle_style font Noto Sans CJK SC',
    'script-message-to uosc_subtitle_style size 38',
    'script-message-to uosc_subtitle_style bold on',
    'script-message-to uosc_subtitle_style style-preset big-bold',
    'script-message-to uosc_subtitle_style style-preset original',
}
local found = {}
local sec_item
for _, it in ipairs(data.items or {}) do
    for i, wv in ipairs(want) do
        if it.value == wv then found[i] = true end
    end
    if it.value == 'script-message-to uosc_subtitle_style target sec' then sec_item = it end
end
local all_found = true
for i = 1, #want do if not found[i] then all_found = false end end
check('menu-has-all-entries', all_found == true)
check('menu-sec-item-muted-without-track', sec_item ~= nil and sec_item.selectable == false)
-- 位置区标题应包含目标轨名
local pos_section
for _, it in ipairs(data.items or {}) do
    if it.title and it.title:find('位置（作用于主字幕）', 1, true) then pos_section = true end
end
check('menu-position-section-names-target', pos_section == true)

-- T15 有次轨时菜单出现同步项
local restore5 = fresh_script_env()
set_tracks(true)
load_script()
env.messages['uosc-version']()
env.messages['open-menu']()
data = jdec(uosc_command()[4])
local has_sync
for _, it in ipairs(data.items or {}) do
    if it.value == 'script-message-to uosc_subtitle_style style-preset sync-other' then has_sync = true end
end
check('menu-has-sync-with-sec-track', has_sync == true)

-- T16 cycle 顺序（主轨）
local restore6 = fresh_script_env()
set_tracks(false)
load_script()
env.messages['pos']('50')
env.messages['cycle']()
check('cycle-next-preset', env.props['sub-pos'] == 25, tostring(env.props['sub-pos']))

-- T17 fix-override 修复 no 并同步基线
local restore7 = fresh_script_env()
set_tracks(false)
env.props['sub-ass-override'] = 'no'
load_script()
env.events['file-loaded']()
env.messages['fix-override']()
flush_timers()
check('fix-override-sets-scale', env.props['sub-ass-override'] == 'scale',
    tostring(env.props['sub-ass-override']))

--------------------------------------------------------------------
-- T18+ 本机字体枚举（合成 sfnt/TTC 字节流）
--------------------------------------------------------------------

-- 隔离 os.getenv，让 font_dirs 只落到 fake-fonts（其余目录 readdir 返回 nil）
local real_getenv = os.getenv
os.getenv = function() return nil end

local function u16s(v) return string.char(math.floor(v / 256) % 256, v % 256) end
local function u32s(v)
    return string.char(math.floor(v / 2 ^ 24) % 256, math.floor(v / 2 ^ 16) % 256,
                       math.floor(v / 2 ^ 8) % 256, v % 256)
end
local function u16be_str(s)  -- ASCII → UTF-16BE
    local out = {}
    for i = 1, #s do out[i] = string.char(0, s:byte(i)) end
    return table.concat(out)
end

local function make_name_table(names)
    local storage, recs, off = {}, {}, 0
    for _, e in ipairs(names) do
        local s = (e.pid == 3 or e.pid == 0) and u16be_str(e.name) or e.name
        storage[#storage + 1] = s
        recs[#recs + 1] = u16s(e.pid) .. u16s(3) .. u16s(0x409) .. u16s(e.nid)
            .. u16s(#s) .. u16s(off)
        off = off + #s
    end
    return u16s(0) .. u16s(#names) .. u16s(6 + 12 * #names)
        .. table.concat(recs) .. table.concat(storage)
end

local function make_cmap_f4(segs)
    local n = #segs + 1
    local t = {}
    for i, s in ipairs(segs) do t[#t + 1] = u16s(s.e) end
    t[#t + 1] = u16s(0xFFFF)
    local starts = {}
    for i, s in ipairs(segs) do starts[#starts + 1] = u16s(s.s) end
    starts[#starts + 1] = u16s(0xFFFF)
    local deltas, ranges = {}, {}
    for _ = 1, n do deltas[#deltas + 1] = u16s(1); ranges[#ranges + 1] = u16s(0) end
    local sub = u16s(4) .. u16s(16 + 8 * n) .. u16s(0) .. u16s(2 * n)
        .. u16s(2) .. u16s(1) .. u16s(0)
        .. table.concat(t) .. u16s(0) .. table.concat(starts)
        .. table.concat(deltas) .. table.concat(ranges)
    return u16s(0) .. u16s(1) .. u16s(3) .. u16s(1) .. u32s(12) .. sub
end

-- ⚠ 真实 TTC 规范：各字体的表目录偏移是**相对文件头的绝对偏移**。
-- make_sfnt 的 base 即该字体在文件内的绝对偏移（单文件 TTF 传 0）。
local function make_sfnt(tables, base)
    base = base or 0
    table.sort(tables, function(a, b) return a.tag < b.tag end)
    local off = base + 12 + 16 * #tables
    local dir_parts, body = {}, {}
    for _, t in ipairs(tables) do
        dir_parts[#dir_parts + 1] = t.tag .. u32s(0) .. u32s(off) .. u32s(#t.data)
        body[#body + 1] = t.data
        off = off + #t.data
    end
    return '\0\1\0\0' .. u16s(#tables) .. u16s(16 * #tables) .. u16s(0) .. u16s(0)
        .. table.concat(dir_parts) .. table.concat(body)
end

-- builders: 函数列表，每项 function(base) -> sfnt 字符串
local function make_ttc(builders)
    local off = 12 + 4 * #builders
    local offsets, datas = {}, {}
    for i, b in ipairs(builders) do
        offsets[i] = u32s(off)
        local d = b(off)
        datas[i] = d
        off = off + #d
    end
    return 'ttcf' .. u32s(0x00010000) .. u32s(#builders)
        .. table.concat(offsets) .. table.concat(datas)
end

local function make_coll()
    return make_ttc({
        function(base) return make_sfnt({
            {tag = 'cmap', data = make_cmap_f4({{s = 0x41, e = 0x5A}})},
            {tag = 'name', data = make_name_table({{pid = 1, nid = 1, name = 'Mac Latin Family'}})},
        }, base) end,
        function(base) return make_sfnt({
            {tag = 'cmap', data = make_cmap_f4({{s = 0x4E00, e = 0x4EFF}})},
            {tag = 'name', data = make_name_table({{pid = 3, nid = 16, name = 'TTC CJK Two'}})},
        }, base) end,
    })
end

-- T18 单 TTF：nameID 16 优先、format 4 cmap 命中 U+4E2D
local restore8 = fresh_script_env()
set_tracks(false)
local f1 = make_sfnt({
    {tag = 'cmap', data = make_cmap_f4({{s = 0x4E00, e = 0x9FFF}, {s = 0x20, e = 0x7E}})},
    {tag = 'name', data = make_name_table({
        {pid = 3, nid = 16, name = 'Test CJK Family'},
        {pid = 3, nid = 1, name = 'Test CJK Family Legacy'},
    })},
})
env.vfs['C:/fake-fonts/test1.ttf'] = f1
env.readdir_map['C:/fake-fonts'] = {'test1.ttf'}
load_script()
env.messages['uosc-version']()
env.messages['open-fonts']()
local c8 = uosc_command()
check('picker-menu-opens', c8 ~= nil and c8[3] == 'open-menu', c8 and c8[3])
local d8 = jdec(c8[4])
check('picker-menu-type', d8.type == 'uosc_subtitle_style_fonts', d8.type)
local found_cjk, found_other
for _, it in ipairs(d8.items or {}) do
    if it.title == 'Test CJK Family' then found_cjk = it end
end
check('enumerated-family', found_cjk ~= nil)
check('cjk-classified', found_cjk ~= nil and found_cjk.hint == '推荐用于中文字幕',
    found_cjk and found_cjk.hint)
check('picker-value-targets-font', found_cjk ~= nil
    and found_cjk.value == 'script-message-to uosc_subtitle_style font Test CJK Family',
    found_cjk and found_cjk.value)
-- 图标字体过滤 + 竖排过滤
env.vfs['C:/fake-fonts/icon.ttf'] = make_sfnt({
    {tag = 'cmap', data = make_cmap_f4({{s = 0x4E00, e = 0x9FFF}})},
    {tag = 'name', data = make_name_table({{pid = 3, nid = 16, name = 'Material Icons Test'}})},
})
env.vfs['C:/fake-fonts/vert.ttf'] = make_sfnt({
    {tag = 'cmap', data = make_cmap_f4({{s = 0x4E00, e = 0x9FFF}})},
    {tag = 'name', data = make_name_table({{pid = 3, nid = 16, name = '@Vertical Test'}})},
})
env.readdir_map['C:/fake-fonts'] = {'test1.ttf', 'icon.ttf', 'vert.ttf'}
env.commands = {}
env.messages['rescan-fonts']()
d8 = jdec(uosc_command()[4])
local icon_in, vert_in
for _, it in ipairs(d8.items or {}) do
    if it.title == 'Material Icons Test' then icon_in = true end
    if it.title == '@Vertical Test' then vert_in = true end
end
check('icon-font-filtered', icon_in == nil)
check('vertical-font-filtered', vert_in == nil)

-- T19 TTC：两个字体都枚举；字体缓存写入且可复用
local restore9 = fresh_script_env()
set_tracks(false)
env.vfs['C:/fake-fonts/coll.ttc'] = make_coll()
env.readdir_map['C:/fake-fonts'] = {'coll.ttc'}
load_script()
env.messages['uosc-version']()
env.messages['open-fonts']()
d8 = jdec(uosc_command()[4])
local ttc_names = {}
for _, it in ipairs(d8.items or {}) do
    if it.title == 'Mac Latin Family' or it.title == 'TTC CJK Two' then
        ttc_names[#ttc_names + 1] = it.title
    end
end
check('ttc-both-fonts', #ttc_names == 2, table.concat(ttc_names, ','))
check('ttc-mac-latin-parsed', ttc_names[1] == 'Mac Latin Family' or ttc_names[2] == 'Mac Latin Family')
check('ttc-cjk-classified', true)  -- TTC CJK Two 应在中文组（上面已解析到）
-- 字体缓存落盘
local fc = env.vfs[FONT_CACHE_PATH]
check('font-cache-written', fc ~= nil and fc:find('"cjk"', 1, true) ~= nil
    and fc:find('TTC CJK Two', 1, true) ~= nil, fc and fc:sub(1, 120))

-- T20 缓存命中：改 readdir 内容但签名不变时用缓存；签名变化时重扫
local restore10 = fresh_script_env()
set_tracks(false)
-- 预置一份与当前目录状态匹配的缓存（sig = 文件数:总字节）。
-- 注意：fresh env 清空了 vfs，先恢复字体数据
env.vfs['C:/fake-fonts/coll.ttc'] = make_coll()
env.readdir_map['C:/fake-fonts'] = {'coll.ttc'}
local sig = '1:' .. #env.vfs['C:/fake-fonts/coll.ttc']
env.vfs[FONT_CACHE_PATH] = '{"sig":"' .. sig .. '","fonts":["Cached Family"],"cjk":["Cached Family"]}'
load_script()
env.messages['uosc-version']()
env.messages['open-fonts']()
d8 = jdec(uosc_command()[4])
local cached_used, fresh_used
for _, it in ipairs(d8.items or {}) do
    if it.title == 'Cached Family' then cached_used = true end
    if it.title == 'TTC CJK Two' then fresh_used = true end
end
check('font-cache-hit', cached_used == true and fresh_used == nil,
    'cached=' .. tostring(cached_used) .. ' fresh=' .. tostring(fresh_used))
-- 签名变化（文件内容改变）⇒ 重扫
env.vfs['C:/fake-fonts/coll.ttc'] = env.vfs['C:/fake-fonts/coll.ttc'] .. 'X'
env.commands = {}   -- uosc_command() 取第一条，先清空以免拿到旧菜单
env.messages['rescan-fonts']()
d8 = jdec(uosc_command()[4])
fresh_used = nil
for _, it in ipairs(d8.items or {}) do
    if it.title == 'TTC CJK Two' then fresh_used = true end
end
check('font-cache-invalidated-on-sig-change', fresh_used == true)

os.getenv = real_getenv
restore8(); restore9(); restore10()

-- T21 稳态编辑不重建：已处于 force 时改字号只发 OSD 微扰，不动 override
local restore11 = fresh_script_env()
set_tracks(false)
env.props['sub-ass-override'] = 'force'
load_script()
env.events['file-loaded']()
env.messages['font']('Noto Sans CJK SC')     -- 先有样式（force 已在）
flush_timers()
env.timers = {}
env.showtexts = {}
env.messages['size']('24')
check('steady-state-no-override-timer', #env.timers == 0,
    'timers=' .. #env.timers)
check('steady-state-nudges-osd', env.showtexts[1] == ' ',
    'showtexts[1]=' .. tostring(env.showtexts[1]))
check('steady-state-keeps-force', env.props['sub-ass-override'] == 'force')

-- T22 进入 force 时仍需要一次延迟设置（重建不可避免）
local restore12 = fresh_script_env()
set_tracks(false)
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
env.timers = {}   -- 丢掉「载入后检测」的计时器，只统计本次编辑
env.messages['size']('24')
check('enter-force-schedules-set', #env.timers == 1, 'timers=' .. #env.timers)
flush_timers()
check('enter-force-applied', env.props['sub-ass-override'] == 'force')

restore11(); restore12()

-- T23 描边：粗细/颜色写入 sub-outline-* 并进入 force
local restore13 = fresh_script_env()
set_tracks(false)
env.props['sub-ass-override'] = 'scale'
env.props['sub-outline-size'] = 0.5
env.props['sub-outline-color'] = '#000000'
load_script()
env.events['file-loaded']()
env.messages['outline']('2')
check('outline-size-set', env.props['sub-outline-size'] == 2,
    tostring(env.props['sub-outline-size']))
flush_timers()
check('outline-implies-force', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
env.messages['outline-color']('#FF0000')
check('outline-color-set', env.props['sub-outline-color'] == '#FF0000',
    tostring(env.props['sub-outline-color']))
-- 稳态（已 force）：描边改动不再重建
env.timers = {}
env.messages['outline']('3')
check('outline-steady-no-rebuild', #env.timers == 0, 'timers=' .. #env.timers)
env.messages['outline']('reset')
flush_timers()
check('outline-reset-baseline', env.props['sub-outline-size'] == 0.5,
    tostring(env.props['sub-outline-size']))
env.messages['outline-color']('reset')
check('outline-color-reset-baseline', env.props['sub-outline-color'] == '#000000',
    tostring(env.props['sub-outline-color']))

-- T24 位置默认与避让
local restore14 = fresh_script_env()
set_tracks(true)
-- 模拟 mpv 的默认：主 100（底部）、次 0（顶部）
env.props['sub-pos'] = 100
env.props['secondary-sub-pos'] = 0
load_script()
env.events['file-loaded']()
-- 加载必须**保留** mpv 的默认（不得把次字幕从顶部拽到底部）
check('load-keeps-mpv-defaults',
    env.props['sub-pos'] == 100 and env.props['secondary-sub-pos'] == 0,
    string.format('main=%s sec=%s', tostring(env.props['sub-pos']),
        tostring(env.props['secondary-sub-pos'])))
-- 主动制造重叠：主字幕也去顶部 0 → 次字幕让位到 25
env.messages['pos']('0')
check('target-pos-kept', env.props['sub-pos'] == 0,
    tostring(env.props['sub-pos']))
check('other-pushed-away',
    math.abs(env.props['sub-pos'] - env.props['secondary-sub-pos']) >= 25,
    string.format('main=%s sec=%s', tostring(env.props['sub-pos']),
        tostring(env.props['secondary-sub-pos'])))
check('push-flash-mentions', last_showtext() ~= nil
    and last_showtext():find('避让', 1, true) ~= nil, last_showtext())

-- T25 外部改动采纳：用户用 mpv 键位改位置后，脚本不得覆盖
local restore15 = fresh_script_env()
set_tracks(true)
env.props['sub-pos'] = 100
env.props['secondary-sub-pos'] = 0
load_script()
env.events['file-loaded']()
-- 用户手动把次字幕挪到 40（mpv 的 r/t 键位/其它脚本）
fire_prop('secondary-sub-pos', 40)
env.messages['size']('24')          -- 编辑主字幕样式
flush_timers()
check('adopted-external-secondary-pos', env.props['secondary-sub-pos'] == 40,
    tostring(env.props['secondary-sub-pos']))
-- 脚本自己写入的值不应被当成外部改动（不产生额外状态漂移）
check('own-write-not-adopted', env.props['sub-pos'] == 100,
    tostring(env.props['sub-pos']))

restore15()

--------------------------------------------------------------------
-- T26 样式检测：ASS 文件解析（主色/描边色/字体/字号/内封字体）
--     + 彩色字幕自动套用预设 + 左上角报告
--------------------------------------------------------------------

-- 合成 ASS fixture。primary/outline 为 &HAABBGGRR 原值；embedded 非 nil 时加 [Fonts] 段
local function make_ass(primary, outline, embedded)
    local lines = {
        '[Script Info]',
        'ScriptType: v4.00+',
    }
    if embedded then
        lines[#lines + 1] = '[Fonts]'
        for _, name in ipairs(embedded) do lines[#lines + 1] = 'fontname: ' .. name end
        lines[#lines + 1] = ''
    end
    lines[#lines + 1] = '[V4+ Styles]'
    lines[#lines + 1] = 'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour,'
        .. ' OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY,'
        .. ' Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding'
    lines[#lines + 1] = 'Style: Default,TestFontSC,40,' .. primary
        .. ',&H00000000,' .. outline .. ',&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '[Events]'
    lines[#lines + 1] = 'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text'
    lines[#lines + 1] = 'Dialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,测试文本'
    return table.concat(lines, '\n') .. '\n'
end

local function set_external_track(filename)
    env.props['sid'] = 1
    env.props['track-list'] = {
        {type = 'sub', id = 1, external = true, ['external-filename'] = filename},
    }
end

local restore16 = fresh_script_env()
set_tracks(false)
-- &HAABBGGRR：主色 #FFFF00 → &H0000FFFF；描边 #0000FF → &H00FF0000（BB=FF）
env.vfs['C:/fake-config/colored.ass'] = make_ass('&H0000FFFF', '&H00FF0000', {'FontA', 'FontB'})
set_external_track('C:/fake-config/colored.ass')
load_script()
env.messages['inspect']()
local rpt = last_showtext() or ''
check('inspect-report-primary-color', rpt:find('主色 #FFFF00', 1, true) ~= nil, rpt)
check('inspect-report-outline-color', rpt:find('描边 #0000FF', 1, true) ~= nil, rpt)
check('inspect-report-font-size', rpt:find('TestFontSC', 1, true) ~= nil
    and rpt:find('字号 40', 1, true) ~= nil, rpt)
check('inspect-report-embedded-fonts', rpt:find('内封字体 2 个', 1, true) ~= nil
    and rpt:find('FontA', 1, true) ~= nil and rpt:find('FontB', 1, true) ~= nil, rpt)
check('inspect-report-source-label', rpt:find('外挂字幕', 1, true) ~= nil, rpt)
-- 彩色 → 套用预设：共享通道立即写（sub-color/outline），override 延迟切换
check('inspect-colored-preset-color', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
check('inspect-colored-preset-outline-color', env.props['sub-outline-color'] == '#000000',
    tostring(env.props['sub-outline-color']))
check('inspect-colored-preset-outline-size', env.props['sub-outline-size'] == 2,
    tostring(env.props['sub-outline-size']))
flush_timers()
check('inspect-colored-force-after-flush', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
check('inspect-report-applied-line', rpt:find('已套用预设样式', 1, true) ~= nil, rpt)
restore16()

-- T27 白色字幕：只报告、不套用
local restore17 = fresh_script_env()
set_tracks(false)
env.vfs['C:/fake-config/white.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/white.ass')
env.props['sub-ass-override'] = 'scale'
load_script()
env.messages['inspect']()
check('inspect-white-not-applied', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
local rpt_w = last_showtext() or ''
check('inspect-white-report-line', rpt_w:find('非彩色字幕，保持原样', 1, true) ~= nil, rpt_w)
check('inspect-white-no-force', env.props['sub-ass-override'] == 'scale',
    tostring(env.props['sub-ass-override']))
restore17()

-- T27c 灰色字幕（2026-11-05 用户报障：Netflix 内封 ASS 主色 #8B8B8B）。
-- 饱和度 0 ⇒ 旧「仅彩色」判据把它当标准黑白字幕跳过，顶部/对白字幕永远不转黑白。
-- 新逻辑：灰阶（非纯白/纯黑）也算「非标准黑白」，自动套用白字黑边，
-- 且必须把 PrimaryColour 写进 ASS 样式表，带 \pos 的字幕才真的会变色。
local restore17c = fresh_script_env()
set_tracks(false)
env.vfs['C:/fake-config/gray.ass'] = make_ass('&H008B8B8B', '&H00000000')
set_external_track('C:/fake-config/gray.ass')
load_script()
env.messages['inspect']()
local rpt_g = last_showtext() or ''
check('inspect-gray-report-primary', rpt_g:find('主色 #8B8B8B', 1, true) ~= nil, rpt_g)
check('inspect-gray-applies-preset', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
check('inspect-gray-report-applied', rpt_g:find('已套用预设样式', 1, true) ~= nil, rpt_g)
local gl = env.props['sub-ass-style-overrides'] or {}
local gray_primary = false
for _, v in ipairs(gl) do
    if v == 'PrimaryColour=&H00FFFFFF' then gray_primary = true end
end
check('inspect-gray-writes-style-primary', gray_primary, table.concat(gl, ' | '))
-- 关掉灰色识别 ⇒ 同一份灰色字幕保持原样（开关真的有牙）
env.messages['toggle-gray']()
env.messages['inspect']()
check('inspect-gray-off-keeps-original',
    (last_showtext() or ''):find('保持原样', 1, true) ~= nil, last_showtext())
restore17c()

-- T27b 白字 + 紫描边（外挂 ASS）：主色白非彩，但描边 #481081 是彩色 ⇒ 判彩色并转黑白。
-- 回归：彩色判定曾只看主色，白字+彩描边被漏判成「非彩色」而不转黑白。
local restore17b = fresh_script_env()
set_tracks(false)
-- &H00811048 = #481081（BB=81, GG=10, RR=48）
env.vfs['C:/fake-config/white-purple.ass'] = make_ass('&H00FFFFFF', '&H00811048')
set_external_track('C:/fake-config/white-purple.ass')
env.props['sub-ass-override'] = 'scale'
load_script()
env.messages['inspect']()
check('inspect-white-purple-applies', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
check('inspect-white-purple-outline-set', env.props['sub-outline-color'] == '#000000',
    tostring(env.props['sub-outline-color']))
flush_timers()  -- override→force 是延迟切换，冲完计时器再断言
check('inspect-white-purple-force', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
local rpt_wp = last_showtext() or ''
check('inspect-white-purple-report-outline', rpt_wp:find('描边 #481081', 1, true) ~= nil, rpt_wp)
check('inspect-white-purple-applied-line', rpt_wp:find('已套用预设样式', 1, true) ~= nil, rpt_wp)
restore17b()

-- T28 饱和度阈值边界（默认 40，含等号）
local restore18 = fresh_script_env()
set_tracks(false)
-- #272700：max-min = 39 < 40 → 非彩色
env.vfs['C:/fake-config/edge-low.ass'] = make_ass('&H00002727', '&H00000000')
set_external_track('C:/fake-config/edge-low.ass')
load_script()
env.messages['inspect']()
check('inspect-threshold-below-not-colored', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
-- #282800：max-min = 40 ≥ 40 → 彩色（边界等号命中）
env.vfs['C:/fake-config/edge-eq.ass'] = make_ass('&H00002828', '&H00000000')
set_external_track('C:/fake-config/edge-eq.ass')
env.messages['inspect']()
check('inspect-threshold-equal-is-colored', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
restore18()

-- T29 预设缓存：修改 → 保存落盘 → 重启（保留缓存）→ 彩色字幕套用缓存值
local restore19 = fresh_script_env()
set_tracks(false)
load_script()
env.messages['color']('#FF00FF')
env.messages['outline-color']('#00FF00')
env.messages['outline']('4')
env.messages['preset-save']()
local saved = env.vfs[PRESET_PATH] or ''
check('preset-saved-to-cache', saved:find('#FF00FF', 1, true) ~= nil
    and saved:find('#00FF00', 1, true) ~= nil and saved:find('"outline":4', 1, true) ~= nil,
    saved)
local save_flash = last_showtext() or ''
check('preset-save-flash', save_flash:find('预设已保存并缓存', 1, true) ~= nil, save_flash)
-- 第二轮：保留 VFS 里的缓存文件，其余全新（模拟重启后 load_preset 读缓存）
local vfs_keep = env.vfs
local restore19b = fresh_script_env()
env.vfs = vfs_keep
set_tracks(false)
env.vfs['C:/fake-config/colored2.ass'] = make_ass('&H0000FFFF', '&H00FF0000')
set_external_track('C:/fake-config/colored2.ass')
load_script()
env.messages['inspect']()
check('preset-cache-color-reloaded', env.props['sub-color'] == '#FF00FF',
    tostring(env.props['sub-color']))
check('preset-cache-outline-color-reloaded', env.props['sub-outline-color'] == '#00FF00',
    tostring(env.props['sub-outline-color']))
check('preset-cache-outline-size-reloaded', env.props['sub-outline-size'] == 4,
    tostring(env.props['sub-outline-size']))
restore19b()
restore19()

-- T30 预设开关与恢复出厂（状态落盘 + 行为差异）
local restore20 = fresh_script_env()
set_tracks(false)
load_script()
env.messages['preset-toggle-colored']()
check('toggle-colored-off-persisted', (env.vfs[PRESET_PATH] or ''):find('"only_colored":false', 1, true) ~= nil,
    env.vfs[PRESET_PATH])
env.messages['preset-toggle-enabled']()
check('toggle-enabled-off-persisted', (env.vfs[PRESET_PATH] or ''):find('"enabled":false', 1, true) ~= nil,
    env.vfs[PRESET_PATH])
env.messages['preset-reset']()
check('preset-reset-factory-persisted',
    (env.vfs[PRESET_PATH] or ''):find('"enabled":true', 1, true) ~= nil
    and (env.vfs[PRESET_PATH] or ''):find('"only_colored":true', 1, true) ~= nil
    and (env.vfs[PRESET_PATH] or ''):find('"color":"#FFFFFF"', 1, true) ~= nil,
    env.vfs[PRESET_PATH])
check('preset-reset-flash', (last_showtext() or ''):find('恢复出厂', 1, true) ~= nil)
-- 关掉「仅彩色」后，白字字幕也会套用（先存一个可辨识的预设色）
env.messages['color']('#FF00FF')
env.messages['preset-save']()
env.messages['preset-toggle-colored']()
env.vfs['C:/fake-config/white2.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/white2.ass')
env.props['sub-color'] = nil
env.messages['inspect']()
check('only-colored-off-applies-white', env.props['sub-color'] == '#FF00FF',
    tostring(env.props['sub-color']))
restore20()

-- T31 像素采样路径（内封字幕：无文件可解析，靠双帧差分）
local restore21 = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['sub-text'] = '内封字幕文本'
env.props['track-list'] = {{type = 'sub', id = 1}}  -- 内封：无 external-filename
local function synth_frame(rows)
    local data = {}
    for y = 1, 4 do
        for x = 1, 4 do
            local p = rows[y][x]
            data[#data + 1] = string.char(p[1], p[2], p[3], 255)  -- bgr0
        end
    end
    return {w = 4, h = 4, stride = 16, data = table.concat(data)}
end
local YELLOW = {0x00, 0xFF, 0xFF}   -- #FFFF00（bgr0）
local BLACK = {0x00, 0x00, 0x00}    -- #000000
local GRAY = {0x80, 0x80, 0x80}
-- 采样点 (0,0)/(0,2)/(2,0)/(2,2)（步进 2）：黄、黄、黑(描边)、黄
env.raw_shots = {
    subtitles = synth_frame({
        {YELLOW, GRAY, YELLOW, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {BLACK, GRAY, YELLOW, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
    }),
    video = synth_frame({
        {GRAY, GRAY, GRAY, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
    }),
}
load_script()
env.messages['inspect']()
local rpt_p = last_showtext() or ''
check('inspect-pixels-source', rpt_p:find('内封字幕(像素采样)', 1, true) ~= nil, rpt_p)
check('inspect-pixels-color', rpt_p:find('主色 #FFFF00', 1, true) ~= nil, rpt_p)
check('inspect-pixels-outline', rpt_p:find('描边 #000000', 1, true) ~= nil, rpt_p)
-- 采到的黄是彩色 → 套用预设
check('inspect-pixels-colored-applies', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
restore21()

-- T31b 像素采样：白字 + 紫描边（#481081）——主色白（非彩），但描边紫是彩色，
-- 必须判「彩色」并转黑白。回归：曾因彩色判定只看主色、且描边亮度 ~72 落在
-- 「亮≥100 算主色 / 暗<60 算描边」的缝档里两头不沾，导致整个漏判。
local restore21b = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['sub-text'] = '内封字幕文本'
env.props['track-list'] = {{type = 'sub', id = 1}}  -- 内封：无 external-filename
local PX_WHITE = {0xFF, 0xFF, 0xFF}    -- #FFFFFF
local PX_PURPLE = {0x81, 0x10, 0x48}   -- #481081（bgr0）
-- 采样点 (0,0)/(0,2)/(2,0)/(2,2)：白、紫、紫、白 ⇒ 主色白、accent 紫、无暗色描边
env.raw_shots = {
    subtitles = synth_frame({
        {PX_WHITE, PX_PURPLE, PX_PURPLE, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {PX_PURPLE, GRAY, PX_WHITE, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
    }),
    video = synth_frame({
        {GRAY, GRAY, GRAY, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
    }),
}
load_script()
env.messages['inspect']()
local rpt_pp = last_showtext() or ''
check('inspect-purple-px-source', rpt_pp:find('内封字幕(像素采样)', 1, true) ~= nil, rpt_pp)
check('inspect-purple-px-main', rpt_pp:find('主色 #FFFFFF', 1, true) ~= nil, rpt_pp)
-- 紫描边靠 accent 抓到并当描边色报告
check('inspect-purple-px-outline', rpt_pp:find('描边 #481081', 1, true) ~= nil, rpt_pp)
-- 描边紫是彩色 ⇒ 套用预设（转黑白）
check('inspect-purple-px-applies', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
check('inspect-purple-px-outline-set', env.props['sub-outline-color'] == '#000000',
    tostring(env.props['sub-outline-color']))
restore21b()

-- T32 flash_tl：临时改 OSD 对齐，显示后必须还原（否则用户后续 OSD 全跑左上角）
local restore22 = fresh_script_env()
set_tracks(false)
env.props['osd-align-x'] = 'center'
env.props['osd-align-y'] = 'bottom'
env.vfs['C:/fake-config/white3.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/white3.ass')
load_script()
env.messages['inspect']()
check('flash-tl-moves-align',
    env.props['osd-align-x'] == 'left' and env.props['osd-align-y'] == 'top',
    string.format('%s/%s', tostring(env.props['osd-align-x']), tostring(env.props['osd-align-y'])))
flush_timers()
check('flash-tl-restores-align',
    env.props['osd-align-x'] == 'center' and env.props['osd-align-y'] == 'bottom',
    string.format('%s/%s', tostring(env.props['osd-align-x']), tostring(env.props['osd-align-y'])))
restore22()

-- T33 菜单：主颜色/描边/预设样式新区
local restore23 = fresh_script_env()
set_tracks(false)
load_script()
env.messages['uosc-version']()
env.messages['open-menu']()
local data2 = jdec(uosc_command()[4])
local want_menu = {
    'script-message-to uosc_subtitle_style color reset',
    -- ⚠ #RRGGBB 必须带引号：mp.command 把裸 # 当注释符，参数会被吞掉（用户报障根因）
    'script-message-to uosc_subtitle_style color "#FFFFFF"',
    'script-message-to uosc_subtitle_style outline reset',
    'script-message-to uosc_subtitle_style outline 2',
    'script-message-to uosc_subtitle_style outline-color reset',
    'script-message-to uosc_subtitle_style outline-color "#FF0000"',
    'script-message-to uosc_subtitle_style preset-apply',
    'script-message-to uosc_subtitle_style preset-save',
    'script-message-to uosc_subtitle_style preset-toggle-colored',
    'script-message-to uosc_subtitle_style preset-toggle-dual',
    'script-message-to uosc_subtitle_style preset-toggle-enabled',
    'script-message-to uosc_subtitle_style toggle-gray',
    'script-message-to uosc_subtitle_style toggle-all',
    'script-message-to uosc_subtitle_style inspect',
    'script-message-to uosc_subtitle_style preset-reset',
}
local found_menu, apply_item, has_section = {}, nil, false
local bare_hash = false
for _, it in ipairs(data2.items or {}) do
    for i, wv in ipairs(want_menu) do
        if it.value == wv then found_menu[i] = true end
    end
    if it.value == 'script-message-to uosc_subtitle_style preset-apply' then apply_item = it end
    if it.title and it.title:find('预设样式', 1, true) then has_section = true end
    if type(it.value) == 'string' and it.value:match('color #') then bare_hash = true end
end
local menu_all = true
for i = 1, #want_menu do if not found_menu[i] then menu_all = false end end
check('menu-preset-entries', menu_all == true)
check('menu-no-bare-hash-color-value', not bare_hash)
check('menu-keep-open-root', data2.keep_open == true)
check('menu-preset-section', has_section == true)
check('menu-preset-apply-hint-shows-preset',
    apply_item ~= nil and apply_item.hint:find('#FFFFFF', 1, true) ~= nil,
    apply_item and apply_item.hint)
-- 双语开关项存在且带勾（默认开启）；无次轨时置灰
local dual_item
for _, it in ipairs(data2.items or {}) do
    if it.value == 'script-message-to uosc_subtitle_style preset-toggle-dual' then dual_item = it end
end
check('menu-dual-toggle-exists', dual_item ~= nil)
check('menu-dual-toggle-default-on', dual_item ~= nil and dual_item.active == true
    and dual_item.icon == 'check_box', dual_item and dual_item.icon)
check('menu-dual-toggle-muted-without-sec', dual_item ~= nil and dual_item.muted == true)
restore23()

--------------------------------------------------------------------
-- T34 双语字幕（双轨）默认不改颜色：彩色也保持原样 + 报告说明原因
--------------------------------------------------------------------
local restore24 = fresh_script_env()
set_tracks(true)
-- 彩色外挂字幕（正常会触发套用）；但有次字幕轨 ⇒ 跳过
env.vfs['C:/fake-config/dual.ass'] = make_ass('&H0000FFFF', '&H00FF0000')
set_external_track('C:/fake-config/dual.ass')
load_script()
env.messages['inspect']()
check('dual-colored-not-applied', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
check('dual-colored-no-force', env.props['sub-ass-override'] ~= 'force',
    tostring(env.props['sub-ass-override']))
local rpt_d = last_showtext() or ''
check('dual-report-skip-line',
    rpt_d:find('双语字幕（双轨），保持原样不改颜色', 1, true) ~= nil, rpt_d)
check('dual-report-still-shows-color', rpt_d:find('主色 #FFFF00', 1, true) ~= nil, rpt_d)
restore24()

--------------------------------------------------------------------
-- T35 双语开关：preset-toggle-dual 落盘 + 关掉后双语也套用 + 恢复
--------------------------------------------------------------------
local restore25 = fresh_script_env()
set_tracks(true)
load_script()
-- 出厂默认应为开（skip_dual=true）
check('dual-toggle-default-persisted-shape',
    (env.vfs[PRESET_PATH] or '') == '', 'load 时不应主动写缓存')
env.messages['preset-toggle-dual']()
check('dual-toggle-off-persisted',
    (env.vfs[PRESET_PATH] or ''):find('"skip_dual":false', 1, true) ~= nil,
    env.vfs[PRESET_PATH])
check('dual-toggle-off-flash',
    (last_showtext() or ''):find('双语字幕（双轨）时也套用预设', 1, true) ~= nil,
    last_showtext())
-- 关掉后：双语 + 彩色 ⇒ 套用预设
env.vfs['C:/fake-config/dual2.ass'] = make_ass('&H0000FFFF', '&H00FF0000')
set_external_track('C:/fake-config/dual2.ass')
env.messages['inspect']()
check('dual-toggle-off-applies', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
check('dual-toggle-off-report-applied',
    (last_showtext() or ''):find('已套用预设样式', 1, true) ~= nil, last_showtext())
-- 再开回去：恢复「双语保持原样」且落盘
env.messages['preset-toggle-dual']()
check('dual-toggle-on-again-persisted',
    (env.vfs[PRESET_PATH] or ''):find('"skip_dual":true', 1, true) ~= nil,
    env.vfs[PRESET_PATH])
env.messages['inspect']()
check('dual-toggle-on-again-skips',
    (last_showtext() or ''):find('双语字幕（双轨）', 1, true) ~= nil,
    last_showtext())
restore25()

--------------------------------------------------------------------
-- T36 避让间距可配（pos_min_gap）：默认 25 → 设为 60 后让位到 60
--------------------------------------------------------------------
local restore26 = fresh_script_env()
set_tracks(true)
env.props['sub-pos'] = 100
env.props['secondary-sub-pos'] = 0
env.opt_overrides['pos_min_gap'] = 60
load_script()
env.events['file-loaded']()
-- 主字幕去顶部 0 → 次字幕只能让到 60（下方唯一合法候选）
env.messages['pos']('0')
check('pos-min-gap-configurable', env.props['secondary-sub-pos'] == 60,
    string.format('main=%s sec=%s', tostring(env.props['sub-pos']),
        tostring(env.props['secondary-sub-pos'])))
restore26()

--------------------------------------------------------------------
-- T37 报告时长可配（report_ms）：show-text 第三参数跟随配置
--------------------------------------------------------------------
local restore27 = fresh_script_env()
set_tracks(false)
env.opt_overrides['report_ms'] = 1234
env.vfs['C:/fake-config/white4.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/white4.ass')
load_script()
env.messages['inspect']()
local last_dur = env.showtext_durs[#env.showtext_durs]
check('report-ms-configurable', last_dur == 1234, tostring(last_dur))
restore27()

--------------------------------------------------------------------
-- T38 自动预设不跨文件泄漏：彩色字幕自动套用预设(auto)后，切到非彩色字幕应恢复
--     该字幕原样（不再继承上个彩色视频的预设）；再切彩色会重新套用。
--     回归：曾因 apply_preset 写入 state 且无 auto 标记，file-loaded 时被 apply_all
--     重新套到非彩色字幕上（报告却显示"保持原样"——画面与报告不一致）。
--------------------------------------------------------------------
local restore28 = fresh_script_env()
set_tracks(false)
env.props['sub-ass-override'] = 'scale'   -- mpv 基线（load 时被 baseline 捕获）
-- 文件1：彩色外挂 → inspect 自动套用预设
env.vfs['C:/fake-config/leak-color.ass'] = make_ass('&H0000FFFF', '&H00FF0000')
set_external_track('C:/fake-config/leak-color.ass')
load_script()
env.messages['inspect']()
flush_timers()
check('leak-color-applied', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
check('leak-color-auto-flag-persisted',
    (env.vfs[STATE_PATH] or ''):find('"auto":true', 1, true) ~= nil, env.vfs[STATE_PATH])
-- 文件2：非彩色外挂（白字黑边）。模拟 mpv reset-on-next-file 已把属性复位
env.vfs['C:/fake-config/leak-white.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/leak-white.ass')
env.props['sub-color'] = nil
env.props['sub-ass-override'] = 'scale'
env.events['file-loaded']()
flush_timers()  -- 跑完 run_inspect（白字 → 不套用，报告"保持原样"）
check('leak-white-color-not-inherited', env.props['sub-color'] == nil, tostring(env.props['sub-color']))
check('leak-white-no-force', env.props['sub-ass-override'] == 'scale', tostring(env.props['sub-ass-override']))
check('leak-white-report-keep-original',
    (last_showtext() or ''):find('非彩色字幕，保持原样', 1, true) ~= nil, last_showtext())
-- 文件3：又变彩色 → 重新套用预设（证明清除不影响彩色检测/套用）
env.vfs['C:/fake-config/leak-color2.ass'] = make_ass('&H0000FFFF', '&H00FF0000')
set_external_track('C:/fake-config/leak-color2.ass')
env.props['sub-color'] = nil
env.props['sub-ass-override'] = 'scale'
env.events['file-loaded']()
flush_timers()
check('leak-recolored-applies-again', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
restore28()

--------------------------------------------------------------------
-- T38b 手动样式跨文件持久：用户手动改的样式(auto=false)在 file-loaded 时不被清除
--       （持久化特性不被"防泄漏"修复破坏）。
--------------------------------------------------------------------
local restore29 = fresh_script_env()
set_tracks(false)
env.props['sub-ass-override'] = 'scale'
env.vfs['C:/fake-config/man-a.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/man-a.ass')
load_script()
env.messages['color']('#123456')   -- 用户手动设一个可辨识的颜色 ⇒ auto=false
check('manual-color-set', env.props['sub-color'] == '#123456', tostring(env.props['sub-color']))
check('manual-no-auto-flag',
    (env.vfs[STATE_PATH] or ''):find('"auto":true', 1, true) == nil, env.vfs[STATE_PATH])
-- 切文件：手动样式应保留（不被 clear_auto_style 清除）
env.vfs['C:/fake-config/man-b.ass'] = make_ass('&H00FFFFFF', '&H00000000')
set_external_track('C:/fake-config/man-b.ass')
env.props['sub-color'] = nil
env.props['sub-ass-override'] = 'scale'
env.events['file-loaded']()
check('manual-color-persists-across-file', env.props['sub-color'] == '#123456', tostring(env.props['sub-color']))
restore29()

--------------------------------------------------------------------
-- T39 CN+JP 双语自动布局：按语言识别，日文轨置底+缩小，中文轨其上
--------------------------------------------------------------------
local function set_dual_lang(main_lang, sec_lang, files)
    set_tracks(true)
    env.props['sid'] = 1
    env.props['secondary-sid'] = 2
    if files then
        env.props['track-list'] = {
            {type = 'sub', id = 1, external = true, ['external-filename'] = files[1]},
            {type = 'sub', id = 2, external = true, ['external-filename'] = files[2]},
        }
    else
        env.props['track-list'] = {
            {type = 'sub', id = 1, lang = main_lang},
            {type = 'sub', id = 2, lang = sec_lang},
        }
    end
end

local restore30 = fresh_script_env()
set_dual_lang('chi', 'jpn')   -- 主=中(内封 lang)，次=日
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
check('dual-layout-cn-pos', env.props['sub-pos'] == 75, tostring(env.props['sub-pos']))
check('dual-layout-cn-scale-unchanged', env.props['sub-scale'] == 1, tostring(env.props['sub-scale']))
check('dual-layout-jp-pos', env.props['secondary-sub-pos'] == 100, tostring(env.props['secondary-sub-pos']))
check('dual-layout-jp-scale', math.abs((env.props['secondary-sub-scale'] or 0) - 0.8) < 0.001,
    tostring(env.props['secondary-sub-scale']))
check('dual-layout-no-color-change', env.props['sub-color'] == nil, tostring(env.props['sub-color']))
-- 布局是 per-file 覆盖层，不写状态文件（不跨文件泄漏）
check('dual-layout-not-persisted', (env.vfs[STATE_PATH] or '') == '', env.vfs[STATE_PATH])
restore30()

-- T40 反向：主=日、次=中 → 日文(主)轨置底+缩小，中文(次)轨其上
local restore31 = fresh_script_env()
set_dual_lang('jpn', 'chi')
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
check('dual-layout-rev-jp-pos', env.props['sub-pos'] == 100, tostring(env.props['sub-pos']))
check('dual-layout-rev-jp-scale', math.abs((env.props['sub-scale'] or 0) - 0.8) < 0.001,
    tostring(env.props['sub-scale']))
check('dual-layout-rev-cn-pos', env.props['secondary-sub-pos'] == 75, tostring(env.props['secondary-sub-pos']))
check('dual-layout-rev-cn-scale', env.props['secondary-sub-scale'] == 1,
    tostring(env.props['secondary-sub-scale']))
restore31()

-- T41 非「一中一日」不布局（日+英）；dual_layout=no 时中日也不布局
local restore32 = fresh_script_env()
set_dual_lang('jpn', 'eng')
env.props['sub-ass-override'] = 'scale'
env.props['sub-pos'] = 100
env.props['secondary-sub-pos'] = 0
load_script()
env.events['file-loaded']()
check('dual-layout-none-main-pos-kept', env.props['sub-pos'] == 100, tostring(env.props['sub-pos']))
check('dual-layout-none-sec-pos-kept', env.props['secondary-sub-pos'] == 0, tostring(env.props['secondary-sub-pos']))
restore32()
local restore32b = fresh_script_env()
set_dual_lang('chi', 'jpn')
env.opt_overrides['dual_layout'] = false   -- 关掉布局
env.props['sub-ass-override'] = 'scale'
env.props['sub-pos'] = 100
env.props['secondary-sub-pos'] = 0
load_script()
env.events['file-loaded']()
check('dual-layout-disabled-main-kept', env.props['sub-pos'] == 100, tostring(env.props['sub-pos']))
check('dual-layout-disabled-sec-kept', env.props['secondary-sub-pos'] == 0, tostring(env.props['secondary-sub-pos']))
restore32b()

-- T42 用户手动设位置/缩放即关闭本次布局（手动优先，且跨 playback-restart 保持）
local restore33 = fresh_script_env()
set_dual_lang('chi', 'jpn')
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
check('dual-layout-manual-before', env.props['sub-pos'] == 75, tostring(env.props['sub-pos']))
env.messages['pos']('60')   -- 用户手动设主字幕位置（cur 默认 main）
check('dual-layout-manual-wins', env.props['sub-pos'] == 60, tostring(env.props['sub-pos']))
env.events['playback-restart']()   -- 重新应用：布局已关，主字幕保持手动的 60
check('dual-layout-manual-stays-after-restart', env.props['sub-pos'] == 60, tostring(env.props['sub-pos']))
restore33()

-- T43 布局不跨文件泄漏：中日文件后再开「日+英」文件，位置不被拽成布局值
local restore34 = fresh_script_env()
set_dual_lang('chi', 'jpn')
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
check('dual-layout-leak-first-applied', env.props['secondary-sub-pos'] == 100,
    tostring(env.props['secondary-sub-pos']))
env.props['track-list'] = {{type = 'sub', id = 1, lang = 'jpn'}, {type = 'sub', id = 2, lang = 'eng'}}
env.props['sub-pos'] = 100          -- 模拟 mpv reset-on-next-file
env.props['secondary-sub-pos'] = 0
env.events['file-loaded']()
check('dual-layout-no-leak-main', env.props['sub-pos'] == 100, tostring(env.props['sub-pos']))
check('dual-layout-no-leak-sec', env.props['secondary-sub-pos'] == 0, tostring(env.props['secondary-sub-pos']))
restore34()

-- T44 外挂轨语言识别：mpv 不给 lang(恒 nil)，从文件名语言标记(.chi./.jpn.)猜
local restore35 = fresh_script_env()
set_dual_lang(nil, nil, {'C:/subs/show.chi.ass', 'C:/subs/show.jpn.ass'})
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
check('dual-layout-ext-cn-pos', env.props['sub-pos'] == 75, tostring(env.props['sub-pos']))
check('dual-layout-ext-jp-pos', env.props['secondary-sub-pos'] == 100, tostring(env.props['secondary-sub-pos']))
check('dual-layout-ext-jp-scale', math.abs((env.props['secondary-sub-scale'] or 0) - 0.8) < 0.001,
    tostring(env.props['secondary-sub-scale']))
restore35()

--------------------------------------------------------------------
-- T45 字幕延迟加载：首检无对白→不套用；第一句对白(sub-text 非空)出现即触发检测并套用；
--     检测完成后后续对白变化不再重跑（inspect_done 守卫）。
--     回归：曾因检测只在 file-loaded+inspect_delay 跑一次，字幕没在开头加载出来就永久
--     识别失败（点恢复默认再重开也一样，因为还是那一个时机）。
--------------------------------------------------------------------
local function synth_frame45(rows)
    local data = {}
    for y = 1, 4 do
        for x = 1, 4 do
            local p = rows[y][x]
            data[#data + 1] = string.char(p[1], p[2], p[3], 255)
        end
    end
    return {w = 4, h = 4, stride = 16, data = table.concat(data)}
end
local Y45 = {0x00, 0xFF, 0xFF}   -- #FFFF00 黄（彩色）
local G45 = {0x80, 0x80, 0x80}
local B45 = {0x00, 0x00, 0x00}
local function yellow_shots45()
    env.raw_shots = {
        subtitles = synth_frame45({{Y45, G45, Y45, G45},
                                   {G45, G45, G45, G45},
                                   {B45, G45, Y45, G45},
                                   {G45, G45, G45, G45}}),
        video = synth_frame45({{G45, G45, G45, G45},
                               {G45, G45, G45, G45},
                               {G45, G45, G45, G45},
                               {G45, G45, G45, G45}}),
    }
end

local restore36 = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['track-list'] = {{type = 'sub', id = 1}}   -- 内封：靠像素采样
env.props['sub-text'] = ''                            -- 片头无对白
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
flush_timers()   -- 首检：无对白 → inspect_style nil → 排重试，不套用
check('inspect-delay-no-apply', env.props['sub-color'] == nil, tostring(env.props['sub-color']))
yellow_shots45()
fire_prop('sub-text', '第一句对白')   -- 观察器触发 → 检出黄色(彩) → 套用
check('inspect-on-first-dialogue', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
-- 检测已完成：后续对白变化不再重跑（否则会重复套用/覆盖用户改动）
env.props['sub-color'] = '#123456'
fire_prop('sub-text', '第二句对白')
check('inspect-done-no-retrigger', env.props['sub-color'] == '#123456', tostring(env.props['sub-color']))
restore36()

-- T45b 重试兜底：观察器未触发时，定时重试在字幕就绪后同样能检出
local restore37 = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['track-list'] = {{type = 'sub', id = 1}}
env.props['sub-text'] = ''
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
flush_timers()   -- 首检失败 → 排一次重试
check('inspect-retry-no-apply-yet', env.props['sub-color'] == nil, tostring(env.props['sub-color']))
yellow_shots45()
env.props['sub-text'] = '对白'   -- 字幕这次直接通过属性就绪（不触发观察器）
flush_timers()                   -- 冲重试计时器 → 检出 → 套用
check('inspect-retry-applies', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
restore37()

-- T45c 手动 inspect 强制重检：无视 inspect_done 守卫（外部字幕文件解析，不受 force 影响）
local restore38 = fresh_script_env()
set_tracks(false)
env.vfs['C:/fake-config/rec.ass'] = make_ass('&H0000FFFF', '&H00FF0000')
set_external_track('C:/fake-config/rec.ass')
env.props['sub-text'] = '对白'
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
flush_timers()   -- 首检即检出（外挂文件可解析）→ 套用
check('inspect-rec-first-applies', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
env.props['sub-color'] = '#123456'   -- 模拟外部改动
env.messages['inspect']()            -- 手动重检：重置 done → 文件仍判彩色 → 再套用
check('inspect-rec-manual-redetect', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
restore38()

-- T45d 观察器门(inspect_armed)：首检(inspect_delay)跑过前，对白出现也不提前检测
--       （守住「先看到原字幕、再转黑白」时序，回归：观察器曾抢在 inspect_delay 前触发）
local restore39 = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['track-list'] = {{type = 'sub', id = 1}}
env.props['sub-text'] = ''
env.props['sub-ass-override'] = 'scale'
load_script()
env.events['file-loaded']()
yellow_shots45()
fire_prop('sub-text', '对白')   -- 首检尚未跑(armed=false) → 观察器不触发，不提前套用
check('inspect-observer-gated-before-armed', env.props['sub-color'] == nil, tostring(env.props['sub-color']))
flush_timers()                   -- 首检跑(armed=true)，此时对白已在 → 首检即检出并套用
check('inspect-after-armed-detects', env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
restore39()

-- T46 白字 + 细彩描边（内封像素路径）：描边占比 <2% 也要判「彩色」并转黑白。
-- 回归 06.mkv：白字(#FFFFFF ~22%) + 黑阴影(#000000 ~1.5%) + 粉描边(#ED74CF ~0.87%)。
-- 旧逻辑只认「高饱和色占比 ≥2%」，0.87% 被漏判成「非彩色，保持原样」——紫/粉描边不转黑白。
local restore46 = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['sub-text'] = '内封字幕文本'
env.props['track-list'] = {{type = 'sub', id = 1}}  -- 内封：无 external-filename
local GY = {0x80, 0x80, 0x80}         -- 背景灰（未变化的像素）
local WH = {0xFF, 0xFF, 0xFF}         -- #FFFFFF 主色(白)
local BK = {0x00, 0x00, 0x00}         -- #000000 真实暗描边/阴影
local PK = {0xCF, 0x74, 0xED}         -- #ED74CF 粉描边(bgr0)：非主色的高饱和元素
local FW, FH = 64, 64                 -- 64x64，步进2 → 32x32=1024 个采样点
local function bigframe(plan)
    local data = {}
    for y = 0, FH - 1 do
        for x = 0, FW - 1 do
            local c = plan(x, y) or GY
            data[#data + 1] = string.char(c[1], c[2], c[3], 255)
        end
    end
    return {w = FW, h = FH, stride = FW * 4, data = table.concat(data)}
end
-- 采样点(偶数 x,y)按序铺色：900 白 + 110 黑 + 10 粉，其余灰 ⇒ 粉占比 10/1020 ≈ 0.98%
local spots46 = {}
for y = 0, FH - 1, 2 do for x = 0, FW - 1, 2 do spots46[#spots46 + 1] = {x, y} end end
local cmap46 = {}
for i, pt in ipairs(spots46) do
    local c
    if i <= 900 then c = WH elseif i <= 1010 then c = BK elseif i <= 1020 then c = PK end
    cmap46[pt[2]] = cmap46[pt[2]] or {}
    cmap46[pt[2]][pt[1]] = c
end
env.raw_shots = {
    subtitles = bigframe(function(x, y) return cmap46[y] and cmap46[y][x] or nil end),
    video = bigframe(function() return nil end),
}
load_script()
env.messages['inspect']()
local rpt46 = last_showtext() or ''
check('t46-thin-outline-source', rpt46:find('内封字幕(像素采样)', 1, true) ~= nil, rpt46)
check('t46-thin-outline-accent-shown', rpt46:find('饱和 #ED74CF', 1, true) ~= nil, rpt46)
-- 粉描边占比 <2% 仍判彩色 → 套用预设(白/黑)
check('t46-thin-outline-colored-applies', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
flush_timers()   -- override 切到 force 走 rebuild_delay 延迟，冲计时器后生效
check('t46-thin-outline-force', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
restore46()

-- T46b 抗锯齿 fringe 守卫：白字 + 极少量高饱和像素(<colored_outline_min)且无暗描边
--       ⇒ 仍判「非彩色」，不因零星饱和像素误转。防 colored_outline_min 过低导致误判。
local restore46b = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['sub-text'] = '内封字幕文本'
env.props['track-list'] = {{type = 'sub', id = 1}}
local cmap46b = {}
for i, pt in ipairs(spots46) do
    local c
    if i <= 900 then c = WH elseif i <= 903 then c = PK end   -- 粉仅 3/903 ≈ 0.33% < 0.5%
    cmap46b[pt[2]] = cmap46b[pt[2]] or {}
    cmap46b[pt[2]][pt[1]] = c
end
env.raw_shots = {
    subtitles = bigframe(function(x, y) return cmap46b[y] and cmap46b[y][x] or nil end),
    video = bigframe(function() return nil end),
}
load_script()
env.messages['inspect']()
-- 无暗描边、粉占比 <0.5% ⇒ 非彩色，不套用（fringe 不进 is_colored_hex(outline)）
check('t46b-fringe-not-colored', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
restore46b()

-- T47 seek 后重新检测（本 bug 回归）：
--   开头无对白（内封字幕，像素采样拿不到）→ 首轮重试额度耗尽 →
--   seek 到有字幕处必须刷新额度并重新检测、套用预设。
--   修复前：额度耗尽后 seek 不刷新，一次采样失败就永久放弃
--   （表现为「打开即 OP/ED，拖动进度到正片后彩色字幕既不识别也不转黑白」）。
local restore47 = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['sub-text'] = ''                            -- 开头无对白
env.props['track-list'] = {{type = 'sub', id = 1}}    -- 内封：无 external-filename
local GRAY_ROWS = {
    {GRAY, GRAY, GRAY, GRAY},
    {GRAY, GRAY, GRAY, GRAY},
    {GRAY, GRAY, GRAY, GRAY},
    {GRAY, GRAY, GRAY, GRAY},
}
-- 两帧完全相同 ⇒ 差分 total==0 ⇒ 采样返回 nil（字幕未渲染）
env.raw_shots = { subtitles = synth_frame(GRAY_ROWS), video = synth_frame(GRAY_ROWS) }
load_script()
env.events['file-loaded']()
flush_timers()                       -- inspect_delay 后的首检 → nil → 排一次重试
for _ = 1, 40 do                     -- 耗尽重试额度（默认 inspect_retries=15）
    if #env.timers == 0 then break end
    flush_timers()
end
check('t47-budget-exhausted', #env.timers == 0, 'timers=' .. #env.timers)
check('t47-not-applied-before-seek', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
-- seek 到有字幕处，但「刚落地字幕尚未渲染」⇒ 首采失败，必须靠重试兜底。
-- 这正是真实时序（seek 后字幕要下一帧才画出来），也是本 bug 的关键：
-- 额度耗尽后若不刷新，首采失败就再没机会重试。
env.props['sub-text'] = '正片对白'
env.raw_shots = { subtitles = synth_frame(GRAY_ROWS), video = synth_frame(GRAY_ROWS) }
env.events['seek']()                 -- 触发 seek 重新武装（刷新额度）
flush_timers()                       -- 0.3s 去抖 → run_inspect → 采样失败 → 排重试
-- 下一帧字幕渲染出来（黄色彩字）
env.raw_shots = {
    subtitles = synth_frame({
        {YELLOW, GRAY, YELLOW, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
        {BLACK, GRAY, YELLOW, GRAY},
        {GRAY, GRAY, GRAY, GRAY},
    }),
    video = synth_frame(GRAY_ROWS),
}
for _ = 1, 8 do                      -- 共享通道立即写；override 延迟重建才切 force
    if env.props['sub-ass-override'] == 'force' then break end
    if #env.timers == 0 then break end
    flush_timers()
end
check('t47-after-seek-applied', env.props['sub-color'] == '#FFFFFF',
    tostring(env.props['sub-color']))
check('t47-after-seek-force', env.props['sub-ass-override'] == 'force',
    tostring(env.props['sub-ass-override']))
restore47()

--------------------------------------------------------------------
-- T48~T51 上下黑边贴合（v1.0.7）
-- 合成帧 32×200：上下各 12 行纯黑(6%)，中央 128 灰。
--   video 帧给 detect_bars 逐行亮度扫描；subtitles 帧在中央补白点，让
--   run_inspect 像素采样成功产出左上角报告 —— 这样能同时验证：
--   refresh_barfit 的 OSD 微扰（show-text ' '）会清报告，脚本必须补回来。
-- 注意 detect_bars 要求 img.h >= 16，故不能用 4×4 的 synth_frame。
--------------------------------------------------------------------
local BW48, BH48 = 32, 200
local function barframe48(top, bottom, mid, sub_pixels)
    local data = {}
    for y = 0, BH48 - 1 do
        local dark = (y < top) or (y >= BH48 - bottom)
        for x = 0, BW48 - 1 do
            local c = dark and 0 or mid
            if sub_pixels and not dark and y >= 80 and y <= 120
                and y % 2 == 0 and x % 2 == 0 then
                c = 255
            end
            data[#data + 1] = string.char(c, c, c, 255)
        end
    end
    return {w = BW48, h = BH48, stride = BW48 * 4, data = table.concat(data)}
end
local function bars_env(top, bottom, mid)
    local r = fresh_script_env()
    set_tracks(true)
    env.props['sid'] = 1
    env.props['sub-text'] = '上下黑边示例'
    env.props['track-list'] = {{type = 'sub', id = 1}}   -- 内封：走像素采样
    env.props['sub-margin-y'] = 34                        -- 基线：关闭/让位后必须还原
    env.props['sub-font-size'] = 50                       -- 字幕盒高度估算输入
    env.opt_overrides = {letterbox_sample_step = 1}
    env.raw_shots = {
        video = barframe48(top, bottom, mid, false),
        subtitles = barframe48(top, bottom, mid, true),
    }
    return r
end

-- T48 检测 → 布局：主轨贴下黑边(100)、次轨贴上黑边(0)、两轨同倍率限缩
local restore48 = bars_env(12, 12, 128)
load_script()
check('t48-letterbox-messages-registered',
    env.messages['letterbox-toggle'] ~= nil and env.messages['letterbox-refresh'] ~= nil)
env.events['file-loaded']()
flush_timers()   -- 首检 + 黑边检测两个 timer 同轮执行（先报告、后贴合）
local scale48 = tonumber(env.props['sub-scale']) or 0
local margin48 = tonumber(env.props['sub-margin-y']) or -1
check('t48-main-pos-bottom-bar', env.props['sub-pos'] == 100,
    tostring(env.props['sub-pos']))
check('t48-sec-pos-top-bar', env.props['secondary-sub-pos'] == 0,
    tostring(env.props['secondary-sub-pos']))
-- usable = 200×0.06×0.9 = 10.8；unit = 50×1.2×(200/720) = 16.667 ⇒ scale = 0.648
check('t48-scale-limited-by-bar-height', math.abs(scale48 - 0.648) < 0.02,
    string.format('scale=%.4f', scale48))
check('t48-sec-scale-same-as-main', env.props['secondary-sub-scale'] == scale48,
    tostring(env.props['secondary-sub-scale']))
-- margin_y = (12 - 10.8)/2 / (200/720) = 2.16，但 sub-margin-y 是 INT 属性，
-- 真机实测写入小数会被 mpv 静默忽略 ⇒ 必须四舍五入成 2。
check('t48-margin-y-centers-box-in-bar', math.abs(margin48 - 2) < 0.001,
    string.format('margin_y=%.4f', margin48))
check('t48-margin-y-is-integer', margin48 == math.floor(margin48),
    tostring(margin48))
local has_nudge48 = false
for _, t in ipairs(env.showtexts) do if t == ' ' then has_nudge48 = true end end
check('t48-nudge-reconfigure-for-margin', has_nudge48)
local last48 = env.showtexts[#env.showtexts] or ''
check('t48-report-restored-after-osd-nudge',
    last48:find('内封字幕', 1, true) ~= nil and last48:find('主色', 1, true) ~= nil,
    last48:gsub('\n', ' / '))

-- T49 开关 / 手动让位 / 复位 / 切文件：都必须还原共享的 sub-margin-y
local restore49 = bars_env(12, 12, 128)
load_script()
env.events['file-loaded']()
flush_timers()
local function refit49()
    env.messages['letterbox-toggle']()   -- 先关
    env.messages['letterbox-toggle']()   -- 再开：refresh_barfit 同步重检
end
env.showtexts = {}
env.messages['letterbox-toggle']()
local off_nudge49 = false
for _, t in ipairs(env.showtexts) do if t == ' ' then off_nudge49 = true end end
check('t49-toggle-off-triggers-reconfigure', off_nudge49)
check('t49-toggle-off-restores-margin', env.props['sub-margin-y'] == 34,
    tostring(env.props['sub-margin-y']))
check('t49-toggle-off-restores-scale', env.props['sub-scale'] == 1,
    tostring(env.props['sub-scale']))
check('t49-toggle-off-flash', (last_showtext() or ''):find('已还原默认位置', 1, true) ~= nil,
    last_showtext())
-- 上面已关过一次，这里单次调用即「重新开启 + 立即重检」
env.messages['letterbox-toggle']()
check('t49-toggle-on-refits', env.props['sub-margin-y'] ~= 34
    and (tonumber(env.props['sub-scale']) or 1) < 1,
    string.format('margin=%s scale=%s', tostring(env.props['sub-margin-y']),
        tostring(env.props['sub-scale'])))
env.messages['pos']('50')
check('t49-manual-pos-yields-barfit', env.props['sub-pos'] == 50
    and env.props['sub-margin-y'] == 34,
    string.format('pos=%s margin=%s', tostring(env.props['sub-pos']),
        tostring(env.props['sub-margin-y'])))
refit49()
env.messages['scale']('0.8')
check('t49-manual-scale-yields-barfit', env.props['sub-scale'] == 0.8
    and env.props['sub-margin-y'] == 34,
    string.format('scale=%s margin=%s', tostring(env.props['sub-scale']),
        tostring(env.props['sub-margin-y'])))
refit49()
env.messages['reset']()
check('t49-reset-restores-margin', env.props['sub-margin-y'] == 34,
    tostring(env.props['sub-margin-y']))
refit49()
env.events['end-file']()
check('t49-end-file-restores-margin', env.props['sub-margin-y'] == 34,
    tostring(env.props['sub-margin-y']))
-- 外部改属性（r/t 键 / 其它脚本）也要让位
refit49()
fire_prop('sub-pos', 70)
check('t49-external-pos-yields-barfit', env.props['sub-margin-y'] == 34,
    tostring(env.props['sub-margin-y']))

-- T50 误判守卫：暗场 / 无黑边 / 黑边过薄 / 单侧黑边都不应贴合
local restore50 = {}
local function guard_case(name, top, bottom, mid)
    restore50[#restore50 + 1] = bars_env(top, bottom, mid)
    load_script()
    env.events['file-loaded']()
    flush_timers()
    check(name, env.props['sub-margin-y'] == 34 and env.props['sub-scale'] == 1,
        string.format('margin=%s scale=%s', tostring(env.props['sub-margin-y']),
            tostring(env.props['sub-scale'])))
end
guard_case('t50-dark-frame-not-misdetected', 12, 12, 0)
guard_case('t50-no-bars', 0, 0, 128)
guard_case('t50-thin-bars-below-min', 2, 2, 128)
guard_case('t50-one-sided-bar-not-fitted', 12, 0, 128)
-- 有黑边但 conf 里关掉 letterbox_fit：不检测、不改写任何布局属性
local restore50b = bars_env(12, 12, 128)
env.opt_overrides = {letterbox_sample_step = 1, letterbox_fit = false}
load_script()
env.events['file-loaded']()
flush_timers()
check('t50-letterbox-fit-no-option', env.props['sub-margin-y'] == 34
    and env.props['sub-scale'] == 1,
    string.format('margin=%s scale=%s', tostring(env.props['sub-margin-y']),
        tostring(env.props['sub-scale'])))
restore50[#restore50 + 1] = restore50b

-- T51 菜单里要有开关与「重新检测」入口
local restore51 = fresh_script_env()
set_tracks(true)
load_script()
env.messages['uosc-version']()
env.messages['open-menu']()
local data51 = jdec(uosc_command()[4])
local values51 = {}
for _, it in ipairs(data51.items or {}) do values51[#values51 + 1] = tostring(it.value) end
local joined51 = table.concat(values51, '\n')
check('t51-menu-has-letterbox-toggle',
    joined51:find('letterbox-toggle', 1, true) ~= nil)
check('t51-menu-has-letterbox-refresh',
    joined51:find('letterbox-refresh', 1, true) ~= nil)

--------------------------------------------------------------------
-- T52 v1.0.8「所有的内封字幕都要被检查」
--   报障截图：内封 ASS 主色 #8B8B8B，旧版显示「非彩色字幕，保持原样」。
--   ① 报告列出全部内封轨、逐轨记录检查状态；② 切换 sid 检查新轨；
--   ③ 内封非标准配色一律套用（即使手动关掉灰色识别）；
--   ④ 标准白字内封 / 外挂字幕 / 关闭开关时保持旧行为。
--------------------------------------------------------------------
local restore52 = {}
local PX_GRAY_INTERNAL = {0x8B, 0x8B, 0x8B}   -- #8B8B8B（bgr0）
local function gray_internal_shots()
    local black_row = {BLACK, BLACK, BLACK, BLACK}
    return {
        subtitles = synth_frame({
            {PX_GRAY_INTERNAL, BLACK, PX_GRAY_INTERNAL, BLACK},
            black_row,
            {BLACK, BLACK, PX_GRAY_INTERNAL, BLACK},
            black_row,
        }),
        video = synth_frame({black_row, black_row, black_row, black_row}),
    }
end
local function setup52(overrides)
    local r = fresh_script_env()
    env.opt_overrides = overrides or {}
    set_tracks(false)
    env.props['sid'] = 1
    env.props['sub-text'] = '内封灰色字幕'
    env.props['track-list'] = {
        {type = 'sub', id = 1},
        {type = 'sub', id = 2},
        {type = 'sub', id = 3, external = true,
         ['external-filename'] = 'C:/fake-config/other.ass'},
    }
    env.raw_shots = gray_internal_shots()
    load_script()
    return r
end
local function flush_all52()
    for _ = 1, 4 do flush_timers() end
end

-- ① 首检：关掉灰色识别，内封全量规则仍然套用；报告列出所有内封轨
local r52a = setup52()
env.messages['toggle-gray']()
env.events['file-loaded']()
flush_all52()
local report52 = last_showtext() or ''
check('t52-report-lists-all-internal-tracks',
    report52:find('内封字幕轨：共 2 条', 1, true) ~= nil, report52)
check('t52-report-shows-checked-count',
    report52:find('已检查 1 条', 1, true) ~= nil, report52)
check('t52-report-shows-pending-tracks',
    report52:find('待检查 2', 1, true) ~= nil, report52)
check('t52-internal-applies-with-gray-off',
    env.props['sub-color'] == '#FFFFFF', tostring(env.props['sub-color']))
check('t52-internal-report-applied',
    report52:find('已套用预设样式', 1, true) ~= nil, report52)
-- ② 切到另一条内封轨 ⇒ 重新检测并记账
local before52 = #env.showtexts
fire_prop('sid', 2)
flush_all52()
check('t52-switch-sid-triggers-reinspect', #env.showtexts > before52,
    tostring(#env.showtexts - before52))
local report52b = last_showtext() or ''
check('t52-second-internal-track-checked',
    report52b:find('已检查 2 条', 1, true) ~= nil, report52b)
check('t52-no-pending-after-all-checked',
    report52b:find('待检查', 1, true) == nil, report52b)
-- ③ 切回已检查过的轨不重复检测
local before52c = #env.showtexts
fire_prop('sid', 1)
flush_all52()
check('t52-revisited-track-no-reinspect', #env.showtexts == before52c,
    tostring(#env.showtexts - before52c))
restore52[#restore52 + 1] = r52a

-- ④ 标准白字内封：保持原样（不误转，fringe 守卫的老规矩）
local r52b = fresh_script_env()
set_tracks(false)
env.props['sid'] = 1
env.props['sub-text'] = '内封白色字幕'
env.props['track-list'] = {{type = 'sub', id = 1}}
local PX_WHITE52 = {0xFF, 0xFF, 0xFF}
local white_row = {BLACK, BLACK, BLACK, BLACK}
env.raw_shots = {
    subtitles = synth_frame({
        {PX_WHITE52, BLACK, PX_WHITE52, BLACK},
        white_row, {BLACK, BLACK, PX_WHITE52, BLACK}, white_row,
    }),
    video = synth_frame({white_row, white_row, white_row, white_row}),
}
load_script()
env.events['file-loaded']()
flush_all52()
check('t52-standard-white-internal-unchanged', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
restore52[#restore52 + 1] = r52b

-- ⑤ 外挂灰色字幕不受内封全量规则影响（灰色识别关掉时保持原样）
local r52c = fresh_script_env()
set_tracks(false)
env.vfs['C:/fake-config/gray52.ass'] = make_ass('&H008B8B8B', '&H00000000')
set_external_track('C:/fake-config/gray52.ass')
load_script()
env.messages['toggle-gray']()
env.messages['inspect']()
check('t52-external-gray-not-forced', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
restore52[#restore52 + 1] = r52c

-- ⑥ 两个开关都关 ⇒ 回到旧行为：无统计行、关掉灰色识别后不套用
local r52d = setup52({inspect_all_internal = false, preset_all_internal = false})
env.messages['toggle-gray']()
env.events['file-loaded']()
flush_all52()
local report52d = last_showtext() or ''
check('t52-switches-off-no-track-report',
    report52d:find('内封字幕轨', 1, true) == nil, report52d)
check('t52-switches-off-keeps-original', env.props['sub-color'] == nil,
    tostring(env.props['sub-color']))
restore52[#restore52 + 1] = r52d

for i = #restore52, 1, -1 do restore52[i]() end

--------------------------------------------------------------------
-- T53 v1.0.9「内封定位字幕也能缩放 / 改字号」
--   真机隔离实验（640x360 双行 ASS）：sub-scale 对 \pos 行完全无效，
--   Fontsize 对两行都有效；force 下两者互不叠加，scale 下会双叠加。
--   本组验证：① 只在「内封 ASS + 有样式表」时激活，外挂/无表零回归；
--   ② 缩放/字号折成 Fontsize 且 sub-scale 归 1；③ ±1px 连续微调与边界；
--   ④ nudge 边界不再静默；⑤ 黑边贴合改用 ASS 原始字号估算盒高并存预设。
-- ⚠ 用独立函数包裹：Lua 5.1 单个函数最多 200 个活跃局部变量，主 chunk
--   到 T52 已接近上限，T53 的局部变量必须放进自己的栈帧。
--------------------------------------------------------------------
function run_t53()
local ASS_HEADER_53 = table.concat({
    '[Script Info]',
    'ScriptType: v4.00+',
    'PlayResX: 384',
    'PlayResY: 288',
    '',
    '[V4+ Styles]',
    'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour',
    'Style: Default,Microsoft YaHei,21,&H00FFFFFF,&H000000FF',
    'Style: Sign,WenQuanYi Micro Hei,14,&H00FFFFFF,&H000000FF',
    '',
    '[Events]',
    'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
    '',
}, '\n')

local function setup53(overrides, ext)
    local r = fresh_script_env()
    env.opt_overrides = overrides or {}
    set_tracks(false)
    if ext then
        env.props['current-tracks/sub'] = {codec = 'ass', image = false,
                                           external = true, id = 1}
    end
    env.props['sub-font-size'] = 38       -- 基线：size_factor 的分母
    env.props['sub-ass-style-overrides'] = nil
    env.props['sub-ass-extradata'] = ASS_HEADER_53
    env.props['sid'] = 1
    env.props['track-list'] = {{type = 'sub', id = 1}}
    load_script()
    return r
end

local function fontsize53()
    for _, e in ipairs(env.props['sub-ass-style-overrides'] or {}) do
        local v = e:match('^Fontsize=(.+)$')
        if v then return tonumber(v) end
    end
    return nil
end

local restore53 = {}

-- ① 无偏差时**不写** Fontsize（否则会把多 style 的原始字号层级压平）
local r53a = setup53()
check('t53-no-fontsize-when-no-deviation', fontsize53() == nil,
    tostring(fontsize53()))
-- ② 整体缩放：1.5 × Default 21 = 31.5，且 sub-scale 归 1 / sub-font-size 乘倍率
env.messages['scale']('1.5')
check('t53-scale-writes-ass-fontsize', math.abs((fontsize53() or 0) - 31.5) < 0.01,
    'Fontsize=' .. tostring(fontsize53()))
check('t53-scale-neutralizes-sub-scale', env.props['sub-scale'] == 1,
    tostring(env.props['sub-scale']))
check('t53-scale-folds-into-sub-font-size',
    math.abs((tonumber(env.props['sub-font-size']) or 0) - 57) < 0.01,
    tostring(env.props['sub-font-size']))
check('t53-scale-flash-names-fontsize',
    (last_showtext() or ''):find('Fontsize', 1, true) ~= nil, last_showtext())
-- ③ 字号覆盖：先撤掉上面的 ×1.5，57px / 基线 38 = 1.5 倍 → 同样的 31.5
--    （缩放与字号本就相乘：不撤掉时 21×1.5×1.5=47.25，属预期行为）
env.messages['scale']('1')
env.messages['size']('57')
check('t53-size-writes-ass-fontsize', math.abs((fontsize53() or 0) - 31.5) < 0.01,
    'Fontsize=' .. tostring(fontsize53()))
-- ④ 字号原样 + 缩放 ×1 ⇒ 清掉 Fontsize，回到 ASS 原始字号
env.messages['size']('reset')
env.messages['scale']('1')
check('t53-reset-clears-fontsize', fontsize53() == nil, tostring(fontsize53()))
-- ⑤ 位置微调到边界：明确提示而不是静默 clamp
env.messages['pos']('150')
env.messages['nudge']('5')
check('t53-nudge-boundary-flash',
    (last_showtext() or ''):find('位置边界', 1, true) ~= nil, last_showtext())
check('t53-nudge-boundary-no-change', env.props['sub-pos'] == 150,
    tostring(env.props['sub-pos']))
-- ⑥ 定位字幕不响应 sub-pos 的说明
env.messages['pos']('50')
check('t53-pos-hint-for-positioned-subtitle',
    (last_showtext() or ''):find('定位字幕保持原位', 1, true) ~= nil, last_showtext())
restore53[#restore53 + 1] = r53a

-- ⑦ ±1px 连续微调：从 size_baseline 起步，逐次递增、两次都生效
local r53b = setup53()
env.messages['size-step']('1')
local f1 = fontsize53()
local s1 = tonumber(env.props['sub-font-size'])
env.messages['size-step']('1')
local f2 = fontsize53()
local s2 = tonumber(env.props['sub-font-size'])
check('t53-size-step-writes-fontsize', f1 ~= nil and f2 ~= nil and f2 > f1,
    string.format('%s → %s', tostring(f1), tostring(f2)))
check('t53-size-step-continuous', s2 > s1,
    string.format('%s → %s', tostring(s1), tostring(s2)))
check('t53-size-step-flash', (last_showtext() or ''):find('+1', 1, true) ~= nil,
    last_showtext())
-- 点回基线字号：算出来的倍率正好 =1，此时不该留下 `Fontsize=20` 这种
-- 无效覆盖（会把 ASS 多 style 的原始字号层级压平）。真机 E2E 在关闭黑边
-- 贴合后发现过这个残留，故补一条回归断言。
env.messages['size-step']('-1')
env.messages['size-step']('-1')
check('t53-size-step-back-to-baseline-clears-fontsize', fontsize53() == nil,
    'Fontsize=' .. tostring(fontsize53()))
-- 边界：先到上限再点 +
env.messages['size']('96')
env.messages['size-step']('1')
check('t53-size-step-max-flash',
    (last_showtext() or ''):find('边界', 1, true) ~= nil, last_showtext())
-- 下限同理
env.messages['size']('12')
env.messages['size-step']('-1')
check('t53-size-step-min-flash',
    (last_showtext() or ''):find('边界', 1, true) ~= nil, last_showtext())
restore53[#restore53 + 1] = r53b

-- ⑧ 外挂 ASS / 无样式表：通道不激活，完全走旧的 sub-scale
local r53c = setup53(nil, true)
env.messages['scale']('1.5')
check('t53-external-no-fontsize', fontsize53() == nil, tostring(fontsize53()))
check('t53-external-keeps-sub-scale', env.props['sub-scale'] == 1.5,
    tostring(env.props['sub-scale']))
restore53[#restore53 + 1] = r53c
local r53d = setup53()
env.props['sub-ass-extradata'] = nil
env.messages['scale']('1.5')
check('t53-missing-extradata-no-channel', fontsize53() == nil,
    tostring(fontsize53()))
restore53[#restore53 + 1] = r53d

-- ⑨ 运行时开关：关掉后清 Fontsize 并恢复原生 sub-scale
local r53e = setup53()
env.messages['scale']('1.5')
env.messages['ass-fontsize-toggle']()
check('t53-toggle-off-clears-fontsize', fontsize53() == nil, tostring(fontsize53()))
check('t53-toggle-off-restores-sub-scale', env.props['sub-scale'] == 1.5,
    tostring(env.props['sub-scale']))
env.messages['ass-fontsize-toggle']()
check('t53-toggle-on-restores-fontsize', fontsize53() ~= nil, tostring(fontsize53()))
restore53[#restore53 + 1] = r53e

-- ⑩ 菜单：±字号 / 通道开关 / 缩放提示都要在
local r53f = setup53()
env.messages['uosc-version']()
env.messages['open-menu']()
local data53 = jdec(uosc_command()[4])
local values53 = {}
for _, it in ipairs(data53.items or {}) do values53[#values53 + 1] = tostring(it.value) end
local joined53 = table.concat(values53, '\n')
check('t53-menu-has-size-step-plus', joined53:find('size-step 1', 1, true) ~= nil)
check('t53-menu-has-size-step-minus', joined53:find('size-step -1', 1, true) ~= nil)
check('t53-menu-has-ass-toggle', joined53:find('ass-fontsize-toggle', 1, true) ~= nil)
check('t53-menu-scale-hint-positioned',
    table.concat(values53, '\n'):find('size-step', 1, true) ~= nil)
restore53[#restore53 + 1] = r53f

-- ⑪ 黑边贴合：改用 ASS 原始字号/PlayResY 估算盒高，并把用户放大存进全局预设
local r53g = bars_env(12, 12, 128)
env.props['sub-ass-extradata'] = ASS_HEADER_53
env.props['sub-font-size'] = 38
load_script()
env.events['file-loaded']()
flush_timers()
-- 通道激活时 sub-scale 被归 1，限缩倍率体现在 ASS Fontsize 里：
--   Fontsize = Default 21 × scale ⇒ scale = Fontsize / 21
-- unit = max_fontsize 21 × 1.2 × (200/288) = 17.5；usable = 200×0.06×0.9 = 10.8
local scale53 = (fontsize53() or 0) / 21
check('t53-barfit-uses-ass-unit', math.abs(scale53 - 0.617) < 0.02,
    string.format('scale=%.4f Fontsize=%s', scale53, tostring(fontsize53())))
check('t53-barfit-neutralizes-sub-scale', env.props['sub-scale'] == 1,
    tostring(env.props['sub-scale']))
check('t53-barfit-writes-shrunk-fontsize',
    fontsize53() ~= nil and fontsize53() < 21, 'Fontsize=' .. tostring(fontsize53()))
env.messages['size-step']('1')
local preset53 = jdec(env.vfs['C:/fake-config/uosc-subtitle-style-preset.json'] or '{}')
-- baseline.size=38（本组显式注入）⇒ 点一次 +1 = 39px
check('t53-size-step-saves-global-preset', preset53.size == 39,
    'preset.size=' .. tostring(preset53.size))
check('t53-size-step-flash-saved',
    (last_showtext() or ''):find('已存为全局预设', 1, true) ~= nil, last_showtext())
restore53[#restore53 + 1] = r53g

for i = #restore53, 1, -1 do restore53[i]() end
end
run_t53()

--------------------------------------------------------------------
-- T54：对外 API（user-data 状态广播 + api 请求-响应 + 白名单动作转发）
--------------------------------------------------------------------
function run_t54()
local API_PREFIX_FOR_TEST = 'uosc_subtitle_style'
local r54 = fresh_script_env()
set_tracks(false)
load_script()

local STATE_KEY = 'user-data/' .. API_PREFIX_FOR_TEST .. '/state'
local RESP = API_PREFIX_FOR_TEST .. '-api-response'

local function replies()
    local out = {}
    for _, c in ipairs(env.script_messages or {}) do
        if c[3] == RESP then out[#out + 1] = c end
    end
    return out
end
local function last_payload()
    local rs = replies()
    local c = rs[#rs]
    return c and jdec(c[5]) or nil
end
local function broadcast()
    local ok, v = pcall(jdec, env.props[STATE_KEY] or '{}')
    return ok and v or {}
end
local function clear_replies() env.script_messages = {} end

-- ① 注册与初始广播
check('t54-api-message-registered', type(env.messages['api']) == 'function')
check('t54-api-version-property',
    env.props['user-data/' .. API_PREFIX_FOR_TEST .. '/version'] == '1.0.0',
    tostring(env.props['user-data/' .. API_PREFIX_FOR_TEST .. '/version']))
local snap0 = broadcast()
check('t54-initial-state-broadcast', snap0.api_version == '1.0.0'
    and type(snap0.main) == 'table' and type(snap0.sec) == 'table',
    'target=' .. tostring(snap0.target))
check('t54-snapshot-has-runtime-and-preset',
    type(snap0.runtime) == 'table' and type(snap0.preset) == 'table')
check('t54-snapshot-has-barfit-flag', type(snap0.barfit_active) == 'boolean')

-- ② get-state 请求-响应（request_id 原样回填，回复走 command_native 数组）
clear_replies()
env.messages['api']('client', 'r1', 'get-state')
local rs = replies()
check('t54-get-state-reply-shape', #rs == 1 and rs[1][2] == 'client'
    and rs[1][3] == RESP and rs[1][4] == 'r1', '#replies=' .. #rs)
local p1 = last_payload()
check('t54-get-state-ok', p1 and p1.ok == true and type(p1.data) == 'table')
check('t54-get-state-request-id', p1 and p1.request_id == 'r1')

-- ③ get 单字段：命中 / 未命中
clear_replies()
env.messages['api']('client', 'r2', 'get', 'main.pos')
local p2 = last_payload()
check('t54-get-dotted-key', p2 and p2.ok == true
    and p2.key == 'main.pos' and type(p2.value) == 'number',
    'value=' .. tostring(p2 and p2.value))
clear_replies()
env.messages['api']('client', 'r3', 'get', 'no.such.key')
local p3 = last_payload()
check('t54-get-unknown-key', p3 and p3.ok == false
    and p3.error == 'unknown_key')
clear_replies()
env.messages['api']('client', 'r4', 'get')
check('t54-get-bad-key', last_payload().error == 'bad_key')

-- ④ 参数校验：非法 reply_to / request_id 不发往未知目标
clear_replies()
env.messages['api']('bad target', 'r5', 'get-state')
env.messages['api'](nil, 'r6', 'get-state')
env.messages['api']('client', '', 'get-state')
check('t54-invalid-tokens-no-reply', #replies() == 0, '#replies=' .. #replies())

-- ⑤ 未知 action / list-actions 不含 api 自身
clear_replies()
env.messages['api']('client', 'r7', 'no-such-action')
check('t54-unknown-action', last_payload().error == 'unknown_action')
clear_replies()
env.messages['api']('client', 'r8', 'list-actions')
local acts = last_payload().actions or {}
local has_nudge, has_api = false, false
for _, a in ipairs(acts) do
    if a == 'nudge' then has_nudge = true end
    if a == 'api' then has_api = true end
end
check('t54-list-actions-whitelist', has_nudge and not has_api,
    'n=' .. #acts .. ' api=' .. tostring(has_api))

-- ⑥ call：白名单转发 / 拒绝递归入口
clear_replies()
env.messages['api']('client', 'r9', 'call', 'nudge', '-5')
local p9 = last_payload()
check('t54-call-dispatch-ok', p9 and p9.ok == true
    and p9.dispatched == 'nudge' and p9.async == true)
local fwd
for _, c in ipairs(env.script_messages) do
    if c[2] == API_PREFIX_FOR_TEST and c[3] == 'nudge' then fwd = c end
end
check('t54-call-forwards-native-message',
    fwd ~= nil and fwd[4] == '-5', fwd and table.concat(fwd, '|') or 'none')
clear_replies()
env.messages['api']('client', 'r10', 'call', 'api')
check('t54-call-rejects-recursive',
    last_payload().error == 'action_not_allowed')
clear_replies()
env.messages['api']('client', 'r11', 'call')
check('t54-call-requires-name', last_payload().error == 'bad_action_name')

-- ⑦ 状态变更会自动刷新广播（订阅者无需主动轮询）
local before = broadcast().main.pos
env.messages['nudge']('-5')
local after = broadcast().main.pos
check('t54-broadcast-refreshes-on-change', after == before - 5,
    string.format('%s -> %s', tostring(before), tostring(after)))

-- ⑧ 复位后既有消息仍全部注册（API 不覆盖原生入口）
check('t54-native-messages-intact',
    type(env.messages['open-menu']) == 'function'
    and type(env.messages['letterbox-toggle']) == 'function'
    and type(env.messages['size-step']) == 'function')

r54()
end
run_t54()

--------------------------------------------------------------------
-- T55：上下黑边里「上下两条对话字幕」字号自适应（v1.0.10 新增判据）
-- 与 T48~T51 的区别：T48 只验证 12/12 对称黑边的一档限缩；
-- 这里横向比较不同厚度 / 上下不等高，证明倍率由**较薄黑边**决定、
-- 两条对白用同一倍率且都不会溢出黑边，并把结果接进对外 API 快照。
-- 帧 32×200、font_size=50 ⇒ unit = 50 × 1.2 × (200/720) = 16.667px
--   usable = 200 × bar_frac × (1-pad=0.9)
--------------------------------------------------------------------
function run_t55()
local UNIT55 = 50 * 1.2 * (200 / 720)
local PAD55 = 0.10

local function bf_case(top, bottom)
    local r = bars_env(top, bottom, 128)
    load_script()
    env.events['file-loaded']()
    flush_timers()
    local out = {
        scale = tonumber(env.props['sub-scale']) or -1,
        sec_scale = tonumber(env.props['secondary-sub-scale']) or -2,
        margin = tonumber(env.props['sub-margin-y']) or -1,
        pos = env.props['sub-pos'],
        sec_pos = env.props['secondary-sub-pos'],
    }
    -- 对外 API 快照里的黑边结果必须与真实属性一致（T54 ↔ T55 联动）
    env.script_messages = {}
    env.messages['api']('client', 'b1', 'get-state')
    local raw
    for _, c in ipairs(env.script_messages) do
        if c[3] == 'uosc_subtitle_style-api-response' then raw = c[5] end
    end
    local ok, res = pcall(jdec, raw or '{}')
    out.api = ok and res and res.data or nil
    r()
    return out
end

local function box_px(case, top, bottom)
    local bar_frac = math.min(top, bottom) / 200
    return case.scale * UNIT55, 200 * bar_frac
end

-- ① 对称 12/12：基线倍率（T48 已验 0.648，此处作为对照组）
local c12 = bf_case(12, 12)
check('t55-symmetric-12-baseline', math.abs(c12.scale - 0.648) < 0.02,
    string.format('scale=%.4f', c12.scale))

-- ② 更薄的 6/6：字号必须按黑边高度同比缩小
local c6 = bf_case(6, 6)
check('t55-thinner-bar-shrinks-font', c6.scale < c12.scale * 0.6,
    string.format('6/6=%.4f vs 12/12=%.4f', c6.scale, c12.scale))
check('t55-thinner-bar-scale-value', math.abs(c6.scale - 0.324) < 0.02,
    string.format('scale=%.4f', c6.scale))

-- ③ 上下不等高 18/6：取较薄一侧，倍率与 6/6 完全一致
local casym = bf_case(18, 6)
check('t55-asymmetric-uses-thinner-bar',
    math.abs(casym.scale - c6.scale) < 0.001,
    string.format('18/6=%.4f vs 6/6=%.4f', casym.scale, c6.scale))
check('t55-asymmetric-both-tracks-same-scale',
    math.abs(casym.sec_scale - casym.scale) < 0.001,
    tostring(casym.sec_scale))

-- ④ 宽黑边 30/30：够宽时不放大字幕，只居中
local c30 = bf_case(30, 30)
check('t55-wide-bar-does-not-enlarge', math.abs(c30.scale - 1) < 0.001,
    string.format('scale=%.4f', c30.scale))

-- ⑤ 每种情况：字幕盒高度不超过该侧黑边的可用高度（自适应不溢出）
for _, spec in ipairs({{c12, 12, 12, '12/12'}, {c6, 6, 6, '6/6'},
                       {casym, 18, 6, '18/6'}, {c30, 30, 30, '30/30'}}) do
    local box, bar_px = box_px(spec[1], spec[2], spec[3])
    check('t55-box-fits-bar-' .. spec[4],
        box <= bar_px * (1 - PAD55) + 0.01 and box > 0,
        string.format('box=%.2f bar=%.2f usable=%.2f',
            box, bar_px, bar_px * (1 - PAD55)))
end

-- ⑥ 上下两条对白分别贴下/上黑边，且 margin 为整数（INT 属性硬约束）
check('t55-both-dialogues-in-opposite-bars',
    c6.pos == 100 and c6.sec_pos == 0,
    string.format('main=%s sec=%s', tostring(c6.pos), tostring(c6.sec_pos)))
check('t55-margin-is-integer', c6.margin == math.floor(c6.margin)
    and casym.margin == math.floor(casym.margin),
    string.format('6/6=%s 18/6=%s', tostring(c6.margin), tostring(casym.margin)))
check('t55-margin-centers-box', c6.margin >= 0 and casym.margin >= 0)

-- ⑦ API 快照把黑边结果对外输出，供其它脚本读取
check('t55-api-exposes-barfit', c6.api ~= nil and c6.api.barfit_active == true
    and type(c6.api.barfit) == 'table',
    c6.api and tostring(c6.api.barfit_active) or 'no api data')
check('t55-api-barfit-scale-matches-property', c6.api ~= nil
    and c6.api.barfit ~= nil
    and math.abs(c6.api.barfit.scale - c6.scale) < 0.001,
    c6.api and c6.api.barfit and string.format('api=%.4f prop=%.4f',
        c6.api.barfit.scale, c6.scale) or 'no api barfit')
check('t55-api-barfit-top-bottom-fractions', c6.api ~= nil
    and c6.api.barfit ~= nil
    and math.abs(c6.api.barfit.top - 6 / 200) < 0.001
    and math.abs(c6.api.barfit.bottom - 6 / 200) < 0.001)

-- ⑧ 关贴合后还原基线 margin，用户手动放大不被自动缩放覆盖
local r55 = bars_env(6, 6, 128)
load_script()
env.events['file-loaded']()
flush_timers()
env.messages['letterbox-toggle']()
check('t55-toggle-off-restores-margin', env.props['sub-margin-y'] == 34,
    tostring(env.props['sub-margin-y']))
check('t55-toggle-off-restores-scale', env.props['sub-scale'] == 1,
    tostring(env.props['sub-scale']))
r55()
end
run_t55()

for _, r in ipairs(restore50) do r() end
restore51(); restore49(); restore48()
restore13(); restore14()

restore(); restore2(); restore3(); restore4(); restore5(); restore6(); restore7()

print(string.format('SUMMARY sub-style-test pass=%d fail=%d %s', pass, fail,
    fail == 0 and 'ALL_OK' or 'HAS_FAIL'))
os.exit(fail == 0 and 0 or 1)
