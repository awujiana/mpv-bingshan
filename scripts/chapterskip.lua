--[[
  * chapterskip.lua v.2026-04-30
  *
  * AUTHORS: po5, detuur, microraptor, Eisa01, allecsc, dyphire
  * License: MIT
  * link: https://github.com/dyphire/mpv-scripts
  *
  * This script skips to the next silence in the file. The
  * intended use for this is to skip until the end of an
  * opening sequence, at which point there's often a short
  * period of silence.
  *
  * You can change this by adding
  * the following line to your input.conf:
  *     KEY script-binding skip-to-silence
  *
  * In order to tweak the script parameters, you can place the
  * text below, between the template markers, in a new file at
  * script-opts/chapterskip.conf in mpv's user folder. The
  * parameters will be automatically loaded on start.
  *
  * Dev note about the used filters:
  * - `silencedetect` is an audio filter that listens for silence and
  * emits text output with details whenever silence is detected.
  * Filter documentation: https://ffmpeg.org/ffmpeg-filters.html
****************** TEMPLATE FOR chapterskip.conf ******************
#--(#number). Maximum amount of noise to trigger, in terms of dB. Lower is more sensitive.
silence_audio_level=-40

#--(#number). Duration of the silence that will be detected to trigger skipping.
silence_duration=0.7

#--(0/#number). The first detcted silence_duration will be ignored for the defined seconds in this option, and it will continue skipping until the next silence_duration.
# (0 for disabled, or specify seconds).
ignore_silence_duration=1

#--(0/#number). Minimum amount of seconds accepted to skip until the configured silence_duration.
# (0 for disabled, or specify seconds)
min_skip_duration=0

#--(0/#number). Maximum amount of seconds accepted to skip until the configured silence_duration.
# (0 for disabled, or specify seconds)
max_skip_duration=120

#--(yes/no). Default is muted, however if audio was enabled due to custom mpv settings, the fast-forwarded audio can sound jarring.
force_mute_on_skip=no

#--(yes/no). Enable position-based inference for chapters (opening/ending detection for videos with chapters)
enable_position_inference=yes

#--(yes/no). Enable position-based inference for history entries in non-chapter files
# When disabled, history entries will show generic "Skip Segment" instead of "Skip Opening/Ending"
# Useful to prevent false positives in non-episodic content
enable_history_position_inference=yes

#--(#number). Time window (in seconds) from the start to consider as intro/opening area
intro_time_window=200

#--(#number). Time window (in seconds) from the end to consider as outro/ending area
outro_time_window=300

************************** END OF TEMPLATE **************************
--]]

local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'
local options = require "mp.options"
local utils = require 'mp.utils'

local categories = {
    prologue = "^[Pp]rologue/^[Ii]ntro",
    opening = "^OP/ OP$/^[Oo]pening/[Oo]pening$/^Intro%s*Start/オープニング$/^片头$/片头开始$",
    ending = "^ED/ ED$/^[Ee]nding/[Ee]nding$/エンディング$",
    credits = "^[Cc]redits/[Cc]redits$",
    preview = "[Pp]review$"
}

local o = {
    mode = "manual",
    -- eng=English, chs=Chinese Simplified
    language = 'eng',
    timeout = 20,
    categories = "",
    skip = "",
    enable_position_inference = true,
    enable_history_position_inference = false,
    intro_time_window = 200,
    outro_time_window = 300,
    silence_audio_level = -40,
    silence_duration = 0.7,
    ignore_silence_duration=1,
    min_skip_duration = 0,
    max_skip_duration = 120,
    force_mute_on_skip = false,
    history_path = "~~/chapterskip_history.json",
    -- Button styling
    button_font_size = 24,
    button_padding_x = 20,
    button_padding_y = 15,
    button_margin = 60,
    button_border = 2,
    button_radius = 13,
    -- Button colors (BGR format: BBGGRR)
    button_progress_color = "2442F4",
    button_progress_hover_color = "2442F4",
    button_remaining_color = "FFFFFF",
    button_remaining_hover_color = "111111",
    button_text_color = "000000",
    button_text_hover_color = "FFFFFF",
    button_border_color = "FFFFFF",
}

options.read_options(o, _, function() end)

local speed_state = 1
local pause_state = false
local mute_state = false
local sub_state = nil
local secondary_sub_state = nil
local vid_state = nil
local geometry_state = nil
local skip_flag = false
local initial_skip_time = 0
local state = {}
local skipped = {}
local parsed = {}
local chapter_skip = {}
local active_skips = {}
local skip_prompt_queue = {}
local skip_timer = nil
local history_path = mp.command_native({ "expand-path", o.history_path })

local locals = {
    ['eng'] = {
        skip_detected = 'Skip Segment',
        auto_skip     = 'Auto-skip: %s-%s',
        chapter_mode  = 'Chapter skip mode: ',
        mark_fragment_empty = 'Mark fragment is empty',
        mark_start_pos = 'Marked %s as start position',
        mark_fragment = 'Mark skip fragment: %s-%s',
        no_audio = 'No audio stream detected',
        skipped_to_silence = 'Skipped to silence at %s',
        skip_cancel_min = 'Skipping Cancelled - Silence is less than configured minimum',
        skip_cancel_max = 'Skipping Cancelled - Silence is more than configured maximum',
        failed_timestamp = 'Failed to get timestamp'
    },
    ['chs'] = {
        skip_detected = '跳过片段',
        auto_skip     = '已跳过: %s-%s',
        chapter_mode  = '跳过章节模式: ',
        mark_fragment_empty = '标记片段为空',
        mark_start_pos = '标记 %s 为起始位置',
        mark_fragment = '标记跳过片段: %s-%s',
        no_audio = '未检测到音频流',
        skipped_to_silence = '已跳过到静音点 %s',
        skip_cancel_min = '取消跳过 - 静音时长低于最小值',
        skip_cancel_max = '取消跳过 - 静音时长超过最大值',
        failed_timestamp = '获取时间戳失败'
    }
}

local texts = locals[o.language] or locals['eng']

local function is_protocol(path)
    return type(path) == "string" and (path:find("^%a[%w.+-]-://") ~= nil or path:find("^%a[%w.+-]-:%?") ~= nil)
end

local function hex_to_char(x)
    return string.char(tonumber(x, 16))
end

local function url_decode(str)
    if str ~= nil then
        str = str:gsub('^%a[%a%d-_]+://', '')
              :gsub('^%a[%a%d-_]+:\\?', '')
              :gsub('%%(%x%x)', hex_to_char)
        if str:find('://localhost:?') then
            str = str:gsub('^.*/', '')
        end
        str = str:gsub("%?.+", ""):gsub("%+", " ")
        local last_pos = str:match('.*[\\/:%?]()')
        if last_pos then
            str = str:sub(last_pos)
        end
    end
    return str
end

local function timestamp(duration)
    local hours = math.floor(duration / 3600)
    local minutes = math.floor(duration % 3600 / 60)
    local seconds = duration % 60
    return string.format("%02d:%02d:%06.3f", hours, minutes, seconds)
end

local function normalize(path)
    if normalize_path ~= nil then
        if normalize_path then
            path = mp.command_native({"normalize-path", path})
        else
            local directory = mp.get_property_native("working-directory", "")
            path = utils.join_path(directory, path:gsub('^%.[\\/]',''))
            if platform == "windows" then path = path:gsub("\\", "/") end
        end
        return path
    end

    normalize_path = false

    local commands = mp.get_property_native("command-list", {})
    for _, command in ipairs(commands) do
        if command.name == "normalize-path" then
            normalize_path = true
            break
        end
    end
    return normalize(path)
end

local function get_parent_dir(path)
    local dir = nil
    if path and not is_protocol(path) then
        path = normalize(path)
        dir = utils.split_path(path)
    end
    return dir
end

local function split_by_numbers(filename)
    local parts = {}
    local pattern = "([^%d]*)(%d+)([^%d]*)"
    for pre, num, post in string.gmatch(filename, pattern) do
        table.insert(parts, {pre = pre, num = tonumber(num), post = post})
    end
    return parts
end

local function compare_filenames(fname1, fname2)
    local parts1 = split_by_numbers(fname1)
    local parts2 = split_by_numbers(fname2)

    local min_len = math.min(#parts1, #parts2)

    for i = 1, min_len do
        local part1 = parts1[i]
        local part2 = parts2[i]

        if part1.pre ~= part2.pre then
            return false
        end

        if part1.num ~= part2.num then
            return part1.num, part2.num
        end

        if part1.post ~= part2.post then
            return false
        end
    end

    return false
end

-- Read config file
local function read_config(file_path)
    local file = io.open(file_path, "r")
    if not file then
        return {}
    end
    local content = file:read("*a")
    file:close()
    return utils.parse_json(content)
end

-- Write config file
local function write_config(file_path, data)
    local file = io.open(file_path, "w")
    if not file then
        return
    end
    file:write(utils.format_json(data))
    file:close()
end

-- Write history file
local function write_history(path)
    local dir = get_parent_dir(path)
    local fname = mp.get_property("filename")
    local title = mp.get_property_native("media-title"):gsub("%.[^%.]+$", "")
    local duration = mp.get_property_native("duration")
    if is_protocol(fname) then
        title = url_decode(title)
        fname = title
    end

    if not dir then
        local media_title, season, episode = title:match("^(.-)%s*[sS](%d+).-[eE](%d+)")
        if season then
            dir = (media_title ~= "" and media_title or title) .. " S" .. season
        else
            dir = media_title ~= "" and media_title or title
        end
    end

    local history = read_config(history_path) or {}
    history[dir] = {}
    history[dir].fname = fname
    history[dir].chapterskip = chapter_skip
    history[dir].duration = duration
    write_config(history_path, history)
end

local function format_message(msg, color)
    return string.format("{\\1c&H%s&}%s", color, msg)
end

-- Send a message to the OSD
message_overlay = mp.create_osd_overlay('ass-events')
message_timer = mp.add_timeout(1, function ()
    message_overlay:remove()
end, true)

local function show_message(msg, time, color)
    local text = color and format_message(msg, color) or msg
    message_timer:kill()
    message_timer.timeout = time or 1
    message_overlay.data = text
    message_overlay:update()
    message_timer:resume()
end

local function info(s)
    msg.info(s)
    show_message(s, 2)
end

-- ── 按钮 UI ──────────────────────────────────────────────────────────
-- 2026-10-05：改用通用件 script-modules/osd-button.lua
--
-- 改造原因（原实现存在「重算漂移」）：
--   旧 render_button() 自己算一遍 button_x/button_y 用于绘制；
--   命中判定用的却是另存的 button_state.mouse_hover —— 而这个布尔值
--   又是在**同一次 render 里**用同一批局部变量算出来的，看似同源，
--   实则依赖「render 一定先于判定发生」。一旦鼠标事件早于 render
--   （例如 show 后立刻点击、或 osd-dimensions 尚未就绪），
--   mouse_hover 仍是上一帧的陈旧值 → 出现「看得见点不着」。
--
--   更根本的问题是**尺寸估算分散**：文字宽度按 #message * font_size * 0.6
--   估算，一旦字体度量与估算不符，绘制与判定都会偏，且无处对账。
--
--   新实现把「算矩形」这件事**唯一化**到 osd-button 内部：
--   渲染时写入 self._hit_rect，命中判定只读它，不再有第二处计算。

local osd_button = require 'osd-button'

-- 供内联命令（chapterskip-* script-message）查询的按钮对象
local prompt_button = nil

-- 保留这些名字以兼容既有调用点（cancel_skip_prompt / show_skip_prompt 等）
local hide_button
local render_button
local bind_button_click
local unbind_button_click

-- 把 o.* 的按钮样式映射到 osd-button 的 style 表
local function button_style()
    return {
        font_size   = o.button_font_size,
        padding_x   = o.button_padding_x,
        padding_y   = o.button_padding_y,
        margin      = o.button_margin,
        border      = o.button_border,
        radius      = o.button_radius,
        line_spacing = 0.1,
        -- chapterskip 用进度条模式：底槽=remaining，已用=progress
        bg          = o.button_remaining_color,
        bg_hover    = o.button_remaining_hover_color,
        fg          = o.button_text_color,
        fg_hover    = o.button_text_hover_color,
        border_color = o.button_border_color,
        progress_bg = o.button_remaining_color,
        progress_bg_hover = o.button_remaining_hover_color,
        progress_fg = o.button_progress_color,
        progress_fg_hover = o.button_progress_hover_color,
    }
end

-- 旧的全局 button_state 仍被少量外部代码引用（on_unload 等）。
-- 保留一个只读投影，避免大范围改动调用点。
local button_state = {
    visible = false,
    message = "",
    mouse_hover = false,
    -- 倒计时与动作仍由本脚本维护（osd-button 不关心业务语义）
    countdown_timer = nil,
    countdown_remaining = 0,
    countdown_total = 0,
    action = nil,
    skip_obj = nil,
}

local function sync_button_state()
    if prompt_button then
        button_state.visible = prompt_button:is_visible()
        button_state.mouse_hover = prompt_button:is_hovered()
    else
        button_state.visible = false
        button_state.mouse_hover = false
    end
end

-- 进度计算：与倒计时联动
local function current_progress()
    if not o or o.timeout <= 0 then return nil end
    local total = button_state.countdown_total or 0
    local rem = button_state.countdown_remaining or 0
    if total <= 0 then return nil end
    local p = 1 - (rem / total)
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    return p
end

-- 渲染：改为「更新已有按钮的文本与进度」，几何计算全部交给 osd-button
render_button = function()
    if not prompt_button or not prompt_button:is_visible() then
        return
    end
    prompt_button:set_text(button_state.message, "[y/n]")
    prompt_button:set_progress(current_progress())
    sync_button_state()
end


-- Bind/unbind button click
-- 2026-10-05：不再读 button_state.mouse_hover（那是上一帧的陈旧值，
-- 且依赖 render 先于判定发生）。改为问 osd-button 的 _hit_rect，
-- 它由渲染过程唯一写入，是当前帧的权威矩形。
bind_button_click = function()
    mp.add_forced_key_binding("MBTN_LEFT", "chapterskip-button-click", function()
        local pos = mp.get_property_native("mouse-pos")
        if not pos then return end

        local consumed = false
        if prompt_button then
            consumed = prompt_button:on_mouse_click(pos.x, pos.y)
        end

        if consumed then
            -- 命中按钮：动作已由 on_click 回调执行，这里只负责收起
            hide_button()
        else
            -- 点在按钮外 —— 取消
            hide_button()
        end
    end)
end

unbind_button_click = function()
    mp.remove_key_binding("chapterskip-button-click")
end

-- Hide button
hide_button = function()
    if button_state.countdown_timer then
        button_state.countdown_timer:kill()
        button_state.countdown_timer = nil
    end

    button_state.visible = false
    button_state.message = ""
    button_state.action = nil
    button_state.skip_obj = nil
    button_state.countdown_remaining = 0
    button_state.countdown_total = 0
    button_state.mouse_hover = false

    if prompt_button then
        prompt_button:hide()
    end

    unbind_button_click()

    -- Remove keyboard shortcuts
    mp.remove_key_binding("chapterskip-confirm")
    mp.remove_key_binding("chapterskip-cancel")
end

-- Show button with countdown
local function show_button(message, action, skip_obj)
    hide_button()  -- Clear any existing button

    button_state.visible = true
    button_state.message = message
    button_state.action = action
    button_state.skip_obj = skip_obj
    button_state.countdown_remaining = o.timeout
    button_state.countdown_total = o.timeout

    -- 2026-10-05：由 osd-button 创建/复用按钮实例。
    -- 复用同一个实例（而非每次 new），可避免反复创建 overlay 与订阅；
    -- 且实例内部持有 _hit_rect，复用才能保证「存矩形→读矩形」持续有效。
    if not prompt_button then
        prompt_button = osd_button.new({
            anchor  = "bottom-right",
            label   = message,
            hint    = "[y/n]",
            z       = 2000,
            style   = button_style(),
            -- 点击回调直接执行动作（命中判定由 osd-button 负责）
            on_click = function()
                if button_state.action then
                    button_state.action()
                end
            end,
        })
    else
        prompt_button:set_text(message, "[y/n]")
        prompt_button:set_enabled(true)
    end

    render_button()
    prompt_button:show()

    bind_button_click()

    -- Add keyboard shortcuts for confirm/cancel
    mp.add_forced_key_binding("y", "chapterskip-confirm", function()
        if button_state.action then
            button_state.action()
        end
        hide_button()
    end)

    mp.add_forced_key_binding("n", "chapterskip-cancel", function()
        if button_state.skip_obj then
            button_state.skip_obj.cancelled = true
        end
        hide_button()
    end)

    if o.timeout > 0 then
        button_state.countdown_timer = mp.add_periodic_timer(1, function()
            button_state.countdown_remaining = button_state.countdown_remaining - 1
            if button_state.countdown_remaining <= 0 then
                if skip_obj then skip_obj.cancelled = true end
                hide_button()
            else
                render_button()
            end
        end)
    end
end

-- 2026-10-05：原先此处注册裸的 mouse-pos observer，每次移动都全量 render。
-- 现改为由 osd-button 内部的**共享订阅**驱动悬停反馈（且只在 hover 翻转时重绘），
-- 不再需要本脚本自行订阅。见 script-modules/osd-button.lua 的 _start_mouse_observer。

-- Check if chapter matches skip pattern (title-based or position-based)
local function matches(i, title, chapter_time, chapter_duration, total_chapters, duration)
    -- First, try title-based matching
    for category in string.gmatch(o.skip, " *([^;]*[^; ]) *") do
        if categories[category:lower()] then
            if string.find(category:lower(), "^idx%-") == nil then
                if title then
                    for pattern in string.gmatch(categories[category:lower()], "([^/]+)") do
                        if string.match(title, pattern) then
                            return true, "title", category:lower()
                        end
                    end
                end
            else
                for pattern in string.gmatch(categories[category:lower()], "([^/]+)") do
                    if tonumber(pattern) == i then
                        return true, "index", category:lower()
                    end
                end
            end
        end
    end

    -- If no title match and position inference is enabled, check position
    if o.enable_position_inference and chapter_time and chapter_duration and total_chapters and duration then
        -- Check chapter duration constraints (80-100 seconds)
        if chapter_duration >= 80 and chapter_duration <= 100 then
            -- Only consider chapters at the beginning or end
            if i <= 2 or i >= total_chapters - 1 then
                -- Check if chapter time is within the intro/outro windows
                if i <= math.ceil(total_chapters / 2) then
                    -- First half: check for opening
                    if chapter_time < o.intro_time_window then
                        -- Check if opening category is in skip list
                        for category in string.gmatch(o.skip, " *([^;]*[^; ]) *") do
                            if category:lower() == "opening" then
                                return true, "position-opening", "opening"
                            end
                        end
                    end
                else
                    -- Second half: check for ending
                    if duration > 0 and chapter_time >= (duration - o.outro_time_window) then
                        -- Check if ending category is in skip list
                        for category in string.gmatch(o.skip, " *([^;]*[^; ]) *") do
                            if category:lower() == "ending" then
                                return true, "position-ending", "ending"
                            end
                        end
                    end
                end
            end
        end
    end

    return false, nil, nil
end

local function add_chapter_skip(s)
    for _, exist in ipairs(chapter_skip) do
        if math.abs(exist.start - s.start) <= 0.5 and math.abs(exist.ended - s.ended) <= 0.5 then
            return
        end
    end
    table.insert(chapter_skip, s)
end

local function cache_skip()
    local chapters = mp.get_property_native("chapter-list") or {}
    local matched = false

    for i, chapter in ipairs(chapters) do
        local start_time = chapters[i - 1] and chapters[i - 1].time or 0
        local duration = chapter.time - start_time
        if math.abs(chapter.time - state.ended) <= 10 and duration <= 120 then
            matched = true
            msg.verbose("Chapter skip found: " .. (chapter.title or ("Chapter "..i)))
            add_chapter_skip({
                start = start_time,
                ended = chapter.time,
            })
        end
    end

    if not matched then
        if state.start > 100 or state.ended - state.start > 120 then
            return
        elseif state.start <= 30 then
            state.start = 0
        end
        add_chapter_skip({
            start = state.start,
            ended = state.ended,
        })
    end
end

function cancel_skip_prompt()
    hide_button()

    if #skip_prompt_queue > 0 then
        local next_prompt = table.remove(skip_prompt_queue, 1)
        show_skip_prompt(next_prompt.action, next_prompt.skip_obj)
    end
end

function confirm_skip_prompt(action)
    cancel_skip_prompt()
    if action then action() end
end

function show_skip_prompt(action, skip_obj)
    if button_state.visible then
        table.insert(skip_prompt_queue, {action = action, skip_obj = skip_obj})
        return
    end

    -- Generate message based on category
    local message = texts.skip_detected
    if skip_obj and skip_obj.category then
        if o.language == "chs" then
            -- Chinese category names with Chinese "跳过" prefix
            local category_names = {
                opening = "片头",
                ending = "片尾",
                credits = "Staff",
                prologue = "序章",
                preview = "预告"
            }
            local category_display = category_names[skip_obj.category] or skip_obj.category
            message = "跳过" .. category_display
        else
            local category_display = skip_obj.category:gsub("^%l", string.upper)
            message = "Skip " .. category_display
        end
    end

    show_button(message, action, skip_obj)
end

local function start_skip_watcher()
    if skip_timer then return end
    skip_timer = mp.add_periodic_timer(0.5, function()
        local t = mp.get_property_number("time-pos")
        local paused = mp.get_property_native("pause")
        if not t or o.mode == "none" or paused then return end

        local i = 1
        while i <= #active_skips do
            local s = active_skips[i]
            if s.cancelled then
                table.remove(active_skips, i)
            elseif t >= s.start - 0.5 and t <= s.ended then
                if o.mode == "auto" then
                    info((texts.auto_skip):format(timestamp(s.start), timestamp(s.ended), s.title))
                    mp.set_property_number("time-pos", s.ended)
                    s.triggered = true
                    table.remove(active_skips, i)
                elseif o.mode == "manual" and not s.triggered then
                    s.triggered = true
                    show_skip_prompt(function()
                        info((texts.auto_skip):format(timestamp(s.start), timestamp(s.ended), s.title))
                        mp.set_property_number("time-pos", s.ended)
                        for j = #active_skips, 1, -1 do
                            if active_skips[j] == s then
                                table.remove(active_skips, j)
                                break
                            end
                        end
                    end, s)
                    i = i + 1
                else
                    i = i + 1
                end
            elseif t < s.start - 0.5 then
                if s.triggered then
                    s.cancelled = true
                    table.remove(active_skips, i)
                    cancel_skip_prompt()
                else
                    i = i + 1
                end
            else
                table.remove(active_skips, i)
                cancel_skip_prompt()
            end
        end

        if #active_skips == 0 and skip_timer then
            skip_timer:kill()
            skip_timer = nil
        end
    end)
end

local function add_active_skip(s)
    for _, exist in ipairs(active_skips) do
        if math.abs(exist.start - s.start) <= 0.5 and math.abs(exist.ended - s.ended) <= 0.5 then
            return
        end
    end
    table.insert(active_skips, {
        start = s.start,
        ended = s.ended,
        title = s.title,
        category = s.category,
        triggered = false
    })
    start_skip_watcher()
end

local function chapterskip(_, current)
    if o.mode == "none" then return end
    for category in string.gmatch(o.categories, "([^;]+)") do
        local name, patterns = string.match(category, " *([^+>]*[^+> ]) *[+>](.*)")
        if name then
            categories[name:lower()] = patterns
        elseif not parsed[category] then
            msg.warn("Improper category definition: " .. category)
        end
        parsed[category] = true
    end
    local chapters = mp.get_property_native("chapter-list")
    local duration = mp.get_property_number("duration") or 0
    local total_chapters = #chapters or 0

    if duration <= o.intro_time_window or total_chapters <= 1 then return end

    local matches_info = {}
    for i, chapter in ipairs(chapters) do
        -- Calculate chapter duration
        local chapter_duration = 0
        if chapters[i + 1] then
            chapter_duration = chapters[i + 1].time - chapter.time
        elseif duration > 0 then
            chapter_duration = duration - chapter.time
        end

        local is_match, match_type, category = matches(i, chapter.title, chapter.time, chapter_duration, total_chapters, duration)
        matches_info[i] = {
            is_match = is_match,
            match_type = match_type,
            category = category,
            time = chapter.time,
            chapter = chapter,
            chapter_duration = chapter_duration,
        }
    end

    -- If multiple opening/preview matches exist within intro_time_window, prefer the second one
    local intro_candidates = {}
    for i, info in ipairs(matches_info) do
        if info and info.is_match and info.time and info.time < o.intro_time_window then
            -- consider opening/preview matches or position-based opening
            if info.category == "opening" or info.category == "preview" or info.match_type == "position-opening" then
                table.insert(intro_candidates, i)
            end
        end
    end
    if #intro_candidates >= 2 then
        table.sort(intro_candidates, function(a, b) return a < b end)
        local chosen = intro_candidates[2]
        for _, idx in ipairs(intro_candidates) do
            if idx ~= chosen and matches_info[idx] then
                matches_info[idx].is_match = false
            end
        end
    end

    for i, info in ipairs(matches_info) do
        if info and not skipped[i] and info.is_match then
            if i == current + 1 then
                skipped[i] = true
                local skip_time = chapters[i + 1] and chapters[i + 1].time or mp.get_property_native("duration")
                add_active_skip({
                    start = chapters[i].time,
                    ended = skip_time,
                    title = chapters[i].title,
                    category = info.category,
                })
            end
        end
    end
end

local function check_skip()
    local path = mp.get_property("path")
    if not path then return end

    local chapters = mp.get_property_native("chapter-list") or {}
    local history = read_config(history_path) or {}
    local duration = mp.get_property_number("duration") or 0
    local filename = mp.get_property("filename")
    local file_ext = filename:lower():match("%.([^%.]+)$") or ""
    local title = mp.get_property_native("media-title"):gsub("%.[^%.]+$", "")
    local dir = get_parent_dir(path)

    if duration <= o.intro_time_window then return end

    if is_protocol(filename) then
        title = url_decode(title)
        filename = title
    end

    if not dir then
        local media_title, season, episode = title:match("^(.-)%s*[sS](%d+).-[eE](%d+)")
        if season then
            dir = (media_title ~= "" and media_title or title) .. " S" .. string.format("%02d", tonumber(season))
        else
            dir = media_title ~= "" and media_title or title
        end
    end

    local file_history = history[dir]
    if not file_history or not file_history.chapterskip then return end

    local skip_list = file_history.chapterskip
    local fname = file_history.fname
    local fname_ext = fname:lower():match("%.([^%.]+)$") or ""

    -- Check if it's the same file or a different file in the same directory
    local is_same_file = (fname == filename)

    if (not is_protocol(path) and file_ext ~= fname_ext) or
    (fname ~= filename and not compare_filenames(fname, filename)) then
        return
    end

    table.sort(skip_list, function(a, b) return a.start < b.start end)

    if next(skip_list) == nil then return end
    if next(chapters) == nil then
        -- No chapters: check if we should apply history
        if not o.enable_history_position_inference and not is_same_file then
            return  -- Skip history for non-chapter files when disabled and not the same file
        end

        -- Apply history with category inference (if enabled or same file)
        for _, s in ipairs(skip_list) do
            local category = nil
            if s.start < o.intro_time_window then
                category = "opening"
            elseif duration > 0 and s.start >= (duration - o.outro_time_window) then
                category = "ending"
            end
            add_active_skip({
                start = s.start,
                ended = s.ended,
                title = s.title,
                category = category
            })
        end
        return
    end

    local used_chapters = {}
    for _, s in ipairs(skip_list) do
        for i, chapter in ipairs(chapters) do
            if not used_chapters[i] then
                local start_time = chapter.time
                local end_time   = chapters[i + 1] and chapters[i + 1].time or duration
                if math.abs((end_time - start_time) - (s.ended - s.start)) <= 0.05 then
                    used_chapters[i] = true
                    -- Infer category for chapter-matched skips
                    local category = nil
                    if start_time < o.intro_time_window then
                        category = "opening"
                    elseif duration > 0 and start_time >= (duration - o.outro_time_window) then
                        category = "ending"
                    end
                    add_active_skip({
                        start = start_time,
                        ended = end_time,
                        category = category
                    })
                    break
                end
            end
        end
    end
end

local function toggle_markskip()
    local pos, err = mp.get_property_number("time-pos")
    if not pos then
        show_message(texts.failed_timestamp, 2)
        msg.error("Failed to get timestamp: " .. err)
        return
    end
    if mark_pos then
        local shift, endpos = mark_pos, pos
        if shift > endpos then
            shift, endpos = endpos, shift
        elseif shift == endpos then
            show_message(texts.mark_fragment_empty, 2)
            return
        end
        mark_pos = nil
        state.ended = endpos
        info(string.format(texts.mark_fragment, timestamp(shift), timestamp(endpos)))
        cache_skip()
    else
        mark_pos = pos
        state.start = pos
        info(string.format(texts.mark_start_pos, timestamp(pos)))
    end
end

local function switch_chapterskip()
    if o.mode == "none" then
        o.mode = "auto"
    elseif o.mode == "auto" then
        o.mode = "manual"
    else
        o.mode = "none"
    end

    info(texts.chapter_mode .. o.mode)
end

local function restoreProp(pause)
    if not pause then pause = pause_state end
    local fullscreen = mp.get_property("fullscreen")

    mp.set_property("vid", vid_state)
    if not fullscreen then
        mp.set_property("geometry", geometry_state)
    end
    mp.set_property_bool("mute", mute_state)
    mp.set_property("speed", speed_state)
    mp.unobserve_property(foundSilence)
    mp.command("no-osd af remove @skiptosilence")
    mp.set_property_bool("pause", pause)
    mp.set_property("sub-visibility", sub_state)
    mp.set_property("secondary-sub-visibility", secondary_sub_state)
    if timer then timer:kill() end
    skip_flag = false
end

local function handleMinMaxDuration(timepos)
    if not skip_flag then return end
    if not timepos then timepos = mp.get_property_number("time-pos") end

    skip_duration = timepos - initial_skip_time
    if o.min_skip_duration > 0 and skip_duration <= o.min_skip_duration then
        restoreProp()
        info(texts.skip_cancel_min)
        return true
    end
    if o.max_skip_duration > 0 and skip_duration >= o.max_skip_duration then
        restoreProp()
        info(texts.skip_cancel_max)
        return true
    end
    return false
end

local function skippedMessage()
    state.ended = mp.get_property_native("time-pos")
    cache_skip()
    info(string.format(texts.skipped_to_silence, mp.get_property_osd("time-pos")))
end

function foundSilence(name, value)
    if value == "{}" or value == nil then
        return
    end

    timecode = tonumber(string.match(value, "%d+%.?%d+"))
    if timecode == nil or timecode < initial_skip_time + o.ignore_silence_duration then
        return
    end

    if handleMinMaxDuration(timecode) then return end

    restoreProp()

    mp.add_timeout(0.05, skippedMessage)
    skip_flag = false
end

local function doSkip()
    state.start = mp.get_property_native("time-pos") or 0
    local audio = mp.get_property_number("aid") or 0
    if audio == 0 then
        info(texts.no_audio)
        return
    end
    if skip_flag then return end
    initial_skip_time = state.start
    if math.floor(initial_skip_time) == math.floor(mp.get_property_native('duration') or 0) then return end

    local width = mp.get_property_native("osd-width")
    local height = mp.get_property_native("osd-height")
    local fullscreen = mp.get_property_native("fullscreen")
    geometry_state = mp.get_property("geometry")
    if not fullscreen then
        mp.set_property_native("geometry", ("%dx%d"):format(width, height))
    end

    mp.command(
        "no-osd af add @skiptosilence:lavfi=[silencedetect=noise=" ..
        o.silence_audio_level .. "dB:d=" .. o.silence_duration .. "]"
    )

    mp.observe_property("af-metadata/skiptosilence", "string", foundSilence)

    sub_state = mp.get_property("sub-visibility")
    mp.set_property("sub-visibility", "no")
    secondary_sub_state = mp.get_property("secondary-sub-visibility")
    mp.set_property("secondary-sub-visibility", "no")
    vid_state = mp.get_property("vid")
    mp.set_property("vid", "no")
    mute_state = mp.get_property_native("mute")
    if o.force_mute_on_skip then
        mp.set_property_bool("mute", true)
    end
    pause_state = mp.get_property_native("pause")
    mp.set_property_bool("pause", false)
    speed_state = mp.get_property_native("speed")
    mp.set_property("speed", 100)
    skip_flag = true

    timer = mp.add_periodic_timer(0.5, function()
        local video_time = (mp.get_property_native("time-pos") or 0)
        handleMinMaxDuration(video_time)
    end)
end


mp.observe_property("chapter", "number", chapterskip)
mp.register_event("file-loaded", check_skip)

mp.observe_property('pause', 'bool', function(_, value)
    if value and skip_flag then
        restoreProp(true)
    end
end)

mp.observe_property('percent-pos', 'number', function(_, value)
    if skip_flag and value and value > 99 then
        local fullscreen = mp.get_property("fullscreen")
        mp.set_property("vid", vid_state)
        if not fullscreen then
            mp.set_property("geometry", geometry_state)
        end
    end
end)

mp.add_hook('on_unload', 10, function()
    sync_button_state()
    if button_state.visible then
        cancel_skip_prompt()
    end
    -- 2026-10-05：销毁按钮实例，释放内部共享 mouse-pos 订阅
    if prompt_button then
        prompt_button:destroy()
        prompt_button = nil
    end
    if skip_timer then
        skip_timer:kill()
        skip_timer = nil
    end
    if chapter_skip and next(chapter_skip) ~= nil then
        write_history(mp.get_property("path"))
    end
    state = {}
    parsed = {}
    skipped = {}
    chapter_skip = {}
    active_skips = {}
    skip_prompt_queue = {}
    if skip_flag then
        restoreProp()
    end
end)

mp.register_script_message("chapter-skip", switch_chapterskip)
mp.register_script_message("toggle-markskip", toggle_markskip)
mp.register_script_message("skip-to-silence", doSkip)
