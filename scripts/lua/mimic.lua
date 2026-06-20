local mq = require('mq')

-- ==========================================
-- SCRIPT ARGUMENTS (e.g. /lua run mimic runforever)
-- ==========================================
local args = {...}
local runForever = false

for _, arg in ipairs(args) do
    if arg:lower() == "runforever" or arg:lower() == "runforever=true" then
        runForever = true
    end
end

print("Porter Automator initialized! Standing by for port...")
if runForever then
    print("--> Mode: Run Forever (will not exit after porting)")
else
    print("--> Mode: Single Port (will cleanly exit after 1 port)")
end

local lastPorter = ""
local lastCommandSent = "" 
local isDone = false 
local isError = false 

-- ==========================================
-- POST-ZONE DICTIONARIES
-- ==========================================
local magusMap = {
    ["butcher"] = "Butcherblock",
    ["ecommons"] = "Commonlands",
    ["everfrost"] = "Everfrost",
    ["nro"] = "North Ro",
    ["sro"] = "South Ro"
}

local liminalMap = {
    ["blackburrow"] = "travel blackburrow",
    ["burningwood"] = "travel burningwood",
    ["eastwastes"] = "travel eastwastes",
    ["emeraldjungle"] = "travel emeraldjungle",
    ["everfrost"] = "travel everfrost",
    ["fieldofbone"] = "travel fieldofbone",
    ["guktop"] = "travel guktop",
    ["hole"] = "travel hole",
    ["lakeofillomen"] = "travel lakeofillomen",
    ["mischiefplane"] = "travel mischiefplane",
    ["mistmoore"] = "travel mistmoore",
    ["overthere"] = "travel overthere",
    ["paw"] = "travel paw",
    ["runnyeye"] = "travel runnyeye",
    ["trakanon"] = "travel trakanon",
    ["unrest"] = "travel unrest",
    ["warrens"] = "travel warrens",
    ["westwastes"] = "travel westwastes",
    ["echo"] = "travel echo",
    ["mseru"] = "travel mseru",
    ["thegrey"] = "travel thegrey",
    ["umbral"] = "travel umbral"
}

-- Translated from previous whisper texts to standard EQ Zone Shortnames
local druidWizMap = {
    ["northkarana"] = "North Karana",
    ["toxxulia"] = "Toxxulia Forest",
    ["butcher"] = "Butcherblock",
    ["qeytoqrg"] = "Surefall Glade",
    ["wcommons"] = "West Commonlands",
    ["ecommons"] = "West Commonlands",
    ["lavastorm"] = "Lavastorm",
    ["steamfont"] = "Steamfont",
    ["sro"] = "South Ro",
    ["feerrott"] = "Feerrott",
    ["misty"] = "Misty Thicket",
    ["sharvahl"] = "Sharvahl",
    ["arena"] = "Arena",
    ["dreadlands"] = "Dreadlands",
    ["emeraldjungle"] = "Emerald Jungle",
    ["skyfire"] = "Skyfire",
    ["iceclad"] = "Iceclad",
    ["greatdivide"] = "Great Divide",
    ["wakening"] = "Wakening Lands",
    ["cobaltscar"] = "Cobalt Scar",
    ["nexus"] = "Nexus",
    ["twilight"] = "Twilight",
    ["dawnshroud"] = "Dawnshroud",
    ["grimling"] = "Grimling",
    ["gfaydark"] = "Greater Faydark",
    ["nektulos"] = "Nektulos Forest",
    ["nro"] = "North Ro",
    ["soltemple"] = "Temple of Solusek Ro",
    ["cazicthule"] = "Cazic-Thule",
    ["qey2hh1"] = "West Karana"
}

-- ==========================================
-- EVENT: Catching DanNet Error (The Retry Logic)
-- ==========================================
local function Event_DanNetError(line)
    if lastCommandSent ~= "" then
        isError = true 
        print("DanNet channel missed! Waiting for group to sync on the other side...")
        
        local retries = 0
        while mq.TLO.Group.Members() == 0 and retries < 100 do
            mq.delay(100)
            retries = retries + 1
        end
        
        mq.delay(1000)
        
        print("Group synced! Retrying port command...")
        mq.cmd(lastCommandSent)
        
        lastCommandSent = "" 
        isError = false 
    end
end

-- ==========================================
-- EVENT: Catching Zone Entries (ALL PORTERS)
-- ==========================================
local function Event_Zone(line)
    if lastPorter == "" then return end

    local shortName = mq.TLO.Zone.ShortName()
    if not shortName then return end

    local barkWord = nil

    -- Determine which map to use based on the NPC we targeted before zoning
    if lastPorter:find("^Magus") then
        barkWord = magusMap[shortName]
    elseif lastPorter:find("^Liminal") then
        barkWord = liminalMap[shortName]
    elseif lastPorter:find("^Circlekeeper") or lastPorter:find("^Spirekeeper") then
        barkWord = druidWizMap[shortName]
    end

    if barkWord then
        print(("Post-Zone port detected for %s. Attempting to drag bots via %s..."):format(shortName, lastPorter))
        
        -- TRY IT IMMEDIATELY
        lastCommandSent = ('/dgge /multiline ; /tar npc "%s" ; /timed 5 /e3bark %s'):format(lastPorter, barkWord)
        mq.cmd(lastCommandSent)
        
        -- Wait 1 second to see if DanNet throws the error event in chat
        mq.delay(1000)
        
        -- If the error event caught it, wait for it to finish fixing the problem
        while isError do
            mq.delay(100)
            mq.doevents()
        end
        
        if not runForever then isDone = true end
    end
    
    lastPorter = ""
end

-- ==========================================
-- EVENT HOOKS & MAIN LOOP
-- ==========================================
mq.event('CatchZone', "You have entered #*#", Event_Zone)
mq.event('CatchDanNetError', "Could not find channel group", Event_DanNetError)

while not isDone do
    local targetName = mq.TLO.Target.CleanName()
    if targetName then
        -- Track any of the 4 porter types
        if targetName:find("^Magus") or targetName:find("^Liminal") or targetName:find("^Circlekeeper") or targetName:find("^Spirekeeper") then
            lastPorter = targetName
        end
    end
    
    mq.doevents()
    mq.delay(100) 
end

print("Port complete! Cleaning up and exiting Automator.")
