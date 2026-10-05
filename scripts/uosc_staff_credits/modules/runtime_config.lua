-- modules/runtime_config.lua
-- 运行时配置持久化模块
-- 持久化到 ~~/staff-credits-runtime-config.json，合并优先级: runtime_config > opts > defaults
-- 遵循 ADR-10 统一 init(opts, deps) 接口；持久化采用 200ms 防抖 + 临时文件原子替换

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")

local M = {}

local opts, deps, init = require("modules.utils.module_loader").make_init(
    "runtime_config",
    { notify = "table" }
)
M.init = init

local CONFIG_FILE = "~~/staff-credits-runtime-config.json"
local runtime_data = {}
local persist_timer = nil

-- 持久化（200ms 防抖，临时文件 + rename 原子写入）
local function persist()
    if persist_timer then
        pcall(function() mp.cancel_timer(persist_timer) end)
    end
    persist_timer = mp.add_timeout(0.2, function()
        persist_timer = nil
        local path = mp.command_native({"command", "expand-path", CONFIG_FILE})
        if not path or path == "" then return end
        local tmp_path = path .. ".tmp"
        local json_str = utils.format_json(runtime_data)
        local f = io.open(tmp_path, "w")
        if not f then return end
        f:write(json_str)
        f:close()
        os.remove(path)
        local ok = os.rename(tmp_path, path)
        if not ok then
            pcall(function() os.remove(tmp_path) end)
        end
    end)
end

-- 覆盖 init：先调用 base_init 注入 opts/deps，再触发 load
local base_init = init
function M.init(new_opts, new_deps)
    base_init(new_opts, new_deps)
    M.load()
end

-- load: 读取持久化文件到内存表；文件不存在或解析失败时静默返回空表
function M.load()
    runtime_data = {}
    local path = mp.command_native({"command", "expand-path", CONFIG_FILE})
    if not path or path == "" then return end
    local f = io.open(path, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return end
    local ok, data = pcall(utils.parse_json, content)
    if ok and type(data) == "table" then
        runtime_data = data
    end
end

-- save: 更新单个配置项并持久化（200ms 防抖）；同时更新 opts 运行时值
-- key: string；value: string/number/boolean
function M.save(key, value)
    if type(key) ~= "string" or key == "" then return end
    runtime_data[key] = value
    if type(opts) == "table" then
        opts[key] = value
    end
    persist()
end

-- get: 获取配置项（合并优先级: runtime_config > opts > defaults），无则 nil
function M.get(key)
    if runtime_data[key] ~= nil then
        return runtime_data[key]
    end
    if type(opts) == "table" then
        return opts[key]
    end
    return nil
end

-- get_all: 获取所有运行时配置（返回 runtime_data 表的浅拷贝）
function M.get_all()
    local copy = {}
    for k, v in pairs(runtime_data) do
        copy[k] = v
    end
    return copy
end

return M
