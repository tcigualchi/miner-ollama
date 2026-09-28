local args = {...}

if #args < 3 then
    print("Uso: goto <x> <y> <z>")
    return
end

local alvoX = tonumber(args[1])
local alvoY = tonumber(args[2])
local alvoZ = tonumber(args[3])

local direcoes = {
    NORTE = 0,
    LESTE = 1,
    SUL = 2,
    OESTE = 3
}

local direcaoAtual = nil

local function localizar()
    local x, y, z = gps.locate(5)

    if not x then
        error("Nao foi possivel localizar pelo GPS.")
    end

    return x, y, z
end

local function descobrirDirecao()
    local x1, y1, z1 = localizar()

    if not turtle.forward() then
        error("Preciso de espaco na frente para descobrir a direcao.")
    end

    sleep(0.3)

    local x2, y2, z2 = localizar()

    turtle.back()

    if x2 > x1 then
        return direcoes.LESTE
    elseif x2 < x1 then
        return direcoes.OESTE
    elseif z2 > z1 then
        return direcoes.SUL
    elseif z2 < z1 then
        return direcoes.NORTE
    end

    error("Nao consegui descobrir a direcao.")
end

local function virarPara(alvo)
    local diff = (alvo - direcaoAtual) % 4

    if diff == 1 then
        turtle.turnRight()
    elseif diff == 2 then
        turtle.turnRight()
        turtle.turnRight()
    elseif diff == 3 then
        turtle.turnLeft()
    end

    direcaoAtual = alvo
end

local function frente()
    while not turtle.forward() do
        if turtle.detect() then
            turtle.dig()
            sleep(0.2)
        else
            sleep(0.2)
        end
    end
end

local function moverVertical(atualY)
    while atualY < alvoY do
        while not turtle.up() do
            if turtle.detectUp() then
                turtle.digUp()
                sleep(0.2)
            else
                sleep(0.2)
            end
        end

        atualY = atualY + 1
    end

    while atualY > alvoY do
        while not turtle.down() do
            if turtle.detectDown() then
                turtle.digDown()
                sleep(0.2)
            else
                sleep(0.2)
            end
        end

        atualY = atualY - 1
    end
end

direcaoAtual = descobrirDirecao()

local x, y, z = localizar()

print("Posicao atual:", x, y, z)
print("Destino:", alvoX, alvoY, alvoZ)

moverVertical(y)

x, y, z = localizar()

while x < alvoX do
    virarPara(direcoes.LESTE)
    frente()
    x = x + 1
end

while x > alvoX do
    virarPara(direcoes.OESTE)
    frente()
    x = x - 1
end

while z < alvoZ do
    virarPara(direcoes.SUL)
    frente()
    z = z + 1
end

while z > alvoZ do
    virarPara(direcoes.NORTE)
    frente()
    z = z - 1
end

local fx, fy, fz = localizar()

print("Cheguei!")
print("Posicao final:", fx, fy, fz)