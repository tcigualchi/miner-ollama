local M = {}
function M.summary()
  -- CC:Tweaked serializa uma tabela Lua vazia como objeto JSON por padrão.
  local out = {}
  for slot=1,16 do
    local item = turtle.getItemDetail(slot)
    if item then out[item.name] = (out[item.name] or 0) + turtle.getItemCount(slot) end
  end
  return out
end
function M.free_slots()
  local count=0; for slot=1,16 do if turtle.getItemCount(slot)==0 then count=count+1 end end; return count
end
function M.select_item(name)
  for slot=1,16 do local d=turtle.getItemDetail(slot); if d and d.name==name and turtle.getItemCount(slot)>0 then turtle.select(slot); return true end end
  return false, "material ausente: " .. name
end
return M
