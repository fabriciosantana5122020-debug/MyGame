--[[
    PowerInventory (ModuleScript)
    Ubicación: ServerScriptService > Modulos > PowerInventory

    Inventario temporal del MVP. El servidor es la única autoridad.
    No usa DataStore todavía.

    Publica el inventario mediante el Attribute "Poderes" para que el HUD
    del cliente pueda mostrar los slots sin tener que recibir datos confiables
    desde el cliente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))

local PowerInventory = {}
local inventarios = {} -- [Player] = { "Fireball", "Teleport", ... }

local function validarJugador(jugador)
    return typeof(jugador) == "Instance" and jugador:IsA("Player") and jugador.Parent == Players
end

local function obtener(jugador)
    if not inventarios[jugador] then
        inventarios[jugador] = {}
    end
    return inventarios[jugador]
end

local function publicar(jugador)
    if validarJugador(jugador) then
        jugador:SetAttribute("Poderes", table.concat(obtener(jugador), ","))
    end
end

function PowerInventory.Agregar(jugador, idPoder)
    if not validarJugador(jugador) then
        return false, "Jugador inválido"
    end
    if typeof(idPoder) ~= "string" or not PowerData.Powers[idPoder] then
        return false, "Poder inexistente"
    end

    local inv = obtener(jugador)
    if table.find(inv, idPoder) then
        return false, "Ya tienes ese poder"
    end
    if #inv >= PowerData.Config.MaxSlots then
        return false, "Slots llenos"
    end

    table.insert(inv, idPoder)
    publicar(jugador)
    return true
end

-- Reemplaza el inventario completo (usado SOLO por SaveSystem al
-- cargar un perfil guardado). Valida cada poder, elimina duplicados
-- y respeta el límite de slots.
function PowerInventory.Establecer(jugador, lista)
    if not validarJugador(jugador) or typeof(lista) ~= "table" then
        return false
    end

    local nuevo = {}
    for _, idPoder in ipairs(lista) do
        if typeof(idPoder) == "string"
            and PowerData.Powers[idPoder]
            and not table.find(nuevo, idPoder)
            and #nuevo < PowerData.Config.MaxSlots
        then
            table.insert(nuevo, idPoder)
        end
    end

    inventarios[jugador] = nuevo
    publicar(jugador)
    return true
end

function PowerInventory.Vaciar(jugador)
    if not validarJugador(jugador) then
        return {}
    end

    local anteriores = table.clone(obtener(jugador))
    inventarios[jugador] = {}
    publicar(jugador)
    return anteriores
end

function PowerInventory.ObtenerSlot(jugador, slot)
    if not validarJugador(jugador) then
        return nil
    end
    if typeof(slot) ~= "number" or slot % 1 ~= 0 then
        return nil
    end
    return obtener(jugador)[slot]
end

function PowerInventory.EstaVacio(jugador)
    if not validarJugador(jugador) then
        return true
    end
    return #obtener(jugador) == 0
end

function PowerInventory.Contiene(jugador, idPoder)
    if not validarJugador(jugador) then
        return false
    end
    return table.find(obtener(jugador), idPoder) ~= nil
end

function PowerInventory.GetSnapshot(jugador)
    if not validarJugador(jugador) then
        return {}
    end
    return table.clone(obtener(jugador))
end

function PowerInventory.Init()
    for _, jugador in Players:GetPlayers() do
        inventarios[jugador] = inventarios[jugador] or {}
        publicar(jugador)
    end

    Players.PlayerRemoving:Connect(function(jugador)
        inventarios[jugador] = nil
    end)
end

return PowerInventory