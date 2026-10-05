-- apis/fankuhub.lua
-- fankuhub 聚合数据源 API 封装
-- 一次请求返回角色 + 声优 + 图片，减少 Bangumi 多次请求开销
-- 遵循 ADR-10 统一 init(opts, deps) 接口

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")

local M = {}

local opts, deps, init = require("modules.utils.module_loader").make_init(
    "fankuhub",
    {notify = "table", request_registry = "table"}
)
M.init = init

-- 引用基础设施
local utils_mod = require("modules.utils")
local url_mod = require("modules.utils.url")
local net_mod = require("modules.utils.net")

-- 错误码
local ERR_NETWORK = "ERR_NETWORK"
local ERR_PARSE = "ERR_PARSE"
local ERR_EMPTY = "ERR_EMPTY"

local function make_error(code, m)
    return { code = code or ERR_PARSE, msg = tostring(m or "") }
end

-- http_get_json: 本地 HTTP GET + JSON 解析辅助
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
        playback_only = false,
        args = args,
    }, function(success, result, error)
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

    local registered_token = nil
    if deps and deps.request_registry and type(deps.request_registry.register) == "function" then
        registered_token = deps.request_registry.register(function()
            pcall(function() mp.abort_async_command(abort_handle) end)
        end)
    end
end

-- get_api_base: 获取 fankuhub API base URL
local function get_api_base()
    return opts.fankuhub_api_base or "https://fankuhub.com"
end

-- search: 搜索动漫（聚合源）
-- GET {opts.fankuhub_api_base}/api/v1/anime/search?q={urlencode(title)}
-- 响应包含 characters with CV 和 images in one request
-- callback(success, data, err_info)
-- data: list of {id, name, name_cn, characters: [{id, name, relation, images, actors: [{id, name, img}]}]}
function M.search(title, callback)
    if not title or title == "" then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty title")) end
        return
    end

    local api_base = get_api_base()
    local encoded = url_mod.url_encode(title)
    local url = string.format("%s/api/v1/anime/search?q=%s", api_base, encoded)

    http_get_json(url, function(success, data, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end
        if not data then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "empty response")) end
            return
        end

        -- 响应可能是数组或 {data: [...]} 结构
        local items = data
        if data.data and type(data.data) == "table" then
            items = data.data
        end
        if type(items) ~= "table" then
            if callback then callback(false, nil, make_error(ERR_PARSE, "invalid response structure")) end
            return
        end

        -- 标准化每条结果
        local results = {}
        for _, item in ipairs(items) do
            if type(item) == "table" then
                local entry = {
                    id = item.id,
                    -- name 优先级：name → titleJa → titleEn → titleRomaji → title → "未知条目"
                    name = item.name or item.titleJa or item.titleEn
                        or item.titleRomaji or item.title or "未知条目",
                    -- name_cn 优先级：name_cn → titleZh → nameCn（可能为 nil）
                    name_cn = item.name_cn or item.titleZh or item.nameCn,
                    characters = {},
                }
                -- 解析 characters
                if item.characters and type(item.characters) == "table" then
                    for _, char in ipairs(item.characters) do
                        if type(char) == "table" then
                            -- v1.9.6: 修复角色图片缺失
                            --   fankuhub search API 返回的角色图片字段为 imageUrl（字符串），
                            --   而非 images（对象）。此前直接拷贝 char.images 始终为 nil，
                            --   导致 cards.lua 的 has_character_image() 返回 false，
                            --   全部角色被归入"无图"组（底部文字区而非卡片网格）。
                            --   同时补充 name_cn/nameCn 字段（此前遗漏）。
                            local char_images = char.images
                            -- fankuhub imageUrl 字符串 → 构造 bangumi 兼容 {medium=url} 格式
                            if not char_images and type(char.imageUrl) == "string" and char.imageUrl ~= "" then
                                char_images = { medium = char.imageUrl }
                            end
                            local char_entry = {
                                id = char.id,
                                name = char.name,
                                name_cn = char.name_cn or char.nameCn,
                                relation = char.relation,
                                images = char_images,
                                actors = {},
                            }
                            -- 解析 actors
                            if char.actors and type(char.actors) == "table" then
                                for _, actor in ipairs(char.actors) do
                                    if type(actor) == "table" then
                                        table.insert(char_entry.actors, {
                                            id = actor.id,
                                            name = actor.name,
                                            name_cn = actor.name_cn or actor.nameCn,
                                            img = actor.img or actor.imageUrl,
                                        })
                                    end
                                end
                            end
                            -- fankuhub voiceActors 兼容
                            if char.voiceActors and type(char.voiceActors) == "table" then
                                for _, actor in ipairs(char.voiceActors) do
                                    if type(actor) == "table" then
                                        table.insert(char_entry.actors, {
                                            id = actor.id,
                                            name = actor.name,
                                            name_cn = actor.nameCn or actor.name_cn,
                                            img = actor.imageUrl or actor.img,
                                        })
                                    end
                                end
                            end
                            table.insert(entry.characters, char_entry)
                        end
                    end
                end
                table.insert(results, entry)
            end
        end

        if #results == 0 then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "no results")) end
            return
        end

        if callback then callback(true, results, nil) end
    end)
end

-- search_by_person: 通过人员名搜索
-- 注：fankuhub 官方 API 无独立人员搜索端点，复用 anime/search 搜索作品后由调用方从 staff 提取
-- GET {opts.fankuhub_api_base}/api/v1/anime/search?q={urlencode(name)}
-- callback(success, data, err_info)
function M.search_by_person(name, callback)
    if not name or name == "" then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty name")) end
        return
    end

    local api_base = get_api_base()
    local encoded = url_mod.url_encode(name)
    local url = string.format("%s/api/v1/anime/search?q=%s", api_base, encoded)

    http_get_json(url, function(success, data, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end
        if not data then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "empty response")) end
            return
        end

        local items = data
        if data.data and type(data.data) == "table" then
            items = data.data
        end

        if callback then callback(true, items, nil) end
    end)
end

-- get_subject_detail: 获取条目详情
-- GET {opts.fankuhub_api_base}/api/v1/anime/{id}
-- callback(success, detail, err_info)
function M.get_subject_detail(subject_id, callback)
    if not subject_id then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty subject_id")) end
        return
    end

    local api_base = get_api_base()
    local url = string.format("%s/api/v1/anime/%s", api_base, tostring(subject_id))

    http_get_json(url, function(success, data, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end
        if not data then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "empty response")) end
            return
        end

        local detail = data
        if data.data and type(data.data) == "table" then
            detail = data.data
        end

        if callback then callback(true, detail, nil) end
    end)
end

-- ============ v1.6: bangumi 兼容适配函数 ============
-- 当 bangumi 全部失败、fankuhub fallback 成功后，subject._source == "fankuhub"。
-- 此时 subject.id 是 fankuhub 字符串 id，不能直接调用 bangumi 的 persons/characters 接口。
-- 以下函数调用 fankuhub get_subject_detail，将返回数据转换为 bangumi 兼容格式。

-- get_subject_persons_compatible: 获取职员（bangumi 兼容格式）
-- 调用 fankuhub 详情接口，从 staff 数组提取并转换为 bangumi persons 格式
-- 返回格式与 api.get_subject_persons 一致：[{id, name, name_cn, type=2, relation, images}]
-- subject_id: fankuhub 条目 id（字符串）
-- callback(success, persons, err_info)
function M.get_subject_persons_compatible(subject_id, callback)
    if not subject_id then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty subject_id")) end
        return
    end

    M.get_subject_detail(subject_id, function(success, detail, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end

        local persons = {}
        if detail and type(detail.staff) == "table" then
            for _, s in ipairs(detail.staff) do
                if type(s) == "table" and s.name then
                    -- positions 数组转字符串（bangumi 用 relation 字符串）
                    local relation = ""
                    if type(s.positions) == "table" and #s.positions > 0 then
                        relation = table.concat(s.positions, "、")
                    end
                    table.insert(persons, {
                        id = s.bangumiId or s.id,  -- 优先用 bangumiId 供后续 get_person_works 使用
                        name = s.name,
                        name_cn = s.nameCn,
                        type = 2,  -- CHAR_TYPE_STAFF
                        relation = relation,
                        images = s.imageUrl and { medium = s.imageUrl } or nil,
                    })
                end
            end
        end

        if callback then callback(true, persons, nil) end
    end)
end

-- get_subject_characters_compatible: 获取角色（bangumi 兼容格式）
-- 调用 fankuhub 详情接口，从 characters 数组提取并转换为 bangumi characters 格式
-- 返回格式与 api.get_subject_characters 一致：[{id, name, name_cn, type=1, images, actors:[{id, name, images}]}]
-- subject_id: fankuhub 条目 id（字符串）
-- callback(success, characters, err_info)
function M.get_subject_characters_compatible(subject_id, callback)
    if not subject_id then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty subject_id")) end
        return
    end

    M.get_subject_detail(subject_id, function(success, detail, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end

        local characters = {}
        if detail and type(detail.characters) == "table" then
            for _, c in ipairs(detail.characters) do
                if type(c) == "table" and c.name then
                    local actors = {}
                    -- fankuhub 用 voiceActors 字段
                    if type(c.voiceActors) == "table" then
                        for _, va in ipairs(c.voiceActors) do
                            if type(va) == "table" and va.name then
                                table.insert(actors, {
                                    id = va.bangumiId or va.id,
                                    name = va.name,
                                    name_cn = va.nameCn,
                                    images = va.imageUrl and { medium = va.imageUrl } or nil,
                                })
                            end
                        end
                    end
                    -- 兼容旧字段 actors
                    if type(c.actors) == "table" then
                        for _, va in ipairs(c.actors) do
                            if type(va) == "table" and va.name then
                                table.insert(actors, {
                                    id = va.bangumiId or va.id,
                                    name = va.name,
                                    name_cn = va.nameCn,
                                    images = va.img and { medium = va.img } or nil,
                                })
                            end
                        end
                    end
                    table.insert(characters, {
                        id = c.id,
                        name = c.name,
                        name_cn = c.nameCn,
                        type = 1,  -- CHAR_TYPE_CHARACTER
                        images = c.imageUrl and { medium = c.imageUrl } or nil,
                        actors = actors,
                        relation = c.relation,
                    })
                end
            end
        end

        if callback then callback(true, characters, nil) end
    end)
end

-- get_subject_detail_compatible: 获取条目详情（bangumi 兼容格式）
-- 调用 fankuhub 详情接口，转换为 bangumi detail 格式
-- 返回格式与 api.get_subject_detail 一致：{id, name, name_cn, summary, images, ...}
-- subject_id: fankuhub 条目 id（字符串）
-- callback(success, detail, err_info)
function M.get_subject_detail_compatible(subject_id, callback)
    if not subject_id then
        if callback then callback(false, nil, make_error(ERR_EMPTY, "empty subject_id")) end
        return
    end

    M.get_subject_detail(subject_id, function(success, detail, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end

        if not detail or type(detail) ~= "table" then
            if callback then callback(false, nil, make_error(ERR_EMPTY, "empty detail")) end
            return
        end

        -- 转换为 bangumi detail 兼容格式
        local compatible = {
            id = detail.id,
            name = detail.titleJa or detail.titleEn or detail.titleRomaji or detail.titleZh or "未知条目",
            name_cn = detail.titleZh or detail.titleJa,
            summary = detail.synopsis or "",
            images = detail.coverUrl and { large = detail.coverUrl, medium = detail.coverUrl, common = detail.coverUrl } or nil,
            -- 保留原始 fankuhub 字段供 cover_intro 使用
            _fankuhub_raw = detail,
            _source = "fankuhub",
        }

        if callback then callback(true, compatible, nil) end
    end)
end

return M
