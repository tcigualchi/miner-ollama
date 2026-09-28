local M = {}

function M.open()
  peripheral.find("modem", function(name, modem)
    if modem.isWireless() then rednet.open(name) end
  end)
  if not rednet.isOpen() then
    error("Nenhum modem wireless encontrado/aberto.")
  end
end

function M.send(id, msg, protocol)
  if id == nil then return false end
  return rednet.send(id, msg, protocol)
end

return M
