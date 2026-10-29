-- sub-style-probe-preset-save.lua —— 预设「可修改并缓存」真机探针
-- 时序：file-loaded +1.5s（避开 1.2s 的自动检测）改当前轨样式
--       → preset-save → 读 ~~/uosc-subtitle-style-preset.json 断言落盘内容。
-- 用白色 fixture 驱动（不触发自动套用，排除竞态）。
-- 输出：PROBE PASS/FAIL <用例> <细节>，最后汇总退出。

local phase = 0
local pass, fail = 0, 0
local failures = {}

local function record(name, ok, detail)
    if ok then pass = pass + 1 else
        fail = fail + 1
        failures[#failures + 1] = name
    end
    print(string.format('PROBE %s %s%s', ok and 'PASS' or 'FAIL', name,
        detail and (' | ' .. tostring(detail)) or ''))
end

local function after(sec, fn)
    mp.add_timeout(sec, function() fn() end)
end

mp.register_event('file-loaded', function()
    if phase == 0 then
        phase = 1
        after(1.5, function()
            mp.commandv('script-message-to', 'uosc_subtitle_style', 'color', '#FF00FF')
            mp.commandv('script-message-to', 'uosc_subtitle_style', 'outline-color', '#00FF00')
            mp.commandv('script-message-to', 'uosc_subtitle_style', 'outline', '4')
            after(0.8, function()
                mp.commandv('script-message-to', 'uosc_subtitle_style', 'preset-save')
                after(0.8, function()
                    local path = mp.command_native({'expand-path', '~~/uosc-subtitle-style-preset.json'})
                    local f = path and io.open(path, 'rb')
                    local content = f and f:read('*a')
                    if f then f:close() end
                    record('preset-file-written', content ~= nil
                        and content:lower():find('ff00ff', 1, true) ~= nil
                        and content:lower():find('00ff00', 1, true) ~= nil
                        and content:find('"outline":4', 1, true) ~= nil,
                        content or '(nil)')
                    -- 保存后当前轨样式应仍是刚设的值（save 不得反向覆盖 state）
                    record('preset-save-keeps-current',
                        tostring(mp.get_property('sub-color') or ''):lower():find('ff00ff', 1, true) ~= nil
                        and math.abs(mp.get_property_number('sub-outline-size', -1) - 4) < 0.01,
                        'sub-color=' .. tostring(mp.get_property('sub-color'))
                        .. ' outline=' .. tostring(mp.get_property_number('sub-outline-size', -1)))
                    print(string.format('PROBE SUMMARY pass=%d fail=%d %s', pass, fail,
                        fail == 0 and 'ALL_OK' or ('FAILED: ' .. table.concat(failures, ','))))
                    mp.command('quit')
                end)
            end)
        end)
    end
end)

print('PROBE driver(preset-save) loaded')
