#!/usr/bin/env python3
# sub-style-conf-verify.py —— script-opts/uosc_subtitle_style.conf 静态门禁
#
# 背景（2026-10-22 真机踩坑）：mpv 的 conf 解析器**不支持行尾注释**。
#   `preset_enabled=yes   # 注释` 会把「yes   # 注释」整段当值：
#     * 布尔/数值项 → 报 `error converting value` 并回落到脚本内默认值
#       （默认值恰好等于期望值时，E2E/冒烟都被巧合掩盖）；
#     * 字符串项 → 静默把注释吃进值里（如 preset_color 变成
#       "#FFFFFF   # 预设主色"，包含匹配的断言也发现不了）。
#   本门禁按 mpv 的解析语义复算，杜绝这两类回归。
#
# 规则：
#   R1 覆盖对齐：conf 的键集合 == 脚本 o 表的键集合（缺项/多项都报）；
#   R2 布尔项（Lua 默认 true/false）：值必须恰好是 yes/no/true/false；
#   R3 数值项（Lua 默认 number）：值必须能 parse 为数值且无内部空白；
#   R4 字符串项：值含 '#' 即报——除非该键是候选列表（Lua 默认含 ','，如
#      colors/outline_colors，值里的 #RRGGBB 合法）；单色键（默认恰好 #RRGGBB）
#      额外要求值也必须恰好是一个 #RRGGBB；
#   R5 行首注释（第一个非空字符是 #）与空行跳过；不识别其它注释形态。
#
# 用法（在 portable_config/ 下）：python tools/sub-style-conf-verify.py
import os
import re
import sys

PORTABLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF = os.path.join(PORTABLE, 'script-opts', 'uosc_subtitle_style.conf')
SCRIPT = os.path.join(PORTABLE, 'scripts', 'uosc_subtitle_style.lua')

BOOL_OK = {'yes', 'no', 'true', 'false'}

failures = []


def check(name, ok, detail=''):
    print('%s %s%s' % ('PASS' if ok else 'FAIL', name,
                       (' | ' + detail) if (detail and not ok) else ''))
    if not ok:
        failures.append(name)


def lua_defaults():
    """从 uosc_subtitle_style.lua 的 o 表提取 键 → (Lua 默认值原文, 类型)。"""
    src = open(SCRIPT, encoding='utf-8').read()
    m = re.search(r'^local o = \{(.*?)^\}', src, re.S | re.M)
    if not m:
        return None
    out = {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith('--'):
            continue
        km = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?),?\s*(?:--.*)?$', line)
        if not km:
            continue
        key, raw = km.group(1), km.group(2).strip()
        if raw in ('true', 'false'):
            typ, val = 'bool', raw == 'true'
        elif re.match(r'^-?\d+(\.\d+)?$', raw):
            typ, val = 'number', float(raw)
        else:
            typ, val = 'string', raw.strip("'\"")
        out[key] = (val, typ)
    return out


def parse_conf():
    """按 mpv 语义解析：整行注释（首非空字符 #）跳过；key=value 取 '=' 后整行（尾部空白修剪）。"""
    entries = {}
    for lineno, line in enumerate(open(CONF, encoding='utf-8'), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if '=' not in stripped:
            continue
        key, _, value = stripped.partition('=')
        entries[key.strip()] = (value.rstrip(), lineno)
    return entries


def main():
    if not os.path.exists(CONF):
        print('FATAL: conf not found: %s' % CONF)
        return 2
    defaults = lua_defaults()
    if defaults is None:
        print('FATAL: 无法从 uosc_subtitle_style.lua 解析 o 表')
        return 2
    conf = parse_conf()

    # R1 覆盖对齐
    missing = sorted(set(defaults) - set(conf))
    extra = sorted(set(conf) - set(defaults))
    check('conf-covers-all-options', not missing, 'conf 缺少: %s' % missing)
    check('conf-no-unknown-keys', not extra, 'conf 多出: %s' % extra)

    # R2-R4 逐键类型/形态校验
    for key, (value, lineno) in sorted(conf.items()):
        if key not in defaults:
            continue
        dv, typ = defaults[key]
        where = '%s (conf:%d)' % (key, lineno)
        if typ == 'bool':
            check('conf-bool-%s' % key, value in BOOL_OK,
                  '%s = %r（mpv 只认 yes/no/true/false）' % (where, value))
        elif typ == 'number':
            ok = bool(re.match(r'^-?\d+(\.\d+)?$', value))
            check('conf-number-%s' % key, ok,
                  '%s = %r（不是合法数值；行尾注释会被吃进值里）' % (where, value))
        else:
            # 字符串键分三类：
            #   ① 单色键（Lua 默认恰好是 #RRGGBB，如 preset_color/preset_outline_color）：
            #      值必须也是恰好一个 #RRGGBB——行尾注释会让它变成 "#FFFFFF  # xxx"；
            #   ② 候选列表键（默认值含 ','，如 colors/outline_colors）：值里含 # 合法；
            #   ③ 其它字符串键（fonts/sizes/preset_font/preset_bold…）：值里不得含 #。
            if isinstance(dv, str) and re.match(r'^#[0-9A-Fa-f]{6}$', dv):
                check('conf-string-%s' % key,
                      bool(re.match(r'^#[0-9A-Fa-f]{6}$', value)),
                      '%s = %r（必须是恰好一个 #RRGGBB；行尾注释会被吃进值里）'
                      % (where, value))
            elif isinstance(dv, str) and ',' in dv:
                check('conf-string-%s' % key, True)  # 候选列表，值本身含 # 合法
            else:
                check('conf-string-%s' % key, '#' not in value,
                      '%s = %r（值里含 #：mpv 不支持行尾注释，整段会被当值）'
                      % (where, value))

    print('SUMMARY sub-style-conf-verify %s fail=%d %s' % (
        'PASS' if not failures else 'FAIL', len(failures),
        '' if not failures else ('FAILED: ' + ','.join(failures))))
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(main())
