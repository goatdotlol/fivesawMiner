-- ================================================================
-- FiveSaw Miner / macros.lua
-- All macro state machines: Mining, Commission, Glacial, Route
-- 1:1 port of MightyMiner Java macros
-- ================================================================

local core = require("fivesawMiner.core")
local bm_mod = require("fivesawMiner.block_miner")
local utils = require("fivesawMiner.utils")

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
