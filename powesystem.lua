--[[
    PowerData (ModuleScript)
    Ubicación: ReplicatedStorage > PowerData

    Fuente única de verdad para balance, rarezas y configuración del MVP.
    El cliente puede leer estos datos para UI, pero el servidor SIEMPRE
    vuelve a validar los valores importantes.
]]

local PowerData = {}

PowerData.Config = {
    MaxSlots = 5,
    PoderInicial = "Fireball",
    DuracionEsfera = 10,
    DistanciaMaxObjetivo = 1000,
    -- Los demás poderes (Lightning, Teleport, Meteoro, NovaSolar)
    -- permanecen definidos aquí para el futuro sistema de huevos:
    -- romper un huevo será la única vía de obtenerlos.
    ModoTest = false,
    -- Evacuación: segundos de canalización para escapar.
    DuracionEvacSeg = 15,
    -- Economía del servidor (valores autoritativos).
    Economia = {
        MonedasIniciales = 100,
        RecompensaBaseEvac = 50,
    },
}

PowerData.Rarities = {
    Comun = {
        Nombre = "Común",
        ExtraccionSeg = 0,
        ValorMonedas = 25,
        Color = Color3.fromRGB(80, 220, 100),
    },
    Raro = {
        Nombre = "Raro",
        ExtraccionSeg = 10,
        ValorMonedas = 60,
        Color = Color3.fromRGB(70, 140, 255),
    },
    Epico = {
        Nombre = "Épico",
        ExtraccionSeg = 20,
        ValorMonedas = 150,
        Color = Color3.fromRGB(170, 90, 255),
    },
    Legendario = {
        Nombre = "Legendario",
        ExtraccionSeg = 30,
        ValorMonedas = 400,
        Color = Color3.fromRGB(255, 200, 40),
    },
    Mitico = {
        Nombre = "Mítico",
        ExtraccionSeg = -1,
        ValorMonedas = 1000,
        Color = Color3.fromRGB(255, 50, 50),
    },
}

PowerData.Powers = {
    Fireball = {
        Nombre = "Fireball",
        Rareza = "Comun",
        Cooldown = 2,
        Dano = 25,
        Velocidad = 90,
        Radio = 1.5,
        VidaSeg = 3,
        Color = Color3.fromRGB(255, 120, 30),
    },

    Lightning = {
        Nombre = "Lightning",
        Rareza = "Raro",
        Cooldown = 6,
        Dano = 35,
        RadioArea = 12,
        AlcanceMax = 60,
        RetrasoSeg = 0.7,
        Color = Color3.fromRGB(255, 255, 120),
    },

    Teleport = {
        Nombre = "Teleport",
        Rareza = "Epico",
        Cooldown = 8,
        AlcanceMax = 50,
        Color = Color3.fromRGB(120, 200, 255),
    },

    Meteoro = {
        Nombre = "Meteoro",
        Rareza = "Legendario",
        Cooldown = 15,
        Dano = 60,
        RadioArea = 18,
        AlcanceMax = 80,
        RetrasoSeg = 1,
        Color = Color3.fromRGB(255, 140, 0),
    },

    NovaSolar = {
        Nombre = "Nova Solar",
        Rareza = "Mitico",
        Cooldown = 40,
        Dano = 100,
        RadioArea = 25,
        Color = Color3.fromRGB(255, 240, 120),
    },
}

-- Orden fijo de otorgamiento en modo test:
-- slot 1 = tecla Q, slot 2 = E, slot 3 = R, slot 4 = F, slot 5 = V.
-- (La iteración de diccionarios en Luau NO garantiza orden, por eso
-- esta lista explícita.)
PowerData.OrdenPoderes = {
    "Fireball",
    "Lightning",
    "Teleport",
    "Meteoro",
    "NovaSolar",
}

-- Huevos de la Safe Zone. Precio y pesos de rareza (%; suman 100).
-- El roll se hace en el servidor con math.random(1, 100).
PowerData.Eggs = {
    HuevoBasico = {
        Nombre = "Huevo Básico",
        Precio = 100,
        Color = Color3.fromRGB(120, 90, 60),
        Probabilidades = {
            Comun = 65,
            Raro = 27,
            Epico = 6,
            Legendario = 1.5,
            Mitico = 0.5,
        },
    },

    HuevoEpico = {
        Nombre = "Huevo Épico",
        Precio = 500,
        Color = Color3.fromRGB(180, 90, 255),
        Probabilidades = {
            Comun = 30,
            Raro = 40,
            Epico = 22,
            Legendario = 6.5,
            Mitico = 1.5,
        },
    },
}

return PowerData
