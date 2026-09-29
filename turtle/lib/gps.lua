local cfg = require("config")
local state = require("lib.state")
local M = {}
local headings = {"north", "east", "south", "west"}

function M.locate()
  local x, y, z = gps.locate(cfg.gps_timeout)
  local saved = state.read()
  if x then
    state.write({position = {x=x, y=y, z=z}, gps_at=os.epoch("utc")})
    return {x=x, y=y, z=z, heading=saved.heading or "unknown", gps=true}
  end
  local old = saved.position or {}
  return {x=old.x, y=old.y, z=old.z, heading=saved.heading or "unknown", gps=false}
end
function M.heading() return state.read().heading or "unknown" end
function M.turn_left()
  local ok, why = turtle.turnLeft(); if not ok then return false, why end
  local saved = state.read(); local h = saved.heading
  for i,v in ipairs(headings) do if v == h then state.write({heading=headings[(i+2)%4+1]}); break end end
  return true
end
function M.turn_right()
  local ok, why = turtle.turnRight(); if not ok then return false, why end
  local saved = state.read(); local h = saved.heading
  for i,v in ipairs(headings) do if v == h then state.write({heading=headings[i%4+1]}); break end end
  return true
end
function M.calibrate_heading()
  local before = M.locate(); if not before.x or before.gps == false then return false, "GPS indisponivel" end
  local moved, move_error = turtle.forward()
  if not moved then return false, move_error or "nao foi possivel avancar para calibrar" end
  local after = M.locate()
  local backed, back_error = turtle.back()
  if not backed then return false, back_error or "nao foi possivel retornar apos calibrar" end
  if not after.x or after.gps == false then return false, "GPS indisponivel durante calibracao" end
  if after.x > before.x then state.write({heading="east"})
  elseif after.x < before.x then state.write({heading="west"})
  elseif after.z > before.z then state.write({heading="south"})
  elseif after.z < before.z then state.write({heading="north"})
  else return false, "movimento bloqueado para calibrar" end
  return true
end
return M
