-- tools/runtime-config-test.lua —— modules/runtime_config 回归测试
--
-- 用法（任意 cwd 均可 —— 路径基准由脚本自身位置推导）：
--   ./luajit.exe portable_config/tools/runtime-config-test.lua
--
-- 为什么需要它（2026-10-07）：
--   发现一个「配置改了、菜单显示新值、重启却回退」的真缺陷，根因**不在**
--   runtime_config 自己，而在它与 module_loader 的交互：
--
--     module_loader.make_init 做的是 shallow_merge(opts, new_opts) ——
--     把调用方的 opts **浅拷贝**进模块自己的一张表。模块一旦 init 过，
--     它的副本就固定了；之后再改那张共享 opts 也传导不到它。
--
--   所以持久化值必须在**第一次 init 之前**并进共享 opts（bootstrap 步骤 1.5）。
--   此前只在 runtime_config.load() 里合并它自己的私有副本 → 全部无效。
--
--   这个「顺序要求」是本测试的核心断言（见 §4），因为它是**看不见的**：
--   代码怎么写都能过语法、过审计，只有真跑一遍才知道没生效。
--
-- ⚠️ 本测试用**真实**的 module_loader.make_init 来复现拷贝语义，
--    而不是自己手写一遍 shallow_merge —— 手写就等于在测我自己对它的理解，
--    一旦 make_init 改成「持有引用」，测试会继续绿而线上行为已变。

-- ---- 路径基准：从脚本自身位置反推，使本测试与 cwd 无关 ----
local _src = debug.getinfo(1, "S").source or "@."
local _tools_dir = _src:match("^@(.*)[/\\][^/\\]*$") or "."
local _pc = _tools_dir:match("^(.*)[/\\][^/\\]*$") or "."

-- ---- 真 JSON 解码器 ----
-- 桩不真实会得出假结论：第一版探针就是因为 mp.utils 桩缺 parse_json，
-- pcall 静默吞掉错误 → runtime_data 恒为空 → 误判「持久化没生效」。
local function json_decode(s)
    local pos = 1
    local function skip() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
    local parse_value
    local function parse_string()
        pos = pos + 1
        local out = {}
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if map[e] then out[#out + 1] = map[e]; pos = pos + 2
                else
                    local cp = tonumber(s:sub(pos + 2, pos + 5), 16)
                    if cp < 0x80 then out[#out + 1] = string.char(cp)
                    else
                        out[#out + 1] = string.char(0xE0 + math.floor(cp / 0x1000),
                            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
                    end
                    pos = pos + 6
                end
            else out[#out + 1] = c; pos = pos + 1 end
        end
        error("unterminated string")
    end
    local function parse_array()
        pos = pos + 1; local arr = {}; skip()
        if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while true do
            arr[#arr + 1] = parse_value(); skip()
            local c = s:sub(pos, pos)
            if c == "," then pos = pos + 1; skip()
            elseif c == "]" then pos = pos + 1; return arr
            else error("bad array") end
        end
    end
    local function parse_object()
        pos = pos + 1; local obj = {}; skip()
        if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
            skip(); local k = parse_string(); skip(); pos = pos + 1
            obj[k] = parse_value(); skip()
            local c = s:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "}" then pos = pos + 1; return obj
            else error("bad object") end
        end
    end
    parse_value = function()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == '"' then return parse_string() end
        if s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
        if s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
        if s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
        local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
        if num and num ~= "" then pos = pos + #num; return tonumber(num) end
        error("bad value at " .. pos)
    end
    return parse_value()
end

-- ---- stub mp ----
-- 目标文件路径可切换，供各用例构造不同场景
local TMP_JSON = (os.getenv("TEMP") or ".") .. "/rtc-test.json"
local current_path = TMP_JSON
local expand_calls = 0

package.preload["mp"] = function()
    return {
        get_opt = function() return nil end,
        -- ⚠️ mp.command_native 只接受一个参数（表），首个元素是命令名
        command_native = function(args)
            if args and args[1] == "expand-path" then
                expand_calls = expand_calls + 1
                return current_path
            end
            return nil
        end,
        add_timeout = function() return 1 end,
        cancel_timer = function() end,
        get_property = function() return nil end,
        msg = setmetatable({}, { __index = function() return function() end end }),
    }
end
package.preload["mp.msg"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["mp.utils"] = function()
    return {
        parse_json = function(str)
            local ok, v = pcall(json_decode, str)
            if not ok then return nil end
            return v
        end,
        format_json = function(t)
            -- 够用即可：本测试只写扁平 string/number/boolean 表
            local parts = {}
            for k, v in pairs(t or {}) do
                local vs
                if type(v) == "string" then vs = '"' .. v .. '"'
                elseif type(v) == "boolean" then vs = tostring(v)
                else vs = tostring(v) end
                parts[#parts + 1] = '"' .. tostring(k) .. '":' .. vs
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end,
    }
end

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
        print(string.format("  [FAIL] %s\n         期望: %s\n         实际: %s",
            desc, tostring(want), tostring(got)))
    end
end
local function section(t)
    print("")
    print("── " .. t .. " " .. string.rep("─", math.max(0, 62 - #t)))
end
local function write_file(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

-- 每次「重启」都要重新 require，以清掉模块级状态
local function fresh_modules()
    for _, name in ipairs({
        "modules.runtime_config", "modules.defaults", "modules.utils.module_loader",
    }) do
        package.loaded[name] = nil
    end
    return require("modules.defaults"), require("modules.runtime_config")
end

-- ============================================================================
-- §0 自检：JSON 解码器本身要可信
-- ============================================================================
section("§0 自检：JSON 解码器")
do
    local d = json_decode('{"a":1,"b":"x","c":true,"d":false,"e":[1,2]}')
    check("对象字段 a", d.a, 1)
    check("对象字段 b", d.b, "x")
    check("布尔 true", d.c, true)
    check("布尔 false", d.d, false)
    check("数组元素", d.e[2], 2)
    check("带缩进与空格", json_decode('{\n  "k": "v"\n}').k, "v")
    local ok = pcall(json_decode, "{bad")
    check("坏输入不抛异常（由 pcall 捕获）", ok, false)
end

-- ============================================================================
-- §1 apply_persisted：把持久化值并入目标表
-- ============================================================================
section("§1 apply_persisted 基本行为")
do
    write_file(TMP_JSON, '{"data_cache_days":7,"debug":false,"progress_sync_mode":"auto"}')
    current_path = TMP_JSON
    local defaults, rc = fresh_modules()

    local opts = defaults.load_options()
    check("合并前 data_cache_days = 默认值", opts.data_cache_days, 30)

    local applied = rc.apply_persisted(opts)
    check("返回值含 3 项", (function() local n = 0; for _ in pairs(applied) do n = n + 1 end; return n end)(), 3)
    check("合并后 data_cache_days = 7", opts.data_cache_days, 7)
    check("合并后 debug = false", opts.debug, false)
    check("合并后 progress_sync_mode = auto", opts.progress_sync_mode, "auto")
    check("未涉及的项保持默认（timeout）", opts.timeout, 8)
end

-- ============================================================================
-- §2 JSON 类型必须原样保留（绕过了 script-opts 的字符串转换）
-- ============================================================================
section("§2 类型保留（不经过 script-opts 的 to_bool/to_number）")
do
    write_file(TMP_JSON, '{"data_cache_days":7,"debug":false,"image_cache_days":90}')
    current_path = TMP_JSON
    local defaults, rc = fresh_modules()
    local opts = defaults.load_options()
    rc.apply_persisted(opts)
    check("number 仍是 number", type(opts.data_cache_days), "number")
    check("boolean 仍是 boolean（不是字符串 \"false\"）", type(opts.debug), "boolean")
    check("boolean 值正确", opts.debug, false)
    check("第二个 number", opts.image_cache_days, 90)
end

-- ============================================================================
-- §3 get() 优先级：runtime_config > opts
-- ============================================================================
section("§3 get() 优先级 runtime_config > opts")
do
    write_file(TMP_JSON, '{"data_cache_days":7}')
    current_path = TMP_JSON
    local defaults, rc = fresh_modules()
    local opts = defaults.load_options()
    opts.data_cache_days = 15          -- 模拟 script-opts 里写了 15
    rc.apply_persisted(opts)
    check("runtime_config 的值胜出", rc.get("data_cache_days"), 7)
    check("opts 也被同步为持久化值", opts.data_cache_days, 7)
end

-- ============================================================================
-- §4 ★核心：init 顺序要求（本缺陷的根因）
-- ============================================================================
section("§4 ★ init 顺序：必须早于任何模块 init（用真实 make_init）")
do
    write_file(TMP_JSON, '{"data_cache_days":7}')
    current_path = TMP_JSON
    local defaults, rc = fresh_modules()
    local ml = require("modules.utils.module_loader")

    -- 4a) 正确顺序：先 apply_persisted(共享 opts) → 再让模块 init
    local shared = defaults.load_options()
    rc.apply_persisted(shared)
    local mod_opts_a, _, mod_init_a = ml.make_init("probe_a", nil)
    mod_init_a(shared, {})
    check("4a 正确顺序：模块 init 时拿到了持久化值", mod_opts_a.data_cache_days, 7)

    -- 4b) 错误顺序：模块先 init（拷贝发生）→ 再 apply_persisted
    --     这是修复前的真实行为，必须复现「模块拿不到」才算测到了根因
    local defaults2, rc2 = fresh_modules()
    local shared2 = defaults2.load_options()
    local mod_opts_b, _, mod_init_b = ml.make_init("probe_b", nil)
    mod_init_b(shared2, {})               -- 先 init：此刻拷贝了默认值 30
    rc2.apply_persisted(shared2)          -- 后合并：共享表变了，但模块副本没变
    check("4b 错误顺序：共享表已更新", shared2.data_cache_days, 7)
    check("4b 错误顺序：模块副本仍是旧值（证明拷贝语义）",
        mod_opts_b.data_cache_days, 30)
end

-- ============================================================================
-- §5 异常输入一律不崩、且不污染 opts
-- ============================================================================
section("§5 异常输入（缺文件 / 空文件 / 坏 JSON）")
do
    -- 5a) 文件不存在
    local missing = (os.getenv("TEMP") or ".") .. "/rtc-does-not-exist.json"
    os.remove(missing)
    current_path = missing
    local defaults, rc = fresh_modules()
    local opts = defaults.load_options()
    local ok, err = pcall(rc.apply_persisted, opts)
    check("5a 缺文件不抛异常", ok, true)
    check("5a opts 未被污染", opts.data_cache_days, 30)

    -- 5b) 空文件
    write_file(TMP_JSON, "")
    current_path = TMP_JSON
    local d2, rc2 = fresh_modules()
    local o2 = d2.load_options()
    local ok2 = pcall(rc2.apply_persisted, o2)
    check("5b 空文件不抛异常", ok2, true)
    check("5b opts 未被污染", o2.data_cache_days, 30)

    -- 5c) 坏 JSON
    write_file(TMP_JSON, '{"data_cache_days":')
    current_path = TMP_JSON
    local d3, rc3 = fresh_modules()
    local o3 = d3.load_options()
    local ok3 = pcall(rc3.apply_persisted, o3)
    check("5c 坏 JSON 不抛异常", ok3, true)
    check("5c opts 未被污染", o3.data_cache_days, 30)

    -- 5d) JSON 顶层是数组（不是对象）→ 也不该崩
    write_file(TMP_JSON, '[1,2,3]')
    current_path = TMP_JSON
    local d4, rc4 = fresh_modules()
    local o4 = d4.load_options()
    local ok4 = pcall(rc4.apply_persisted, o4)
    check("5d 顶层为数组不抛异常", ok4, true)
end

-- ============================================================================
-- §6 save()：三处写入 + 不重复读文件
-- ============================================================================
section("§6 save() 与重复调用")
do
    write_file(TMP_JSON, '{"data_cache_days":7}')
    current_path = TMP_JSON
    local defaults, rc = fresh_modules()
    local opts = defaults.load_options()
    rc.apply_persisted(opts)
    check("apply 后 runtime_data 就位", rc.get("data_cache_days"), 7)

    rc.save("data_cache_days", 15)
    check("save 后 get 返回新值", rc.get("data_cache_days"), 15)
    check("save 同步了共享 opts", opts.data_cache_days, 15)

    -- 再次 apply_persisted 不应重读文件（避免启动时读两遍）
    local before = expand_calls
    rc.apply_persisted(opts)
    check("重复 apply 不重复读文件", expand_calls, before)
    check("重复 apply 也不会把值改回文件里的旧值", opts.data_cache_days, 15)
end

-- ============================================================================
-- §7 load() 向后兼容（模块自身 init 走这条路）
-- ============================================================================
section("§7 load() 仍可用（向后兼容）")
do
    write_file(TMP_JSON, '{"data_cache_days":7}')
    current_path = TMP_JSON
    local defaults, rc = fresh_modules()
    local opts = defaults.load_options()
    rc.init(opts, { notify = { warn = function() end, info = function() end } })
    check("init 内部的 load() 生效", rc.get("data_cache_days"), 7)
    local ok = pcall(rc.load)
    check("重复 load() 不抛异常", ok, true)
end

-- ============================================================================
-- §8 ★静态顺序门禁：bootstrap 必须「先 load_options → 再 apply_persisted →
--     最后才 init_module」，且 apply_persisted 必须早于**任何** init_module
-- ============================================================================
-- 为什么放在测试里而不是另写一个 py 门禁：这条约束与 §4 是同一个不变式
-- （「持久化值必须早于任何模块 init」），分开两处会各自漂移。
--
-- 为什么必须静态查：§1~§7 都是直接调 apply_persisted，**删掉 bootstrap 里那次
-- 调用它们照样全绿** —— 只有查源码才守得住。
section("§8 ★静态门禁：bootstrap 中的合并顺序")
do
    local path = _pc .. "/scripts/uosc_staff_credits/app/bootstrap.lua"
    local f = io.open(path, "r")
    check("能读到 bootstrap.lua", f ~= nil, true)
    if f then
        local src = f:read("*a")
        f:close()

        -- 先剥掉行注释，避免注释里提到这些名字造成误判
        --
        -- ⚠️ 按行切分必须用 ("([^\n]*)\n") 这种写法。
        --    写成 gmatch("[^\n]*") 是错的：该模式能匹配空串，
        --    gmatch 会在每个 \n 处再补一个空匹配 → 条目数约为行数的 2 倍，
        --    于是算出来的「行号」全部虚高（实测 593 行的文件被数成 1128 条，
        --    定义在第 24 行却被报成第 43 行）。这个 bug 是被本节的断言
        --    「apply_persisted 早于第一个 init_module」失败暴露出来的。
        local code = {}
        for line in (src .. "\n"):gmatch("([^\n]*)\n") do
            code[#code + 1] = (line:gsub("%-%-.*$", ""))
        end

        local line_load, line_apply, line_first_init = nil, nil, nil
        for i, l in ipairs(code) do
            if not line_load and l:find("load_options%s*%(") then line_load = i end
            -- ⚠️ 必须匹配**完整调用形态** `xxx.apply_persisted(opts)`，
            --    不能只查名字 `apply_persisted` 出现过 ——
            --    变异验证发现：把调用改成 rc_apply_persisted_DISABLED(opts)
            --    （一个不存在的函数，运行必崩）时，只查名字的门禁照样全绿。
            --    这类「查到了名字 ≠ 真的调用」是静态门禁最常见的假阳性来源。
            if not line_apply and l:find("%.apply_persisted%s*%(%s*opts%s*%)") then
                line_apply = i
            end
            -- 只认**调用**，不认定义：`local function init_module(` / `function init_module(`
            -- 定义行里 init_module 前面是 function，用负向判据排除。
            if not line_first_init
                and l:find("init_module%s*%(")
                and not l:find("function%s+init_module%s*%(") then
                line_first_init = i
            end
        end

        check("bootstrap 里能找到 load_options(", line_load ~= nil, true)
        check("bootstrap 里能找到 apply_persisted(", line_apply ~= nil, true)
        check("bootstrap 里能找到 init_module(", line_first_init ~= nil, true)

        if line_load and line_apply and line_first_init then
            check(string.format(
                "apply_persisted(第%d行) 晚于 load_options(第%d行)",
                line_apply, line_load), line_apply > line_load, true)
            check(string.format(
                "apply_persisted(第%d行) 早于第一个 init_module(第%d行)",
                line_apply, line_first_init), line_apply < line_first_init, true)
        end
    end
end

-- ============================================================================
-- 汇总
-- ============================================================================
print("")
print(string.rep("=", 76))
print(string.format("通过 %d，失败 %d", pass, fail))
if fail == 0 then
    print("结果：全部通过 ✅")
else
    print("结果：存在失败 ❌")
end
os.remove(TMP_JSON)
os.exit(fail == 0 and 0 or 1)
