---- uosc_updater.lua —— uosc 系列脚本的 GitHub 自更新驱动
--
-- 管理的组件（详见 script-modules/updater.lua）：
--   * uosc_subtitle_style   单文件脚本，跟 GitHub Release 最新资产
--   * uosc_staff_credits    多文件脚本的 git 工作副本，跟 origin/main **仅快进**
--
-- 为什么单独成一个脚本，而不是把逻辑塞进两个脚本内部：
--   1. uosc_staff_credits 是 `scripts/uosc_staff_credits/` 下的 **git 工作副本**，
--      更新方式是 `git reset --hard`——写进它内部的更新代码会被自己的更新抹掉。
--   2. 两个脚本共用同一套检查/下载/替换逻辑，放一份比抄两份可靠。
--   3. 脚本自身出错时，外部驱动仍然能把它换掉（自更新逻辑若在脚本内部，
--      脚本一崩就永远修不回来了）。
--
-- 生效时机：**更新落盘，下次启动 mpv 生效**。mpv 不支持卸载/热重载脚本
--   （只有 load-script 追加，没有 unload），所以本脚本不会尝试在运行时替换自己。
--
-- 手动触发：
--   script-message uosc-updater-check     立即检查（不等周期）
--   script-message uosc-updater-status    显示上次检查结果

local mp = require 'mp'
local msg = require 'mp.msg'

-- script-modules 不在 package.path（mpv 只把 scripts/<子目录> 加进去）
do
    local ok, p = pcall(mp.command_native, { 'expand-path', '~~/script-modules/?.lua' })
    if ok and p and p ~= '' then
        package.path = p .. ';' .. package.path
    end
end

local updater = require 'updater'

------------------------------------------------------------------ 配置

-- 用 mp.options.read_options 而不是 mp.get_opt：
-- 本机实测（mpv v0.41，--config-dir 模式）mp.get_opt 对
-- script-opts/uosc_updater.conf 里的键**一律返回 nil**（同名脚本也一样），
-- 而 read_options 会自己去打开 ~~/script-opts/<name>.conf，取值正常。
-- 这也是本项目其它脚本（uosc_subtitle_style 等）采用的方式。
local OPTIONS = {
    enabled = true,
    startup_delay = 30,
    interval_hours = 6,
    notify = true,
    update_subtitle_style = true,
    update_staff_credits = true,
    git_path = 'git',
    api_base = updater.DEFAULT_API_BASE,
}

do
    local ok, err = pcall(require('mp.options').read_options, OPTIONS, 'uosc_updater')
    if not ok then
        msg.error('uosc_updater: 读取 script-opts/uosc_updater.conf 失败，改用默认配置: '
            .. tostring(err))
        OPTIONS = {
            enabled = true, startup_delay = 30, interval_hours = 6, notify = true,
            update_subtitle_style = true, update_staff_credits = true,
            git_path = 'git', api_base = updater.DEFAULT_API_BASE,
        }
    end
end

-- 防御：conf 里留空或写错的字符串项回落到默认值
if type(OPTIONS.api_base) ~= 'string' or OPTIONS.api_base == '' then
    OPTIONS.api_base = updater.DEFAULT_API_BASE
end
if type(OPTIONS.git_path) ~= 'string' or OPTIONS.git_path == '' then
    OPTIONS.git_path = 'git'
end

------------------------------------------------------------------ 组件表

local COMPONENTS = {
    {
        name = 'uosc_subtitle_style',
        label = 'uosc_subtitle_style',
        kind = 'file',
        repo = 'awujiana/uosc_subtitle_style',
        branch = 'main',
        asset = 'uosc_subtitle_style.lua',
        target = '~~/scripts/uosc_subtitle_style.lua',
        opt = 'update_subtitle_style',
    },
    {
        name = 'uosc_staff_credits',
        label = 'uosc_staff_credits',
        kind = 'git',
        repo = 'awujiana/uosc-staff-credits',
        branch = 'main',
        dir = '~~/scripts/uosc_staff_credits',
        opt = 'update_staff_credits',
    },
}

------------------------------------------------------------------ 状态文件

local STATE_PATH = '~~/uosc-updater-state.json'
local state = { version = 1, components = {} }

local function resolve(path)
    local ok, p = pcall(mp.command_native, { 'expand-path', path })
    if not ok or not p or p == '' then return nil end
    if p:match('^%a:[/\\]') or p:sub(1, 1) == '/' or p:sub(1, 1) == '\\' then return p end
    local cwd = mp.get_property('working-directory')
    if not cwd or cwd == '' then return p end
    return cwd .. '/' .. p
end

local function load_state()
    local path = resolve(STATE_PATH)
    if not path then return end
    local f = io.open(path, 'rb')
    if not f then return end
    local body = f:read('*a')
    f:close()
    local data = updater.parse_json(body)
    if type(data) == 'table' then
        state.version = data.version or 1
        state.last_check = data.last_check
        state.components = type(data.components) == 'table' and data.components or {}
    end
end

-- 手写的极简 JSON 编码：状态文件结构固定（表里只有数字/字符串/表），
-- 用它兜底就不依赖 utils.format_json 的存在性。
local function encode(v)
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[\\"]', { ['\\'] = '\\\\', ['"'] = '\\"' }) .. '"'
    elseif t == 'number' then
        return tostring(v)
    elseif t == 'boolean' then
        return v and 'true' or 'false'
    elseif t == 'table' then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = '"' .. tostring(k) .. '":' .. encode(v[k])
        end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    return 'null'
end

local function save_state()
    local path = resolve(STATE_PATH)
    if not path then return end
    updater.write_text(path, encode(state))
end

------------------------------------------------------------------ 提示

local function osd(text, dur)
    mp.osd_message(text, dur or 5)
end

local function report(comp, res)
    local label = comp.label or comp.name
    if res.status == 'updated' then
        local from_ver = res.from_version and tostring(res.from_version) or '未知版本'
        local to_ver = res.to_version and tostring(res.to_version) or '最新版'
        msg.info(string.format('uosc_updater: %s 已更新 %s → %s', label, from_ver, to_ver))
        if OPTIONS.notify then
            osd(string.format('%s 已更新 %s → %s（重启 mpv 生效）', label, from_ver, to_ver), 6)
        end
    elseif res.status == 'uptodate' then
        msg.verbose(string.format('uosc_updater: %s 已是最新（%s）', label, tostring(res.to_version)))
    elseif res.status == 'skipped' then
        msg.warn(string.format('uosc_updater: %s 跳过更新（%s）', label, tostring(res.reason)))
    else
        msg.warn(string.format('uosc_updater: %s 检查失败（%s）', label, tostring(res.error)))
    end
end

------------------------------------------------------------------ 主循环

local busy = false

local function run_cycle(reason, done)
    if busy then
        msg.verbose('uosc_updater: 上一轮检查还没结束，跳过本次（' .. tostring(reason) .. '）')
        if done then done({ skipped_busy = true }) end
        return
    end
    if not OPTIONS.enabled then
        if done then done({ disabled = true }) end
        return
    end

    busy = true
    local opts = {
        api_base = OPTIONS.api_base,
        git = OPTIONS.git_path,
        tmp_json = resolve('~~/uosc-updater-remote.json'),
    }

    local summary = {}
    local index = 0

    local function step()
        index = index + 1
        local comp = COMPONENTS[index]
        if not comp then
            busy = false
            state.last_check = os.time()
            save_state()
            if done then done(summary) end
            return
        end
        if not OPTIONS[comp.opt] then
            step()
            return
        end
        local ok, err = pcall(updater.check_and_update, comp, state, opts, function(res)
            report(comp, res)
            summary[#summary + 1] = { name = comp.name, status = res.status, res = res }
            save_state()
            step()
        end)
        if not ok then
            msg.error('uosc_updater: ' .. comp.name .. ' 检查异常: ' .. tostring(err))
            summary[#summary + 1] = { name = comp.name, status = 'error', res = { error = tostring(err) } }
            step()
        end
    end

    step()
end

------------------------------------------------------------------ 手动命令

mp.register_script_message('uosc-updater-check', function()
    osd('正在检查脚本更新…', 2)
    run_cycle('manual', function(summary)
        if summary.skipped_busy or summary.disabled then return end
        local parts = {}
        for _, item in ipairs(summary) do
            local r = item.res or {}
            if item.status == 'updated' then
                parts[#parts + 1] = item.name .. ' → ' .. tostring(r.to_version) .. '（重启生效）'
            elseif item.status == 'uptodate' then
                parts[#parts + 1] = item.name .. ' 已最新'
            elseif item.status == 'skipped' then
                parts[#parts + 1] = item.name .. ' 跳过'
            else
                parts[#parts + 1] = item.name .. ' 失败'
            end
        end
        osd('更新检查：' .. (#parts > 0 and table.concat(parts, '；') or '无组件启用'), 6)
    end)
end)

mp.register_script_message('uosc-updater-status', function()
    local lines = {}
    local stamp = state.last_check
    if stamp then
        lines[#lines + 1] = '上次检查 ' .. os.date('%m-%d %H:%M', stamp)
    else
        lines[#lines + 1] = '尚未检查过'
    end
    for _, comp in ipairs(COMPONENTS) do
        local st = state.components[comp.name]
        if st and st.tag then
            lines[#lines + 1] = (comp.label or comp.name) .. ' ' .. tostring(st.tag)
        end
    end
    osd(table.concat(lines, '｜'), 6)
end)

------------------------------------------------------------------ 启动

load_state()

do
    local delay = OPTIONS.startup_delay or 30
    if delay < 0 then delay = 0 end
    mp.add_timeout(delay, function() run_cycle('startup') end)

    local hours = OPTIONS.interval_hours or 6
    if hours > 0 then
        mp.add_periodic_timer(hours * 3600, function() run_cycle('periodic') end)
    end
end

msg.verbose('uosc_updater: 已加载，组件 ' .. #COMPONENTS .. ' 个')
