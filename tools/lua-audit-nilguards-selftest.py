#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""lua-audit-nilguards 的「金丝雀」自检 —— 证明审计工具真的抓得到它该抓的东西。

为什么需要它：
  静态检查工具最大的风险是「规则悄悄失效」——比如某次改动后正则不再匹配，
  工具照样输出「未发现可疑模式 ✅」，于是所有人都以为干净了。
  **一个不报错的坏工具，比没有工具更危险。**
  所以必须有一个反例测试：故意注入已知缺陷，看工具是否仍然命中。

做法：把 4 类原始缺陷 + 3 个「正确写法」写进一份临时 Lua 文件，
只让审计器扫这一份，然后断言：
  · 4 类缺陷全部被报出（A 1 条、B 3 条、C 1 条 INFO）
  · 3 个正确写法**一条都不报**（这是防误报的反向断言）

用法：python tools/lua-audit-nilguards-selftest.py
退出码：0 = 自检通过，1 = 审计工具行为不符合预期（规则已失效或误报）
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
AUDITOR = os.path.join(HERE, 'lua-audit-nilguards.py')

# 金丝雀源码：左半是「必须被报出」的缺陷，右半是「必须保持静默」的正确写法
CANARY = r'''
-- 必须被报出（4 类原始缺陷）
local a = mp.command_native({"command", "expand-path", "~~/cache"})
deps.notify.info("已更新: %s = %s", tostring(k), tostring(v))
deps.notify.warn("count=%d items", n)
deps.notify.error("加载失败，重试 %s 次", n)
local c = mp.command_native({'expand-path', '~~/cache'}):gsub('a','b')
-- 必须保持静默（正确写法 / 不构成缺陷）
deps.notify.info(string.format("已更新: %s = %s", tostring(k), tostring(v)))
deps.notify.info("纯文本提示，第二参是 tag", "mytag")
mp.command_native({'expand-text', tpl}):gsub('a','b')
'''

# (期望级别, 期望规则前缀, 期望命中次数)
EXPECT_HITS = [
    ('P0', 'A/', 1),
    ('P0', 'B/', 3),
    ('INFO', 'C/', 1),
]
# 这些行号（1-based，含 CANARY 开头的空行）必须**不出现**在任何告警里
EXPECT_SILENT = [8, 9, 10]


def main():
    with tempfile.TemporaryDirectory() as td:
        canary = os.path.join(td, 'canary.lua')
        with open(canary, 'w', encoding='utf-8') as f:
            f.write(CANARY)

        # 复制审计器并把自动搜集 FILES 的那段替换成「只扫金丝雀」
        src = open(AUDITOR, encoding='utf-8').read()
        patched = re.sub(
            r"FILES = \[\]\nfor pat in .*?\n    FILES \+= glob\.glob\(pat, recursive=True\)",
            "FILES = [%r]" % canary.replace('\\', '/'),
            src, flags=re.S, count=1)
        if patched == src:
            print("✗ 无法改写审计器的 FILES 搜集段 —— 源码结构变了，请同步本自检")
            return 1

        runner = os.path.join(td, 'runner.py')
        with open(runner, 'w', encoding='utf-8') as f:
            f.write(patched)

        p = subprocess.run([sys.executable, runner], capture_output=True, text=True)
        out = p.stdout

    ok = True

    # 断言 1：该报的都报了
    for level, rule, want in EXPECT_HITS:
        got = len(re.findall(r'\[%s\] %s' % (level, re.escape(rule)), out))
        mark = '✓' if got == want else '✗'
        if got != want:
            ok = False
        print("  %s 期望 [%s] %-4s 命中 %d 次，实际 %d 次" % (mark, level, rule, want, got))

    # 断言 2：正确写法必须静默
    for ln in EXPECT_SILENT:
        # 告警块形如 "     <path>:<line>"，检查该行号是否作为告警出现
        hit = re.search(r':%d\s*$' % ln, out, re.M)
        mark = '✗' if hit else '✓'
        if hit:
            ok = False
        print("  %s 正确写法（第 %d 行）保持静默" % (mark, ln))

    print()
    if ok:
        print("金丝雀自检通过 —— 审计规则有效且无已知误报 ✅")
        return 0
    print("金丝雀自检失败 —— 审计规则可能已失效或产生误报 ❌")
    print("以下是审计器完整输出，供排查：")
    print(out)
    return 1


if __name__ == '__main__':
    sys.exit(main())
