-- osd-button 自检运行器
--
-- 用法（在 portable_config/ 目录下执行）：
--   ../luajit.exe tools/osd-button-selftest.lua
--
-- 目的：在**没有 mpv 运行时**的情况下验证 osd-button 的四条纪律。
--   osd-button.lua 顶部 require 了 mp.msg / mp.assdraw，并调用 mp.create_osd_overlay 等，
--   这里用最小 stub 顶掉，只跑 M.self_test() 的纯几何断言。
--
-- 退出码：0 = 全部通过，1 = 有失败项（可直接用于 CI）

-- ── 最小 mp 运行时 stub ──────────────────────────────────────────────
package.preload['mp.msg'] = function()
    return setmetatable({}, { __index = function() return function() end end })
end

package.preload['mp.assdraw'] = function()
    return { ass_new = function() return {} end }
end

_G.mp = {
    create_osd_overlay = function()
        return { update = function() end, remove = function() end }
    end,
    observe_property = function()
        return { unobserve = function() end }
    end,
    get_property_native = function() return nil end,
}

-- ── 定位模块（相对于本脚本所在目录的上两级）────────────────────────
local script_path = arg and arg[0] or "tools/osd-button-selftest.lua"
local dir = script_path:match("^(.*)[/\\][^/\\]*$") or "tools"
local root = dir:match("^(.*)[/\\][^/\\]*$") or "."

local module_path = root .. "/script-modules/osd-button.lua"

local chunk, err = loadfile(module_path)
if not chunk then
    -- 回退到当前工作目录（应已在 portable_config/ 下）
    chunk, err = loadfile("script-modules/osd-button.lua")
end
if not chunk then
    print("无法加载 osd-button.lua：" .. tostring(err))
    print("请在 portable_config/ 目录下执行：../luajit.exe tools/osd-button-selftest.lua")
    os.exit(1)
end

local mod = chunk()
if type(mod.self_test) ~= "function" then
    print("osd-button.lua 未导出 self_test()")
    os.exit(1)
end

-- ── 运行 ────────────────────────────────────────────────────────────
print("osd-button 纪律自检")
print("─────────────────────────────────────────")
local ok, report = mod.self_test()
print(report)
print("─────────────────────────────────────────")
print(ok and "结果：16/16 通过 —— 四条纪律成立"
          or "结果：存在失败项，请检查上面标 [FAIL] 的条目")
os.exit(ok and 0 or 1)
