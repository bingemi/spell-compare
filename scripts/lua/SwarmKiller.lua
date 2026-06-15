local mq = require('mq')

local radius = 30

mq.delay(200)
mq.cmd('mqtarget npc radius 40 zradius 20')
mq.cmd('/assistme')

while true do
    local npcCount = mq.TLO.SpawnCount(('npc radius %d'):format(radius))()

    if npcCount == 0 then
        break
    end

    local targetID = mq.TLO.Target.ID()
    if not targetID or targetID == 0 then
        mq.delay(200)
        mq.cmd('mqtarget npc radius 40 zradius 20')
        mq.cmd('/assistme')
    end

    mq.delay(100)
end