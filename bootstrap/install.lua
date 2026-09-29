-- CC Fleet OS bootstrap. Usage:
-- wget run https://YOUR-SERVER/bootstrap/install.lua https://YOUR-SERVER ENROLLMENT_TOKEN "Turtle name"
local args = {...}
local server = args[1]
local enrollment = args[2]
local name = args[3] or ("turtle-" .. os.getComputerID())
local dimension = args[4] or "minecraft:overworld"

if not server or not enrollment then
  print("Uso: wget run <url>/bootstrap/install.lua <url-do-servidor> <token-de-cadastro> [nome]")
  return
end
server = server:gsub("/$", "")
if not http.checkURL(server .. "/health") then
  print("URL do servidor bloqueada. Ative HTTP e permita o dominio no config do CC:Tweaked.")
  return
end

local function request(url, body, headers)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local h, err = http.post(url, body, headers)
  if not h then return nil, err end
  local code, message = h.getResponseCode()
  local text = h.readAll()
  h.close()
  if code < 200 or code >= 300 then return nil, "HTTP " .. code .. ": " .. text end
  return textutils.unserializeJSON(text)
end

local info, err = request(server .. "/api/agents/register", textutils.serializeJSON({
  computer_id = os.getComputerID(),
  name = name,
  dimension = dimension,
  capabilities = {"gps", "move", "mine", "build", "inventory"},
}), {["X-Enrollment-Token"] = enrollment})
if not info then print("Cadastro falhou: " .. tostring(err)); return end

local root = "/fleet"
if not fs.exists(root) then fs.makeDir(root) end
if not fs.exists(root .. "/lib") then fs.makeDir(root .. "/lib") end
local config = {
  server_url = server, agent_id = info.agent_id, agent_token = info.agent_token,
  name = name, dimension = dimension, gps_timeout = 2,
  poll_seconds = info.poll_seconds or 2, heartbeat_seconds = 3,
  low_fuel_reserve = 120, update_seconds = 900,
}
local h = fs.open(root .. "/config.lua", "w")
h.write("return " .. textutils.serialize(config, {compact = false}))
h.close()

local function download(relative)
  local response, why = http.get(server .. "/agent/" .. relative)
  if not response then return false, why end
  local target = root .. "/" .. relative
  local parent = fs.getDir(target)
  if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
  local temp = target .. ".new"
  local out = fs.open(temp, "w")
  out.write(response.readAll())
  out.close(); response.close()
  if fs.exists(target) then fs.delete(target) end
  fs.move(temp, target)
  return true
end

local manifest = {"agent.lua", "startup.lua", "lib/state.lua", "lib/net.lua", "lib/gps.lua", "lib/movement.lua", "lib/navigation.lua", "lib/inventory.lua", "lib/fuel.lua", "lib/tasks.lua", "lib/mining.lua", "lib/building.lua", "lib/update.lua"}
for _, file in ipairs(manifest) do
  local ok, why = download(file)
  if not ok then print("Falha ao baixar " .. file .. ": " .. tostring(why)); return end
end

local versionFile = fs.open(root .. "/version", "w")
versionFile.write(info.version)
versionFile.close()

local startup = fs.open("startup", "w")
startup.write('shell.run("/fleet/startup.lua")\n')
startup.close()
print("CC Fleet OS instalado: " .. info.agent_id)
print("A Turtle aparecerá no painel após iniciar.")
shell.run(root .. "/startup.lua")
