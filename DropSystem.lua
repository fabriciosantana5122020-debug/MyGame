
--[[Por favor, ayuda a estructurar las partes y modelos dentro de Workspace
    DropSystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > DropSystem

    MVP:
      - Si un jugador muere dentro de Zona Roja, todos sus poderes actuales
        se convierten en esferas físicas.
      - Cada esfera dura 10 segundos (la expiración se PAUSA mientras
        alguien canaliza una extracción).
      - Otro jugador puede extraerla si tiene un slot libre y no posee ya
        ese poder.
      - Si muere fuera de Zona Roja, NO pierde poderes.

    FASE 0.1B - Sistema de Extracción por Rareza (PowerData.Rarities):
      - Comun (0s): instantáneo.
      - Raro (10s) / Epico (20s) / Legendario (30s): canalización con
        barra de progreso visual en el cliente.
      - Mitico (-1s, valor centinela): anuncio global a todo el servidor
        + canalización con duración de respaldo (CANAL_MITICO_SEG).

    REGLAS DE AUTORIDAD:
      - El temporizador se gestiona 100% en el servidor (task.spawn).
      - El cliente SOLO renderiza la barra (remote "Extraccion").
      - Cancelación inmediata si el jugador muere, recibe daño o se aleja
        de la esfera. La esfera vuelve a quedar disponible para todos.

    Todavía NO implementa bounty, seguros ni DataStore.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))
local ZoneSystem = require(script.Parent.ZoneSystem)
local PowerInventory = require(script.Parent.PowerInventory)

local DropSystem = {}
local remotes
local personajesProcesados = {} -- [Character] = true

-- Duración usada por rarezas con ExtraccionSeg negativo (centinela Mítico).
local CANAL_MITICO_SEG = 30
-- Frecuencia con la que el servidor valida vida/daño/distancia.
local INTERVALO_CANAL = 0.2
-- Margen extra sobre MaxActivationDistance antes de considerar que se alejó.
local MARGEN_DISTANCIA = 4

local function notificar(jugador, texto)
    if remotes and remotes:FindFirstChild("Notificacion") then
        remotes.Notificacion:FireClient(jugador, texto)
    end
end

-- Aviso global (Mítico) a todos los clientes conectados.
local function anunciarGlobal(jugador, datosPoder)
    local evento = remotes and remotes:FindFirstChild("AnuncioGlobal")
    if evento then
        evento:FireAllClients(jugador.DisplayName, datosPoder.Nombre)
    end
end

-- Estado de extracción hacia el cliente (solo visual, sin autoridad).
local function informarExtraccion(jugador, payload)
    local evento = remotes and remotes:FindFirstChild("Extraccion")
    if evento then
        evento:FireClient(jugador, payload)
    end
end

local function estaVivo(jugador)
    local personaje = jugador.Character
    local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")
    return humanoide ~= nil and humanoide.Health > 0
end

local function crearEsfera(idPoder, posicion, indice, total)
    local datos = PowerData.Powers[idPoder]
    if not datos then
        return
    end

    local rareza = PowerData.Rarities[datos.Rareza]
    if not rareza then
        return
    end

    local duracion = PowerData.Config.DuracionEsfera
    local desfase = Vector3.zero

    if total > 1 then
        local angulo = (indice / total) * math.pi * 2
        desfase = Vector3.new(math.cos(angulo), 0, math.sin(angulo)) * 3
    end

    local esfera = Instance.new("Part")
    esfera.Name = "EsferaDePoder"
    esfera.Shape = Enum.PartType.Ball
    esfera.Size = Vector3.one * 2.5
    esfera.Material = Enum.Material.Neon
    esfera.Color = rareza.Color
    esfera.Anchored = true
    esfera.CanCollide = false
    esfera.CanTouch = false
    esfera.CanQuery = true
    esfera.Position = posicion + desfase + Vector3.new(0, 2, 0)
    esfera:SetAttribute("PowerId", idPoder)
    esfera:SetAttribute("ExpiraEn", os.clock() + duracion)

    local luz = Instance.new("PointLight")
    luz.Color = rareza.Color
    luz.Range = 14
    luz.Brightness = 2
    luz.Parent = esfera

    local sparkles = Instance.new("Sparkles")
    sparkles.SparkleColor = rareza.Color
    sparkles.Parent = esfera

    local cartel = Instance.new("BillboardGui")
    cartel.Name = "Info"
    cartel.Size = UDim2.fromOffset(190, 45)
    cartel.StudsOffset = Vector3.new(0, 2.5, 0)
    cartel.AlwaysOnTop = true
    cartel.Parent = esfera

    local texto = Instance.new("TextLabel")
    texto.Size = UDim2.fromScale(1, 1)
    texto.BackgroundTransparency = 1
    texto.TextColor3 = rareza.Color
    texto.TextStrokeTransparency = 0.4
    texto.TextScaled = true
    texto.Font = Enum.Font.GothamBold
    texto.Parent = cartel

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Extraer poder"
    prompt.ObjectText = datos.Nombre .. " • " .. rareza.Nombre
    prompt.HoldDuration = 0.4
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    -- G en vez de E: E ya está ocupada por un poder (Lightning).
    prompt.KeyboardKeyCode = Enum.KeyCode.G
    prompt.Parent = esfera

    local estado = {
        reclamada = false,
        canalizando = false,
    }

    -- La esfera vuelve a estar disponible para todos (tras cancelar).
    local function liberarEsfera()
        estado.canalizando = false
        if esfera.Parent then
            prompt.Enabled = true
        end
    end

    local function concederPoder(jugador)
        estado.reclamada = true
        estado.canalizando = false

        informarExtraccion(jugador, { Estado = "Completado" })
        PowerInventory.Agregar(jugador, idPoder)
        notificar(jugador, "¡Extrajiste " .. datos.Nombre .. "!")

        if esfera.Parent then
            esfera:Destroy()
        end
    end

    local function cancelarExtraccion(jugador, motivo)
        liberarEsfera()
        informarExtraccion(jugador, { Estado = "Cancelado", Motivo = motivo })
        notificar(jugador, "Extracción cancelada: " .. motivo)
    end

    --
    -- Temporizador de canalización gestionado 100% en el SERVIDOR.
    -- Cancela si el jugador muere, recibe daño o se aleja de la esfera.
    --
    local function canalizar(jugador, segundos)
        local personaje = jugador.Character
        local humanoide = personaje and personaje:FindFirstChildOfClass("Humanoid")

        if not (personaje and humanoide) then
            cancelarExtraccion(jugador, "personaje inválido")
            return
        end

        local distanciaMax = prompt.MaxActivationDistance + MARGEN_DISTANCIA
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
            cancelarExtraccion(jugador, motivo)
        end

        -- El cliente solo recibe los datos para dibujar la barra.
        informarExtraccion(jugador, {
            Estado = "Iniciar",
            Poder = idPoder,
            Rareza = datos.Rareza,
            Segundos = segundos,
        })

        -- Regla: recibir daño cancela la extracción.
        -- (Regenerar vida sube la línea base para no enmascarar daño posterior.)
        conexiones[1] = humanoide.HealthChanged:Connect(function(nuevaSalud)
            if nuevaSalud < saludBase then
                cancelar("recibiste daño")
            elseif nuevaSalud > saludBase then
                saludBase = nuevaSalud
            end
        end)

        -- Regla: morir cancela la extracción.
        conexiones[2] = humanoide.Died:Connect(function()
            cancelar("moriste")
        end)

        task.spawn(function()
            local tiempoInicio = os.clock()

            while not cancelada do
                if not esfera.Parent then
                    cancelar("la esfera desapareció")
                    return
                end
                if not (jugador.Parent == Players and jugador.Character == personaje) then
                    cancelar("perdiste tu personaje")
                    return
                end

                -- Regla: alejarse de la esfera cancela la extracción.
                local raiz = personaje:FindFirstChild("HumanoidRootPart")
                if not raiz or (raiz.Position - esfera.Position).Magnitude > distanciaMax then
                    cancelar("te alejaste de la esfera")
                    return
                end

                if os.clock() - tiempoInicio >= segundos then
                    break
                end

                task.wait(INTERVALO_CANAL)
            end

            if cancelada then
                return
            end

            for _, conexion in conexiones do
                conexion:Disconnect()
            end

            -- Revalidación final antes de conceder (anti race conditions).
            if not estaVivo(jugador) or not esfera.Parent then
                cancelar("condiciones inválidas")
                return
            end

            local inventario = PowerInventory.GetSnapshot(jugador)
            if table.find(inventario, idPoder) or #inventario >= PowerData.Config.MaxSlots then
                cancelar("ya no puedes tomar ese poder")
                return
            end

            concederPoder(jugador)
        end)
    end

    prompt.Triggered:Connect(function(jugador)
        if estado.reclamada or estado.canalizando or not esfera.Parent then
            return
        end
        if not estaVivo(jugador) then
            return
        end

        -- Validación previa SIN mutar el inventario (se muta solo al completar).
        local inventario = PowerInventory.GetSnapshot(jugador)
        if table.find(inventario, idPoder) then
            notificar(jugador, "Ya tienes ese poder")
            return
        end
        if #inventario >= PowerData.Config.MaxSlots then
            notificar(jugador, "Slots llenos")
            return
        end

        local segundos = rareza.ExtraccionSeg

        -- Mítico: valor centinela negativo → aviso global + canal respaldo.
        if segundos < 0 then
            anunciarGlobal(jugador, datos)
            segundos = CANAL_MITICO_SEG
        end

        -- Común: extracción instantánea, sin barra.
        if segundos <= 0 then
            concederPoder(jugador)
            return
        end

        -- La esfera queda reservada mientras alguien canaliza.
        estado.canalizando = true
        prompt.Enabled = false
        canalizar(jugador, segundos)
    end)

    esfera.Parent = workspace

    -- Expiración: se PAUSA mientras alguien canaliza la esfera.
    task.spawn(function()
        local restante = duracion

        while restante > 0 do
            if not esfera.Parent or estado.reclamada then
                return
            end

            if estado.canalizando then
                task.wait(0.5)
            else
                texto.Text = string.format("%s (%ds)", datos.Nombre, restante)
                task.wait(1)
                restante -= 1
            end
        end

        if esfera.Parent and not estado.reclamada and not estado.canalizando then
            esfera:Destroy()
        end
    end)
end

local function alMorir(jugador, personaje, humanoide)
    if personajesProcesados[personaje] then
        return
    end
    personajesProcesados[personaje] = true

    local raiz = personaje:FindFirstChild("HumanoidRootPart")
    local posicion = raiz and raiz.Position or personaje:GetPivot().Position

    -- La zona se determina con la posición real del personaje al morir.
    if ZoneSystem.GetZoneAt(posicion) ~= "Red" then
        return
    end

    local perdidos = PowerInventory.Vaciar(jugador)

    for i, idPoder in perdidos do
        crearEsfera(idPoder, posicion, i, #perdidos)
    end

    local tag = humanoide:FindFirstChild("creator")
    local asesino = tag and tag.Value

    if asesino and asesino:IsA("Player") and asesino ~= jugador and asesino.Parent == Players then
        if #perdidos > 0 then
            notificar(
                asesino,
                string.format(
                    "¡Eliminaste a %s! Sus poderes cayeron en esferas.",
                    jugador.DisplayName
                )
            )
        end
    end
end

local function conectarPersonaje(jugador, personaje)
    personajesProcesados[personaje] = nil

    local humanoide = personaje:WaitForChild("Humanoid", 10)
    if not humanoide then
        return
    end

    humanoide.Died:Connect(function()
        alMorir(jugador, personaje, humanoide)
    end)
end

local function conectarJugador(jugador)
    jugador.CharacterAdded:Connect(function(personaje)
        conectarPersonaje(jugador, personaje)
    end)

    if jugador.Character then
        task.spawn(conectarPersonaje, jugador, jugador.Character)
    end
end

function DropSystem.Init(carpetaRemotes)
    remotes = carpetaRemotes

    Players.PlayerAdded:Connect(conectarJugador)

    Players.PlayerRemoving:Connect(function(jugador)
        if jugador.Character then
            personajesProcesados[jugador.Character] = nil
        end
    end)

    for _, jugador in Players:GetPlayers() do
        conectarJugador(jugador)
    end
end

return DropSystem