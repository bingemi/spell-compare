local mq = require('mq')

-- List of all possible necklace names to check for
local possibleNecklaces = {
    "Amulet of Necropotence",
    "Amulet of Necropotence (Enhanced)",
    "Amulet of Necropotence (Exalted)",
    "Amulet of Necropotence (Ascendant)"
}

local buffName = "Illusion: Skeleton"

-- Helper function to scan inventory/worn items for the amulet
local function getAvailableNecklace()
    for _, name in ipairs(possibleNecklaces) do
        -- Added '=' to force an EXACT match, preventing partial string bugs
        local item = mq.TLO.FindItem("=" .. name)
        
        if item() then
            -- Return the exact name natively registered by MQ
            return item.Name()
        end
    end
    return nil
end

local function main()
    printf("\ag[Door Clipper]\aw Starting clipping sequence...")
    
    -- Dynamically figure out which amulet we have before starting
    local necklaceName = getAvailableNecklace()
    if not necklaceName then
        printf("\ar[Door Clipper]\aw ERROR: Could not find an Amulet of Necropotence on your character!")
        return -- Abort so we don't end up stuck without the clicky
    end

    printf("\ag[Door Clipper]\aw Found amulet: \ay%s", necklaceName)

    -- Step 1: Move forward for 3 seconds
    printf("\ag[Door Clipper]\aw Pushing into the door...")
    mq.cmd('/keypress forward hold')
    mq.delay(1000)
    mq.cmd('/keypress forward')

    -- Step 2: Turn right ~90 degrees
    printf("\ag[Door Clipper]\aw Turning 90 degrees right...")
    local currentHeading = mq.TLO.Me.Heading.Degrees()
    local newHeading = (currentHeading + 90) % 360
    mq.cmdf('/face heading %f', newHeading)
    mq.delay(200)

    -- Step 3: Turn off Illusion: Skeleton
    if mq.TLO.Me.Buff(buffName)() then
        printf("\ag[Door Clipper]\aw Removing buff: %s...", buffName)
        mq.cmdf('/removebuff "%s"', buffName)
        mq.delay(500)
    else
        printf("\ay[Door Clipper]\aw Warning: %s buff not found.", buffName)
    end

    -- Step 4: Strafe left for 1 second to pin left arm
    printf("\ag[Door Clipper]\aw Pushing left arm into the wall...")
    mq.cmd('/keypress strafe_left hold')
    mq.delay(1000)
    mq.cmd('/keypress strafe_left')
    mq.delay(200)

    -- Step 5: Use fear necklace to re-cast illusion
    printf("\ag[Door Clipper]\aw Clicking %s...", necklaceName)
    mq.cmdf('/useitem "%s"', necklaceName)
    
    mq.delay(500)
    while mq.TLO.Me.Casting.ID() do
        mq.delay(10)
    end
    mq.delay(200)

    -- Step 6: Strafe left for 2 seconds to clip through
    printf("\ag[Door Clipper]\aw Forcing model through the door...")
    mq.cmd('/keypress strafe_left hold')
    mq.delay(1000)
    mq.cmd('/keypress strafe_left')

    printf("\ag[Door Clipper]\aw Sequence complete. You should be on the other side!")
end

main()
