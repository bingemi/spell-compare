--[[
    backup_character.lua

    Backs up the current character's core data (equipment, inventory bags,
    personal bank, AAs, spellbook, memorized gems, currency) to a
    timestamped JSON file.

    Usage:
        /lua run backup_character

    Output:
        <MacroQuest config folder>/CharacterBackups/<Name>_<Server>_<timestamp>.json

    Notes:
        - AA scanning loops indexes 1..MAX_AA. Raise MAX_AA if your server's
          AA index range is higher than 3000.
        - Personal bank is included; shared bank is NOT, since it isn't
          reliably exposed via Lua TLOs on most MQ builds.
        - Some servers only populate bank data correctly with the bank
          window open - open it before running if bank data comes back empty.
        - Augments socketed in items (worn, bagged, or banked) are captured
          in each item's "augments" array.
]]

local mq = require('mq')

----------------------------------------------------------------------
-- Minimal JSON encoder (no external deps required)
----------------------------------------------------------------------
local function jsonEscape(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return s
end

local function isArray(t)
    local n = 0
    for k, _ in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    return n == #t
end

local function jsonEncode(val, indentLevel)
    indentLevel = indentLevel or 0
    local pad = string.rep('  ', indentLevel)
    local padInner = string.rep('  ', indentLevel + 1)

    local t = type(val)
    if val == nil then
        return 'null'
    elseif t == 'boolean' then
        return tostring(val)
    elseif t == 'number' then
        if val ~= val then return 'null' end -- NaN guard
        return tostring(val)
    elseif t == 'string' then
        return '"' .. jsonEscape(val) .. '"'
    elseif t == 'table' then
        if next(val) == nil then
            return '[]'
        end
        if isArray(val) then
            local parts = {}
            for _, v in ipairs(val) do
                table.insert(parts, padInner .. jsonEncode(v, indentLevel + 1))
            end
            return '[\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. ']'
        else
            local keys = {}
            for k, _ in pairs(val) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

            local parts = {}
            for _, k in ipairs(keys) do
                local v = val[k]
                table.insert(parts, padInner .. '"' .. jsonEscape(tostring(k)) .. '": ' .. jsonEncode(v, indentLevel + 1))
            end
            return '{\n' .. table.concat(parts, ',\n') .. '\n' .. pad .. '}'
        end
    else
        return 'null'
    end
end

----------------------------------------------------------------------
-- Helpers to safely pull TLO values (avoid nil/userdata surprises)
----------------------------------------------------------------------
local function safe(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

----------------------------------------------------------------------
-- Character meta / currency
----------------------------------------------------------------------
local function getMeta()
    return {
        name        = safe(function() return mq.TLO.Me.Name() end),
        server      = safe(function() return mq.TLO.MacroQuest.Server() end),
        level       = safe(function() return mq.TLO.Me.Level() end),
        class       = safe(function() return mq.TLO.Me.Class.Name() end),
        race        = safe(function() return mq.TLO.Me.Race() end),
        deity       = safe(function() return mq.TLO.Me.Deity() end),
        guild       = safe(function() return mq.TLO.Me.Guild() end),
        backup_date = os.date('%Y-%m-%d %H:%M:%S'),
    }
end

local function getCurrency()
    return {
        platinum = safe(function() return mq.TLO.Me.Platinum() end) or 0,
        gold     = safe(function() return mq.TLO.Me.Gold() end) or 0,
        silver   = safe(function() return mq.TLO.Me.Silver() end) or 0,
        copper   = safe(function() return mq.TLO.Me.Copper() end) or 0,
        bank = {
            platinum = safe(function() return mq.TLO.Inventory.Bank.Platinum() end) or 0,
            gold     = safe(function() return mq.TLO.Inventory.Bank.Gold() end) or 0,
            silver   = safe(function() return mq.TLO.Inventory.Bank.Silver() end) or 0,
            copper   = safe(function() return mq.TLO.Inventory.Bank.Copper() end) or 0,
        },
    }
end

----------------------------------------------------------------------
-- AAs: loop indexes, keep anything with Rank > 0
----------------------------------------------------------------------
local function getAAs()
    local result = {
        unspent_points = safe(function() return mq.TLO.Me.AAPoints() end) or 0,
        spent_points   = safe(function() return mq.TLO.Me.AAPointsSpent() end) or 0,
        abilities      = {},
    }

    local MAX_AA = 3000 -- raise this if your server has a larger AA pool
    for i = 1, MAX_AA do
        local aa = mq.TLO.Me.AltAbility(i)
        local rank = safe(function() return aa.Rank() end)
        if rank and rank > 0 then
            local name = safe(function() return aa.Name() end)
            if name and name ~= '' then
                table.insert(result.abilities, { name = name, rank = rank })
            end
        end
    end

    return result
end

----------------------------------------------------------------------
-- Equipment (worn slots 0-22)
----------------------------------------------------------------------
local WORN_SLOTS = {
    [0] = 'Charm', [1] = 'Left Ear', [2] = 'Head', [3] = 'Face',
    [4] = 'Right Ear', [5] = 'Neck', [6] = 'Shoulders', [7] = 'Arms',
    [8] = 'Back', [9] = 'Left Wrist', [10] = 'Right Wrist', [11] = 'Ranged',
    [12] = 'Hands', [13] = 'Primary', [14] = 'Secondary', [15] = 'Left Finger',
    [16] = 'Right Finger', [17] = 'Chest', [18] = 'Legs', [19] = 'Feet',
    [20] = 'Waist', [21] = 'Power Source', [22] = 'Ammo',
}

local MAX_AUG_SLOTS = 6 -- max possible augment sockets on any item

local function getAugments(item)
    local augs = {}
    local augCount = safe(function() return item.Augs() end) or 0
    if augCount == 0 then return augs end

    for slot = 1, MAX_AUG_SLOTS do
        local augItem = item.Item(slot)
        local id = safe(function() return augItem.ID() end)
        if id then
            table.insert(augs, {
                slot = slot,
                name = safe(function() return augItem.Name() end),
                id   = id,
            })
        end
    end
    return augs
end

local function getItemTable(item)
    if not item or not safe(function() return item.ID() end) then return nil end
    local data = {
        name    = safe(function() return item.Name() end),
        id      = safe(function() return item.ID() end),
        charges = safe(function() return item.Charges() end),
        stack   = safe(function() return item.Stack() end),
    }
    local augs = getAugments(item)
    if #augs > 0 then
        data.augments = augs
    end
    return data
end

local function getEquipment()
    local equipment = {}
    for slotNum, slotName in pairs(WORN_SLOTS) do
        local item = mq.TLO.Me.Inventory(slotNum)
        local itemData = getItemTable(item)
        if itemData then
            itemData.slot = slotName
            table.insert(equipment, itemData)
        end
    end
    return equipment
end

----------------------------------------------------------------------
-- General inventory bags (pack1-pack10 == inventory slots 23-32)
----------------------------------------------------------------------
local function getInventoryBags()
    local bags = {}
    for packNum = 1, 10 do
        local packName = 'pack' .. packNum
        local container = mq.TLO.Me.Inventory(packName)
        local containerData = getItemTable(container)

        local bagEntry = {
            bag_slot = packNum,
            container_name = containerData and containerData.name or nil,
            items = {},
        }

        if containerData then
            local size = safe(function() return container.Container() end) or 0
            for sub = 1, size do
                local subItem = container.Item(sub)
                local subData = getItemTable(subItem)
                if subData then
                    subData.bag_position = sub
                    table.insert(bagEntry.items, subData)
                end
            end
        end

        table.insert(bags, bagEntry)
    end
    return bags
end

----------------------------------------------------------------------
-- Spellbook (known spells) and currently memorized gems
----------------------------------------------------------------------
local function getSpellbook()
    local spells = {}
    for i = 1, 720 do -- generous upper bound on spellbook slots
        local name = safe(function() return mq.TLO.Me.Book(i)() end)
        if name and name ~= '' then
            table.insert(spells, { book_slot = i, name = name })
        end
    end
    return spells
end

local function getMemorizedSpells()
    local gems = {}
    for i = 1, 16 do -- covers modern gem counts; harmless if server has fewer
        local name = safe(function() return mq.TLO.Me.Gem(i)() end)
        if name and name ~= '' then
            table.insert(gems, { gem_slot = i, name = name })
        end
    end
    return gems
end

----------------------------------------------------------------------
-- Personal bank (primary bank slots only - shared bank not included,
-- as it isn't reliably exposed via Lua TLOs on most MQ builds).
-- Some servers only populate bank data correctly with the bank window
-- open, so open it before running this script if bank data comes back empty.
----------------------------------------------------------------------
local function getBank()
    local baseSlots = safe(function() return mq.TLO.Inventory.Bank.BagSlots() end) or 24

    local bank = {}
    for slotNum = 1, baseSlots do
        local item = mq.TLO.Me.Bank(slotNum)
        local itemData = getItemTable(item)

        local bankEntry = {
            bank_slot = slotNum,
            container_name = itemData and itemData.name or nil,
            item = itemData, -- present if this slot holds a non-container item directly
            items = {},
        }

        if itemData then
            local size = safe(function() return item.Container() end) or 0
            if size > 0 then
                bankEntry.item = nil -- it's a bag, contents go in items instead
                for sub = 1, size do
                    local subItem = item.Item(sub)
                    local subData = getItemTable(subItem)
                    if subData then
                        subData.bag_position = sub
                        table.insert(bankEntry.items, subData)
                    end
                end
            end
        end

        table.insert(bank, bankEntry)
    end
    return bank
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------
local function main()
    if not mq.TLO.Me.Name() then
        print('\arbackup_character: character is not fully loaded in, aborting.')
        return
    end

    print('\ayBacking up character data, this may take a few seconds...')

    local data = {
        meta          = getMeta(),
        currency      = getCurrency(),
        aa            = getAAs(),
        equipment     = getEquipment(),
        inventory     = getInventoryBags(),
        bank          = getBank(),
        spellbook     = getSpellbook(),
        memorized     = getMemorizedSpells(),
    }

    local json = jsonEncode(data)

    local outDir = mq.configDir .. '/CharacterBackups'
    os.execute('mkdir "' .. outDir .. '"') -- no-op if it already exists

    local fileName = string.format(
        '%s_%s_%s.json',
        data.meta.name or 'Unknown',
        data.meta.server or 'server',
        os.date('%Y%m%d_%H%M%S')
    )
    local fullPath = outDir .. '/' .. fileName

    local file, err = io.open(fullPath, 'w')
    if not file then
        print('\arFailed to open file for writing: ' .. tostring(err))
        return
    end

    file:write(json)
    file:close()

    print('\agCharacter backup saved to: ' .. fullPath)
end

main()