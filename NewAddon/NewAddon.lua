-- This addon is a template that helps developers create new addons.
-- Most parts can be removed or modified to need.

-- List of all Events we can use: https://wiki.esoui.com/Events
-- List of all API functions/calls we can use: https://wiki.esoui.com/Api
-- List of all textures/icons we can use (GUI/XML file resources): https://wiki.esoui.com/Texture_List
-- List of all accessible Global variables: https://wiki.esoui.com/Globals

-- First, we create a namespace for our addon by declaring a top-level table that will hold everything else.
NewAddon = {
    name            = "NewAddon",           -- Matches folder and Manifest file names.
    author          = "@Rite",
    menuName        = "New Addon",          -- A UNIQUE identifier for menu object.
}

-- This is our function to run once the mods have loaded. Triggered by the "EVENT_ADD_ON_LOADED" event as specified in our code.
function NewAddon.OnAddOnLoaded(event, addonName)
    -- The "EVENT_ADD_ON_LOADED" event fires each time *any* addon loads, but we only care about when our own addon loads.
    if addonName == NewAddon.name then
        NewAddon:Initialize()
    end
end

-- Our "main" code section that runs when our mod detects that it is now loaded.
function NewAddon:Initialize()
    -- We are telling it to wait for these events to occur to trigger the specified function.
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_READY, self.OnPlayerReady)
end

-- This is the first thing that runs and will start calling the chain of functions that our mod uses.
-- Run our "OnAddonLoaded" function when the mods finish loading.
EVENT_MANAGER:RegisterForEvent(NewAddon.name, EVENT_ADD_ON_LOADED, NewAddon.OnAddOnLoaded)