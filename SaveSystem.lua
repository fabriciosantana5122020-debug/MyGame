--[[
    SaveSystem (ModuleScript)
    Ubicación: ServerScriptService > Modulos > SaveSystem

    FASE 0.2 - Persistencia de Datos (100% SERVIDOR):
      - Carga el perfil del jugador al entrar (PlayerAdded).
      - Guarda al salir (PlayerRemoving) y al cerrar el servidor (BindToClose).
      - Auto-Save cada 5 minutos para prevenir pérdida por crashes.
      - pcall + reintentos en cada lectura/escritura de DataStore.

    ANTI-DATA-LOSS:
      - Si la carga inicial falla, la sesión se marca como "CargaFallida"
        y NUNCA se sobrescribe el perfil guardado (ni auto-save ni quit-save).
      - El jugador recibe una notificación del error de carga.

    PERFIL GUARDADO (clave: "Player_<UserId>"):
      {
        Monedas = number,
        Gemas = number,
        Nivel = number,
        XP = number,
        InventarioPoderes = { "Fireball", "Lightning", ... },
        VersionDatos = number,
      }
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerData = require(ReplicatedStorage:WaitForChild("PowerData"))
local EconomySystem = require(script.Parent.EconomySystem)
local PowerInventory = require(script.Parent.PowerInventory)

local SaveSystem = {}

-- ============================ CONFIGURACIÓN ============================

local NOMBRE_DATASTORE = "RobaElPoder_Perfiles_v1"
local PREFIJO_CLAVE = "Player_"
local VERSION_DATOS = 1
local AUTOSAVE_SEG = 300 -- 5 minutos
local INTENTOS = 3 -- reintentos por operación de red
local ESPERA_CIERRE_SEG = 25 -- margen máximo en BindToClose

-- ============================== ESTADO ================================

local remotes
local dataStore = nil
local dataStoreOk = false

-- [Player] = {
--   Cargado = true si el perfil se cargó correctamente,
--   CargaFallida = true si la carga falló (protegido contra sobrescritura),
-- }
local sesiones = {}
local guardando = {} -- [Player] = true mientras hay un guardado en curso

-- ============================ UTILIDADES ==============================

local function notificar(jugador, texto)
    if remotes and remotes:FindFirstChild("Notificacion") then
        remotes.Notificacion:FireClient(jugador, texto)
    end
end

local function claveDe(jugador)
    return PREFIJO_CLAVE .. jugador.UserId
end

local function perfilPorDefecto()
    local economia = PowerData.Config.Economia or {}
    return {
        Monedas = economia.MonedasIniciales or 100,
        Gemas = 0,
        Nivel = 1,
        XP = 0,
        InventarioPoderes = { PowerData.Config.PoderInicial },
        VersionDatos = VERSION_DATOS,
    }
end

-- Snapshot del estado ACTUAL del jugador (fuente: EconomySystem/PowerInventory).
local function construirPerfil(jugador)
    return {
        Monedas = EconomySystem.Obtener(jugador) or 0,
        Gemas = EconomySystem.ObtenerGemas(jugador) or 0,
        Nivel = EconomySystem.ObtenerNivel(jugador) or 1,
        XP = EconomySystem.ObtenerXP(jugador) or 0,
        InventarioPoderes = PowerInventory.GetSnapshot(jugador),
        VersionDatos = VERSION_DATOS,
    }
end

-- Migraciones de versión (placeholder para futuras fases).
local function migrar(datos)
    local version = tonumber(datos.VersionDatos) or 1

    -- Ejemplo futuro:
    -- if version < 2 then datos.NuevoCampo = 0 end

    datos.VersionDatos = VERSION_DATOS
    return datos
end

-- Aplica un perfil guardado a las sesiones vivas de Economy/Inventory.
local function aplicarPerfil(jugador, perfil)
    EconomySystem.Establecer(jugador, tonumber(perfil.Monedas) or 0)
    EconomySystem.EstablecerGemas(jugador, tonumber(perfil.Gemas) or 0)
    EconomySystem.EstablecerNivel(jugador, tonumber(perfil.Nivel) or 1)
    EconomySystem.EstablecerXP(jugador, tonumber(perfil.XP) or 0)
    PowerInventory.Establecer(jugador, perfil.InventarioPoderes or {})
end

-- ========================= LECTURA DE DATOS ===========================

-- Devuelve (true, datos|nil) o (false, nil).
-- datos == nil significa jugador NUEVO (sin perfil previo).
local function cargarPerfil(jugador)
    if not dataStoreOk then
        return false, nil
    end

    for intento = 1, INTENTOS do
        local exito, resultado = pcall(function()
            return dataStore:GetAsync(claveDe(jugador))
        end)

        if exito then
            if typeof(resultado) ~= "table" then
                -- Clave sin datos -> jugador nuevo.
                return true, nil
            end
            return true, resultado
        end

        warn(string.format(
            "[SaveSystem] Error al cargar %s (intento %d/%d): %s",
            jugador.Name, intento, INTENTOS, tostring(resultado)
        ))
        if intento < INTENTOS then
            task.wait(2 ^ intento)
        end
    end

    return false, nil
end

-- ======================== ESCRITURA DE DATOS =========================

-- Guarda el perfil si la sesión es válida (cargada y sin fallos).
-- Devuelve true si el guardado tuvo éxito.
local function guardarPerfil(jugador, razon)
    local sesion = sesiones[jugador]
    if not sesion or not sesion.Cargado or sesion.CargaFallida then
        return false
    end
    if not dataStoreOk then
        return false
    end
    -- Evita dos escrituras simultáneas del mismo jugador.
    if guardando[jugador] then
        return false
    end

    guardando[jugador] = true

    local exitoFinal = false
    for intento = 1, INTENTOS do
        local exito, err = pcall(function()
            -- El snapshot se construye DENTRO de UpdateAsync para capturar
            -- el estado más reciente posible de la sesión.
            dataStore:UpdateAsync(claveDe(jugador), function()
                return construirPerfil(jugador)
            end)
        end)

        if exito then
            exitoFinal = true
            break
        end

        warn(string.format(
            "[SaveSystem] Error al guardar %s (intento %d/%d, razón: %s): %s",
            jugador.Name, intento, INTENTOS, tostring(razon), tostring(err)
        ))
        if intento < INTENTOS then
            task.wait(2 ^ intento)
        end
    end

    guardando[jugador] = nil
    return exitoFinal
end

-- ========================== CICLO DE VIDA ==============================

local function cuandoEntra(jugador)
    sesiones[jugador] = { Cargado = false, CargaFallida = false }

    local exito, datos = cargarPerfil(jugador)

    -- El jugador pudo salir mientras cargaba (yield en GetAsync).
    local sesion = sesiones[jugador]
    if not sesion then
        return
    end

    if not exito then
        -- Carga fallida: la sesión queda protegida contra sobrescrituras.
        sesion.CargaFallida = true
        notificar(jugador, "⚠ Error al cargar tu perfil. Tu progreso NO se guardará en esta sesión para proteger tus datos.")
        return
    end

    sesion.Cargado = true

    local perfil
    if datos then
        -- Jugador existente: aplicar datos guardados.
        perfil = migrar(datos)
    else
        -- Jugador nuevo: monedas iniciales + poder base.
        perfil = perfilPorDefecto()
    end

    aplicarPerfil(jugador, perfil)
end

local function cuandoSale(jugador)
    local sesion = sesiones[jugador]

    if sesion and sesion.Cargado and not sesion.CargaFallida then
        -- Guardado inmediato al salir (no bloquea PlayerRemoving).
        task.spawn(function()
            guardarPerfil(jugador, "salida")
        end)
    end

    sesiones[jugador] = nil
    guardando[jugador] = nil
end

-- ============================== INIT ==================================

function SaveSystem.Init(carpetaRemotes)
    remotes = carpetaRemotes

    -- Obtener el DataStore con manejo de errores (Studio sin API access fallará aquí).
    local ok, resultado = pcall(function()
        return DataStoreService:GetDataStore(NOMBRE_DATASTORE)
    end)

    if ok and typeof(resultado) == "Instance" then
        dataStore = resultado
        dataStoreOk = true
    else
        warn("[SaveSystem] DataStore no disponible: " .. tostring(resultado))
        if RunService:IsStudio() then
            warn("[SaveSystem] (Studio) Activa 'Enable Studio Access to API Services' en Game Settings > Security para probar el guardado.")
        end
    end

    -- IMPORTANTE: SaveSystem.Init debe llamarse ANTES que EconomySystem.Init
    -- y PowerInventory.Init en Main. Así sus conexiones de PlayerAdded/
    -- PlayerRemoving se ejecutan primero: los datos se cargan antes de que
    -- otros sistemas asignen valores por defecto, y el guardado de salida lee
    -- el inventario/monedas antes de que esos módulos limpien sus tablas.

    Players.PlayerAdded:Connect(cuandoEntra)
    for _, jugador in Players:GetPlayers() do
        task.spawn(cuandoEntra, jugador)
    end

    Players.PlayerRemoving:Connect(cuandoSale)

    -- Auto-Save periódico (protege contra crashes del servidor).
    task.spawn(function()
        while true do
            task.wait(AUTOSAVE_SEG)
            for _, jugador in Players:GetPlayers() do
                task.spawn(guardarPerfil, jugador, "autosave")
            end
        end
    end)

    -- Cierre del servidor / shutdown: guardar todos los perfiles activos.
    game:BindToClose(function()
        local pendientes = 0
        for _, jugador in Players:GetPlayers() do
            local sesion = sesiones[jugador]
            if sesion and sesion.Cargado and not sesion.CargaFallida then
                pendientes += 1
                task.spawn(function()
                    guardarPerfil(jugador, "cierre")
                    pendientes -= 1
                end)
            end
        end

        if pendientes > 0 then
            local t0 = os.clock()
            while pendientes > 0 and os.clock() - t0 < ESPERA_CIERRE_SEG do
                task.wait(0.1)
            end
        end
    end)

    print("[SaveSystem] Fase 0.3 iniciada (DataStore: " .. tostring(dataStoreOk) .. ")")
end

return SaveSystem