--[[
    MapBuilder (Script)
    Ubicación: ServerScriptService > MapBuilder

    Construye el mapa mínimo del MVP si no existe workspace.Zones.
    Si el equipo ya creó un mapa manual, no lo pisa.
]]

if workspace:FindFirstChild("Zones") then
    print("[MapBuilder] workspace.Zones ya existe; no se generará el mapa de prueba.")
    return
end

local function crearParte(nombre, tamano, posicion, color, transparencia, esZona)
    local p = Instance.new("Part")
    p.Name = nombre
    p.Size = tamano
    p.Position = posicion
    p.Color = color
    p.Transparency = transparencia
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth

    if esZona then
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Material = Enum.Material.Neon
    end

    return p
end

local suelo = crearParte(
    "Suelo",
    Vector3.new(300, 1, 300),
    Vector3.new(0, -0.5, 0),
    Color3.fromRGB(110, 110, 110),
    0,
    false
)
suelo.Parent = workspace

local carpeta = Instance.new("Folder")
carpeta.Name = "Zones"

crearParte(
    "SafeZone",
    Vector3.new(150, 40, 300),
    Vector3.new(-75, 20, 0),
    Color3.fromRGB(60, 200, 90),
    0.9,
    true
).Parent = carpeta

crearParte(
    "RedZone",
    Vector3.new(150, 40, 300),
    Vector3.new(75, 20, 0),
    Color3.fromRGB(220, 50, 50),
    0.9,
    true
).Parent = carpeta

carpeta.Parent = workspace

local spawn = Instance.new("SpawnLocation")
spawn.Name = "SafeSpawn"
spawn.Size = Vector3.new(12, 1, 12)
spawn.Position = Vector3.new(-100, 0.5, 0)
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 2
spawn.Parent = workspace

print("[MapBuilder] Mapa de prueba MVP creado.")
