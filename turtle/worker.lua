local cfg = require("config")
local nav = require("lib.nav")
local inv = require("lib.inventory")
local net = require("lib.net")
local builder = require("lib.builder")
local miner = require("lib.miner")

net.open()

local lastState = "BOOTING"
local lastExtra = {
  boot = true
}

local function status(state, extra)
  lastState = state or lastState
  lastExtra = extra or lastExtra or {}

  local x, y, z = gps.locate(1)

  net.send(cfg.controller_id, {
    type = "status",
    id = os.getComputerID(),
    name = cfg.turtle_name,
    state = lastState,
    x = x,
    y = y,
    z = z,
    fuel = turtle.getFuelLevel(),
    inventory = inv.summary(),
    extra = lastExtra,
    label = os.getComputerLabel(),
    timestamp = os.epoch("utc")
  }, cfg.protocol)
end

print("CC Fleet Worker v2.3")
print("ID:", os.getComputerID())
print("Nome:", cfg.turtle_name)

local ok, err = pcall(nav.calibrate)

if not ok then
  print("Aviso de calibracao:", err)
else
  print("GPS/orientacao OK")
end

status("IDLE", {
  boot = true
})

local function handleCommand(msg)
  if msg.cmd == "ping" then
    status("IDLE", {
      pong = true
    })

    return
  end

  if msg.cmd == "goto" then
    status("MOVING", {
      action = "goto",
      target = msg.target,
      dig = msg.dig == true
    })

    local t = msg.target

    local okMove, why = nav.gotoXYZ(
      t.x,
      t.y,
      t.z,
      {
        dig = msg.dig == true
      }
    )

    if okMove then
      status("IDLE", {
        action = "goto_completed",
        arrived = t
      })
    else
      status("ERROR", {
        action = "goto_failed",
        error = why,
        command = "goto"
      })
    end

    return
  end

  if msg.cmd == "build" then
    status("BUILDING", {
      action = "loading_plan",
      plan_id = msg.plan_id
    })

    local okBuild, why = builder.buildPlan(
      msg.plan_id,
      status
    )

    if okBuild then
      status("IDLE", {
        action = "build_completed",
        completed_plan = msg.plan_id,
        progress = 100
      })
    else
      status("ERROR", {
        action = "build_failed",
        error = why,
        plan_id = msg.plan_id,
        command = "build"
      })
    end

    return
  end

  if msg.cmd == "dig_line" then
    status("DIGGING", {
      action = "starting",
      length = msg.length,
      height = msg.height
    })

    local okDig, why = miner.digLine(
      msg.length,
      msg.height,
      status
    )

    if okDig then
      status("IDLE", {
        action = "dig_line_completed",
        completed = "dig_line",
        length = msg.length,
        progress = 100
      })
    else
      status("ERROR", {
        action = "dig_line_failed",
        error = why,
        command = "dig_line"
      })
    end

    return
  end

  if msg.cmd == "quarry" then
    status("QUARRY", {
      action = "starting",
      width = msg.width,
      depth = msg.depth,
      height = msg.height
    })

    local okQ, why = miner.quarry(
      msg.width,
      msg.depth,
      msg.height,
      status
    )

    if okQ then
      status("IDLE", {
        action = "quarry_completed",
        completed = "quarry",
        width = msg.width,
        depth = msg.depth,
        height = msg.height,
        progress = 100
      })
    else
      status("ERROR", {
        action = "quarry_failed",
        error = why,
        command = "quarry"
      })
    end

    return
  end

  if msg.cmd == "reboot" then
    status("REBOOTING", {
      action = "reboot"
    })

    sleep(0.2)
    os.reboot()
  end
end

local function heartbeatLoop()
  while true do
    sleep(cfg.status_interval or 1)
    status(lastState, lastExtra)
  end
end

local function listenLoop()
  while true do
    local sender, msg = rednet.receive(
      cfg.protocol,
      cfg.status_interval or 1
    )

    if sender and type(msg) == "table" then
      if cfg.controller_id == 0 or sender == cfg.controller_id then
        handleCommand(msg)
      end
    end
  end
end

parallel.waitForAny(
  listenLoop,
  heartbeatLoop
)
