---- updater.lua —— GitHub 自更新公共模块（mpv Lua 脚本侧）
--
-- 设计约束（本机实测，mpv v0.41）：
--   * mpv 的 Lua 环境**没有 HTTP 客户端**，`utils.read_file` / `utils.write_file`
--     在本机也是 nil ⇒ 网络一律经 curl 子进程（Windows 10 1803+ 自带 curl.exe），
--     文件 IO 用 io.open 二进制模式。
--   * 所有子进程都走 `command_native_async`，**绝不阻塞播放线程**
--     （同步 subprocess 遇到网络抖动会把画面卡住好几秒）。
--   * 本模块只做「检查 / 下载 / 安装 / 记录」，**不弹 OSD、不排定时器**——
--     调度与提示由 scripts/uosc_updater.lua 负责，这样逻辑才能被单测覆盖。
--   * 安装前一律先写同目录的 `.new` 暂存文件并校验（尺寸、Lua 头），
--     通过后才替换原文件；替换用「临时中转名 + rename」保证失败可回滚，
--     中转文件在成功后立即删除 ⇒ **不保留 .bak 备份**，目录里不留多余文件。
--
-- 两种组件形态：
--   kind = 'file'  单文件脚本，跟 GitHub Release 的最新资产（uosc_subtitle_style）
--   kind = 'git'   多文件脚本的 git 工作副本，跟 origin/<branch> **仅快进**
--                  （uosc_staff_credits；非快进一律跳过，绝不动用户的本地提交）
--
-- 远端信息来源：
--   1. 主路径：`{api_base}/repos/{repo}/releases/latest`（含资产 url/size）
--   2. 回退：仓库根 `version.json`（raw），再用 `releases/download/v{ver}/{asset}`
--      拼出资产地址（api.github.com 在部分地区不可达时的兜底；仅在 api_base
--      保持默认值时才启用）

local mp = require 'mp'
local utils = require 'mp.utils'

local M = {}

M.VERSION = '1.0.0'
M.USER_AGENT = 'uosc-updater/1.0 (mpv script)'
M.DEFAULT_API_BASE = 'https://api.github.com'
M.RAW_VERSION = 'https://raw.githubusercontent.com/%s/%s/version.json'
M.RELEASE_ASSET = 'https://github.com/%s/releases/download/v%s/%s'

------------------------------------------------------------------ 基础工具

-- parse_json 的防御包装：远端内容永远可能是脏的
function M.parse_json(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, data = pcall(utils.parse_json, s)
    if ok and type(data) == 'table' then return data end
    return nil
end

-- 把 `~~/...` 展开成实际路径；返回 nil 表示展开失败
function M.expand(path)
    if type(path) ~= 'string' or path == '' then return nil end
    if path:sub(1, 2) == '~~' then
        local ok, p = pcall(mp.command_native, { 'expand-path', path })
        if not ok or not p or p == '' then return nil end
        return p
    end
    return path
end

-- expand-path 在 `--config-dir` 传相对路径时会返回相对路径，而 mpv 有
-- `--working-directory`（会按文件切 CWD）⇒ 统一补成绝对路径，子进程才稳定。
function M.absolutize(path)
    if type(path) ~= 'string' or path == '' then return nil end
    if path:match('^%a:[/\\]') or path:sub(1, 1) == '/' or path:sub(1, 1) == '\\' then
        return path
    end
    local cwd = mp.get_property and mp.get_property('working-directory')
    if not cwd or cwd == '' then return path end
    return cwd .. '/' .. path
end

function M.file_size(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local size = f:seek('end')
    f:close()
    return size
end

function M.read_text(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

function M.write_text(path, data)
    local f = io.open(path, 'wb')
    if not f then return false, 'open failed: ' .. tostring(path) end
    f:write(data)
    f:close()
    return true
end

------------------------------------------------------------------ 子进程

-- run(args, cb)：异步执行子进程。cb(spawned, res, err)
--   spawned=false 表示进程都没起来（git/curl 不存在等），err 是原因；
--   spawned=true 时 res.status 才是退出码，由调用方判断。
function M.run(args, cb)
    local ok, err = pcall(mp.command_native_async, {
        name = 'subprocess',
        args = args,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, res, e)
        if not success then cb(false, nil, tostring(e)) return end
        cb(true, res or {})
    end)
    if not ok then cb(false, nil, tostring(err)) end
end

-- run_ok(args, cb)：cb(ok, res, err)，ok 为「起来了且退出码 0」
function M.run_ok(args, cb)
    M.run(args, function(spawned, res, err)
        if not spawned then cb(false, nil, err) return end
        if (res.status or -1) ~= 0 then
            local detail = (res.stderr or ''):gsub('%s+$', '')
            if detail == '' then detail = (res.stdout or ''):gsub('%s+$', '') end
            cb(false, res, detail:sub(1, 300))
            return
        end
        cb(true, res)
    end)
end

-- curl 下载到文件（-f 让 4xx/5xx 直接失败，不会把错误页写成文件）
function M.curl_to_file(url, dest, cb)
    M.run_ok({
        'curl', '-fsSL',
        '--connect-timeout', '8',
        '--max-time', '30',
        '-H', 'User-Agent: ' .. M.USER_AGENT,
        '-o', dest, url,
    }, cb)
end

------------------------------------------------------------------ 版本比较

-- 'v1.0.5' / '1.12.0' → {1,0,5} / {1,12,0}
function M.parse_version(s)
    local nums = {}
    for n in tostring(s or ''):gmatch('%d+') do
        nums[#nums + 1] = tonumber(n)
    end
    return nums
end

-- 返回 -1 / 0 / 1；缺位按 0 补（1.0 == 1.0.0）
function M.compare_version(a, b)
    local A, B = M.parse_version(a), M.parse_version(b)
    local n = math.max(#A, #B)
    for i = 1, n do
        local x, y = A[i] or 0, B[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

------------------------------------------------------------------ 组件规范化

-- spec 必填：name / kind / repo；kind='file' 还需 asset + target；
-- kind='git' 还需 dir（可选 branch，默认 main）
function M.make_component(spec)
    local c = {}
    for k, v in pairs(spec or {}) do c[k] = v end
    if type(c.name) ~= 'string' or c.name == '' then return nil, 'missing name' end
    if type(c.repo) ~= 'string' or c.repo == '' then return nil, 'missing repo' end
    if c.kind == 'file' then
        if type(c.asset) ~= 'string' or c.asset == '' then return nil, 'missing asset' end
        if type(c.target) ~= 'string' or c.target == '' then return nil, 'missing target' end
    elseif c.kind == 'git' then
        if type(c.dir) ~= 'string' or c.dir == '' then return nil, 'missing dir' end
        c.branch = c.branch or 'main'
    else
        return nil, 'bad kind: ' .. tostring(c.kind)
    end
    return c
end

------------------------------------------------------------------ file 型

-- 取远端 release 信息。cb(ok, info, err)
-- info = { tag, version, assets = { [name] = {url, size} }, source }
local function fetch_release(comp, opts, cb)
    local api_base = (opts.api_base or M.DEFAULT_API_BASE):gsub('/+$', '')
    local url = api_base .. '/repos/' .. comp.repo .. '/releases/latest'
    local tmp = opts.tmp_json

    M.curl_to_file(url, tmp, function(ok, _res, err)
        if ok then
            local data = M.parse_json(M.read_text(tmp))
            if data and data.tag_name then
                local assets = {}
                for _, a in ipairs(data.assets or {}) do
                    if a.name and a.browser_download_url then
                        assets[a.name] = {
                            url = a.browser_download_url,
                            size = tonumber(a.size) or 0,
                        }
                    end
                end
                cb(true, {
                    tag = data.tag_name,
                    version = tostring(data.tag_name):gsub('^[vV]', ''),
                    assets = assets,
                    source = 'api',
                })
                return
            end
            err = 'release JSON 解析失败'
        end

        -- 回退只在默认 API 下启用（自定义 api_base 说明用户自己搭了源）
        if api_base ~= M.DEFAULT_API_BASE then
            cb(false, nil, err or 'API 请求失败')
            return
        end
        local vurl = string.format(M.RAW_VERSION, comp.repo, comp.branch or 'main')
        M.curl_to_file(vurl, tmp, function(ok2, _r2, err2)
            if not ok2 then cb(false, nil, err2 or err or '版本检查失败') return end
            local data = M.parse_json(M.read_text(tmp))
            if not (data and data.version) then
                cb(false, nil, 'version.json 解析失败')
                return
            end
            local ver = tostring(data.version)
            cb(true, {
                tag = 'v' .. ver,
                version = ver,
                -- 回退路径拿不到 size ⇒ 0 表示「不做尺寸预判」，靠下载后比对内容
                assets = { [comp.asset] = {
                    url = string.format(M.RELEASE_ASSET, comp.repo, ver, comp.asset),
                    size = 0,
                } },
                source = 'version.json',
            })
        end)
    end)
end

local function check_file(comp, state, opts, cb)
    local target = M.absolutize(M.expand(comp.target))
    if not target then
        cb({ status = 'error', error = '无法解析目标路径: ' .. tostring(comp.target) })
        return
    end

    fetch_release(comp, opts, function(ok, info, err)
        if not ok then
            cb({ status = 'error', error = err or '检查失败' })
            return
        end
        local asset = info.assets[comp.asset]
        if not asset then
            cb({ status = 'error', error = 'Release 中找不到资产 ' .. comp.asset })
            return
        end

        local st = state.components[comp.name] or {}
        local local_size = M.file_size(target)

        -- 快速判定：状态记录的 tag/size 与远端一致，且本地文件尺寸没变
        -- ⇒ 完全跳过下载（避免每轮都拉 100KB）
        if local_size and st.tag == info.tag and st.size and local_size == st.size
            and (asset.size == 0 or asset.size == st.size) then
            st.checked_at = os.time()
            state.components[comp.name] = st
            cb({ status = 'uptodate', from_version = info.version, to_version = info.version })
            return
        end

        local tmp = target .. '.new'
        M.curl_to_file(asset.url, tmp, function(ok2, _r2, err2)
            if not ok2 then
                cb({ status = 'error', error = '下载失败: ' .. tostring(err2) })
                return
            end

            local nsize = M.file_size(tmp)
            if not nsize or nsize < 512 then
                os.remove(tmp)
                cb({ status = 'error', error = '下载内容过小，已丢弃' })
                return
            end
            if asset.size > 0 and nsize ~= asset.size then
                os.remove(tmp)
                cb({ status = 'error',
                    error = string.format('尺寸不符（期望 %d，实际 %d），已丢弃', asset.size, nsize) })
                return
            end
            local new = M.read_text(tmp) or ''
            if new:sub(1, 2) ~= '--' then
                os.remove(tmp)
                cb({ status = 'error', error = '下载内容不是 Lua 脚本，已丢弃' })
                return
            end

            -- 与本地逐字节比较：相同说明只是状态文件丢了，不写盘
            local old = local_size and M.read_text(target) or nil
            if old and old == new then
                os.remove(tmp)
                st.tag = info.tag
                st.size = nsize
                st.version = info.version
                st.checked_at = os.time()
                state.components[comp.name] = st
                cb({ status = 'uptodate', from_version = info.version, to_version = info.version })
                return
            end

            -- 替换：**不保留 .bak 备份**。旧文件先挪成临时中转名（只为失败回滚），
            -- 新文件就位后立刻删掉中转文件 ⇒ 正常路径下目录里不留任何多余文件。
            local prev = st.tag
            local swap = target .. '.tmpbak'
            os.remove(swap)
            local moved = old and os.rename(target, swap) or true
            local installed = false
            if moved then
                installed = os.rename(tmp, target) and true or false
            end
            if not installed then
                if moved and old then os.rename(swap, target) end
                os.remove(tmp)
                cb({ status = 'error', error = '替换失败（文件被占用？），已回滚' })
                return
            end
            if moved and old then os.remove(swap) end

            st.tag = info.tag
            st.size = nsize
            st.version = info.version
            st.checked_at = os.time()
            st.updated_at = os.time()
            state.components[comp.name] = st
            cb({ status = 'updated', from_version = prev, to_version = info.version, size = nsize })
        end)
    end)
end

------------------------------------------------------------------ git 型

local function check_git(comp, state, opts, cb)
    local dir = M.absolutize(M.expand(comp.dir))
    if not dir then
        cb({ status = 'error', error = '无法解析目录: ' .. tostring(comp.dir) })
        return
    end
    local exe = opts.git or 'git'
    local branch = comp.branch or 'main'

    local function run(argv, next)
        local args = { exe, '-C', dir }
        for _, a in ipairs(argv) do args[#args + 1] = a end
        M.run_ok(args, next)
    end

    run({ 'rev-parse', '--is-inside-work-tree' }, function(ok, _res, err)
        if not ok then
            cb({ status = 'error', error = '不是 git 工作副本或 git 不可用: ' .. tostring(err) })
            return
        end

        run({ 'status', '--porcelain' }, function(ok2, res2, err2)
            if not ok2 then
                cb({ status = 'error', error = 'git status 失败: ' .. tostring(err2) })
                return
            end
            if (res2.stdout or ''):match('%S') then
                cb({ status = 'skipped', reason = '工作区有未提交改动，跳过' })
                return
            end

            run({ 'fetch', '--quiet', 'origin', branch }, function(ok3, _r3, err3)
                if not ok3 then
                    cb({ status = 'error', error = 'fetch 失败: ' .. tostring(err3) })
                    return
                end

                run({ 'rev-parse', 'HEAD' }, function(ok4, res4)
                    local head = ok4 and res4 and (res4.stdout or ''):match('%x+') or nil
                    run({ 'rev-parse', 'FETCH_HEAD' }, function(ok5, res5)
                        local remote = ok5 and res5 and (res5.stdout or ''):match('%x+') or nil
                        if not head or not remote then
                            cb({ status = 'error', error = '读取提交号失败' })
                            return
                        end
                        if head == remote then
                            local st = state.components[comp.name] or {}
                            st.tag = head:sub(1, 7)
                            st.checked_at = os.time()
                            state.components[comp.name] = st
                            cb({ status = 'uptodate',
                                from_version = head:sub(1, 7), to_version = remote:sub(1, 7) })
                            return
                        end

                        -- 只做快进：HEAD 必须是 FETCH_HEAD 的祖先，否则跳过
                        run({ 'merge-base', '--is-ancestor', 'HEAD', 'FETCH_HEAD' }, function(ok6)
                            if not ok6 then
                                cb({ status = 'skipped', reason = '本地有额外提交（非快进），跳过' })
                                return
                            end
                            run({ 'reset', '--hard', '--quiet', 'FETCH_HEAD' }, function(ok7, _r7, err7)
                                if not ok7 then
                                    cb({ status = 'error', error = 'reset 失败: ' .. tostring(err7) })
                                    return
                                end
                                local st = state.components[comp.name] or {}
                                st.tag = remote:sub(1, 7)
                                st.version = remote:sub(1, 7)
                                st.checked_at = os.time()
                                st.updated_at = os.time()
                                state.components[comp.name] = st
                                cb({ status = 'updated',
                                    from_version = head:sub(1, 7), to_version = remote:sub(1, 7) })
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end

------------------------------------------------------------------ 对外入口

-- 检查并（按需）更新一个组件。cb(result)
-- result.status ∈ 'uptodate' | 'updated' | 'skipped' | 'error'
function M.check_and_update(comp, state, opts, cb)
    opts = opts or {}
    state.components = state.components or {}
    if comp.kind == 'file' then
        return check_file(comp, state, opts, cb)
    elseif comp.kind == 'git' then
        return check_git(comp, state, opts, cb)
    end
    cb({ status = 'error', error = '未知组件类型: ' .. tostring(comp.kind) })
end

return M
