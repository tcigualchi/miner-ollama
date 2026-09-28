local M = {}

local cfg = require("config")
local nav = require("lib.nav")
local inv = require("lib.inventory")
local net = require("lib.net")

local function apiGet(path)
  local url = cfg.server_url .. path

  local h, err = http.get(url, {
    ["X-Fleet-Token"] = cfg.fleet_token,
    ["Accept"] = "application/json"
  })

  if not h then
    return nil, err
  end

  local code = h.getResponseCode()
  local body = h.readAll()
  h.close()

  if code < 200 or code >= 300 then
    return nil, "HTTP " .. tostring(code) .. ": " .. tostring(body)
  end

  local data = textutils.unserializeJSON(body)

  if not data then
    return nil, "JSON invalido recebido do servidor."
  end

  return data
end

local function defaultReport(state, extra)
  local x, y, z = gps.locate(2)

  net.send(cfg.controller_id, {
    type = "status",
    id = os.getComputerID(),
    name = cfg.turtle_name,
    state = state,
    x = x,
    y = y,
    z = z,
    fuel = turtle.getFuelLevel(),
    inventory = inv.summary(),
    extra = extra or {},
    label = os.getComputerLabel(),
    timestamp = os.epoch("utc")
  }, cfg.protocol)
end

local function waitForMaterial(itemName, report)
  while not inv.select(itemName) do
    report("WAITING_MATERIAL", {
      item = itemName,
      message = "Aguardando material no inventario."
    })

    print("Faltando:", itemName)
    print("Coloque o material no inventario da turtle.")

    sleep(1)
  end
end

local function placeTarget(itemName, report)
  local exists, data = turtle.inspectDown()

  if exists and data and data.name == itemName then
    return true, "already"
  end

  if exists then
    report("BUILDING", {
      action = "removing_target_block",
      block = data and data.name or "unknown"
    })

    local ok, why = turtle.digDown()

    if not ok then
      return false,
        "Nao consegui remover bloco existente no ponto da construcao: " ..
        tostring(why)
    end
  end

  waitForMaterial(itemName, report)

  if not turtle.placeDown() then
    return false, "Falha ao colocar " .. itemName
  end

  return true
end

function M.buildPlan(planId, reportFn)
  local report = reportFn or defaultReport

  local plan, err = apiGet(
    "/api/plans/" .. textutils.urlEncode(planId)
  )

  if not plan then
    return false, err
  end

  if not plan.origin or not plan.placements then
    return false, "Blueprint incompleto."
  end

  local ox = plan.origin.x
  local oy = plan.origin.y
  local oz = plan.origin.z
  local total = #plan.placements

  -- A turtle sempre trabalha um bloco acima do bloco que sera colocado.
  -- Portanto este e o Y minimo seguro da turtle durante esta obra.
  local safeMinY = oy + 1

  table.sort(plan.placements, function(a, b)
    if a.y ~= b.y then
      return a.y < b.y
    end

    if a.z ~= b.z then
      return a.z < b.z
    end

    return a.x < b.x
  end)

  report("BUILDING", {
    plan_id = planId,
    action = "starting",
    done = 0,
    total = total,
    progress = 0,
    safe_min_y = safeMinY
  })

  print("Construindo plano:", planId)
  print("Blocos:", total)
  print("Y minimo seguro:", safeMinY)

  for i, p in ipairs(plan.placements) do
    local blockX = ox + p.x
    local blockY = oy + p.y
    local blockZ = oz + p.z

    local turtleX = blockX
    local turtleY = blockY + 1
    local turtleZ = blockZ

    report("BUILDING", {
      plan_id = planId,
      action = "moving_to_block",
      target_block = p.block,

      block_target = {
        x = blockX,
        y = blockY,
        z = blockZ
      },

      turtle_target = {
        x = turtleX,
        y = turtleY,
        z = turtleZ
      },

      done = i - 1,
      total = total,
      progress = math.floor(
        ((i - 1) * 100) / math.max(total, 1)
      )
    })

    -- Modo seguro de construcao:
    --   * pode quebrar na frente;
    --   * pode quebrar acima;
    --   * NUNCA cava para baixo para navegar;
    --   * nunca desce abaixo de oy + 1;
    --   * verifica GPS durante cada movimento.
    local ok, why = nav.gotoXYZ(
      turtleX,
      turtleY,
      turtleZ,
      {
        digForward = cfg.build_dig_obstacles == true,
        digUp = cfg.build_dig_obstacles == true,
        digDown = false,
        minY = safeMinY,
        verify = true
      }
    )

    if not ok then
      local ax, ay, az = nav.locate()

      report("ERROR", {
        plan_id = planId,
        action = "movement_failed",
        index = i,
        total = total,
        error = why,

        current = {
          x = ax,
          y = ay,
          z = az
        },

        turtle_target = {
          x = turtleX,
          y = turtleY,
          z = turtleZ
        }
      })

      return false,
        ("Movimento falhou no bloco %d: %s"):format(
          i,
          tostring(why)
        )
    end

    report("BUILDING", {
      plan_id = planId,
      action = "placing_block",
      target_block = p.block,

      block_target = {
        x = blockX,
        y = blockY,
        z = blockZ
      },

      done = i - 1,
      total = total,
      progress = math.floor(
        ((i - 1) * 100) / math.max(total, 1)
      )
    })

    local placed, perr = placeTarget(
      p.block,
      report
    )

    if not placed then
      report("ERROR", {
        plan_id = planId,
        action = "place_failed",
        index = i,
        total = total,
        error = perr
      })

      return false, perr
    end

    local progress = math.floor(
      (i * 100) / math.max(total, 1)
    )

    report("BUILDING", {
      plan_id = planId,
      action = "block_placed",
      block = p.block,

      block_target = {
        x = blockX,
        y = blockY,
        z = blockZ
      },

      done = i,
      total = total,
      progress = progress
    })

    print(
      ("%d/%d (%d%%)"):format(
        i,
        total,
        progress
      )
    )
  end

  report("IDLE", {
    completed_plan = planId,
    action = "completed",
    done = total,
    total = total,
    progress = 100
  })

  return true
end

return M
