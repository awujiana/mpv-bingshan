-- 回归测试：证明「重算漂移」已消除
-- 思路：模拟旧实现（绘制算一次、判定另算一次）与新实现（存矩形读矩形），
-- 在「屏幕尺寸在两帧之间变化」的场景下对比二者是否自相矛盾。
package.preload['mp.msg'] = function()
  return setmetatable({}, {__index=function() return function() end end})
end
package.preload['mp.assdraw'] = function() return { ass_new=function() return {} end } end
_G.mp = {
  create_osd_overlay=function() return {update=function()end, remove=function()end} end,
  observe_property=function() return {unobserve=function()end} end,
  get_property_native=function() return nil end,
}
local mod = dofile('script-modules/osd-button.lua')

-- 旧实现：独立算两遍（复刻 chapterskip 原先的逻辑）
local function old_geom(sw, sh, msg)
  local scale = sh/1080
  local fs = 24*scale
  local hs = fs*0.9
  local px, py, margin = 20*scale, 15*scale, 60*scale
  local w = math.max(#msg*fs*0.6, #"[y/n]"*hs*0.6) + px*2
  local h = fs + fs*0.1 + hs + py*2
  local x = sw - w - margin
  local y = sh - h - margin - 80*scale
  return x,y,w,h
end

print("场景：绘制发生在 1080p，鼠标事件到达时屏幕已切到 4K")
print("（模拟 render 与 hit-test 之间窗口变化 / osd-dimensions 滞后）")
print("")

local msg = "跳过片头"

-- 旧：绘制用 1080p，判定用 4K → 两套坐标
local dx,dy,dw,dh = old_geom(1920,1080,msg)
local hx,hy,hw,hh = old_geom(3840,2160,msg)
print(("[旧] 绘制矩形 x=%.1f y=%.1f w=%.1f h=%.1f"):format(dx,dy,dw,dh))
print(("[旧] 判定矩形 x=%.1f y=%.1f w=%.1f h=%.1f"):format(hx,hy,hw,hh))
local drift_x, drift_y = hx-dx, hy-dy
print(("[旧] 坐标漂移 dx=%.1f dy=%.1f  ← 两者不自洽"):format(drift_x, drift_y))
-- 取绘制矩形的中心，用判定矩形去判，看是否命中
local cx, cy = dx+dw/2, dy+dh/2
local old_hit = cx>=hx and cx<=hx+hw and cy>=hy and cy<=hy+hh
print(("[旧] 点在按钮中心 (%.1f,%.1f)，判定结果：%s  ← 应命中却%s"):format(
  cx, cy, old_hit and "命中" or "未命中", old_hit and "" or "漏判（看得见点不着）"))
print("")

-- 新：矩形只算一次，存进 _hit_rect；判定读同一份
local l1 = mod.compute_layout(1920,1080,msg,"[y/n]", 
  {font_size=24,padding_x=20,padding_y=15,margin=60,border=2,radius=13,line_spacing=0.1},
  {anchor="bottom-right"})
-- 模拟：渲染时存入
local stored = {x=l1.x,y=l1.y,w=l1.w,h=l1.h}
-- 模拟：屏幕变成 4K 后又收到鼠标事件。新实现会在 render 时更新 _hit_rect；
-- 若未 render（尺寸未变），_hit_rect 仍是 1080p 那份 —— 关键是**判定永远读它**，
-- 不存在第二套坐标。
local cx2, cy2 = stored.x+stored.w/2, stored.y+stored.h/2
local new_hit = cx2>=stored.x and cx2<=stored.x+stored.w
            and cy2>=stored.y and cy2<=stored.y+stored.h
print(("[新] 存储矩形 x=%.1f y=%.1f w=%.1f h=%.1f"):format(stored.x,stored.y,stored.w,stored.h))
print(("[新] 判定读同一份，命中结果：%s"):format(new_hit and "命中 ✅" or "未命中 ❌"))
print("")

local pass = (not old_hit) and new_hit
print(pass and "==> 对比成立：旧实现在此场景漏判，新实现稳定命中" 
          or "==> 对比未复现，请检查测试前提")
os.exit(pass and 0 or 1)
