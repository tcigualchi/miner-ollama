local inventory=require("lib.inventory")
local move=require("lib.movement")
local nav=require("lib.navigation")
local gps=require("lib.gps")
local M={}

local function place_down(material)
  if turtle.detectDown() then return true end
  local ok,why=inventory.select_item(material); if not ok then return false,why end
  ok,why=turtle.placeDown()
  if not ok then return false,why or "nao foi possivel colocar bloco abaixo" end
  return true
end

-- Walks along a clear lane and places a straight wall in front of the turtle.
function M.wall(length,height,material,progress,skip)
  local ok,why=move.right(); if not ok then return false,why end
  for column=1,length do
    for level=1,height do
      if not (skip and skip(column,level)) and not turtle.detect() then
        ok,why=inventory.select_item(material); if not ok then return false,why end
        ok,why=turtle.place(); if not ok then return false,why end
      end
      if level<height then ok,why=move.up(false); if not ok then return false,why end end
    end
    for _=2,height do ok,why=move.down(false); if not ok then return false,why end end
    progress(math.floor(column*100/length),"wall")
    if column<length then
      ok,why=move.left(); if not ok then return false,why end
      ok,why=move.forward(false); if not ok then return false,why end
      ok,why=move.right(); if not ok then return false,why end
    end
  end
  return move.left()
end

function M.bridge(length,material,progress)
  for step=1,length do
    local ok,why=place_down(material); if not ok then return false,why end
    if step<length then ok,why=move.forward(false); if not ok then return false,why end end
    progress(math.floor(step*100/length),"bridge")
  end
  return true
end

function M.house(width,depth,height,material,origin,progress)
  local here=gps.locate()
  origin=origin or {x=here.x,y=here.y,z=here.z}
  if not origin.x or not origin.y or not origin.z then return false,"GPS required to plan the house" end
  if width<3 or depth<3 then return false,"house must be at least 3 by 3 blocks" end
  local wallBlocks={}
  for x=0,width-1 do
    wallBlocks[#wallBlocks+1]={x=origin.x+x,z=origin.z,front=true}
    wallBlocks[#wallBlocks+1]={x=origin.x+x,z=origin.z+depth-1}
  end
  for z=1,depth-2 do
    wallBlocks[#wallBlocks+1]={x=origin.x,z=origin.z+z}
    wallBlocks[#wallBlocks+1]={x=origin.x+width-1,z=origin.z+z}
  end
  local perimeter=#wallBlocks
  local total=width*depth+perimeter*height+width*depth
  local done=0
  local function report(label)
    done=done+1
    progress(math.min(99,math.floor(done*100/total)),label)
  end
  local function go(x,y,z) return nav.go_to({x=x,y=y,z=z},{dig=false}) end
  local safeY=origin.y+height+1

  -- Place the floor at the turtle's feet, revisiting absolute coordinates on recovery.
  for z=0,depth-1 do
    for x=0,width-1 do
      local ok,why=go(origin.x+x,origin.y,origin.z+z); if not ok then return false,why end
      ok,why=place_down(material); if not ok then return false,why end
      report("foundation")
    end
  end

  -- Build each wall block from above. This keeps every placement on its exact GPS cell.
  for level=1,height do
    for _,point in ipairs(wallBlocks) do
      local door=point.front and point.x==origin.x+math.floor(width/2) and level<=2
      if not door then
        local blockY=origin.y+level-1
        local ok,why=go(point.x,safeY,point.z); if not ok then return false,why end
        for _=1,safeY-(blockY+1) do ok,why=move.down(false); if not ok then return false,why end end
        ok,why=place_down(material); if not ok then return false,why end
      end
      report(door and "doorway" or "walls")
    end
  end

  -- The flat roof is placed below the turtle while it walks at safeY.
  for z=0,depth-1 do
    for x=0,width-1 do
      local ok,why=go(origin.x+x,safeY,origin.z+z); if not ok then return false,why end
      ok,why=place_down(material); if not ok then return false,why end
      report("roof")
    end
  end
  return true
end

return M
