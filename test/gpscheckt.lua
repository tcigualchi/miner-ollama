print("=== TESTE DE EIXOS GPS ===")
print("")

local function localizar()
    local x, y, z = gps.locate(5)

    if not x then
        error("GPS nao localizado.")
    end

    -- Mesmo arredondamento usado pelo sistema de navegacao.
    x = math.floor(x + 0.5)
    y = math.floor(y + 0.5)
    z = math.floor(z + 0.5)

    return x, y, z
end

local x1, y1, z1 = localizar()

print("ANTES:")
print("X =", x1)
print("Y =", y1)
print("Z =", z1)
print("")

print("Subindo 1 bloco...")
sleep(1)

if not turtle.up() then
    error("Nao consegui subir. Verifique combustivel ou bloco acima.")
end

sleep(1)

local x2, y2, z2 = localizar()

print("")
print("DEPOIS DE SUBIR:")
print("X =", x2)
print("Y =", y2)
print("Z =", z2)

local dx = x2 - x1
local dy = y2 - y1
local dz = z2 - z1

print("")
print("DIFERENCA REAL:")
print("dX =", dx)
print("dY =", dy)
print("dZ =", dz)

print("")
print("Voltando para baixo...")

if not turtle.down() then
    print("AVISO: nao consegui voltar para baixo.")
end

print("")
print("=== RESULTADO ===")

if dx == 0 and dy == 1 and dz == 0 then
    print("GPS PERFEITO!")
    print("X, Y e Z estao corretos.")
    print("Subir aumenta Y em +1.")
else
    print("ATENCAO!")
    print("Movimento vertical inesperado.")
    print("")
    print("Esperado:")
    print("dX = 0")
    print("dY = 1")
    print("dZ = 0")
    print("")
    print("Recebido:")
    print("dX =", dx)
    print("dY =", dy)
    print("dZ =", dz)
end