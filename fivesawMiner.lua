-- ================================================================
-- fivesawMiner.lua
-- FiveSaw Miner — Full 1:1 MightyMiner Port
-- All-in-one bundled macro: Commission, Mining, Glacial, Route
-- Anti-cheat compliant: Bézier rotations, humanized timing
-- ================================================================
local __fsm_preload = {}
local __fsm_loaded = {}
local function __fsm_require(modname)
    if __fsm_loaded[modname] then return __fsm_loaded[modname] end
    if __fsm_preload[modname] then
        local res = __fsm_preload[modname]()
        __fsm_loaded[modname] = res or true
        return __fsm_loaded[modname]
    end
    return require(modname) -- fallback to standard require
end

__fsm_preload["fivesawMiner/core"] = function()
    -- ================================================================
    -- FiveSaw Miner / core.lua
    -- Core utilities: Clock, GameState, RotationHandler, MacroBase
    -- 1:1 port of MightyMiner infrastructure
    -- ================================================================
    
    -- ═══════════════════════════════════════════════════════════════
    -- CLOCK (1:1 Clock.java)
    -- ═══════════════════════════════════════════════════════════════
    local Clock = {}
    Clock.__index = Clock
    
    function Clock.new()
        return setmetatable({ _scheduled = false, _startMs = 0, _durationMs = 0, _accumMs = 0 }, Clock)
    end
    
    function Clock:schedule(ms)
        self._scheduled = true
        self._startMs = os.clock() * 1000
        self._durationMs = ms
    end
    
    function Clock:passed()
        if not self._scheduled then return false end
        return (os.clock() * 1000 - self._startMs) >= self._durationMs
    end
    
    function Clock:isScheduled() return self._scheduled end
    
    function Clock:reset()
        self._scheduled = false
        self._startMs = 0
        self._durationMs = 0
    end
    
    function Clock:elapsed()
        if not self._scheduled then return 0 end
        return os.clock() * 1000 - self._startMs
    end
    
    function Clock:start(resetAccum)
        if resetAccum then self._accumMs = 0 end
        self._startMs = os.clock() * 1000
        self._scheduled = true
    end
    
    function Clock:stop(resetAccum)
        if self._scheduled then
            self._accumMs = self._accumMs + (os.clock() * 1000 - self._startMs)
        end
        if resetAccum then self._accumMs = 0 end
        self._scheduled = false
    end
    
    function Clock:getAccumMs() return self._accumMs + (self._scheduled and (os.clock() * 1000 - self._startMs) or 0) end
    
    -- ═══════════════════════════════════════════════════════════════
    -- LOCATION ENUMS (1:1 Location.java + SubLocation.java)
    -- ═══════════════════════════════════════════════════════════════
    local Location = {
        PRIVATE_ISLAND = "Private Island", HUB = "Hub", THE_PARK = "The Park",
        THE_FARMING_ISLANDS = "The Farming Islands", SPIDER_DEN = "Spider's Den",
        THE_END = "The End", CRIMSON_ISLE = "Crimson Isle", GOLD_MINE = "Gold Mine",
        DEEP_CAVERNS = "Deep Caverns", DWARVEN_MINES = "Dwarven Mines",
        CRYSTAL_HOLLOWS = "Crystal Hollows", JERRY_WORKSHOP = "Jerry's Workshop",
        DUNGEON_HUB = "Dungeon Hub", GARDEN = "Garden", DUNGEON = "Dungeon",
        LIMBO = "LIMBO", LOBBY = "LOBBY", KNOWHERE = "KNOWHERE",
    }
    
    local LocationByName = {}
    for k, v in pairs(Location) do LocationByName[v] = k end
    
    local SubLocation = {
        -- Dwarven Mines (critical for mining macros)
        ARISTOCRAT_PASSAGE = "Aristocrat Passage", CLIFFSIDE_VEINS = "Cliffside Veins",
        DIVANS_GATEWAY = "Divan's Gateway", DWARVEN_MINES = "Dwarven Mines",
        DWARVEN_VILLAGE = "Dwarven Village", FAR_RESERVE = "Far Reserve",
        FORGE_BASIN = "Forge Basin", GOBLIN_BURROWS = "Goblin Burrows",
        GREAT_ICE_WALL = "Great Ice Wall", LAVA_SPRINGS = "Lava Springs",
        MINERS_GUILD = "Miner's Guild", PALACE_BRIDGE = "Palace Bridge",
        RAMPARTS_QUARRY = "Rampart's Quarry", ROYAL_MINES = "Royal Mines",
        THE_FORGE = "The Forge", THE_MIST = "The Mist", UPPER_MINES = "Upper Mines",
        -- Glacite
        DWARVEN_BASE_CAMP = "Dwarven Base Camp", GLACITE_TUNNELS = "Glacite Tunnels",
        GLACITE_MINESHAFT = "Glacite Mineshafts",
        -- Crystal Hollows
        CRYSTAL_NUCLEUS = "Crystal Nucleus", JUNGLE = "Jungle",
        GOBLIN_HOLDOUT = "Goblin Holdout", MITHRIL_DEPOSITS = "Mithril Deposits",
        PRECURSOR_REMNANTS = "Precursor Remnants", MAGMA_FIELDS = "Magma Fields",
        KNOWHERE = "KNOWHERE",
    }
    
    local SubLocationByName = {}
    for k, v in pairs(SubLocation) do SubLocationByName[v] = k end
    
    -- ═══════════════════════════════════════════════════════════════
    -- GAME STATE HANDLER (1:1 GameStateHandler.java)
    -- ═══════════════════════════════════════════════════════════════
    local GameState = {
        currentLocation = "KNOWHERE",
        currentSubLocation = "KNOWHERE",
        serverIp = "",
        godpotActive = false,
        cookieActive = false,
    }
    
    function GameState.update()
        if not player then return end
        local tab = player.getTabList and player.getTabList() or {}
    
        -- Detect location from tablist "Area: xxx"
        for _, line in ipairs(tab) do
            local area = line:match("Area:%s*(.+)")
            if area then
                area = area:gsub("§.", "")  -- strip color codes
                GameState.currentLocation = LocationByName[area] or "KNOWHERE"
                break
            end
        end
    
        -- Detect sublocation from scoreboard
        local sb = player.getScoreboard and player.getScoreboard() or {}
        for _, line in ipairs(sb) do
            local clean = line:gsub("§.", ""):gsub("[⏣ф]", ""):match("^%s*(.-)%s*$")
            if clean and SubLocationByName[clean] then
                GameState.currentSubLocation = SubLocationByName[clean]
                break
            end
        end
    end
    
    function GameState.isInSkyBlock()
        local loc = GameState.currentLocation
        return loc ~= "KNOWHERE" and loc ~= "LOBBY" and loc ~= "LIMBO"
    end
    
    function GameState.inDwarvenMines()
        return GameState.currentLocation == "DWARVEN_MINES"
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- ANGLE UTILITIES (1:1 AngleUtil.java)
    -- ═══════════════════════════════════════════════════════════════
    local AngleUtil = {}
    
    function AngleUtil.normalizeAngle(yaw)
        local n = yaw % 360
        if n < -180 then n = n + 360 end
        if n > 180 then n = n - 360 end
        return n
    end
    
    function AngleUtil.get360Yaw(yaw)
        return (yaw % 360 + 360) % 360
    end
    
    function AngleUtil.getPlayerAngle()
        local rot = player.getRotation()
        return { yaw = AngleUtil.get360Yaw(rot.yaw), pitch = rot.pitch }
    end
    
    function AngleUtil.getRotationTo(from, to)
        local dx = to.x - from.x
        local dy = to.y - from.y
        local dz = to.z - from.z
        local dist = math.sqrt(dx * dx + dz * dz)
        local yaw = math.deg(math.atan2(dz, dx)) - 90
        local pitch = -math.deg(math.atan2(dy, dist))
        return { yaw = yaw, pitch = pitch }
    end
    
    function AngleUtil.getRotationToBlock(bx, by, bz)
        local pos = player.getPos()
        local eyeY = pos.y + 1.62  -- eye height
        return AngleUtil.getRotationTo(
            { x = pos.x, y = eyeY, z = pos.z },
            { x = bx + 0.5, y = by + 0.5, z = bz + 0.5 }
        )
    end
    
    function AngleUtil.getNeededChange(startAngle, endAngle)
        local yawChange = AngleUtil.normalizeAngle(
            AngleUtil.normalizeAngle(endAngle.yaw) - AngleUtil.normalizeAngle(startAngle.yaw)
        )
        return { yaw = yawChange, pitch = endAngle.pitch - startAngle.pitch }
    end
    
    function AngleUtil.angleMagnitude(change)
        return math.sqrt(change.yaw * change.yaw + change.pitch * change.pitch)
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- ROTATION HANDLER (1:1 RotationHandler.java — Bézier curves)
    -- ═══════════════════════════════════════════════════════════════
    local RotationHandler = {
        _enabled = false,
        _queue = {},
        _startAngle = { yaw = 0, pitch = 0 },
        _targetAngle = { yaw = 0, pitch = 0 },
        _startTime = 0,
        _endTime = 0,
        _lastBezierYaw = 0,
        _lastBezierPitch = 0,
        _serverYaw = 0,
        _serverPitch = 0,
        _randMul1 = 1,
        _randMul2 = 1,
        _followTarget = false,
        _stopRequested = false,
        _callback = nil,
        _rotationType = "SERVER",  -- "SERVER" or "CLIENT"
        _easeBackToClient = false,
        _config = nil,
    }
    
    -- Cubic Bézier (exact MightyMiner formula)
    local function bezier(t, c1, c2, e)
        return 3 * (1 - t)^2 * t * c1 + 3 * (1 - t) * t^2 * c2 + t^3 * e
    end
    
    -- Ease function (smooth step)
    local function easeInOutQuad(t)
        if t < 0.5 then return 2 * t * t end
        return 1 - (-2 * t + 2)^2 / 2
    end
    
    -- Time scaling based on angle magnitude (exact MightyMiner getTime())
    local function getScaledTime(magnitude, baseTime)
        if baseTime <= 0 then return 1 end
        if magnitude < 25 then return math.floor(baseTime * 0.65) end
        if magnitude < 45 then return math.floor(baseTime * 0.77) end
        if magnitude < 80 then return math.floor(baseTime * 0.9) end
        if magnitude > 100 then return math.floor(baseTime * 1.1) end
        return baseTime
    end
    
    function RotationHandler.easeTo(targetYaw, targetPitch, timeMs, rotType, followTarget, callback, easeBack)
        local rh = RotationHandler
        rh._rotationType = rotType or "SERVER"
        rh._followTarget = followTarget or false
        rh._callback = callback
        rh._easeBackToClient = easeBack or false
        rh._startTime = os.clock() * 1000
    
        if rh._rotationType == "SERVER" then
            if rh._serverYaw == 0 and rh._serverPitch == 0 then
                local rot = player.getRotation()
                rh._serverYaw = rot.yaw
                rh._serverPitch = rot.pitch
            end
            rh._startAngle = { yaw = AngleUtil.get360Yaw(rh._serverYaw), pitch = rh._serverPitch }
        else
            rh._startAngle = AngleUtil.getPlayerAngle()
        end
    
        rh._targetAngle = { yaw = targetYaw, pitch = targetPitch }
    
        local change = AngleUtil.getNeededChange(rh._startAngle, rh._targetAngle)
        local mag = AngleUtil.angleMagnitude(change)
        rh._endTime = rh._startTime + getScaledTime(mag, timeMs or 400)
    
        -- Randomized Bézier control point multipliers (exact MightyMiner)
        local sign = math.random() > 0.5 and 1 or -1
        rh._randMul1 = sign
        rh._randMul2 = sign
    
        rh._lastBezierYaw = 0
        rh._lastBezierPitch = 0
        rh._stopRequested = false
        rh._enabled = true
    end
    
    function RotationHandler.queueRotation(targetYaw, targetPitch, timeMs, rotType, followTarget, callback)
        table.insert(RotationHandler._queue, {
            yaw = targetYaw, pitch = targetPitch, time = timeMs,
            rotType = rotType, follow = followTarget, callback = callback
        })
    end
    
    function RotationHandler.startQueue()
        if #RotationHandler._queue == 0 or RotationHandler._enabled then return end
        local r = table.remove(RotationHandler._queue, 1)
        RotationHandler.easeTo(r.yaw, r.pitch, r.time, r.rotType, r.follow, r.callback)
    end
    
    function RotationHandler.stop()
        RotationHandler._queue = {}
        RotationHandler._stopRequested = true
        RotationHandler._enabled = false
    end
    
    function RotationHandler._getBezierAngle()
        local rh = RotationHandler
        local totalTime = rh._endTime - rh._startTime
        if totalTime <= 0 then totalTime = 1 end
        local timeProgress = math.min(1.0, (os.clock() * 1000 - rh._startTime) / totalTime)
        local rotProgress = easeInOutQuad(timeProgress)
    
        local bEnd = AngleUtil.getNeededChange(rh._startAngle, rh._targetAngle)
        local c1 = { yaw = bEnd.yaw * 0.05 * rh._randMul1, pitch = bEnd.yaw * 0.1 * rh._randMul2 }
        local c2 = { yaw = bEnd.yaw - bEnd.yaw * 0.05 * rh._randMul2, pitch = bEnd.pitch - bEnd.yaw * 0.1 * rh._randMul1 }
    
        return {
            yaw = bezier(rotProgress, c1.yaw, c2.yaw, bEnd.yaw),
            pitch = bezier(rotProgress, c1.pitch, c2.pitch, bEnd.pitch),
        }
    end
    
    function RotationHandler._handleEnd()
        local rh = RotationHandler
        if not rh._stopRequested then
            if rh._followTarget then
                RotationHandler.easeTo(rh._targetAngle.yaw, rh._targetAngle.pitch, 400, rh._rotationType, true, rh._callback)
                return
            end
            if rh._callback then rh._callback() end
            if #rh._queue > 0 then
                local r = table.remove(rh._queue, 1)
                RotationHandler.easeTo(r.yaw, r.pitch, r.time, r.rotType, r.follow, r.callback)
                return
            end
        end
        -- Reset
        rh._enabled = false
        rh._followTarget = false
        rh._stopRequested = false
        if rh._stopRequested then
            rh._config = nil
            rh._serverYaw = 0
            rh._serverPitch = 0
            rh._lastBezierYaw = 0
            rh._lastBezierPitch = 0
        end
    end
    
    -- Call every tick
    function RotationHandler.onTick()
        local rh = RotationHandler
        if not rh._enabled then return end
    
        local ba = rh._getBezierAngle()
    
        if rh._rotationType == "SERVER" then
            rh._serverYaw = rh._serverYaw + (ba.yaw - rh._lastBezierYaw)
            rh._serverPitch = rh._serverPitch + (ba.pitch - rh._lastBezierPitch)
            -- Clamp pitch
            rh._serverPitch = math.max(-90, math.min(90, rh._serverPitch))
            player.setSilentRotation(rh._serverYaw, rh._serverPitch, true, false)
        else
            local rot = player.getRotation()
            local newYaw = rot.yaw + (ba.yaw - rh._lastBezierYaw)
            local newPitch = math.max(-90, math.min(90, rot.pitch + (ba.pitch - rh._lastBezierPitch)))
            player.setRotation(newYaw, newPitch)
        end
    
        rh._lastBezierYaw = ba.yaw
        rh._lastBezierPitch = ba.pitch
    
        if os.clock() * 1000 > rh._endTime or rh._stopRequested then
            rh._handleEnd()
        end
    end
    
    function RotationHandler.isEnabled() return RotationHandler._enabled end
    
    -- ═══════════════════════════════════════════════════════════════
    -- MACRO BASE (1:1 AbstractMacro.java)
    -- ═══════════════════════════════════════════════════════════════
    local MacroBase = {}
    MacroBase.__index = MacroBase
    
    function MacroBase.new(name)
        return setmetatable({
            _name = name,
            _enabled = false,
            timer = Clock.new(),
            uptime = Clock.new(),
        }, MacroBase)
    end
    
    function MacroBase:getName() return self._name end
    function MacroBase:isEnabled() return self._enabled end
    
    function MacroBase:enable()
        self:log("enable")
        self:onEnable()
        self.uptime:start(true)
        self._enabled = true
    end
    
    function MacroBase:disable(reason)
        if reason then self:error(reason) end
        self:log("disable")
        self.uptime:stop(false)
        self._enabled = false
        self:onDisable()
    end
    
    function MacroBase:pause()
        self:log("pause")
        self.uptime:stop(false)
        self._enabled = false
        self:onPause()
    end
    
    function MacroBase:resume()
        self:log("resume")
        self:onResume()
        self.uptime:start(false)
        self._enabled = true
    end
    
    function MacroBase:toggle()
        if self._enabled then self:disable() else self:enable() end
    end
    
    function MacroBase:hasTimerEnded()
        return self.timer:isScheduled() and self.timer:passed()
    end
    
    function MacroBase:isTimerRunning()
        return self.timer:isScheduled() and not self.timer:passed()
    end
    
    -- Override these in subclasses
    function MacroBase:onEnable() end
    function MacroBase:onDisable() end
    function MacroBase:onPause() end
    function MacroBase:onResume() end
    function MacroBase:onTick() end
    function MacroBase:onChat(msg) end
    function MacroBase:getNecessaryItems() return {} end
    
    function MacroBase:log(msg) player.addMessage("§7[" .. self._name .. "] " .. msg) end
    function MacroBase:send(msg) player.addMessage("§a[" .. self._name .. "] " .. msg) end
    function MacroBase:error(msg) player.addMessage("§c[" .. self._name .. "] " .. msg) end
    function MacroBase:warn(msg) player.addMessage("§e[" .. self._name .. "] " .. msg) end
    
    -- ═══════════════════════════════════════════════════════════════
    -- EXPORTS
    -- ═══════════════════════════════════════════════════════════════
    return {
        Clock = Clock,
        Location = Location,
        SubLocation = SubLocation,
        GameState = GameState,
        AngleUtil = AngleUtil,
        RotationHandler = RotationHandler,
        MacroBase = MacroBase,
    }
    
end

__fsm_preload["fivesawMiner/block_miner"] = function()
    -- ================================================================
    -- FiveSaw Miner / block_miner.lua
    -- Block Mining Engine — 1:1 port of BlockMiner.java + all states
    -- ================================================================
    
    local core = __fsm_require("fivesawMiner/core")
    local Clock = core.Clock
    local AngleUtil = core.AngleUtil
    local RotationHandler = core.RotationHandler
    
    -- ═══════════════════════════════════════════════════════════════
    -- MINEABLE BLOCKS (1:1 MineableBlock.java → NeoScripts 1.21.11)
    -- Block names mapped to their NeoScripts block identifiers
    -- ═══════════════════════════════════════════════════════════════
    local MineableBlock = {
        GRAY_MITHRIL    = { "minecraft:gray_wool", "minecraft:cyan_terracotta" },
        GREEN_MITHRIL   = { "minecraft:prismarine", "minecraft:dark_prismarine", "minecraft:prismarine_bricks" },
        BLUE_MITHRIL    = { "minecraft:light_blue_wool" },
        TITANIUM        = { "minecraft:polished_diorite" },
        DIAMOND         = { "minecraft:diamond_block" },
        EMERALD         = { "minecraft:emerald_block" },
        REDSTONE        = { "minecraft:redstone_block" },
        LAPIS           = { "minecraft:lapis_block" },
        GOLD            = { "minecraft:gold_block" },
        IRON            = { "minecraft:iron_block" },
        COAL            = { "minecraft:coal_block" },
        HARDSTONE       = { "minecraft:stone" },
        GLACITE         = { "minecraft:packed_ice" },
        SULPHUR         = { "minecraft:sponge" },
        UMBER           = { "minecraft:terracotta", "minecraft:brown_terracotta" },
        TUNGSTEN        = { "minecraft:polished_granite", "minecraft:iron_ore" },
        OPAL            = { "minecraft:glass", "minecraft:glass_pane" },
        JASPER          = { "minecraft:magenta_stained_glass", "minecraft:magenta_stained_glass_pane" },
        TOPAZ           = { "minecraft:yellow_stained_glass", "minecraft:yellow_stained_glass_pane" },
        AMBER           = { "minecraft:orange_stained_glass", "minecraft:orange_stained_glass_pane" },
        SAPPHIRE        = { "minecraft:light_blue_stained_glass", "minecraft:light_blue_stained_glass_pane" },
        JADE            = { "minecraft:lime_stained_glass", "minecraft:lime_stained_glass_pane" },
        AMETHYST        = { "minecraft:purple_stained_glass", "minecraft:purple_stained_glass_pane" },
        RUBY            = { "minecraft:red_stained_glass", "minecraft:red_stained_glass_pane" },
        AQUAMARINE      = { "minecraft:cyan_stained_glass", "minecraft:cyan_stained_glass_pane" },
        PERIDOT         = { "minecraft:green_stained_glass", "minecraft:green_stained_glass_pane" },
        ONYX            = { "minecraft:black_stained_glass", "minecraft:black_stained_glass_pane" },
        CITRINE         = { "minecraft:brown_stained_glass", "minecraft:brown_stained_glass_pane" },
    }
    
    -- Block strength table (1:1 getBlockStrength())
    local BlockStrength = {
        ["minecraft:diamond_block"] = 600, ["minecraft:gold_block"] = 600,
        ["minecraft:redstone_block"] = 600, ["minecraft:lapis_block"] = 600,
        ["minecraft:emerald_block"] = 600, ["minecraft:iron_block"] = 600,
        ["minecraft:coal_block"] = 600, ["minecraft:sponge"] = 500,
        ["minecraft:stone"] = 50, ["minecraft:polished_diorite"] = 2000,
        ["minecraft:gray_wool"] = 500, ["minecraft:light_blue_wool"] = 1500,
        ["minecraft:cyan_terracotta"] = 500,
        ["minecraft:prismarine"] = 800, ["minecraft:dark_prismarine"] = 800,
        ["minecraft:prismarine_bricks"] = 800,
        ["minecraft:glass"] = 3800, ["minecraft:glass_pane"] = 3800,
        ["minecraft:yellow_stained_glass"] = 3800, ["minecraft:yellow_stained_glass_pane"] = 3800,
        ["minecraft:orange_stained_glass"] = 3000, ["minecraft:orange_stained_glass_pane"] = 3000,
        ["minecraft:light_blue_stained_glass"] = 3000, ["minecraft:light_blue_stained_glass_pane"] = 3000,
        ["minecraft:lime_stained_glass"] = 3000, ["minecraft:lime_stained_glass_pane"] = 3000,
        ["minecraft:purple_stained_glass"] = 3000, ["minecraft:purple_stained_glass_pane"] = 3000,
        ["minecraft:magenta_stained_glass"] = 4800, ["minecraft:magenta_stained_glass_pane"] = 4800,
        ["minecraft:cyan_stained_glass"] = 5200, ["minecraft:cyan_stained_glass_pane"] = 5200,
        ["minecraft:green_stained_glass"] = 5200, ["minecraft:green_stained_glass_pane"] = 5200,
        ["minecraft:black_stained_glass"] = 5200, ["minecraft:black_stained_glass_pane"] = 5200,
        ["minecraft:brown_stained_glass"] = 5200, ["minecraft:brown_stained_glass_pane"] = 5200,
        ["minecraft:red_stained_glass"] = 2300, ["minecraft:red_stained_glass_pane"] = 2300,
        ["minecraft:packed_ice"] = 500,
    }
    
    local function getBlockStrength(blockName)
        return BlockStrength[blockName] or 5000
    end
    
    local function getMiningTime(blockName, miningSpeed, tickOffset)
        tickOffset = tickOffset or 2
        return math.ceil((getBlockStrength(blockName) * 30) / miningSpeed) + tickOffset
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- BLOCK SCANNER — find mineable blocks near player
    -- (1:1 BlockUtil.findMineableBlocksAroundHead)
    -- ═══════════════════════════════════════════════════════════════
    local function longHash(x, y, z)
        local hash = 3241
        hash = 3457689 * hash + x
        hash = 8734625 * hash + y
        hash = 2873465 * hash + z
        return hash
    end
    
    --- Build a priority lookup from config tables
    --- @param blockTypes table array of MineableBlock keys
    --- @param priorities table array of priority ints (0=ignore)
    --- @return table blockName→priority
    local function buildPriorityMap(blockTypes, priorities)
        local pmap = {}
        for i, key in ipairs(blockTypes) do
            local pri = priorities[i] or 1
            if pri > 0 then
                local blocks = MineableBlock[key]
                if blocks then
                    for _, bname in ipairs(blocks) do
                        pmap[bname] = pri
                    end
                end
            end
        end
        return pmap
    end
    
    --- Scan blocks around player, sorted by cost
    --- @param priorityMap table blockName→priority
    --- @param miningSpeed number
    --- @param ignorePos table|nil {x,y,z} to ignore
    --- @param config table with miningCoeff, angleCoeff, distCoeff
    --- @return table array of {x,y,z,cost,blockName}
    local function findMineableBlocks(priorityMap, miningSpeed, ignorePos, config)
        config = config or {}
        local mCoeff = config.miningCoeff or 1.0
        local aCoeff = config.angleCoeff or 0.2
        local dCoeff = config.distCoeff or 0.5
    
        local pos = player.getPos()
        local eyeX, eyeY, eyeZ = pos.x, pos.y + 1.62, pos.z
        local playerAngle = AngleUtil.getPlayerAngle()
    
        local visited = {}
        if ignorePos then
            visited[longHash(math.floor(ignorePos.x), math.floor(ignorePos.y), math.floor(ignorePos.z))] = true
        end
    
        local results = {}
        local HR = 5  -- horizontal radius
        local VL, VU = -3, 4  -- vertical bounds
    
        for dy = VL, VU do
            for dx = -HR, HR do
                for dz = -HR, HR do
                    local bx = math.floor(eyeX) + dx
                    local by = math.floor(eyeY) + dy
                    local bz = math.floor(eyeZ) + dz
    
                    local h = longHash(bx, by, bz)
                    if not visited[h] then
                        visited[h] = true
    
                        local ddx = eyeX - (bx + 0.5)
                        local ddy = eyeY - (by + 0.5)
                        local ddz = eyeZ - (bz + 0.5)
                        local distSq = ddx*ddx + ddy*ddy + ddz*ddz
    
                        if distSq <= 16 then  -- 4^2 max reach
                            local block = world.getBlock(bx, by, bz)
                            if block and priorityMap[block.name] then
                                local pri = priorityMap[block.name]
                                -- Calculate cost
                                local hardness = getBlockStrength(block.name)
                                local rot = AngleUtil.getRotationToBlock(bx, by, bz)
                                local change = AngleUtil.getNeededChange(playerAngle, rot)
                                local angleDist = AngleUtil.angleMagnitude(change)
    
                                local cost = (hardness / miningSpeed) * mCoeff
                                           + angleDist * aCoeff
                                           + distSq * dCoeff
                                cost = cost / pri
    
                                table.insert(results, { x = bx, y = by, z = bz, cost = cost, blockName = block.name })
                            end
                        end
                    end
                end
            end
        end
    
        -- Sort by cost (lowest first)
        table.sort(results, function(a, b) return a.cost < b.cost end)
        return results
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- BLOCK MINER STATE MACHINE (1:1 BlockMiner.java + all states)
    -- ═══════════════════════════════════════════════════════════════
    local BlockMiner = {
        enabled = false,
        error = "NONE",  -- NONE, NOT_ENOUGH_BLOCKS, NO_TOOLS_AVAILABLE, NO_POINTS_FOUND, NO_TARGET_BLOCKS, NO_PICKAXE_ABILITY
        state = "IDLE",  -- IDLE, STARTING, CHOOSING, ROTATING, BREAKING, APPLY_ABILITY
        priorityMap = {},
        miningSpeed = 0,
        pickaxeAbility = "NONE",  -- NONE, PICKOBULUS, MINING_SPEED_BOOST
        pickaxeAbilityState = "AVAILABLE",  -- AVAILABLE, UNAVAILABLE
        targetBlock = nil,  -- {x,y,z,blockName}
        targetBlockType = nil,
        waitThreshold = 5000,
        _retryAbility = 0,
        _breakAttemptTicks = 0,
        _miningTimeTicks = 0,
        _choosingTimer = Clock.new(),
        _abilityTimer1 = Clock.new(),
        _abilityTimer2 = Clock.new(),
        _lookAwayTimer = Clock.new(),
        _wasLookingAway = false,
        _config = {},
    }
    
    function BlockMiner.start(blockTypes, miningSpeed, pickaxeAbility, priorities, miningTool, config)
        local bm = BlockMiner
    
        -- Validate
        if not blockTypes or #blockTypes == 0 then
            bm.error = "NO_TARGET_BLOCKS"
            return
        end
    
        -- Hold mining tool
        if miningTool and miningTool ~= "" then
            local held = false
            local inv = player.getInventory()
            for slot = 0, 8 do
                local item = inv.getHotbarItem(slot)
                if item and item.name and item.name:find(miningTool) then
                    inv.setSelectedSlot(slot)
                    held = true
                    break
                end
            end
            if not held then
                bm.error = "NO_TOOLS_AVAILABLE"
                return
            end
        end
    
        bm.priorityMap = buildPriorityMap(blockTypes, priorities)
        bm.miningSpeed = math.max(1, miningSpeed - 200)  -- base adjustment (exact MightyMiner)
        bm.pickaxeAbility = pickaxeAbility or "NONE"
        bm.pickaxeAbilityState = "AVAILABLE"
        bm._retryAbility = 0
        bm._config = config or {}
        bm.error = "NONE"
        bm.enabled = true
        bm.targetBlock = nil
        bm.state = "STARTING"
    end
    
    function BlockMiner.stop()
        local bm = BlockMiner
        bm.enabled = false
        bm.state = "IDLE"
        bm.targetBlock = nil
        input.setPressedAttack(false)
        input.setPressedForward(false)
        input.setPressedSneak(false)
        RotationHandler.stop()
    end
    
    function BlockMiner.onChat(msg)
        local bm = BlockMiner
        local lower = msg:lower()
        if lower:find("is now available!") then
            bm.pickaxeAbilityState = "AVAILABLE"
        end
        if lower:find("you used your") or lower:find("your pickaxe ability is on cooldown") then
            bm.pickaxeAbilityState = "UNAVAILABLE"
        end
    end
    
    function BlockMiner.onTick()
        local bm = BlockMiner
        if not bm.enabled then return end
    
        -- Retry abort (exact MightyMiner: 4 retries)
        if bm._retryAbility >= 4 then
            bm.error = "NO_PICKAXE_ABILITY"
            bm.stop()
            return
        end
    
        -- STATE MACHINE
        if bm.state == "STARTING" then
            bm._onStarting()
        elseif bm.state == "CHOOSING" then
            bm._onChoosing()
        elseif bm.state == "BREAKING" then
            bm._onBreaking()
        elseif bm.state == "APPLY_ABILITY" then
            bm._onApplyAbility()
        end
    end
    
    -- ── STARTING STATE (1:1 StartingState.java) ──
    function BlockMiner._onStarting()
        local bm = BlockMiner
        local prevState = bm._prevState
        bm._prevState = "STARTING"
    
        if bm.pickaxeAbility ~= "NONE" and bm.pickaxeAbilityState == "AVAILABLE" then
            -- Track retry pattern
            if prevState == "APPLY_ABILITY" then bm._retryAbility = bm._retryAbility + 1
            else bm._retryAbility = 0 end
            bm.state = "APPLY_ABILITY"
            bm._abilityTimer1:reset()
            bm._abilityTimer2:reset()
            bm._abilityTimer1:schedule(200)
            input.setPressedAttack(false)
        else
            if prevState == "STARTING" then bm._retryAbility = bm._retryAbility + 1
            else bm._retryAbility = 0 end
            bm.state = "CHOOSING"
            bm._choosingTimer:reset()
        end
    end
    
    -- ── CHOOSING STATE (1:1 ChoosingBlockState.java) ──
    function BlockMiner._onChoosing()
        local bm = BlockMiner
        local blocks = findMineableBlocks(bm.priorityMap, bm.miningSpeed, bm.targetBlock, bm._config)
    
        if #blocks == 0 then
            if not bm._choosingTimer:isScheduled() then
                bm._choosingTimer:schedule(bm.waitThreshold)
            end
            if bm._choosingTimer:isScheduled() and bm._choosingTimer:passed() then
                bm.error = "NOT_ENOUGH_BLOCKS"
                bm.stop()
            end
            return
        end
    
        -- Select best block
        bm.targetBlock = blocks[1]
        bm.targetBlockType = blocks[1].blockName
    
        -- Transition to BREAKING
        bm.state = "BREAKING"
        bm._breakAttemptTicks = 0
        bm._wasLookingAway = false
        bm._miningTimeTicks = getMiningTime(bm.targetBlockType, bm.miningSpeed, bm._config.tickOffset)
    
        -- Start rotation to target (exact MightyMiner BreakingState.initializeRotation)
        RotationHandler.stop()
        local rot = AngleUtil.getRotationToBlock(bm.targetBlock.x, bm.targetBlock.y, bm.targetBlock.z)
        local rotTime = bm._config.rotationTime or 400
        rotTime = rotTime + math.random(-50, 50)  -- randomize (humanize)
        RotationHandler.easeTo(rot.yaw, rot.pitch, rotTime, "SERVER", false, nil)
    end
    
    -- ── BREAKING STATE (1:1 BreakingState.java) ──
    function BlockMiner._onBreaking()
        local bm = BlockMiner
        local tb = bm.targetBlock
        if not tb then bm.state = "STARTING"; return end
    
        -- Hold attack
        input.setPressedAttack(true)
    
        -- Failsafe: stuck too long
        bm._breakAttemptTicks = bm._breakAttemptTicks + 1
        if bm._breakAttemptTicks > bm._miningTimeTicks + 40 then
            bm.state = "STARTING"
            bm._prevState = "BREAKING"
            input.setPressedAttack(false)
            return
        end
    
        -- Check if block changed (broken)
        local currentBlock = world.getBlock(tb.x, tb.y, tb.z)
        if not currentBlock or currentBlock.name ~= bm.targetBlockType then
            -- Block broken! Go back to starting
            input.setPressedAttack(false)
            bm.state = "STARTING"
            bm._prevState = "BREAKING"
            return
        end
    end
    
    -- ── APPLY ABILITY STATE (1:1 ApplyAbilityState.java) ──
    function BlockMiner._onApplyAbility()
        local bm = BlockMiner
    
        -- Phase 1: wait 200ms then right-click
        if bm._abilityTimer1:isScheduled() and bm._abilityTimer1:passed() then
            bm._abilityTimer1:reset()
            bm._abilityTimer2:schedule(200)
            input.setPressedUseItem(true)
            -- Release after 1 tick
            threads.startThread("ability_release", function()
                threads.yield(50)
                input.setPressedUseItem(false)
            end)
        end
    
        -- Phase 2: wait 200ms then go to starting
        if bm._abilityTimer2:isScheduled() and bm._abilityTimer2:passed() then
            bm._abilityTimer2:reset()
            bm._prevState = "APPLY_ABILITY"
            bm.state = "STARTING"
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- EXPORTS
    -- ═══════════════════════════════════════════════════════════════
    return {
        MineableBlock = MineableBlock,
        BlockStrength = BlockStrength,
        getBlockStrength = getBlockStrength,
        getMiningTime = getMiningTime,
        findMineableBlocks = findMineableBlocks,
        buildPriorityMap = buildPriorityMap,
        BlockMiner = BlockMiner,
    }
    
end

__fsm_preload["fivesawMiner/utils"] = function()
    -- ================================================================
    -- FiveSaw Miner / utils.lua
    -- Utilities: CommissionUtil, InventoryUtil, FailsafeManager
    -- 1:1 port of MightyMiner Java utilities
    -- ================================================================
    
    local core = __fsm_require("fivesawMiner/core")
    local Clock = core.Clock
    local AngleUtil = core.AngleUtil
    
    -- ═══════════════════════════════════════════════════════════════
    -- COMMISSION ENUM (1:1 Commission.java)
    -- ═══════════════════════════════════════════════════════════════
    local Commission = {
        -- Mining commissions
        MITHRIL_MINER = "Mithril Miner",
        TITANIUM_MINER = "Titanium Miner",
        UPPER_MINES_MITHRIL = "Upper Mines Mithril",
        ROYAL_MINES_MITHRIL = "Royal Mines Mithril",
        CLIFFSIDE_MITHRIL = "Cliffside Veins Mithril",
        RAMPARTS_MITHRIL = "Rampart's Quarry Mithril",
        LAVA_SPRINGS_MITHRIL = "Lava Springs Mithril",
        -- Slayer commissions
        GOBLIN_SLAYER = "Goblin Slayer",
        GLACITE_WALKER_SLAYER = "Glacite Walker Slayer",
        MINES_SLAYER = "Mines Slayer",
        -- Glacite
        GLACITE_MINER = "Glacite Miner",
        HARD_STONE_MINER = "Hard Stone Miner",
        UMBER_MINER = "Umber Collector",
        TUNGSTEN_MINER = "Tungsten Collector",
        -- Special
        COMMISSION_CLAIM = "CLAIM",
    }
    
    -- Commission name lookup (tablist text → commission key)
    local CommissionByName = {}
    for k, v in pairs(Commission) do CommissionByName[v] = k end
    
    -- Which commissions are "best" (mining > slayer, then alphabetical)
    local CommissionPriority = {
        MITHRIL_MINER = 10, TITANIUM_MINER = 9,
        UPPER_MINES_MITHRIL = 8, ROYAL_MINES_MITHRIL = 8,
        CLIFFSIDE_MITHRIL = 8, RAMPARTS_MITHRIL = 8,
        LAVA_SPRINGS_MITHRIL = 8,
        GLACITE_MINER = 7, HARD_STONE_MINER = 6,
        UMBER_MINER = 5, TUNGSTEN_MINER = 5,
        GOBLIN_SLAYER = 3, GLACITE_WALKER_SLAYER = 3, MINES_SLAYER = 3,
        COMMISSION_CLAIM = 100,
    }
    
    -- Slayer mob names (1:1 CommissionUtil.java)
    local SlayerMobs = {
        GOBLIN_SLAYER = { "Goblin", "Knifethrower", "Fireslinger" },
        MINES_SLAYER = { "Goblin", "Knifethrower", "Fireslinger", "Glacite Walker" },
        GLACITE_WALKER_SLAYER = { "Glacite Walker" },
    }
    
    -- ═══════════════════════════════════════════════════════════════
    -- EMISSARY LOCATIONS (1:1 CommissionUtil.java emissaries list)
    -- ═══════════════════════════════════════════════════════════════
    local Emissaries = {
        { name = "Ceanna",  x = 42.50,  y = 134.50, z = 22.50 },
        { name = "Carlton", x = -72.50, y = 153.00, z = -10.50 },
        { name = "Wilson",  x = 171.50, y = 150.00, z = 31.50 },
        { name = "Lilith",  x = 58.50,  y = 198.00, z = -8.50 },
        { name = "Fraiser", x = -132.50,y = 174.00, z = -50.50 },
    }
    
    -- ═══════════════════════════════════════════════════════════════
    -- COMMISSION UTIL (1:1 CommissionUtil.java)
    -- ═══════════════════════════════════════════════════════════════
    local CommissionUtil = {}
    
    --- Parse commissions from tablist
    function CommissionUtil.getCurrentCommissions()
        if not player then return {} end
        local tab = player.getTabList and player.getTabList() or {}
        local comms = {}
        local foundHeader = false
    
        for _, line in ipairs(tab) do
            local clean = line:gsub("§.", ""):match("^%s*(.-)%s*$")
            if not foundHeader then
                if clean == "Commissions:" then foundHeader = true end
            else
                if clean == "" then break end
                if clean:find("DONE") then
                    return { "COMMISSION_CLAIM" }
                end
                local commName = clean:match("^(.-):%s")
                if commName then
                    for k, v in pairs(Commission) do
                        if commName:find(v, 1, true) then
                            table.insert(comms, k)
                            break
                        end
                    end
                end
            end
        end
    
        -- Sort by priority (best first)
        table.sort(comms, function(a, b)
            return (CommissionPriority[a] or 0) > (CommissionPriority[b] or 0)
        end)
        return comms
    end
    
    --- Get closest emissary position to player
    function CommissionUtil.getClosestEmissary()
        local pos = player.getPos()
        local bestDist = math.huge
        local best = nil
        for _, e in ipairs(Emissaries) do
            local dx = pos.x - e.x
            local dy = pos.y - e.y
            local dz = pos.z - e.z
            local d = dx*dx + dy*dy + dz*dz
            if d < bestDist then
                bestDist = d
                best = e
            end
        end
        return best
    end
    
    --- Get mob names for a slayer commission
    function CommissionUtil.getMobsForCommission(commKey)
        return SlayerMobs[commKey] or {}
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- INVENTORY UTIL (1:1 InventoryUtil.java subset)
    -- ═══════════════════════════════════════════════════════════════
    local InventoryUtil = {}
    
    function InventoryUtil.holdItem(itemName)
        local inv = player.getInventory()
        for slot = 0, 8 do
            local item = inv.getHotbarItem(slot)
            if item and item.name and item.name:lower():find(itemName:lower(), 1, true) then
                inv.setSelectedSlot(slot)
                return true
            end
        end
        return false
    end
    
    function InventoryUtil.hasItem(itemName)
        local inv = player.getInventory()
        for slot = 0, 8 do
            local item = inv.getHotbarItem(slot)
            if item and item.name and item.name:lower():find(itemName:lower(), 1, true) then
                return true
            end
        end
        return false
    end
    
    function InventoryUtil.isInventoryEmpty()
        local inv = player.getInventory()
        for slot = 0, 35 do
            local item = inv.getItem(slot)
            if item and item.name then return false end
        end
        return true
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- AUTO MOB KILLER (1:1 AutoMobKiller subset)
    -- ═══════════════════════════════════════════════════════════════
    local AutoMobKiller = {
        enabled = false,
        mobNames = {},
        _attackTimer = Clock.new(),
        _target = nil,
        _ignoredMobs = {},
    }
    
    function AutoMobKiller.start(mobNames)
        AutoMobKiller.mobNames = mobNames or {}
        AutoMobKiller.enabled = true
        AutoMobKiller._ignoredMobs = {}
        AutoMobKiller._target = nil
    end
    
    function AutoMobKiller.stop()
        AutoMobKiller.enabled = false
        AutoMobKiller._target = nil
        input.setPressedAttack(false)
    end
    
    function AutoMobKiller.onTick()
        local amk = AutoMobKiller
        if not amk.enabled then return end
    
        -- Find closest mob matching name
        if not amk._target then
            local pos = player.getPos()
            local bestDist = 36  -- 6 block range
            local entities = world.getEntities and world.getEntities() or {}
            for _, ent in ipairs(entities) do
                if ent.isAlive and not amk._ignoredMobs[ent.id] then
                    for _, mobName in ipairs(amk.mobNames) do
                        if ent.name and ent.name:find(mobName, 1, true) then
                            local dx = pos.x - ent.x
                            local dz = pos.z - ent.z
                            local d = dx*dx + dz*dz
                            if d < bestDist then
                                bestDist = d
                                amk._target = ent
                            end
                        end
                    end
                end
            end
        end
    
        -- Attack target
        if amk._target then
            -- Rotate to mob
            local rot = AngleUtil.getRotationTo(
                { x = player.getPos().x, y = player.getPos().y + 1.62, z = player.getPos().z },
                { x = amk._target.x, y = amk._target.y + (amk._target.height or 1.7) * 0.85, z = amk._target.z }
            )
            core.RotationHandler.easeTo(rot.yaw, rot.pitch, 300, "SERVER", true, nil)
    
            -- Attack on cooldown
            if not amk._attackTimer:isScheduled() or amk._attackTimer:passed() then
                input.setPressedAttack(true)
                amk._attackTimer:schedule(600)  -- attack cooldown ~0.6s
                -- Release attack next tick
                threads.startThread("amk_release", function()
                    threads.yield(50)
                    input.setPressedAttack(false)
                end)
            end
    
            -- Check if mob dead
            if not amk._target.isAlive then
                amk._ignoredMobs[amk._target.id] = true
                amk._target = nil
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- FAILSAFE MANAGER (1:1 FailsafeManager.java — COMPLETE)
    -- Includes: Name Mention, World Change, Item Change, Profile,
    --           Knockback Detection, Disconnect/Auto-Reconnect
    -- ═══════════════════════════════════════════════════════════════
    local FailsafeManager = {
        enabled = false,
        triggered = nil,  -- active failsafe name
        _timer = Clock.new(),
        _config = {},
        _onTrigger = nil,  -- callback when failsafe triggers
        -- Knockback tracking (1:1 KnockbackFailsafe.java)
        _lastPos = nil,
        _knockbackThreshold = 3.0,  -- blocks moved in 1 tick = knockback
        _knockbackCooldown = Clock.new(),
        -- Disconnect tracking (1:1 DisconnectFailsafe.java)
        _disconnected = false,
        _reconnectAttempts = 0,
        _maxReconnectAttempts = 5,
        _reconnectTimer = Clock.new(),
    }
    
    function FailsafeManager.start(config, onTriggerCallback)
        local fm = FailsafeManager
        fm.enabled = true
        fm.triggered = nil
        fm._config = config or {}
        fm._onTrigger = onTriggerCallback
        fm._lastPos = nil
        fm._disconnected = false
        fm._reconnectAttempts = 0
        fm._knockbackCooldown:reset()
        fm._reconnectTimer:reset()
    end
    
    function FailsafeManager.stop()
        FailsafeManager.enabled = false
        FailsafeManager.triggered = nil
    end
    
    function FailsafeManager.onChat(msg)
        if not FailsafeManager.enabled then return end
        local clean = msg:gsub("§.", ""):lower()
    
        -- Name mention check (1:1 NameMentionFailsafe)
        local myName = player.getName and player.getName():lower() or ""
        if myName ~= "" and clean:find(myName, 1, true)
           and not clean:find("guild >") and not clean:find("from ") then
            FailsafeManager.triggered = "NAME_MENTION"
        end
    
        -- Teleport/warp detection (1:1 WorldChangeFailsafe)
        if clean:find("sending to server") or clean:find("warping you to") then
            FailsafeManager.triggered = "WORLD_CHANGE"
        end
    
        -- Profile swap (1:1 ProfileFailsafe)
        if clean:find("profile") and clean:find("selected") then
            FailsafeManager.triggered = "PROFILE_CHANGE"
        end
    
        -- Disconnect detection
        if clean:find("you were kicked") or clean:find("connection lost")
           or clean:find("timed out") or clean:find("disconnected") then
            FailsafeManager._disconnected = true
            FailsafeManager.triggered = "DISCONNECT"
        end
    end
    
    function FailsafeManager.onTick()
        local fm = FailsafeManager
        if not fm.enabled then return end
    
        -- Item change check (1:1 ItemChangeFailsafe — hotbar tool missing)
        if fm._config.miningTool and fm._config.miningTool ~= "" then
            if not InventoryUtil.hasItem(fm._config.miningTool) then
                fm.triggered = "ITEM_CHANGE"
            end
        end
    
        -- Knockback check (1:1 KnockbackFailsafe — position delta tracking)
        local pos = player.getPos()
        if pos and fm._lastPos then
            if not fm._knockbackCooldown:isScheduled() or fm._knockbackCooldown:passed() then
                local dx = pos.x - fm._lastPos.x
                local dy = pos.y - fm._lastPos.y
                local dz = pos.z - fm._lastPos.z
                local delta = math.sqrt(dx*dx + dy*dy + dz*dz)
                if delta > fm._knockbackThreshold then
                    fm.triggered = "KNOCKBACK"
                    fm._knockbackCooldown:schedule(5000)  -- 5s cooldown to avoid spam
                end
            end
        end
        if pos then
            fm._lastPos = { x = pos.x, y = pos.y, z = pos.z }
        end
    
        -- Disconnect auto-reconnect (1:1 DisconnectFailsafe)
        if fm._disconnected then
            if not fm._reconnectTimer:isScheduled() then
                fm._reconnectTimer:schedule(5000)  -- wait 5s before reconnect
            elseif fm._reconnectTimer:passed() then
                if fm._reconnectAttempts < fm._maxReconnectAttempts then
                    fm._reconnectAttempts = fm._reconnectAttempts + 1
                    player.addMessage("§c[FiveSaw] §eReconnect attempt " .. fm._reconnectAttempts .. "/" .. fm._maxReconnectAttempts)
                    -- Try to reconnect
                    if player.sendCommand then
                        player.sendCommand("play skyblock")
                    end
                    fm._reconnectTimer:schedule(10000)  -- wait 10s between attempts
                else
                    player.addMessage("§c[FiveSaw] §cMax reconnect attempts reached, stopping macro")
                    fm._disconnected = false
                    fm.triggered = "DISCONNECT_FAILED"
                end
            end
        end
    
        -- Bedrock check (1:1 BedrockCheckFailsafe.java)
        -- If surrounded by >10 bedrock blocks within radius 5, likely in void/wrong area
        if not fm.triggered then
            local bedrockCount = 0
            for bx = -5, 5, 3 do  -- sample every 3 for perf
                for by = -5, 5, 3 do
                    for bz = -5, 5, 3 do
                        local block = world.getBlock(
                            math.floor(pos.x) + bx,
                            math.floor(pos.y) + by,
                            math.floor(pos.z) + bz
                        )
                        if block and block.name == "minecraft:bedrock" then
                            bedrockCount = bedrockCount + 1
                        end
                        if bedrockCount >= 10 then
                            fm.triggered = "BEDROCK_SURROUND"
                            break
                        end
                    end
                    if fm.triggered then break end
                end
                if fm.triggered then break end
            end
        end
    
        -- Player proximity check (1:1 PlayerFailsafe.java)
        -- If a non-NPC player is within 3 blocks and staring at us for >1s, trigger
        if not fm.triggered and world.getEntities then
            local entities = world.getEntities()
            local myPos = player.getPos()
            for _, ent in ipairs(entities) do
                if ent.isPlayer and ent.name ~= (player.getName and player.getName() or "") then
                    local dx = myPos.x - ent.x
                    local dz = myPos.z - ent.z
                    local distSq = dx*dx + dz*dz
                    if distSq < 9 then  -- 3 block radius
                        -- Simple staring detection — check if they're facing us
                        -- (simplified from dot product in Java, since we don't have look vectors)
                        if not fm._playerNearTimer then fm._playerNearTimer = Clock.new() end
                        if not fm._playerNearTimer:isScheduled() then
                            fm._playerNearTimer:schedule(3000)  -- 3s threshold (conservative)
                        elseif fm._playerNearTimer:passed() then
                            fm.triggered = "PLAYER_NEARBY"
                            fm._playerNearTimer:reset()
                        end
                        break
                    else
                        if fm._playerNearTimer then fm._playerNearTimer:reset() end
                    end
                end
            end
        end
    
        -- React if triggered
        if fm.triggered then
            if fm._onTrigger then
                fm._onTrigger(fm.triggered)
                fm.triggered = nil  -- clear after handling (prevent infinite loop)
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- AUTO WARP (1:1 AutoWarp.java)
    -- ═══════════════════════════════════════════════════════════════
    local AutoWarp = {}
    
    function AutoWarp.warpTo(destination, callback)
        player.sendCommand("warp " .. destination)
        if callback then
            threads.startThread("warp_wait", function()
                threads.yield(3000)
                callback()
            end)
        end
    end
    
    function AutoWarp.lobbySwap(callback)
        player.sendCommand("l")
        threads.startThread("lobby_swap", function()
            threads.yield(2000)
            player.sendCommand("play skyblock")
            threads.yield(5000)
            if callback then callback() end
        end)
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- MINING SPEED AUTO-DETECTION (1:1 MiningSpeedRetrievalTask.java)
    -- Reads mining speed from item lore in hotbar
    -- Falls back to manual config value if detection fails
    -- ═══════════════════════════════════════════════════════════════
    local MiningSpeedDetector = {}
    
    --- Auto-detect mining speed from the player's pickaxe/drill lore
    --- Looks for "Mining Speed: +XXX" in item lore
    --- @param toolName string name of tool to check
    --- @return number|nil detected speed or nil
    function MiningSpeedDetector.detect(toolName)
        local inv = player.getInventory()
        for slot = 0, 8 do
            local item = inv.getHotbarItem(slot)
            if item and item.name then
                local nameMatch = not toolName or toolName == "" or item.name:lower():find(toolName:lower(), 1, true)
                if nameMatch and item.lore then
                    for _, loreLine in ipairs(item.lore) do
                        local clean = loreLine:gsub("§.", "")
                        -- Match "Mining Speed: +1234" or "⸕ Mining Speed: +1234"
                        local speed = clean:match("Mining Speed:%s*%+(%d+)")
                        if speed then
                            return tonumber(speed)
                        end
                    end
                end
            end
        end
        return nil
    end
    
    --- Auto-detect pickaxe ability from item lore
    --- @param toolName string name of tool to check
    --- @return string "NONE", "MINING_SPEED_BOOST", or "PICKOBULUS"
    function MiningSpeedDetector.detectAbility(toolName)
        local inv = player.getInventory()
        for slot = 0, 8 do
            local item = inv.getHotbarItem(slot)
            if item and item.name then
                local nameMatch = not toolName or toolName == "" or item.name:lower():find(toolName:lower(), 1, true)
                if nameMatch and item.lore then
                    for _, loreLine in ipairs(item.lore) do
                        local clean = loreLine:gsub("§.", ""):lower()
                        if clean:find("pickobulus") then return "PICKOBULUS" end
                        if clean:find("mining speed boost") or clean:find("vein seeker")
                           or clean:find("maniac miner") then
                            return "MINING_SPEED_BOOST"
                        end
                    end
                end
            end
        end
        return "NONE"
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- NPC INTERACTION (emissary GUI clicking)
    -- ═══════════════════════════════════════════════════════════════
    local NPCInteraction = {}
    
    --- Interact with the closest entity matching name (right-click)
    --- @param entityName string partial name match
    --- @param callback function called after interaction
    function NPCInteraction.interactWithNPC(entityName, callback)
        threads.startThread("npc_interact", function()
            -- Look for NPC entity nearby
            local pos = player.getPos()
            local entities = world.getEntities and world.getEntities() or {}
            local target = nil
            local bestDist = 25  -- 5 block range
    
            for _, ent in ipairs(entities) do
                if ent.name and ent.name:find(entityName, 1, true) then
                    local dx = pos.x - ent.x
                    local dz = pos.z - ent.z
                    local d = dx*dx + dz*dz
                    if d < bestDist then
                        bestDist = d
                        target = ent
                    end
                end
            end
    
            if not target then
                player.addMessage("§c[FiveSaw] NPC '" .. entityName .. "' not found nearby")
                if callback then callback(false) end
                return
            end
    
            -- Rotate to NPC
            local rot = core.AngleUtil.getRotationTo(
                { x = pos.x, y = pos.y + 1.62, z = pos.z },
                { x = target.x, y = target.y + 1.5, z = target.z }
            )
            core.RotationHandler.easeTo(rot.yaw, rot.pitch, 300, "SERVER", false, nil)
            threads.yield(400)
    
            -- Right click to interact
            input.setPressedUseItem(true)
            threads.yield(100)
            input.setPressedUseItem(false)
            threads.yield(2000)  -- wait for GUI to open
    
            -- Attempt to click commission claim slot in GUI
            -- The GUI should have a "Completed" item we need to click
            local inv = player.getInventory()
            if inv.getContainerItem then
                for slot = 0, 53 do
                    local item = inv.getContainerItem(slot)
                    if item and item.lore then
                        for _, loreLine in ipairs(item.lore) do
                            local clean = loreLine:gsub("§.", ""):lower()
                            if clean:find("completed") or clean:find("click to claim") then
                                inv.clickContainerSlot(slot)
                                threads.yield(500)
                                break
                            end
                        end
                    end
                end
            end
    
            -- Close GUI
            threads.yield(500)
            if player.closeScreen then player.closeScreen() end
    
            if callback then callback(true) end
        end)
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- GLACITE VEIN SCANNER
    -- Scans surrounding area for glacite ore concentrations
    -- ═══════════════════════════════════════════════════════════════
    local GlaciteVeinScanner = {}
    
    local GLACITE_BLOCKS = {
        ["minecraft:packed_ice"] = true,
        ["minecraft:blue_ice"] = true,
    }
    
    --- Scan for the densest glacite vein within range
    --- @param range number scan radius (default 30)
    --- @return table|nil {x,y,z} center of densest vein, or nil
    function GlaciteVeinScanner.findBestVein(range)
        range = range or 30
        local pos = player.getPos()
        local cx, cy, cz = math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)
    
        -- Grid-based density scan (sample every 4 blocks for speed)
        local bestDensity = 0
        local bestPos = nil
        local step = 4
    
        for dx = -range, range, step do
            for dy = -10, 10, step do
                for dz = -range, range, step do
                    local sx, sy, sz = cx + dx, cy + dy, cz + dz
                    local density = 0
    
                    -- Count glacite blocks in 5x5x5 cube around this point
                    for ix = -2, 2 do
                        for iy = -2, 2 do
                            for iz = -2, 2 do
                                local block = world.getBlock(sx + ix, sy + iy, sz + iz)
                                if block and GLACITE_BLOCKS[block.name] then
                                    density = density + 1
                                end
                            end
                        end
                    end
    
                    -- Penalize distance
                    local distSq = dx*dx + dy*dy + dz*dz
                    local score = density - (distSq / (range * range)) * 5
    
                    if score > bestDensity and density >= 3 then
                        bestDensity = score
                        bestPos = { x = sx, y = sy, z = sz }
                    end
                end
            end
        end
    
        return bestPos
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- AUTO DRILL REFUEL (1:1 AutoDrillRefuel.java)
    -- Detects when drill fuel is low and triggers refuel sequence
    -- ═══════════════════════════════════════════════════════════════
    local AutoDrillRefuel = {
        enabled = false,
        error = "NONE",  -- NONE, NO_DRILL, NO_FUEL, NO_ABIPHONE
        state = "IDLE",  -- IDLE, STARTING, ABIPHONE, GREATFORGE, REFUELING
        drillName = "",
        fuelType = "Volta",  -- "Volta" or "Oil Barrel"
        _timer = Clock.new(),
        _fuelThreshold = 1000,  -- refuel when below this
    }
    
    function AutoDrillRefuel.start(drillName, fuelType, threshold)
        local adr = AutoDrillRefuel
        adr.drillName = drillName or ""
        adr.fuelType = fuelType or "Volta"
        adr._fuelThreshold = threshold or 1000
        adr.error = "NONE"
        adr.enabled = true
        adr.state = "STARTING"
    end
    
    function AutoDrillRefuel.stop()
        AutoDrillRefuel.enabled = false
        AutoDrillRefuel.state = "IDLE"
    end
    
    --- Check if drill needs fuel by reading lore
    function AutoDrillRefuel.needsFuel()
        local inv = player.getInventory()
        for slot = 0, 8 do
            local item = inv.getHotbarItem(slot)
            if item and item.name and item.lore then
                local isDrill = AutoDrillRefuel.drillName == "" or
                    item.name:lower():find(AutoDrillRefuel.drillName:lower(), 1, true)
                if isDrill then
                    for _, loreLine in ipairs(item.lore) do
                        local clean = loreLine:gsub("§.", "")
                        local fuel = clean:match("Fuel:%s*(%d[%d,]*)")
                        if fuel then
                            local fuelNum = tonumber(fuel:gsub(",", "")) or 0
                            return fuelNum < AutoDrillRefuel._fuelThreshold
                        end
                    end
                end
            end
        end
        return false
    end
    
    function AutoDrillRefuel.onTick()
        local adr = AutoDrillRefuel
        if not adr.enabled then return end
    
        if adr.state == "STARTING" then
            -- Check for Abiphone
            if not InventoryUtil.hasItem("Abiphone") then
                adr.error = "NO_ABIPHONE"
                adr.stop()
                return
            end
            if not adr.needsFuel() then
                adr.stop()
                return
            end
            -- Open Abiphone
            InventoryUtil.holdItem("Abiphone")
            input.setPressedUseItem(true)
            threads.startThread("drill_refuel", function()
                threads.yield(100)
                input.setPressedUseItem(false)
                threads.yield(2000)
                -- Search for Greatforge contact in GUI and click
                local inv = player.getInventory()
                if inv.getContainerItem then
                    for s = 0, 53 do
                        local item = inv.getContainerItem(s)
                        if item and item.name and item.name:find("Greatforge", 1, true) then
                            inv.clickContainerSlot(s)
                            threads.yield(2000)
                            -- Now click "Refuel Drill"
                            for s2 = 0, 53 do
                                local item2 = inv.getContainerItem(s2)
                                if item2 and item2.name and item2.name:lower():find("refuel", 1, true) then
                                    inv.clickContainerSlot(s2)
                                    threads.yield(1000)
                                    break
                                end
                            end
                            break
                        end
                    end
                end
                threads.yield(500)
                if player.closeScreen then player.closeScreen() end
                adr.stop()
                player.addMessage("§a[FiveSaw] Drill refueled")
            end)
            adr.state = "REFUELING"
    
        elseif adr.state == "REFUELING" then
            -- Wait for thread to complete
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- EXPORTS
    -- ═══════════════════════════════════════════════════════════════
    return {
        Commission = Commission,
        CommissionPriority = CommissionPriority,
        CommissionUtil = CommissionUtil,
        Emissaries = Emissaries,
        InventoryUtil = InventoryUtil,
        AutoMobKiller = AutoMobKiller,
        FailsafeManager = FailsafeManager,
        AutoWarp = AutoWarp,
        SlayerMobs = SlayerMobs,
        MiningSpeedDetector = MiningSpeedDetector,
        NPCInteraction = NPCInteraction,
        GlaciteVeinScanner = GlaciteVeinScanner,
        AutoDrillRefuel = AutoDrillRefuel,
    }
    
end

__fsm_preload["fivesawMiner/route_data"] = function()
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
    
end

__fsm_preload["fivesawMiner/macros"] = function()
    -- ================================================================
    -- FiveSaw Miner / macros.lua
    -- All macro state machines: Mining, Commission, Glacial, Route
    -- 1:1 port of MightyMiner Java macros
    -- ================================================================
    
    local core = __fsm_require("fivesawMiner/core")
    local bm_mod = __fsm_require("fivesawMiner/block_miner")
    local utils = __fsm_require("fivesawMiner/utils")
    
    local MiningSpeedDetector = utils.MiningSpeedDetector
    local NPCInteraction = utils.NPCInteraction
    local GlaciteVeinScanner = utils.GlaciteVeinScanner
    
    local Clock = core.Clock
    local MacroBase = core.MacroBase
    local GameState = core.GameState
    local RotationHandler = core.RotationHandler
    local BlockMiner = bm_mod.BlockMiner
    local MineableBlock = bm_mod.MineableBlock
    local CommissionUtil = utils.CommissionUtil
    local InventoryUtil = utils.InventoryUtil
    local AutoMobKiller = utils.AutoMobKiller
    local FailsafeManager = utils.FailsafeManager
    local AutoWarp = utils.AutoWarp
    
    -- ═══════════════════════════════════════════════════════════════
    -- MINING MACRO (1:1 MiningMacro.java)
    -- Simple loop: Get stats → Start BlockMiner → Handle errors
    -- ═══════════════════════════════════════════════════════════════
    local MiningMacro = MacroBase.new("Mining Macro")
    MiningMacro._isMining = false
    MiningMacro._config = {}
    
    -- Ore type → block type mapping (1:1 MiningMacro.setBlocksToMineBasedOnOreType)
    local OreTypeBlocks = {
        [0] = { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL", "TITANIUM" },  -- Mithril
        [1] = { "DIAMOND" },
        [2] = { "EMERALD" },
        [3] = { "REDSTONE" },
        [4] = { "LAPIS" },
        [5] = { "GOLD" },
        [6] = { "IRON" },
        [7] = { "COAL" },
        [8] = { "GLACITE" },
        [9] = { "HARDSTONE" },
        [10] = { "UMBER" },
        [11] = { "TUNGSTEN" },
    }
    
    function MiningMacro:configure(config)
        self._config = config or {}
    end
    
    function MiningMacro:onEnable()
        self:log("Enabling")
        self._isMining = false
    end
    
    function MiningMacro:onDisable()
        self:log("Disabling")
        BlockMiner.stop()
        self._isMining = false
    end
    
    function MiningMacro:onPause() BlockMiner.stop(); self._isMining = false end
    function MiningMacro:onResume() self._isMining = false end
    
    function MiningMacro:onTick()
        if not self._enabled then return end
        local cfg = self._config
    
        if not self._isMining then
            -- Auto-detect mining speed if enabled (1:1 MiningSpeedRetrievalTask)
            local speed = cfg.miningSpeed or 1500
            if cfg.autoDetectSpeed then
                local detected = MiningSpeedDetector.detect(cfg.miningTool)
                if detected then
                    speed = detected
                    self:log("Auto-detected mining speed: " .. speed)
                end
            end
            -- Auto-detect pickaxe ability
            if cfg.usePickaxeAbility and (not cfg.pickaxeAbility or cfg.pickaxeAbility == "NONE") then
                local ab = MiningSpeedDetector.detectAbility(cfg.miningTool)
                if ab ~= "NONE" then
                    cfg.pickaxeAbility = ab
                    self:log("Auto-detected ability: " .. ab)
                end
            end
    
            local oreType = cfg.oreType or 0
            local blockTypes = OreTypeBlocks[oreType] or OreTypeBlocks[0]
            local priorities = cfg.priorities or {}
            -- Default priorities
            if #priorities == 0 then
                if oreType == 0 then
                    priorities = {
                        cfg.mineGrayMithril and 1 or 0,
                        cfg.mineGreenMithril and 1 or 0,
                        cfg.mineBlueMithril and 1 or 0,
                        cfg.mineTitanium and 10 or 0,
                    }
                else
                    for i = 1, #blockTypes do priorities[i] = 1 end
                end
            end
    
            BlockMiner.start(blockTypes, speed, cfg.pickaxeAbility or "NONE",
                priorities, cfg.miningTool or "", cfg)
            BlockMiner.waitThreshold = (cfg.oreRespawnWait or 5) * 1000
            self._isMining = true
            self:log("Started mining with speed: " .. speed)
        end
    
        -- Handle BlockMiner errors (1:1 MiningMacro.handleMining)
        local err = BlockMiner.error
        if err == "NO_POINTS_FOUND" then
            self:log("Block cannot be mined, restarting")
            self._isMining = false
        elseif err == "NO_TARGET_BLOCKS" then
            self:disable("Please set at least one type of target block in configs!")
        elseif err == "NOT_ENOUGH_BLOCKS" then
            self:disable("Not enough blocks nearby! Move to a new vein")
        elseif err == "NO_TOOLS_AVAILABLE" then
            self:disable("Cannot find tools in hotbar!")
        elseif err == "NO_PICKAXE_ABILITY" then
            self:disable("Cannot use pickaxe ability! Enable chat messages or disable in config.")
        end
    end
    
    function MiningMacro:onChat(msg) BlockMiner.onChat(msg) end
    function MiningMacro:getNecessaryItems() return { self._config.miningTool or "Pickaxe" } end
    
    -- ═══════════════════════════════════════════════════════════════
    -- COMMISSION MACRO (1:1 CommissionMacro.java + all states)
    -- States: STARTING → GETTING_STATS → MINING → CLAIMING → WARPING → NEW_LOBBY
    -- ═══════════════════════════════════════════════════════════════
    local CommissionMacro = MacroBase.new("Commission Macro")
    CommissionMacro._state = "STARTING"
    CommissionMacro._commissionCount = 0
    CommissionMacro._currentCommission = nil
    CommissionMacro._config = {}
    CommissionMacro._isMining = false
    CommissionMacro._claimTimer = Clock.new()
    CommissionMacro._warpTimer = Clock.new()
    CommissionMacro._startTimer = Clock.new()
    
    function CommissionMacro:configure(config)
        self._config = config or {}
    end
    
    function CommissionMacro:onEnable()
        self._state = "STARTING"
        self._startTimer:schedule(1000)
        self._isMining = false
        self:log("Enabled")
    end
    
    function CommissionMacro:onDisable()
        BlockMiner.stop()
        AutoMobKiller.stop()
        self._isMining = false
        self:log("Disabled")
    end
    
    function CommissionMacro:onPause()
        BlockMiner.stop()
        AutoMobKiller.stop()
    end
    
    function CommissionMacro:onResume()
        self._isMining = false
    end
    
    function CommissionMacro:onChat(msg)
        if not self._enabled then return end
        BlockMiner.onChat(msg)
    
        local clean = msg:gsub("§.", "")
        if clean:find("Commission Complete") then
            self._commissionCount = self._commissionCount + 1
            self:log("Commission Complete! Total: " .. self._commissionCount)
            self._isMining = false
            self._state = "CLAIMING"
            self._claimTimer:schedule(500)
        end
    end
    
    function CommissionMacro:onTick()
        if not self._enabled then return end
        if self:isTimerRunning() then return end
    
        -- Update commissions from tablist
        local comms = CommissionUtil.getCurrentCommissions()
        if #comms > 0 and self._state ~= "WARPING" and self._state ~= "NEW_LOBBY" then
            self._currentCommission = comms[1]
        end
    
        -- ── STATE MACHINE ──
        if self._state == "STARTING" then
            self:_onStarting()
        elseif self._state == "MINING" then
            self:_onMining()
        elseif self._state == "SLAYING" then
            self:_onSlaying()
        elseif self._state == "CLAIMING" then
            self:_onClaiming()
        elseif self._state == "WARPING" then
            self:_onWarping()
        elseif self._state == "NEW_LOBBY" then
            self:_onNewLobby()
        end
    end
    
    -- ── Commission States ──
    
    function CommissionMacro:_onStarting()
        if not self._startTimer:passed() then return end
    
        -- Validate inventory
        local cfg = self._config
        if cfg.miningTool and not InventoryUtil.hasItem(cfg.miningTool) then
            self:disable("Mining tool '" .. cfg.miningTool .. "' not found!")
            return
        end
    
        -- Check current commission
        if not self._currentCommission then
            self:log("Waiting for commission data...")
            return
        end
    
        if self._currentCommission == "COMMISSION_CLAIM" then
            self._state = "CLAIMING"
            self._claimTimer:schedule(500)
            return
        end
    
        -- Check if slayer commission
        local slayerMobs = utils.SlayerMobs[self._currentCommission]
        if slayerMobs then
            self:log("Slayer commission: " .. self._currentCommission)
            AutoMobKiller.start(slayerMobs)
            self._state = "SLAYING"
            return
        end
    
        -- Mining commission — determine blocks
        local blockTypes, priorities = self:_getBlocksForCommission(self._currentCommission)
        if blockTypes then
            BlockMiner.start(blockTypes, cfg.miningSpeed or 1500, cfg.pickaxeAbility or "NONE",
                priorities, cfg.miningTool or "", cfg)
            self._isMining = true
            self._state = "MINING"
            self:log("Mining for commission: " .. (self._currentCommission or "?"))
        else
            self:warn("Unknown commission type, defaulting to mithril")
            BlockMiner.start(
                { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL", "TITANIUM" },
                cfg.miningSpeed or 1500, cfg.pickaxeAbility or "NONE",
                { 1, 1, 1, 10 }, cfg.miningTool or "", cfg
            )
            self._isMining = true
            self._state = "MINING"
        end
    end
    
    function CommissionMacro:_getBlocksForCommission(comm)
        local map = {
            MITHRIL_MINER = { { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL" }, { 1, 1, 1 } },
            TITANIUM_MINER = { { "TITANIUM" }, { 1 } },
            UPPER_MINES_MITHRIL = { { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL" }, { 1, 1, 1 } },
            ROYAL_MINES_MITHRIL = { { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL" }, { 1, 1, 1 } },
            CLIFFSIDE_MITHRIL = { { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL" }, { 1, 1, 1 } },
            RAMPARTS_MITHRIL = { { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL" }, { 1, 1, 1 } },
            LAVA_SPRINGS_MITHRIL = { { "GRAY_MITHRIL", "GREEN_MITHRIL", "BLUE_MITHRIL" }, { 1, 1, 1 } },
            GLACITE_MINER = { { "GLACITE" }, { 1 } },
            HARD_STONE_MINER = { { "HARDSTONE" }, { 1 } },
            UMBER_MINER = { { "UMBER" }, { 1 } },
            TUNGSTEN_MINER = { { "TUNGSTEN" }, { 1 } },
        }
        local entry = map[comm]
        if entry then return entry[1], entry[2] end
        return nil, nil
    end
    
    function CommissionMacro:_onMining()
        -- Handle BlockMiner errors
        local err = BlockMiner.error
        if err ~= "NONE" then
            self:warn("BlockMiner error: " .. err)
            if err == "NOT_ENOUGH_BLOCKS" then
                self:log("No blocks, restarting search...")
                self._isMining = false
                self._state = "STARTING"
                self._startTimer:schedule(2000)
            elseif err == "NO_TOOLS_AVAILABLE" then
                self:disable("Mining tool not found!")
            end
        end
    end
    
    function CommissionMacro:_onSlaying()
        AutoMobKiller.onTick()
        -- Commission complete detected via onChat
    end
    
    function CommissionMacro:_onClaiming()
        if not self._claimTimer:passed() then return end
    
        local cfg = self._config
        BlockMiner.stop()
        AutoMobKiller.stop()
    
        if cfg.claimMethod == 1 then
            -- Royal Pigeon method
            self:log("Using Royal Pigeon to claim")
            if InventoryUtil.holdItem("Royal Pigeon") then
                input.setPressedUseItem(true)
                threads.startThread("pigeon_claim", function()
                    threads.yield(100)
                    input.setPressedUseItem(false)
                    threads.yield(3000)
                    -- After pigeon GUI, go back to starting
                    self._state = "STARTING"
                    self._startTimer:schedule(2000)
                    self._isMining = false
                end)
            else
                self:warn("Royal Pigeon not found, going to emissary")
                self:_goToEmissary()
            end
        else
            -- Emissary method
            self:_goToEmissary()
        end
    end
    
    function CommissionMacro:_goToEmissary()
        local emissary = CommissionUtil.getClosestEmissary()
        if not emissary then
            self:error("Cannot find emissary!")
            self._state = "STARTING"
            self._startTimer:schedule(5000)
            return
        end
    
        self:log("Walking to emissary: " .. emissary.name)
        -- Use fivesawUtils pathfinding
        local fivetone = require("fivesawUtils")
        if fivetone then
            fivetone.navigateTo(math.floor(emissary.x), math.floor(emissary.y), math.floor(emissary.z), function(success)
                if success then
                    self:log("Reached emissary, interacting...")
                    -- Use NPC interaction to open GUI and click claim slot
                    NPCInteraction.interactWithNPC(emissary.name, function(interacted)
                        if interacted then
                            self:log("Commission claimed via emissary")
                        else
                            self:warn("Failed to interact with emissary")
                        end
                        self._state = "STARTING"
                        self._startTimer:schedule(2000)
                        self._isMining = false
                    end)
                else
                    self:warn("Failed to reach emissary")
                    self._state = "STARTING"
                    self._startTimer:schedule(3000)
                end
            end)
        end
        self._state = "WARPING"  -- Wait while pathfinding
    end
    
    function CommissionMacro:_onWarping()
        -- Wait for pathfinding/warping to complete
        -- Transitions happen via callbacks
    end
    
    function CommissionMacro:_onNewLobby()
        AutoWarp.lobbySwap(function()
            self:log("New lobby joined, restarting")
            self._state = "STARTING"
            self._startTimer:schedule(5000)
        end)
        self._state = "WARPING"  -- prevent re-entry
    end
    
    function CommissionMacro:getNecessaryItems()
        local items = { self._config.miningTool or "Pickaxe" }
        if self._config.slayerWeapon then table.insert(items, self._config.slayerWeapon) end
        if self._config.claimMethod == 1 then table.insert(items, "Royal Pigeon") end
        return items
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- GLACIAL MACRO (1:1 GlacialMacro.java + states)
    -- States: STARTING → MINING → PATHFINDING → CLAIMING → TELEPORTING → NEW_LOBBY
    -- ═══════════════════════════════════════════════════════════════
    local GlacialMacro = MacroBase.new("Glacial Macro")
    GlacialMacro._state = "STARTING"
    GlacialMacro._config = {}
    GlacialMacro._isMining = false
    GlacialMacro._startTimer = Clock.new()
    
    function GlacialMacro:configure(config) self._config = config or {} end
    
    function GlacialMacro:onEnable()
        self._state = "STARTING"
        self._startTimer:schedule(1000)
        self._isMining = false
        self:log("Enabled")
    end
    
    function GlacialMacro:onDisable()
        BlockMiner.stop()
        self._isMining = false
    end
    
    function GlacialMacro:onChat(msg)
        if not self._enabled then return end
        BlockMiner.onChat(msg)
        local clean = msg:gsub("§.", "")
        if clean:find("Commission Complete") then
            self._state = "CLAIMING"
        end
    end
    
    function GlacialMacro:onTick()
        if not self._enabled then return end
        if self:isTimerRunning() then return end
    
        if self._state == "STARTING" then
            if not self._startTimer:passed() then return end
            local cfg = self._config
            BlockMiner.start(
                { "GLACITE", "HARDSTONE" },
                cfg.miningSpeed or 1500, cfg.pickaxeAbility or "NONE",
                { 5, 1 }, cfg.miningTool or "", cfg
            )
            self._isMining = true
            self._state = "MINING"
            self:log("Mining glacite veins")
    
        elseif self._state == "MINING" then
            local err = BlockMiner.error
            if err == "NOT_ENOUGH_BLOCKS" then
                self:log("No blocks, pathfinding to new vein...")
                self._state = "PATHFINDING"
            elseif err ~= "NONE" then
                self:warn("BlockMiner error: " .. err)
            end
    
        elseif self._state == "PATHFINDING" then
            -- Scan for nearby glacite vein concentrations
            local vein = GlaciteVeinScanner.findBestVein(30)
            if vein then
                self:log("Found glacite vein at " .. vein.x .. ", " .. vein.y .. ", " .. vein.z)
                local fivetone = require("fivesawUtils")
                if fivetone then
                    fivetone.navigateTo(vein.x, vein.y, vein.z, function(success)
                        if success then
                            self:log("Reached vein, resuming mining")
                            self._isMining = false
                            self._state = "STARTING"
                            self._startTimer:schedule(1000)
                        else
                            self:warn("Failed to reach vein")
                            self._isMining = false
                            self._state = "STARTING"
                            self._startTimer:schedule(5000)
                        end
                    end)
                    self._state = "WAITING_PATH"
                end
            else
                self:warn("No glacite veins found nearby")
                self._isMining = false
                self._state = "STARTING"
                self._startTimer:schedule(5000)
            end
    
        elseif self._state == "WAITING_PATH" then
            -- Wait for pathfinding callback (transitions happen in the callback)
    
        elseif self._state == "CLAIMING" then
            BlockMiner.stop()
            self:log("Commission done, claiming...")
            -- Use Royal Pigeon if available, else emissary
            local cfg = self._config
            if cfg.claimMethod == 1 and InventoryUtil.holdItem("Royal Pigeon") then
                input.setPressedUseItem(true)
                threads.startThread("glacial_pigeon", function()
                    threads.yield(100)
                    input.setPressedUseItem(false)
                    threads.yield(3000)
                    self._state = "STARTING"
                    self._startTimer:schedule(2000)
                    self._isMining = false
                end)
                self._state = "WAITING_PATH"  -- prevent re-entry
            else
                local emissary = CommissionUtil.getClosestEmissary()
                if emissary then
                    local fivetone = require("fivesawUtils")
                    if fivetone then
                        fivetone.navigateTo(math.floor(emissary.x), math.floor(emissary.y), math.floor(emissary.z), function(success)
                            if success then
                                NPCInteraction.interactWithNPC(emissary.name, function()
                                    self._state = "STARTING"
                                    self._startTimer:schedule(2000)
                                    self._isMining = false
                                end)
                            else
                                self._state = "STARTING"
                                self._startTimer:schedule(5000)
                            end
                        end)
                        self._state = "WAITING_PATH"
                    end
                else
                    self._state = "STARTING"
                    self._startTimer:schedule(5000)
                end
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- ROUTE MINER MACRO (1:1 RouteMinerMacro.java + states)
    -- States: STARTING → MOVING → MINING
    -- ═══════════════════════════════════════════════════════════════
    local RouteMinerMacro = MacroBase.new("Route Miner")
    RouteMinerMacro._state = "STARTING"
    RouteMinerMacro._config = {}
    RouteMinerMacro._currentWaypoint = 1
    RouteMinerMacro._route = {}
    RouteMinerMacro._isMining = false
    RouteMinerMacro._startTimer = Clock.new()
    
    function RouteMinerMacro:configure(config) self._config = config or {} end
    function RouteMinerMacro:setRoute(route) self._route = route or {} end
    
    function RouteMinerMacro:onEnable()
        self._state = "STARTING"
        self._currentWaypoint = 1
        self._isMining = false
        self._startTimer:schedule(1000)
        self:log("Enabled with " .. #self._route .. " waypoints")
    end
    
    function RouteMinerMacro:onDisable()
        BlockMiner.stop()
        self._isMining = false
    end
    
    function RouteMinerMacro:onChat(msg)
        if not self._enabled then return end
        BlockMiner.onChat(msg)
    end
    
    function RouteMinerMacro:onTick()
        if not self._enabled then return end
        if self:isTimerRunning() then return end
    
        if self._state == "STARTING" then
            if not self._startTimer:passed() then return end
            if #self._route == 0 then
                self:disable("No route set! Configure waypoints first.")
                return
            end
            self._state = "MOVING"
    
        elseif self._state == "MOVING" then
            local wp = self._route[self._currentWaypoint]
            if not wp then
                -- Loop back
                self._currentWaypoint = 1
                wp = self._route[1]
            end
    
            self:log("Moving to waypoint " .. self._currentWaypoint .. "/" .. #self._route)
    
            -- Use fivesawUtils pathfinding
            local fivetone = require("fivesawUtils")
            if fivetone then
                fivetone.navigateTo(wp.x, wp.y, wp.z, function(success)
                    if success then
                        self:log("Reached waypoint " .. self._currentWaypoint)
                        self._state = "MINING"
                        self._isMining = false
                    else
                        self:warn("Failed to reach waypoint, skipping")
                        self._currentWaypoint = self._currentWaypoint + 1
                        self._state = "MOVING"
                    end
                end)
            end
            self._state = "WAITING_PATH"  -- prevent re-entry
    
        elseif self._state == "WAITING_PATH" then
            -- Wait for pathfinding callback
    
        elseif self._state == "MINING" then
            if not self._isMining then
                local cfg = self._config
                local oreType = cfg.oreType or 0
                local blockTypes = OreTypeBlocks[oreType] or OreTypeBlocks[0]
                local priorities = {}
                for i = 1, #blockTypes do priorities[i] = 1 end
    
                BlockMiner.start(blockTypes, cfg.miningSpeed or 1500, cfg.pickaxeAbility or "NONE",
                    priorities, cfg.miningTool or "", cfg)
                self._isMining = true
            end
    
            -- Check if blocks exhausted → move to next waypoint
            if BlockMiner.error == "NOT_ENOUGH_BLOCKS" then
                self:log("Blocks exhausted, moving to next waypoint")
                BlockMiner.stop()
                self._isMining = false
                self._currentWaypoint = self._currentWaypoint + 1
                self._state = "MOVING"
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- EXPORTS
    -- ═══════════════════════════════════════════════════════════════
    return {
        MiningMacro = MiningMacro,
        CommissionMacro = CommissionMacro,
        GlacialMacro = GlacialMacro,
        RouteMinerMacro = RouteMinerMacro,
        OreTypeBlocks = OreTypeBlocks,
    }
    
end

__fsm_preload["fivesawMiner/init"] = function()
    -- ================================================================
    -- FiveSaw Miner / init.lua (autoload entry point)
    -- MacroManager + ImGui Config + HUD + Command Interface
    -- 1:1 port of MightyMiner main orchestrator
    -- ================================================================
    
    local core = __fsm_require("fivesawMiner/core")
    local bm_mod = __fsm_require("fivesawMiner/block_miner")
    local utils = __fsm_require("fivesawMiner/utils")
    local macros = __fsm_require("fivesawMiner/macros")
    local route_data = __fsm_require("fivesawMiner/route_data")
    
    local Clock = core.Clock
    local GameState = core.GameState
    local RotationHandler = core.RotationHandler
    local BlockMiner = bm_mod.BlockMiner
    local FailsafeManager = utils.FailsafeManager
    local AutoDrillRefuel = utils.AutoDrillRefuel
    local RouteManager = route_data.RouteManager
    
    -- ═══════════════════════════════════════════════════════════════
    -- CONFIG (1:1 MightyMinerConfig.java)
    -- ═══════════════════════════════════════════════════════════════
    local Config = {
        -- Macro selection
        macroType = 0,  -- 0=Commission, 1=Glacial, 2=Mining, 3=Route
        -- Mining
        oreType = 0,  -- 0=Mithril, 1=Diamond, 2=Emerald, etc.
        miningTool = "Drill",
        miningSpeed = 1500,
        autoDetectSpeed = true,
        -- Mithril toggles
        mineGrayMithril = true, mineGreenMithril = true,
        mineBlueMithril = true, mineTitanium = true,
        -- Pickaxe ability
        usePickaxeAbility = false,
        pickaxeAbility = "NONE",  -- NONE, MINING_SPEED_BOOST, PICKOBULUS
        -- Coefficients
        miningCoeff = 1.0, angleCoeff = 0.2, distCoeff = 0.5,
        tickOffset = 2,
        -- Commission
        claimMethod = 0,  -- 0=Emissary, 1=Royal Pigeon
        slayerWeapon = "",
        -- Failsafe
        failsafeEnabled = true,
        failsafeDelay = 2000,
        -- Rotation
        rotationTime = 400,
        -- Misc
        sneakWhileMining = false,
        debugMode = false,
        oreRespawnWait = 5,  -- seconds
        selectedRoute = "",
        -- Drill refuel
        autoDrillRefuel = false,
        drillFuelThreshold = 1000,
        drillFuelType = "Volta",  -- "Volta" or "Oil Barrel"
    }
    
    -- ═══════════════════════════════════════════════════════════════
    -- MACRO MANAGER (1:1 MacroManager.java)
    -- ═══════════════════════════════════════════════════════════════
    local MacroManager = {
        currentMacro = nil,
    }
    
    function MacroManager.getCurrentMacro()
        if Config.macroType == 0 then return macros.CommissionMacro
        elseif Config.macroType == 1 then return macros.GlacialMacro
        elseif Config.macroType == 2 then return macros.MiningMacro
        else return macros.RouteMinerMacro end
    end
    
    function MacroManager.toggle()
        if MacroManager.currentMacro then
            MacroManager.disable()
        else
            MacroManager.enable()
        end
    end
    
    function MacroManager.enable()
        local macro = MacroManager.getCurrentMacro()
        macro:configure(Config)
    
        -- Setup route if route miner
        if Config.macroType == 3 then
            RouteManager.init()
            local route = RouteManager.getRoute(Config.selectedRoute)
            if route then macro:setRoute(route) end
        end
    
        -- Start failsafe
        if Config.failsafeEnabled then
            FailsafeManager.start(Config, function(failType)
                player.addMessage("§c[FiveSaw] §eFailsafe triggered: " .. failType)
                if MacroManager.currentMacro then
                    MacroManager.currentMacro:pause()
                end
            end)
        end
    
        -- Start auto drill refuel
        if Config.autoDrillRefuel then
            AutoDrillRefuel.start(Config.miningTool, Config.drillFuelType, Config.drillFuelThreshold)
        end
    
        MacroManager.currentMacro = macro
        macro:enable()
        player.addMessage("§a[FiveSaw] §f" .. macro:getName() .. " §aEnabled")
    end
    
    function MacroManager.disable()
        if not MacroManager.currentMacro then return end
        FailsafeManager.stop()
        AutoDrillRefuel.stop()
        MacroManager.currentMacro:disable()
        player.addMessage("§c[FiveSaw] §f" .. MacroManager.currentMacro:getName() .. " §cDisabled")
        MacroManager.currentMacro = nil
    
        -- Release all inputs
        input.setPressedForward(false)
        input.setPressedBack(false)
        input.setPressedLeft(false)
        input.setPressedRight(false)
        input.setPressedJump(false)
        input.setPressedSneak(false)
        input.setPressedAttack(false)
        input.setPressedUseItem(false)
        input.setPressedSprint(false)
    end
    
    function MacroManager.isEnabled()
        return MacroManager.currentMacro ~= nil
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- TICK DISPATCHER
    -- ═══════════════════════════════════════════════════════════════
    registerClientTick(function()
        -- Update game state
        GameState.update()
    
        -- Rotation handler
        RotationHandler.onTick()
    
        -- Block miner
        BlockMiner.onTick()
    
        -- Current macro
        if MacroManager.currentMacro and MacroManager.currentMacro:isEnabled() then
            MacroManager.currentMacro:onTick()
        end
    
        -- Failsafe
        FailsafeManager.onTick()
    
        -- Auto Drill Refuel
        if AutoDrillRefuel.enabled then
            AutoDrillRefuel.onTick()
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════
    -- CHAT DISPATCHER
    -- ═══════════════════════════════════════════════════════════════
    registerMessageEvent(function(msg, overlay, json)
        if overlay then return end
        local text = msg:gsub("§.", "")
    
        -- Forward to macro
        if MacroManager.currentMacro then
            MacroManager.currentMacro:onChat(text)
        end
    
        -- Forward to failsafe
        FailsafeManager.onChat(text)
    
        -- Forward to block miner
        BlockMiner.onChat(text)
    end)
    
    -- ═══════════════════════════════════════════════════════════════
    -- COMMANDS
    -- ═══════════════════════════════════════════════════════════════
    registerMessageEvent(function(msg, overlay, json)
        if overlay then return end
        local text = msg:gsub("§.", "")
        if not text:match("^#") then return end
    
        local cmd = text:match("^#(%S+)")
        local args = text:match("^#%S+%s+(.+)") or ""
    
        if cmd == "fivesaw" or cmd == "fs" then
            MacroManager.toggle()
        elseif cmd == "fsstop" then
            MacroManager.disable()
        elseif cmd == "fstype" then
            local t = tonumber(args)
            if t then
                Config.macroType = t
                local names = { [0]="Commission", [1]="Glacial", [2]="Mining", [3]="Route" }
                player.addMessage("§a[FiveSaw] Macro type: " .. (names[t] or "?"))
            end
        elseif cmd == "fsspeed" then
            local s = tonumber(args)
            if s then
                Config.miningSpeed = s
                player.addMessage("§a[FiveSaw] Mining speed: " .. s)
            end
        elseif cmd == "fstool" then
            Config.miningTool = args
            player.addMessage("§a[FiveSaw] Tool: " .. args)
        elseif cmd == "fsore" then
            local o = tonumber(args)
            if o then
                Config.oreType = o
                player.addMessage("§a[FiveSaw] Ore type: " .. o)
            end
        elseif cmd == "fsroute" then
            if args == "add" then
                local pos = player.getPos()
                RouteManager.init()
                RouteManager.addWaypoint("Custom", math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
                player.addMessage("§a[FiveSaw] Added waypoint at current position")
            elseif args == "clear" then
                RouteManager.routes["Custom"] = {}
                player.addMessage("§a[FiveSaw] Route cleared")
            elseif args:match("^load ") then
                local file = args:match("^load (.+)")
                RouteManager.init()
                if RouteManager.loadFromFile("Custom", file) then
                    player.addMessage("§a[FiveSaw] Route loaded from " .. file)
                else
                    player.addMessage("§c[FiveSaw] Failed to load route")
                end
            end
        elseif cmd == "fshelp" then
            player.addMessage("§6═══ FiveSaw Miner Commands ═══")
            player.addMessage("§a#fivesaw §7/ §a#fs §7— Toggle macro")
            player.addMessage("§a#fsstop §7— Stop macro")
            player.addMessage("§a#fstype <0-3> §7— Set macro (0=Comm, 1=Glacial, 2=Mining, 3=Route)")
            player.addMessage("§a#fsspeed <n> §7— Set mining speed")
            player.addMessage("§a#fstool <name> §7— Set mining tool")
            player.addMessage("§a#fsore <0-11> §7— Set ore type")
            player.addMessage("§a#fsroute add/clear/load <file> §7— Route commands")
        elseif cmd == "fsdebug" then
            Config.debugMode = not Config.debugMode
            player.addMessage("§a[FiveSaw] Debug: " .. tostring(Config.debugMode))
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════
    -- IMGUI CONFIG PANEL + HUD (1:1 MightyMinerConfig + CommissionHUD)
    -- ═══════════════════════════════════════════════════════════════
    local imgui = require("imgui")
    local showConfig = false
    
    registerKeyEvent(function(key, action)
        if key == 295 then
            if action == "Press" or action == 1 then
                showConfig = not showConfig
                player.addMessage("§a[FiveSaw] Config toggled: " .. tostring(showConfig))
            end
        end
    end)
    
    registerImGuiRenderEvent(function()
    
        -- ── HUD OVERLAY ──
        if MacroManager.isEnabled() then
            local macro = MacroManager.currentMacro
            imgui.setNextWindowPos(10, 10, imgui.constants.Cond_FirstUseEver)
            imgui.setNextWindowSize(210, 0, imgui.constants.Cond_FirstUseEver)
            if imgui.begin("FiveSaw Status") then
                imgui.text("§a" .. macro:getName())
                imgui.separator()
    
                -- Uptime
                local uptimeMs = macro.uptime:getAccumMs()
                local mins = math.floor(uptimeMs / 60000)
                local secs = math.floor((uptimeMs % 60000) / 1000)
                imgui.text("Uptime: " .. string.format("%02d:%02d", mins, secs))
    
                -- Location
                imgui.text("Location: " .. GameState.currentLocation)
                imgui.text("SubLoc: " .. GameState.currentSubLocation)
    
                -- Macro-specific info
                if macro._state then
                    imgui.text("State: §e" .. macro._state)
                end
                if macro._commissionCount then
                    imgui.text("Commissions: §b" .. macro._commissionCount)
                end
                if macro._currentCommission then
                    imgui.text("Current: §d" .. macro._currentCommission)
                end
    
                -- BlockMiner status
                if BlockMiner.enabled then
                    imgui.text("Miner: §a" .. BlockMiner.state)
                    if BlockMiner.targetBlock then
                        imgui.text("Target: " .. BlockMiner.targetBlock.x .. "," .. BlockMiner.targetBlock.y .. "," .. BlockMiner.targetBlock.z)
                    end
                end
    
                imgui.endBegin()
            end
        end
    
        -- ── CONFIG WINDOW ──
        if not showConfig then return end
    
        imgui.setNextWindowPos(50, 50)
        imgui.setNextWindowSize(400, 0)
        if imgui.begin("FiveSaw Miner Config (F6)") then
    
            -- Macro Type
            imgui.text("§6Macro Type")
            local macroNames = { "Commission", "Glacial", "Mining", "Route Miner" }
            for i, name in ipairs(macroNames) do
                local selected = Config.macroType == (i - 1)
                if imgui.radioButton(name, selected) then
                    Config.macroType = i - 1
                end
            end
            imgui.separator()
    
            -- Mining Settings
            imgui.text("§6Mining Settings")
            local oreNames = { "Mithril", "Diamond", "Emerald", "Redstone", "Lapis", "Gold", "Iron", "Coal", "Glacite", "Hardstone", "Umber", "Tungsten" }
            for i, name in ipairs(oreNames) do
                local selected = Config.oreType == (i - 1)
                if imgui.radioButton(name, selected) then
                    Config.oreType = i - 1
                end
            end
            imgui.separator()
    
            -- Speed
            imgui.text("Mining Speed: " .. Config.miningSpeed)
            local c_miningSpeed, v_miningSpeed = imgui.sliderInt("##speed", Config.miningSpeed, 100, 5000); if c_miningSpeed then Config.miningSpeed = v_miningSpeed end
            local c_autoDetectSpeed, v_autoDetectSpeed = imgui.checkbox("Auto-Detect Speed", Config.autoDetectSpeed); if c_autoDetectSpeed then Config.autoDetectSpeed = v_autoDetectSpeed end
            if imgui.button("Detect Now") then
                local detected = utils.MiningSpeedDetector.detect(Config.miningTool)
                if detected then
                    Config.miningSpeed = detected
                    player.addMessage("§a[FiveSaw] Detected mining speed: " .. detected)
                else
                    player.addMessage("§c[FiveSaw] Could not detect speed from tool lore")
                end
                local ab = utils.MiningSpeedDetector.detectAbility(Config.miningTool)
                if ab ~= "NONE" then
                    Config.pickaxeAbility = ab
                    Config.usePickaxeAbility = true
                    player.addMessage("§a[FiveSaw] Detected ability: " .. ab)
                end
            end
    
            -- Tool
            imgui.text("Mining Tool:")
            local c_miningTool, v_miningTool = imgui.inputText("##tool", Config.miningTool); if c_miningTool then Config.miningTool = v_miningTool end
            imgui.separator()
    
            -- Mithril options (only show for mithril ore type)
            if Config.oreType == 0 then
                imgui.text("§6Mithril Options")
                local c_mineGrayMithril, v_mineGrayMithril = imgui.checkbox("Gray Mithril", Config.mineGrayMithril); if c_mineGrayMithril then Config.mineGrayMithril = v_mineGrayMithril end
                local c_mineGreenMithril, v_mineGreenMithril = imgui.checkbox("Green Mithril", Config.mineGreenMithril); if c_mineGreenMithril then Config.mineGreenMithril = v_mineGreenMithril end
                local c_mineBlueMithril, v_mineBlueMithril = imgui.checkbox("Blue Mithril", Config.mineBlueMithril); if c_mineBlueMithril then Config.mineBlueMithril = v_mineBlueMithril end
                local c_mineTitanium, v_mineTitanium = imgui.checkbox("Titanium", Config.mineTitanium); if c_mineTitanium then Config.mineTitanium = v_mineTitanium end
                imgui.separator()
            end
    
            -- Pickaxe Ability
            imgui.text("§6Pickaxe Ability")
            local c_usePickaxeAbility, v_usePickaxeAbility = imgui.checkbox("Use Pickaxe Ability", Config.usePickaxeAbility); if c_usePickaxeAbility then Config.usePickaxeAbility = v_usePickaxeAbility end
            if Config.usePickaxeAbility then
                local abilities = { "MINING_SPEED_BOOST", "PICKOBULUS" }
                for _, ab in ipairs(abilities) do
                    if imgui.radioButton(ab, Config.pickaxeAbility == ab) then
                        Config.pickaxeAbility = ab
                    end
                end
            end
            imgui.separator()
    
            -- Commission
            if Config.macroType == 0 then
                imgui.text("§6Commission Settings")
                if imgui.radioButton("Emissary", Config.claimMethod == 0) then Config.claimMethod = 0 end
                if imgui.radioButton("Royal Pigeon", Config.claimMethod == 1) then Config.claimMethod = 1 end
    
                imgui.text("Slayer Weapon:")
                local c_slayerWeapon, v_slayerWeapon = imgui.inputText("##slayer", Config.slayerWeapon); if c_slayerWeapon then Config.slayerWeapon = v_slayerWeapon end
                imgui.separator()
            end
    
            -- Failsafe
            imgui.text("§6Failsafe")
            local c_failsafeEnabled, v_failsafeEnabled = imgui.checkbox("Enable Failsafes", Config.failsafeEnabled); if c_failsafeEnabled then Config.failsafeEnabled = v_failsafeEnabled end
            imgui.separator()
    
            -- Coefficients
            imgui.text("§6Advanced")
            local c_sneakWhileMining, v_sneakWhileMining = imgui.checkbox("Sneak While Mining", Config.sneakWhileMining); if c_sneakWhileMining then Config.sneakWhileMining = v_sneakWhileMining end
            local c_debugMode, v_debugMode = imgui.checkbox("Debug Mode", Config.debugMode); if c_debugMode then Config.debugMode = v_debugMode end
    
            local c_rotationTime, v_rotationTime = imgui.sliderInt("Rotation Time##rot", Config.rotationTime, 100, 1000); if c_rotationTime then Config.rotationTime = v_rotationTime end
            local c_oreRespawnWait, v_oreRespawnWait = imgui.sliderInt("Ore Respawn Wait (s)##wait", Config.oreRespawnWait, 1, 30); if c_oreRespawnWait then Config.oreRespawnWait = v_oreRespawnWait end
    
            imgui.separator()
    
            -- Drill Refuel
            imgui.text("§6Drill Refuel")
            local c_autoDrillRefuel, v_autoDrillRefuel = imgui.checkbox("Auto Drill Refuel", Config.autoDrillRefuel); if c_autoDrillRefuel then Config.autoDrillRefuel = v_autoDrillRefuel end
            if Config.autoDrillRefuel then
                local c_drillFuelThreshold, v_drillFuelThreshold = imgui.sliderInt("Fuel Threshold##fuel", Config.drillFuelThreshold, 100, 10000); if c_drillFuelThreshold then Config.drillFuelThreshold = v_drillFuelThreshold end
                if imgui.radioButton("Volta##fuel", Config.drillFuelType == "Volta") then Config.drillFuelType = "Volta" end
                if imgui.radioButton("Oil Barrel##fuel", Config.drillFuelType == "Oil Barrel") then Config.drillFuelType = "Oil Barrel" end
            end
            imgui.separator()
    
            -- Toggle button
            if MacroManager.isEnabled() then
                if imgui.button("§c■ Stop Macro") then MacroManager.disable() end
            else
                if imgui.button("§a▶ Start Macro") then MacroManager.enable() end
            end
    
            imgui.endBegin()
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════
    -- DEBUG RENDERER
    -- ═══════════════════════════════════════════════════════════════
    registerWorldRenderer(function(ctx)
        if not Config.debugMode then return end
    
        -- Render target block
        if BlockMiner.enabled and BlockMiner.targetBlock then
            local tb = BlockMiner.targetBlock
            ctx.color(1, 0, 0, 0.4)
            ctx.drawBox(tb.x, tb.y, tb.z, tb.x + 1, tb.y + 1, tb.z + 1)
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════
    -- INIT
    -- ═══════════════════════════════════════════════════════════════
    RouteManager.init()
    if player then
        player.addMessage("§6═══════════════════════════════════")
        player.addMessage("§6  FiveSaw Miner v1.0 §7— Loaded")
        player.addMessage("§7  Press §eF6 §7for config")
        player.addMessage("§7  Type §a#fshelp §7for commands")
        player.addMessage("§6═══════════════════════════════════")
    end
    
end

return __fsm_require("fivesawMiner/init")