local _, Addon = ...
local DB = Addon:GetModule("DB")
local Training = Addon:GetModule("Training")

-- Remembers which ability ranks are in the hunter's Beast Training window,
-- whether or not the current pet can learn them. On this client Beast Training
-- is the class trainer window, so it is read with the trainer API. The list is
-- saved per character in `DB.char.trained` / `trained_ids` whenever the window
-- is opened. Ranks the spellbook says the character knows are saved in
-- `DB.char.known_ids`. Both only ever grow, so what was known stays known
-- between sessions even when the pet is away or the window is closed.

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

-- spell id -> the rank (1, 2, ...) of that ability in the addon's data: the exact version of the ability.
local rankBySpell
local function RankOfSpell(spellId)
  if not rankBySpell then
    rankBySpell = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      for index, rank in ipairs(ability.ranks) do
        if rank.spell_id then rankBySpell[rank.spell_id] = rank.rank or index end
      end
    end
  end
  return rankBySpell[spellId]
end

-- "Rank 3" for a trainer entry: from the addon's data when the spell is in it, otherwise from the game's own
-- text for the spell. nil when the entry has no rank.
local function RankText(spellId)
  if not spellId then return nil end
  local number = RankOfSpell(spellId)
  if number then return ("%s %d"):format(Addon:GetModule("Locale").RANK, number) end
  local subtext = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellId)
  if type(subtext) == "string" and subtext ~= "" then return subtext end
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

    if name and category ~= "header" and (not petOnly or self:IsPetAbility(name)) then
      local spellId = serviceSpellId(i)
      list[#list + 1] = {
        index = i,
        spell_id = spellId,
        name = name,
        rank = RankText(spellId) or ((type(rank) == "string" and rank ~= "") and rank or nil),
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

local function record()
  if not DB.char then return end

  -- Ranks are tracked by spell id when the client gives one, otherwise by
  -- name and rank text. Only the entries the window marks as learned ("used")
  -- count: a trainer lists every rank, learned or not. (This client gives no
  -- status at all, so nothing is marked here; the pet's spellbook tells.)
  local trained, trainedIds, count = {}, {}, 0
  for _, service in ipairs(Training:ReadServices(true)) do
    if service.category == "used" then
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

-- Spell ids the game said were not known, so the window and tooltips don't ask again (each ask can be
-- several protected calls) until the spellbook, the pet or the trainer list changes.
local notKnown = {}

-- Saves every rank the game says the character knows right now.
function Training:SyncKnown()
  if not DB.char then return end
  local known = DB.char.known_ids
  if not known then
    known = {}
    DB.char.known_ids = known
  end
  for _, ability in pairs(Addon.TameableAbilities) do
    for _, rank in ipairs(ability.ranks) do
      if rank.spell_id and not known[rank.spell_id] and Addon:IsSpellKnown(rank.spell_id) then
        known[rank.spell_id] = true
      end
    end
  end
end

-- Spellbook events come in bursts, so sync once things settle.
local syncPending = false
local function scheduleSync()
  wipe(notKnown) -- What is known may have changed.
  if syncPending then return end
  syncPending = true
  C_Timer.After(2, function()
    syncPending = false
    local ok, err = pcall(Training.SyncKnown, Training)
    if not ok then Addon:Debug("training sync error:", err) end
  end)
end

local syncFrame = CreateFrame("Frame")
syncFrame:SetScript("OnEvent", scheduleSync)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UNIT_PET", "PET_BAR_UPDATE" }) do
  pcall(syncFrame.RegisterEvent, syncFrame, event)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
  Addon:Debug("training: event", event)
  wipe(notKnown)
  local ok, err = pcall(record)
  if not ok then Addon:Debug("training error:", err) end
end)
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do
  pcall(frame.RegisterEvent, frame, event) -- Not every client has every event.
end

-- Returns true if the ability rank was in the hunter's Beast Training window,
-- was known before (saved per character), or the player (or their pet) knows the spell.
function Addon:IsRankKnown(ability, rankIndex)
  local rank = ability.ranks[rankIndex]
  if not rank then return false end
  if ability.attack_speed then return false end -- A beast's passive, not something to learn.

  local id = rank.spell_id
  local char = DB.char
  if char then
    if char.known_ids and char.known_ids[id] then return true end
    if char.trained_ids and char.trained_ids[id] then return true end
    -- By name, only for trainer entries the client gave no spell id for (usually none).
    if char.trained and next(char.trained) and char.trained[key(ability.name, rank.rank or rankIndex)] then
      return true
    end
  end
  if notKnown[id] then return false end

  if self:IsSpellKnown(id) then
    if char and char.known_ids then char.known_ids[id] = true end -- Saved: known from now on.
    return true
  end
  notKnown[id] = true
  return false
end
