local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local DB = Addon:GetModule("DB")
local L = Addon:GetModule("Locale")

-- Pet families hunters can tame: the generated family data, by English name.
local function IsHunterFamily(family)
  return Addon.TameableFamilies ~= nil and Addon.TameableFamilies[family] ~= nil
end

-- Pet family id (CreatureFamily.db2) for an English family name, from the generated family data.
local function GetFamilyId(family)
  local info = Addon.TameableFamilies and Addon.TameableFamilies[family]
  return info and info.id
end

local TITLE = Colors.Primary(Addon.TITLE)
local R, G, B = unpack(Colors.TextRGB)
local format = string.format

-- Adds the family (with id) and attack speed lines.
local function AddInfoLines(tooltip, unit, family)
  if family then
    local familyId = GetFamilyId(family)
    local label = Addon:FamilyLabel(family)
    local text = familyId and format("%s (%d)", label, familyId) or label
    tooltip:AddDoubleLine("  " .. L.FAMILY, text, nil, nil, nil, R, G, B)
  end

  -- The speed may be a "secret" value, which can't be compared or used in
  -- arithmetic. Formatting it is allowed; pcall covers a nil or blocked value.
  if unit then
    local ok, speed = pcall(format, "%.2f", UnitAttackSpeed(unit))
    if ok then
      -- The speed's spell tier, e.g. "1.20 (Faster Attack VI)"; the speed is read as text so a hidden value
      -- cannot error here.
      local _, rounded = pcall(format, "%.1f", UnitAttackSpeed(unit))
      local tier = Addon:GetAttackTierName(rounded) -- none for a secret speed (in combat)
      if tier then speed = ("%s (%s)"):format(speed, tier) end
      tooltip:AddDoubleLine("  " .. L.ATTACK_SPEED, speed, nil, nil, nil, R, G, B)
    end
  end
end

-- The wild creature a tamed pet came from, when the npc id in the pet's GUID is one the addon knows. (On this
-- client every hunter pet carries the same id, 165189, which is no creature in the data, so nothing is shown
-- for those.)
local function AddOriginLine(tooltip, id, npc)
  if not npc then return end
  tooltip:AddDoubleLine("  " .. L.ORIGIN, ("%s (%s)"):format(npc.name, id), nil, nil, nil, R, G, B)
end

local function AddAbilityLines(tooltip, npc)
  for _, ability in ipairs(npc.abilities) do
    tooltip:AddLine("  " .. ability, R, G, B)
  end
end

local function OnTooltipSetUnit(self, data)
  if not DB.global.npc_tooltips then return end

  -- Get guid. Newer clients pass it in the tooltip data.
  local _, unit = self:GetUnit()
  local guid = data and data.guid or (unit and UnitGUID(unit))
  if not guid then return Addon:Debug("tooltip: no unit") end

  -- Get unit type and id.
  local unitType, _, _, _, _, id = strsplit("-", guid)
  if not (id and (unitType == "Creature" or unitType == "Pet")) then
    return Addon:Debug("tooltip: not a creature", guid)
  end

  -- Get live unit info.
  if not unit and UnitTokenFromGUID then unit = UnitTokenFromGUID(guid) end
  local family = unit and Addon:UnitFamily(unit) -- English, whatever the client's language; nil for demons
  local npc = Addon:GetNPC(id)

  -- Pets owned by a player. Only hunter families count (not warlock demons).
  if unitType == "Pet" or (unit and UnitPlayerControlled(unit)) then
    if not (family and IsHunterFamily(family)) then return end

    self:AddLine(TITLE)
    AddInfoLines(self, unit, family)
    AddOriginLine(self, id, npc)
    self:AddDoubleLine("  " .. L.TAMEABLE, L.ALREADY_OWNED, nil, nil, nil, R, G, B)
    if npc then AddAbilityLines(self, npc) end
    return
  end

  if not npc then
    Addon:Debug("tooltip: npc not in data", id)

    -- Fall back to live unit info. Only creatures with a pet family are shown.
    if not family then return end

    self:AddLine(TITLE)
    AddInfoLines(self, unit, family)
    self:AddDoubleLine("  " .. L.TAMEABLE, L.LIKELY, nil, nil, nil, R, G, B)
    self:AddDoubleLine("  " .. L.ABILITIES, L.UNKNOWN, nil, nil, nil, 0.6, 0.6, 0.6)
    return
  end
  Addon:Debug("tooltip: npc found", id, npc.name)

  -- Add lines.
  self:AddLine(TITLE)
  AddInfoLines(self, unit, family or npc.family)
  AddAbilityLines(self, npc)
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  -- Newer clients no longer fire the `OnTooltipSetUnit` script.
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
    if tooltip == GameTooltip then
      -- Unit info may be "secret" on newer clients; don't let that error out.
      local ok, err = pcall(OnTooltipSetUnit, tooltip, data)
      if not ok then Addon:Debug("tooltip error:", err) end
    end
  end)
else
  GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
end
