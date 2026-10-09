--[[
    ZoneSystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > ZoneSystem

    Única responsabilidad: determinar la zona de una posición/jugador.
    Zonas: Safe, Red, Neutral.
]]

local Players = game:GetService("Players")

local ZoneSystem = {}
local INTERVALO_ACTUALIZACION = 0.2

local function puntoEnParte(parte, posicion)
    local localPosition = parte.CFrame:PointToObjectSpace(posicion)
    local mitad = parte.Size / 2
    return math.abs(localPosition.X) <= mitad.X
        and math.abs(localPosition.Y) <= mitad.Y
        and math.abs(localPosition.Z) <= mitad.Z
end

function ZoneSystem.GetZoneAt(posicion)
    if typeof(posicion) ~= "Vector3" then
        return "Neutral"
    end

    local zonas = workspace:FindFirstChild("Zones")
    if not zonas then
        return "Neutral"
    end

    local segura = zonas:FindFirstChild("SafeZone")
    if segura and puntoEnParte(segura, posicion) then
        return "Safe"
    end

    local roja = zonas:FindFirstChild("RedZone")
    if roja and puntoEnParte(roja, posicion) then
        return "Red"
    end

    return "Neutral"
end

function ZoneSystem.GetPlayerZone(jugador)
    if typeof(jugador) ~= "Instance" or not jugador:IsA("Player") then
        return "Neutral"
    end

    local personaje = jugador.Character
    local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
    if not raiz then
        return "Neutral"
    end

    return ZoneSystem.GetZoneAt(raiz.Position)
end

function ZoneSystem.IsInSafeZone(jugador)
    return ZoneSystem.GetPlayerZone(jugador) == "Safe"
end

function ZoneSystem.IsInRedZone(jugador)
    return ZoneSystem.GetPlayerZone(jugador) == "Red"
end

function ZoneSystem.Init()
    task.spawn(function()
        while true do
            for _, jugador in Players:GetPlayers() do
                jugador:SetAttribute("Zona", ZoneSystem.GetPlayerZone(jugador))
            end
            task.wait(INTERVALO_ACTUALIZACION)
        end
    end)
end

return ZoneSystem