-- tools/guess-title-test.lua —— guess 模块的标题/集数解析回归测试
--
-- 用法（在 mpv 根目录）：
--   ./luajit.exe portable_config/tools/guess-title-test.lua
--   （纯 luajit 运行，stub 掉 mp API，不需要真机）
--
-- 为什么需要它（2026-10-05）：
--   实际播放「無職転生 III ～異世界行ったら本気だす～ - 09」时，
--   搜索框里填的是**整套原始文件名**，Bangumi 搜不到条目。定位到两个缺陷：
--     · 缺「 - 09」DashEpisode 模式 → 集数抽不出，标题还带着 "- 09"
--     · 标题含 ～副标题～ → 搜索关键词被污染
--   这两类问题用「看一眼代码」很难发现，必须用真实文件名跑一遍才暴露。

-- ---- stub mp API（让 guess.lua 能在纯 luajit 下加载）----
local mods = {}
local fake_mp = {
    get_property = function() return nil end,
    command_native = function() return nil end,
    msg = setmetatable({}, { __index = function() return function() end end }),
}
package.preload["mp"] = function() return fake_mp end
package.preload["mp.utils"] = function() return { split_path = function(p) return p, "" end } end
package.preload["mp.msg"] = function() return fake_mp.msg end
package.preload["modules.utils.module_loader"] = function()
    return {
        make_init = function()
            local o, d = {}, {}
            return o, d, function() end
        end,
    }
end

-- 让 require "modules.xxx" 能解析
package.path = "portable_config/scripts/uosc_staff_credits/?.lua;"
    .. "portable_config/scripts/uosc_staff_credits/?/init.lua;" .. package.path

local guess = require("modules.guess")

-- ---- 测试用例 ----
-- { 描述, 输入文件名, 期望标题(子串), 期望集数 }
local CASES = {
    -- 用户实际遇到的那一条：日文原名 + 全角副标题 + DashEpisode
    { "無職転生 III（用户实际场景）",
      "無職転生 III ～異世界行ったら本気だす～ - 09", "無職転生 III", "09" },

    -- 去掉发布组标签后的形态
    { "無職転生 III（带发布组标签）",
      "[Lilith-Raws] 無職転生 III ～異世界行ったら本気だす～ - 09 [Baha][WEB-DL][1080p]",
      "無職転生 III", "09" },

    -- 无副标题的纯 DashEpisode
    { "纯 DashEpisode",
      "Mushoku Tensei III - 09", "Mushoku Tensei III", "09" },

    -- 回归：原有模式不能被破坏
    { "SxxExx 模式",
      "Mushoku Tensei S03E09", "Mushoku Tensei", "09" },
    { "第N话 模式",
      "无职转生 第9话", "无职转生", "9" },
    { "Episode 模式",
      "Mushoku Tensei Episode 09", "Mushoku Tensei", "09" },

    -- 保护性用例：片名自带连字符，不能被误切
    { "片名含连字符（不可误切）",
      "Re-Zero kara Hajimeru Isekai Seikatsu - 09",
      "Re-Zero kara Hajimeru Isekai Seikatsu", "09" },

    -- ---- 以下为 2026-10-05 补的字节安全回归 ----
    -- 副标题用半角波浪号
    { "半角波浪号副标题",
      "Mushoku Tensei III ~Isekai Ittara Honki Dasu~ - 09",
      "Mushoku Tensei III", "09" },
    -- 副标题用 U+301C「〜」（与 U+FF5E「～」不同码点、不同字节）
    { "U+301C 波浪号副标题",
      "無職転生 III 〜異世界行ったら本気だす〜 - 09",
      "無職転生 III", "09" },
    -- 中文简繁混排 + 副标题（无集数，只验标题不被啃字节）
    { "中文副标题（无集数）",
      "无职转生 ～到了异世界就拿出真本事～",
      "无职转生", "" },
    -- 片名末尾恰好是汉字，紧邻波浪号 —— 最容易暴露「啃到字符中间」
    { "副标题前是汉字（字节安全）",
      "無職転生 ～異世界行ったら本気だす～ - 09",
      "無職転生", "09" },
    -- 尾部多个发布标签
    { "多段发布标签",
      "[ANi] Mushoku Tensei III - 09 [1080P][Baha][WEB-DL][AAC AVC][CHT]",
      "Mushoku Tensei III", "09" },
    -- 年份（4 位数字）不应被当成集数
    { "4位年份不误判为集数",
      "Mushoku Tensei III 2024",
      "Mushoku Tensei III", "" },
}

-- ---- 字节安全断言：标题里不得出现残缺 UTF-8 序列 ----
-- 判据：所有字节要么是 ASCII，要么满足 UTF-8 合法序列；且末尾不得截断。
local function is_valid_utf8(s)
    if not s then return true end
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local need
        if b < 0x80 then need = 0
        elseif b >= 0xC2 and b <= 0xDF then need = 1
        elseif b >= 0xE0 and b <= 0xEF then need = 2
        elseif b >= 0xF0 and b <= 0xF4 then need = 3
        else return false end
        if i + need > n then return false end
        for k = 1, need do
            local c = s:byte(i + k)
            if not c or c < 0x80 or c > 0xBF then return false end
        end
        i = i + need + 1
    end
    return true
end

-- ---- expand-path 在真机下会返回路径，这里用不到 ----
local pass, fail = 0, 0
print(string.rep("-", 72))
for _, c in ipairs(CASES) do
    local desc, fname, want_title, want_ep = c[1], c[2], c[3], c[4]
    -- 直接测内部解析：construct 一个伪 path
    local title, season, ep = guess.parse_title("/videos/" .. fname .. ".mkv")

    local ok_title = title and title:find(want_title, 1, true) ~= nil
    local ok_ep
    if want_ep == "" then
        ok_ep = (ep == nil)
    else
        ok_ep = (ep ~= nil) and (tonumber(ep) == tonumber(want_ep))
    end
    -- 硬性字节安全断言：残缺 UTF-8 一律算失败
    local ok_utf8 = is_valid_utf8(title)
    if not ok_utf8 then
        print(string.format("  [BUG ] 标题含残缺 UTF-8: %q", tostring(title)))
    end

    if ok_title and ok_ep and ok_utf8 then
        pass = pass + 1
        print(string.format("  [PASS] %s", desc))
        print(string.format("         title=%q  ep=%s", title, tostring(ep)))
    else
        fail = fail + 1
        print(string.format("  [FAIL] %s", desc))
        print(string.format("         输入: %s", fname))
        print(string.format("         得到: title=%q season=%s ep=%s",
            tostring(title), tostring(season), tostring(ep)))
        print(string.format("         期望: title 含 %q, ep=%s", want_title, want_ep))
    end
end
print(string.rep("-", 72))
print(string.format("结果：%d/%d 通过", pass, pass + fail))
os.exit(fail == 0 and 0 or 1)
