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
  if not h then return nil, err end
  local code = h.getResponseCode()
  local body = h.readAll()
  h.close()
  if code < 200 or code >= 300 then
    return nil, "HTTP " .. tostring(code) .. ": " .. tostring(body)
  end
  local data = textutils.unserializeJSON(body)
  if not data then return nil, "JSON invalido recebido do servidor." end
  return data
end

local function report(state, extra)
  local x, y, z = gps.locate(2)
  local msg = {
    type = "status",
    id = os.getComputerID(),
    name = cfg.turtle_name,
    state = state,
    x = x, y = y, z = z,
    fuel = turtle.getFuelLevel(),
    inventory = inv.summary(),
    extra = extra
  }
  net.send(cfg.controller_id, msg, cfg.protocol)
end

local function waitForMaterial(itemName)
  while not inv.select(itemName) do
    report("WAITING_MATERIAL", { item = itemName })
    print("Faltando:", itemName)
    print("Coloque o material no inventario da turtle.")
    sleep(2)
  end
end

local function placeTarget(itemName)
  local exists, data = turtle.inspectDown()
  if exists and data and data.name == itemName then
    return true, "already"
  end

  if exists then
    local ok, why = turtle.digDown()
    if not ok then return false, "Nao consegui remover bloco existente: " .. tostring(why) end
  end

  waitForMaterial(itemName)
  if not turtle.placeDown() then
    return false, "Falha ao colocar " .. itemName
  end
  return true
end

function M.buildPlan(planId)
  local plan, err = apiGet("/api/plans/" .. textutils.urlEncode(planId))
  if not plan then return false, err end

  if not plan.origin or not plan.placements then
    return false, "Blueprint incompleto."
  end

  local ox, oy, oz = plan.origin.x, plan.origin.y, plan.origin.z

  table.sort(plan.placements, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.z ~= b.z then return a.z < b.z end
    return a.x < b.x
  end)

  report("BUILDING", { plan_id = planId, total = #plan.placements })
  print("Construindo plano:", planId)
  print("Blocos:", #plan.placements)

  for i, p in ipairs(plan.placements) do
    local tx, ty, tz = ox + p.x, oy + p.y + 1, oz + p.z

    local ok, why = nav.gotoXYZ(tx, ty, tz, {dig=false})
    if not ok then
      report("ERROR", { plan_id = planId, index = i, error = why })
      return false, ("Movimento falhou no bloco %d: %s"):format(i, tostring(why))
    end

    local placed, perr = placeTarget(p.block)
    if not placed then
      report("ERROR", { plan_id = planId, index = i, error = perr })
      return false, perr
    end

    if i % 10 == 0 or i == #plan.placements then
      report("BUILDING", {
        plan_id = planId,
        done = i,
        total = #plan.placements,
        progress = math.floor(i * 100 / #plan.placements)
      })
      print(("%d/%d (%d%%)"):format(i, #plan.placements, math.floor(i*100/#plan.placements)))
    end
  end

  report("IDLE", { completed_plan = planId })
  return true
end

return M
