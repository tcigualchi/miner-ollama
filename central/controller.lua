local cfg = require("config")

peripheral.find("modem", function(name, modem)
  if modem.isWireless() then rednet.open(name) end
end)
if not rednet.isOpen() then error("Nenhum modem wireless.") end

local turtles = {}

local function apiRequest(url, method, body)
  local headers = {
    ["X-Fleet-Token"] = cfg.fleet_token,
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json"
  }
  if method == "GET" then
    local h, err = http.get(url, headers)
    if not h then return nil, err end
    local code = h.getResponseCode()
    local txt = h.readAll()
    h.close()
    if code == 204 then return {} end
    if code < 200 or code >= 300 then return nil, "HTTP " .. code .. ": " .. txt end
    return textutils.unserializeJSON(txt)
  else
    local h, err = http.post(url, body or "{}", headers)
    if not h then return nil, err end
    local code = h.getResponseCode()
    local txt = h.readAll()
    h.close()
    if code < 200 or code >= 300 then return nil, "HTTP " .. code .. ": " .. txt end
    if txt == "" then return {} end
    return textutils.unserializeJSON(txt)
  end
end

local function postStatus(turtleId, msg)
  local body = textutils.serializeJSON({
    controller_id = os.getComputerID(),
    turtle_id = turtleId,
    name = msg.name,
    label = msg.label,
    state = msg.state,
    x = msg.x, y = msg.y, z = msg.z,
    fuel = msg.fuel,
    inventory = msg.inventory or {},
    extra = msg.extra or {},
    timestamp = msg.timestamp or os.epoch("utc")
  })
  apiRequest(cfg.server_url .. "/api/status", "POST", body)
end

local function forwardCommand(cmd)
  local tid = tonumber(cmd.turtle_id)
  if tid == nil then return false, "turtle_id invalido" end
  if cmd.command == "build" then
    return rednet.send(tid, {cmd="build", plan_id=cmd.plan_id}, cfg.protocol)
  elseif cmd.command == "goto" then
    return rednet.send(tid, {cmd="goto", target={x=cmd.x, y=cmd.y, z=cmd.z}, dig=cmd.dig == true}, cfg.protocol)
  elseif cmd.command == "dig_line" then
    return rednet.send(tid, {cmd="dig_line", length=cmd.length, height=cmd.height or 2}, cfg.protocol)
  elseif cmd.command == "quarry" then
    return rednet.send(tid, {cmd="quarry", width=cmd.width, depth=cmd.depth, height=cmd.height or 2}, cfg.protocol)
  elseif cmd.command == "ping" then
    return rednet.send(tid, {cmd="ping"}, cfg.protocol)
  elseif cmd.command == "reboot" then
    return rednet.send(tid, {cmd="reboot"}, cfg.protocol)
  end
  return false, "comando desconhecido"
end

local function printDashboard()
  term.setCursorPos(1,1)
  term.clear()
  print("CC Fleet Central v2 - ID " .. os.getComputerID())
  print(string.rep("-", 45))
  local count = 0
  for id, t in pairs(turtles) do
    count = count + 1
    print(("#%d %-14s %-10s %s,%s,%s fuel:%s"):format(
      id, tostring(t.name or "?"), tostring(t.state or "?"),
      tostring(t.x or "?"), tostring(t.y or "?"), tostring(t.z or "?"),
      tostring(t.fuel or "?")
    ))
  end
  if count == 0 then print("Nenhuma turtle reportada ainda.") end
  print("")
  print("Comandos: list | ping <id> | goto <id> <x> <y> <z>")
  print("          dig <id> <len> [altura]")
  print("          quarry <id> <w> <d> [altura]")
  print("          build <id> <plan_id> | reboot <id>")
end

local function receiver()
  while true do
    local sender, msg = rednet.receive(cfg.protocol)
    if type(msg) == "table" and msg.type == "status" then
      msg.last_seen = os.epoch("utc")
      turtles[sender] = msg
      printDashboard()
      postStatus(sender, msg)
    elseif type(msg) == "table" and msg.type == "remote_cmd" then
      local ok, why = forwardCommand(msg)
      rednet.send(sender, { type="remote_reply", ok=ok == true, message=tostring(why or "") }, cfg.protocol)
    end
  end
end

local function webPoller()
  while true do
    local url = cfg.server_url .. "/api/commands/next?controller_id=" .. os.getComputerID()
    local cmd = apiRequest(url, "GET")
    if cmd and cmd.id then
      local ok, why = forwardCommand(cmd)
      apiRequest(cfg.server_url .. "/api/commands/" .. cmd.id .. "/ack", "POST", textutils.serializeJSON({ok=ok == true, message=tostring(why or "")}))
    end
    sleep(cfg.poll_seconds or 2)
  end
end

local function console()
  printDashboard()
  while true do
    write("> ")
    local line = read()
    local a = {}
    for w in line:gmatch("%S+") do table.insert(a, w) end

    if a[1] == "list" then
      printDashboard()
    elseif a[1] == "ping" and a[2] then
      forwardCommand({command="ping", turtle_id=tonumber(a[2])})
    elseif a[1] == "goto" and #a >= 5 then
      forwardCommand({command="goto", turtle_id=tonumber(a[2]), x=tonumber(a[3]), y=tonumber(a[4]), z=tonumber(a[5]), dig=false})
    elseif a[1] == "dig" and #a >= 3 then
      forwardCommand({command="dig_line", turtle_id=tonumber(a[2]), length=tonumber(a[3]), height=tonumber(a[4]) or 2})
    elseif a[1] == "quarry" and #a >= 4 then
      forwardCommand({command="quarry", turtle_id=tonumber(a[2]), width=tonumber(a[3]), depth=tonumber(a[4]), height=tonumber(a[5]) or 2})
    elseif a[1] == "build" and #a >= 3 then
      forwardCommand({command="build", turtle_id=tonumber(a[2]), plan_id=a[3]})
    elseif a[1] == "reboot" and a[2] then
      forwardCommand({command="reboot", turtle_id=tonumber(a[2])})
    elseif a[1] == "help" then
      print("list")
      print("ping <id>")
      print("goto <id> <x> <y> <z>")
      print("dig <id> <len> [altura]")
      print("quarry <id> <w> <d> [altura]")
      print("build <id> <plan_id>")
      print("reboot <id>")
    end
  end
end

parallel.waitForAny(receiver, webPoller, console)
