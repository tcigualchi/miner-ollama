url = "https://strength-ranging-buddhist.ngrok-free.dev"
print(http.checkURL(url .. "/plan"))
r, erro, falha = http.get(url)
print("Resposta:", r and r.getResponseCode(), "Erro:", erro)
if r then print(r.readAll()); r.close() end
if falha then print(falha.readAll()); falha.close() end