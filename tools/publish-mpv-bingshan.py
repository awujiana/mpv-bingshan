#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 `awujiana/mpv-bingshan` 的开箱即用发布副本。

生产工作区 `portable_config` 里混有开发态文件（git 元数据、WorkBuddy 私有数据、
视频、运行时 json、日志），且 `scripts/uosc_danmaku` / `scripts/uosc_staff_credits`
是两个 gitlink —— 下载 zip 的人只会拿到空目录。本工具做两件事：

  export <目标目录>   按排除清单导出一份纯文件副本（gitlink 展开成实体文件）
  index               把当前 git 索引改写成「发布树」：删排除项、gitlink 换成实体文件
  verify              校验索引已是发布树（无排除项、无 gitlink、两个脚本目录非空）

排除清单（用户指定，见 README《脚本公开仓库》一节）：
  .workbuddy-ai/、Git 元数据(.gitattributes/.gitignore/.gitmodules/.git)、
  视频文件、danmaku-search-history*、日志文件、运行时 json。

典型流程（在 portable_config 根目录）：
  git add -A && git commit -m "..."           # 先提交开发改动，保留完整 dev 历史
  python tools/publish-mpv-bingshan.py export /path/to/mpv-Bingshan
  python tools/publish-mpv-bingshan.py index
  python tools/publish-mpv-bingshan.py verify
  git commit -m "chore(release): ..." && git push origin main

所有文件内容直接从 git object DB 读取（而不是拷工作区），因此导出结果与提交到
仓库的 blob **字节一致**，不会被 Windows CRLF 污染（mpv 配置要求 UTF-8 + LF）。
"""

from __future__ import annotations

import os
import posixpath
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 仓库相对路径（posix）的前缀/文件名排除项
EXCLUDE_EXACT = {
    ".gitattributes", ".gitignore", ".gitmodules",
}
EXCLUDE_PREFIX = (
    ".git/", ".workbuddy-ai/", "log/", "logs/",
)
EXCLUDE_BASENAME = {
    ".gitattributes", ".gitignore", ".gitmodules",
    ".git", ".gitmodules",
}
EXCLUDE_SUFFIX = (
    ".log",
    ".mkv", ".mp4", ".avi", ".mov", ".m2ts", ".ts", ".webm", ".flv",
    ".wmv", ".rmvb", ".iso", ".mka", ".mks", ".ass.bak",
)
# 运行时状态/缓存（mpv 启动后生成，不应进发布包）
RUNTIME_JSON = {
    "danmaku-search-history.json",
    "uosc-updater-state.json", "uosc-updater-remote.json",
    "uosc-subtitle-style-state.json", "uosc-subtitle-style-fonts.json",
    "uosc-subtitle-style-preset.json",
    "staff-credits-runtime-config.json", "staff-credits-data-cache.json",
    "staff-credits-history.json", "recent.json",
}
SUBMODULES = ("scripts/uosc_danmaku", "scripts/uosc_staff_credits")


def git(args, cwd=ROOT, data=None):
    p = subprocess.run(["git"] + list(args), cwd=cwd, input=data,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (
            " ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout


def excluded(rel: str) -> bool:
    """rel 为 posix 风格仓库相对路径。"""
    rel = rel.replace("\\", "/").lstrip("/")
    if rel.startswith("./"):
        rel = rel[2:]
    if not rel:
        return True
    parts = rel.split("/")
    base = parts[-1]
    if rel in EXCLUDE_EXACT or base in EXCLUDE_BASENAME:
        return True
    if any(p == ".git" or p == ".workbuddy-ai" or p == ".workbuddy"
           for p in parts[:-1]):
        return True
    for pre in EXCLUDE_PREFIX:
        if rel.startswith(pre):
            return True
    if base.startswith("danmaku-search-history"):
        return True
    if base in RUNTIME_JSON:
        return True
    if base.lower().endswith(EXCLUDE_SUFFIX):
        return True
    return False


def index_entries(repo=ROOT):
    """[(mode, sha, stage, path)]；-z 保证中文/空格路径安全。"""
    raw = git(["ls-files", "-s", "-z"], cwd=repo)
    out = []
    for rec in raw.split(b"\0"):
        if not rec:
            continue
        meta, _, path = rec.partition(b"\t")
        fields = meta.decode("ascii").split()
        if len(fields) < 3:
            continue
        out.append((fields[0], fields[1], fields[2],
                    path.decode("utf-8", "surrogateescape")))
    return out


def normalized_path(p: str) -> str:
    return p.replace("\\", "/")


def blob(repo: str, sha: str) -> bytes:
    return git(["cat-file", "blob", sha], cwd=repo)


def collect():
    """返回 (常规文件列表[(mode, sha, rel, repo)], gitlink 路径列表)。"""
    regular, links = [], []
    for mode, sha, _stage, path in index_entries():
        rel = normalized_path(path)
        if mode == "160000":
            links.append(rel)
            continue
        if excluded(rel):
            continue
        regular.append((mode, sha, rel, ROOT))
    for link in links:
        sub = os.path.join(ROOT, *link.split("/"))
        for mode, sha, _stage, path in index_entries(sub):
            rel = normalized_path(path)
            if mode == "160000" or excluded(rel) or excluded(link + "/" + rel):
                continue
            regular.append((mode, sha, link + "/" + rel, sub))
    return regular, links


def cmd_export(target: str):
    regular, links = collect()
    target = os.path.abspath(target)
    os.makedirs(target, exist_ok=True)
    for mode, sha, rel, repo in regular:
        dst = os.path.join(target, *rel.split("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = blob(repo, sha)
        with open(dst, "wb") as f:
            f.write(data)
        if mode == "100755":
            os.chmod(dst, 0o755)
    print("EXPORT target=%s files=%d submodules=%s"
          % (target, len(regular), ",".join(links)))
    return 0


def cmd_index():
    regular, links = collect()
    # 1) 从索引移除排除项与 gitlink
    removals = [normalized_path(p) for _m, _s, _st, p in index_entries()
                if _m == "160000" or excluded(normalized_path(p))]
    for rel in removals:
        git(["update-index", "--force-remove", "--", rel])
    # 2) 把 submodule 的 blob 写入父仓库 object DB，再以实体文件加入索引
    #    （用 --cacheinfo 绕开嵌套 .git 目录，git 不会把它们重新识别成 gitlink）
    added = 0
    for mode, sha, rel, repo in regular:
        if repo == ROOT:
            continue
        data = blob(repo, sha)
        new_sha = git(["hash-object", "-w", "--stdin"], data=data).decode().strip()
        git(["update-index", "--add", "--cacheinfo",
             "%s,%s,%s" % (mode, new_sha, rel)])
        added += 1
    print("INDEX removed=%d（排除项 %d + gitlink %d） added_submodule_files=%d"
          % (len(removals), len(removals) - len(links), len(links), added))
    return 0


def cmd_verify():
    bad, links, subfiles = [], [], {k: 0 for k in SUBMODULES}
    for mode, _sha, _stage, path in index_entries():
        rel = normalized_path(path)
        if mode == "160000":
            links.append(rel)
        if excluded(rel):
            bad.append(rel)
        for sub in SUBMODULES:
            if rel.startswith(sub + "/"):
                subfiles[sub] += 1
    print("VERIFY excluded_in_index=%d gitlinks=%d sub_files=%s"
          % (len(bad), len(links), subfiles))
    if bad:
        print("  excluded paths: " + ", ".join(bad[:20]))
    if links:
        print("  gitlinks: " + ", ".join(links))
    ok = not bad and not links and all(v > 0 for v in subfiles.values())
    print("VERIFY %s" % ("OK" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("export", "index", "verify"):
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "export":
        if len(sys.argv) != 3:
            print("usage: publish-mpv-bingshan.py export <target-dir>")
            return 2
        return cmd_export(sys.argv[2])
    if cmd == "index":
        return cmd_index()
    return cmd_verify()


if __name__ == "__main__":
    sys.exit(main())
