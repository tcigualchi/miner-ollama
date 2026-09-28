local M = {}
local cfg = require("config")

M.NORTH = 0
M.EAST  = 1
M.SOUTH = 2
M.WEST  = 3

local heading = nil

local function round(n)
  return math.floor(n + 0.5)
end

local function locate()
  local x, y, z = gps.locate(cfg.gps_timeout or 5)

  if not x then
    error("GPS indisponivel.")
  end

  return round(x), round(y), round(z)
end

function M.locate()
  return locate()
end

local function fuelLevel()
  local f = turtle.getFuelLevel()

  if type(f) == "string" then
    return math.huge
  end

  return f
end

function M.ensureFuel(minimum)
  minimum = minimum or 64

  if fuelLevel() >= minimum then
    return true
  end

  local selected = turtle.getSelectedSlot()

  for slot = 1, 16 do
    turtle.select(slot)

    if turtle.refuel(0) then
      while fuelLevel() < minimum and turtle.getItemCount(slot) > 0 do
        turtle.refuel(1)
      end

      if fuelLevel() >= minimum then
        break
      end
    end
  end

  turtle.select(selected)

  if fuelLevel() < minimum then
    return false, "Combustivel insuficiente. Necessario pelo menos " .. tostring(minimum)
  end

  return true
end

local function headingFromDelta(dx, dz)
  if dx == 1 and dz == 0 then
    return M.EAST
  end

  if dx == -1 and dz == 0 then
    return M.WEST
  end

  if dx == 0 and dz == 1 then
    return M.SOUTH
  end

  if dx == 0 and dz == -1 then
    return M.NORTH
  end

  return nil
end

function M.calibrate()
  local x1, y1, z1 = locate()

  for i = 1, 4 do
    if turtle.forward() then
      sleep(0.15)

      local x2, y2, z2 = locate()

      if not turtle.back() then
        error("Nao consegui voltar apos calibrar.")
      end

      if y2 ~= y1 then
        error("Calibracao horizontal recebeu alteracao inesperada no Y.")
      end

      heading = headingFromDelta(x2 - x1, z2 - z1)

      if not heading then
        error(
          ("Nao consegui calcular a direcao. Delta GPS: %d,%d,%d"):format(
            x2 - x1,
            y2 - y1,
            z2 - z1
          )
        )
      end

      return heading
    end

    turtle.turnRight()
  end

  error("Nao consegui calibrar. Verifique combustivel, blocos ou entidades ao redor.")
end

function M.heading()
  if heading == nil then
    M.calibrate()
  end

  return heading
end

function M.turnTo(target)
  if heading == nil then
    M.calibrate()
  end

  local d = (target - heading) % 4

  if d == 1 then
    turtle.turnRight()
  elseif d == 2 then
    turtle.turnRight()
    turtle.turnRight()
  elseif d == 3 then
    turtle.turnLeft()
  end

  heading = target
end

local function forwardRaw(allowDig)
  if turtle.forward() then
    return true
  end

  if allowDig and turtle.detect() then
    local ok, reason = turtle.dig()

    if not ok then
      return false, reason or "Nao consegui quebrar na frente."
    end

    sleep(0.1)

    if turtle.forward() then
      return true
    end
  end

  return false, "Caminho bloqueado na frente."
end

local function upRaw(allowDig)
  if turtle.up() then
    return true
  end

  if allowDig and turtle.detectUp() then
    local ok, reason = turtle.digUp()

    if not ok then
      return false, reason or "Nao consegui quebrar acima."
    end

    sleep(0.1)

    if turtle.up() then
      return true
    end
  end

  return false, "Caminho bloqueado acima."
end

local function downRaw(allowDig)
  if turtle.down() then
    return true
  end

  if allowDig and turtle.detectDown() then
    local ok, reason = turtle.digDown()

    if not ok then
      return false, reason or "Nao consegui quebrar abaixo."
    end

    sleep(0.1)

    if turtle.down() then
      return true
    end
  end

  return false, "Caminho bloqueado abaixo."
end

function M.forward(allowDig)
  return forwardRaw(allowDig == true)
end

function M.up(allowDig)
  return upRaw(allowDig == true)
end

function M.down(allowDig)
  return downRaw(allowDig == true)
end

local function verifyPosition(ex, ey, ez, action)
  sleep(0.05)

  local ax, ay, az = locate()

  if ax ~= ex or ay ~= ey or az ~= ez then
    return false,
      ("GPS divergiu durante %s. Esperado %d,%d,%d; atual %d,%d,%d"):format(
        action,
        ex, ey, ez,
        ax, ay, az
      )
  end

  return true
end

local function moveUp(x, y, z, allowDig, verify)
  local moved, err = upRaw(allowDig)

  if not moved then
    return false, err
  end

  if verify then
    local ok, why = verifyPosition(x, y + 1, z, "subida")

    if not ok then
      return false, why
    end
  end

  return true
end

local function moveDown(x, y, z, allowDig, verify)
  local moved, err = downRaw(allowDig)

  if not moved then
    return false, err
  end

  if verify then
    local ok, why = verifyPosition(x, y - 1, z, "descida")

    if not ok then
      return false, why
    end
  end

  return true
end

local function moveForward(x, y, z, targetHeading, allowDig, verify)
  M.turnTo(targetHeading)

  local moved, err = forwardRaw(allowDig)

  if not moved then
    return false, err
  end

  local ex, ey, ez = x, y, z

  if targetHeading == M.EAST then
    ex = ex + 1
  elseif targetHeading == M.WEST then
    ex = ex - 1
  elseif targetHeading == M.SOUTH then
    ez = ez + 1
  elseif targetHeading == M.NORTH then
    ez = ez - 1
  end

  if verify then
    local ok, why = verifyPosition(ex, ey, ez, "movimento horizontal")

    if not ok then
      -- Nao continuamos movimentando com coordenadas internas incorretas.
      heading = nil
      return false, why
    end
  end

  return true
end

function M.gotoXYZ(tx, ty, tz, opts)
  opts = opts or {}

  local digForward = opts.digForward == true or opts.dig == true
  local digUp = opts.digUp == true or opts.dig == true

  -- Por seguranca, dig=true NAO habilita escavacao para baixo.
  -- Para permitir isso, precisa ser explicitamente digDown=true.
  local digDown = opts.digDown == true

  local verify = opts.verify ~= false
  local minY = opts.minY

  tx = round(tx)
  ty = round(ty)
  tz = round(tz)

  local x, y, z = locate()

  if minY ~= nil then
    minY = round(minY)

    if ty < minY then
      return false,
        ("Destino Y=%d esta abaixo do limite seguro Y=%d."):format(ty, minY)
    end

    if y < minY then
      -- Sai primeiro de qualquer buraco existente.
      while y < minY do
        local moved, err = moveUp(x, y, z, true, verify)

        if not moved then
          return false, err
        end

        x, y, z = locate()
      end
    end
  end

  local distance =
    math.abs(tx - x) +
    math.abs(ty - y) +
    math.abs(tz - z) +
    16

  local ok, why = M.ensureFuel(distance)

  if not ok then
    return false, why
  end

  -- 1. Primeiro sobe ate a altura necessaria.
  while y < ty do
    local moved, err = moveUp(x, y, z, digUp, verify)

    if not moved then
      return false, err
    end

    x, y, z = locate()
  end

  -- 2. Depois anda no eixo X.
  while x < tx do
    local moved, err = moveForward(x, y, z, M.EAST, digForward, verify)

    if not moved then
      return false, err
    end

    x, y, z = locate()
  end

  while x > tx do
    local moved, err = moveForward(x, y, z, M.WEST, digForward, verify)

    if not moved then
      return false, err
    end

    x, y, z = locate()
  end

  -- 3. Depois anda no eixo Z.
  while z < tz do
    local moved, err = moveForward(x, y, z, M.SOUTH, digForward, verify)

    if not moved then
      return false, err
    end

    x, y, z = locate()
  end

  while z > tz do
    local moved, err = moveForward(x, y, z, M.NORTH, digForward, verify)

    if not moved then
      return false, err
    end

    x, y, z = locate()
  end

  -- 4. Somente no final desce.
  -- Nunca cava para baixo durante build, a menos que digDown=true.
  while y > ty do
    if minY ~= nil and (y - 1) < minY then
      return false,
        ("Descida bloqueada pelo limite seguro Y=%d."):format(minY)
    end

    local moved, err = moveDown(x, y, z, digDown, verify)

    if not moved then
      return false, err
    end

    x, y, z = locate()
  end

  local fx, fy, fz = locate()

  if fx ~= tx or fy ~= ty or fz ~= tz then
    return false,
      ("GPS divergiu no destino. Esperado %d,%d,%d; atual %d,%d,%d"):format(
        tx, ty, tz,
        fx, fy, fz
      )
  end

  return true
end

return M
