# uosc 脚本自更新（`scripts/uosc_updater.lua`）

定期检查两个脚本的 GitHub 上游，有新版就静默下载替换，**下次启动 mpv 生效**。
没有弹窗、没有确认框，也不需要你手动下载解压。

> 相关文件
> - `scripts/uosc_updater.lua` —— 驱动：配置、调度、OSD、手动命令
> - `script-modules/updater.lua` —— 共享逻辑：版本比较、下载、git 快进、原子替换
> - `script-opts/uosc_updater.conf` —— 配置项

---

## 1. 为什么是一个独立脚本，而不是写进两个脚本内部

这不是风格偏好，是三个硬约束推出来的：

1. **`scripts/uosc_staff_credits/` 是一个 git 工作副本**（自带 `.git`）。
   它的更新方式必然是 `git reset --hard`——如果把更新代码写进它内部，
   **第一次自动更新就会把自己的更新逻辑抹掉**。
2. 两个脚本形态不同（一个是单文件、一个是多文件仓库），但检查/校验/替换的规则一样，
   写两份必然发散。
3. **脚本自身出错时，外部驱动仍然能把它换掉**。若自更新逻辑在脚本内部，
   脚本一崩就再也没法靠它修复自己。

---

## 2. 管理的组件

两个仓库的**发布形态完全不同**，所以用两套更新策略，不能一招通吃。

| 组件 | 形态 | 上游仓库 | 版本来源 | 更新方式 |
| --- | --- | --- | --- | --- |
| `uosc_subtitle_style` | 单文件 `scripts/uosc_subtitle_style.lua` | `awujiana/uosc_subtitle_style` | Release 资产（`releases/latest` 的 `tag_name`） | 下载资产覆盖单文件 |
| `uosc_staff_credits` | 目录 `scripts/uosc_staff_credits/`（git 工作副本） | `awujiana/uosc-staff-credits` | `origin/main` 的提交号 | `git fetch` + 仅快进 |

---

## 3. 检查与更新流程

所有网络与子进程调用都走 `command_native_async`，**不阻塞播放线程**——
同步 `subprocess` 遇到网络抖动会把画面卡住好几秒。

### 3.1 单文件型（`uosc_subtitle_style`）

1. `GET {api_base}/repos/awujiana/uosc_subtitle_style/releases/latest`
   → 取 `tag_name` 与资产列表（`name` / `size` / `browser_download_url`）。
2. **快速路径**：状态文件里记录的 `tag` 与远端一致、记录的 `size` 与本地文件尺寸一致
   → 判定「已最新」，**不下载那 100 KB**。
3. 下载资产到同目录 `<target>.new`（`curl -fsSL`，`-f` 保证 4xx/5xx 直接失败，
   不会把错误页写成文件）。
4. **校验**：尺寸与 Release 声明一致、不小于 512 字节、开头是 `--`（Lua 注释）。
5. **逐字节比对**：与本地文件相同 → 只补状态、不写盘。
6. **替换**：旧文件改名成临时中转名 → 新文件 rename 就位 → **成功后立刻删中转文件**。

### 3.2 git 型（`uosc_staff_credits`）

1. `git -C <dir> rev-parse --is-inside-work-tree` —— 不是仓库（或 git 不可用）则报错退出。
2. `git -C <dir> status --porcelain` —— **工作区有未提交改动就跳过**，绝不动你的改动。
3. `git -C <dir> fetch --quiet origin main`。
4. `rev-parse HEAD` 与 `rev-parse FETCH_HEAD` 相同 → 已最新。
5. `git merge-base --is-ancestor HEAD FETCH_HEAD` —— **不成立（本地有额外提交）就跳过**。
6. 通过才 `git reset --hard FETCH_HEAD`。

> 这里只做**快进**，不做强制对齐。所以即使你在这个目录里开发、有未推送的提交，
> 自动更新也不会把它们冲掉——最多是「跳过」并在日志里说明原因。
>
> 该目录以 **git submodule** 形式纳入整合包（见 `.gitmodules`）。子模块内部仍是完整的
> git 工作副本，所以 `git -C <dir>` 的 fetch / 比对 / reset 全部照常工作；唯一的区别是：
> 自更新把子模块推进到新提交后，**父仓库会显示 `modified: scripts/uosc_staff_credits (new commits)`**。
> 这是正常现象，但需要在父仓库里 `git add scripts/uosc_staff_credits` 并提交一次，
> 把父仓库记录的指向更新掉——否则别人（或你自己）执行 `git submodule update`
> 时会被拉回旧提交。

---

## 4. 安全设计

| 风险 | 措施 |
| --- | --- |
| 网络返回错误页 / 半截文件 | `curl -f` + 尺寸校验 + Lua 头校验 + 逐字节比对 |
| 替换过程中文件被占用 | 先写 `.new`，中转名 rename；失败自动回滚，原文件完好 |
| 目录里留垃圾 | **不保留 `.bak`**；`.new` 与中转文件在成功/失败路径都会清掉 |
| 破坏用户对 git 工作副本的改动 | 脏工作区跳过；非快进跳过；只做 FF |
| 反复拉大文件 | 状态文件记录 `tag`+`size`，命中快速路径直接跳过下载 |
| 无界重试 / 卡死 | 单次 `--max-time 30`；同一时刻只允许一轮检查（`busy` 互斥） |
| 启动时抢占资源 | 默认启动后 30 秒才首查，避开开播高峰 |

---

## 5. 生效时机（必须知道的边界）

**更新只落盘，下次启动 mpv 生效。**

mpv 没有卸载或热重载脚本的能力——`load-script` 只能**追加**，不能替换；
强行加载第二份会造成同名 `script-message` 重复注册（后注册覆盖前者）与双份属性观察器。
所以本脚本不会在运行时替换自己，也不会假装能做到。

---

## 6. 配置（`script-opts/uosc_updater.conf`）

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `enabled` | `yes` | 总开关；`no` 时连手动命令也失效 |
| `startup_delay` | `30` | 启动后多少秒开始首查 |
| `interval_hours` | `6` | 周期检查间隔；`0` = 只在启动时查一次 |
| `notify` | `yes` | 真正安装更新后弹一条 OSD；检查结果只写日志 |
| `update_subtitle_style` | `yes` | 是否管理 `uosc_subtitle_style` |
| `update_staff_credits` | `yes` | 是否管理 `uosc_staff_credits` |
| `git_path` | `git` | git 可执行文件；不在 PATH 就填绝对路径 |
| `api_base` | `https://api.github.com` | GitHub API 根地址，可指向自建/镜像的兼容 API |

> mpv 的 conf **不支持行尾注释**：`key=value  # 注释` 会把「值 + 注释」整段当值，
> 布尔/数值项会报 `error converting value` 并回落默认值。注释必须独立成行。

**读取方式用 `mp.options.read_options`，不要用 `mp.get_opt`。**
本机实测（mpv v0.41 winbuild）`mp.get_opt` 对 `script-opts/<name>.conf` 里的键
**一律返回 nil**（顶层 `scripts/*.lua` 与 `scripts/<dir>/main.lua` 两种形态都试过），
而 `read_options` 会自己去打开 conf 文件，取值正常。

---

## 7. 手动命令

```bash
# 立即检查（不等周期）
mpv --script-message=uosc-updater-check

# 或在播放中通过 input.conf / 控制台触发
script-message uosc-updater-check
script-message uosc-updater-status
```

- `uosc-updater-check`：立刻跑一轮检查，结束后用 OSD 汇总每个组件的结果。
- `uosc-updater-status`：显示上次检查时间与两个组件记录的版本，不发起网络请求。

---

## 8. 状态与缓存文件

| 文件 | 内容 | 说明 |
| --- | --- | --- |
| `~~/uosc-updater-state.json` | 各组件 `tag`/`size`/`checked_at`/`updated_at` | 快速路径依据；删掉只会导致下一轮多下载一次 |
| `~~/uosc-updater-remote.json` | 最近一次 GitHub API 响应 | 排查用缓存，可随时删 |

两者都是运行时产物，已在 `.gitignore` 中排除。

---

## 9. 故障排查

| 症状 | 原因 / 处理 |
| --- | --- |
| 一直没动静 | `enabled=no`、或该组件开关为 `no`、或还没到 `startup_delay`。看日志里的 `uosc_updater:` 行 |
| 日志报「不是 git 工作副本或 git 不可用」 | git 不在 PATH，或 `scripts/uosc_staff_credits/` 被删掉了 `.git`；改 `git_path` 或重新 clone |
| 日志报「工作区有未提交改动，跳过」 | 该目录里有你未提交的修改；提交/丢弃后再等下一轮 |
| 日志报「本地有额外提交（非快进），跳过」 | 你有未推送的提交；这是保护行为，不是故障 |
| 日志报「下载失败」「尺寸不符」 | 网络问题或 GitHub 返回了异常内容；已被拒绝，原文件未动，下一轮会重试 |
| 更新成功但要重启才生效 | 设计如此，见第 5 节 |
| 改过脚本后被换回官方版本 | 自动更新会覆盖本地修改；要保留就把对应 `update_*` 设为 `no` |

---

## 10. 测试体系

```bash
# 单测（stub mp + 虚拟文件系统 + 假 curl/git）：39 条断言
../luajit.exe tools/updater-test.lua

# 真机 E2E：隔离 --config-dir + 本地 HTTP 假 API + 本地 bare 仓库，14 条断言
/c/Python314/python.exe tools/updater-e2e.py

# 变异测试：7 个变异必须全部被断言抓住（证明用例有牙）
/c/Python314/python.exe tools/updater-mutation-test.py
```

E2E 跑**两轮**：第一轮验证真的更新（文件被替换、git 被快进、状态被记录），
第二轮验证**快速路径生效**（不再请求资产、不重复更新、文件不变）。

变异覆盖的七个点：git 脏检查、非快进保护、资产尺寸校验、Lua 头校验、
内容相同判定、状态快速路径、中转文件清理。
