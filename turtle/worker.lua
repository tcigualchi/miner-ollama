local cfg = require("config")
local nav = require("lib.nav")
local inv = require("lib.inventory")
local net = require("lib.net")
local builder = require("lib.builder")

net.open()

local function status(state, extra)
  local x, y, z = gps.locate(2)
  net.send(cfg.controller_id, {
    type = "status",
    id = os.getComputerID(),
    name = cfg.turtle_name,
    state = state,
    x=x, y=y, z=z,
    fuel=turtle.getFuelLevel(),
    inventory=inv.summary(),
    extra=extra
  }, cfg.protocol)
end

print("CC Fleet Worker")
print("ID:", os.getComputerID())
print("Nome:", cfg.turtle_name)

local ok, err = pcall(nav.calibrate)
if not ok then
  print("Aviso de calibracao:", err)
else
  print("GPS/orientacao OK")
end

status("IDLE", { boot = true })

while true do
  local sender, msg = rednet.receive(cfg.protocol, cfg.status_interval or 5)

  if sender and type(msg) == "table" then
    if cfg.controller_id == 0 or sender == cfg.controller_id then
      if msg.cmd == "ping" then
        status("IDLE", { pong = true })

      elseif msg.cmd == "goto" then
        status("MOVING", { target = msg.target })
        local t = msg.target
        local okMove, why = nav.gotoXYZ(t.x, t.y, t.z, {dig = msg.dig == true})
        if okMove then
          status("IDLE", { arrived = t })
        else
          status("ERROR", { error = why })
        end

      elseif msg.cmd == "build" then
        local okBuild, why = builder.buildPlan(msg.plan_id)
        if not okBuild then
          print("Erro:", why)
          status("ERROR", { error = why, plan_id = msg.plan_id })
        end

      elseif msg.cmd == "reboot" then
        os.reboot()
      end
    end
  else
    status("IDLE")
  end
end
