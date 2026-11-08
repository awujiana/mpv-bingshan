# 更新日志

本文件记录 `uosc 弹幕`（uosc_danmaku，awujiana fork）的重要变更，版本号遵循语义化版本 `MAJOR.MINOR.PATCH`。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [未发布]

### 新增

- 新增 awujiana 风格 `CONTRIBUTING.md`、`AGENTS.md`、`CHANGELOG.md`。
- README 增加「🏷 关联标签」节、双名标题与底部三节，并补充 fork 说明。

### 改进

- 统一 README 的徽章、双名标题与关联标签风格。

## [1.0.0] - 2026-11-06

### 新增

- 基于上游 `Tony15246/uosc_danmaku` 建立 fork，并保留上游全部功能。
- 本 fork 新增：对外输出当前匹配结果（消息 + user-data 双通道，带 `path` 校验与换片清场）。

### 已知限制

- 哈希匹配需 LuaJIT 或 Lua 5.2，不支持 Lua 5.1。
- 未安装 uosc 时部分菜单功能不可用（回退到 `mp.input`）。
- 默认经项目维护的 API 代理访问弹弹play，含缓存与频率限制。

## 更早的版本

本仓库为上游 `Tony15246/uosc_danmaku` 的 fork，更早的变更见上游仓库的提交历史，此处不做追溯编造。
