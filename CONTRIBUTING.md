<div align="center">

<p align="center">
  <a href="LICENSE"><img alt="协议 AGPL-3.0" src="https://img.shields.io/badge/协议-AGPL--3.0-blue?style=flat"></a>
  <a href="CONTRIBUTING.md"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat"></a>
  <a href="https://github.com/awujiana"><img alt="AI辅助生成 是" src="https://img.shields.io/badge/AI辅助生成-是-orange?style=flat"></a>
</p>

<h1>贡献指南</h1>

<strong>欢迎参与「冰山 MPV 配置」的共建</strong>

</div>

---

> [!WARNING]
> 本项目的相当一部分代码由 AI 辅助生成，并经过持续的人工作业、联调和重构，但它仍然可能存在遗漏、边界情况处理不足或行为与预期不完全一致的问题。如果你在使用过程中发现 Bug、兼容性问题、异常行为或文档缺失，欢迎积极提交 Issue。最好附上复现步骤、日志、截图和系统版本信息，这会非常有帮助。

感谢你关注 **mpv-bingshan** 并愿意贡献。本指南用于确保协作顺畅、门禁有效、许可证统一。

> 维护者：awujian ｜ 开源协议：AGPL-3.0（第三方脚本与着色器保留各自协议，见 `LICENSE.MD`）

## 📚 目录

- [我能如何参与](#-我能如何参与)
- [提交 Issue 前](#-提交-issue-前)
- [提交 Pull Request 前](#-提交-pull-request-前)
- [命名规范（不缩写）](#-命名规范不缩写)
- [代码与文档约定](#-代码与文档约定)
- [行为准则](#-行为准则)
- [许可证](#-许可证)

## 🤝 我能如何参与

- **提交 Issue**：反馈字幕样式、黑边贴合、自更新、菜单交互的异常与兼容性问题。
- **改进脚本**：`scripts/uosc_subtitle_style.lua`、`scripts/uosc_updater.lua` 与两个 submodule 脚本。
- **补充测试**：`tools/sub-style-test.lua` 单测、`tools/sub-style-e2e.py` 真机 E2E、变异测试，以及配套夹具。
- **完善文档**：README、`docs/`、`docs/script-repositories.md`（脚本仓库索引）与 `script-opts/*.conf` 注释。

## 🐞 提交 Issue 前

1. 先搜索确认问题未被重复提出，并**完全退出并重启 mpv**（脚本更新落盘后需重启才生效）。
2. 说明场景：mpv 版本、操作系统、uosc 版本、视频 / 字幕类型（内封 ASS / 外挂 SRT / PGS）、是否带 `\pos`、是否有内嵌黑边。
3. 附 `--msg-level=all=info` 日志、左上角样式检测报告截图、复现步骤。
4. 涉及样式的，附 `script-opts/uosc_subtitle_style.conf` 中的相关配置值。

## 🔀 提交 Pull Request 前

1. 从 `main` 切出特性分支，命名如 `fix/pos-subtitle-scale` 或 `feat/bar-fit`。
2. **全套门禁必须通过**（在 `portable_config/` 下执行）：

   ```bash
   ../luajit.exe tools/lua-syntax-check.lua
   ../luajit.exe tools/sub-style-test.lua                    # 446 条断言
   python tools/sub-style-conf-verify.py                     # conf 静态门禁
   /c/Python314/python.exe tools/sub-style-e2e.py            # 真机 E2E
   ../luajit.exe tools/updater-test.lua                      # 72 条断言
   /c/Python314/python.exe tools/updater-e2e.py
   /c/Python314/python.exe tools/updater-mutation-test.py    # ALL_KILLED
   python scripts/update_badges.py --check
   ```

   无 mpv / 无 Lua 解释器时脚本会明确打印 `SKIP`；**不得把 `SKIP` 当作通过**，也不得删减断言凑绿。E2E 视觉判据依赖 Pillow，请用系统 Python。
3. **改 `scripts/uosc_subtitle_style.lua` 必须同步递增文件头 `-- @version:`**，否则自更新器会把它判成同版本或旧版本；同时新增对应单测与真机断言。
4. **改 `script-opts/*.conf` 必须跑 `sub-style-conf-verify.py`**：mpv conf **不支持行尾注释**，注释一律独立成行；键集合必须与脚本 `o` 表一致。
5. 改 README 需遵循 `awujiana-readme-style`：徽章由 `scripts/update_badges.py` 生成、`<p align="center">` 纯 HTML 居中、双名标题、AI `[!WARNING]`、底部三节齐全；**脚本仓库链接一律写进 `docs/script-repositories.md` 的表格**，不要散落在 README。
6. 涉及发布副本时，用 `tools/publish-mpv-bingshan.py verify` 确认无排除项、无 gitlink、两个 submodule 路径已有实体文件。
7. 命名一律全拼、禁止缩写、名称不重复（见下文）。提交信息清晰说明「做了什么 / 为什么」。

## 📝 命名规范（不缩写）

> 本节为**硬性命名规范**，完整对照表与反例见技能 `awujiana-readme-style` 的 `references/naming-conventions.md`。

### 总则

- **一律全拼，禁止缩写**：`usr`→`user`、`cfg`→`config`、`btn`→`button`、`img`→`image`、`msg`→`message`、`err`→`error`、`idx`→`index`、`tmp`→`temporary`。
- **名称不重复**：项目名全局唯一；同目录文件名唯一（大小写不敏感）；同模块导出名唯一；组件名全局唯一。
- **名称即语义**：禁止 `utils`、`common`、`misc`、`temp`、`data1`、`file2` 等泛化名。
- **同一项目内形态统一**：mpv Lua 脚本沿用 `snake_case.lua`，测试工具沿用 `<对象>-<用途>.<ext>`，不混用风格。

### 项目（仓库）命名

- `kebab-case`，全小写，2–5 个单词；同一账号下不得重名。
- 禁止含版本号、日期、作者名，以及 `test` / `demo` / `untitled` 等无信息量名称。

### 文件命名

| 类型 | 规则 | 本仓库示例 |
| --- | --- | --- |
| 文档 | `kebab-case.md` | `script-repositories.md`、`api-uosc-subtitle-style.md` |
| mpv 脚本 | `snake_case.lua` | `uosc_subtitle_style.lua`、`uosc_updater.lua` |
| 测试 | `<对象>-test.lua` / `<对象>-e2e.py` / `<对象>-probe-*.lua` | `sub-style-test.lua`、`sub-style-probe-api.lua` |
| 夹具 | `<对象>-smoke-*.ass` / `<对象>-fixture.py` | `sub-style-mkv-fixture.py` |
| 配置 | `snake_case.conf` / `badges.config.json` | `uosc_subtitle_style.conf` |
| 常量 | `UPPER_SNAKE_CASE` | `API_VERSION`、`MANAGED_OVERRIDE_KEYS` |

- 同一目录内不得出现同名文件（含仅大小写不同）。
- 冲突时加**语义限定词**而不是数字后缀：`probe2.lua` ❌ → `probe-fontsize.lua` ✅。

### 函数与符号命名

- Lua 局部函数 `snake_case` 且动词开头：`detect_bars()`、`compute_barfit()`、`ass_fontsize_override()`、`publish_api_state()`。
- `script-message` 入口一律 `kebab-case` 且全拼：`letterbox-refresh`、`size-step`、`ass-fontsize-toggle`。
- `user-data` 键与 `script-message` 目标名全局唯一：`uosc_subtitle_style` / `uosc_staff_credits`。
- 对外 API 的 `action` 名用 `kebab-case`：`get-state`、`list-actions`、`call`。

### 门禁

- 提交前 `lua-syntax-check.lua` 必须 `FAIL 0`，`sub-style-test.lua` 必须 `fail=0 ALL_OK`。
- `sub-style-e2e.py` 中第三方 submodule 的无关 Lua error 只按标签隔离，**不得**放宽被测脚本与探针自身的报错判据。

## 📋 代码与文档约定

- 正文以简体中文为主，专有名词保留英文原文；对比 / 参数类信息优先用表格。
- **版本标记是硬约定**：改脚本功能必须同步递增文件头**行首独立成行**的 `-- @version: X.Y.Z`；状态文件里的 `tag` 只代表「上次从远端装了什么」，永远不能当本地版本。
- **绝不轻易重建解码器**：位置 / 缩放走属性即时生效；字体 / 字号 / 描边在已是 `force` 时只写属性 + 一次 OSD 微扰；只有进出 `force` 才允许重建一次。历史上重建会让内封字幕「定住一句不跳」。
- **带 `\pos` 的 explicit ASS** 对 `sub-pos` / `sub-scale` / `sub-font-size` 全部豁免；改样式必须写 `sub-ass-style-overrides`（ASS 颜色 `&H00BBGGRR`，BGR 倒序），缩放 / 字号写 `Fontsize`；`ScaleX/ScaleY` 在 125%/150% 会让字幕消失，禁止使用。
- `sub-margin-y` 是 **INT 属性**且全局共享，不在 `reset-on-next-file` 列表里，贴合结束必须显式还原基准值。
- `user-data` 是 mpv **node 属性**：读取必须 `get_property_native()` / `observe_property(..., 'native')`。
- `script-message-to` 参数含 `#RRGGBB` 必须加引号，否则 mpv 命令解析会把裸 `#` 当注释起始符。
- **对外 API 只读 + 白名单转发**：不得新增属性写入路径，`api` 自身不得进入 `call` 白名单（防递归）；职员表快照不得输出 token / 原始响应 / 缓存正文。
- **conf 不支持行尾注释**；配置读取用 `mp.options.read_options`。
- **发布副本排除清单**：`.workbuddy-ai` / Git 元数据 / 视频 / `.gitattributes` / `.gitignore` / `.gitmodules` / `danmaku-search-history` / 日志 / 运行时 json 一律不进 `main` 发布树；两个 submodule 必须展开成实体文件（不能有 gitlink）。
- **徽章不要手改**：改 `scripts/badges.config.json` 后运行 `python scripts/update_badges.py`，提交前 `--check` 必须通过。
- **文档索引只列操作文档**；测试文件默认只在 README「测试与门禁」节一句话带过。所有脚本仓库链接集中在 `docs/script-repositories.md` 表格。
- 每次改动同步 `CHANGELOG.md`（Keep a Changelog，语义化版本）。

## 🤗 行为准则

请保持友善、专业、就事论事。尊重不同经验水平的贡献者，对规范分歧以讨论达成共识，不人身攻击、不贬低他人工作。上游脚本作者归属以源码为准，不得把他人作品改记为本仓库作者。

## 📄 许可证

向本仓库提交贡献，即表示你同意以仓库 `LICENSE` 所载协议（AGPL-3.0）发布你的贡献，并确认你拥有相应授权。第三方脚本与着色器保留各自原有协议，见 [`LICENSE.MD`](LICENSE.MD)。

[![AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
