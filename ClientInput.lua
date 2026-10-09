--[[
    ClientInput (LocalScript)
    Ubicación: StarterPlayer > StarterPlayerScripts > ClientInput

    El cliente solo:
      - lee input
      - muestra HUD
      - solicita usar un poder
      - renderiza la barra de progreso de extracción (SOLO VISUAL:
        el temporizador y las cancelaciones las decide el servidor)
      - muestra el aviso global cuando alguien extrae un poder Mítico
      - muestra el saldo de Monedas y el resultado de abrir un huevo

    El cliente NO decide daño, cooldown, inventario ni zona.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local jugador = Players.LocalPlayer
local mouse = jugador:GetMouse()

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UsarPoder = Remotes:WaitForChild("UsarPoder")
local Notificacion = Remotes:WaitForChild("Notificacion")
local Extraccion = Remotes:WaitForChild("Extraccion")
local AnuncioGlobal = Remotes:WaitForChild("AnuncioGlobal")
local AbrirHuevo = Remotes:WaitForChild("AbrirHuevo")
local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))

local TECLAS = {
    Enum.KeyCode.Q,
    Enum.KeyCode.E,
    Enum.KeyCode.R,
    Enum.KeyCode.F,
    Enum.KeyCode.V,
}

local COLORES_ZONA = {
    Safe = Color3.fromRGB(80, 220, 100),
    Red = Color3.fromRGB(255, 70, 70),
    Neutral = Color3.fromRGB(220, 220, 220),
}

local NOMBRES_ZONA = {
    Safe = "ZONA SEGURA",
    Red = "ZONA ROJA",
    Neutral = "ZONA NEUTRAL",
}

local pantalla = Instance.new("ScreenGui")
pantalla.Name = "HUD"
pantalla.ResetOnSpawn = false
pantalla.IgnoreGuiInset = false
pantalla.Parent = jugador:WaitForChild("PlayerGui")

local function crearEtiqueta(posicion, tamano)
    local e = Instance.new("TextLabel")
    e.Position = posicion
    e.Size = tamano
    e.BackgroundColor3 = Color3.new(0, 0, 0)
    e.BackgroundTransparency = 0.45
    e.TextColor3 = Color3.new(1, 1, 1)
    e.Font = Enum.Font.GothamBold
    e.TextScaled = true
    e.TextWrapped = true
    e.Parent = pantalla
    return e
end

local etiquetaZona = crearEtiqueta(
    UDim2.new(0.5, -110, 0, 10),
    UDim2.fromOffset(220, 32)
)

local etiquetaAviso = crearEtiqueta(
    UDim2.new(0.5, -200, 0, 50),
    UDim2.fromOffset(400, 36)
)
etiquetaAviso.Visible = false

-- Saldo de Monedas (publicado por el servidor como attribute).
local etiquetaMonedas = crearEtiqueta(
    UDim2.new(0, 10, 0, 10),
    UDim2.fromOffset(170, 32)
)
etiquetaMonedas.TextColor3 = Color3.fromRGB(255, 210, 60)

--
-- HOTBAR GRÁFICA (FASE 0.1E)
-- Slots clicables: tecla (Q/E/R/F/V o 1..5), nombre, color de rareza
-- y overlay de cooldown. El daño y el cooldown real los decide el servidor.
--
local etiquetasSlots = {}
local maxSlots = math.min(PowerData.Config.MaxSlots, #TECLAS)

local contenedorHotbar = Instance.new("Frame")
contenedorHotbar.Name = "Hotbar"
contenedorHotbar.AnchorPoint = Vector2.new(0.5, 1)
contenedorHotbar.Position = UDim2.new(0.5, 0, 1, -18)
contenedorHotbar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
contenedorHotbar.BackgroundTransparency = 0.35
contenedorHotbar.BorderSizePixel = 0
contenedorHotbar.AutomaticSize = Enum.AutomaticSize.X
contenedorHotbar.Parent = pantalla

local esquinaHotbar = Instance.new("UICorner")
esquinaHotbar.CornerRadius = UDim.new(0, 10)
esquinaHotbar.Parent = contenedorHotbar

local paddingHotbar = Instance.new("UIPadding")
paddingHotbar.PaddingLeft = UDim.new(0, 8)
paddingHotbar.PaddingRight = UDim.new(0, 8)
paddingHotbar.PaddingTop = UDim.new(0, 8)
paddingHotbar.PaddingBottom = UDim.new(0, 8)
paddingHotbar.Parent = contenedorHotbar

local layoutHotbar = Instance.new("UIListLayout")
layoutHotbar.FillDirection = Enum.FillDirection.Horizontal
layoutHotbar.Padding = UDim.new(0, 8)
layoutHotbar.VerticalAlignment = Enum.VerticalAlignment.Center
layoutHotbar.SortOrder = Enum.SortOrder.LayoutOrder
layoutHotbar.Parent = contenedorHotbar

for i = 1, maxSlots do
    local boton = Instance.new("TextButton")
    boton.Name = "Slot" .. i
    boton.LayoutOrder = i
    boton.Size = UDim2.fromOffset(110, 110)
    boton.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    boton.BackgroundTransparency = 0.15
    boton.Text = ""
    boton.Parent = contenedorHotbar

    local esquinaSlot = Instance.new("UICorner")
    esquinaSlot.CornerRadius = UDim.new(0, 10)
    esquinaSlot.Parent = boton

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 3
    stroke.Color = Color3.fromRGB(90, 90, 90)
    stroke.Parent = boton

    local etiquetaTecla = Instance.new("TextLabel")
    etiquetaTecla.Name = "Tecla"
    etiquetaTecla.Position = UDim2.new(0, 6, 0, 5)
    etiquetaTecla.Size = UDim2.fromOffset(28, 22)
    etiquetaTecla.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    etiquetaTecla.BackgroundTransparency = 0.2
    etiquetaTecla.TextColor3 = Color3.new(1, 1, 1)
    etiquetaTecla.Font = Enum.Font.GothamBold
    etiquetaTecla.TextScaled = true
    etiquetaTecla.Text = TECLAS[i].Name
    etiquetaTecla.Parent = boton

    local esquinaTecla = Instance.new("UICorner")
    esquinaTecla.CornerRadius = UDim.new(0, 6)
    esquinaTecla.Parent = etiquetaTecla

    local nombre = Instance.new("TextLabel")
    nombre.Name = "Poder"
    nombre.AnchorPoint = Vector2.new(0.5, 1)
    nombre.Position = UDim2.new(0.5, 0, 1, -8)
    nombre.Size = UDim2.new(1, -12, 0, 34)
    nombre.BackgroundTransparency = 1
    nombre.TextColor3 = Color3.fromRGB(170, 170, 170)
    nombre.Font = Enum.Font.GothamBold
    nombre.TextScaled = true
    nombre.TextWrapped = true
    nombre.Text = "—"
    nombre.Parent = boton

    local overlay = Instance.new("Frame")
    overlay.Name = "Cooldown"
    overlay.AnchorPoint = Vector2.new(0, 1)
    overlay.Position = UDim2.fromScale(0, 1)
    overlay.Size = UDim2.fromScale(1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.35
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 2
    overlay.Parent = boton

    local esquinaOverlay = Instance.new("UICorner")
    esquinaOverlay.CornerRadius = UDim.new(0, 10)
    esquinaOverlay.Parent = overlay

    local cuenta = Instance.new("TextLabel")
    cuenta.Name = "Cuenta"
    cuenta.AnchorPoint = Vector2.new(0.5, 0.5)
    cuenta.Position = UDim2.fromScale(0.5, 0.35)
    cuenta.Size = UDim2.fromOffset(64, 48)
    cuenta.BackgroundTransparency = 1
    cuenta.TextColor3 = Color3.fromRGB(255, 230, 120)
    cuenta.Font = Enum.Font.GothamBold
    cuenta.TextScaled = true
    cuenta.Text = ""
    cuenta.ZIndex = 3
    cuenta.Parent = boton

    etiquetasSlots[i] = {
        Boton = boton,
        Nombre = nombre,
        Overlay = overlay,
        Cuenta = cuenta,
        Stroke = stroke,
    }
end

-- Cooldown visual por poder: el servidor publica el attribute "CD_<Poder>"
-- (os.time del fin) cuando un lanzamiento tiene éxito.
local cooldowns = {} -- [idPoder] = {inicio = os.clock(), duracion = seg}

local function iniciarCooldownVisual(idPoder, restante)
    cooldowns[idPoder] = {
        inicio = os.clock(),
        duracion = math.max(restante, 0.05),
    }
end

for idPoder in PowerData.Powers do
    jugador:GetAttributeChangedSignal("CD_" .. idPoder):Connect(function()
        local fin = jugador:GetAttribute("CD_" .. idPoder)
        if typeof(fin) == "number" then
            iniciarCooldownVisual(idPoder, fin - os.time())
        end
    end)
end

--
-- Barra de progreso de extracción (render 100% visual).
-- El servidor envía "Iniciar" con la duración autoritativa y
-- "Cancelado" / "Completado" para ocultarla.
--
local contenedorBarra = Instance.new("Frame")
contenedorBarra.Name = "BarraExtraccion"
contenedorBarra.AnchorPoint = Vector2.new(0.5, 1)
contenedorBarra.Position = UDim2.new(0.5, 0, 1, -120)
contenedorBarra.Size = UDim2.fromOffset(380, 58)
contenedorBarra.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
contenedorBarra.BackgroundTransparency = 0.2
contenedorBarra.BorderSizePixel = 0
contenedorBarra.Visible = false
contenedorBarra.Parent = pantalla

local esquinaBarra = Instance.new("UICorner")
esquinaBarra.CornerRadius = UDim.new(0, 8)
esquinaBarra.Parent = contenedorBarra

local tituloBarra = Instance.new("TextLabel")
tituloBarra.Name = "Titulo"
tituloBarra.Size = UDim2.fromScale(1, 0.5)
tituloBarra.BackgroundTransparency = 1
tituloBarra.TextColor3 = Color3.new(1, 1, 1)
tituloBarra.Font = Enum.Font.GothamBold
tituloBarra.TextScaled = true
tituloBarra.Text = ""
tituloBarra.Parent = contenedorBarra

local fondoProgreso = Instance.new("Frame")
fondoProgreso.Name = "Fondo"
fondoProgreso.AnchorPoint = Vector2.new(0.5, 1)
fondoProgreso.Position = UDim2.new(0.5, 0, 1, -5)
fondoProgreso.Size = UDim2.new(1, -20, 0, 14)
fondoProgreso.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
fondoProgreso.BorderSizePixel = 0
fondoProgreso.Parent = contenedorBarra

local esquinaFondo = Instance.new("UICorner")
esquinaFondo.CornerRadius = UDim.new(1, 0)
esquinaFondo.Parent = fondoProgreso

local rellenoProgreso = Instance.new("Frame")
rellenoProgreso.Name = "Relleno"
rellenoProgreso.Size = UDim2.fromScale(0, 1)
rellenoProgreso.BackgroundColor3 = Color3.fromRGB(70, 140, 255)
rellenoProgreso.BorderSizePixel = 0
rellenoProgreso.Parent = fondoProgreso

local esquinaRelleno = Instance.new("UICorner")
esquinaRelleno.CornerRadius = UDim.new(1, 0)
esquinaRelleno.Parent = rellenoProgreso

local extraccion = {
    activa = false,
    inicio = 0,
    segundos = 1,
    nombre = "",
    etiqueta = nil, -- Texto base alternativo (ej: "Evacuando").
}

RunService.RenderStepped:Connect(function()
    if not extraccion.activa then
        return
    end

    local transcurrido = math.clamp(os.clock() - extraccion.inicio, 0, extraccion.segundos)
    local restante = math.ceil(extraccion.segundos - transcurrido)

    rellenoProgreso.Size = UDim2.fromScale(transcurrido / extraccion.segundos, 1)

    -- "Extrayendo X..." para esferas; etiqueta personalizada para evacuación.
    local base = extraccion.etiqueta or ("Extrayendo " .. extraccion.nombre)
    tituloBarra.Text = string.format("%s... %ds", base, restante)
end)

Extraccion.OnClientEvent:Connect(function(datos)
    if typeof(datos) ~= "table" or typeof(datos.Estado) ~= "string" then
        return
    end

    if datos.Estado == "Iniciar" then
        local datosPoder = PowerData.Powers[datos.Poder]
        local rareza = datosPoder and PowerData.Rarities[datosPoder.Rareza]

        extraccion.activa = true
        extraccion.inicio = os.clock()
        -- Nunca 0: evita división por cero en el render.
        extraccion.segundos = math.max(datos.Segundos or 0, 0.05)
        extraccion.nombre = datosPoder and datosPoder.Nombre or "poder"
        -- Etiqueta opcional del servidor (evacuación reutiliza esta barra).
        if typeof(datos.Etiqueta) == "string" and datos.Etiqueta ~= "" then
            extraccion.etiqueta = datos.Etiqueta
        else
            extraccion.etiqueta = nil
        end

        rellenoProgreso.Size = UDim2.fromScale(0, 1)
        -- Color explícito del servidor, o el de la rareza del poder.
        if typeof(datos.Color) == "Color3" then
            rellenoProgreso.BackgroundColor3 = datos.Color
        else
            rellenoProgreso.BackgroundColor3 = rareza and rareza.Color or Color3.new(1, 1, 1)
        end
        contenedorBarra.Visible = true
    elseif datos.Estado == "Cancelado" or datos.Estado == "Completado" then
        extraccion.activa = false
        contenedorBarra.Visible = false
    end
end)

--
-- Aviso global: un jugador está extrayendo un poder Mítico.
--
local etiquetaMito = crearEtiqueta(
    UDim2.new(0.5, -300, 0, 100),
    UDim2.fromOffset(600, 44)
)
etiquetaMito.Visible = false
etiquetaMito.TextColor3 = Color3.fromRGB(255, 60, 60)

local contadorMito = 0
AnuncioGlobal.OnClientEvent:Connect(function(nombreJugador, nombrePoder)
    contadorMito += 1
    local numero = contadorMito

    etiquetaMito.Text = string.format(
        "[MÍTICO] %s está extrayendo el poder %s",
        tostring(nombreJugador),
        tostring(nombrePoder)
    )
    etiquetaMito.Visible = true

    task.delay(5, function()
        if numero == contadorMito then
            etiquetaMito.Visible = false
        end
    end)
end)

--
-- Resultado de abrir un huevo (animación 100% visual; el servidor
-- ya validó la compra, el roll y el inventario).
--
local marcoHuevo = Instance.new("Frame")
marcoHuevo.Name = "ResultadoHuevo"
marcoHuevo.AnchorPoint = Vector2.new(0.5, 0.5)
marcoHuevo.Position = UDim2.fromScale(0.5, 0.4)
marcoHuevo.Size = UDim2.fromOffset(0, 0)
marcoHuevo.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
marcoHuevo.BackgroundTransparency = 0.1
marcoHuevo.BorderSizePixel = 0
marcoHuevo.Visible = false
marcoHuevo.Parent = pantalla

local esquinaHuevo = Instance.new("UICorner")
esquinaHuevo.CornerRadius = UDim.new(0, 12)
esquinaHuevo.Parent = marcoHuevo

local tituloHuevo = Instance.new("TextLabel")
tituloHuevo.Name = "Titulo"
tituloHuevo.AnchorPoint = Vector2.new(0.5, 0)
tituloHuevo.Position = UDim2.new(0.5, 0, 0, 10)
tituloHuevo.Size = UDim2.new(1, -30, 0, 28)
tituloHuevo.BackgroundTransparency = 1
tituloHuevo.TextColor3 = Color3.fromRGB(200, 200, 200)
tituloHuevo.Font = Enum.Font.GothamBold
tituloHuevo.TextScaled = true
tituloHuevo.Text = ""
tituloHuevo.Parent = marcoHuevo

local nnombreHuevo = Instance.new("TextLabel")
nnombreHuevo.Name = "Poder"
nnombreHuevo.AnchorPoint = Vector2.new(0.5, 0)
nnombreHuevo.Position = UDim2.new(0.5, 0, 0, 44)
nnombreHuevo.Size = UDim2.new(1, -30, 0, 46)
nnombreHuevo.BackgroundTransparency = 1
nnombreHuevo.TextColor3 = Color3.new(1, 1, 1)
nnombreHuevo.Font = Enum.Font.GothamBold
    nnombreHuevo.TextScaled = true
nnombreHuevo.Text = ""
nnombreHuevo.Parent = marcoHuevo

local rarezaHuevo = Instance.new("TextLabel")
rarezaHuevo.Name = "Rareza"
rarezaHuevo.AnchorPoint = Vector2.new(0.5, 1)
rarezaHuevo.Position = UDim2.new(0.5, 0, 1, -12)
rarezaHuevo.Size = UDim2.new(1, -30, 0, 26)
rarezaHuevo.BackgroundTransparency = 1
rarezaHuevo.TextColor3 = Color3.new(1, 1, 1)
rarezaHuevo.Font = Enum.Font.GothamBold
rarezaHuevo.TextScaled = true
rarezaHuevo.Text = ""
rarezaHuevo.Parent = marcoHuevo

local tweenHuevo = TweenService:Create(
    marcoHuevo,
    TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    { Size = UDim2.fromOffset(400, 150) }
)

local contadorHuevo = 0
AbrirHuevo.OnClientEvent:Connect(function(datos)
    if typeof(datos) ~= "table" then
        return
    end

    local datosPoder = PowerData.Powers[datos.Poder]
    local rareza = PowerData.Rarities[datos.Rareza]
    local color = rareza and rareza.Color or Color3.new(1, 1, 1)

    contadorHuevo += 1
    local numero = contadorHuevo

    tituloHuevo.Text = string.format("¡%s abierto!", tostring(datos.Huevo or "Huevo"))
    nnombreHuevo.Text = datosPoder and datosPoder.Nombre or tostring(datos.Poder)
    nnombreHuevo.TextColor3 = color
    rarezaHuevo.Text = rareza and rareza.Nombre or ""
    rarezaHuevo.TextColor3 = color

    -- Pop-in: reinicia el tamaño y vuelve a crecer (permite reactivar la
    -- animación si se abren varios huevos seguidos).
    marcoHuevo.Size = UDim2.fromOffset(0, 0)
    marcoHuevo.Visible = true
    tweenHuevo:Play()

    task.delay(3.5, function()
        if numero == contadorHuevo then
            marcoHuevo.Visible = false
        end
    end)
end)

local function obtenerListaPoderes()
    local atributo = jugador:GetAttribute("Poderes") or ""
    if atributo == "" then
        return {}
    end
    return string.split(atributo, ",")
end

local function refrescarZona()
    local zona = jugador:GetAttribute("Zona") or "Neutral"
    etiquetaZona.Text = NOMBRES_ZONA[zona] or zona
    etiquetaZona.TextColor3 = COLORES_ZONA[zona] or COLORES_ZONA.Neutral
end

local function refrescarSlots()
    local lista = obtenerListaPoderes()

    for i, slot in etiquetasSlots do
        local idPoder = lista[i]
        local datos = idPoder and PowerData.Powers[idPoder]
        local rareza = datos and PowerData.Rarities[datos.Rareza]

        slot.Nombre.Text = datos and datos.Nombre or "—"
        slot.Nombre.TextColor3 = rareza and rareza.Color or Color3.fromRGB(170, 170, 170)
        slot.Stroke.Color = rareza and rareza.Color or Color3.fromRGB(90, 90, 90)
    end
end

-- Render del cooldown de la hotbar (100% visual: el servidor es la
-- autoridad y solo publica "CD_<Poder>" tras un lanzamiento válido).
RunService.RenderStepped:Connect(function()
    local lista = obtenerListaPoderes()

    for i, slot in etiquetasSlots do
        local idPoder = lista[i]
        local estado = idPoder and cooldowns[idPoder]

        if estado then
            local restante = estado.duracion - (os.clock() - estado.inicio)

            if restante <= 0 then
                cooldowns[idPoder] = nil
                slot.Overlay.Size = UDim2.fromScale(1, 0)
                slot.Cuenta.Text = ""
            else
                slot.Overlay.Size = UDim2.fromScale(1, restante / estado.duracion)
                slot.Cuenta.Text = string.format("%.1f", restante)
            end
        else
            slot.Overlay.Size = UDim2.fromScale(1, 0)
            slot.Cuenta.Text = ""
        end
    end
end)

local function refrescarMonedas()
    etiquetaMonedas.Text = "Monedas: " .. tostring(jugador:GetAttribute("Monedas") or 0)
end

jugador:GetAttributeChangedSignal("Zona"):Connect(refrescarZona)
jugador:GetAttributeChangedSignal("Poderes"):Connect(refrescarSlots)
jugador:GetAttributeChangedSignal("Monedas"):Connect(refrescarMonedas)

refrescarZona()
refrescarSlots()
refrescarMonedas()

local contadorAviso = 0
Notificacion.OnClientEvent:Connect(function(texto)
    contadorAviso += 1
    local numero = contadorAviso

    etiquetaAviso.Text = tostring(texto)
    etiquetaAviso.Visible = true

    task.delay(3, function()
        if numero == contadorAviso then
            etiquetaAviso.Visible = false
        end
    end)
end)

local NUMEROS = {
    Enum.KeyCode.One,
    Enum.KeyCode.Two,
    Enum.KeyCode.Three,
    Enum.KeyCode.Four,
    Enum.KeyCode.Five,
}

-- Lanza un slot (tecla o clic). El servidor vuelve a validar todo.
local function usarSlot(slot)
    local lista = obtenerListaPoderes()
    if not lista[slot] then
        return
    end

    local hit = mouse.Hit
    if hit then
        UsarPoder:FireServer(slot, hit.Position)
    end
end

-- Clic en los slots de la hotbar.
for i, slot in etiquetasSlots do
    slot.Boton.Activated:Connect(function()
        usarSlot(i)
    end)
end

UserInputService.InputBegan:Connect(function(input, procesadoPorUI)
    if procesadoPorUI then
        return
    end

    for slot, tecla in TECLAS do
        if input.KeyCode == tecla then
            usarSlot(slot)
            return
        end
    end

    -- Teclas numéricas 1..5 como alternativa a Q/E/R/F/V.
    for slot, tecla in NUMEROS do
        if input.KeyCode == tecla then
            usarSlot(slot)
            return
        end
    end
end)
