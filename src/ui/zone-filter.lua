local _, Addon = ...
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")
local Window = Addon:GetModule("Window")

-- The Zone Filter: a checkbox in the title bar, left of the close button. While it is on, the ability tabs list only
-- the tameable creatures in the zone the player is in, and the Trainers tab only that zone's trainers (all of them
-- when the zone has none). The setting is saved (DB.global.zone_filter); the lists follow the player into a new zone.

-- The zone the player is in: its name (as the game names zones, in the player's language) and its world map (the
-- zone's, not a subzone's or a dungeon level's). nil when the game does not say.
function Window:PlayerZone()
  local name = GetRealZoneText and GetRealZoneText()
  if not name or name == "" then return nil end
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  -- Up to the zone's own map.
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  local info = map and C_Map.GetMapInfo(map)
  while info and info.mapType and info.mapType > zoneType and info.parentMapID and info.parentMapID > 0 do
    map = info.parentMapID
    info = C_Map.GetMapInfo(map)
  end
  return { name = name, map = map }
end

-- The zone to filter by: the player's, while the filter is on (nil otherwise).
function Window:ZoneFilter()
  if not DB.global.zone_filter then return nil end
  return self:PlayerZone()
end

-- Whether a creature lives in the zone: one of its zones has the zone's name, or it has map points on the zone's map.
function Window:NPCInZone(npc, zone)
  for _, name in ipairs(npc.zone_names or {}) do
    if name == zone.name then return true end
  end
  return zone.map ~= nil and ((npc.maps and npc.maps[zone.map]) or npc.map == zone.map) and true or false
end

function Window:CreateZoneFilter(frame)
  -- In the title bar (the template's own frame for it, when it has one), at the close button's level: the title bar's
  -- art is drawn over anything lower.
  local close = frame.CloseButton
  local check = CreateFrame("CheckButton", nil, frame.TitleContainer or frame, "UICheckButtonTemplate")
  check:SetSize(22, 22)
  if close then
    check:SetPoint("RIGHT", close, "LEFT", -2, 0)
    check:SetFrameStrata(close:GetFrameStrata())
    check:SetFrameLevel(close:GetFrameLevel() + 1)
  else
    check:SetPoint("TOPRIGHT", -28, 0)
    check:SetFrameLevel(frame:GetFrameLevel() + 500)
  end
  local label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("RIGHT", check, "LEFT", 0, 1)
  label:SetText(L.ZONE_FILTER)
  check:SetChecked(DB.global.zone_filter == true)
  check:SetScript("OnClick", function(this)
    DB.global.zone_filter = this:GetChecked() and true or false
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    self:Refresh()
  end)
  check:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L.ZONE_FILTER_TITLE, 1, 1, 1)
    local zone = self:PlayerZone()
    if zone then GameTooltip:AddLine(zone.name, 1, 0.82, 0) end
    GameTooltip:AddLine(L.ZONE_FILTER_TOOLTIP, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", GameTooltip_Hide)
  self.zoneFilterCheck = check

  -- The lists follow the player into a new zone.
  frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  frame:HookScript("OnEvent", function(_, event)
    if event == "ZONE_CHANGED_NEW_AREA" and frame:IsShown() and DB.global.zone_filter then self:Refresh() end
  end)
end
