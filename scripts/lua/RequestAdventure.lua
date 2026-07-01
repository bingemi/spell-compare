local mq = require('mq')

local TARGET_NAME = "Ulyist Son of Night"
local WIN_NAME = "AdventureRequestWnd"

-- Using just the first names to avoid backtick and surname targeting bugs
local zoneMerchants = {
    butcher = "Xyzelauna",
    everfrost = "Mannis",
    ecommons = "Periac",
    commonlands = "Periac", 
    nro = "Escon",
    sro = "Kallei"
}

local function requestAdventure()
    local currentZone = mq.TLO.Zone.ShortName():lower()
    local merchantFirstName = zoneMerchants[currentZone]

    -- Native MQ Auto-Targeting Logic
    if merchantFirstName then
        -- Check if we already have them targeted by looking for the first name
        local currentTarget = mq.TLO.Target.Name() or ""
        if not string.find(currentTarget, merchantFirstName) then
            print("\ay[LDoNReq]\aw Searching radar for merchant: \ap" .. merchantFirstName)
            
            -- Ask MQ to find the nearest NPC with this first name
            local merchantSpawn = mq.TLO.Spawn('npc ' .. merchantFirstName)
            
            if merchantSpawn() then
                print("\ag[LDoNReq]\aw Found them! Forcing target...")
                merchantSpawn.DoTarget()
                -- Give the client a half second to register the target change
                mq.delay(500)
            else
                print("\ar[LDoNReq]\aw Could not find " .. merchantFirstName .. " nearby. Are you in camp?")
            end
        end
    else
        print("\ay[LDoNReq]\aw Zone not in auto-target list. Please target the merchant manually.")
    end

    if mq.TLO.Target.ID() == 0 then
        print("\ar[LDoNReq]\aw Error: No target selected. Aborting.")
        return
    end

    print("\ay[LDoNReq]\aw Starting Adventure Request Loop...")

    while true do
        -- 1. Ensure the window is open
        if not mq.TLO.Window(WIN_NAME).Open() then
            print("\ay[LDoNReq]\aw Opening window via Right-Click...")
            mq.cmd("/click right target")
            mq.delay("3s", function() return mq.TLO.Window(WIN_NAME).Open() end)
        end

        if mq.TLO.Window(WIN_NAME).Open() then
            -- 2. Force the 'Type' Combobox to "Single Boss"
            mq.cmd("/nomodkey /notify AdventureRequestWnd AdvRqst_TypeCombobox listselect 2")
            mq.delay(200)

            -- 3. Click Request Adventure
            mq.TLO.Window(WIN_NAME .. "/AdvRqst_RequestButton"):LeftMouseUp()
            
            -- Wait for the text to appear from the server
            mq.delay(1000)

            -- 4. Safely read and convert the MQ object to a native Lua string
            local rawText = mq.TLO.Window(WIN_NAME .. "/AdvRqst_NPCText").Text()
            local desc = rawText and tostring(rawText) or ""
            
            -- 5. EDGE CASE: Cooldown / Zero Adventures
            if string.find(desc, "The number of adventures returned was zero") then
                print("\ar[LDoNReq]\aw Cooldown active (0 adventures). Closing window and retrying in 5 seconds...")
                mq.cmd("/windowstate AdventureRequestWnd close")
                mq.delay(5000)
            else
                local shouldAccept = false
                
                -- 6. Logic Switch: Butcherblock vs Everywhere Else
                if currentZone == "butcher" then
                    if string.find(desc, TARGET_NAME) then
                        print("\ag[LDoNReq]\aw Found " .. TARGET_NAME .. "! Accepting.")
                        shouldAccept = true
                    else
                        print("\ay[LDoNReq]\aw Wrong boss/mission. Declining...")
                    end
                else
                    print("\ag[LDoNReq]\aw Normal zone mode. Accepting first adventure.")
                    shouldAccept = true
                end

                -- 7. Action & Anti-Deadlock
                if shouldAccept then
                    mq.TLO.Window(WIN_NAME .. "/AdvRqst_AcceptButton"):LeftMouseUp()
                    print("\ag[LDoNReq]\aw Adventure Accepted. Stopping script.")
                    break
                else
                    mq.TLO.Window(WIN_NAME .. "/AdvRqst_DeclineButton"):LeftMouseUp()
                    
                    -- Wait for the server to process the decline
                    mq.delay(2000)
                    
                    -- Anti-Deadlock Check: If the window is still open but the button is grayed out
                    if mq.TLO.Window(WIN_NAME).Open() then
                        local declineBtn = mq.TLO.Window(WIN_NAME .. "/AdvRqst_DeclineButton")
                        
                        if declineBtn() and not declineBtn.Enabled() then
                            print("\ar[LDoNReq]\aw UI Deadlock detected! Forcing window closed to reset...")
                            mq.cmd("/windowstate AdventureRequestWnd close")
                            -- Give the UI a second to clear before the loop restarts
                            mq.delay(1000) 
                        end
                    end
                end
            end
        else
            print("\ar[LDoNReq]\aw Error: Window failed to open. Ensure you are close enough to the NPC.")
            break
        end
    end
end

requestAdventure()
