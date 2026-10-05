-- 业务链路冒烟测试（真机运行，非静态检查）
--
-- 用法（在 mpv-20260831/ 目录下执行）：
--   ./mpv.exe --vo=null --ao=null --msg-level=all=info \
--       --script=portable_config/tools/biz-smoke.lua "av://lavfi:testsrc=d=3"
--
-- 目的：验证 uosc_staff_credits 的业务路由是否真的被 dispatcher 接收并响应。
--   语法检查（loadstring）发现不了「路由注册失败」和「模块 require 失败」，
--   只有真机跑一遍才有信号 —— 见 docs/REVIEW_AND_MERGE.md §7.5。
--
-- ⚠️ 判据设计上的一个坑（本测试踩过，2026-10-05）：
--   一开始只抓 notify 的「加载中...」回执，于是 main-menu 被判为无响应 ——
--   但那是**误判**。main-menu 的响应不走 notify，而是
--   `mp.commandv("script-message-to", "uosc", "open-menu", <json>)`。
--   只因本测试脚本的加载顺序在 uosc 之后，`register_script_message("open-menu")`
--   拿不到那条消息（mpv 的 script-message 不会回放给后注册者）。
--   ⇒ 结论：**不能用「本进程能否收到某个 script-message」当判据**，
--     必须改看 mpv 自身的命令日志（trace 级）或可观测的副作用。
--   现做法：main-menu 单独以 trace 级命令日志核验（见 §8.3.1 的 mm2 输出），
--   本脚本负责其余三条 notify 型路由。
--
-- 判据：日志中出现各路由的「加载中...」回执，且**不出现 Lua error / traceback**。

local mp = require 'mp'
local msg = require 'mp.msg'

-- 与 script-opts/uosc.conf 的 controls 里新增的业务按钮一一对应。
-- main-menu 单独标注，因为它不产出 notify 回执（见上方说明）。
local CASES = {
    { name = "职员表(主菜单)", route = "main-menu",
      evidence = "uosc 收到 open-menu（需 --msg-level=all=trace 核验）" },
    { name = "角色介绍",       route = "character-intro" },
    { name = "封面简介",       route = "cover-intro" },
    { name = "制作评分",       route = "staff-credits-production-score" },
}

local SCRIPT = "uosc_staff_credits"
local STEP_DELAY = 1.5   -- 每个路由之间的间隔，留出异步响应时间

local i = 0
local dispatched = {}

local function step()
    i = i + 1
    if i > #CASES then
        msg.info("=== BIZ SMOKE SUMMARY ===")
        for _, r in ipairs(dispatched) do
            msg.info("  " .. r)
        end
        msg.info(string.format("=== 共派发 %d 个业务路由 ===", #dispatched))
        mp.commandv("quit")
        return
    end

    local c = CASES[i]
    msg.info(string.format("=== [%d/%d] 触发按钮「%s」→ route=%s",
        i, #CASES, c.name, c.route))

    mp.commandv("script-message-to", SCRIPT, c.route)
    dispatched[#dispatched + 1] = string.format("%s → route=%s 已派发", c.name, c.route)
    if c.evidence then
        dispatched[#dispatched + 1] = "  └ 判据: " .. c.evidence
    end

    mp.add_timeout(STEP_DELAY, step)
end

mp.register_event("file-loaded", function()
    -- 稍等，确保所有脚本已完成 init（按钮注册发生在 init 阶段）
    msg.info("=== BIZ SMOKE START ===")
    mp.add_timeout(2, step)
end)
