-- ================================================================
-- FiveSaw Miner / block_miner.lua
-- Block Mining Engine — 1:1 port of BlockMiner.java + all states
-- ================================================================

local core = require("fivesawMiner.core")
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
