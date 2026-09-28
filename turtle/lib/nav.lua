local M = {}

local cfg = require("config")
local heading = nil

local NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3

local function locate()
  local x, y, z = gps.locate(cfg.gps_timeout or 5)
  if not x then error("GPS indisponivel.") end
  return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
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

function M.locate()
  return locate()
end

local function headingFromDelta(dx, dz)
  if dx == 1 then return EAST end
  if dx == -1 then return WEST end
  if dz == 1 then return SOUTH end
  if dz == -1 then return NORTH end
end

function M.calibrate()
  local x1, y1, z1 = locate()

  for i = 1, 4 do
    if turtle.forward() then
      sleep(0.25)
      local x2, y2, z2 = locate()
      if not turtle.back() then
        error("Consegui andar para frente, mas nao consegui voltar.")
      end
      heading = headingFromDelta(x2 - x1, z2 - z1)
      if not heading then error("Movimento GPS inesperado durante calibracao.") end
      return heading
    end
    turtle.turnRight()
  end

  error("Turtle cercada: preciso de um bloco livre em pelo menos uma direcao para calibrar.")
end

local function turnTo(target)
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

local function moveForward(allowDig)
  if turtle.forward() then return true end
  if allowDig and turtle.detect() then
    local ok, reason = turtle.dig()
    if not ok then return false, reason or "Nao consegui quebrar obstaculo." end
    sleep(0.15)
    return turtle.forward()
  end
  return false, "Caminho bloqueado."
end

local function moveUp(allowDig)
  if turtle.up() then return true end
  if allowDig and turtle.detectUp() then
    local ok, reason = turtle.digUp()
    if not ok then return false, reason or "Nao consegui quebrar acima." end
    sleep(0.15)
    return turtle.up()
  end
  return false, "Caminho acima bloqueado."
end

local function moveDown(allowDig)
  if turtle.down() then return true end
  if allowDig and turtle.detectDown() then
    local ok, reason = turtle.digDown()
    if not ok then return false, reason or "Nao consegui quebrar abaixo." end
    sleep(0.15)
    return turtle.down()
  end
  return false, "Caminho abaixo bloqueado."
end

function M.gotoXYZ(tx, ty, tz, opts)
  opts = opts or {}
  local allowDig = opts.dig == true
  local x, y, z = locate()

  local distance = math.abs(tx-x) + math.abs(ty-y) + math.abs(tz-z) + 16
  local ok, reason = M.ensureFuel(distance)
  if not ok then return false, reason end

  -- Sobe primeiro quando necessario. Isso ajuda a navegar por cima de construcoes.
  while y < ty do
    local moved, why = moveUp(allowDig)
    if not moved then return false, why end
    y = y + 1
  end

  while x < tx do
    turnTo(EAST)
    local moved, why = moveForward(allowDig)
    if not moved then return false, why end
    x = x + 1
  end
  while x > tx do
    turnTo(WEST)
    local moved, why = moveForward(allowDig)
    if not moved then return false, why end
    x = x - 1
  end

  while z < tz do
    turnTo(SOUTH)
    local moved, why = moveForward(allowDig)
    if not moved then return false, why end
    z = z + 1
  end
  while z > tz do
    turnTo(NORTH)
    local moved, why = moveForward(allowDig)
    if not moved then return false, why end
    z = z - 1
  end

  while y > ty do
    local moved, why = moveDown(allowDig)
    if not moved then return false, why end
    y = y - 1
  end

  local fx, fy, fz = locate()
  if fx ~= tx or fy ~= ty or fz ~= tz then
    return false, ("GPS divergiu. Esperado %d,%d,%d; atual %d,%d,%d"):format(tx,ty,tz,fx,fy,fz)
  end
  return true
end

function M.heading()
  if heading == nil then M.calibrate() end
  return heading
end

return M
