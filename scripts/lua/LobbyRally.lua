local mq = require('mq')

-- ==========================================
-- GUILD LOBBY PATHING DEFINITIONS
-- EQ Coordinates are natively Y, X
-- ==========================================
local spawnPads = {
    { 
        name = "WestRoom", 
        y = 411, x = 257, radius = 50, 
        path = {
            {y = 411, x = 175},
            {y = 481, x = 47},
            {y = 483, x = 0}
        } 
    },
    { 
        name = "EastRoom", 
        y = 414, x = -262, radius = 50, 
        path = {
            {y = 414, x = -171},
            {y = 481, x = -54},
            {y = 483, x = 0}
        } 
    },
    { 
        name = "Nexus", 
        y = 315, x = 0, radius = 50, 
        path = {
            {y = 355, x = 45},
            {y = 481, x = 47},
            {y = 483, x = 0}
        } 
    }
}

-- ==========================================
-- PATHING LOGIC
-- ==========================================
local function handleGuildLobbyRun()
    local myY = mq.TLO.Me.Y()
    local myX = mq.TLO.Me.X()
    
    -- 1. Check if we are near one of the three known spawn pads
    for _, pad in ipairs(spawnPads) do
        -- Distance formula checking bot's current location against the pad's center
        local dist = math.sqrt((myY - pad.y)^2 + (myX - pad.x)^2)
        
        if dist <= pad.radius then
            print(string.format("\ar[Lobby Runner]\aw Spawned near %s. Moving to meetup point...", pad.name))
            
            -- 2. Follow the specific waypoint array for this pad
            for _, wp in ipairs(pad.path) do
                mq.cmd(string.format('/moveto loc %d %d', wp.y, wp.x))
                
                -- Give the client a tiny moment to register the moveto command
                mq.delay(200) 
                
                -- Loop while the MoveTo command is actively running
                while mq.TLO.MoveTo.Moving() do
                    
                    -- 3. THE KILL SWITCH: If the bot gets a target, stop everything
                    if mq.TLO.Target.ID() > 0 then
                        print("\ar[Lobby Runner]\aw Target acquired! Killing pathing.")
                        mq.cmd('/nomoveto')
                        return -- Exits the entire pathing function
                    end
                    
                    mq.delay(100)
                end
            end
            
            print("\ar[Lobby Runner]\aw Arrived at meetup point.")
            break -- Finished pathing successfully
        end
    end
end

-- ==========================================
-- ZONE EVENT HOOK
-- ==========================================
mq.event('CatchZone', "You have entered #*#", function()
    if mq.TLO.Zone.ShortName():lower() == "guildlobby" then
        -- Wait 3 seconds for e3, the UI, and coordinates to fully stabilize after zoning
        mq.delay(3000) 
        
        -- Ensure they don't already have a target before taking off
        if mq.TLO.Target.ID() == 0 then
            handleGuildLobbyRun()
        else
            print("\ar[Lobby Runner]\aw Zoned in with a target. Skipping pathing.")
        end
    end
end)

-- ==========================================
-- MAIN LOOP
-- ==========================================
print("\ar[Lobby Runner]\aw Background script running. Waiting for Guild Lobby zone-ins...")

while true do
    mq.doevents()
    mq.delay(100) -- Sleep briefly to prevent high CPU usage
end
