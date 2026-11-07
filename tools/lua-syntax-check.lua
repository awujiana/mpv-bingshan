-- 语法检查工具：用 mpv 自带的 luajit 校验本目录下所有 .lua 文件
--
-- 用法（在仓库根执行，即 portable_config/ 或独立脚本仓库根）：
--   luajit tools/lua-syntax-check.lua
--   路径一律按相对路径读取，因此仓库位于中文目录时也能正常工作。
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
    -- 真机探针同样是会被 mpv 加载的 Lua，语法错误只有跑到 E2E 才暴露；
    -- 纳入静态门禁，让新增探针在提交前就被 loadstring 校验。
    "tools",
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

-- cmd 的 `dir /b /s` 返回绝对路径。若仓库放在中文 / 非 ASCII 目录下，
-- Lua 5.1 的 io.open 在 Windows 上无法按控制台编码打开这段绝对路径
-- （独立公开仓库 D:\编程\uosc_subtitle_style 实测报「无法读取文件」）。
-- 解决办法：从 `cd` 取同编码的当前目录前缀并剥掉，之后一律用相对路径读取。
local CWD = ''
do
    local p = io.popen('cd')
    if p then
        CWD = (p:read('*l') or ''):match('^%s*(.-)%s*$')
        p:close()
    end
end

local function to_relative(path)
    local prefix = CWD .. '\\'
    if CWD ~= '' and path:sub(1, #prefix):lower() == prefix:lower() then
        return path:sub(#prefix + 1)
    end
    return path
end

-- 递归收集 .lua 文件
local function collect(dir, out)
    local p = io.popen('dir /b /s "' .. dir .. '\\*.lua" 2>nul')
    if not p then return end
    for line in p:lines() do
        local path = line:match("^%s*(.-)%s*$")
        if path and path ~= "" then
            path = to_relative(path)
            if not is_excluded(path) then
                out[#out + 1] = path
            end
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
