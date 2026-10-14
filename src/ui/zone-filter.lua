local _, Addon = ...
local DB = Addon:GetModule("DB")
local Window = Addon:GetModule("Window")

-- The Zone Filter: the Zone button in the header (Window:CreateFilterButtons). While it is on, the ability tabs list only
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
  -- (Turned on and off by the Zone button in the header: Window:CreateFilterButtons.)
  -- The lists follow the player into a new zone.
  frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  frame:HookScript("OnEvent", function(_, event)
    if event == "ZONE_CHANGED_NEW_AREA" and frame:IsShown() and DB.global.zone_filter then self:Refresh() end
  end)
end
