--[[
    Main (Script)
    Ubicación: ServerScriptService > Main

    Punto de entrada del MVP. Crea los RemoteEvents y conecta los módulos.
    No contiene lógica específica de combate/drop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modulos = ServerScriptService:WaitForChild("Modulos")
local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))

-- Crear Remotes una sola vez.
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local function obtenerOCrearRemote(nombre)
    local evento = Remotes:FindFirstChild(nombre)
    if evento and evento:IsA("RemoteEvent") then
        return evento
    end

    if evento then
        evento:Destroy()
    end

    evento = Instance.new("RemoteEvent")
    evento.Name = nombre
    evento.Parent = Remotes
    return evento
end

obtenerOCrearRemote("UsarPoder")
obtenerOCrearRemote("Notificacion")
obtenerOCrearRemote("Extraccion") -- Estado de canalización hacia el cliente (solo visual).
obtenerOCrearRemote("AnuncioGlobal") -- Aviso global de extracción Mítica.
obtenerOCrearRemote("AbrirHuevo") -- Resultado de abrir un huevo (solo visual).

local ZoneSystem = require(Modulos:WaitForChild("ZoneSystem"))
local PowerInventory = require(Modulos:WaitForChild("PowerInventory"))
local CombateServer = require(Modulos:WaitForChild("CombateServer"))
local DropSystem = require(Modulos:WaitForChild("DropSystem"))
local EvacSystem = require(Modulos:WaitForChild("EvacSystem"))
local EconomySystem = require(Modulos:WaitForChild("EconomySystem"))
local EggSystem = require(Modulos:WaitForChild("EggSystem"))
local PortalSystem = require(Modulos:WaitForChild("PortalSystem"))
local SaveSystem = require(Modulos:WaitForChild("SaveSystem"))

-- FASE 0.2: SaveSystem se inicializa PRIMERO para que sus conexiones de
-- PlayerAdded/PlayerRemoving se ejecuten antes que las de los demás módulos.
-- Así los datos guardados se cargan antes de asignar defaults, y el guardado
-- al salir ocurre antes de que Economy/PowerInventory limpien sus tablas.
SaveSystem.Init(Remotes)

ZoneSystem.Init()
PowerInventory.Init()
CombateServer.Init(Remotes)
DropSystem.Init(Remotes)
EvacSystem.Init(Remotes)
EconomySystem.Init()
EggSystem.Init(Remotes)
PortalSystem.Init(Remotes)

local function darPoderes(jugador)
    if PowerData.Config.ModoTest then
        -- TEST: otorga TODOS los poderes en orden fijo (slot 1 = Q).
        -- Cada uno ocupa un slot y por tanto una tecla del HUD.
        local orden = PowerData.OrdenPoderes or {}
        for _, idPoder in orden do
            PowerInventory.Agregar(jugador, idPoder)
        end
        return
    end

    if PowerInventory.EstaVacio(jugador) then
        PowerInventory.Agregar(jugador, PowerData.Config.PoderInicial)
    end
end

local function conectarJugador(jugador)
    -- El inventario no se reinicia al respawn.
    jugador.CharacterAdded:Connect(function()
        task.defer(function()
            if jugador.Parent == Players then
                darPoderes(jugador)
            end
        end)
    end)

    -- Manejar jugadores que ya existían al iniciar/reiniciar el servidor.
    if jugador.Character then
        darPoderes(jugador)
    end
end

Players.PlayerAdded:Connect(conectarJugador)

for _, jugador in Players:GetPlayers() do
    conectarJugador(jugador)
end

print("[Main] Servidor MVP 0.1E iniciado correctamente.")
print("[Main] Fase 0.2 (Persistencia) activa.")
