# -*- coding: utf-8 -*-
"""静态核验：本项目脚本发出的每个 script-message-to 路由，是否真的被注册过。

为什么需要它（2026-10-06）：
    项目原有的两道路由类门禁（uosc-verify-routes / uosc-verify-buttons）
    **都只解析 script-opts/uosc.conf 的 controls= 行**，也就是只管工具栏按钮。
    菜单项里的 `value = "script-message-to ... <route>"` 完全没人检查。
    实测确认过这个盲区：把 dispatcher 里
        mp.register_script_message("staff-credits-mark-watched", ...)
    整行删掉，uosc-verify-routes.py 依然报「未注册: 0」。

    后果和 buttons 那道门禁要防的一样：路由名写错（或忘了注册）**不会报错**，
    只会表现为「点了菜单没反应」—— 用户看不出、日志里也没有 Lua error。
    必须静态比对才能发现。

覆盖两种写法：
    1) 整串在一个字面量里：  "script-message-to myscript route arg"
    2) 拼接写法（本项目主用）：
       "script-message-to " .. script_name .. " route arg"
       —— 路由名是拼接串里最后一段字面量的第一个词。

两条「别踩」的坑（初版都踩了）：
    · **必须先剥注释**。open_dialog.lua / delete-current-file.lua 的用法说明里
      大段写着 `key script-message-to open_dialog import_files`，那是**文档**，
      不剥注释就会凭空多出 5 条 FAIL。
    · **只对本项目自己的脚本判失败**。scripts/ 下还有 uosc、open_dialog、
      dyn_menu 等第三方脚本，它们的发送点约定各不相同（uosc 走
      `bind_command` / `key-binding` 转发，压根不用 register_script_message），
      拿本项目的尺子去量它们只会制造噪声。第三方一律降级为 INFO。

用法（在 portable_config/ 目录下）：
    python tools/uosc-verify-menu-routes.py
退出码：0 = 本项目发出的路由全部有注册；1 = 存在发了但没人收的路由
"""
import re
import glob
import sys

SCRIPT_GLOB = 'scripts/**/*.lua'
OWN_PREFIX = 'scripts/uosc_staff_credits/'      # 本项目自己的脚本

PAT_INLINE = re.compile(r'script-message-to\s+([A-Za-z0-9_.\-]+)\s+([A-Za-z0-9_\-]+)')
PAT_CONCAT = re.compile(r'"script-message-to\s*"\s*\.\.[^"\n]*?\s*"\s*([A-Za-z0-9_\-]+)')


def strip_comments(src):
    """把行注释与 --[[ ]] 块注释整段抹掉（保留换行以维持行号）。

    必须做：否则文档里示例的 `script-message-to ...` 会被当成真实发送点。
    """
    out = []
    in_block = False
    for line in src.split('\n'):
        if in_block:
            end = line.find(']]')
            if end == -1:
                out.append('')
                continue
            in_block = False
            line = line[end + 2:]
        # 去掉行注释（注意 --[[ 是块注释开始）
        pos = 0
        while True:
            c = line.find('--', pos)
            if c == -1:
                break
            if line.startswith('--[[', c):
                end = line.find(']]', c + 4)
                if end == -1:
                    in_block = True
                    line = line[:c]
                    break
                line = line[:c] + line[end + 2:]
                pos = c
                continue
            line = line[:c]
            break
        out.append(line)
    return '\n'.join(out)


senders = {}     # route -> [(file, line)]
registered = {}  # route -> file

for path in sorted(glob.glob(SCRIPT_GLOB, recursive=True)):
    raw = open(path, encoding='utf-8', errors='ignore').read()
    src = strip_comments(raw)
    norm = path.replace('\\', '/')

    for mm in re.finditer(r'register_script_message\(\s*"([^"]+)"', src):
        registered.setdefault(mm.group(1), norm)

    for pat in (PAT_INLINE, PAT_CONCAT):
        for mm in pat.finditer(src):
            route = mm.group(2) if pat is PAT_INLINE else mm.group(1)
            line_no = src[:mm.start()].count('\n') + 1
            senders.setdefault(route, []).append((norm, line_no))

print("发出的路由: %d 个    已注册的路由: %d 个" % (len(senders), len(registered)))
print()

own_bad, foreign_bad = [], []
for route in sorted(senders):
    if route in registered:
        continue
    where = senders[route][0]
    if where[0].startswith(OWN_PREFIX):
        own_bad.append(route)
        print("  [FAIL] %-40s ← %s:%d  **本项目发出但无注册，点了不会有反应**"
              % (route, where[0], where[1]))
    else:
        foreign_bad.append(route)
        print("  [INFO] %-40s ← %s:%d  （第三方脚本，约定不同，不判失败）"
              % (route, where[0], where[1]))

print()
print("=" * 68)
print("本项目未注册: %d %s" % (len(own_bad), own_bad if own_bad else ""))
print("第三方未注册（仅提示）: %d %s" % (len(foreign_bad), foreign_bad if foreign_bad else ""))
sys.exit(1 if own_bad else 0)
