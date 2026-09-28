local M = {}

function M.find(itemName)
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name == itemName and turtle.getItemCount(slot) > 0 then
      return slot
    end
  end
  return nil
end

function M.count(itemName)
  local n = 0
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name == itemName then
      n = n + turtle.getItemCount(slot)
    end
  end
  return n
end

function M.select(itemName)
  local slot = M.find(itemName)
  if not slot then return false end
  turtle.select(slot)
  return true
end

function M.summary()
  local out = {}
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d then
      out[d.name] = (out[d.name] or 0) + turtle.getItemCount(slot)
    end
  end
  return out
end

return M
