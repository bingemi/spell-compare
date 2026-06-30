local mq = require('mq')
local imgui = require('ImGui')

-- Script state
local openGUI = true
local shouldExit = false

-- Timer dictionary storing expiration timestamp (os.time())
-- 0 means no active timer
local timers = {
    MM = 0,
    CL = 0,
    EF = 0,
    NR = 0,
    SR = 0
}

-- Total duration in seconds for each active timer (for progress bar)
local timerDurations = {
    MM = 0,
    CL = 0,
    EF = 0,
    NR = 0,
    SR = 0
}

-- Tracks the last remaining-second we announced to avoid spamming chat
local last_announced = {
    MM = -1, CL = -1, EF = -1, NR = -1, SR = -1
}

-- Maps the current instance zone to your UI categories
local function getActiveLDoNTheme()
    local zone = mq.TLO.Zone.ShortName():lower()
    if string.find(zone, "^mmc") then return "MM" end
    if string.find(zone, "^ruj") then return "CL" end
    if string.find(zone, "^mir") then return "EF" end
    if string.find(zone, "^tak") then return "NR" end
    if string.find(zone, "^guk") then return "SR" end
    return nil
end

-- Formats seconds into MM:SS
local function formatTime(secondsLeft)
    if secondsLeft <= 0 then return "0:00" end
    local m = math.floor(secondsLeft / 60)
    local s = secondsLeft % 60
    return string.format("%d:%02d", m, s)
end

-- Event triggered when adventure succeeds
local function onAdventureSuccess()
    local theme = getActiveLDoNTheme()
    if theme then
        local duration = 30 * 60 -- 30 minutes
        timers[theme] = os.time() + duration
        timerDurations[theme] = duration
        last_announced[theme] = -1            -- Reset announcement state
        print('\ar[LDoN Timers]\aw Success detected. Started 30 min timer for ' .. theme)
    else
        print('\ar[LDoN Timers]\aw Adventure success detected, but could not determine LDoN theme from current zone.')
    end
end

-- Bind the event to the standard LDoN success text
-- Note: Adjust this string if your specific server uses a slightly different success message
mq.event("LDoNSuccess", "#*#You have successfully completed your adventure#*#", onAdventureSuccess)

-- Handles checking times and outputting to /g
local function checkAnnouncements()
    local now = os.time()
    for theme, expireTime in pairs(timers) do
        if expireTime > 0 then
            local remaining = expireTime - now
            
            if remaining > 0 and remaining <= 300 then
                local announce = false
                
                if remaining <= 10 then
                    -- Under 10 seconds: spam every 1 second
                    if last_announced[theme] ~= remaining then
                        announce = true
                    end
                elseif remaining <= 60 then
                    -- Under 1 minute: every 10 seconds
                    if remaining % 10 == 0 and last_announced[theme] ~= remaining then
                        announce = true
                    end
                else
                    -- Under 5 minutes: every 30 seconds
                    if remaining % 30 == 0 and last_announced[theme] ~= remaining then
                        announce = true
                    end
                end
                
                if announce then
                    mq.cmd(string.format("/g %s LDoN timer: %s remaining!", theme, formatTime(remaining)))
                    last_announced[theme] = remaining
                end
            elseif remaining <= 0 then
                -- Timer hit zero, announce and clear it
                timers[theme] = 0
                timerDurations[theme] = 0
                mq.cmd(string.format("/g %s LDoN timer is UP!", theme))
            end
        end
    end
end

-- ImGui rendering for the compact window
local function renderUI()
    if not openGUI then return end

    imgui.SetNextWindowSize(220, 0, ImGuiCond.FirstUseEver)

    openGUI, shouldDraw = imgui.Begin("LDoN", openGUI)
    if shouldDraw then
        local now = os.time()
        
        -- Lock display order to match your example
        local displayOrder = {"MM", "CL", "EF", "NR", "SR"}
        
        for _, theme in ipairs(displayOrder) do
            local expireTime = timers[theme]
            local remaining = 0
            if expireTime > 0 then
                remaining = expireTime - now
                if remaining < 0 then remaining = 0 end
            end
            
            local duration = timerDurations[theme]
            local fraction = duration > 0 and remaining / duration or 0
            imgui.Text(string.format("%s:", theme))
            imgui.SameLine(40)
            imgui.PushStyleColor(ImGuiCol.PlotHistogram, ImVec4(0.4, 0.7, 1.0, 1.0))
            imgui.ProgressBar(fraction, -1, 0, "")
            imgui.PopStyleColor()
            local drawList = imgui.GetWindowDrawList()
            local barMinX, barMinY = imgui.GetItemRectMin()
            local _, barMaxY = imgui.GetItemRectMax()
            drawList:AddText(ImVec2(barMinX + 4, barMinY + (barMaxY - barMinY - imgui.GetTextLineHeight()) / 2), IM_COL32(255, 255, 255, 255), formatTime(remaining))
        end
        
        imgui.Separator()
        
        -- Stop button
        if imgui.Button("Close Script") then
            shouldExit = true
        end
    end
    imgui.End()
    
    -- If they click the 'X' in the top right of the ImGui window
    if not openGUI then
        shouldExit = true
    end
end

-- Initialize UI
mq.imgui.init('LDoNTimerUI', renderUI)

print('\ar[LDoN Timers]\aw Script started. Type \a-y/lua stop ldon_timers\aw or click "Close Script" on the UI to end.')

-- Main loop
while not shouldExit do
    mq.doevents()
    checkAnnouncements()
    mq.delay(100) -- Prevents the script from consuming too much CPU
end

-- Cleanup when script ends
mq.imgui.destroy('LDoNTimerUI')
