-- updater-test.lua —— script-modules/updater.lua + scripts/uosc_updater.lua 的单元测试
-- 用法（在 portable_config/ 下执行）：
--   ../luajit.exe tools/updater-test.lua
-- 判据：exit code 0 且汇总行 PASS=… FAIL=0。
--
-- 覆盖重点（都是「出错会毁用户文件」的路径，不是覆盖率凑数）：
--   * 版本比较的数值语义（1.0.9 < 1.0.10，不能用字符串比）
--   * file 型：正常安装 / 快速跳过 / 内容相同不写盘 / 尺寸不符拒绝 / 非 Lua 拒绝
--   * file 型：API 不可达时回退 version.json
--   * git 型：已最新 / 可快进 / 工作区脏跳过 / 非快进跳过 / 非仓库报错
--   * 任何拒绝路径都必须保证**原文件未被改动**

local ROOT = 'C:/fake'

local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(string.format('%s %s%s', ok and 'PASS' or 'FAIL', name,
        detail and (' | ' .. tostring(detail)) or ''))
end

------------------------------------------------------------------ 环境桩

local env = {}

local function reset_env()
    env.files = {}          -- path -> content（虚拟文件系统）
    env.renames = {}
    env.removals = {}
    env.calls = {}          -- 记录所有子进程 argv
    env.api = nil           -- {status=, body=}
    env.version_json = nil  -- {status=, body=}
    env.asset = nil         -- {status=, content=}
    env.git = {
        is_repo = true,
        dirty = false,
        head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        fetch_head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ff = true,
        reset_ok = true,
        status = 0,
    }
end

local function fake_sub(args)
    env.calls[#env.calls + 1] = table.concat(args, ' ')

    if args[1] == 'curl' then
        local dest, url
        for i = 2, #args do
            if args[i] == '-o' then dest = args[i + 1] end
        end
        url = args[#args]
        local resp
        if url:find('/releases/latest', 1, true) then
            resp = env.api
        elseif url:find('version.json', 1, true) then
            resp = env.version_json
        else
            resp = env.asset
        end
        if not resp then return { status = 6, stdout = '', stderr = 'could not resolve host' } end
        if resp.status ~= 0 then
            return { status = resp.status, stdout = '', stderr = resp.stderr or 'curl failed' }
        end
        if dest and resp.content then env.files[dest] = resp.content end
        return { status = 0, stdout = '', stderr = '' }
    end

    if args[1] == 'git' then
        -- git -C <dir> <sub> ...
        local sub = {}
        for i = 4, #args do sub[#sub + 1] = args[i] end
        local g = env.git
        if sub[1] == 'rev-parse' and sub[2] == '--is-inside-work-tree' then
            if not g.is_repo then return { status = 128, stdout = '', stderr = 'not a git repository' } end
            return { status = 0, stdout = 'true\n', stderr = '' }
        elseif sub[1] == 'status' then
            return { status = 0, stdout = g.dirty and ' M modules/x.lua\n' or '', stderr = '' }
        elseif sub[1] == 'fetch' then
            if g.status ~= 0 then return { status = g.status, stdout = '', stderr = 'fetch failed' } end
            return { status = 0, stdout = '', stderr = '' }
        elseif sub[1] == 'rev-parse' and sub[2] == 'HEAD' then
            return { status = 0, stdout = g.head .. '\n', stderr = '' }
        elseif sub[1] == 'rev-parse' and sub[2] == 'FETCH_HEAD' then
            return { status = 0, stdout = g.fetch_head .. '\n', stderr = '' }
        elseif sub[1] == 'merge-base' then
            return { status = g.ff and 0 or 1, stdout = '', stderr = '' }
        elseif sub[1] == 'reset' then
            if not g.reset_ok then return { status = 1, stdout = '', stderr = 'reset failed' } end
            g.head = g.fetch_head
            return { status = 0, stdout = '', stderr = '' }
        end
        return { status = 1, stdout = '', stderr = 'unsupported: ' .. table.concat(sub, ' ') }
    end

    return { status = 127, stdout = '', stderr = 'command not found' }
end

local real_mp_global = rawget(_G, 'mp')
local real_io_open = io.open
local real_os_rename = os.rename
local real_os_remove = os.remove

local function install_stubs()
    local mp_stub = {}
    function mp_stub.command_native(t)
        if type(t) == 'table' and t[1] == 'expand-path' then
            local p = t[2]
            if p:sub(1, 2) == '~~' then return ROOT .. p:sub(3) end
            return p
        end
        return nil
    end
    function mp_stub.command_native_async(t, cb)
        cb(true, fake_sub(t.args or {}), nil)
        return true
    end
    function mp_stub.get_property(name)
        if name == 'working-directory' then return ROOT end
        return nil
    end
    function mp_stub.get_opt() return nil end
    function mp_stub.osd_message() end
    function mp_stub.add_timeout() end
    function mp_stub.add_periodic_timer() end
    function mp_stub.register_script_message() end

    rawset(_G, 'mp', mp_stub)
    package.loaded['mp'] = mp_stub
    package.loaded['mp.msg'] = {
        info = function() end, warn = function() end, error = function() end,
        verbose = function() end, debug = function() end,
    }
    package.loaded['mp.utils'] = {
        parse_json = function(s)
            -- 测试用固定几种 JSON，手写解析太啰嗦，直接用最小实现
            local ok, v = pcall(function() return dofile(ROOT .. '/_json.lua') and nil end)
            return nil
        end,
    }

    io.open = function(path, mode)
        mode = mode or 'r'
        if mode:find('w') then
            local buf = {}
            return {
                write = function(_, s) buf[#buf + 1] = s end,
                close = function() env.files[path] = table.concat(buf) end,
            }
        end
        local content = env.files[path]
        if content == nil then return nil, 'no such file: ' .. tostring(path) end
        local pos = 1
        return {
            read = function(_, fmt)
                if fmt == '*a' or fmt == 'a' then
                    local r = content:sub(pos)
                    pos = #content + 1
                    return r
                end
                return nil
            end,
            seek = function(_, whence)
                if whence == 'end' then pos = #content + 1; return #content end
                if whence == 'set' then pos = 1; return 0 end
                return pos - 1
            end,
            close = function() end,
        }
    end

    os.rename = function(a, b)
        if env.files[a] == nil then return nil, 'no source' end
        env.files[b] = env.files[a]
        env.files[a] = nil
        env.renames[#env.renames + 1] = a .. ' -> ' .. b
        return true
    end
    os.remove = function(p)
        env.removals[#env.removals + 1] = p
        env.files[p] = nil
        return true
    end
end

local function uninstall_stubs()
    io.open = real_io_open
    os.rename = real_os_rename
    os.remove = real_os_remove
    if real_mp_global ~= nil then rawset(_G, 'mp', real_mp_global) else rawset(_G, 'mp', nil) end
    package.loaded['mp'] = nil
    package.loaded['mp.msg'] = nil
    package.loaded['mp.utils'] = nil
end

------------------------------------------------------------------ 真实 JSON 解析
-- utils.parse_json 在桩里必须是真的（模块拿它解 GitHub 响应）。
-- 这里塞一个够用的最小实现：对象/数组/字符串/数字/true/false/null。

local function json_decode(s)
    local pos = 1
    local function skip() while pos <= #s and s:sub(pos, pos):match('%s') do pos = pos + 1 end end
    local parse_value
    local function parse_string()
        pos = pos + 1
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == '' then error('unterminated string') end
            if c == '\\' then
                local n = s:sub(pos + 1, pos + 1)
                out[#out + 1] = ({ n = '\n', t = '\t', ['\\'] = '\\', ['"'] = '"' })[n] or n
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end
    parse_value = function()
        skip()
        local c = s:sub(pos, pos)
        if c == '"' then return parse_string() end
        if c == '{' then
            pos = pos + 1
            local obj = {}
            skip()
            if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while true do
                skip()
                local k = parse_string()
                skip()
                if s:sub(pos, pos) ~= ':' then error('expected :') end
                pos = pos + 1
                obj[k] = parse_value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == '}' then return obj end
                if d ~= ',' then error('expected , or }') end
            end
        end
        if c == '[' then
            pos = pos + 1
            local arr = {}
            skip()
            if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while true do
                arr[#arr + 1] = parse_value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == ']' then return arr end
                if d ~= ',' then error('expected , or ]') end
            end
        end
        if s:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true end
        if s:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false end
        if s:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil end
        local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
        if num and num ~= '' then pos = pos + #num; return tonumber(num) end
        error('unexpected char at ' .. pos .. ': ' .. c)
    end
    local v = parse_value()
    return v
end

------------------------------------------------------------------ 载入被测模块

reset_env()
install_stubs()
package.loaded['mp.utils'].parse_json = json_decode

local ok_mod, updater = pcall(dofile, 'script-modules/updater.lua')
if not ok_mod then
    uninstall_stubs()
    print('FATAL 无法载入 script-modules/updater.lua: ' .. tostring(updater))
    os.exit(1)
end

------------------------------------------------------------------ 辅助

local function new_state() return { version = 1, components = {} } end

local function lua_body(tag)
    return '-- fake script ' .. tag .. '\n' .. string.rep('-- pad\n', 100)
end

local function api_json(tag, asset_name, size, url)
    return string.format(
        '{"tag_name":"%s","assets":[{"name":"%s","size":%d,"browser_download_url":"%s"}]}',
        tag, asset_name, size, url)
end

local FILE_COMP = {
    name = 'demo_file',
    kind = 'file',
    repo = 'owner/demo',
    asset = 'demo.lua',
    target = '~~/scripts/demo.lua',
}
local GIT_COMP = {
    name = 'demo_git',
    kind = 'git',
    repo = 'owner/demo-git',
    dir = '~~/scripts/demo_git',
    branch = 'main',
}

local function run(comp, state)
    local result
    updater.check_and_update(comp, state, { git = 'git', tmp_json = ROOT .. '/remote.json' },
        function(res) result = res end)
    return result
end

------------------------------------------------------------------ 1. 版本比较

check('compare-1.0.9-lt-1.0.10', updater.compare_version('v1.0.9', 'v1.0.10') == -1,
    '字符串比较会把 1.0.10 判成更小')
check('compare-equal-padding', updater.compare_version('1.0', '1.0.0') == 0)
check('compare-greater', updater.compare_version('v1.12.0', 'v1.2.0') == 1)
check('parse-version', table.concat(updater.parse_version('v1.12.3'), '.') == '1.12.3')

------------------------------------------------------------------ 2. 组件校验

do
    local c, err = updater.make_component({ name = 'x', kind = 'file', repo = 'a/b' })
    check('component-reject-missing-asset', c == nil and err == 'missing asset', err)
    local c2 = updater.make_component({ name = 'x', kind = 'git', repo = 'a/b', dir = '~~/d' })
    check('component-git-default-branch', c2 and c2.branch == 'main', c2 and c2.branch)
end

------------------------------------------------------------------ 3. file 型：正常安装

do
    reset_env()
    local state = new_state()
    local body = lua_body('v1.0.6')
    env.files[ROOT .. '/scripts/demo.lua'] = lua_body('v1.0.5')
    env.api = { status = 0, content = api_json('v1.0.6', 'demo.lua', #body,
        'https://example.test/demo.lua') }
    env.asset = { status = 0, content = body }

    local res = run(FILE_COMP, state)
    check('file-update-status', res and res.status == 'updated', res and res.status)
    check('file-update-content', env.files[ROOT .. '/scripts/demo.lua'] == body)
    check('file-update-no-bak', env.files[ROOT .. '/scripts/demo.lua.bak'] == nil,
        '不保留 .bak 备份')
    check('file-update-no-swap-left', env.files[ROOT .. '/scripts/demo.lua.tmpbak'] == nil,
        '中转文件必须删掉')
    check('file-update-state', state.components.demo_file
        and state.components.demo_file.tag == 'v1.0.6'
        and state.components.demo_file.size == #body)
    check('file-update-cleanup-tmp', env.files[ROOT .. '/scripts/demo.lua.new'] == nil)
end

------------------------------------------------------------------ 4. file 型：状态一致时快速跳过（不应下载资产）

do
    reset_env()
    local state = new_state()
    local body = lua_body('v1.0.6')
    env.files[ROOT .. '/scripts/demo.lua'] = body
    env.api = { status = 0, content = api_json('v1.0.6', 'demo.lua', #body,
        'https://example.test/demo.lua') }
    env.asset = { status = 0, content = body }
    state.components.demo_file = { tag = 'v1.0.6', size = #body, version = '1.0.6' }

    local res = run(FILE_COMP, state)
    check('file-fastpath-uptodate', res and res.status == 'uptodate', res and res.status)
    local downloaded = false
    for _, c in ipairs(env.calls) do
        if c:find('example.test', 1, true) then downloaded = true end
    end
    check('file-fastpath-no-download', not downloaded, '状态一致时不应再拉 100KB 资产')
end

------------------------------------------------------------------ 5. file 型：内容相同则只补状态，不写盘

do
    reset_env()
    local state = new_state()
    local body = lua_body('v1.0.6')
    env.files[ROOT .. '/scripts/demo.lua'] = body
    env.api = { status = 0, content = api_json('v1.0.6', 'demo.lua', #body,
        'https://example.test/demo.lua') }
    env.asset = { status = 0, content = body }

    local res = run(FILE_COMP, state)
    check('file-identical-uptodate', res and res.status == 'uptodate', res and res.status)
    check('file-identical-no-rename', #env.renames == 0, table.concat(env.renames, ','))
    check('file-identical-state-fixed', state.components.demo_file
        and state.components.demo_file.tag == 'v1.0.6')
end

------------------------------------------------------------------ 6. file 型：尺寸不符 → 拒绝且不动原文件

do
    reset_env()
    local state = new_state()
    local old = lua_body('v1.0.5')
    env.files[ROOT .. '/scripts/demo.lua'] = old
    local body = lua_body('v1.0.6')
    env.api = { status = 0, content = api_json('v1.0.6', 'demo.lua', #body + 500,
        'https://example.test/demo.lua') }
    env.asset = { status = 0, content = body }

    local res = run(FILE_COMP, state)
    check('file-size-mismatch-error', res and res.status == 'error', res and res.status)
    check('file-size-mismatch-untouched', env.files[ROOT .. '/scripts/demo.lua'] == old)
    check('file-size-mismatch-no-backup', env.files[ROOT .. '/scripts/demo.lua.bak'] == nil)
    check('file-size-mismatch-no-leftover',
        env.files[ROOT .. '/scripts/demo.lua.new'] == nil
        and env.files[ROOT .. '/scripts/demo.lua.tmpbak'] == nil,
        '拒绝路径也必须清掉暂存文件')
end

------------------------------------------------------------------ 7. file 型：下载到 HTML 错误页 → 拒绝

do
    reset_env()
    local state = new_state()
    local old = lua_body('v1.0.5')
    env.files[ROOT .. '/scripts/demo.lua'] = old
    local html = '<!DOCTYPE html><html>' .. string.rep('x', 2000) .. '</html>'
    env.api = { status = 0, content = api_json('v1.0.6', 'demo.lua', #html,
        'https://example.test/demo.lua') }
    env.asset = { status = 0, content = html }

    local res = run(FILE_COMP, state)
    check('file-not-lua-rejected', res and res.status == 'error', res and res.status)
    check('file-not-lua-untouched', env.files[ROOT .. '/scripts/demo.lua'] == old)
end

------------------------------------------------------------------ 8. file 型：API 挂了 → 回退 version.json

do
    reset_env()
    local state = new_state()
    local body = lua_body('v1.0.7')
    env.files[ROOT .. '/scripts/demo.lua'] = lua_body('v1.0.5')
    env.api = { status = 22, stderr = 'HTTP 403' }
    env.version_json = { status = 0, content = '{"version":"1.0.7","name":"demo"}' }
    env.asset = { status = 0, content = body }

    local res = run(FILE_COMP, state)
    check('file-fallback-updated', res and res.status == 'updated', res and res.status)
    local used_version_json = false
    for _, c in ipairs(env.calls) do
        if c:find('version.json', 1, true) then used_version_json = true end
    end
    check('file-fallback-used-version-json', used_version_json)
    check('file-fallback-content', env.files[ROOT .. '/scripts/demo.lua'] == body)
end

------------------------------------------------------------------ 9. file 型：本地文件缺失 → 全新安装

do
    reset_env()
    local state = new_state()
    local body = lua_body('v1.0.6')
    env.api = { status = 0, content = api_json('v1.0.6', 'demo.lua', #body,
        'https://example.test/demo.lua') }
    env.asset = { status = 0, content = body }

    local res = run(FILE_COMP, state)
    check('file-fresh-install', res and res.status == 'updated', res and res.status)
    check('file-fresh-no-backup', env.files[ROOT .. '/scripts/demo.lua.bak'] == nil)
    check('file-fresh-content', env.files[ROOT .. '/scripts/demo.lua'] == body)
end

------------------------------------------------------------------ 10. git 型：已最新

do
    reset_env()
    local state = new_state()
    env.git.head = 'abc1234'
    env.git.fetch_head = 'abc1234'
    local res = run(GIT_COMP, state)
    check('git-uptodate', res and res.status == 'uptodate', res and res.status)
    local reset_called = false
    for _, c in ipairs(env.calls) do
        if c:find('reset', 1, true) then reset_called = true end
    end
    check('git-uptodate-no-reset', not reset_called)
end

------------------------------------------------------------------ 11. git 型：可快进 → reset

do
    reset_env()
    local state = new_state()
    env.git.head = 'aaa1111'
    env.git.fetch_head = 'bbb2222'
    env.git.ff = true
    local res = run(GIT_COMP, state)
    check('git-ff-updated', res and res.status == 'updated', res and res.status)
    check('git-ff-state', state.components.demo_git
        and state.components.demo_git.tag == 'bbb2222')
end

------------------------------------------------------------------ 12. git 型：工作区脏 → 跳过（且不 fetch）

do
    reset_env()
    local state = new_state()
    env.git.dirty = true
    env.git.head = 'aaa1111'
    env.git.fetch_head = 'bbb2222'
    local res = run(GIT_COMP, state)
    check('git-dirty-skipped', res and res.status == 'skipped', res and res.status)
    local fetched = false
    for _, c in ipairs(env.calls) do
        if c:find(' fetch ', 1, true) then fetched = true end
    end
    check('git-dirty-no-fetch', not fetched)
end

------------------------------------------------------------------ 13. git 型：非快进 → 跳过（不 reset）

do
    reset_env()
    local state = new_state()
    env.git.head = 'aaa1111'
    env.git.fetch_head = 'bbb2222'
    env.git.ff = false
    local res = run(GIT_COMP, state)
    check('git-diverged-skipped', res and res.status == 'skipped', res and res.status)
    local reset_called = false
    for _, c in ipairs(env.calls) do
        if c:find('reset', 1, true) then reset_called = true end
    end
    check('git-diverged-no-reset', not reset_called, '非快进绝不能 reset --hard')
end

------------------------------------------------------------------ 14. git 型：不是仓库 → 报错

do
    reset_env()
    local state = new_state()
    env.git.is_repo = false
    local res = run(GIT_COMP, state)
    check('git-not-repo-error', res and res.status == 'error', res and res.status)
end

------------------------------------------------------------------ 15. git 型：fetch 失败 → 报错

do
    reset_env()
    local state = new_state()
    env.git.status = 128
    local res = run(GIT_COMP, state)
    check('git-fetch-error', res and res.status == 'error', res and res.status)
end

uninstall_stubs()

print(string.format('\n汇总：PASS=%d FAIL=%d', pass, fail))
if fail > 0 then
    print('HAS_FAIL')
    os.exit(1)
end
print('ALL_OK')
