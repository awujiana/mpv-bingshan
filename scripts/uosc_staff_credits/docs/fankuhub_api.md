# fankuhub API 全面使用文档

> **网站**: https://fankuhub.com/
> **API 基础 URL**: `https://fankuhub.com/api/v1`
> **数据源**: 聚合 Bangumi、MyAnimeList(MAL)、AniList 等评分网站数据
> **后端框架**: NestJS
> **ID 格式**: ULID（26位大小写字母+数字，如 `cmpaxwn190rbomhlhlarixtik`）
> **图片 CDN**: `https://img.fankuhub.com/` 或 `https://img-worker.fankuhub.com/`

## 目录

1. [API 端点总览](#1-api-端点总览)
2. [通用响应格式](#2-通用响应格式)
3. [搜索动漫](#3-搜索动漫)
4. [获取动漫详情](#4-获取动漫详情)
5. [获取本季新番](#5-获取本季新番)
6. [数据结构详解](#6-数据结构详解)
7. [图片资源](#7-图片资源)
8. [错误处理](#8-错误处理)
9. [在 uosc_staff_credits 中的使用](#9-在-uosc_staff_credits-中的使用)
10. [与 Bangumi API 的对比](#10-与-bangumi-api-的对比)

---

## 1. API 端点总览

| 端点 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 搜索动漫 | GET | `/api/v1/anime/search?q={keyword}` | 按关键词搜索番剧 |
| 动漫详情 | GET | `/api/v1/anime/{id}` | 获取番剧详情（含角色+职员） |
| 本季新番 | GET | `/api/v1/anime/seasonal` | 获取当季新番列表 |

### 不存在的端点（已验证 404）

| 路径 | 状态 |
|------|------|
| `/api/v1/character/{id}` | 404 |
| `/api/v1/anime/{id}/characters` | 404 |
| `/api/v1/anime/{id}/staff` | 404 |
| `/api/v1/search?keyword={kw}` | 404 |
| `/api/v1/anime/trending` | 404 |
| `/api/v1/anime/ratings` | 404 |
| `/api/search?keyword={kw}` | 404（旧路径，勿用） |
| `/api/search/person?keyword={kw}` | 404（无独立人员搜索端点） |
| `/api/subject/{id}` | 404（旧路径，勿用） |

> **注意**: 角色和职员数据包含在动漫详情 API 的返回数据中，无独立端点。人员搜索复用 `/api/v1/anime/search?q=` 搜索作品后从 staff 提取。

---

## 2. 通用响应格式

所有 API 返回 JSON，统一格式如下：

### 成功响应

```json
{
  "success": true,
  "data": { ... },
  "timestamp": "2026-06-25T04:26:47.304Z"
}
```

### 失败响应

```json
{
  "success": false,
  "statusCode": 404,
  "timestamp": "2026-06-25T04:26:47.304Z",
  "path": "/api/v1/anime/xxx",
  "message": {
    "message": "Cannot GET /api/v1/anime/xxx",
    "error": "Not Found",
    "statusCode": 404
  }
}
```

### 参数校验错误（400）

```json
{
  "success": false,
  "statusCode": 400,
  "message": [
    "property keyword should not exist",
    "q must be longer than or equal to 1 characters",
    "q must be a string"
  ],
  "error": "Bad Request"
}
```

---

## 3. 搜索动漫

### 请求

```
GET /api/v1/anime/search?q={keyword}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `q` | string | 是 | 搜索关键词（1-100 字符），支持中文/日文/英文 |

### 请求示例

```
GET https://fankuhub.com/api/v1/anime/search?q=葬送的芙莉莲
GET https://fankuhub.com/api/v1/anime/search?q=ONE PIECE
```

### 响应

```json
{
  "success": true,
  "data": [
    {
      "id": "cmpaxwle20oaamhlhwg7vly45",
      "titleZh": "葬送的芙莉莲",
      "titleJa": "葬送のフリーレン",
      "titleEn": "Frieren: Beyond the Journey's End",
      "titleRomaji": "Sousou no Frieren",
      "coverUrl": "https://img.fankuhub.com/i/anime/.../small.webp",
      "type": "TV",
      "status": "FINISHED",
      "airDate": "2023-09-29T00:00:00.000Z",
      "airDatePrecision": "DAY",
      "sqlScore": 1.0
    }
  ],
  "timestamp": "2026-06-25T04:29:11.136Z"
}
```

### 搜索结果字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | fankuhub 内部 ULID（26位） |
| `titleZh` | string\|null | 中文名 |
| `titleJa` | string\|null | 日文名 |
| `titleEn` | string\|null | 英文名 |
| `titleRomaji` | string\|null | 罗马音 |
| `coverUrl` | string | 封面图 URL（webp 格式） |
| `type` | string | 类型: `TV`/`MOVIE`/`OVA`/`ONA`/`SPECIAL` |
| `status` | string | 状态: `UPCOMING`/`AIRING`/`FINISHED` |
| `airDate` | string\|null | 开播日期（ISO 8601） |
| `airDatePrecision` | string | 日期精度: `DAY`/`MONTH`/`YEAR` |
| `sqlScore` | number | 全文搜索评分（0-1，越高越匹配） |

### `sqlScore` 说明

- `1.0` = 完全匹配
- `0.8-0.99` = 高度相关
- `< 0.8` = 部分匹配
- 用于搜索结果排序和匹配度判断

---

## 4. 获取动漫详情

### 请求

```
GET /api/v1/anime/{id}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | fankuhub 动漫 ULID |

### 请求示例

```
GET https://fankuhub.com/api/v1/anime/cmpaxwn190rbomhlhlarixtik
```

### 响应数据结构

详情 API 返回的数据包含以下顶层字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | ULID |
| `titleZh` | string\|null | 中文名 |
| `titleJa` | string\|null | 日文名 |
| `titleEn` | string\|null | 英文名 |
| `titleRomaji` | string\|null | 罗马音 |
| `synopsis` | string\|null | 简介 |
| `coverUrl` | string | 详情封面 URL |
| `type` | string | 类型: TV/MOVIE/OVA/ONA/SPECIAL |
| `status` | string | 状态: UPCOMING/AIRING/FINISHED |
| `episodes` | number\|null | 总集数 |
| `duration` | number | 每集时长（秒） |
| `broadcastTimeMinutes` | number | 播放时长（分钟） |
| `weekday` | number | 放送星期（1-7） |
| `airDate` | string\|null | 开播日期 |
| `airDatePrecision` | string | 日期精度 |
| `endDate` | string\|null | 完结日期 |
| `studio` | string\|null | 动画制作公司 |
| `season` | string | 季度（如 `2026-Spring`） |
| `infobox` | array | 信息框（键值对数组） |
| `heat` | number | 综合热度 |
| `aggregateScore` | number | 综合评分 |
| `platforms` | object | 各平台评分数据 |
| `viewerTracking` | object\|null | 观众追踪数据 |
| `latestEpisodeUpdateDate` | string\|null | 最新集更新日期 |
| `latestEpisodeNumber` | number\|null | 最新集数 |
| `latestEpisodeUpdateIsFuture` | boolean | 最新集是否未来更新 |
| `latestEpisodeUpdateState` | string | 更新状态: UPDATED/FUTURE |
| `latestWatchableEpisode` | number\|null | 最新可观看集数 |
| `broadcastProgress` | number\|null | 播放进度 |
| `tags` | array | 标签列表（字符串数组） |
| `genres` | array | 类型标签 |
| `externalIds` | array | 外部平台 ID 映射 |
| `characters` | array | **角色列表（含声优）** |
| `staff` | array | **职员列表（含职位）** |
| `relatedAnime` | array | 关联作品 |

---

## 5. 获取本季新番

### 请求

```
GET /api/v1/anime/seasonal
```

无需参数，返回当季所有新番列表。每项数据结构与搜索结果类似，但额外包含 `heat`（热度）、`aggregateScore`（评分）、`platforms`（各平台数据）等字段。

---

## 6. 数据结构详解

### 6.1 角色结构（Character）

```json
{
  "id": "cmpazzqfj2uqksylhdclc4q99",
  "name": "ブルック",
  "nameCn": "布鲁克",
  "imageUrl": "https://img.fankuhub.com/i/character/.../small.webp",
  "summary": null,
  "infobox": [
    { "key": "简体中文名", "value": "布鲁克" },
    { "key": "别名", "value": [
      { "k": "日文名", "v": "ブルック" },
      { "k": "罗马字", "v": "Brook" }
    ]},
    { "key": "性别", "value": "男" },
    { "key": "生日", "value": "4月3日" },
    { "key": "身高", "value": "266cm" }
  ],
  "type": 1,
  "voiceActors": [
    {
      "id": "cmpazddqp0s4ksylhci4l9a9i",
      "bangumiId": 3828,
      "name": "チョー",
      "nameCn": null,
      "imageUrl": "https://img.fankuhub.com/i/person/.../small.webp",
      "summary": "日本の俳優、声優...",
      "infobox": [...]
    }
  ]
}
```

#### 角色字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 角色 ULID |
| `name` | string | 角色名（通常为日文） |
| `nameCn` | string\|null | 角色中文名 |
| `imageUrl` | string | 角色图片 URL |
| `summary` | string\|null | 角色简介 |
| `infobox` | array | 信息框（键值对） |
| `type` | number | 类型: 1=角色 |
| `voiceActors` | array | 声优列表 |

#### 声优（VoiceActor）字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 声优 ULID |
| `bangumiId` | number | Bangumi 平台 ID |
| `name` | string | 声优名（通常为日文） |
| `nameCn` | string\|null | 声优中文名 |
| `imageUrl` | string | 声优头像 URL |
| `summary` | string\|null | 声优简介 |
| `infobox` | array | 信息框 |

---

### 6.2 职员结构（Staff）

```json
{
  "id": "cmpazzqoz2vd0sylh0ki9cw6a",
  "bangumiId": 290,
  "name": "尾田栄一郎",
  "nameCn": null,
  "imageUrl": "https://img.fankuhub.com/i/person/.../small.webp",
  "summary": "1992年，尾田荣一郎...",
  "infobox": [
    { "key": "简体中文名", "value": "尾田荣一郎" },
    { "key": "性别", "value": "男" },
    { "key": "生日", "value": "1975年1月1日" },
    { "key": "血型", "value": "A" }
  ],
  "positions": ["原作"]
}
```

#### 职员字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 职员 ULID |
| `bangumiId` | number | Bangumi 平台 ID |
| `name` | string | 职员名（通常为日文） |
| `nameCn` | string\|null | 职员中文名 |
| `imageUrl` | string | 职员头像 URL |
| `summary` | string\|null | 职员简介 |
| `infobox` | array | 信息框 |
| `positions` | array | 担任职位列表（如 `["原作"]`、`["系列构成", "脚本"]`） |

---

### 6.3 infobox 信息框结构

infobox 是一个数组，每项为键值对：

```json
[
  { "key": "中文名", "value": "航海王" },
  { "key": "别名", "value": [
    { "v": "ワンピース" },
    { "k": "罗马字", "v": "ONE PIECE" }
  ]},
  { "key": "话数", "value": "*" },
  { "key": "放送开始", "value": "2026年4月5日" }
]
```

- 简单值: `{ "key": "...", "value": "字符串" }`
- 复合值: `{ "key": "...", "value": [ { "k": "标签", "v": "值" }, ... ] }`
- 无标签复合值: `{ "key": "...", "value": [ { "v": "值1" }, { "v": "值2" } ] }`

---

### 6.4 platforms 平台评分

```json
{
  "BANGUMI": {
    "score": 7.8,
    "voteCount": 135,
    "watching": 606,
    "completed": 62,
    "fetchedAt": "2026-06-23T07:51:15.689Z",
    "ratingDist": [
      { "score": 1, "count": 5 },
      { "score": 10, "count": 30 }
    ]
  },
  "MAL": {
    "score": 8.73,
    "voteCount": 1539822,
    "watching": 1922409,
    "completed": 0
  },
  "ANILIST": {
    "score": 8.7,
    "voteCount": 271841,
    "watching": 457277,
    "completed": 40017
  }
}
```

---

### 6.5 externalIds 外部 ID 映射

```json
[
  { "platform": "MAL", "externalId": "21" },
  { "platform": "ANILIST", "externalId": "21" },
  { "platform": "BANGUMI", "externalId": "602059" }
]
```

可用于跨平台数据关联。

---

### 6.6 relatedAnime 关联作品

```json
{
  "id": "cmpaxwb6w0485mhlh12s6aeee",
  "titleZh": "航海王",
  "titleJa": "ONE PIECE",
  "titleEn": "ONE PIECE",
  "coverUrl": "...",
  "type": "TV",
  "status": "FINISHED",
  "airDate": "1999-10-20T00:00:00.000Z",
  "season": "1999-Fall",
  "relations": ["前传"]
}
```

`relations` 字段表示关联类型：`前传`、`续集`、`改编`等。

---

## 7. 图片资源

### 图片 CDN

- 主域名: `https://img.fankuhub.com/`
- Worker 域名: `https://img-worker.fankuhub.com/`（网页中使用，API 中用主域名）

### 图片路径格式

```
https://img.fankuhub.com/i/{type}/{ulid}/{hash}/{size}.webp
```

| 部分 | 说明 | 示例 |
|------|------|------|
| `{type}` | 资源类型 | `anime`/`character`/`person` |
| `{ulid}` | 资源 ULID | `cmpaxwn190rbomhlhlarixtik` |
| `{hash}` | 图片哈希 | `cf3a542ed2e4c20f84aca6c0` |
| `{size}` | 图片尺寸 | `card`/`small`/`detail` |

### 可用尺寸

| 尺寸 | 用途 | 常见出现位置 |
|------|------|-------------|
| `card` | 卡片封面 | 首页推荐、seasonal |
| `small` | 缩略图 | 搜索结果、角色列表 |
| `detail` | 详情图 | 动漫详情页 |

### 格式

所有图片均为 **WebP** 格式。mpv 支持 WebP 解码，可直接用于 overlay。

---

## 8. 错误处理

### 常见错误码

| 状态码 | 含义 | 处理建议 |
|--------|------|----------|
| 400 | 参数错误 | 检查 `q` 参数是否存在且为非空字符串 |
| 404 | 资源不存在 | 检查 ID 是否正确 |
| 500 | 服务器错误 | 重试或切换数据源 |

### 400 错误示例

搜索时使用 `keyword` 而非 `q` 会触发 400 错误：

```
GET /api/v1/anime/search?keyword=test
→ 400: "property keyword should not exist", "q must be a string"
```

### 404 错误示例

```
GET /api/v1/anime/invalid_id
→ 404: "Anime #invalid_id not found"
```

---

## 9. 在 uosc_staff_credits 中的使用

### 配置

在 `script-opts/uosc_staff_credits.conf` 中配置：

```ini
# 数据源选择
#   bangumi - 使用 Bangumi API
#   fankuhub - 使用 fankuhub.com API
#   auto - 先尝试 fankuhub，失败回退到 bangumi（推荐）
data_source=auto
fankuhub_api_base=https://fankuhub.com
```

### 模块接口

`apis/fankuhub.lua` 提供以下函数：

#### `M.set_opts(new_opts)`
注入配置。由 `main.lua` 在初始化时调用。

#### `M.search_anime(keyword, callback)`
搜索动漫。
- **keyword**: 搜索关键词（支持中文）
- **callback**: `function(success, results)`
- **results**: 搜索结果数组，每项含 `id`/`title`/`titleZh`/`sqlScore` 等

#### `M.get_anime_detail(anime_id, callback)`
获取动漫详情（含角色+职员）。
- **anime_id**: fankuhub ULID
- **callback**: `function(success, data)`
- **data**: 详情对象，含 `characters`/`staff`/`synopsis` 等

#### `M.select_best_match(keyword, results, season_num)`
从搜索结果中选择最佳匹配。
- **keyword**: 原始搜索关键词
- **results**: `search_anime` 返回的结果列表
- **season_num**: 季数（可选）
- **返回**: 最佳匹配项
- **算法**: 综合 jaro_winkler（50%）+ sqlScore（50%）评分

#### `M.fetch_characters(keyword, season_num, callback)`
统一接口：搜索 + 获取详情，返回与 Bangumi 兼容的角色数据。
- **keyword**: 搜索关键词
- **season_num**: 季数（可选）
- **callback**: `function(success, subject_info, characters)`
- **subject_info**: `{ id, name, name_cn, url }`
- **characters**: 角色列表，格式与 `api.parse_characters_data` 兼容

#### `M.fetch_characters_by_id(anime_id, subject_info, callback, cancel_cb)`
按 anime_id 直接获取角色+职员（跳过搜索步骤，用于缓存命中场景）。
- **anime_id**: fankuhub 动漫 ULID
- **subject_info**: 可选，缓存的 `{id,name,name_cn,url}`；缺省时用 anime_id 构造
- **callback**: `function(success, result, err_info)`，`result = { subject, characters }`
- 与 `fetch_characters` 返回格式完全一致，避免缓存字符串 ID 时重搜

#### `M.fetch_cover_intro(keyword, season_num, callback, cancel_cb)`
获取番剧详情用于封面简介（含多平台评分、制作信息、多语言名称）。
- **keyword**: 搜索关键词
- **season_num**: 季数（可选）
- **callback**: `function(success, detail, err_info)`
- **detail**: 封面简介数据对象，含以下字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 原始名（日文优先） |
| `name_cn` | string | 中文名 |
| `name_en` | string | 英文名 |
| `name_romaji` | string | 罗马音 |
| `summary` | string | 简介（多层回退: summary → synopsis → description → info.summary → overview） |
| `date` | string | 首播日期 |
| `tags` | array | 标签列表 |
| `cover_url` | string | 封面图 URL |
| `episode_count` | number\|null | 集数 |
| `score` | number\|null | 综合评分（`aggregateScore`） |
| `duration` | number\|null | 每集时长（秒） |
| `platform` | string | 播放平台/类型（TV/Movie/OVA 等） |
| `director` | string | 导演（从 staff positions 提取） |
| `original_work` | string | 原作（从 staff positions 提取） |
| `studio` | string | 动画制作公司（从 staff positions 提取） |
| `source` | string | 改编来源（从 detail.source 或 infobox 提取） |
| `platforms` | array\|nil | 多平台评分数据（V4-P3 新增，见下方） |

##### `platforms` 多平台评分结构

从 `detail.platforms` 提取，按固定顺序输出（仅含 score > 0 的平台）：

```lua
{
    {
        key = "BANGUMI",
        label = "Bangumi",
        score = 7.8,
        vote_count = 135,
        watching = 606,
        completed = 62,
    },
    {
        key = "MAL",
        label = "MAL",
        score = 8.73,
        vote_count = 1539822,
        watching = 1922409,
        completed = 0,
    },
    {
        key = "ANILIST",
        label = "AniList",
        score = 8.7,
        vote_count = 271841,
        watching = 457277,
        completed = 40017,
    },
}
```

封面简介右侧评分区块按此数组顺序渲染。

### V4-P3 封面简介布局规范

封面简介面板（cover_intro）采用 960×580 基准布局（1920×1080 OSD），居中显示：

| 区域 | 位置 | 内容 |
|------|------|------|
| 左侧 | 280 宽 | 封面图（2:3 比例，居中） |
| 右侧顶部 | 300+ 宽 | 番剧名称 / 多平台评分 / 元数据 / 制作信息 / 标签 |
| 右侧底部 | 300+ 宽 | 简介梗概（自动换行 + clip 限制） |
| 底部提示 | 全宽 | "ESC 关闭 \| 数据来源: 番库/Bangumi" |

#### 多平台评分渲染逻辑（`cover_intro.lua` render_info）

1. 检测 `detail.platforms` 数组是否存在且非空
2. 有 platforms：遍历数组，每平台一行，显示 `平台名 评分 (投票数)`
   - 投票数 ≥ 10000 时用"万"简化（如 `8.7 (27.2万)`）
   - 投票数 < 10000 时显示原始数字（如 `7.8 (135)`）
3. 无 platforms（Bangumi 数据源回退）：显示单行 `评分 8.7` + `Bangumi 8.7 (12345人)`

#### 制作信息提取逻辑（`fankuhub.lua` fetch_cover_intro）

从 `detail.staff` 的 `positions` 数组中提取关键职位：

| 职位关键词 | 提取字段 |
|------------|----------|
| `导演`/`監督`/`director` | `director` |
| `原作`/`original` | `original_work` |
| `动画制作`/`制作会社`/`animationproduction`/`studio` | `studio` |

#### 简介字段多层回退

```
summary → synopsis → description → info.summary → info.synopsis → info.description → overview
```

任一字段非空即停止回退，确保尽可能获取到简介文本。

#### `M.search_characters(keyword, season_num, callback, cancel_cb)`
搜索角色: 搜索番剧 → 获取详情 → 提取 `characters`（type=1）。

#### `M.search_persons(keyword, season_num, callback, cancel_cb)`
搜索人物: 搜索番剧 → 获取详情 → 提取 staff + voiceActors（去重）。

#### `M.search_studios(keyword, season_num, callback, cancel_cb)`
搜索制作公司: 搜索番剧 → 获取详情 → 提取 staff 中 positions 含"动画制作"的项。

### 数据源选择流程

```
data_source 配置
      │
      ├─ "fankuhub" ──→ 直接用 fankuhub 搜索+获取详情
      │                   失败 ──→ 返回失败（不回退）
      │
      ├─ "bangumi" ──→ 直接用 Bangumi 搜索+获取详情
      │
      └─ "auto" ─────→ 先尝试 fankuhub
                        失败 ──→ 回退到 Bangumi
```

### fankuhub 角色数据格式（与 Bangumi 兼容）

```lua
{
    id = "cmpazzqfj2uqksylhdclc4q99",
    name = "ブルック",
    name_cn = "布鲁克",
    image_url = "https://img.fankuhub.com/.../small.webp",
    actor_name = "チョー",
    actor_name_cn = "",
    actor_image_url = "https://img.fankuhub.com/.../small.webp",
    _source = "fankuhub",
}
```

### fankuhub 职员数据格式

```lua
{
    id = "cmpazzqoz2vd0sylh0ki9cw6a",
    name = "尾田栄一郎",
    name_cn = nil,
    image_url = "https://img.fankuhub.com/.../small.webp",
    positions = {"原作"},
    _source = "fankuhub",
    _is_staff = true,
}
```

---

## 10. 与 Bangumi API 的对比

| 特性 | fankuhub | Bangumi |
|------|----------|---------|
| 搜索支持中文 | 是 | 是 |
| 搜索评分 | `sqlScore`（全文搜索评分） | 无 |
| 角色获取 | 1 次请求（详情含角色+职员+声优） | 2 次请求（characters + persons 并行） |
| 职员数据 | 含 `positions` 职位数组 | 需从 persons API 推断 |
| 声优数据 | 嵌套在角色的 `voiceActors` 中 | 需从 persons API 的 `actors` 字段提取 |
| 角色中文名 | `nameCn` 字段 | `name_cn` 字段 |
| 图片格式 | WebP | JPG |
| 图片尺寸 | small/card/detail | large/medium/common/grid/small |
| 限流 | 无已知限流 | 官方 API 每秒 1 次 |
| User-Agent | 无特殊要求 | 官方 API 要求包含联系方式 |
| 外部 ID 映射 | 含 MAL/AniList/Bangumi ID | 仅 Bangumi ID |
| 综合评分 | 聚合 Bangumi+MAL+AniList | 仅 Bangumi |
| 关联作品 | 含关联类型（前传/续集等） | 含关联类型 |

### fankuhub 优势

1. **一次请求获取全部数据**：搜索 + 详情只需 2 次请求，Bangumi 需 3 次（搜索 + characters + persons）
2. **聚合多平台评分**：可同时获取 Bangumi/MAL/AniList 三个平台的评分和追番数据
3. **中文搜索友好**：内置全文搜索评分 `sqlScore`，匹配度更高
4. **无限流限制**：无需担心官方 API 的每秒 1 次限流
5. **跨平台 ID 映射**：可直接获取 MAL/AniList ID 用于跨平台关联

### Bangumi 优势

1. **数据最权威**：Bangumi 是中文圈最权威的番剧数据库
2. **数据最全**：部分冷门条目可能只有 Bangumi 有收录
3. **角色图片更全**：部分条目 fankuhub 可能缺少角色图片

### 推荐配置

```ini
# 推荐：auto 模式，先 fankuhub 快速获取，失败回退 Bangumi 补全
data_source=auto
```

---

## 附录：curl 测试命令

```bash
# 搜索动漫
curl -s "https://fankuhub.com/api/v1/anime/search?q=葬送的芙莉莲" | python -m json.tool

# 获取详情（含角色+职员）
curl -s "https://fankuhub.com/api/v1/anime/cmpaxwn190rbomhlhlarixtik" | python -m json.tool

# 获取本季新番
curl -s "https://fankuhub.com/api/v1/anime/seasonal" | python -m json.tool

# 提取角色列表
curl -s "https://fankuhub.com/api/v1/anime/cmpaxwn190rbomhlhlarixtik" | \
  python -c "import sys,json; d=json.load(sys.stdin); chars=d['data']['characters']; print(f'角色数: {len(chars)}'); [print(f'  {c[\"name\"]} ({c.get(\"nameCn\",\"\")}) - CV: {[v[\"name\"] for v in c.get(\"voiceActors\",[])]}') for c in chars[:5]]"

# 提取职员列表
curl -s "https://fankuhub.com/api/v1/anime/cmpaxwn190rbomhlhlarixtik" | \
  python -c "import sys,json; d=json.load(sys.stdin); staff=d['data']['staff']; print(f'职员数: {len(staff)}'); [print(f'  {s[\"name\"]} - {s.get(\"positions\",[])}') for s in staff[:5]]"
```
