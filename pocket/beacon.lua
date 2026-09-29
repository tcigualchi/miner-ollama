-- Player GPS beacon. Put on a Pocket Computer carried by the player.
local args = {...}
local server, token, player, dimension = args[1], args[2], args[3], args[4] or "minecraft:overworld"
if not server or not token or not player then
  print("Uso: beacon <url-servidor> <token-beacon> <nome-do-jogador>")
  return
end
server = server:gsub("/$","")
while true do
  local x,y,z = gps.locate(2)
  if x then
    local h,err = http.post(server.."/api/player/location", textutils.serializeJSON({
      name=player,x=x,y=y,z=z,dimension=dimension
    }), {["Content-Type"]="application/json",["X-Player-Token"]=token})
    if h then h.close() else print("Beacon: "..tostring(err)) end
  else
    print("Beacon: GPS indisponível")
  end
  sleep(3)
end
