#!/usr/bin/env python3
# sub-style-e2e.py —— uosc_subtitle_style.lua 真机端到端测试编排
# 流程：
#   1. 以 --script 加载 tools/sub-style-probe.lua 驱动真实 mpv（加载真实
#      portable_config），双字幕轨（主 fixture + 次 fixture，--secondary-sid），
#      依次验证：分轨位置 / 分轨字体 / 分轨字号（及时反馈）/ 状态文件 / 重置 /
#      字体选择器。
#   2. 解析日志里的 PROBE 行汇总断言。
#   3. 视觉判据（截图波段分析）：
#      - main50：主字幕带移到中部，次字幕带仍在底部 ⇒ 两条独立白字带
#      - sec25：次字幕带上移到中上部，主字幕带保持不动
#      - secfont：下部带（次）变形、上部带（主）像素数不变 ⇒ 分轨字体
#      - secsize：次带高度 25px → ~8px ⇒ 分轨字号 + 及时反馈
#   4. 预设样式真机用例：彩色才套用 / 白色保持原样 / 预设可修改并缓存 /
#      双语（双轨）跳过（A 套用+B 保持+C 保存+D 重启读缓存+E 双轨不套用，
#      含左上角报告与字幕变色判据）
# 用法（在 portable_config/ 下）：python tools/sub-style-e2e.py
# ⚠ 视觉判据依赖 Pillow：PATH 里的 managed python 未装 Pillow，本机请用
#   系统 Python（C:\Python314\python.exe，已装 Pillow 12.x）运行；缺 PIL 时
#   本脚本会以 exit 2 明确退出，而不是崩在 traceback 里。
import os, re, subprocess, sys, tempfile

try:
    import PIL  # noqa: F401
except ImportError:
    print('FATAL: 缺少 Pillow（视觉判据需要）。请用系统 Python 运行，例如：')
    print('  C:\\Python314\\python.exe tools/sub-style-e2e.py')
    sys.exit(2)

PORTABLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # portable_config/
MPV_DIR = os.path.dirname(PORTABLE)                                       # mpv 根目录（含 mpv.exe）
MPV = os.path.join(MPV_DIR, 'mpv.exe')
PROBE = os.path.join(PORTABLE, 'tools', 'sub-style-probe.lua')
FIXTURE_MAIN = os.path.join(PORTABLE, 'tools', 'sub-style-smoke.ass')
FIXTURE_SEC = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-sec.ass')
FIXTURE_MULTI = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-multi.ass')
PROBE_STREAM = os.path.join(PORTABLE, 'tools', 'sub-style-probe-stream.lua')
PROBE_PRESET = os.path.join(PORTABLE, 'tools', 'sub-style-probe-preset.lua')
PROBE_PRESET_SAVE = os.path.join(PORTABLE, 'tools', 'sub-style-probe-preset-save.lua')
STATE_FILE = os.path.join(PORTABLE, 'uosc-subtitle-style-state.json')
PRESET_FILE = os.path.join(PORTABLE, 'uosc-subtitle-style-preset.json')
FONT_CACHE = os.path.join(PORTABLE, 'uosc-subtitle-style-fonts.json')

failures = []
def check(name, ok, detail=''):
    print('%s %s%s' % ('PASS' if ok else 'FAIL', name, (' | ' + detail) if detail else ''))
    if not ok:
        failures.append(name)

def main():
    workdir = tempfile.mkdtemp(prefix='substyle-e2e-')
    log = os.path.join(workdir, 'e2e-log.txt')
    watch_dir = os.path.join(workdir, 'watch_later')
    os.makedirs(watch_dir, exist_ok=True)

    # 清理上一轮的状态文件与字体缓存，保证从干净起点开始
    for p in (STATE_FILE, PRESET_FILE, FONT_CACHE):
        if os.path.exists(p):
            os.remove(p)

    env = dict(os.environ)
    env['SUBSTYLE_SMOKE_DIR'] = workdir
    # 本环境（portable_config）uosc 是产品前端，恒应存在：探测到 main.lua 即以
    # SUBSTYLE_UOSC=1 令探针把字体选择器断言升级为强制；确实没有 uosc 时才容忍
    # SKIP（探针会打印原因），避免「悄悄少测三项」。必须在 mpv 启动前设置。
    uosc_main = os.path.join(PORTABLE, 'scripts', 'uosc', 'main.lua')
    uosc_present = os.path.exists(uosc_main)
    if uosc_present:
        env['SUBSTYLE_UOSC'] = '1'
        print('uosc: %s（字体选择器断言强制）' % uosc_main)
    else:
        print('uosc: 未找到 %s —— 字体选择器三项将 SKIP' % uosc_main)
    cmd = [
        MPV,
        '--script=' + PROBE,
        '--sub-file=' + FIXTURE_MAIN,
        '--sub-file=' + FIXTURE_SEC,
        '--secondary-sid=2',
        # vo=image 无窗口 → osd-dimensions 为空 → uosc 菜单不渲染；必须用带窗口的 gpu
        '--vo=gpu',
        '--screenshot-dir=' + workdir,
        '--screenshot-template=substyle-menu',
        '--screenshot-format=png',
        # watch-later 隔离：用户的 mpv.conf 开了 save-position-on-quit，lavfi URL 会在
        # cache/watch_later 留 resume 状态，下次运行触发竞态
        '--watch-later-dir=' + watch_dir,
        '--save-position-on-quit=no',
        '--no-resume-playback',
        '--msg-level=all=info',
        'av://lavfi:color=c=gray:s=640x360:d=60:rate=25',
    ]
    print('RUN:', ' '.join(cmd))
    proc = subprocess.run(cmd, cwd=MPV_DIR, env=env, stdout=open(log, 'w'),
                          stderr=subprocess.STDOUT, timeout=240)
    print('mpv exit=%d' % proc.returncode)

    text = open(log, encoding='utf-8', errors='replace').read()

    # ---- 1. PROBE 断言汇总 ----
    results = {}
    for l in text.splitlines():
        m = re.search(r'PROBE (PASS|FAIL|SKIP) ([a-z0-9.-]+)', l)
        if m:
            results[m.group(2)] = (m.group(1), l)
    expected = ['base-shot', 'baseline-keeps-mpv-defaults', 'main-pos-50', 'main50-shot',
                'sec-target-switched', 'sec-pos-75', 'main-pos-untouched', 'sec10-shot',
                'sec-font-set', 'sec-override-force', 'main-override-baseline',
                'font-not-leaked-to-shared-list', 'secfont-shot',
                'sec-size-24-prop', 'secsize03-shot', 'secsize-shot',
                'overlap-target-kept', 'overlap-other-pushed',
                'outline-size-set', 'outline-color-set',
                'state-file-written',
                'reset-restores-defaults',
                'font-picker-opens', 'font-cache-enumerated', 'font-picker-rescan']
    # 无 uosc 时字体选择器三项合法 SKIP（探针记录原因）；带 uosc 时 SKIP = 缺陷
    skippable = set() if uosc_present else {
        'font-picker-opens', 'font-cache-enumerated', 'font-picker-rescan'}
    for name in expected:
        if name not in results:
            check('probe-' + name, False, 'missing in log')
        elif results[name][0] == 'SKIP' and name in skippable:
            print('SKIP probe-%s | %s' % (name, results[name][1][:110]))
        else:
            check('probe-' + name, results[name][0] == 'PASS', results[name][1][:110])
    summary = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', text)
    check('probe-summary-all-ok', bool(summary) and summary.group(2) == '0',
          summary.group(0) if summary else 'not found')

    # ---- 2. 日志中不得有 Lua 错误，也不得中途结束播放 ----
    lua_errs = [l for l in text.splitlines() if 'Lua error' in l or 'traceback' in l]
    check('no-lua-errors', len(lua_errs) == 0, '; '.join(lua_errs[:3]))
    eof_lines = [l for l in text.splitlines() if 'Exiting... (End of file)' in l]
    check('playback-survives-styles', len(eof_lines) == 0,
          'sub-reload/异常导致播放提前结束 %d 次' % len(eof_lines))

    # ---- 3. 视觉判据（截图波段）----
    def bands(tag):
        """返回 [(y0,y1,px), ...] 白字带（排除 uosc 顶栏与进度条）"""
        from PIL import Image
        p = os.path.join(workdir, tag + '.png')
        if not os.path.exists(p):
            return None
        im = Image.open(p).convert('RGB')
        w, h = im.size
        px = im.load()
        rows = []
        # 排除 uosc 顶栏（y<40）与进度条（y>348）；范围经实测标定
        for y in range(40, min(h - 12, 348)):
            c = sum(1 for x in range(w) if sum(px[x, y]) / 3.0 > 200)
            if c > 3:
                rows.append((y, c))
        if not rows:
            return []
        groups = []
        for y, c in rows:
            if groups and y - groups[-1][-1][0] <= 2:
                groups[-1].append((y, c))
            else:
                groups.append([(y, c)])
        out = []
        for g in groups:
            ys = [y for y, _ in g]
            out.append((min(ys), max(ys), sum(c for _, c in g)))
        return out

    # 尺子说明：截图里除主/次字幕外还有 uosc 底部 UI 区（进度条/控件，y>300）
    # 与顶栏（y<40）。因此不用「第几条带」索引，改为按 y 区间找带：
    #   主字幕带：y120-180（pos=50 实测 y136-161）
    #   次字幕带：y200-270（pos=75 实测 y220-244）
    #   底部混合带：y290+（两轨 baseline 时的字幕 + UI，只用于证明「原本在底部」）
    def find_band(bs, lo, hi):
        for b in bs:
            if lo <= b[0] <= hi:
                return b
        return None

    def h_of(b):
        return (b[1] - b[0] + 1) if b else None

    b_base = bands('base')
    b_main = bands('main50')
    b_sec = bands('sec10')
    b_font = bands('secfont')
    b_size = bands('secsize')
    for tag, bb in (('base', b_base), ('main50', b_main), ('sec10', b_sec),
                    ('secfont', b_font), ('secsize', b_size)):
        check('shot-' + tag, bb is not None, 'bands=%s' % (bb,))

    if all(x is not None for x in (b_base, b_main, b_sec, b_font, b_size)):
        # baseline：两轨重叠在底部 ⇒ 存在 y290+ 的宽带
        bottom0 = find_band(b_base, 290, 400)
        check('baseline-bottom-band', bottom0 is not None, str(b_base))

        # main50：主字幕带到中部（y136-161），底部仍有宽带（次字幕+UI）
        m50 = find_band(b_main, 120, 180)
        check('main50-main-at-middle', m50 is not None, str(b_main))

        # sec75：次字幕带到中下部（y220-244），主字幕带保持原位
        s75 = find_band(b_sec, 200, 270)
        m75 = find_band(b_sec, 120, 180)
        check('sec75-sec-at-lower-middle', s75 is not None, str(b_sec))
        check('sec75-main-unchanged',
              m75 is not None and m50 is not None
              and abs(m75[0] - m50[0]) <= 4 and abs(m75[2] - m50[2]) < m50[2] * 0.02,
              'main %s → %s' % (m50, m75))

        # 分轨字体（作用于次轨）：次带像素变化，主带像素级不变
        f75 = find_band(b_font, 200, 270)
        mf = find_band(b_font, 120, 180)
        if s75 and f75 and mf and m75:
            check('font-per-track-main-unchanged',
                  abs(mf[2] - m75[2]) < m75[2] * 0.02,
                  'main px %d → %d' % (m75[2], mf[2]))
            check('font-per-track-sec-changed',
                  abs(f75[2] - s75[2]) > s75[2] * 0.10,
                  'sec px %d → %d' % (s75[2], f75[2]))

        # 分轨字号（作用于次轨）：次带 15px → ~5px，主带高度不变
        z75 = find_band(b_size, 200, 270)
        mz = find_band(b_size, 120, 180)
        if s75 and z75 and mf and mz:
            check('size-shrinks-target-only',
                  h_of(z75) <= 8 and h_of(s75) >= 12
                  and abs(h_of(mz) - h_of(mf)) <= 2,
                  'sec h %d → %d, main h %d → %d' % (h_of(s75), h_of(z75), h_of(mf), h_of(mz)))

    # ---- 4. 字幕流连续性回归（用户报障：编辑时字幕定住不跳句）----
    # 用多句 fixture（每 2s 一句）：编辑前后「显示文本」必须始终与
    # playback-time 对应的期望事件一致。单句贯穿全片的 fixture 覆盖不到。
    stream_log = os.path.join(workdir, 'stream-log.txt')
    stream_cmd = [
        MPV,
        '--script=' + PROBE_STREAM,
        '--sub-file=' + FIXTURE_MULTI,
        '--vo=gpu', '--ao=null',
        '--watch-later-dir=' + watch_dir,
        '--save-position-on-quit=no',
        '--no-resume-playback',
        '--msg-level=all=info',
        'av://lavfi:color=c=gray:s=640x360:d=24:rate=25',
    ]
    print('RUN(stream):', ' '.join(stream_cmd))
    sproc = subprocess.run(stream_cmd, cwd=MPV_DIR, env=env, stdout=open(stream_log, 'w'),
                           stderr=subprocess.STDOUT, timeout=180)
    print('mpv(stream) exit=%d' % sproc.returncode)
    stext = open(stream_log, encoding='utf-8', errors='replace').read()
    sresults = {}
    for l in stext.splitlines():
        m = re.search(r'PROBE (PASS|FAIL) ([a-z0-9.-]+)', l)
        if m:
            sresults[m.group(2)] = (m.group(1), l)
    for name in ('baseline-advances', 'after-size-edit-advances',
                 'after-font-edit-advances'):
        if name not in sresults:
            check('stream-' + name, False, 'missing in log')
        else:
            check('stream-' + name, sresults[name][0] == 'PASS',
                  sresults[name][1][:110])
    ssum = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', stext)
    check('stream-summary-all-ok', bool(ssum) and ssum.group(2) == '0',
          ssum.group(0) if ssum else 'not found')
    serrs = [l for l in stext.splitlines() if 'Lua error' in l or 'traceback' in l]
    check('stream-no-lua-errors', len(serrs) == 0, '; '.join(serrs[:2]))

    # ---- 5. 预设样式：彩色才套用 / 白色保持原样 / 预设可修改并缓存 ----
    # 六个真机用例（每次独立运行，watch-later 已隔离）：
    #   A 彩色 fixture + 出厂预设 → 自动套用（override=force / 粗细 2 / 白字）
    #   B 白色 fixture            → 只报告不修改（override=scale / 粗细 0.5）
    #   C 白色 fixture            → 改样式 + preset-save → 断言落盘
    #   D 删 state 留 preset 缓存 → 重启 → 彩色套用缓存预设（洋红/绿描边/4）
    #   E 彩色 fixture + 次字幕轨（双语）→ 双轨跳过：不套用（override=scale /
    #     粗细 0.5），且字幕带保持黄色（与 A 同 fixture 差分 ⇒ 证明是双语生效而非偶然）
    #   F 白字 + 紫描边(#481081) fixture → 描边是彩色 ⇒ 判彩色并转黑白（override=force /
    #     白字），字幕带由紫描边变黑描边（与 A 差分：A 考彩字变白，F 考彩描边也触发）
    FIXTURE_COLORED = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-colored.ass')
    FIXTURE_PURPLE = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-purple.ass')

    def probe_of(text):
        rs = {}
        for l in text.splitlines():
            m = re.search(r'PROBE (PASS|FAIL) ([a-z0-9.-]+)', l)
            if m:
                rs[m.group(2)] = (m.group(1), l)
        return rs

    def run_preset_case(script, fixture, tag, expect, color='#FFFFFF', outline='2',
                        sec_fixture=None):
        plog = os.path.join(workdir, tag + '-log.txt')
        pcmd = [MPV, '--script=' + script, '--sub-file=' + fixture]
        if sec_fixture:
            pcmd += ['--sub-file=' + sec_fixture, '--secondary-sid=2']
        pcmd += [
                '--vo=gpu',
                '--screenshot-dir=' + workdir,
                '--screenshot-template=' + tag,
                '--screenshot-format=png',
                '--watch-later-dir=' + watch_dir,
                '--save-position-on-quit=no',
                '--no-resume-playback',
                '--msg-level=all=info',
                'av://lavfi:color=c=gray:s=640x360:d=12:rate=25']
        penv = dict(env)
        penv['SUBSTYLE_PRESET_EXPECT'] = expect
        penv['SUBSTYLE_PRESET_COLOR'] = color
        penv['SUBSTYLE_PRESET_OUTLINE'] = outline
        penv['SUBSTYLE_PRESET_TAG'] = tag
        print('RUN(%s):' % tag, ' '.join(pcmd))
        pproc = subprocess.run(pcmd, cwd=MPV_DIR, env=penv,
                               stdout=open(plog, 'w'), stderr=subprocess.STDOUT,
                               timeout=120)
        print('mpv(%s) exit=%d' % (tag, pproc.returncode))
        return open(plog, encoding='utf-8', errors='replace').read()

    # 每个用例都从「干净起点」开始：persist=true 会跨进程记忆样式
    # （A 退出时 save_state 写下 force/白字，B 若不清就会被带过去——
    #  这是产品设计而非缺陷，测试要的是干净起点）。
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    ta = run_preset_case(PROBE_PRESET, FIXTURE_COLORED, 'preset-a', 'applied')
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    tb = run_preset_case(PROBE_PRESET, FIXTURE_MULTI, 'preset-b', 'kept')
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    tc = run_preset_case(PROBE_PRESET_SAVE, FIXTURE_MULTI, 'preset-c', 'kept')
    # D 前只删 state（保留 C 写下的 preset 缓存）→ 模拟「重启后读缓存」
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)
    td = run_preset_case(PROBE_PRESET, FIXTURE_COLORED, 'preset-d', 'applied',
                         color='#FF00FF', outline='4')
    # E 前全清（state + preset）→ 与 A 的唯一差别是多了次字幕轨
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    te = run_preset_case(PROBE_PRESET, FIXTURE_COLORED, 'preset-e', 'kept-dual',
                         sec_fixture=FIXTURE_SEC)
    # F：白字 + 紫描边（#481081）——主色白非彩，但描边紫是彩色 ⇒ 判彩色并转黑白。
    #    与 A 的差分：A 是彩字（黄）转白；F 是白字+彩描边，专考「描边色也参与彩色判定」。
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    tf = run_preset_case(PROBE_PRESET, FIXTURE_PURPLE, 'preset-f', 'applied')

    for tag, text, names in (
            ('a', ta, ('early-shot', 'late-shot', 'preset-auto-applied')),
            ('b', tb, ('early-shot', 'late-shot', 'preset-kept-original')),
            ('c', tc, ('preset-file-written', 'preset-save-keeps-current')),
            ('d', td, ('early-shot', 'late-shot', 'preset-auto-applied')),
            ('e', te, ('early-shot', 'late-shot', 'dual-track-present',
                       'preset-kept-dual')),
            ('f', tf, ('early-shot', 'late-shot', 'preset-auto-applied'))):
        rs = probe_of(text)
        for name in names:
            if name not in rs:
                check('preset-%s-%s' % (tag, name), False, 'missing in log')
            else:
                check('preset-%s-%s' % (tag, name), rs[name][0] == 'PASS',
                      rs[name][1][:110])
        psum = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', text)
        check('preset-%s-summary' % tag, bool(psum) and psum.group(2) == '0',
              psum.group(0) if psum else 'not found')

    # ---- 5b. 视觉判据（截图像素）----
    from PIL import Image

    def px_of(tag):
        p = os.path.join(workdir, tag + '.png')
        if not os.path.exists(p):
            return None
        return Image.open(p).convert('RGB')

    def report_region_diff(tag_early, tag_late):
        """左上角报告区（y<36, x<420）early→late 像素差异数。
        early 早于 inspect_delay(1.2s) 截图 ⇒ 报告只应出现在 late。"""
        a, b = px_of(tag_early), px_of(tag_late)
        if a is None or b is None:
            return None
        pa, pb = a.load(), b.load()
        diff = 0
        for y in range(0, min(36, a.size[1])):
            for x in range(0, min(420, a.size[0])):
                r1, g1, b1 = pa[x, y]
                r2, g2, b2 = pb[x, y]
                if abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) > 90:
                    diff += 1
        return diff

    def band_color_count(tag, lo, hi, pred):
        """字幕带（按 y 区间）内满足 pred(r,g,b) 的像素数。"""
        im = px_of(tag)
        if im is None:
            return None
        w, h = im.size
        px = im.load()
        n = 0
        for y in range(lo, min(hi, h)):
            for x in range(0, w):
                if pred(*px[x, y]):
                    n += 1
        return n

    # 字幕带 y 区间（640x360，pos=100 实测 y304-328；uosc 底栏在 y>348）
    BAND_LO, BAND_HI = 295, 335
    # 报告出现：A/B/D/E/F 的左上角区域都应有大量新像素（报告显示 6s 窗口）
    for tag in ('a', 'b', 'd', 'e', 'f'):
        d = report_region_diff('preset-%s-early' % tag, 'preset-%s-late' % tag)
        check('preset-%s-report-shown' % tag, d is not None and d > 50,
              'diff=%s' % (d,))
    # A：彩色字幕套用预设 ⇒ late 字幕带由黄(#FFFF00)变白（预设 #FFFFFF）
    y_early = band_color_count('preset-a-early', BAND_LO, BAND_HI,
                               lambda r, g, b: r > 200 and g > 200 and b < 120)
    y_late = band_color_count('preset-a-late', BAND_LO, BAND_HI,
                              lambda r, g, b: r > 200 and g > 200 and b < 120)
    w_late = band_color_count('preset-a-late', BAND_LO, BAND_HI,
                              lambda r, g, b: r > 225 and g > 225 and b > 225)
    check('preset-a-early-is-yellow', y_early is not None and y_early > 100,
          'yellow=%s' % (y_early,))
    check('preset-a-late-is-white',
          y_late is not None and y_early is not None
          and y_late < y_early * 0.25 and w_late is not None and w_late > 100,
          'yellow %s → %s, white=%s' % (y_early, y_late, w_late))
    # D：缓存预设（洋红 #FF00FF）⇒ late 字幕带出现洋红像素
    m_late = band_color_count('preset-d-late', BAND_LO, BAND_HI,
                              lambda r, g, b: r > 200 and b > 200 and g < 120)
    check('preset-d-late-is-magenta', m_late is not None and m_late > 100,
          'magenta=%s' % (m_late,))
    # B：白色字幕本就白字，套用与否的强断言已在探针属性层完成
    #   （override=scale / 粗细 0.5），这里只补「不套用=不引入 force」的截图确认：
    b_late = band_color_count('preset-b-late', BAND_LO, BAND_HI,
                              lambda r, g, b: r > 225 and g > 225 and b > 225)
    check('preset-b-late-still-white', b_late is not None and b_late > 100,
          'white=%s' % (b_late,))
    # E：与 A 同一个彩色 fixture，唯一差别是次字幕轨 ⇒ 双轨跳过逻辑必须让它
    #   保持黄色（若误套用会变白，与 A 的判据相同）。这是「双语默认不改颜色」
    #   的差分证明：同 fixture 单轨套用、双轨不套用。
    e_early_yellow = band_color_count('preset-e-early', BAND_LO, BAND_HI,
                                      lambda r, g, b: r > 200 and g > 200 and b < 120)
    e_late_yellow = band_color_count('preset-e-late', BAND_LO, BAND_HI,
                                     lambda r, g, b: r > 200 and g > 200 and b < 120)
    e_late_white = band_color_count('preset-e-late', BAND_LO, BAND_HI,
                                    lambda r, g, b: r > 225 and g > 225 and b > 225)
    # 只判主轨黄字仍在（未被误套用预设转白）：主轨若被误转白，黄字会跌到近 0。
    # 不用 white<yellow*0.25——次轨(白字)因 configure_ass 渲染时序在高负载下可能落入
    # 底部测量带、覆盖部分主轨黄字（干净复刻下次轨在顶部、黄字满值），会误报。
    check('preset-e-late-still-yellow',
          e_early_yellow is not None and e_late_yellow is not None
          and e_early_yellow > 100 and e_late_yellow >= e_early_yellow * 0.5,
          'yellow %s → %s (sec-white=%s)' % (e_early_yellow, e_late_yellow, e_late_white))
    # F：白字 + 紫描边。早图（未套用）字幕带应有紫(#481081)；套用后描边转黑 ⇒ 紫消失。
    #    与 A 差分：A 考「彩字变白」，F 考「白字+彩描边也判彩色、描边转黑」。
    def is_purple(r, g, b):
        return b > 90 and b - r > 40 and b - g > 60
    f_early_purple = band_color_count('preset-f-early', BAND_LO, BAND_HI, is_purple)
    f_late_purple = band_color_count('preset-f-late', BAND_LO, BAND_HI, is_purple)
    f_late_white = band_color_count('preset-f-late', BAND_LO, BAND_HI,
                                    lambda r, g, b: r > 225 and g > 225 and b > 225)
    check('preset-f-early-has-purple', f_early_purple is not None and f_early_purple > 50,
          'purple=%s' % (f_early_purple,))
    check('preset-f-late-purple-gone',
          f_late_purple is not None and f_early_purple is not None
          and f_late_purple < f_early_purple * 0.2,
          'purple %s → %s' % (f_early_purple, f_late_purple))
    check('preset-f-late-has-white', f_late_white is not None and f_late_white > 100,
          'white=%s' % (f_late_white,))

    perrs = []
    for tag, text in (('a', ta), ('b', tb), ('c', tc), ('d', td), ('e', te), ('f', tf)):
        for l in text.splitlines():
            if 'Lua error' in l or 'traceback' in l:
                perrs.append(tag + ':' + l)
    check('preset-no-lua-errors', len(perrs) == 0, '; '.join(perrs[:3]))

    # ---- 6. 清理测试产物 ----
    for p in (STATE_FILE, PRESET_FILE, FONT_CACHE):
        if os.path.exists(p):
            os.remove(p)

    print('workdir=%s' % workdir)
    print('SUMMARY sub-style-e2e %s fail=%d %s' % (
        'PASS' if not failures else 'FAIL', len(failures),
        '' if not failures else ('FAILED: ' + ','.join(failures))))
    return 0 if not failures else 1

if __name__ == '__main__':
    sys.exit(main())
