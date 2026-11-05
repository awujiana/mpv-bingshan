# -*- coding: utf-8 -*-
"""静态核验：uosc.conf 的 controls 里引用的每个 button:NAME 是否真的被某个脚本注册过。
   依据：uosc 的 lib/buttons.lua 中 buttons:get() 对未注册名字返回 help_center 兜底，
   所以「名字拼错」不会报错，只会显示错误图标 —— 必须静态比对才能发现。"""
import re, io, os, glob

cfg = open('script-opts/uosc.conf', encoding='utf-8').read()
# 取 controls= 那一行（可能被注释换行，取真正生效的）
m = re.search(r'^controls=(.*)$', cfg, re.M)
controls = m.group(1)
print("controls 行长度:", len(controls))

# 提取所有 button:NAME
btn_refs = re.findall(r'button:([A-Za-z0-9_\-]+)', controls)
print("button: 引用 →", btn_refs)

# 收集所有脚本注册的按钮名
registered = {}
for path in glob.glob('scripts/**/*.lua', recursive=True):
    src = open(path, encoding='utf-8', errors='ignore').read()
    # 匹配 set-button 后面的按钮名（可能跨行）
    for mm in re.finditer(r'"set-button"\s*,\s*"([^"]+)"', src):
        registered.setdefault(mm.group(1), []).append(path)
    # 也匹配同行写法: set-button", "name",
    for mm in re.finditer(r'set-button\s*\W+?([A-Za-z0-9_\-]+)\W+\s*\{', src):
        registered.setdefault(mm.group(1), []).append(path)

print("\n已注册的按钮名:")
for k in sorted(registered):
    print("  %-28s ← %s" % (k, registered[k][0]))

print("\n核验结果:")
bad = []
for b in btn_refs:
    if b in registered:
        print("  [OK]   button:%s" % b)
    else:
        print("  [FAIL] button:%s  ← 无任何脚本注册，将显示 help_center 占位图标" % b)
        bad.append(b)
print()
print("未注册数量:", len(bad), bad if bad else "")
