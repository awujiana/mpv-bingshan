-- sub-style-probe-api.lua —— uosc_subtitle_style 对外 API 真机探针
--
-- 由 tools/sub-style-e2e.py 第 ⑨ 组加载：
--   mpv --script=<本文件> --vo=gpu --pause=yes --image-display-duration=inf <MKV>
--
-- 验证两条通道在**真实 mpv** 下都通：
--   ① user-data/uosc_subtitle_style/version + /state 可读、state 是合法 JSON；
--   ② script-message-to uosc_subtitle_style api ... 的回复能被另一个脚本收到，
--      request_id 原样回填，call 白名单动作真的改变状态并刷新广播。
-- 不依赖字幕像素，只验证 API 契约；输出 PROBE PASS/FAIL + PROBE SUMMARY 后 quit。

local mp = require('mp')
local utils = require('mp.utils')

local PREFIX = 'uosc_subtitle_style'
local RESP = PREFIX .. '-api-response'
local STATE_KEY = 'user-data/' .. PREFIX .. '/state'
local VERSION_KEY = 'user-data/' .. PREFIX .. '/version'
-- 同一 mpv 实例里也加载了 uosc_staff_credits（submodule），顺带验它的 API。
local STAFF_PREFIX = 'uosc_staff_credits'
local STAFF_RESP = STAFF_PREFIX .. '-api-response'
local STAFF_STATE_KEY = 'user-data/' .. STAFF_PREFIX .. '/state'
local STAFF_VERSION_KEY = 'user-data/' .. STAFF_PREFIX .. '/version'
local SELF = mp.get_script_name() or 'sub-style-probe-api'

local pass, fail = 0, 0
local failures = {}
local replies = {}

local function record(name, ok, detail)
    if ok then pass = pass + 1 else
        fail = fail + 1
        failures[#failures + 1] = name
    end
    print(string.format('PROBE %s %s%s', ok and 'PASS' or 'FAIL', name,
        detail and (' | ' .. tostring(detail)) or ''))
end

local function after(sec, fn) mp.add_timeout(sec, fn) end

local function send_to(target, action, rid, ...)
    local cmd = {'script-message-to', target, 'api', SELF, rid, action}
    for _, v in ipairs({...}) do cmd[#cmd + 1] = tostring(v) end
    mp.command_native(cmd)
end
local function send(action, rid, ...)
    return send_to(PREFIX, action, rid, ...)
end

-- ⚠ user-data 是 node 属性：mp.get_property('...') 返回带引号的 JSON 表示
--   （version 会变成 "1.0.0"、state 会被二次转义），必须读 native。
local function state_json()
    local raw = mp.get_property_native(STATE_KEY)
    if type(raw) ~= 'string' or raw == '' then return nil, 'empty' end
    local ok, v = pcall(utils.parse_json, raw)
    if not ok or type(v) ~= 'table' then return nil, 'parse_failed' end
    return v
end

-- 订阅通道：observe_property 同样要用 native，否则拿到的是 JSON 文本而非 Lua string。
local observed_raw = nil
mp.observe_property(STATE_KEY, 'native', function(_, v)
    if type(v) == 'string' then observed_raw = v end
end)

local function last_reply(rid)
    for i = #replies, 1, -1 do
        if replies[i].rid == rid then return replies[i] end
    end
    return nil
end

local function response_handler(rid, json)
    local ok, v = pcall(utils.parse_json, json)
    replies[#replies + 1] = {rid = rid, ok = ok, body = ok and v or nil,
                             raw = tostring(json):sub(1, 160)}
    print(string.format('API RESPONSE rid=%s ok=%s json=%s', tostring(rid),
        tostring(ok), tostring(json):sub(1, 160)))
end
mp.register_script_message(RESP, response_handler)
mp.register_script_message(STAFF_RESP, response_handler)

local function finish()
    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
    mp.commandv('quit')
end

mp.register_event('file-loaded', function()
    -- 等脚本加载完并发布初始状态（真实配置里还有其它脚本，给足 2s）
    after(2.0, function()
        ---------------------------------------------------------------- ① user-data
        local ver = mp.get_property_native(VERSION_KEY)
        record('api-userdata-version', ver == '1.0.0', 'version=' .. tostring(ver))
        record('api-userdata-version-is-native-string', type(ver) == 'string')
        local st, err = state_json()
        record('api-userdata-state-json', st ~= nil, 'err=' .. tostring(err))
        record('api-userdata-state-fields', st ~= nil
            and st.api_version == '1.0.0'
            and type(st.main) == 'table' and type(st.sec) == 'table'
            and type(st.runtime) == 'table',
            'target=' .. tostring(st and st.target))

        ------------------------------------------------- ①b staff_credits user-data
        local st_ver = mp.get_property_native(STAFF_VERSION_KEY)
        record('staff-api-userdata-version', st_ver == '1.0.0',
            'version=' .. tostring(st_ver))
        local st_raw = mp.get_property_native(STAFF_STATE_KEY)
        local ok_sst, sst = false, nil
        if type(st_raw) == 'string' then ok_sst, sst = pcall(utils.parse_json, st_raw) end
        record('staff-api-userdata-state-json', ok_sst and type(sst) == 'table',
            'len=' .. (type(st_raw) == 'string' and #st_raw or 0))
        record('staff-api-state-fields', ok_sst and type(sst) == 'table'
            and sst.api_version == '1.0.0' and type(sst.features) == 'table'
            and sst.ready == true,
            'script=' .. tostring(sst and sst.script_name))
        record('staff-api-no-token-leak', type(st_raw) == 'string'
            and not st_raw:find('token', 1, true))
        send_to(STAFF_PREFIX, 'get-state', 's1')
        send_to(STAFF_PREFIX, 'list-actions', 's2')

        ---------------------------------------------------------------- ② get-state
        send('get-state', 'r1')
        after(0.6, function()
            local sr = last_reply('s1')
            record('staff-api-get-state-reply', sr ~= nil and sr.ok
                and sr.body ~= nil and sr.body.ok == true,
                sr and sr.raw or 'no reply')
            record('staff-api-get-state-request-id', sr ~= nil
                and sr.body ~= nil and sr.body.request_id == 's1')
            local sr2 = last_reply('s2')
            record('staff-api-list-actions', sr2 ~= nil and sr2.body ~= nil
                and sr2.body.ok == true and type(sr2.body.actions) == 'table'
                and #sr2.body.actions > 0,
                'n=' .. tostring(sr2 and sr2.body and sr2.body.actions and #sr2.body.actions))
            local r = last_reply('r1')
            record('api-get-state-reply', r ~= nil and r.ok
                and r.body ~= nil and r.body.ok == true,
                r and r.raw or 'no reply')
            record('api-get-state-request-id', r ~= nil and r.body ~= nil
                and r.body.request_id == 'r1')
            record('api-get-state-has-data', r ~= nil and r.body ~= nil
                and type(r.body.data) == 'table'
                and r.body.data.api_version == '1.0.0')

            ------------------------------------------------------------ ③ get
            send('get', 'r2', 'main.pos')
            after(0.6, function()
                local r2 = last_reply('r2')
                record('api-get-dotted-key', r2 ~= nil and r2.body ~= nil
                    and r2.body.ok == true and type(r2.body.value) == 'number',
                    r2 and r2.raw or 'no reply')
                local pos0 = r2 and r2.body and r2.body.value or nil

                send('get', 'r3', 'no.such.key')
                after(0.5, function()
                    local r3 = last_reply('r3')
                    record('api-get-unknown-key', r3 ~= nil and r3.body ~= nil
                        and r3.body.ok == false
                        and r3.body.error == 'unknown_key')

                    ---------------------------------------------------- ④ call
                    send('call', 'r4', 'nudge', '-5')
                    after(1.2, function()
                        local r4 = last_reply('r4')
                        record('api-call-dispatch', r4 ~= nil and r4.body ~= nil
                            and r4.body.ok == true
                            and r4.body.dispatched == 'nudge'
                            and r4.body.async == true,
                            r4 and r4.raw or 'no reply')
                        -- 真机关键判据：call 是异步派发，但动作必须真的生效，
                        -- 且 user-data 广播要同步刷新（单测桩里转发不执行，测不到）。
                        local st2 = state_json()
                        local pos1 = st2 and st2.main and st2.main.pos or nil
                        record('api-call-changes-state-broadcast',
                            type(pos0) == 'number' and type(pos1) == 'number'
                            and math.abs((pos0 - pos1) - 5) < 0.001,
                            string.format('pos %s -> %s', tostring(pos0), tostring(pos1)))
                        record('api-property-pos-matches-broadcast',
                            type(pos1) == 'number'
                            and math.abs(mp.get_property_number('sub-pos', -999) - pos1) < 0.001,
                            'sub-pos=' .. tostring(mp.get_property_number('sub-pos', -999)))
                        -- 订阅通道（native observer）也要收到刷新后的可解析 JSON
                        local ok_obs, obs = false, nil
                        if type(observed_raw) == 'string' then
                            ok_obs, obs = pcall(utils.parse_json, observed_raw)
                        end
                        record('api-subscribe-native-observer', ok_obs
                            and type(obs) == 'table' and obs.main ~= nil,
                            'raw_len=' .. (observed_raw and #observed_raw or 0))

                        send('call', 'r5', 'api')
                        after(0.5, function()
                            local r5 = last_reply('r5')
                            record('api-call-rejects-recursive', r5 ~= nil
                                and r5.body ~= nil and r5.body.ok == false
                                and r5.body.error == 'action_not_allowed')
                            finish()
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
