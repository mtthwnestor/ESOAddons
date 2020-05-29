-- List of all Events we can use: https://wiki.esoui.com/Events
-- List of all API functions/calls we can use: https://wiki.esoui.com/Api
-- List of all textures/icons we can use (GUI/XML file resources): https://wiki.esoui.com/Texture_List
-- List of all accessible Global variables (probably won't use these directly?): https://wiki.esoui.com/Globals

-- First, we create a namespace for our addon by declaring a top-level table that will hold everything else.
DeconstructIntricateItems = {
  name            = "DeconstructIntricateItems",           -- Matches folder and Manifest file names.
  author          = "@Rite",
  menuName        = "Deconstruct Intricate Items",          -- A UNIQUE identifier for menu object.
}

-- This is our function to run once the mods have loaded. Triggered by the "EVENT_ADD_ON_LOADED" event as specified in our code.
function DeconstructIntricateItems.OnAddOnLoaded(event, addonName)
  -- The "EVENT_ADD_ON_LOADED" event fires each time *any* addon loads, but we only care about when our own addon loads.
  if addonName == DeconstructIntricateItems.name then
    DeconstructIntricateItems:Initialize()

    -- Start with our on-screen icon disabled.
    DeconstructIntricateItemsIndicator:SetHidden(true)
  end
end

-- Our "main" code section that runs when our mod detects that it is now loaded.
function DeconstructIntricateItems:Initialize()
  -- We are telling it to wait for these events to occur to trigger the specified function.
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CRAFTING_STATION_INTERACT, self.OnCraftingStationStart)
  EVENT_MANAGER:RegisterForEvent(self.name, EVENT_END_CRAFTING_STATION_INTERACT, self.OnCraftingStationEnd)
end

function DeconstructIntricateItems.OnCraftingStationStart(event, craftSkill, sameStation)
  -- Show our on-screen icon when a crafting station is used.
  DeconstructIntricateItemsIndicator:SetHidden(false)
end

function DeconstructIntricateItems.OnCraftingStationEnd(event, craftSkill, sameStation)
  -- Hide our on-screen icon when a crafting station menu is closed.
  DeconstructIntricateItemsIndicator:SetHidden(true)
end

-- This is the function that runs when our on-screen icon is clicked.
function DeconstructIntricateItems.Deconstruct()
  local slotId = 0
  local bagSize = GetBagSize(BAG_BACKPACK) -- The global variable BAG_BACKPACK = 1
  local itemCount = 0

  PrepareDeconstructMessage()
  -- Loop through each inventory slot.
  for slotId = 0,bagSize do
    -- Check if the item has the "Intricate" trait.
    if GetItemTrait(BAG_BACKPACK, slotId) == ITEM_TRAIT_TYPE_ARMOR_INTRICATE or GetItemTrait(BAG_BACKPACK, slotId) == ITEM_TRAIT_TYPE_WEAPON_INTRICATE or GetString("SI_ITEMTRAITTYPE", GetItemTrait(BAG_BACKPACK, slotId)) == "Intricate" then
      -- Add the items to the Deconstruction "queue".
      if AddItemToDeconstructMessage(BAG_BACKPACK, slotId, 1) then
        itemCount = itemCount + 1
        d("Deconstructed: " .. GetItemLink(BAG_BACKPACK, slotId) .. ".")
      end
    end 
  end
  -- Perform the actual Deconstruction.
  SendDeconstructMessage()
	d("Deconstructed " .. itemCount .. " items.")
end

-- This is the first thing that runs and will start calling the chain of functions that our mod uses.
-- Run our "OnAddonLoaded" function when the mods finish loading.
EVENT_MANAGER:RegisterForEvent(DeconstructIntricateItems.name, EVENT_ADD_ON_LOADED, DeconstructIntricateItems.OnAddOnLoaded)
