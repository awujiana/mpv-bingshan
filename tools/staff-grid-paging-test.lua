-- tools/staff-grid-paging-test.lua —— staff_grid 翻页回调的运行时回归测试
--
-- 用法（任意 cwd 均可 —— 路径基准由脚本自身位置推导）：
--   ./luajit.exe portable_config/tools/staff-grid-paging-test.lua
--
-- 为什么需要它（2026-10-06）：
--   staff_grid.lua 里 render 曾被写成 `local function render()`，位置在
--   page_up / page_down **之后**。Lua 的局部量作用域从声明语句之后才开始，
--   于是两个翻页函数体内的 `render()` 被编译成**全局读取**：
--       staff_grid.lua:114: attempt to call global 'render' (a nil value)
--       staff_grid.lua:130: attempt to call global 'render' (a nil value)
--   触发条件很普通：职员表条目多到能翻页时按 LEFT/RIGHT，或点翻页箭头。
--   已改成标准前向声明（先 `local render`，后 `render = function() ... end`）。
--
--   为什么不能只靠静态检查：静态工具能指出「这里有可疑引用」，但**证明不了**
--   它真的会崩 —— 也可能分支永远走不到。所以这里用真调用兜底：
--   捕获模块注册的按键回调，构造足够多的条目让翻页分支可达，然后真按下去。
--
--   注意 40 个条目**测不出来**（visible_count 一屏装得下 → max_offset=0 →
--   翻页分支提前 return）。必须给足够多的条目，否则测试会「静静地通过」。

-- ============================================================================
-- stub mp：捕获按键回调
-- ============================================================================
local keys = {}
local overlay = {
    data = "", visible = false,
    update = function(self) return self end,
    remove = function(self) return self end,
    resolve = function() end,
}

package.preload["mp"] = function()
    return {
        get_property = function(_, d) return d end,
        get_property_number = function(n, d)
            if n == "osd-width" then return 1920 end
            if n == "osd-height" then return 1080 end
            return d
        end,
        get_property_native = function(_, d) return d end,
        set_property = function() end,
        command = function() end,
        commandv = function() end,
        command_native = function() return {} end,
        add_forced_key_binding = function(_, name, fn) keys[name] = fn return true end,
        add_key_binding = function(_, name, fn) keys[name] = fn return true end,
        remove_key_binding = function() end,
        observe_property = function() end,
        unobserve_property = function() end,
        add_timeout = function() return { kill = function() end } end,
        cancel_timer = function() end,
        create_osd_overlay = function() return overlay end,
        register_script_message = function() end,
        unregister_script_message = function() end,
        get_time = function() return 0 end,
        msg = setmetatable({}, { __index = function() return function() end end }),
        utils = { parse_json = function() return nil end, format_json = function() return "{}" end },
    }
end
package.preload["mp.msg"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.preload["mp.utils"] = function()
    return { parse_json = function() return nil end, format_json = function() return "{}" end }
end

-- ---- 路径基准：从脚本自身位置反推，使本测试与 cwd 无关 ----
-- 脚本位于 <mpv根>/portable_config/tools/，故上溯一级即 portable_config。
local _src = debug.getinfo(1, "S").source or "@."
local _tools_dir = _src:match("^@(.*)[/\\][^/\\]*$") or "."
local _pc = _tools_dir:match("^(.*)[/\\][^/\\]*$") or "."
package.path = _pc .. "/scripts/uosc_staff_credits/?.lua;"
    .. _pc .. "/scripts/uosc_staff_credits/?/init.lua;" .. package.path

local ui_base = require("modules.ui_base")
local grid = require("modules.staff_grid")

local ass_lib = {
    get_osd_size = function() return 1920, 1080 end,
    ass_escape = function(s) return tostring(s) end,
    hex_to_ass = function(s) return tostring(s) end,
    draw_rect = function() return "" end,
    draw = function() end,
    append = function() end,
    create_ass = function() return "" end,
    text_width = function() return 10 end,
}
local noop = function() end

grid.init({}, {
    ui_base = ui_base,
    panel_registry = { register = noop, unregister = noop },
    input_service = { enable = noop, disable = noop },
    ass_lib = ass_lib,
    notify = { info = noop, warn = noop, error = noop, debug = noop },
    utils = {},
    loading_controller = { nuclear_menu_dismiss = noop },
})

-- ============================================================================
-- 断言
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
print("== staff_grid 翻页回调 ==")

-- 条目必须多到一屏装不下，否则翻页分支不可达，测试会假通过
local items = {}
for i = 1, 500 do items[i] = { name = "角色" .. i } end

local ok_show, err_show = pcall(grid.show, items, "测试职员表")
check("grid.show 成功（500 条）", ok_show, true)
if not ok_show then print("         " .. tostring(err_show)) end

for _, name in ipairs({ "staff_grid-right", "staff_grid-left" }) do
    local fn = keys[name]
    check(name .. " 已注册按键回调", type(fn), "function")
    if type(fn) == "function" then
        -- 关键断言：render 必须是**上值**（局部量），不能是全局读取
        local info = debug.getinfo(fn, "u")
        local has_render = false
        for i = 1, info.nups do
            if (debug.getupvalue(fn, i)) == "render" then has_render = true end
        end
        check(name .. " 把 render 捕获为上值（而非全局）", has_render, true)

        local ok_call, err_call = pcall(fn)
        check(name .. " 调用不报错", ok_call, true)
        if not ok_call then print("         " .. tostring(err_call)) end
    end
end

print(string.rep("-", 76))
print(string.format("通过 %d，失败 %d", pass, fail))
if fail > 0 then
    print("结果：有断言未通过 ❌")
    os.exit(1)
end
print("结果：全部通过 ✅")
