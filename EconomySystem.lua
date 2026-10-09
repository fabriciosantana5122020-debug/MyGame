--[[
    EconomySystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > EconomySystem

    FASE 0.3 - Economía & Niveles (100% autoritativa en servidor):
      - Guarda Monedas, Gemas, Nivel y XP de cada jugador en tablas en servidor.
      - Publica cada valor mediante attributes (Monedas, Gemas, Nivel, XP)
        para que el HUD del cliente los muestre (solo lectura visual).
      - SaveSystem carga/establece los valores persistidos.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))

local EconomySystem = {}

-- Tablas de estado en servidor (una entrada por jugador activo)
local monedas = {} -- [Player] = number
local gemas = {}   -- [Player] = number
local nivel = {}   -- [Player] = number
local xp = {}      -- [Player] = number

-- Límites
local MAX_MONEDAS = 1e9
local MAX_GEMAS = 1e9
local NIVEL_MAXIMO = 999

local function validar(jugador)
    return typeof(jugador) == "Instance"
        and jugador:IsA("Player")
        and jugador.Parent == Players
end

local function publicar(jugador)
    if validar(jugador) then
        jugador:SetAttribute("Monedas", monedas[jugador] or 0)
        jugador:SetAttribute("Gemas", gemas[jugador] or 0)
        jugador:SetAttribute("Nivel", nivel[jugador] or 1)
        jugador:SetAttribute("XP", xp[jugador] or 0)
    end
end

-- ===================== MONEDAS =====================

-- Saldo actual del jugador.
function EconomySystem.Obtener(jugador)
    if not validar(jugador) then
        return 0
    end
    return monedas[jugador] or 0
end

-- Añade monedas (recompensas, reembolsos). Devuelve el nuevo saldo.
function EconomySystem.Agregar(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" or cantidad <= 0 then
        return EconomySystem.Obtener(jugador)
    end

    monedas[jugador] = (monedas[jugador] or 0) + cantidad
    publicar(jugador)
    return monedas[jugador]
end

-- Establece un saldo exacto (usado SOLO por SaveSystem al cargar
-- un perfil guardado). Valida y limita el valor antes de asignarlo.
function EconomySystem.Establecer(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" then
        return false
    end
    if cantidad ~= cantidad then -- NaN
        return false
    end

    monedas[jugador] = math.clamp(math.floor(cantidad), 0, MAX_MONEDAS)
    publicar(jugador)
    return true
end

-- Cobra si hay saldo suficiente. Devuelve true si se cobró.
function EconomySystem.Cobrar(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" or cantidad <= 0 then
        return false
    end

    if (monedas[jugador] or 0) < cantidad then
        return false
    end

    monedas[jugador] -= cantidad
    publicar(jugador)
    return true
end

-- ===================== GEMAS =====================

function EconomySystem.ObtenerGemas(jugador)
    if not validar(jugador) then
        return 0
    end
    return gemas[jugador] or 0
end

function EconomySystem.AgregarGemas(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" or cantidad <= 0 then
        return EconomySystem.ObtenerGemas(jugador)
    end

    gemas[jugador] = (gemas[jugador] or 0) + cantidad
    publicar(jugador)
    return gemas[jugador]
end

function EconomySystem.EstablecerGemas(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" then
        return false
    end
    if cantidad ~= cantidad then -- NaN
        return false
    end

    gemas[jugador] = math.clamp(math.floor(cantidad), 0, MAX_GEMAS)
    publicar(jugador)
    return true
end

function EconomySystem.CobrarGemas(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" or cantidad <= 0 then
        return false
    end

    if (gemas[jugador] or 0) < cantidad then
        return false
    end

    gemas[jugador] -= cantidad
    publicar(jugador)
    return true
end

-- ===================== NIVEL & XP =====================

function EconomySystem.ObtenerNivel(jugador)
    if not validar(jugador) then
        return 1
    end
    return nivel[jugador] or 1
end

function EconomySystem.EstablecerNivel(jugador, valor)
    if not validar(jugador) or typeof(valor) ~= "number" then
        return false
    end
    if valor ~= valor then -- NaN
        return false
    end

    nivel[jugador] = math.clamp(math.floor(valor), 1, NIVEL_MAXIMO)
    publicar(jugador)
    return true
end

function EconomySystem.ObtenerXP(jugador)
    if not validar(jugador) then
        return 0
    end
    return xp[jugador] or 0
end

function EconomySystem.EstablecerXP(jugador, valor)
    if not validar(jugador) or typeof(valor) ~= "number" then
        return false
    end
    if valor ~= valor then -- NaN
        return false
    end

    xp[jugador] = math.max(math.floor(valor), 0)
    publicar(jugador)
    return true
end

-- Añade XP y sube de nivel automáticamente si se alcanza el umbral.
-- Formula: XP necesaria para subir = nivel * 100
-- Devuelve el nuevo nivel del jugador.
function EconomySystem.AgregarXP(jugador, cantidad)
    if not validar(jugador) or typeof(cantidad) ~= "number" or cantidad <= 0 then
        return EconomySystem.ObtenerNivel(jugador)
    end

    xp[jugador] = (xp[jugador] or 0) + cantidad

    -- Subida de nivel automática
    while xp[jugador] >= (nivel[jugador] or 1) * 100 do
        xp[jugador] -= (nivel[jugador] or 1) * 100
        nivel[jugador] = math.min((nivel[jugador] or 1) + 1, NIVEL_MAXIMO)
    end

    publicar(jugador)
    return nivel[jugador]
end

function EconomySystem.Init()
    local inicial = PowerData.Config.Economia
        and PowerData.Config.Economia.MonedasIniciales
        or 0

    local function conectar(jugador)
        monedas[jugador] = monedas[jugador] or inicial
        gemas[jugador] = gemas[jugador] or 0
        nivel[jugador] = nivel[jugador] or 1
        xp[jugador] = xp[jugador] or 0
        publicar(jugador)
    end

    Players.PlayerAdded:Connect(conectar)
    Players.PlayerRemoving:Connect(function(jugador)
        monedas[jugador] = nil
        gemas[jugador] = nil
        nivel[jugador] = nil
        xp[jugador] = nil
    end)

    for _, jugador in Players:GetPlayers() do
        conectar(jugador)
    end

    print("[EconomySystem] Fase 0.3 iniciada (Monedas, Gemas, Nivel, XP)")
end

return EconomySystem