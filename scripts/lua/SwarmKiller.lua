local mq = require('mq')

local radius = 30
local zradius = 20

print("SwarmKiller started!")

mq.delay(500)
mq.cmd(('/mqtarget npc radius %d zradius %d'):format(radius, zradius))
mq.cmd('/assistme')

local lastTargetID = 0

while true do
    local npcCount = mq.TLO.SpawnCount(('npc radius %d zradius %d'):format(radius, zradius))()

    if npcCount == 0 then
        print("Swarm cleared! SwarmKiller exiting.")
        break
    end

    local targetID = mq.TLO.Target.ID()
    if targetID and targetID ~= 0 and targetID ~= lastTargetID then
        mq.delay(100)
        mq.cmd('/assistme')
		mq.cmd('/face fast')
        lastTargetID = targetID
    elseif not targetID or targetID == 0 then
        mq.cmd(('/mqtarget npc radius %d zradius %d'):format(radius, zradius))
        mq.delay(200)
        mq.cmd('/assistme')
		mq.cmd('/face fast')
    end

    mq.delay(100)
end
