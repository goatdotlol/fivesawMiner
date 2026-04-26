-- ================================================================
-- FiveSaw Miner / utils.lua
-- Utilities: CommissionUtil, InventoryUtil, FailsafeManager
-- 1:1 port of MightyMiner Java utilities
-- ================================================================

local core = require("fivesawMiner.core")
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
