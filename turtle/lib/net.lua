local cfg = require("config")
local M = {}

local function headers()
  return {["Content-Type"] = "application/json", ["Accept"] = "application/json", ["X-Agent-Token"] = cfg.agent_token}
end

local function request(method, path, body)
  local h, err
  if method == "GET" then
    h, err = http.get(cfg.server_url .. path, headers())
  else
    h, err = http.post(cfg.server_url .. path, textutils.serializeJSON(body or {}), headers())
  end
  if not h then return nil, err end
  local code = h.getResponseCode()
  local text = h.readAll()
  h.close()
  if code == 204 then return nil, "empty" end
  if code < 200 or code >= 300 then return nil, "HTTP " .. code .. ": " .. text end
  return text == "" and {} or textutils.unserializeJSON(text)
end

function M.heartbeat(data)
  local ok, err = request("POST", "/api/agents/" .. cfg.agent_id .. "/heartbeat", data)
  return ok, err
end
function M.next_task() return request("GET", "/api/agents/" .. cfg.agent_id .. "/tasks/next") end
function M.player_target() return request("GET", "/api/agents/" .. cfg.agent_id .. "/player-target") end
function M.progress(id, status, progress, message, checkpoint, level)
  return request("POST", "/api/agents/" .. cfg.agent_id .. "/tasks/" .. id .. "/progress", {
    state=status, progress=progress, message=message, checkpoint=checkpoint or {}, log_level=level or "INFO"
  })
end
function M.get_task(id) return request("GET", "/api/agents/" .. cfg.agent_id .. "/tasks/" .. id) end
return M
