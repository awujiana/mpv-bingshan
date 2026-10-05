-- probe-expand-text.lua —— 实测 mp.command_native 各类命令的「失败返回什么」
--
-- 为什么需要这个探测（2026-10-05）：
--   本项目 3 处缺陷都源于「假设 command_native 失败会抛错」，实际它是**返回 nil**，
--   于是后面的 nil 守卫把崩溃变成了静默失效。要正确评估这类风险，必须先知道
--   **具体哪个命令会返回 nil**——这只能实测，不能靠猜。
--
-- 已验证结论（本次运行的实测数据）：
--   expand-text  **不会**返回 nil：
--       "plain text"                 → "plain text"    （原样）
--       "${不存在属性}"               → "(error)"       （替换为字面量）
--       "${}"/"${不存在} ${path}"     → "(error) …"     （同上）
--       "${"（非法/未闭合模板）        → "${"            （原样返回）
--     ⇒ 故 TopBar.lua:40 的 command_native({'expand-text',…}):gsub() **永远安全**，
--       既不会抛错也不会静默失效。审计工具因此把规则 C 降为 INFO 并跳过 expand-text。
--
--   expand-path  则**会**返回 nil（本机 3 处缺陷 2 的成因）：
--       错误写法 {"command", "expand-path", X} → nil
--       正确写法 {"expand-path", X}            → 展开后的路径字符串
--
-- 跑法（在 mpv 根目录）：
--   ./mpv.exe --vo=null --ao=null --frames=1 --msg-level=all=info \
--       --script=portable_config/tools/probe-expand-text.lua \
--       "av://lavfi:testsrc=d=1"
--   ⚠️ 不要加 --no-config，否则 portable_config 不被加载。

local cases = {
	"plain text",
	"${definitely-not-a-real-prop-xyz}",
	"${definitely-not-a-real-prop-xyz} ${path}",
	"${",
	"${}",
	"no-such=${}end",
}

for _, c in ipairs(cases) do
	local ok, r = pcall(mp.command_native, { "expand-text", c })
	local ok2, err = pcall(function()
		-- 复现 TopBar 的用法：返回后立刻链式调方法
		return mp.command_native({ "expand-text", c }):gsub("x", "y")
	end)
	print(string.format(
		"PROBE ok=%s type=%s nil=%s len=%s repr=[%s] | chained_call_ok=%s",
		tostring(ok), type(r), tostring(r == nil),
		tostring(#(r or "")), tostring(r), tostring(ok2)
	))
	if not ok2 then print("PROBE   chained error: " .. tostring(err)) end
end
