local mq = require('mq')

-- Your exact add names
local targetNames = {
    "a regrua waterfiend",
    "a hraquis icefiend",
    "a triloun vaporfiend"
}

local ignoreList = {}
local ignoreDuration = 30 

-- State Tracking Variables
local currentTargetID = 0
local engageTime = 0
local lastHP = 100
local lastHPTime = 0

-- Gatekeeper function: Ensures a name is exactly on the approved list
local function isValidTargetName(name)
    for _, tName in ipairs(targetNames) do
        if name == tName then return true end
    end
    return false
end

local function getNearestTarget()
    local closestID = nil
    local closestDistance = 999999
    local now = os.time()

    for _, name in ipairs(targetNames) do
        -- Added '=' to force native MQ exact matching, plus a 300 unit radius
        for i = 1, 5 do
            local spawn = mq.TLO.NearestSpawn(i, string.format('npc ="%s" radius 300 targetable', name))
            if not spawn() then break end

            local spawnID = spawn.ID()
            
            if ignoreList[spawnID] and ignoreList[spawnID] < now then
                ignoreList[spawnID] = nil
            end

            -- Double check in Lua just to be safe
            if not ignoreList[spawnID] and spawn.Distance3D() < closestDistance and spawn.CleanName() == name then
                closestID = spawnID
                closestDistance = spawn.Distance3D()
            end
        end
    end

    if closestID then return mq.TLO.Spawn(closestID) end
    return nil
end

local function clearState(reason, idToIgnore)
    if idToIgnore then
        printf("\ar[Coirnav Hunter]\aw %s. Blacklisting ID %d for %ds.", reason, idToIgnore, ignoreDuration)
        ignoreList[idToIgnore] = os.time() + ignoreDuration
    end
    
    mq.cmd('/squelch /moveto off')
    mq.cmd('/squelch /stick off')
    mq.cmd('/attack off')
    mq.cmd('/squelch /target clear')
    currentTargetID = 0
    mq.delay(200) 
end

local function mainLoop()
    printf("\ag[Coirnav Hunter]\aw v3 Started. Rogue is ONLY attacking approved adds...")

    while true do
        local target = mq.TLO.Target
        
        -- ==========================================
        -- STATE 1: NO TARGET (OR WRONG TARGET)
        -- ==========================================
        -- Gatekeeper check: If we have a target, but it's not an approved name, drop it!
        if not target() or target.Type() == "Corpse" or not isValidTargetName(target.CleanName()) then
            
            -- If we accidentally targeted a boss, clear it immediately
            if target() and target.Type() == "NPC" and not isValidTargetName(target.CleanName()) then
                mq.cmd('/squelch /target clear')
            end

            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            if currentTargetID ~= 0 then currentTargetID = 0 end

            local newTarget = getNearestTarget()
            if newTarget and newTarget() then
                printf("\ag[Coirnav Hunter]\aw New Target Acquired: \ay%s\aw", newTarget.CleanName())
                newTarget.DoTarget()
                mq.delay(200)
            end
            
        -- ==========================================
        -- STATE 2: ENGAGING APPROVED TARGET
        -- ==========================================
        elseif target() and target.Type() == "NPC" and isValidTargetName(target.CleanName()) then
            local tID = target.ID()
            local dist3D = target.Distance3D() or 9999
            
            if tID ~= currentTargetID then
                currentTargetID = tID
                engageTime = os.time()
                lastHP = target.PctHPs()
                lastHPTime = os.time()
            end
            
            local currentHP = target.PctHPs()
            if currentHP ~= lastHP then
                lastHP = currentHP
                lastHPTime = os.time()
            end

            -- MOVEMENT PHASE
            if dist3D > 40 then
                mq.cmd('/squelch /stick off') 
                mq.cmdf('/squelch /moveto id %d', tID)
                if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
                
            elseif dist3D <= 40 then
                mq.cmd('/squelch /moveto off')
                mq.cmd('/squelch /stick 12 uw')
                if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
                
                if dist3D <= 15 and mq.TLO.Me.AbilityReady("Backstab")() then
                    mq.cmd('/doability "Backstab"')
                end
            end

            -- ==========================================
            -- STATE 3: STUCK CHECKS
            -- ==========================================
            if dist3D > 20 and (os.time() - engageTime > 10) then
                clearState("Took too long to reach target", tID)
            end
            
            if dist3D <= 20 and (os.time() - lastHPTime > 4) then
                clearState("Target HP is stalled (Possible Z-Axis/LoS bug)", tID)
            end
        end
        
        mq.delay(100)
    end
end

mainLoop()
