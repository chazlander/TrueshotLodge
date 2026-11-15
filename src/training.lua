local _, Addon = ...
local DB = Addon:GetModule("DB")
local Training = Addon:GetModule("Training")

-- Remembers which ability ranks the hunter has learned: the ones listed in their Beast Training window. A rank only
-- appears there once it is learned, and a pet's own spellbook is no guide (a beast arrives knowing its abilities before
-- the hunter has learned them). On this client Beast Training is the class trainer window, so it is read with the
-- trainer API. The list is saved per character in `DB.char.trained` / `trained_ids` whenever the window is opened. It
-- only ever grows, because the window shows less for a pet that can't use a rank. The game also tells the addon
-- without the window: by the "You have learned..." chat line, and by the hunter's own spells (scanKnownSpells, below),
-- which find every learned rank at login.

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

-- The hunter's own spell that teaches a rank (the data's learn_id: what the game links in "You have learned a new
-- spell: [Web]."; 1265888 teaches the pet's Web Rank 2, 1265878) -> the rank's spell id, built the first time it is
-- needed. A spell id that is already a rank's is given back as it is; nil for one that is neither.
local byLearnSpell
function Addon:RankSpellOf(spellId)
  if not spellId then return nil end
  if not byLearnSpell then
    byLearnSpell = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      for _, rank in ipairs(ability.ranks) do
        if rank.learn_id and rank.spell_id then byLearnSpell[rank.learn_id] = rank.spell_id end
      end
    end
  end
  if self:AbilityOfSpell(spellId) then return spellId end
  return byLearnSpell[spellId]
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
      spellId = Addon:RankSpellOf(spellId) or spellId -- (a hunter's teaching spell counts as the rank it teaches)
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

-- The second way to learn of a rank: the moment it is learned. When the hunter learns a rank (from a pet, a pet
-- trainer or Beast Training), the game says "You have learned a new ability: Bite (Rank 3)." in chat, and some clients
-- also fire LEARNED_SPELL_IN_TAB with its spell id. Either one saves the rank straight away, so the list keeps up
-- without opening Beast Training. It only catches ranks learned from now on; the window is still how older ones are
-- found.

-- Lua patterns for the game's "You have learned..." lines, made from its own strings so they work in every language,
-- with the English ones as a fallback. The %s in each becomes a capture. (The list is walked by count, not ipairs: a
-- string this client lacks is nil, and ipairs stops at the first nil, which left no patterns at all.)
local learnPatterns = {}
local learnTexts = { ERR_LEARN_ABILITY_S, ERR_LEARN_SPELL_S,
  "You have learned a new ability: %s.", "You have learned a new spell: %s." }
for index = 1, 4 do
  local text = learnTexts[index]
  if type(text) == "string" and text:find("%s", 1, true) then
    local pattern = "^" .. text:gsub("%%s", "\0"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%z", "(.+)") .. "$"
    learnPatterns[#learnPatterns + 1] = pattern
  end
end

-- Lowercase ability name -> the ability in the data, to find a rank's spell id from the chat line's text. The names
-- are the game's own, in the client's language (data.lua names each ability from its spell), as the chat line is.
local byName
local function abilityNamed(name)
  if not byName then
    byName = {}
    for _, ability in pairs(Addon.TameableAbilities) do
      if not ability.attack_speed then byName[ability.name:lower()] = ability end
    end
  end
  return byName[tostring(name):lower()]
end

-- Saves one learned rank, by spell id: a rank's own, or the hunter's spell that teaches it (Addon:RankSpellOf).
local function saveLearned(spellId)
  spellId = Addon:RankSpellOf(spellId)
  if not (DB.char and spellId) then return false end
  DB.char.trained_ids = DB.char.trained_ids or {}
  DB.char.trained_ids[spellId] = true
  Addon:Debug("training: learned", spellId)
  return true
end

-- Works out the rank from what the chat line names, and saves it. The line links the hunter's own spell for learning
-- the rank, not the pet's ("[Web]" is 1265888, which teaches Web Rank 2): the data names that spell for each rank
-- (learn_id), so the link's id says exactly which rank it is. Only for a spell the data does not know is the name and
-- rank in the link's text tried.
local function learnedFromText(what)
  local id = tonumber(what:match("spell:(%d+)"))
  if id and saveLearned(id) then return true end

  local plain = what:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
  plain = plain:gsub("^%[", ""):gsub("%]$", "")
  local name, rank = plain:match("^(.-)%s*%((.-)%)$")
  name = name or plain
  local ability = abilityNamed(name)
  if not ability then
    return Addon:Debug("training: learned a spell that is no pet ability:", plain, id and ("(spell " .. id .. ")") or "")
  end
  -- The rank: in the link's text ("Bite (Rank 4)"), else what the game says of the linked spell ("Rank 2"). A link
  -- can show none ("[Web]" was the hunter's spell for Web Rank 2, 1265888): then, when the ability has more than one
  -- rank, nothing is guessed, since a rank marked known by mistake would never come off.
  if not rank and id then
    local subtext = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    rank = type(subtext) == "string" and subtext ~= "" and subtext or nil
  end
  local number = tonumber(tostring(rank or ""):match("%d+"))
  if not number and #ability.ranks > 1 then
    return Addon:Debug("training: learned", plain, id and ("(spell " .. id .. ")") or "",
      "but the game does not say which rank: open Beast Training to record it")
  end
  number = number or 1
  for index, r in ipairs(ability.ranks) do
    if (r.rank or index) == number then return saveLearned(r.spell_id) end
  end
  return Addon:Debug("training: learned", plain, "but the data has no such rank")
end
Training.LearnedFromText = learnedFromText -- (.tools/smoke.py tries it with the game's own chat lines)
Training.LearnPatterns = learnPatterns

local learnFrame = CreateFrame("Frame")
learnFrame:SetScript("OnEvent", function(_, event, arg)
  local ok, err = pcall(function()
    if event == "LEARNED_SPELL_IN_TAB" then
      saveLearned(tonumber(Addon:Plain(arg)))
      return
    end
    local text = Addon:Plain(arg)
    if type(text) ~= "string" then return end
    for _, pattern in ipairs(learnPatterns) do
      local what = text:match(pattern)
      if what then
        learnedFromText(what)
        return
      end
    end
  end)
  if not ok then Addon:Debug("training learn error:", err) end
end)
for _, event in ipairs({ "CHAT_MSG_SYSTEM", "LEARNED_SPELL_IN_TAB" }) do
  pcall(learnFrame.RegisterEvent, learnFrame, event) -- Not every client has every event.
end

-- The third way, and the one that needs nothing opened: the hunter's own spells. Learning a rank gives the hunter a
-- spell of their own (the data's learn_id: 1265888 for Web Rank 2), and the game says whether they know it, through
-- IsPlayerSpell or C_SpellBook.IsSpellKnown. (The plain IsSpellKnown looks in another spellbook and says no.) The
-- addon asks about every rank when the hunter enters the world, levels up or learns a spell, so ranks learned before
-- the addon was installed are found too. A rank found this way is verified, like one seen in Beast Training.
local function knowsSpell(id)
  if IsPlayerSpell and Addon:Plain(IsPlayerSpell(id)) then return true end
  local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown
  return isKnown ~= nil and Addon:Plain(isKnown(id)) == true
end

-- Saves every rank whose learning spell the hunter knows; returns how many were new.
local function scanKnownSpells()
  if not DB.char then return 0 end
  DB.char.trained_ids = DB.char.trained_ids or {}
  local found = 0
  for _, ability in pairs(Addon.TameableAbilities) do
    if not ability.attack_speed then
      for _, rank in ipairs(ability.ranks) do
        if rank.learn_id and rank.spell_id and not DB.char.trained_ids[rank.spell_id] and knowsSpell(rank.learn_id) then
          DB.char.trained_ids[rank.spell_id] = true
          found = found + 1
        end
      end
    end
  end
  return found
end
Training.ScanKnownSpells = scanKnownSpells -- (.tools/smoke.py tries it)

-- The scan runs a moment after the last of a burst of events (SPELLS_CHANGED fires many times at login), and redraws
-- the window when it found something new.
local scanPending = false
local function runScan()
  scanPending = false
  local ok, found = pcall(scanKnownSpells)
  if not ok then return Addon:Debug("training scan error:", found) end
  Addon:Debug("training: spells scan found", found, "new ranks")
  local Window = Addon:GetModule("Window")
  if found > 0 and Window.IsShown and Window:IsShown() then Window:Refresh() end
end

local scanFrame = CreateFrame("Frame")
scanFrame:SetScript("OnEvent", function()
  if scanPending then return end
  scanPending = true
  if C_Timer and C_Timer.After then C_Timer.After(2, runScan) else runScan() end
end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
  pcall(scanFrame.RegisterEvent, scanFrame, event) -- Not every client has every event.
end

-- Returns true if the game has shown that the hunter learned the ability rank: it was listed in their Beast Training
-- window, or the game said it was learned (the chat line or the event). That cannot be undone: a hunter cannot unlearn
-- a rank, so a verified rank is known for good, and no mark by hand takes it back.
function Addon:IsRankVerified(ability, rankIndex)
  local rank = ability.ranks[rankIndex]
  local char = DB.char
  if not (rank and char) or ability.attack_speed then return false end
  if char.trained_ids and char.trained_ids[rank.spell_id] then return true end
  -- By name, only for trainer entries the client gave no spell id for (usually none).
  return char.trained ~= nil and char.trained[key(ability.name, rank.rank or rankIndex)] == true
end

-- Returns true if the hunter knows the ability rank: verified by the game (IsRankVerified), or marked known by hand
-- (`rank_marked`: SetRankKnown) for a rank the addon has not seen them learn.
function Addon:IsRankKnown(ability, rankIndex)
  local rank = ability.ranks[rankIndex]
  if not rank or ability.attack_speed then return false end -- (an attack speed is a beast's passive, not learned)
  if self:IsRankVerified(ability, rankIndex) then return true end
  local char = DB.char
  return char ~= nil and char.rank_marked ~= nil and char.rank_marked[rank.spell_id] == true
end

-- Marks a rank known, or takes that mark back, by hand (a click on an ability's icon, with Known Ability Edit on: tab-abilities.lua):
-- for a rank the hunter learned before the addon could see it. Saved per character in DB.char.rank_marked (spell id
-- -> true). A rank the game has verified is known for good: it cannot be marked not known (false comes back).
function Addon:SetRankKnown(ability, rankIndex, known)
  local rank = ability.ranks[rankIndex]
  local char = DB.char
  if not (rank and rank.spell_id and char) or ability.attack_speed then return false end
  if self:IsRankVerified(ability, rankIndex) then return known end -- (already known; never unmarked)
  char.rank_marked = char.rank_marked or {}
  char.rank_marked[rank.spell_id] = known or nil
  Addon:Debug("training: marked", ability.name, rankIndex, known and "known" or "not known", "by hand")
  return true
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
