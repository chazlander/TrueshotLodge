local _, Addon = ...
local DB = Addon:GetModule("DB")
local Training = Addon:GetModule("Training")

-- Remembers which ability ranks the hunter has learned: the ones listed in their Beast Training window. A rank only
-- appears there once it is learned, and a pet's own spellbook is no guide (a beast arrives knowing its abilities before
-- the hunter has learned them). On this client Beast Training is the class trainer window, so it is read with the
-- trainer API. The list is saved per character in `DB.char.trained` / `trained_ids` whenever the window is opened. It
-- only ever grows, because the window shows less for a pet that can't use a rank.

local function key(name, rank)
  return tostring(name):lower() .. "|" .. (tonumber(tostring(rank or ""):match("%d+")) or 1)
end

-- Calls the global trainer function if it exists, otherwise the `C_Trainer` one.
local function trainerCall(name, ...)
  local fn = _G[name]
  if type(fn) ~= "function" and C_Trainer then fn = C_Trainer[name] end
  if type(fn) ~= "function" then return end
  return fn(...)
end

-- Every value a call returned, nils included: { n = count, ... }.
local function allValues(...)
  return { n = select("#", ...), ... }
end

-- Returns the spell id of a trainer entry, from its link or its tooltip data.
local function serviceSpellId(index)
  local link = trainerCall("GetTrainerServiceItemLink", index)
  if type(link) == "string" then
    local id = link:match("spell:(%d+)")
    if id then return tonumber(id) end
  end

  if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
    local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
    if ok and type(data) == "table" and type(data.id) == "number" then
      return data.id
    end
  end
end

-- Set of ability names (lowercase) from the data, used to tell Beast Training
-- apart from the hunter's normal class trainer.
local abilityNames
function Training:IsPetAbility(name)
  if not abilityNames then
    abilityNames = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      abilityNames[ability.name:lower()] = true
    end
  end
  return abilityNames[tostring(name):lower()] == true
end

local STATUSES = { available = true, unavailable = true, used = true, header = true }

-- spell id -> { name, rank } of that ability rank in the addon's data: its English name and its rank (1, 2, ...).
-- The game names spells in the client's language; the spell id is the same in every language.
local bySpell
function Addon:AbilityOfSpell(spellId)
  if not bySpell then
    bySpell = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      for index, rank in ipairs(ability.ranks) do
        if rank.spell_id then
          bySpell[rank.spell_id] = { name = ability.name, rank = rank.rank or index, pet_level = rank.pet_level,
            training_cost = rank.training_cost, trainer_cost = rank.trainer_cost, attack_speed = ability.attack_speed }
        end
      end
    end
  end
  return spellId and bySpell[spellId] or nil
end

-- A rank as saved: "Rank 3" in English from the game's text in any language ("Уровень 3"), or the text as it is
-- when it has no number.
function Addon:RankText(text)
  local number = type(text) == "string" and tonumber(text:match("%d+")) or nil
  return number and ("Rank %d"):format(number) or text
end

-- "Rank 3" for a trainer entry: from the addon's data when the spell is in it, otherwise from the game's own
-- text for the spell. nil when the entry has no rank.
local function RankText(spellId)
  if not spellId then return nil end
  local ability = Addon:AbilityOfSpell(spellId)
  if ability then return ("Rank %d"):format(ability.rank) end
  local subtext = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellId)
  if type(subtext) == "string" and subtext ~= "" then return Addon:RankText(subtext) end
end

-- Returns a list of { index, name, rank, category, cost, level_req, icon } for every
-- non-header entry in the open trainer window (`spell_id` may be nil). With
-- `petOnly`, entries that aren't pet abilities are skipped before the costlier
-- lookups.
function Training:ReadServices(petOnly)
  local list = {}
  local n = trainerCall("GetNumTrainerServices")
  if type(n) ~= "number" then return list end

  for i = 1, n do
    local name, rank, category = trainerCall("GetTrainerServiceInfo", i)
    if type(name) == "table" then -- Newer clients return a table.
      local t = name
      name = t.serviceName or t.name
      rank = t.serviceSubText or t.subText or t.rank
      category = t.serviceType or t.category
    end

    -- On this client the second value is the entry's status ("used", "unavailable", ...), not its rank.
    if STATUSES[rank] then
      category = category or rank
      rank = nil
    end
    if type(category) ~= "string" then category = nil end

    -- With petOnly, only the data's pet abilities: known by their English name, or on other client languages by
    -- their spell id.
    local wanted, spellId = name and category ~= "header", nil
    if wanted and petOnly and not self:IsPetAbility(name) then
      spellId = serviceSpellId(i)
      wanted = Addon:AbilityOfSpell(spellId) ~= nil
    end
    if wanted then
      spellId = spellId or serviceSpellId(i)
      local ability = Addon:AbilityOfSpell(spellId)
      list[#list + 1] = {
        index = i,
        spell_id = spellId,
        name = ability and ability.name or name, -- English for the data's abilities
        rank = RankText(spellId) or ((type(rank) == "string" and rank ~= "") and Addon:RankText(rank) or nil),
        category = category,
        cost = trainerCall("GetTrainerServiceCost", i),
        -- Everything GetTrainerServiceCost returned (money first; on classic clients the next ones can be other costs,
        -- such as training points), for `/tsl debug training` to show which is which.
        costs = allValues(trainerCall("GetTrainerServiceCost", i)),
        level_req = trainerCall("GetTrainerServiceLevelReq", i),
        icon = trainerCall("GetTrainerServiceIcon", i),
      }
    end
  end

  return list
end

-- Whether the open trainer window is Beast Training: it opens with no npc at all (at most a targeted beast), where a pet
-- trainer or a stable master is an npc of its own.
local function isBeastTraining()
  return not UnitExists("npc") or Addon:UnitIsBeast("npc") or Addon:Plain((UnitCreatureFamily("npc"))) ~= nil
end

local function record()
  if not DB.char then return end

  -- Ranks are tracked by spell id when the client gives one, otherwise by name and rank text. Everything listed in
  -- Beast Training is learned. A trainer lists every rank, learned or not, so there only the entries it marks as
  -- learned ("used") count.
  local allLearned = isBeastTraining()
  local trained, trainedIds, count = {}, {}, 0
  for _, service in ipairs(Training:ReadServices(true)) do
    if allLearned or service.category == "used" then
      if service.spell_id then
        trainedIds[service.spell_id] = true
      else
        trained[key(service.name, service.rank)] = true
      end
    end
    count = count + 1
  end

  -- Not the Beast Training window (e.g. the normal class trainer).
  if count == 0 then return Addon:Debug("training: no pet abilities in trainer") end

  DB.char.trained = DB.char.trained or {}
  DB.char.trained_ids = DB.char.trained_ids or {}
  for k in pairs(trained) do DB.char.trained[k] = true end
  for id in pairs(trainedIds) do DB.char.trained_ids[id] = true end
  Addon:Debug("training: saved", count, "ranks")
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
  Addon:Debug("training: event", event)
  local ok, err = pcall(record)
  if not ok then Addon:Debug("training error:", err) end
end)
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do
  pcall(frame.RegisterEvent, frame, event) -- Not every client has every event.
end

-- Returns true if the hunter has learned the ability rank: it has been listed in their Beast Training window.
function Addon:IsRankKnown(ability, rankIndex)
  local rank = ability.ranks[rankIndex]
  if not rank then return false end
  if ability.attack_speed then return false end -- A beast's passive, not something to learn.

  local char = DB.char
  if not char then return false end
  if char.trained_ids and char.trained_ids[rank.spell_id] then return true end
  -- By name, only for trainer entries the client gave no spell id for (usually none).
  return char.trained ~= nil and char.trained[key(ability.name, rank.rank or rankIndex)] == true
end

-- A rank's state, for its color (colors.lua): Complete (known), Available (the character's level has reached it, not
-- known yet) or Unavailable (level not reached). An attack speed is a beast's passive, not learned: Default. The level
-- is the character's own unless one is given; in combat it can be hidden from addons, and then only level 1 counts.
function Addon:RankState(ability, rankIndex, level)
  if ability.attack_speed then return "Default" end
  if self:IsRankKnown(ability, rankIndex) then return "Complete" end
  level = level or self:Plain(UnitLevel("player")) or 1
  return (ability.ranks[rankIndex].pet_level or 1) <= level and "Available" or "Unavailable"
end
