local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local Helpers = Addon:GetModule("Helpers")
local L = Addon:GetModule("Locale")
local PinHelper = Addon:GetModule("PinHelper")
local Window = Addon:GetModule("Window")

-- The "Trainers" tab: the pet trainers by zone, colored by faction, on the left; the selected one on the right with
-- its title, level, location and faction, and a small copy of the zone map with a pin on it.

local PlayClick = Helpers.PlayClick
local MINI_MAP_WIDTH = Helpers.MINI_MAP_WIDTH

local function TrainerOnClick(button)
  PlayClick()
  Window:SelectTrainer(button.ftTrainer)
end

-- ============================================================================
-- Trainers
-- ============================================================================

local TRAINER_ICON = "Interface\\Icons\\Ability_Hunter_BeastTraining"

local function ZoneName(trainer)
  local name = trainer.zone_id and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(trainer.zone_id)
  return name or trainer.zone or L.UNKNOWN
end

local function SideName(side)
  if side == "alliance" then return FACTION_ALLIANCE or L.ALLIANCE end
  if side == "horde" then return FACTION_HORDE or L.HORDE end
  if side == "both" then return L.BOTH_FACTIONS end
  return L.UNKNOWN
end

-- Visible trainers that match the search (name, title or zone), grouped by zone: { { zone, trainers }, ... }.
-- With Filter by Faction on, only trainers the character's faction can use (their own and both-faction ones).
function Window:FactionShown(trainer)
  if not DB.global.filter_by_faction then return true end
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local side = trainer.side
  if not faction or not side or side == "both" then return true end
  return side == faction:lower()
end

function Window:GetTrainerGroups()
  local byZone = {}
  for _, trainer in pairs(Addon.TameableTrainers or {}) do
    local zone = ZoneName(trainer)
    local haystack = (trainer.name .. " " .. (trainer.tag or "") .. " " .. zone):lower()
    if (self.search == "" or haystack:find(self.search, 1, true)) and self:FactionShown(trainer) then
      byZone[zone] = byZone[zone] or {}
      table.insert(byZone[zone], trainer)
    end
  end
  local groups = {}
  for zone, trainers in pairs(byZone) do
    table.sort(trainers, function(a, b) return a.name < b.name end)
    groups[#groups + 1] = { zone = zone, trainers = trainers }
  end
  table.sort(groups, function(a, b) return a.zone < b.zone end)
  -- The Zone Filter: only the player's zone. A zone without a trainer lists none, as the other tabs list nothing for a
  -- zone without creatures (it used to list every trainer then, which read as the filter not working).
  local zone = self:ZoneFilter()
  if zone then
    local here = {}
    for _, group in ipairs(groups) do
      local inZone = group.zone == zone.name
      for _, trainer in ipairs(group.trainers) do
        if zone.map and trainer.ui_map_id == zone.map then inZone = true end
      end
      if inZone then here[#here + 1] = group end
    end
    return here
  end
  return groups
end

function Window:RefreshTrainers()
  local groups = self:GetTrainerGroups()
  local provider = CreateTreeDataProvider()
  local count, first, stillListed = 0, nil, false
  self.listKeys = {}
  for _, group in ipairs(groups) do
    local key = "zone:" .. group.zone
    self.listKeys[#self.listKeys + 1] = key
    local category = provider:Insert({ categoryInfo = { name = group.zone }, key = key })
    self:SetCollapsed(category, key)
    for _, trainer in ipairs(group.trainers) do
      category:Insert({ trainer = trainer })
      count = count + 1
      first = first or trainer
      if trainer == self.selectedTrainer then stillListed = true end
    end
  end
  if not stillListed then
    local saved = self:Sticky() and Addon.TameableTrainers[DB.global.selections.TRAINERS]
    local listed = false
    for _, group in ipairs(groups) do
      for _, trainer in ipairs(group.trainers) do
        if trainer == saved then listed = true end
      end
    end
    self.selectedTrainer = listed and saved or first
  end

  self.scrollBox:SetDataProvider(provider)
  self.noResults:SetShown(first == nil)
  self.headerCount:SetFormattedText(L.TRAINER_COUNT, count)
  self:UpdateToggleButton()
  self:UpdateTrainerDetails()
end

local function TrainerOnEnter(button)
  local trainer = button.ftTrainer
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(trainer.name)
  if trainer.tag then GameTooltip:AddLine(trainer.tag, 1, 1, 1) end
  GameTooltip:AddLine(("%s (%s)"):format(ZoneName(trainer), SideName(trainer.side)), 1, 1, 1)
  GameTooltip:Show()
end

function Window:InitTrainerButton(button, trainer)
  button.Label:SetText(trainer.name)
  button.Label:SetVertexColor((Colors.Side[trainer.side] or Colors.Default):GetRGB()) -- by faction, as on the website
  self:SetRowCount(button, nil)
  self:SetRowSelected(button, self.selectedTrainer == trainer)

  button.ftTrainer = trainer
  button:RegisterForClicks("LeftButtonUp")
  button:SetScript("OnClick", TrainerOnClick)
  button:SetScript("OnEnter", TrainerOnEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

function Window:SelectTrainer(trainer)
  self.selectedTrainer = trainer
  self:Remember()
  self:MarkSelected("trainer", function(other) return other == trainer end)
  self:UpdateTrainerDetails()
end

function Window:UpdateTrainerDetails()
  local trainer = self.selectedTrainer
  if not trainer then
    self.details:Hide()
    return
  end
  self.details:Show()

  self.icon:SetTexture(TRAINER_ICON)
  self.name:SetText(trainer.name)
  self.subtitle:SetText(trainer.tag or "")
  local coords = trainer.coords and trainer.coords[1]
  self.facts:SetText(table.concat({
    ("%s: %s"):format(Colors.Label(L.LEVEL), trainer.level_range or "?"),
    ("%s: %s"):format(Colors.Label(L.LOCATION), ZoneName(trainer)),
    ("%s: %s"):format(Colors.Label(L.FACTION), SideName(trainer.side)),
    coords and ("%s: %.1f, %.1f"):format(Colors.Label(L.COORDINATES), coords.x, coords.y) or nil,
  }, "\n"))
  self.description:SetText("")
  self:PlaceDescription()

  -- No creature list for a trainer: a small map with a pin on them, and the map button under it.
  self.npcLabel:Hide()
  self.npcBox:Hide()
  self.npcBar:Hide()
  local hasMap = trainer.ui_map_id and coords
  local function openMap(_, mouseButton) PinHelper:MapClick(trainer, mouseButton) end

  local miniMap = self.miniMap
  miniMap:ClearAllPoints()
  miniMap:SetPoint("TOPLEFT", self.description, "TOPLEFT", 0, 0)
  local shown = hasMap and self:DrawMiniMap(trainer.ui_map_id, coords.x, coords.y)
  miniMap:SetShown(shown and true or false)
  miniMap:SetScript("OnMouseUp", openMap)

  self.mapButton:ClearAllPoints()
  if shown then
    self.mapButton:SetPoint("TOPLEFT", miniMap, "BOTTOMLEFT", 0, -10)
  else
    self.mapButton:SetPoint("TOPLEFT", self.description, "TOPLEFT", 0, 0)
  end
  self.mapButton:SetText(hasMap and L.MAP or L.MAP_UNAVAILABLE)
  self.mapButton:SetWidth(MINI_MAP_WIDTH) -- as wide as the map preview it sits under
  self.mapButton:SetEnabled(hasMap and true or false)
  self.mapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (right-click clears the pins)
  self.mapButton:SetScript("OnClick", openMap)
  self.mapButton:SetScript("OnEnter", function(button) PinHelper:ShowMapTooltip(button) end)
  self.mapButton:SetScript("OnLeave", GameTooltip_Hide)
  self.mapButton:Show()
end

-- Draws a zone's map art into the small map and puts the pin at x, y (0-100). Returns false when the
-- game has no art for that map.
function Window:DrawMiniMap(uiMapId, x, y)
  local miniMap = self.miniMap
  for _, tile in ipairs(miniMap.tiles) do tile:Hide() end

  local getLayers = C_Map and C_Map.GetMapArtLayers
  local getTextures = C_Map and C_Map.GetMapArtLayerTextures
  if not (getLayers and getTextures) then return false end
  local ok, layers = pcall(getLayers, uiMapId)
  local layer = ok and layers and layers[1]
  if not layer or not layer.layerWidth or layer.layerWidth == 0 then return false end
  local textures = getTextures(uiMapId, 1)
  if not textures or #textures == 0 then return false end

  -- The art is a grid of tiles covering at least layerWidth x layerHeight; scale it to the frame's width.
  local scale = MINI_MAP_WIDTH / layer.layerWidth
  local height = layer.layerHeight * scale
  miniMap:SetSize(MINI_MAP_WIDTH, height)
  local columns = math.ceil(layer.layerWidth / layer.tileWidth)
  local tileWidth, tileHeight = layer.tileWidth * scale, layer.tileHeight * scale
  for i, fileId in ipairs(textures) do
    local tile = miniMap.tiles[i]
    if not tile then
      tile = miniMap:CreateTexture(nil, "ARTWORK")
      miniMap.tiles[i] = tile
    end
    local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
    tile:SetTexture(fileId)
    tile:SetSize(tileWidth, tileHeight)
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", miniMap, "TOPLEFT", column * tileWidth, -row * tileHeight)
    tile:Show()
  end

  miniMap.pin:ClearAllPoints()
  miniMap.pin:SetPoint("CENTER", miniMap, "TOPLEFT", x / 100 * MINI_MAP_WIDTH, -(y / 100) * height)
  return true
end
