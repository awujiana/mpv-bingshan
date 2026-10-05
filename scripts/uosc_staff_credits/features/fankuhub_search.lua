-- features/fankuhub_search.lua
-- 番库搜索 feature：封装 fankuhub API 的搜索入口
-- 提供条目搜索 / 人员搜索两个用例，自动填入中文标题
-- 遵循 ADR-09：dispatcher 仅路由，业务下沉 features
-- 使用 make_feature_init（无 opts）

local mp = require("mp")

local M = {}

local deps, init = require("modules.utils.module_loader").make_feature_init(
    "fankuhub_search",
    {
        notify = "table",
        fankuhub = "table",
        name_resolver = "table",
        menu = "table",
        state = "table",
        search_pipeline = "table",
        request_registry = "table",
        history = "table",
        get_danmaku_info = "function",
        get_current_title = "function",
        cards = "table",
    }
)
M.init = init

-- ============ 内部辅助 ============

local function make_err(code, m)
    return { code = code or "ERR_EMPTY", msg = tostring(m or "") }
end

-- 规范化 fankuhub 搜索结果，补全展示字段
local function normalize_results(results)
    if type(results) ~= "table" then return {} end
    local out = {}
    for _, item in ipairs(results) do
        if type(item) == "table" then
            local name = item.name_cn or item.name or item.titleJa or item.title
            table.insert(out, {
                id = item.id,
                name = item.name or item.titleJa or item.title,
                name_cn = item.name_cn or item.titleZh or item.nameCn,
                url = item.url,
                type = item.type,
                images = item.images,
                characters = item.characters,
                _source = "fankuhub",
            })
        end
    end
    return out
end

-- ============ 公共接口 ============

-- search: fankuhub 条目搜索入口（数据层）
-- query: 搜索关键词
-- callback(success, results, err_info)
-- results: 规范化后的条目列表
function M.search(query, callback)
    if not deps.fankuhub or type(deps.fankuhub.search) ~= "function" then
        if callback then callback(false, nil, make_err("ERR_NETWORK", "fankuhub 模块未就绪")) end
        return
    end
    if not query or query == "" then
        if callback then callback(false, nil, make_err("ERR_EMPTY", "搜索关键词为空")) end
        return
    end

    deps.fankuhub.search(query, function(success, data, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end
        local results = normalize_results(data)
        if #results == 0 then
            if callback then callback(false, nil, make_err("ERR_EMPTY", "fankuhub 无匹配结果")) end
            return
        end
        if callback then callback(true, results, nil) end
    end)
end

-- search_by_person: fankuhub 人员搜索入口（数据层）
-- name: 人员名称
-- callback(success, results, err_info)
function M.search_by_person(name, callback)
    if not deps.fankuhub or type(deps.fankuhub.search_by_person) ~= "function" then
        if callback then callback(false, nil, make_err("ERR_NETWORK", "fankuhub 模块未就绪")) end
        return
    end
    if not name or name == "" then
        if callback then callback(false, nil, make_err("ERR_EMPTY", "人员名称为空")) end
        return
    end

    deps.fankuhub.search_by_person(name, function(success, data, err_info)
        if not success then
            if callback then callback(false, nil, err_info) end
            return
        end
        if not data or (type(data) == "table" and #data == 0) then
            if callback then callback(false, nil, make_err("ERR_EMPTY", "fankuhub 无匹配人员")) end
            return
        end
        if callback then callback(true, data, nil) end
    end)
end

-- ============ UI 层接口 ============

-- show_search_panel: 展示番库搜索面板，自动填入中文标题
-- suggestion: 预填建议（可为 nil，nil 时自动获取）
-- source: 数据源标识（"fankuhub" 或 "fankuhub_person"）
-- 流程：
--   1. 获取原始 suggestion（调用统一接口 resolve_title_sync，4 级优先级）
--   2. 立即显示面板
--   3. 异步调用 resolve_chinese_title 转换为中文，转换成功后 update_menu 更新
-- v1.6: 复用 search_pipeline.resolve_title_sync 统一标题获取逻辑
--       （独立于 uosc_danmaku，未暴露时也能通过文件名解析 + 中文转换获取中文标题）
function M.show_search_panel(suggestion, source)
    if deps.notify and deps.notify.set_tag then deps.notify.set_tag("番库搜索") end
    if not deps.menu or type(deps.menu.show_search_panel) ~= "function" then
        if deps.notify then deps.notify.error("菜单模块未就绪") end
        return
    end
    source = source or "fankuhub"

    -- 1. 获取原始 suggestion（4 级优先级，统一接口）
    if (not suggestion or suggestion == "")
       and deps.search_pipeline
       and type(deps.search_pipeline.resolve_title_sync) == "function" then
        suggestion = deps.search_pipeline.resolve_title_sync()
    end

    -- 2. 立即显示面板
    deps.menu.show_search_panel(suggestion, source)

    -- 3. 异步转换为中文标题
    if suggestion and suggestion ~= ""
       and deps.search_pipeline
       and type(deps.search_pipeline.resolve_chinese_title) == "function" then
        deps.search_pipeline.resolve_chinese_title(suggestion, function(chinese_title)
            if chinese_title and chinese_title ~= ""
               and chinese_title ~= suggestion then
                -- 同类型菜单用 update-menu 避免闪烁
                deps.menu.show_search_panel(chinese_title, source)
            end
        end)
    end
end

-- search_subject: 执行番库搜索并展示结果
-- query: 搜索关键词
-- source: 数据源标识（"fankuhub" 或 "fankuhub_person"）
function M.search_subject(query, source)
    if not query or query == "" then
        if deps.notify then deps.notify.warn("搜索关键词为空") end
        return
    end

    source = source or "fankuhub"

    -- 记录最近搜索关键词
    if deps.state and type(deps.state.set_last_search_query) == "function" then
        pcall(deps.state.set_last_search_query, query)
    end

    -- 加载来源提示：搜索中
    local hint_name = (source == "fankuhub_person") and "番库人物搜索" or "番库搜索"
    if deps.notify and type(deps.notify.show_click_hint) == "function" then
        pcall(deps.notify.show_click_hint, hint_name, "搜索中...")
    end
    if deps.notify then deps.notify.info("正在搜索番库: " .. query) end

    if source == "fankuhub_person" then
        -- 人员搜索路径
        M.search_by_person(query, function(success, results, err_info)
            if not success then
                local msg_str = "番库人员搜索失败"
                if err_info and err_info.msg then msg_str = err_info.msg end
                if deps.notify then deps.notify.error(msg_str) end
                return
            end
            -- 加载来源提示：搜索完成
            if deps.notify and type(deps.notify.show_click_hint) == "function" then
                local count = (type(results) == "table") and #results or 0
                pcall(deps.notify.show_click_hint, hint_name, "从番库加载 " .. count .. " 条结果")
            end
            M.show_search_results(results, source)
        end)
    else
        -- 条目搜索路径
        M.search(query, function(success, results, err_info)
            if not success then
                local msg_str = "番库搜索失败"
                if err_info and err_info.msg then msg_str = err_info.msg end
                if deps.notify then deps.notify.error(msg_str) end
                return
            end
            -- 加载来源提示：搜索完成
            if deps.notify and type(deps.notify.show_click_hint) == "function" then
                local count = (type(results) == "table") and #results or 0
                pcall(deps.notify.show_click_hint, hint_name, "从番库加载 " .. count .. " 条结果")
            end
            M.show_search_results(results, source)
        end)
    end
end

-- show_search_results: 展示番库搜索结果列表
-- results: 搜索结果数组
-- source: 数据源标识
function M.show_search_results(results, source)
    if not deps.menu or type(deps.menu.show_search_results) ~= "function" then
        if deps.notify then deps.notify.error("菜单模块未就绪") end
        return
    end
    deps.menu.show_search_results(results, source or "fankuhub")
end

-- handle_select: 处理从番库搜索结果中选中条目
-- id: 选中的条目 id（字符串形式）
-- source: 数据源标识
-- 流程：
--   1. 用 fankuhub.get_subject_detail 获取详情（含完整 characters）
--   2. 写入缓存（state + history）
--   3. 通过 cards.show 展示角色卡片
function M.handle_select(id, source)
    if not id then
        if deps.notify then deps.notify.warn("未提供条目 id") end
        return
    end

    if not deps.fankuhub or type(deps.fankuhub.get_subject_detail) ~= "function" then
        if deps.notify then deps.notify.error("fankuhub 模块未就绪") end
        return
    end

    if deps.notify then deps.notify.info("正在获取番库条目详情...") end
    -- 加载来源提示：获取详情中
    if deps.notify and type(deps.notify.show_click_hint) == "function" then
        pcall(deps.notify.show_click_hint, "番库搜索", "加载详情中...")
    end

    deps.fankuhub.get_subject_detail(id, function(success, detail, err_info)
        if not success or not detail then
            local msg_str = "获取番库条目详情失败"
            if err_info and err_info.msg then msg_str = err_info.msg end
            if deps.notify then deps.notify.error(msg_str) end
            return
        end

        -- 加载来源提示：详情加载完成
        if deps.notify and type(deps.notify.show_click_hint) == "function" then
            pcall(deps.notify.show_click_hint, "番库搜索", "从番库加载详情")
        end

        -- 写入缓存：state + history
        local path = mp.get_property("path")
        local info = {
            id = detail.id or id,
            name = detail.name,
            name_cn = detail.name_cn,
            url = detail.url,
            _source = "fankuhub",
            _ts = mp.get_time(),
        }
        if path and deps.state and type(deps.state.set_last_subject) == "function" then
            pcall(deps.state.set_last_subject, path, info)
        end
        if path and deps.history and type(deps.history.save) == "function" then
            local path_mod = require("modules.utils.path")
            if not path_mod.is_protocol(path) then
                local ok, dir = pcall(path_mod.get_parent_directory, path)
                if ok and dir then
                    pcall(deps.history.save, dir, info)
                end
            end
        end

        -- 展示角色卡片（fankuhub 详情中已含 characters + actors + images）
        local characters = detail.characters or {}
        if #characters == 0 then
            if deps.notify then deps.notify.warn("该条目无角色信息") end
            return
        end

        -- 选中提示（无论卡片能否展示都先通知用户）
        local display_name = info.name_cn or info.name or tostring(id)
        if deps.notify then deps.notify.info("已选择番库条目: " .. display_name) end

        -- 直接调用 cards.show 展示角色卡片
        -- cards.show 的首参 new_deps 仅作签名兼容（cards 模块使用闭包注入的 deps），传本 feature deps 即可
        if deps.cards and type(deps.cards.show) == "function" then
            deps.cards.show(deps, characters, display_name)
        else
            if deps.notify then deps.notify.warn("角色卡片模块未就绪") end
        end
    end)
end

return M
