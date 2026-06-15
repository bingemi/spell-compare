local mq = require('mq')

local radius = 30

mq.delay(1000)
mq.cmd('/keypress 1')

while true do
    local npcCount = mq.TLO.SpawnCount(('npc radius %d'):format(radius))()

    if npcCount == 0 then
        break
    end

    local targetID = mq.TLO.Target.ID()
    if not targetID or targetID == 0 then
        mq.delay(500)
        mq.cmd('/keypress 1')
    end

    mq.delay(100)
end
