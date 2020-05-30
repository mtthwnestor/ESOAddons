DeconstructIntricateItems = {
    name            = "DeconstructIntricateItems",
    author          = "@Rite",
    menuName        = "Deconstruct Intricate Items",
}

function DeconstructIntricateItems.OnAddOnLoaded(event, addonName)
    if addonName == DeconstructIntricateItems.name then
        EVENT_MANAGER:UnregisterForEvent(DeconstructIntricateItems.name, EVENT_ADD_ON_LOADED)
        DeconstructIntricateItems:Initialize()
        DeconstructIntricateItemsIndicator:SetHidden(true)
    end
end

function DeconstructIntricateItems:Initialize()
    -- Trigger our mod with crafting station interactions.
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CRAFTING_STATION_INTERACT, self.OnCraftingStationStart)
    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_END_CRAFTING_STATION_INTERACT, self.OnCraftingStationEnd)
end

function DeconstructIntricateItems.OnCraftingStationStart(event, craftSkill, sameStation)
    -- Crafting station interaction started. Show our on-screen icon.
    DeconstructIntricateItemsIndicator:SetHidden(false)
end

function DeconstructIntricateItems.OnCraftingStationEnd(event, craftSkill, sameStation)
    -- Crafting station interaction ended. Hide our on-screen icon.
    DeconstructIntricateItemsIndicator:SetHidden(true)
end

function DeconstructIntricateItems.Deconstruct()
    -- On-screen icon clicked. Deconstruct items.

    local slotId = 0
    local bagSize = GetBagSize(BAG_BACKPACK)
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
    -- Perform the actual deconstruction.
    SendDeconstructMessage()

    d("Deconstructed " .. itemCount .. " items.")
end

EVENT_MANAGER:RegisterForEvent(DeconstructIntricateItems.name, EVENT_ADD_ON_LOADED, DeconstructIntricateItems.OnAddOnLoaded)