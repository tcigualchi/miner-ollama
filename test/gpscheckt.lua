print("=== TESTE DE EIXOS GPS ===")
print("")

local x1, y1, z1 = gps.locate(5)

if not x1 then
    error("GPS nao localizado.")
end

print("Posicao inicial:")
print("X:", x1)
print("Y:", y1)
print("Z:", z1)
print("")

print("Vou tentar SUBIR 1 bloco...")
sleep(2)

if not turtle.up() then
    error("Nao consegui subir. Deixe o bloco acima livre.")
end

sleep(1)

local x2, y2, z2 = gps.locate(5)

print("")
print("Depois de turtle.up():")
print("X:", x2)
print("Y:", y2)
print("Z:", z2)

print("")
print("Diferenca:")
print("dX:", x2 - x1)
print("dY:", y2 - y1)
print("dZ:", z2 - z1)

print("")
print("Voltando para baixo...")

if not turtle.down() then
    error("Nao consegui voltar para baixo.")
end

print("")
print("=== RESULTADO ===")

if x2 == x1 and y2 == y1 + 1 and z2 == z1 then
    print("PERFEITO!")
    print("O GPS esta usando X Y Z corretamente.")
else
    print("ATENCAO!")
    print("O eixo vertical do GPS esta configurado errado.")
    print("")
    print("Ao subir, deveria acontecer:")
    print("dX = 0")
    print("dY = 1")
    print("dZ = 0")
end