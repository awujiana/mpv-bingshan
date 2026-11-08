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
#   4b. v1.0.6 回归：灰色 #8B8B8B + 带 \pos 的顶部字幕自动转黑白、
#       菜单点黑色主色（带引号的 "#000000" 不再被当注释吞掉）、字体写入共享样式表。
#       顶部字幕带的像素由 screenshot-raw 差分统计，与 OSD/UI 无关。
#   5d. v1.0.7 上下黑边贴合：用 Pillow 生成 640x360、上下各 24px 内嵌黑条
#       的图片当视频帧，双轨 SRT 普通对白；探针轮询等自动检测落定后，
#       对比开关前后的字幕像素分布 —— 贴合后主/次轨分别缩进下/上黑边，
#       画面中部（视频内容区）差分像素必须归零。
#   5e. v1.0.9 内封定位 ASS：用 sub-style-mkv-fixture.py 生成带内封 ASS
#       轨的最小 MKV（MJPEG 单帧 + \pos 事件），跑 plain / bars 两轮真机，
#       验证缩放与字号真的改变 \pos 字幕画面、sub-scale 不双叠加、1% 微调
#       通过 PlayResY 同步位移 \pos 字幕、关通道可复现原报障、黑边自动缩小
#       并把放大值存进预设。
#   5g. v1.0.11 对话轨道也是 \pos：上下 24px 黑条 + 两条 explicit 定位对白，
#       验证黑边贴合把底部对白整条推进黑边、点下移真的有效、关位移通道
#       后复现「点下移没反应」，且开关可逆。
#   5h. v1.0.11 show_report：同一夹具起 yes / no 两轮互为对照组，验证 conf
#       能完全关掉左上角 OSD、运行时 report-toggle 双向生效，而检测链与
#       黑边贴合照常执行。
#   5i/5j. v1.0.12 多内封轨字号自动匹配、多 Style 表下只按 Default 定字号。
#   5k. v1.0.13 切轨重检：内封 + 两条外挂（彩色 / 标准白字）逐轨切换，切过去
#       与切回来都必须重新检测、重新套用或清除自动预设。
#   5l. v1.0.13 换片清场：有黑边 → 无黑边，end-file 清掉 PlayResY / Fontsize
#       绝对覆盖，新文件黑边贴合关闭、边距 / 字号回到基线。
#   5m. v1.0.15 画面边界守护：bars=24 / bars=0 两种夹具，连续点下移到
#       pos 110/111/112/150，底部 \pos 对白必须「盒高不缩水 + 完整在帧内」，
#       PlayResY 倍率被钳在 ass_pos_shift_max，顶部 signs 仍可见。回归用户
#       截图「对话字幕有一部分在视频外了」（修复前 pos=110 只剩 5 行像素）。
#   ⚠ 第三方插件（.gitmodules 里的 submodule）自身的 Lua 报错由 lua_errors()
#     按日志标签隔离，被测脚本与探针的任何报错仍然算 FAIL。
# 用法（在 portable_config/ 下）：python tools/sub-style-e2e.py
# 独立公开仓库（仓库根没有 mpv.exe）复用本编排时：
#   MPV_EXE=/path/to/mpv.exe python tools/sub-style-e2e.py
#   会自动加 --config-dir=<仓库根>，把仓库当作 portable_config 且不读用户全局配置。
# ⚠ 视觉判据依赖 Pillow：PATH 里的 managed python 未装 Pillow，本机请用
#   系统 Python（C:\Python314\python.exe，已装 Pillow 12.x）运行；缺 PIL 时
#   本脚本会以 exit 2 明确退出，而不是崩在 traceback 里。
import os, re, shutil, subprocess, sys, tempfile

try:
    import PIL  # noqa: F401
    from PIL import Image
except ImportError:
    print('FATAL: 缺少 Pillow（视觉判据需要）。请用系统 Python 运行，例如：')
    print('  C:\\Python314\\python.exe tools/sub-style-e2e.py')
    sys.exit(2)

PORTABLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # portable_config/
MPV_DIR = os.path.dirname(PORTABLE)                                       # mpv 根目录（含 mpv.exe）
MPV = os.path.join(MPV_DIR, 'mpv.exe')
# 独立公开仓库（awujiana/uosc_subtitle_style）也共用这份编排：仓库根就是配置根，
# 播放器不在上一级目录。此时由 MPV_EXE 指定 mpv.exe，并显式 --config-dir 隔离
# 用户全局配置；生产环境命中 mpv.exe 时 CONFIG_ARGS 为空，行为与旧版完全一致。
CONFIG_ARGS = []
STANDALONE = not os.path.exists(MPV)
if STANDALONE:
    MPV = os.environ.get('MPV_EXE') or shutil.which('mpv') or MPV
    MPV_DIR = os.path.dirname(os.path.abspath(MPV))
    CONFIG_ARGS = ['--config-dir=' + PORTABLE, '--idle=no']
    if not os.path.exists(MPV):
        print('FATAL: 未找到 mpv.exe；请设置 MPV_EXE 或把 mpv 放进 PATH')
        sys.exit(2)
    print('standalone layout: config-dir=%s mpv=%s' % (PORTABLE, MPV))


def run_mpv(args, **kwargs):
    """在真正启动 mpv 前注入 CONFIG_ARGS，统一 cwd 为 mpv.exe 所在目录。"""
    return subprocess.run([args[0]] + CONFIG_ARGS + args[1:],
                          cwd=MPV_DIR, **kwargs)


PROBE = os.path.join(PORTABLE, 'tools', 'sub-style-probe.lua')
FIXTURE_MAIN = os.path.join(PORTABLE, 'tools', 'sub-style-smoke.ass')
FIXTURE_SEC = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-sec.ass')
FIXTURE_MULTI = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-multi.ass')
FIXTURE_POS_GRAY = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-pos-gray.ass')
PROBE_STREAM = os.path.join(PORTABLE, 'tools', 'sub-style-probe-stream.lua')
PROBE_PRESET = os.path.join(PORTABLE, 'tools', 'sub-style-probe-preset.lua')
PROBE_PRESET_SAVE = os.path.join(PORTABLE, 'tools', 'sub-style-probe-preset-save.lua')
PROBE_POS = os.path.join(PORTABLE, 'tools', 'sub-style-probe-pos.lua')
PROBE_BARS = os.path.join(PORTABLE, 'tools', 'sub-style-probe-bars.lua')
FIXTURE_BARS_MAIN = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-bars-main.srt')
FIXTURE_BARS_SEC = os.path.join(PORTABLE, 'tools', 'sub-style-smoke-bars-sec.srt')
MKV_FIXTURE = os.path.join(PORTABLE, 'tools', 'sub-style-mkv-fixture.py')
PROBE_FONTSIZE = os.path.join(PORTABLE, 'tools', 'sub-style-probe-fontsize.lua')
PROBE_API = os.path.join(PORTABLE, 'tools', 'sub-style-probe-api.lua')
PROBE_SHIFT = os.path.join(PORTABLE, 'tools', 'sub-style-probe-shift.lua')
PROBE_TRACKS = os.path.join(PORTABLE, 'tools', 'sub-style-probe-tracks.lua')
PROBE_REINSPECT = os.path.join(PORTABLE, 'tools', 'sub-style-probe-reinspect.lua')
PROBE_BOUNDS = os.path.join(PORTABLE, 'tools', 'sub-style-probe-bounds.lua')
STATE_FILE = os.path.join(PORTABLE, 'uosc-subtitle-style-state.json')
PRESET_FILE = os.path.join(PORTABLE, 'uosc-subtitle-style-preset.json')
FONT_CACHE = os.path.join(PORTABLE, 'uosc-subtitle-style-fonts.json')

failures = []
def check(name, ok, detail=''):
    print('%s %s%s' % ('PASS' if ok else 'FAIL', name, (' | ' + detail) if detail else ''))
    if not ok:
        failures.append(name)

# 随 portable_config 一起加载、但不在本仓库维护的第三方插件（见 .gitmodules）。
# uosc_danmaku 在无网络环境下 sites/iqiyi.lua:17 的报错每次都会污染日志；
# 只放行带这些标签的行，被测脚本 uosc_subtitle_style / 各探针的报错仍然 FAIL。
THIRD_PARTY_LOG_TAGS = ('[uosc_danmaku]', '[uosc_staff_credits]', '[dynamic_crop]')

def lua_errors(text):
    errs, ignored = [], 0
    for l in text.splitlines():
        if 'Lua error' in l or 'traceback' in l:
            if any(t in l for t in THIRD_PARTY_LOG_TAGS):
                ignored += 1
            else:
                errs.append(l)
    return errs, ignored

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
    if not uosc_present and STANDALONE:
        # 独立仓库不内置 uosc（第三方 LGPL 项目）：从 UOSC_MAIN 或 mpv 目录的
        # portable_config 复制一份，让字体选择器断言照常参与实测而非悄悄 SKIP。
        # 副本保留在 scripts/uosc/（.gitignore 已排除），后续 E2E 直接复用：
        # 不做退出时删除 —— 部分托管 Python 会拦截 shutil.rmtree / os.unlink 的
        # 批量删除，在 atexit 里抛 SystemExit 污染 E2E 日志末尾。副本不会进提交，
        # 也不随 git 源码分发（Release / 克隆得到的仓库里没有这个目录）。
        source = os.environ.get('UOSC_MAIN') or os.path.join(
            MPV_DIR, 'portable_config', 'scripts', 'uosc', 'main.lua')
        if os.path.exists(source):
            uosc_dir = os.path.dirname(uosc_main)
            shutil.copytree(os.path.dirname(source), uosc_dir, dirs_exist_ok=True)
            uosc_present = os.path.exists(uosc_main)
            print('uosc: %s → %s（测试副本，.gitignore 已排除，后续复用）'
                  % (source, uosc_dir))
    if uosc_present:
        env['SUBSTYLE_UOSC'] = '1'
        print('uosc: %s（字体选择器断言强制）' % uosc_main)
    else:
        print('uosc: 未找到 %s —— 字体选择器三项将 SKIP' % uosc_main)

    # uosc_staff_credits 是配置整合包里的另一份脚本；独立仓库没有它时，
    # 令 API 探针跳过职员表那 7 条断言（不伪造 PASS，直接不参与期望表）。
    staff_present = os.path.exists(os.path.join(
        PORTABLE, 'scripts', 'uosc_staff_credits', 'main.lua'))
    env['SUBSTYLE_STAFF_API'] = '1' if staff_present else '0'
    print('staff_credits: %s（API 探针职员表断言%s）'
          % ('present' if staff_present else 'absent',
             '启用' if staff_present else '跳过'))
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
    proc = run_mpv(cmd, env=env, stdout=open(log, 'w'),
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
                'font-in-shared-list-for-pos-signs',
                'toggle-all-clears-shared-style', 'secfont-shot',
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
    lua_errs, ignored = lua_errors(text)
    check('no-lua-errors', len(lua_errs) == 0,
          '; '.join(lua_errs[:3]) + (' | 已忽略第三方插件报错 %d 行' % ignored if ignored else ''))
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
    sproc = run_mpv(stream_cmd, env=env, stdout=open(stream_log, 'w'),
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
    serrs, signored = lua_errors(stext)
    check('stream-no-lua-errors', len(serrs) == 0,
          '; '.join(serrs[:2]) + (' | 已忽略第三方插件报错 %d 行' % signored if signored else ''))

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
                # v1.0.14 起「保持原样」默认静音（show_keep_original=no）。
                # 5b 的 report_region_diff 靠左上角报告像素证明检测确实跑过，
                # 且 B/E 正是「保持原样」用例，故这些真机轮次显式打开报告；
                # 默认静音本身由单测 T27d / T27e 守，不在这里放松。
                '--script-opts=uosc_subtitle_style-show_keep_original=yes',
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
        pproc = run_mpv(pcmd, env=penv,
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

    perrs, pignored = [], 0
    for tag, ptext in (('a', ta), ('b', tb), ('c', tc), ('d', td), ('e', te), ('f', tf)):
        es, ig = lua_errors(ptext)
        pignored += ig
        perrs += [tag + ':' + l for l in es]
    check('preset-no-lua-errors', len(perrs) == 0,
          '; '.join(perrs[:3]) + (' | 已忽略第三方插件报错 %d 行' % pignored if pignored else ''))

    # ---- 5c. v1.0.6 回归：\pos 顶部字幕 / 灰色字幕 / 黑色主色 / 字体 ----
    # 用户报障的四条集中在一个真机用例里验证：灰色(#8B8B8B)自动转黑白、
    # 顶部 \pos 字幕随样式表覆盖变色、菜单点黑色不再被当注释吞掉、字体写入共享列表。
    # 背景用纯黑，让灰/白字幕像素在 screenshot-raw 差分里清晰可数。
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    pos_log = os.path.join(workdir, 'pos-log.txt')
    pos_cmd = [
        MPV, '--script=' + PROBE_POS, '--sub-file=' + FIXTURE_POS_GRAY,
        '--vo=gpu', '--ao=null',
        '--watch-later-dir=' + watch_dir,
        '--save-position-on-quit=no', '--no-resume-playback',
        '--msg-level=all=info',
        'av://lavfi:color=c=black:s=640x360:d=14:rate=25',
    ]
    print('RUN(pos):', ' '.join(pos_cmd))
    posproc = run_mpv(pos_cmd, env=env,
                            stdout=open(pos_log, 'w'), stderr=subprocess.STDOUT,
                            timeout=120)
    print('mpv(pos) exit=%d' % posproc.returncode)
    postext = open(pos_log, encoding='utf-8', errors='replace').read()
    prs = probe_of(postext)
    for name in ('pos-early-top-gray', 'pos-auto-primary-ass', 'pos-auto-outline-ass',
                 'pos-auto-sub-color', 'pos-top-gray-turned-white',
                 'pos-black-sub-color', 'pos-black-primary-ass',
                 'pos-black-top-not-white', 'pos-font-shared-list',
                 'pos-font-sub-font'):
        if name not in prs:
            check(name, False, 'missing in log')
        else:
            check(name, prs[name][0] == 'PASS', prs[name][1][:150])
    psum = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', postext)
    check('pos-summary-all-ok', bool(psum) and psum.group(2) == '0',
          psum.group(0) if psum else 'not found')
    poerrs, poignored = lua_errors(postext)
    check('pos-no-lua-errors', len(poerrs) == 0,
          '; '.join(poerrs[:2]) + (' | 已忽略第三方插件报错 %d 行' % poignored if poignored else ''))

    # ---- 5d. v1.0.7 上下黑边贴合：双轨普通对白缩进上下黑边 ----
    # 夹具是「视频帧里真的编码了黑条」的图片（不是窗口 letterbox），
    # mpv 的 sub-use-margins 对它无能为力，只能靠脚本逐行亮度检测。
    for p in (STATE_FILE, PRESET_FILE):
        if os.path.exists(p):
            os.remove(p)
    bars_png = os.path.join(workdir, 'substyle-bars.png')
    bars_img = Image.new('RGB', (640, 360), (0, 0, 0))
    bars_img.paste((128, 128, 128), (0, 24, 640, 336))   # 上下各 24px 黑条
    bars_img.save(bars_png)
    bars_log = os.path.join(workdir, 'bars-log.txt')
    bars_cmd = [
        MPV, '--script=' + PROBE_BARS,
        '--sub-file=' + FIXTURE_BARS_MAIN,
        '--sub-file=' + FIXTURE_BARS_SEC,
        '--secondary-sid=2',
        '--sub-margin-y=80',          # 关闭贴合时字幕明显压在画面上，便于对照
        '--vo=gpu', '--ao=null',
        '--pause=yes', '--image-display-duration=inf',
        '--watch-later-dir=' + watch_dir,
        '--save-position-on-quit=no', '--no-resume-playback',
        '--msg-level=all=info',
        bars_png,
    ]
    print('RUN(bars):', ' '.join(bars_cmd))
    barsproc = run_mpv(bars_cmd, env=env,
                              stdout=open(bars_log, 'w'), stderr=subprocess.STDOUT,
                              timeout=120)
    print('mpv(bars) exit=%d' % barsproc.returncode)
    barstext = open(bars_log, encoding='utf-8', errors='replace').read()
    brs = probe_of(barstext)
    bars_expected = (
        'bars-auto-detect-applied', 'bars-fit-main-pos-bottom', 'bars-fit-sec-pos-top',
        'bars-fit-scale-limited', 'bars-fit-sec-scale-same',
        'bars-fit-margin-overrides-baseline', 'bars-fit-margin-is-integer',
        'bars-off-restores-margin', 'bars-base-frame-ok',
        'bars-base-dialogue-over-picture', 'bars-fit-frame-ok',
        'bars-fit-bottom-dialogue-in-lower-bar', 'bars-fit-top-dialogue-in-upper-bar',
        'bars-fit-no-dialogue-over-picture', 'bars-fit-both-bars-populated',
    )
    for name in bars_expected:
        if name not in brs:
            check(name, False, 'missing in log')
        else:
            check(name, brs[name][0] == 'PASS', brs[name][1][:150])
    bsum = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', barstext)
    check('bars-summary-all-ok', bool(bsum) and bsum.group(2) == '0',
          bsum.group(0) if bsum else 'not found')

    # Python 侧独立复核：解析探针打印的 BARS BASE/FIT 像素分布，
    # 不依赖探针自己的 PASS 判定，确保「不遮挡画面内容」有独立证据。
    def bars_row(tag):
        m = re.search(r'BARS %s [^\n]*?top=(\d+) mid=(\d+) bottom=(\d+)' % tag,
                      barstext)
        return tuple(int(x) for x in m.groups()) if m else None
    base_row, fit_row = bars_row('BASE'), bars_row('FIT')
    check('bars-visual-rows-present', base_row is not None and fit_row is not None,
          'base=%s fit=%s' % (base_row, fit_row))
    check('bars-visual-picture-cleared',
          bool(base_row and fit_row and base_row[1] > 150 and fit_row[1] == 0
               and fit_row[0] > 80 and fit_row[2] > 80),
          'base(top,mid,bottom)=%s fit=%s' % (base_row, fit_row))
    berrs, bignored = lua_errors(barstext)
    check('bars-no-lua-errors', len(berrs) == 0,
          '; '.join(berrs[:2]) + (' | 已忽略第三方插件报错 %d 行' % bignored
                                  if bignored else ''))

    # ---- 5e. v1.0.9 内封 \pos ASS：缩放 / 字号 / 黑边自动缩小真机回归 ----
    # 没有 ffmpeg、示例 MKV 4.1GB 也不在仓库里，所以夹具由纯 Python 直接写
    # 最小 Matroska：MJPEG 单帧视频 + 内封 S_TEXT/ASS 轨（含 \pos 事件）。
    # mpv 播放它时 current-tracks/sub.external=false，才走得到 v1.0.9 新通道。
    import importlib.util
    spec = importlib.util.spec_from_file_location('sub_style_mkv_fixture', MKV_FIXTURE)
    mkvmod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mkvmod)
    fs_plain = os.path.join(workdir, 'internal-plain.mkv')
    fs_bars = os.path.join(workdir, 'internal-bars.mkv')
    mkvmod.build(fs_plain, bars=0)
    mkvmod.build(fs_bars, bars=24)
    check('fs-fixtures-built',
          os.path.getsize(fs_plain) > 1024 and os.path.getsize(fs_bars) > 1024,
          'plain=%d bars=%d bytes' % (os.path.getsize(fs_plain),
                                      os.path.getsize(fs_bars)))

    def run_fs(tag, mkv_path, mode, base_n=0):
        for p in (STATE_FILE, PRESET_FILE):
            if os.path.exists(p):
                os.remove(p)
        flog = os.path.join(workdir, 'fs-' + tag + '-log.txt')
        fcmd = [
            MPV, '--script=' + PROBE_FONTSIZE,
            '--vo=gpu', '--ao=null', '--pause=yes',
            '--image-display-duration=inf',
            '--watch-later-dir=' + watch_dir,
            '--save-position-on-quit=no', '--no-resume-playback',
            '--msg-level=all=info', mkv_path,
        ]
        fenv = dict(env)
        fenv['SUBSTYLE_FS_MODE'] = mode
        fenv['SUBSTYLE_FS_BASE_N'] = str(int(base_n))
        print('RUN(fs-%s):' % tag, ' '.join(fcmd))
        fproc = run_mpv(fcmd, env=fenv,
                               stdout=open(flog, 'w'), stderr=subprocess.STDOUT,
                               timeout=180)
        print('mpv(fs-%s) exit=%d' % (tag, fproc.returncode))
        return open(flog, encoding='utf-8', errors='replace').read()

    def fs_n(text, tag):
        m = re.search(r'FS %s n=(\d+)' % re.escape(tag), text)
        return int(m.group(1)) if m else None

    def fs_asserts(prefix, text, expected):
        rs = probe_of(text)
        for name in expected:
            if name not in rs:
                check(prefix + name, False, 'missing in log')
            else:
                check(prefix + name, rs[name][0] == 'PASS', rs[name][1][:150])
        sm = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', text)
        check(prefix + 'summary-all-ok', bool(sm) and sm.group(2) == '0',
              sm.group(0) if sm else 'not found')
        es, ig = lua_errors(text)
        check(prefix + 'no-lua-errors', len(es) == 0,
              '; '.join(es[:2]) + (' | 已忽略第三方插件报错 %d 行' % ig if ig else ''))

    plain_expected = (
        'fs-track-internal-ass', 'fs-extradata-has-style',
        'fs-baseline-frame-ok', 'fs-baseline-no-fontsize',
        'fs-scale-writes-ass-fontsize', 'fs-scale-neutralizes-sub-scale',
        'fs-scale-folds-sub-font-size', 'fs-scale-enlarges-pos-subtitle',
        'fs-scale-reset-restores',
        'fs-size-step-writes-fontsize', 'fs-size-step-enlarges',
        'fs-size-step-reversible',
        'fs-nudge-moves-pos-subtitle', 'fs-nudge-writes-playres',
        'fs-nudge-compensates-fontsize', 'fs-nudge-ratio-at-limit',
        'fs-nudge-boundary-clamps',
        'fs-nudge-1-pos-step', 'fs-nudge-1-playres-ratio',
        'fs-pos-reset-clears-playres', 'fs-pos-reset-restores-visual',
        'fs-toggle-off-clears-fontsize',
        'fs-channel-off-uses-native-sub-scale',
        'fs-channel-off-scale-ignored-by-pos', 'fs-toggle-on-restores',
    )
    ptext = run_fs('plain', fs_plain, 'plain')
    fs_asserts('fs-plain-', ptext, plain_expected)

    # Python 侧独立复核：解析探针 FS 行的像素数，不依赖探针自己的 PASS 判定
    n_base = fs_n(ptext, '00-baseline')
    n_s150 = fs_n(ptext, '01-scale150')
    n_back = fs_n(ptext, '02-scale100')
    n_plus = fs_n(ptext, '03-sizeplus8')
    n_off = fs_n(ptext, '09-off-scale-no-visual')
    n_on = fs_n(ptext, '11-toggle-on-restores')
    check('fs-plain-visual-rows-present',
          all(v is not None for v in (n_base, n_s150, n_back, n_plus, n_off, n_on)),
          'base=%s scale150=%s back=%s plus=%s off=%s on=%s'
          % (n_base, n_s150, n_back, n_plus, n_off, n_on))
    if all(v is not None for v in (n_base, n_s150, n_back, n_plus, n_off, n_on)):
        check('fs-plain-visual-scale-enlarges', n_s150 > n_base * 1.35,
              '%d -> %d' % (n_base, n_s150))
        check('fs-plain-visual-reset-restores', abs(n_back - n_base) < n_base * 0.08,
              '%d -> %d' % (n_base, n_back))
        check('fs-plain-visual-size-step-enlarges',
              n_plus > n_base * 1.08 and n_plus < n_s150,
              'base=%d plus=%d scale150=%d' % (n_base, n_plus, n_s150))
        check('fs-plain-visual-channel-off-ignores',
              abs(n_off - n_base) < n_base * 0.10,
              'base=%d off=%d（复现原报障：sub-scale 变了但画面不变）'
              % (n_base, n_off))
        check('fs-plain-visual-toggle-on-restores', n_on > n_base * 1.35,
              '%d -> %d' % (n_base, n_on))

    bars_expected = (
        'fs-bars-track-internal-ass', 'fs-bars-auto-detect-applied',
        'fs-bars-shrinks-pos-subtitle', 'fs-bars-size-step-writes-fontsize',
        'fs-bars-size-step-enlarges', 'fs-bars-size-step-saves-preset',
        'fs-bars-size-step-reversible', 'fs-bars-off-clears-fontsize',
        'fs-bars-off-restores-visual',
    )
    btext = run_fs('bars', fs_bars, 'bars', n_base or 0)
    fs_asserts('fs-bars-', btext, bars_expected)
    b_fit = fs_n(btext, '00-fit')
    b_plus = fs_n(btext, '01-sizeplus8')
    b_off = fs_n(btext, '03-fit-off')
    check('fs-bars-visual-rows-present',
          all(v is not None for v in (b_fit, b_plus, b_off)),
          'fit=%s plus=%s off=%s plain-baseline=%s' % (b_fit, b_plus, b_off, n_base))
    if all(v is not None for v in (b_fit, b_plus, b_off)) and n_base:
        check('fs-bars-visual-auto-shrinks', b_fit < n_base * 0.95,
              'plain=%d fit=%d' % (n_base, b_fit))
        check('fs-bars-visual-size-step-enlarges', b_plus > b_fit * 1.05,
              'fit=%d plus=%d' % (b_fit, b_plus))
        check('fs-bars-visual-off-restores', abs(b_off - n_base) < n_base * 0.10,
              'off=%d plain=%d' % (b_off, n_base))
    # 预设缓存内容独立复核（探针在 Lua 侧已断言，这里再从 Python 读一次）
    try:
        preset_raw = open(PRESET_FILE, encoding='utf-8').read() \
            if os.path.exists(PRESET_FILE) else ''
    except OSError:
        preset_raw = ''
    check('fs-bars-preset-file-has-size', '"size"' in preset_raw,
          preset_raw[:120])

    # ---- 5f. v1.0.10 对外 API：user-data 广播 + 请求-响应 + call 真机生效 ----
    # 复用 5e 生成的无黑边内封 ASS MKV；这一组不判像素，只判 API 契约。
    api_log = os.path.join(workdir, 'api-log.txt')
    api_cmd = [
        MPV, '--script=' + PROBE_API,
        '--vo=gpu', '--ao=null', '--pause=yes',
        '--image-display-duration=inf',
        '--watch-later-dir=' + watch_dir,
        '--save-position-on-quit=no', '--no-resume-playback',
        '--msg-level=all=info', fs_plain,
    ]
    print('RUN(api):', ' '.join(api_cmd))
    aproc = run_mpv(api_cmd, env=env,
                           stdout=open(api_log, 'w'), stderr=subprocess.STDOUT,
                           timeout=180)
    print('mpv(api) exit=%d' % aproc.returncode)
    atext = open(api_log, encoding='utf-8', errors='replace').read()
    api_expected = [
        'api-userdata-version', 'api-userdata-version-is-native-string',
        'api-userdata-state-json', 'api-userdata-state-fields',
        'api-get-state-reply', 'api-get-state-request-id',
        'api-get-state-has-data', 'api-get-dotted-key', 'api-get-unknown-key',
        'api-call-dispatch', 'api-call-changes-state-broadcast',
        'api-property-pos-matches-broadcast', 'api-subscribe-native-observer',
        'api-call-rejects-recursive',
    ]
    # uosc_staff_credits 子仓库的对外 API：仅当配置里真的装了它才验，
    # 独立公开仓库不带这份脚本，跳过相应 7 条而不是伪造 PASS。
    if staff_present:
        api_expected += [
            'staff-api-userdata-version', 'staff-api-userdata-state-json',
            'staff-api-state-fields', 'staff-api-no-token-leak',
            'staff-api-get-state-reply', 'staff-api-get-state-request-id',
            'staff-api-list-actions',
        ]
    ars = probe_of(atext)
    for name in api_expected:
        if name not in ars:
            check('api-' + name, False, 'missing in log')
        else:
            check('api-' + name, ars[name][0] == 'PASS', ars[name][1][:150])
    asum = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', atext)
    check('api-summary-all-ok', bool(asum) and asum.group(2) == '0',
          asum.group(0) if asum else 'not found')
    aerrs, aignored = lua_errors(atext)
    check('api-no-lua-errors', len(aerrs) == 0,
          '; '.join(aerrs[:2]) + (' | 已忽略第三方插件报错 %d 行' % aignored if aignored else ''))

    # ---- 5g/5h. v1.0.11：\pos 对白进黑边 + show_report 开关 ----
    # 用户截图里底部「对话轨道」本身也是 \pos explicit ASS（普通对白 sub-pos
    # 是有效的，只有点下移没反应才说明是 explicit），因此两条事件都带 \pos。
    sh_mkv = os.path.join(workdir, 'internal-posdialog.mkv')
    mkvmod.build(sh_mkv, bars=24, events=(
        '{\\pos(320,60)}TOPDIALOG',
        '{\\pos(320,338)}BOTTOMDIALOG',
    ))
    check('sh-fixture-built', os.path.getsize(sh_mkv) > 1024,
          '%d bytes' % os.path.getsize(sh_mkv))

    def run_shift(tag, mode, expect, show_report=None):
        # 状态文件里残留的 pos=105/150 会让 ass_y_ratio() 误判成用户位移，
        # 造成「关贴合不清残留」的假失败；每轮必须从干净状态起。
        for p in (STATE_FILE, PRESET_FILE):
            if os.path.exists(p):
                os.remove(p)
        slog = os.path.join(workdir, 'shift-' + tag + '-log.txt')
        scmd = [
            MPV, '--script=' + PROBE_SHIFT,
            '--vo=gpu', '--ao=null', '--pause=yes',
            '--image-display-duration=inf',
            '--watch-later-dir=' + watch_dir,
            '--save-position-on-quit=no', '--no-resume-playback',
            '--msg-level=all=info',
        ]
        if show_report:
            scmd.append('--script-opts=uosc_subtitle_style-show_report='
                        + show_report)
        scmd.append(sh_mkv)
        senv = dict(env)
        senv['SUBSTYLE_SHIFT_MODE'] = mode
        senv['SUBSTYLE_SHIFT_EXPECT'] = expect
        print('RUN(shift-%s):' % tag, ' '.join(scmd))
        sproc = run_mpv(scmd, env=senv,
                        stdout=open(slog, 'w'), stderr=subprocess.STDOUT,
                        timeout=240)
        print('mpv(shift-%s) exit=%d' % (tag, sproc.returncode))
        return open(slog, encoding='utf-8', errors='replace').read()

    def shift_asserts(prefix, text, expected):
        rs = probe_of(text)
        for name in expected:
            if name not in rs:
                check(prefix + name, False, 'missing in log')
            else:
                check(prefix + name, rs[name][0] == 'PASS', rs[name][1][:150])
        sm = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', text)
        check(prefix + 'summary-all-ok', bool(sm) and sm.group(2) == '0',
              sm.group(0) if sm else 'not found')
        es, ig = lua_errors(text)
        check(prefix + 'no-lua-errors', len(es) == 0,
              '; '.join(es[:2]) + (' | 已忽略第三方插件报错 %d 行' % ig if ig else ''))

    shift_bars_expected = (
        'sh-barfit-writes-playres', 'sh-barfit-shrinks-fontsize',
        'sh-dialogue-fully-inside-bottom-bar', 'sh-top-sign-still-rendered',
        'sh-fit-off-clears-playres', 'sh-fit-off-clears-fontsize',
        'sh-fit-off-dialogue-leaves-bar',
        'sh-pos150-writes-playres', 'sh-pos150-moves-positioned-subtitle',
        'sh-pos150-compensates-fontsize', 'sh-pos150-ratio-at-limit',
        'sh-channel-off-no-playres', 'sh-channel-off-keeps-pos-subtitle',
        'sh-channel-off-sub-pos-changed',
        'sh-refresh-restores-playres', 'sh-refresh-dialogue-back-in-bar',
    )
    sh_bars = run_shift('bars', 'bars', 'no')
    shift_asserts('sh-bars-', sh_bars, shift_bars_expected)
    # Python 侧独立复核：解析探针 SH 行的 BOT 波段像素范围，不依赖它自己的 PASS
    def sh_bot_y0(text, tag):
        m = re.search(r'SH %s\s+.*?BOT\[n=\d+ y=(-?\d+)\.\.(-?\d+)\]'
                      % re.escape(tag), text)
        return int(m.group(1)) if m else None
    y_fit = sh_bot_y0(sh_bars, '00-fit')
    y_off = sh_bot_y0(sh_bars, '01-fit-off')
    check('sh-bars-visual-rows-present', y_fit is not None and y_off is not None,
          'fit_y0=%s off_y0=%s' % (y_fit, y_off))
    if y_fit is not None and y_off is not None:
        # 360 - 24 = 336，对白整条必须越过黑边上沿
        check('sh-bars-visual-dialogue-crosses-bar-top',
              y_fit >= 336 and y_off < 336,
              'fit_y0=%d off_y0=%d bar_top=336' % (y_fit, y_off))

    report_common = (
        'sh-report-counter-readable', 'sh-report-no-osd-align-change',
        'sh-report-detection-still-runs', 'sh-report-dialogue-still-in-bar',
        'sh-report-off-keeps-osd-align',
        'sh-report-toggle-flips-runtime-state',
        'sh-report-toggle-takes-effect',
        'sh-report-toggle-restores-conf-value',
        'sh-report-restore-takes-effect',
    )
    for expect, opt in (('no', 'no'), ('yes', 'yes')):
        text = run_shift('report-' + expect, 'report', expect, opt)
        names = report_common + (
            ('sh-report-config-read-as-off', 'sh-report-off-no-osd-output')
            if expect == 'no' else
            ('sh-report-config-read-as-on', 'sh-report-on-actually-shows'))
        shift_asserts('sh-report-%s-' % expect, text, names)

    # ---- 5i/5j. v1.0.12：拓展夹具的多场景真机回归 ----
    # 5i 三条内封 ASS 轨（PlayResY / Default.Fontsize 各不相同）：切 sid 后
    #    sub-ass-extradata 会变，Fontsize= / PlayResY= 绝对值必须逐轨重算，
    #    归一化物理字号 Fontsize/PlayResY 必须恒定。
    # 5j 单轨 + 多 Style（Default=20 / Sign=60）+ 带 \N 的多行对白 + 黑边：
    #    黑边贴合的盒高只按 Default 估算，Fontsize 不被大标题样式拉偏。
    SIGN_STYLE = ('Style: Sign,Arial,60,&H00FFFFFF,&H000000FF,&H00000000,'
                  '&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1')
    tr_switch = os.path.join(workdir, 'internal-three-tracks.mkv')
    mkvmod.build(tr_switch, bars=24,
                 events=('{\\pos(320,60)}TOPDIALOG',
                         '{\\pos(320,338)}FIRSTLINE\\NSECONDLINE'),
                 extra_subs=[
                     {'fontsize': 48, 'playres_y': 720,
                      'events': ('{\\pos(320,60)}TRACKB',)},
                     {'fontsize': 14, 'playres_y': 240,
                      'events': ('{\\pos(320,60)}TRACKC',)},
                 ])
    tr_styles = os.path.join(workdir, 'internal-multistyle.mkv')
    mkvmod.build(tr_styles, bars=24,
                 events=('{\\pos(320,60)}TOPDIALOG',
                         '{\\pos(320,338)}FIRSTLINE\\NSECONDLINE'),
                 styles=(SIGN_STYLE,))
    check('tr-fixtures-built',
          os.path.getsize(tr_switch) > 1024
          and os.path.getsize(tr_styles) > 1024,
          '%d / %d bytes' % (os.path.getsize(tr_switch),
                             os.path.getsize(tr_styles)))

    def run_tracks(tag, mode, fixture):
        # 与 5g/5h 同理：残留 state 会让 ass_y_ratio() 误判成用户位移
        for p in (STATE_FILE, PRESET_FILE):
            if os.path.exists(p):
                os.remove(p)
        tlog = os.path.join(workdir, 'tracks-' + tag + '-log.txt')
        tcmd = [
            MPV, '--script=' + PROBE_TRACKS,
            '--vo=gpu', '--ao=null', '--pause=yes',
            '--image-display-duration=inf',
            '--watch-later-dir=' + watch_dir,
            '--save-position-on-quit=no', '--no-resume-playback',
            '--msg-level=all=info', fixture,
        ]
        tenv = dict(env)
        tenv['SUBSTYLE_TRACKS_MODE'] = mode
        print('RUN(tracks-%s):' % tag, ' '.join(tcmd))
        tproc = run_mpv(tcmd, env=tenv,
                        stdout=open(tlog, 'w'), stderr=subprocess.STDOUT,
                        timeout=240)
        print('mpv(tracks-%s) exit=%d' % (tag, tproc.returncode))
        return open(tlog, encoding='utf-8', errors='replace').read()

    def tracks_asserts(prefix, text, expected):
        rs = probe_of(text)
        for name in expected:
            if name not in rs:
                check(prefix + name, False, 'missing in log')
            else:
                check(prefix + name, rs[name][0] == 'PASS', rs[name][1][:150])
        sm = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', text)
        check(prefix + 'summary-all-ok', bool(sm) and sm.group(2) == '0',
              sm.group(0) if sm else 'not found')
        es, ig = lua_errors(text)
        check(prefix + 'no-lua-errors', len(es) == 0,
              '; '.join(es[:2]) + (' | 已忽略第三方插件报错 %d 行' % ig if ig else ''))

    tracks_switch_expected = (
        'tr-three-internal-sub-tracks',
        'tr-track-a-header-readable', 'tr-track-a-writes-fontsize',
        'tr-track-b-header-readable', 'tr-track-b-writes-fontsize',
        'tr-track-b-header-changed', 'tr-track-b-fontsize-recomputed',
        'tr-track-b-physical-size-matches',
        'tr-track-c-header-readable', 'tr-track-c-writes-fontsize',
        'tr-track-c-header-changed', 'tr-track-c-fontsize-recomputed',
        'tr-track-c-physical-size-matches',
        'tr-all-tracks-physical-size-constant', 'tr-track-a-restored',
    )
    tracks_asserts('tr-switch-', run_tracks('switch', 'switch', tr_switch),
                   tracks_switch_expected)
    tracks_styles_expected = (
        'tr-multi-style-header', 'tr-multi-style-fontsize-uses-base',
        'tr-multi-style-not-skewed-by-sign', 'tr-multi-style-playres-written',
    )
    tracks_asserts('tr-styles-', run_tracks('styles', 'styles', tr_styles),
                   tracks_styles_expected)

    # ---- 5k/5l. v1.0.13：切轨与换片都必须重新检测 / 清场 ----
    # 5k 用「1 条内封 ASS + 2 条外挂 ASS」组合夹具，覆盖内封⇄外挂、彩色⇄白字、
    #   切出去再切回来；判据用 API state 的 report_shown（每次成功检测 +1）与
    #   main.auto / main.color，能区分「真的重跑了」和「样式恰好没变」。
    # 5l 同会话 loadfile 换片，验证 end-file 清掉解码器级绝对覆盖、新文件黑边
    #   贴合关闭、sub-margin-y / sub-font-size 回到基线。
    ri_tracks = os.path.join(workdir, 'reinspect-tracks.mkv')
    ri_bars = os.path.join(workdir, 'reinspect-bars.mkv')
    ri_nobars = os.path.join(workdir, 'reinspect-nobars.mkv')
    mkvmod.build(ri_tracks, bars=0)
    mkvmod.build(ri_bars, bars=24)
    mkvmod.build(ri_nobars, bars=0)
    check('ri-fixtures-built',
          all(os.path.getsize(p) > 1024
              for p in (ri_tracks, ri_bars, ri_nobars)),
          '%d / %d / %d bytes' % tuple(os.path.getsize(p) for p in
                                       (ri_tracks, ri_bars, ri_nobars)))

    def run_reinspect(tag, mode, fixture, extra_args=()):
        # 残留 state / preset 会让自动预设与黑边判据从脏起点开始
        for p in (STATE_FILE, PRESET_FILE):
            if os.path.exists(p):
                os.remove(p)
        rlog = os.path.join(workdir, 'reinspect-' + tag + '-log.txt')
        rcmd = [MPV, '--script=' + PROBE_REINSPECT]
        rcmd += list(extra_args)
        rcmd += [
            '--vo=gpu', '--ao=null', '--pause=yes',
            '--image-display-duration=inf',
            '--watch-later-dir=' + watch_dir,
            '--save-position-on-quit=no', '--no-resume-playback',
            '--msg-level=all=info', fixture,
        ]
        renv = dict(env)
        renv['SUBSTYLE_REINSPECT_MODE'] = mode
        renv['SUBSTYLE_NOBARS_MKV'] = ri_nobars
        print('RUN(reinspect-%s):' % tag, ' '.join(rcmd))
        rproc = run_mpv(rcmd, env=renv,
                        stdout=open(rlog, 'w'), stderr=subprocess.STDOUT,
                        timeout=240)
        print('mpv(reinspect-%s) exit=%d' % (tag, rproc.returncode))
        return open(rlog, encoding='utf-8', errors='replace').read()

    reinspect_tracks_expected = (
        'ri-three-sub-tracks', 'ri-api-internal-tracks-field',
        'ri-colored-first-reinspected', 'ri-colored-first-applies-preset',
        'ri-api-current-track-is-external',
        'ri-switch-to-white-reinspected',
        'ri-switch-to-white-clears-auto-style',
        'ri-switch-back-colored-reinspected',
        'ri-switch-back-colored-reapplies',
        'ri-switch-to-internal-clears-auto-style',
        'ri-internal-back-to-colored-reinspected',
        'ri-internal-back-to-colored-reapplies',
    )
    # 「切到白字（保持原样）」用 report_shown 递增证明重新检测发生；v1.0.14
    # 默认静音后该 OSD 不再弹出，故本轮显式打开 show_keep_original，保持探针
    # 语义不变（默认静音由单测 T27d 守）。
    tracks_asserts('ri-switch-', run_reinspect(
        'tracks', 'tracks', ri_tracks,
        ('--sub-file=' + FIXTURE_COLORED, '--sub-file=' + FIXTURE_MAIN,
         '--script-opts=uosc_subtitle_style-show_keep_original=yes')),
        reinspect_tracks_expected)

    reinspect_files_expected = (
        'ri-end-file-clears-ass-overrides',
        'ri-first-barfit-active', 'ri-first-playres-written',
        'ri-second-barfit-cleared', 'ri-second-no-playres-shift',
        'ri-second-margin-restored', 'ri-second-fontsize-baseline',
        'ri-second-ratio-neutral',
    )
    tracks_asserts('ri-files-', run_reinspect('files', 'files', ri_bars),
                   reinspect_files_expected)

    # ---- 5m. v1.0.15：字幕不得越过画面边界（用户截图回归） ----
    # 截图里底部对白字形下半截被画面下边缘切掉。真机复现：修复前
    # pos=110 → BOT 只剩 5 行像素，pos=120 → 整条对白消失在视频外。
    # 判据刻意同时检查「盒高不缩水」与「y1 <= h-1」：被裁时 y1 卡在
    # 底边而盒高骤减，只看 y1 会漏判。
    bnd_fixtures = {}
    for kind, bars in (('bars', 24), ('nobars', 0)):
        p = os.path.join(workdir, 'bounds-' + kind + '.mkv')
        mkvmod.build(p, bars=bars, events=(
            '{\\pos(320,60)}TOPDIALOG',
            '{\\pos(320,338)}BOTTOMDIALOG',
        ))
        bnd_fixtures[kind] = p
    check('bnd-fixtures-built',
          all(os.path.getsize(p) > 1024 for p in bnd_fixtures.values()),
          ' / '.join('%s=%d' % (k, os.path.getsize(v))
                     for k, v in bnd_fixtures.items()))

    def run_bounds(kind):
        for p in (STATE_FILE, PRESET_FILE):
            if os.path.exists(p):
                os.remove(p)
        blog = os.path.join(workdir, 'bounds-' + kind + '-log.txt')
        bcmd = [
            MPV, '--script=' + PROBE_BOUNDS,
            '--vo=gpu', '--ao=null', '--pause=yes',
            '--image-display-duration=inf',
            '--watch-later-dir=' + watch_dir,
            '--save-position-on-quit=no', '--no-resume-playback',
            '--msg-level=all=info', bnd_fixtures[kind],
        ]
        benv = dict(env)
        benv['SUBSTYLE_BOUNDS_KIND'] = kind
        print('RUN(bounds-%s):' % kind, ' '.join(bcmd))
        bproc = run_mpv(bcmd, env=benv,
                        stdout=open(blog, 'w'), stderr=subprocess.STDOUT,
                        timeout=240)
        print('mpv(bounds-%s) exit=%d' % (kind, bproc.returncode))
        return open(blog, encoding='utf-8', errors='replace').read()

    bounds_expected = (
        'bnd-baseline-dialogue-in-frame', 'bnd-baseline-top-sign-visible',
        'bnd-ratio-clamped-at-limit', 'bnd-api-limit-exposed',
        'bnd-reset-clears-playres', 'bnd-reset-dialogue-in-frame',
    ) + tuple(
        'bnd-%s-%s' % (tag, suffix)
        for tag in ('pos110', 'nudge1', 'nudge2', 'pos150')
        for suffix in ('dialogue-not-clipped', 'playres-bounded',
                       'top-sign-visible')
    )
    for kind in ('bars', 'nobars'):
        btext = run_bounds(kind)
        rs = probe_of(btext)
        for name in bounds_expected:
            if name not in rs:
                check('bnd-%s-%s' % (kind, name), False, 'missing in log')
            else:
                check('bnd-%s-%s' % (kind, name), rs[name][0] == 'PASS',
                      rs[name][1][:150])
        sm = re.search(r'PROBE SUMMARY pass=(\d+) fail=(\d+)', btext)
        check('bnd-%s-summary-all-ok' % kind,
              bool(sm) and sm.group(2) == '0',
              sm.group(0) if sm else 'not found')
        es, ig = lua_errors(btext)
        check('bnd-%s-no-lua-errors' % kind, len(es) == 0,
              '; '.join(es[:2]) + (' | 已忽略第三方插件报错 %d 行' % ig if ig else ''))

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
