# 变异测试驱动：证明 tools/updater-test.lua 的断言真的能抓住错误。
# 用法（在 portable_config/ 下）：/c/Python314/python.exe tools/updater-mutation-test.py
#
# 纪律：按**字节**读写，别用文本模式——文本模式会把 \n 翻成 \r\n，
# 还原后文件虽内容等价但字节不同，污染工作区（本脚本第一版就踩过）。
import subprocess
import sys

TARGET = 'script-modules/updater.lua'
ORIG = open(TARGET, 'rb').read()

MUTATIONS = [
    ('A 去掉 git 工作区脏检查',
     b"if (res2.stdout or ''):match('%S') then",
     b'if false then'),
    ('B 去掉非快进保护',
     b"run({ 'merge-base', '--is-ancestor', 'HEAD', 'FETCH_HEAD' }, function(ok6)\n                            if not ok6 then",
     b"run({ 'merge-base', '--is-ancestor', 'HEAD', 'FETCH_HEAD' }, function(ok6)\n                            if false then"),
    ('C 去掉资产尺寸校验',
     b'if asset.size > 0 and nsize ~= asset.size then',
     b'if false then'),
    ('D 去掉 Lua 头部校验',
     b"if new:sub(1, 2) ~= '--' then",
     b'if false then'),
    ('E 去掉内容相同判定',
     b'if old and old == new then',
     b'if false then'),
    ('F 去掉状态快速路径',
     b'if local_size and st.tag == info.tag and st.size and local_size == st.size',
     b'if false and st.tag == info.tag and st.size and local_size == st.size'),
    ('G 忘记删除中转文件',
     b'if moved and old then os.remove(swap) end',
     b'-- mutated: no swap cleanup'),
    ('H 去掉本地版本守卫（同版本/本地更新不再跳过）',
     b'if local_ver and M.compare_version(local_ver, remote_ver) >= 0 then',
     b'if false then'),
    ('I 去掉同 tag 兜底（状态记录同版本时会重复安装）',
     b'if local_size and not local_ver and (st.tag == info.tag or',
     b'if false and (st.tag == info.tag or'),
    ('J 去掉安装前版本兜底（远端回退时降级本地文件）',
     b'if old and from_ver and M.compare_version(from_ver, remote_ver) >= 0 then',
     b'if false then'),
]

# 先整体预检所有 pattern：任何一条不匹配时还没动过源文件就退出，
# 否则「写到一半才 assert 失败」会把变异版留在工作区（本脚本踩过这个坑）。
for name, old, _ in MUTATIONS:
    assert old in ORIG, 'pattern not found for ' + name

results = []
try:
    for name, old, new in MUTATIONS:
        open(TARGET, 'wb').write(ORIG.replace(old, new, 1))
        r = subprocess.run(['../luajit.exe', 'tools/updater-test.lua'],
                           capture_output=True, text=True, encoding='utf-8', errors='replace')
        fails = [ln.split()[1] for ln in (r.stdout or '').splitlines()
                 if ln.startswith('FAIL ')]
        results.append((name, r.returncode, fails))
finally:
    # 断言失败 / 子进程异常 / 中断，都必须把源文件按字节还原
    open(TARGET, 'wb').write(ORIG)
restored = open(TARGET, 'rb').read() == ORIG

print('=' * 68)
ok_all = True
for name, code, fails in results:
    killed = code != 0 and len(fails) > 0
    ok_all = ok_all and killed
    print('%s %s | exit=%d | 抓住 %d 条：%s' % (
        'KILLED  ' if killed else 'SURVIVED', name, code, len(fails), ', '.join(fails[:4])))
print('=' * 68)
print('已还原原始文件（字节级）：', restored)
print('结论：', 'ALL_KILLED（用例有牙）' if ok_all and restored else 'HAS_SURVIVOR')
sys.exit(0 if ok_all and restored else 1)
