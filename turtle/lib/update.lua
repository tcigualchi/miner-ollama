local cfg=require("config")
local M={}
function M.try()
  local h,err=http.get(cfg.server_url.."/api/agent/manifest?agent_id="..textutils.urlEncode(cfg.agent_id), {["X-Agent-Token"]=cfg.agent_token})
  if not h then return false,err end
  local manifest=textutils.unserializeJSON(h.readAll()); h.close()
  if not manifest or not manifest.version then return false,"manifesto inválido" end
  local versionFile="/fleet/version"
  local current=fs.exists(versionFile) and (function() local f=fs.open(versionFile,"r"); local v=f.readAll(); f.close(); return v end)() or ""
  if current==manifest.version then return false end
  for _,entry in ipairs(manifest.files or {}) do
    local response,why=http.get(cfg.server_url.."/agent/"..entry.path)
    if not response then return false,why end
    local target="/fleet/"..entry.path
    local dir=fs.getDir(target); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
    local temp=target..".new"; local out=fs.open(temp,"w"); out.write(response.readAll()); out.close(); response.close()
    if fs.exists(target) then fs.delete(target) end
    fs.move(temp,target)
  end
  local out=fs.open(versionFile,"w"); out.write(manifest.version); out.close()
  return true
end
return M
