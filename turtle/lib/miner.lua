local M = {}
local nav = require("lib.nav")

local function clearAbove(height)
  if height <= 1 then return true end
  for i = 1, height - 1 do
    while turtle.detectUp() do
      local ok, why = turtle.digUp()
      if not ok then return false, why or "Falha ao quebrar acima." end
      sleep(0.05)
    end
    if i < height - 1 then
      local ok, why = nav.up(false)
      if not ok then return false, why end
    end
  end
  for i = height - 2, 1, -1 do
    local ok, why = nav.down(false)
    if not ok then return false, why end
  end
  return true
end

function M.digLine(length, clearHeight)
  length = tonumber(length) or 0
  clearHeight = tonumber(clearHeight) or 2
  if length <= 0 then return false, "Comprimento invalido." end

  local ok, why = nav.ensureFuel(length + 8)
  if not ok then return false, why end

  local cOk, cWhy = clearAbove(clearHeight)
  if not cOk then return false, cWhy end

  for i = 1, length do
    local moved, err = nav.forward(true)
    if not moved then return false, err end
    cOk, cWhy = clearAbove(clearHeight)
    if not cOk then return false, cWhy end
  end
  return true
end

function M.quarry(width, depth, height)
  width = tonumber(width) or 0
  depth = tonumber(depth) or 0
  height = tonumber(height) or 0
  if width <= 0 or depth <= 0 or height <= 0 then
    return false, "Dimensoes invalidas para quarry."
  end

  local fuelNeed = width * depth * math.max(height, 1) + 50
  local ok, why = nav.ensureFuel(fuelNeed)
  if not ok then return false, why end
  nav.heading()

  local startDir = nav.heading()
  local function serpentineLayer()
    local rightDir = (startDir + 1) % 4
    local leftDir = (startDir + 3) % 4
    for z = 1, depth do
      for x = 1, width - 1 do
        local moved, err = nav.forward(true)
        if not moved then return false, err end
        local cOk, cWhy = clearAbove(height)
        if not cOk then return false, cWhy end
      end
      if z < depth then
        if z % 2 == 1 then
          nav.turnTo(rightDir)
          local moved, err = nav.forward(true)
          if not moved then return false, err end
          local cOk, cWhy = clearAbove(height)
          if not cOk then return false, cWhy end
          nav.turnTo((rightDir + 2) % 4)
        else
          nav.turnTo(leftDir)
          local moved, err = nav.forward(true)
          if not moved then return false, err end
          local cOk, cWhy = clearAbove(height)
          if not cOk then return false, cWhy end
          nav.turnTo((leftDir + 2) % 4)
        end
      end
    end
    return true
  end

  local function returnToLayerStart(layer)
    local x, y, z = nav.locate()
    -- volta para a origem XY da camada usando GPS
    local okMove, err = nav.gotoXYZ(x - 0, y, z - 0, {dig=false})
    -- nao usamos este metodo; reposicionamento sera por GPS abaixo
    return okMove, err
  end

  local originX, originY, originZ = nav.locate()
  local cOk, cWhy = clearAbove(height)
  if not cOk then return false, cWhy end

  for layer = 1, 1 do
    local okLayer, errLayer = serpentineLayer()
    if not okLayer then return false, errLayer end
  end

  -- Retorno simples ao inicio usando GPS.
  local okBack, errBack = nav.gotoXYZ(originX, originY, originZ, {dig=false})
  if not okBack then return false, errBack end
  nav.turnTo(startDir)
  return true
end

return M
