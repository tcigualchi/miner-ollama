local M = {}
local cfg = require("config")

M.NORTH = 0
M.EAST  = 1
M.SOUTH = 2
M.WEST  = 3

local heading = nil

local function locate()
  local x, y, z = gps.locate(cfg.gps_timeout or 5)
  if not x then error("GPS indisponivel.") end
  return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
end

function M.locate()
  return locate()
end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  if type(f) == "string" then return math.huge end
  return f
end

function M.ensureFuel(minimum)
  minimum = minimum or 64
  if fuelLevel() >= minimum then return true end
  local selected = turtle.getSelectedSlot()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then
      while fuelLevel() < minimum and turtle.getItemCount(slot) > 0 do
        turtle.refuel(1)
      end
      if fuelLevel() >= minimum then break end
    end
  end
  turtle.select(selected)
  if fuelLevel() < minimum then
    return false, "Combustivel insuficiente. Necessario pelo menos " .. minimum
  end
  return true
end

local function headingFromDelta(dx, dz)
  if dx == 1 then return M.EAST end
  if dx == -1 then return M.WEST end
  if dz == 1 then return M.SOUTH end
  if dz == -1 then return M.NORTH end
end

function M.calibrate()
  local x1, y1, z1 = locate()
  for i = 1, 4 do
    if turtle.forward() then
      sleep(0.2)
      local x2, _, z2 = locate()
      if not turtle.back() then error("Nao consegui voltar apos calibrar.") end
      heading = headingFromDelta(x2 - x1, z2 - z1)
      if not heading then error("Nao consegui calcular a direcao.") end
      return heading
    end
    turtle.turnRight()
  end
  error("Turtle cercada: preciso de um bloco livre para calibrar.")
end

function M.heading()
  if heading == nil then M.calibrate() end
  return heading
end

function M.turnTo(target)
  if heading == nil then M.calibrate() end
  local d = (target - heading) % 4
  if d == 1 then
    turtle.turnRight()
  elseif d == 2 then
    turtle.turnRight(); turtle.turnRight()
  elseif d == 3 then
    turtle.turnLeft()
  end
  heading = target
end

local function tryForward(allowDig)
  if turtle.forward() then return true end
  if allowDig and turtle.detect() then
    local ok, reason = turtle.dig()
    if not ok then return false, reason or "Nao consegui quebrar na frente." end
    sleep(0.1)
    return turtle.forward()
  end
  return false, "Caminho bloqueado na frente."
end

local function tryUp(allowDig)
  if turtle.up() then return true end
  if allowDig and turtle.detectUp() then
    local ok, reason = turtle.digUp()
    if not ok then return false, reason or "Nao consegui quebrar acima." end
    sleep(0.1)
    return turtle.up()
  end
  return false, "Caminho bloqueado acima."
end

local function tryDown(allowDig)
  if turtle.down() then return true end
  if allowDig and turtle.detectDown() then
    local ok, reason = turtle.digDown()
    if not ok then return false, reason or "Nao consegui quebrar abaixo." end
    sleep(0.1)
    return turtle.down()
  end
  return false, "Caminho bloqueado abaixo."
end

function M.forward(allowDig)
  return tryForward(allowDig == true)
end

function M.up(allowDig)
  return tryUp(allowDig == true)
end

function M.down(allowDig)
  return tryDown(allowDig == true)
end

function M.gotoXYZ(tx, ty, tz, opts)
  opts = opts or {}
  local allowDig = opts.dig == true
  local x, y, z = locate()

  local distance = math.abs(tx-x) + math.abs(ty-y) + math.abs(tz-z) + 16
  local ok, why = M.ensureFuel(distance)
  if not ok then return false, why end

  while y < ty do
    local moved, err = tryUp(allowDig)
    if not moved then return false, err end
    y = y + 1
  end

  while x < tx do
    M.turnTo(M.EAST)
    local moved, err = tryForward(allowDig)
    if not moved then return false, err end
    x = x + 1
  end
  while x > tx do
    M.turnTo(M.WEST)
    local moved, err = tryForward(allowDig)
    if not moved then return false, err end
    x = x - 1
  end

  while z < tz do
    M.turnTo(M.SOUTH)
    local moved, err = tryForward(allowDig)
    if not moved then return false, err end
    z = z + 1
  end
  while z > tz do
    M.turnTo(M.NORTH)
    local moved, err = tryForward(allowDig)
    if not moved then return false, err end
    z = z - 1
  end

  while y > ty do
    local moved, err = tryDown(allowDig)
    if not moved then return false, err end
    y = y - 1
  end

  local fx, fy, fz = locate()
  if fx ~= tx or fy ~= ty or fz ~= tz then
    return false, ("GPS divergiu. Esperado %d,%d,%d; atual %d,%d,%d"):format(tx,ty,tz,fx,fy,fz)
  end
  return true
end

return M
