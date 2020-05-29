local MattsMiniMap = {
	name = "VotansMiniMap",
	isSpecialZoom = false,
	IsZoomHandledExternal = function()
		return false
	end,
	zoneAlertMode = {
		Always = "ALWAYS",
		MiniMapHidden = "MINIMAPHIDDEN",
		Never = "NEVER"
	},
	compassMode = {
		Untouched = "UNTOUCHED",
		Hidden = "HIDDEN",
		Shown = "SHOWN"
	},
	fontFaces = {
		["MEDIUM_FONT"] = ZoFontGame:GetFontInfo(),
		["BOLD_FONT"] = ZoFontWinH1:GetFontInfo(),
		["CHAT_FONT"] = ZoFontChat:GetFontInfo(),
		["GAMEPAD_LIGHT_FONT"] = ZoFontGamepadCondensed61:GetFontInfo(),
		["GAMEPAD_MEDIUM_FONT"] = ZoFontGamepad61:GetFontInfo(),
		["GAMEPAD_BOLD_FONT"] = ZoFontGamepadBold61:GetFontInfo(),
		["ANTIQUE_FONT"] = ZoFontBookPaper:GetFontInfo(),
		["HANDWRITTEN_FONT"] = ZoFontBookLetter:GetFontInfo(),
		["STONE_TABLET_FONT"] = ZoFontBookTablet:GetFontInfo()
	}
}

local am = GetAnimationManager()
local async = LibAsync

MAP_MODE_VOTANS_MINIMAP = 41

local MAP_MODE_VOTANS_MINIMAP = MAP_MODE_VOTANS_MINIMAP

local lookup = {
	frameStyles = {},
	fonts = {},
	fontSizes = {}
}

local function NoOp()
end

local function GetScene()
	return IsInGamepadPreferredMode() and GAMEPAD_WORLD_MAP_SCENE or WORLD_MAP_SCENE
end

local function FakeIsInGamepadPreferredMode()
	return false
end

local function NoGamepad(func, ...)
	local orgIsInGamepadPreferredMode = IsInGamepadPreferredMode
	IsInGamepadPreferredMode = FakeIsInGamepadPreferredMode
	func(...)
	IsInGamepadPreferredMode = orgIsInGamepadPreferredMode
end

local function GetAddon()
	return string.match(debug.traceback(), "'GetAddon'.+user:/AddOns/(.+)")
end

MattsMiniMap.pinManager = ZO_WorldMap_GetPinManager()
MattsMiniMap.panZoom = ZO_WorldMap_GetPanAndZoom()
MattsMiniMap.GetCurrentZoom = MattsMiniMap.panZoom.GetCurrentNormalizedZoom and function(self)
		return self.panZoom:GetCurrentNormalizedZoom()
	end or function(self)
		return self.panZoom:GetCurrentZoom()
	end
MattsMiniMap.SetCurrentZoom = MattsMiniMap.panZoom.SetCurrentNormalizedZoom and function(self, zoom)
		return self.panZoom:SetCurrentNormalizedZoom(zoom)
	end or function(self, zoom)
		return self.panZoom:SetCurrentZoom(zoom)
	end

function MattsMiniMap:InitTweaks()
	local WaitForGPS = function(task)
	end

	local function GetLibGPS()
		EVENT_MANAGER:UnregisterForEvent("VOTAN_MINI_MAP_GPS", EVENT_PLAYER_ACTIVATED)
		local gps = LibGPS2
		if not gps or not gps.IsMeasuring then
			return
		end
		local taskToResumeFromWait = {}
		-- Come back here as long as measuring
		local function WaitForLibGPS(measuring)
			if not measuring then
				for i = #taskToResumeFromWait, 1, -1 do
					taskToResumeFromWait[i]:Resume()
					taskToResumeFromWait[i] = nil
				end
			end
		end
		CALLBACK_MANAGER:RegisterCallback(gps.LIB_EVENT_STATE_CHANGED, WaitForLibGPS)

		WaitForGPS = function(task)
			if gps:IsMeasuring() then
				task:Suspend()
				taskToResumeFromWait[#taskToResumeFromWait + 1] = task
			end
		end
	end
	EVENT_MANAGER:RegisterForEvent("VOTAN_MINI_MAP_GPS", EVENT_PLAYER_ACTIVATED, GetLibGPS)

	do
		local task = async:Create("VOTAN_RefreshAllPOIs")

		local zoneIndex
		local POI_TYPE_GROUP_DUNGEON, POI_TYPE_WAYSHRINE, MAP_PIN_TYPE_POI_SEEN = POI_TYPE_GROUP_DUNGEON, POI_TYPE_WAYSHRINE, MAP_PIN_TYPE_POI_SEEN
		local createTag = ZO_MapPin.CreatePOIPinTag
		local function DrawPin(poiIndex)
			local xLoc, zLoc, iconType, icon, isShownInCurrentMap, linkedCollectibleIsLocked, isDiscovered, isNearby = GetPOIMapInfo(zoneIndex, poiIndex)

			if isShownInCurrentMap and (isDiscovered or isNearby) then
				if ZO_MapPin.POI_PIN_TYPES[iconType] then
					local poiType = GetPOIType(zoneIndex, poiIndex)

					if iconType ~= MAP_PIN_TYPE_POI_SEEN then
						-- Seen Wayshines are POIs, discovered Wayshrines are handled by AddWayshrines()
						-- Request was made by design to have houses and dungeons behave like wayshrines.
						if poiType == POI_TYPE_WAYSHRINE or poiType == POI_TYPE_HOUSE or poiType == POI_TYPE_GROUP_DUNGEON then
							return
						end
					end
					MattsMiniMap.pinManager:CreatePin(iconType, createTag(zoneIndex, poiIndex, icon, linkedCollectibleIsLocked), xLoc, zLoc)
				end
			end
		end

		local function RemovePins(task)
			MattsMiniMap.pinManager:RemovePins("poi")
			zoneIndex = GetCurrentMapZoneIndex()
			if zoneIndex <= 1 or zoneIndex >= 2147483648 then
				return
			end
			if not ZO_WorldMap_IsPinGroupShown(MAP_FILTER_OBJECTIVES) then
				return
			end
			task:For(1, GetNumPOIs(zoneIndex)):Do(DrawPin):Call(WaitForGPS)
			-- d("do ZO_WorldMap_RefreshAllPOIs")
		end
		function ZO_WorldMap_RefreshAllPOIs()
			createTag = ZO_MapPin.CreatePOIPinTag
			task:Cancel():Call(WaitForGPS):Then(RemovePins)
		end
	end

	do
		local task = async:Create("VOTAN_RefreshWayshrines")

		local function IsShowingCosmicMap()
			return GetMapType() == MAPTYPE_COSMIC
		end

		local function IsNormalizedPointInsideMapBounds(x, y)
			return x > 0 and x < 1 and y > 0 and y < 1
		end
		local orgZO_WorldMap_PanToWayshrine = ZO_WorldMap_PanToWayshrine
		local running = false
		local pendingWayshrineNode = nil
		local function GoPendingWayshrine()
			running = false
			if pendingWayshrineNode then
				orgZO_WorldMap_PanToWayshrine(pendingWayshrineNode)
				pendingWayshrineNode = nil
			end
		end

		local MAP_PIN_TYPE_FAST_TRAVEL_WAYSHRINE_CURRENT_LOC = MAP_PIN_TYPE_FAST_TRAVEL_WAYSHRINE_CURRENT_LOC
		local MAP_PIN_TYPE_FAST_TRAVEL_WAYSHRINE = MAP_PIN_TYPE_FAST_TRAVEL_WAYSHRINE
		local createTag, nodeInfo, g_fastTravelNodeIndex = ZO_MapPin.CreateTravelNetworkPinTag, GetFastTravelNodeInfo
		local function DrawPin(nodeIndex)
			local known, name, normalizedX, normalizedY, icon, glowIcon, poiType, isLocatedInCurrentMap, linkedCollectibleIsLocked = nodeInfo(nodeIndex)

			if known and isLocatedInCurrentMap and IsNormalizedPointInsideMapBounds(normalizedX, normalizedY) then
				local isCurrentLoc = g_fastTravelNodeIndex == nodeIndex
				if isCurrentLoc then
					glowIcon = nil
				end

				local pinType = isCurrentLoc and MAP_PIN_TYPE_FAST_TRAVEL_WAYSHRINE_CURRENT_LOC or MAP_PIN_TYPE_FAST_TRAVEL_WAYSHRINE

				MattsMiniMap.pinManager:CreatePin(pinType, createTag(nodeIndex, icon, glowIcon, linkedCollectibleIsLocked), normalizedX, normalizedY)
			end
		end
		local function RemovePins(task)
			MattsMiniMap.pinManager:RemovePins("fastTravelWayshrine")
			-- Dungeons no longer show wayshrines of any kind (possibly pending some system rework)
			-- Design rule, don't show wayshrine pins on cosmic, even if they're in the map
			if IsShowingCosmicMap() or not ZO_WorldMap_IsPinGroupShown(MAP_FILTER_WAYSHRINES) then
				return
			end
			createTag, nodeInfo, g_fastTravelNodeIndex = ZO_MapPin.CreateTravelNetworkPinTag, GetFastTravelNodeInfo, ZO_Map_GetFastTravelNode()
			task:For(1, GetNumFastTravelNodes()):Do(DrawPin):Call(WaitForGPS)
		end
		function ZO_WorldMap_RefreshWayshrines()
			running = true
			task:Cancel():Call(WaitForGPS):Then(RemovePins):Then(GoPendingWayshrine)
		end
		function ZO_WorldMap_PanToWayshrine(nodeIndex)
			if running then
				pendingWayshrineNode = nodeIndex
			else
				pendingWayshrineNode = nil
				return orgZO_WorldMap_PanToWayshrine(nodeIndex)
			end
		end
		local orgZO_WorldMap_SetMapByIndex = ZO_WorldMap_SetMapByIndex
		function ZO_WorldMap_SetMapByIndex(mapIndex)
			running = running or GetCurrentMapIndex() ~= mapIndex
			return orgZO_WorldMap_SetMapByIndex(mapIndex)
		end
	end

	do
		local task = async:Create("VOTAN_RefreshLocations")

		local locations
		local function DrawPin(i)
			locations:AddLocation(i)
		end
		local function releaseAllObjects()
			locations:ReleaseAllObjects()
		end
		local function removePins(task)
			MattsMiniMap.pinManager:RemovePins("loc")
			task:For(1, GetNumMapLocations()):Do(DrawPin):Call(WaitForGPS)
		end
		local function delayStart(task)
			task:Call(releaseAllObjects):Then(removePins)
		end
		local function start(task)
			task:Delay(200, delayStart)
		end
		function ZO_MapLocations:RefreshLocations()
			locations = self
			task:Cancel():Call(WaitForGPS):Then(start)
		end
	end

	local function DeferRefresh(methodName, identifier, delay)
		local task = async:Create("VOTAN_" .. identifier)
		local orgMethod = _G[methodName]
		local function runRefresh(task)
			task:Call(WaitForGPS):Then(orgMethod)
		end
		_G[methodName] = function()
			task:Cancel():Delay(GetScene():GetState() == SCENE_SHOWN and 0 or (delay * 7), runRefresh)
		end
	end
	DeferRefresh("ZO_WorldMap_RefreshAllPOIs", "MAP_RefreshAllPOIs", 20)
	DeferRefresh("ZO_WorldMap_RefreshAvAObjectives", "MAP_RefreshAvAObjectives", 50)
	DeferRefresh("ZO_WorldMap_RefreshKeeps", "MAP_RefreshKeeps", 30)
	DeferRefresh("ZO_WorldMap_RefreshKillLocations", "MAP_RefreshKillLocations", 60)
	DeferRefresh("ZO_WorldMap_RefreshWayshrines", "MAP_RefreshWayshrines", 10)
	DeferRefresh("ZO_WorldMap_RefreshForwardCamps", "MAP_RefreshForwardCamps", 70)
	DeferRefresh("ZO_WorldMap_RefreshAccessibleAvAGraveyards", "MAP_RefreshAccessibleAvAGraveyards", 80)

	do
		local task = async:Create("VOTANS_MAP_CUSTOM_PIN_UPDATE")
		local function OnError(err)
			d("Error", err)
		end
		task:OnError(OnError)
		local refreshPinType = {}

		local GetFrameTimeMilliseconds, GetGameTimeMilliseconds = GetFrameTimeMilliseconds, GetGameTimeMilliseconds
		local function DoLayout(self, pinData)
			local start, runTime = GetFrameTimeMilliseconds(), GetGameTimeMilliseconds()
			pinData.layoutCallback(self)
			if async:GetDebug() then
				local now = GetGameTimeMilliseconds()
				local freezeTime = now - start
				runTime = now - runTime
				if freezeTime > 16 then
					df("%s Freeze!!! used %ims, new frametime %ims", pinData.pinTypeString, runTime, freezeTime)
				end
			end
		end
		local pins
		local function drawPin(pinTypeId, pinData)
			-- self:RemovePins(pinData.pinTypeString)
			if pinData.enabled and refreshPinType[pinTypeId] then
				refreshPinType[pinTypeId] = nil
				return DoLayout(pins, pinData)
			end
		end
		local function drawPins(self)
			task:For(pairs(refreshPinType)):Do(drawPin)
		end
		local function removePinType(pinTypeId, pinData)
			pins:RemovePins(pinData.pinTypeString)
			refreshPinType[pinTypeId] = pinData
		end
		local function startDrawPins()
			drawPins(pins)
		end

		function ZO_WorldMapPins:RefreshCustomPins(optionalPinType)
			pins = self
			if optionalPinType then
				-- d("Request RefreshCustomPins single", optionalPinType, GetAddon())
				-- Dummy pins are used to get pinManager. This must be done without delay.
				local pinData = self.customPins[optionalPinType]
				if pinData then
					refreshPinType[optionalPinType] = pinData
				else
					return
				end
			else
				-- d("Request RefreshCustomPins all", GetAddon())
				for pinTypeId, pinData in pairs(self.customPins) do
					refreshPinType[pinTypeId] = pinData
				end
			end
			task:Cancel():For(pairs(refreshPinType)):Do(removePinType):Then(WaitForGPS):Then(startDrawPins)
		end
	end

	do
		local task = async:Create("VOTANS_MAP_UPDATE_MAP_SIZE_CHANGE")
		local orgUpdatePinsForMapSizeChange = ZO_WorldMapPins.UpdatePinsForMapSizeChange
		local lastW, lastH, lastZone = -1, -1, -1
		local pins, w, h
		local function updateLocationAndSize(pinKey, pin)
			pin:UpdateLocation()
			pin:UpdateSize()
		end
		local function callResizeCallback(pinTypeId, pinData)
			if (pinData.enabled and pinData.resizeCallback) then
				pinData.resizeCallback(pins, w, h)
			end
		end
		local function resizePins(task)
			-- df("resize run %ix%i %s", lastW, lastH, lastZone)
			local pinControls = pins:GetActiveObjects()
			task:For(pairs(pinControls)):Do(updateLocationAndSize):For(pairs(pins.customPins)):Do(callResizeCallback)
		end
		local function updatePlayerPinLevel()
			local control = MattsMiniMap.pinManager.playerPin:GetControl()
			local labelControl = control:GetNamedChild("Label")
			local overlayControl = control:GetNamedChild("Background")
			local highlightControl = control:GetNamedChild("Highlight")
			local pinLevel = zo_max(ZO_MapPin.PIN_DATA[MAP_PIN_TYPE_PLAYER].level, 1)
			control:SetDrawLevel(pinLevel)
			overlayControl:SetDrawLevel(pinLevel)
			highlightControl:SetDrawLevel(pinLevel - 1)
			labelControl:SetDrawLevel(pinLevel + 1)
		end
		function ZO_WorldMapPins:UpdatePinsForMapSizeChange()
			w, h = ZO_WorldMapContainer:GetDimensions()
			local zone = GetMapTileTexture()
			if lastW ~= w or lastH ~= h or lastZone ~= zone then
				lastW, lastH, lastZone, pins = w, h, zone, self

				task:StopTimer():Cancel()

				updatePlayerPinLevel()

				if GetScene():IsShowing() then
					return orgUpdatePinsForMapSizeChange(self)
				end

				task:Call(WaitForGPS):Then(resizePins):Delay(50)
			end
		end
	end

	---- Delaying ZO_WorldMap_UpdateMap is a bad idea, because it breaks zoom sliders.
	do
		local orgGetDimensions = ZO_WorldMapContainer.GetDimensions
		function ZO_WorldMapContainer:GetDimensions()
			-- w and h jitter in decimals.
			local w, h = orgGetDimensions(self)
			w, h = zo_round(w), zo_round(h)
			return w, h
		end

		local orgSetDimensions = ZO_WorldMapContainer.SetDimensions
		function ZO_WorldMapContainer:SetDimensions(w, h)
			-- w and h jitter in decimals.
			w, h = zo_round(w), zo_round(h)
			return orgSetDimensions(self, w, h)
		end
	end
end

function MattsMiniMap:InitRequiredModifications()
	local orgUpdatePinsForMapSizeChange = ZO_WorldMapPins.UpdatePinsForMapSizeChange
	local lastW, lastH, lastZone = -1, -1, -1
	function ZO_WorldMapPins:UpdatePinsForMapSizeChange()
		local w, h = ZO_WorldMapContainer:GetDimensions()
		w, h = zo_round(w), zo_round(h)
		local zone = GetMapTileTexture()
		if lastW ~= w or lastH ~= h or lastZone ~= zone then
			lastW, lastH, lastZone = w, h, zone
			return orgUpdatePinsForMapSizeChange(self)
		end
	end
end

local isDirty = false
local function UpdateVisibility()
	isDirty = false
	if GetScene():IsShowing() or ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
		return true
	end

	local settings = MattsMiniMap.player
	if IsMounted() then
		return settings.showMounted
	end
	if SIEGE_BAR_SCENE:IsShowing() then
		return settings.showSiege
	end
	if LOOT_SCENE:IsShowing() then
		return settings.showLoot
	end
	if IsUnitInCombat("player") then
		return settings.showCombat
	else
		return settings.showHUD
	end
end

function MattsMiniMap:InitCameraAngle()
	if self.cameraAngleLeft then
		return
	end
	local playerPin = self.pinManager:GetPlayerPin()
	local playerControl = playerPin:GetControl()
	local parent = playerControl:GetParent()
	local function setupCameraAngle(control)
		control:SetTexture("VotansMiniMap/ViewLimit.dds")
		control:SetDimensions(4, 64)
		control:SetAnchor(BOTTOM, playerControl, CENTER)
		control:SetHidden(not self.account.showCameraAngle)
		control:SetPixelRoundingEnabled(true)
		control:SetDrawLayer(DL_TEXT)
	end
	local control
	control = CreateControl("$(parent)ViewLimitLeft", parent, CT_TEXTURE)
	setupCameraAngle(control)
	self.cameraAngleLeft = control
	control = CreateControl("$(parent)ViewLimitRight", parent, CT_TEXTURE)
	setupCameraAngle(control)
	self.cameraAngleRight = control

	self.cameraAngleRad = self.account.cameraAngle * 0.0174532925199 -- pi/180°
	local orgSetHidden = playerControl.SetHidden
	local function setHiddenPlayerPin(pin, hidden)
		local noViewLimit = hidden or not self.account.showCameraAngle
		self.cameraAngleLeft:SetHidden(noViewLimit)
		self.cameraAngleRight:SetHidden(noViewLimit)
		return orgSetHidden(pin, hidden)
	end
	playerControl.SetHidden = setHiddenPlayerPin
	local orgSetRotation = playerPin.SetRotation
	function playerPin.SetRotation(...)
		if self.account.showCameraAngle then
			local pin = ...
			local heading = select(3, GetMapPlayerPosition("player"))
			return orgSetRotation(pin, heading)
		else
			return orgSetRotation(...)
		end
	end
end

function MattsMiniMap:InitMiniMap()
	-- Used by GoToWorldMapMode, too
	local orgUpdateSize = ZO_MapPin.UpdateSize

	local scale = 1
	local limitedScale = 1
	local blacklistedPins = {}
	for _, list in pairs({ZO_MapPin.UNIT_PIN_TYPES}) do
		for pinType in pairs(list) do
			blacklistedPins[pinType] = true
		end
	end
	function MattsMiniMap:CalculateScale(pinType)
		return not blacklistedPins[pinType] and scale or limitedScale
	end

	local orgzo_max, factor
	local function newMax(a, ...)
		return orgzo_max(a * factor, ...)
	end
	local function newUpdateSize(self)
		if self.radius and self.radius > 0 then
			return orgUpdateSize(self)
		end
		local pinType = self:GetPinType()
		local singlePinData = ZO_MapPin.PIN_DATA[pinType]
		if not singlePinData then
			return orgUpdateSize(self)
		end
		local orgSize, orgMinSize = singlePinData.size or 20, singlePinData.minSize
		local scale = MattsMiniMap:CalculateScale(pinType)
		singlePinData.size, singlePinData.minSize = orgSize * scale, orgMinSize and orgMinSize * scale or nil
		orgUpdateSize(self)
		singlePinData.size, singlePinData.minSize = orgSize, orgMinSize
	end

	function MattsMiniMap.ShowClock()
		local self = MattsMiniMap

		self.clockRealTime:SetText(FormatTimeSeconds(GetSecondsSinceMidnight(), TIME_FORMAT_STYLE_CLOCK_TIME, self.account.timeFormat, TIME_FORMAT_DIRECTION_NONE))

		local igSecondsPerDay = 20955
		local rlTimeStamp = GetTimeStamp()
		local inGameTime = (rlTimeStamp % igSecondsPerDay) * 86400 / igSecondsPerDay
		self.clockInGame:SetText(FormatTimeSeconds(inGameTime, TIME_FORMAT_STYLE_CLOCK_TIME, self.account.timeFormat, TIME_FORMAT_DIRECTION_NONE))
	end

	local vars = MattsMiniMap.mapVars
	local myMode = vars[MAP_MODE_VOTANS_MINIMAP]
	if not myMode then
		myMode = ZO_DeepTableCopy(vars[MAP_MODE_SMALL_CUSTOM])
		vars[MAP_MODE_VOTANS_MINIMAP] = myMode
		myMode.width, myMode.height = 301, 363
	end
	myMode.mapSize = 2

	-- Map Pin Filter checked-state is the same
	local filters = vars[MAP_MODE_LARGE_CUSTOM].filters
	myMode.filters[1] = filters[1]
	myMode.filters[2] = filters[2]
	myMode.filters[3] = filters[3]

	self.modeData = myMode
	if self.account.keepSquare ~= nil then
		self.modeData.keepSquare = self.account.keepSquare
	else
		self.account.keepSquare = self.modeData.keepSquare
	end

	ZO_WorldMapTitleBarBG:SetColor(0, 0, 0, 0)
	ZO_WorldMapButtonsBG:SetColor(0, 0, 0, 0)
	ZO_WorldMapButtonsBG:SetHandler("OnDragStart", ZO_WorldMapTitleBar_OnDragStart)
	ZO_WorldMapButtonsBG:SetHandler(
		"OnMouseUp",
		function(self, button, upInside)
			ZO_WorldMapTitleBar_OnMouseUp(button, upInside)
		end
	)

	local wm = GetWindowManager()
	local control = wm:CreateControl("VotanMiniMapBg", ZO_WorldMap, CT_BACKDROP)
	control:SetAnchor(TOPLEFT, nil, TOPLEFT, -8, -4)
	control:SetAnchor(BOTTOMRIGHT, ZO_WorldMapButtons, BOTTOMRIGHT, 8, 4)
	control:SetExcludeFromResizeToFitExtents(true)
	self.background = control
	self:UpdateBorder()
	WORLD_MAP_FRAGMENT:SetAllowShowHideTimeUpdates(true)
	WORLD_MAP_FRAGMENT.alwaysAnimate = true
	WORLD_MAP_FRAGMENT.duration = 0

	ZO_WorldMap:SetClampedToScreenInsets(4, 29, -4, -40)

	control = CreateControl("$(parent)ClockRealTime", self.background, CT_LABEL)
	self.clockRealTime = control
	control:SetFont("ZoFontWindowTitle")
	control:SetDimensions(66, 40)
	control:SetResizeToFitDescendents(true)
	control:SetAnchor(BOTTOMLEFT, nil, BOTTOMLEFT, 14, -4)

	control = CreateControl("$(parent)ClockInGame", self.background, CT_LABEL)
	self.clockInGame = control
	control:SetFont("ZoFontWindowSubtitle")
	control:SetDimensions(70, 32)
	control:SetResizeToFitDescendents(true)
	control:SetAnchor(BOTTOMLEFT, self.clockRealTime, BOTTOMRIGHT, 6, -2)
	control:SetVerticalAlignment(BOTTOM)

	self.cameraAngleRad = 0

	if self.account.showCameraAngle then
		self:InitCameraAngle()
	end

	WORLD_MAP_FRAGMENT:SetConditional(UpdateVisibility)
	self:UpdateVisibility()

	local isBattlegound = false
	local function IsBattleground()
		return isBattlegound
	end
	local function PlayerActivated()
		MattsMiniMap.cameraAngle = 0
		MattsMiniMap:GoMiniMapMode(true)
		isBattlegound = GetCurrentBattlegroundId() > 0
	end
	local function PlayerDeactivated()
		MattsMiniMap:StopFollowPlayer()
	end
	EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_ACTIVATED, PlayerActivated)
	EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PLAYER_DEACTIVATED, PlayerDeactivated)

	local function RestorePosition()
		-- Skip full update for just setting new position
		local orgZO_WorldMap_UpdateMap = ZO_WorldMap_UpdateMap
		ZO_WorldMap_UpdateMap = NoOp

		ZO_WorldMap_OnResizeStart(ZO_WorldMap)

		local sv = MattsMiniMap.modeData
		local UIWidth, UIHeight = GuiRoot:GetDimensions()

		ZO_WorldMap:ClearAnchors()
		ZO_WorldMap:SetDimensionConstraints(128, 144, UIWidth, UIHeight)
		ZO_WorldMap:SetAnchor(CENTER, nil, CENTER, self.account.x or sv.x, self.account.y or sv.y)
		ZO_WorldMap:SetDimensions(self.account.width or sv.width or 301, self.account.height or sv.height or 363)

		ZO_WorldMap_OnResizeStop(ZO_WorldMap)
		ZO_WorldMap_UpdateMap = orgZO_WorldMap_UpdateMap
	end

	local function SaveMapPosition()
		local cx, cy = GuiRoot:GetCenter()
		local x, y = ZO_WorldMap:GetCenter()
		x, y = x - cx, y - cy

		local sv = MattsMiniMap.modeData
		sv.x, sv.y = x, y
		sv.width, sv.height = ZO_WorldMap:GetDimensions()
		self.account.x, self.account.y = x, y
		self.account.width, self.account.height = ZO_WorldMap:GetDimensions()
	end

	local function StateChanged()
		self:UpdateVisibility()
	end
	EVENT_MANAGER:RegisterForEvent(MattsMiniMap.name, EVENT_PLAYER_COMBAT_STATE, StateChanged)
	EVENT_MANAGER:RegisterForEvent(MattsMiniMap.name, EVENT_MOUNTED_STATE_CHANGED, StateChanged)

	local lastZoom, lastW, lastH = -1, -1, -1
	EVENT_MANAGER:RegisterForEvent(
		MattsMiniMap.name,
		EVENT_GAMEPAD_PREFERRED_MODE_CHANGED,
		function()
			lastZoom, lastW, lastH = -1, -1, -1
			ZO_WorldMap_InteractKeybindForceHidden(true)
			self:UpdateVisibility()
			self:UpdateBorder()
		end
	)
	EVENT_MANAGER:RegisterForEvent(
		MattsMiniMap.name,
		EVENT_SCREEN_RESIZED,
		function()
			if IsInGamepadPreferredMode() and not ZO_WorldMap_IsWorldMapShowing() then
				ZO_WorldMap_UpdateMap()
			end
		end
	)

	local MoveToPlayer = ZO_WorldMap_PanToPlayer
	local function AdjustZoom()
		local numTiles = GetMapNumTiles()
		local tilePixelWidth = ZO_WorldMapContainer1:GetTextureFileDimensions()
		local totalPixels = numTiles * tilePixelWidth
		local w, h = ZO_WorldMapScroll:GetDimensions()
		w, h = zo_round(w), zo_round(h)
		local mapAreaUIUnits = zo_max(w, h)
		local mapAreaPixels = mapAreaUIUnits * GetUIGlobalScale()
		if mapAreaPixels < 1 then
			mapAreaPixels = 1
		end

		local mode, targetScale
		if MattsMiniMap.isSpecialZoom then
			mode = "specialZoom"
			targetScale = MattsMiniMap.specialZoom
		elseif IsBattleground() then
			mode = "battlegroundZoom"
			targetScale = MattsMiniMap.account.battlegroundZoom
		elseif GetMapContentType() == MAP_CONTENT_DUNGEON then
			mode = "dungeonZoom"
			targetScale = MattsMiniMap.account.dungeonZoom
		elseif GetMapType() == MAPTYPE_SUBZONE then
			mode = "subZoneZoom"
			targetScale = MattsMiniMap.account.subZoneZoom
		else
			mode = "zoom"
			targetScale = MattsMiniMap.account.zoom
		end
		if IsMounted() and MattsMiniMap.account.mountedZoom ~= 1 then
			targetScale = targetScale * MattsMiniMap.account.mountedZoom
			mode = "mountedZoom"
		end

		if MattsMiniMap.zoomMode ~= mode then
			MoveToPlayer = ZO_WorldMap_JumpToPlayer
		end
		MattsMiniMap.zoomMode = mode

		local maxZoomToStayBelowNative = math.floor((totalPixels / mapAreaPixels - 1) * 500 * targetScale) / 500 + 1
		if lastZoom ~= maxZoomToStayBelowNative or w ~= lastW or h ~= lastH then
			MoveToPlayer = ZO_WorldMap_JumpToPlayer
			scale = math.min(math.max(0.6, targetScale * 0.75), 1)
			limitedScale = math.max(scale, MattsMiniMap.account.unitPinScaleLimit)
			ZO_MapPin.UpdateSize = newUpdateSize

			self.modeData.mapZoom, self.scale, self.limitedScale = maxZoomToStayBelowNative, scale, limitedScale

			lastZoom, lastW, lastH = maxZoomToStayBelowNative, w, h
			self.panZoom:SetMapZoomMinMax(self.panZoom:ComputeMinZoom(), self.panZoom:ComputeMaxZoom())
		end
	end
	local orgGetMapCustomMaxZoom = GetMapCustomMaxZoom
	function GetMapCustomMaxZoom(...)
		if ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
			return orgGetMapCustomMaxZoom(...)
		else
			if lastZoom < 0 then
				AdjustZoom()
			end
			return lastZoom
		end
	end
	local orgCanMapZoom = self.panZoom.CanMapZoom
	function self.panZoom.CanMapZoom(...)
		return orgCanMapZoom(...) or ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP
	end

	local asyncCallbacks = async:Create("VOTANS_MAP_DO_CALLBACKS")
	local runningCallbacks
	local function StopCallbacks()
		if not runningCallbacks then
			asyncCallbacks:Cancel()
		end
		self.panZoom:ClearJumpToPinWhenAvailable()
	end
	CALLBACK_MANAGER:RegisterCallback("OnWorldMapChanged", StopCallbacks)

	local isWaitingForTexture = false
	local function WaitForTexture()
		if not self.panZoom:CanInitializeMap() then
			asyncCallbacks:Suspend()
			isWaitingForTexture = true
		end
	end

	local function WaitForTextureLoaded()
		if isWaitingForTexture then
			isWaitingForTexture = false
			asyncCallbacks:Resume()
		end
	end
	ZO_PreHookHandler(ZO_WorldMapContainer1, "OnTextureLoaded", WaitForTextureLoaded)

	local callbacks
	local function Callback(index)
		local callback = callbacks[index]
		if callback then
			local deleted = callback[3]
			if deleted then
				return
			end
			local argument = callback[2]
			callback = callback[1]

			if argument then
				pcall(callback, argument, false)
			else
				pcall(callback, false)
			end
		end
	end
	local function DoCallbacks(asyncCallbacks)
		callbacks = CALLBACK_MANAGER.callbackRegistry["OnWorldMapChanged"]
		if not callbacks or #callbacks == 0 then
			return
		end
		asyncCallbacks:For(1, #callbacks):Do(Callback)
	end
	local function AfterCallbacks()
		callbacks = nil
		runningCallbacks = false
		if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
			AdjustZoom()
			if DoesCurrentMapMatchMapForPlayerLocation() then
				local orgSetMapToPlayerLocation = SetMapToPlayerLocation
				SetMapToPlayerLocation = NoOp

				MoveToPlayer()
				SetMapToPlayerLocation = orgSetMapToPlayerLocation
			end
			if IsInGamepadPreferredMode() then
				RestorePosition()
			end
		end
	end
	asyncCallbacks:Finally(AfterCallbacks)
	-- ToDo: Scene StateChange
	local map, currentTime, running
	local lastUpdate, lastMapUpdate, lastMapId = 0, 0, GetMapTileTexture()
	local function UpdateMap(force)
		if runningCallbacks then
			return
		end

		if not force then
			if HUD_UI_SCENE:IsShowing() or ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
				return
			end
		end

		-- local stopwatch = GetGameTimeSeconds()

		local needChange, oldMapType, mapId
		if (currentTime - lastMapUpdate) >= 1 then
			lastMapUpdate = currentTime

			needChange, oldMapType, mapId = not DoesCurrentMapMatchMapForPlayerLocation(), GetMapType(), GetMapTileTexture()
			needChange = needChange or mapId ~= lastMapId
			if needChange then
				SetMapToPlayerLocation()
				if oldMapType ~= MAPTYPE_SUBZONE and DoesCurrentMapShowPlayerWorld() then
					local mapType = GetMapType()
					if mapType == MAPTYPE_SUBZONE and GetMapContentType() == MAP_CONTENT_NONE then
						local x, y = GetMapPlayerPosition("player")
						if x < 0.17 or x > 0.83 or y < 0.17 or y > 0.83 then
							MapZoomOut()
							local currentMapId = GetMapTileTexture()
							if mapId == currentMapId then
								-- df("skip %.2fx%.2f", x, y)
								needChange = currentMapId ~= lastMapId
								-- Compensate overhead: delay next check 1.5sec
								lastMapUpdate = lastMapUpdate + 1.5
							end
						end
					end
				end
			elseif oldMapType == MAPTYPE_SUBZONE and DoesCurrentMapShowPlayerWorld() then
				local x, y = GetMapPlayerPosition("player")
				if x < 0.10 or x > 0.90 or y < 0.10 or y > 0.90 then
					MapZoomOut()
					local mapType = GetMapType()
					if mapType == MAPTYPE_SUBZONE or GetMapTileTexture() ~= mapId then
						lastMapUpdate = lastMapUpdate + 1.5
						SetMapToPlayerLocation()
					else
						needChange = true
					end
				end
			end
		else
			needChange = lastMapId ~= GetMapTileTexture()
		end
		if needChange then
			runningCallbacks = true
			asyncCallbacks:Cancel():Call(DoCallbacks):Then(WaitForTexture)
			MoveToPlayer = ZO_WorldMap_JumpToPlayer
			lastMapId = GetMapTileTexture()
		elseif (currentTime - lastUpdate) >= 0.200 then
			lastUpdate = currentTime
			local orgZO_WorldMap_UpdateMap, orgSetMapToPlayerLocation = ZO_WorldMap_UpdateMap, SetMapToPlayerLocation
			ZO_WorldMap_UpdateMap, SetMapToPlayerLocation = NoOp, NoOp

			AdjustZoom()

			MoveToPlayer()
			MoveToPlayer = ZO_WorldMap_PanToPlayer

			ZO_WorldMap_UpdateMap, SetMapToPlayerLocation = orgZO_WorldMap_UpdateMap, orgSetMapToPlayerLocation
		end
		-- 	stopwatch = GetGameTimeSeconds() - stopwatch
		-- 	if stopwatch > 0.001 then
		-- 		df("check map change required took %.3fms needChange=%s", stopwatch * 1000, tostring(needChange))
		-- 	end
	end

	do
		local orgUpdate = ZO_WorldMap:GetHandler("OnUpdate")
		local orgSetMapToPlayerLocation = SetMapToPlayerLocation
		-- 	local orgIsShowing = SCENE_MANAGER.IsShowing
		-- 	local orgIsInGamepadPreferredMode = IsInGamepadPreferredMode
		-- 	local function isShowingFake(self, name) return name == "worldMap" or orgIsShowing(self, name) end
		local updateTask = async:Create("VotansMiniMapUpdateMap")

		local function asyncUpdate1()
			if SetMapToPlayerLocation ~= NoOp then
				orgSetMapToPlayerLocation = SetMapToPlayerLocation
			end
			return UpdateMap()
		end
		local function asyncUpdate2(task)
			SetMapToPlayerLocation = NoOp
			orgUpdate(map, currentTime)
			SetMapToPlayerLocation = orgSetMapToPlayerLocation
			running = false
		end
		local function updateHeading()
			local heading = GetPlayerCameraHeading()
			local angle = self.cameraAngleRad
			self.cameraAngleRad = angle
			self.cameraAngleLeft:SetTextureRotation(heading - angle, 0.5, 1)
			self.cameraAngleRight:SetTextureRotation(heading + angle, 0.5, 1)
		end
		local function minimapUpdate(...)
			map, currentTime = ...

			if self.account.showCameraAngle then
				updateHeading()
			end

			if self.account.asyncUpdate then
				if running then
					-- d("skip")
					return
				end
				running = true
				updateTask:Call(asyncUpdate1):Then(asyncUpdate2)
			else
				asyncUpdate1()
				asyncUpdate2()
			end
		end
		-- 	local function minimapUpdateWithTooltips(...)
		-- 		SetMapToPlayerLocation, SCENE_MANAGER.IsShowing, IsInGamepadPreferredMode = orgSetMapToPlayerLocation, orgIsShowing, orgIsInGamepadPreferredMode
		-- 		UpdateMap()
		-- 		if SetMapToPlayerLocation ~= NoOp then
		-- 			orgSetMapToPlayerLocation, orgIsShowing, orgIsInGamepadPreferredMode = SetMapToPlayerLocation, SCENE_MANAGER.IsShowing, IsInGamepadPreferredMode
		-- 		end
		-- 		SetMapToPlayerLocation, SCENE_MANAGER.IsShowing, IsInGamepadPreferredMode = NoOp, isShowingFake, NoOp
		-- 		orgUpdate(...)
		-- 		SetMapToPlayerLocation, SCENE_MANAGER.IsShowing, IsInGamepadPreferredMode = orgSetMapToPlayerLocation, orgIsShowing, orgIsInGamepadPreferredMode
		-- 	end
		ZO_WorldMap:SetHandler("OnUpdate", minimapUpdate)
	end

	do
		local function toggleMapPoint(pinTypeId, getPositionFunc, removeFunc)
			local x, y = NormalizeMousePositionToControl(ZO_WorldMapContainer)
			local cx, cy = getPositionFunc()
			if cx ~= 0 and cy ~= 0 then
				local distance = zo_distance3D(x, y, 0, cx, cy, 0) * self:GetCurrentZoom()
				if distance <= 0.023 then
					return removeFunc()
				end
			end
			PingMap(pinTypeId, MAP_TYPE_LOCATION_CENTERED, x, y)
		end
		local orgZO_WorldMap_MouseDown = ZO_WorldMap_MouseDown
		function ZO_WorldMap_MouseDown(...)
			if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				local button, ctrl, alt, shift = ...
				if button == MOUSE_BUTTON_INDEX_LEFT and not shift and not alt and ctrl then
					return toggleMapPoint(MAP_PIN_TYPE_PLAYER_WAYPOINT, GetMapPlayerWaypoint, ZO_WorldMap_RemovePlayerWaypoint)
				end
			end
			return orgZO_WorldMap_MouseDown(...)
		end
	end

	do
		function MattsMiniMap:StartFollowPlayer()
			MoveToPlayer = ZO_WorldMap_JumpToPlayer
		end

		function MattsMiniMap:StopFollowPlayer()
		end
	end

	local ZO_CachedStrFormat, SI_ZONE_NAME = ZO_CachedStrFormat, SI_ZONE_NAME
	local function SetMapTitle(zoneName, subZoneName)
		if subZoneName and #subZoneName > 0 then
			zoneName = ZO_CachedStrFormat(SI_ZONE_NAME, subZoneName)
		end
		if not zoneName or #zoneName == 0 then
			zoneName = GetMapName()
		end
		if not zoneName or #zoneName == 0 then
			zoneName = GetZoneNameByIndex(GetUnitZoneIndex("player"))
		end
		zoneName = ZO_CachedStrFormat(SI_ZONE_NAME, zoneName)
		return zoneName
	end
	local function SetMapTitleCurrentLocation()
		return SetMapTitle(GetPlayerLocationName(), GetPlayerActiveSubzoneName())
	end
	local function ZoneChanged(_, zoneName, subZoneName)
		if ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
			return
		end
		ZO_WorldMapTitle:SetText(SetMapTitle(zoneName, subZoneName))
	end
	EVENT_MANAGER:RegisterForEvent(MattsMiniMap.name, EVENT_ZONE_CHANGED, ZoneChanged)

	local orgZO_WorldMap_GetMapTitle = ZO_WorldMap_GetMapTitle
	function ZO_WorldMap_GetMapTitle(...)
		if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP and not self.account.showFullTitle and DoesCurrentMapMatchMapForPlayerLocation() then
			return SetMapTitleCurrentLocation(...)
		end

		return orgZO_WorldMap_GetMapTitle(...)
	end

	local function ClearMouseoverText()
		ZO_WorldMap_OnHide()
		ZO_WorldMap_HandlePinExit()
		ZO_WorldMapTitle:SetText(SetMapTitleCurrentLocation())
	end
	do
		local function DoIt(orgZO_WorldMap_UpdateMap, skipWorldMapUpdate)
			CALLBACK_MANAGER:UnregisterCallback("OnWorldMapModeChanged", DoIt, orgZO_WorldMap_UpdateMap, skipWorldMapUpdate)

			if g_inSpecialMode then
				ZO_WorldMap_UpdateMap = NoOp
				-- Clear interaction, otherwise button does not get enabled again
				EndInteraction(INTERACTION_FAST_TRAVEL_KEEP)
				EndInteraction(INTERACTION_FAST_TRAVEL)
			end

			ZO_MapPin.UpdateSize = newUpdateSize
			ZO_WorldMap_UpdateMap = skipWorldMapUpdate and NoOp or orgZO_WorldMap_UpdateMap
			ZO_WorldMap_PushSpecialMode(MAP_MODE_VOTANS_MINIMAP)
			g_inSpecialMode = false
			ZO_WorldMap_UpdateMap = orgZO_WorldMap_UpdateMap

			self.background:SetHidden(false)

			ZO_WorldMap:StopMovingOrResizing()
			ZO_WorldMap_MouseUp()
			MoveToPlayer = ZO_WorldMap_JumpToPlayer
			RestorePosition()
			self:UpdateBorder()
			ClearMouseoverText()
			lastZoom = -1
		end
		function MattsMiniMap:GoMiniMapMode(skipWorldMapUpdate)
			local orgZO_WorldMap_UpdateMap = ZO_WorldMap_UpdateMap

			local mode = ZO_WorldMap_GetMode()
			if mode ~= MAP_MODE_VOTANS_MINIMAP then
				if g_inSpecialMode then
					if mode ~= MAP_MODE_KEEP_TRAVEL and mode ~= MAP_MODE_FAST_TRAVEL then
						ClearMouseoverText()

						ZO_WorldMap_UpdateMap = NoOp
						g_inSpecialMode = false
						ZO_WorldMap_PushSpecialMode(MAP_MODE_VOTANS_MINIMAP)
						ZO_WorldMap_UpdateMap = orgZO_WorldMap_UpdateMap

						self.background:SetHidden(false)

						RestorePosition()
						self:UpdateBorder()
						g_inSpecialMode = false
					else
						CALLBACK_MANAGER:RegisterCallback("OnWorldMapModeChanged", DoIt, orgZO_WorldMap_UpdateMap, skipWorldMapUpdate)
						-- ZO_WorldMap_UpdateMap = NoOp
						-- Needed to cause OnWorldMapModeChanged:
						EndInteraction(INTERACTION_FAST_TRAVEL_KEEP)
						EndInteraction(INTERACTION_FAST_TRAVEL)
					end
				else
					DoIt(orgZO_WorldMap_UpdateMap, skipWorldMapUpdate)
				end
			else
				SetMapTitleCurrentLocation()
			end
			self:StartFollowPlayer()
		end
	end
	function MattsMiniMap:GoWorldMapMode(skipPanToPlayer)
		self:StopFollowPlayer()
		if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
			lastZoom = -1
			MoveToPlayer = ZO_WorldMap_JumpToPlayer
			ZO_MapPin.UpdateSize = orgUpdateSize

			local orgZO_WorldMap_UpdateMap, orgSetMapToPlayerLocation = ZO_WorldMap_UpdateMap, SetMapToPlayerLocation
			SetMapToPlayerLocation, ZO_WorldMap_UpdateMap = NoOp, NoOp

			g_inSpecialMode = true
			self.mapVars.userMode = MAP_MODE_LARGE_CUSTOM
			ZO_WorldMap_ClearCustomZoomLevels()
			ZO_WorldMap_PopSpecialMode()

			self:SetCurrentZoom(0)
			-- This triggers internal handlers. One of them would call ZO_WorldMap_UpdateMap, but not this time
			CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged", true)
			if not self.IsZoomHandledExternal() and not skipPanToPlayer and DoesCurrentMapMatchMapForPlayerLocation() then
				-- Avoid duplicate action
				if self.account.zoomToPlayer then
					ZO_WorldMap_JumpToPlayer()
				end
			end

			SetMapToPlayerLocation, ZO_WorldMap_UpdateMap = orgSetMapToPlayerLocation, orgZO_WorldMap_UpdateMap

			self.background:SetHidden(true)
		end
		self:UpdateBorder()
	end

	do
		local orgZO_WorldMap_OnResizeStop = ZO_WorldMap_OnResizeStop
		function ZO_WorldMap_OnResizeStop(...)
			orgZO_WorldMap_OnResizeStop(...)
			if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				SaveMapPosition()
			end
		end
	end

	do
		local orgZO_WorldMapTitleBar_OnMouseUp = ZO_WorldMapTitleBar_OnMouseUp
		function ZO_WorldMapTitleBar_OnMouseUp(...)
			orgZO_WorldMapTitleBar_OnMouseUp(...)
			SaveMapPosition()
			UpdateMap(true)
		end
	end

	do
		local function WorldMapStateChanged(oldState, newState)
			if (newState == SCENE_FRAGMENT_SHOWING) then
				MattsMiniMap:GoWorldMapMode()
			elseif (newState == SCENE_FRAGMENT_SHOWN) then
				-- Avoid "Access private ...":
				WORLD_MAP_FRAGMENT.duration = 100
			elseif (newState == SCENE_FRAGMENT_HIDING) then
				MattsMiniMap:GoMiniMapMode(not g_inSpecialMode)
			elseif (newState == SCENE_FRAGMENT_HIDDEN) then
				WORLD_MAP_FRAGMENT.duration = 0
			end
		end
		WORLD_MAP_SCENE:RegisterCallback("StateChange", WorldMapStateChanged)
		GAMEPAD_WORLD_MAP_SCENE:RegisterCallback("StateChange", WorldMapStateChanged)
	end
	do
		local function SiegeStateChanged(oldState, newState)
			if (newState == SCENE_FRAGMENT_SHOWING) then
				MattsMiniMap:GoMiniMapMode(not g_inSpecialMode)
			end
		end
		SIEGE_BAR_SCENE:RegisterCallback("StateChange", SiegeStateChanged)
	end

	do
		local function WorldFragmentStateChanged(oldState, newState)
			if (newState == SCENE_FRAGMENT_SHOWING) then
				if MattsMiniMap.account.showClock then
					EVENT_MANAGER:RegisterForUpdate("VOTAN_MAP_CLOCK", 5000, MattsMiniMap.ShowClock)
					MattsMiniMap.ShowClock()
				end
			elseif (newState == SCENE_FRAGMENT_HIDING) then
				EVENT_MANAGER:UnregisterForUpdate("VOTAN_MAP_CLOCK")
			end
			local hidden = not MattsMiniMap.account.showClock
			MattsMiniMap.clockRealTime:SetHidden(hidden)
			MattsMiniMap.clockInGame:SetHidden(hidden)
		end
		WORLD_MAP_FRAGMENT:RegisterCallback("StateChange", WorldFragmentStateChanged)
	end

	do
		local orgZO_WorldMap_RefreshMapFrameAnchor = ZO_WorldMap_RefreshMapFrameAnchor
		function ZO_WorldMap_RefreshMapFrameAnchor(...)
			if MattsMiniMap.account and ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				RestorePosition()
				return
			end
			return orgZO_WorldMap_RefreshMapFrameAnchor(...)
		end
	end

	do
		local orgZO_WorldMap_PushSpecialMode = ZO_WorldMap_PushSpecialMode
		function ZO_WorldMap_PushSpecialMode(...)
			local mode = select(1, ...)
			local zoomOut = (mode == MAP_MODE_FAST_TRAVEL or mode == MAP_MODE_KEEP_TRAVEL)
			local orgZO_WorldMap_UpdateMap = ZO_WorldMap_UpdateMap
			if mode ~= MAP_MODE_VOTANS_MINIMAP and ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				ZO_WorldMap_UpdateMap = NoOp
				MattsMiniMap:GoWorldMapMode(zoomOut)
			end
			if zoomOut and GetMapType() == MAPTYPE_SUBZONE then
				asyncCallbacks:Cancel()
				MapZoomOut()

				ZO_WorldMap_UpdateMap = NoOp
				-- ZO_WorldMap_UpdateMap will be called in ZO_WorldMap_PushSpecialMode again, but not this time
				orgZO_WorldMap_PushSpecialMode(...)

				ZO_WorldMap_UpdateMap = orgZO_WorldMap_UpdateMap
				CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged", true)
				return
			end
			ZO_WorldMap_UpdateMap = orgZO_WorldMap_UpdateMap
			return orgZO_WorldMap_PushSpecialMode(...)
		end
	end

	do
		local orgZO_WorldMap_ShowWorldMap = ZO_WorldMap_ShowWorldMap
		function ZO_WorldMap_ShowWorldMap(...)
			if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				MattsMiniMap:GoWorldMapMode()
			end
			return orgZO_WorldMap_ShowWorldMap(...)
		end
	end

	do
		local function QuestTrackerRefreshedMapPins()
			if not ZO_WorldMap_IsWorldMapShowing() and not DoesCurrentMapMatchMapForPlayerLocation() then
				if SetMapToPlayerLocation() == SET_MAP_RESULT_MAP_CHANGED then
					CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
				end
			end
		end
		if GetAPIVersion() <= 100022 then
			QUEST_TRACKER:RegisterCallback("QuestTrackerRefreshedMapPins", QuestTrackerRefreshedMapPins)
		else
			FOCUSED_QUEST_TRACKER:RegisterCallback("QuestTrackerRefreshedMapPins", QuestTrackerRefreshedMapPins)
		end
	end

	do
		local orgSetHidden = ZO_WorldMapButtonsFloors.SetHidden
		function ZO_WorldMapButtonsFloors:SetHidden(hidden)
			return orgSetHidden(self, (not MattsMiniMap.account.allowFloorNavigation and ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP) or hidden)
		end
	end
	do
		local orgSetHidden = ZO_WorldMapButtonsLevels.SetHidden
		function ZO_WorldMapButtonsLevels:SetHidden(hidden)
			return orgSetHidden(self, (ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP) or hidden)
		end
	end

	do
		local handlers = ZO_AlertText_GetHandlers()
		local orgZoneChange = handlers[EVENT_ZONE_CHANGED]
		handlers[EVENT_ZONE_CHANGED] = function(...)
			local mode = self.account.zoneAlertMode
			if mode == self.zoneAlertMode.Never then
				return
			end
			if mode == self.zoneAlertMode.MiniMapHidden and WORLD_MAP_FRAGMENT:IsShowing() then
				return
			end
			return orgZoneChange(...)
		end
	end

	local ZO_MapPanAndZoom = getmetatable(ZO_WorldMap_GetPanAndZoom()).__index
	local function IsNormalizedPointInsideMapBounds(x, y)
		return (x > 0 and x < 1 and y > 0 and y < 1)
	end
	local function FocusZoomAndOffset(self, normalizedX, normalizedY)
		local mapId = GetMapTileTexture()
		local fixed = MattsMiniMap.account and MattsMiniMap.account.fixedMaps[mapId]
		if fixed then
			normalizedX, normalizedY = unpack(fixed)
		end

		if normalizedX and normalizedY and IsNormalizedPointInsideMapBounds(normalizedX, normalizedY) then
			local targetNormalizedZoom = 1
			local curvedTargetZoom = self:ComputeCurvedZoom(targetNormalizedZoom)

			local zoomedNX, zoomedNY = normalizedX * curvedTargetZoom, normalizedY * curvedTargetZoom
			local borderSizeN = (curvedTargetZoom - 1) * 0.5
			local offsetNX, offsetNY = 0.5 + borderSizeN - zoomedNX, 0.5 + borderSizeN - zoomedNY

			if not self.allowPanPastMapEdge then
				offsetNX, offsetNY = zo_clamp(offsetNX, -borderSizeN, borderSizeN), zo_clamp(offsetNY, -borderSizeN, borderSizeN)
			end

			local units = zo_max(ZO_WorldMapScroll:GetDimensions())
			local offsetX, offsetY = offsetNX * units, offsetNY * units

			return targetNormalizedZoom, offsetX, offsetY
		end
	end
	local orgGetNormalizedPositionFocusZoomAndOffset = ZO_MapPanAndZoom.GetNormalizedPositionFocusZoomAndOffset
	function ZO_MapPanAndZoom:GetNormalizedPositionFocusZoomAndOffset(normalizedX, normalizedY, useCurrentZoom)
		if ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
			return orgGetNormalizedPositionFocusZoomAndOffset(self, normalizedX, normalizedY, useCurrentZoom)
		else
			return FocusZoomAndOffset(self, normalizedX, normalizedY)
		end
	end

	local function refreshFragment()
		WORLD_MAP_FRAGMENT:Refresh()
	end
	local function mountedStateChanged()
		async:Call(refreshFragment)
	end
	EVENT_MANAGER:RegisterForEvent(MattsMiniMap.name, EVENT_MOUNTED_STATE_CHANGED, mountedStateChanged)
end

function MattsMiniMap:UpdateVisibility()
	if not isDirty then
		isDirty = true
		WORLD_MAP_FRAGMENT:Refresh()
	end
end

do
	local orgGetLeft = GAMEPAD_WORLD_MAP_TOOLTIP_FRAGMENT.control.GetLeft
	function GAMEPAD_WORLD_MAP_TOOLTIP_FRAGMENT.control:GetLeft()
		if ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
			return orgGetLeft(self)
		else
			local right = GAMEPAD_WORLD_MAP_INFO_FRAGMENT.control:GetRight()
			local padding = 50
			local width = MattsMiniMap.account.width or MattsMiniMap.modeData.width or 301
			return width + right + padding
		end
	end
	local orgGetHeight = ZO_KeybindStripGamepadBackgroundTexture.GetHeight
	function ZO_KeybindStripGamepadBackgroundTexture:GetHeight()
		if ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP then
			return orgGetHeight(self)
		else
			return -100
		end
	end
	-- local orgZO_WorldMapSetAnchor = ZO_WorldMap.SetAnchor
	-- function ZO_WorldMap:SetAnchor(...)
	-- 	d("SetAnchor", GetAddon())
	-- 	return orgZO_WorldMapSetAnchor(self, ...)
	-- end
	--  local orgZO_WorldMapSetDimensions = ZO_WorldMap.SetDimensions
	--  function ZO_WorldMap:SetDimensions(...)
	--  	d("SetDimensions", GetAddon())
	--  	return orgZO_WorldMapSetDimensions(self, ...)
	--  end

	do
		local ZO_MapPanAndZoom = MattsMiniMap.panZoom
		local orgZO_MapPanAndZoomUpdate = ZO_MapPanAndZoom.Update
		function ZO_MapPanAndZoom.Update(...)
			if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				return NoGamepad(orgZO_MapPanAndZoomUpdate, ...)
			end
			return orgZO_MapPanAndZoomUpdate(...)
		end
		local orgZO_MapPanAndZoomSetCurrentZoom = ZO_MapPanAndZoom.SetCurrentNormalizedZoom
		function ZO_MapPanAndZoom.SetCurrentNormalizedZoom(...)
			if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				return NoGamepad(orgZO_MapPanAndZoomSetCurrentZoom, ...)
			end
			return orgZO_MapPanAndZoomSetCurrentZoom(...)
		end

		local orgZO_WorldMap_UpdateMap = ZO_WorldMap_UpdateMap
		function ZO_WorldMap_UpdateMap(...)
			if ZO_WorldMap_GetMode() == MAP_MODE_VOTANS_MINIMAP then
				return NoGamepad(orgZO_WorldMap_UpdateMap, ...)
			end
			return orgZO_WorldMap_UpdateMap(...)
		end
	end
	do
		local function ApplyModeStyle()
			ApplyTemplateToControl(ZO_WorldMapMapFrame, ZO_GetPlatformTemplate("ZO_WorldMapFrame"))
			ApplyTemplateToControl(ZO_WorldMapButtonsFloors, ZO_GetPlatformTemplate("ZO_DungeonFloorNavigation"))
		end

		function MattsMiniMap:UpdateBorder()
			local _, numFloors = GetMapFloorInfo()
			ZO_WorldMapButtonsFloors:SetHidden(numFloors == 0)
			ZO_WorldMapButtonsLevels:SetHidden(not IsInGamepadPreferredMode())

			local control = self.background
			local inMiniMap = not GetScene():IsShowing()
			if inMiniMap then
				if self.lastTitleFont ~= self.account.titleFont then
					self.lastTitleFont = self.account.titleFont
					if self.account.titleFont and #self.account.titleFont > 0 then
						ZO_WorldMapTitle:SetFont(string.format("%s|%s|soft-shadow-thick", self.fontFaces[self.account.titleFont] or self.account.titleFont, self.account.titleFontSize))
					else
						ZO_WorldMapTitle:SetFont("")
					end
				end
				local item = lookup.nameToFontSize[self.account.titleFontSize]
				if item then
					ZO_WorldMapTitle:ClearAnchors()
					if self.account.titleAtTop then
						ZO_WorldMapTitle:SetAnchor(TOP, nil, TOP, 0, item.data.offsetY)
					else
						ZO_WorldMapTitle:SetAnchor(TOP, ZO_WorldMapMapFrame, BOTTOM, 0, item.data.offsetY)
					end
				end
				ZO_WorldMapButtons:ClearAnchors()
				if self.account.titleAtTop then
					ZO_WorldMapButtons:SetAnchor(BOTTOMLEFT, nil, BOTTOMLEFT, 4, -4)
					ZO_WorldMapButtons:SetAnchor(BOTTOMRIGHT, nil, BOTTOMRIGHT, -4, -4)
				else
					local offsetY = MattsMiniMap.account.showClock and ZO_WorldMapTitle:GetHeight() or 0
					ZO_WorldMapButtons:SetAnchor(TOPLEFT, ZO_WorldMapMapFrame, BOTTOMLEFT, 0, offsetY)
					ZO_WorldMapButtons:SetAnchor(TOPRIGHT, ZO_WorldMapMapFrame, BOTTOMRIGHT, 0, offsetY)
				end

				ZO_WorldMapTitle:SetColor(self.titleColor:UnpackRGB())
				ZO_WorldMapTitle:SetHidden(false)
				local enable = not (self.account.lockWindow or IsInGamepadPreferredMode())
				ZO_WorldMapButtonsBG:SetMouseEnabled(enable)
				ZO_WorldMapTitleBar:SetMouseEnabled(enable)
				ZO_WorldMap:SetMouseEnabled(enable)

				self:UpdateCompass()
				if IsInGamepadPreferredMode() then
					NoGamepad(ApplyModeStyle)
				end
				ZO_WorldMap:SetDrawLayer(DL_BACKGROUND)
				ZO_WorldMap:SetDrawLevel(0)

				local style = lookup.frameToFile[self.account.frameStyle]
				if style and style.data.setup then
					style.data.setup(self.account, control, ZO_WorldMapMapFrame)
					return
				end
			else
				ApplyModeStyle()
				ZO_WorldMap:SetMouseEnabled(true)
			end
			ZO_WorldMap:SetDrawLayer(DL_CONTROLS)
			ZO_WorldMap:SetDrawLevel(0)
			control:SetCenterColor(0, 0, 0, 0)
			control:SetEdgeColor(0, 0, 0, 0)
			control:SetCenterTexture("")
			control:SetInsets(0, 0, 0, 0)
			ZO_WorldMapMapFrame:SetEdgeTexture("/esoui/art/worldmap/worldmap_frame_edge.dds", 128, 16)
			ZO_WorldMapMapFrame:SetAlpha(1)
			ZO_WorldMapMapFrame:SetHidden(false)
			ZO_WorldMapTitle:SetHidden(true)
		end
	end
	function MattsMiniMap:UpdateCompass()
		if self.account.enableCompass ~= self.compassMode.Untouched then
			local hidden = self.player.showHUD and self.account.enableCompass ~= self.compassMode.Shown

			ZO_CompassCenterOverPinLabel:SetHidden(hidden)
			ZO_CompassContainer:SetHidden(hidden)
			ZO_CompassFrameLeft:SetHidden(hidden)
			ZO_CompassFrameCenter:SetHidden(hidden)
			ZO_CompassFrameRight:SetHidden(hidden)
		end
	end
end

function MattsMiniMap:Initialize()
	local accountDefaults = {
		enableTweaks = true,
		enableMap = true,
		zoom = 1.3,
		mountedZoom = 1,
		subZoneZoom = 1,
		dungeonZoom = 0.7,
		battlegroundZoom = 0,
		zoomOut = 0.15,
		zoomIn = 2,
		zoomToPlayer = false,
		frameStyle = "ESO",
		borderAlpha = 100,
		titleFont = "BOLD_FONT",
		titleFontSize = "$(KB_18)",
		titleColor = {GetInterfaceColor(INTERFACE_COLOR_TYPE_TEXT_COLORS, INTERFACE_TEXT_COLOR_NORMAL)},
		showClock = true,
		lockWindow = false,
		allowFloorNavigation = true,
		showFullTitle = false,
		showCameraAngle = false,
		cameraAngle = 45,
		zoneAlertMode = self.zoneAlertMode.MiniMapHidden,
		timeFormat = TIME_FORMAT_PRECISION_TWENTY_FOUR_HOUR,
		debug = false,
		asyncUpdate = false,
		enableCompass = self.compassMode.Untouched,
		titleAtTop = true,
		unitPinScaleLimit = 0.8,
		fixedMaps = {}
	}
	self.accountDefaults = accountDefaults

	self.account = ZO_SavedVars:NewAccountWide("VotansMiniMap_Data", 1, nil, accountDefaults)

	local defaults = {
		showHUD = self.account.showHUD or true,
		showLoot = self.account.showLoot or true,
		showMounted = self.account.showMounted or true,
		showCombat = self.account.showCombat or false,
		showSiege = self.account.showSiege or false
	}

	self.player = ZO_SavedVars:NewCharacterIdSettings("VotansMiniMap_Data", 1, nil, defaults)

	defaults = {
		showHUD = true,
		showLoot = true,
		showMounted = true,
		showCombat = false,
		showSiege = false
	}
	self.defaults = defaults

	if self.account.enableTweaks then
		self:InitTweaks()
	elseif self.account.enableMap then
		self:InitRequiredModifications()
	end
	if self.account.enableMap then
		lookup.frameToFile = {}
		for _, item in pairs(lookup.frameStyles) do
			lookup.frameToFile[item.data.value] = item
		end
		if not lookup.frameToFile[self.account.frameStyle] then
			self.account.frameStyle = "Default"
		end

		lookup.nameToFont = {}
		for _, item in pairs(lookup.fonts) do
			lookup.nameToFont[item.data] = item
		end
		if not lookup.nameToFont[self.account.titleFont] then
			self.account.titleFont = "BOLD_FONT"
		end

		self.titleColor = ZO_ColorDef:New(unpack(type(self.account.titleColor) == "table" and self.account.titleColor or accountDefaults.titleColor))
		self.titleColor:SetAlpha(1)

		lookup.nameToFontSize = {}
		for _, item in pairs(lookup.fontSizes) do
			lookup.nameToFontSize[item.data.size] = item
		end
		if not lookup.nameToFontSize[self.account.titleFontSize] then
			self.account.titleFontSize = "$(KB_18)"
		end

		self:InitMiniMap()
		HUD_UI_SCENE:RemoveFragment(MOUSE_UI_MODE_FRAGMENT)
		HUD_SCENE:AddFragment(WORLD_MAP_FRAGMENT)
		HUD_UI_SCENE:AddFragment(WORLD_MAP_FRAGMENT)
		SIEGE_BAR_SCENE:AddFragment(WORLD_MAP_FRAGMENT)
		SIEGE_BAR_UI_SCENE:AddFragment(WORLD_MAP_FRAGMENT)
		LOOT_SCENE:AddFragment(WORLD_MAP_FRAGMENT)
		HUD_UI_SCENE:AddFragment(MOUSE_UI_MODE_FRAGMENT)

		async:SetDebug(self.account.debug)
	end
end

function MattsMiniMap:AddBorderStyle(name, displayText, setupFunction, resetFunction)
	lookup.frameStyles[#lookup.frameStyles + 1] = {
		name = displayText,
		data = {value = name, setup = setupFunction, reset = resetFunction}
	}
end

function MattsMiniMap:AddFont(font, displayText)
	if zo_plainstrfind(font, "/") then
		self.fontFaces[font] = font
	else
		if not self.fontFaces[font] then
			self.fontFaces[font] = string.format("$(%s)", font)
		end
	end
	lookup.fonts[#lookup.fonts + 1] = {name = displayText, data = font}
end

function MattsMiniMap:AddFontSize(fontSize, displayText, offsetY)
	lookup.fontSizes[#lookup.fontSizes + 1] = {name = displayText, data = {size = fontSize, offsetY = offsetY}}
end

function MattsMiniMap:InitSettings()
	local LibHarvensAddonSettings = LibHarvensAddonSettings

	local settings = LibHarvensAddonSettings:AddAddon("Votan's Mini Map")
	if not settings then
		return
	end
	MattsMiniMap.settingsControls = settings
	settings.allowDefaults = true
	settings.version = "1.6.9"
	settings.website = "http://www.esoui.com/downloads/info1399-VotansMiniMap.html"

	settings:AddSetting {
		type = LibHarvensAddonSettings.ST_CHECKBOX,
		label = GetString(SI_VOTANSMINIMAP_WORLD_MAP_TWEAKS),
		tooltip = GetString(SI_VOTANSMINIMAP_WORLD_MAP_TWEAKS_TOOLTIP),
		default = self.accountDefaults.enableTweaks,
		getFunction = function()
			return self.account.enableTweaks
		end,
		setFunction = function(value)
			self.account.enableTweaks = value
		end
	}
	settings:AddSetting {
		type = LibHarvensAddonSettings.ST_CHECKBOX,
		label = GetString(SI_KEYBINDINGS_CATEGORY_VOTANS_MINIMAP),
		tooltip = GetString(SI_VOTANSMINIMAP_MINI_MAP_TOOLTIP),
		default = self.accountDefaults.enableMap,
		getFunction = function()
			return self.account.enableMap
		end,
		setFunction = function(value)
			self.account.enableMap = value
		end
	}
	settings:AddSetting {
		type = LibHarvensAddonSettings.ST_LABEL,
		label = ""
	}
	settings:AddSetting {
		type = LibHarvensAddonSettings.ST_BUTTON,
		label = "",
		tooltip = nil,
		buttonText = GetString(SI_VOTANSMINIMAP_APPLY_BUTTON),
		clickHandler = function()
			SLASH_COMMANDS["/reloadui"]()
		end
	}

	if self.account.enableMap then
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_LABEL,
			label = GetString(SI_KEYBINDINGS_CATEGORY_VOTANS_MINIMAP)
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_ZOOM),
			tooltip = GetString(SI_VOTANSMINIMAP_ZOOM_TOOLTIP),
			min = 0.0,
			max = 2,
			step = 0.05,
			default = self.accountDefaults.zoom,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.zoom
			end,
			setFunction = function(value)
				self.account.zoom = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_SUB_ZONE_ZOOM),
			tooltip = GetString(SI_VOTANSMINIMAP_SUB_ZONE_ZOOM_TOOLTIP),
			min = 0.0,
			max = 2,
			step = 0.05,
			default = self.accountDefaults.subZoneZoom,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.subZoneZoom
			end,
			setFunction = function(value)
				self.account.subZoneZoom = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_DUNGEON_ZOOM),
			tooltip = GetString(SI_VOTANSMINIMAP_DUNGEON_ZOOM_TOOLTIP),
			min = 0.0,
			max = 2,
			step = 0.05,
			default = self.accountDefaults.dungeonZoom,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.dungeonZoom
			end,
			setFunction = function(value)
				self.account.dungeonZoom = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_MOUNTED_ZOOM),
			tooltip = GetString(SI_VOTANSMINIMAP_MOUNTED_ZOOM_TOOLTIP),
			min = 0.0,
			max = 2,
			step = 0.05,
			default = self.accountDefaults.mountedZoom,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.mountedZoom
			end,
			setFunction = function(value)
				self.account.mountedZoom = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_BG_ZOOM),
			tooltip = GetString(SI_VOTANSMINIMAP_BG_ZOOM_TOOLTIP),
			min = 0.0,
			max = 2,
			step = 0.05,
			default = self.accountDefaults.battlegroundZoom,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.battlegroundZoom
			end,
			setFunction = function(value)
				self.account.battlegroundZoom = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_UNIT_PINS_MINIMUM_SIZE),
			tooltip = GetString(SI_VOTANSMINIMAP_UNIT_PINS_MINIMUM_SIZE_TOOLTIP),
			min = 0.65,
			max = 1,
			step = 0.01,
			default = self.accountDefaults.unitPinScaleLimit,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.unitPinScaleLimit
			end,
			setFunction = function(value)
				self.account.unitPinScaleLimit = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_HUD),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_HUD_TOOLTIP),
			default = self.defaults.showHUD,
			getFunction = function()
				return self.player.showHUD
			end,
			setFunction = function(value)
				self.player.showHUD = value
				self:UpdateVisibility()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = " |u12:0::|u" .. GetString(SI_VOTANSMINIMAP_SHOW_LOOTING),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_LOOTING_TOOLTIP),
			default = self.defaults.showLoot,
			getFunction = function()
				return self.player.showLoot
			end,
			setFunction = function(value)
				self.player.showLoot = value
				self:UpdateVisibility()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_MOUNTED),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_MOUNTED_TOOLTIP),
			default = self.defaults.showMounted,
			getFunction = function()
				return self.player.showMounted
			end,
			setFunction = function(value)
				self.player.showMounted = value
				self:UpdateVisibility()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_COMBAT),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_COMBAT_TOOLTIP),
			default = self.defaults.showCombat,
			getFunction = function()
				return self.player.showCombat
			end,
			setFunction = function(value)
				self.player.showCombat = value
				self:UpdateVisibility()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_SIEGE),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_SIEGE_TOOLTIP),
			default = self.defaults.showSiege,
			getFunction = function()
				return self.player.showSiege
			end,
			setFunction = function(value)
				self.player.showSiege = value
				self:UpdateVisibility()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_ASYNC_UPDATE),
			tooltip = GetString(SI_VOTANSMINIMAP_ASYNC_UPDATE_TOOLTIP),
			default = self.accountDefaults.asyncUpdate,
			getFunction = function()
				return self.account.asyncUpdate
			end,
			setFunction = function(value)
				self.account.asyncUpdate = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SECTION,
			label = GetString(SI_VOTANSMINIMAP_KEYBINDINGS_ZOOM)
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_ZOOM_TO_PLAYER),
			tooltip = GetString(SI_VOTANSMINIMAP_ZOOM_TO_PLAYER_TOOLTIP),
			default = self.accountDefaults.zoomToPlayer,
			getFunction = function()
				return self.account.zoomToPlayer
			end,
			setFunction = function(value)
				self.account.zoomToPlayer = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_ZOOM_OUT),
			tooltip = GetString(SI_VOTANSMINIMAP_ZOOM_OUT_TOOLTIP),
			min = 0.0,
			max = 1,
			step = 0.05,
			default = self.accountDefaults.zoomOut,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.zoomOut
			end,
			setFunction = function(value)
				self.account.zoomOut = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_ZOOM_IN),
			tooltip = GetString(SI_VOTANSMINIMAP_ZOOM_IN_TOOLTIP),
			min = 1,
			max = 2,
			step = 0.05,
			default = self.accountDefaults.zoomIn,
			format = "%f",
			unit = "",
			getFunction = function()
				return self.account.zoomIn
			end,
			setFunction = function(value)
				self.account.zoomIn = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SECTION,
			label = GetString(SI_VOTANSMINIMAP_APPEARANCE)
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_LOCK_POSITION),
			tooltip = GetString(SI_VOTANSMINIMAP_LOCK_POSITION_TOOLTIP),
			default = self.accountDefaults.lockWindow,
			getFunction = function()
				return self.account.lockWindow
			end,
			setFunction = function(value)
				self.account.lockWindow = value
				self:UpdateBorder()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_DROPDOWN,
			label = GetString(SI_VOTANSMINIMAP_BORDER_STYLE),
			items = lookup.frameStyles,
			default = lookup.frameToFile[self.accountDefaults.frameStyle].name,
			getFunction = function()
				return lookup.frameToFile[self.account.frameStyle].name
			end,
			setFunction = function(combobox, name, item)
				if self.account.frameStyle ~= item.data.value then
					local style = lookup.frameToFile[self.account.frameStyle]
					if style and style.data.reset then
						style.data.reset(self.account, self.background, ZO_WorldMapMapFrame)
					end
					self.account.frameStyle = item.data.value
					self:UpdateBorder()
				end
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = GetString(SI_VOTANSMINIMAP_BORDER_OPACITY),
			tooltip = GetString(SI_VOTANSMINIMAP_BORDER_OPACITY_TOOLTIP),
			min = 0,
			max = 100,
			step = 1,
			default = self.accountDefaults.borderAlpha,
			unit = "%",
			getFunction = function()
				return self.account.borderAlpha
			end,
			setFunction = function(value)
				self.account.borderAlpha = value
				self:UpdateBorder()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_DROPDOWN,
			label = GetString(SI_VOTANSMINIMAP_TITLE_FONT),
			items = lookup.fonts,
			default = lookup.nameToFont[self.accountDefaults.titleFont].name,
			getFunction = function()
				return lookup.nameToFont[self.account.titleFont].name
			end,
			setFunction = function(combobox, name, item)
				self.account.titleFont = item.data
				self:UpdateBorder()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_DROPDOWN,
			label = GetString(SI_VOTANSMINIMAP_TITLE_FONT_SIZE),
			items = lookup.fontSizes,
			default = lookup.nameToFontSize[self.accountDefaults.titleFontSize].name,
			getFunction = function()
				return lookup.nameToFontSize[self.account.titleFontSize].name
			end,
			setFunction = function(combobox, name, item)
				self.account.titleFontSize = item.data.size
				self.lastTitleFont = ""
				self:UpdateBorder()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_COLOR,
			label = GetString(SI_VOTANSMINIMAP_TITLE_COLOR),
			default = self.accountDefaults.titleColor,
			getFunction = function()
				return self.titleColor:UnpackRGB()
			end,
			setFunction = function(newR, newG, newB, newA)
				self.titleColor:SetRGB(newR, newG, newB)
				self.account.titleColor = {self.titleColor:UnpackRGB()}
				self:UpdateBorder()
			end
		}
		do
			local items = {
				{name = "Top", data = true},
				{name = "Bottom", data = false}
			}
			settings:AddSetting {
				type = LibHarvensAddonSettings.ST_DROPDOWN,
				label = GetString(SI_VOTANSMINIMAP_TITLE_POSITION),
				items = items,
				default = items[self.accountDefaults.titleAtTop and 1 or 2].name,
				getFunction = function()
					return items[self.account.titleAtTop and 1 or 2].name
				end,
				setFunction = function(combobox, name, item)
					self.account.titleAtTop = item.data
					self:UpdateBorder()
				end
			}
		end
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_FULL_TITLE),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_FULL_TITLE_TOOLTIP),
			default = self.accountDefaults.showFullTitle,
			getFunction = function()
				return self.account.showFullTitle
			end,
			setFunction = function(value)
				self.account.showFullTitle = value
				ZO_WorldMapTitle:SetText(ZO_WorldMap_GetMapTitle(GetPlayerLocationName(), GetPlayerActiveSubzoneName()))
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_ALLOW_FLOOR_NAVIGATION),
			tooltip = GetString(SI_VOTANSMINIMAP_ALLOW_FLOOR_NAVIGATION_TOOLTIP),
			default = self.accountDefaults.allowFloorNavigation,
			getFunction = function()
				return self.account.allowFloorNavigation
			end,
			setFunction = function(value)
				self.account.allowFloorNavigation = value
				self:UpdateBorder()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_KEEP_SQUARE),
			tooltip = GetString(SI_VOTANSMINIMAP_KEEP_SQUARE_TOOLTIP),
			default = true,
			getFunction = function()
				return self.modeData.keepSquare
			end,
			setFunction = function(value)
				self.account.keepSquare = value
				self.modeData.keepSquare = value
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_CLOCK),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_CLOCK_TOOLTIP),
			default = self.accountDefaults.showClock,
			getFunction = function()
				return self.account.showClock
			end,
			setFunction = function(value)
				self.account.showClock = value
				self:UpdateBorder()
			end
		}
		do
			local Modes = {
				{name = "12h", data = TIME_FORMAT_PRECISION_TWELVE_HOUR},
				{name = "24h", data = TIME_FORMAT_PRECISION_TWENTY_FOUR_HOUR}
			}
			local ModeToData = {}
			for i = 1, #Modes do
				ModeToData[Modes[i].data] = Modes[i]
			end
			settings:AddSetting {
				type = LibHarvensAddonSettings.ST_DROPDOWN,
				label = GetString(SI_VOTANSMINIMAP_TIME_FORMAT),
				items = Modes,
				default = ModeToData[self.accountDefaults.timeFormat].name,
				getFunction = function()
					return (ModeToData[self.account.timeFormat] or ModeToData[self.accountDefaults.timeFormat]).name
				end,
				setFunction = function(combobox, name, item)
					self.account.timeFormat = item.data
				end
			}
		end
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_CAMERA_HEADING),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_CAMERA_HEADING_TOOLTIP),
			default = self.accountDefaults.showCameraAngle,
			getFunction = function()
				return self.account.showCameraAngle
			end,
			setFunction = function(value)
				self.account.showCameraAngle = value
				if value then
					self:InitCameraAngle()
				end
				self.cameraAngle = 0
				if self.cameraAngleLeft then
					self.cameraAngleLeft:SetHidden(not value)
					self.cameraAngleRight:SetHidden(not value)
				end
				settings:UpdateControls()
			end
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = " |u12:0::|u" .. GetString(SI_VOTANSMINIMAP_CAMERA_HEADING_ANGLE),
			tooltip = GetString(SI_VOTANSMINIMAP_CAMERA_HEADING_ANGLE_TOOLTIP),
			min = 20,
			max = 70,
			step = 1,
			default = self.accountDefaults.cameraAngle,
			unit = "°",
			getFunction = function()
				return self.account.cameraAngle
			end,
			setFunction = function(value)
				self.account.cameraAngle = value
				self.cameraAngleRad = value * 0.0174532925199 -- pi/180°
			end,
			disable = function()
				return not self.account.showCameraAngle
			end
		}
		do
			local Modes = {
				{name = GetString(SI_VOTANSMINIMAP_ZONEALERTMODE_ALWAYS), data = self.zoneAlertMode.Always},
				{name = GetString(SI_VOTANSMINIMAP_ZONEALERTMODE_MAP_HIDDEN), data = self.zoneAlertMode.MiniMapHidden},
				{name = GetString(SI_VOTANSMINIMAP_ZONEALERTMODE_NEVER), data = self.zoneAlertMode.Never}
			}
			local ModeToData = {}
			for i = 1, #Modes do
				ModeToData[Modes[i].data] = Modes[i]
			end
			settings:AddSetting {
				type = LibHarvensAddonSettings.ST_DROPDOWN,
				label = GetString(SI_VOTANSMINIMAP_ZONE_CHANGE_ALERT),
				items = Modes,
				default = ModeToData[self.accountDefaults.zoneAlertMode].name,
				getFunction = function()
					return (ModeToData[self.account.zoneAlertMode] or ModeToData[self.accountDefaults.zoneAlertMode]).name
				end,
				setFunction = function(combobox, name, item)
					self.account.zoneAlertMode = item.data
				end
			}
		end
		do
			local Modes = {
				{name = GetString(SI_VOTANSMINIMAP_COMPASSMODE_UNTOUCHED), data = self.compassMode.Untouched},
				{name = GetString(SI_VOTANSMINIMAP_COMPASSMODE_HIDDEN), data = self.compassMode.Hidden},
				{name = GetString(SI_VOTANSMINIMAP_COMPASSMODE_SHOWN), data = self.compassMode.Shown}
			}
			local ModeToData = {}
			for i = 1, #Modes do
				ModeToData[Modes[i].data] = Modes[i]
			end
			settings:AddSetting {
				type = LibHarvensAddonSettings.ST_DROPDOWN,
				label = GetString(SI_VOTANSMINIMAP_SHOW_COMPASS),
				tooltip = GetString(SI_VOTANSMINIMAP_SHOW_COMPASS_TOOLTIP),
				items = Modes,
				default = ModeToData[self.accountDefaults.enableCompass].name,
				getFunction = function()
					return (ModeToData[self.account.enableCompass] or ModeToData[self.accountDefaults.enableCompass]).name
				end,
				setFunction = function(combobox, name, item)
					self.account.enableCompass = item.data
					self:UpdateCompass()
				end
			}
		end
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_SECTION,
			label = GetString(SI_VOTANSMINIMAP_FRAMEDROP_DEBUG)
		}
		settings:AddSetting {
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_VOTANSMINIMAP_SHOW_FREEZE_WARNING),
			tooltip = GetString(SI_VOTANSMINIMAP_SHOW_FREEZE_WARNING_TOOLTIP),
			default = false,
			getFunction = function()
				return async:GetDebug()
			end,
			setFunction = function(value)
				self.account.debug = value
				async:SetDebug(value)
			end
		}
	end
end

CALLBACK_MANAGER:RegisterCallback(
	"OnWorldMapSavedVarsReady",
	function(vars)
		MattsMiniMap.mapVars = vars
	end
)

do
	local function UpdateControls()
		if MattsMiniMap.settingsControls.selected then
			MattsMiniMap.settingsControls:UpdateControls()
		end
	end
	function MattsMiniMap:ToggleShowHUD()
		if IsMounted() then
			self.player.showMounted = not self.player.showMounted
		else
			self.player.showHUD = not self.player.showHUD
		end
		self:UpdateVisibility()
		self:UpdateCompass()
		UpdateControls()
	end
	function MattsMiniMap:ToggleShowCombat()
		self.player.showCombat = not self.player.showCombat
		self:UpdateVisibility()
		UpdateControls()
	end
	function MattsMiniMap:ToggleShowSiege()
		self.player.showSiege = not self.player.showSiege
		self:UpdateVisibility()
		UpdateControls()
	end
	function MattsMiniMap:ToogleZoom(enabled, zoom)
		self.isSpecialZoom = enabled
		if enabled then
			self.specialZoom = zoom or 1
		end
	end
	function MattsMiniMap:StepZoom(add)
		if ZO_WorldMap_GetMode() ~= MAP_MODE_VOTANS_MINIMAP or WORLD_MAP_FRAGMENT:IsHidden() or MattsMiniMap.isSpecialZoom or not self.account[self.zoomMode] then
			PlaySound(SOUNDS.NEGATIVE_CLICK)
			return
		end

		local step = -0.05
		if add then
			step = -step
		end

		self.account[self.zoomMode] = math.max(0, math.min(2, self.account[self.zoomMode] + step))
		UpdateControls()
	end
	local function IsMouseOverMap()
		if IsInGamepadPreferredMode() then
			return SCENE_MANAGER:IsShowing("gamepad_worldMap")
		else
			return not ZO_WorldMapScroll:IsHidden() and MouseIsOver(ZO_WorldMapScroll) and SCENE_MANAGER:IsShowing("worldMap")
		end
	end
	local function NormalizePreferredMousePositionToMap()
		if (IsInGamepadPreferredMode()) then
			local x, y = ZO_WorldMapScroll:GetCenter()
			return NormalizePointToControl(x, y, ZO_WorldMapContainer)
		else
			return NormalizeMousePositionToControl(ZO_WorldMapContainer)
		end
	end
	local function distanceSq(x1, y1, x2, y2)
		local dx, dy = x2 - x1, y2 - y1
		return dx * dx + dy * dy
	end
	function MattsMiniMap:ToggleFixedOffset()
		local mapId = GetMapTileTexture()
		local isNotFixed = not self.account.fixedMaps[mapId]
		local isMouseOverMap = IsMouseOverMap()
		if isNotFixed and not isMouseOverMap then
			PlaySound(SOUNDS.NEGATIVE_CLICK)
			return
		end
		if isMouseOverMap then
			local offsetX, offsetY = NormalizePreferredMousePositionToMap()
			if isNotFixed or distanceSq(offsetX, offsetY, unpack(self.account.fixedMaps[mapId])) > 0.0001 then
				self.account.fixedMaps[mapId] = {offsetX, offsetY}
				PlaySound(SOUNDS.MAP_PING)
			else
				self.account.fixedMaps[mapId] = nil
				PlaySound(SOUNDS.MAP_PING_REMOVE)
			end
		else
			self.account.fixedMaps[mapId] = nil
			PlaySound(SOUNDS.MAP_PING_REMOVE)
		end
	end
end

local function OnAddonLoaded(event, name)
	if name ~= MattsMiniMap.name then
		return
	end

	EVENT_MANAGER:UnregisterForEvent(MattsMiniMap.name, EVENT_ADD_ON_LOADED)
	MattsMiniMap:Initialize()
	MattsMiniMap:InitSettings()
	-- MattsMiniMap:InitPinLevels()
end

EVENT_MANAGER:RegisterForEvent(MattsMiniMap.name, EVENT_ADD_ON_LOADED, MattsMiniMap.OnAddonLoaded)
