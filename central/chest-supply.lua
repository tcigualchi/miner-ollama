-- Dispatcher for normal inventories on a CC:Tweaked wired network.
-- Run on an Advanced Computer with wireless modem plus wired access to source
-- chests and to the delivery chest below the Turtle.
local protocol = "grabcraft.ae2_supply.v1" -- Compatible with the existing Turtle client.
local configPath = "/.grabcraft-chest-supply"

local function hasMethod(name, wanted)
  local ok, methods = pcall(peripheral.getMethods, name)
  if not ok or type(methods) ~= "table" then return false end
  for _, method in ipairs(methods) do if method == wanted then return true end end
  return false
end

local cfg
if fs.exists(configPath) then
  local h = fs.open(configPath, "r")
  local ok, value = pcall(textutils.unserialize, h.readAll())
  h.close()
  if ok and type(value) == "table" then cfg = value end
end
if not cfg or type(cfg.secret) ~= "string" or #cfg.secret < 8 or type(cfg.output) ~= "string" then
  print("Chave compartilhada (minimo 8 caracteres):")
  write("> ")
  local secret = read()
  if #secret < 8 then error("A chave precisa ter pelo menos 8 caracteres.") end
  print("Nome do bau de entrega (veja peripheral.getNames):")
  write("> ")
  local output = read()
  if output == "" then error("Informe o nome do inventario de entrega.") end
  cfg = {secret = secret, output = output, max_count = 64}
  local h = fs.open(configPath, "w")
  h.write(textutils.serialize(cfg, {compact = true}))
  h.close()
end

if not hasMethod(cfg.output, "list") then error("Bau de entrega nao encontrado: " .. cfg.output) end
local wireless = false
peripheral.find("modem", function(name, modem)
  if modem.isWireless() then rednet.open(name); wireless = true end
end)
if not wireless then error("Conecte um modem wireless ao computador para falar com a Turtle.") end

local function sourceInventories()
  local result = {}
  for _, name in ipairs(peripheral.getNames()) do
    if name ~= cfg.output and hasMethod(name, "list") and hasMethod(name, "pushItems") then
      result[#result + 1] = name
    end
  end
  return result
end

local function fulfill(msg)
  if type(msg.item) ~= "string" or not msg.item:match("^[%w_.%-]+:[%w_./%-]+$") then
    return 0, "ID de item invalido"
  end
  local requested = math.max(1, math.min(cfg.max_count or 64, math.floor(tonumber(msg.count) or 64)))
  local moved_total = 0
  while moved_total < requested do
    local found = false
    for _, name in ipairs(sourceInventories()) do
      local chest = peripheral.wrap(name)
      local ok, contents = pcall(chest.list)
      if ok and type(contents) == "table" then
        for slot, stack in pairs(contents) do
          if type(stack) == "table" and stack.name == msg.item then
            found = true
            local amount = math.min(requested - moved_total, tonumber(stack.count) or 0)
            local push_ok, moved = pcall(chest.pushItems, cfg.output, slot, amount)
            if push_ok then moved_total = moved_total + (tonumber(moved) or 0) end
            if moved_total >= requested then break end
          end
        end
      end
      if moved_total >= requested then break end
    end
    if not found or moved_total == 0 then break end
  end
  if moved_total == 0 then return 0, "item nao encontrado nos baus cabeados: " .. msg.item end
  return moved_total, moved_total < requested and "quantidade parcial; confira os baus" or nil
end

print("Despachante de baus ativo. Saida: " .. cfg.output)
print("Inventarios fonte encontrados: " .. #sourceInventories())
while true do
  local sender, msg = rednet.receive(protocol)
  if type(msg) == "table" and msg.type == "request" and msg.secret == cfg.secret then
    local ok, count, detail = pcall(fulfill, msg)
    local response
    if ok then
      response = {type = "result", ok = count > 0, item = msg.item, count = count,
        note = detail, error = count > 0 and nil or detail}
      print(("Turtle #%d pediu %s; separados %d."):format(sender, tostring(msg.item), count))
    else
      response = {type = "result", ok = false, error = tostring(count)}
      print("Falha no pedido: " .. tostring(count))
    end
    response.id = msg.id
    rednet.send(sender, response, protocol)
  end
end
