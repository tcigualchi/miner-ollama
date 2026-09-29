package.path = "/fleet/?.lua;/fleet/?/init.lua;" .. package.path

local cfg = require("config")
local state = require("lib.state")
local net = require("lib.net")
local gps = require("lib.gps")
local inventory = require("lib.inventory")
local fuel = require("lib.fuel")
local tasks = require("lib.tasks")
local updater = require("lib.update")

local function report(status)
  local pos = gps.locate()
  local saved = state.read()
  local x,y,z
  if pos.gps ~= false then x,y,z=pos.x,pos.y,pos.z end
  local reported_status=status or saved.status or "IDLE"
  if pos.gps == false and reported_status == "IDLE" then reported_status="GPS_UNAVAILABLE" end
  net.heartbeat({
    state = reported_status,
    x = x, y = y, z = z,
    heading = pos.heading,
    dimension = cfg.dimension,
    fuel = turtle.getFuelLevel(),
    inventory = inventory.summary(),
    current_task_id = saved.task_id,
    base = cfg.base or {},
    capabilities = {"gps", "move", "mine", "build", "inventory", "recover"},
  })
end

local function run()
  if updater.try() then os.reboot() end
  report("IDLE")
  local last_update=os.epoch("utc")
  while true do
    local saved = state.read()
    local task, why
    if saved.task_id then
      task, why = net.get_task(saved.task_id)
      if not task and why ~= "empty" then state.write({status = "IDLE"}) end
    end
    if not task then task = net.next_task() end
    if task then
      local activity=({mine_area="MINING",clear_area="EXPLORING",build_wall="BUILDING",
        build_house="BUILDING",build_bridge="BUILDING",["goto"]="EXPLORING",
        follow_player="EXPLORING",return_base="RETURNING"})[task.kind] or "WORKING"
      state.write({task_id = task.id, status = activity or "WORKING", checkpoint = saved.checkpoint or {}})
      local finished,ok,result=false,false,nil
      parallel.waitForAny(function()
        ok,result=xpcall(function() return tasks.execute(task) end, debug.traceback)
        finished=true
      end,function()
        while not finished do sleep(cfg.heartbeat_seconds or 3); if not finished then report(activity) end end
      end)
      if ok then
        net.progress(task.id, "DONE", 100, result or "Tarefa concluída", state.read().checkpoint)
        state.write({status = "IDLE"})
      else
        local message = tostring(result)
        local lower=message:lower()
        local follow_retry=task.kind=="follow_player" and (lower:find("conflict",1,true)
          or lower:find("http 404",1,true) or lower:find("http 409",1,true)
          or lower:find("not found",1,true) or lower:find("could not connect",1,true)
          or lower:find("timed out",1,true) or lower:find("continuou se movendo",1,true))
        local recoverable = message:find("combustível", 1, true) or message:find("inventário cheio", 1, true)
          or message:find("GPS indisponível", 1, true) or message:find("beacon", 1, true)
          or message:find("bloqueado", 1, true) or message:find("base não configurada", 1, true) or follow_retry
        if recoverable then
          net.progress(task.id, "BLOCKED", 0, message, state.read().checkpoint, "WARN")
          state.write({status = "BLOCKED"})
          for _=1,10 do sleep(3); report("BLOCKED") end
        else
          net.progress(task.id, "FAILED", 0, message, state.read().checkpoint, "ERROR")
          state.write({status = "IDLE"})
        end
      end
      report(state.read().status)
    else
      report("IDLE")
      if os.epoch("utc")-last_update >= (cfg.update_seconds or 900)*1000 then
        last_update=os.epoch("utc")
        local updated,why=updater.try()
        if updated then os.reboot() end
        if why then print("Atualização adiada: "..tostring(why)) end
      end
      sleep(cfg.poll_seconds)
    end
  end
end

while true do
  local ok, err = xpcall(run, debug.traceback)
  print("Agente reiniciará: " .. tostring(err))
  sleep(5)
end
