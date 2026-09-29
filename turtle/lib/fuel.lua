local cfg = require("config")
local M = {}
function M.level() return turtle.getFuelLevel() end
function M.ensure(needed)
  local level=turtle.getFuelLevel()
  if level=="unlimited" or level >= needed + cfg.low_fuel_reserve then return true end
  for slot=1,16 do
    turtle.select(slot)
    if turtle.refuel(0) then turtle.refuel() end
    level=turtle.getFuelLevel()
    if level=="unlimited" or level >= needed + cfg.low_fuel_reserve then return true end
  end
  return false, "combustível insuficiente"
end
return M
