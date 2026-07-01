local mq = require('mq')

local radius = 30
local zradius = 20

print("SwarmKiller started!")

-- Custom filter to check if a spawn's name belongs to a group member's pet
local function getValidSwarmTarget()
    -- Still use the base nopet filter to weed out standard formal pets
    local searchString = ('npc nopet radius %d zradius %d'):format(radius, zradius)
    local count = mq.TLO.SpawnCount(searchString)()
    
    for i = 1, count do
        local spawn = mq.TLO.NearestSpawn(i, searchString)
        if spawn() and spawn.ID() > 0 then
            local spawnName = spawn.CleanName():lower()
            local isSwarmPet = false
            
            -- Check if "pet" is in the name, then cross-reference with the group
            if spawnName:find("pet") then
                -- Check yourself first
                if spawnName:find(mq.TLO.Me.CleanName():lower()) then
                    isSwarmPet = true
                else
                    -- Check all group members
                    local groupCount = mq.TLO.Group.Members() or 0
                    for g = 1, groupCount do
                        local member = mq.TLO.Group.Member(g)
                        if member and member() then
                            local memberName = member.CleanName():lower()
                            if spawnName:find(memberName) then
                                isSwarmPet = true
                                break
                            end
                        end
                    end
                end
            end
            
            -- If it passed the name checks, this is our valid target ID
            if not isSwarmPet then
                return spawn.ID()
            end
        end
    end
    
    return 0 -- No valid targets found
end

local lastTargetID = 0

while true do
    -- Find the nearest valid target ID using our custom filter
    local nextTargetID = getValidSwarmTarget()

    if nextTargetID == 0 then
        print("Swarm cleared! SwarmKiller exiting.")
        break
    end

    local targetID = mq.TLO.Target.ID()
    
    -- If we don't have a target, or we have the wrong target, acquire it
    if not targetID or targetID ~= nextTargetID then
        mq.cmd('/target id ' .. nextTargetID)
        mq.delay(200, function() return mq.TLO.Target.ID() == nextTargetID end)
        targetID = mq.TLO.Target.ID()
    end

    -- If it's a new, valid target, attack it
    if targetID == nextTargetID and targetID ~= lastTargetID then
        mq.delay(100)
        mq.cmd('/assistme')
        mq.cmd('/face fast')
        lastTargetID = targetID
    end

    mq.delay(100)
end
