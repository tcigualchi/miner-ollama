-- Fetches a voxel blueprint, checks the Turtle's inventory/fuel, then builds it.
local args={...}
local url=args[1]
if not url then
  print("Uso: grabcraft <link-do-blueprint> [origemX origemY origemZ]")
  return
end
if not fs.exists("/.grabcraft") then
  print("Instale primeiro: wget run <ngrok>/install.lua <ngrok> <token>")
  return
end
local f=fs.open("/.grabcraft","r")
local config=textutils.unserialize(f.readAll()); f.close()
local fuel_reserve=tonumber(config.fuel_reserve) or 120
local fuel_item_set={}
for _,name in ipairs(config.fuel_items or {"minecraft:coal","minecraft:charcoal"}) do fuel_item_set[name]=true end
local supply_protocol="grabcraft.ae2_supply.v1"
local supply_modem=false
if tonumber(config.supply_computer_id) and type(config.supply_secret)=="string" and #config.supply_secret>=8 then
  peripheral.find("modem",function(name,modem)
    if modem.isWireless() then rednet.open(name); supply_modem=true end
  end)
end
local function refuel_for_move()
  local warned=false
  while true do
    local level=turtle.getFuelLevel()
    if level=="unlimited" then return true end
    local limit=turtle.getFuelLimit()
    if limit=="unlimited" then return true end
    local target=math.min(fuel_reserve+1,limit)
    if level>=target then return true end
    local gained=false
    if config.auto_refuel~=false then
      local old_slot=turtle.getSelectedSlot()
      for slot=1,16 do
        local detail=turtle.getItemDetail(slot)
        if level>=target then break end
        if detail and fuel_item_set[detail.name] and turtle.getItemCount(slot)>0 then
          turtle.select(slot)
          local can_refuel=turtle.refuel(0)
          if can_refuel then
            local before=turtle.getFuelLevel()
            turtle.refuel(1)
            level=turtle.getFuelLevel()
            if level>before then gained=true end
          end
        end
      end
      if old_slot then turtle.select(old_slot) end
      level=turtle.getFuelLevel()
      if level=="unlimited" or level>=target then return true end
    end
    if not gained then
      if not warned then
        print("PAUSADA: pouco combustivel. Coloque carvao na Turtle; vou reabastecer e continuar.")
        warned=true
      end
      sleep(2)
    end
  end
end
local function move_with_fuel(move)
  refuel_for_move()
  local ok,err=move()
  if not ok and turtle.getFuelLevel()==0 then
    refuel_for_move()
    ok,err=move()
  end
  return ok,err
end
local endpoint=config.server.."/inspect"
local function post(path,value)
  local target=config.server..path
  if not http.checkURL(target) then return nil,"URL bloqueada pelo CC:Tweaked" end
  local response,why=http.post(target,textutils.serializeJSON(value),{
    ["Content-Type"]="application/json",["X-GrabCraft-Token"]=config.token,
  })
  if not response then return nil,why end
  local code,message=response.getResponseCode()
  local body=response.readAll(); response.close()
  local data=textutils.unserializeJSON(body)
  if code<200 or code>=300 then return nil,tostring(data and (data.detail or data.message) or message or body) end
  if not data then return nil,"resposta JSON inválida" end
  return data
end

print("Lendo o modelo 3D do GrabCraft...")
local info,why=post("/inspect",{url=url})
if not info then print("Não foi possível ler o blueprint: "..tostring(why)); return end
local dims=info.dimensions or {}
print("Blueprint: "..tostring(info.title))
print("Dimensões L x A x P: "..tostring(dims.width).." x "..tostring(dims.height).." x "..tostring(dims.depth))
print("Blocos: "..tostring(info.block_count))
if tonumber(info.ignored_block_count) and info.ignored_block_count>0 then
  print("Ignorados (criativo/indisponíveis): "..tostring(info.ignored_block_count))
  for _,item in ipairs(info.ignored_materials or {}) do
    print("  ignorando "..tostring(item.count).." x "..tostring(item.name))
  end
end
print("Materiais necessários:")
for _,item in ipairs(info.materials or {}) do print("  "..tostring(item.count).." x "..tostring(item.name)) end

if not tonumber(info.block_count) or info.block_count>12000 or not tonumber(dims.height) or dims.height>128 or not tonumber(dims.width) or dims.width>128 or not tonumber(dims.depth) or dims.depth>128 then
  print("Construção cancelada: modelo excede o limite seguro de 12000 blocos ou 128 blocos por dimensão.")
  return
end

local function clean_name(name)
  local value=name:lower():gsub("_", " "):gsub("%s*%([^)]*%)", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  -- GrabCraft uses names from older Minecraft versions. In 1.21.1,
  -- stained/hardened clay is terracotta, with the color in the item ID.
  value=value:gsub(" stained hardened clay$", " terracotta")
  value=value:gsub(" stained clay$", " terracotta")
  value=value:gsub(" hardened clay$", " terracotta")
  value=value:gsub(" hardned clay$", " terracotta")
  if value=="hardened clay" or value=="stained hardened clay" or value=="hardned clay" or value=="stained clay" then
    value="terracotta"
  end
  -- Older lists sometimes put "Block of" before the material name.
  value=value:gsub("^block of (.+)$", "%1 block")
  value=value:gsub(" wood plank$", " planks")
  value=value:gsub(" wood slab$", " slab"):gsub(" wood stairs$", " stairs")
  value=value:gsub(" wood$", " log")
  value=value:gsub("hay bale", "hay block")
  value=value:gsub("mob head", "player head")
  value=value:gsub("cobblestone wall", "cobblestone wall")
  return value
end
local item_name_aliases={
  -- GrabCraft labels the placeable block as "Nether Brick"; Minecraft's
  -- block item is minecraft:nether_bricks (singular is the crafting item).
  ["nether bricks"]="nether brick",
  ["stone bricks"]="stone brick",
  -- The old generic wooden trapdoor became the oak variant when trapdoors
  -- gained wood-specific variants. GrabCraft still emits the legacy label.
  ["wooden trapdoor"]="oak trapdoor",
  ["wood trapdoor"]="oak trapdoor",
  ["trapdoor"]="oak trapdoor",
}
local function match_name(name)
  local value=clean_name(name)
  return item_name_aliases[value] or value
end
local item_by_label={}
local item_counts={}
local inv_by_id={}
for slot=1,16 do
  local detail=turtle.getItemDetail(slot)
  if detail then
    inv_by_id[detail.name]=inv_by_id[detail.name] or {}
    table.insert(inv_by_id[detail.name],slot)
    item_counts[detail.name]=(item_counts[detail.name] or 0)+turtle.getItemCount(slot)
    local label=match_name(detail.displayName or detail.name:match("[^:]+$" ):gsub("_"," "))
    item_by_label[label]=item_by_label[label] or {}
    table.insert(item_by_label[label],detail.name)
  end
end

local function canonical_id(label)
  -- Keep generated IDs in sync with the aliases used for inventory matching.
  local cleaned=match_name(label)
  if cleaned=="nether brick" then cleaned="nether_bricks" end
  if cleaned=="stone brick" then cleaned="stone_bricks" end
  cleaned=cleaned:gsub(" ","_")
  return "minecraft:"..cleaned
end
local requirements={}
local missing={}
local used={}
local unsupported={}
local safe_material={}
local side_mount={}
local facing_by_name={}
for _,mat in ipairs(info.materials or {}) do
  local source=mat.name
  local canonical=match_name(source)
  local raw_state=(source:match("%((.-)%)") or ""):lower()
  local facing=raw_state:match("facing%s+(%a+)") or raw_state:match("^(%a+),%s*normal$")
  local is_ladder=source:lower():find("ladder",1,true)~=nil
  local is_torch=source:lower():find("torch",1,true)~=nil
  local id=canonical_id(source)
  if canonical=="material not identified" or canonical=="material nao identificado" then
    table.insert(unsupported,source.." (sem identificação de bloco)")
  else
    local is_wall_torch=is_torch and facing and facing~="up"
    if is_ladder or is_wall_torch then
    if not facing or not ({north=true,east=true,south=true,west=true})[facing] then
      table.insert(unsupported,source.." (orientação lateral não reconhecida)")
    else
      side_mount[source]=facing
    end
    end
    local chosen=nil
    if inv_by_id[id] then chosen=id end
    if not chosen and item_by_label[canonical] and #item_by_label[canonical]==1 then chosen=item_by_label[canonical][1] end
    if canonical=="player head" and not chosen then
      local candidates={}
      for item_id in pairs(inv_by_id) do if item_id:find("head",1,true) or item_id:find("skull",1,true) then table.insert(candidates,item_id) end end
      if #candidates==1 then chosen=candidates[1] end
    end
    chosen=chosen or id -- missing blocks are waited for at placement time
    safe_material[source]=chosen
    requirements[chosen]=(requirements[chosen] or 0)+tonumber(mat.count)
    used[chosen]=true
    if facing and ({north=true,east=true,south=true,west=true})[facing] then facing_by_name[source]=facing end
  end
end
if #unsupported>0 then
  print("\nConstrução cancelada antes de se mover.")
  for _,value in ipairs(unsupported) do print("  Não suportado: "..value) end
  for _,value in ipairs(missing) do print("  Material ausente ou ambíguo: "..value) end
  print("Coloque materiais identificáveis nos slots da Turtle e tente de novo.")
  return
end
if #missing>0 then
  print("\nConstrução cancelada: faltam materiais.")
  for _,value in ipairs(missing) do print("  "..value) end
  return
end

-- Load one layer at a time; estimate its exact Manhattan travel before moving.
local function grid_coord(value)
  if value<0 then return math.ceil(value-0.5) end
  return math.floor(value+0.5)
end
local function gps_position()
  local previous=nil
  local reported=false
  while true do
    local x,y,z=gps.locate(5)
    if x then
      local point={x=grid_coord(x),y=grid_coord(y),z=grid_coord(z)}
      if previous and point.x==previous.x and point.y==previous.y and point.z==previous.z then
        return point.x,point.y,point.z
      end
      previous=point
    else
      previous=nil
      if not reported then
        print("GPS sem resposta. Construcao pausada; aguardando o sinal voltar...")
        reported=true
      end
    end
    sleep(1)
  end
end
local state_path="/.grabcraft-build-"..tostring(info.model_id)..".txt"
local saved_state=nil
if fs.exists(state_path) then
  local state_file=fs.open(state_path,"r")
  saved_state=textutils.unserialize(state_file.readAll())
  state_file.close()
end
local start=nil
if args[2] and args[3] and args[4] then
  start={x=tonumber(args[2]),y=tonumber(args[3]),z=tonumber(args[4])}
elseif saved_state and saved_state.x and saved_state.y and saved_state.z then
  start={x=saved_state.x,y=saved_state.y,z=saved_state.z}
end
if not start then
  local sx,sy,sz=gps_position()
  start={x=sx,y=sy,z=sz}
end
if not start.x then print("Construção cancelada: GPS indisponível."); return end
local resume_layer,resume_index,resume_completed=1,1,0
if saved_state and saved_state.x==start.x and saved_state.y==start.y and saved_state.z==start.z then
  resume_layer=tonumber(saved_state.layer) or 1
  resume_index=tonumber(saved_state.index) or 1
  resume_completed=tonumber(saved_state.completed) or 0
end
local function save_progress(layer,index,completed)
  local state_file=fs.open(state_path,"w")
  state_file.write(textutils.serialize({x=start.x,y=start.y,z=start.z,layer=layer,index=index,completed=completed},{compact=true}))
  state_file.close()
end
save_progress(resume_layer,resume_index,resume_completed)
local px,py,pz=gps_position()
local current={x=px,y=py,z=pz}
local layers={}
local movement_cost=0
local prev={x=current.x,y=current.y,z=current.z}
local vectors={north={x=0,z=-1},east={x=1,z=0},south={x=0,z=1},west={x=-1,z=0}}
local headings={"north","east","south","west"}
local heading=nil
local function turn_right()
  local ok,err=turtle.turnRight(); if not ok then return false,err end
  for i,h in ipairs(headings) do if h==heading then heading=headings[i%4+1]; break end end
  return true
end
local function face(wanted)
  if not heading then return false,"direção ainda não calibrada" end
  for _=1,4 do
    if heading==wanted then return true end
    local ok,err=turn_right(); if not ok then return false,err end
  end
  return false,"não foi possível orientar para "..wanted
end
local position={x=current.x,y=current.y,z=current.z}
local function move_to(target)
  local function axis(axis_name,positive,negative)
    while position[axis_name]~=target[axis_name] do
      local step=target[axis_name]>position[axis_name] and 1 or -1
      local ok,err
      if axis_name=="y" then
        if step>0 then ok,err=move_with_fuel(function() return turtle.up() end)
        else ok,err=move_with_fuel(function() return turtle.down() end) end
      else
        ok,err=face(step>0 and positive or negative)
        if ok then ok,err=move_with_fuel(function() return turtle.forward() end) end
      end
      if not ok then return false,"movimento bloqueado no eixo "..axis_name..": "..tostring(err) end
      position[axis_name]=position[axis_name]+step
    end
    return true
  end
  local ok,err=axis("y","up","down"); if not ok then return false,err end
  ok,err=axis("x","east","west"); if not ok then return false,err end
  ok,err=axis("z","south","north"); if not ok then return false,err end
  local x,y,z=gps_position()
  local drift=math.abs(x-position.x)+math.abs(y-position.y)+math.abs(z-position.z)
  if drift>3 then
    return false,"GPS confirmou posicao inesperada ("..x..", "..y..", "..z.."); confira o local"
  elseif drift>0 then
    print("GPS corrigiu a posicao estimada para "..x..", "..y..", "..z.."; continuando.")
    position={x=x,y=y,z=z}
  end
  return true
end
local function is_side(block) return side_mount[block.name]~=nil and (block.name:lower():find("ladder",1,true) or block.name:lower():find("torch",1,true) and side_mount[block.name]~="up") end
for layer=1,dims.height do
  local data,err=post("/layer",{model_id=tostring(info.model_id),y=layer})
  if not data then print("Falha ao carregar camada "..layer..": "..tostring(err)); return end
  layers[layer]=data.blocks or {}
  for _,block in ipairs(layers[layer]) do
    block.item=safe_material[block.name]
    block.target={x=start.x+block.x,y=start.y+layer,z=start.z+block.z}
    block.layer=layer
    block.support_direction=side_mount[block.name]
    if is_side(block) then
      local v=vectors[block.support_direction]
      block.approach={x=block.target.x-v.x,y=block.target.y-1,z=block.target.z-v.z}
    else
      block.approach={x=block.target.x,y=block.target.y,z=block.target.z}
    end
  end
  -- Place same-layer support blocks first, wall attachments second, and their
  -- approach-side blocks last so the Turtle does not seal itself out.
  local support_cells={}
  for _,block in ipairs(layers[layer]) do
    if is_side(block) then
      local v=vectors[block.support_direction]
      support_cells[(block.x+v.x)..":"..(block.z+v.z)]=true
    end
  end
  for _,block in ipairs(layers[layer]) do
    local v=vectors[block.support_direction or "north"]
    if is_side(block) then block.priority=2
    elseif support_cells[block.x..":"..block.z] then block.priority=1
    else block.priority=3 end
  end
  table.sort(layers[layer],function(a,b)
    if a.priority~=b.priority then return a.priority<b.priority end
    if a.z~=b.z then return a.z<b.z end
    return a.x<b.x
  end)
  for block_index,block in ipairs(layers[layer]) do
    if layer>resume_layer or (layer==resume_layer and block_index>=resume_index) then
      movement_cost=movement_cost+math.abs(block.approach.x-prev.x)+math.abs(block.approach.y-prev.y)+math.abs(block.approach.z-prev.z)
      prev=block.approach
    end
  end
end
refuel_for_move()
local fuel=turtle.getFuelLevel()
local reserve=fuel_reserve
local calibration_cost=2
if fuel~='unlimited' then
  print('Movimentos estimados: '..movement_cost..'; combustivel atual: '..tostring(fuel)..'. Reabastecimento automatico ativo.')
end

-- Infer cardinal facing by one reversible move, comparing GPS before/after.
local moved=move_with_fuel(function() return turtle.forward() end)
if not moved then print("Construção cancelada: deixe livre o bloco à frente para calibrar."); return end
local cx,cy,cz=gps_position()
local backed=move_with_fuel(function() return turtle.back() end)
local rx,ry,rz=gps_position()
if not backed or not cx or not rx or rx~=current.x or ry~=current.y or rz~=current.z then
  print("Construção cancelada: não consegui calibrar e voltar ao ponto GPS inicial."); return
end
if cx>current.x then heading="east" elseif cx<current.x then heading="west"
elseif cz>current.z then heading="south" elseif cz<current.z then heading="north" end
if not heading then print("Construção cancelada: o GPS não detectou a direção."); return end

print("\nGPS/origem: "..start.x..", "..start.y..", "..start.z.." (canto mínimo; +X leste, +Z sul)")
print("Deslocamento estimado: "..movement_cost.." blocos, mais calibração GPS. Iniciando construção em camadas...")
print("A Turtle não escava: terreno ou blocos ocupando a planta fazem a execução parar com segurança.")
print("Blocos de orientação do GrabCraft são aproximados conforme o lado de colocação do CC:Tweaked.")
local placed=0
local processed=resume_completed
local function select_material(block)
  local expected_label=match_name(block.name)
  for slot=1,16 do
    local detail=turtle.getItemDetail(slot)
    if detail and turtle.getItemCount(slot)>0 then
      local label=match_name(detail.displayName or detail.name:match("[^:]+$"):gsub("_"," "))
      if detail.name==block.item or label==expected_label then
        turtle.select(slot)
        return true
      end
    end
  end
  return false
end
local function chest_can_push_items(chest)
  return chest and type(chest.list)=="function" and type(chest.pushItems)=="function"
end
local function selective_chest_pull(block)
  local turtle_network_name=nil
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name)=="modem" then
      local modem=peripheral.wrap(name)
      if modem and type(modem.isWireless)=="function" and not modem.isWireless()
          and type(modem.getNameLocal)=="function" then
        local ok,value=pcall(modem.getNameLocal)
        if ok and value then turtle_network_name=value; break end
      end
    end
  end
  if not turtle_network_name then return nil,"modem cabeado da Turtle nao conectado" end

  for _,name in ipairs(peripheral.getNames()) do
    local ok,methods=pcall(peripheral.getMethods,name)
    if ok and type(methods)=="table" then
      local available={}
      for _,method in ipairs(methods) do available[method]=true end
      if available.list and available.pushItems then
        local chest=peripheral.wrap(name)
        if chest_can_push_items(chest) then
          local ok_list,items=pcall(chest.list)
          if ok_list and type(items)=="table" then
            for source_slot,item in pairs(items) do
              if type(item)=="table" and item.name then
                local wanted=block.item
                local matches=item.name==wanted
                if not matches then
                  local details=item
                  if type(chest.getItemDetail)=="function" then
                    local detail_ok,detail=pcall(chest.getItemDetail,source_slot)
                    if detail_ok and type(detail)=="table" then details=detail end
                  end
                  local label=match_name(details.displayName or item.name:match("[^:]+$"):gsub("_"," "))
                  matches=label==match_name(block.name)
                end
                if matches then
                  for target_slot=1,16 do
                    local existing=turtle.getItemDetail(target_slot)
                    local compatible=not existing or existing.name==item.name or existing.name==wanted
                    local space=turtle.getItemSpace(target_slot)
                    if compatible and space>0 then
                      local limit=math.min(tonumber(item.count) or 64,space)
                      local pushed_ok,pushed=pcall(chest.pushItems,turtle_network_name,source_slot,limit,target_slot)
                      if pushed_ok and (tonumber(pushed) or 0)>0 then
                        turtle.select(target_slot)
                        return true
                      end
                    end
                  end
                  return false,"sem slot livre para "..wanted
                end
              end
            end
          end
        end
      end
    end
  end
  return false,"item ainda nao esta no bau"
end
local function fetch_material_from_ae2(block)
  if not config.supply_station then return false end
  local central_id=tonumber(config.supply_computer_id)
  local work_position={x=position.x,y=position.y,z=position.z}
  local home=config.supply_station or {x=start.x,y=start.y,z=start.z}
  local function restore_work()
    local restored,restore_error=move_to(work_position)
    if not restored then error("PAREI ao voltar do abastecimento: "..tostring(restore_error)) end
  end
  print("Voltando ao ponto de abastecimento...")
  local reached,travel_error=move_to(home)
  if not reached then
    print("Nao consegui chegar ao ponto AE2: "..tostring(travel_error))
    restore_work()
    return false
  end
  local delivered=true
  if supply_modem then
    local request_id=tostring(os.getComputerID()).."-"..tostring(os.epoch("utc"))
    local request={type="request",id=request_id,secret=config.supply_secret,item=block.item,count=64}
    print("Solicitando ate 64 x "..block.item.." ao computador de abastecimento...")
    if not rednet.send(central_id,request,supply_protocol) then
      print("Falha ao enviar pedido ao computador de abastecimento.")
      restore_work()
      return false
    end
    delivered=false
    local timeouts=0
    while true do
      local sender,response=rednet.receive(supply_protocol,15)
      if sender==central_id and type(response)=="table" and response.id==request_id and response.type=="result" then
        if response.ok then
          print("Separado no ponto de carga: "..tostring(response.count or 64).." x "..block.item)
          delivered=true
        else
          print("O computador nao forneceu o item: "..tostring(response.error or "erro desconhecido"))
        end
        break
      elseif not sender then
        timeouts=timeouts+1
        if timeouts>=4 then
          print("Despachante sem resposta. Vou tentar novamente durante a pausa.")
          restore_work()
          return false
        end
        print("Aguardando o despachante... reenviando pedido.")
        rednet.send(central_id,request,supply_protocol)
      end
    end
    if not delivered then restore_work(); return false end
  else
    print("Aguardando "..block.item.." no inventario conectado...")
  end
  while not select_material(block) do
    local pulled,why=selective_chest_pull(block)
    if pulled==nil then
      -- Keep a simple chest-only fallback for stations without wired modems.
      local before={}
      for slot=1,16 do
        local detail=turtle.getItemDetail(slot)
        if detail then before[detail.name]=(before[detail.name] or 0)+turtle.getItemCount(slot) end
      end
      turtle.suckDown()
      if not select_material(block) then
        local changed=false
        for slot=1,16 do
          local detail=turtle.getItemDetail(slot)
          if detail and turtle.getItemCount(slot)>(before[detail.name] or 0) then changed=true end
        end
        if not changed then
          print("Sem espaco/item no bau inferior. Libere um slot ou confira o abastecimento.")
          sleep(3)
        end
      end
    elseif not pulled then
      if why=="sem slot livre para "..block.item then
        print("Inventario cheio. Libere um slot para "..block.item.."; vou tentar novamente.")
      end
      sleep(3)
    end
  end
  print("Material coletado. Voltando ao bloco de trabalho...")
  restore_work()
  return select_material(block)
end
local function wait_for_material(block)
  if config.supply_station and fetch_material_from_ae2(block) then return true end
  local last_supply_attempt=os.epoch("utc")
  print("\nPAUSADA: preciso de "..block.name.." ("..block.item..").")
  print("Insira esse bloco no inventÃ¡rio da Turtle; verifico novamente a cada 2 segundos.")
  print("Deixe um slot livre. Quando o item aparecer, continuo deste bloco automaticamente.")
  while true do
    if select_material(block) then
      print("Material detectado: "..block.name..". Continuando.")
      return true
    end
    if config.supply_station and os.epoch("utc")-last_supply_attempt>=30000 then
      last_supply_attempt=os.epoch("utc")
      if fetch_material_from_ae2(block) then return true end
    end
    sleep(2)
  end
end
local function report_progress()
  processed=processed+1
  if processed%25==0 or processed==info.block_count then
    print("Progresso: "..processed.."/"..info.block_count.." voxels; novos blocos: "..placed)
  end
end
for layer=resume_layer,#layers do
  print("Camada "..layer.."/"..dims.height.." ("..#layers[layer].." blocos)")
  local first_index=layer==resume_layer and resume_index or 1
  for block_index=first_index,#layers[layer] do
    local block=layers[layer][block_index]
    local ok,err=move_to(block.approach)
    if not ok then print("PAREI no GPS da camada "..layer..": "..tostring(err)); return end
    if is_side(block) then
      ok,err=face(block.support_direction)
      if not ok then print("PAREI ao orientar a Turtle: "..tostring(err)); return end
      if turtle.detect() then
        local exists,info_block=turtle.inspect()
        if not exists or info_block.name~=block.item then
          print("PAREI: caminho de colocação ocupado em "..block.target.x..", "..(block.target.y-1)..", "..block.target.z)
          return
        end
        report_progress()
      else
        if not select_material(block) then wait_for_material(block) end
        local success,place_error=turtle.place()
        if not success then print("PAREI ao colocar "..block.name..": "..tostring(place_error)); return end
        placed=placed+1
        report_progress()
      end
    elseif turtle.detectDown() then
      local exists,info_block=turtle.inspectDown()
      if exists and info_block.name==block.item then
        -- A colocação já existia, então continuar permite retomar a mesma blueprint.
        report_progress()
      else
        print("PAREI: espaço ocupado em "..block.target.x..", "..(block.target.y-1)..", "..block.target.z)
        print("Bloco presente: "..tostring(info_block and info_block.name or "desconhecido").."; esperado: "..block.item)
        return
      end
    else
      if facing_by_name[block.name] then
        ok,err=face(facing_by_name[block.name])
        if not ok then print("PAREI ao orientar bloco: "..tostring(err)); return end
      end
      if not select_material(block) then wait_for_material(block) end
      local success,place_error=turtle.placeDown()
      if not success then print("PAREI ao colocar "..block.name..": "..tostring(place_error)); return end
      placed=placed+1
      report_progress()
    end
    local next_layer,next_index=layer,block_index+1
    if next_index>#layers[layer] then next_layer,next_index=layer+1,1 end
    save_progress(next_layer,next_index,processed)
  end
end
print("Construção concluída. Novos blocos colocados: "..placed)
if fs.exists(state_path) then fs.delete(state_path) end
