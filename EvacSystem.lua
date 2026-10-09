--[[
    EvacSystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > EvacSystem

    FASE 0.1C - Sistema de Evacuación (core loop de extracción):
      - Construye una Zona de Evacuación DENTRO de la Zona Roja
        (en el lado opuesto a la Safe Zone, se ubica sola).
      - El jugador inicia la evacuación con un ProximityPrompt (tecla T).
      - Canalización de Config.DuracionEvacSeg (15s) gestionada 100% en
        el servidor. Se cancela si recibe daño, muere o sale de la zona.
      - Al completar: los poderes rescatados se convierten en Monedas
        (EconomySystem, 100% servidor), se anuncia globalmente, el personaje
        se elimina del mapa y respawnea en la Safe Zone con el inventario limpio.

    No modifica PowerData, ZoneSystem, PowerInventory ni DropSystem.
    Reutiliza el remote "Extraccion" para la barra del cliente
    (payload con Etiqueta = "Evacuando").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))
local ZoneSystem = require(script.Parent.ZoneSystem)
local PowerInventory = require(script.Parent.PowerInventory)
local EconomySystem = require(script.Parent.EconomySystem)

local EvacSystem = {}

local remotes
local zonaEvac -- Part de detección (workspace.EvacZone)
local canalizando = {} -- [Player] = true

local INTERVALO = 0.2
local COLOR_EVAC = Color3.fromRGB(60, 220, 160)
local TAMANO_ZONA = Vector3.new(26, 14, 26)

local function notificar(jugador, texto)
    local evento = remotes and remotes:FindFirstChild("Notificacion")
    if evento then
        evento:FireClient(jugador, texto)
    end
end

-- Anuncio global (escape exitoso) a todos los clientes.
local function anunciar(texto)
    local evento = remotes and remotes:FindFirstChild("Notificacion")
    if evento then
        evento:FireAllClients(texto)
    end
end

-- Reutiliza la barra de extracción del cliente (solo visual).
local function informarBarra(jugador, payload)
    local evento = remotes and remotes:FindFirstChild("Extraccion")
    if evento then
        evento:FireClient(jugador, payload)
    end
end

local function puntoEnZona(posicion)
    if not zonaEvac then
        return false
    end
    local localPos = zonaEvac.CFrame:PointToObjectSpace(posicion)
    local mitad = zonaEvac.Size / 2
    return math.abs(localPos.X) <= mitad.X
        and math.abs(localPos.Y) <= mitad.Y
        and math.abs(localPos.Z) <= mitad.Z
end

local function estaEnZonaEvac(jugador)
    local personaje = jugador.Character
    local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")
    return raiz ~= nil and puntoEnZona(raiz.Position)
end

local function obtenerVivo(jugador)
    local personaje = jugador.Character
    local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
    if humanoide and humanoide.Health > 0 then
        return personaje, humanoide
    end
    return nil, nil
end

---------------------------------------------------------------------
-- CONSTRUCCIÓN DE LA ZONA DE EVACUACIÓN (dentro de la Red Zone)
---------------------------------------------------------------------

local function construirZona()
    -- Si la zona ya existe (mapa manual del equipo), reutilizarla.
    local carpetaExistente = workspace:FindFirstChild("Evacuacion")
    if carpetaExistente then
        zonaEvac = carpetaExistente:FindFirstChild("EvacZone")
        if zonaEvac then
            return
        end
    end

    local zonas = workspace:FindFirstChild("Zones")
    local roja = zonas and zonas:FindFirstChild("RedZone")
    local segura = zonas and zonas:FindFirstChild("SafeZone")

    local centroXZ

    if roja then
        -- Lado opuesto a la Safe Zone (o al centro del mapa si no hay).
        local referencia = segura or { Position = Vector3.zero }
        local dir = Vector3.new(roja.Position.X - referencia.Position.X, 0, roja.Position.Z - referencia.Position.Z)

        centroXZ = roja.Position
        if dir.Magnitude > 1 then
            centroXZ = roja.Position + dir.Unit * math.min(roja.Size.X, roja.Size.Z) * 0.3
        end
    else
        centroXZ = Vector3.new(60, 4, 0)
    end

    -- Buscar el suelo real bajo el punto elegido.
    local resultado = workspace:Raycast(
        Vector3.new(centroXZ.X, centroXZ.Y + 60, centroXZ.Z),
        Vector3.new(0, -300, 0)
    )
    local sueloY = resultado and resultado.Position.Y or centroXZ.Y

    local carpeta = Instance.new("Folder")
    carpeta.Name = "Evacuacion"

    -- Plataforma visible.
    local pad = Instance.new("Part")
    pad.Name = "EvacPad"
    pad.Shape = Enum.PartType.Cylinder
    pad.Size = Vector3.new(0.4, 24, 24)
    pad.CFrame = CFrame.new(centroXZ.X, sueloY + 0.2, centroXZ.Z) * CFrame.Angles(0, 0, math.rad(90))
    pad.Color = COLOR_EVAC
    pad.Material = Enum.Material.Neon
    pad.Anchored = true
    pad.CanCollide = false
    pad.CanTouch = false
    pad.CanQuery = false
    pad.Parent = carpeta

    -- Columna guía para verla desde lejos.
    local haz = Instance.new("Part")
    haz.Name = "HazEvac"
    haz.Size = Vector3.new(6, 60, 6)
    haz.CFrame = CFrame.new(centroXZ.X, sueloY + 30, centroXZ.Z)
    haz.Color = COLOR_EVAC
    haz.Material = Enum.Material.Neon
    haz.Transparency = 0.8
    haz.Anchored = true
    haz.CanCollide = false
    haz.CanTouch = false
    haz.CanQuery = false
    haz.Parent = carpeta

    local luz = Instance.new("PointLight")
    luz.Color = COLOR_EVAC
    luz.Range = 25
    luz.Brightness = 2
    luz.Parent = pad

    -- Zona de detección (invisible, igual criterio que ZoneSystem).
    zonaEvac = Instance.new("Part")
    zonaEvac.Name = "EvacZone"
    zonaEvac.Size = TAMANO_ZONA
    zonaEvac.CFrame = CFrame.new(centroXZ.X, sueloY + TAMANO_ZONA.Y / 2, centroXZ.Z)
    zonaEvac.Transparency = 1
    zonaEvac.Anchored = true
    zonaEvac.CanCollide = false
    zonaEvac.CanTouch = false
    zonaEvac.CanQuery = false
    zonaEvac.Parent = carpeta

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Evacuar"
    prompt.ObjectText = "Zona de Evacuación"
    prompt.HoldDuration = 0.5
    prompt.MaxActivationDistance = 14
    prompt.RequiresLineOfSight = false
    -- T: G ya la usan las esferas de poder.
    prompt.KeyboardKeyCode = Enum.KeyCode.T
    prompt.Parent = pad

    prompt.Triggered:Connect(function(jugador)
        EvacSystem.Iniciar(jugador)
    end)

    carpeta.Parent = workspace
end

---------------------------------------------------------------------
-- CANALIZACIÓN (100% servidor, mismo patrón que DropSystem)
---------------------------------------------------------------------

local function cancelarEvac(jugador, motivo)
    canalizando[jugador] = nil
    informarBarra(jugador, { Estado = "Cancelado", Motivo = motivo })
    notificar(jugador, "Evacuación cancelada: " .. motivo)
end

-- Convierte los poderes rescatados en Monedas:
-- base de PowerData.Config.Economia + ValorMonedas de cada rareza.
-- El poder inicial NO cuenta (se reotorga al reaparecer), para evitar
-- farmear la recompensa base sin loot.
local function calcularRecompensa(snapshot)
    local economia = PowerData.Config.Economia or {}
    local total = economia.RecompensaBaseEvac or 0
    local rescatados = 0

    for _, idPoder in snapshot do
        if idPoder ~= PowerData.Config.PoderInicial then
            local datos = PowerData.Powers[idPoder]
            local rareza = datos and PowerData.Rarities[datos.Rareza]
            total += (rareza and rareza.ValorMonedas) or 0
            rescatados += 1
        end
    end

    return total, rescatados
end

local function completarEvac(jugador)
    canalizando[jugador] = nil

    -- Contabilizar los poderes evacuados y convertirlos en Monedas.
    local snapshot = PowerInventory.GetSnapshot(jugador)
    local recompensa, rescatados = calcularRecompensa(snapshot)
    EconomySystem.Agregar(jugador, recompensa)

    jugador:SetAttribute("PoderesEvacuados", (jugador:GetAttribute("PoderesEvacuados") or 0) + rescatados)
    jugador:SetAttribute("EscapesExitosos", (jugador:GetAttribute("EscapesExitosos") or 0) + 1)

    informarBarra(jugador, { Estado = "Completado" })
    notificar(jugador, string.format("¡Escape exitoso! +%d monedas", recompensa))
    anunciar(string.format("¡%s ha escapado con éxito! (+%d poderes, +%d monedas)", jugador.DisplayName, rescatados, recompensa))

    -- Efecto visual: columna de luz en el pad.
    if zonaEvac then
        local efecto = Instance.new("Part")
        efecto.Name = "EscapeExitoso"
        efecto.Size = Vector3.new(10, 1, 10)
        efecto.CFrame = CFrame.new(zonaEvac.Position)
        efecto.Color = Color3.new(1, 1, 1)
        efecto.Material = Enum.Material.Neon
        efecto.Anchored = true
        efecto.CanCollide = false
        efecto.CanTouch = false
        efecto.CanQuery = false
        efecto.Parent = workspace

        task.spawn(function()
            for i = 1, 20 do
                if not efecto.Parent then
                    return
                end
                efecto.Size += Vector3.new(0, 4, 0)
                efecto.CFrame = CFrame.new(zonaEvac.Position + Vector3.new(0, 2 * i, 0))
                efecto.Transparency = i / 20
                task.wait()
            end
            if efecto.Parent then
                efecto:Destroy()
            end
        end)
    end

    -- Inventario limpio y respawn en Safe Zone (SafeSpawn).
    -- Main reotorgará solo el poder inicial al reaparecer.
    PowerInventory.Vaciar(jugador)
    task.delay(0.15, function()
        if jugador.Parent == Players then
            jugador:LoadCharacter()
        end
    end)
end

function EvacSystem.Iniciar(jugador)
    if canalizando[jugador] then
        return
    end

    local personaje, humanoide = obtenerVivo(jugador)
    if not personaje then
        return
    end
    if not estaEnZonaEvac(jugador) then
        notificar(jugador, "Debes estar dentro de la zona de evacuación")
        return
    end
    -- Solo se evacúa loot: el poder inicial se reotorga al reaparecer, así
    -- que evacuar sin loot no daría recompensa (y permitiría farmear la base).
    local tieneLoot = false
    for _, idPoder in PowerInventory.GetSnapshot(jugador) do
        if idPoder ~= PowerData.Config.PoderInicial then
            tieneLoot = true
            break
        end
    end
    if not tieneLoot then
        notificar(jugador, "No tienes poderes rescatados: extrae esferas en la Zona Roja")
        return
    end

    local duracion = PowerData.Config.DuracionEvacSeg or 15
    canalizando[jugador] = true

    local saludBase = humanoide.Health
    local cancelada = false
    local conexiones = {}

    local function cancelar(motivo)
        if cancelada then
            return
        end
        cancelada = true
        for _, conexion in conexiones do
            conexion:Disconnect()
        end
        cancelarEvac(jugador, motivo)
    end

    -- Barra visual del cliente (reutiliza el HUD de extracción).
    informarBarra(jugador, {
        Estado = "Iniciar",
        Etiqueta = "Evacuando",
        Segundos = duracion,
        Color = COLOR_EVAC,
    })

    -- Regla: recibir daño cancela la evacuación.
    conexiones[1] = humanoide.HealthChanged:Connect(function(nuevaSalud)
        if nuevaSalud < saludBase then
            cancelar("recibiste daño")
        elseif nuevaSalud > saludBase then
            saludBase = nuevaSalud
        end
    end)

    -- Regla: morir cancela la evacuación.
    conexiones[2] = humanoide.Died:Connect(function()
        cancelar("moriste")
    end)

    task.spawn(function()
        local inicio = os.clock()

        while not cancelada do
            if not (jugador.Parent == Players and jugador.Character == personaje) then
                cancelar("perdiste tu personaje")
                return
            end
            -- Regla: salir de la zona cancela la evacuación.
            if not estaEnZonaEvac(jugador) then
                cancelar("saliste de la zona de evacuación")
                return
            end

            if os.clock() - inicio >= duracion then
                break
            end

            task.wait(INTERVALO)
        end

        if cancelada then
            return
        end

        for _, conexion in conexiones do
            conexion:Disconnect()
        end

        -- Revalidación final antes de conceder el escape.
        if not obtenerVivo(jugador) or not estaEnZonaEvac(jugador) then
            cancelar("condiciones inválidas")
            return
        end

        completarEvac(jugador)
    end)
end

function EvacSystem.Init(carpetaRemotes)
    remotes = carpetaRemotes

    construirZona()

    Players.PlayerRemoving:Connect(function(jugador)
        canalizando[jugador] = nil
    end)

    print("[EvacSystem] Zona de evacuación lista (canalización " .. (PowerData.Config.DuracionEvacSeg or 15) .. "s).")
end

return EvacSystem