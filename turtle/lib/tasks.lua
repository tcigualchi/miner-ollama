local nav=require("lib.navigation")
local mining=require("lib.mining")
local building=require("lib.building")
local net=require("lib.net")
local state=require("lib.state")
local M={}
local function checkpoint(task, percent, message)
  local point={percent=percent,message=message,at=os.epoch("utc")}
  state.write({checkpoint=point})
  net.progress(task.id,"RUNNING",percent,message,point)
end
function M.execute(task)
  local p=task.payload or {}
  if task.kind=="goto" then
    local ok,why=nav.go_to(p,{dig=p.dig}); if not ok then error(why) end
  elseif task.kind=="return_base" then
    local ok,why=nav.return_base(); if not ok then error(why) end
  elseif task.kind=="follow_player" then
    local arrived=false
    for _=1,60 do
      local target,why=net.player_target(); if not target then error(why or "beacon indisponível") end
      local here=require("lib.gps").locate()
      if not here.x then error("GPS indisponível durante a aproximação") end
      if math.abs(target.x-here.x)<=1 and math.abs(target.z-here.z)<=1 and math.abs(target.y-here.y)<=1 then arrived=true; break end
      if target.dimension and target.dimension~=require("config").dimension then error("Jogador está em outra dimensão; a Turtle não atravessa portais automaticamente") end
      local ok,why=nav.go_to(target,{dig=p.dig}); if not ok then error(why) end
      sleep(p.recalculate_seconds or 4)
    end
    if not arrived then error("O jogador continuou se movendo; tarefa pausada para evitar perseguição sem fim") end
  elseif task.kind=="mine_area" or task.kind=="clear_area" then
    if p.origin then
      local depth=p.depth
      if p.partition then
        local slice=math.ceil(depth/p.partition.total)
        local first=p.partition.index*slice
        local remaining=math.max(0,depth-first)
        if remaining==0 then return "Sem partição de trabalho" end
        p.depth=math.min(slice,remaining)
        p.origin.x=p.origin.x+first
      end
      local ok,why=nav.go_to({x=p.origin.x,y=p.origin.y,z=p.origin.z+p.width-1},{dig=true}); if not ok then error(why) end
      ok,why=nav.face("north"); if not ok then error(why) end
    end
    local ok,why=mining.area(p.width,p.depth,p.height or 2,function(percent,message) checkpoint(task,percent,message) end); if not ok then error(why) end
  elseif task.kind=="build_wall" then
    if p.origin and p.origin.x and p.origin.y and p.origin.z then
      local ok,why=nav.go_to(p.origin,{dig=false}); if not ok then error(why) end
      ok,why=nav.face("north"); if not ok then error(why) end
    end
    local ok,why=building.wall(p.length,p.height,p.material,function(percent,message) checkpoint(task,percent,message) end); if not ok then error(why) end
  elseif task.kind=="build_bridge" then
    if p.origin and p.origin.x and p.origin.y and p.origin.z then
      local ok,why=nav.go_to(p.origin,{dig=false}); if not ok then error(why) end
      ok,why=nav.face("north"); if not ok then error(why) end
    end
    local ok,why=building.bridge(p.length,p.material,function(percent,message) checkpoint(task,percent,message) end); if not ok then error(why) end
  elseif task.kind=="build_house" then
    local ok,why=building.house(p.width,p.depth,p.height or 3,p.material,p.origin,function(percent,message) checkpoint(task,percent,message) end); if not ok then error(why) end
  else error("tipo de tarefa não suportado: "..tostring(task.kind)) end
  return "Tarefa concluída"
end
return M
