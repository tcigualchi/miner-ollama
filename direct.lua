local x1, y1, z1 = gps.locate(5)

if not x1 then
    print("GPS nao encontrado.")
    return
end

print("Posicao inicial:", x1, y1, z1)

if not turtle.forward() then
    print("Tem um bloco na frente.")
    return
end

sleep(0.5)

local x2, y2, z2 = gps.locate(5)

if not x2 then
    print("Nao consegui obter a segunda posicao.")
    turtle.back()
    return
end

local direcao

if x2 > x1 then
    direcao = "LESTE"
elseif x2 < x1 then
    direcao = "OESTE"
elseif z2 > z1 then
    direcao = "SUL"
elseif z2 < z1 then
    direcao = "NORTE"
else
    direcao = "DESCONHECIDA"
end

print("Direcao:", direcao)
print("Posicao atual:", x2, y2, z2)

turtle.back()