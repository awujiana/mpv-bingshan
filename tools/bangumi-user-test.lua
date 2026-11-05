-- tools/bangumi-user-test.lua —— apis/bangumi_user 回归测试
--
-- 用法（任意 cwd 均可 —— 路径基准由脚本自身位置推导）：
--   ./luajit.exe portable_config/tools/bangumi-user-test.lua
--
-- 为什么需要它（2026-10-06）：
--   这个模块要拿 token 去改用户的 Bangumi 收藏，错了会**悄悄写坏用户数据**，
--   而且它全是网络调用，肉眼根本看不出对错。写的时候我按记忆里的旧文档，
--   把两个端点的方法写反了：
--       · `.../collections/{id}/episodes`   我写 POST  → 实际只有 get/patch
--       · `.../-/episodes/{episode_id}`     我写 PATCH → 实际只有 get/put
--   又因为 curl 没加 --fail，405 的响应体不是 ErrorDetail，会被报成
--   「json 解析失败」—— 报错信息完全指向别处，极难定位。
--   还有第三个坑：**写操作成功返回 204 无响应体**，而模块把空体一律当失败，
--   于是「写成功了却报错」。三个坑都是靠 open-api/v0.yaml 逐条核对才发现的。
--   所以这里把「方法 + 空体策略 + 错误体识别 + 编排 + 脱敏」全部固化成断言。
--
-- 设计要点（三条，都是为了让测试**真跑**而不是走过场）：
--   1. 回调**延迟执行**：桩只把任务入队，由 flush() 事后触发。
--      若在 command_native_async 里同步回调，回调会早于
--      `registered_token = register(...)` 执行 —— 恰好掩盖掉第 8 节要测的
--      「闭包捕获全局」缺陷，测试就白写了。
--   2. JSON 用**真编解码器**而非夹具查表：查表式桩一旦与真实报文漂移，
--      测试会静静地测错东西。编解码器本身也先跑一轮自检（第 0 节）。
--   3. 参数直接改**模块持有的 opts/deps 表**：make_init 有「单次初始化保护」，
--      第二次 init 会被跳过 —— 若靠反复 init 切参数，后面所有用例都会
--      悄悄沿用第一组参数（典型的「测试静静测错东西」）。

-- ============================================================================
-- stub mp（含延迟回调 + 调用捕获）
-- ============================================================================
local pending = {}      -- 待触发回调队列
local calls = {}        -- 每次请求的 args 快照
local next_res = nil    -- 下一次请求要返回的结果

package.preload["mp"] = function()
    return {
        get_property = function() return nil end,
        command_native_async = function(cfg, cb)
            calls[#calls + 1] = cfg.args
            pending[#pending + 1] = { cb = cb, res = next_res }
            return #calls          -- abort handle
        end,
        abort_async_command = function() end,
        msg = setmetatable({}, { __index = function() return function() end end }),
        get_time = function() return 0 end,
    }
end
package.preload["mp.msg"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end

-- ---- 极简 JSON 编解码（只覆盖本模块用到的形态）----
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function jstr(s)
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        local e = ESC[c]
        if not e and c:byte() < 32 then e = string.format("\\u%04x", c:byte()) end
        out[#out + 1] = e or c
    end
    return '"' .. table.concat(out) .. '"'
end

local function jenc(v)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return tostring(v)
    end
    if t == "string" then return jstr(v) end
    if t ~= "table" then return "null" end
    if #v > 0 then
        local parts = {}
        for i = 1, #v do parts[i] = jenc(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = jstr(k) .. ":" .. jenc(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function jdec(s)
    local pos = 1
    local function fail(m) error("JSON 解析失败 @" .. pos .. ": " .. m, 0) end
    local function ws()
        local _, e = s:find("^[ \t\r\n]*", pos)
        pos = e + 1
    end
    local function pstr()
        pos = pos + 1
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == "" then fail("字符串未闭合") end
            if c == '"' then pos = pos + 1 return table.concat(out) end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                if e == "u" then
                    local cp = tonumber(s:sub(pos + 2, pos + 5), 16)
                    if not cp then fail("坏的 \\u 转义") end
                    if cp < 0x80 then
                        out[#out + 1] = string.char(cp)
                    elseif cp < 0x800 then
                        out[#out + 1] = string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
                    else
                        out[#out + 1] = string.char(0xE0 + math.floor(cp / 4096),
                            0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
                    end
                    pos = pos + 6
                else
                    out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end
    local parse
    parse = function()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local obj = {}
            ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return obj end
            while true do
                ws()
                local k = pstr()
                ws()
                if s:sub(pos, pos) ~= ":" then fail("缺冒号") end
                pos = pos + 1
                obj[k] = parse()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return obj end
                if d ~= "," then fail("缺逗号") end
            end
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = parse()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return arr end
                if d ~= "," then fail("缺逗号") end
            end
        elseif c == '"' then
            return pstr()
        end
        local lit = s:match("^(%a+)", pos)
        if lit == "true" then pos = pos + 4 return true end
        if lit == "false" then pos = pos + 5 return false end
        if lit == "null" then pos = pos + 4 return nil end
        local num = s:match("^%-?%d+%.?%d*", pos)
        if not num then fail("无法识别的字面量") end
        pos = pos + #num
        return tonumber(num)
    end
    local v = parse()
    ws()
    if pos <= #s then fail("尾部有多余内容") end
    return v
end

-- mpv 的 mp.utils.parse_json 契约是「失败返回 nil，不抛异常」——
-- 桩必须照这个契约来，否则测试行为会与真机不一致。
local function safe_parse(s)
    local ok, v = pcall(jdec, s)
    if not ok then return nil end
    return v
end

package.preload["mp.utils"] = function()
    return {
        parse_json = safe_parse,
        format_json = jenc,
        join_path = function(a, b) return a .. "/" .. b end,
    }
end

-- ---- 路径基准：从脚本自身位置反推，使本测试与 cwd 无关 ----
-- 脚本位于 <mpv根>/portable_config/tools/，故上溯一级即 portable_config。
-- 为什么必须这么做：原先写死相对路径 "portable_config/..."，
-- 从 portable_config/ 里跑会**崩在 require 上**，而崩溃前 stdout 末尾恰好是
-- §0 自检的 [PASS] 行 —— 用 `tail` 看像全绿，实际 exit=1。这类「绿灯假象」
-- 比直接报错更难发现，索性让 cwd 不再成为变量。
local _src = debug.getinfo(1, "S").source or "@."
local _tools_dir = _src:match("^@(.*)[/\\][^/\\]*$") or "."
local _pc = _tools_dir:match("^(.*)[/\\][^/\\]*$") or "."
package.path = _pc .. "/scripts/uosc_staff_credits/?.lua;"
    .. _pc .. "/scripts/uosc_staff_credits/?/init.lua;" .. package.path

-- ============================================================================
-- 测试小工具
-- ============================================================================
local pass, fail = 0, 0
local function check(desc, got, want)
    if got == want then
        pass = pass + 1
        print(string.format("  [PASS] %s", desc))
    else
        fail = fail + 1
        print(string.format("  [FAIL] %s", desc))
        print(string.format("         得到 %s  期望 %s", tostring(got), tostring(want)))
    end
end

print(string.rep("-", 76))
print("== 0. 测试自带 JSON 编解码器的自检 ==")
-- 先证明工具本身可信，否则后面所有断言都可能被「解析器坏了」污染
check("解析对象", (jdec('{"id":1,"username":"alice"}')).id, 1)
check("解析空对象", type(jdec("{}")), "table")
check("解析数组字段", (jdec('{"episode_id":[1,2,8],"type":2}')).episode_id[3], 8)
check("解析 false", (jdec('{"private":false}')).private, false)
check("编码对象", jenc({ type = 3 }), '{"type":3}')
check("编码数组字段", jenc({ episode_id = { 1, 2, 8 }, type = 2 }),
    '{"episode_id":[1,2,8],"type":2}')
check("坏输入不抛异常、返回 nil（对齐 mpv 契约）", safe_parse("这不是 JSON"), nil)
check("空串返回 nil", safe_parse(""), nil)

-- 捕获模块持有的 opts/deps 表（make_init 有单次初始化保护，必须直接改表）
local ml = require("modules.utils.module_loader")
local captured = {}
local real_make_init = ml.make_init
ml.make_init = function(name, schema)
    local o, d, init = real_make_init(name, schema)
    if name == "bangumi_user" then captured.opts, captured.deps = o, d end
    return o, d, init
end

local bu = require("apis.bangumi_user")
assert(captured.opts, "没能捕获 bangumi_user 的 opts —— make_init 签名变了？")
bu.init({}, {})     -- 走一遍文档化的初始化路径

local TOKEN = "test-token-DO-NOT-LEAK-0123456789"
local BASE = "https://api.bgm.tv"

local function reset()
    pending, calls = {}, {}
    next_res = nil
end

local function setup(extra_opts)
    reset()
    local o, d = captured.opts, captured.deps
    for k in pairs(o) do o[k] = nil end     -- 清空但保留表身份（模块持有同一张表）
    for k in pairs(d) do d[k] = nil end
    o.bangumi_token = TOKEN
    o.api_base_url = BASE
    for k, v in pairs(extra_opts or {}) do o[k] = v end
    local reg = { registered = {}, unregistered = {} }
    reg.register = function(fn)
        reg.registered[#reg.registered + 1] = fn
        return #reg.registered
    end
    reg.unregister = function(tok)
        reg.unregistered[#reg.unregistered + 1] = tok
    end
    d.request_registry = reg
    return reg
end

local function flush(max_steps)
    local steps = 0
    while #pending > 0 do
        steps = steps + 1
        if steps > (max_steps or 12) then
            error("flush 步数超限，疑似回调死循环", 0)
        end
        local job = table.remove(pending, 1)
        job.cb(job.res.success, job.res.result, job.res.error)
    end
    return steps
end

local function ok_result(body)
    return { success = true, result = { status = 0, stdout = body or "", stderr = "" } }
end

local function arg_after(args, flag)
    for i = 1, #args do
        if args[i] == flag then return args[i + 1] end
    end
    return nil
end

local function method_of(i)
    local args = calls[i]
    return args and arg_after(args, "-X") or nil
end

local function url_of(i)
    local args = calls[i]
    return args and args[#args] or nil
end

local function auth_header(args)
    if not args then return nil end
    for i = 1, #args - 1 do
        if args[i] == "-H" and type(args[i + 1]) == "string"
           and args[i + 1]:find("^Authorization:") then
            return args[i + 1]
        end
    end
    return nil
end

local function body_of(i)
    local args = calls[i]
    return args and arg_after(args, "-d") or nil
end

-- ============================================================================
print(string.rep("-", 76))
print("== 1. get_base_url 解析 ==")
setup({ api_base_url = "https://api.bgm.tv/" })
check("尾部斜杠被去掉", bu.get_base_url(), "https://api.bgm.tv")
setup({ api_base_url = "", api_server = "https://a.example|备注,https://b.example" })
check("回退到 api_server 第一项（剥掉 | 备注）", bu.get_base_url(), "https://a.example")
setup({ api_base_url = "", api_server = "" })
check("都没配时用官方默认", bu.get_base_url(), "https://api.bgm.tv")

print(string.rep("-", 76))
print("== 2. token 开关 ==")
setup({ bangumi_token = "" })
check("空 token → has_token=false", bu.has_token(), false)
check("空 token → is_enabled=false", bu.is_enabled(), false)
setup({})
check("有 token → has_token=true", bu.has_token(), true)
check("默认开进度同步", bu.is_enabled(), true)
setup({ enable_progress_sync = false })
check("显式关开关 → is_enabled=false", bu.is_enabled(), false)

print(string.rep("-", 76))
print("== 3. 未配置 token 时绝不发起请求 ==")
setup({ bangumi_token = "" })
local r3
bu.get_me(function(ok, _d, e) r3 = { ok = ok, code = e and e.code } end)
flush()
check("回调报错", r3 and r3.ok, false)
check("错误码是 ERR_NO_TOKEN", r3 and r3.code, bu.ERR_NO_TOKEN)
check("一个子进程都没起（不泄漏、不试探）", #calls, 0)

print(string.rep("-", 76))
print("== 4. 请求构造：URL / 方法 / 鉴权头 / 请求体 ==")
setup({})
next_res = ok_result('{"id":1,"username":"alice"}')
bu.get_me(function() end)
flush()
check("GET /v0/me 的 URL", url_of(1), BASE .. "/v0/me")
check("方法 GET", method_of(1), "GET")
check("带 Bearer 鉴权头", auth_header(calls[1]), "Authorization: Bearer " .. TOKEN)

setup({})
next_res = ok_result("")
bu.update_collection(123, bu.COLLECTION_DOING, function() end)
flush()
check("收藏 URL", url_of(1), BASE .. "/v0/users/-/collections/123")
check("收藏方法 POST", method_of(1), "POST")
check("收藏体只含 type=3（在看）", body_of(1), '{"type":3}')

setup({})
next_res = ok_result("")
bu.update_episode_progress(123, { 1, 2, 8 }, bu.EP_DONE, function() end)
flush()
check("批量进度 URL", url_of(1), BASE .. "/v0/users/-/collections/123/episodes")
check("批量进度方法 **PATCH**（不是 POST）", method_of(1), "PATCH")
check("批量进度体", body_of(1), '{"episode_id":[1,2,8],"type":2}')

setup({})
next_res = ok_result("")
bu.update_single_episode(456, bu.EP_DONE, function() end)
flush()
check("单集 URL", url_of(1), BASE .. "/v0/users/-/collections/-/episodes/456")
check("单集方法 **PUT**（不是 PATCH）", method_of(1), "PUT")
check("单集体只含 type=2", body_of(1), '{"type":2}')

print(string.rep("-", 76))
print("== 5. 空响应体策略：写操作 204 必须算成功 ==")
setup({})
next_res = ok_result("")
local r5
bu.get_me(function(ok, _d, e) r5 = { ok = ok, code = e and e.code } end)
flush()
check("GET 空体 → 失败（读操作本该有 JSON）", r5 and r5.ok, false)
check("GET 空体错误码 ERR_EMPTY", r5 and r5.code, "ERR_EMPTY")

setup({})
next_res = ok_result("")
r5 = nil
bu.update_single_episode(456, bu.EP_DONE, function(ok, d)
    r5 = { ok = ok, data = d }
end)
flush()
check("PUT 空体（204）→ **成功**", r5 and r5.ok, true)
check("PUT 空体返回空表而非 nil", r5 and type(r5.data), "table")

setup({})
next_res = ok_result("")
r5 = nil
bu.update_collection(123, bu.COLLECTION_DONE, function(ok) r5 = ok end)
flush()
check("POST 空体（204）→ **成功**", r5, true)

setup({})
next_res = ok_result("")
r5 = nil
bu.update_episode_progress(123, { 1 }, bu.EP_DONE, function(ok) r5 = ok end)
flush()
check("PATCH 空体（204）→ **成功**", r5, true)

print(string.rep("-", 76))
print("== 6. 错误体识别（ErrorDetail = title + description）==")
setup({})
next_res = ok_result('{"title":"Unauthorized","description":"Invalid token"}')
local r6
bu.get_me(function(ok, _d, e) r6 = { ok = ok, code = e and e.code, msg = e and e.msg } end)
flush()
check("ErrorDetail → 失败", r6 and r6.ok, false)
check("错误码 ERR_HTTP", r6 and r6.code, "ERR_HTTP")
check("错误信息含服务端原文", r6 and r6.msg, "Unauthorized: Invalid token")

-- 关键回归：成功响应里**有 type 字段**，不得被误判成错误
setup({})
next_res = ok_result(
    '{"subject_id":8,"type":3,"rate":0,"ep_status":5,"vol_status":0,"private":false}')
r6 = nil
bu.get_collection(8, function(ok, d) r6 = { ok = ok, type = d and d.type } end)
flush()
check("含 type 的收藏响应 → 成功（不是错误体）", r6 and r6.ok, true)
check("收藏类型读出为 3（在看）", r6 and r6.type, 3)

setup({})
next_res = ok_result("这不是 JSON")
r6 = nil
bu.get_me(function(ok, _d, e) r6 = { ok = ok, code = e and e.code } end)
flush()
check("坏 JSON → ERR_PARSE", r6 and r6.code, "ERR_PARSE")

-- 6b 判别边界：把「什么算错误体」钉死
--
-- 说明：这里**故意**不测「错误体里额外带 id/type 会不会漏判」——
-- 那是等价变异。已逐条核对 open-api/v0.yaml 的三个成功 schema：
--   User              : id, username, nickname, user_group, avatar, sign
--   UserSubjectCollection: subject_id, subject_type, rate, type, comment,
--                          tags, ep_status, vol_status, updated_at, private, subject
--   UserEpisodeCollection: episode, type, updated_at
-- 全都没有 title/description，而 ErrorDetail 的 required 恰好就是这两个。
-- 所以「title + description」是充要判别式，多余的守卫是死代码。
-- 写在这里是为了防止后人误以为那是漏测而补一个假用例。
setup({})
next_res = ok_result(
    '{"title":"Bad Request","description":"episode ID not valid",'
    .. '"details":{"error":"x","path":"/v0/x"}}')
r6 = nil
bu.get_me(function(ok, _d, e) r6 = { ok = ok, msg = e and e.msg } end)
flush()
check("带 details 的错误体仍判为错误", r6 and r6.ok, false)
check("details 不影响错误信息拼装", r6 and r6.msg, "Bad Request: episode ID not valid")

setup({})
next_res = ok_result('{"episode":{"id":999,"name":"第1话"},"type":2,"updated_at":"2026-10-06"}')
r6 = nil
bu.get_me(function(ok, d) r6 = { ok = ok, t = d and d.type } end)
flush()
check("含 episode/type 的成功体不被误判", r6 and r6.ok, true)
check("读出 type=2", r6 and r6.t, 2)

print(string.rep("-", 76))
print("== 7. mark_episode_watched 编排 ==")
-- 7a 未收藏（读收藏报 404）→ 先 POST 收藏，再 PATCH 标集
setup({})
next_res = ok_result('{"title":"Not Found","description":"subject not collected"}')
local r7
bu.mark_episode_watched(8, 999, function(ok, info, e)
    r7 = { ok = ok, info = info, code = e and e.code }
end)
check("第 1 步只发 1 个请求（先读收藏）", #calls, 1)
check("第 1 步是 GET", method_of(1), "GET")
next_res = ok_result("")        -- 后续写操作都返回 204 空体
flush()
check("未收藏路径共发 3 个请求", #calls, 3)
check("第 2 个是 POST 收藏", method_of(2), "POST")
check("第 2 个 URL 指向该条目", url_of(2), BASE .. "/v0/users/-/collections/8")
check("第 3 个是 PATCH 集进度", method_of(3), "PATCH")
check("第 3 个 URL 指向该集", url_of(3), BASE .. "/v0/users/-/collections/8/episodes")
check("最终成功", r7 and r7.ok, true)
check("info 带条目/集号", r7 and r7.info and (r7.info.subject_id .. "/" .. r7.info.episode_id),
    "8/999")

-- 7b 已收藏 → 跳过 POST，只发 2 个请求
setup({})
next_res = ok_result('{"subject_id":8,"type":3,"ep_status":5}')
local r7b
bu.mark_episode_watched(8, 999, function(ok) r7b = ok end)
check("已收藏：第 1 步只发读请求", #calls, 1)
next_res = ok_result("")
flush()
check("已收藏路径共发 2 个请求（跳过 POST 收藏）", #calls, 2)
check("第 2 个是 PATCH", method_of(2), "PATCH")
check("已收藏路径也成功", r7b, true)

print(string.rep("-", 76))
print("== 8. request_registry 注销（闭包作用域回归）==")
-- 若 `local registered_token = nil` 被写在闭包**之后**，闭包读到的是全局 nil，
-- 注销永不执行 —— request_registry 会随每次请求无界增长。
-- 这一节能成立的前提是回调**延迟**触发（见文件头设计要点 1）。
local reg8 = setup({})
next_res = ok_result('{"id":1}')
bu.get_me(function() end)
check("请求发出后注册了 1 个取消器", #reg8.registered, 1)
check("此刻尚未注销（回调还没跑）", #reg8.unregistered, 0)
flush()
check("回调执行后注销了 1 次", #reg8.unregistered, 1)
check("注销的正是注册时拿到的 token", reg8.unregistered[1], 1)

print(string.rep("-", 76))
print("== 9. 脱敏：token 只能出现在 Authorization 头里 ==")
setup({})
next_res = ok_result('{"id":1}')
bu.get_me(function() end)
flush()
local leaks = 0
for _, args in ipairs(calls) do
    for _, a in ipairs(args) do
        if type(a) == "string" and a:find(TOKEN, 1, true)
           and not a:find("^Authorization: Bearer ") then
            leaks = leaks + 1
            print("         泄漏点: " .. a)
        end
    end
end
check("除 Authorization 头外无 token 泄漏", leaks, 0)
check("Authorization 头确实带了 token", auth_header(calls[1]),
    "Authorization: Bearer " .. TOKEN)

print(string.rep("-", 76))
print("== 10. 剧集列表与「集数 → episode_id」映射 ==")
local EP_BODY = '{"total":3,"limit":200,"offset":0,"data":['
    .. '{"id":101,"type":0,"sort":1,"ep":1,"name":"第1话"},'
    .. '{"id":102,"type":0,"sort":2,"ep":2,"name":"第2话"},'
    .. '{"id":103,"type":0,"sort":3,"ep":3,"name":"第3话"}]}'

setup({})
bu.clear_episode_cache()
next_res = ok_result(EP_BODY)
local r10
bu.get_episodes(8, function(ok, list) r10 = { ok = ok, n = list and #list } end)
flush()
check("剧集列表拉取成功", r10 and r10.ok, true)
check("解析出 3 集", r10 and r10.n, 3)
check("URL 带 subject_id/type/limit", url_of(1),
    BASE .. "/v0/episodes?subject_id=8&type=0&limit=200")
check("公开端点**不带**鉴权头", auth_header(calls[1]), nil)
check("公开端点不需要 token", method_of(1), "GET")

-- 缓存：第二次调用不应再起子进程
local before = #calls
bu.get_episodes(8, function() end)
flush()
check("第二次读剧集列表走缓存（未再发请求）", #calls, before)

setup({})
bu.clear_episode_cache()
next_res = ok_result(EP_BODY)
r10 = nil
bu.resolve_episode_id(8, 2, function(ok, id) r10 = { ok = ok, id = id } end)
flush()
check("集数 2 → episode_id 102", r10 and r10.id, 102)

-- 集数写成字符串（文件名解析出来就是字符串）也要能匹配
setup({})
bu.clear_episode_cache()
next_res = ok_result(EP_BODY)
r10 = nil
bu.resolve_episode_id(8, "3", function(ok, id) r10 = { ok = ok, id = id } end)
flush()
check("字符串集数 '3' → episode_id 103", r10 and r10.id, 103)

-- 越界集数必须明确报错，绝不静默标错集
setup({})
bu.clear_episode_cache()
next_res = ok_result(EP_BODY)
r10 = nil
bu.resolve_episode_id(8, 99, function(ok, _id, e)
    r10 = { ok = ok, code = e and e.code, msg = e and e.msg }
end)
flush()
check("越界集数 → 失败", r10 and r10.ok, false)
check("错误码 ERR_NOT_FOUND（不静默标错）", r10 and r10.code, "ERR_NOT_FOUND")
check("错误信息说明共几集", r10 and r10.msg, "该条目下找不到第 99 集（共 3 集）")

-- 无法识别集数时直接失败，不联网
setup({})
bu.clear_episode_cache()
r10 = nil
bu.resolve_episode_id(8, nil, function(ok, _id, e) r10 = { ok = ok, code = e and e.code } end)
flush()
check("集数缺失 → ERR_PARSE", r10 and r10.code, "ERR_PARSE")
check("集数缺失时不发请求", #calls, 0)

print(string.rep("-", 76))
print(string.format("通过 %d，失败 %d", pass, fail))
if fail > 0 then
    print("结果：有断言未通过 ❌")
    os.exit(1)
end
print("结果：全部通过 ✅")
