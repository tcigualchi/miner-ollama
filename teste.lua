url = "https://strength-ranging-buddhist.ngrok-free.dev"
token = "123"
r, erro, falha = http.post(url, '{"prompt":"abra um tunel de 3 blocos"}', {["Content-Type"]="application/json", ["X-Miner-Token"]=token, ["ngrok-skip-browser-warning"]="true"})
print("Status:", (r or falha) and (r or falha).getResponseCode(), "Erro:", erro)
if r or falha then print((r or falha).readAll()); (r or falha).close() end