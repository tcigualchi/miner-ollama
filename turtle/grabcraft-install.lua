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
print("ID do computador CC que executara o despachante de materiais (Enter para configurar depois):")
write("> ")
local station_id=tonumber(read())
local supply_secret=nil
local supply_station=nil
if station_id then
  print("Chave compartilhada do despachante (minimo 8 caracteres):")
  write("> ")
  supply_secret=read()
  if #supply_secret<8 then
    print("Chave curta; integracao AE2 desativada nesta instalacao.")
    station_id=nil
    supply_secret=nil
  end
end
local use_supply_station=station_id~=nil
if not use_supply_station then
  print("Configurar um bau manual de abastecimento sob a Turtle? (s/n)")
  write("> ")
  use_supply_station=read():lower():sub(1,1)=="s"
end
if use_supply_station then
  print("Capturando a posicao GPS desta Turtle como ponto do bau. Deixe-a em cima do bau de abastecimento.")
  local previous=nil
  for _=1,20 do
    local x,y,z=gps.locate(3)
    if x then
      local point={x=math.floor(x+0.5),y=math.floor(y+0.5),z=math.floor(z+0.5)}
      if previous and previous.x==point.x and previous.y==point.y and previous.z==point.z then
        supply_station=point
        break
      end
      previous=point
    else
      previous=nil
    end
    sleep(1)
  end
  if not supply_station then
    print("GPS nao confirmou a posicao do bau. Digite X Y Z separados por espaco:")
    write("> ")
    local line=read()
    local x,y,z=line:match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$")
    if x then supply_station={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
    else print("Coordenadas invalidas; abastecimento por bau desativado."); station_id=nil; supply_secret=nil end
  end
end
local config = fs.open("/.grabcraft", "w")
config.write(textutils.serialize({
  server = server,
  token = token,
  auto_refuel = true,
  fuel_reserve = 120,
  fuel_items = {"minecraft:coal", "minecraft:charcoal"},
  supply_computer_id = station_id,
  supply_secret = supply_secret,
  supply_station = supply_station,
}, {compact = true}))
config.close()
print("Instalado. Use: grabcraft <link-direto-do-blueprint>")
if station_id then print("Abastecimento automatico configurado para o computador "..station_id..".") end
