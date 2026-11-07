-- sub-style-probe-reinspect.lua —— v1.0.13「切轨 / 换片必须重新检测」真机探针
--
-- 由 tools/sub-style-e2e.py 第 5k / 5l 组编排：
--   SUBSTYLE_REINSPECT_MODE=tracks  内封 ASS + 两条外挂 ASS（彩色 / 标准白字）
--       逐轨切换，读 user-data/uosc_subtitle_style/state 的 report_shown 与
--       main.auto / main.color，证明每次切换都真的重跑了检测：
--         彩色 → 套黑白预设(auto=true)；标准白字 → 清掉自动样式；
--         切回彩色 / 切到内封 / 再从内封切回，都不许残留上一轨的样式。
--   SUBSTYLE_REINSPECT_MODE=files   有黑边 MKV → loadfile 无黑边 MKV，
--       验证 end-file 清掉 sub-ass-style-overrides 里的 PlayResY / Fontsize
--       绝对覆盖，新文件 barfit 关闭、边距 / 字号回到基线。
--
-- 为什么必须真机：单测桩是手动 fire_prop 模拟 sid 变化，且 sub-text 恒定可用；
-- 真实 mpv 的 sid 观察器触发时机、解码器级 overrides 列表何时被读到、
-- 图片型视频 + 内封 ASS 的 sub-text=nil 边界，都只能在真机上验证。
--
-- ⚠ 图片型 MJPEG + 内封 ASS 夹具下 mpv 不暴露 sub-text（不带主脚本也一样，
--   见架构文档 §20.5），所以「切到内封轨」这一步不拿 report_shown 作判据，
--   只验证自动预设已被清除；该轨的重新检测放行由单测 T52 / T59b 覆盖。
-- 探针自行 quit。

local utils = require 'mp.utils'
local MODE = os.getenv('SUBSTYLE_REINSPECT_MODE') or 'tracks'
local NOBARS = os.getenv('SUBSTYLE_NOBARS_MKV') or ''
local SETTLE = 3.0
local STATE_KEY = 'user-data/uosc_subtitle_style/state'

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

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.commandv('quit')
end

-- ⚠ user-data 是 node 属性：mp.get_property 会返回带引号的 JSON 文本，
--   必须读 native（与 sub-style-probe-api.lua 一致）。
local function api_state()
    local raw = mp.get_property_native(STATE_KEY)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, v = pcall(utils.parse_json, raw)
    return (ok and type(v) == 'table') and v or nil
end

local function shown_count(a)
    return a and a.runtime and tonumber(a.runtime.report_shown) or 0
end

local function main_of(a)
    return a and a.main or {}
end

local function ov_num(key)
    for _, e in ipairs(mp.get_property_native('sub-ass-style-overrides') or {}) do
        local v = tostring(e):match('^' .. key .. '=([%d%.]+)')
        if v then return tonumber(v) end
    end
    return nil
end

local function ov_desc()
    local parts = {}
    for _, e in ipairs(mp.get_property_native('sub-ass-style-overrides') or {}) do
        parts[#parts + 1] = tostring(e)
    end
    return '[' .. table.concat(parts, ',') .. ']'
end

local function sub_tracks()
    local out = {}
    for _, t in ipairs(mp.get_property_native('track-list') or {}) do
        if t.type == 'sub' and t.id then
            out[#out + 1] = {
                id = t.id,
                external = t.external and true or false,
                base = (tostring(t['external-filename'] or '')):match('([^/\\]+)$') or '',
            }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function state_desc(a)
    local m = main_of(a)
    return string.format('shown=%s auto=%s color=%s barfit=%s ratio=%s overrides=%s',
        tostring(shown_count(a)), tostring(m.auto), tostring(m.color),
        tostring(a and a.barfit_active), tostring(a and a.ass_y_ratio), ov_desc())
end

--------------------------------------------------------------------
-- 5k：切换内封 / 外挂轨，切过去与切回来都要重新检测
--------------------------------------------------------------------
local function run_tracks()
    local ts = sub_tracks()
    local colored, white, internal
    for _, t in ipairs(ts) do
        if t.external and t.base == 'sub-style-smoke-colored.ass' then colored = t.id end
        if t.external and t.base == 'sub-style-smoke.ass' then white = t.id end
        if not t.external and not internal then internal = t.id end
    end
    record('ri-three-sub-tracks', colored ~= nil and white ~= nil and internal ~= nil,
        string.format('colored=%s white=%s internal=%s', tostring(colored),
            tostring(white), tostring(internal)))
    -- v1.0.13：逐轨检查进度从左上角 OSD 挪到 API state.internal_tracks。
    -- 真机上也必须能读到，且字段要能随当前轨变化。
    local a0 = api_state()
    local it0 = a0 and a0.internal_tracks
    record('ri-api-internal-tracks-field',
        type(it0) == 'table' and it0.total == 1
        and it0.checked ~= nil and type(it0.pending) == 'table',
        type(it0) == 'table' and string.format('total=%s checked=%s',
            tostring(it0.total), tostring(it0.checked)) or 'missing')
    if not (colored and white and internal) then finish() return end

    local steps = {
        {sid = colored, name = 'ri-colored-first', check = function(a, n0, n)
             record('ri-colored-first-reinspected', n >= 1,
                 'report_shown=' .. tostring(n))
             record('ri-colored-first-applies-preset',
                 main_of(a).auto == true and main_of(a).color == '#FFFFFF',
                 state_desc(a))
             record('ri-api-current-track-is-external',
                 a ~= nil and type(a.internal_tracks) == 'table'
                 and a.internal_tracks.current_is_internal == false,
                 tostring(a and a.internal_tracks
                     and a.internal_tracks.current_is_internal))
         end},
        {sid = white, name = 'ri-switch-to-white', check = function(a, n0, n)
             record('ri-switch-to-white-reinspected', n > n0,
                 'report_shown ' .. tostring(n0) .. ' -> ' .. tostring(n))
             record('ri-switch-to-white-clears-auto-style',
                 main_of(a).auto == false and main_of(a).color == nil,
                 state_desc(a))
         end},
        {sid = colored, name = 'ri-switch-back-colored', check = function(a, n0, n)
             record('ri-switch-back-colored-reinspected', n > n0,
                 'report_shown ' .. tostring(n0) .. ' -> ' .. tostring(n))
             record('ri-switch-back-colored-reapplies',
                 main_of(a).auto == true and main_of(a).color == '#FFFFFF',
                 state_desc(a))
         end},
        -- 内封轨：sub-text 恒 nil，采样不成功 ⇒ 不拿 report_shown 作判据
        {sid = internal, name = 'ri-switch-to-internal', check = function(a)
             record('ri-switch-to-internal-clears-auto-style',
                 main_of(a).auto == false and main_of(a).color == nil,
                 state_desc(a))
         end},
        {sid = colored, name = 'ri-internal-back-to-colored', check = function(a, n0, n)
             record('ri-internal-back-to-colored-reinspected', n > n0,
                 'report_shown ' .. tostring(n0) .. ' -> ' .. tostring(n))
             record('ri-internal-back-to-colored-reapplies',
                 main_of(a).auto == true and main_of(a).color == '#FFFFFF',
                 state_desc(a))
         end},
    }

    local i, prev_shown = 1, 0
    local step
    step = function()
        if i > #steps then finish() return end
        local st = steps[i]
        mp.commandv('set', 'sid', tostring(st.sid))
        after(SETTLE, function()
            local a = api_state()
            local n = shown_count(a)
            st.check(a, prev_shown, n)
            prev_shown = n
            i = i + 1
            step()
        end)
    end
    after(2.0, step)   -- 等主脚本 file-loaded 首检链落定（inspect_delay=1.2s）
end

--------------------------------------------------------------------
-- 5l：有黑边 → end-file → 无黑边，黑边位移 / 限缩字号不得残留
--------------------------------------------------------------------
local function run_files()
    local base_margin = mp.get_property_number('sub-margin-y', 22)
    local base_fontsize = mp.get_property_number('sub-font-size', 38)
    local loaded, checked_end = 0, false

    mp.register_event('end-file', function()
        -- 稍等一拍：保证主脚本的 end-file 清理已跑完（脚本加载顺序不定）
        after(0.1, function()
            if checked_end then return end
            checked_end = true
            record('ri-end-file-clears-ass-overrides',
                ov_num('PlayResY') == nil and ov_num('Fontsize') == nil,
                'overrides=' .. ov_desc())
        end)
    end)

    mp.register_event('file-loaded', function()
        loaded = loaded + 1
        if loaded == 1 then
            after(SETTLE, function()
                local a = api_state()
                record('ri-first-barfit-active',
                    a ~= nil and a.barfit_active == true, state_desc(a))
                record('ri-first-playres-written', ov_num('PlayResY') ~= nil,
                    'overrides=' .. ov_desc())
                mp.commandv('loadfile', NOBARS, 'replace')
            end)
        else
            after(SETTLE, function()
                local a = api_state()
                record('ri-second-barfit-cleared',
                    a ~= nil and a.barfit_active == false, state_desc(a))
                record('ri-second-no-playres-shift',
                    ov_num('PlayResY') == nil and ov_num('Fontsize') == nil,
                    'overrides=' .. ov_desc())
                local margin = mp.get_property_number('sub-margin-y', -1)
                record('ri-second-margin-restored',
                    math.abs(margin - base_margin) < 0.01,
                    string.format('base=%s now=%s', tostring(base_margin),
                        tostring(margin)))
                local fs = mp.get_property_number('sub-font-size', -1)
                record('ri-second-fontsize-baseline',
                    math.abs(fs - base_fontsize) < 0.01,
                    string.format('base=%s now=%s', tostring(base_fontsize),
                        tostring(fs)))
                record('ri-second-ratio-neutral',
                    a ~= nil and a.ass_y_ratio ~= nil
                    and math.abs(a.ass_y_ratio - 1) < 0.001,
                    'ratio=' .. tostring(a and a.ass_y_ratio))
                finish()
            end)
        end
    end)
end

if MODE == 'files' then
    run_files()
else
    -- ⚠ 脚本加载时 track-list 还没有任何字幕轨（外部 --sub-file 也尚未挂上），
    --   必须等 file-loaded 才能枚举；早期版本在脚本顶层直接跑，得到三条全 nil。
    mp.register_event('file-loaded', function()
        after(0.2, run_tracks)
    end)
end
