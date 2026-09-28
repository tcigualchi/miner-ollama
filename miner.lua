-- Configure os dois valores abaixo. Nao publique seu token em repositorio publico.
local SERVER = "https://SEU-ENDERECO.ngrok-free.dev"
local TOKEN = "COLOQUE_O_MESMO_TOKEN_DO_SERVIDOR"

if not turtle then error("Execute em uma Mining Turtle") end
if not http then error("Ative HTTP no CC: Tweaked") end
if SERVER:find("SEU%-ENDERECO") or TOKEN == "COLOQUE_O_MESMO_TOKEN_DO_SERVIDOR" then
  error("Configure SERVER e TOKEN no inicio do arquivo")
end
SERVER = SERVER:gsub("/+$", "")

local heading, x, y, z = 0, 0, 0, 0 -- norte arbitrario; sem GPS
local labels = {"norte", "leste", "sul", "oeste"}
local collected = {}
local progress, total, estimate, status = 0, 0, 0, "Aguardando comando"
local headers = {
  ["Content-Type"] = "application/json",
  ["X-Miner-Token"] = TOKEN,
  ["ngrok-skip-browser-warning"] = "true"
}

local function request(route, data, seconds)
  local response, err, failed = http.post {
    url = SERVER .. route,
    body = textutils.serialiseJSON(data),
    headers = headers,
    timeout = seconds
  }
  local handle = response or failed
  if not handle then return nil, "Conexao: " .. tostring(err) end
  local body, code = handle.readAll(), handle.getResponseCode()
  handle.close()
  local parsed = textutils.unserialiseJSON(body)
  if code ~= 200 then
    return nil, "Servidor " .. code .. ": " .. tostring(parsed and parsed.error or body)
  end
  return parsed
end

local function inventory()
  local slots, counts = {}, {}
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail then
      slots[#slots + 1] = {slot = slot, name = detail.name, count = detail.count}
      counts[detail.name] = (counts[detail.name] or 0) + detail.count
    end
  end
  return slots, counts
end

local function report(before)
  local slots, counts = inventory()
  if before then
    for name, count in pairs(counts) do
      local gained = count - (before[name] or 0)
      if gained > 0 then collected[name] = (collected[name] or 0) + gained end
    end
  end
  local _, err = request("/telemetry", {
    status = status, inventory = slots, collected = collected,
    heading = labels[heading + 1], position = {x = x, y = y, z = z},
    fuel = turtle.getFuelLevel(), progress = progress, total = total, estimate = estimate
  }, 8)
  if err then print("Painel: " .. err) end
  return counts
end

local fuelItems = {
  ["minecraft:coal"] = true, ["minecraft:charcoal"] = true,
  ["minecraft:coal_block"] = true, ["minecraft:lava_bucket"] = true
}
local function refuelFromInventory()
  local selected = turtle.getSelectedSlot()
  local before = select(2, inventory())
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and fuelItems[item.name] then
      turtle.select(slot)
      turtle.refuel(item.count)
    end
  end
  turtle.select(selected)
  report(before)
end

local function ensureFuel(needed)
  local limit = turtle.getFuelLimit()
  if type(limit) == "number" and needed > limit then return false end
  while type(turtle.getFuelLevel()) == "number" and turtle.getFuelLevel() < needed do
    refuelFromInventory()
    if turtle.getFuelLevel() >= needed then break end
    status = "Aguardando combustivel (precisa " .. needed .. ", tem " .. turtle.getFuelLevel() .. ")"
    report()
    print(status)
    print("Coloque carvao/carvao vegetal/bloco de carvao/balde de lava no inventario.")
    write("Depois pressione Enter para continuar: ")
    read()
  end
  return true
end

local function turnLeft()
  if turtle.turnLeft() then heading = (heading + 3) % 4; return true end
  return false
end
local function turnRight()
  if turtle.turnRight() then heading = (heading + 1) % 4; return true end
  return false
end
local function face(direction)
  if direction == "esquerda" then return turnLeft() end
  if direction == "direita" then return turnRight() end
  if direction == "tras" then return turnRight() and turnRight() end
  return true
end
local function advance()
  local ok, err = turtle.forward()
  if ok then
    if heading == 0 then z = z - 1
    elseif heading == 1 then x = x + 1
    elseif heading == 2 then z = z + 1
    else x = x - 1 end
  end
  return ok, err
end
local function climb(direction)
  local ok, err
  if direction == "cima" then ok, err = turtle.up()
  else ok, err = turtle.down() end
  if ok then y = y + (direction == "cima" and 1 or -1) end
  return ok, err
end
local function occupied()
  for slot = 1, 16 do
    if turtle.getItemSpace(slot) > 0 then return false end
  end
  return true
end
local function inspectAndDig(inspect, dig, target)
  local found, block = inspect()
  if not found then return true end
  local name = block and block.name or ""
  if name:find("lava") or name:find("water") then
    return false, "Liquido detectado: " .. name
  end
  if target ~= "" and name ~= target then
    return false, "Bloco diferente no caminho: " .. name
  end
  local ok, err = dig()
  if not ok then return false, err or "Nao foi possivel minerar " .. name end
  return true
end

local function returnHome(steps, direction)
  status = "Retornando"
  report()
  local vertical = direction == "cima" or direction == "baixo"
  if not vertical and not (turnRight() and turnRight()) then return false end
  for i = 1, steps do
    ensureFuel(1)
    local ok, err
    if vertical then ok, err = climb(direction == "cima" and "baixo" or "cima")
    else ok, err = advance() end
    if not ok then
      status = "Retorno bloqueado: " .. tostring(err)
      report()
      return false
    end
    report()
  end
  if not vertical then turnRight(); turnRight() end
  return true
end

local function placeBlock(plan)
  local slot
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and item.name == plan.block and item.count > 0 then slot = i; break end
  end
  if not slot then status = "Item nao encontrado: " .. plan.block; print(status); report(); return end
  if not face(plan.direction) then status = "Falha ao girar"; report(); return end
  local selected = turtle.getSelectedSlot()
  turtle.select(slot)
  local before = select(2, inventory())
  local ok, err
  if plan.direction == "cima" then ok, err = turtle.placeUp()
  elseif plan.direction == "baixo" then ok, err = turtle.placeDown()
  else ok, err = turtle.place() end
  turtle.select(selected)
  status = ok and ("Colocado: " .. plan.block .. " " .. plan.direction)
    or ("Nao foi possivel colocar: " .. tostring(err))
  print(status)
  report(before)
end

local function execute(plan)
  if plan.task == "place" then placeBlock(plan); return end
  local fuel = turtle.getFuelLevel()
  estimate = plan.length * 2
  if type(fuel) == "number" then
    print("Ida e volta: ate " .. estimate .. " unidades de combustivel. Disponivel: " .. fuel)
  end
  local vertical = plan.direction == "cima" or plan.direction == "baixo"
  if not vertical and not face(plan.direction) then status = "Falha ao girar"; report(); return end
  total, progress = plan.length, 0
  status = "Minerando " .. plan.direction
  report()
  local target = plan.task == "mine_target" and plan.block or ""
  local steps, reason = 0, nil
  for i = 1, plan.length do
    -- Reservar combustivel para ir um passo e voltar desde o proximo ponto.
    ensureFuel(2 * (steps + 1))
    status = "Minerando " .. plan.direction
    if occupied() then reason = "Inventario cheio"; break end
    local _, before = inventory()
    local inspect, dig, move = turtle.inspect, turtle.dig, advance
    if plan.direction == "cima" then
      inspect, dig, move = turtle.inspectUp, turtle.digUp, function() return climb("cima") end
    elseif plan.direction == "baixo" then
      inspect, dig, move = turtle.inspectDown, turtle.digDown, function() return climb("baixo") end
    end
    local ok, err = inspectAndDig(inspect, dig, target)
    if not ok then reason = err; break end
    ok, err = move()
    if not ok then reason = err or "Caminho bloqueado"; break end
    steps, progress = steps + 1, i
    if target == "" and not vertical then
      ok, err = inspectAndDig(turtle.inspectUp, turtle.digUp, "")
      if not ok then reason = err end
    elseif target ~= "" and not vertical then
      for _, pair in ipairs({
        {turtle.inspectUp, turtle.digUp},
        {turtle.inspectDown, turtle.digDown}
      }) do
        local found, block = pair[1]()
        if found and block.name == target then
          ok, err = pair[2]()
          if not ok then reason = err or "Falha ao minerar alvo"; break end
        end
      end
    end
    report(before)
    print("Percorrido: " .. i .. "/" .. plan.length)
    if reason then break end
  end
  local returned = returnHome(steps, plan.direction)
  if reason then print("Interrompido: " .. reason) end
  status = returned and (reason or "Concluido") or "Retorno incompleto"
  report()
end

local function executeArea(plan)
  local width, height, depth = plan.width, plan.height, plan.depth
  local area = width * height
  local originalHeading = heading
  local trail = {}
  local column, row = 0, 0
  total, progress = area, 0
  -- Estimativa conservadora: superficie, volta e descida/subida em cada celula.
  estimate = 2 * depth * area + 2 * (width + height)
  status = "Area " .. width .. "x" .. height .. " profundidade " .. depth
  print(status .. " | estimativa de combustivel: " .. estimate)
  report()

  local function faceHeading(target)
    for i = 1, 3 do
      if heading == target then return true end
      if not turnRight() then return false end
    end
    return heading == target
  end
  local function walk(deltaColumn, deltaRow)
    local target
    if deltaColumn == 1 then target = (originalHeading + 1) % 4
    elseif deltaColumn == -1 then target = (originalHeading + 3) % 4
    elseif deltaRow == 1 then target = originalHeading
    else target = (originalHeading + 2) % 4 end
    if not faceHeading(target) then return false, "Falha ao girar" end
    if not ensureFuel(#trail + 1) then
      return false, "Limite de combustivel para voltar desta distancia"
    end
    local ok, err = advance()
    if not ok then return false, "Caminho bloqueado: " .. tostring(err) end
    trail[#trail + 1] = target
    column, row = column + deltaColumn, row + deltaRow
    return true
  end
  local function reach(targetColumn, targetRow)
    while column ~= targetColumn do
      local step = targetColumn > column and 1 or -1
      local ok, err = walk(step, 0)
      if not ok then return false, err end
    end
    while row ~= targetRow do
      local step = targetRow > row and 1 or -1
      local ok, err = walk(0, step)
      if not ok then return false, err end
    end
    return true
  end
  local function digColumn()
    local descent, reason = 0, nil
    if not ensureFuel(#trail + 2 * (depth - 1)) then
      return false, "Limite de combustivel para voltar desta profundidade", true
    end
    for level = 1, depth do
      if occupied() then reason = "Inventario cheio"; break end
      local ok, err = inspectAndDig(turtle.inspectDown, turtle.digDown, "")
      if not ok then reason = err; break end
      if level < depth then
        if not ensureFuel(#trail + 2 * (depth - level)) then
          reason = "Limite de combustivel na escavacao"; break
        end
        ok, err = climb("baixo")
        if not ok then reason = "Descida bloqueada: " .. tostring(err); break end
        descent = descent + 1
      end
    end
    for i = 1, descent do
      ensureFuel(#trail + 1)
      local ok, err = climb("cima")
      if not ok then
        status = "Retorno vertical bloqueado: " .. tostring(err)
        report()
        return false, status, false
      end
    end
    return reason == nil, reason, true
  end
  local function visit(c, r)
    local ok, err = reach(c, r)
    if not ok then return false, err, true end
    local before = select(2, inventory())
    local surface
    ok, err, surface = digColumn()
    if not surface then return false, err, false end
    if ok then progress = progress + 1 end
    status = ok and ("Escavando area: " .. progress .. "/" .. total) or err
    report(before)
    if progress % 10 == 0 then print(status) end
    return ok, err, true
  end
  local function returnTrail()
    status = "Retornando da area"
    report()
    for i = #trail, 1, -1 do
      local reverse = (trail[i] + 2) % 4
      if not faceHeading(reverse) then return false, "Falha ao girar na volta" end
      ensureFuel(1)
      local ok, err = advance()
      if not ok then return false, "Retorno bloqueado: " .. tostring(err) end
      if i % 16 == 0 then report() end
    end
    if not faceHeading(originalHeading) then return false, "Falha ao restaurar direcao" end
    return true
  end

  local ok, reason, onSurface = true, nil, true
  for c = 0, width - 1 do
    ok, reason, onSurface = visit(c, 0)
    if not ok then break end
  end
  if ok then
    for r = 1, height - 1 do
      ok, reason, onSurface = visit(width - 1, r)
      if not ok then break end
    end
  end
  if ok and height > 1 then
    for c = width - 2, 0, -1 do
      ok, reason, onSurface = visit(c, height - 1)
      if not ok then break end
    end
  end
  if ok and width > 1 then
    for r = height - 2, 1, -1 do
      ok, reason, onSurface = visit(0, r)
      if not ok then break end
    end
  end
  if ok and width > 2 and height > 2 then
    for r = 1, height - 2 do
      if r % 2 == 1 then
        for c = 1, width - 2 do
          ok, reason, onSurface = visit(c, r)
          if not ok then break end
        end
      else
        for c = width - 2, 1, -1 do
          ok, reason, onSurface = visit(c, r)
          if not ok then break end
        end
      end
      if not ok then break end
    end
  end
  if onSurface then
    local returned, err = returnTrail()
    status = returned and (reason or "Area concluida") or err
  end
  print(status)
  report()
end

report()
while true do
  print("Pedido (ex.: tunel de 5 blocos a direita; sair):")
  local prompt = read()
  if not prompt or prompt:lower() == "sair" then break end
  if prompt ~= "" then
    status = "Consultando IA"; report()
    local plan, err = request("/plan", {prompt = prompt}, 60)
    if not plan then
      status = err; print(err); report()
    elseif plan.task == "unsupported" then
      status = "Pedido nao suportado"; print(status); report()
    elseif plan.task == "area" and type(plan.width) == "number"
       and type(plan.height) == "number" and type(plan.depth) == "number"
       and plan.width % 1 == 0 and plan.height % 1 == 0 and plan.depth % 1 == 0
       and plan.width >= 1 and plan.width <= 256
       and plan.height >= 1 and plan.height <= 256
       and plan.depth >= 1 and plan.depth <= 64 then
      print("Area: " .. plan.width .. "x" .. plan.height
        .. ", profundidade " .. plan.depth .. " | contorno e interior")
      write("Executar? (sim/nao): ")
      if read():lower() == "sim" then executeArea(plan)
      else status = "Cancelado"; report() end
    elseif (plan.task == "tunnel" or plan.task == "mine_target" or plan.task == "place")
       and (plan.direction == "frente" or plan.direction == "tras"
            or plan.direction == "direita" or plan.direction == "esquerda"
            or plan.direction == "cima" or plan.direction == "baixo")
       and type(plan.length) == "number" and plan.length % 1 == 0
       and plan.length >= 1 and plan.length <= 4096
       and type(plan.block) == "string"
       and (plan.task ~= "place" or plan.length == 1)
       and (plan.task == "tunnel" or plan.block:match("^minecraft:[%w_]+$")) then
      print("Plano: " .. plan.task .. " | " .. plan.direction .. " | "
        .. plan.length .. " blocos | " .. plan.block)
      write("Executar? (sim/nao): ")
      if read():lower() == "sim" then execute(plan)
      else status = "Cancelado"; report() end
    else
      status = "Plano invalido"; print(status); report()
    end
  end
end
status = "Programa encerrado"; report()
