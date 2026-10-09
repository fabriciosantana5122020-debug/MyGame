--[[
    PortalSystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > PortalSystem

    FASE 0.1E - Portal a Zona Roja:
      - Construye un arco de portal DENTRO de la Safe Zone, en el borde
        orientado hacia la Red Zone (se ubica solo a partir de las zonas).
      - ProximityPrompt (tecla P) que teletransporta al jugador a un
        punto ALEATORIO de la Zona Roja (sobre el suelo real).
      - Validaciones 100% servidor: jugador vivo, dentro de la Safe Zone
        y reutilización mínima entre viajes (anti-spam).
      - El retorno a la Safe Zone SOLO es posible evacuando (EvacSystem).

    No modifica ZoneSystem ni ningún otro módulo existente.
]]

local Players = game:GetService("Players")

local ZoneSystem = require(script.Parent.ZoneSystem)

local PortalSystem = {}
local remotes
local reutilizacion = {} -- [Player] = os.clock() del próximo uso permitido

local INTERVALO_REUTILIZACION = 3
local MARGEN_BORDE = 20 -- margen dentro de la Red Zone al elegir punto
local COLOR_PORTAL = Color3.fromRGB(170, 60, 255)

local function notificar(jugador, texto)
    local evento = remotes and remotes:FindFirstChild("Notificacion")
    if evento then
        evento:FireClient(jugador, texto)
    end
end

local function obtenerVivo(jugador)
    local personaje = jugador.Character
    local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
    if humanoide and humanoide.Health > 0 then
        return personaje
    end
    return nil
end

-- Punto aleatorio dentro de la Red Zone, sobre el suelo real.
local function puntoAleatorioRedZone()
    local zonas = workspace:FindFirstChild("Zones")
    local roja = zonas and zonas:FindFirstChild("RedZone")
    if not (roja and roja:IsA("BasePart")) then
        return nil
    end

    local rx = (math.random() * 2 - 1) * (roja.Size.X / 2 - MARGEN_BORDE)
    local rz = (math.random() * 2 - 1) * (roja.Size.Z / 2 - MARGEN_BORDE)
    local x = roja.Position.X + rx
    local z = roja.Position.Z + rz

    local resultado = workspace:Raycast(
        Vector3.new(x, roja.Position.Y + 60, z),
        Vector3.new(0, -300, 0)
    )
    if not resultado then
        return nil
    end

    return resultado.Position + Vector3.new(0, 3.5, 0)
end

function PortalSystem.Viajar(jugador)
    if not (typeof(jugador) == "Instance" and jugador:IsA("Player") and jugador.Parent == Players) then
        return
    end

    local personaje = obtenerVivo(jugador)
    if not personaje then
        return
    end

    -- Solo se puede viajar DESDE la Safe Zone.
    if ZoneSystem.GetPlayerZone(jugador) ~= "Safe" then
        notificar(jugador, "El portal solo funciona en la zona segura")
        return
    end

    local listoEn = reutilizacion[jugador] or 0
    if listoEn > os.clock() then
        return
    end

    local destino = puntoAleatorioRedZone()
    if not destino then
        notificar(jugador, "La Zona Roja no está disponible")
        return
    end

    reutilizacion[jugador] = os.clock() + INTERVALO_REUTILIZACION

    personaje:PivotTo(CFrame.new(destino))
    notificar(jugador, "Has entrado en la Zona Roja: ¡el retorno solo es posible evacuando!")
end

---------------------------------------------------------------------
-- CONSTRUCCIÓN DEL PORTAL (borde de la Safe Zone hacia la Red Zone)
---------------------------------------------------------------------

local function construirPortal()
    if workspace:FindFirstChild("Portal") then
        return -- Ya construido (no pisar un mapa manual).
    end

    local zonas = workspace:FindFirstChild("Zones")
    local segura = zonas and zonas:FindFirstChild("SafeZone")
    local roja = zonas and zonas:FindFirstChild("RedZone")
    if not (segura and segura:IsA("BasePart")) then
        return
    end

    -- Dirección horizontal Safe Zone -> Red Zone.
    local dir = Vector3.new(1, 0, 0)
    if roja and roja:IsA("BasePart") then
        local d = Vector3.new(roja.Position.X - segura.Position.X, 0, roja.Position.Z - segura.Position.Z)
        if d.Magnitude > 1 then
            dir = d.Unit
        end
    end

    -- Avanzar desde el centro de la Safe Zone hasta cerca del borde.
    local margen = 15
    local hx, hz = segura.Size.X / 2, segura.Size.Z / 2
    local avance = math.huge
    if dir.X ~= 0 then
        avance = math.min(avance, (hx - margen) / math.abs(dir.X))
    end
    if dir.Z ~= 0 then
        avance = math.min(avance, (hz - margen) / math.abs(dir.Z))
    end
    if avance == math.huge or avance <= 0 then
        avance = 0
    end

    local centro = segura.Position + dir * avance

    -- Suelo real bajo el portal.
    local resultado = workspace:Raycast(
        Vector3.new(centro.X, centro.Y + 60, centro.Z),
        Vector3.new(0, -300, 0)
    )
    local sueloY = resultado and resultado.Position.Y or centro.Y

    local base = Vector3.new(centro.X, sueloY, centro.Z)
    local cf = CFrame.lookAt(base, base + dir) -- -Z apunta a la Red Zone
    local derecha = cf.RightVector

    local carpeta = Instance.new("Folder")
    carpeta.Name = "Portal"

    local function parte(nombre, tamano, cframe, material, transparencia)
        local p = Instance.new("Part")
        p.Name = nombre
        p.Size = tamano
        p.CFrame = cframe
        p.Color = COLOR_PORTAL
        p.Material = material or Enum.Material.Neon
        p.Transparency = transparencia or 0
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Parent = carpeta
        return p
    end

    -- Arco: dos pilares y travesaño (se atraviesa caminando hacia la Red Zone).
    parte("PilarIzq", Vector3.new(2, 14, 2), CFrame.new(base + Vector3.new(0, 7, 0) - derecha * 5) * cf.Rotation)
    parte("PilarDer", Vector3.new(2, 14, 2), CFrame.new(base + Vector3.new(0, 7, 0) + derecha * 5) * cf.Rotation)
    local travesano = parte("Travesano", Vector3.new(2, 2, 12), CFrame.new(base + Vector3.new(0, 14, 0)) * cf.Rotation)

    -- Velo del portal (atravesable).
    local velo = parte("Velo", Vector3.new(8, 12, 0.4), CFrame.new(base + Vector3.new(0, 6.5, 0)) * cf.Rotation, Enum.Material.ForceField, 0.2)

    local luz = Instance.new("PointLight")
    luz.Color = COLOR_PORTAL
    luz.Range = 16
    luz.Brightness = 2
    luz.Parent = velo

    -- Cartel del portal.
    local cartel = Instance.new("BillboardGui")
    cartel.Name = "Info"
    cartel.Size = UDim2.fromOffset(260, 50)
    cartel.StudsOffset = Vector3.new(0, 5, 0)
    cartel.AlwaysOnTop = true
    cartel.Parent = travesano

    local texto = Instance.new("TextLabel")
    texto.Size = UDim2.fromScale(1, 1)
    texto.BackgroundTransparency = 1
    texto.TextColor3 = COLOR_PORTAL
    texto.TextStrokeTransparency = 0.4
    texto.TextScaled = true
    texto.Font = Enum.Font.GothamBold
    texto.Text = "PORTAL → ZONA ROJA"
    texto.Parent = cartel

    -- Base de interacción (invisible) para el prompt.
    local basePrompt = Instance.new("Part")
    basePrompt.Name = "Base"
    basePrompt.Size = Vector3.new(10, 0.4, 10)
    basePrompt.CFrame = CFrame.new(base + Vector3.new(0, 0.2, 0)) * cf.Rotation
    basePrompt.Transparency = 1
    basePrompt.Anchored = true
    basePrompt.CanCollide = false
    basePrompt.CanTouch = false
    basePrompt.CanQuery = false
    basePrompt.Parent = carpeta

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Viajar a la Zona Roja"
    prompt.ObjectText = "Portal"
    prompt.HoldDuration = 0.3
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    -- P: G esferas, H huevos, T evacuación.
    prompt.KeyboardKeyCode = Enum.KeyCode.P
    prompt.Parent = basePrompt

    prompt.Triggered:Connect(function(jugador)
        PortalSystem.Viajar(jugador)
    end)

    carpeta.Parent = workspace
end

function PortalSystem.Init(carpetaRemotes)
    remotes = carpetaRemotes

    construirPortal()

    Players.PlayerRemoving:Connect(function(jugador)
        reutilizacion[jugador] = nil
    end)

    print("[PortalSystem] Portal a la Zona Roja listo (tecla P).")
end

return PortalSystem