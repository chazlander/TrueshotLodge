local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local HBDPins = Addon:GetLibrary("HBDPins")
local L = Addon:GetModule("Locale")
local PinHelper = Addon:GetModule("PinHelper")

local pins = {}
local pool = {}

-- ============================================================================
-- Callbacks
-- ============================================================================

-- Creatures and trainers share these pins; only the lines with data are shown.
local R, G, B = unpack(Colors.TextRGB)
local function line(label, value)
  if value ~= nil and value ~= "" then
    GameTooltip:AddDoubleLine(label, value, nil, nil, nil, R, G, B)
  end
end

-- The creature's (or trainer's) lines in GameTooltip, which is already owned: its name, title, level, abilities,
-- family, diet, type, attack speed and location. A creature's missing level, attack speed or zone shows as unknown.
function PinHelper:AddTooltipLines(npc)
  GameTooltip:SetText(Colors.Primary(npc.name))
  if npc.tag then GameTooltip:AddLine(npc.tag, R, G, B) end
  line(L.LEVEL, npc.level_range)
  line(L.ABILITIES, type(npc.abilities) == "table" and table.concat(npc.abilities, ", ") or nil)
  line(L.FAMILY, Addon:FamilyLabel(npc.family))
  line(L.DIET, npc.diet)
  line(L.TYPE, npc.type)
  line(L.ATTACK_SPEED, npc.speed_text) -- creatures only (trainers have none)
  line(L.LOCATION, npc.location or npc.zone or (npc.speed_text and L.UNKNOWN_ZONE) or nil)
end

local function onEnter(self)
  -- Show highlight
  self.highlight:SetAlpha(0.4)
  -- Show tooltip
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  PinHelper:AddTooltipLines(self.npc)
  GameTooltip:AddDoubleLine(L.LEFT_CLICK, L.CLEAR_PINS, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function onLeave(self)
  self.highlight:SetAlpha(0)
  GameTooltip:Hide()
end

local function onClick(self)
  PinHelper:Clear()
end

-- ============================================================================
-- Functions
-- ============================================================================

-- Opens the world map on the npc's map and pins every place it has been seen. A creature without map points opens
-- its zone's map without pins. Returns false when the npc has no map at all.
function PinHelper:ShowOnMap(npc)
  if not npc or not npc.ui_map_id then return false end

  -- `WorldMapFrame:Show()` doesn't open the map on newer clients.
  if OpenWorldMap then
    OpenWorldMap(npc.ui_map_id)
  else
    if not WorldMapFrame:IsShown() then ToggleWorldMap() end
    WorldMapFrame:SetMapID(npc.ui_map_id)
  end

  self:Clear()
  for _, coords in ipairs(npc.coords or {}) do
    HBDPins:AddWorldMapIconMap(Addon, self:Get(npc), npc.ui_map_id, coords.x * 0.01, coords.y * 0.01,
      HBD_PINS_WORLDMAP_SHOW_WORLD)
  end
  return true
end

function PinHelper:Get(npc)
  local pin = next(pool)

  if pin then
    pool[pin] = nil
  else
    pin = CreateFrame("Button", nil, WorldMapFrame)
    pin:SetSize(14, 14)

    pin.texture = pin:CreateTexture(nil, "BACKGROUND")
    pin.texture:SetTexture(Addon.PIN_ICON)
    pin.texture:SetAllPoints()

    pin.highlight = pin:CreateTexture(nil, "HIGHLIGHT")
    pin.highlight:SetTexture(Addon.PIN_ICON)
    pin.highlight:SetBlendMode("ADD")
    pin.highlight:SetAlpha(0)
    pin.highlight:SetAllPoints(pin.texture)

    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    pin:SetScript("OnClick", onClick)

    pins[#pins + 1] = pin
  end

  pin.npc = npc
  pin:Show()
  return pin
end

function PinHelper:Clear()
  for _, pin in next, pins do
    pin:Hide()
    pool[pin] = true
  end
  HBDPins:RemoveAllWorldMapIcons(Addon)
end

function PinHelper:Hide()
  for _, pin in next, pins do pin:Hide() end
end
