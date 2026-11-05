---- uosc_subtitle_style.lua —— 内封字幕样式快速切换（uosc 菜单）
-- @version: 1.0.8
-- ⚠ 上面这行版本标记由 script-modules/updater.lua 读取，用来判定本地版本：
--   本地 >= 远端时不更新、绝不降级。改动功能时请同步递增版本号，否则
--   自更新会认为本地仍是旧版（或误判成同版本反复「已更新」）。
-- 用途：把「底部字幕」在 原位 / 上移 / 中下 / 中部 / 中上 / 顶部 之间一键切换，
--   并可整体缩放、改字体、字号、粗体。UI 直接用 uosc 的菜单
--   （script-message-to uosc open-menu）。
--
-- 机制依据（mpv v0.41 源码 + 本机实测，详见 README）：
--   * 主/次字幕（sid / secondary-sid）**位置与缩放完全独立**：
--     sub-pos/sub-scale 与 secondary-sub-pos/secondary-sub-scale。
--   * 字体/字号/粗体的 mpv 属性是**单份值**（sub_create 给主/次解码器同一份
--     mp_subtitle_opts）：sub-font / sub-font-size / sub-bold /
--     sub-ass-style-overrides 都只有一份。因此采用「编辑目标」制——
--     菜单顶部切换 主字幕/次字幕，样式区只作用于目标轨，另一轨恢复原样
--     （其预设仍被记忆，切回即恢复）。两轨样式值相同时可一起生效。
--     分轨能力矩阵（ASS，本机实测）：
--       位置/缩放  两轨完全独立（sub-pos/scale 与 secondary-sub-*），且**自动避让**
--       字体/字号/描边  仅目标轨（force 的选择性覆盖；副带效果是对白幕按 --sub-* 配色）
--       粗体       共享（style-overrides 列表是解码器级共享，mpv 无分轨粗体通道）
--   * 位置避让：两轨 sub-pos 至少相差一档（pos_min_gap，默认 25）。目标轨设新位置时，
--     另一轨自动让位到最近的不重叠位置（避让范围 0-100）；加载/复位时同样保证。
--   * 描边走 force 的 BORDER/COLORS 位：sub-outline-size 与 sub-outline-color
--     （颜色格式 #RRGGBB，可带 AA 透明度前缀）。
--   * 位置写 sub-pos：sub-ass-override != no 时 mpv 经
--     ass_set_line_position(100-sub-pos) 作用于 libass，ASS 对白幕同样可移动
--     （实测 0→顶部 5.7%、50→中部 41%、100→底部 87.7%）；且运行时即时生效
--     （mpv 的 r/t 键位同路径）。带 \pos 的 signs/特效幕不受影响。
--   * 字体（ASS）→ sub-ass-override=force + sub-font：force 的选择性覆盖
--     FONT_NAME 位只作用于该轨（另一轨保持 scale 基线 ⇒ 保留字幕自带字体），
--     实现真正的分轨字体。代价：该轨对白幕同时按 --sub-* 配色渲染
--     （带 \pos 的 signs 因 explicit 豁免，不受影响）。
--     （注：不能用 style-overrides 列表的 FontName= —— 列表是解码器级共享，
--     会同时改掉所有字幕轨，无法分轨。）
--   * 字号（ASS）→ sub-ass-override=force + sub-font-size：mpv 按
--     「720p 等效」换算到脚本 PlayResY（实测 24→12 脚本单位→墨高约 8px）。
--   * **绝不轻易重建解码器**（用户报障：编辑时字幕定住不跳句）：
--     override 切换 / sub-reload 都会让字幕解码器重建，重建后新解码器拿不到
--     已消费的包 → 当前句丢失/滞留。外挂字幕因 fully_read 会被 sub_preload
--     全量重载而侥幸无恙，**内封字幕则必然中招**。
--     因此：① 进入/退出 force 才重建一次（不可避免）；
--           ② 已是 force 时改字体/字号/描边 → 只写属性 + 一次 OSD 微扰
--              （show-text），让 configure_ass 重跑读到新值（实测 0.2s 生效）；
--           ③ 位置/缩放本来即时生效，不碰 override。
--     粗体只能走 style-overrides 列表（解码器级共享），列表变化会触发一次
--     重建——这是 mpv 唯一通道，菜单已注明。
--   * 粗体（ASS）→ 只能走列表 Bold=（force 的 flags 不含 ATTRIBUTES 位）。
--   * **force 对带 \pos 的 signs 完全无效**（2026-11-05 真机像素实测）：libass 的选择性
--     覆盖只作用于 !explicit 事件。Netflix 内封 ASS 每行都带 \pos，实测 force 前后
--     差分像素一字不差（主色 #8B8B8B 7943 个像素完全不变），所以改字体/主色会「没反应」。
--     正解是同时写 sub-ass-style-overrides 的 PrimaryColour/OutlineColour/FontName：
--     它改写 track->styles 表，所有引用该 style 的事件（含 \pos）都拿到新值。
--     代价：列表是解码器级共享（主/次轨同变），且列表变化会触发一次重建。
--   * 灰色字幕（如 #8B8B8B）饱和度为 0，旧的「仅彩色字幕」判定会把它当标准黑白字幕
--     跳过；现新增灰阶识别，灰色对白/注释同样套用黑白预设。
--   * 图形字幕（PGS/VOBSUB，image=true）不走 libass，位置/缩放/样式均不可调。
--   * 上下黑边贴合（v1.0.7）：视频文件内嵌的上下黑条（如 3840×2160 里上下各
--     120px）mpv 完全感知不到——osd-dimensions.mt/mb 是 0，sub-use-margins 帮不上忙。
--     本脚本用 screenshot-raw('video') 逐行亮度扫描出黑条厚度，再按
--     sub-font-size × 帧高/720 估算字幕盒高度，把 sub-scale 限到黑条放得下，
--     并用共享的 sub-margin-y 把字幕居中在黑条内：主轨 100（下黑边）、次轨 0（上黑边）。
--     ⚠ 带 \pos 的 explicit ASS 事件对 sub-pos/sub-scale 豁免（mpv 硬边界），
--       这类 signs 保持原位；窗口 letterbox 黑边由 mpv 原生 sub-use-margins 负责。
--   * ⚠ 不要用 sub-reload 推动重建：本机实测它会让播放直接结束
--     （"Exiting... (End of file)"），历届 E2E 的异常均源于此。
--   * ⚠ uosc 菜单 value 是**命令字符串**，uosc 用 mp.command() 执行；mpv 把 `#` 当
--     注释起始符 ⇒ `color #FFFFFF` 的参数会被整段吞掉，退化成「恢复字幕原样」。
--     凡含 #RRGGBB 的 value 必须用双引号包住参数。
--
-- 入口（script-message）：
--   open-menu       打开 uosc 菜单（未检测到 uosc 时降级为循环切换）
--   cycle           循环切换目标轨的位置预设
--   target <main|sec>  切换编辑目标轨道
--   pos <0-150>     设置目标轨 sub-pos
--   scale <倍率>    设置目标轨 sub-scale
--   nudge <±%>      以当前值为基准微调目标轨 sub-pos
--   font <字体名|reset>     字体覆盖（名字含空格，参数会自动拼回）
--   size <像素值|reset>     字号覆盖（720p 等效像素；ASS 下会启用 force）
--   bold <on|off|reset>    粗体覆盖
--   outline <粗细|reset>        描边粗细（sub-outline-size）
--   outline-color <#RRGGBB|reset>  描边颜色（sub-outline-color）
--   style-preset <big-bold|original|sync-other>  快捷预设
--   open-fonts / rescan-fonts  本机字体选择器 / 重新扫描
--   color <#RRGGBB|reset>       主颜色（sub-color）
--   preset-apply / preset-save / preset-reset / preset-toggle-colored /
--   preset-toggle-dual / preset-toggle-enabled / inspect   预设样式与样式检测
--   reset           恢复默认并清除记忆
--   fix-override    把目标轨 sub-ass-override 设为 scale（位置/样式的前置条件）
--   letterbox-toggle / letterbox-refresh  上下黑边贴合开关 / 立即重新检测

local msg = require('mp.msg')
local utils = require('mp.utils')
local options = require('mp.options')

local o = {
    persist = true,      -- 跨文件/重启记忆当前预设（状态文件 ~~/uosc-subtitle-style-state.json）
    pos_default = 100,   -- 主字幕默认位置（mpv 原生默认 sub-pos=100）
    sec_pos_default = 0, -- 次字幕默认位置（mpv 原生默认 secondary-sub-pos=0，即顶部）
    scale_default = 1,   -- 默认缩放倍率
    nudge = 5,           -- 菜单微调的步长（% 屏幕高度）
    pos_min_gap = 25,    -- 两轨位置避让的最小间距（% 屏幕高度；实测一档 ≈ 84px）
    fallback_cycle = true, -- 无 uosc 时 open-menu 降级为循环切换
    fonts = 'Noto Sans CJK SC,Noto Serif CJK SC,Noto Sans CJK KR,Noto Serif CJK KR', -- 字体候选（逗号分隔）
    sizes = '小=32,标准=38,大=46,特大=56', -- 字号候选：标签=数值（720p 等效像素），或裸数值
    colors = '白=#FFFFFF,黑=#000000,深灰=#404040,灰=#808080,浅灰=#C0C0C0,黄=#FFFF00,淡黄=#FFFFC8,青=#00FFFF,淡蓝=#C8E6FF,粉=#FFC8DC,绿=#90EE90,橙=#FFA500', -- 主颜色候选（sub-color）
    colored_threshold = 40,   -- 判定「彩色字幕」的最小饱和度（max-min(RGB)）
    colored_outline_min = 0.005, -- 内封像素采样：白字+彩描边时，高饱和描边像素占比下限。
                              -- 彩描边是细线、占比常不足 2%（实测 06.mkv 粉描边 #ED74CF 仅 ~0.87%），
                              -- 故对「非主色的高饱和元素」单独用这个更低阈值（0.5%）。
    inspect_delay = 1.2,      -- 载入后等待多久做样式检测（秒）
    report_ms = 6000,         -- 左上角检测报告的显示时长（毫秒）
    inspect_retries = 15,     -- 检测重试次数：字幕未及时加载/片头无对白时，等第一句对白出现再检
    inspect_retry_delay = 1.0, -- 检测重试间隔（秒）
    preset_enabled = true,    -- 载入时默认套用预设样式
    preset_only_colored = true, -- 仅当字幕本身是彩色时才套用
    preset_skip_dual = true,  -- 双语字幕（同时存在次字幕轨）时默认不套用、不改颜色
    preset_color = '#FFFFFF',
    preset_outline_color = '#000000',
    preset_outline = 2,
    preset_font = '',         -- 空 = 不指定
    preset_size = 0,          -- 0 = 不指定（720p 等效像素）
    preset_bold = 'keep',     -- keep/on/off
    outlines = '无=0,细=0.5,标准=1,粗=2,特粗=3', -- 描边粗细候选（sub-outline-size）
    outline_colors = '黑=#000000,白=#FFFFFF,红=#FF0000,黄=#FFFF00,绿=#00FF00,青=#00FFFF,蓝=#0000FF,灰=#808080', -- 描边颜色候选（#RRGGBB）
    rebuild_delay = 0.12,     -- override 切换的延迟设置（秒；同 tick 设属性+重建会读旧值）
    dual_layout = true,       -- 中日双语(双轨)自动布局：按语言识别，日文轨置底+缩小、中文轨其上
    dual_layout_scale = 0.8,  -- 双语布局中日文轨的缩放倍率（视觉上小于中文轨）
    -- v1.0.6：把主色/描边色/字体同步写进 sub-ass-style-overrides，使带 \pos 的
    -- 顶部字幕 / signs 也能改色改字体（force 的选择性覆盖对 explicit 事件豁免）。
    -- 关掉则退回纯 force 通道：只改普通对白，但保留主/次分轨能力。
    style_override_all = true,
    -- 灰色字幕（#8B8B8B 这类饱和度为 0 的非纯白/纯黑主色）也算「非标准黑白」，
    -- 载入时同样自动套用黑白预设。关掉则只有彩色字幕才套用。
    preset_include_gray = true,
    -- v1.0.7 上下黑边贴合：检测到视频内嵌上下黑条时，主轨进下黑边、次轨进上黑边。
    letterbox_fit = true,
    letterbox_min_bar = 0.03,   -- 黑条至少占帧高 3% 才启用（防误判暗场）
    letterbox_dark_luma = 20,   -- 行平均亮度低于此视为黑条
    letterbox_pad = 0.10,       -- 字幕盒相对黑条高度留 10% 余量
    letterbox_sample_step = 8,  -- 列采样步长（4K 下每 8 列取 1 像素，控制耗时）
    letterbox_delay = 0.6,      -- 首检延迟（秒，相对 inspect_delay 之后，等画面稳定）
    -- v1.0.8「所有的内封字幕都要被检查」：
    --   ① 旧检测只看当前选中的一条轨，且成功一次就 inspect_done=true，
    --      文件里其它内封轨（简/繁/英/注释 signs 轨）永远不会被检查。
    --   ② 套用判据只看「是否彩色 / 是否灰阶」，任何没落进这两个窄区间的内封配色
    --      都会像用户截图那样被判「非彩色字幕，保持原样」（主色 #8B8B8B）。
    inspect_all_internal = true,  -- 统计全部内封轨；切换 sid 时对新轨重新检测；报告逐轨列出
    preset_all_internal = true,   -- 内封轨除「标准白字黑边」外一律套用黑白预设（不再靠颜色筛选）
}
options.read_options(o, 'uosc_subtitle_style')

-- 运行时开关（菜单可即时切换，不落盘；重启回到 conf 出厂值）
local runtime = {
    override_all = o.style_override_all and true or false,
    include_gray = o.preset_include_gray and true or false,
    bar_fit = o.letterbox_fit and true or false,
}

-- #RRGGBB → ASS 颜色 &H00BBGGRR（sub-ass-style-overrides 里用的格式，BGR 倒序）
local function hex_to_ass_color(hex)
    local rr, gg, bb = tostring(hex or ''):match('^#?(%x%x)(%x%x)(%x%x)$')
    if not rr then return nil end
    return string.format('&H00%s%s%s', bb:upper(), gg:upper(), rr:upper())
end

-- 灰阶判定：饱和度低于彩色阈值，且亮度既不是黑也不是白（#8B8B8B → true）。
-- 像素采样会有抗锯齿/明暗偏差，故用区间而非等值比较。v1.0.8 把区间放宽到
-- [30, 235]：深灰 #2A2A2A / 浅灰 #EAEAEA 这类「看着像黑白但仍偏灰」的内封字幕
-- 也要能被识别，不再因阈值卡在 40/220 而被判「非彩色，保持原样」。
local function is_gray_hex(hex)
    local rr, gg, bb = tostring(hex or ''):match('^#(%x%x)(%x%x)(%x%x)$')
    if not rr then return false end
    local r2, g2, b2 = tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16)
    local lum = (r2 + g2 + b2) / 3
    local sat = math.max(r2, g2, b2) - math.min(r2, g2, b2)
    return sat < (o.colored_threshold or 40) and lum >= 30 and lum <= 235
end

-- 菜单项 value 是命令字符串（uosc 用 mp.command 执行）。mpv 命令解析把 # 当注释符，
-- 所以含 #RRGGBB 的参数必须加双引号；字体名含空格不影响（脚本用 varargs 拼回）。
local function menu_cmd(...)
    local parts = {}
    for i = 1, select('#', ...) do
        local v = tostring((select(i, ...)))
        if v:find('#', 1, true) or v:find(';', 1, true) then
            v = '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
        end
        parts[#parts + 1] = v
    end
    return table.concat(parts, ' ')
end

-- 字体候选表（菜单「字体」区）
local FONT_PRESETS = {}
do
    for name in tostring(o.fonts):gmatch('[^,]+') do
        name = name:gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then FONT_PRESETS[#FONT_PRESETS + 1] = name end
    end
end

-- 字号候选表（菜单「字号」区）。支持两种写法：
--   "标签=数值,标签=数值" 或 "数值,数值"（无标签时按序号自动取名）
local SIZE_PRESETS = {}
do
    local auto_labels = {'小', '较小', '标准', '较大', '大'}
    for item in tostring(o.sizes):gmatch('[^,]+') do
        item = item:gsub('^%s+', ''):gsub('%s+$', '')
        if item ~= '' then
            local label, num = item:match('^([^=]-)%s*=%s*(%d+%.?%d*)$')
            if label and num then
                SIZE_PRESETS[#SIZE_PRESETS + 1] = {label = label, size = tonumber(num)}
            else
                local n = tonumber(item)
                if n then SIZE_PRESETS[#SIZE_PRESETS + 1] = {size = n} end
            end
        end
    end
    for i, p in ipairs(SIZE_PRESETS) do
        if not p.label then p.label = auto_labels[i] or ('第' .. i) end
    end
end

local POS_MIN, POS_MAX = 0, 150
local SCALE_MIN, SCALE_MAX = 0.1, 3
-- 主/次字幕位置避让：两轨 sub-pos 至少相差 o.pos_min_gap（默认 25，实测一档 ≈ 84px，
-- 够放两行字幕）。自动避让的范围限定在 0-100（>100 会把字幕推到屏幕外）。
local PUSH_MAX = 100

-- 描边粗细候选（标签=数值 或裸数值）
local OUTLINE_PRESETS = {}
do
    for item in tostring(o.outlines):gmatch('[^,]+') do
        item = item:gsub('^%s+', ''):gsub('%s+$', '')
        if item ~= '' then
            local label, num = item:match('^([^=]-)%s*=%s*(%d+%.?%d*)$')
            if label and num then
                OUTLINE_PRESETS[#OUTLINE_PRESETS + 1] = {label = label, size = tonumber(num)}
            else
                local n = tonumber(item)
                if n then OUTLINE_PRESETS[#OUTLINE_PRESETS + 1] = {size = n} end
            end
        end
    end
end

-- 主颜色候选（标签=#RRGGBB）
local COLOR_PRESETS = {}
do
    for item in tostring(o.colors):gmatch('[^,]+') do
        item = item:gsub('^%s+', ''):gsub('%s+$', '')
        if item ~= '' then
            local label, color = item:match('^([^=]-)%s*=%s*(.+)$')
            if label and color then
                COLOR_PRESETS[#COLOR_PRESETS + 1] = {label = label, color = color}
            end
        end
    end
end

-- 描边颜色候选（标签=#RRGGBB 或 标签=颜色名）
local OUTLINE_COLOR_PRESETS = {}
do
    for item in tostring(o.outline_colors):gmatch('[^,]+') do
        item = item:gsub('^%s+', ''):gsub('%s+$', '')
        if item ~= '' then
            local label, color = item:match('^([^=]-)%s*=%s*(.+)$')
            if label and color then
                OUTLINE_COLOR_PRESETS[#OUTLINE_COLOR_PRESETS + 1] =
                    {label = label, color = color}
            end
        end
    end
end

local function clamp(v, lo, hi)
    if not v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- 位置预设：sub-pos 值（% 屏幕高度，100=原位）。
-- 取值经本机实测标定（640x360）：5→贴顶 y9-33 / 25→中上 / 50→中部 y136-161 /
-- 75→中下 / 100→原位 y304-328。注意 92 一带字幕会压到 OSC 进度条，不做预设。
local POS_PRESETS = {
    {id = 'pos_default', title = '原位',   hint = 'sub-pos 100', icon = 'vertical_align_center', pos = 100},
    {id = 'pos_up2',     title = '中下部', hint = 'sub-pos 75',  icon = 'swap_vert',             pos = 75},
    {id = 'pos_mid',     title = '中部',   hint = 'sub-pos 50',  icon = 'vertical_align_center', pos = 50},
    {id = 'pos_up3',     title = '中上部', hint = 'sub-pos 25',  icon = 'swap_vert',             pos = 25},
    {id = 'pos_top',     title = '顶部',   hint = 'sub-pos 5',   icon = 'vertical_align_top',    pos = 5},
}

-- 字号（scale）预设：相对倍率
local SCALE_PRESETS = {
    {id = 'scale_080', title = '×0.80', scale = 0.8},
    {id = 'scale_100', title = '×1.00', scale = 1},
    {id = 'scale_125', title = '×1.25', scale = 1.25},
    {id = 'scale_150', title = '×1.50', scale = 1.5},
}

--------------------------------------------------------------------
-- 轨道模型：主/次各自一套预设；font/size/bold 为 nil 表示「字幕原样」
--------------------------------------------------------------------

-- pos_owned：位置是否由**本脚本**设定。false 时脚本只观察不回写，
-- 这样 mpv 配置/默认值（如 secondary-sub-pos=5）不会被脚本覆盖。
local function new_track(pos_default)
    return {pos = clamp(pos_default or o.pos_default, POS_MIN, POS_MAX),
            scale = clamp(o.scale_default, SCALE_MIN, SCALE_MAX),
            font = nil, size = nil, bold = nil,
            color = nil, outline = nil, outline_color = nil,
            pos_owned = false,
            auto = false}  -- auto：当前样式是否由「彩色检测自动套用预设」写入（非用户手动）
end

local state = {
    main = new_track(o.pos_default),
    sec = new_track(o.sec_pos_default),
    target = 'main',   -- 当前编辑/生效的目标轨：'main' | 'sec'
}

-- 进入脚本前的基线值：「恢复原样」要把它们还回去
local baseline = {
    main_override = 'scale',
    sec_override = 'strip',
    font = nil,
    size = 38,
    bold = nil,
    color = nil,
    outline = nil,
    outline_color = nil,
    margin_y = 22,   -- sub-margin-y 是共享且不在 reset-on-next-file 里，改过必须还原
}
do
    baseline.margin_y = mp.get_property_number('sub-margin-y', 22)
    baseline.main_override = tostring(mp.get_property('sub-ass-override') or 'scale')
    baseline.sec_override = tostring(mp.get_property('secondary-sub-ass-override') or 'strip')
    baseline.font = mp.get_property('sub-font')
    local sz = mp.get_property_number('sub-font-size', 0)
    if sz > 0 then baseline.size = sz end
    -- sub-bold 读不到时回落到 mpv 文档默认值 no，否则「恢复原样」清不掉粗体
    baseline.bold = mp.get_property('sub-bold') or 'no'
    baseline.color = mp.get_property('sub-color')
    local osz = mp.get_property_number('sub-outline-size', -1)
    if osz >= 0 then baseline.outline = osz end
    baseline.outline_color = mp.get_property('sub-outline-color')
end

-- 初始位置/缩放取 mpv 的**当前值**，而不是脚本自己的默认值：
-- mpv 对次字幕的默认是 secondary-sub-pos=0（**顶部**），若脚本硬写 100，
-- 启动/首次编辑就会把次字幕从顶部拽到底部（用户报障现象）。
-- 优先级：状态文件 > mpv 当前值 > 配置默认值。
local initial_props = {}
do
    local mp_pos = mp.get_property_number('sub-pos', -1)
    if mp_pos >= 0 then
        state.main.pos = clamp(mp_pos, POS_MIN, POS_MAX)
        initial_props['sub-pos'] = state.main.pos
    end
    local mp_scale = mp.get_property_number('sub-scale', -1)
    if mp_scale > 0 then
        state.main.scale = clamp(mp_scale, SCALE_MIN, SCALE_MAX)
        initial_props['sub-scale'] = state.main.scale
    end
    local sec_pos = mp.get_property_number('secondary-sub-pos', -1)
    if sec_pos >= 0 then
        state.sec.pos = clamp(sec_pos, POS_MIN, POS_MAX)
        initial_props['secondary-sub-pos'] = state.sec.pos
    end
    local sec_scale = mp.get_property_number('secondary-sub-scale', -1)
    if sec_scale > 0 then
        state.sec.scale = clamp(sec_scale, SCALE_MIN, SCALE_MAX)
        initial_props['secondary-sub-scale'] = state.sec.scale
    end
end

local function has_secondary_track()
    local t = mp.get_property_native('current-tracks/sub2')
    if type(t) == 'table' and t.id ~= nil then return true end
    return false
end

local function is_sec()
    return state.target == 'sec' and has_secondary_track()
end

local function cur()
    return is_sec() and state.sec or state.main
end

local function other()
    return is_sec() and state.main or state.sec
end

local function track_name()
    return is_sec() and '次字幕' or '主字幕'
end

local function pos_prop()
    return is_sec() and 'secondary-sub-pos' or 'sub-pos'
end

local function scale_prop()
    return is_sec() and 'secondary-sub-scale' or 'sub-scale'
end

local function override_prop()
    return is_sec() and 'secondary-sub-ass-override' or 'sub-ass-override'
end

local function other_override_prop()
    return is_sec() and 'sub-ass-override' or 'secondary-sub-ass-override'
end

local function baseline_override()
    return is_sec() and baseline.sec_override or baseline.main_override
end

-- 位置避让：把另一轨推到与 target_pos 不重叠的最近位置（0-100 内）。
-- 目标轨位置不被改动——用户刚设的值优先。
-- 注：只在**用户设位置**时避让；加载/复位不强制分离（未拥有的轨保留 mpv 值，
-- mpv 默认本身是主 100 / 次 0，天然不重叠）。
local function push_other_away(target_pos)
    if not has_secondary_track() then return end
    local gap = o.pos_min_gap      -- ⚠ 必须在局部 o 遮蔽选项表之前取出
    local o = other().pos
    if math.abs(o - target_pos) >= gap then return end
    local cands = {}
    if target_pos - gap >= POS_MIN then cands[#cands + 1] = target_pos - gap end
    if target_pos + gap <= PUSH_MAX then cands[#cands + 1] = target_pos + gap end
    if #cands == 0 then return end
    -- 候选相同时取较小值（偏向屏幕上方），保证确定性
    table.sort(cands, function(a, b)
        local da, db = math.abs(a - o), math.abs(b - o)
        if da == db then return a < b end
        return da < db
    end)
    other().pos = cands[1]
    other().pos_owned = true     -- 让位也是脚本改的 ⇒ 取得归属权
    return cands[1]
end

-- 外部改动采纳：用户用 mpv 自己的键位（r/t）、其它脚本或配置文件改位置/缩放时，
-- 脚本必须跟着记；否则下一次「编辑样式」会把用户手设的值覆盖回脚本记忆的旧值。
-- ⚠ save_state 定义在后面的持久化区：这里必须前向声明，否则闭包里的
--   save_state 会解析成全局 nil（Lua 局部量作用域从声明之后才开始）。
local save_state
-- 菜单刷新：定义在后面的 uosc 菜单区，set_* 里要调用，必须前向声明
local refresh_menu
local expected_value = {}     -- prop -> 本脚本最后写入的值
local in_reset_window = false -- end-file 期间 mpv 会按 reset-on-next-file 重置，勿采纳
-- CN+JP 双语自动布局（per-file 覆盖层）：非 nil 时 apply_all 用布局值写两轨位置/缩放，
-- 用户手动设位置/缩放或外部改动即置 nil 关闭。不写状态文件、不跨文件泄漏。
local layout = nil
-- 上下黑边贴合（v1.0.7，per-file 覆盖层）：检测到视频内嵌上下黑条时，
-- {top, bottom, scale, margin_y}；不写状态文件、不跨文件泄漏。
-- 优先级高于 CN+JP 布局（黑边贴合要求主轨 100 / 次轨 0，天然分列上下）。
local barfit = nil
local barfit_gen = 0   -- 切文件后作废上个文件遗留的黑边检测定时器
local disable_barfit   -- 前向声明：adopt_external / set_pos / set_scale 要调用
local refresh_barfit   -- 前向声明：file-loaded 与菜单消息要调用
-- 检测报告文案缓存：黑边贴合要触发 OSD 微扰重绘，会用空白 show-text 覆盖
-- 左上角报告；重绘后必须把报告补回来，否则用户看不到检测结果。
local last_report_text = nil
local report_clear_timer = nil
local function barfit_active()
    return runtime.bar_fit and barfit ~= nil
end

-- 样式检测状态与前向声明（reset_style / file-loaded / sub-text 观察器都要用）：
-- run_inspect 定义在后面的「预设样式与样式检测」区，此处必须前向声明，
-- 否则前置闭包里的 run_inspect 会解析成全局 nil（Lua 局部量作用域从声明之后才开始）。
local inspect_gen = 0           -- 文件代号：自增；切文件后作废上个文件遗留的检测链/观察回调
local inspect_done = false      -- 本文件是否已完成一次检测（成功即不再因对白变化重检）
local inspect_attempts = 0      -- 本文件已重试次数
local inspect_scheduled = false -- 是否已有待执行的重试计时器（防重复排程）
local inspect_armed = false     -- 首检(inspect_delay)是否已跑过；跑过才允许 sub-text 观察器触发
-- 本文件累计检测尝试次数（硬上限）：seek / 新一段对白都会刷新 inspect_attempts，
-- 若不加总上限，字幕始终不可采样（如 sub-visibility=no）时会无界重试、反复截图。
local inspect_total = 0
local INSPECT_TOTAL_CAP = 100
local sub_text_was_empty = true -- 上一帧 sub-text 是否为空（用于识别「新一段对白开始」）
-- v1.0.8：按轨记录检测结果，使「文件里每一条内封字幕轨」都至少被检查一次。
-- key = track-list 的 sub 轨 id，value = 该轨是否已成功检出（nil = 尚未检查）。
local inspected_internal = {}
local run_inspect

local function write_prop(prop, value)
    expected_value[prop] = value
    mp.set_property_native(prop, value)
end

local function adopt_external(prop, track_key, field)
    return function(_, v)
        if type(v) ~= 'number' or in_reset_window then return end
        local exp = expected_value[prop]
        if exp ~= nil and math.abs(v - exp) < 0.001 then return end
        if math.abs(v - state[track_key][field]) < 0.001 then return end
        state[track_key][field] = v
        layout = nil   -- 用户从外部(r/t 键/其它脚本)改了位置/缩放 ⇒ 关闭本次文件的自动布局
        disable_barfit()  -- 同理让出黑边贴合，并还原共享的 sub-margin-y
        save_state()
    end
end

--------------------------------------------------------------------
-- 字幕轨识别
--------------------------------------------------------------------

local function sub_track(order)
    local name = order == 2 and 'current-tracks/sub2' or 'current-tracks/sub'
    local t = mp.get_property_native(name)
    if type(t) == 'table' then return t end
    return nil
end

-- 返回 kind（none/image/ass/text）；order 缺省取当前目标轨
local function track_info(order)
    local ord = order or (is_sec() and 2 or 1)
    local t = sub_track(ord)
    if not t then return 'none' end
    local codec = tostring(t.codec or ''):lower()
    if t.image then
        return 'image'
    elseif codec == 'ass' or codec == 'ssa' then
        return 'ass'
    end
    return 'text'
end

local KIND_TEXT = {
    none  = '未选择字幕轨',
    image = '图形字幕(PGS/VOBSUB)',
    ass   = 'ASS 字幕',
    text  = '文本字幕',
}

local function track_origin(order)
    local ord = order or (is_sec() and 2 or 1)
    local t = sub_track(ord)
    if not t then return nil end
    return t.external and '外挂' or '内封'
end

local function ass_override_ok(prop)
    return tostring(mp.get_property(prop or override_prop()) or 'scale') ~= 'no'
end

--------------------------------------------------------------------
-- 状态持久化（跨文件/重启记忆；mpv.conf 的 reset-on-next-file 会重置属性，
-- 故每个文件加载后都要重新应用）
--------------------------------------------------------------------

local function state_path()
    local p = mp.command_native({'expand-path', '~~/uosc-subtitle-style-state.json'})
    return type(p) == 'string' and p or nil
end

local function read_track_fields(data, track)
    if type(data.pos) == 'number' then
        track.pos = clamp(data.pos, POS_MIN, POS_MAX)
        track.pos_owned = true    -- 状态文件里的位置 = 用户通过本脚本设过的
    end
    if type(data.scale) == 'number' then track.scale = clamp(data.scale, SCALE_MIN, SCALE_MAX) end
    -- 样式字段缺失（含旧版状态文件）一律按「原样」处理
    if type(data.font) == 'string' and data.font ~= '' then track.font = data.font end
    if type(data.size) == 'number' then track.size = data.size end
    if type(data.bold) == 'boolean' then track.bold = data.bold end
    if type(data.color) == 'string' and data.color ~= '' then track.color = data.color end
    if type(data.outline) == 'number' then track.outline = data.outline end
    if type(data.outline_color) == 'string' and data.outline_color ~= '' then
        track.outline_color = data.outline_color
    end
    -- auto：样式是否由彩色检测自动套用（决定切文件时是否清除，见 clear_auto_style）
    if type(data.auto) == 'boolean' then track.auto = data.auto end
end

local function load_state()
    local path = state_path()
    if not path then return end
    local f = io.open(path, 'rb')
    if not f then return end
    local content = f:read('*a')
    f:close()
    if not content or content == '' then return end
    local ok, data = pcall(utils.parse_json, content)
    if not ok or type(data) ~= 'table' then
        msg.warn('state file corrupt, ignored: ' .. path)
        return
    end
    if type(data.main) == 'table' or type(data.sec) == 'table' then
        -- 新格式：{main={...}, sec={...}, target=, version=}
        if type(data.main) == 'table' then read_track_fields(data.main, state.main) end
        if type(data.sec) == 'table' then read_track_fields(data.sec, state.sec) end
        if data.target == 'sec' then state.target = 'sec' end
        if type(data.version) ~= 'number' then
            -- 旧版状态文件：sec.pos 来自脚本硬编码的 100（mpv 对次字幕的默认其实是
            -- 0=顶部），并非用户意图 ⇒ 放弃归属权，回落到 mpv 当前值
            local cur = mp.get_property_number('secondary-sub-pos', -1)
            state.sec.pos = clamp(cur >= 0 and cur or o.sec_pos_default, POS_MIN, POS_MAX)
            state.sec.pos_owned = false
            msg.info('legacy state: sec.pos released to mpv value ' .. tostring(state.sec.pos))
        end
    else
        -- 旧版扁平格式迁移：{pos,scale,sec_pos,font,size,bold}
        read_track_fields(data, state.main)
        state.sec.pos = clamp(type(data.sec_pos) == 'number' and data.sec_pos or o.pos_default,
                              POS_MIN, POS_MAX)
        msg.info('migrated legacy sub-style state file')
    end
    -- 目标轨保护：选了次字幕但当前文件没有次字幕轨时退回主字幕
    if state.target == 'sec' and not has_secondary_track() then
        state.target = 'main'
    end
end

save_state = function()
    if not o.persist then return end
    local path = state_path()
    if not path then return end
    local data = {
        version = 2,
        main = {pos = state.main.pos, scale = state.main.scale},
        sec = {pos = state.sec.pos, scale = state.sec.scale},
        target = state.target,
    }
    for _, key in ipairs({'main', 'sec'}) do
        local t, d = state[key], data[key]
        if t.font ~= nil then d.font = t.font end
        if t.size ~= nil then d.size = t.size end
        if t.bold ~= nil then d.bold = t.bold end
        if t.color ~= nil then d.color = t.color end
        if t.outline ~= nil then d.outline = t.outline end
        if t.outline_color ~= nil then d.outline_color = t.outline_color end
        if t.auto then d.auto = true end
    end
    local f = io.open(path, 'wb')
    if not f then
        msg.warn('cannot write state file: ' .. path)
        return
    end
    f:write(utils.format_json(data))
    f:close()
end

--------------------------------------------------------------------
-- 应用引擎
--------------------------------------------------------------------

-- style-overrides 列表里由本脚本管理的键。
-- ⚠ 运行时 set_property_native 对该列表是**严格替换**（m_config_set_option_node），
-- 用户通过 sub-ass-style-overrides-append 追加的条目（如 Encoding=-1）会被冲掉，
-- 因此必须先读回现有列表、剔除旧的管理键、再整表写回。
-- FontName/Fontsize 是早期版本写入过的键，保留以清理旧状态残留；
-- v1.0.6 起还会写 FontName / PrimaryColour / OutlineColour（全样式覆盖通道），
-- 「恢复原样」时必须把这些键一并剔除，否则 ASS 原色再也回不来。
local MANAGED_OVERRIDE_KEYS = {
    'FontName', 'Fontsize', 'Bold', 'PrimaryColour', 'OutlineColour', 'Outline',
}

local function same_list(a, b)
    if #a ~= #b then return false end
    local seen = {}
    for _, v in ipairs(a) do seen[v] = (seen[v] or 0) + 1 end
    for _, v in ipairs(b) do
        if not seen[v] then return false end
        seen[v] = seen[v] - 1
    end
    for _, n in pairs(seen) do
        if n ~= 0 then return false end
    end
    return true
end

local function style_equal(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a.font == b.font and a.size == b.size and a.bold == b.bold
end

-- 目标轨是否有任何样式覆盖
local function has_style(t)
    return t.font ~= nil or t.size ~= nil or t.bold ~= nil
        or t.color ~= nil or t.outline ~= nil or t.outline_color ~= nil
end

-- force 只对字体/字号有必要（粗体走列表即可，force 反而会额外扁平配色）
local function needs_force(t)
    return t.font ~= nil or t.size ~= nil or t.color ~= nil
        or t.outline ~= nil or t.outline_color ~= nil
end

-- 某轨是否应当启用 force：该轨有字体/字号样式，且（它是目标轨 或 与目标轨样式相同）
local function wants_force(t)
    return needs_force(t) and (t == cur() or style_equal(t, cur()))
end

-- 写共享样式通道（font/size/bold + 列表）。target_style 为生效的那套样式
local function apply_style_channel(target_style)
    if target_style.font or baseline.font then
        mp.set_property_native('sub-font', target_style.font or baseline.font)
    end
    mp.set_property_native('sub-font-size', target_style.size or baseline.size)
    -- 主颜色：sub-color（force 的 COLORS 位）
    if target_style.color ~= nil then
        mp.set_property_native('sub-color', target_style.color)
    elseif baseline.color then
        mp.set_property_native('sub-color', baseline.color)
    end
    -- 描边：粗细走 sub-outline-size、颜色走 sub-outline-color（force 的
    -- BORDER/COLORS 位），同样是共享单值通道 → 只反映目标轨
    if target_style.outline ~= nil then
        mp.set_property_native('sub-outline-size', target_style.outline)
    elseif baseline.outline then
        mp.set_property_native('sub-outline-size', baseline.outline)
    end
    if target_style.outline_color ~= nil then
        mp.set_property_native('sub-outline-color', target_style.outline_color)
    elseif baseline.outline_color then
        mp.set_property_native('sub-outline-color', baseline.outline_color)
    end
    if target_style.bold ~= nil then
        mp.set_property_native('sub-bold', target_style.bold and 'yes' or 'no')
    else
        mp.set_property_native('sub-bold', baseline.bold)
    end

    -- 列表通道（解码器级共享，主/次轨同变）：
    --   Bold 一直走这里（force 的 flags 不含 ATTRIBUTES 位）；
    --   v1.0.6 起，开启全样式覆盖时再写 FontName / PrimaryColour / OutlineColour。
    -- force 的选择性覆盖只作用于 !explicit 事件，带 \pos 的顶部字幕 / signs 完全不受影响
    -- （真机实测：Netflix 内封 ASS 主色 #8B8B8B，force 前后差分像素一字不差）。
    -- 列表改写的是 track->styles 本身，所有引用该 style 的事件（含 \pos）都会拿到新值。
    -- 只在字段非 nil 时写入 ⇒ 「恢复字幕原样」自动清掉这些键，ASS 原色恢复。
    local want = {}
    if target_style.bold ~= nil then want[#want + 1] = 'Bold=' .. (target_style.bold and '1' or '0') end
    if runtime.override_all then
        if target_style.font then
            want[#want + 1] = 'FontName=' .. target_style.font
        end
        local primary = hex_to_ass_color(target_style.color)
        if primary then want[#want + 1] = 'PrimaryColour=' .. primary end
        local outline_col = hex_to_ass_color(target_style.outline_color)
        if outline_col then want[#want + 1] = 'OutlineColour=' .. outline_col end
        -- 字号/描边粗细不写：ASS 的 Fontsize/Outline 是脚本像素单位，与 mpv 的
        -- 720p 等效像素不同，需要 PlayResY 换算（脚本拿不到），乱写会放大/缩小字幕。
        -- 它们仍由 force + sub-font-size / sub-outline-size 作用于普通对白。
    end

    local cur_list = mp.get_property_native('sub-ass-style-overrides') or {}
    local kept = {}
    for _, entry in ipairs(cur_list) do
        if type(entry) == 'string' then
            local key = entry:match('^%s*([^=]+)%s*=')
            local managed = false
            if key then
                for _, k in ipairs(MANAGED_OVERRIDE_KEYS) do
                    if key == k then managed = true; break end
                end
            end
            if not managed then kept[#kept + 1] = entry end
        end
    end
    local merged = {}
    for _, v in ipairs(kept) do merged[#merged + 1] = v end
    for _, v in ipairs(want) do merged[#merged + 1] = v end
    if not same_list(cur_list, merged) then
        mp.set_property_native('sub-ass-style-overrides', merged)
    end
end

-- 运行时推动重建：把目标轨 override 的最终值推迟一个 tick 设置。
-- 原因（本机实测）：sub-font-size 等没有 UPDATE flag，同一 tick 内先设属性、
-- 后设 override 触发的重建会读到**旧值**；sub-reload 虽然能重建但会让播放直接
-- 结束。override 的每次取值变化都会触发 UPDATE_SUB_HARD 重建，
-- 因此「先切到中间值 → 下一 tick 再切回目标值」，最后一次重建必读到新值。
-- 延迟时长可配（rebuild_delay，秒）。

-- 推动 mpv 重跑 configure_ass（**不重建解码器**）：OSD 状态变化会改变字幕的
-- osd_res，mpv 随即重跑 configure_ass，从而重新读取 --sub-* 属性。
-- 实测（tr3）：force 模式下改 sub-font-size 后调用本函数，0.2s 内画面即更新；
-- 而不调用则 2s 都不变（configure_ass 不会被触发）。
local function nudge_reconfigure()
    mp.commandv('show-text', ' ', 60)
end

-- 设置 override（会触发一次解码器重建）。仅在需要**切换** override 模式时调用。
local function schedule_override(prop, final_value)
    mp.add_timeout(o.rebuild_delay or 0.12, function()
        mp.set_property_native(prop, final_value)
    end)
end

--------------------------------------------------------------------
-- CN+JP 双语自动布局（per-file 覆盖层，不落状态、不跨文件泄漏）
-- 语言识别双路：内封轨读 track-list.lang；外挂轨 mpv 不给 lang(恒 nil)，
-- 改从文件名/标题的语言标记猜(.jpn./.chi./.sc./(JP)/(CHS)…)。
-- 识别为一中一日时：日文轨置底(100)+缩放 dual_layout_scale，中文轨在其上
-- (100-pos_min_gap)，两轨用避让间距分开。带 \pos 的注释幕(signs)对位置与
-- 缩放都豁免（真机实测），样式/位置不受影响。
--------------------------------------------------------------------
local function sub_track_by_id(track_id)
    local tl = mp.get_property_native('track-list') or {}
    for _, t in ipairs(tl) do
        if t.type == 'sub' and t.id == track_id then return t end
    end
    return nil
end

-- 语言码 → 'cn' | 'jp' | nil（兼容 639-1/2/3 与字幕组常见简写；去空格/下划线/连字符）
local function lang_code_class(code)
    code = tostring(code or ''):lower():gsub('[%s_%-]', '')
    if code == '' then return nil end
    if code == 'chi' or code == 'zho' or code == 'zh' or code == 'cmn'
        or code == 'chs' or code == 'sc' or code == 'gb' or code == 'cn'
        or code == 'zhcn' or code == 'zhhans' then
        return 'cn'
    end
    if code == 'jpn' or code == 'ja' or code == 'jp' then return 'jp' end
    return nil
end

-- 判定一条字幕轨的语言：先 track-list.lang，再文件名/标题的语言标记（点分段 + 括号段）
local function track_lang_class(t)
    if not t then return nil end
    local c = lang_code_class(t.lang)
    if c then return c end
    local name = tostring(t['external-filename'] or t.title or '')
    for seg in name:gmatch('[^%./]+') do
        c = lang_code_class(seg)
        if c then return c end
    end
    for seg in name:gmatch('%(([^%)]+)%)') do
        c = lang_code_class(seg)
        if c then return c end
    end
    return nil
end

-- 返回布局覆盖层 {main={pos,scale}, sec={pos,scale}}；非「一中一日」双语返回 nil
local function compute_layout()
    if not o.dual_layout then return nil end
    if not has_secondary_track() then return nil end
    local sid = mp.get_property_number('sid', -1)
    local ssid = mp.get_property_number('secondary-sid', -1)
    if sid < 0 or ssid < 0 then return nil end
    local mc = track_lang_class(sub_track_by_id(sid))
    local sc = track_lang_class(sub_track_by_id(ssid))
    local jp_key
    if mc == 'cn' and sc == 'jp' then jp_key = 'sec'
    elseif mc == 'jp' and sc == 'cn' then jp_key = 'main'
    else return nil end
    local cn_key = (jp_key == 'sec') and 'main' or 'sec'
    local jp_pos = PUSH_MAX                                          -- 日文轨置底
    local cn_pos = clamp(jp_pos - o.pos_min_gap, POS_MIN, PUSH_MAX)  -- 中文轨其上，保持避让间距
    local lay = {}
    lay[jp_key] = {pos = jp_pos, scale = clamp(o.dual_layout_scale, SCALE_MIN, SCALE_MAX)}
    lay[cn_key] = {pos = cn_pos, scale = nil}   -- nil = 不动中文轨缩放
    return lay
end

-- 全量应用。
--   dance=true, rebuild=true：字体/字号变化——需要推动目标轨解码器重建
--     （sub-font-size 无 UPDATE flag），并只触碰**真正需要变化**的轨道。
--     ⚠ 另一轨 or 无变化时绝不能 flink override：实测 mid-flink 会让目标轨
--     经历 重建→显示空白 ~0.3s（用户感知的"改了没反馈"），且会波及无辜轨道。
--   dance=true, rebuild=false：仅切换目标/复位——按需直接设目标值。
--   dance=false：文件加载阶段/pos、scale 变化——pos、scale 实测即时生效，
--     不碰 override，无闪烁。
local function apply_all(dance, rebuild)
    -- 位置：**只回写本脚本拥有（用户通过菜单设过）的轨**。
    -- 未拥有的保持 mpv 当前值（配置/默认），脚本不越权覆盖。
    -- 缩放同理（两轨独立、即时生效）。
    -- CN+JP 双语布局激活(layout)时，用布局值覆盖两轨（日轨置底+缩小，中轨其上）；
    -- 用户手动设位置/缩放即 layout=nil，回到下面的「拥有才回写」。
    local function apply_track_layout(key, pos_prop_, scale_prop_)
        local st = state[key]
        if barfit_active() then
            -- 黑边贴合优先：主轨贴下黑边(100)、次轨贴上黑边(0)，两轨同一限缩倍率
            write_prop(pos_prop_, key == 'main' and PUSH_MAX or POS_MIN)
            write_prop(scale_prop_, barfit.scale)
            return
        end
        local l = layout and layout[key]
        if l then
            write_prop(pos_prop_, l.pos)
            write_prop(scale_prop_, l.scale ~= nil and l.scale or st.scale)
        else
            if st.pos_owned then write_prop(pos_prop_, st.pos) end
            write_prop(scale_prop_, st.scale)
        end
    end
    apply_track_layout('main', 'sub-pos', 'sub-scale')
    if has_secondary_track() then
        apply_track_layout('sec', 'secondary-sub-pos', 'secondary-sub-scale')
    end
    -- 共享属性：把字幕盒居中在黑条内（上下对称，故一条 margin 同时服务两轨）
    if barfit_active() then write_prop('sub-margin-y', barfit.margin_y) end

    -- 共享样式通道 = 目标轨的样式
    apply_style_channel(cur())

    local t_final = wants_force(cur()) and 'force' or baseline_override()
    local o_final = wants_force(other()) and 'force'
        or (is_sec() and baseline.main_override or baseline.sec_override)

    if not dance then
        mp.set_property_native(override_prop(), t_final)
        mp.set_property_native(other_override_prop(), o_final)
        in_reset_window = false   -- 已按 state 重新应用，后续改动重新采纳
        return
    end

    if rebuild then
        -- 目标轨：只有 override 模式**需要切换**时才重建（进入/退出 force）。
        -- 已经是目标模式时完全不碰解码器，仅用 OSD 微扰让 configure_ass
        -- 重跑——这样字体/字号/描边改动 0.2s 内生效且字幕流不中断。
        local t_now = mp.get_property_native(override_prop())
        if t_now ~= t_final then
            schedule_override(override_prop(), t_final)
        else
            nudge_reconfigure()
        end
        -- 另一轨：只在真正需要变化时才动
        local o_prop = other_override_prop()
        local o_now = mp.get_property_native(o_prop)
        if o_now ~= o_final then
            schedule_override(o_prop, o_final)
        end
    else
        mp.set_property_native(override_prop(), t_final)
        local o_prop = other_override_prop()
        local o_now = mp.get_property_native(o_prop)
        if o_now ~= o_final then
            schedule_override(o_prop, o_final)
        end
    end
end

--------------------------------------------------------------------
-- 上下黑边贴合（v1.0.7）
--
-- 为什么必须自己检测：示例视频 Dead-End...mkv 是 3840×2160，上下各 120px
-- 是**编码进画面**的黑条，osd-dimensions.mt/mb 实测为 0，mpv 的
-- sub-use-margins / sub-ass-force-margins 完全帮不上忙。只有读视频帧像素
-- 才知道黑条在哪。窗口 letterbox 黑边由 mpv 原生 margins 机制负责，这里不碰。
--
-- 怎么把字幕放进黑条（本机 2160p 实测标定）：
--   sub-pos=100 + sub-margin-y=34 ⇒ 字幕盒 y1858..2038，黑条从 y2040 开始，
--   字幕正好整条压在画面上。实测字幕盒高 181px ≈ sub-font-size(50) × 1.2
--   × (2160/720)=180px，因此可以用 sub-font-size 估算盒高而不必再截一次图。
--   ① scale = 黑条高×(1-pad) / 估算盒高 ⇒ 把字幕缩到黑条放得下；
--   ② sub-margin-y = (黑条高 - 缩后盒高)/2 / (帧高/720) ⇒ 居中在黑条内。
--   sub-margin-y 是共享属性且对上下对称生效，所以主轨 100 / 次轨 0 会分别
--   居中在下/上黑条内，互不遮挡画面内容。
-- ⚠ 带 \pos 的 explicit ASS 事件对 sub-pos/sub-scale 豁免，保持原位（mpv 硬边界）。
--------------------------------------------------------------------

local BAR_LUMA_R, BAR_LUMA_G, BAR_LUMA_B = 0.299, 0.587, 0.114
local BAR_LINE_GAP = 1.2

-- 逐行平均亮度 → 上下连续暗行厚度（占帧高比例）。
-- 守卫：中央区域必须明显亮于阈值，否则整帧暗场/淡入淡出会被误判成「全是黑边」。
local function detect_bars(img, dark_luma, step)
    if type(img) ~= 'table' or not img.data or not img.w or not img.h or img.h < 16 then
        return nil
    end
    local w, h, stride, data = img.w, img.h, img.stride or (img.w * 4), img.data
    step = math.max(1, math.floor(step or 8))
    local luma = {}
    for y = 0, h - 1 do
        local sum, n = 0, 0
        local base = y * stride + 1
        for x = 0, w - 1, step do
            local i = base + x * 4
            local bb, gg, rr = data:byte(i, i + 2)
            sum = sum + rr * BAR_LUMA_R + gg * BAR_LUMA_G + bb * BAR_LUMA_B
            n = n + 1
        end
        luma[y + 1] = n > 0 and (sum / n) or 0
    end
    local mid_sum, mid_n = 0, 0
    for y = math.floor(h * 0.4), math.ceil(h * 0.6) do
        mid_sum = mid_sum + luma[y + 1]; mid_n = mid_n + 1
    end
    if mid_n == 0 or mid_sum / mid_n < dark_luma * 2 then return nil end
    local top, bottom = 0, 0
    for y = 1, math.floor(h * 0.45) do
        if luma[y] <= dark_luma then top = y else break end
    end
    for y = h, math.ceil(h * 0.55), -1 do
        if luma[y] <= dark_luma then bottom = bottom + 1 else break end
    end
    return top / h, bottom / h
end

-- 由黑条比例算 per-file 覆盖层。纯计算，便于单测。
local function compute_barfit(top_frac, bottom_frac, frame_h, font_size)
    local min_bar = math.max(0, o.letterbox_min_bar or 0.03)
    if top_frac < min_bar or bottom_frac < min_bar then return nil end
    local pad = math.max(0, math.min(0.5, o.letterbox_pad or 0.10))
    -- 上下黑条不等高时取较薄的一侧，保证两条字幕都放得下
    local bar_frac = math.min(top_frac, bottom_frac)
    local usable_px = frame_h * bar_frac * (1 - pad)
    local unit = (font_size > 0 and font_size or 38) * BAR_LINE_GAP * (frame_h / 720)
    if unit <= 0 then return nil end
    local scale = clamp(usable_px / unit, SCALE_MIN, SCALE_MAX)
    if scale > 1 then scale = 1 end   -- 黑条够宽时不放大字幕，只居中
    local box_px = unit * scale
    -- ⚠ sub-margin-y 是 INT 属性：真机实测 mp.set_property_native 传 2.4 会被
    --   mpv 静默忽略（属性仍停在命令行值 80），传整数才生效。必须四舍五入。
    local margin_y = math.max(0, math.floor(
        (frame_h * bar_frac - box_px) / 2 / (frame_h / 720) + 0.5))
    return {top = top_frac, bottom = bottom_frac, scale = scale, margin_y = margin_y}
end

-- 关闭贴合：还原共享的 sub-margin-y（它不在 reset-on-next-file 里，会跨文件泄漏）。
disable_barfit = function()
    barfit = nil
    if mp.get_property_number('sub-margin-y', -1) ~= baseline.margin_y then
        write_prop('sub-margin-y', baseline.margin_y)
        -- sub-margin-y 无 UPDATE flag：不触发 configure_ass 的话，关开关/手动让位
        -- 后画面上的字幕仍停在黑边里，要等 seek 才跳回默认位置。
        nudge_reconfigure()
    end
end

-- 检测一次并应用。检测依赖画面已渲染，故由 file-loaded 延迟触发 / 菜单手动触发。
refresh_barfit = function()
    if not runtime.bar_fit then
        disable_barfit()
        apply_all(false)
        return nil
    end
    local ok, img = pcall(mp.command_native, {'screenshot-raw', 'video'})
    if not ok or type(img) ~= 'table' then return nil end
    local top, bottom = detect_bars(img, o.letterbox_dark_luma or 20,
        o.letterbox_sample_step or 8)
    local fit = top and compute_barfit(top, bottom, img.h,
        mp.get_property_number('sub-font-size', 38))
    if not fit then
        if barfit then
            disable_barfit()
            apply_all(false)
        end
        return nil
    end
    barfit = fit
    apply_all(false)
    nudge_reconfigure()   -- sub-margin-y / sub-scale 无 UPDATE flag，需重跑 configure_ass
    -- OSD 微扰会清掉左上角检测报告，补回来（沿用 flash_tl 已设好的 left/top 对齐）
    if last_report_text then
        mp.commandv('show-text', last_report_text, o.report_ms or 6000)
    end
    return fit
end

--------------------------------------------------------------------
-- 设置入口（全部作用于当前目标轨）
--------------------------------------------------------------------

local function flash(text)
    mp.commandv('show-text', text, 3000)
    -- 菜单开启了 keep_open：改完样式立即把 active/hint 刷新回菜单，
    -- 否则用户看不到「当前选中项」变化，会以为点击没生效。
    if refresh_menu then refresh_menu() end
end

local function describe()
    return string.format('%s：位置 %d%% · 缩放 ×%.2f', track_name(), cur().pos, cur().scale)
end

local function style_desc()
    local t = cur()
    local font = t.font or '原样'
    local size = t.size and string.format('%g', t.size) or '原样'
    local bold
    if t.bold == nil then bold = '原样'
    elseif t.bold then bold = '开'
    else bold = '关' end
    local outline = t.outline and string.format('%g', t.outline) or '原样'
    local ocolor = t.outline_color or '原样'
    local color = t.color or '原样'
    return string.format('%s：字体=%s · 字号=%s · 粗体=%s · 主色=%s · 描边=%s/%s',
        track_name(), font, size, bold, color, outline, ocolor)
end

-- 位置警告（图形字幕/override=no 时设置不生效）
local function position_warning()
    local kind = track_info()
    if kind == 'image' then
        return '图形字幕(PGS/VOBSUB)位置不可调'
    elseif not ass_override_ok() then
        return track_name() .. ' sub-ass-override=no 时位置不生效，请先选「修复」'
    end
    return nil
end

local function set_pos(v, quiet)
    layout = nil   -- 用户手动设位置 ⇒ 关闭本次文件的 CN+JP 自动布局
    disable_barfit()  -- 用户手动调位置即让位，黑边贴合不再回写
    cur().pos = clamp(v, POS_MIN, POS_MAX)
    cur().pos_owned = true                       -- 用户显式设定 ⇒ 取得归属权
    local pushed = push_other_away(cur().pos)    -- 另一轨自动让位，避免重叠
    apply_all(false)
    save_state()
    if not quiet then
        local w = position_warning()
        local text = describe()
        if pushed then
            text = text .. string.format('（%s已避让至 %d%%）',
                is_sec() and '主字幕' or '次字幕', pushed)
        end
        flash(w and (text .. ' ⚠ ' .. w) or text)
    end
end

local function set_scale(v, quiet)
    layout = nil   -- 用户手动设缩放 ⇒ 关闭本次文件的 CN+JP 自动布局
    disable_barfit()  -- 用户手动调缩放即让位，黑边贴合不再回写
    cur().scale = clamp(v, SCALE_MIN, SCALE_MAX)
    apply_all(false)
    save_state()
    if not quiet then flash(describe()) end
end

local function size_label(v)
    for _, p in ipairs(SIZE_PRESETS) do
        if math.abs(p.size - v) < 0.001 then return p.label end
    end
    return nil
end

local function set_font(v, quiet)
    cur().font = v
    cur().auto = false
    apply_all(true, true)
    save_state()
    if not quiet then
        local text = track_name() .. (v and ('字体：' .. v) or '字体：恢复字幕原样')
        if v and track_info() == 'ass' then
            text = text .. '（对白幕将按 sub-* 配色，signs 不受影响）'
        end
        flash(text)
    end
end

local function set_size(v, quiet)
    cur().size = v
    cur().auto = false
    apply_all(true, true)
    save_state()
    if not quiet then
        if v then
            local label = size_label(v)
            local text = string.format('%s字号：%s（720p 等效 %gpx）',
                track_name(), label or tostring(v), v)
            if track_info() == 'ass' then
                text = text .. ' ⚠ 对白幕改按 sub-* 配色渲染（signs 不受影响）'
            end
            flash(text)
        else
            flash(track_name() .. '字号：恢复字幕原样')
        end
    end
end

local function set_bold(v, quiet)
    cur().bold = v
    cur().auto = false
    apply_all(true)
    save_state()
    if not quiet then
        local what
        if v == nil then what = '恢复字幕原样'
        elseif v then what = '加粗'
        else what = '常规' end
        flash(track_name() .. '粗体：' .. what)
    end
end

local function set_color(c, quiet)
    cur().color = c
    cur().auto = false
    apply_all(true, true)
    save_state()
    if not quiet then
        local label = c
        if c ~= nil then
            for _, p in ipairs(COLOR_PRESETS) do
                if p.color:lower() == c:lower() then label = p.label .. '(' .. c .. ')' break end
            end
        end
        flash(track_name() .. (c ~= nil and ('主颜色：' .. tostring(label))
            or '主颜色：恢复字幕原样'))
    end
end

local function set_outline(v, quiet)
    cur().outline = v
    cur().auto = false
    apply_all(true, true)
    save_state()
    if not quiet then
        local label
        if v ~= nil then
            for _, p in ipairs(OUTLINE_PRESETS) do
                if math.abs(p.size - v) < 0.001 then label = p.label break end
            end
        end
        flash(track_name() .. (v ~= nil
            and string.format('描边：%s（%g）', label or tostring(v), v)
            or '描边：恢复字幕原样'))
    end
end

local function set_outline_color(c, quiet)
    cur().outline_color = c
    cur().auto = false
    apply_all(true, true)
    save_state()
    if not quiet then
        local label = c
        if c ~= nil then
            for _, p in ipairs(OUTLINE_COLOR_PRESETS) do
                if p.color:lower() == c:lower() then label = p.label .. '(' .. c .. ')' break end
            end
        end
        flash(track_name() .. (c ~= nil and ('描边颜色：' .. tostring(label))
            or '描边颜色：恢复字幕原样'))
    end
end

-- 切换编辑目标轨道（样式通道随之迁移）
local function switch_target(name, quiet)
    if name ~= 'main' and name ~= 'sec' then return end
    if name == 'sec' and not has_secondary_track() then
        if not quiet then flash('未检测到次字幕轨，目标保持主字幕') end
        return
    end
    if name == state.target then
        if not quiet then flash('编辑目标已是' .. (name == 'sec' and '次字幕' or '主字幕')) end
        return
    end
    state.target = name
    apply_all(true, false)
    save_state()
    if not quiet then flash('编辑目标 → ' .. track_name() .. '（' .. style_desc() .. '）') end
end

-- 快捷预设
local function set_style_preset(name, quiet)
    if name == 'big-bold' then
        local max_size = 0
        for _, p in ipairs(SIZE_PRESETS) do
            if p.size > max_size then max_size = p.size end
        end
        cur().size = #SIZE_PRESETS > 0 and max_size or nil
        cur().bold = true
        cur().auto = false
        apply_all(true, true)
        save_state()
        if not quiet then
            flash(string.format('预设：%s 大字号%s + 加粗', track_name(),
                #SIZE_PRESETS > 0 and ('（' .. size_label(max_size) .. '）') or ''))
        end
    elseif name == 'original' then
        local t = cur()
        t.font, t.size, t.bold = nil, nil, nil
        t.auto = false
        apply_all(true, true)
        save_state()
        if not quiet then flash('样式预设：' .. track_name() .. '全部恢复字幕原样') end
    elseif name == 'sync-other' then
        -- 把目标轨的样式复制给另一轨（两轨一致 ⇒ 一起生效）
        local t = cur()
        other().font, other().size, other().bold = t.font, t.size, t.bold
        t.auto = false
        other().auto = false
        apply_all(true, true)
        save_state()
        if not quiet then flash('样式已同步到' .. (is_sec() and '主字幕' or '次字幕')) end
    end
end

local function reset_style()
    layout = nil
    disable_barfit()   -- 恢复默认也要还原 sub-margin-y，别把黑边贴合带到下一个文件
    state.main = new_track(o.pos_default)
    state.sec = new_track(o.sec_pos_default)
    -- 「恢复默认」是用户显式动作 ⇒ 位置按 mpv 默认值回写并取得归属权
    state.main.pos_owned = true
    state.sec.pos_owned = true
    state.target = 'main'
    apply_all(true, true)
    save_state()
    -- 恢复默认后重新检测一次（字幕可能在首次检测之后才加载出来 / 才出对白）
    inspect_done = false
    inspect_attempts = 0
    inspect_total = 0        -- 用户显式动作：重置总额度，避免被硬上限拦住
    mp.add_timeout(o.inspect_delay or 1.2, function() run_inspect() end)
    flash('已恢复默认（主/次位置已避让 · 缩放 ×1.00 · 样式全原样）')
end

local function fix_override()
    local prop = override_prop()
    mp.set_property_native(prop, 'scale')
    -- 同步基线，否则「恢复原样」会把用户刚做的修复又退回旧值
    if is_sec() then baseline.sec_override = 'scale' else baseline.main_override = 'scale' end
    apply_all(true, true)
    flash(track_name() .. ' sub-ass-override 已设为 scale（位置/样式覆盖生效）')
end

--------------------------------------------------------------------
-- 本机字体枚举（字体选择器数据源）
-- 纯 Lua sfnt/TTC **区间读取**解析 name 表族名 + cmap 检测中文字形（U+4E2D）。
-- 要点（本机实测 + 源码核对）：
--   * TTC 内各字体的表目录偏移是**相对文件头的绝对偏移**，不是相对该字体基址；
--   * 只读 表目录 + name 表 + cmap 表区间，不整文件读（本机 223 个字体 719MB，
--     实测枚举约 0.5s；LuaJIT 比 Python 慢，故做懒加载 + 磁盘缓存）；
--   * 族名取 nameID 16（Typographic Family）优先于 1；
--   * 图标字体（Material Icons / uosc 等）对字幕无意义，按名字关键字过滤；
--   * @ 开头的是竖排变体，跳过。
--------------------------------------------------------------------

local FONT_CACHE_PATH = '~~/uosc-subtitle-style-fonts.json'
local ICON_FONT_MARKERS = {'icon', 'material', 'mdl2', 'uosc', 'modernx', 'wingding', 'webding'}
local CJK_PROBE_CODEPOINT = 0x4E2D  -- 「中」

local function ru16(d, o)
    local a, b = d:byte(o, o + 1)
    if not a or not b then return nil end
    return a * 256 + b
end

local function ru32(d, o)
    local a, b, c, e = d:byte(o, o + 3)
    if not a or not b or not c or not e then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + e
end

local function utf16be_to_utf8(s)
    local out, n, i = {}, #s, 1
    while i + 1 <= n do
        local code = s:byte(i) * 256 + s:byte(i + 1)
        i = i + 2
        if code >= 0xD800 and code <= 0xDBFF and i + 1 <= n then
            local lo = s:byte(i) * 256 + s:byte(i + 1)
            if lo >= 0xDC00 and lo <= 0xDFFF then
                code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00)
                i = i + 2
            end
        end
        if code < 0x80 then
            out[#out + 1] = string.char(code)
        elseif code < 0x800 then
            out[#out + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
        elseif code < 0x10000 then
            out[#out + 1] = string.char(0xE0 + math.floor(code / 0x1000),
                                        0x80 + math.floor(code / 0x40) % 0x40,
                                        0x80 + code % 0x40)
        else
            out[#out + 1] = string.char(0xF0 + math.floor(code / 0x40000),
                                        0x80 + math.floor(code / 0x1000) % 0x40,
                                        0x80 + math.floor(code / 0x40) % 0x40,
                                        0x80 + code % 0x40)
        end
    end
    return table.concat(out)
end

-- name 表 → 最佳族名（nameID 16 优先于 1，Windows/Unicode 平台优先）
local function parse_name_table(nt)
    local count = ru16(nt, 3)
    local storage = ru16(nt, 5)
    if not count or not storage or count > 512 then return nil end
    local best, best_score = nil, -1
    for i = 0, count - 1 do
        local rec = 7 + i * 12
        local pid = ru16(nt, rec)
        local nid = ru16(nt, rec + 6)
        local len = ru16(nt, rec + 8)
        local off = ru16(nt, rec + 10)
        if nid == 16 or nid == 1 then
            local raw = nt:sub(storage + 1 + off, storage + off + (len or 0))
            local name
            if pid == 3 or pid == 0 then
                name = utf16be_to_utf8(raw)
            else
                name = raw
            end
            name = name:gsub('^%s+', ''):gsub('%s+$', '')
            if name ~= '' then
                local score = (nid == 16 and 20 or 10) + ((pid == 3 or pid == 0) and 2 or 0)
                if score > best_score then best, best_score = name, score end
            end
        end
    end
    return best
end

-- ⚠ 解析子表必须带子表在 cmap 表内的偏移 so（0-based）。
-- 教训：初版固定从 cmap 表开头读，msyh 的 format 4 子表在 off=28，全部漏检。
local function cmap_f4_has(t, so, c)
    local seg = ru16(t, so + 7)          -- segCountX2
    if not seg or seg == 0 then return false end
    seg = seg / 2
    local endc_base = so + 15            -- endCode[0] 的 Lua 下标
    for i = 0, seg - 1 do
        local endc = ru16(t, endc_base + i * 2)
        if endc and c <= endc then
            local start = ru16(t, endc_base + seg * 2 + 2 + i * 2)
            if start and c >= start then return true end
            return false
        end
    end
    return false
end

local function cmap_f12_has(t, so, c)
    local n = ru32(t, so + 13)           -- nGroups
    if not n or n > 65536 then return false end
    for i = 0, n - 1 do
        local rec = so + 17 + i * 12
        local start = ru32(t, rec)
        local endc = ru32(t, rec + 4)
        if start and endc and c >= start and c <= endc then return true end
    end
    return false
end

local function cmap_supports(ct, cp)
    local count = ru16(ct, 3)
    if not count or count > 100 then return false end
    for i = 0, count - 1 do
        local rec = 5 + i * 8
        local pid = ru16(ct, rec)
        local off = ru32(ct, rec + 4)
        if off and (pid == 3 or pid == 0) then
            local fmt = ru16(ct, off + 1)
            if fmt == 12 then
                if cmap_f12_has(ct, off, cp) then return true end
            elseif fmt == 4 then
                if cmap_f4_has(ct, off, cp) then return true end
            end
        end
    end
    return false
end

-- 解析一个 sfnt 字体（base 为文件内偏移；TTC 传各字体基址）。
-- 返回 family, cjk
local function parse_font_at(f, base)
    f:seek('set', base)
    local head = f:read(12)
    if not head or #head < 12 then return nil end
    local tag = head:sub(1, 4)
    if tag ~= '\0\1\0\0' and tag ~= 'OTTO' and tag ~= 'true' then return nil end
    local num = ru16(head, 5)
    if not num or num == 0 or num > 64 then return nil end
    f:seek('set', base + 12)
    local dir = f:read(16 * num)
    if not dir or #dir < 16 * num then return nil end
    local name_off, name_len, cmap_off, cmap_len
    for i = 0, num - 1 do
        local rec = 1 + i * 16
        local t = dir:sub(rec, rec + 3)
        if t == 'name' then
            name_off, name_len = ru32(dir, rec + 8), ru32(dir, rec + 12)
        elseif t == 'cmap' then
            cmap_off, cmap_len = ru32(dir, rec + 8), ru32(dir, rec + 12)
        end
    end
    if not name_off then return nil end
    f:seek('set', name_off)   -- TTC 表偏移为绝对偏移（普通 TTF base=0 同理）
    local nt = f:read(math.min(name_len or 0, 65536))
    if not nt or #nt < 6 then return nil end
    local family = parse_name_table(nt)
    if not family then return nil end
    local cjk = false
    if cmap_off then
        f:seek('set', cmap_off)
        local ct = f:read(math.min(cmap_len or 0, 4 * 1024 * 1024))
        if ct and #ct >= 4 then cjk = cmap_supports(ct, CJK_PROBE_CODEPOINT) end
    end
    return family, cjk
end

local function font_dirs()
    local dirs = {}
    local function add(p)
        if p and p ~= '' then dirs[#dirs + 1] = p end
    end
    local cfg = mp.command_native({'expand-path', '~~/fonts'})
    add(cfg)
    local windir = os.getenv('WINDIR') or os.getenv('SYSTEMROOT')
    if windir then add((windir:gsub('\\', '/')) .. '/Fonts') end
    local localappdata = os.getenv('LOCALAPPDATA')
    if localappdata then
        add((localappdata:gsub('\\', '/')) .. '/Microsoft/Windows/Fonts')
    end
    -- 非 Windows 的常见位置
    add('/usr/share/fonts')
    add('/usr/local/share/fonts')
    local home = os.getenv('HOME')
    if home then
        add(home .. '/.fonts')
        add(home .. '/.local/share/fonts')
    end
    return dirs
end

local function font_files()
    local files = {}
    for _, d in ipairs(font_dirs()) do
        local ok, entries = pcall(utils.readdir, d)
        if ok and entries then
            for _, e in ipairs(entries) do
                local name = type(e) == 'table' and (e.name or e[1]) or e
                if type(name) == 'string' then
                    local lower = name:lower()
                    if lower:match('%.ttf$') or lower:match('%.otf$') or lower:match('%.ttc$') then
                        files[#files + 1] = d .. '/' .. name
                    end
                end
            end
        end
    end
    return files
end

local function dirs_signature(files)
    local total = 0
    for _, p in ipairs(files) do
        local f = io.open(p, 'rb')
        if f then
            local size = f:seek('end')
            f:close()
            total = total + (size or 0)
        end
    end
    return string.format('%d:%d', #files, total)
end

local function load_font_cache(sig)
    local path = mp.command_native({'expand-path', FONT_CACHE_PATH})
    if not path then return nil end
    local f = io.open(path, 'rb')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    local ok, data = pcall(utils.parse_json, content or '')
    if ok and type(data) == 'table' and data.sig == sig
        and type(data.fonts) == 'table' and type(data.cjk) == 'table' then
        return data
    end
    return nil
end

local function save_font_cache(data)
    if not o.persist then return end
    local path = mp.command_native({'expand-path', FONT_CACHE_PATH})
    if not path then return end
    local f = io.open(path, 'wb')
    if not f then return end
    f:write(utils.format_json(data))
    f:close()
end

local font_cache = nil   -- 懒加载：首次打开字体选择器时才枚举

local function enumerate_fonts(force)
    local files = font_files()
    local sig = dirs_signature(files)
    if not force then
        local cached = load_font_cache(sig)
        if cached then return cached end
    end

    local seen, cjk_seen = {}, {}
    local fonts, cjk = {}, {}
    for _, p in ipairs(files) do
        local f = io.open(p, 'rb')
        if f then
            local head = f:read(12)
            local bases = {0}
            if head and head:sub(1, 4) == 'ttcf' then
                local num = ru32(head, 9)
                if num and num > 0 and num <= 12 then
                    bases = {}
                    f:seek('set', 12)
                    local raw = f:read(4 * num)
                    if raw then
                        for i = 0, num - 1 do
                            local off = ru32(raw, 1 + i * 4)
                            if off then bases[#bases + 1] = off end
                        end
                    end
                    if #bases == 0 then bases = {0} end
                end
            end
            for _, base in ipairs(bases) do
                local family, has_cjk = parse_font_at(f, base)
                if family and family ~= '' and not family:match('^@') then
                    local lower = family:lower()
                    local is_icon = false
                    for _, m in ipairs(ICON_FONT_MARKERS) do
                        if lower:find(m, 1, true) then is_icon = true; break end
                    end
                    if not is_icon then
                        if not seen[family] then
                            seen[family] = true
                            fonts[#fonts + 1] = family
                        end
                        if has_cjk and not cjk_seen[family] then
                            cjk_seen[family] = true
                            cjk[#cjk + 1] = family
                        end
                    end
                end
            end
            f:close()
        end
    end
    table.sort(fonts)
    table.sort(cjk)
    local data = {sig = sig, fonts = fonts, cjk = cjk}
    save_font_cache(data)
    return data
end

local function font_data()
    if not font_cache then font_cache = enumerate_fonts(false) end
    return font_cache
end


--------------------------------------------------------------------
-- 预设样式（可修改 + 缓存）与字幕样式检测
--------------------------------------------------------------------

local PRESET_PATH = '~~/uosc-subtitle-style-preset.json'

local function preset_from_options()
    return {
        enabled = o.preset_enabled and true or false,
        only_colored = o.preset_only_colored and true or false,
        skip_dual = o.preset_skip_dual and true or false,
        color = o.preset_color,
        outline_color = o.preset_outline_color,
        outline = o.preset_outline,
        font = (o.preset_font ~= '' and o.preset_font) or nil,
        size = (o.preset_size > 0 and o.preset_size) or nil,
        bold = (o.preset_bold == 'on' and true) or (o.preset_bold == 'off' and false) or nil,
    }
end

local preset = preset_from_options()
local preset_factory = preset_from_options()

-- 前向声明：全轨枚举 / 标准黑白判定的实现放在后面的「样式检测」区，
-- 但 needs_preset（预设区）要先引用；Lua 局部变量作用域从声明之后才开始，
-- 不占位会解析成全局 nil（踩过：attempt to call global 'current_internal_id'）。
local current_internal_id, is_standard_black_white

-- 判定「需要转成黑白样式」：
--   only_colored=false → 一律套用；
--   彩色字幕 → 套用；
--   灰色字幕（饱和度为 0 但既不是白也不是黑，如 Netflix 内封 ASS 的 #8B8B8B）→ 也套用；
--   v1.0.8：内封字幕轨除「标准白字黑边」外一律套用 —— 不再依赖单一颜色判据，
--   任何没落进「彩色 / 灰阶」窄区间的内封配色也不会被漏掉。
--   外挂字幕仍走上面的颜色判据（其样式来自文件解析，用户往往有意保留配色）。
local function needs_preset(info)
    if not preset.only_colored then return true end
    if info.colored then return true end
    if runtime.include_gray and is_gray_hex(info.color) then return true end
    if o.preset_all_internal and current_internal_id()
        and not is_standard_black_white(info) then
        return true
    end
    return false
end

local function load_preset()
    local path = mp.command_native({'expand-path', PRESET_PATH})
    if not path then return end
    local f = io.open(path, 'rb')
    if not f then return end
    local content = f:read('*a')
    f:close()
    local ok, data = pcall(utils.parse_json, content or '')
    if not ok or type(data) ~= 'table' then return end
    if type(data.enabled) == 'boolean' then preset.enabled = data.enabled end
    if type(data.only_colored) == 'boolean' then preset.only_colored = data.only_colored end
    if type(data.skip_dual) == 'boolean' then preset.skip_dual = data.skip_dual end
    if type(data.color) == 'string' then preset.color = data.color end
    if type(data.outline_color) == 'string' then preset.outline_color = data.outline_color end
    if type(data.outline) == 'number' then preset.outline = data.outline end
    if type(data.font) == 'string' and data.font ~= '' then preset.font = data.font end
    if type(data.size) == 'number' and data.size > 0 then preset.size = data.size end
    if type(data.bold) == 'boolean' then preset.bold = data.bold end
end

local function save_preset()
    local path = mp.command_native({'expand-path', PRESET_PATH})
    if not path then return end
    local f = io.open(path, 'wb')
    if not f then return end
    f:write(utils.format_json(preset))
    f:close()
end

-- ASS 颜色 &HAABBGGRR → #RRGGBB（⚠ 多捕获的 string.match 返回多个值，不是表）
local function ass_color_to_hex(s)
    local aa, bb, gg, rr = tostring(s or ''):match('^&H(%x%x)(%x%x)(%x%x)(%x%x)$')
    if not rr then return nil end
    return '#' .. rr:upper() .. gg:upper() .. bb:upper()
end

-- 解析 ASS 文件：样式（字体/字号/主色/描边色）+ 内封字体（[Fonts] 段）
local function parse_ass_file(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local txt = f:read('*a') or ''
    f:close()
    if #txt == 0 then return nil end
    local info = {embedded_fonts = {}}
    -- 内封字体：[Fonts] 段里每段以 fontname: 开头
    local fonts_sec = txt:match('%[Fonts%](.-)%[Events%]') or txt:match('%[Fonts%](.*)$')
    if fonts_sec then
        for name in fonts_sec:gmatch('fontname:%s*([^\r\n]+)') do
            info.embedded_fonts[#info.embedded_fonts + 1] = name
        end
    end
    -- 样式：优先名为 Default 的，否则第一条
    for line in (txt .. '\n'):gmatch('([^\n]*)\n') do
        local body = line:match('^Style:%s*(.*)$')
        if body then
            local fld = {}
            for v in (body .. ','):gmatch('([^,]*),') do fld[#fld + 1] = v end
            local cand = {
                name = fld[1], font = fld[2], size = tonumber(fld[3] or ''),
                color = ass_color_to_hex(fld[4]),
                outline_color = ass_color_to_hex(fld[6]),
            }
            if fld[1] == 'Default' then info.style = cand break end
            if not info.style then info.style = cand end
        end
    end
    return info
end

-- 当前目标轨的字幕文件路径（仅外挂轨有）
local function current_sub_path()
    local tl = mp.get_property_native('track-list') or {}
    local want = is_sec() and mp.get_property_number('secondary-sid', -1)
        or mp.get_property_number('sid', -1)
    for _, t in ipairs(tl) do
        if t.type == 'sub' and t.id == want and t.external then
            return t['external-filename']
        end
    end
    return nil
end

-- 是否「彩色」：饱和度 max-min(RGB) ≥ 阈值（前向声明，sample_rendered_colors 先引用）
local is_colored_hex

-- 像素采样：暂停后取「含字幕」与「纯视频」两帧做差分，统计字幕像素颜色。
-- 用于内封字幕（无法读取文件内容）时判断配色。
local function sample_rendered_colors()
    local function raw(kind)
        local ok, img = pcall(mp.command_native, {'screenshot-raw', kind})
        if ok and type(img) == 'table' and img.data then return img end
    end
    local a, b = raw('subtitles'), raw('video')
    if not a or not b or a.w ~= b.w or a.h ~= b.h then return nil end
    local counts, total = {}, 0
    for y = 0, a.h - 1, 2 do
        for x = 0, a.w - 1, 2 do
            local i = y * a.stride + x * 4 + 1
            local bb, gg, rr = a.data:byte(i, i + 2)
            local j = y * b.stride + x * 4 + 1
            local bb2, gg2, rr2 = b.data:byte(j, j + 2)
            if math.abs(bb - bb2) + math.abs(gg - gg2) + math.abs(rr - rr2) > 60 then
                total = total + 1
                local k = string.format('%02X%02X%02X', rr, gg, bb)
                counts[k] = (counts[k] or 0) + 1
            end
        end
    end
    if total == 0 then return nil end
    local arr = {}
    for k, v in pairs(counts) do arr[#arr + 1] = {k = '#' .. k, v = v} end
    table.sort(arr, function(p, q) return p.v > q.v end)
    -- 主色 = 出现最多的「亮色」；描边色 = 出现最多的「暗色」；
    -- accent = 出现最多的「高饱和」色（彩字或彩色描边都归它——白字+紫描边时主色是白、
    -- 而描边亮度落在 60~100 的缝档里两头不沾，只能靠 accent 抓到）
    local color, outline, accent, outline_from_accent
    for _, it in ipairs(arr) do
        local rr, gg, bb = it.k:match('^#(%x%x)(%x%x)(%x%x)$')
        if rr then
            local r2, g2, b2 = tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16)
            local lum = (r2 + g2 + b2) / 3
            if not color and lum >= 100 then color = it.k end
            if not outline and lum < 60 then outline = it.k end
            if not accent and (math.max(r2, g2, b2) - math.min(r2, g2, b2)) >= o.colored_threshold then
                accent = it
            end
        end
    end
    -- 没有暗色描边、但存在高饱和色且不是主色本身时，把它当描边色报告（如紫描边白字）
    if not outline and accent and accent.k ~= color then
        outline = accent.k
        outline_from_accent = true   -- 该描边色由 accent 派生，其饱和度不可单独采信（防 fringe 误判）
    end
    -- 彩色判定（与文件解析路径 is_colored_hex 对齐，另补内封专用规则）：
    --   ① 主色饱和 = 彩字；② 「真实暗描边」饱和 = 深色饱和描边；
    --   ③ 存在非主色的高饱和元素（accent≠主色）且占比 ≥ colored_outline_min = 白字+彩描边。
    -- 彩描边是细线、占比常不足 2%（实测 06.mkv 粉描边 #ED74CF 仅 ~0.87%，旧 2% 阈值漏判），
    -- 故对细描边走更低的专用阈值；差分已剔除背景，计数里只剩字幕像素，≥0.5% 的单幅 saturated
    -- 基本即 deliberate 彩色元素，而非抗锯齿 fringe 的零星像素。
    local accent_frac = accent and (accent.v / total) or 0
    local colored = is_colored_hex(color)
        or (not outline_from_accent and is_colored_hex(outline))
        or (accent ~= nil and accent.k ~= color
            and accent_frac >= (o.colored_outline_min or 0.005))
    return {color = color, outline_color = outline, accent = accent and accent.k,
            total = total, colored = colored}
end

is_colored_hex = function(hex)
    local rr, gg, bb = tostring(hex or ''):match('^#(%x%x)(%x%x)(%x%x)$')
    if not rr then return false end
    rr, gg, bb = tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16)
    return (math.max(rr, gg, bb) - math.min(rr, gg, bb)) >= o.colored_threshold
end

--------------------------------------------------------------------
-- v1.0.8「所有的内封字幕都要被检查」
--   track-list 里 type='sub' 且 external=false 的轨全部纳入检查范围；
--   当前目标轨若是内封轨，也返回其 id，用于按轨记录「已检查」状态。
--------------------------------------------------------------------
local function internal_subtitle_tracks()
    local out = {}
    local tl = mp.get_property_native('track-list') or {}
    for _, t in ipairs(tl) do
        if t.type == 'sub' and not t.external and t.id ~= nil then
            out[#out + 1] = t
        end
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

current_internal_id = function()
    local want = is_sec() and mp.get_property_number('secondary-sid', -1)
        or mp.get_property_number('sid', -1)
    if not want or want < 1 then return nil end
    for _, t in ipairs(internal_subtitle_tracks()) do
        if t.id == want then return want end
    end
    return nil
end

-- 「已经是标准白字黑边」是唯一保留原样的内封例外：
--   非彩色 + 主色接近纯白（各通道 ≥235）。灰色 #8B8B8B、浅灰 #EAEAEA、
--   任意带色调的内封字幕都不属于此例外。
--   ⚠ 不查描边色：像素采样把「少量高饱和抗锯齿 fringe」也会记成 accent 并派生
--     成 outline_color（如白字 + 0.33% 粉边），拿它判「非黑描边」会把标准白字
--     误转成预设；彩色判据（info.colored）已经负责识别真彩描边，这里不重复判断。
is_standard_black_white = function(info)
    if not info or info.colored then return false end
    local rr, gg, bb = tostring(info.color or ''):match('^#(%x%x)(%x%x)(%x%x)$')
    if not rr then return false end
    local r2, g2, b2 = tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16)
    return math.min(r2, g2, b2) >= 235
end

-- 综合检测：优先解析外挂文件（精确），否则像素采样（内封可用）
local function inspect_style()
    local info = {source = nil}
    local path = current_sub_path()
    if path then
        local parsed = parse_ass_file(path)
        if parsed and parsed.style then
            info.source = 'file'
            info.font = parsed.style.font
            info.size = parsed.style.size
            info.color = parsed.style.color
            info.outline_color = parsed.style.outline_color
            info.embedded_fonts = parsed.embedded_fonts or {}
        end
    end
    if not info.color then
        -- 内封字幕：像素采样（要求字幕正在显示、且未处于我们的 force 配色）
        local txt = mp.get_property('sub-text') or ''
        if txt ~= '' and not wants_force(cur()) then
            local s = sample_rendered_colors()
            if s then
                info.source = 'pixels'
                info.color = s.color
                info.outline_color = s.outline_color
                info.accent = s.accent
                info.embedded_fonts = {}
                info.colored = s.colored
            end
        end
    end
    if not info.color and not info.font then return nil end
    -- 彩色判定：主色或描边色任一饱和即算「彩色」（白字+紫描边也要转黑白）。
    -- 像素采样路径已在 sample_rendered_colors 里按 accent 算好（info.colored 非 nil），
    -- 这里只兜底外挂 ASS 解析路径。
    if info.colored == nil then
        info.colored = is_colored_hex(info.color) or is_colored_hex(info.outline_color)
    end
    return info
end

-- 左上角消息（临时把 OSD 对齐设为 left/top，显示后还原）
local function flash_tl(text, ms)
    ms = ms or 6000
    local ax = mp.get_property('osd-align-x')
    local ay = mp.get_property('osd-align-y')
    local moved = false
    if ax ~= 'left' then mp.set_property('osd-align-x', 'left'); moved = true end
    if ay ~= 'top' then mp.set_property('osd-align-y', 'top'); moved = true end
    mp.commandv('show-text', text, ms)
    if moved then
        mp.add_timeout(ms / 1000 + 0.2, function()
            mp.set_property('osd-align-x', ax or 'center')
            mp.set_property('osd-align-y', ay or 'bottom')
        end)
    end
end

-- is_auto=true：由「彩色检测」自动套用（标记 auto；切到非彩色文件时会被清除）；
-- is_auto=false/nil：用户手动 preset-apply（视为用户选择，跨文件持久，不清除）。
local function apply_preset(quiet, is_auto)
    local t = cur()
    t.color = preset.color
    t.outline_color = preset.outline_color
    t.outline = preset.outline
    if preset.font then t.font = preset.font end
    if preset.size then t.size = preset.size end
    if preset.bold ~= nil then t.bold = preset.bold end
    t.auto = is_auto == true
    apply_all(true, true)
    save_state()
    if not quiet then
        flash(track_name() .. ' 已套用预设样式')
    end
    return true
end

-- 清除某轨由「自动预设」写入的样式（auto=true）：自动预设只对彩色字幕生效，
-- 不跨文件泄漏到非彩色字幕。用户手动设过样式的轨（auto=false）不受影响、依旧持久。
local function clear_auto_style(t)
    if not t.auto then return end
    t.font, t.size, t.bold = nil, nil, nil
    t.color, t.outline, t.outline_color = nil, nil, nil
    t.auto = false
end

local function preset_report(info, applied, skipped_dual)
    local lines = {}
    local src = info.source == 'file' and '外挂字幕' or (info.source == 'pixels' and '内封字幕(像素采样)' or '字幕')
    local accent_note = (info.accent and info.accent ~= info.color
        and info.accent ~= info.outline_color) and (' · 饱和 ' .. info.accent) or ''
    lines[#lines + 1] = string.format('%s：主色 %s · 描边 %s%s',
        src, info.color or '未知', info.outline_color or '未知', accent_note)
    local extra = {}
    if info.font then extra[#extra + 1] = '字体 ' .. info.font end
    if info.size then extra[#extra + 1] = '字号 ' .. string.format('%g', info.size) end
    if info.embedded_fonts and #info.embedded_fonts > 0 then
        extra[#extra + 1] = '内封字体 ' .. #info.embedded_fonts .. ' 个：'
            .. table.concat(info.embedded_fonts, '、')
    elseif info.source == 'file' then
        extra[#extra + 1] = '内封字体 无'
    end
    if #extra > 0 then lines[#lines + 1] = table.concat(extra, ' · ') end
    local reason
    if skipped_dual then
        reason = '双语字幕（双轨），保持原样不改颜色'
    elseif not preset.enabled then
        reason = '载入时自动套用未开启，保持原样'
    elseif info.colored then
        reason = '彩色字幕，但预设条件未通过'
    elseif is_gray_hex(info.color) then
        reason = runtime.include_gray and '灰色字幕，但预设条件未通过'
            or '灰色字幕（灰色识别已关闭），保持原样'
    else
        -- 保留「非彩色字幕，保持原样」措辞（历届 E2E/单测的判据），补注说明标准白字黑边
        reason = '非彩色字幕，保持原样（标准白字黑边）'
    end
    lines[#lines + 1] = applied and ('已套用预设样式（黑白：' .. preset.color .. ' / 描边 '
        .. preset.outline_color .. '）') or reason
    return table.concat(lines, '\n')
end

-- 载入后：检测 → 左上角报告 → 按需套用预设
-- 双语（同时存在次字幕轨）默认不套用：两条轨往往已经各有配色，强行统一反而破坏双语可读性
-- （菜单「双语时套用预设」或 conf 的 preset_skip_dual=no 可改回；手动 preset-apply 始终可用）。
-- gen：文件代号（缺省取当前）；非当前文件说明已切文件，放弃本次旧链。
-- inspect_done：本文件已检测过即不再因对白变化重检（避免每句对白都重跑/重复套用）。
run_inspect = function(gen, allow_retry)
    gen = gen or inspect_gen
    if gen ~= inspect_gen or inspect_done then return end
    if inspect_total >= INSPECT_TOTAL_CAP then return end
    inspect_total = inspect_total + 1
    local info = inspect_style()
    if not info then
        -- 字幕尚未加载 / 片头尚无对白：排一次重试（防重复排程），等第一句对白出现
        -- （sub-text 观察器也会即时触发）再检，最多 inspect_retries 次。
        -- allow_retry=false（手动 inspect）不进重试循环——手动重检若因已处 force 采不到，重试也无益。
        if allow_retry ~= false and inspect_attempts < (o.inspect_retries or 15)
            and not inspect_scheduled then
            inspect_attempts = inspect_attempts + 1
            inspect_scheduled = true
            mp.add_timeout(o.inspect_retry_delay or 1.0, function()
                inspect_scheduled = false
                run_inspect(gen, true)
            end)
        end
        return
    end
    inspect_done = true
    inspect_attempts = 0
    -- v1.0.8：按轨记账。切换 sid 后若该内封轨尚未检查过，观察器会重新放行检测。
    local internal_id = current_internal_id()
    if internal_id then inspected_internal[internal_id] = true end
    local applied, skipped_dual = false, false
    if has_secondary_track() and preset.skip_dual then
        skipped_dual = true
    elseif preset.enabled and needs_preset(info) then
        applied = apply_preset(true, true)
    end
    local report = preset_report(info, applied, skipped_dual)
    if o.inspect_all_internal then
        local tracks = internal_subtitle_tracks()
        if #tracks > 0 then
            local checked, pending = 0, {}
            for _, t in ipairs(tracks) do
                if inspected_internal[t.id] then checked = checked + 1
                else pending[#pending + 1] = tostring(t.id) end
            end
            report = report .. string.format('\n内封字幕轨：共 %d 条，已检查 %d 条（当前 %s）',
                #tracks, checked, internal_id and tostring(internal_id) or '外挂')
            if #pending > 0 then
                -- 真机实测示例 MKV 有 42 条内封字幕轨，全列会把左上角 OSD 撑出屏幕。
                -- 最多列前 6 条，其余用「等 N 条」概括。
                local shown = {}
                for i = 1, math.min(#pending, 6) do shown[i] = pending[i] end
                local more = #pending > 6 and (' 等 ' .. #pending .. ' 条') or ''
                report = report .. '，待检查 ' .. table.concat(shown, '/') .. more
            end
        end
    end
    last_report_text = report
    if report_clear_timer and report_clear_timer.kill then report_clear_timer:kill() end
    report_clear_timer = mp.add_timeout((o.report_ms or 6000) / 1000, function()
        last_report_text = nil
        report_clear_timer = nil
    end)
    flash_tl(report, o.report_ms or 6000)
end

--------------------------------------------------------------------
-- uosc 菜单
--------------------------------------------------------------------

local function header(text, hint)
    return {title = text, hint = hint, italic = true, selectable = false,
            keep_open = true, bold = true, align = 'left'}
end

local function section(text)
    return {title = text, muted = true, selectable = false, keep_open = true, align = 'left'}
end

local function build_items()
    local items = {}
    local has_sec = has_secondary_track()
    local kind = track_info()
    local kind_text = KIND_TEXT[kind] or kind
    local origin = track_origin()

    items[#items + 1] = header('编辑目标：' .. track_name() .. '（' .. kind_text ..
        (origin and (' · ' .. origin) or '') .. '）',
        has_sec and '位置/缩放两轨独立；字体/字号/粗体为共享通道，只对目标轨生效'
                 or '未检测到次字幕轨')
    items[#items + 1] = header(string.format('位置 %d%% · 缩放 ×%.2f', cur().pos, cur().scale),
        style_desc())

    local warn = position_warning()
    if kind == 'none' then
        items[#items + 1] = section('未检测到字幕轨，先按 j 选择字幕轨')
    elseif warn then
        items[#items + 1] = section('⚠ ' .. warn)
    end

    -- 编辑目标切换
    items[#items + 1] = section('编辑目标（样式只对目标轨生效）')
    items[#items + 1] = {
        title = '主字幕', hint = 'sid', icon = 'subtitles',
        value = 'script-message-to uosc_subtitle_style target main',
        active = not is_sec(),
    }
    items[#items + 1] = {
        title = '次字幕', hint = has_sec and 'secondary-sid' or '当前文件无次字幕轨',
        icon = 'subtitles',
        value = 'script-message-to uosc_subtitle_style target sec',
        active = is_sec(),
        selectable = has_sec,
        muted = not has_sec,
    }

    items[#items + 1] = section('位置（作用于' .. track_name() .. '）')
    for _, p in ipairs(POS_PRESETS) do
        items[#items + 1] = {
            title = p.title, hint = p.hint, icon = p.icon,
            value = 'script-message-to uosc_subtitle_style pos ' .. p.pos,
            active = (cur().pos == p.pos),
        }
    end
    items[#items + 1] = {
        title = string.format('上移 %d%%（微调）', o.nudge),
        hint = '可连续点击', icon = 'arrow_upward', keep_open = true,
        value = 'script-message-to uosc_subtitle_style nudge ' .. (-o.nudge),
    }
    items[#items + 1] = {
        title = string.format('下移 %d%%（微调）', o.nudge),
        hint = '可连续点击', icon = 'arrow_downward', keep_open = true,
        value = 'script-message-to uosc_subtitle_style nudge ' .. o.nudge,
    }

    items[#items + 1] = section('整体缩放（相对字幕原始大小）')
    for _, p in ipairs(SCALE_PRESETS) do
        items[#items + 1] = {
            title = p.title, hint = '对白幕缩放，不含特效幕', icon = 'format_size',
            value = 'script-message-to uosc_subtitle_style scale ' .. string.format('%g', p.scale),
            active = (math.abs(cur().scale - p.scale) < 0.001),
        }
    end

    items[#items + 1] = section('字体')
    items[#items + 1] = {
        title = '字幕原样', hint = '用字幕文件指定字体', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style font reset',
        active = (cur().font == nil),
    }
    for _, name in ipairs(FONT_PRESETS) do
        items[#items + 1] = {
            title = name, hint = '含 \\pos 的字幕一并生效', icon = 'text_fields',
            value = menu_cmd('script-message-to', 'uosc_subtitle_style', 'font', name),
            active = (cur().font == name),
        }
    end
    items[#items + 1] = {
        title = '选择本机字体…', hint = '打开字体选择器（含中文字体筛选）', icon = 'find_in_page',
        value = 'script-message-to uosc_subtitle_style open-fonts',
    }

    items[#items + 1] = section('字号（720p 等效像素）')
    items[#items + 1] = {
        title = '字幕原样', hint = '用字幕文件指定字号', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style size reset',
        active = (cur().size == nil),
    }
    for _, p in ipairs(SIZE_PRESETS) do
        items[#items + 1] = {
            title = string.format('%s（%gpx）', p.label, p.size),
            hint = '只对目标轨生效；对白幕按 sub-* 配色', icon = 'height',
            value = 'script-message-to uosc_subtitle_style size ' .. string.format('%g', p.size),
            active = (cur().size ~= nil and math.abs(cur().size - p.size) < 0.001),
        }
    end

    items[#items + 1] = section('粗体')
    items[#items + 1] = {
        title = '字幕原样', hint = '用字幕文件指定粗体', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style bold reset',
        active = (cur().bold == nil),
    }
    items[#items + 1] = {
        title = '加粗', hint = 'Bold=1（共享通道：主/次字幕都会生效）', icon = 'format_bold',
        value = 'script-message-to uosc_subtitle_style bold on',
        active = (cur().bold == true),
    }
    items[#items + 1] = {
        title = '常规', hint = 'Bold=0（取消粗体）', icon = 'format_clear',
        value = 'script-message-to uosc_subtitle_style bold off',
        active = (cur().bold == false),
    }

    items[#items + 1] = section('主颜色')
    items[#items + 1] = {
        title = '字幕原样', hint = '用字幕文件指定主色', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style color reset',
        active = (cur().color == nil),
    }
    for _, p in ipairs(COLOR_PRESETS) do
        items[#items + 1] = {
            title = p.label .. '（' .. p.color .. '）',
            hint = '含 \\pos 的字幕一并生效', icon = 'palette',
            -- ⚠ 必须走 menu_cmd 给 #RRGGBB 加引号：mp.command 会把裸 # 当注释符，
            -- 参数被吞掉后脚本收到空值 → 显示「恢复字幕原样」且颜色不变。
            value = menu_cmd('script-message-to', 'uosc_subtitle_style', 'color', p.color),
            active = (cur().color ~= nil and cur().color:lower() == p.color:lower()),
        }
    end

    items[#items + 1] = section('描边粗细')
    items[#items + 1] = {
        title = '字幕原样', hint = '用字幕文件指定描边', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style outline reset',
        active = (cur().outline == nil),
    }
    for _, p in ipairs(OUTLINE_PRESETS) do
        items[#items + 1] = {
            title = string.format('%s（%g）', p.label, p.size),
            hint = '只对目标轨生效（force）', icon = 'border_outer',
            value = 'script-message-to uosc_subtitle_style outline ' .. string.format('%g', p.size),
            active = (cur().outline ~= nil and math.abs(cur().outline - p.size) < 0.001),
        }
    end

    items[#items + 1] = section('描边颜色')
    items[#items + 1] = {
        title = '字幕原样', hint = '用字幕文件指定描边颜色', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style outline-color reset',
        active = (cur().outline_color == nil),
    }
    for _, p in ipairs(OUTLINE_COLOR_PRESETS) do
        items[#items + 1] = {
            title = p.label .. '（' .. p.color .. '）',
            hint = '含 \\pos 的字幕一并生效', icon = 'format_color_text',
            value = menu_cmd('script-message-to', 'uosc_subtitle_style', 'outline-color', p.color),
            active = (cur().outline_color ~= nil
                and cur().outline_color:lower() == p.color:lower()),
        }
    end

    items[#items + 1] = section('快捷预设')
    if #SIZE_PRESETS > 0 then
        items[#items + 1] = {
            title = '大字号 + 加粗',
            hint = '取字号候选中的最大值并加粗', icon = 'tune',
            value = 'script-message-to uosc_subtitle_style style-preset big-bold',
        }
    end
    if has_sec then
        items[#items + 1] = {
            title = '样式同步到另一轨',
            hint = '两轨样式一致时一起生效（mpv 字体通道共享）', icon = 'sync',
            value = 'script-message-to uosc_subtitle_style style-preset sync-other',
        }
    end
    items[#items + 1] = {
        title = '全部恢复原样', hint = '字体/字号/粗体均不覆盖', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style style-preset original',
    }

    if not ass_override_ok() then
        items[#items + 1] = {
            title = '修复：' .. override_prop() .. ' → scale',
            hint = track_name() .. '位置/样式覆盖的前置条件', icon = 'restart_alt',
            value = 'script-message-to uosc_subtitle_style fix-override',
        }
    end

    items[#items + 1] = section('预设样式（载入时自动套用）')
    items[#items + 1] = {
        title = '套用预设样式', hint = string.format('%s / 描边 %s / 粗细 %g',
            preset.color, preset.outline_color, preset.outline), icon = 'auto_fix_high',
        value = 'script-message-to uosc_subtitle_style preset-apply',
    }
    items[#items + 1] = {
        title = '把当前样式存为预设', hint = '用目标轨现有设置覆盖预设并缓存', icon = 'save',
        value = 'script-message-to uosc_subtitle_style preset-save',
    }
    items[#items + 1] = {
        title = '仅彩色/灰色字幕时套用',
        hint = preset.only_colored and '已开启：标准白字黑边字幕保持原样'
            or '已关闭：所有字幕都套用',
        icon = preset.only_colored and 'check_box' or 'check_box_outline_blank',
        value = 'script-message-to uosc_subtitle_style preset-toggle-colored',
        active = preset.only_colored,
    }
    items[#items + 1] = {
        title = '灰色字幕也自动转黑白',
        hint = runtime.include_gray and '已开启：灰字（如 #8B8B8B）识别为需转换'
            or '已关闭：只有彩色字幕才套用',
        icon = runtime.include_gray and 'check_box' or 'check_box_outline_blank',
        value = 'script-message-to uosc_subtitle_style toggle-gray',
        active = runtime.include_gray,
    }
    items[#items + 1] = {
        title = '顶部/定位字幕一并改样式',
        hint = runtime.override_all and '已开启：带 \\pos 的 signs 也改色改字体（主/次轨同变）'
            or '已关闭：只改普通对白（保持分轨）',
        icon = runtime.override_all and 'check_box' or 'check_box_outline_blank',
        value = 'script-message-to uosc_subtitle_style toggle-all',
        active = runtime.override_all,
    }
    items[#items + 1] = {
        title = '双语字幕保持原样',
        hint = preset.skip_dual and ('已开启：检测到次字幕轨时不套用、不改颜色')
            or '已关闭：双语字幕也套用预设（两轨强行统一配色）',
        icon = preset.skip_dual and 'check_box' or 'check_box_outline_blank',
        value = 'script-message-to uosc_subtitle_style preset-toggle-dual',
        active = preset.skip_dual,
        muted = not has_secondary_track(),
    }
    items[#items + 1] = {
        title = '载入时自动套用',
        hint = preset.enabled and '已开启' or '已关闭（只报告不修改）',
        icon = preset.enabled and 'check_box' or 'check_box_outline_blank',
        value = 'script-message-to uosc_subtitle_style preset-toggle-enabled',
        active = preset.enabled,
    }
    items[#items + 1] = {
        title = '重新检测字幕样式', hint = '再次输出主色/描边色/内封字体', icon = 'search',
        value = 'script-message-to uosc_subtitle_style inspect',
    }
    items[#items + 1] = {
        title = '恢复出厂预设', hint = '回到 uosc_subtitle_style.conf 的默认预设', icon = 'restart_alt',
        value = 'script-message-to uosc_subtitle_style preset-reset',
    }

    items[#items + 1] = section('其它')
    local bar_hint
    if not runtime.bar_fit then
        bar_hint = '已关闭：字幕按 mpv 默认位置显示'
    elseif barfit then
        bar_hint = string.format('已开启：黑边 上%.1f%% / 下%.1f%% · 限缩 ×%.2f',
            barfit.top * 100, barfit.bottom * 100, barfit.scale)
    else
        bar_hint = '已开启：当前画面没检测到上下黑边'
    end
    items[#items + 1] = {
        title = '上下黑边内显示字幕',
        hint = bar_hint .. '（\\pos 定位字幕受 mpv 限制保持原位）',
        icon = runtime.bar_fit and 'check_box' or 'check_box_outline_blank',
        value = 'script-message-to uosc_subtitle_style letterbox-toggle',
        active = runtime.bar_fit,
    }
    items[#items + 1] = {
        title = '重新检测上下黑边', hint = '按当前画面重新扫描并立即贴合', icon = 'search',
        value = 'script-message-to uosc_subtitle_style letterbox-refresh',
    }
    items[#items + 1] = {
        title = '恢复默认', hint = '主/次位置 100% · 缩放 ×1.00 · 样式全原样', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style reset',
    }
    return items
end

-- 前向声明：refresh_menu 定义在 open_uosc_menu 之后，却要引用后面才定义的字体选择器
local open_font_picker

local function open_uosc_menu()
    local menu_props = {
        type = 'uosc_subtitle_style',
        title = '内封字幕样式',
        footnote = '主色/字体/描边色含 \\pos 字幕一并生效；字号/描边粗细只作用于普通对白 · 修改即时保存',
        search_style = 'on_demand',
        -- 根级 keep_open 会被所有 item 继承（uosc Menu.lua 第 217 行），
        -- 配合 refresh_menu 的 update-menu，点击后可连续调整并实时看到选中态。
        keep_open = true,
        items = build_items(),
    }
    local json = utils.format_json(menu_props)
    local open_type = mp.get_property_native('user-data/uosc/menu/type')
    local cmd = 'open-menu'
    if open_type ~= nil and tostring(open_type) == 'uosc_subtitle_style' then cmd = 'update-menu' end
    mp.commandv('script-message-to', 'uosc', cmd, json)
end

-- 样式改动后刷新已打开的菜单（uosc 的 update-menu 会保留 selected_index/scroll_y/search）。
-- 仅在本脚本的菜单处于打开态时才发消息，避免打扰其它菜单/无 uosc 的降级路径。
refresh_menu = function()
    local t = mp.get_property_native('user-data/uosc/menu/type')
    if t == nil then return end
    local name = tostring(t)
    if name == 'uosc_subtitle_style' then
        open_uosc_menu()
    elseif name == 'uosc_subtitle_style_fonts' then
        open_font_picker(false)
    end
end

-- 本机字体选择器（懒加载枚举；中文/其他分两组；可重新扫描）
open_font_picker = function(force_rescan)
    local data
    if force_rescan then
        font_cache = enumerate_fonts(true)
        data = font_cache
    else
        data = font_data()
    end
    local items = {}
    items[#items + 1] = header('当前' .. track_name() .. '字体：' .. (cur().font or '字幕原样'),
        string.format('本机共 %d 款字体（含中文 %d 款）· 修改自动保存',
            #(data.fonts or {}), #(data.cjk or {})))

    local function add_font_items(list, title, hint)
        if #list == 0 then return end
        items[#items + 1] = section(title)
        for _, name in ipairs(list) do
            items[#items + 1] = {
                title = name, hint = hint, icon = 'text_fields',
                value = menu_cmd('script-message-to', 'uosc_subtitle_style', 'font', name),
                active = (cur().font == name),
            }
        end
    end

    add_font_items(data.cjk or {}, '中文字体（含「中」字字形）', '推荐用于中文字幕')
    local cjk_set, other = {}, {}
    for _, n in ipairs(data.cjk or {}) do cjk_set[n] = true end
    for _, n in ipairs(data.fonts or {}) do
        if not cjk_set[n] then other[#other + 1] = n end
    end
    add_font_items(other, '其他字体（可能无中文字形）', '中文将回退默认字体渲染')

    items[#items + 1] = section('操作')
    items[#items + 1] = {
        title = '恢复字幕原样', hint = '清除字体覆盖', icon = 'undo',
        value = 'script-message-to uosc_subtitle_style font reset',
        active = (cur().font == nil),
    }
    items[#items + 1] = {
        title = '重新扫描本机字体', hint = '字体目录有增减后使用', icon = 'refresh',
        value = 'script-message-to uosc_subtitle_style rescan-fonts',
    }

    local menu_props = {
        type = 'uosc_subtitle_style_fonts',
        title = '选择字体（本机）',
        footnote = '族名按 sfnt name 表解析；选中后对' .. track_name() .. '生效并自动保存',
        search_style = 'on_demand',
        keep_open = true,
        items = items,
    }
    local json = utils.format_json(menu_props)
    local open_type = mp.get_property_native('user-data/uosc/menu/type')
    local cmd = 'open-menu'
    if open_type ~= nil and tostring(open_type) == 'uosc_subtitle_style_fonts' then cmd = 'update-menu' end
    mp.commandv('script-message-to', 'uosc', cmd, json)
end

-- 循环切换目标轨的位置预设（亦用于无 uosc 时的降级）
local function cycle_pos()
    local next_index = 1
    for i, p in ipairs(POS_PRESETS) do
        if p.pos == cur().pos then
            next_index = (i % #POS_PRESETS) + 1
            break
        end
    end
    set_pos(POS_PRESETS[next_index].pos)
end

-- 无 uosc 时的降级：循环切换 + OSD 文本列表
local function fallback_menu()
    if not o.fallback_cycle then return end
    local lines = {'未检测到 uosc，字幕样式降级为循环切换（目标：' .. track_name() .. '）：'}
    for i, p in ipairs(POS_PRESETS) do
        lines[#lines + 1] = string.format('%d. %s（%d）%s', i, p.title, p.pos,
            p.pos == cur().pos and ' ← 当前' or '')
    end
    mp.commandv('show-text', table.concat(lines, '\n'), 6000)
    cycle_pos()
end

local function open_menu()
    if uosc_available then open_uosc_menu() else fallback_menu() end
end

--------------------------------------------------------------------
-- 入口注册
--------------------------------------------------------------------

-- 字体名含空格，消息参数会被 mpv 命令解析拆开 ⇒ 用 varargs 重新拼回
mp.register_script_message('open-menu', open_menu)
mp.register_script_message('cycle', cycle_pos)
mp.register_script_message('target', switch_target)
mp.register_script_message('pos', function(v)
    local n = tonumber(v)
    if n then set_pos(n) else msg.warn('pos: bad number: ' .. tostring(v)) end
end)
mp.register_script_message('scale', function(v)
    local n = tonumber(v)
    if n then set_scale(n) else msg.warn('scale: bad number: ' .. tostring(v)) end
end)
mp.register_script_message('nudge', function(v)
    local n = tonumber(v)
    if n then set_pos(cur().pos + n) else msg.warn('nudge: bad number: ' .. tostring(v)) end
end)
mp.register_script_message('font', function(...)
    local v = table.concat({...}, ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if v == '' or v == 'reset' then set_font(nil) else set_font(v) end
end)
mp.register_script_message('size', function(v)
    if v == nil or v == 'reset' then set_size(nil) return end
    local n = tonumber(v)
    if n then set_size(n) else msg.warn('size: bad number: ' .. tostring(v)) end
end)
mp.register_script_message('bold', function(v)
    if v == 'on' or v == '1' or v == 'yes' then set_bold(true)
    elseif v == 'off' or v == '0' or v == 'no' then set_bold(false)
    elseif v == 'reset' or v == nil or v == '' then set_bold(nil)
    else msg.warn('bold: bad value: ' .. tostring(v)) end
end)
mp.register_script_message('outline', function(v)
    if v == nil or v == 'reset' then set_outline(nil) return end
    local n = tonumber(v)
    if n then set_outline(n) else msg.warn('outline: bad number: ' .. tostring(v)) end
end)
-- 兼容不带 # 的 6 位 hex：input.conf 里写 `color FFFFFF` 不会被 mpv 当注释吞掉
local function normalize_color_arg(v)
    v = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if v:match('^%x%x%x%x%x%x$') then v = '#' .. v end
    return v
end
mp.register_script_message('outline-color', function(...)
    local v = normalize_color_arg(table.concat({...}, ' '))
    if v == '' or v == 'reset' then set_outline_color(nil) else set_outline_color(v) end
end)
mp.register_script_message('color', function(...)
    local v = normalize_color_arg(table.concat({...}, ' '))
    if v == '' or v == 'reset' then set_color(nil) else set_color(v) end
end)
mp.register_script_message('preset-apply', function() apply_preset(false, false) end)
mp.register_script_message('preset-save', function()
    local t = cur()
    preset.color = t.color or preset.color
    preset.outline_color = t.outline_color or preset.outline_color
    preset.outline = t.outline or preset.outline
    preset.font = t.font
    preset.size = t.size
    preset.bold = t.bold
    save_preset()
    flash_tl(string.format('预设已保存并缓存：%s / 描边 %s / 粗细 %g',
        preset.color, preset.outline_color, preset.outline), 4000)
end)
mp.register_script_message('preset-toggle-colored', function()
    preset.only_colored = not preset.only_colored
    save_preset()
    flash(preset.only_colored and '仅彩色/灰色字幕时套用：开' or '仅彩色/灰色字幕时套用：关')
end)
mp.register_script_message('toggle-gray', function()
    runtime.include_gray = not runtime.include_gray
    flash(runtime.include_gray and '灰色字幕自动转黑白：开' or '灰色字幕自动转黑白：关')
end)
mp.register_script_message('toggle-all', function()
    runtime.override_all = not runtime.override_all
    -- 开关直接决定列表里有没有 PrimaryColour/FontName，必须重新应用一次
    apply_all(true, true)
    flash(runtime.override_all and '顶部/定位字幕一并改样式：开（主/次轨同变）'
        or '顶部/定位字幕一并改样式：关（只改普通对白，保持分轨）')
end)
mp.register_script_message('letterbox-toggle', function()
    runtime.bar_fit = not runtime.bar_fit
    if runtime.bar_fit then
        local fit = refresh_barfit()
        flash(fit and string.format('上下黑边内显示字幕：开（黑边 上%.1f%% / 下%.1f%% · 限缩 ×%.2f）',
            fit.top * 100, fit.bottom * 100, fit.scale)
            or '上下黑边内显示字幕：开（当前画面未检测到上下黑边）')
    else
        disable_barfit()
        apply_all(false)
        flash('上下黑边内显示字幕：关（已还原默认位置与边距）')
    end
end)
mp.register_script_message('letterbox-refresh', function()
    if not runtime.bar_fit then
        flash('上下黑边贴合未开启，请先打开开关')
        return
    end
    local fit = refresh_barfit()
    flash(fit and string.format('已贴合上下黑边（上%.1f%% / 下%.1f%% · 限缩 ×%.2f）',
        fit.top * 100, fit.bottom * 100, fit.scale)
        or '未检测到上下黑边，保持 mpv 默认位置')
end)
mp.register_script_message('preset-toggle-dual', function()
    preset.skip_dual = not preset.skip_dual
    save_preset()
    flash(preset.skip_dual and '双语字幕（双轨）时保持原样：开' or '双语字幕（双轨）时也套用预设')
end)
mp.register_script_message('preset-toggle-enabled', function()
    preset.enabled = not preset.enabled
    save_preset()
    flash(preset.enabled and '载入时自动套用预设：开' or '载入时自动套用预设：关')
end)
mp.register_script_message('preset-reset', function()
    preset = preset_from_options()
    save_preset()
    flash('预设已恢复出厂值')
end)
mp.register_script_message('inspect', function()
    inspect_done = false      -- 手动重检：无视「本文件已检测过」守卫
    inspect_attempts = 0
    inspect_total = 0         -- 手动重检：重置总额度，确保不被硬上限拦住
    run_inspect(nil, false)   -- 手动重检不进入重试循环
end)
mp.register_script_message('style-preset', set_style_preset)
mp.register_script_message('open-fonts', function()
    flash('正在扫描本机字体…')
    if uosc_available then open_font_picker(false) end
end)
mp.register_script_message('rescan-fonts', function()
    flash('正在重新扫描本机字体…')
    if uosc_available then open_font_picker(true) end
end)
mp.register_script_message('reset', reset_style)
mp.register_script_message('fix-override', fix_override)
mp.register_script_message('uosc-version', function() uosc_available = true end)

--------------------------------------------------------------------
-- 生命周期：每个文件加载后重新应用（mpv.conf reset-on-next-file 会重置属性）
--------------------------------------------------------------------

load_state()
load_preset()

-- 预填「本脚本写入值」= 初始值，使观察器的首次回调成为 no-op
for prop, v in pairs(initial_props) do expected_value[prop] = v end

-- 外部改动采纳（用户 r/t 键位、其它脚本、配置文件）
mp.observe_property('sub-pos', 'number', adopt_external('sub-pos', 'main', 'pos'))
mp.observe_property('sub-scale', 'number', adopt_external('sub-scale', 'main', 'scale'))
mp.observe_property('secondary-sub-pos', 'number',
    adopt_external('secondary-sub-pos', 'sec', 'pos'))
mp.observe_property('secondary-sub-scale', 'number',
    adopt_external('secondary-sub-scale', 'sec', 'scale'))

-- 第一句对白渲染出来即触发检测：内封字幕片头常无对白，inspect_delay 后的首检会采空；
-- 用户需求「按第一句底部对话字幕开始识别」——sub-text 由空转非空即是第一句对白出现。
-- inspect_armed：首检(inspect_delay)跑过才触发，避免对白刚渲染就提前检测、抢在 inspect_delay
-- 之前（守住「先看到原字幕、再转黑白」的时序）。inspect_done：检测成功后不再随每句对白重跑。
mp.observe_property('sub-text', 'string', function(_, val)
    if inspect_done or not inspect_armed then return end
    local is_empty = not (type(val) == 'string' and val ~= '')
    local new_segment = (not is_empty) and sub_text_was_empty
    sub_text_was_empty = is_empty
    if is_empty then return end
    -- 新一段对白开始（片头结束进正片、或 seek 到有字幕处后的第一句）：刷新重试额度。
    -- 否则片头/片尾无对白时首轮额度（inspect_retries）会被耗尽，此处再检时额度已满，
    -- 采样一次失败就永久放弃——表现为「拖动进度到正片后，彩色字幕既不识别也不转黑白」。
    if new_segment and inspect_total < INSPECT_TOTAL_CAP then
        inspect_attempts = 0
    end
    run_inspect()
end)

-- end-file 期间 mpv 会按 reset-on-next-file 重置 sub-pos/sub-scale，
-- 那不是用户意图 ⇒ 打开窗口期禁止采纳，file-loaded 应用完再关闭。
-- sub-margin-y 不在该重置列表里，必须在这里显式还原，否则黑边贴合会跨文件泄漏。
mp.register_event('end-file', function()
    in_reset_window = true
    barfit_gen = barfit_gen + 1
    disable_barfit()
end)

-- 启动即应用一次：让 style-overrides 列表在任何字幕轨初始化**之前**就位
-- （该列表只在解码器 init 时读取）
apply_all(false)

mp.register_event('file-loaded', function()
    -- 自动预设只对彩色字幕生效，不跨文件泄漏：先清除上个文件由「彩色检测」写入的
    -- 样式（auto=true），使新文件从「字幕原样」起；随后 run_inspect 若判定彩色再套用。
    -- 附带好处：清除后内封字幕的像素检测能看到原配色，不被上一处 force+白字干扰而漏检。
    clear_auto_style(state.main)
    clear_auto_style(state.sec)
    layout = compute_layout()   -- CN+JP 双语自动布局（per-file；非中日双语为 nil）
    apply_all(false)
    -- 每个文件重新检测：gen++ 作废上个文件遗留的检测链；首检在 inspect_delay 后，
    -- 字幕未就绪（未加载/片头无对白）则由 sub-text 观察器（第一句对白出现即触发）
    -- 与有界重试兜底，直到检出或超过 inspect_retries 次。
    inspect_gen = inspect_gen + 1
    inspect_done = false
    inspected_internal = {}     -- v1.0.8：新文件重置逐轨检查账本
    inspect_attempts = 0
    inspect_total = 0           -- 新文件的累计尝试额度（硬上限，见 INSPECT_TOTAL_CAP）
    sub_text_was_empty = true   -- 新文件首句对白视为「新一段」
    inspect_armed = false       -- 首检跑过才允许 sub-text 观察器触发，避免提前于 inspect_delay
    local gen = inspect_gen
    mp.add_timeout(o.inspect_delay or 1.2, function()
        inspect_armed = true
        run_inspect(gen)
    end)
    -- 黑边检测在样式报告之后跑：报告显示 6s，refresh_barfit 内部会在
    -- OSD 微扰重绘后把报告补回来（见 last_report_text）。
    barfit_gen = barfit_gen + 1
    local bgen = barfit_gen
    mp.add_timeout((o.inspect_delay or 1.2) + (o.letterbox_delay or 0.6), function()
        if bgen ~= barfit_gen then return end
        if runtime.bar_fit then refresh_barfit() end
    end)
end)
-- v1.0.8「所有的内封字幕都要被检查」：
--   旧逻辑一个文件只检测一次（inspect_done=true 后不再重检），文件里其它内封轨
--   （简体/繁体/英文/注释 signs 轨）用户切换过去时永远不会被检查、也不会套用样式。
--   这里按轨放行：切到尚未检查过的内封轨时重置一次性守卫，重新跑检测。
--   已检查过的轨直接跳过，避免来回切轨反复截图；inspect_armed 防止抢在首检之前；
--   INSPECT_TOTAL_CAP 仍是本文件的总尝试硬上限。
local function reinspect_internal_track()
    if not o.inspect_all_internal or not inspect_armed then return end
    local id = current_internal_id()
    if not id or inspected_internal[id] then return end
    if inspect_total >= INSPECT_TOTAL_CAP then return end
    inspect_done = false
    inspect_attempts = 0
    sub_text_was_empty = true
    -- 内封像素采样要求「还没被我们的 force 白字覆盖」：切到新轨前先撤掉上一条轨
    -- 的自动预设（只清 auto=true，用户手动设的样式不动），否则 inspect_style
    -- 会因 wants_force 直接放弃采样，新轨看起来「检查过了」其实什么都没采到。
    clear_auto_style(state.main)
    clear_auto_style(state.sec)
    apply_all(false)
    mp.add_timeout(0.1, function() run_inspect() end)
end
mp.observe_property('sid', 'number', function() reinspect_internal_track() end)
mp.observe_property('secondary-sid', 'number', function() reinspect_internal_track() end)

-- playback-restart 覆盖 seek/reload 等造成的重载
mp.register_event('playback-restart', function() apply_all(false) end)

-- 拖动进度后重新给检测一次机会：片头/片尾无对白时首轮重试额度会被耗尽，
-- 之后 seek 到有字幕的正片若不再刷新额度，一次采样失败就永久放弃（即本次 bug）。
-- 0.3s 去抖，避免拖动过程中连续 seek 触发多次采样；inspect_armed 门保证不抢在首检之前。
local seek_rearm_timer = nil
mp.register_event('seek', function()
    if inspect_done or not inspect_armed then return end
    if inspect_total >= INSPECT_TOTAL_CAP then return end
    if seek_rearm_timer then seek_rearm_timer:kill() end
    seek_rearm_timer = mp.add_timeout(0.3, function()
        seek_rearm_timer = nil
        if inspect_done or inspect_total >= INSPECT_TOTAL_CAP then return end
        inspect_attempts = 0        -- 刷新重试额度
        run_inspect()               -- 立即再检；采样失败则按新额度继续重试
    end)
end)

msg.info(string.format('sub-style loaded (target=%s pos=%d scale=%.2f persist=%s) %s',
    state.target, state.main.pos, state.main.scale, tostring(o.persist), style_desc()))
