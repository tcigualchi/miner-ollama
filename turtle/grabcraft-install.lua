-- One-time installer: wget run https://TUNNEL/install.lua https://TUNNEL TOKEN
local args = {...}
local server = (args[1] or ""):gsub("/$", "")
local token = args[2]
if server == "" or not token then
  print("Uso: wget run <ngrok-url>/install.lua <ngrok-url> <token-do-inspector>")
  return
end
if not http.checkURL(server .. "/grabcraft.lua") then
  print("URL bloqueada. Ative HTTP no CC:Tweaked e permita o dominio ngrok.")
  return
end
local response, err = http.get(server .. "/grabcraft.lua")
if not response then print("Download falhou: " .. tostring(err)); return end
local code, message = response.getResponseCode()
local source = response.readAll()
response.close()
if code < 200 or code >= 300 then print("Download falhou: HTTP " .. tostring(code) .. " " .. tostring(message)); return end
local file = fs.open("/grabcraft.lua", "w")
file.write(source)
file.close()
local config = fs.open("/.grabcraft", "w")
config.write(textutils.serialize({server = server, token = token}, {compact = true}))
config.close()
print("Instalado. Use: grabcraft <link-direto-do-blueprint>")
