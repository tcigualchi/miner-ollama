local gps = require("lib.gps")
local move = require("lib.movement")
local state = require("lib.state")
local fuel = require("lib.fuel")
local cfg = require("config")
local headings = {"north","east","south","west"}
local M = {}

local function face(wanted)
  for _=1,4 do
    if gps.heading() == wanted then return true end
    local ok,why=move.right(); if not ok then return false,why end
  end
  return false,"orientação desconhecida; execute calibração GPS"
end
local function axis(target, axis, positive, negative, dig)
  while true do
    local pos=gps.locate()
    if pos.gps==false then return false,"GPS indisponivel durante navegacao" end
    local value=pos[axis]
    if not value then return false,"GPS indisponível durante navegação" end
    local delta=target-value
    if math.abs(delta)<.5 then return true end
    local wanted=delta>0 and positive or negative
    local ok,why
    if axis=="y" then
      if wanted=="up" then ok,why=move.up(dig) else ok,why=move.down(dig) end
    else
      ok,why=face(wanted); if not ok then return false,why end
      ok,why=move.forward(dig)
    end
    if not ok then return false,why end
    local updated=gps.locate()
    if updated.gps==false then return false,"GPS indisponivel depois do movimento" end
    state.write({position={x=updated.x,y=updated.y,z=updated.z}})
  end
end
function M.face(wanted) return face(wanted) end
function M.heading_axis()
  local h=gps.heading()
  for i,value in ipairs(headings) do if value==h then return h,i end end
  return nil
end
function M.go_to(target, options)
  options=options or {}; local pos=gps.locate()
  if pos.gps==false then return false,"GPS indisponivel; rota cancelada para evitar movimento sem coordenadas" end
  if not pos.x then
    local ok,why=gps.calibrate_heading(); if not ok then return false,why end
    pos=gps.locate()
  elseif gps.heading()=="unknown" then
    local ok,why=gps.calibrate_heading(); if not ok then return false,why end
  end
  local distance=math.abs(target.x-pos.x)+math.abs(target.y-pos.y)+math.abs(target.z-pos.z)
  if distance>(cfg.max_navigation_blocks or 4096) then return false,"rota excede o limite de seguranca de 4096 blocos" end
  local enough, fuel_error=fuel.ensure(distance)
  if not enough then return false,fuel_error end
  local ok,why=axis(target.y,"y","up","down",options.dig)
  if not ok then return false,why end
  ok,why=axis(target.x,"x","east","west",options.dig); if not ok then return false,why end
  return axis(target.z,"z","south","north",options.dig)
end
function M.return_base()
  if not cfg.base or not cfg.base.x then return false,"base não configurada" end
  return M.go_to(cfg.base,{dig=false})
end
return M
