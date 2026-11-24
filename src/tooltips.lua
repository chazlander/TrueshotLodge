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

-- The lines under a creature's or a pet's tooltip are gathered first and added only when there is at least one (each
-- line can be turned off in Options, Tooltips), so a tooltip with every line off gets no TrueshotLodge heading either.
local function NewLines()
  local lines = {}
  -- A line with a label (indented) and a value, the value in the text color unless given one.
  function lines.add(field, label, value, r, g, b)
    if not Addon:TooltipShows(field) then return end
    lines[#lines + 1] = { label = "  " .. label, value = value, r = r or R, g = g or G, b = b or B }
  end
  -- A line on its own (an ability).
  function lines.addText(field, text)
    if not Addon:TooltipShows(field) then return end
    lines[#lines + 1] = { text = "  " .. text }
  end
  function lines.into(tooltip)
    if #lines == 0 then return end
    tooltip:AddLine(TITLE)
    for _, line in ipairs(lines) do
      if line.text then
        tooltip:AddLine(line.text, R, G, B)
      else
        tooltip:AddDoubleLine(line.label, line.value, nil, nil, nil, line.r, line.g, line.b)
      end
    end
  end
  return lines
end

-- The family (with id) and attack speed lines.
local function AddInfoLines(lines, unit, family)
  if family then
    local familyId = GetFamilyId(family)
    local label = Addon:FamilyLabel(family)
    lines.add("family", L.FAMILY, familyId and format("%s (%d)", label, familyId) or label)
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
      lines.add("speed", L.ATTACK_SPEED, speed)
    end
  end
end

-- A creature a TrueshotLodge hunter has tamed: "Tamed" with the green dot after it (as in the window's creature lists),
-- and the day and who, when they sent their name.
local function AddTamedLine(lines, npc)
  if Addon:NPCMark(npc) ~= "tamed" then return end
  local by = type(npc.tamed_by) == "string" and npc.tamed_by ~= "" and npc.tamed_by or nil
  lines.add("tamed", ("%s |T%s:12:12:0:0|t"):format(L.TAMED, Addon.GREEN_DOT),
    by and L.TAMED_DATE_BY:format(npc.tamed, by) or npc.tamed)
end

-- The wild creature a tamed pet came from, when the npc id in the pet's GUID is one the addon knows. (On this
-- client every hunter pet carries the same id, 165189, which is no creature in the data, so nothing is shown
-- for those.)
local function AddOriginLine(lines, id, npc)
  if not npc then return end
  lines.add("origin", L.ORIGIN, ("%s (%s)"):format(npc.name, id))
end

local function AddAbilityLines(lines, npc)
  for _, ability in ipairs(Addon:TaughtLines(npc)) do
    lines.addText("abilities", ability)
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
    return -- (players, objects, ...: nothing to add, and too common to report)
  end

  -- Get live unit info.
  if not unit and UnitTokenFromGUID then unit = UnitTokenFromGUID(guid) end
  local family = unit and Addon:UnitFamily(unit) -- English, whatever the client's language; nil for demons
  local npc = Addon:GetNPC(id)
  local lines = NewLines()

  -- Pets owned by a player. Only hunter families count (not warlock demons).
  if unitType == "Pet" or (unit and UnitPlayerControlled(unit)) then
    if not (family and IsHunterFamily(family)) then return end

    AddInfoLines(lines, unit, family)
    AddOriginLine(lines, id, npc)
    lines.add("tameable", L.TAMEABLE, L.ALREADY_OWNED)
    if npc then AddAbilityLines(lines, npc) end
    return lines.into(self)
  end

  if not npc then
    Addon:Debug("tooltip: npc not in data", id)

    -- Fall back to live unit info. Only creatures with a pet family are shown.
    if not family then return end

    AddInfoLines(lines, unit, family)
    lines.add("tameable", L.TAMEABLE, L.LIKELY)
    lines.add("abilities", L.ABILITIES, L.UNKNOWN, Colors.Muted:GetRGB())
    return lines.into(self)
  end
  Addon:Debug("tooltip: npc found", id, npc.name)

  AddInfoLines(lines, unit, family or npc.family)
  AddTamedLine(lines, npc)
  -- The game refused to tame it (the website's red Not tameable badge).
  if npc.not_tameable then
    lines.add("tameable", L.TAMEABLE, L.TAME_CHECK_NOT_TAMEABLE, Colors.Bad:GetRGB())
  end
  AddAbilityLines(lines, npc)
  lines.into(self)
end

-- Pet Ability Tooltips: under a pet ability's own tooltip (the spellbook, the pet bar, Beast Training, a chat link, the
-- addon's tabs), the pet level and training points its rank needs, from the addon's data. Other spells are left alone.
local function AddSpellLines(tooltip, spellId)
  if not DB.global.ability_tooltips then return end
  local ability = spellId and Addon:AbilityOfSpell(spellId)
  Addon:Debug("tooltip: spell", spellId, ability and ability.name or "(not a pet ability)")
  if not ability or ability.attack_speed then return end
  local lines = NewLines()
  if ability.pet_level then lines.add("pet_level", L.REQUIRED_PET_LEVEL, ability.pet_level) end
  if ability.training_cost then lines.add("training", L.TRAINING_COST, ability.training_cost) end
  if #lines == 0 then return end
  lines.into(tooltip)
  tooltip:Show() -- (resized for the new lines)
end

-- The spell a tooltip shows: from the tooltip data, else the tooltip itself.
local function TooltipSpell(tooltip, data)
  if data and type(data.id) == "number" then return data.id end
  if tooltip.GetSpell then
    local _, spellId = tooltip:GetSpell()
    return spellId
  end
end

local function OnTooltipSetSpell(tooltip, data)
  local ok, err = pcall(function() AddSpellLines(tooltip, TooltipSpell(tooltip, data)) end)
  if not ok then Addon:Debug("tooltip error:", err) end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  -- Spells, and the pet bar's buttons where the client gives them their own type.
  for _, kind in ipairs({ "Spell", "PetAction" }) do
    local id = Enum.TooltipDataType[kind]
    if id then
      TooltipDataProcessor.AddTooltipPostCall(id, function(tooltip, data)
        if tooltip == GameTooltip or tooltip == ItemRefTooltip then OnTooltipSetSpell(tooltip, data) end
      end)
    end
  end
else
  GameTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
  if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell) end
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
