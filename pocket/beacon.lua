-- Player GPS beacon. Keep this running on a Pocket Computer carried by the player.
local args = {...}
local server, token, player, dimension = args[1], args[2], args[3], args[4] or "minecraft:overworld"
if not server or not token or not player then
  print("Usage: beacon <server-url> <pocket-token> <player-name> [dimension]")
  return
end
server = server:gsub("/$", "")
local lastError = nil
while true do
  local x,y,z = gps.locate(2)
  if x then
    local h,err = http.post(server.."/api/player/location", textutils.serializeJSON({
      name=player,x=x,y=y,z=z,dimension=dimension
    }), { ["Content-Type"]="application/json", ["X-Player-Token"]=token })
    if h then
      local code=h.getResponseCode()
      local body=h.readAll()
      h.close()
      if code<200 or code>=300 then
        local message="HTTP "..code..": "..body
        if message~=lastError then print("Beacon: "..message) end
        lastError=message
      else
        lastError=nil
      end
    else
      local message="connection: "..tostring(err)
      if message~=lastError then print("Beacon: "..message) end
      lastError=message
    end
  else
    if lastError~="GPS unavailable" then print("Beacon: GPS unavailable") end
    lastError="GPS unavailable"
  end
  sleep(3)
end
