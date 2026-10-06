-- tools/progress-sync-test.lua —— features/progress_sync 回归测试
--
-- 用法（任意 cwd 均可 —— 路径基准由脚本自身位置推导）：
--   ./luajit.exe portable_config/tools/progress-sync-test.lua
--
-- 为什么需要它（2026-10-06）：
--   这个模块会**代表用户去写 Bangumi 收藏**，所以最要紧的不是「能不能写成功」，
--   而是**不该写的时候绝不写**：
--     · 没配 token        → 一个请求都不许发
--     · 没识别出条目      → 不许瞎猜条目去写
--     · progress_sync_mode=off（默认） → 打开视频不许产生任何网络请求
--   这三种「克制」用肉眼看代码看不出来，只有把请求桩下来数一数才作数。
--   另外「集数 → episode_id」这一步必须**先解析再写**，顺序错了会写错集。
--
-- 设计要点：
--   1. 定时器是假的：mp.add_periodic_timer 只登记，由测试手动 tick，
--      否则读进度那步永远不会被触发，测试会「静静地」什么都测不到。
--   2. deps 直接改模块持有的那张表：make_feature_init 有单次初始化保护，
--      第二次 init 会被跳过 —— 靠反复 init 切参数会悄悄沿用第一组参数。

-- ============================================================================
-- stub mp
-- ============================================================================
local periodic = {}     -- {fn=..., dead=false}

package.preload["mp"] = function()
    return {
        get_property = function(_, d) return d end,
        get_property_number = function(_, d) return d end,
        command = function() end,
        commandv = function() end,
        add_timeout = function(_, fn) return { kill = function() end } end,
        add_periodic_timer = function(_, fn)
            local t = { fn = fn, dead = false }
            t.kill = function() t.dead = true end
            periodic[#periodic + 1] = t
            return t
        end,
        cancel_timer = function() end,
        get_time = function() return 0 end,
        msg = setmetatable({}, { __index = function() return function() end end }),
        utils = {
            split_path = function(p)
                local dir, file = tostring(p):match("^(.*)[/\\]([^/\\]*)$")
                if not dir then return "", tostring(p) end
                return dir, file
            end,
        },
    }
end
package.preload["mp.msg"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["mp.utils"] = function()
    return {
        split_path = function(p)
            local dir, file = tostring(p):match("^(.*)[/\\]([^/\\]*)$")
            if not dir then return "", tostring(p) end
            return dir, file
        end,
    }
end

-- ---- 路径基准：从脚本自身位置反推，使本测试与 cwd 无关 ----
-- 脚本位于 <mpv根>/portable_config/tools/，故上溯一级即 portable_config。
local _src = debug.getinfo(1, "S").source or "@."
local _tools_dir = _src:match("^@(.*)[/\\][^/\\]*$") or "."
local _pc = _tools_dir:match("^(.*)[/\\][^/\\]*$") or "."
package.path = _pc .. "/scripts/uosc_staff_credits/?.lua;"
    .. _pc .. "/scripts/uosc_staff_credits/?/init.lua;" .. package.path

-- 捕获模块持有的 deps 表
local ml = require("modules.utils.module_loader")
local captured = nil
local real_feature_init = ml.make_feature_init
ml.make_feature_init = function(name, schema)
    local d, init = real_feature_init(name, schema)
    if name == "progress_sync" then captured = d end
    return d, init
end

local ps = require("features.progress_sync")
assert(captured, "没能捕获 progress_sync 的 deps —— make_feature_init 签名变了？")

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

-- 假的 bangumi_user：记录调用顺序
local calls
local behavior

local function make_bu()
    return {
        is_enabled = function() return behavior.enabled end,
        describe_collection_type = function(t)
            if tonumber(t) == 3 then return "在看" end
            return "未收藏"
        end,
        clear_episode_cache = function()
            calls[#calls + 1] = { "clear_episode_cache" }
        end,
        get_collection = function(sid, cb)
            calls[#calls + 1] = { "get_collection", sid }
            if behavior.collection_fails then
                cb(false, nil, { msg = "读取失败" })
            else
                cb(true, behavior.collection or { type = 3, ep_status = 5 }, nil)
            end
        end,
        resolve_episode_id = function(sid, ep, cb)
            calls[#calls + 1] = { "resolve_episode_id", sid, ep }
            if behavior.resolve_fails then
                cb(false, nil, { code = "ERR_NOT_FOUND", msg = "找不到该集" })
            else
                cb(true, behavior.episode_id or 102, nil)
            end
        end,
        mark_episode_watched = function(sid, eid, cb)
            calls[#calls + 1] = { "mark_episode_watched", sid, eid }
            if behavior.mark_fails then
                cb(false, nil, { msg = "写入失败" })
            else
                cb(true, { subject_id = sid, episode_id = eid }, nil)
            end
        end,
    }
end

local notices
local notify = {
    info = function(t) notices[#notices + 1] = { "info", t } end,
    warn = function(t) notices[#notices + 1] = { "warn", t } end,
    error = function(t) notices[#notices + 1] = { "error", t } end,
    debug = function(t) notices[#notices + 1] = { "debug", t } end,
}

-- 可切换的假 state / guess
local fake_state = { search_state = { current_path = nil }, last_subject = nil }
fake_state.get_last_subject = function() return fake_state.last_subject end

local fake_guess = { episode_number = nil }
fake_guess.get_episode_number = function() return fake_guess.episode_number end

local fake_opts = { progress_sync_mode = "off", progress_sync_threshold = 80 }

-- setup: 重置全部桩状态
local function setup(opts)
    calls, notices = {}, {}
    periodic = {}
    behavior = {
        enabled = true,
        collection = { type = 3, ep_status = 5 },
        episode_id = 102,
    }
    for k in pairs(captured) do captured[k] = nil end
    captured.notify = notify
    captured.state = fake_state
    captured.guess = fake_guess
    captured.opts = fake_opts
    captured.script_name = "uosc_staff_credits"
    for k, v in pairs(opts or {}) do
        if k == "no_bangumi_user" then
            captured.bangumi_user = nil
        elseif k == "opts" then
            for kk, vv in pairs(v) do fake_opts[kk] = vv end
        else
            captured[k] = v
        end
    end
    if not opts or not opts.no_bangumi_user then
        captured.bangumi_user = make_bu()
    end
    fake_opts.progress_sync_mode = "off"
    fake_opts.progress_sync_threshold = 80
    if opts and opts.opts then
        for kk, vv in pairs(opts.opts) do fake_opts[kk] = vv end
    end
    fake_state.search_state.current_path = nil
    fake_state.last_subject = nil
    fake_guess.episode_number = nil
end

-- 手动触发所有存活的周期定时器一次。
--
-- ⚠️ 必须先**快照**再触发，不能边遍历边触发：真实的周期定时器不会在
--    「刚创建的那一刻」就回调。初版直接 ipairs(periodic) 边遍历边调，
--    结果新挂上的 auto 定时器在同一轮里立刻跑了一次并被自己 kill 掉，
--    于是「重复挂表」这个真实差异被掩盖 —— 变异测试才暴露出来。
local function tick()
    local snapshot = {}
    for _, t in ipairs(periodic) do
        if not t.dead then snapshot[#snapshot + 1] = t end
    end
    for _, t in ipairs(snapshot) do t.fn() end
    return #snapshot
end

local function call_names()
    local out = {}
    for _, c in ipairs(calls) do out[#out + 1] = c[1] end
    return table.concat(out, " → ")
end

local function fully_ready()
    fake_state.search_state.current_path = "D:/anime/某番/[Lilith-Raws] 某番 - 02 [1080p].mkv"
    fake_state.last_subject = { id = 8, name = "某番" }
    fake_guess.episode_number = 2
end

-- ============================================================================
print(string.rep("-", 76))
print("== 1. 开关与可用性判断 ==")
setup({ no_bangumi_user = true })
check("没有 bangumi_user 模块 → is_enabled=false", ps.is_enabled(), false)
check("此时 available 也是 false", (ps.available()), false)

setup({})
behavior.enabled = false
check("模块在但未配 token → is_enabled=false", ps.is_enabled(), false)
local ok1, why1 = ps.available()
check("available=false", ok1, false)
check("原因点明缺 token", why1, "未配置 bangumi_token")

setup({})
fully_ready()
check("条件齐备 → is_enabled=true", ps.is_enabled(), true)
check("available=true", (ps.available()), true)

setup({})
fake_state.search_state.current_path = "D:/anime/ep02.mkv"
fake_guess.episode_number = 2
local ok2, why2 = ps.available()
check("有 token 有集数但没识别条目 → false", ok2, false)
check("原因点明要搜索", why2, "尚未识别出 Bangumi 条目（先执行一次搜索）")

setup({})
fake_state.search_state.current_path = "D:/anime/没有集数的文件名.mkv"
fake_state.last_subject = { id = 8 }
local ok3, why3 = ps.available()
check("有 token 有条目但认不出集数 → false", ok3, false)
check("原因点明认不出集数", why3, "无法从文件名识别集数")

-- ============================================================================
print(string.rep("-", 76))
print("== 2. 主菜单条目（未配 token 时不得出现死项）==")
setup({ no_bangumi_user = true })
check("没配 token → 返回空表（菜单里完全不出现）", #ps.build_menu_items(), 0)

setup({})
behavior.enabled = false
check("模块在但没 token → 仍返回空表", #ps.build_menu_items(), 0)

setup({})
fake_state.search_state.current_path = "D:/anime/ep02.mkv"
local items2 = ps.build_menu_items()
check("配了 token 但暂不可用 → 给 1 条置灰说明项", #items2, 1)
check("置灰项不可选中", items2[1] and items2[1].unselectable, true)
check("置灰项不带 value（点了也不会发消息）", items2[1] and items2[1].value, nil)
check("置灰项的 hint 说明原因", items2[1] and items2[1].hint,
    "暂不可用：尚未识别出 Bangumi 条目（先执行一次搜索）")

setup({})
fully_ready()
local items3 = ps.build_menu_items()
check("条件齐备 → 给 2 条可点项", #items3, 2)
check("第 1 条是标记看过", items3[1] and items3[1].title, "标记本集为看过")
check("第 1 条路由正确", items3[1] and items3[1].value,
    "script-message-to uosc_staff_credits staff-credits-mark-watched")
check("第 2 条是查看进度", items3[2] and items3[2].title, "查看观看进度")
check("第 2 条路由正确", items3[2] and items3[2].value,
    "script-message-to uosc_staff_credits staff-credits-show-progress")

-- ============================================================================
print(string.rep("-", 76))
print("== 3. 标记本集为看过：顺序与克制 ==")
setup({})
behavior.enabled = false
local r3
ps.mark_current_episode(function(ok, _i, e) r3 = { ok = ok, err = e } end)
check("未配 token → 回调失败", r3 and r3.ok, false)
check("未配 token → 一个 bangumi 调用都没有", #calls, 0)

setup({})
fake_state.search_state.current_path = "D:/anime/没有集数的文件名.mkv"
fake_state.last_subject = { id = 8 }
r3 = nil
ps.mark_current_episode(function(ok, _i, e) r3 = { ok = ok, err = e } end)
check("认不出集数 → 回调失败", r3 and r3.ok, false)
check("认不出集数 → 不联网瞎猜", #calls, 0)

setup({})
fully_ready()
r3 = nil
local rinfo
ps.mark_current_episode(function(ok, i, _e) r3 = ok; rinfo = i end)
check("**先解析 episode_id 再写**", call_names(),
    "resolve_episode_id → mark_episode_watched")
check("解析时带的是条目 id + 集数", calls[1] and (calls[1][2] .. "/" .. tostring(calls[1][3])), "8/2")
check("写入时用的是解析出来的 episode_id", calls[2] and calls[2][3], 102)
check("整体成功", r3, true)
check("返回条目/集/episode_id", rinfo and (rinfo.subject_id .. "/" .. rinfo.episode_id), "8/102")

setup({})
fully_ready()
behavior.resolve_fails = true
r3 = nil
ps.mark_current_episode(function(ok) r3 = ok end)
check("解析失败 → 回调失败", r3, false)
check("解析失败 → **绝不**继续写入（否则会标错集）", call_names(), "resolve_episode_id")
check("给出了失败提示", (notices[#notices] and notices[#notices][1]), "warn")

-- ============================================================================
print(string.rep("-", 76))
print("== 4. 打开视频时的行为（默认档必须零网络请求）==")
setup({})
fully_ready()
fake_opts.progress_sync_mode = "off"
ps.on_file_loaded(fake_state.search_state.current_path)
check("mode=off → 不建任何定时器", #periodic, 0)
tick()
check("mode=off → 不产生任何 bangumi 调用", #calls, 0)

setup({ no_bangumi_user = true })
fake_opts.progress_sync_mode = "notify"
ps.on_file_loaded("D:/anime/ep02.mkv")
check("没配 token → 即使 mode=notify 也不建定时器", #periodic, 0)

setup({})
fake_opts.progress_sync_mode = "notify"
-- ⚠️ 必须先把 current_path 设成和传入的 path **一致**，否则首拍就会按
--    「期间换台了」中止 —— 那样第一条断言会因为错误的原因通过，测试静默失效。
local NOTIFY_PATH = "D:/anime/某番/[Lilith-Raws] 某番 - 02 [1080p].mkv"
fake_state.search_state.current_path = NOTIFY_PATH
ps.on_file_loaded(NOTIFY_PATH)
check("mode=notify → 建了等待定时器", #periodic, 1)
tick()
check("条目未就绪时不读进度", #calls, 0)
check("会继续等（定时器仍存活）", periodic[1] and periodic[1].dead, false)
-- 条目出现（路径不变）
fake_state.last_subject = { id = 8, name = "某番" }
fake_guess.episode_number = 2
tick()
check("条目就绪后读进度", call_names(), "get_collection")
check("读完后停掉等待定时器", periodic[1] and periodic[1].dead, true)
check("提示里带上进度", notices[#notices] and notices[#notices][2], "Bangumi 进度：在看 · 已看 5 集")

-- 中途换台必须放弃，否则会给**上一个视频**的条目写进度
setup({})
fake_opts.progress_sync_mode = "notify"
fake_state.search_state.current_path = NOTIFY_PATH
ps.on_file_loaded(NOTIFY_PATH)
fake_state.search_state.current_path = "D:/anime/另一个番/ep01.mkv"     -- 换台
tick()
check("中途换台 → 中止等待", periodic[1] and periodic[1].dead, true)
check("中途换台 → 不发任何请求", #calls, 0)

setup({})
fully_ready()
fake_opts.progress_sync_mode = "notify"
ps.on_file_loaded(fake_state.search_state.current_path)
tick()
check("mode=notify 不会自动标记", call_names(), "get_collection")

-- ============================================================================
print(string.rep("-", 76))
print("== 5. auto 档：达到阈值才标记，且只标一次 ==")
setup({})
fully_ready()
fake_opts.progress_sync_mode = "auto"
fake_opts.progress_sync_threshold = 80
ps.on_file_loaded(fake_state.search_state.current_path)
tick()                       -- 读进度，并挂上 auto 检查定时器
check("auto 档先读进度", calls[1] and calls[1][1], "get_collection")

-- 进度不到阈值：不许标记
local pct = 50
package.loaded["mp"].get_property_number = function(_, d)
    if d ~= nil then return pct end
    return pct
end
tick()
check("进度 50% < 阈值 80% → 不标记", call_names(), "get_collection")

-- 进度到阈值：标记
pct = 85
tick()
check("进度 85% ≥ 阈值 → 标记（先解析再写）", call_names(),
    "get_collection → resolve_episode_id → mark_episode_watched")

-- 再 tick：不得重复标记
local before = #calls
tick()
check("同一视频只自动标记一次", #calls, before)

-- 同一视频**再次打开**：不得重新挂 auto 检查定时器，否则会重复标记。
-- （这条是变异测试逼出来的：auto_tick 末尾已经 kill 了定时器，
--   真正防重复的是 on_file_loaded 里的 `not auto_marked[path]` 守卫。）
--
-- 附一条等价变异说明，免得后人白折腾：把 auto_tick 开头那句
-- `auto_marked[p]` 判断删掉，本测试**不会**报错 —— 因为紧随其后就
-- `auto_marked[p] = true` + `stop_auto_timer()`，定时器已被 kill，
-- 那句守卫在 tick 路径上是冗余的（保留它只是防御性写法）。
-- 真正起作用的是下面这段 on_file_loaded 的守卫，去掉它本测试必报错。
local function live_timers()
    local n = 0
    for _, t in ipairs(periodic) do if not t.dead then n = n + 1 end end
    return n
end
local function count_of(name)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
    return n
end
check("标记后没有存活定时器", live_timers(), 0)
ps.on_file_loaded(fake_state.search_state.current_path)
tick()
check("已标记过的视频再次打开 → 不再挂 auto 定时器", live_timers(), 0)
check("已标记过的视频再次打开 → 不重复标记", count_of("mark_episode_watched"), 1)

-- ============================================================================
print(string.rep("-", 76))
print("== 6. 清除缓存 ==")
setup({})
fully_ready()
ps.clear_cache()
check("clear_cache 会清 bangumi_user 的剧集缓存", call_names(), "clear_episode_cache")

setup({ no_bangumi_user = true })
ps.clear_cache()
check("没有 bangumi_user 时 clear_cache 不崩", #calls, 0)

-- ============================================================================
print(string.rep("-", 76))
print(string.format("通过 %d，失败 %d", pass, fail))
if fail > 0 then
    print("结果：有断言未通过 ❌")
    os.exit(1)
end
print("结果：全部通过 ✅")
