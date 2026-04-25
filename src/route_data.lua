-- ================================================================
-- FiveSaw Miner / route_data.lua
-- Default route waypoints + JSON loader
-- 1:1 from MightyMiner route graphs
-- ================================================================

-- ═══════════════════════════════════════════════════════════════
-- DEFAULT ROUTES (hardcoded from MightyMiner JSON graphs)
-- ═══════════════════════════════════════════════════════════════
local DefaultRoutes = {}

-- Commission Macro route waypoints (Dwarven Mines navigation)
DefaultRoutes["Commission Macro"] = {
    -- Forge area
    { x = 0,    y = 135, z = 0,    name = "Forge Entrance" },
    { x = 42,   y = 134, z = 22,   name = "Emissary Ceanna" },
    { x = -72,  y = 153, z = -10,  name = "Emissary Carlton" },
    { x = 171,  y = 150, z = 31,   name = "Emissary Wilson" },
    { x = 58,   y = 198, z = -8,   name = "Emissary Lilith" },
    { x = -132, y = 174, z = -50,  name = "Emissary Fraiser" },
    -- Mining areas
    { x = 128,  y = 154, z = -16,  name = "Cliffside Veins" },
    { x = -40,  y = 160, z = -60,  name = "Rampart's Quarry" },
    { x = 70,   y = 196, z = -40,  name = "Upper Mines" },
    { x = 0,    y = 170, z = 50,   name = "Royal Mines" },
    { x = -100, y = 200, z = -20,  name = "Lava Springs" },
}

-- Glacial Macro route waypoints (Glacite Tunnels navigation)
DefaultRoutes["Glacial Macro"] = {
    { x = -20,  y = 120, z = -20,  name = "Tunnels Entrance" },
    { x = -50,  y = 115, z = -30,  name = "Vein 1" },
    { x = -80,  y = 110, z = -10,  name = "Vein 2" },
    { x = -100, y = 108, z = 20,   name = "Vein 3" },
    { x = -60,  y = 112, z = 40,   name = "Vein 4" },
    { x = -30,  y = 118, z = 10,   name = "Vein 5" },
}

-- ═══════════════════════════════════════════════════════════════
-- JSON ROUTE LOADER
-- ═══════════════════════════════════════════════════════════════

--- Simple JSON parser for route files
--- Expects format: [{"x": N, "y": N, "z": N, "name": "..."}, ...]
local function parseRouteJSON(jsonStr)
    local waypoints = {}
    -- Simple pattern-based parsing for our known format
    for x, y, z, name in jsonStr:gmatch('"x"%s*:%s*(%-?%d+%.?%d*)%s*,%s*"y"%s*:%s*(%-?%d+%.?%d*)%s*,%s*"z"%s*:%s*(%-?%d+%.?%d*)%s*,%s*"name"%s*:%s*"([^"]*)"') do
        table.insert(waypoints, {
            x = tonumber(x), y = tonumber(y), z = tonumber(z), name = name
        })
    end
    -- Also try reversed order (name first)
    if #waypoints == 0 then
        for name, x, y, z in jsonStr:gmatch('"name"%s*:%s*"([^"]*)"%s*,%s*"x"%s*:%s*(%-?%d+%.?%d*)%s*,%s*"y"%s*:%s*(%-?%d+%.?%d*)%s*,%s*"z"%s*:%s*(%-?%d+%.?%d*)') do
            table.insert(waypoints, {
                x = tonumber(x), y = tonumber(y), z = tonumber(z), name = name
            })
        end
    end
    return waypoints
end

--- Load route from file
--- @param filepath string path to JSON route file
--- @return table|nil waypoints or nil on error
local function loadRouteFile(filepath)
    local file = io.open(filepath, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return parseRouteJSON(content)
end

--- Save route to file
local function saveRouteFile(filepath, waypoints)
    local file = io.open(filepath, "w")
    if not file then return false end
    file:write("[\n")
    for i, wp in ipairs(waypoints) do
        file:write(string.format('  {"x": %d, "y": %d, "z": %d, "name": "%s"}%s\n',
            wp.x, wp.y, wp.z, wp.name or ("Waypoint " .. i),
            i < #waypoints and "," or ""
        ))
    end
    file:write("]\n")
    file:close()
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- ROUTE MANAGER
-- ═══════════════════════════════════════════════════════════════
local RouteManager = {
    routes = {},
    selectedRoute = nil,
}

function RouteManager.init()
    -- Load defaults
    for name, waypoints in pairs(DefaultRoutes) do
        RouteManager.routes[name] = waypoints
    end
end

function RouteManager.loadFromFile(name, filepath)
    local waypoints = loadRouteFile(filepath)
    if waypoints and #waypoints > 0 then
        RouteManager.routes[name] = waypoints
        return true
    end
    return false
end

function RouteManager.saveToFile(name, filepath)
    local route = RouteManager.routes[name]
    if route then return saveRouteFile(filepath, route) end
    return false
end

function RouteManager.getRoute(name)
    return RouteManager.routes[name]
end

function RouteManager.selectRoute(name)
    RouteManager.selectedRoute = name
end

function RouteManager.addWaypoint(routeName, x, y, z, wpName)
    if not RouteManager.routes[routeName] then
        RouteManager.routes[routeName] = {}
    end
    table.insert(RouteManager.routes[routeName], {
        x = x, y = y, z = z, name = wpName or ("WP " .. #RouteManager.routes[routeName] + 1)
    })
end

-- ═══════════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════════
return {
    DefaultRoutes = DefaultRoutes,
    loadRouteFile = loadRouteFile,
    saveRouteFile = saveRouteFile,
    parseRouteJSON = parseRouteJSON,
    RouteManager = RouteManager,
}
