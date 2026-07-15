local mq = require('mq')
local ImGui = require('ImGui')

local isOpen = true
local itemList = {}
local currentIndex = 1

local pendingBazaarSearch = nil

local args = {...}
if #args == 0 then
    printf("\ag[ItemLookup]\ax Please provide bag numbers (e.g., /lua run ItemLookup 1,3,4)")
    return
end

local bagListStr = tostring(args[1])
for bagNumStr in string.gmatch(bagListStr, '([^,]+)') do
    local bagNum = tonumber(bagNumStr)
    if bagNum then
        local packSlotName = "pack" .. bagNum
        local packItem = mq.TLO.InvSlot(packSlotName).Item
        
        if packItem() and packItem.Container() > 0 then
            local capacity = packItem.Container()
            for slot = 1, capacity do
                local item = packItem.Item(slot)
                if item() then
                    table.insert(itemList, {
                        name = item.Name(),
                        id = item.ID(),
                        link = item.ItemLink('CLICKABLE')() 
                    })
                end
            end
        end
    end
end

if #itemList == 0 then
    printf("\ar[ItemLookup]\ax No items found in the specified bags.")
    return
end

local function getBaseName(name)
    return name:gsub("%s*%([^%)]+%)$", "")
end

local function getModifiedID(name, id)
    local idStr = tostring(id)
    
    if name:match("%(Enhanced%)$") or name:match("%(Exalted%)$") then
        return "7" .. idStr:sub(2)
    elseif name:match("%(Ascendant%)$") then
        return idStr
    else
        return "7" .. idStr
    end
end

local function drawGUI()
    if not isOpen then return end

    local shouldDraw
    isOpen, shouldDraw = ImGui.Begin("Item Lookup Processor", isOpen)
    
    if shouldDraw then
        if currentIndex <= #itemList then
            local currentItem = itemList[currentIndex]
            local baseName = getBaseName(currentItem.name)
            local allaId = getModifiedID(currentItem.name, currentItem.id)
            
            ImGui.TextColored(ImVec4(0, 1, 1, 1), "Item %d of %d", currentIndex, #itemList)
            ImGui.Separator()
            
            ImGui.Text("Current Item: " .. currentItem.name)
            ImGui.Text("Original ID: " .. tostring(currentItem.id))
            ImGui.Text("Ascendant ID: " .. tostring(allaId))
            ImGui.Text("Base Name: " .. baseName)
            
            ImGui.Separator()
            
            if ImGui.Button("1. Open Allaclone Website") then
                local url = string.format("https://allaclone.lanoel.com/items/%s", allaId)
                os.execute(string.format('start "" "%s"', url))
            end
            
            if ImGui.Button("2. Print Ascendant Link to Chat") then
                local oldId = currentItem.id
                local newId = tonumber(allaId)
                local newName = baseName .. " (Ascendant)"
                local linkStr = currentItem.link
                
                -- Escape any special Lua pattern characters in the item name
                local escapedName = currentItem.name:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
                
                -- Use the exact item name as the anchor to split the string
                local prefix, hexData, suffix = linkStr:match("^(.)(.-)" .. escapedName .. "(.*)$")
                
                if prefix and hexData and suffix then
                    local oldHex6 = string.format("%06X", oldId)
                    local oldHex5 = string.format("%05X", oldId)
                    local newHexData = hexData
                    
                    -- Swap the old ID out for the new ID in the hex data
                    if hexData:sub(1, 6):upper() == oldHex6:upper() then
                        newHexData = string.format("%06X", newId) .. hexData:sub(7)
                    elseif hexData:sub(1, 5):upper() == oldHex5:upper() then
                        newHexData = string.format("%05X", newId) .. hexData:sub(6)
                    else
                        local oldHexRaw = string.format("%X", oldId)
                        local matchStart, matchEnd = hexData:upper():find(oldHexRaw:upper(), 1, true)
                        if matchStart == 1 then
                            local padLen = matchEnd - matchStart + 1
                            local newHexFormat = "%0" .. padLen .. "X"
                            newHexData = string.format(newHexFormat, newId) .. hexData:sub(matchEnd + 1)
                        end
                    end
                    
                    -- Reconstruct the forged link
                    local ascendantLink = prefix .. newHexData .. newName .. suffix
                    printf("\ag[ItemLookup]\ax Ascendant Version: %s", ascendantLink)
                else
                    printf("\ar[ItemLookup]\ax Could not parse original link string. Name anchor failed.")
                end
            end
            
            if ImGui.Button("3. Search Base Name in Bazaar") then
                pendingBazaarSearch = baseName
            end
            
            ImGui.Separator()
            
            if ImGui.Button("Next Item ->") then
                currentIndex = currentIndex + 1
            end
            
        else
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "Finished processing all items!")
            if ImGui.Button("Close") then
                isOpen = false
            end
        end
    end
    
    ImGui.End()
end

mq.imgui.init('ItemLookupGUI', drawGUI)

while isOpen do
    if pendingBazaarSearch then
        if not mq.TLO.Window("BazaarSearchWnd").Open() then
            mq.cmd("/bazaar")
            mq.delay(200) 
        end
        
        if mq.TLO.Window("BazaarSearchWnd/BZR_ItemNameInput")() then
            mq.TLO.Window("BazaarSearchWnd/BZR_ItemNameInput").SetText(pendingBazaarSearch)
            mq.delay(200) 
            mq.cmd("/notify BazaarSearchWnd BZR_QueryButton leftmouseup")
        else
            printf("\ar[ItemLookup]\ax Could not find the Bazaar search box.")
        end
        
        pendingBazaarSearch = nil
    end

    mq.delay(10)
    mq.doevents()
end
