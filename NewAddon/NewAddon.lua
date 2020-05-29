--[[
    This addon is a template that helps developers create new addons.
    Most parts can be removed or modified to need.
--]]

-- List of all Events we can use: https://wiki.esoui.com/Events
-- List of all API functions/calls we can use: https://wiki.esoui.com/Api
-- List of all textures/icons we can use (GUI/XML file resources): https://wiki.esoui.com/Texture_List
-- List of all accessible Global variables (probably won't use these directly?): https://wiki.esoui.com/Globals

NewAddon = {
    name            = "NewAddon",           -- Matches folder and Manifest file names.
    -- version         = "1.0",                -- A nuisance to match to the Manifest.
    author          = "Developer",
    color           = "DDFFEE",             -- Used in menu titles and so on.
    menuName        = "New Addon",          -- A UNIQUE identifier for menu object.
}

-- Default settings.
NewAddon.savedVars = {
    firstLoad = true,                   -- First time the addon is loaded ever.
    accountWide = false,                -- Load settings from account savedVars, instead of character.
}

-- Wraps text with a color.
function NewAddon.Colorize(text, color)
    -- Default to addon's .color.
    if not color then color = NewAddon.color end

    text = string.format('|c%s%s|r', color, text)

    return text
end

function NewAddon.AnimateText()
    -- Avoid playing the animation over itself.
    if not NewAddonActive:IsHidden() then return end

    local animation, timeline = CreateSimpleAnimation(ANIMATION_ALPHA, NewAddonActive)

    NewAddonActive:SetHidden(false)
    animation:SetAlphaValues(NewAddonActive:GetAlpha(), 1)
    animation:SetDuration(3000)

    -- Fade-out after fade-in.
    timeline:SetHandler('OnStop', function()
        local animation, timeline = CreateSimpleAnimation(ANIMATION_ALPHA, NewAddonActive)

        animation:SetAlphaValues(NewAddonActive:GetAlpha(), 0)
        animation:SetDuration(3000)

        timeline:SetHandler('OnStop', function()
            NewAddonActive:SetHidden(true)
        end)

        timeline:PlayFromStart()
    end)

    timeline:PlayFromStart()
end

-- Only show the loading message on first load ever.
function NewAddon.Activated(e)
    EVENT_MANAGER:UnregisterForEvent(NewAddon.name, EVENT_PLAYER_ACTIVATED)

    if NewAddon.savedVars.firstLoad then
        NewAddon.savedVars.firstLoad = false

        d(NewAddon.name .. GetString(SI_NEW_ADDON_MESSAGE)) -- Prints to chat.

        ZO_AlertNoSuppression(UI_ALERT_CATEGORY_ALERT, nil,
            NewAddon.name .. GetString(SI_NEW_ADDON_MESSAGE)) -- Top-right alert.

        -- Animate the xml UI center text, after a delay.
        zo_callLater(NewAddon.AnimateText, 3000)
    end
end
-- When player is ready, after everything has been loaded.
EVENT_MANAGER:RegisterForEvent(NewAddon.name, EVENT_PLAYER_ACTIVATED, NewAddon.Activated)

function NewAddon.OnAddOnLoaded(event, addonName)
    if addonName ~= NewAddon.name then return end
    EVENT_MANAGER:UnregisterForEvent(NewAddon.name, EVENT_ADD_ON_LOADED)

    -- Load saved variables.
    NewAddon.characterSavedVars = ZO_SavedVars:New("NewAddonSavedVariables", 1, nil, NewAddon.savedVars)
    NewAddon.accountSavedVars = ZO_SavedVars:NewAccountWide("NewAddonSavedVariables", 1, nil, NewAddon.savedVars)

    if not NewAddon.characterSavedVars.accountWide then
        NewAddon.savedVars = NewAddon.characterSavedVars
    else
        NewAddon.savedVars = NewAddon.accountSavedVars
    end

    -- Settings menu in Settings.lua.
    NewAddon.LoadSettings()

    -- Slash commands must be lowercase!!! Set to nil to disable.
    SLASH_COMMANDS["/newaddon"] = NewAddon.AnimateText

    -- The following is only needed when changing SLASH_COMMANDS live,
    -- but not when loading addons, starting with 100030.
    -- CHAT_SYSTEM.textEntry.slashCommandAutoComplete:InvalidateSlashCommandCache()
end
-- When any addon is loaded, but before UI (Chat) is loaded.
EVENT_MANAGER:RegisterForEvent(NewAddon.name, EVENT_ADD_ON_LOADED, NewAddon.OnAddOnLoaded)