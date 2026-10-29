#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""updater-e2e.py —— uosc_updater 的真机端到端测试

思路：造一个**隔离的临时 config 目录**（--config-dir），里面只放被测脚本，
让更新器面对真实环境：
  * 真实 curl 进程访问本地 HTTP 服务（假 GitHub API + 假 Release 资产）
  * 真实 git 进程访问本地 bare 仓库（假远程，离线可跑）
  * 真实文件替换（.new 暂存 → .bak 备份 → 覆盖）

断言（都是"错了会毁用户文件"的点）：
  1. 单文件组件被替换成新内容，旧内容进 .bak
  2. git 组件被快进到远程 HEAD
  3. 状态文件记录了两边的版本
  4. 日志无 Lua error / traceback
  5. **第二轮不再下载资产**（快速路径生效）且不再重复更新

用法（在 portable_config/ 下）：
  /c/Python314/python.exe tools/updater-e2e.py
判据：exit code 0 且最后一行 SUMMARY ... PASS fail=0
"""

import http.server
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MPV = os.path.join(os.path.dirname(ROOT), 'mpv.exe')

pass_count = 0
fail_count = 0


def check(name, ok, detail=''):
    global pass_count, fail_count
    if ok:
        pass_count += 1
        print('PASS %s%s' % (name, (' | ' + str(detail)) if detail else ''))
    else:
        fail_count += 1
        print('FAIL %s%s' % (name, (' | ' + str(detail)) if detail else ''))


def run(cmd, cwd=None, check_rc=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       encoding='utf-8', errors='replace')
    if check_rc and r.returncode != 0:
        raise RuntimeError('cmd failed (%d): %s\n%s\n%s'
                           % (r.returncode, ' '.join(cmd), r.stdout, r.stderr))
    return r


def lua_body(tag, pad_lines=80):
    return ('-- fake script %s\n' % tag) + ('-- padding line for size\n' * pad_lines)


# ------------------------------------------------------------------ 假 HTTP 服务

class Handler(http.server.SimpleHTTPRequestHandler):
    hits = []

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        Handler.hits.append(self.path)
        return super().do_GET()


def start_server(directory):
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()

    handler = lambda *a, **kw: Handler(*a, directory=directory, **kw)
    httpd = http.server.ThreadingHTTPServer(('127.0.0.1', port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, port


# ------------------------------------------------------------------ 场景搭建

def build_scenario(work):
    """返回 (tmp_config, srv_dir, old_body, new_body, git_expect_head)"""
    tmp = os.path.join(work, 'config')
    srv = os.path.join(work, 'srv')
    for d in (os.path.join(tmp, 'scripts'), os.path.join(tmp, 'script-modules'),
              os.path.join(tmp, 'script-opts'),
              os.path.join(srv, 'repos', 'awujiana', 'uosc_subtitle_style', 'releases')):
        os.makedirs(d, exist_ok=True)

    # 被测脚本
    shutil.copy(os.path.join(ROOT, 'scripts', 'uosc_updater.lua'),
                os.path.join(tmp, 'scripts', 'uosc_updater.lua'))
    shutil.copy(os.path.join(ROOT, 'script-modules', 'updater.lua'),
                os.path.join(tmp, 'script-modules', 'updater.lua'))

    # 探针：10 秒后自己退出（让更新循环有时间跑完）
    with open(os.path.join(tmp, 'scripts', 'zz_probe.lua'), 'w', encoding='utf-8') as f:
        f.write("local mp = require 'mp'\n"
                "local n = 0\n"
                "mp.add_periodic_timer(0.5, function()\n"
                "  n = n + 1\n"
                "  if n >= 20 then mp.command('quit') end\n"
                "end)\n")

    # 单文件组件的"旧版本"：纯注释，mpv 会当无害脚本加载
    old_body = lua_body('v0.0.1-old')
    with open(os.path.join(tmp, 'scripts', 'uosc_subtitle_style.lua'), 'w',
              encoding='utf-8', newline='\n') as f:
        f.write(old_body)

    # 假 Release 资产（新版本）
    new_body = lua_body('v9.9.9-new', pad_lines=100)
    with open(os.path.join(srv, 'uosc_subtitle_style.lua'), 'w',
              encoding='utf-8', newline='\n') as f:
        f.write(new_body)

    # ---------------- 假 git 远程 ----------------
    bare = os.path.join(work, 'bare.git')
    seed = os.path.join(work, 'seed')
    os.makedirs(seed, exist_ok=True)
    run(['git', 'init', '--bare', bare])
    run(['git', 'symbolic-ref', 'HEAD', 'refs/heads/main'], cwd=bare)
    run(['git', 'init', seed])
    run(['git', 'symbolic-ref', 'HEAD', 'refs/heads/main'], cwd=seed)
    with open(os.path.join(seed, 'main.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- fake staff credits stub v1\n')
    run(['git', 'add', '.'], cwd=seed)
    run(['git', '-c', 'user.name=e2e', '-c', 'user.email=e2e@example.test',
         'commit', '-m', 'init'], cwd=seed)
    run(['git', 'remote', 'add', 'origin', bare], cwd=seed)
    run(['git', 'push', '-u', 'origin', 'main'], cwd=seed)

    # 本地工作副本（= 被测的 git 组件）
    clone = os.path.join(tmp, 'scripts', 'uosc_staff_credits')
    run(['git', 'clone', bare, clone])
    run(['git', 'checkout', 'main'], cwd=clone, check_rc=False)

    # 远程再前进一个提交 ⇒ 工作副本落后，更新器应当快进
    with open(os.path.join(seed, 'main.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- fake staff credits stub v2 (upstream ahead)\n')
    run(['git', 'add', '.'], cwd=seed)
    run(['git', '-c', 'user.name=e2e', '-c', 'user.email=e2e@example.test',
         'commit', '-m', 'upstream ahead'], cwd=seed)
    run(['git', 'push', 'origin', 'main'], cwd=seed)
    expect_head = run(['git', 'rev-parse', 'HEAD'], cwd=seed).stdout.strip()

    return tmp, srv, old_body, new_body, expect_head


def write_release_json(srv, port, new_body):
    payload = {
        'tag_name': 'v9.9.9',
        'assets': [{
            'name': 'uosc_subtitle_style.lua',
            'size': len(new_body.encode('utf-8')),
            'browser_download_url': 'http://127.0.0.1:%d/uosc_subtitle_style.lua' % port,
        }],
    }
    path = os.path.join(srv, 'repos', 'awujiana', 'uosc_subtitle_style',
                        'releases', 'latest')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(payload, f)


def write_conf(tmp, port):
    lines = [
        '# E2E 生成，勿手工维护',
        'enabled=yes',
        'startup_delay=1',
        'interval_hours=0',
        'notify=yes',
        'update_subtitle_style=yes',
        'update_staff_credits=yes',
        'git_path=git',
        'api_base=http://127.0.0.1:%d' % port,
    ]
    with open(os.path.join(tmp, 'script-opts', 'uosc_updater.conf'), 'w',
              encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def run_mpv(tmp, log_path):
    cmd = [MPV, '--config-dir=' + tmp, '--idle=yes', '--force-window=no',
           '--vo=null', '--ao=null', '--msg-level=all=info',
           '--no-input-default-bindings', '--no-input-terminal']
    with open(log_path, 'w', encoding='utf-8', errors='replace') as log:
        r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    return r.returncode


def read(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            return f.read()
    except FileNotFoundError:
        return None


def main():
    if not os.path.exists(MPV):
        print('SKIP 找不到 mpv.exe: %s' % MPV)
        return 0

    work = tempfile.mkdtemp(prefix='updater-e2e-')
    keep = os.environ.get('UPDATER_E2E_KEEP') == '1'
    if keep:
        print('工作目录（保留）：' + work)
    try:
        tmp, srv, old_body, new_body, expect_head = build_scenario(work)
        httpd, port = start_server(srv)
        write_release_json(srv, port, new_body)
        write_conf(tmp, port)

        # ---------------- 第一轮：应当全部更新 ----------------
        Handler.hits = []
        log1 = os.path.join(work, 'mpv1.log')
        run_mpv(tmp, log1)

        target = os.path.join(tmp, 'scripts', 'uosc_subtitle_style.lua')
        bak = target + '.bak'
        state_path = os.path.join(tmp, 'uosc-updater-state.json')

        check('run1-script-replaced', read(target) == new_body,
              'size=%s' % (len(read(target) or '')))
        check('run1-no-bak-left', not os.path.exists(bak), '不保留 .bak 备份')
        check('run1-no-tmp-left',
              not os.path.exists(target + '.tmpbak') and not os.path.exists(target + '.new'),
              '中转/暂存文件必须清干净')
        check('run1-no-staging-left', not os.path.exists(target + '.new'))

        head_now = run(['git', 'rev-parse', 'HEAD'],
                       cwd=os.path.join(tmp, 'scripts', 'uosc_staff_credits')).stdout.strip()
        check('run1-git-fast-forwarded', head_now == expect_head,
              'now=%s expect=%s' % (head_now[:8], expect_head[:8]))

        state = json.loads(read(state_path) or '{}')
        comps = state.get('components', {})
        check('run1-state-subtitle', comps.get('uosc_subtitle_style', {}).get('tag') == 'v9.9.9',
              comps.get('uosc_subtitle_style'))
        check('run1-state-git', comps.get('uosc_staff_credits', {}).get('tag') == expect_head[:7],
              comps.get('uosc_staff_credits'))

        logtext1 = read(log1) or ''
        bad = [kw for kw in ('Lua error', 'traceback', 'attempt to call') if kw in logtext1]
        check('run1-no-lua-error', not bad, bad)
        check('run1-logged-update', '已更新' in logtext1,
              [ln for ln in logtext1.splitlines() if 'uosc_updater' in ln][:3])

        # ---------------- 第二轮：不应再下载、不应再更新 ----------------
        Handler.hits = []
        log2 = os.path.join(work, 'mpv2.log')
        run_mpv(tmp, log2)

        asset_hits = [h for h in Handler.hits if h.endswith('uosc_subtitle_style.lua')]
        api_hits = [h for h in Handler.hits if h.endswith('/releases/latest')]
        check('run2-no-asset-download', len(asset_hits) == 0,
              '资产请求=%d（快速路径应命中）' % len(asset_hits))
        check('run2-api-still-queried', len(api_hits) >= 1,
              'API 请求=%d（仍需确认远端 tag 未变）' % len(api_hits))

        logtext2 = read(log2) or ''
        check('run2-no-repeat-update', '已更新' not in logtext2,
              [ln for ln in logtext2.splitlines() if 'uosc_updater' in ln][:3])
        check('run2-file-unchanged', read(target) == new_body)
        bad2 = [kw for kw in ('Lua error', 'traceback', 'attempt to call') if kw in logtext2]
        check('run2-no-lua-error', not bad2, bad2)

        httpd.shutdown()
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)

    print('\nSUMMARY updater-e2e %s fail=%d'
          % ('PASS' if fail_count == 0 else 'FAIL', fail_count))
    return 0 if fail_count == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
