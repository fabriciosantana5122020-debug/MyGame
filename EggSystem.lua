--[[
    EggSystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > EggSystem

    FASE 0.1D - Huevos en Safe Zone:
      - Los tipos de huevo (Precio, Color, Probabilidades por rareza)
        están definidos en PowerData.Eggs.
      - Construye los huevos físicos en el lateral oeste de la Safe Zone.
      - Compra 100% autoritativa en servidor, en este orden:
          1. Zona: solo se pueden abrir en Safe Zone.
          2. Slot libre en PowerInventory (se valida ANTES de cobrar).
          3. Monedas suficientes en EconomySystem.
          4. Cobra las monedas.
          5. Roll de rareza con math.random(1, 100) sobre los pesos.
          6. Elige un poder aleatorio de esa rareza y lo agrega.
          7. Remote "AbrirHuevo" al cliente para la animación.
        Si algo falla después de cobrar, se reembolsa y no se pierde nada.

    No modifica PowerData, ZoneSystem, PowerInventory ni DropSystem.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))
local ZoneSystem = require(script.Parent.ZoneSystem)
local PowerInventory = require(script.Parent.PowerInventory)
local EconomySystem = require(script.Parent.EconomySystem)

local EggSystem = {}
local remotes

local function notificar(jugador, texto)
    local evento = remotes and remotes:FindFirstChild("Notificacion")
    if evento then
        evento:FireClient(jugador, texto)
    end
end

-- Animación/efecto visual de recompensa (solo cliente).
local function anunciarHuevo(jugador, payload)
    local evento = remotes and remotes:FindFirstChild("AbrirHuevo")
    if evento then
        evento:FireClient(jugador, payload)
    end
end

-- Roll de rareza: pesos de PowerData.Eggs que suman 100,
-- usando math.random(1, 100) escalado al total real de pesos.
local function elegirRareza(probabilidades)
    local total = 0
    for _, peso in probabilidades do
        total += peso
    end

    local roll = math.random(1, 100) * (total / 100)
    local acumulado = 0

    for rareza, peso in probabilidades do
        acumulado += peso
        if roll <= acumulado then
            return rareza
        end
    end

    return nil
end

local function poderesDeRareza(rareza)
    local lista = {}
    for idPoder, datos in PowerData.Powers do
        if datos.Rareza == rareza then
            table.insert(lista, idPoder)
        end
    end
    return lista
end

---------------------------------------------------------------------
-- CONSTRUCCIÓN VISUAL DE LOS HUEVOS (junto al SafeSpawn)
---------------------------------------------------------------------

local function construirHuevo(idHuevo, datos, posicion)
    local carpeta = workspace:FindFirstChild("Huevos")
    if not carpeta then
        carpeta = Instance.new("Folder")
        carpeta.Name = "Huevos"
        carpeta.Parent = workspace
    end

    local pedestal = Instance.new("Part")
    pedestal.Name = "Pedestal" .. idHuevo
    pedestal.Shape = Enum.PartType.Cylinder
    pedestal.Size = Vector3.new(0.4, 4.5, 4.5)
    pedestal.CFrame = CFrame.new(posicion + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
    pedestal.Color = Color3.fromRGB(50, 50, 55)
    pedestal.Material = Enum.Material.SmoothPlastic
    pedestal.Anchored = true
    pedestal.CanCollide = false
    pedestal.CanTouch = false
    pedestal.CanQuery = false
    pedestal.Parent = carpeta

    -- Huevo (esfera escalada no-uniforme = forma de huevo).
    local huevo = Instance.new("Part")
    huevo.Name = idHuevo
    huevo.Size = Vector3.new(2.4, 3.4, 2.4)
    huevo.CFrame = CFrame.new(posicion + Vector3.new(0, 2.7, 0))
    huevo.Color = datos.Color
    huevo.Material = Enum.Material.SmoothPlastic
    huevo.Anchored = true
    huevo.CanCollide = false
    huevo.CanTouch = false
    huevo.CanQuery = false

    local malla = Instance.new("SpecialMesh")
    malla.MeshType = Enum.MeshType.Sphere
    malla.Parent = huevo

    local luz = Instance.new("PointLight")
    luz.Color = datos.Color
    luz.Range = 10
    luz.Brightness = 1.5
    luz.Parent = huevo

    local cartel = Instance.new("BillboardGui")
    cartel.Name = "Info"
    cartel.Size = UDim2.fromOffset(190, 45)
    cartel.StudsOffset = Vector3.new(0, 2.5, 0)
    cartel.AlwaysOnTop = true
    cartel.Parent = huevo

    local texto = Instance.new("TextLabel")
    texto.Size = UDim2.fromScale(1, 1)
    texto.BackgroundTransparency = 1
    texto.TextColor3 = datos.Color
    texto.TextStrokeTransparency = 0.4
    texto.TextScaled = true
    texto.Font = Enum.Font.GothamBold
    texto.Text = string.format("%s • %d M", datos.Nombre, datos.Precio)
    texto.Parent = cartel

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Abrir huevo"
    prompt.ObjectText = datos.Nombre
    prompt.HoldDuration = 0.4
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    -- H: G son las esferas, T la evacuación.
    prompt.KeyboardKeyCode = Enum.KeyCode.H
    prompt.Parent = huevo

    prompt.Triggered:Connect(function(jugador)
        EggSystem.Abrir(jugador, idHuevo)
    end)

    huevo.Parent = carpeta
end

local function construirHuevos()
    if workspace:FindFirstChild("Huevos") then
        return -- Ya construidos (no pisar un mapa manual).
    end

    -- Punto de referencia: el SafeSpawn (o el centro de la Safe Zone).
    local zonas = workspace:FindFirstChild("Zones")
    local segura = zonas and zonas:FindFirstChild("SafeZone")
    local spawn = workspace:FindFirstChild("SafeSpawn")
    local referencia = (spawn and spawn.Position) or (segura and segura.Position) or Vector3.zero

    -- FASE 0.1E: huevos en el lateral OESTE de la Safe Zone, lejos del
    -- SafeSpawn y del portal (que está en el borde orientado a la Red Zone).
    referencia = referencia + Vector3.new(-30, 0, 0)

    local separacion = 10

    -- # sobre un diccionario devuelve 0: contar manualmente.
    local total = 0
    for _ in PowerData.Eggs do
        total += 1
    end

    local i = 0
    for idHuevo, datos in PowerData.Eggs do
        i += 1

        local posicion = referencia + Vector3.new(0, 0, (i - (total + 1) / 2) * separacion)

        -- Buscar el suelo real bajo ese punto.
        local resultado = workspace:Raycast(
            Vector3.new(posicion.X, posicion.Y + 60, posicion.Z),
            Vector3.new(0, -300, 0)
        )
        local sueloY = resultado and resultado.Position.Y or referencia.Y

        construirHuevo(idHuevo, datos, Vector3.new(posicion.X, sueloY, posicion.Z))
    end
end

---------------------------------------------------------------------
-- COMPRA AUTORITATIVA
---------------------------------------------------------------------

function EggSystem.Abrir(jugador, idHuevo)
    if not (typeof(jugador) == "Instance" and jugador:IsA("Player") and jugador.Parent == Players) then
        return
    end

    local datos = PowerData.Eggs[idHuevo]
    if not datos then
        return
    end

    -- 1. Los huevos solo se abren en Safe Zone.
    if ZoneSystem.GetPlayerZone(jugador) ~= "Safe" then
        notificar(jugador, "Los huevos solo se abren en la zona segura")
        return
    end

    -- 2. Slot libre ANTES de cobrar (sin coste si está lleno).
    local inventario = PowerInventory.GetSnapshot(jugador)
    if #inventario >= PowerData.Config.MaxSlots then
        notificar(jugador, "Slots llenos: libera espacio antes de abrir un huevo")
        return
    end

    -- 3. Monedas suficientes ANTES de cobrar.
    local saldo = EconomySystem.Obtener(jugador)
    if saldo < datos.Precio then
        notificar(jugador, string.format("Monedas insuficientes (%d/%d)", saldo, datos.Precio))
        return
    end

    -- 4. Roll de rareza y poder.
    local rareza = elegirRareza(datos.Probabilidades)
    local candidatos = rareza and poderesDeRareza(rareza)

    if not candidatos or #candidatos == 0 then
        notificar(jugador, "No hay poderes de esa rareza disponibles")
        return
    end

    -- 5. Cobrar (atómico: falla solo si algo cambió entre la validación
    --    y aquí, en cuyo caso no se cobra).
    if not EconomySystem.Cobrar(jugador, datos.Precio) then
        notificar(jugador, "Monedas insuficientes")
        return
    end

    -- 6. Poder aleatorio de la rareza ganada.
    local idPoder = candidatos[math.random(1, #candidatos)]

    local ok, motivo = PowerInventory.Agregar(jugador, idPoder)
    if not ok then
        -- 7. Reembolso íntegro: el jugador no pierde nada.
        EconomySystem.Agregar(jugador, datos.Precio)
        notificar(jugador, motivo)
        return
    end

    -- 8. Animación de recompensa en el cliente.
    anunciarHuevo(jugador, {
        Huevo = datos.Nombre,
        Poder = idPoder,
        Rareza = rareza,
    })
end

function EggSystem.Init(carpetaRemotes)
    remotes = carpetaRemotes

    construirHuevos()

    local cantidad = 0
    for _ in PowerData.Eggs do
        cantidad += 1
    end
    print("[EggSystem] Huevos construidos en la Safe Zone (" .. cantidad .. " tipos).")
end

return EggSystem