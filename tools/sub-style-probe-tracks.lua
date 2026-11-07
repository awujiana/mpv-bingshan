-- sub-style-probe-tracks.lua —— v1.0.12 多内封 ASS 轨 / 多样式表真机探针
--
-- 由 tools/sub-style-e2e.py 第 5i / 5j 组编排：
--   mpv --script=<本文件> --vo=gpu --pause=yes --image-display-duration=inf
--       <tools/sub-style-mkv-fixture.py 生成的多场景 MKV>
--   SUBSTYLE_TRACKS_MODE=switch  三条内封 ASS 轨（PlayResY / Default.Fontsize
--                                各不相同），逐轨切换验证字号自动匹配
--   SUBSTYLE_TRACKS_MODE=styles  单轨 + 多 Style（Default=20 / Sign=60）+
--                                带 \N 的多行对白 + 上下黑边，验证字号基准
--                                只取最下行对白、不被大标题样式拉偏
--
-- 为什么必须有这一组：写进 sub-ass-style-overrides 的 Fontsize= / PlayResY=
-- 是按当前轨 ASS 头算出的**绝对值**；单测桩是手动 fire_prop 模拟切轨的，
-- 无法证明真实 mpv 切 sid 时 sub-ass-extradata 会变、脚本的补读与重算链路
-- 会跑。v1.0.12 真机诊断实测三轨：
--   A PlayResY=360 Default=20 → Fontsize=17.0221 PlayResY_ov=340.443
--   B PlayResY=720 Default=48 → Fontsize=34.0443 PlayResY_ov=680.885
--   C PlayResY=240 Default=14 → Fontsize=11.3481 PlayResY_ov=226.962
--   三者 Fontsize/PlayResY 恒为 0.05，即物理字号一致。
--
-- 判据：归一化物理字号 = Fontsize覆盖 / 生效PlayResY（覆盖值优先，否则原始
-- PlayResY）。切轨前后该值必须一致；同时 Fontsize 绝对值必须真的变了，
-- 证明确实重算过而不是照抄旧值；切回原轨还要能还原。
--
-- ⚠ 夹具是 MJPEG 单帧 + 内封 ASS，真机实测 mpv 不暴露 sub-text / sub-text-ass
-- （不带主脚本也一样，见架构文档 §20.5）。因此多行对白盒高由单测 T58 覆盖，
-- 这里只把两种文本属性的实测值打进日志作诊断，不作为判据。探针自行 quit。

local MODE = os.getenv('SUBSTYLE_TRACKS_MODE') or 'switch'
local SETTLE = 1.5
local PREFIX = 'script-message-to uosc_subtitle_style '
local BASE_UNITS = 20

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

local function snapshot()
    local extra = mp.get_property('sub-ass-extradata') or ''
    local pry = tonumber(extra:match('PlayResY%s*:%s*(%d+%.?%d*)'))
    local default_fs, sign_fs
    for line in extra:gmatch('[^\r\n]+') do
        local name, fs = line:match(
            '^%s*Style%s*:%s*([^,]-),%s*[^,]-,%s*(%d+%.?%d*)')
        if name and name:lower() == 'default' then default_fs = tonumber(fs) end
        if name and name:lower() == 'sign' then sign_fs = tonumber(fs) end
    end
    local ov = mp.get_property('sub-ass-style-overrides') or ''
    local font_ov = tonumber(ov:match('Fontsize=([%d%.]+)'))
    local pry_ov = tonumber(ov:match('PlayResY=([%d%.]+)'))
    local eff_pry = pry_ov or pry
    local physical = (font_ov and eff_pry and eff_pry > 0)
        and (font_ov / eff_pry) or nil
    return {
        pry = pry, default_fs = default_fs, sign_fs = sign_fs,
        font_ov = font_ov, pry_ov = pry_ov, physical = physical,
        sid = mp.get_property_number('sid', 0),
    }
end

local function desc(s)
    return string.format(
        'sid=%s PlayResY=%s Default=%s Sign=%s Fontsize=%s PlayResY_ov=%s phys=%s',
        tostring(s.sid), tostring(s.pry), tostring(s.default_fs),
        tostring(s.sign_fs), tostring(s.font_ov), tostring(s.pry_ov),
        s.physical and string.format('%.6f', s.physical) or 'nil')
end

local function sub_ids()
    local ids = {}
    for _, t in ipairs(mp.get_property_native('track-list') or {}) do
        if t.type == 'sub' and t.id then ids[#ids + 1] = t.id end
    end
    table.sort(ids)
    return ids
end

local function close(a, b, tol)
    return a ~= nil and b ~= nil
        and math.abs(a - b) <= tol * math.max(math.abs(b), 1e-9)
end

local function phys(s)
    return s.physical and string.format('%.6f', s.physical) or 'nil'
end

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.commandv('quit')
end

local function diag_text()
    print(string.format('TR-DIAG sub-text=[%s] sub-text-ass=[%s]',
        tostring(mp.get_property('sub-text')),
        tostring(mp.get_property('sub-text-ass'))))
end

-- 5i：三条内封轨逐轨切换，物理字号必须恒定，绝对覆盖值必须逐轨重算。
local function run_switch()
    local ids = sub_ids()
    local joined = {}
    for _, id in ipairs(ids) do joined[#joined + 1] = tostring(id) end
    record('tr-three-internal-sub-tracks', #ids >= 3,
        'sub ids=' .. table.concat(joined, ','))
    if #ids < 3 then finish() return end
    -- 人为设一个非 1 缩放，保证即使某轨黑边检测没触发也一定写出 Fontsize
    cmd('scale 1.5')
    local snaps, tags = {}, {'a', 'b', 'c'}
    local visit
    visit = function(i)
        if i > 3 then
            local all_ok = true
            for j = 2, 3 do
                if not close(snaps[1].physical, snaps[j].physical, 0.02) then
                    all_ok = false
                end
            end
            record('tr-all-tracks-physical-size-constant', all_ok,
                string.format('A=%s B=%s C=%s', phys(snaps[1]),
                    phys(snaps[2]), phys(snaps[3])))
            mp.commandv('set', 'sid', tostring(ids[1]))
            after(SETTLE, function()
                local c = snapshot()
                record('tr-track-a-restored',
                    close(snaps[1].physical, c.physical, 0.02)
                    and close(snaps[1].font_ov, c.font_ov, 0.02),
                    string.format('A[%s] A2[%s]', desc(snaps[1]), desc(c)))
                diag_text()
                finish()
            end)
            return
        end
        local s = snapshot()
        snaps[i] = s
        local tag = tags[i]
        record('tr-track-' .. tag .. '-header-readable',
            s.pry ~= nil and s.default_fs ~= nil, desc(s))
        record('tr-track-' .. tag .. '-writes-fontsize',
            s.font_ov ~= nil, desc(s))
        if i > 1 then
            local p = snaps[i - 1]
            -- 头必须真的换了，否则下面的比较只是自证
            record('tr-track-' .. tag .. '-header-changed',
                s.pry ~= p.pry or s.default_fs ~= p.default_fs,
                string.format('prev[%s] now[%s]', desc(p), desc(s)))
            record('tr-track-' .. tag .. '-fontsize-recomputed',
                s.font_ov ~= nil and p.font_ov ~= nil
                and math.abs(s.font_ov - p.font_ov) > 0.5,
                string.format('prev Fontsize=%s now=%s',
                    tostring(p.font_ov), tostring(s.font_ov)))
            record('tr-track-' .. tag .. '-physical-size-matches',
                close(p.physical, s.physical, 0.02),
                string.format('prev=%s now=%s', phys(p), phys(s)))
        end
        if i < 3 then
            mp.commandv('set', 'sid', tostring(ids[i + 1]))
            after(SETTLE, function() visit(i + 1) end)
        else
            visit(i + 1)
        end
    end
    after(SETTLE, function() visit(1) end)
end

-- 5j：多样式表下字号基准只取最下行对白（Default），不被 Sign=60 拉偏。
-- 期望：unit = 20×1.2×(360/360) = 24；usable = 360×(24/360)×0.9 = 21.6
--       scale = 0.9；ratio ≈ 1.0574 ⇒ Fontsize ≈ 17.02。
-- 若误用 max_fontsize=60：scale = 0.3 ⇒ Fontsize ≈ 5.67。
local function run_styles()
    local s = snapshot()
    record('tr-multi-style-header',
        s.default_fs == BASE_UNITS and s.sign_fs ~= nil
        and s.sign_fs > BASE_UNITS * 2, desc(s))
    record('tr-multi-style-fontsize-uses-base',
        s.font_ov ~= nil and math.abs(s.font_ov - 17.02) < 1.2, desc(s))
    record('tr-multi-style-not-skewed-by-sign',
        s.font_ov ~= nil and s.font_ov > 10, desc(s))
    record('tr-multi-style-playres-written',
        s.pry_ov ~= nil and s.pry ~= nil and s.pry_ov < s.pry, desc(s))
    diag_text()
    finish()
end

mp.register_event('file-loaded', function()
    -- 等自动检测 / 黑边贴合链落定（与 5g 探针一致的 4.5s）
    after(4.5, function()
        if MODE == 'styles' then run_styles() else run_switch() end
    end)
end)
