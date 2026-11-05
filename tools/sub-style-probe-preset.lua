-- sub-style-probe-preset.lua —— 预设样式自动套用真机探针
-- 加载方式：mpv --script=<本文件> --sub-file=<fixture> ...（独立 VM）
-- 时序：file-loaded +1.0s 截「报告前」图（run_inspect 尚未触发，inspect_delay=1.2）
--       file-loaded +3.2s 截「报告后」图（报告显示 6s，套用+重建均已完成）
-- 断言：自动套用结果（override/描边粗细/主色）+ 两张截图已落盘。
-- 输出：PROBE PASS/FAIL <用例> <细节>，最后汇总退出。
-- 依赖环境变量 SUBSTYLE_SMOKE_DIR 指定截图输出目录（缺省用 TEMP）。

local SMOKE_DIR = os.getenv('SUBSTYLE_SMOKE_DIR') or (os.getenv('TEMP') or '.')
SMOKE_DIR = SMOKE_DIR:gsub('\\$', '')

-- 期望行为由用例方（E2E）在解析日志后判定；探针只如实汇报关键属性。
-- SUBSTYLE_PRESET_EXPECT = applied | kept | kept-dual —— 告诉探针该 fixture 的预期
--   kept-dual：彩色但带次字幕轨（双语）⇒ 双轨跳过逻辑生效，同样保持原样。
--   与 kept 的属性判据相同，仅用例名不同（E2E 侧区分断言）。
local EXPECT = os.getenv('SUBSTYLE_PRESET_EXPECT') or 'applied'
-- SUBSTYLE_PRESET_COLOR = 期望的主色（applied 时；缺省出厂预设 #FFFFFF）
local EXPECT_COLOR = os.getenv('SUBSTYLE_PRESET_COLOR') or '#FFFFFF'
-- SUBSTYLE_PRESET_OUTLINE = 期望的描边粗细（applied 时；缺省出厂预设 2）
local EXPECT_OUTLINE = tonumber(os.getenv('SUBSTYLE_PRESET_OUTLINE') or '2') or 2
-- 截图 tag 前缀：多用例共用同一截图目录时必须区分，否则互相覆盖
local TAG = os.getenv('SUBSTYLE_PRESET_TAG') or 'preset'

-- 「未套用」的描边判据不能硬编码 0.5——那是用户 mpv.conf 的 sub-outline-size，
-- 换台没有该配置的机器就是另一个值（实测仓库模式 mpv 默认 1.65）。
-- 探针先于被测脚本加载（--script 早于 config-dir 脚本），此刻属性还是原生值，
-- 捕获为基线；断言「预设未写入」= 与该基线一致。
local BASELINE_OUTLINE = mp.get_property_number('sub-outline-size', -1)

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

local function num(name)
    return mp.get_property_number(name, -1e9)
end

local function str(name)
    return mp.get_property(name)
end

local function after(sec, fn)
    mp.add_timeout(sec, function() fn() end)
end

-- 截图：模板名别带 .png；先清 show-text OSD 会误伤本用例要抓的「左上角报告」，
-- 因此这里**不清** OSD（报告正是被测对象，用 subtitles+osd 一并截取）。
local function shoot(tag)
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

-- 属性序列化为 #AARRGGBB（如 #FFFFFF → #FFFFFFFF），用包含匹配
local function has_color(name, hex)
    local v = tostring(str(name) or ''):lower()
    local want = hex:lower():gsub('^#', '')
    return v:find(want, 1, true) ~= nil
end

mp.register_event('file-loaded', function()
    if phase == 0 then
        phase = 1
        -- 报告前：run_inspect（inspect_delay=1.2s）还没跑
        after(1.0, function()
            shoot(TAG .. '-early')
            after(0.4, function()
                record('early-shot', shot_saved(TAG .. '-early'))
                -- 报告后：报告显示 6s 窗口内，套用 + override 重建均完成
                after(1.8, function()
                    shoot(TAG .. '-late')
                    after(0.4, function()
                        record('late-shot', shot_saved(TAG .. '-late'))
                        -- 防真空：双语用例必须确认次字幕轨真的加载了，
                        -- 否则「没套用」可能只是 secondary-sid 没生效（静默通过）
                        if EXPECT == 'kept-dual' then
                            local sub2 = mp.get_property_native('current-tracks/sub2')
                            record('dual-track-present',
                                type(sub2) == 'table' and sub2.id ~= nil,
                                'sub2=' .. tostring(sub2 and sub2.id))
                        end
                        if EXPECT == 'applied' then
                            record('preset-auto-applied',
                                str('sub-ass-override') == 'force'
                                and math.abs(num('sub-outline-size') - EXPECT_OUTLINE) < 0.01
                                and has_color('sub-color', EXPECT_COLOR),
                                string.format('override=%s outline=%s color=%s',
                                    tostring(str('sub-ass-override')),
                                    tostring(num('sub-outline-size')),
                                    tostring(str('sub-color'))))
                        else
                            -- kept / kept-dual：不套用 —— override 保持 mpv 默认 scale，
                            -- 描边粗细保持加载时基线（预设是 2，未被写入）
                            local kname = EXPECT == 'kept-dual'
                                and 'preset-kept-dual' or 'preset-kept-original'
                            record(kname,
                                str('sub-ass-override') == 'scale'
                                and BASELINE_OUTLINE >= 0
                                and math.abs(num('sub-outline-size') - BASELINE_OUTLINE) < 0.001,
                                string.format('override=%s outline=%s (baseline=%s)',
                                    tostring(str('sub-ass-override')),
                                    tostring(num('sub-outline-size')),
                                    tostring(BASELINE_OUTLINE)))
                        end
                        finish()
                    end)
                end)
            end)
        end)
    end
end)

print('PROBE driver(preset) loaded, expect=' .. EXPECT
    .. ' color=' .. EXPECT_COLOR .. ' outline=' .. tostring(EXPECT_OUTLINE))
