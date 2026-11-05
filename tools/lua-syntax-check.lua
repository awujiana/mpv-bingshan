-- 语法检查工具：用 mpv 自带的 luajit 校验本目录下所有 .lua 文件
--
-- 用法（在本文件所在目录执行，即 portable_config/）：
--   ../luajit.exe tools/lua-syntax-check.lua
--
-- 说明：
--   本项目目录里没有独立安装 Lua，直接复用 mpv 自带的 luajit.exe
--   （位于 portable_config 的上一级目录，即 mpv.exe 同目录）。
--   仅做语法解析（loadstring），不执行文件，因此不需要 mp 运行时环境。
--
-- 2026-10-05 修正：原先只扫 scripts/ 一个根目录，导致 script-modules/、
--   osc-style/ 等同样会被 mpv 加载的 .lua 成为检查盲区
--   （新建的 script-modules/osd-button.lua 就正好落在盲区里）。
--   现改为扫描多个根目录，并自动跳过第三方/依赖目录。

local ROOTS = {
    "scripts",
    "script-modules",
    "osc-style",
}

-- 这些目录不检查：第三方依赖、缓存、版本控制
local EXCLUDE = {
    "[/\\]node_modules[/\\]",
    "[/\\]%.git[/\\]",
    "[/\\]cache[/\\]",
}

local function is_excluded(path)
    for _, pat in ipairs(EXCLUDE) do
        if path:find(pat) then return true end
    end
    return false
end

-- 递归收集 .lua 文件
local function collect(dir, out)
    local p = io.popen('dir /b /s "' .. dir .. '\\*.lua" 2>nul')
    if not p then return end
    for line in p:lines() do
        local path = line:match("^%s*(.-)%s*$")
        if path and path ~= "" and not is_excluded(path) then
            out[#out + 1] = path
        end
    end
    p:close()
end

local files = {}
for _, root in ipairs(ROOTS) do
    collect(root, files)
end

if #files == 0 then
    print("未找到 .lua 文件，请确认在 portable_config/ 目录下执行")
    os.exit(1)
end

local ok_cnt, fail_cnt = 0, 0
local failed = {}

for _, path in ipairs(files) do
    local f = io.open(path, "rb")
    if not f then
        fail_cnt = fail_cnt + 1
        failed[#failed + 1] = path .. "\n    无法读取文件"
    else
        local src = f:read("*a")
        f:close()
        local chunk, err = loadstring(src, "@" .. path)
        if chunk then
            ok_cnt = ok_cnt + 1
        else
            fail_cnt = fail_cnt + 1
            failed[#failed + 1] = path .. "\n    " .. tostring(err)
        end
    end
end

for _, msg in ipairs(failed) do
    print("FAIL " .. msg)
end

print(string.format("\n语法检查完成：共 %d 个文件，OK %d，FAIL %d",
    #files, ok_cnt, fail_cnt))

os.exit(fail_cnt == 0 and 0 or 1)
