-- apis/dandanplay.lua
-- dandanplay 弹幕库搜索 API 封装
-- 通过 dandanplay 的 search/episodes 接口获取番剧中文名候选
-- 用于增强 Bangumi 搜索的候选标题
-- 遵循 ADR-10 统一 init(opts, deps) 接口

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")

local M = {}

local opts, deps, init = require("modules.utils.module_loader").make_init(
    "dandanplay",
    {notify = "table", request_registry = "table"}
)
M.init = init

-- 引用基础设施
local utils_mod = require("modules.utils")
local url_mod = require("modules.utils.url")
local net_mod = require("modules.utils.net")

-- 错误码（与 api.lua 一致，便于上层统一处理）
local ERR_NETWORK = "ERR_NETWORK"
local ERR_PARSE = "ERR_PARSE"
local ERR_EMPTY = "ERR_EMPTY"

local function make_error(code, m)
    return { code = code or ERR_PARSE, msg = tostring(m or "") }
end

-- http_get_json: 本地 HTTP GET + JSON 解析辅助
-- url: 请求 URL
-- callback(success, data, err_info)
local function http_get_json(url, callback)
    if not url or url == "" then
        if callback then callback(false, nil, make_error(ERR_NETWORK, "empty url")) end
        return
    end

    local timeout = tonumber(opts.timeout) or 10
    local user_agent = opts.user_agent or "uosc_staff_credits"

    local args = {
        "curl", "-sL", "--fail",
        "--max-time", tostring(timeout),
        "-H", "User-Agent: " .. user_agent,
    }
    -- v1.6: SSL/TLS 选项（修复 Windows curl exit code 35）
    local ssl_args = net_mod.build_ssl_args(opts)
    for _, a in ipairs(ssl_args) do table.insert(args, a) end
    table.insert(args, url)

    local abort_handle = mp.command_native_async({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,  -- 用户交互请求不依赖播放状态
        args = args,
    }, function(success, result, error)
        -- 请求完成：注销 cancel_fn
        if registered_token and deps and deps.request_registry and type(deps.request_registry.unregister) == "function" then
            pcall(deps.request_registry.unregister, registered_token)
        end

        if not success or not result or result.status ~= 0 then
            local err_msg = error or "request failed"
            -- 识别常见 curl 退出码
            if result and result.status and result.status ~= 0 then
                if result.status == 28 then
                    err_msg = "请求超时（curl exit code 28），请检查网络或增大 timeout 配置"
                elseif result.status == 6 then
                    err_msg = "DNS 解析失败（curl exit code 6）"
                elseif result.status == 7 then
                    err_msg = "无法连接服务器（curl exit code 7）"
                else
                    err_msg = "curl exit code: " .. tostring(result.status)
                end
            end
            if result and result.stderr and result.stderr ~= "" then
                err_msg = err_msg .. " | " .. result.stderr
            end
            if callback then callback(false, nil, make_error(ERR_NETWORK, err_msg)) end
            return
        end

        local body = result.stdout or ""
        if body == "" then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "empty body")) end
            return
        end

        local data = utils.parse_json(body)
        if type(data) ~= "table" then
            if callback then callback(false, nil, make_error(ERR_PARSE, "json parse failed")) end
            return
        end

        if callback then callback(true, data, nil) end
    end)

    -- 注册 cancel_fn 到 request_registry
    local registered_token = nil
    if deps and deps.request_registry and type(deps.request_registry.register) == "function" then
        registered_token = deps.request_registry.register(function()
            pcall(function() mp.abort_async_command(abort_handle) end)
        end)
    end
end

-- search: 搜索 dandanplay 弹幕库
-- GET {opts.danmaku_api_server}/api/v2/search/episodes?anime={urlencode(title)}
-- 响应解析：data.animes[].animeTitle
-- callback(success, candidates, err_info)
-- candidates: list of animeTitle strings
function M.search(title, callback)
    if not title or title == "" then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty title")) end
        return
    end

    local api_base = opts.danmaku_api_server or "https://api.dandanplay.net"
    local encoded = url_mod.url_encode(title)
    local url = string.format("%s/api/v2/search/episodes?anime=%s", api_base, encoded)

    http_get_json(url, function(success, data, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end
        if not data or not data.animes then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "no animes in response")) end
            return
        end

        local candidates = {}
        for _, anime in ipairs(data.animes) do
            if anime.animeTitle and anime.animeTitle ~= "" then
                table.insert(candidates, anime.animeTitle)
            end
        end

        if #candidates == 0 then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "no animeTitle found")) end
            return
        end

        if callback then callback(true, candidates, nil) end
    end)
end

return M
