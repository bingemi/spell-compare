local mq = require('mq')

printf("\ag[Trader]\ax Starting Bazaar Auto-Pricer...")

-- 1. Ensure the necessary windows are actually open
if not mq.TLO.Window("BazaarWnd").Open() then
    printf("\ar[Trader]\ax Please open your Bazaar Vendor window first!")
    return
end

if not mq.TLO.Window("BazaarSearchWnd").Open() then
    mq.cmd("/bazaar")
    mq.delay(1000) 
end

-- 2. Reset Bazaar search filters to default to guarantee accurate searches
if mq.TLO.Window("BazaarSearchWnd/BZR_Default")() then
    mq.cmd("/nomodkey /notify BazaarSearchWnd BZR_Default leftmouseup")
    mq.delay(200)
end

-- Helper to isolate the base item name
local function getBaseName(name)
    return name:gsub("%s*%([^%)]+%)$", "")
end

-- 3. Loop through all 200 possible trader slots
for i = 0, 199 do
    local slotName = "BZR_BazaarSlot" .. i
    local slotWindow = mq.TLO.Window("BazaarWnd/" .. slotName)
    
    -- Check if the slot actually has an item by verifying its tooltip
    if slotWindow() and slotWindow.Tooltip() and slotWindow.Tooltip() ~= "" and slotWindow.Tooltip() ~= "Empty" then
        local tooltipName = slotWindow.Tooltip()
        local baseName = getBaseName(tooltipName)
        
        printf("\ag[Trader]\ax Pricing: %s (Slot %d)", baseName, i)
        
        -- Inject the name into the search box
        mq.TLO.Window("BazaarSearchWnd/BZR_ItemNameInput").SetText(baseName)
        mq.delay(200)
        
        -- Safely wait for the search button to be clickable
        while not mq.TLO.Window("BazaarSearchWnd/BZR_QueryButton").Enabled() do
            mq.delay(100)
        end
        
        -- Click "Find Items"
        mq.cmd("/nomodkey /notify BazaarSearchWnd BZR_QueryButton leftmouseup")
        
        -- Wait for it to disable, then wait for it to re-enable (handles the 5-second server timeout)
        mq.delay(500) 
        while not mq.TLO.Window("BazaarSearchWnd/BZR_QueryButton").Enabled() do
            mq.delay(100)
        end
        mq.delay(500) 
        
        -- Parse the Search Results
        local list = mq.TLO.Window("BazaarSearchWnd/BZR_ItemList")
        local listCount = list.Items()
        local minPrice = 999999999
        
        if listCount and listCount > 0 then
            for row = 1, listCount do
                local nameStr = list.List(row, 2)() -- Column 2 is Item Name
                
                -- Ensure we only match the exact base name
                if nameStr and getBaseName(nameStr) == baseName then
                    local traderName = list.List(row, 8)() -- Column 8 is Trader Name
                    
                    -- Ignore our own listings so we don't undercut ourselves
                    if traderName and traderName ~= mq.TLO.Me.CleanName() then
                        local platStr = list.List(row, 4)() -- Column 4 is Platinum
                        if platStr then
                            local plat = tonumber((platStr:gsub(",", ""))) or 0
                            if plat > 0 and plat < minPrice then
                                minPrice = plat
                            end
                        end
                    end
                end
            end
        end
        
        -- Calculate the undercut and set the new price
        if minPrice < 999999999 then
            local newPrice = minPrice
            
            if minPrice < 500 then
                newPrice = minPrice - 50
            elseif minPrice < 1000 then
                newPrice = minPrice - 100
            elseif minPrice < 10000 then
                newPrice = minPrice - 500
            else
                newPrice = minPrice - 1000
            end
            
            if newPrice < 1 then newPrice = 1 end
            
            printf("\ag[Trader]\ax Lowest competitor is %dpp. Undercutting to %dpp.", minPrice, newPrice)
            
            -- A. Click the item slot in your vendor window to select it
            mq.cmd("/nomodkey /notify BazaarWnd " .. slotName .. " leftmouseup")
            mq.delay(300)
            
            -- B. Click the Platinum button to spawn the Quantity Window
            mq.cmd("/nomodkey /notify BazaarWnd BZW_Money0 leftmouseup")
            mq.delay(300)
            
            -- C. Inject the price, accept it, and set the price on the Bazaar UI
            if mq.TLO.Window("QuantityWnd").Open() then
                mq.cmd("/nomodkey /notify QuantityWnd QTYW_SliderInput leftmouseup")
                mq.delay(100)
                mq.TLO.Window("QuantityWnd/QTYW_SliderInput").SetText(tostring(newPrice))
                mq.delay(200)
                
                mq.cmd("/nomodkey /notify QuantityWnd QTYW_Accept_Button leftmouseup")
                mq.delay(300)
                
                mq.cmd("/nomodkey /notify BazaarWnd BZW_SetPrice_Button leftmouseup")
                mq.delay(300)
            else
                printf("\ar[Trader]\ax Error: The Quantity Window did not open for %s!", baseName)
            end
        else
            printf("\ay[Trader]\ax No competitors found for %s. Skipping adjustment.", baseName)
        end
    end
end

printf("\ag[Trader]\ax Auto-Pricing Complete!")
