--[[
    CombateServer (ModuleScript)
    Ubicación: ServerScriptService > Modulos > CombateServer

    TODA la autoridad de combate está en el servidor.
    El cliente solo solicita: (slot, posición objetivo).

    El servidor valida:
      - tipos y valores recibidos
      - jugador vivo
      - zona del atacante
      - poder real del slot
      - cooldown
      - alcance de cada poder
      - reglas de PvP

    Regla MVP:
      - Jugador vs jugador: ambos deben estar en Zona Roja.
      - NPC/Dummy: puede recibir daño fuera de la Zona Roja.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))
local ZoneSystem = require(script.Parent.ZoneSystem)
local PowerInventory = require(script.Parent.PowerInventory)

local CombateServer = {}
local remotes
local cooldowns = {} -- [Player] = { [PowerId] = tiempoUnix }

local function notificar(jugador, texto)
    if remotes and remotes:FindFirstChild("Notificacion") then
        remotes.Notificacion:FireClient(jugador, texto)
    end
end

local function obtenerVivo(jugador)
    local personaje = jugador.Character
    local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
    local raiz = personaje and personaje:FindFirstChild("HumanoidRootPart")

    if humanoide and raiz and humanoide.Health > 0 then
        return raiz, humanoide, personaje
    end

    return nil
end

local function humanoideDeParte(parte)
    if not parte or not parte:IsA("BasePart") then
        return nil
    end

    local modelo = parte:FindFirstAncestorOfClass("Model")
    return modelo and modelo:FindFirstChildOfClass("Humanoid")
end

local function crearTagAsesino(humanoide, atacante)
    local anterior = humanoide:FindFirstChild("creator")
    if anterior then
        anterior:Destroy()
    end

    local tag = Instance.new("ObjectValue")
    tag.Name = "creator"
    tag.Value = atacante
    tag.Parent = humanoide
    Debris:AddItem(tag, 5)
end

local function aplicarDano(atacante, humanoide, cantidad)
    if not humanoide or humanoide.Health <= 0 then
        return false
    end

    local modeloVictima = humanoide.Parent
    local victima = modeloVictima and Players:GetPlayerFromCharacter(modeloVictima)

    if victima then
        if victima == atacante then
            return false
        end

        -- PvP únicamente si ambos están dentro de la Zona Roja.
        if ZoneSystem.GetPlayerZone(atacante) ~= "Red" then
            return false
        end
        if ZoneSystem.GetPlayerZone(victima) ~= "Red" then
            return false
        end
    end

    crearTagAsesino(humanoide, atacante)
    humanoide:TakeDamage(cantidad)
    return true
end

local function paramsSinPersonaje(personaje)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { personaje }
    params.IgnoreWater = true
    return params
end

local function crearEfecto(nombre, forma, tamano, cframe, color, transparencia)
    local p = Instance.new("Part")
    p.Name = nombre
    p.Shape = forma
    p.Size = tamano
    p.CFrame = cframe
    p.Color = color
    p.Transparency = transparencia
    p.Material = Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Parent = workspace
    return p
end

---------------------------------------------------------------------
-- VFX: helpers visuales reutilizables.
-- Solo decoran: NO alteran daño, validaciones ni cooldowns.
---------------------------------------------------------------------

local function crearParticulas(padre, color, tasa, tamano, velocidad, duracion)
    local p = Instance.new("ParticleEmitter")
    p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    p.Color = ColorSequence.new(color)
    p.LightEmission = 1
    p.LightInfluence = 0
    p.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, tamano),
        NumberSequenceKeypoint.new(1, 0),
    })
    p.Lifetime = NumberRange.new(duracion * 0.4, duracion)
    p.Rate = tasa
    p.Speed = NumberRange.new(velocidad * 0.4, velocidad)
    p.SpreadAngle = Vector2.new(180, 180)
    p.Rotation = NumberRange.new(0, 360)
    p.RotSpeed = NumberRange.new(-120, 120)
    p.Acceleration = Vector3.new(0, 6, 0)
    p.Parent = padre
    return p
end

-- Anillo expansivo horizontal (onda de choque).
local function crearAnillo(posicion, radioFinal, color, duracion)
    local anillo = crearEfecto(
        "Anillo",
        Enum.PartType.Cylinder,
        Vector3.new(0.5, 2, 2),
        CFrame.new(posicion) * CFrame.Angles(0, 0, math.rad(90)),
        color,
        0.35
    )

    task.spawn(function()
        local t0 = os.clock()
        while anillo.Parent and os.clock() - t0 < duracion do
            local prog = (os.clock() - t0) / duracion
            local diametro = 2 + radioFinal * 2 * prog
            anillo.Size = Vector3.new(0.5, diametro, diametro)
            anillo.Transparency = 0.35 + prog * 0.65
            task.wait()
        end
        if anillo.Parent then
            anillo:Destroy()
        end
    end)

    return anillo
end

-- Explosión completa: destello + luz + anillo expansivo + chispas.
local function crearExplosion(posicion, radio, color)
    local destello = crearEfecto(
        "Destello",
        Enum.PartType.Ball,
        Vector3.one * math.max(radio * 0.6, 2),
        CFrame.new(posicion),
        Color3.new(1, 1, 1),
        0
    )
    local luzDestello = Instance.new("PointLight")
    luzDestello.Color = color
    luzDestello.Range = math.max(radio * 2, 10)
    luzDestello.Brightness = 5
    luzDestello.Parent = destello
    Debris:AddItem(destello, 0.15)

    crearAnillo(posicion + Vector3.new(0, 0.6, 0), radio, color, 0.5)

    local emisorChispas = crearEfecto(
        "Chispas",
        Enum.PartType.Ball,
        Vector3.one * 1,
        CFrame.new(posicion),
        color,
        1
    )
    crearParticulas(emisorChispas, color, 100, 1.4, radio * 4, 0.7)
    Debris:AddItem(emisorChispas, 1)
end

---------------------------------------------------------------------
-- FIREBALL
-- Proyectil visual controlado por servidor + raycast continuo.
-- Evitamos depender de Touched para un proyectil rápido.
---------------------------------------------------------------------

local function poderFireball(jugador, datos, objetivo)
    local raiz, _, personaje = obtenerVivo(jugador)
    if not raiz then
        return false
    end

    local origen = raiz.Position + Vector3.new(0, 1.5, 0)
    local direccion = objetivo - origen

    if direccion.Magnitude < 0.1 then
        direccion = raiz.CFrame.LookVector
    else
        direccion = direccion.Unit
    end

    local bola = Instance.new("Part")
    bola.Name = "Fireball"
    bola.Shape = Enum.PartType.Ball
    bola.Size = Vector3.one * datos.Radio * 2
    bola.Material = Enum.Material.Neon
    bola.Color = datos.Color
    bola.Anchored = true
    bola.CanCollide = false
    bola.CanTouch = false
    bola.CanQuery = false
    bola.CastShadow = false
    bola.Position = origen + direccion * 3
    bola.Parent = workspace

    local luz = Instance.new("PointLight")
    luz.Color = datos.Color
    luz.Range = 10
    luz.Brightness = 2
    luz.Parent = bola

    -- Estela de fuego mientras la bola viaja.
    crearParticulas(bola, datos.Color, 70, 1.6, 5, 0.45)

    local velocidad = datos.Velocidad
    local maxVida = datos.VidaSeg
    local inicio = os.clock()
    local ultimaPosicion = bola.Position
    local terminado = false
    local conexion

    local function finalizar()
        if terminado then
            return
        end
        terminado = true
        if conexion then
            conexion:Disconnect()
            conexion = nil
        end
        if bola.Parent then
            bola:Destroy()
        end
    end

    conexion = RunService.Heartbeat:Connect(function(dt)
        if not bola.Parent or not personaje.Parent or os.clock() - inicio >= maxVida then
            finalizar()
            return
        end

        local desplazamiento = direccion * velocidad * dt
        local resultado = workspace:Raycast(
            ultimaPosicion,
            desplazamiento,
            paramsSinPersonaje(personaje)
        )

        if resultado then
            bola.Position = resultado.Position

            local humanoide = humanoideDeParte(resultado.Instance)
            if humanoide then
                aplicarDano(jugador, humanoide, datos.Dano)
            end

            crearExplosion(resultado.Position, datos.Radio * 4, datos.Color)
            finalizar()
            return
        end

        local nuevaPosicion = ultimaPosicion + desplazamiento
        bola.Position = nuevaPosicion
        ultimaPosicion = nuevaPosicion
    end)

    return true
end

---------------------------------------------------------------------
-- LIGHTNING
---------------------------------------------------------------------

local function poderLightning(jugador, datos, objetivo)
    local raiz, _, personaje = obtenerVivo(jugador)
    if not raiz then
        return false
    end

    local desfase = objetivo - raiz.Position
    if desfase.Magnitude > datos.AlcanceMax then
        objetivo = raiz.Position + desfase.Unit * datos.AlcanceMax
    end

    local resultado = workspace:Raycast(
        objetivo + Vector3.new(0, 50, 0),
        Vector3.new(0, -200, 0),
        paramsSinPersonaje(personaje)
    )

    local suelo = resultado and resultado.Position or objetivo

    local aviso = crearEfecto(
        "AvisoRayo",
        Enum.PartType.Cylinder,
        Vector3.new(0.2, datos.RadioArea * 2, datos.RadioArea * 2),
        CFrame.new(suelo + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
        datos.Color,
        0.6
    )

    task.delay(datos.RetrasoSeg, function()
        if aviso.Parent then
            aviso:Destroy()
        end

        local golpeados = {}
        for _, parte in workspace:GetPartBoundsInRadius(suelo, datos.RadioArea) do
            local humanoide = humanoideDeParte(parte)
            if humanoide and not golpeados[humanoide] then
                golpeados[humanoide] = true
                aplicarDano(jugador, humanoide, datos.Dano)
            end
        end

        -- Rayo principal (columna vertical brillante).
        local rayo = crearEfecto(
            "Rayo",
            Enum.PartType.Block,
            Vector3.new(1.5, 80, 1.5),
            CFrame.new(suelo + Vector3.new(0, 40, 0)),
            datos.Color,
            0
        )

        local luzRayo = Instance.new("PointLight")
        luzRayo.Color = datos.Color
        luzRayo.Range = datos.RadioArea * 2
        luzRayo.Brightness = 5
        luzRayo.Parent = rayo
        Debris:AddItem(rayo, 0.25)

        -- Rayos secundarios en zigzag (más electricidad y drama).
        local numPuntos = 12
        for zigzag = 1, 2 do
            local prev = suelo
            for i = 1, numPuntos do
                local t = i / numPuntos
                local ondulacion = (1 - math.abs(t - 0.5) * 2) * 5
                local punto = suelo
                    + Vector3.new(0, 80 * t, 0)
                    + Vector3.new(
                        (math.random() - 0.5) * ondulacion,
                        0,
                        (math.random() - 0.5) * ondulacion
                    )
                local medio = (prev + punto) / 2
                local largo = (punto - prev).Magnitude
                local seg = crearEfecto(
                    "RayoSeg",
                    Enum.PartType.Block,
                    Vector3.new(0.4, 0.4, largo),
                    CFrame.lookAt(medio, punto),
                    datos.Color,
                    0.1
                )
                Debris:AddItem(seg, 0.2)
                prev = punto
            end
        end

        -- Impacto eléctrico en el suelo.
        crearExplosion(suelo, datos.RadioArea, datos.Color)
    end)

    return true
end

---------------------------------------------------------------------
-- TELEPORT
---------------------------------------------------------------------

local function poderTeleport(jugador, datos, objetivo)
    local raiz, _, personaje = obtenerVivo(jugador)
    if not raiz then
        return false
    end

    local plano = Vector3.new(
        objetivo.X - raiz.Position.X,
        0,
        objetivo.Z - raiz.Position.Z
    )

    if plano.Magnitude < 1 then
        return false
    end

    local distancia = math.min(plano.Magnitude, datos.AlcanceMax)
    local direccion = plano.Unit
    local parametros = paramsSinPersonaje(personaje)

    -- Evitar atravesar paredes.
    local choque = workspace:Raycast(
        raiz.Position + Vector3.new(0, 2, 0),
        direccion * distancia,
        parametros
    )

    if choque then
        distancia = math.max(choque.Distance - 4, 0)
    end

    if distancia < 2 then
        notificar(jugador, "No hay espacio para teletransportarte ahí")
        return false
    end

    local destinoHorizontal = raiz.Position + direccion * distancia

    -- Buscar el suelo para no dejar al jugador flotando/enterrado.
    local suelo = workspace:Raycast(
        destinoHorizontal + Vector3.new(0, 30, 0),
        Vector3.new(0, -80, 0),
        parametros
    )

    local posicionFinal = suelo
        and (suelo.Position + Vector3.new(0, 3, 0))
        or (destinoHorizontal + Vector3.new(0, 2, 0))

    -- Estela de partículas en el punto de origen.
    local estelaOrigen = crearEfecto(
        "EstelaTP",
        Enum.PartType.Ball,
        Vector3.one * 3,
        CFrame.new(raiz.Position),
        datos.Color,
        0.5
    )
    crearParticulas(estelaOrigen, datos.Color, 140, 1, 16, 0.5)
    Debris:AddItem(estelaOrigen, 0.8)

    raiz.CFrame = CFrame.new(posicionFinal) * CFrame.Angles(
        raiz.Orientation.X * math.pi / 180,
        raiz.Orientation.Y * math.pi / 180,
        raiz.Orientation.Z * math.pi / 180
    )

    -- Estela de partículas en el punto de destino.
    local estelaDestino = crearEfecto(
        "EstelaTP",
        Enum.PartType.Ball,
        Vector3.one * 3,
        CFrame.new(posicionFinal),
        datos.Color,
        0.5
    )
    crearParticulas(estelaDestino, datos.Color, 140, 1, 16, 0.5)
    Debris:AddItem(estelaDestino, 0.8)

    return true
end

---------------------------------------------------------------------
-- METEORO (Legendario)
-- Aviso en el suelo + meteoro que cae y explota en área.
---------------------------------------------------------------------

local function poderMeteoro(jugador, datos, objetivo)
    local raiz, _, personaje = obtenerVivo(jugador)
    if not raiz then
        return false
    end

    local desfase = objetivo - raiz.Position
    if desfase.Magnitude > datos.AlcanceMax then
        objetivo = raiz.Position + desfase.Unit * datos.AlcanceMax
    end

    local resultado = workspace:Raycast(
        objetivo + Vector3.new(0, 50, 0),
        Vector3.new(0, -200, 0),
        paramsSinPersonaje(personaje)
    )

    local suelo = resultado and resultado.Position or objetivo
    local aviso = crearEfecto(
        "AvisoMeteoro",
        Enum.PartType.Cylinder,
        Vector3.new(0.2, datos.RadioArea * 2, datos.RadioArea * 2),
        CFrame.new(suelo + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
        datos.Color,
        0.6
    )

    task.delay(datos.RetrasoSeg, function()
        if aviso.Parent then
            aviso:Destroy()
        end

        -- Meteoro visual descendiendo.
        local meteoro = crearEfecto(
            "Meteoro",
            Enum.PartType.Ball,
            Vector3.one * 6,
            CFrame.new(suelo + Vector3.new(0, 60, 0)),
            datos.Color,
            0
        )

        -- Estela de fuego mientras cae.
        crearParticulas(meteoro, datos.Color, 120, 3, 10, 0.5)
        local luzMeteoro = Instance.new("PointLight")
        luzMeteoro.Color = datos.Color
        luzMeteoro.Range = 20
        luzMeteoro.Brightness = 4
        luzMeteoro.Parent = meteoro

        local t0 = os.clock()
        while meteoro.Parent and os.clock() - t0 < 0.4 do
            local progreso = (os.clock() - t0) / 0.4
            meteoro.Position = suelo + Vector3.new(0, 60 * (1 - progreso), 0)
            task.wait()
        end

        local golpeados = {}
        for _, parte in workspace:GetPartBoundsInRadius(suelo, datos.RadioArea) do
            local humanoide = humanoideDeParte(parte)
            if humanoide and not golpeados[humanoide] then
                golpeados[humanoide] = true
                aplicarDano(jugador, humanoide, datos.Dano)
            end
        end

        crearExplosion(suelo, datos.RadioArea, datos.Color)
        -- Segunda onda expansiva retardada para más impacto.
        task.delay(0.15, function()
            crearAnillo(suelo + Vector3.new(0, 0.6, 0), datos.RadioArea * 1.3, datos.Color, 0.6)
        end)
        if meteoro.Parent then
            meteoro:Destroy()
        end
    end)

    return true
end

---------------------------------------------------------------------
-- NOVA SOLAR (Mítico)
-- Explosión solar centrada en el propio jugador.
---------------------------------------------------------------------

local function poderNovaSolar(jugador, datos)
    local raiz = obtenerVivo(jugador)
    if not raiz then
        return false
    end

    local centro = raiz.Position

    -- Expansión visual de la nova.
    local nova = crearEfecto(
        "NovaSolar",
        Enum.PartType.Ball,
        Vector3.one * 4,
        CFrame.new(centro),
        datos.Color,
        0.4
    )

    local luz = Instance.new("PointLight")
    luz.Color = datos.Color
    luz.Range = 40
    luz.Brightness = 4
    luz.Parent = nova

    -- Destello + chispas + ondas expansivas concéntricas.
    crearExplosion(centro, datos.RadioArea, datos.Color)
    task.delay(0.18, function()
        crearAnillo(centro + Vector3.new(0, 1, 0), datos.RadioArea * 1.2, datos.Color, 0.6)
    end)
    task.delay(0.36, function()
        crearAnillo(centro + Vector3.new(0, 1, 0), datos.RadioArea * 1.4, datos.Color, 0.7)
    end)

    task.spawn(function()
        local t0 = os.clock()
        local duracion = 0.5
        while nova.Parent and os.clock() - t0 < duracion do
            local progreso = (os.clock() - t0) / duracion
            nova.Size = Vector3.one * (4 + datos.RadioArea * 2 * progreso)
            nova.CFrame = CFrame.new(centro)
            nova.Transparency = 0.4 + progreso * 0.6
            task.wait()
        end
        if nova.Parent then
            nova:Destroy()
        end
    end)

    local golpeados = {}
    for _, parte in workspace:GetPartBoundsInRadius(centro, datos.RadioArea) do
        local humanoide = humanoideDeParte(parte)
        if humanoide and not golpeados[humanoide] then
            golpeados[humanoide] = true
            -- aplicarDano ignora al propio atacante (self == atacante).
            aplicarDano(jugador, humanoide, datos.Dano)
        end
    end

    return true
end

local PODERES = {
    Fireball = poderFireball,
    Lightning = poderLightning,
    Teleport = poderTeleport,
    Meteoro = poderMeteoro,
    NovaSolar = poderNovaSolar,
}

---------------------------------------------------------------------
-- VALIDACIÓN DE LA PETICIÓN DEL CLIENTE
---------------------------------------------------------------------

local function vectorEsValido(vector)
    if typeof(vector) ~= "Vector3" then
        return false
    end

    return vector.X == vector.X
        and vector.Y == vector.Y
        and vector.Z == vector.Z
        and math.abs(vector.X) < 1e6
        and math.abs(vector.Y) < 1e6
        and math.abs(vector.Z) < 1e6
end

local function alUsarPoder(jugador, slot, objetivo)
    if typeof(slot) ~= "number" or slot % 1 ~= 0 then
        return
    end
    if slot < 1 or slot > PowerData.Config.MaxSlots then
        return
    end
    if not vectorEsValido(objetivo) then
        return
    end

    local raiz = obtenerVivo(jugador)
    if not raiz then
        return
    end

    -- No se pueden lanzar poderes desde Safe Zone.
    if ZoneSystem.GetPlayerZone(jugador) == "Safe" then
        notificar(jugador, "No puedes usar poderes en la zona segura")
        return
    end

    local idPoder = PowerInventory.ObtenerSlot(jugador, slot)
    local funcionPoder = idPoder and PODERES[idPoder]
    local datos = idPoder and PowerData.Powers[idPoder]

    if not funcionPoder or not datos then
        return
    end

    cooldowns[jugador] = cooldowns[jugador] or {}
    local ahora = os.clock()
    local listoEn = cooldowns[jugador][idPoder] or 0

    if listoEn > ahora then
        return
    end

    if funcionPoder(jugador, datos, objetivo) then
        cooldowns[jugador][idPoder] = ahora + datos.Cooldown
        -- Publica el fin del cooldown (os.time) para que la hotbar del
        -- cliente lo renderice (solo visual: la autoridad sigue aquí).
        jugador:SetAttribute("CD_" .. idPoder, os.time() + math.ceil(datos.Cooldown))
    end
end

function CombateServer.Init(carpetaRemotes)
    remotes = carpetaRemotes

    remotes.UsarPoder.OnServerEvent:Connect(alUsarPoder)

    Players.PlayerRemoving:Connect(function(jugador)
        cooldowns[jugador] = nil
    end)
end

return CombateServer
