local M = {}
local path = "/fleet/state.json"

function M.read()
  if not fs.exists(path) then return {status = "IDLE", checkpoint = {}} end
  local h = fs.open(path, "r")
  local data = textutils.unserializeJSON(h.readAll())
  h.close()
  return data or {status = "IDLE", checkpoint = {}}
end

function M.write(patch)
  local data = M.read()
  for key, value in pairs(patch) do data[key] = value end
  if data.status == "IDLE" then data.task_id = nil; data.checkpoint = {} end
  local h = fs.open(path .. ".new", "w")
  h.write(textutils.serializeJSON(data))
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(path .. ".new", path)
end

return M
