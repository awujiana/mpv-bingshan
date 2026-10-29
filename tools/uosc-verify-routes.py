# -*- coding: utf-8 -*-
"""按 uosc 的真实分隔规则解析 controls，再核验 script-message-to 路由。
   uosc 用逗号分隔控件项；每项格式 条件:command:参数:script-message-to 脚本 路由?提示
   所以路由名到 '?' 或项结束为止。"""
import re, glob

cfg = open('script-opts/uosc.conf', encoding='utf-8').read()
m = re.search(r'^controls=(.*)$', cfg, re.M)
controls = m.group(1)

# 更精确：script-message-to <script> <route>，route 到 '?' 或 ',' 或行尾
routes = re.findall(r'script-message-to\s+([^\s,?]+)\s+([^\s,?]+)', controls)
print("解析出的 script-message-to 路由:")
for s, r in routes:
    print("  脚本=%-20s 路由=%s" % (s, r))

registered = {}
for path in glob.glob('scripts/**/*.lua', recursive=True):
    src = open(path, encoding='utf-8', errors='ignore').read()
    # 2026-10-20 修：初版只匹配双引号，单引号注册（如 scripts/uosc_subtitle_style.lua）
    # 全部看不见 → 新脚本的路由被误报「未注册」。两种引号都要认。
    for mm in re.finditer(r'register_script_message\(\s*[\'"]([^\'"]+)[\'"]', src):
        registered.setdefault(mm.group(1), path)

print("\n核验:")
bad = []
for s, r in routes:
    ok = r in registered
    print("  [%s] %-45s (%s)" % ("OK" if ok else "FAIL", r, s))
    if not ok: bad.append(r)
print("\n未注册:", len(bad), bad if bad else "")
