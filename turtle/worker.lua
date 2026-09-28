local cfg = require("config")
local nav = require("lib.nav")
local inv = require("lib.inventory")
local net = require("lib.net")
local builder = require("lib.builder")
local miner = require("lib.miner")

net.open()

local lastState = "BOOTING"
local lastExtra = { boot = true }

local function status(state, extra)
  lastState = state or lastState
  lastExtra = extra or lastExtra or {}
  local x, y, z = gps.locate(2)
  net.send(cfg.controller_id, {
    type = "status",
    id = os.getComputerID(),
    name = cfg.turtle_name,
    state = lastState,
    x=x, y=y, z=z,
    fuel=turtle.getFuelLevel(),
    inventory=inv.summary(),
    extra=lastExtra,
    label=os.getComputerLabel(),
    timestamp=os.epoch("utc")
  }, cfg.protocol)
end

print("CC Fleet Worker v2")
print("ID:", os.getComputerID())
print("Nome:", cfg.turtle_name)

local ok, err = pcall(nav.calibrate)
if not ok then
  print("Aviso de calibracao:", err)
else
  print("GPS/orientacao OK")
end

status("IDLE", { boot = true })

local function handleCommand(msg)
  if msg.cmd == "ping" then
    status("IDLE", { pong = true })
    return
  elseif msg.cmd == "goto" then
    status("MOVING", { target = msg.target, dig = msg.dig == true })
    local t = msg.target
    local okMove, why = nav.gotoXYZ(t.x, t.y, t.z, {dig = msg.dig == true})
    if okMove then
      status("IDLE", { arrived = t })
    else
      status("ERROR", { error = why, command = "goto" })
    end
    return
  elseif msg.cmd == "build" then
    local okBuild, why = builder.buildPlan(msg.plan_id)
    if okBuild then
      status("IDLE", { completed_plan = msg.plan_id })
    else
      status("ERROR", { error = why, plan_id = msg.plan_id, command = "build" })
    end
    return
  elseif msg.cmd == "dig_line" then
    status("DIGGING", { length = msg.length, height = msg.height })
    local okDig, why = miner.digLine(msg.length, msg.height)
    if okDig then
      status("IDLE", { completed = "dig_line", length = msg.length })
    else
      status("ERROR", { error = why, command = "dig_line" })
    end
    return
  elseif msg.cmd == "quarry" then
    status("QUARRY", { width = msg.width, depth = msg.depth, height = msg.height })
    local okQ, why = miner.quarry(msg.width, msg.depth, msg.height)
    if okQ then
      status("IDLE", { completed = "quarry", width = msg.width, depth = msg.depth, height = msg.height })
    else
      status("ERROR", { error = why, command = "quarry" })
    end
    return
  elseif msg.cmd == "reboot" then
    os.reboot()
  end
end

local function heartbeatLoop()
  while true do
    sleep(cfg.status_interval or 5)
    status(lastState, lastExtra)
  end
end

local function listenLoop()
  while true do
    local sender, msg = rednet.receive(cfg.protocol, cfg.status_interval or 5)
    if sender and type(msg) == "table" then
      if cfg.controller_id == 0 or sender == cfg.controller_id then
        handleCommand(msg)
      end
    end
  end
end

parallel.waitForAny(listenLoop, heartbeatLoop)
