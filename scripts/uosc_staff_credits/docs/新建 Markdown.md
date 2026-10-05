基于对 d:\Software\PlayerSoftware\MPV\MPV_config\mpv_config-2025.11.28\mpv_config-2025.11.28\portable_config\scripts\uosc_danmaku\ 目录的完整调研，以下是详细的分析报告。

uosc_danmaku 脚本 API 接口调研报告
一、项目结构概览

Plain Text

scripts/uosc_danmaku/
├── apis/
│   ├── dandanplay.lua   # 弹弹play API 封装（核心搜索/匹配/获取弹幕）
│   └── extra.lua        # 额外数据源（TMDB 中文翻译 + 360kan 三方源）
├── modules/
│   ├── aes.lua / base64.lua / hash.lua / md5.lua  # 加密/签名
│   ├── guess.lua        # 文件名 → 番剧名/季/集 解析
│   ├── menu.lua         # uosc 菜单 + 所有 script-message 注册
│   ├── options.lua      # 配置项
│   ├── parse.lua        # 弹幕文件解析
│   ├── render.lua       # ASS 弹幕渲染
│   ├── update.lua       # 自更新
│   └── utils.lua        # 工具函数（含 parse_title / 哈希等）
├── main.lua             # 入口（生命周期 + 主 script-message）
└── README.md
入口文件：d:\Software\PlayerSoftware\MPV\MPV_config\mpv_config-2025.11.28\mpv_config-2025.11.28\portable_config\scripts\uosc_danmaku\main.lua

二、uosc_danmaku 暴露的所有 script-message 命令列表
1. 入口文件 main.lua 中注册的命令（共 9 个）
命令名	参数	用途	注册位置
danmaku-delay	<seconds> [time-pos] [source_url]	设置弹幕延迟（秒，可为负；0 重置；带 time-pos 时只影响该时间点之后；带 source_url 时只影响该弹幕源）	main.lua:892
show_danmaku_keyboard	无	切换弹幕开关（键盘 j）	main.lua:909
check-update	无	检查脚本更新	main.lua:929
clear-source	无	重置当前视频所有弹幕源更改	main.lua:930
immediately_save_danmaku	无	立即保存弹幕到本地	main.lua:931
open_source_delay_menu	无	打开弹幕源延迟设置菜单	main.lua:932
open_search_danmaku_menu	无	打开弹幕搜索菜单（Ctrl+d）	main.lua:933
open_add_source_menu	无	打开"从源添加弹幕"菜单	main.lua:934
open_add_total_menu	无	打开弹幕设置总菜单	main.lua:935
2. apis/extra.lua 中注册的命令（2 个，菜单内部使用）
命令名	参数	用途
get-extra-event	cat, id, playlink, source_id, title, year	选中 360kan 搜索结果后加载详情/电影
add-extra-event	url, episode, number, class, id, site, title, year	选中某集后加载该集弹幕
3. modules/menu.lua 中注册的命令（共 16 个）
命令名	参数	用途
uosc-version	无	uosc 框架回执（用于探测 uosc 是否在线）
set	prop, value	uosc 控件状态同步（仅处理 show_danmaku = on/off）
search-anime-event	query	用户输入搜索关键字后触发搜索
search-episodes-event	animeTitle, bangumiId, api_server	拉取某番剧的剧集列表
load-danmaku	animeTitle, episodeTitle, episodeId, api_server	加载指定剧集的弹幕（核心入口）
add-source-event	query	添加弹幕源（URL/本地路径）
open_danmaku_style_menu	无	打开弹幕样式菜单
open_content_danmaku_menu	无	打开弹幕内容菜单
open-latest-menu-anime	无	重新打开上次搜索结果菜单
cancel-active-request	[menu_type]	取消当前活跃的并发请求
setup-danmaku-style	query_or_json, [text]	弹幕样式菜单事件分发
setup-danmaku-source	json	弹幕源管理菜单事件（delete/block/unblock）
setup-source-delay	query_or_json, [text]	弹幕源延迟菜单事件
handle-danmaku-content-action	json	弹幕内容菜单动作（block_source/adjust_delay）
open_content_delay_menu	source, time	打开"以该弹幕时间为起点"的延迟菜单
setup-content-delay	time, source, [delay_str]	内容延迟菜单的输入回调
4. 启动时对外广播的命令
main.lua:3 启动时调用 mp.commandv('script-message', 'uosc_danmaku-version', VERSION)，外部脚本可监听该消息获取版本号。

大量 script-message-to uosc open-menu / close-menu / set 用于驱动 uosc UI（这些是出站消息，不是入站接口）。

5. 暴露给外部的 mpv 属性（user-data）
仅暴露两个属性，没有暴露当前番剧信息：

user-data/uosc_danmaku/danmaku-delay — 当前弹幕总延迟（数字，秒）

user-data/uosc_danmaku/has-danmaku — 当前是否有弹幕在显示（布尔）

三、获取中文名的可行方案
1. 是否有"获取中文名"的专门接口
没有专门的"翻译为中文名"接口。但实际效果上，uosc_danmaku 通过两条路径已经把番剧的中文名获取到了内部 DANMAKU.anime 字段：

方案 A：直接走弹弹play API（首选，已是中文名）
弹弹play 的 /api/v2/search/anime 接口返回的 animeTitle 字段对中文番剧默认就是中文名。从历史文件可证（截取自 danmaku-history.json）：


Plain Text

"animeTitle":"葬送的芙莉莲 第二季"
"animeTitle":"公鸡斗士"
"animeTitle":"好想告诉你 第三季"
"animeTitle":"咒术回战 死灭回游"
"animeTitle":"凉宫春日的忧郁 (2009)"
调用链（见 apis/dandanplay.lua）：

哈希匹配：match_file → POST /api/v2/match → data.matches[1].animeTitle（main.lua:347）

标题匹配：match_anime → GET /api/v2/search/anime → match_episode → GET /api/v2/bangumi/{bangumiId} → episode.episodeTitle（main.lua:190-191）

外部脚本若想复用，最简办法是直接调用 dandanplay API：


Plain Text

GET https://api.dandanplay.net/api/v2/search/anime?keyword=<URL编码后的关键词>
返回 JSON 中 animes[].animeTitle 即中文标题，animes[].bangumiId 用于进一步获取剧集。

注意：dandanplay.net 的接口需要 X-AppId / X-Timestamp / X-Signature 签名头，签名算法见 apis/dandanplay.lua 的 generateXSignature（基于 AES-ECB 解密 appid+app_accept 拼接 SHA256）。可配置 api_server 指向不需要签名的镜像（如 https://api.dandanplay.net 之外的自建服务），脚本已支持多 server 并发。

方案 B：通过 TMDB 获取中文译名（用于非中文搜索）
见 apis/extra.lua:44 的 query_tmdb：


Plain Text

GET https://api.tmdb.org/3/search/{tv|movie}?api_key=<base64解码的tmdb_api_key>&query=<关键词>&language=zh-CN
电视剧取 data.results[1].name

电影取 data.results[1].title

仅在 query_extra 中检测到搜索词不是中文（is_chinese(name) 返回 false）且 tmdb_api_key 已正确配置时触发，先翻译成中文再用 360kan 搜索。

默认 tmdb_api_key 在 modules/options.lua:15 已内置一个 base64 编码的公共 key，但建议替换为自己的。

方案 C：直接读取 danmaku-history.json（最稳，无需联网）
如果只是想知道"当前这个文件之前匹配过什么中文名"，直接读取历史文件最快，文件路径为 ~~/danmaku-history.json（即 mpv 配置目录下），通过 mp.command_native({"expand-path", options.history_path}) 解析。实测路径： d:\Software\PlayerSoftware\MPV\MPV_config\mpv_config-2025.11.28\mpv_config-2025.11.28\portable_config\danmaku-history.json

key 为文件父目录或文件路径，value 中 animeTitle 字段就是中文名。详见下一节。

2. 是否有"获取当前播放番剧信息"的接口
没有直接暴露的接口。当前番剧信息保存在脚本内部的 Lua 全局表 DANMAKU（含 .anime / .episode / .source / .api_server / .extra），外部脚本无法直接读取。

外部获取当前番剧信息的可行方式：

方式	说明	局限
读取 danmaku-history.json	用 mp.get_property("path") 拿到当前文件路径，在 history JSON 中按 key 查找	仅当该文件/目录已被记录过时可用；首次播放新文件无记录
监听 uosc_danmaku 的 OSD 消息	show_loaded 会通过 show_message 显示 "匹配内容：{anime}-{episode}"	仅是屏幕 OSD，无结构化输出
复用 parse_title() 函数	该函数会从文件名解析出 title/season/episode（在 modules/utils.lua:603）	仅得到文件名层面的解析，不是 dandanplay 返回的标准中文名
自己直接调用 dandanplay API	见方案 A	需要实现签名；或使用自建无需签名的镜像
通过 user-data/uosc_danmaku/has-danmaku	仅能判断是否有弹幕	不包含标题信息
四、danmaku-history.json 文件结构
文件路径：~~/danmaku-history.json（默认即 portable_config/danmaku-history.json），由 options.history_path 配置。

顶层结构

JSON

{
  "<key1>": { <record1> },
  "<key2>": { <record2> },
  ...
  "show_danmaku": false
}
<key> 的取值有两种情形：

本地文件：当前播放文件的父目录路径（带尾部分隔符），如 "E:\\下载的影视资源\\26.04-公鸡斗士\\"；如果文件直接放在根目录，也可能是文件路径本身。

网络流：parse_title() 返回的 title 或 title SeasonN 字符串；网络路径有时也会用去除 query 后的 URL。

show_danmaku 是顶层的弹幕开关状态记忆。

单条记录的字段
通过 write_history 函数（main.lua:341-387）和 add_source_to_history 函数（main.lua:413-446）可总结出两种记录形态：

形态一：通过 dandanplay 主流程匹配（含 animeTitle 等元信息）

JSON

{
  "fname": "[Studio GreenTea] Niwatori Fighter [07][WebRip][HEVC-10bit 1080p AAC ASSx2]",
  "source": "dandanplay",
  "animeTitle": "公鸡斗士",
  "episodeTitle": "第7话",
  "episodeNumber": 7,
  "episodeId": 187720007,
  "api_server": "https://api.dandanplay.net"
}
字段含义：

fname：触发匹配时的源文件名（no-ext）

source：弹幕来源标识，固定 "dandanplay"

animeTitle：中文名番剧标题（核心字段）

episodeTitle：集标题（如 "第7话" 或 "第1话 颠倒的帕特玛"）

episodeNumber：集数（整数）

episodeId：dandanplay 的剧集 ID（用于直接 GET /api/v2/comment/{episodeId} 拉取弹幕）

api_server：实际提供弹幕的 API 服务器 URL

形态二：通过 360kan 三方源匹配（extra 路径）

JSON

{
  "fname": "...",
  "source": "qq",   // 或 bilibili1/qiyi/youku
  "animeTitle": "公鸡斗士 (2025)",  // title + " (" + year + ")"
  "episodeTitle": "第7话",
  "episodeNumber": 7,
  "extra": {
    "id": "...",
    "site": "qq",
    "year": "2025",
    "class": "动漫",
    "title": "公鸡斗士",
    "number": 12,
    "episodenum": 7
  },
  "api_server": "..."
}
形态三：仅记录弹幕源（sources 表，无 animeTitle）
当用户手动添加了弹幕源但未走完整匹配流程时，记录形态为：


JSON

{
  "sources": {
    "https://api.dandanplay.net/api/v2/comment/183360022?withRelated=true&chConvert=0": {
      "from": "api_server",
      "api_server": "https://api.dandanplay.net",
      "blocked": false
    },
    "https://www.bilibili.com/bangumi/play/ep1633238": {
      "from": "api_server",
      "blocked": false
    },
    "https://ani.gamer.com.tw/animeVideo.php?sn=47424": {
      "from": "api_server",
      "blocked": true
    }
  }
}
sources 内的每个 key 是弹幕源 URL（dandanplay 的 comment 接口 URL 或第三方网页 URL），value 含：

from：来源类型，api_server / user_custom / user_local

blocked：是否被屏蔽

api_server（可选）：来源 dandanplay 服务器

delay_segments（可选）：分段延迟数组 [{start, delay}, ...]

形态四：旧格式（已自动升级）

JSON

[
  "-<api_server>http://www.bilibili.com/video/av3330542/index_2.html",
  "-<api_server>http://www.bilibili.com/video/av3330542/index_1.html"
]
数组元素格式：[-]<from>[<...>]<url>，- 前缀表示 blocked，{{delay}} 表示延迟。脚本读取时会通过 read_danmaku_source_record（main.lua:448）自动升级为形态三。

空记录
[] 表示该 key 被记下但没有有效数据（例如 "[YYDM&VCB-Studio] Shinsekai Yori [05]..." 一例）。

实际示例（节选自当前 danmaku-history.json）

JSON

{
  "E:\\下载的影视资源\\26.04-公鸡斗士\\": {
    "animeTitle": "公鸡斗士",
    "api_server": "https://api.dandanplay.net",
    "episodeTitle": "第7话",
    "episodeId": 187720007,
    "fname": "[Studio GreenTea] Niwatori Fighter [07][WebRip][HEVC-10bit 1080p AAC ASSx2]",
    "source": "dandanplay",
    "episodeNumber": 7
  },
  "E:\\下载的影视资源\\[orion origin] Dr.Stone Science Future [22] [1080p] [H265 AAC] [CHS_JPN].mp4": {
    "sources": {
      "https://api.dandanplay.net/api/v2/comment/183360022?withRelated=true&chConvert=0": {
        "from": "api_server",
        "api_server": "https://api.dandanplay.net",
        "blocked": false
      }
    }
  },
  "show_danmaku": false
}
五、推荐的集成方式
场景：外部脚本想获取当前播放番剧的中文名
按优先级推荐：

推荐方案 1：读取 danmaku-history.json（最稳、零网络开销）
适合"曾经播放过、已被记录"的场景。

伪流程：

local path = mp.get_property("path") 拿当前文件路径

local history_path = mp.command_native({"expand-path", "~~/danmaku-history.json"})

读取并 utils.parse_json 解析

依次尝试以下 key 查找：

文件父目录（get_parent_directory 等价操作，带尾部分隔符）
文件路径本身
若是网络流，用 parse_title() 算出的 title 或 title SeasonN
命中后取 record.animeTitle（中文名）和 record.episodeTitle（中文集名）

局限：首次播放新番剧时无记录。

推荐方案 2：直接调用 dandanplay API（最权威）
适合需要"实时获取中文名 + 完整剧集列表"的场景。

最简单方式：复用 uosc_danmaku 的 load-danmaku 接口反向查询——但该接口是入站（设置 animeTitle），不是出站查询。

因此外部脚本需自行实现：

从文件名 mp.get_property("filename/no-ext") 用 format_filename 等价正则解析出 title/season/episode（可参考 modules/guess.lua 的 formatters 数组）

URL 编码后调用 GET https://api.dandanplay.net/api/v2/search/anime?keyword=<title>

取 animes[0].animeTitle 即中文名

如果走 dandanplay.net 官方接口需要签名，可：

改用脚本里配置的 api_server（读取 script-opts/uosc_danmaku.conf），如果用户配了无需签名的镜像则直接用

或自己实现签名（参考 apis/dandanplay.lua:9-20 的 generateXSignature，需要 AES-ECB + SHA256 + Base64，KEY 在 main.lua:33 内置）

推荐方案 3：被动监听 uosc_danmaku 的内部消息（不推荐）
uosc_danmaku 没有主动广播"当前番剧信息"的出站消息。show_loaded 只通过 OSD 显示，无法被外部脚本结构化捕获。此方案不可行，除非你愿意 fork 修改源码，在 set_episode_id 或 show_loaded 中加一行 mp.commandv("script-message-to", "<your_script>", "anime-info", DANMAKU.anime, DANMAKU.episode)。

推荐方案 4：TMDB 中文翻译（仅适合非中文文件名）
如果文件名是英文/日文，想得到中文译名，且不想用 dandanplay：

复用 apis/extra.lua:44 的 query_tmdb 逻辑

GET https://api.tmdb.org/3/search/tv?api_key=<key>&query=<keyword>&language=zh-CN

取 results[0].name

局限：仅适合影视剧，对动画番剧的覆盖不如 dandanplay 完整。

综合建议
需求	推荐方案
获取已播放过的番剧中文名	方案 1（读 history.json）
获取新番剧的中文名 + 剧集列表	方案 2（调用 dandanplay API）
仅获取当前文件的中文标题用于显示	方案 1 优先，miss 时降级方案 2

六、关键文件路径汇总
入口：d:\Software\PlayerSoftware\MPV\MPV_config\mpv_config-2025.11.28\mpv_config-2025.11.28\portable_config\scripts\uosc_danmaku\main.lua

菜单与 script-message 注册：...\scripts\uosc_danmaku\modules\menu.lua

dandanplay API 封装：...\scripts\uosc_danmaku\apis\dandanplay.lua

TMDB + 360kan 三方源：...\scripts\uosc_danmaku\apis\extra.lua

文件名解析（标题/季/集）：...\scripts\uosc_danmaku\modules\guess.lua

parse_title / 工具函数：...\scripts\uosc_danmaku\modules\utils.lua

配置项（含 history_path、api_server、tmdb_api_key）：...\scripts\uosc_danmaku\modules\options.lua

历史文件：d:\Software\PlayerSoftware\MPV\MPV_config\mpv_config-2025.11.28\mpv_config-2025.11.28\portable_config\danmaku-history.json

七、核心结论
没有专门"获取中文名"的出站 script-message 接口；中文名是 dandanplay API 返回的 animeTitle 字段（默认即中文），由脚本内部使用，未对外暴露。

共暴露 27 个 mp.register_script_message 入站接口（main.lua 9 个 + extra.lua 2 个 + menu.lua 16 个），但全部是控制类（开关/搜索/延迟/菜单），无"查询当前番剧"接口。

danmaku-history.json 包含完整的中文名信息（animeTitle 字段），且按文件路径/目录路径索引，是外部脚本最易复用的数据源。

DANMAKU 全局表是内部的，外部脚本无法直接读取当前番剧；只能通过历史文件或自行调用 dandanplay API 间接获取。

如需对外提供"当前番剧中文名"能力，需要对 uosc_danmaku 打补丁：在 set_episode_id / show_loaded / write_history 等位置增加 mp.commandv("script-message-to", "<target>", "anime-info", DANMAKU.anime, DANMAKU.episode, ...) 广播，这是唯一能实现实时结构化输出的途径。