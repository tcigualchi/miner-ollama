local gps = require("lib.gps")
local fuel = require("lib.fuel")
local M = {}
local function clear(direction)
  local detect = direction=="up" and turtle.detectUp or direction=="down" and turtle.detectDown or turtle.detect
  local dig = direction=="up" and turtle.digUp or direction=="down" and turtle.digDown or turtle.dig
  if detect() then
    local ok, why = dig()
    if not ok then return false, why end
  end
  return true
end
function M.forward(dig)
  local ok, why=fuel.ensure(1); if not ok then return false, why end
  for tries=1,4 do
    ok,why=turtle.forward(); if ok then return true end
    if not dig then return false,why end
    local cleared, why2=clear("front"); if not cleared then turtle.attack(); sleep(.3) else sleep(.1) end
  end
  return false, why or "caminho bloqueado"
end
function M.up(dig)
  local ok,why=fuel.ensure(1); if not ok then return false,why end
  for _=1,4 do ok,why=turtle.up(); if ok then return true end; if not dig then return false,why end; local c,w=clear("up"); if not c then turtle.attackUp(); sleep(.3) end end
  return false,why
end
function M.down(dig)
  local ok,why=fuel.ensure(1); if not ok then return false,why end
  for _=1,4 do ok,why=turtle.down(); if ok then return true end; if not dig then return false,why end; local c,w=clear("down"); if not c then turtle.attackDown(); sleep(.3) end end
  return false,why
end
function M.left() return gps.turn_left() end
function M.right() return gps.turn_right() end
return M
