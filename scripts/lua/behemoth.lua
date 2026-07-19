local mq = require('mq')

local targetName = "a clockwork device"
local scanRadius = 100

-- Record the exact starting location as the "Home" anchor
local homeY = mq.TLO.Me.Y()
local homeX = mq.TLO.Me.X()
local homeZ = mq.TLO.Me.Z()

-- State Tracking Variables
local currentTargetID = 0
local isSticking = false
local isMovingToTarget = false -- Safe Lua flag to track movement state

-- Calculates flat 2D distance to our home anchor
local function getDistanceToHome()
    local currentY = mq.TLO.Me.Y()
    local currentX = mq.TLO.Me.X()
    return math.sqrt((currentY - homeY)^2 + (currentX - homeX)^2)
end

local function getNearestTarget()
    -- Native MQ exact match (=) with a 100 unit radius limit
    local spawn = mq.TLO.NearestSpawn(string.format('npc ="%s" radius %d targetable', targetName, scanRadius))
    
    if spawn() and spawn.CleanName() == targetName then 
        return spawn 
    end
    
    return nil
end

local function mainLoop()
    printf("\ag[Behemoth Defender]\aw Started. Anchored to Location: Y: \ay%.2f\aw, X: \ay%.2f\aw", homeY, homeX)
    printf("\ag[Behemoth Defender]\aw Scanning 100 units for Clockwork Devices...")

    while true do
        local target = mq.TLO.Target
        
        -- ==========================================
        -- STATE 1: IDLE / RETURN TO ANCHOR
        -- ==========================================
        if not target() or target.Type() == "Corpse" or target.CleanName() ~= targetName then
            
            -- Clear wrong targets immediately
            if target() and target.Type() == "NPC" and target.CleanName() ~= targetName then
                mq.cmd('/squelch /target clear')
            end

            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            if currentTargetID ~= 0 then currentTargetID = 0 end
            isSticking = false
            isMovingToTarget = false

            local newTarget = getNearestTarget()
            
            if newTarget then
                -- Enemy spotted within 100 units! Target it.
                printf("\ag[Behemoth Defender]\aw Target Acquired: \ay%s\aw", newTarget.CleanName())
                newTarget.DoTarget()
                mq.delay(200)
            else
                -- No enemies nearby. Check if we wandered away from our anchor.
                local distHome = getDistanceToHome()
                
                if distHome > 15 then
                    if not mq.TLO.MoveTo.Moving() then
                        mq.cmdf('/squelch /moveto loc %f %f %f', homeY, homeX, homeZ)
                    end
                else
                    -- We are safely back at camp. Stop moving.
                    if mq.TLO.MoveTo.Moving() then
                        mq.cmd('/squelch /moveto off')
                    end
                end
            end
            
        -- ==========================================
        -- STATE 2: ENGAGING TARGET
        -- ==========================================
        elseif target() and target.Type() == "NPC" and target.CleanName() == targetName then
            local tID = target.ID()
            local dist = target.Distance() or 9999
            
            if tID ~= currentTargetID then
                currentTargetID = tID
                isMovingToTarget = false -- Reset movement flag for a fresh target
            end

            -- MOVEMENT PHASE
            if dist > 15 then
                -- Target is far, run to it
                if isSticking then
                    mq.cmd('/squelch /stick off')
                    isSticking = false
                end
                
                -- Safely verify we aren't already running to it
                if not isMovingToTarget or not mq.TLO.MoveTo.Moving() then
                    mq.cmdf('/squelch /moveto id %d', tID)
                    isMovingToTarget = true
                end
                
                if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
                
            elseif dist <= 15 then
                -- Target is in melee range, lock on and attack
                if mq.TLO.MoveTo.Moving() or isMovingToTarget then
                    mq.cmd('/squelch /moveto off')
                    isMovingToTarget = false
                end
                
                if not isSticking then
                    mq.cmd('/squelch /stick 10') -- Force backstab positioning
                    isSticking = true
                end
                
                if not mq.TLO.Me.Combat() then mq.cmd('/attack on') end
                
                if mq.TLO.Me.AbilityReady("Backstab")() then
                    mq.cmd('/doability "Backstab"')
                end
            end
        end
        
        mq.delay(100)
    end
end

mainLoop()
