-- Configure os dois valores antes de executar.
local SERVER = "https://SEU-ENDERECO.ngrok-free.app"
local TOKEN = "COLOQUE_O_MESMO_TOKEN_DO_SERVIDOR"

if not turtle then error("Execute em uma Mining Turtle") end
if not http then error("Ative HTTP no CC: Tweaked") end
if SERVER:find("SEU%-ENDERECO") or TOKEN == "COLOQUE_O_MESMO_TOKEN_DO_SERVIDOR" then
  error("Configure SERVER e TOKEN no inicio do arquivo")
end

local function ask(prompt)
  local response, err = http.post(SERVER .. "/plan", textutils.serialiseJSON({prompt=prompt}), {
    ["Content-Type"] = "application/json", ["X-Miner-Token"] = TOKEN,
    ["ngrok-skip-browser-warning"] = "true"
  })
  if not response then error("Conexao: " .. tostring(err)) end
  local body = response.readAll()
  local status = response.getResponseCode()
  response.close()
  local data = textutils.unserialiseJSON(body)
  if status ~= 200 then error("Servidor " .. status .. ": " .. tostring(data and data.error or body)) end
  return data
end

local function inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

local function clear(inspect, dig)
  local block, info = inspect()
  if not block then return true end
  local name = info and info.name or ""
  if name:find("lava") or name:find("water") then return false, "Liquido detectado: " .. name end
  local ok, reason = dig()
  if not ok then return false, reason or "Nao foi possivel minerar" end
  return true
end

local function returnHome(moved)
  turtle.turnLeft()
  turtle.turnLeft()
  for i = 1, moved do
    local ok, reason = turtle.forward()
    if not ok then
      print("Retorno bloqueado apos " .. (i - 1) .. " blocos: " .. tostring(reason))
      return false
    end
  end
  turtle.turnLeft()
  turtle.turnLeft()
  return true
end

local function tunnel(length)
  local fuel = turtle.getFuelLevel()
  if type(fuel) == "number" and fuel < length * 2 then
    print("Combustivel insuficiente: precisa de pelo menos " .. length * 2)
    return
  end
  local moved, reason = 0, nil
  for i = 1, length do
    if inventoryFull() then reason = "Inventario cheio"; break end
    local ok, why = clear(turtle.inspect, turtle.dig)
    if not ok then reason = why; break end
    ok, why = turtle.forward()
    if not ok then reason = why or "Caminho bloqueado"; break end
    moved = moved + 1
    ok, why = clear(turtle.inspectUp, turtle.digUp)
    if not ok then reason = why; break end
    print("Minerado: " .. i .. "/" .. length)
  end
  local returned = returnHome(moved)
  if reason then print("Interrompido: " .. reason) end
  if returned then print("Voltou ao ponto inicial. Avanco: " .. moved .. " blocos") end
end

print("Descreva a tarefa (ex.: abra um tunel de 12 blocos):")
local prompt = read()
local plan = ask(prompt)
if type(plan) ~= "table" or plan.task ~= "tunnel" or type(plan.length) ~= "number"
   or plan.length % 1 ~= 0 or plan.length < 1 or plan.length > 64 then
  print("Pedido nao suportado. Exemplo: abra um tunel de 12 blocos.")
  return
end
print("Plano: tunel de 2 blocos de altura por " .. plan.length .. " de comprimento.")
write("Executar? (sim/nao): ")
if read():lower() ~= "sim" then print("Cancelado"); return end
tunnel(plan.length)
