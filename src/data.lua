local _, Addon = ...
local Colors = Addon:GetModule("Colors")
local L = Addon:GetModule("Locale")
local TameableAbilities = Addon.TameableAbilities
local TameableNPCs = Addon.TameableNPCs

-- Returns name, icon for a spell, or nil. Supports both the legacy
-- `GetSpellInfo` and the newer `C_Spell.GetSpellInfo` (returns a table).
local function GetSpellNameAndIcon(spellId)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spellId)
    if info then return info.name, info.iconID end
    return nil
  end
  local name, _, icon = GetSpellInfo(spellId)
  return name, icon
end

-- ============================================================================
-- Attack speed tiers
-- ============================================================================

-- Every hunter pet has a spell in its spellbook that stands for its native attack speed: a pet's base speed is
-- 2.0 and the spell's percentage turns it into the creature's own speed (Faster Attack VI, +67%, is 1.2). The
-- speed the game reports for any beast is therefore the tier, so the tier is named from the speed. Speeds of 2.0
-- have no spell. The ids are the spells' ids; the percentages are from their tooltips (II, III, IV, V and VI confirmed in game).
local ATTACK_TIER_SPELLS = {
  ["1.0"] = 1263110, -- Faster Attack VII, +100%
  ["1.2"] = 1263109, -- Faster Attack VI, +67% (confirmed)
  ["1.3"] = 1263107, -- Faster Attack V, +54% (confirmed)
  ["1.4"] = 1263104, -- Faster Attack IV, +43% (confirmed)
  ["1.5"] = 1263102, -- Faster Attack III, +33% (confirmed)
  ["1.6"] = 1263100, -- Faster Attack II, +25% (confirmed)
  ["1.7"] = 1263099, -- Faster Attack I, +17%
  ["2.5"] = 1263113, -- Slower Attack II, -20%
  ["2.7"] = 1263114, -- Slower Attack III, -26% (no creature has it yet)
}
local ATTACK_TIER_NAMES = {
  [1263110] = "Faster Attack VII", [1263109] = "Faster Attack VI", [1263107] = "Faster Attack V",
  [1263104] = "Faster Attack IV", [1263102] = "Faster Attack III", [1263100] = "Faster Attack II",
  [1263099] = "Faster Attack I", [1263113] = "Slower Attack II", [1263114] = "Slower Attack III",
}

-- The name of the attack speed spell for a speed (a number, or the text "1.2"), or nil when it has none.
-- The game's own spell name is used when it knows the spell, so it shows in the player's language.
function Addon:GetAttackTierName(speed)
  -- In combat the game can hand addons a unit's attack speed as a "secret" value: it can be shown, but not used as a
  -- table key or compared. Such a speed has no tier name here.
  if Addon:IsSecret(speed) then return nil end
  local key = type(speed) == "number" and ("%.1f"):format(speed) or speed
  local ok, spellId = pcall(function() return ATTACK_TIER_SPELLS[key] end)
  if not (ok and spellId) then return nil end
  local name = GetSpellNameAndIcon(spellId)
  return (type(name) == "string" and name ~= "") and name or ATTACK_TIER_NAMES[spellId]
end

-- A creature's attack speed as shown: "1.20 (Faster Attack VI)", "2.00", or "Unknown" when the data has none.
function Addon:AttackSpeedText(speed)
  if type(speed) ~= "number" then return L.UNKNOWN end
  local tier = self:GetAttackTierName(speed)
  return tier and ("%.2f (%s)"):format(speed, tier) or ("%.2f"):format(speed)
end

-- The attack speed tiers as abilities of their own, so the window can list them like the others (the data files
-- have none: they belong to individual beasts). One per speed that has a spell, with every creature of that speed.
-- `attack_speed` marks them; their only rank has the creatures in `npc_ids`.
do
  local byKey = {}
  for id, npc in pairs(TameableNPCs) do
    if npc.speed and not Addon.IGNORED_NPC_IDS[id] then
      local key = ("%.1f"):format(npc.speed)
      if ATTACK_TIER_SPELLS[key] then
        byKey[key] = byKey[key] or {}
        table.insert(byKey[key], id)
      end
    end
  end
  -- Every tier is listed, also one no creature has (Slower Attack III stays empty).
  for key, spellId in pairs(ATTACK_TIER_SPELLS) do
    local ids = byKey[key] or {}
    table.sort(ids)
    TameableAbilities["attack-speed-" .. key] = {
      name = ATTACK_TIER_NAMES[spellId],
      learned_by = {},
      passive = true,
      attack_speed = tonumber(key),
      ranks = { { spell_id = spellId, rank = 1, npc_ids = ids } },
    }
  end
end

-- Update TameableAbilities with in-game data: the game supplies each ability's icon and its name in the
-- player's language (the data has the English name). Spell data can still be loading at login, so a
-- failed lookup is retried when the spell loads; the ability is never dropped for it.
local QUESTION_MARK_ICON = Addon.QUESTION_MARK_ICON -- until the real icon is known

local function ApplySpellInfo(ability, spellId)
  local name, icon = GetSpellNameAndIcon(spellId)
  if type(name) == "string" and name ~= "" then ability.name = name end
  if icon then ability.icon = icon end
  return icon ~= nil
end

for key, ability in pairs(TameableAbilities) do
  ability.key = key -- what sticky selections save
  local first = ability.ranks[1]
  if first and not ApplySpellInfo(ability, first.spell_id) and Spell and Spell.CreateFromSpellID then
    local spell = Spell:CreateFromSpellID(first.spell_id)
    if not (spell.IsSpellEmpty and spell:IsSpellEmpty()) then
      spell:ContinueOnSpellLoad(function() ApplySpellInfo(ability, first.spell_id) end)
    end
  end
  ability.icon = ability.icon or QUESTION_MARK_ICON
end

for id, trainer in pairs(Addon.TameableTrainers or {}) do trainer.id = id end

-- ============================================================================
-- Creatures, built on demand
-- ============================================================================

-- The creature data stays as generated (data/ForeverTameableNPCs.lua). What the tooltips, the window and
-- the map pins show (level range, zone names, diet, abilities, map points) is worked out the first time a
-- creature is asked for, through Addon:GetNPC, and kept on it.

-- Map points are packed 3 characters per point: x and y rounded to 0.2 percent (0-500 each), and
-- n = x * 501 + y written as three base-64 digits in this alphabet (the same one the exporter uses).
local PACK_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local packValue = {} -- byte -> digit
for i = 1, #PACK_ALPHABET do packValue[PACK_ALPHABET:byte(i)] = i - 1 end

local function UnpackPoints(packed)
  local points, byte = {}, string.byte
  for i = 1, #packed - 2, 3 do
    local a, b, c = byte(packed, i, i + 2)
    local n = packValue[a] * 4096 + packValue[b] * 64 + packValue[c]
    local x = (n - n % 501) / 501
    points[#points + 1] = { x = x / 5, y = (n % 501) / 5 }
  end
  return points
end

-- npc id -> list of { ability, rankIndex } it teaches, built in one pass the first time it is needed.
local npcAbilities
local function GetTaughtRanks(id)
  if not npcAbilities then
    npcAbilities = {}
    for _, ability in pairs(TameableAbilities) do
      for rankIndex, rank in ipairs(ability.ranks) do
        for _, npcId in ipairs(rank.npc_ids or {}) do
          local list = npcAbilities[npcId]
          if not list then
            list = {}
            npcAbilities[npcId] = list
          end
          list[#list + 1] = { ability = ability, rankIndex = rankIndex }
        end
      end
    end
  end
  return npcAbilities[id] or {}
end

local function PrepareNPC(id, npc)
  npc.id = id

  -- Level range, e.g. "5-6", or "12 (Elite)"; "Unknown" when the data has none.
  local range = npc.min and tostring(npc.min) or L.UNKNOWN
  if npc.max and npc.max ~= npc.min then range = range .. "-" .. npc.max end
  if npc.class then range = ("%s (%s)"):format(range, Colors.Highlight(npc.class)) end
  npc.level_range = range

  npc.speed_text = Addon:AttackSpeedText(npc.speed)

  -- Zone names, in the player's language (nil when the data has none: shown as "Unknown Zone").
  local zones = {}
  for _, zoneId in ipairs(npc.zones or {}) do
    local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zoneId)
    if name then zones[#zones + 1] = name end
  end
  npc.location = #zones > 0 and table.concat(zones, ", ") or nil
  npc.zone_names = zones -- for the Zone Filter

  -- Diet and type are the family's.
  local family = Addon.TameableFamilies and Addon.TameableFamilies[npc.family]
  npc.diet = family and family.foods and table.concat(family.foods, ", ") or nil
  npc.type = family and family.type or nil

  -- The ability ranks it teaches, by name then rank.
  local taught = GetTaughtRanks(id)
  table.sort(taught, function(a, b)
    if a.ability.name ~= b.ability.name then return a.ability.name < b.ability.name end
    return a.rankIndex < b.rankIndex
  end)
  npc.abilities = {}
  for i, entry in ipairs(taught) do
    npc.abilities[i] = ("|T%s:0|t %s |cFF9D9D9D(%s %s)|r"):format(
      entry.ability.icon, entry.ability.name, L.RANK, entry.rankIndex)
  end

  -- Map pins: the map with the most points. A creature without points has its zone's world map (`map`), which opens
  -- without pins.
  local bestMap, bestPacked
  for mapId, packed in pairs(npc.maps or {}) do
    if not bestPacked or #packed > #bestPacked then bestMap, bestPacked = mapId, packed end
  end
  npc.ui_map_id = bestMap or npc.map
  npc.coords = bestPacked and UnpackPoints(bestPacked) or {}

  npc.prepared = true
end

-- The creature with this npc id (a number or a string), ready to show; nil when it is not in the data.
function Addon:GetNPC(id)
  id = tonumber(id)
  if id and Addon.IGNORED_NPC_IDS[id] then return nil end
  local npc = id and TameableNPCs[id]
  if npc and not npc.prepared then PrepareNPC(id, npc) end
  return npc
end

-- The tab an ability is listed on: "UNIQUE" when it is the exclusive ability of a single pet family
-- (`unique = true` in the data), even when it is passive; "PASSIVE" for the other passive abilities
-- (resistances, Great Stamina, ...), which are learned from trainers; "COMMON" for everything else.
function Addon:GetAbilityTab(ability)
  if ability.attack_speed then return "ATTACK" end
  if ability.unique == true then return "UNIQUE" end
  if ability.passive == true then return "PASSIVE" end
  return "COMMON"
end

-- Spellbook checks, in order. Resolved once here, not on every call.
local spellChecks = {}
if IsPlayerSpell then spellChecks[#spellChecks + 1] = IsPlayerSpell end
if C_SpellBook and C_SpellBook.IsSpellKnown then
  local isKnown = C_SpellBook.IsSpellKnown
  local bank = Enum and Enum.SpellBookSpellBank
  spellChecks[#spellChecks + 1] = isKnown
  if bank then
    spellChecks[#spellChecks + 1] = function(id) return isKnown(id, bank.Pet) end
  end
elseif IsSpellKnown then
  spellChecks[#spellChecks + 1] = IsSpellKnown
  spellChecks[#spellChecks + 1] = function(id) return IsSpellKnown(id, true) end
end

-- Returns true if the player (or their pet) knows the spell.
function Addon:IsSpellKnown(spellId)
  for _, check in ipairs(spellChecks) do
    local ok, known = pcall(check, spellId)
    if ok and known == true then return true end
  end
  return false
end
