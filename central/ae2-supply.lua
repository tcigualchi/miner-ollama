-- AE2 material dispatcher for the GrabCraft builder.
-- Run on a stationary CC:Tweaked computer connected to an Advanced Peripherals
-- ME Bridge and a wireless modem on the same rednet network as the Turtle.

local protocol = "grabcraft.ae2_supply.v1"
local configPath = "/.grabcraft-ae2-supply"

local function readConfig()
  if fs.exists(configPath) then
    local h = fs.open(configPath, "r")
    local cfg = textutils.unserialize(h.readAll())
    h.close()
    if type(cfg) == "table" and type(cfg.secret) == "string" and #cfg.secret >= 8 then
      return cfg
    end
  end
  print("Chave compartilhada (minimo 8 caracteres):")
  write("> ")
  local secret = read()
  if #secret < 8 then error("A chave precisa ter pelo menos 8 caracteres.") end
  print("Direcao do ME Bridge para o bau de entrega (ex.: @up):")
  write("> ")
  local direction = read()
  if direction == "" then direction = "@up" end
  local cfg = {secret = secret, output = direction, max_count = 64}
  local h = fs.open(configPath, "w")
  h.write(textutils.serialize(cfg, {compact = true}))
  h.close()
  return cfg
end

local cfg = readConfig()
local bridge
for _, name in ipairs(peripheral.getNames()) do
  local kind = peripheral.getType(name)
  if kind == "meBridge" or kind == "me_bridge" then
    bridge = peripheral.wrap(name)
    print("ME Bridge: " .. name .. " (" .. tostring(kind) .. ")")
    break
  end
end
if not bridge then error("ME Bridge nao encontrado. Conecte-o ao computador por modem/cabo.") end

local wireless = false
peripheral.find("modem", function(name, modem)
  if modem.isWireless() then
    rednet.open(name)
    wireless = true
  end
end)
if not wireless then error("Conecte um modem wireless ao computador para falar com a Turtle.") end

local lastItem = cfg.last_item
local replies = {}
local function saveConfig()
  local h = fs.open(configPath, "w")
  h.write(textutils.serialize(cfg, {compact = true}))
  h.close()
end

local function itemCount(name)
  local ok, data = pcall(bridge.getItem, {name = name})
  if not ok or type(data) ~= "table" then return 0, nil end
  return tonumber(data.amount or data.count) or 0, data
end

local function exportItem(name, count)
  -- AP 0.8 uses (target, filter); ATM10 releases with AP 0.7 use
  -- (filter, direction). Try the documented 0.8 API, then its 0.7 form.
  local ok, result = pcall(bridge.exportItem, cfg.output, {name = name, count = count})
  if ok and result ~= nil then return result end
  local legacyOk, legacyResult = pcall(bridge.exportItem, {name = name, count = count}, cfg.output:gsub("^@", ""))
  if legacyOk then return legacyResult end
  return nil, tostring(result) .. "; " .. tostring(legacyResult)
end

local function importItem(name, count)
  if not name then return end
  local ok, result = pcall(bridge.importItem, cfg.output, {name = name, count = count or 64})
  if not ok or result == nil then
    pcall(bridge.importItem, {name = name, count = count or 64}, cfg.output:gsub("^@", ""))
  end
end

local function craftUntilAvailable(name, wanted)
  local count, data = itemCount(name)
  if count >= wanted then return true end
  local missing = wanted - count
  local craftable = false
  local craftCheckOk, craftCheck = pcall(bridge.isCraftable, {name = name})
  if craftCheckOk then craftable = craftCheck == true end
  if not craftable then
    return count > 0, count > 0 and "quantidade parcial disponivel" or "item ausente e sem padrao de craft no AE2"
  end

  local ok, job, detail = pcall(bridge.craftItem, {name = name, count = missing})
  if not ok then return false, tostring(job) end
  if job == nil or job == false then return false, tostring(detail or "AE2 nao iniciou o craft") end

  local started = os.epoch("utc")
  while os.epoch("utc") - started < 300000 do
    if type(job) == "table" and type(job.isDone) == "function" then
      local doneOk, done = pcall(job.isDone)
      if doneOk and done then
        local errorOk, hasError = pcall(job.hasErrorOccurred)
        if errorOk and hasError then
          local messageOk, message = pcall(job.getDebugMessage)
          return false, messageOk and tostring(message) or "falha no craft ME"
        end
        break
      end
      local cancelOk, canceled = pcall(job.isCanceled)
      if cancelOk and canceled then return false, "craft cancelado no AE2" end
    end
    local available = itemCount(name)
    if available >= wanted then break end
    sleep(1)
  end
  local available = itemCount(name)
  if available < 1 then return false, "AE2 nao entregou o item em 5 minutos" end
  return true, available >= wanted and nil or "quantidade parcial craftada"
end

local function fulfill(sender, msg)
  if type(msg.item) ~= "string" or not msg.item:match("^[%w_.%-]+:[%w_./%-]+$") then
    return {type = "result", ok = false, error = "ID de item invalido"}
  end
  local requested = math.max(1, math.min(cfg.max_count or 64, math.floor(tonumber(msg.count) or 64)))

  -- Reclaim leftovers from the previous delivery before staging another item.
  if lastItem then
    importItem(lastItem, 64)
    lastItem = nil
    cfg.last_item = nil
    saveConfig()
  end

  local ok, detail = craftUntilAvailable(msg.item, requested)
  local available = itemCount(msg.item)
  if not ok and available < 1 then
    return {type = "result", ok = false, error = detail or "item indisponivel no AE2"}
  end
  local amount = math.min(requested, available)
  local exported, exportError = exportItem(msg.item, amount)
  if exported == nil then return {type = "result", ok = false, error = "exportacao falhou: " .. tostring(exportError)} end
  lastItem = msg.item
  cfg.last_item = msg.item
  saveConfig()
  print(("Turtle #%d pediu %d x %s; enviado ao ponto de coleta."):format(sender, amount, msg.item))
  return {type = "result", ok = true, item = msg.item, count = amount, note = detail}
end

print("Despachante AE2 ativo. Aguardando pedidos de materiais...")
print("Protocolo: " .. protocol .. " | saida: " .. cfg.output)
while true do
  local sender, msg = rednet.receive(protocol)
  if type(msg) == "table" and msg.type == "request" and msg.secret == cfg.secret then
    local key = tostring(sender) .. ":" .. tostring(msg.id)
    local response = replies[key]
    if not response then
      local ok, result = pcall(fulfill, sender, msg)
      if ok then response = result
      else response = {type = "result", ok = false, error = tostring(result)} end
      replies[key] = response
    end
    response.id = msg.id
    rednet.send(sender, response, protocol)
  end
end
