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
        - AA scanning loops indexes 1..MAX_AA (currently 32000, based on this
          server's `SELECT MAX(id) FROM aa_ability` = 31101). If you move to
          a different server, re-check that value and adjust MAX_AA.
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

    local MAX_AA = 32000 -- confirmed via `SELECT MAX(id) FROM aa_ability;` = 31101, padded for future content
    for i = 1, MAX_AA do
        local aa = mq.TLO.Me.AltAbility(i)
        local rank = safe(function() return aa.Rank() end)
        if rank and rank > 0 then
            local name = safe(function() return aa.Name() end)
            if name and name ~= '' then
                table.insert(result.abilities, {
                    name      = name,
                    rank      = rank,
                    group_id  = i, -- unique per AA line; distinguishes same-named abilities that are actually different lines
                    max_rank  = safe(function() return aa.MaxRank() end), -- static design max, NOT filtered per-character
                    category  = safe(function() return aa.Category() end),
                    short_name = safe(function() return aa.ShortName() end),
                })
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
-- LDoN (Legends of Norrath adventures)
-- Points earned per theme come from the character TLO (always available).
-- Win/loss counts are NOT exposed via any character TLO - the only place
-- that data exists is the "Adventure Stats" UI window (Alt+V -> View
-- Stats). We read it directly from the window's listbox if it happens to
-- be open. This is a real (non-OCR) technique - MQ can read text out of
-- UI list controls - but it only works while that window is open, and
-- could break if a server uses a heavily customized UI that renames the
-- window/listbox. If it's not open, we note that clearly rather than
-- silently omitting the data.
----------------------------------------------------------------------
local function getLDoNThemeStats()
    local statsWnd = mq.TLO.Window('AdventureStatsWnd')
    local isOpen = safe(function() return statsWnd.Open() end)

    if not isOpen then
        return {
            available = false,
            note = 'AdventureStatsWnd was not open. In-game, press Alt+V, click "View Stats", then re-run this script to capture win/loss counts per theme.',
        }
    end

    local themeList = statsWnd.Child('AdvStats_ThemeList')
    local rowCount = safe(function() return themeList.Items() end) or 0
    local themes = {}

    for row = 1, rowCount do
        local cols = {}
        for col = 1, 7 do
            cols[col] = safe(function() return themeList.List(row, col)() end)
        end
        table.insert(themes, {
            theme           = cols[1],
            rank            = cols[2],
            wins            = cols[3],
            losses          = cols[4],
            success_percent = cols[5],
            total_points    = cols[7],
            raw_columns     = cols, -- fallback if column layout differs on your server's UI
        })
    end

    return { available = true, themes = themes }
end

local function getLDoN()
    return {
        total_points = safe(function() return mq.TLO.Me.LDoNPoints() end) or 0,
        earned_by_theme = {
            deepest_guk         = safe(function() return mq.TLO.Me.GukEarned() end) or 0,
            miraguls_menagerie  = safe(function() return mq.TLO.Me.MMEarned() end) or 0,
            rujarkian_hills     = safe(function() return mq.TLO.Me.RujEarned() end) or 0,
            takish_hiz          = safe(function() return mq.TLO.Me.TakEarned() end) or 0,
            mistmoore_catacombs = safe(function() return mq.TLO.Me.MirEarned() end) or 0,
        },
        theme_stats = getLDoNThemeStats(),
    }
end

----------------------------------------------------------------------
-- Skills - the full canonical skill name list per MacroQuest's docs.
-- Me.Skill[name] returns 0 for skills your class/race can't use, so we
-- only keep the ones that are actually trained/usable.
----------------------------------------------------------------------
local SKILL_NAMES = {
    '1H Blunt', '1H Slashing', '2H Blunt', '2H Slashing', 'Abjuration',
    'Alchemy', 'Alcohol Tolerance', 'Alteration', 'Apply Poison', 'Archery',
    'Backstab', 'Baking', 'Bash', 'Begging', 'Berserking', 'Bind Wound',
    'Blacksmithing', 'Block', 'Brass Instruments', 'Brewing', 'Channeling',
    'Conjuration', 'Defense', 'Disarm', 'Disarm Traps', 'Divination',
    'Dodge', 'Double Attack', 'Dragon Punch', 'Duel Wield', 'Eagle Strike',
    'Evocation', 'Feign Death', 'Fishing', 'Fletching', 'Flying Kick',
    'Forage', 'Frenzy', 'Hand To Hand', 'Hide', 'Intimidation',
    'Jewelry Making', 'Kick', 'Make Poison', 'Meditate', 'Mend', 'Offense',
    'Parry', 'Percussion Instruments', 'Pick Lock', 'Pick Pockets',
    'Piercing', 'Pottery', 'Research', 'Riposte', 'Round Kick', 'Safe Fall',
    'Sense Heading', 'Sense Traps', 'Sing', 'Slam', 'Sneak',
    'Specialize Abjure', 'Specialize Alteration', 'Specialize Conjuration',
    'Specialize Divination', 'Specialize Evocation', 'Stringed Instruments',
    'Tailoring', 'Taunt', 'Throwing', 'Tiger Claw', 'Tinkering', 'Tracking',
    'Wind Instruments',
}

local function getSkills()
    local skills = {}
    for _, skillName in ipairs(SKILL_NAMES) do
        local value = safe(function() return mq.TLO.Me.Skill(skillName)() end)
        if value and value > 0 then
            skills[skillName] = value
        end
    end
    return skills
end

----------------------------------------------------------------------
-- Keyrings (mounts, illusions, familiars)
----------------------------------------------------------------------
local function getKeyringSection(keyringTLO)
    local count = safe(function() return keyringTLO().Count() end) or 0
    local items = {}
    for i = 1, count do
        local kri = keyringTLO(i)
        table.insert(items, {
            index = i,
            name  = safe(function() return kri.Name() end),
            id    = safe(function() return kri.Item.ID() end),
        })
    end
    return items
end

local function getKeyrings()
    return {
        mounts    = getKeyringSection(mq.TLO.Mount),
        illusions = getKeyringSection(mq.TLO.Illusion),
        familiars = getKeyringSection(mq.TLO.Familiar),
    }
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

    local ldonData = getLDoN()
    if not ldonData.theme_stats.available then
        print('\ayNote: LDoN win/loss data was unavailable. ' .. ldonData.theme_stats.note)
    end

    local data = {
        meta          = getMeta(),
        currency      = getCurrency(),
        aa            = getAAs(),
        equipment     = getEquipment(),
        inventory     = getInventoryBags(),
        bank          = getBank(),
        ldon          = ldonData,
        skills        = getSkills(),
        keyrings      = getKeyrings(),
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
