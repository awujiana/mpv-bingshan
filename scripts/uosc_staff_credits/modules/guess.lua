-- modules/guess.lua
-- 文件名/标题解析模块
-- 从播放路径中提取 标题 / 季数 / 集数，用于 Bangumi 搜索
-- 遵循 ADR-10 统一 init(opts, deps) 接口
--
-- 参考 uosc_danmaku/modules/utils.lua 的 parse_title / get_episode_number 实现，
-- 简化并适配 uosc_staff_credits 的 opts.title_replace JSON 规则格式

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")

local M = {}

local opts, deps, init = require("modules.utils.module_loader").make_init(
    "guess",
    {}
)
M.init = init

-- 工具：获取路径 basename（不含扩展名）
local function basename_no_ext(path)
    if not path or path == "" then return nil end
    -- 协议路径直接返回 nil（由 media-title 兜底）
    local sep = "/"
    if path:find("\\") then sep = "\\" end
    local fname = path
    local pos = path:match("^.*()" .. sep)
    if pos and pos > 0 then
        fname = path:sub(pos + 1)
    end
    -- 去掉扩展名
    fname = fname:gsub("%.[^%.\\/]*$", "")
    return fname
end

-- 应用 opts.title_replace 规则（JSON 字符串）
-- 格式：{"rules": [{"pattern": "replacement"}, ...]}
local function apply_title_replace(title)
    if not title or title == "" then return title end
    if not opts.title_replace or opts.title_replace == "" then
        return title
    end
    local cfg = utils.parse_json(opts.title_replace)
    if type(cfg) ~= "table" then return title end
    -- cfg 可能是 {rules = {...}} 或数组形态
    local rules = cfg.rules
    if type(rules) ~= "table" then
        -- 退化：把 cfg 当作数组处理
        rules = cfg
    end
    if type(rules) ~= "table" then return title end
    for _, entry in pairs(rules) do
        if type(entry) == "table" then
            for pattern, replacement in pairs(entry) do
                local ok, _ = pcall(function()
                    title = title:gsub(pattern, replacement)
                end)
                if not ok then
                    msg.warn("[guess] invalid title_replace pattern: " .. tostring(pattern))
                end
            end
            -- 兼容 uosc_danmaku 的清理步骤
            title = title:gsub("[_%.]", " ")
                     :gsub("^%s*(.-)%s*$", "%1")
                     :gsub("[@#%.%+%-%%&*_=,/~`]+$", "")
        end
    end
    return title
end

-- 清理标题噪声：方括号、圆括号、书名号、常见分隔符
local function clean_title(s)
    if not s then return s end
    s = s:gsub("%[[^%]]*%]", " ")
         :gsub("%([^%)]*%)", " ")
         :gsub("【[^】]*】", " ")
         :gsub("《([^》]*)》", "%1")
         :gsub("〔([^〕]*)〕", "%1")
         :gsub("[%._]", " ")
         :gsub("%s+", " ")
         :gsub("^%s*(.-)%s*$", "%1")
    return s
end

-- parse_title: 从路径解析 标题/季数/集数
-- path: 视频路径（本地或 URL）。若为 nil，自动从 mp.get_property("path") 获取
-- 返回 title, season_num, episode_num（季/集为字符串形式，便于外部比较；不存在时为 nil）
function M.parse_title(path)
    if not path then
        path = mp.get_property("path")
    end
    if not path then return nil end

    local fname = basename_no_ext(path)
    -- 协议路径优先用 media-title
    local is_url = path:find("^%a[%w.+-]-://") ~= nil
    if is_url then
        local mtitle = mp.get_property("media-title")
        if mtitle and mtitle ~= "" then
            fname = mtitle
        end
    end
    if not fname or fname == "" then return nil end

    -- 细空格统一为普通空格
    local thin_space = string.char(0xE2, 0x80, 0x89)
    fname = fname:gsub(thin_space, " ")

    local season, episode
    local title_part = fname

    -- 模式 1: S\d+E\d+ 或 s\d+e\d+
    local m_title, m_s, m_e = fname:match("^(.-)%s*[sS](%d+)[%.%-%s:]?[eE](%d+[%.v]?%d*)")
    if m_s and m_e then
        title_part = m_title
        season = m_s
        episode = m_e:gsub("v%d+$", "")
    else
        -- 模式 2: [Ee]pisode.?\d+ 或 EP?\d+（匹配完整 "Episode" 单词）
        m_title, m_e = fname:match("^(.-)%s*[Ee]pisode[%s_.%-]*(%d+[%.v]?%d*)")
        if m_e then
            title_part = m_title
            episode = m_e:gsub("v%d+$", "")
        else
            -- 模式 2b: EP?\d+ 或 ep\d+（缩写形式，不消耗前字符）
            m_title, m_e = fname:match("^(.-)%s*[eEpP]+(%d+[%.v]?%d*)")
            if m_e then
                title_part = m_title
                episode = m_e:gsub("v%d+$", "")
            else
                -- 模式 3: 第\d+话 / 第\d+集 / 第\d+回
                m_title, m_e = fname:match("^(.-)%s*第%s*(%d+[%.v]?%d*)%s*[话集回]")
                if m_e then
                    title_part = m_title
                    episode = m_e:gsub("v%d+$", "")
                else
                    -- 模式 4: [\d+] （末尾方括号集数）
                    m_title, m_e = fname:match("^(.-)%s*%[(%d+[%.v]?%d*)%]")
                    if m_e then
                        title_part = m_title
                        episode = m_e:gsub("v%d+$", "")
                    else
                        -- 模式 5: Season \d+ 形式
                        m_title, m_s = fname:match("^(.-)[%s_%-]?[sS]eason[%s_%-]*(%d+)")
                        if m_s then
                            title_part = m_title
                            season = m_s
                        end
                    end
                end
            end
        end
    end

    -- 兜底：本地文件取父目录名作为标题
    if (not title_part or title_part == "") and not is_url then
        local parent = nil
        local ok, result = pcall(function()
            return mp.command_native({"normalize-path", path})
        end)
        if ok and type(result) == "string" and result ~= "" then
            parent = utils.split_path(result)
        else
            parent = utils.split_path(path)
        end
        if parent then
            -- 去掉末尾分隔符后再 split 一次，得到目录名
            local _, dir_name = utils.split_path(parent:sub(1, -2))
            if dir_name and dir_name ~= "" then
                -- 跳过 Season/Specials/第X季 类目录，向上再取一层
                if dir_name:lower():match("^%s*seasons?%s*%d+%s*$")
                   or dir_name:lower():match("^%s*specials?%s*$")
                   or dir_name:match("^%s*SPs?%s*$")
                   or dir_name:match("^%s*O[VAD]+s?%s*$")
                   or dir_name:match("^%s*第.-[季部]+%s*$") then
                    local upper_dir = utils.split_path(parent:sub(1, -2))
                    if upper_dir then
                        _, dir_name = utils.split_path(upper_dir:sub(1, -2))
                    end
                end
                title_part = dir_name
            end
        end
    end

    if not title_part or title_part == "" then
        return nil
    end

    -- 清理 + 应用用户替换规则
    title_part = clean_title(title_part)
    title_part = apply_title_replace(title_part)

    return title_part, season, episode
end

-- get_episode_number: 从文件名推断集数
-- filename: 当前播放文件名（无扩展名）
-- history_fname: 可选，uosc_danmaku 历史记录中的文件名，用于推断集数偏移
-- 返回 number 或 nil
function M.get_episode_number(filename, history_fname)
    if not filename or filename == "" then return nil end
    local thin_space = string.char(0xE2, 0x80, 0x89)
    filename = filename:gsub(thin_space, " ")

    -- 若提供了历史文件名，尝试通过两者集数差值推断
    -- 这里简化为：分别从两个文件名中提取集数，若都存在则返回当前集数
    -- （uosc_danmaku 的 get_series_episodes 较复杂，这里只做基础匹配）
    local function extract_ep(s)
        if not s then return nil end
        local _, e = s:match("^.-[sS]%d+[%.%-%s:]?[eE](%d+[%.v]?%d*)")
        if e then return tonumber(e:gsub("v%d+$", "")) end
        _, e = s:match("^.-[^%ddD][eEpP]+(%d+[%.v]?%d*)")
        if e then return tonumber(e:gsub("v%d+$", "")) end
        _, e = s:match("^.-第%s*(%d+[%.v]?%d*)%s*[话集回]")
        if e then return tonumber(e:gsub("v%d+$", "")) end
        _, e = s:match("^.-[%[(%d+[%.v]?%d*)%]]")
        if e then return tonumber(e:gsub("v%d+$", "")) end
        -- 纯数字结尾
        e = s:match("(%d+)%s*$")
        if e then return tonumber(e) end
        return nil
    end

    local current_ep = extract_ep(filename)
    if not current_ep then return nil end

    if history_fname and history_fname ~= "" then
        local history_ep = extract_ep(history_fname)
        -- 若历史记录有集数，且与当前文件名集数不同，说明可能有偏移
        -- 简化：直接返回当前文件名解析出的集数
        if history_ep then
            return current_ep
        end
    end

    return current_ep
end

-- best_match_by_jw: 复用 utils facade 的同名函数
-- 保留导出便于 deps.guess.best_match_by_jw 调用
local utils_mod = require("modules.utils")
M.best_match_by_jw = utils_mod.best_match_by_jw
M.jaro_winkler = utils_mod.jaro_winkler

return M
