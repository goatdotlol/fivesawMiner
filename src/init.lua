-- ================================================================
-- FiveSaw Miner / init.lua (autoload entry point)
-- MacroManager + ImGui Config + HUD + Command Interface
-- 1:1 port of MightyMiner main orchestrator
-- ================================================================

local core = require("fivesawMiner.core")
local bm_mod = require("fivesawMiner.block_miner")
local utils = require("fivesawMiner.utils")
local macros = require("fivesawMiner.macros")
local route_data = require("fivesawMiner.route_data")

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
local tui = require("tui")
local showConfig = false

registerImGuiRenderEvent(function()
    -- Toggle key (F6)
    if tui.isKeyPressed(tui.Keys.F6) then
        showConfig = not showConfig
    end

    -- ── HUD OVERLAY ──
    if MacroManager.isEnabled() then
        local macro = MacroManager.currentMacro
        local w = tui.getWindowWidth()
        tui.setNextWindowPos(w - 220, 10)
        tui.setNextWindowSize(210, 0)
        if tui.begin("FiveSaw Status", true) then
            tui.text("§a" .. macro:getName())
            tui.separator()

            -- Uptime
            local uptimeMs = macro.uptime:getAccumMs()
            local mins = math.floor(uptimeMs / 60000)
            local secs = math.floor((uptimeMs % 60000) / 1000)
            tui.text("Uptime: " .. string.format("%02d:%02d", mins, secs))

            -- Location
            tui.text("Location: " .. GameState.currentLocation)
            tui.text("SubLoc: " .. GameState.currentSubLocation)

            -- Macro-specific info
            if macro._state then
                tui.text("State: §e" .. macro._state)
            end
            if macro._commissionCount then
                tui.text("Commissions: §b" .. macro._commissionCount)
            end
            if macro._currentCommission then
                tui.text("Current: §d" .. macro._currentCommission)
            end

            -- BlockMiner status
            if BlockMiner.enabled then
                tui.text("Miner: §a" .. BlockMiner.state)
                if BlockMiner.targetBlock then
                    tui.text("Target: " .. BlockMiner.targetBlock.x .. "," .. BlockMiner.targetBlock.y .. "," .. BlockMiner.targetBlock.z)
                end
            end

            tui.finish()
        end
    end

    -- ── CONFIG WINDOW ──
    if not showConfig then return end

    tui.setNextWindowPos(50, 50)
    tui.setNextWindowSize(400, 0)
    if tui.begin("FiveSaw Miner Config (F6)", true) then

        -- Macro Type
        tui.text("§6Macro Type")
        local macroNames = { "Commission", "Glacial", "Mining", "Route Miner" }
        for i, name in ipairs(macroNames) do
            local selected = Config.macroType == (i - 1)
            if tui.radioButton(name, selected) then
                Config.macroType = i - 1
            end
        end
        tui.separator()

        -- Mining Settings
        tui.text("§6Mining Settings")
        local oreNames = { "Mithril", "Diamond", "Emerald", "Redstone", "Lapis", "Gold", "Iron", "Coal", "Glacite", "Hardstone", "Umber", "Tungsten" }
        for i, name in ipairs(oreNames) do
            local selected = Config.oreType == (i - 1)
            if tui.radioButton(name, selected) then
                Config.oreType = i - 1
            end
        end
        tui.separator()

        -- Speed
        tui.text("Mining Speed: " .. Config.miningSpeed)
        Config.miningSpeed = tui.sliderInt("##speed", Config.miningSpeed, 100, 5000) or Config.miningSpeed
        Config.autoDetectSpeed = tui.checkbox("Auto-Detect Speed", Config.autoDetectSpeed)
        if tui.button("Detect Now") then
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
        tui.text("Mining Tool:")
        Config.miningTool = tui.inputText("##tool", Config.miningTool) or Config.miningTool
        tui.separator()

        -- Mithril options (only show for mithril ore type)
        if Config.oreType == 0 then
            tui.text("§6Mithril Options")
            Config.mineGrayMithril = tui.checkbox("Gray Mithril", Config.mineGrayMithril)
            Config.mineGreenMithril = tui.checkbox("Green Mithril", Config.mineGreenMithril)
            Config.mineBlueMithril = tui.checkbox("Blue Mithril", Config.mineBlueMithril)
            Config.mineTitanium = tui.checkbox("Titanium", Config.mineTitanium)
            tui.separator()
        end

        -- Pickaxe Ability
        tui.text("§6Pickaxe Ability")
        Config.usePickaxeAbility = tui.checkbox("Use Pickaxe Ability", Config.usePickaxeAbility)
        if Config.usePickaxeAbility then
            local abilities = { "MINING_SPEED_BOOST", "PICKOBULUS" }
            for _, ab in ipairs(abilities) do
                if tui.radioButton(ab, Config.pickaxeAbility == ab) then
                    Config.pickaxeAbility = ab
                end
            end
        end
        tui.separator()

        -- Commission
        if Config.macroType == 0 then
            tui.text("§6Commission Settings")
            if tui.radioButton("Emissary", Config.claimMethod == 0) then Config.claimMethod = 0 end
            if tui.radioButton("Royal Pigeon", Config.claimMethod == 1) then Config.claimMethod = 1 end

            tui.text("Slayer Weapon:")
            Config.slayerWeapon = tui.inputText("##slayer", Config.slayerWeapon) or Config.slayerWeapon
            tui.separator()
        end

        -- Failsafe
        tui.text("§6Failsafe")
        Config.failsafeEnabled = tui.checkbox("Enable Failsafes", Config.failsafeEnabled)
        tui.separator()

        -- Coefficients
        tui.text("§6Advanced")
        Config.sneakWhileMining = tui.checkbox("Sneak While Mining", Config.sneakWhileMining)
        Config.debugMode = tui.checkbox("Debug Mode", Config.debugMode)

        Config.rotationTime = tui.sliderInt("Rotation Time##rot", Config.rotationTime, 100, 1000) or Config.rotationTime
        Config.oreRespawnWait = tui.sliderInt("Ore Respawn Wait (s)##wait", Config.oreRespawnWait, 1, 30) or Config.oreRespawnWait

        tui.separator()

        -- Drill Refuel
        tui.text("§6Drill Refuel")
        Config.autoDrillRefuel = tui.checkbox("Auto Drill Refuel", Config.autoDrillRefuel)
        if Config.autoDrillRefuel then
            Config.drillFuelThreshold = tui.sliderInt("Fuel Threshold##fuel", Config.drillFuelThreshold, 100, 10000) or Config.drillFuelThreshold
            if tui.radioButton("Volta##fuel", Config.drillFuelType == "Volta") then Config.drillFuelType = "Volta" end
            if tui.radioButton("Oil Barrel##fuel", Config.drillFuelType == "Oil Barrel") then Config.drillFuelType = "Oil Barrel" end
        end
        tui.separator()

        -- Toggle button
        if MacroManager.isEnabled() then
            if tui.button("§c■ Stop Macro") then MacroManager.disable() end
        else
            if tui.button("§a▶ Start Macro") then MacroManager.enable() end
        end

        tui.finish()
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
player.addMessage("§6═══════════════════════════════════")
player.addMessage("§6  FiveSaw Miner v1.0 §7— Loaded")
player.addMessage("§7  Press §eF6 §7for config")
player.addMessage("§7  Type §a#fshelp §7for commands")
player.addMessage("§6═══════════════════════════════════")
