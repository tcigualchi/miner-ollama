local cfg = require("config")

peripheral.find("modem", function(name, modem)
  if modem.isWireless() then rednet.open(name) end
end)
if not rednet.isOpen() then error("Pocket Computer precisa de modem wireless.") end
if cfg.controller_id == 0 then error("Configure controller_id em config.lua") end

local function send(cmd)
  cmd.type = "remote_cmd"
  local ok = rednet.send(cfg.controller_id, cmd, cfg.protocol)
  if not ok then
    print("Falha ao enviar ao PC central.")
    sleep(2)
    return
  end

  local sender, reply = rednet.receive(cfg.protocol, 2)
  if sender == cfg.controller_id and type(reply) == "table" and reply.type == "remote_reply" then
    print(reply.ok and "Comando encaminhado." or ("Falhou: " .. tostring(reply.message)))
  else
    print("Enviado; sem confirmacao do central.")
  end
  sleep(1.5)
end

while true do
  term.clear()
  term.setCursorPos(1,1)
  print("CC Fleet Pocket")
  print("Central #" .. cfg.controller_id)
  print("1 - Ping turtle")
  print("2 - Goto")
  print("3 - Build plan")
  print("4 - Reboot turtle")
  print("5 - Sair")
  write("> ")
  local c = read()

  if c == "1" then
    write("Turtle ID: ")
    send({command="ping", turtle_id=tonumber(read())})

  elseif c == "2" then
    write("Turtle ID: "); local id = tonumber(read())
    write("X: "); local x = tonumber(read())
    write("Y: "); local y = tonumber(read())
    write("Z: "); local z = tonumber(read())
    send({command="goto", turtle_id=id, x=x, y=y, z=z, dig=false})

  elseif c == "3" then
    write("Turtle ID: "); local id = tonumber(read())
    write("Plan ID: "); local pid = read()
    send({command="build", turtle_id=id, plan_id=pid})

  elseif c == "4" then
    write("Turtle ID: ")
    send({command="reboot", turtle_id=tonumber(read())})

  elseif c == "5" then
    return
  end
end
