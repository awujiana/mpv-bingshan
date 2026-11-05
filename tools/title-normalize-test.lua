-- tools/title-normalize-test.lua —— title_normalize 模块回归测试
--
-- 用法（任意 cwd 均可 —— 路径基准由脚本自身位置推导）：
--   ./luajit.exe portable_config/tools/title-normalize-test.lua
--
-- 为什么需要它（2026-10-05）：
--   本模块是修「繁体/日文标题搜不到 Bangumi」引入的。修的过程中连着踩了
--   **三次**同一类坑：Lua 字符类对多字节字符是**字节集**语义。
--     · guess.lua strip_subtitle 的 [～〜~]  → 啃掉「す～」6 字节
--     · title_normalize 的 KANA 类           → 误匹配**所有汉字**
--     · 原 utils.is_chinese 的 [\228-\233]   → 简繁日不分
--   这类 bug 用「看一眼代码」发现不了，必须跑真实字符串。
--   所以这里把「字节类必须换码点」这件事固化成测试。

-- ---- 路径基准：从脚本自身位置反推，使本测试与 cwd 无关 ----
-- 脚本位于 <mpv根>/portable_config/tools/，故上溯一级即 portable_config。
-- 原先这里写死相对路径，必须从 mpv 根目录跑；换目录跑会崩在 require 上。
local _src = debug.getinfo(1, "S").source or "@."
local _tools_dir = _src:match("^@(.*)[/\\][^/\\]*$") or "."
local _pc = _tools_dir:match("^(.*)[/\\][^/\\]*$") or "."

-- ---- stub mp ----
package.preload["mp"] = function()
    return {
        get_property = function() return nil end,
        -- 真机下 expand-path 返回真实路径；这里给绝对路径，语义与真机一致
        command_native = function(_, a) return _pc .. "/scripts" end,
        msg = setmetatable({}, { __index = function() return function() end end }),
        get_time = function() return 0 end,
    }
end
package.preload["mp.utils"] = function() return {} end
package.preload["mp.msg"] = function()
    return setmetatable({}, { __index = function() return function() end end })
end
package.path = _pc .. "/scripts/uosc_staff_credits/?.lua;"
    .. _pc .. "/scripts/uosc_staff_credits/?/init.lua;" .. package.path

local tn = require("modules.title_normalize")

-- 注入真实字典（若不可达则跳过所有转换类断言）
local DICT_PATH = _pc .. "/scripts/uosc_danmaku/dicts/t2s_chars.lua"
local dict = dofile(DICT_PATH)
assert(type(dict) == "table", "找不到 t2s 字典: " .. DICT_PATH)
tn._set_dict(dict)

local pass, fail = 0, 0
local function check(desc, got, want)
    if got == want then
        pass = pass + 1
        print(string.format("  [PASS] %s", desc))
    else
        fail = fail + 1
        print(string.format("  [FAIL] %s", desc))
        print(string.format("         得到 %q  期望 %q", tostring(got), tostring(want)))
    end
end

print(string.rep("-", 76))
print("== 1. to_simplified 逐字转换 ==")
check("無職転生 → 无职転生", tn.to_simplified("無職転生"), "无职転生")
check("異世界 → 异世界", tn.to_simplified("異世界"), "异世界")
check("間諜家家酒 → 间谍家家酒", tn.to_simplified("間諜家家酒"), "间谍家家酒")
check("鬼滅 → 鬼灭", tn.to_simplified("鬼滅"), "鬼灭")
-- 日文新字体（転/気）不在 t2s 字典中，应原样保留 —— 这是预期行为
check("転 不在字典（日文新字体）", tn.to_simplified("転"), "転")
check("気 不在字典（日文新字体）", tn.to_simplified("気"), "気")
check("已是简体则不变", tn.to_simplified("进击的巨人"), "进击的巨人")

print()
print("== 2. has_kana / has_han（★字节类 bug 红线）==")
-- 这一组是**核心红线**：旧 KANA 字节类会让它们全部为 true
check("has_kana('进击的巨人') = false", tn.has_kana("进击的巨人"), false)
check("has_kana('无职转生')   = false", tn.has_kana("无职转生"), false)
check("has_kana('間諜家家酒') = false", tn.has_kana("間諜家家酒"), false)
check("has_kana('鬼滅')       = false", tn.has_kana("鬼滅"), false)
check("has_kana('の')         = true",  tn.has_kana("の"), true)
check("has_kana('あ')         = true",  tn.has_kana("あ"), true)
check("has_kana('ア')         = true",  tn.has_kana("ア"), true)
check("has_kana('Mushoku')    = false", tn.has_kana("Mushoku"), false)
check("has_han('进击')        = true",  tn.has_han("进击"), true)
check("has_han('無職')        = true",  tn.has_han("無職"), true)
check("has_han('Mushoku')     = false", tn.has_han("Mushoku"), false)
check("has_han('123 III')     = false", tn.has_han("123 III"), false)

print()
print("== 3. is_simplified_chinese ==")
check("纯简体 → true", tn.is_simplified_chinese("进击的巨人"), true)
check("简体+符号 → true", tn.is_simplified_chinese("【我推的孩子】"), true)
check("繁体 → false（需转换）", tn.is_simplified_chinese("無職転生 III"), false)
check("日文（含假名）→ false", tn.is_simplified_chinese("鬼滅の刃"), false)
check("纯英文 → false", tn.is_simplified_chinese("Mushoku Tensei III"), false)
check("空串 → false", tn.is_simplified_chinese(""), false)

print()
print("== 4. normalize 组合 ==")
local s1, c1 = tn.normalize("無職転生 III")
check("normalize 繁体: 结果", s1, "无职転生 III")
check("normalize 繁体: changed", c1, true)
local s2, c2 = tn.normalize("进击的巨人")
check("normalize 简体: 不变", s2, "进击的巨人")
check("normalize 简体: changed=false", c2, false)

print()
print("== 5. UTF-8 解码器健壮性 ==")
-- 残缺字节不应导致崩溃，应产出 U+FFFD
local bad = "\xE3\x81"       -- 截断的「ぁ」
local ok_bad, cps = pcall(tn._codepoints, bad)
check("残缺 UTF-8 不崩溃", ok_bad, true)
check("残缺字节 → U+FFFD", ok_bad and cps[1], 0xFFFD)
check("ASCII 解码", tn._codepoints("ABC")[1], 65)
check("汉字解码(进=U+8FDB)", tn._codepoints("进")[1], 0x8FDB)
check("假名解码(の=U+306E)", tn._codepoints("の")[1], 0x306E)

print()
print("== 6. to_standard_name（弹幕 API 名称清洗）==")
-- 下列输入全部是从真实弹幕 API 抓回来的原文
local NAME_CASES = {
    { "无职转生Ⅲ ～到了异世界就拿出真本事～(2026)【TV动画】from dandan",
      "无职转生Ⅲ ～到了异世界就拿出真本事～" },
    { "无职转生Ⅱ ～到了异世界就拿出真本事～ 第2部分(2024)【TV动画】from dandan",
      "无职转生Ⅱ ～到了异世界就拿出真本事～ 第2部分" },
    { "无职转生Ⅱ ～到了异世界就拿出真本事～(2023)【TV动画】from dandan",
      "无职转生Ⅱ ～到了异世界就拿出真本事～" },
    { "無職転生Ⅲ ～異世界行ったら本気だす～(2026)【TV动画】from bahamut",
      "無職転生Ⅲ ～異世界行ったら本気だす～" },
    -- 已经是干净的，应保持不变
    { "进击的巨人", "进击的巨人" },
    { "无职转生 ～在异世界认真地活下去～", "无职转生 ～在异世界认真地活下去～" },
    -- ★ 字节陷阱红线：「一」= E4 B8 80，含续接字节 80
    --   若用 [^】] 这类字节类去剥【】，会把「一」切坏
    { "第一部 一【TV动画】from x", "第一部 一" },
    -- 非数字括号不应被剥掉
    { "无职转生（第一部）", "无职转生（第一部）" },
    -- 全角括号年份应被剥掉
    { "进击的巨人（2013）", "进击的巨人" },
    -- 纯噪声不应被清成空串
    { "【TV动画】", "【TV动画】" },
    -- ★ 保护性红线：正片名里本来就有 "from"，不能被当来源标记剥掉
    { "Escape from Tarkov", "Escape from Tarkov" },
    { "The Girl from the Other Side", "The Girl from the Other Side" },
}
for _, c in ipairs(NAME_CASES) do
    local got = tn.to_standard_name(c[1])
    check(string.format("清洗 %q", c[1]), got, c[2])
end

print()
print("== 7. 清洗结果必须是合法 UTF-8（不得切坏字符）==")
local function valid_utf8(s)
    if not s then return false end
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
            local cc = s:byte(i + k)
            if not cc or cc < 0x80 or cc > 0xBF then return false end
        end
        i = i + need + 1
    end
    return true
end
for _, c in ipairs(NAME_CASES) do
    local got = tn.to_standard_name(c[1])
    check(string.format("UTF-8 合法 %q", got), valid_utf8(got), true)
end

print(string.rep("-", 76))
print(string.format("结果：%d/%d 通过", pass, pass + fail))
os.exit(fail == 0 and 0 or 1)