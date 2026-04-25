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
