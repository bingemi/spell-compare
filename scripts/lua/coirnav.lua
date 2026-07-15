local mq = require('mq')

-- Replace with the exact names of the little guys (e.g., "Guardian of Coirnav")
local targetNames = {
    "a regrua waterfiend",
    "a hraquis icefiend",
    "a triloun vaporfiend"
}

local ignoreList = {}
local ignoreDuration = 30 -- How long (in seconds) to blacklist a stuck mob

local function getNearestTarget()
    local closestSpawn = nil
    local closestDistance = 999999
    local now = os.time()

    for _, name in ipairs(targetNames) do
        -- Strict exactname match to prevent targeting partial names
        for i = 1, 5 do
            local spawn = mq.TLO.NearestSpawn(i, string.format('npc exactname "%s" targetable', name))
            if not spawn() then break end

            local spawnID = spawn.ID()
            
            -- Clean up expired ignore entries
            if ignoreList[spawnID] and ignoreList[spawnID] < now then
                ignoreList[spawnID] = nil
            end

            -- Double-check exact string match in Lua
            if not ignoreList[spawnID] and spawn.Distance() < closestDistance and spawn.CleanName() == name then
                closestSpawn = spawn
                closestDistance = spawn.Distance()
            end
        end
    end

    return closestSpawn
end

local function mainLoop()
    printf("\ag[Coirnav Hunter]\aw Started. Rogue is strictly hunting exact names...")

    while true do
        if not mq.TLO.Target() or mq.TLO.Target.Type() == "Corpse" then
            local target = getNearestTarget()

            if target and target() then 
                local targetID = target.ID()
                printf("\ag[Coirnav Hunter]\aw Engaging: \ay%s\aw at distance \ag%.2f", target.CleanName(), target.Distance())
                target.DoTarget()
                
                mq.delay(500, function() return mq.TLO.Target.ID() == targetID end)

                if mq.TLO.Target() then
                    mq.cmd('/squelch /stick 12 uw')
                    mq.cmd('/attack on')

                    local engageTime = os.time()
                    local lastHP = mq.TLO.Target.PctHPs()
                    local lastHPTime = os.time()
                    local isStuck = false

                    -- Combat Loop
                    while mq.TLO.Target() and mq.TLO.Target.Type() == "NPC" and mq.TLO.Target.PctHPs() > 0 do
                        local currentDist = mq.TLO.Target.Distance()
                        local currentHP = mq.TLO.Target.PctHPs()
                        
                        -- Update HP tracker if we are doing damage
                        if currentHP ~= lastHP then
                            lastHP = currentHP
                            lastHPTime = os.time()
                        end
                        
                        -- COMBAT DROPPED CHECK: If in range but auto-attack got turned off, turn it back on
                        if currentDist <= 20 and not mq.TLO.Me.Combat() then
                            mq.cmd('/attack on')
                        end

                        -- Auto-Backstab
                        if mq.TLO.Me.AbilityReady("Backstab")() and currentDist <= 15 then
                            mq.cmd('/doability "Backstab"')
                        end

                        -- STUCK CHECK 1: Taking too long to reach the target (> 5 seconds, out of range)
                        if os.time() - engageTime > 5 and currentDist > 20 then
                            printf("\ar[Coirnav Hunter]\aw Can't reach \ay%s\aw. Ignoring for %ds.", mq.TLO.Target.CleanName(), ignoreDuration)
                            ignoreList[targetID] = os.time() + ignoreDuration
                            isStuck = true
                            break
                        end

                        -- STUCK CHECK 2: In range, but HP hasn't moved in 3 seconds (Standstill check)
                        if currentDist <= 20 and (os.time() - lastHPTime > 3) then
                            printf("\ar[Coirnav Hunter]\aw \ay%s\aw HP is not moving (Standstill). Ignoring for %ds.", mq.TLO.Target.CleanName(), ignoreDuration)
                            ignoreList[targetID] = os.time() + ignoreDuration
                            isStuck = true
                            break
                        end

                        mq.delay(100)
                    end

                    -- Cleanup
                    mq.cmd('/attack off')
                    mq.cmd('/squelch /stick off')
                    mq.cmd('/squelch /target clear')
                    
                    if isStuck then mq.delay(500) end
                end
            end
        end
        
        mq.delay(500)
    end
end

mainLoop()
