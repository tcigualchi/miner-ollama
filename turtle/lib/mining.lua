local move=require("lib.movement")
local inventory=require("lib.inventory")
local M={}
function M.area(width, depth, height, progress)
  local total=width*depth; local done=0
  for row=1,depth do
    for col=1,width do
      if col>1 then local ok,why=move.forward(true); if not ok then return false,why end end
      for level=2,height do local ok,why=move.up(true); if not ok then return false,why end end
      for level=2,height do local ok,why=move.down(true); if not ok then return false,why end end
      done=done+1
      if inventory.free_slots()==0 then return false,"inventário cheio" end
      progress(math.floor(done*100/total),"linha "..row)
    end
    if row<depth then
      local turn=row%2==1 and move.right or move.left
      local ok,why=turn(); if not ok then return false,why end
      ok,why=move.forward(true); if not ok then return false,why end
      ok,why=turn(); if not ok then return false,why end
    end
  end
  return true
end
return M
